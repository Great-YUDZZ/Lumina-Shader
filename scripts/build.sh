#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
PACK_DIR="$ROOT_DIR/lumina_shader"

HORIZON_SHADER_BIN="${HORIZON_SHADER_BIN:-}"
if [[ -z "$HORIZON_SHADER_BIN" ]]; then
    if command -v horizon-shader >/dev/null 2>&1; then
        HORIZON_SHADER_BIN="$(command -v horizon-shader)"
    elif [[ -x "$HOME/.local/share/horizon-launcher/native/target/fast/horizon-shader" ]]; then
        HORIZON_SHADER_BIN="$HOME/.local/share/horizon-launcher/native/target/fast/horizon-shader"
    else
        echo "Error: horizon-shader binary not found. Please install horizon-shader or set HORIZON_SHADER_BIN." >&2
        exit 1
    fi
fi

"$SCRIPT_DIR/check.sh"
rm -f "$ROOT_DIR"/lumina_shader-*.hshader
"$HORIZON_SHADER_BIN" pack "$PACK_DIR"

HSHADER_FILE="$(ls -1 "$ROOT_DIR"/lumina_shader-*.hshader | head -n 1)"
INSTANCE_SHADERPACKS="${INSTANCE_SHADERPACKS:-$HOME/.local/share/horizon/instances/idk/shaderpacks}"
if [[ -d "$INSTANCE_SHADERPACKS" ]]; then
    rm -f "$INSTANCE_SHADERPACKS"/lumina_shader-*.hshader
    cp -f "$HSHADER_FILE" "$INSTANCE_SHADERPACKS/"
    echo "Copied to instance shaderpacks: $INSTANCE_SHADERPACKS/$(basename "$HSHADER_FILE")"
fi
echo "Package ready: $HSHADER_FILE"
