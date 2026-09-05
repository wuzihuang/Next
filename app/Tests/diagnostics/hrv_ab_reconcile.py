#!/usr/bin/env python3
"""Read-only scientific-sleep ON/OFF/ON reconciliation; never controls a device.

Consumes scientific-sleep-ab/manifest.json and its relative callback files. Production
HealthSampleMapping performs RR conversion through hrv_full_read_reconcile.production.
Run --self-test for deterministic synthetic boundary fixtures (no device conclusions).
"""
import argparse
import datetime as dt
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from zoneinfo import ZoneInfo

SPEC = importlib.util.spec_from_file_location('full_reconcile', Path(__file__).with_name('hrv_full_read_reconcile.py'))
FULL = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(FULL)


def instant(value):
    result = dt.datetime.fromisoformat(value.replace('Z', '+00:00'))
    if result.tzinfo is None:
        raise ValueError('Timestamps must include a timezone')
    return result


def analyze_window(window, capture, rows, mapped, zone):
    confirmed = instant(window['confirmedAt']).astimezone(zone)
    quiet_start = instant(window.get('quietStartedAt', window['confirmedAt'])).astimezone(zone)
    end = instant(window.get('quietEndedAt', window['sampleEndedAt'])).astimezone(zone)
    completed = instant(capture['completedAt']).astimezone(zone)
    effective_start = max(confirmed, quiet_start)
    if end <= effective_start or end.date() != effective_start.date():
        raise ValueError('Window must be positive and within one capture calendar date')
    start = effective_start.replace(second=0, microsecond=0) + dt.timedelta(minutes=1)
    stop = end.replace(second=0, microsecond=0)
    captured_complete = completed.replace(second=0, microsecond=0)
    raw = FULL.row_map(rows)
    times = []
    cursor = start
    while cursor < stop:
        time = cursor.strftime('%H:%M')
        observed = time in raw and cursor < captured_complete
        times.append({'time': time, 'observed': observed,
                      'hasValidRR': time in mapped['rrMinutes'] if observed else None,
                      'rmssdMS': mapped['minutes'].get(time) if observed else None})
        cursor += dt.timedelta(minutes=1)
    expected_state = {'off': False, 'restored_on': True}.get(window['name'])
    readback = window.get('readback', {}).get('scientificSleepOn')
    end_readback = window.get('endingReadback', {}).get('scientificSleepOn')
    readback_matches = isinstance(readback, bool) and readback == expected_state
    end_matches = end_readback is None or end_readback == expected_state
    last_clock = max(raw) if raw else None
    reaches_end = last_clock is not None and last_clock >= stop.strftime('%H:%M')
    observed_count = sum(m['observed'] for m in times)
    enough_duration = (end - quiet_start).total_seconds() >= 720
    complete = bool(times) and observed_count == len(times) and completed >= end and reaches_end
    complete = complete and readback_matches and end_matches and enough_duration
    return {'name': window['name'], 'day': effective_start.date().isoformat(),
            'confirmedAt': confirmed.isoformat(), 'quietStartedAt': quiet_start.isoformat(),
            'quietEndedAt': end.isoformat(), 'quietElapsedSeconds': (end - quiet_start).total_seconds(),
            'excludedSwitchMinute': effective_start.strftime('%H:%M'),
            'analysisStartInclusive': start.isoformat(), 'analysisEndExclusive': stop.isoformat(),
            'observedMinuteCount': observed_count, 'expectedCompleteMinuteCount': len(times),
            'coverage': observed_count / len(times) if times else None,
            'readbackMatchesPhase': readback_matches, 'endingReadbackAvailable': end_readback is not None,
            'endingReadbackMatchesPhase': end_matches if end_readback is not None else None,
            'captureCompletedAfterWindow': completed >= end, 'rawReadReachesWindowEnd': reaches_end,
            'atLeastTwelveQuietMinutes': enough_duration, 'completeWindowObserved': complete,
            'rrMinuteCount': sum(m['hasValidRR'] is True for m in times),
            'validRMSSDMinuteCount': sum(m['rmssdMS'] is not None for m in times), 'minutes': times}


class BoundaryFixtures(unittest.TestCase):
    """Synthetic timing/mapping fixtures only; these are not physiological observations."""
    def fixture(self):
        window = {'name': 'off', 'confirmedAt': '2026-09-05T10:00:30Z',
                  'quietStartedAt': '2026-09-05T10:00:35Z', 'quietEndedAt': '2026-09-05T10:12:35Z',
                  'sampleEndedAt': '2026-09-05T10:12:35Z', 'readback': {'scientificSleepOn': False}}
        rows = [{'time': f'10:{m:02}', 'hearts': []} for m in range(13)]
        mapped = {'minutes': {'10:00': 50, '10:01': 51, '10:12': 52}, 'rrMinutes': ['10:00', '10:01', '10:12']}
        capture = {'completedAt': '2026-09-05T10:13:00Z'}
        return window, capture, rows, mapped, ZoneInfo('UTC')

    def testExcludesSwitchAndPartialEndMinutes(self):
        report = analyze_window(*self.fixture())
        self.assertEqual(report['observedMinuteCount'], 11)
        self.assertEqual(report['validRMSSDMinuteCount'], 1)
        self.assertEqual(report['minutes'][0]['time'], '10:01')
        self.assertEqual(report['minutes'][-1]['time'], '10:11')
        self.assertTrue(report['completeWindowObserved'])

    def testUnobservedMinuteIsUnknownNotZero(self):
        window, capture, rows, mapped, zone = self.fixture()
        rows = [r for r in rows if r['time'] != '10:05']
        report = analyze_window(window, capture, rows, mapped, zone)
        self.assertFalse(report['completeWindowObserved'])
        missing = next(m for m in report['minutes'] if m['time'] == '10:05')
        self.assertIsNone(missing['hasValidRR'])
        self.assertIsNone(missing['rmssdMS'])

    def testReadBeforeWindowEndCannotCompare(self):
        window, capture, rows, mapped, zone = self.fixture()
        capture['completedAt'] = '2026-09-05T10:11:30Z'
        self.assertFalse(analyze_window(window, capture, rows, mapped, zone)['completeWindowObserved'])

    def testWrongReadbackCannotCompare(self):
        window, capture, rows, mapped, zone = self.fixture()
        window['readback']['scientificSleepOn'] = True
        self.assertFalse(analyze_window(window, capture, rows, mapped, zone)['completeWindowObserved'])

    def testCaptureMustReachWindowTailEvenThoughPartialMinuteExcluded(self):
        window, capture, rows, mapped, zone = self.fixture()
        rows = [r for r in rows if r['time'] != '10:12']
        report = analyze_window(window, capture, rows, mapped, zone)
        self.assertEqual(report['coverage'], 1)
        self.assertFalse(report['completeWindowObserved'])

    def testProductionMapperIsUsedForMinuteEvidence(self):
        mapped = FULL.production([[{'time': '10:01', 'hearts': ['80', '82']}]])[0]
        self.assertEqual(mapped['rrMinutes'], ['10:01'])
        self.assertEqual(mapped['minutes'], {'10:01': 20})

    def testIncompleteCallbackRejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / 'partial.json'
            path.write_text(json.dumps({'callbacks': [{'currentPackage': 1, 'totalPackage': 2, 'data': None}]}))
            with self.assertRaises(ValueError):
                FULL.full_rows(path)

    def testPreviouslyCapturedMinuteChangesRemainSeparate(self):
        before = [{'time': '09:55', 'hearts': ['80', '82']}]
        after = [{'time': '09:55', 'hearts': ['80', '84']}, {'time': '10:05', 'hearts': ['80', '82']}]
        old = {'minutes': {'09:55': 20}}
        new = {'minutes': {'09:55': 40, '10:05': 20}}
        report = FULL.full_comparison(before, after, old, new)
        self.assertEqual(report['changedHeartsMinuteCount'], 1)
        self.assertEqual(report['newValidOutsidePreviousCapture'], ['10:05'])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--manifest')
    parser.add_argument('--timezone', default='Asia/Shanghai')
    parser.add_argument('--self-test', action='store_true')
    args = parser.parse_args()
    if args.self_test:
        result = unittest.TextTestRunner().run(unittest.defaultTestLoader.loadTestsFromTestCase(BoundaryFixtures))
        return 0 if result.wasSuccessful() else 1
    if not args.manifest:
        parser.error('--manifest or --self-test is required')
    manifest_path = Path(args.manifest).resolve()
    manifest = FULL.read_json(manifest_path)
    if manifest.get('schemaVersion') != 1:
        raise ValueError('Unsupported manifest version')
    windows = manifest.get('windows', [])
    if len({w['name'] for w in windows}) != len(windows):
        raise ValueError('Ambiguous repeated phase names')
    order = {'on_baseline': 0, 'off': 1, 'restored_on': 2}
    if [order.get(w['name'], -1) for w in windows] != sorted(order.get(w['name'], -1) for w in windows):
        raise ValueError('Phases must be in acquisition order')
    accepted, reports = [], []
    for window in windows:
        name = window.get('name')
        if name not in ('on_baseline', 'off', 'restored_on'):
            raise ValueError('Unknown phase')
        relative = Path(window['fullFile'])
        file = (manifest_path.parent / relative).resolve()
        if relative.is_absolute() or not file.is_relative_to(manifest_path.parent):
            raise ValueError('Capture file must be relative to manifest directory')
        try:
            rows, phase = FULL.full_rows(file)
            capture = FULL.read_json(file)
            accepted.append((window, capture, rows, phase))
        except (ValueError, OSError, KeyError, TypeError):
            reports.append({'name': name, 'completeWindowObserved': False,
                            'error': 'Missing, incomplete or incompatible callback capture'})
    mapped = FULL.production([entry[2] for entry in accepted]) if accepted else []
    previous = None
    for entry, mapping in zip(accepted, mapped):
        window, capture, rows, phase = entry
        try:
            if window['name'] == 'on_baseline':
                report = {'name': 'on_baseline', 'purpose': 'Historical baseline only; no equal-duration intervention window',
                          'completeWindowObserved': False}
            else:
                report = analyze_window(window, capture, rows, mapping, ZoneInfo(args.timezone))
            report['callbackStage'] = phase
            if previous is not None:
                old_window, old_rows, old_mapping = previous
                report['previousCaptureComparison'] = FULL.full_comparison(old_rows, rows, old_mapping, mapping)
                report['previousCaptureComparison']['previousPhase'] = old_window['name']
            reports.append(report)
            previous = (window, rows, mapping)
        except (ValueError, KeyError, TypeError):
            reports.append({'name': window['name'], 'completeWindowObserved': False,
                            'error': 'Missing or invalid confirmed readback/window timing'})
    phases = {r['name']: r for r in reports}
    session_valid = manifest.get('valid', True) is not False and manifest.get('pendingRestore') is False
    session_valid = session_valid and manifest.get('needsRestartRestore', False) is False
    comparable = session_valid and all(phases.get(name, {}).get('completeWindowObserved', False)
                                       for name in ('off', 'restored_on'))
    output = {'timezone': args.timezone, 'manifestValidAndRestored': session_valid,
              'offAndRestoredOnWindowsComparable': comparable, 'phases': reports,
              'sourceScope': {'bindingVerificationSource': 'Caller acquisition probe; this script cannot verify device identity independently',
                  'captureFilesContainNoDeviceOrDayIdentity': True,
                  'dayDerivedFromConfirmedPhaseTimestamps': True,
                  'unobservedMinuteIsUnknown': True},
              'interpretation': 'Short daytime ON/OFF/ON observations cannot establish the cause of missing overnight HRV. Historical RR changes and new tail minutes are reported separately; no causal attribution is made.'}
    if comparable:
        output['observedDifference'] = {
            'onMinusOffValidRMSSDMinuteCount': phases['restored_on']['validRMSSDMinuteCount'] - phases['off']['validRMSSDMinuteCount'],
            'offCoverage': phases['off']['coverage'], 'restoredOnCoverage': phases['restored_on']['coverage']}
    print(json.dumps(output, indent=2, sort_keys=True))
    return 0


if __name__ == '__main__':
    try:
        raise SystemExit(main())
    except (ValueError, KeyError, TypeError, OSError):
        raise SystemExit('A/B reconciliation failed: invalid or unavailable manifest/capture; no device or account details emitted.')
