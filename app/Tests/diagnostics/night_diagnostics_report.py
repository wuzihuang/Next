#!/usr/bin/env python3
"""Summarize local overnight evidence without exporting identities or raw payloads."""
import argparse
from collections import Counter
from datetime import datetime, timezone
import json
from pathlib import Path
import re
import tempfile

SNAPSHOT_KEYS = set('day sampleCount hrvSampleCount temperatureSampleCount sleepPresent sleepStart wakeAt sleepMinutes nightHRVKnown nightHRVCount sleepRespirationCount sleepOxygenCount hrvFiveMinuteSlots hrvMinuteTicksAcrossReadPages nightHRVReadComplete hrvReadStatus temperatureReadStatus oxygenReadStatus sleepReadStatus sdkSleepPresent pagesRequested pagesReturned archivedHRVMinutes displayHRVPoints respirationPoints oxygenPoints windowStart windowEnd'.split())
SETTING_KEYS = set('kind on source startHour endHour intervalMinutes state reason cachedAvailable'.split())
UUID = re.compile(r'\b[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}\b', re.I)


def clean(value):
    return UUID.sub('<redacted-id>', str(value))[:160]


def selected(record, keys):
    return {'timestamp': record['timestamp'], **{key: clean(value) for key, value in record['fields'].items() if key in keys}}


def summarize(directory):
    records, malformed, skipped = [], 0, 0
    remaining = 16 * 1024 * 1024
    for path in sorted(directory.glob('events-*.jsonl')):
        size = path.stat().st_size
        if size > remaining:
            skipped += 1
            continue
        remaining -= size
        with path.open('rb') as stream:
            for line in stream:
                try:
                    if len(line) > 65536:
                        raise ValueError('large line')
                    row = json.loads(line)
                    if not isinstance(row, dict) or not isinstance(row.get('fields'), dict):
                        raise ValueError('invalid record')
                    if not all(isinstance(row.get(key), str) for key in ('event', 'timestamp', 'session')):
                        raise ValueError('invalid metadata')
                    if not re.fullmatch(r'[a-zA-Z0-9_.-]{1,80}', row['event']):
                        raise ValueError('invalid event')
                    if not all(isinstance(k, str) and isinstance(v, str) for k, v in row['fields'].items()):
                        raise ValueError('invalid summary fields')
                    datetime.fromisoformat(row['timestamp'].replace('Z', '+00:00'))
                    records.append(row)
                except (ValueError, TypeError, UnicodeError):
                    malformed += 1
    records.sort(key=lambda row: row['timestamp'])
    counts = Counter(row['event'] for row in records)
    starts, ends, outcomes = {}, set(), Counter()
    settings, phases, mapped, ui = {}, [], {}, {}
    readbacks, failures = Counter(), Counter()
    for row in records:
        event, fields = row['event'], row['fields']
        command_key = (row['session'], fields.get('commandID'))
        if event == 'sdk.command_start' and command_key[1]:
            starts[command_key] = row
        elif event == 'sdk.command_end':
            if command_key[1]:
                ends.add(command_key)
            outcomes[clean(fields.get('outcome', 'unknown'))] += 1
        elif event == 'app.scene':
            phases.append(selected(row, {'phase'}))
        elif event.startswith('sdk.setting_'):
            key = (event, fields.get('kind', 'unknown'), fields.get('source', 'none'))
            settings[key] = {'event': event, **selected(row, SETTING_KEYS)}
        elif event == 'sync.mapped':
            mapped[clean(fields.get('day', 'unknown'))] = selected(row, SNAPSHOT_KEYS)
        elif event.startswith('ui.'):
            ui[event] = selected(row, SNAPSHOT_KEYS)
        if event.startswith('storage.') and event.endswith('_readback'):
            readbacks[clean(fields.get('status', 'unknown'))] += 1
        if (event.startswith('storage.') or event.startswith('sync.')) and event.endswith('_failed'):
            failures[event] += 1
    unresolved = [
        {'startID': f'local-{index}', 'command': clean(row['fields'].get('command', 'unknown')),
         'timestamp': row['timestamp'], 'meaning': 'No matching terminal event in retained evidence; not proof of device failure.'}
        for index, (key, row) in enumerate(starts.items(), 1) if key not in ends
    ]
    try:
        lease = json.loads((directory / 'lease.json').read_text())
        expiry = datetime.fromtimestamp(float(lease['expiresAt']), timezone.utc)
        lease_status = {'expiresAt': expiry.isoformat(), 'expiredAtReportTime': datetime.now(timezone.utc) >= expiry}
    except (OSError, ValueError, TypeError, KeyError, OverflowError):
        lease_status = {'status': 'missing_or_invalid'}
    return {
        'schemaVersion': 1, 'lease': lease_status, 'records': len(records),
        'malformedLines': malformed, 'filesSkippedByReadLimit': skipped,
        'firstTimestamp': records[0]['timestamp'] if records else None,
        'lastTimestamp': records[-1]['timestamp'] if records else None,
        'eventCounts': dict(sorted(counts.items())), 'appPhases': phases[-100:],
        'appPhasesOmitted': max(0, len(phases) - 100),
        'settingObservationsLatestBySource': list(settings.values()),
        'sdkCommandOutcomes': dict(outcomes), 'unresolvedCommandStarts': unresolved,
        'latestSyncMappedByDay': mapped, 'storageReadbackStatuses': dict(readbacks),
        'storageReadbackProblems': sum(value for key, value in readbacks.items() if key != 'matched'),
        'storageAndSyncFailures': dict(failures), 'latestUIInputs': ui,
        'limits': [
            'SDK cache getter evidence is not raw BLE packet evidence.',
            'No events while the app is suspended does not prove the band stopped sampling.',
            'Cached settings are not fresh device readbacks; sources remain separate.',
            'Unresolved starts can reflect termination or retained-file boundaries.',
            'This report identifies pipeline observations, not a firmware root cause.',
            'The writer retains bounded files; this report never assumes the retained log covers the whole night.'
        ]
    }


def self_test():
    with tempfile.TemporaryDirectory() as temp:
        root = Path(temp)
        def row(event, **fields):
            return {'event': event, 'timestamp': '2026-09-05T12:00:00Z', 'session': 'secret-session', 'fields': fields}
        fixture = [row('sdk.command_start', command='readHRV', commandID='private-one'),
                   row('sdk.command_start', command='readOrigin', commandID='private-two'),
                   row('sdk.command_end', command='readOrigin', commandID='private-two', outcome='timeout'),
                   row('storage.observations_readback', status='mismatched', userId='NEVER_EXPORT'),
                   row('storage.home_save_failed', account='NEVER_EXPORT'),
                   row('sdk.setting_snapshot', kind='hrv', on='true', source='cached_switch_table'),
                   row('sdk.setting_snapshot', kind='hrv', on='false', source='base_switch_callback'),
                   row('sync.mapped', day='2026-09-05', nightHRVCount='0'),
                   row('ui.sleep_input', day='2026-09-05', displayHRVPoints='0'),
                   row('app.scene', phase='background')]
        (root / 'events-2026-09-05.jsonl').write_text('\n'.join(map(json.dumps, fixture)) + '\n{broken\n')
        result = summarize(root)
        assert result['malformedLines'] == 1
        assert len(result['unresolvedCommandStarts']) == 1
        assert result['unresolvedCommandStarts'][0]['command'] == 'readHRV'
        assert result['sdkCommandOutcomes'] == {'timeout': 1}
        assert result['storageReadbackProblems'] == 1
        assert result['storageAndSyncFailures']['storage.home_save_failed'] == 1
        assert len(result['settingObservationsLatestBySource']) == 2
        assert result['latestUIInputs']['ui.sleep_input']['displayHRVPoints'] == '0'
        exported = json.dumps(result)
        assert all(secret not in exported for secret in ('NEVER_EXPORT', 'secret-session', 'private-one', 'private-two'))
    print('PASS: missing/failed commands, storage mismatch/failure, malformed evidence, source separation, sanitized output')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('directory', nargs='?', type=Path)
    parser.add_argument('--self-test', action='store_true')
    args = parser.parse_args()
    if args.self_test:
        self_test()
    elif not args.directory or not args.directory.is_dir():
        parser.error('provide the retrieved night-diagnostics directory')
    else:
        print(json.dumps(summarize(args.directory), indent=2, ensure_ascii=False))
