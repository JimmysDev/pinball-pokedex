#!/bin/bash
# Snapshot the live Pokémon Pinball R&S save into ./save-backups/ with a timestamp.
set -euo pipefail
cd "$(dirname "$0")"
SAVE="$HOME/Documents/Game Boy Advance/Pokemon Pinball - Ruby & Sapphire (USA).sav"
mkdir -p save-backups
TS=$(date +%Y-%m-%d_%H%M%S)
cp "$SAVE" "save-backups/Pokemon Pinball - Ruby & Sapphire (USA) ${TS}.sav"
echo "✅ backed up -> save-backups/Pokemon Pinball - Ruby & Sapphire (USA) ${TS}.sav"
