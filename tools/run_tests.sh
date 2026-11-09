#!/usr/bin/env bash
# Ejecuta la suite GUT en modo headless.
# Uso:  GODOT=/ruta/a/godot tools/run_tests.sh [carpeta res://tests/...]
# Ejemplo: tools/run_tests.sh res://tests/unit/
set -euo pipefail

GODOT="${GODOT:-godot}"
DIR="${1:-res://tests/}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

cd "$ROOT/game"
mkdir -p tests/results
"$GODOT" --headless --import >/dev/null 2>&1 || true
"$GODOT" --headless -s res://addons/gut/gut_cmdln.gd \
	-gdir="$DIR" -ginclude_subdirs -gexit
