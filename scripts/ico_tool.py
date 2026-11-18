#!/usr/bin/env python3
"""Validate or rebuild Windows .ico files.

Why this exists
---------------
Windows Shell silently falls back to a generic "blank page" icon when an .ico
declares more image bytes than the file actually contains. Such files often
still load in some viewers, which makes the bug hard to spot.

Usage
-----
    python ico_tool.py check app.ico
    python ico_tool.py rebuild source.png -o app.ico
    python ico_tool.py rebuild source.png -o app.ico --sizes 16,32,48,256

Exit codes
----------
    0  file is valid / rebuild succeeded
    1  file is invalid or rebuild failed
"""

import argparse
import os
import struct
import sys
from typing import List, Tuple


def read_dir(data: bytes) -> Tuple[int, List[Tuple[int, int, int, int, int]]]:
    """Return (entry_count, [(width, height, bytes, offset, bitcount), ...])."""
    if len(data) < 6:
        raise ValueError("file too small to be an ICO")
    reserved, ico_type, count = struct.unpack_from("<HHH", data, 0)
    if reserved != 0 or ico_type != 1:
        raise ValueError("not an ICO file (bad header)")
    if count == 0:
        raise ValueError("ICO declares zero images")

    entries = []
    for i in range(count):
        off = 6 + i * 16
        if off + 16 > len(data):
            raise ValueError("truncated directory")
        w, h = data[off], data[off + 1]
        bitcount = struct.unpack_from("<H", data, off + 6)[0]
        size = struct.unpack_from("<I", data, off + 8)[0]
        offset = struct.unpack_from("<I", data, off + 12)[0]
        entries.append((w or 256, h or 256, size, offset, bitcount))
    return count, entries


def cmd_check(path: str) -> int:
    with open(path, "rb") as f:
        data = f.read()

    try:
        count, entries = read_dir(data)
    except ValueError as exc:
        print(f"INVALID  {path}\n  reason: {exc}")
        return 1

    problems = []
    print(f"file   : {path}")
    print(f"size   : {len(data)} bytes")
    print(f"images : {count}")
    for idx, (w, h, size, offset, bitcount) in enumerate(entries):
        end = offset + size
        ok = size > 0 and end <= len(data)
        fmt = "PNG" if bitcount == 0 else f"{bitcount}bpp BMP"
        print(f"  [{idx}] {w}x{h:<4} {fmt:<10} bytes={size:<8} end={end:<8} {'ok' if ok else 'OUT OF BOUNDS'}")
        if not ok:
            problems.append(idx)

    if problems:
        print(f"\nINVALID  {len(problems)} entr(y/ies) point past end of file -> Shell will show a generic icon.")
        print("Fix: rebuild from the original PNG with `rebuild`.")
        return 1

    print("\nOK")
    return 0


def cmd_rebuild(src: str, out: str, sizes: str) -> int:
    try:
        from PIL import Image
    except ImportError:
        print("Pillow is required: pip install pillow", file=sys.stderr)
        return 1

    size_list = [int(s) for s in sizes.split(",") if s.strip()]
    if not size_list:
        print("no sizes given", file=sys.stderr)
        return 1

    img = Image.open(src).convert("RGBA")
    img.save(out, format="ICO", sizes=[(s, s) for s in size_list])

    print(f"written: {out} ({os.path.getsize(out)} bytes)")
    return cmd_check(out)


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate or rebuild Windows .ico files.")
    sub = parser.add_subparsers(dest="command", required=True)

    p_check = sub.add_parser("check", help="verify that all ICO entries fit inside the file")
    p_check.add_argument("file")

    p_build = sub.add_parser("rebuild", help="rebuild a multi-size ICO from a PNG")
    p_build.add_argument("source")
    p_build.add_argument("-o", "--out", required=True)
    p_build.add_argument("--sizes", default="16,24,32,48,64,128,256")

    args = parser.parse_args()
    if args.command == "check":
        return cmd_check(args.file)
    return cmd_rebuild(args.source, args.out, args.sizes)


if __name__ == "__main__":
    sys.exit(main())
