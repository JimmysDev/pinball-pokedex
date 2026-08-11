#!/usr/bin/env python3
"""
Turn the raw in-game dex portraits (portraits_raw/, indexed PNGs ripped from the
pret/pokepinballrs decompilation) into transparent-background sprites in Resources/portraits/.

Why this is fiddly: the portraits bake the dex *scene* background into the image. They're
16-colour palette PNGs, and a Pokémon's white eye is a DIFFERENT palette index than the white
background even though both render white — so we key out the background by *index*, never by
colour (keying by colour gouged eyes/mouths).

Two strategies:
  A (default, safe): remove only the single most-common border index globally. Clears the
     background + interior pockets, and never cuts the Pokémon (its parts are other indices).
     Leaves a fringe on multi-colour *scene* backgrounds.
  B (flood, opt-in per sprite): flood from the border through all border indices, stopping at
     the subject's colours. Cleans scene backgrounds (e.g. Machamp's jungle) BUT eats any
     Pokémon whose body reaches the frame edge (Wingull, Tentacool's tentacles). Only enable it
     per-sprite after visually confirming the subject sits away from the edges.

To fix a specific scene-background sprite: add its pinball number to SCENE_BG and re-run, then
eyeball the result. If the flood eats the subject, take it back out (that sprite stays on A).
"""
import os, sys
from collections import Counter, deque
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RAW = os.path.join(ROOT, "portraits_raw")
OUT = os.path.join(ROOT, "Resources", "portraits")

# Pinball numbers that need the flood method (subject verified to sit away from the edges).
# Sprites that use the flood method. Empty for now: the flood cleared Machamp's jungle but left
# him a "floating head" (the game's portrait is a head-crop), which looked worse — so Machamp uses
# the standard method like everything else.
SCENE_BG = set()   # strat_b (flood all border colours) eats subjects that touch the edge — avoid.

# Corner-flood (strat_c): flood out only the indices found at the four corners, from the border inward.
# Removes a background that's a DIFFERENT index from the subject even when the subject's body reaches
# the frame edge (where strat_a/strat_b would gouge it). e.g. cream Ninetales; Torkoal's scene bg.
CORNER_FLOOD = {75, 105, 154}

# Pinball numbers to leave exactly as the raw original (background kept, nothing cut).
RAW_AS_IS = set()

def border_pixels(px, w, h):
    return ([(x, 0) for x in range(w)] + [(x, h - 1) for x in range(w)] +
            [(0, y) for y in range(h)] + [(w - 1, y) for y in range(h)])

def strat_a(im):
    w, h = im.size; px = im.load()
    bg = Counter(px[xy] for xy in border_pixels(px, w, h)).most_common(1)[0][0]
    out = im.convert("RGBA"); o = out.load()
    for x in range(w):
        for y in range(h):
            if px[x, y] == bg:
                o[x, y] = (0, 0, 0, 0)
    return out

def strat_b(im):
    w, h = im.size; px = im.load()
    bp = border_pixels(px, w, h)
    bset = {idx for idx, n in Counter(px[xy] for xy in bp).items() if n >= 0.015 * len(bp)}
    seen = [[False] * h for _ in range(w)]; dq = deque()
    for x, y in bp:
        if not seen[x][y] and px[x, y] in bset:
            seen[x][y] = True; dq.append((x, y))
    out = im.convert("RGBA"); o = out.load()
    while dq:
        x, y = dq.popleft(); o[x, y] = (0, 0, 0, 0)
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            nx, ny = x + dx, y + dy
            if 0 <= nx < w and 0 <= ny < h and not seen[nx][ny] and px[nx, ny] in bset:
                seen[nx][ny] = True; dq.append((nx, ny))
    return out

def strat_c(im):
    w, h = im.size; px = im.load()
    corners = {px[0, 0], px[w - 1, 0], px[0, h - 1], px[w - 1, h - 1]}
    # A corner colour is BACKGROUND only if it's essentially absent from the centre (the body). This
    # removes all of a multi-colour scene bg (Torkoal) yet keeps a body colour that merely touches a
    # corner (Ninetales' cream/brown).
    cx0, cx1, cy0, cy1 = int(w * 0.28), int(w * 0.72), int(h * 0.28), int(h * 0.72)
    centre = Counter(px[x, y] for x in range(cx0, cx1) for y in range(cy0, cy1))
    ctot = max(1, sum(centre.values()))
    bset = {c for c in corners if centre.get(c, 0) < 0.03 * ctot}
    if not bset:   # subject fills the frame — fall back to the single dominant corner
        bset = {Counter([px[0, 0], px[w - 1, 0], px[0, h - 1], px[w - 1, h - 1]]).most_common(1)[0][0]}
    seen = [[False] * h for _ in range(w)]; dq = deque()
    for x, y in border_pixels(px, w, h):
        if not seen[x][y] and px[x, y] in bset:
            seen[x][y] = True; dq.append((x, y))
    out = im.convert("RGBA"); o = out.load()
    while dq:
        x, y = dq.popleft(); o[x, y] = (0, 0, 0, 0)
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            nx, ny = x + dx, y + dy
            if 0 <= nx < w and 0 <= ny < h and not seen[nx][ny] and px[nx, ny] in bset:
                seen[nx][ny] = True; dq.append((nx, ny))
    clear_pockets(im, out, bset, seen)
    return out

def clear_pockets(im, out, bset, seen, max_frac=0.06):
    """Remove background the border flood can't reach: pockets of a background index fully enclosed by
    the subject (e.g. Ninetales' white showing through between body and tails). Safe because we key by
    palette INDEX — a Pokémon's own white is a different index than the background's (Ninetales has
    both: bg white is index 15, its eye highlight is index 11). The size cap keeps a genuinely large
    enclosed area — which would more likely be part of the subject — intact."""
    w, h = im.size; px = im.load(); o = out.load()
    done = [[seen[x][y] for y in range(h)] for x in range(w)]
    for sx in range(w):
        for sy in range(h):
            if done[sx][sy] or px[sx, sy] not in bset:
                continue
            comp, dq = [], deque([(sx, sy)]); done[sx][sy] = True
            while dq:
                x, y = dq.popleft(); comp.append((x, y))
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < w and 0 <= ny < h and not done[nx][ny] and px[nx, ny] in bset:
                        done[nx][ny] = True; dq.append((nx, ny))
            if len(comp) <= max_frac * w * h:
                for x, y in comp:
                    o[x, y] = (0, 0, 0, 0)

def over_cut(im):
    """True if strat_a would gouge the subject: the most-common border index isn't a corner index,
    meaning the body (not the background) dominates the border. Such sprites need the corner-flood."""
    w, h = im.size; px = im.load()
    mc = Counter(px[xy] for xy in border_pixels(px, w, h)).most_common(1)[0][0]
    corners = {px[0, 0], px[w - 1, 0], px[0, h - 1], px[w - 1, h - 1]}
    return mc not in corners

def center_opaque_frac(rgba):
    w, h = rgba.size; o = rgba.load()
    xs = range(int(w * 0.3), int(w * 0.7)); ys = range(int(h * 0.3), int(h * 0.7))
    cells = [(x, y) for x in xs for y in ys]
    return sum(1 for x, y in cells if o[x, y][3] > 0) / max(1, len(cells))

def main():
    os.makedirs(OUT, exist_ok=True)
    n = 0; auto = []
    for fn in sorted(os.listdir(RAW)):
        if not fn.endswith(".png"):
            continue
        num = int(fn[:-4]); im = Image.open(os.path.join(RAW, fn))
        if im.mode != "P" or num in RAW_AS_IS:
            im.convert("RGBA").save(os.path.join(OUT, fn)); n += 1; continue
        # Auto-detect over-cut sprites (Ninetales/Machamp/Blaziken-style) and corner-flood them; fall
        # back to strat_a if the flood would eat the body (subject reaches a corner).
        use_c = num in CORNER_FLOOD or (num not in SCENE_BG and over_cut(im))
        if use_c:
            out = strat_c(im)
            if num not in CORNER_FLOOD and center_opaque_frac(out) < 0.55:
                out = strat_a(im)          # flood ate too much — keep the safe method
            elif num not in CORNER_FLOOD:
                auto.append(num)
        else:
            out = strat_b(im) if num in SCENE_BG else strat_a(im)
        out.save(os.path.join(OUT, fn)); n += 1
    print(f"cleaned {n} portraits -> {OUT}")
    print(f"corner-flood (manual): {sorted(CORNER_FLOOD)}   (auto-detected over-cut): {sorted(auto)}")

if __name__ == "__main__":
    main()
