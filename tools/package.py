#!/usr/bin/env python3
"""Assemble the Pocket SD-card package from the compiled bitstream.

    python3 tools/package.py

Reads src/fpga/output_files/ap_core.rbf, bit-reverses every byte into
bitstream.rbf_r (the format the Pocket loads), copies dist/ to
release/pocket/ and zips it. ROM files are never packaged.
"""
import os
import shutil
import sys
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RBF = os.path.join(ROOT, "src", "fpga", "output_files", "ap_core.rbf")
DIST = os.path.join(ROOT, "dist")
OUT = os.path.join(ROOT, "release", "pocket")
CORE_ID = "mcbeefy34.Tempest"


def main():
    if not os.path.exists(RBF):
        sys.exit(f"missing {RBF}: run the Quartus compile first")

    rev = bytes(int(f"{b:08b}"[::-1], 2) for b in range(256))
    data = open(RBF, "rb").read().translate(rev)

    if os.path.exists(OUT):
        shutil.rmtree(OUT)
    shutil.copytree(DIST, OUT, ignore=shutil.ignore_patterns(".DS_Store", "*.rom", "*.zip", "*.sav"))
    with open(os.path.join(OUT, "Cores", CORE_ID, "bitstream.rbf_r"), "wb") as f:
        f.write(data)
    shutil.copy(os.path.join(ROOT, "tools", "make_tempest_rom.py"),
                os.path.join(OUT, "Assets", "tempest", "common", "make_tempest_rom.py"))

    strays = [os.path.join(dp, f) for dp, _, fs in os.walk(OUT) for f in fs
              if f.lower().endswith((".rom", ".zip"))]
    if strays:
        sys.exit("refusing to package, ROM files present:\n  " + "\n  ".join(strays))

    zpath = os.path.join(ROOT, "release", "tempest-pocket.zip")
    with zipfile.ZipFile(zpath, "w", zipfile.ZIP_DEFLATED) as z:
        for dp, _, fs in os.walk(OUT):
            for f in fs:
                full = os.path.join(dp, f)
                z.write(full, os.path.relpath(full, OUT))
    print(f"packaged {OUT}\nzip: {zpath}")


if __name__ == "__main__":
    main()
