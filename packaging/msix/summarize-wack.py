"""Report WACK results without confusing process exit zero with certification."""
import argparse
import json
from pathlib import Path
import xml.etree.ElementTree as ET

parser = argparse.ArgumentParser()
parser.add_argument("report", type=Path)
parser.add_argument("--require-pass", action="store_true")
args = parser.parse_args()
report = ET.parse(args.report).getroot()
tests = [{"name": t.get("NAME"), "optional": t.get("OPTIONAL") == "TRUE",
          "result": t.findtext("RESULT"),
          "messages": [m.get("TEXT") for m in t.findall("./MESSAGES/MESSAGE")]}
         for t in report.iter("TEST")]
required = [t for t in tests if not t["optional"]]
passed = bool(required) and all(t["result"] == "PASS" for t in required)
summary = {"overall": report.get("OVERALL_RESULT"), "kit": report.get("VERSION"),
           "os": report.get("OSVERSION"), "requiredPassed": passed,
           "tests": tests}
args.report.with_suffix(".summary.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
print(f"Overall: {summary['overall']}; required tests all PASS: {passed}")
for test in tests:
    print(f"{'optional' if test['optional'] else 'required'}: {test['name']}: {test['result']}")
if args.require_pass and not passed:
    raise SystemExit(1)
