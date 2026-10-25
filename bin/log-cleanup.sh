#!/usr/bin/env bash
# Compress old logs and delete very old ones.
#
#   log-cleanup.sh [-c compress_after_days] [-r delete_after_days] [-n] directory
#
#   -n  dry run: print what would happen without changing anything
set -euo pipefail

COMPRESS_DAYS=7
DELETE_DAYS=30
DRY_RUN=false

while getopts ":c:r:nh" opt; do
  case "$opt" in
    c) COMPRESS_DAYS="$OPTARG" ;;
    r) DELETE_DAYS="$OPTARG" ;;
    n) DRY_RUN=true ;;
    h | *) sed -n '2,7p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
  esac
done
shift $((OPTIND - 1))
DIR="${1:-}"
[[ -d "$DIR" ]] || { echo "error: '$DIR' is not a directory" >&2; exit 2; }
if (( DELETE_DAYS <= COMPRESS_DAYS )); then
  echo "error: delete age (-r) must be greater than compress age (-c)" >&2
  exit 2
fi

run() {
  if $DRY_RUN; then echo "[dry-run] $*"; else "$@"; fi
}

deleted=0
while IFS= read -r -d '' f; do
  run rm -f -- "$f"
  deleted=$((deleted + 1))
done < <(find "$DIR" -type f \( -name '*.log' -o -name '*.log.gz' \) -mtime +"$DELETE_DAYS" -print0)

compressed=0
while IFS= read -r -d '' f; do
  run gzip -- "$f"
  compressed=$((compressed + 1))
done < <(find "$DIR" -type f -name '*.log' -mtime +"$COMPRESS_DAYS" -print0)

echo "deleted=$deleted compressed=$compressed dry_run=$DRY_RUN"
