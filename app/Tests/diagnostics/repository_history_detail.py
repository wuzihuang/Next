"""Replay actual history-summary loading with already-cached sleep and temperature.

Reuse the existing credential-free Repository compile harness. Exit 1 demonstrates
that a summary refresh erased detailed observations; no production state is changed.
"""
from pathlib import Path
import sys

base = Path(__file__).with_name("repository_history_data.py")
source = base.read_text()
source = source.replace('if mode == "offline-cached" {\n var cached',
                        'if mode == "modern" {\n var cached')
source = source.replace(
    'cached.bodyBattery = 72; cached.balance = -350; store.history = [cached]',
    'cached.bodyBattery = 1; cached.balance = -1; cached.bbWake = 88; '
    'cached.sleep = SleepSummary(totalMinutes: 410, deepMinutes: 100, lightMinutes: 310, wakeCount: 1); '
    'cached.vitalsCurve = [VitalSample(ts: Date(), hr: 65, stress: nil, temp: 33.6)]; store.history = [cached]')
source = source.replace(
    'let checks = [("historical battery and fuel summary", rejected ? !restored : restored)]',
    'let checks = [("SDK sleep survives history summary reload", store.history.first?.sleep?.totalMinutes == 410), '
    '("SDK temperature survives history summary reload", store.history.first?.vitalsCurve.first?.temp == 33.6), ("new computed summary wins", store.history.first?.bodyBattery == 72 && store.history.first?.balance == -350 && store.history.first?.bbWake == nil)]')
sys.argv = [str(base), "modern"]
exec(compile(source, str(base), "exec"), {"__file__": str(base), "__name__": "__main__"})
