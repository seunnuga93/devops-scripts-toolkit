#!/usr/bin/env bash
# Archive a directory and upload it to Azure Blob Storage, pruning old backups.
#
#   backup-to-azure-blob.sh -a storage_account -c container [-k keep_days] directory
#
# Auth uses your `az login` session or a managed identity (--auth-mode login), not account keys.
set -euo pipefail

KEEP_DAYS=14
ACCOUNT=""
CONTAINER=""

while getopts ":a:c:k:h" opt; do
  case "$opt" in
    a) ACCOUNT="$OPTARG" ;;
    c) CONTAINER="$OPTARG" ;;
    k) KEEP_DAYS="$OPTARG" ;;
    h | *) sed -n '2,6p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
  esac
done
shift $((OPTIND - 1))
SRC="${1:-}"
[[ -n "$ACCOUNT" && -n "$CONTAINER" && -d "$SRC" ]] || { echo "error: need -a, -c and an existing directory" >&2; exit 2; }
command -v az >/dev/null || { echo "error: Azure CLI (az) not found" >&2; exit 2; }

stamp=$(date -u +%Y%m%dT%H%M%SZ)
name="$(basename "$SRC")-${stamp}.tar.gz"
archive=$(mktemp -d)/"$name"
trap 'rm -rf "$(dirname "$archive")"' EXIT

tar -czf "$archive" -C "$(dirname "$SRC")" "$(basename "$SRC")"
echo "created $name ($(du -h "$archive" | cut -f1))"

az storage blob upload --auth-mode login --account-name "$ACCOUNT" --container-name "$CONTAINER" \
  --name "$name" --file "$archive" --only-show-errors --output none
echo "uploaded to $ACCOUNT/$CONTAINER/$name"

# Prune by the timestamp in the blob name so it works without extra metadata.
cutoff=$(date -u -d "-${KEEP_DAYS} days" +%Y%m%d 2>/dev/null || date -u -v-"${KEEP_DAYS}"d +%Y%m%d)
prefix="$(basename "$SRC")-"
az storage blob list --auth-mode login --account-name "$ACCOUNT" --container-name "$CONTAINER" \
  --prefix "$prefix" --query '[].name' --output tsv |
  while read -r blob; do
    blob_date=${blob#"$prefix"}
    blob_date=${blob_date:0:8}
    if [[ "$blob_date" < "$cutoff" ]]; then
      az storage blob delete --auth-mode login --account-name "$ACCOUNT" --container-name "$CONTAINER" \
        --name "$blob" --only-show-errors
      echo "pruned $blob"
    fi
  done
