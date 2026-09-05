"""Replay real SDK RR through the production Swift minute mapper and optionally compare local sleep.hrv."""
import argparse
from datetime import datetime
import json
import math
from pathlib import Path
import sqlite3
import subprocess
import tempfile
from zoneinfo import ZoneInfo

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('sdk_database', type=Path)
parser.add_argument('--day', required=True)
parser.add_argument('--start', required=True)
parser.add_argument('--end', required=True)
parser.add_argument('--local-db', type=Path)
parser.add_argument('--sleep-day')
parser.add_argument('--timezone', default='Asia/Shanghai')
args = parser.parse_args()
app = Path(__file__).resolve().parents[2]
with sqlite3.connect(args.sdk_database.resolve().as_uri() + '?mode=ro', uri=True) as db:
    rows = db.execute('SELECT json FROM hrv_table WHERE createdTime=?', (args.day,)).fetchall()
    if len(rows) != 1:
        raise SystemExit('SDK day has missing/ambiguous device partition; select an unambiguous export')
    raw = rows[0][0]
with tempfile.TemporaryDirectory() as directory:
    path = Path(directory)
    (path / 'rows.json').write_text(raw)
    (path / 'main.swift').write_text(r'''
import Foundation
let raw = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))) as! [[String: Any]]
let minutes = HealthSampleMapping.hrvByMinute(raw.compactMap(HealthSampleMapping.hrv))
let points = minutes.filter { $0.key >= CommandLine.arguments[2] && $0.key < CommandLine.arguments[3] }
    .sorted { $0.key < $1.key }.map { ["time": $0.key, "rmssd_ms": $0.value] as [String: Any] }
print(String(data: try JSONSerialization.data(withJSONObject: points), encoding: .utf8)!)
''')
    subprocess.run(['swiftc', str(app / 'NextBody/Services/Band/HealthSampleMapping.swift'), str(path / 'main.swift'), '-o', str(path / 'test')], check=True)
    result = subprocess.run([str(path / 'test'), str(path / 'rows.json'), args.start, args.end], check=True, capture_output=True, text=True)
    expected = {row['time']: row['rmssd_ms'] for row in json.loads(result.stdout)}
print(f'{args.day}: production Swift minute RMSSD count={len(expected)}')
if args.local_db:
    with sqlite3.connect(args.local_db.resolve().as_uri() + '?mode=ro', uri=True) as db:
        rows = db.execute('SELECT payload FROM observation_documents WHERE key=?', ('band-day:' + (args.sleep_day or args.day),)).fetchall()
    if len(rows) != 1:
        raise SystemExit('Local sleep day has missing/ambiguous account partition')
    sleep = json.loads(rows[0][0]).get('sleep') or {}
    if 'hrv' not in sleep:
        raise SystemExit('FAIL: local sleep.hrv is unknown/unmigrated')
    actual = {}
    for point in sleep['hrv']:
        timestamp = datetime.fromtimestamp(point['ts'] + 978307200, ZoneInfo(args.timezone))
        clock = timestamp.strftime('%H:%M')
        if timestamp.strftime('%Y-%m-%d') == args.day and args.start <= clock < args.end:
            if clock in actual:
                raise SystemExit('FAIL: duplicate local measured minute')
            actual[clock] = point['rmssdMS']
    matches = actual.keys() == expected.keys() and all(math.isclose(actual[k], v, rel_tol=1e-10, abs_tol=1e-10) for k, v in expected.items())
    if not matches:
        raise SystemExit(f'FAIL: expected {len(expected)} SDK minutes, local {len(actual)}; timestamps/values differ')
    print(f'PASS: local sleep.hrv matches all {len(expected)} measured timestamps and RMSSD values')
