#!/usr/bin/env python3
"""Build tempest.rom for the Analogue Pocket Tempest core from a MAME romset.

    python3 make_tempest_rom.py tempest.zip [tempest.rom] [--set NAME]

The input can be a MAME zip or a folder of ROM files. Parts are matched by
CRC32, so file names inside the zip don't matter, and the script refuses to
write anything unless every part of a known set is present and correct.

Output layout (24,576 bytes):
    0x0000-0x4FFF  program ROM, CPU $9000-$DFFF
    0x5000-0x5FFF  vector ROM,  CPU $3000-$3FFF

Part lists are taken from MAME's src/mame/atari/tempest.cpp.
"""
import argparse
import os
import sys
import zipfile
import zlib

# (name, file offset, size, crc32)
SETS = {
    "tempest": [   # rev 3, revised hardware
        ("136002-133.d1",  0x0000, 0x1000, 0x1d0cc503),
        ("136002-134.f1",  0x1000, 0x1000, 0xc88e3524),
        ("136002-235.j1",  0x2000, 0x1000, 0xa4b2ce3f),
        ("136002-136.lm1", 0x3000, 0x1000, 0x65a9a9f9),
        ("136002-237.p1",  0x4000, 0x1000, 0xde4e9e34),
        ("136002-138.np3", 0x5000, 0x1000, 0x9995256d),
    ],
    "tempest1r": [  # rev 1, revised hardware
        ("136002-133.d1",  0x0000, 0x1000, 0x1d0cc503),
        ("136002-134.f1",  0x1000, 0x1000, 0xc88e3524),
        ("136002-135.j1",  0x2000, 0x1000, 0x1ca27781),
        ("136002-136.lm1", 0x3000, 0x1000, 0x65a9a9f9),
        ("136002-137.p1",  0x4000, 0x1000, 0xd75fd2ef),
        ("136002-138.np3", 0x5000, 0x1000, 0x9995256d),
    ],
}

_2K_COMMON = [
    ("136002-113.d1",  0x0000, 0x0800, 0x65d61fe7),
    ("136002-114.e1",  0x0800, 0x0800, 0x11077375),
    ("136002-115.f1",  0x1000, 0x0800, 0xf3e2827a),
    ("136002-118.k1",  0x2800, 0x0800, 0xbeb352ab),
    ("136002-119.lm1", 0x3000, 0x0800, 0xa4de050f),
    ("136002-120.mn1", 0x3800, 0x0800, 0x35619648),
    ("136002-121.p1",  0x4000, 0x0800, 0x73d38e47),
    ("136002-123.np3", 0x5000, 0x0800, 0x29f7e937),
    ("136002-124.r3",  0x5800, 0x0800, 0xc16ec351),
]

SETS["tempest3"] = _2K_COMMON + [
    ("136002-316.h1",  0x1800, 0x0800, 0xaeb0f7e9),
    ("136002-217.j1",  0x2000, 0x0800, 0xef2eb645),
    ("136002-222.r1",  0x4800, 0x0800, 0x707bd5c3),
]
SETS["tempest2"] = _2K_COMMON + [
    ("136002-116.h1",  0x1800, 0x0800, 0x7356896c),
    ("136002-217.j1",  0x2000, 0x0800, 0xef2eb645),
    ("136002-222.r1",  0x4800, 0x0800, 0x707bd5c3),
]
SETS["tempest1"] = _2K_COMMON + [
    ("136002-116.h1",  0x1800, 0x0800, 0x7356896c),
    ("136002-117.j1",  0x2000, 0x0800, 0x55952119),
    ("136002-122.r1",  0x4800, 0x0800, 0x796a9918),
]
SETS["temptube"] = [p for p in _2K_COMMON if p[0] != "136002-118.k1"] + [
    ("136002-316.h1",  0x1800, 0x0800, 0xaeb0f7e9),
    ("136002-217.j1",  0x2000, 0x0800, 0xef2eb645),
    ("tube-118.k1",    0x2800, 0x0800, 0xcefb03f0),
    ("136002-222.r1",  0x4800, 0x0800, 0x707bd5c3),
]

ROM_SIZE = 0x6000


def load_files(path):
    """Return {crc32: bytes} for every file in a zip or folder."""
    blobs = {}
    if os.path.isdir(path):
        for name in os.listdir(path):
            full = os.path.join(path, name)
            if os.path.isfile(full):
                data = open(full, "rb").read()
                blobs[zlib.crc32(data) & 0xFFFFFFFF] = data
    else:
        with zipfile.ZipFile(path) as z:
            for info in z.infolist():
                if not info.is_dir():
                    data = z.read(info)
                    blobs[zlib.crc32(data) & 0xFFFFFFFF] = data
    return blobs


def build(parts, blobs):
    rom = bytearray(ROM_SIZE)
    for name, off, size, crc in parts:
        data = blobs[crc]
        if len(data) != size:
            raise ValueError(f"{name}: expected {size} bytes, found {len(data)}")
        rom[off:off + size] = data
    return bytes(rom)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("source", help="MAME zip (e.g. tempest.zip) or folder of ROM files")
    ap.add_argument("output", nargs="?", default="tempest.rom")
    ap.add_argument("--set", choices=sorted(SETS), help="force a specific romset")
    args = ap.parse_args()

    blobs = load_files(args.source)
    candidates = [args.set] if args.set else list(SETS)
    for name in candidates:
        missing = [p[0] for p in SETS[name] if p[3] not in blobs]
        if not missing:
            rom = build(SETS[name], blobs)
            with open(args.output, "wb") as f:
                f.write(rom)
            print(f"Built {args.output} from the '{name}' set ({len(rom)} bytes).")
            print("Copy it to /Assets/tempest/common/ on the Pocket's SD card.")
            return 0
        if args.set:
            print(f"Set '{name}' is missing or has bad CRCs for: {', '.join(missing)}")
            return 1

    print("No complete Tempest romset found. Closest matches:")
    for name in SETS:
        have = sum(1 for p in SETS[name] if p[3] in blobs)
        print(f"  {name:10s} {have}/{len(SETS[name])} parts")
    print("A parent set zip may be needed alongside a clone (merge them into one folder).")
    return 1


if __name__ == "__main__":
    sys.exit(main())
