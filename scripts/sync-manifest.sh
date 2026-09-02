#!/usr/bin/env bash
set -Eeuo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
MANIFEST="$ROOT/manifest.json"
SHARED="$ROOT/skills/shared"

command -v jq >/dev/null || { echo "missing dependency: jq" >&2; exit 1; }
command -v sha256sum >/dev/null || command -v shasum >/dev/null || { echo "missing dependency: sha256sum or shasum" >&2; exit 1; }

[[ -d "$SHARED" ]] || { echo "missing vendored skills directory: $SHARED" >&2; exit 1; }

sha256() {
  if command -v sha256sum >/dev/null; then sha256sum "$@"; else shasum -a 256 "$@"; fi
}

tree_sha() {
  local dir=$1
  { cd "$dir" || exit 1; while IFS= read -r file; do printf '%s\n' "$file"; sha256 "$file" | awk '{print $1}'; done < <(find . -type f | LC_ALL=C sort); } | sha256 | awk '{print $1}'
}

VENDORED=()
while IFS= read -r name; do VENDORED+=("$name"); done < <(cd "$SHARED" && find . -mindepth 1 -maxdepth 1 -type d | sed 's|^\./||' | LC_ALL=C sort)
(( ${#VENDORED[@]} > 0 )) || { echo "no vendored skills found in $SHARED" >&2; exit 1; }

pairs=$(mktemp "$ROOT/.sync-manifest.XXXXXX")
trap 'rm -f -- "${pairs:-}"' EXIT
for name in "${VENDORED[@]}"; do
  [[ -f "$SHARED/$name/SKILL.md" ]] || { echo "vendored skill has no SKILL.md: $name" >&2; exit 1; }
  printf '%s\t%s\n' "$name" "$(tree_sha "$SHARED/$name")" >>"$pairs"
done

manifest_tmp=$(mktemp "$MANIFEST.XXXXXX")
jq --rawfile pairs "$pairs" '
  del(.tools, .devtools) | .schemaVersion = 2
  | (.skills | map({key: .name, value: .}) | from_entries) as $old
  | .skills = ($pairs | split("\n") | map(select(length > 0) | split("\t"))
      | map(. as [$name, $sha]
          | (($old[$name] // {name: $name, source: "local"})
             + {name: $name, treeSha256: $sha, installPath: ("~/.agents/skills/" + $name)})))
' "$MANIFEST" >"$manifest_tmp"
mv "$manifest_tmp" "$MANIFEST"

printf 'Synced %d skill(s) into manifest.json\n' "${#VENDORED[@]}"
for name in "${VENDORED[@]}"; do
  source_value=$(jq -r --arg name "$name" '.skills[] | select(.name == $name) | .source' "$MANIFEST")
  if [[ "$source_value" == "local" ]]; then
    printf 'note: %s has no upstream source pinned\n' "$name"
  fi
done
