#!/usr/bin/env python3
"""Read-only, identifier-free reconciliation of an exported physical-phone container.

Exit 1 means SDK evidence is absent/different in an available archive or UI cache. Exit 2
means the export could not be audited. Outbox is transient, never an archive.
This audits cached UI inputs, not the pixels of the running application.
"""
import argparse
from collections import Counter, defaultdict
from datetime import datetime, timedelta, timezone
import json
import math
from pathlib import Path
import plistlib
import sqlite3
from zoneinfo import ZoneInfo


APPLE_EPOCH = datetime(2001, 1, 1, tzinfo=timezone.utc).timestamp()


def number(value):
    try:
        result = float(value)
        return result if math.isfinite(result) else None
    except (TypeError, ValueError):
        return None


def database(path):
    connection = sqlite3.connect(path.resolve().as_uri() + '?mode=ro', uri=True)
    connection.row_factory = sqlite3.Row
    return connection


def decode(value):
    try:
        return json.loads(value)
    except (ValueError, TypeError):
        return None


def quote(name):
    return '"' + name.replace('"', '""') + '"'


def audit(root, zone):
    local = database(root / 'Library/Application Support/HOOP/local-data.sqlite')
    sdk = database(root / 'Documents/wypDataBase.sqlite')
    documents = list(local.execute('SELECT account,key,payload,expiry FROM documents'))
    homes = [(row, decode(row['payload'])) for row in documents if row['key'] == 'home']
    homes = [(row, home) for row, home in homes if isinstance(home, dict) and number(home.get('savedAt')) is not None]
    if not homes:
        raise ValueError('missing_home_snapshot')
    selected, home = max(homes, key=lambda pair: number(pair[1]['savedAt']))
    account = selected['account']
    end = APPLE_EPOCH + float(home['savedAt'])
    report = {'timezone': str(zone), 'snapshot_date': datetime.fromtimestamp(end, zone).isoformat(),
              'scope': {'application_account': 'latest_home_savedAt', 'sdk_device': 'unconfirmed',
                        'historical_device_ownership': 'not_inferred_from_bluetooth_partition'},
              'uncertain': [], 'coverage': [], 'temperature': [], 'sleep': [], 'respiration': [],
              'outbox': {'semantics': 'pending_upload_only_not_permanent_storage', 'domains': {}},
              'limitation': 'Cached UI inputs only; verify actual panels with UI test attachments.'}
    preferences = {}
    for path in root.glob('Library/Preferences/*.plist'):
        try:
            preferences.update(plistlib.loads(path.read_bytes()))
        except (OSError, ValueError, plistlib.InvalidFileException):
            report['uncertain'].append('unreadable_preferences')
    candidates = {preferences.get(key) for key in ('deviceMacKey', 'VPDeviceMacKey')
                  if isinstance(preferences.get(key), str) and preferences.get(key)}
    device = next(iter(candidates)) if len(candidates) == 1 else None
    if device:
        report['scope']['sdk_device'] = 'matched_current_device_preferences'
    else:
        report['uncertain'].append('SDK device partition cannot be confirmed; no combined-device verdicts')
    # Home details are what hydration actually restores. Day documents additionally
    # support history navigation; retain both independently instead of masking loss.
    caches = defaultdict(list)
    for row in documents:
        if row['account'] != account or (row['expiry'] is not None and row['expiry'] <= end):
            continue
        if row['key'].startswith('day:'):
            payload = decode(row['payload'])
            if isinstance(payload, dict) and isinstance(payload.get('detail'), dict):
                detail = payload['detail']
                caches[detail.get('dayKey', row['key'][4:])].append(('day_document', detail))
    for detail in home.get('details') or []:
        caches[detail['dayKey']].append(('home_detail', detail))
    caches[home['dayKey']].append(('home_today', {'vitalsCurve': home.get('todayVitals', []), 'sleep': home.get('todaySleep')}))
    yesterday = (datetime.fromisoformat(home['dayKey']) - timedelta(days=1)).date().isoformat()
    caches[yesterday].append(('home_yesterday', {'vitalsCurve': home.get('yesterdayVitals', [])}))
    durable = defaultdict(list)
    local_tables = {row[0] for row in local.execute("SELECT name FROM sqlite_master WHERE type='table'")}
    if 'observation_documents' in local_tables:
        for row in local.execute('SELECT key,payload FROM observation_documents WHERE account=?', (account,)):
            if not row['key'].startswith('band-day:'):
                continue
            payload = decode(row['payload'])
            if not isinstance(payload, dict):
                report['uncertain'].append('invalid_observation_document')
                continue
            detail = payload.get('detail', payload)
            if isinstance(detail, dict):
                day = detail.get('dayKey', row['key'][len('band-day:'):])
                detail = dict(detail)
                detail['vitalsCurve'] = detail.get('samples', detail.get('vitalsCurve', []))
                durable[day].append(('observation_document', detail))
    report['persisted_dates'] = sorted(durable)
    report['cached_dates'] = sorted(caches)
    # Mirror HomeSnapshot.apply: last detail wins; explicit today/yesterday
    # curves override details. day: documents never hydrate Home automatically.
    last_details = {detail['dayKey']: detail for detail in home.get('details') or []}

    def metric_day(metric):
        value = number((metric.get('day') or {}).get('date'))
        return datetime.fromtimestamp(APPLE_EPOCH + value, zone).date().isoformat() if value is not None else None

    home_cache = {}
    for metric in home.get('history') or []:
        day = metric_day(metric)
        if day:
            home_cache[day] = [('home_display', last_details.get(day, metric))]
    today_detail = dict(last_details.get(home['dayKey'], home.get('today') or {}))
    today_detail.update(vitalsCurve=home.get('todayVitals', []), sleep=home.get('todaySleep'))
    home_cache[home['dayKey']] = [('home_display', today_detail)]
    if isinstance(home.get('yesterday'), dict):
        day = metric_day(home['yesterday'])
        if day:
            detail = dict(last_details.get(day, home['yesterday']))
            detail['vitalsCurve'] = home.get('yesterdayVitals', [])
            home_cache[day] = [('home_display', detail)]
    for row in local.execute('SELECT kind,payload FROM outbox WHERE account=?', (account,)):
        payload = decode(row['payload'])
        # Only allow fixed domain names in output; never echo arbitrary payload text.
        domain = payload.get('p_domain') if isinstance(payload, dict) else None
        allowed = {'origin', 'temperature', 'hrv', 'oxygen', 'sleep', 'optical', 'band-domain', 'band-sleep', 'meal', 'measurement', 'rr', 'response'}
        label = domain if domain in allowed else row['kind'] if row['kind'] in allowed else 'other'
        report['outbox']['domains'][label] = report['outbox']['domains'].get(label, 0) + 1

    grouped = defaultdict(list)
    tables = [row[0] for row in sdk.execute("SELECT name FROM sqlite_master WHERE type='table'")]
    for table in tables:
        columns = {row[1] for row in sdk.execute('PRAGMA table_info(' + quote(table) + ')')}
        partition = 'accountUser' if 'accountUser' in columns else 'mac' if 'mac' in columns else None
        if not device or not partition or 'json' not in columns:
            report['coverage'].append({'table': table, 'status': 'unconfirmed_partition_or_no_json'})
            continue
        rows = sdk.execute('SELECT * FROM ' + quote(table) + ' WHERE ' + quote(partition) + '=?', (device,))
        counts = Counter()
        for row in rows:
            date = str(row['createdTime'] if 'createdTime' in columns else row['testDate'])[:10]
            payload = decode(row['json'])
            if payload is None:
                report['uncertain'].append('invalid_sdk_json:' + table + ':' + date)
                continue
            items = list(payload.values()) if isinstance(payload, dict) else payload if isinstance(payload, list) else []
            counts[date] += len(items)
            grouped[table].append((date, payload))
        report['coverage'].append({'table': table, 'dates': dict(sorted(counts.items())), 'status': 'partition_matched'})

    all_temperatures = set()
    for date, payload in grouped['temperatrue_table']:
        for point in payload if isinstance(payload, list) else []:
            value = number(point.get('originalValue', point.get('riginalValue')))
            if value is None:
                continue
            value = value / 10 if value > 100 else value
            try:
                at = datetime.fromisoformat(date).replace(hour=int(point['hour']), minute=int(point['minute']), tzinfo=zone).timestamp()
            except (ValueError, KeyError, TypeError):
                report['uncertain'].append('invalid_temperature_clock:' + date)
                continue
            if 10 <= value <= 50 and at <= end:
                all_temperatures.add((at, value))
    by_day = defaultdict(set)
    for at, value in all_temperatures:
        day = (datetime.fromtimestamp(at, zone) - timedelta(hours=4)).date().isoformat()
        by_day[day].add((at, value))

    def compare(expected, entries):
        actual = defaultdict(set)
        for _, detail in entries:
            for point in detail.get('vitalsCurve') or []:
                at, value = number(point.get('ts')), number(point.get('temp'))
                if at is not None and value is not None:
                    actual[round(at + APPLE_EPOCH, 3)].add(value)
        absent = mismatched = matched = 0
        for at, value in expected:
            values = actual.get(round(at, 3), set())
            if not values:
                absent += 1
            elif any(abs(candidate - value) < 0.000001 for candidate in values):
                matched += 1
            else:
                mismatched += 1
        return {'sdk_points': len(expected), 'matched': matched, 'missing_timestamp': absent, 'different_value': mismatched,
                'status': 'missing' if absent or mismatched else 'matched'}

    rolling = {(at, value) for at, value in all_temperatures if end - 86400 <= at <= end}

    nights = defaultdict(dict)
    for _, payload in grouped['sleep_accurate_table']:
        for record in payload if isinstance(payload, list) else []:
            wake = str(record.get('wakeTime', '')).replace('/', '-')
            try:
                instant = datetime.fromisoformat(wake).replace(tzinfo=zone)
            except ValueError:
                continue
            # A completed afternoon wake is still sleep evidence. Repeating the
            # app's historical hour<12 filter here would hide the actual bug.
            if instant.timestamp() > end:
                continue
            nights[instant.date().isoformat()][(record.get('sleepTime'), wake)] = record
    respiration_days = Counter()
    for date, payload in sorted(grouped['original_table'], key=lambda item: item[0]):
        for clock, point in payload.items() if isinstance(payload, dict) else []:
            try:
                instant = datetime.fromisoformat(date + 'T' + clock).replace(tzinfo=zone)
            except ValueError:
                report['uncertain'].append('invalid_respiration_clock:' + date)
                continue
            if instant.timestamp() > end or not isinstance(point, dict):
                continue
            day = (instant - timedelta(hours=4)).date().isoformat()
            respiration_days[day] += sum(number(value) is not None and number(value) != 0 for value in point.get('resRates', []))

    sleep_respiration = set()
    for date, payload in grouped['oxygen_table']:
        for point in payload if isinstance(payload, list) else []:
            rate = number(point.get('RespirationRate'))
            if rate is None or rate == 255 or not 0 < rate < 255:
                continue
            try:
                at = datetime.fromisoformat(date + 'T' + point['Time']).replace(tzinfo=zone).timestamp()
            except (ValueError, KeyError, TypeError):
                report['uncertain'].append('invalid_sleep_respiration_clock:' + date)
                continue
            if at <= end:
                sleep_respiration.add((at, rate))

    def sleep_window(record):
        try:
            return tuple(datetime.fromisoformat(str(record[key]).replace('/', '-')).replace(tzinfo=zone).timestamp()
                         for key in ('sleepTime', 'wakeTime'))
        except (ValueError, KeyError, TypeError):
            return None

    def evaluate(cache, persistent=False):
        result = {'temperature': [], 'sleep': [], 'respiration': []}
        for day, expected in sorted(by_day.items()):
            values = (compare(expected, cache.get(day, [])) if day in cache or persistent else
                      {'sdk_points': len(expected), 'status': 'uncertain_no_cached_day'})
            result['temperature'].append({'date': day, **values})
        result['temperature_rolling_24h'] = compare(rolling, [entry for entries in cache.values() for entry in entries])
        for day, records in sorted(nights.items()):
            total = sum(number(record.get('sleepDuration')) or sum(number(record.get(key)) or 0 for key in ('deepDuration', 'lightDuration', 'otherDuration')) for record in records.values())
            summaries = [detail['sleep'] for _, detail in cache.get(day, []) if isinstance(detail.get('sleep'), dict)]
            status = ('uncertain_no_cached_day' if day not in cache and not persistent else 'missing' if not summaries
                      else 'matched' if any(summary.get('totalMinutes') == int(total) for summary in summaries) else 'different_total')
            result['sleep'].append({'date': day, 'sdk_segments': len(records), 'cached_summaries': len(summaries), 'status': status})
            windows = [window for record in records.values() if (window := sleep_window(record))]
            expected = {(at, value) for at, value in sleep_respiration if any(start <= at < wake for start, wake in windows)}
            # Adapt the shared timestamp/value comparator to the actual SleepSummary
            # schema, never to unrelated origin resRates or daytime vitals fields.
            entries = [('respiration', {'vitalsCurve': [
                {'ts': point.get('ts'), 'temp': point.get('breathsPerMinute')}
                for summary in summaries for point in summary.get('respiration') or []]})]
            values = compare(expected, entries)
            if not expected:
                values['status'] = 'no_valid_sdk_values_in_sleep_window'
            elif day not in cache and not persistent:
                values['status'] = 'uncertain_no_cached_day'
            result['respiration'].append({'date': day, **values})
        result['confirmed_missing'] = any(row['status'] in {'missing', 'different_total', 'missing_field'}
                                          for key in ('temperature', 'sleep', 'respiration') for row in result[key]) or result['temperature_rolling_24h']['status'] == 'missing'
        return result

    report['persistent_observations'] = evaluate(durable, persistent=True)
    report['any_local_cache'] = evaluate(caches)
    report['home_display'] = evaluate(home_cache)
    for key in ('temperature', 'sleep', 'respiration'):
        del report[key]
    report['origin_respiration_diagnostic'] = dict(sorted(respiration_days.items()))
    report['respiration_note'] = 'Sleep respiration compares oxygen_table Time/RespirationRate inside recorded sleep windows; 255 and zero are missing. origin resRates counts are diagnostic only.'
    report['confirmed_missing'] = report['persistent_observations']['confirmed_missing'] or report['any_local_cache']['confirmed_missing'] or report['home_display']['confirmed_missing']
    report['incomplete'] = device is None
    local.close()
    sdk.close()
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('root', type=Path)
    parser.add_argument('--timezone', default='Asia/Shanghai')
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    try:
        report = audit(args.root, ZoneInfo(args.timezone))
    except (OSError, ValueError, sqlite3.Error, KeyError) as error:
        print('Audit unavailable: ' + type(error).__name__ + ' (inspect export structure; details suppressed)')
        return 2
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    print('SCOPE            FIELD          DATE         SDK COUNT  STATUS')
    for scope in ('persistent_observations', 'any_local_cache', 'home_display'):
        for field in ('temperature', 'sleep', 'respiration'):
            for row in report[scope][field]:
                count = row.get('sdk_points', row.get('sdk_segments', row.get('sdk_nonzero_values', 0)))
                print(f"{scope:16} {field:14} {row['date']:12} {count:9}  {row['status']}")
        rolling = report[scope]['temperature_rolling_24h']
        print(f"{scope:16} temperature24h {'rolling':12} {rolling['sdk_points']:9}  {rolling['status']}")
    print('SDK partition:', report['scope']['sdk_device'])
    uncertain = len(report['uncertain']) + sum(row['status'].startswith('uncertain')
                  for scope in ('persistent_observations', 'any_local_cache', 'home_display') for field in ('temperature', 'sleep', 'respiration') for row in report[scope][field])
    print('Uncertain observations:', uncertain)
    print('Confirmed missing:', report['confirmed_missing'])
    return 2 if report['incomplete'] else int(report['confirmed_missing'])


if __name__ == '__main__':
    raise SystemExit(main())
