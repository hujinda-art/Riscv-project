#!/usr/bin/env python3
import struct
import sys
from pathlib import Path

if len(sys.argv) != 3:
    print("Usage: bin2hex.py <input.bin> <output.hex>")
    sys.exit(1)

in_path = Path(sys.argv[1])
out_path = Path(sys.argv[2])

data = in_path.read_bytes()
if len(data) % 4 != 0:
    data += b"\x00" * (4 - (len(data) % 4))

with out_path.open("w", encoding="ascii") as f:
    for i in range(0, len(data), 4):
        word = struct.unpack("<I", data[i:i+4])[0]
        f.write(f"{word:08x}\n")
