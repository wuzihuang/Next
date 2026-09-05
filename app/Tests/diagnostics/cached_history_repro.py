#!/usr/bin/env python3
"""Compile the real SDK cache-date probe with deterministic database fixtures.

Default fixtures contain no personal data. Optional --sdk-db reads an exported
wypDataBase.sqlite; its sibling app preferences select the current device. An
export with multiple partitions and no matching preferences is rejected.
No identifiers or health measurements are printed or committed.
"""
import argparse
from datetime import date
import json
from pathlib import Path
import plistlib
import sqlite3
import subprocess
import tempfile


APP = Path(__file__).resolve().parents[2]


def private_fixture(path, ending):
    with sqlite3.connect(path.resolve().as_uri() + '?mode=ro', uri=True) as db:
        partitions = {row[0] for row in db.execute('SELECT DISTINCT accountUser FROM temperatrue_table')}
        preferences = {}
        for item in path.parent.parent.glob('Library/Preferences/*.plist'):
            preferences.update(plistlib.loads(item.read_bytes()))
        remembered = {preferences[key] for key in ('VPDeviceMacKey', 'deviceMacKey')
                      if isinstance(preferences.get(key), str) and preferences[key]}
        matching = partitions.intersection(remembered)
        if len(matching) == 1:
            partition = next(iter(matching))
        elif not remembered and len(partitions) == 1:
            partition = next(iter(partitions))
        else:
            raise ValueError('ambiguous_partition')
        rows = {day: json.loads(payload) for day, payload in db.execute(
            'SELECT createdTime,json FROM temperatrue_table WHERE accountUser=?', (partition,))}
    end = date.fromisoformat(ending or max(rows))
    expected = set()
    for day, points in rows.items():
        offset = (end - date.fromisoformat(day)).days
        if not 0 <= offset <= 6:
            continue
        if points and offset > 0:
            expected.add(offset)
        for point in points:
            try:
                value = float(point.get('originalValue', point.get('riginalValue')))
                value = value / 10 if value > 100 else value
                hour, minute = int(point['hour']), int(point['minute'])
                if 10 <= value <= 50 and 0 <= hour < 4 and 0 <= minute < 60 and offset < 6:
                    expected.add(offset + 1)
            except (ValueError, TypeError, KeyError):
                continue
    return rows, end, sorted(expected)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--sdk-db', type=Path)
    parser.add_argument('--end-date', help='Calendar date YYYY-MM-DD for the optional SDK fixture')
    args = parser.parse_args()
    production = (APP / 'NextBody/Services/Band/VeepooBand.swift').read_text()
    start = production.index('    func cachedHistoryDayOffsets(')
    end = production.index('    /// HRV and temperature', start)
    source = '''import Foundation
struct Model { let deviceAddress: String? = "fixture" }
struct Central { let peripheralModel: Model? = Model() }
enum BandError: Error { case notConnected }
struct Temperature { let time: String }
struct HealthSampleMapping {
 static func temperature(from raw: [String: Any]) -> Temperature? {
  guard let hour = Int(String(describing: raw["hour"] ?? "")), (0..<24).contains(hour),
        let minute = Int(String(describing: raw["minute"] ?? "")), (0..<60).contains(minute),
        let value = Double(String(describing: raw["originalValue"] ?? raw["riginalValue"] ?? "")),
        (10...50).contains(value > 100 ? value / 10 : value) else { return nil }
  return Temperature(time: String(format: "%02d:%02d", hour, minute))
 }
}
struct VPDataBaseOperation {
 static let rows = (try! JSONSerialization.jsonObject(with: Data(contentsOf:
  URL(fileURLWithPath: CommandLine.arguments[1])))) as! [String: [[String: Any]]]
 static func veepooSDKGetDeviceTemperatureData(withDate date: String, andTableID: String) -> Any? { rows[date] }
 static func veepooSDKGetOriginalData(withDate: String, andTableID: String) -> Any? { nil }
 static func veepooSDKGetDeviceHrvData(withDate: String, andTableID: String) -> Any? { nil }
 static func veepooSDKGetDeviceOxygenData(withDate: String, andTableID: String) -> Any? { nil }
 static func veepooSDKGetDeviceBloodGlucoseData(withDate: String, andTableID: String) -> Any? { nil }
 static func veepooSDKGetAccurateSleepData(withDate: String, andTableID: String) -> [Int]? { nil }
 static func veepooSDKGetSleepData(withDate: String, andTableID: String) -> Any? { nil }
}
struct Adapter {
 let central = Central()
 static func dayString(daysAgo: Int) -> String {
  let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd"
  formatter.timeZone = TimeZone(secondsFromGMT: 0)
  return formatter.string(from: formatter.date(from: CommandLine.arguments[2])!.addingTimeInterval(Double(-daysAgo) * 86400))
 }
''' + production[start:end] + '''
}
let offsets = try await Adapter().cachedHistoryDayOffsets(limit: Int(CommandLine.arguments[3])!)
let expected = CommandLine.arguments[4].split(separator: ",").compactMap { Int($0) }
guard offsets == expected else {
 print("FAIL cache-date offsets: expected \\(expected), received \\(offsets)")
 exit(1)
}
print("PASS " + CommandLine.arguments[5])
'''
    point = {'hour': '12', 'minute': '00', 'originalValue': '33.2'}
    early = {**point, 'hour': '00', 'minute': '20'}
    cases = [
        ('older SDK date survives retention3', {'2026-09-02': [point]}, 6, [3]),
        ('today early reading targets previous user day', {'2026-09-05': [early]}, 6, [1]),
        ('old early reading preserves both recovery dates', {'2026-09-02': [early]}, 6, [3, 4]),
        ('no cached data creates no recovery requests', {}, 6, []),
        ('zero limit makes no recovery request', {'2026-09-02': [point]}, 0, []),
        ('bounded scan skips distant history', {'2026-08-29': [point]}, 6, []),
        ('requested small limit is respected', {'2026-09-02': [point]}, 1, []),
    ]
    ending = date(2026, 9, 5)
    private = None
    if args.sdk_db:
        try:
            private = private_fixture(args.sdk_db, args.end_date)
        except (OSError, ValueError, sqlite3.Error, plistlib.InvalidFileException):
            print('SDK fixture unavailable or partition ambiguous; identifying details suppressed')
            return 2
    with tempfile.TemporaryDirectory(prefix='next-cached-history-') as directory:
        temporary = Path(directory)
        (temporary / 'main.swift').write_text(source)
        subprocess.run(['swiftc', str(temporary / 'main.swift'), '-o', str(temporary / 'run')], check=True)

        def run(label, rows, end_day, limit, expected):
            fixture = temporary / 'fixture.json'
            fixture.write_text(json.dumps(rows))
            return subprocess.run([str(temporary / 'run'), str(fixture), end_day.isoformat(),
                                   str(limit), ','.join(map(str, expected)), label]).returncode

        failures = sum(run(label, rows, ending, limit, expected) != 0 for label, rows, limit, expected in cases)
        if private:
            rows, end_day, expected = private
            failures += run('optional current-device SDK temperature dates', rows, end_day, 6, expected) != 0
        return int(failures > 0)


if __name__ == '__main__':
    raise SystemExit(main())
