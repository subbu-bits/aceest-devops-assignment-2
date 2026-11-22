#!/usr/bin/env bash
# Save the SonarQube results as a report file for the submission.
#
#   scripts/sonar_report.sh SONAR_TOKEN [SONAR_URL]
#
# Writes reports/sonar-report.md (quality gate, metrics, open issues).
set -euo pipefail

TOKEN=${1:?Usage: $0 SONAR_TOKEN [SONAR_URL]}
SONAR=${2:-http://localhost:9000}
KEY=aceest-fitness
cd "$(dirname "$0")/.."
mkdir -p reports

get() { curl -fsS -u "$TOKEN:" "$SONAR/api/$1"; }

get "qualitygates/project_status?projectKey=$KEY" > /tmp/sonar_gate.json
get "measures/component?component=$KEY&metricKeys=bugs,vulnerabilities,code_smells,coverage,duplicated_lines_density,ncloc,security_hotspots,reliability_rating,security_rating,sqale_rating" > /tmp/sonar_measures.json
get "issues/search?componentKeys=$KEY&resolved=false&ps=100" > /tmp/sonar_issues.json

python3 - "$SONAR" "$KEY" <<'PY' > reports/sonar-report.md
import json, sys, datetime
sonar, key = sys.argv[1], sys.argv[2]
gate = json.load(open("/tmp/sonar_gate.json"))["projectStatus"]
measures = json.load(open("/tmp/sonar_measures.json"))["component"]["measures"]
issues = json.load(open("/tmp/sonar_issues.json"))["issues"]
print(f"# SonarQube report - {key}\n")
print(f"Generated {datetime.datetime.now():%Y-%m-%d %H:%M} from {sonar}/dashboard?id={key}\n")
print(f"**Quality gate: {gate['status']}**\n")
print("| Metric | Value |\n|---|---|")
for m in sorted(measures, key=lambda m: m["metric"]):
    print(f"| {m['metric']} | {m.get('value', '-')} |")
print(f"\n## Open issues ({len(issues)})\n")
if not issues:
    print("None.")
for i in issues:
    where = i["component"].split(":", 1)[-1]
    print(f"- [{i['severity']}] {i['type']} - {where}:{i.get('line', '-')} - {i['message']}")
PY
echo "Wrote reports/sonar-report.md"
cat reports/sonar-report.md
