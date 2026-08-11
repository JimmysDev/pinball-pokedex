#!/bin/bash
# One-click launcher: opens mGBA with the Pinball ROM and auto-loads the live bridge.
# Double-click this file (Finder) to run it. First run will ask to grant Accessibility
# permission to Terminal/osascript so it can drive mGBA's menus — that's a one-time prompt.
#
# This uses UI automation (it clicks Tools ▸ Scripting… and pastes the loader for you),
# because mGBA 0.10.5 has no --script command-line flag. If a step misfires, tell me which
# one and I'll tune the delays / menu names.

ROM="/Users/jimmy/GBA/Pokemon Pinball - Ruby & Sapphire (USA).gba"
LOADER='dofile("/Users/jimmy/Developer/repos/pinball-pokedex/scripts/mgba_bridge.lua")'

# 1) Put the loader line on the clipboard (so we paste, not type, into the Scripting box).
printf '%s' "$LOADER" | pbcopy

# 2) Launch mGBA with the ROM.
open -a mGBA "$ROM"

# 3) Drive the UI: open the Scripting window, paste the loader, run it.
osascript <<'OSA'
tell application "mGBA" to activate
delay 3
tell application "System Events"
  tell process "mGBA"
    click menu item "Scripting…" of menu "Tools" of menu bar 1
    delay 1.5
    keystroke "v" using command down   -- paste the loader into the Scripting input box
    delay 0.3
    key code 36                        -- Return → run it
  end tell
end tell
OSA

echo "Launched. Check the Pinball Pokédex header — it should flip to 'Live'."
