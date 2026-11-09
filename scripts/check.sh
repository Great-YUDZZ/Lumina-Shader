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
    fi
fi

if [[ -z "$HORIZON_SHADER_BIN" || ! -x "$HORIZON_SHADER_BIN" ]]; then
    HORIZON_STAGE="${HORIZON_STAGE:-$HOME/.local/share/horizon-launcher/native/stage}"
    if [[ -d "$HORIZON_STAGE" ]]; then
        echo "Building horizon-shader CLI from local Horizon stage..."
        env -u CARGO_ENCODED_RUSTDOCFLAGS -u CARGO_ENCODED_RUSTFLAGS -u CARGO_INCREMENTAL \
            -u RUSTC_WORKSPACE_WRAPPER -u RUSTC_WRAPPER -u RUSTDOCFLAGS -u RUSTFLAGS -u RUSTUP_TOOLCHAIN \
            CARGO_HOME="$HOME/.local/share/horizon-launcher/cargo" \
            CARGO_TARGET_DIR="$HOME/.local/share/horizon-launcher/native/target" \
            PATH="$HOME/.local/share/horizon-launcher/rust/1.99.1-x86_64-unknown-linux-gnu/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin" \
            RUSTC="$HOME/.local/share/horizon-launcher/rust/1.99.1-x86_64-unknown-linux-gnu/bin/rustc" \
            "$HOME/.local/share/horizon-launcher/rust/1.99.1-x86_64-unknown-linux-gnu/bin/cargo" \
            build --manifest-path "$HORIZON_STAGE/Cargo.toml" --locked --offline --profile fast \
            -p horizon-shader-api --bin horizon-shader
        HORIZON_SHADER_BIN="$HOME/.local/share/horizon-launcher/native/target/fast/horizon-shader"
    else
        echo "Error: horizon-shader binary not found. Please install horizon-shader." >&2
        exit 1
    fi
fi

"$HORIZON_SHADER_BIN" check "$PACK_DIR"
