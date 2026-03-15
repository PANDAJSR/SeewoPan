#!/usr/bin/env bash
set -euo pipefail

SRC_DEFAULT="/Users/hunter/Workspace/seewoCli"
DST_DEFAULT="/Users/hunter/workspace/SeewoPan/cli"

SRC="${1:-$SRC_DEFAULT}"
DST="${2:-$DST_DEFAULT}"

SRC="${SRC%/}/"
DST="${DST%/}/"

if [[ ! -d "$SRC" ]]; then
  echo "Source directory not found: $SRC" >&2
  exit 1
fi

mkdir -p "$DST"

RSYNC_OPTS=(
  -av
  --delete
  --exclude ".git/"
  --exclude "node_modules/"
  --exclude ".DS_Store"
)

rsync "${RSYNC_OPTS[@]}" "$SRC" "$DST"

echo "Mirror sync complete"
echo "  source: $SRC"
echo "  target: $DST"
