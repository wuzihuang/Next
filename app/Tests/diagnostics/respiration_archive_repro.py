"""Compare the production read-only SDK archive reader against exported oxygen JSON."""
import argparse
from pathlib import Path
import sqlite3
import subprocess
import tempfile

parser = argparse.ArgumentParser()
parser.add_argument('database')
parser.add_argument('--day', required=True)
parser.add_argument('--start', required=True, help='HH:mm, inclusive')
parser.add_argument('--end', required=True, help='HH:mm, exclusive')
args = parser.parse_args()
root = Path(__file__).resolve().parents[2]
with sqlite3.connect(Path(args.database).resolve().as_uri() + '?mode=ro', uri=True) as connection:
    rows = connection.execute('SELECT accountUser,json FROM oxygen_table WHERE createdTime=?', (args.day,)).fetchall()
    if len(rows) != 1:
        raise SystemExit('Expected one device partition; select an unambiguous export')
    address, oxygen = rows[0]
with tempfile.TemporaryDirectory() as directory:
    path = Path(directory)
    (path / 'oxygen.json').write_text(oxygen)
    (path / 'main.swift').write_text(r'''
import Foundation
let root = URL(fileURLWithPath: CommandLine.arguments[1])
let start = CommandLine.arguments[2], end = CommandLine.arguments[3]
let oxygen = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("oxygen.json"))) as! [[String: Any]]
let archived = try SDKRespirationArchive.read(url: URL(fileURLWithPath: CommandLine.arguments[4]),
    deviceAddress: CommandLine.arguments[5], day: CommandLine.arguments[6])
let expected = oxygen.compactMap(HealthSampleMapping.respiration).filter { $0.time >= start && $0.time < end }
let actual = archived.map { RespirationSample(time: $0.time, breathsPerMinute: $0.rate) }
    .filter { $0.time >= start && $0.time < end }
guard !expected.isEmpty, actual == expected else {
    print("FAIL: archive \(actual.count) and oxygen \(expected.count) respiratory minutes differ")
    exit(1)
}
print("PASS: all \(actual.count) respiratory timestamps and values match via actual Swift mappings")
''')
    subprocess.run(['swiftc', str(root / 'NextBody/Services/Band/HealthSampleMapping.swift'), str(root / 'NextBody/Services/Storage/SDKRespirationArchive.swift'), str(path / 'main.swift'), '-o', str(path / 'test')], check=True)
    raise SystemExit(subprocess.run([str(path / 'test'), str(path), args.start, args.end, args.database, address, args.day]).returncode)
