#!/usr/bin/env bash
# Report filesystems above a usage threshold, optionally posting to a Slack webhook.
#
#   disk-usage-alert.sh [-t percent] [-w slack_webhook_url]
#
# Exit code: 0 all below threshold, 1 one or more above it.
set -euo pipefail

THRESHOLD=85
WEBHOOK="${SLACK_WEBHOOK_URL:-}"

while getopts ":t:w:h" opt; do
  case "$opt" in
    t) THRESHOLD="$OPTARG" ;;
    w) WEBHOOK="$OPTARG" ;;
    h | *) sed -n '2,6p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
  esac
done
[[ "$THRESHOLD" =~ ^[0-9]+$ ]] || { echo "error: -t must be a number" >&2; exit 2; }

# df -P gives one line per filesystem on both Linux and macOS.
alerts=$(df -P -x tmpfs -x devtmpfs -x overlay -x squashfs 2>/dev/null || df -P)
alerts=$(awk -v t="$THRESHOLD" 'NR > 1 { use = $5; sub("%", "", use); if (use + 0 >= t) printf "%s %s%% (%s)\n", $6, use, $1 }' <<<"$alerts")

if [[ -z "$alerts" ]]; then
  echo "All filesystems below ${THRESHOLD}%"
  exit 0
fi

message="Disk usage above ${THRESHOLD}% on $(hostname):
${alerts}"
echo "$message"

if [[ -n "$WEBHOOK" ]]; then
  payload=$(printf '%s' "$message" | python3 -c 'import json, sys; print(json.dumps({"text": sys.stdin.read()}))')
  curl -fsS -X POST -H 'Content-Type: application/json' -d "$payload" "$WEBHOOK" >/dev/null
fi
exit 1
