#!/usr/bin/env bash
# Launch only a prepared isolated game and Proton prefix. Does not copy or edit saves.
set -euo pipefail

if (( $# != 2 )); then
    echo "Usage: $0 ISOLATED_GAME_ROOT ISOLATED_COMPATDATA_3669570" >&2
    exit 2
fi
game_root=$(realpath "$1")
compatdata=$(realpath "$2")
exe="$game_root/AlchemyFactory.exe"
mods="$game_root/AlchemyFactory/Binaries/Win64/ue4ss/Mods"
steam_root=${STEAM_ROOT:-$HOME/.local/share/Steam}
proton=${PROTON:-$HOME/.steam/steam/steamapps/common/Proton - Experimental/proton}
real_game="$steam_root/steamapps/common/Alchemy Factory"
real_compatdata="$steam_root/steamapps/compatdata/3669570"

if [[ -d "$real_game" && "$game_root" == "$(realpath "$real_game")" ]] ||
   [[ -d "$real_compatdata" && "$compatdata" == "$(realpath "$real_compatdata")" ]]; then
    echo "Refusing to test against the real Steam game or Proton prefix" >&2
    exit 1
fi

for path in "$exe" "$compatdata/pfx" "$mods/InventorySlotReservations/Scripts/main.lua" "$mods/mods.txt" "$proton"; do
    if [[ ! -e "$path" ]]; then
        echo "Missing isolated test prerequisite: $path" >&2
        exit 1
    fi
done
if [[ ! -d "$steam_root" ]]; then
    echo "Steam root not found: $steam_root (set STEAM_ROOT)" >&2
    exit 1
fi
if ! grep -Eq '^InventorySlotReservations[[:space:]]*:[[:space:]]*1([[:space:]]*)$' "$mods/mods.txt"; then
    echo "Enable InventorySlotReservations : 1 in isolated mods.txt first" >&2
    exit 1
fi
command -v gamescope >/dev/null || { echo "gamescope is required" >&2; exit 1; }

cd "$game_root"
export STEAM_COMPAT_DATA_PATH="$compatdata"
export STEAM_COMPAT_CLIENT_INSTALL_PATH="$steam_root"
export STEAM_COMPAT_INSTALL_PATH="$game_root"
export SteamAppId=3669570 SteamGameId=3669570
exec gamescope --backend headless -W 1600 -H 900 -w 1600 -h 900 -- "$proton" run "$exe"
