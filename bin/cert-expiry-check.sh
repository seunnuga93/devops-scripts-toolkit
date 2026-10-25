#!/usr/bin/env bash
# Warn when TLS certificates are close to expiry.
#
#   cert-expiry-check.sh [-d days] host[:port] ...
#   cert-expiry-check.sh [-d days] -f cert.pem ...
#
# Exit code: 0 all fine, 1 at least one cert expires within <days>, 2 usage/connection error.
set -euo pipefail

DAYS=30
MODE=host

usage() {
  sed -n '2,7p' "$0" | sed 's/^# \{0,1\}//'
  exit 2
}

while getopts ":d:fh" opt; do
  case "$opt" in
    d) DAYS="$OPTARG" ;;
    f) MODE="file" ;;
    h | *) usage ;;
  esac
done
shift $((OPTIND - 1))
[[ $# -gt 0 ]] || usage
[[ "$DAYS" =~ ^[0-9]+$ ]] || { echo "error: -d must be a whole number of days" >&2; exit 2; }

fetch_cert() {
  local target=$1 host port
  if [[ "$MODE" == file ]]; then
    cat "$target"
    return
  fi
  host=${target%%:*}
  port=${target##*:}
  [[ "$host" == "$port" ]] && port=443
  openssl s_client -connect "$host:$port" -servername "$host" </dev/null 2>/dev/null \
    | openssl x509
}

status=0
for target in "$@"; do
  if ! pem=$(fetch_cert "$target") || [[ -z "$pem" ]]; then
    printf '%-40s ERROR could not read certificate\n' "$target"
    status=2
    continue
  fi
  not_after=$(openssl x509 -noout -enddate <<<"$pem" | cut -d= -f2)
  # -checkend avoids GNU/BSD `date` differences: it just answers "valid N seconds from now?"
  if openssl x509 -noout -checkend $((DAYS * 86400)) <<<"$pem" >/dev/null; then
    printf '%-40s OK      expires %s\n' "$target" "$not_after"
  else
    printf '%-40s EXPIRING within %s days (%s)\n' "$target" "$DAYS" "$not_after"
    [[ $status -eq 0 ]] && status=1
  fi
done
exit "$status"
