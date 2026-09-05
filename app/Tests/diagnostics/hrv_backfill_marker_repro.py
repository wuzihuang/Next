"""Compile the production backfill marker and guard against an existing v8 receipt."""
from pathlib import Path
import re
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
source = (root / 'NextBody/Services/Band/OriginDataSync.swift').read_text()
expression = re.search(r'let key = ("nb\.band\.backfilled\.[^\n]+)', source).group(1)
guard_expression = re.search(r'guard force \|\| (!UserDefaults.standard.bool\(forKey: key\)) else', source).group(1)
with tempfile.TemporaryDirectory() as directory:
    path = Path(directory)
    main = '''import Foundation
enum Replay {
 static func dayString(_ date: Date) -> String { "2026-09-05" }
 static func shouldBackfill(defaults: UserDefaults) -> Bool {
  let userId = "test-account", bound = "test-band"
  let key = ''' + expression + '''
  return ''' + guard_expression.replace('UserDefaults.standard', 'defaults') + '''
 }
}
let suite = "next-hrv-backfill-test-" + UUID().uuidString
let defaults = UserDefaults(suiteName: suite)!
defers: do {
 defer { defaults.removePersistentDomain(forName: suite) }
 defaults.set(true, forKey: "nb.band.backfilled.v8.test-account.test-band.2026-09-05")
 precondition(Replay.shouldBackfill(defaults: defaults), "existing v8 receipt must not skip exact-minute HRV backfill")
 print("PASS: existing v8 receipt triggers exact-minute HRV history repair")
}
'''
    (path / 'main.swift').write_text(main)
    subprocess.run(['swiftc', str(path / 'main.swift'), '-o', str(path / 'test')], check=True)
    raise SystemExit(subprocess.run([str(path / 'test')]).returncode)
