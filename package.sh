#!/usr/bin/env bash
# Assemble the two things that are released: the zip for installing by hand and the Workshop
# mod folder.  Both hold the same script and art; only the folder they sit in differs.
#
# Usage: ./package.sh <mod version>      e.g. ./package.sh 1.1
set -euo pipefail

version=${1:?usage: package.sh <mod version>}
here=$(cd "$(dirname "$0")" && pwd)
data="scripts/internal/improved-chairs"

# The Lua template must be the one made from the PNG, and the controls the ones in art/.
python3 "$here/art/make_template.py" --check
lua "$here/test/run_tests.lua"
cmp "$here/art/controls.png" "$here/$data/chair_controls.png"

files=(improved-chairs.lua internal/improved-chairs/template.lua internal/improved-chairs/chair_controls.png)

stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
mkdir -p "$here/dist" "$stage/dfhack-config/scripts/internal/improved-chairs"
for f in "${files[@]}"; do cp "$here/scripts/$f" "$stage/dfhack-config/scripts/$f"; done
cp "$here/LICENSE" "$stage/dfhack-config/scripts/internal/improved-chairs/LICENSE.txt"
out="$here/dist/improved-chairs-$version.zip"
rm -f "$out"
(cd "$stage" && zip -qr "$out" dfhack-config)
echo "wrote $out"
unzip -l "$out"

mod="$here/dist/workshop/new_and_improved_chairs"
rm -rf "$here/dist/workshop"
mkdir -p "$mod/scripts_modinstalled/internal/improved-chairs"
cp "$here/steam/info.txt" "$here/steam/preview.png" "$mod/"
cp "$here/LICENSE" "$mod/LICENSE.txt"
for f in "${files[@]}"; do cp "$here/scripts/$f" "$mod/scripts_modinstalled/$f"; done
echo "wrote $mod"
(cd "$mod" && find . -type f | sort)
