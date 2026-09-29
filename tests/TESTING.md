# Testing Inventory Slot Reservations

The tests described here were run on Linux in a **separate copy** of the game binaries and Proton prefix, with the game's audio stream muted. No test save was copied back to the real prefix. The executable tests and helpers are in this directory; the test-only UE4SS F-key diagnostics used during the earlier live run were appended **only to the isolated copy** of `Scripts/main.lua`, not to the shipped mod. Live checks can also be performed manually as described below. This procedure is Linux-specific; Windows users can perform the manual scenarios on a backed-up test save.

## Automated Lua checks (no game required)

From the repository root, with `luajit` installed:

```sh
for test in slot_binding reservation_policy game_integration chestpull chestpull_integration; do
    luajit "InventorySlotReservations/tests/$test.lua" || exit 1
done
for source in InventorySlotReservations/Scripts/*.lua; do
    luajit -b "$source" "/tmp/$(basename "$source").luac" || exit 1
done
python3 -m json.tool InventorySlotReservations/mod.json >/dev/null
```

`chestpull.lua` tests quantities and randomized conservation/isolation; `chestpull_integration.lua` mocks delayed game inventory updates and negative paths. `game_integration.lua` checks filter removal and the marker. These tests **do not replace an in-game test**.

## Prepare an isolated game and save (Linux)

Requirements: Steam installation of Alchemy Factory (AppID `3669570`), a compatible UE4SS setup, Steam Proton, `gamescope`, `wpctl`, `pw-dump`, GStreamer with `pipewiresrc`/`pngenc`, Python 3, and `luajit` for unit tests. `gst-launch-1.0` comes from GStreamer tools. The scripts below **do not** install dependencies, build a prefix, copy saves, inject input, or edit the game.

1. Exit the game. Back up **all** real `SaveGames` and the current UE4SS mod. Use a disposable test save; Steam Cloud might sync saves if you use the real prefix.
2. Copy the game directory and its **entire** Proton `compatdata/3669570` to a separate location. Reflinks (`cp -a --reflink=auto`) may make this faster. Make sure the isolated game's `AlchemyFactory/Content` and `Engine` paths exist; if you symlink those to the original install, do not edit the linked files. Keep the isolated `AlchemyFactory/Binaries/Win64` and prefix independent of the real ones.
3. Copy a selected saved world **from real to isolated**, never back. The default prefix's saves are under `steamapps/compatdata/3669570/pfx/drive_c/users/steamuser/AppData/Local/AlchemyFactory/Saved/SaveGames/`. Preserve the `SANDBOX_…` directory and the other save metadata needed to load it. Confirm the isolated `SaveGame0.sav` timestamp before launching.
4. Install the workspace mod in the isolated `AlchemyFactory/Binaries/Win64/ue4ss/Mods/`, enable `InventorySlotReservations : 1` in the isolated `mods.txt`, and configure the UE4SS proxy/Proton DLL override **in the isolated prefix only**. The tested setup had `dwmapi` set to `native,builtin` and used experimental UE4SS commit `44afb36d`. Check `mod.json` version and that the isolated `Scripts/main.lua` matches the workspace **before** adding any test-only instrumentation.

Useful test-world setup: stand within reach of a **small closed chest**, aim the camera so the E/G prompt is visible, put two stacks of the **same item type** (100 each in the tested `GrowthPotion` example) in that chest, and leave two player slots available for reservations plus a neighboring **unreserved control slot**. Save and exit. Reserve one empty destination beforehand (by reserving an occupied stack and moving it elsewhere) or reserve an occupied stack of the matching type; N cannot create a reservation by hovering a completely unfiltered empty slot. Set up one partial stack (e.g. 50/100) to verify exact filling. Record baseline counts in chest/player and the slot indices. The actual stack limit depends on the item; don't assume all items cap at 100. If the camera doesn't point at the chest on load, adjust it and save again before the run.

### Launch the isolated game

The helper takes the **isolated game root** and **isolated compatdata/3669570 directory**, then runs Proton inside 1600×900 headless Gamescope. It does not redirect logs or detach; launch it in a terminal and keep it running. Set `PROTON` if Steam's Proton installation has a different location.

```sh
export PROTON="$HOME/.steam/steam/steamapps/common/Proton - Experimental/proton"
InventorySlotReservations/tests/scripts/start-isolated-linux.sh \
    "$HOME/.local/share/alchemyfactory-mod/selftest/game" \
    "$HOME/.local/share/alchemyfactory-mod/selftest/compatdata" \
    > "$HOME/isolated-alchemy-game.log" 2>&1
```

The paths above are **examples**, not required locations. Do not launch this script against your real game/prefix. If a first start needs Proton setup, wait for it to finish. After the game appears, confirm UE4SS's `UE4SS.log` reports the mod loaded and no script errors. Menus in the headless setup did not reliably receive injected mouse clicks; the tested run loaded the save with temporary test-only UE4SS widget-handler calls. This helper launches the game but intentionally makes **no** claim that it can navigate the menu unattended. If input fails, use a visible interactive setup or safely instrument only the isolated mod; never ship test bindings with `main.lua`.

### Mute the game's audio

In a **second terminal**, after the game's audio stream appears:

```sh
InventorySlotReservations/tests/scripts/mute-game-linux.sh
wpctl status    # check the AlchemyFactory stream is muted
```

The helper searches the PipeWire/WirePlumber streams for exactly one `AlchemyFactory` stream and calls `wpctl set-mute <stream-id> 1`; it refuses zero/multiple matches. You can pass a known stream ID as its first argument if necessary. **Re-run it after every game restart**, because stream IDs change. This mutes only the isolated game's stream, not the system output. For Windows/manual testing, mute the game in the OS volume mixer **before** running scenarios.

### Screenshots (and optional GIFs)

Headless Gamescope publishes a PipeWire video node. With the game visible and still running:

```sh
InventorySlotReservations/tests/scripts/screenshot-linux.sh /tmp/closed-chest.png
InventorySlotReservations/tests/scripts/screenshot-linux.sh /tmp/open-inventory.png
```

The helper discovers a uniquely named Gamescope node using `pw-dump`, then captures one PNG frame with `gst-launch-1.0`; if several matches exist, pass the node ID as a second argument. Check `pw-dump` if no node is found. For an X11/Xvfb run (not Gamescope), `DISPLAY=:99 import -window root /tmp/frame.png` is an alternative if ImageMagick is installed. You can also use the desktop's normal screenshot shortcut for a visible game. To make a GIF, capture a sequence of PNGs and encode with an image tool (e.g. `ffmpeg -framerate 5 -i 'frame-%03d.png' -vf 'fps=5,scale=800:-1:flags=lanczos' demo.gif`); never present still screenshots as transfer proof without checking the inventories/log. The README uses two cropped stills from the isolated run, not a GIF.

## Manual in-game scenarios and expected results

1. With inventory open, hover an **occupied player slot** and press N. Verify the circular mark and native filter. N again clears both; a neighboring unreserved slot remains unchanged.
2. Empty a reserved slot without removing its filter. Save, restart, and check the filter/marker persists; G / Take All should skip incompatible items while an unreserved control slot may receive them.
3. Aim at the **closed** chest (E/G prompt); press N. Check both inventories: matching reserved destinations fill only up to their native cap, unrelated/unreserved slots are unchanged, and total item counts are conserved.
4. Repeat with a partial reserved stack, e.g. 50/100. Expect exactly 50 to transfer if the chest has at least 50, and no overfill. Press N again with all reservations full: expect zero transfers.
5. Open the chest UI and press N while not hovering a player slot: expect **no pull**. Confirm the chest and player totals remain unchanged. Check the sort button is disabled while reservations exist. Close the UI before testing another pull.

In the 2026-09-29 isolated camera-aligned save, chest 100+100 and an empty filtered player slot yielded player 100/chest 100 after N. Native splitting created player reserved 50 plus free 50; a second N filled the reserved slot to 100, left the free stack at 50, and left chest 50. A third N moved zero stacks; N with the chest UI open did not pull. The filter and circular marker remained. Earlier isolated tests also checked save/restart persistence, filled and empty reserved destinations, and neighboring unreserved controls. These are observed results on the tested game build, not a guarantee for every chest/item or multiplayer session.

Inspect the **isolated** `AlchemyFactory/Binaries/Win64/ue4ss/UE4SS.log` for `Chest pull started`, `Restored filter`, and `Chest pull done: ... moved N stacks`, plus script errors. Logs alone do not prove quantities: compare the visible inventory counts or safe read-only diagnostics **before and after** each transfer. Do not copy isolated saves back to the real prefix after testing.
