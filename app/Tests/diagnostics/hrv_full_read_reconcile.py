#!/usr/bin/env python3
"""Read-only, redacted reconciliation of full SDK callbacks, SDK cache and app storage.

Swift executes production HealthSampleMapping; Python only compares its results.
Device/account partitions are never printed. Capture snapshots at different times may
have additional tail minutes; these are reported separately from overlapping changes.
"""
import argparse
from contextlib import contextmanager
import datetime as dt
import json
from pathlib import Path
import sqlite3
import subprocess
import tempfile
from zoneinfo import ZoneInfo

APP = Path(__file__).resolve().parents[2]
SWIFT = r'''
import Foundation
@main struct Reconcile {
 static func main() throws {
  let inputs = try JSONSerialization.jsonObject(with: FileHandle.standardInput.readDataToEndOfFile()) as! [[[String: Any]]]
  let output: [[String: Any]] = inputs.map { rows in
   let samples = rows.compactMap(HealthSampleMapping.hrv)
   return ["minutes": HealthSampleMapping.hrvByMinute(samples), "slots": HealthSampleMapping.hrvBySlot(samples),
    "observedMinutes": Array(Set(samples.map(\.time))).sorted(),
    "rrMinutes": Array(Set(samples.filter { $0.rrCount > 0 }.map(\.time))).sorted()]
  }
  FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject: output, options: [.sortedKeys]))
 }
}
'''


def read_json(path):
    return json.loads(Path(path).read_text())


def clock(value):
    dt.datetime.strptime(value, '%H:%M')
    if len(value) != 5:
        raise ValueError('Invalid minute clock')
    return value


def full_rows(path):
    capture = read_json(path)
    callbacks = capture.get('callbacks', [])
    finals = [c for c in callbacks if isinstance(c.get('data'), list)]
    if not finals:
        raise ValueError('No non-nil full callback array')
    final = finals[-1]
    progress = [c for c in callbacks[:callbacks.index(final)] if c.get('totalPackage', 0) > 0]
    completed = bool(progress and progress[-1]['currentPackage'] == progress[-1]['totalPackage'])
    terminal = final.get('currentPackage') == 0 and final.get('totalPackage') == 0
    if not completed or not terminal:
        raise ValueError('Full callback lacks completed N/N then terminal 0/0 data')
    rows = [minute for slot in final['data'] for minute in slot.get('HRV', [])]
    return rows, {'completedPackages': progress[-1]['totalPackage'], 'terminalArrayRows': len(final['data']),
                  'terminalZeroZero': terminal}


@contextmanager
def readonly(path):
    connection = sqlite3.connect(Path(path).resolve().as_uri() + '?mode=ro', uri=True)
    try:
        yield connection
    finally:
        connection.close()


def sdk_rows(path, day):
    with readonly(path) as db:
        partitions = db.execute('SELECT DISTINCT accountUser FROM hrv_table WHERE createdTime=?', (day,)).fetchall()
        if len(partitions) != 1:
            raise ValueError('SDK archive must contain exactly one device partition')
        rows = db.execute('SELECT json FROM hrv_table WHERE accountUser=? AND createdTime=?',
                          (partitions[0][0], day)).fetchall()
        if len(rows) != 1:
            raise ValueError('SDK day partition is missing or ambiguous')
        return json.loads(rows[0][0])


def production(inputs):
    with tempfile.TemporaryDirectory(prefix='next-hrv-reconcile-') as temporary:
        root = Path(temporary)
        source = root / 'main.swift'
        source.write_text(SWIFT)
        result = subprocess.run(['swiftc', '-parse-as-library', str(source),
            str(APP / 'NextBody/Services/Band/HealthSampleMapping.swift'), '-o', str(root / 'map')], capture_output=True)
        if result.returncode:
            raise ValueError('Production mapping harness could not compile')
        result = subprocess.run([str(root / 'map')], input=json.dumps(inputs).encode(), capture_output=True)
        if result.returncode:
            raise ValueError('Production mapping harness failed')
        return json.loads(result.stdout)


def row_map(rows):
    output = {}
    for row in rows:
        time = clock(row['time'])
        if time in output and output[time].get('hearts') != row.get('hearts'):
            raise ValueError('Conflicting repeated minute in input')
        output[time] = row
    return output


def compare_values(expected, actual):
    overlap = expected.keys() & actual.keys()
    mismatches = sum(abs(expected[t] - actual[t]) > 0.11 for t in overlap)
    return {'expectedCount': len(expected), 'overlapCount': len(overlap), 'matchedCount': len(overlap) - mismatches,
            'differentValueCount': mismatches, 'missingExpectedCount': len(expected.keys() - actual.keys()),
            'actualAdditionalCount': len(actual.keys() - expected.keys()),
            'matchedRatio': (len(overlap) - mismatches) / len(expected) if expected else None,
            'allExpectedMatched': len(overlap) == len(expected) and mismatches == 0}


def summary(mapped, start, end, rows):
    valid = mapped['minutes']
    rr = mapped['rrMinutes']
    observed = mapped['observedMinutes']
    observed = sorted(row_map(rows))
    return {'observedMinuteCount': len(observed), 'readStart': observed[0] if observed else None,
        'readEnd': observed[-1] if observed else None, 'rrMinuteCount': len(rr), 'validRMSSDMinuteCount': len(valid), 'validFiveMinuteSlotCount': len(mapped['slots']),
        'sleepRRMinuteCount': sum(start <= t < end for t in rr),
        'sleepValidMinuteCount': sum(start <= t < end for t in valid),
        'hours': {f'{h:02}': {'observedMinuteCount': sum(t[:2] == f'{h:02}' for t in observed), 'observedMinuteCount': sum(t[:2] == f'{h:02}' for t in observed),
                              'rrMinutes': sum(t[:2] == f'{h:02}' for t in rr),
                              'validRMSSDMinutes': sum(t[:2] == f'{h:02}' for t in valid)} for h in range(24)}}


def full_comparison(before_rows, after_rows, before, after):
    old, new = row_map(before_rows), row_map(after_rows)
    overlap = old.keys() & new.keys()
    changed = sum(old[t].get('hearts') != new[t].get('hearts') for t in overlap)
    valid_added = sorted(after['minutes'].keys() - before['minutes'].keys())
    return {'overlappingRawMinutes': len(overlap), 'changedHeartsMinuteCount': changed,
        'missingPreviouslyPresentMinutes': len(old.keys() - new.keys()),
        'additionalRawMinutes': len(new.keys() - old.keys()),
        'newValidRMSSDMinutes': valid_added,
        'newValidWithinPreviouslyCapturedMinutes': [t for t in valid_added if t in old],
        'newValidOutsidePreviousCapture': [t for t in valid_added if t not in old],
        'overlapRMSSD': compare_values({t: v for t, v in before['minutes'].items() if t in new}, after['minutes']),
        'interpretation': 'Changes reflect the two captured states; new tail minutes are not classified as cache loss.'}


def app_rows(path, day, zone, account):
    with readonly(path) as db:
        rows = db.execute('SELECT account,payload FROM observation_documents WHERE key=?', ('band-day:' + day,)).fetchall()
        if account is not None:
            rows = [r for r in rows if r[0] == account]
        if len(rows) != 1:
            raise ValueError('Current-day observation account is missing or ambiguous; select --account')
        owner = rows[0][0]
        previous = (dt.date.fromisoformat(day) - dt.timedelta(days=1)).isoformat()
        archives = db.execute('SELECT payload FROM observation_documents WHERE account=? AND key IN (?,?)',
                             (owner, 'band-day:' + previous, 'band-day:' + day)).fetchall()
        homes = db.execute('SELECT payload FROM documents WHERE account=? AND key=?', (owner, 'home')).fetchall()
        if len(homes) != 1:
            raise ValueError('Selected account Home snapshot is missing or ambiguous')
        home = json.loads(homes[0][0])
        if home.get('dayKey') != day:
            raise ValueError('Selected Home snapshot is not the requested current day')
        def points(samples):
            result = {}
            for sample in samples:
                ts = sample.get('ts')
                if not isinstance(ts, (int, float)):
                    raise ValueError('Unsupported local timestamp encoding')
                stamp = dt.datetime.fromtimestamp(ts + 978307200, zone)
                if stamp.date().isoformat() == day and sample.get('hrv') is not None:
                    result[stamp.strftime('%H:%M')] = sample['hrv']
            return result
        durable = points([s for (blob,) in archives for s in json.loads(blob).get('samples', [])])
        # Home todayVitals may already include pre-04:00 night minutes. Add the matching
        # previous-day detail only; never select another account's newer Home payload.
        today_points = home.get('todayVitals', [])
        prior_points = [s for detail in home.get('details', []) if detail.get('dayKey') == previous
                        for s in detail.get('vitalsCurve', [])]
        snapshot = points(prior_points + today_points)
        return durable, snapshot


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--sdk-db')
    parser.add_argument('--full-json', required=True)
    parser.add_argument('--after-full-json')
    parser.add_argument('--day', required=True)
    parser.add_argument('--sleep-start', default='03:59')
    parser.add_argument('--sleep-end', default='13:09')
    parser.add_argument('--local-db')
    parser.add_argument('--account', help='Optional account selector; never included in output')
    parser.add_argument('--timezone', default='Asia/Shanghai', help='Phone capture timezone (default Asia/Shanghai)')
    args = parser.parse_args()
    dt.date.fromisoformat(args.day)
    start, end = clock(args.sleep_start), clock(args.sleep_end)
    if start >= end:
        raise ValueError('This single-day audit requires sleep start before end')
    full, phase = full_rows(args.full_json)
    inputs = [full]
    sdk = sdk_rows(args.sdk_db, args.day) if args.sdk_db else None
    after, after_phase = full_rows(args.after_full_json) if args.after_full_json else (None, None)
    if sdk is not None:
        inputs.append(sdk)
    if after is not None:
        inputs.append(after)
    mapped = production(inputs)
    output = {'day': args.day, 'timezone': args.timezone, 'sleepWindow': [start, end],
              'captureProvenance': 'Full callback day and device identity must be guaranteed by the capture session; CLI day is supplied by the operator.',
              'sourceScope': {'fullCaptureHasDayOrDeviceIdentity': False,
                'daySource': '--day supplied by caller',
                'bindingRequirement': 'Caller must ensure captures belong to the same bound device; the acquisition probe verifies binding.',
                'unobservedHoursAreNotMissingMeasurements': True},
              'callbackStage': phase, 'full': summary(mapped[0], start, end, full)}
    if sdk is not None:
        expected = mapped[1]
        output['sdkCache'] = summary(expected, start, end, sdk)
        output['sdkToFull'] = full_comparison(sdk, full, expected, mapped[0])
        if args.local_db:
            durable, home = app_rows(args.local_db, args.day, ZoneInfo(args.timezone), args.account)
            output['sdkToDurableFiveMinute'] = compare_values(expected['slots'], durable)
            output['sdkToHomeFiveMinute'] = compare_values(expected['slots'], home)
    elif args.local_db:
        raise ValueError('--local-db requires --sdk-db for a captured-time baseline')
    if after is not None:
        output['afterCallbackStage'] = after_phase
        output['afterFull'] = summary(mapped[-1], start, end, after)
        output['beforeToAfterFull'] = full_comparison(full, after, mapped[0], mapped[-1])
    print(json.dumps(output, indent=2, sort_keys=True))


if __name__ == '__main__':
    try:
        main()
    except (ValueError, KeyError, TypeError, sqlite3.Error, OSError):
        # Raw exceptions may contain paths, SQL or payload details. Never echo them.
        raise SystemExit('Reconciliation failed: invalid or ambiguous input, unavailable database, or incompatible capture/schema.')
