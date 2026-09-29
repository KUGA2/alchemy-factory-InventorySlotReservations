#!/usr/bin/env bash
# Capture one frame from a headless Gamescope PipeWire node.
set -euo pipefail
if (( $# < 1 || $# > 2 )); then
    echo "Usage: $0 OUTPUT.png [GAMESCOPE_PIPEWIRE_NODE_ID]" >&2
    exit 2
fi
output=$1
[[ $output == *.png ]] || { echo "Output must end in .png" >&2; exit 2; }
for command in gst-launch-1.0 pw-dump python3; do
    command -v "$command" >/dev/null || { echo "$command is required" >&2; exit 1; }
done
if (( $# == 2 )); then
    [[ $2 =~ ^[0-9]+$ ]] || { echo "Node ID must be numeric" >&2; exit 2; }
    node=$2
else
    node=$(pw-dump | python3 -c '
import json, sys
nodes = [str(obj["id"]) for obj in json.load(sys.stdin)
         if obj.get("type") == "PipeWire:Interface:Node"
         and obj.get("info", {}).get("props", {}).get("node.name") == "gamescope"]
if len(nodes) != 1:
    sys.exit(f"Expected one gamescope PipeWire node, found {len(nodes)}; inspect pw-dump or pass a node ID")
print(nodes[0])')
fi
gst-launch-1.0 -q pipewiresrc path="$node" num-buffers=1 keepalive-time=1000 \
    '!' videoconvert '!' pngenc '!' filesink location="$output"
test -s "$output" || { echo "No screenshot produced: $output" >&2; exit 1; }
echo "Saved $output (PipeWire node $node)"
