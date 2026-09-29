#!/usr/bin/env bash
# Mute only the game's current PipeWire stream; do not touch the default sink.
set -euo pipefail
command -v wpctl >/dev/null || { echo "wpctl is required" >&2; exit 1; }

if (( $# > 1 )); then
    echo "Usage: $0 [STREAM_ID]" >&2
    exit 2
fi
if (( $# == 1 )); then
    [[ $1 =~ ^[0-9]+$ ]] || { echo "STREAM_ID must be numeric" >&2; exit 2; }
    stream=$1
else
    mapfile -t matches < <(wpctl status | awk '
        /Streams:/ { streams=1; next }
        streams && /AlchemyFactory/ {
            id=$1; gsub(/[^0-9]/, "", id);
            if (id != "") print id
        }')
    if (( ${#matches[@]} != 1 )); then
        echo "Expected exactly one AlchemyFactory stream; found ${#matches[@]}. Inspect wpctl status or pass an ID." >&2
        exit 1
    fi
    stream=${matches[0]}
fi
wpctl set-mute "$stream" 1
echo "Muted AlchemyFactory stream $stream: $(wpctl get-volume "$stream")"
