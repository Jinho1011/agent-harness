#!/usr/bin/env bash
set -Eeuo pipefail

BACKUP=${1:?usage: restore.sh BACKUP_DIRECTORY}
TARGETS="$BACKUP/targets.tsv"
[[ -f "$TARGETS" && -d "$BACKUP/files" ]] || { echo "invalid backup: $BACKUP" >&2; exit 1; }

# Validate the entire plan before removing any installed target.
while IFS=$'\t' read -r state rel; do
  [[ -n "$rel" && "$rel" != /* && "$rel" != *'..'* ]] || { echo "unsafe backup target: $rel" >&2; exit 1; }
  case "$state" in
    present) [[ -e "$BACKUP/files/$rel" || -L "$BACKUP/files/$rel" ]] || { echo "missing backup: $rel" >&2; exit 1; } ;;
    absent) ;;
    *) echo "invalid target state: $state" >&2; exit 1 ;;
  esac
done <"$TARGETS"

while IFS=$'\t' read -r state rel; do
  [[ -n "$rel" && "$rel" != /* && "$rel" != *'..'* ]] || { echo "unsafe backup target: $rel" >&2; exit 1; }
  target="$HOME/$rel"
  rm -rf -- "$target"
  if [[ "$state" == present ]]; then
    mkdir -p "$(dirname "$target")"
    cp -a "$BACKUP/files/$rel" "$target"
  elif [[ "$state" != absent ]]; then
    echo "invalid target state: $state" >&2
    exit 1
  fi
done <"$TARGETS"

echo "Restored managed targets from $BACKUP"
