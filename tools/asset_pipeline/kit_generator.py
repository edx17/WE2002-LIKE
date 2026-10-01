"""Kit textures: data/kits/*.json -> assets/kits/<id>.png

    python tools/asset_pipeline/kit_generator.py            (every kit)
    python tools/asset_pipeline/kit_generator.py team_a_home

No dependencies (plain zlib PNG writer), so kits can be regenerated on any
machine, including CI, without Blender.

UV contract shared with player_generator.py (every player uses the same one):

    u: angle around the torso      0.0 back | 0.25 right side | 0.5 chest | 0.75 left side | 1.0 back
    v: height                      0.0 hem  ..........  0.95 shoulders | 0.955-1.0 collar ring only

Patterns: plain, stripes (vertical), hoops (horizontal), halves, sash.
"""

import json
import os
import struct
import sys
import zlib

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
KITS = os.path.join(ROOT, "data", "kits")
OUT = os.path.join(ROOT, "assets", "kits")
SIZE = 1024


def rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def pattern_value(kit, u, v):
    """True where the secondary colour goes."""
    p = kit.get("pattern", "plain")
    if p == "stripes":
        return int(u * kit.get("stripes", 10)) % 2 == 1
    if p == "hoops":
        return int(v * kit.get("hoops", 7)) % 2 == 1
    if p == "halves":
        return u < 0.5
    if p == "sash":
        # Diagonal band across the chest.
        d = (u - 0.5) * 2.2 + (v - 0.5)
        return abs(d) < 0.14
    return False


def render(kit, size=SIZE):
    primary, secondary, collar = rgb(kit["primary"]), rgb(kit["secondary"]), rgb(kit.get("collar", kit["secondary"]))
    rows = []
    for y in range(size):
        v = 1.0 - (y + 0.5) / size
        row = bytearray(b"\x00")  # PNG filter: none
        for x in range(size):
            u = (x + 0.5) / size
            if v > 0.955:
                c = collar
            else:
                c = secondary if pattern_value(kit, u, v) else primary
                # Soft fabric shading bands: seams at the sides, darker hem.
                side = min(abs(u - 0.25), abs(u - 0.75))
                shade = 0.93 if side < 0.006 else (0.96 if v < 0.03 else 1.0)
                c = tuple(int(ch * shade) for ch in c)
            row += bytes(c)
        rows.append(bytes(row))
    return b"".join(rows)


def write_png(path, size, raw):
    def chunk(tag, data):
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 2, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(raw, 9))
    png += chunk(b"IEND", b"")
    with open(path, "wb") as f:
        f.write(png)


def main(ids):
    if not ids:
        ids = sorted(f[:-5] for f in os.listdir(KITS) if f.endswith(".json"))
    os.makedirs(OUT, exist_ok=True)
    for kid in ids:
        with open(os.path.join(KITS, f"{kid}.json"), encoding="utf-8") as f:
            kit = json.load(f)
        path = os.path.join(OUT, f"{kid}.png")
        write_png(path, SIZE, render(kit))
        print(f"[kit_generator] {kid} ({kit.get('pattern', 'plain')}) -> {os.path.relpath(path, ROOT)}")


if __name__ == "__main__":
    main(sys.argv[1:])
