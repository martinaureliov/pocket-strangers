#!/usr/bin/env bash
# Compare the Godot version this project is pinned to with the latest upstream releases.
# Pinned version source of truth: GODOT_VERSION in .github/workflows/ci.yml
# Usage: tools/check_versions.sh
set -euo pipefail
cd "$(dirname "$0")/.."

pinned=$(sed -n 's/^ *GODOT_VERSION: *\([0-9.]*\).*/\1/p' .github/workflows/ci.yml | head -1)

tags() { git ls-remote --tags "$1" 2>/dev/null | sed 's#.*refs/tags/##; s#\^{}##' | sort -uV; }

latest_stable=$(tags https://github.com/godotengine/godot.git | grep -E '^[0-9]+\.[0-9]+(\.[0-9]+)?-stable$' | tail -1 | sed 's/-stable$//')
# Order pre-releases dev < beta < rc (plain sort -V would put "dev" after "beta").
latest_preview=$(tags https://github.com/godotengine/godot-builds.git | grep -E -- '-(dev|beta|rc)[0-9]+$' \
  | sed 's/-dev/-1dev/; s/-beta/-2beta/; s/-rc/-3rc/' | sort -V | tail -1 | sed 's/-[123]/-/')

echo "Godot pinned:          ${pinned:-unknown}"
echo "Godot latest stable:   ${latest_stable:-unknown (network?)}"
echo "Godot latest preview:  ${latest_preview:-unknown}"

if [[ -n "$latest_stable" && -n "$pinned" && "$latest_stable" != "$pinned" ]]; then
  newest=$(printf '%s\n%s\n' "$pinned" "$latest_stable" | sort -V | tail -1)
  [[ "$newest" == "$latest_stable" ]] && echo "UPDATE AVAILABLE: Godot $latest_stable (project is on $pinned)"
fi
