#!/usr/bin/env python3
"""Tiny offline prompt/tool eval harness skeleton.
Fill eval_cases.json with synthetic cases. Do not put private user data here.
"""
from __future__ import annotations
import json, pathlib, sys
path = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "eval_cases.json")
if not path.exists():
    print("No eval_cases.json found. Create synthetic cases before release.")
    sys.exit(0)
for case in json.loads(path.read_text()):
    required = {"name", "input", "expected"}
    missing = required - set(case)
    if missing:
        print(f"FAIL {case.get('name','<unnamed>')}: missing {sorted(missing)}")
        sys.exit(1)
    print(f"CASE {case['name']}: ready for model/tool evaluation")
