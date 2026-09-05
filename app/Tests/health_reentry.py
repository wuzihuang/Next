"""Run the actual Swift Profile startup code with isolated, persistent defaults.

The app has no host unit-test target. Extract only the Foundation model declarations;
no copied implementation and no HealthKit permission emulation is needed for reentry.
"""
from pathlib import Path
import subprocess
import tempfile

APP = Path(__file__).resolve().parents[1]


def declaration(path, marker):
    source = path.read_text()
    start = source.index(marker)
    opening = source.index('{', start)
    depth = 1
    end = opening + 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[start:end]


source = 'import Foundation\n'
source += declaration(APP / 'NextBody/Models/Metrics.swift', 'enum Goal:') + '\n'
source += declaration(APP / 'NextBody/Services/DataStore.swift', 'struct Profile:') + '\n'
sheet = declaration(APP / 'NextBody/Features/Profile/ProfileSheets.swift', 'struct AppleHealthSheet:')
action = sheet[sheet.index('Task {') + len('Task {'):]
# The Task is the final action in this sheet; extract its balanced body.
depth, end = 1, 0
while depth:
    depth += (action[end] == '{') - (action[end] == '}')
    end += 1
source += '''
struct TestBaseline { let isEmpty: Bool }
struct HealthService {
    static let shared = HealthService()
    func requestRead() async {}
    func readBaseline() async -> TestBaseline { TestBaseline(isEmpty: true) }
}
final class TestData { var profile = Profile.blank }
func recheck(_ data: TestData) async {
''' + action[:end - 1] + '\n}\n'
source += r'''
let suite = CommandLine.arguments[1]
let defaults = UserDefaults(suiteName: suite)!
// Redirect this isolated executable's standard defaults to the test suite only.
UserDefaults.standard.addSuite(named: suite)
let mode = CommandLine.arguments[2]
if mode == "write" {
    defaults.set(true, forKey: "nb.health.asked")
    defaults.set(Date(timeIntervalSince1970: 1700000000), forKey: "nb.health.lastRead")
    defaults.synchronize()
} else if mode == "emptyRecheck" {
    let data = TestData()
    data.profile.appleHealthLinked = true
    await recheck(data)
    guard data.profile.appleHealthLinked else {
        print("FAIL: empty re-check cleared completed sync"); exit(1)
    }
    print("PASS: empty re-check preserves completed sync")
} else if mode == "cache" {
    var cached = Profile.blank
    cached.appleHealthLinked = false
    let decoded = try JSONDecoder().decode(Profile.self, from: JSONEncoder().encode(cached))
    guard decoded.restoringHealthSync().appleHealthLinked else {
        print("FAIL: old cached profile lost persisted sync"); exit(1)
    }
    print("PASS: old cached profile restores sync")
} else if mode == "sameProcess" {
    _ = Profile.blank
    defaults.set(Date(timeIntervalSince1970: 1700000000), forKey: "nb.health.lastRead")
    guard Profile.blank.appleHealthLinked else {
        print("FAIL: blank profile remained frozen before sync"); exit(1)
    }
    defaults.removeObject(forKey: "nb.health.lastRead")
    print("PASS: profile reset restores current sync receipt")
} else if mode == "askedOnly" {
    defaults.set(true, forKey: "nb.health.asked")
    defaults.synchronize()
    guard !Profile.blank.appleHealthLinked else {
        print("FAIL: permission prompt alone is not a successful sync"); exit(1)
    }
} else {
    let expected = mode == "synced"
    guard Profile.blank.appleHealthLinked == expected else {
        print("FAIL: reopening after successful sync shows NOT CONNECTED"); exit(1)
    }
    print("PASS: \(mode)")
}
'''

with tempfile.TemporaryDirectory(prefix='nextbody-health-test-') as directory:
    root = Path(directory)
    swift = root / 'main.swift'
    binary = root / 'health-reentry'
    swift.write_text(source)
    subprocess.run(['swiftc', str(swift), '-o', str(binary)], check=True)
    suite = 'test.nextbody.health.' + root.name
    try:
        for mode in ['fresh', 'askedOnly', 'emptyRecheck', 'sameProcess', 'write', 'synced', 'synced', 'cache']:
            subprocess.run([str(binary), suite, mode], check=True)
    finally:
        subprocess.run(['defaults', 'delete', suite], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
