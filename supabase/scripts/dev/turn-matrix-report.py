#!/usr/bin/env python3
"""Summarize a turn-matrix run: per-case outcome, tool coverage, chart coverage, failures.

usage: turn-matrix-report.py <matrix.json> <results.json>
"""
import json, sys
from collections import OrderedDict

matrix = {c["id"]: c for c in json.load(open(sys.argv[1]))}
rows = json.load(open(sys.argv[2]))

READ = ["day.get", "data.read", "data.catalog", "metric.compare", "profile.get",
        "device.capabilities", "meals.openSlots", "meals.search", "image.inspect", "meal.estimate"]
PHONE = ["device.find", "device.sync", "device.alarm.set", "device.alarm.delete", "sport.start",
         "sport.stop", "meal.log", "balance_check.start", "body_scan.start", "app.open"]
CHARTS = ["battery", "metric", "text", "line", "band", "bars", "days", "sparks", "ring", "gauge",
          "split", "cells", "hypnogram", "zones", "wave", "table", "workout", "events", "heat",
          "o2night", "food", "meal", "fuel", "balance", "recomp", "delta", "dual", "plan"]

called, rendered, failures = {}, {}, []
by_surface = OrderedDict()
for r in rows:
    for t in r.get("tools") or []:
        called.setdefault(t, []).append(r["id"])
        if t.startswith("screen.render."):
            rendered.setdefault(t.split(".")[-1], []).append(r["id"])
        if t == "plan.render":
            rendered.setdefault("plan", []).append(r["id"])
    hard = [e for e in (r.get("errors") or []) if not e.startswith("E_SCHEMA:UNTRACEABLE") or True]
    if hard or r.get("asr_error") or not r.get("frame"):
        failures.append(r)
    by_surface.setdefault(r.get("surface", "?"), []).append(r)

print("=" * 100)
print("PER CASE")
print("=" * 100)
for surface, group in by_surface.items():
    print(f"\n--- {surface} ({len(group)}) ---")
    for r in group:
        case = matrix.get(r["id"], {})
        want = case.get("want")
        hit = "  " if not want else ("ok" if want in (r.get("tools") or []) else "!!")
        line = f"{hit} {r['id']:<18} {str(r.get('seconds','?')):>5}s hops={r.get('hops',0)} frame={r.get('frame')}"
        print(line)
        if r.get("transcript"): print(f"     语音转写: {r['transcript']}")
        if want: print(f"     期望 {want} → {'命中' if hit=='ok' else '未命中'}")
        print(f"     工具: {', '.join(r.get('tools') or []) or '（无）'}")
        if r.get("requests"):
            for q in r["requests"]:
                print(f"     手机工具: {q['name']} confirm={q['confirm']} args={json.dumps(q['args'], ensure_ascii=False)}")
        if r.get("title") or r.get("sentence"):
            print(f"     上屏: {r.get('title')} | {r.get('sentence')}")
        if r.get("tasks"): print(f"     任务: {' / '.join(r['tasks'])}")
        if r.get("sub"): print(f"     正文: {r['sub'][:220]}")
        if r.get("errors"): print(f"     错误: {r['errors']}")

print("\n" + "=" * 100)
print("TOOL COVERAGE")
print("=" * 100)
for name, group in (("读工具", READ), ("手机工具", PHONE), ("输出", ["plan.render"])):
    print(f"\n{name}")
    for t in group:
        ids = called.get(t, [])
        print(f"  {'✓' if ids else '✗'} {t:<22} {len(ids):>2}×  {', '.join(sorted(set(ids))[:4])}")

print("\n图表类型（screen.render.<type> 实际渲染过的）")
for t in CHARTS:
    ids = rendered.get(t, [])
    print(f"  {'✓' if ids else '✗'} {t:<12} {len(ids):>2}×  {', '.join(sorted(set(ids))[:3])}")

tools_hit = sum(1 for t in READ + PHONE if called.get(t))
charts_hit = sum(1 for t in CHARTS if rendered.get(t))
print("\n" + "=" * 100)
print(f"合计 {len(rows)} 轮；读+手机工具 {tools_hit}/{len(READ)+len(PHONE)}；图表 {charts_hit}/{len(CHARTS)}")
bad = [r for r in rows if r.get("errors") or r.get("asr_error") or not r.get("frame")]
print(f"有错误或没出帧的用例 {len(bad)}：")
for r in bad:
    print(f"  {r['id']:<18} frame={r.get('frame')} errors={r.get('errors')} asr={r.get('asr_error')}")
