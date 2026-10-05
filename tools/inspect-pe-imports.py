#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Madeira Converter Exception: see LICENSE-EXCEPTION.md
"""Inspect a PE image and resolve its direct imports beside the image.

This is a read-only loader diagnostic. It never copies Windows runtime files.
"""

import argparse
import hashlib
import json
import struct
from pathlib import Path


def inspect(path: Path) -> dict:
    data = path.read_bytes()

    def unpack(fmt: str, offset: int):
        size = struct.calcsize(fmt)
        if offset < 0 or offset + size > len(data):
            raise ValueError(f"truncated PE at offset 0x{offset:x}")
        return struct.unpack_from(fmt, data, offset)

    if data[:2] != b"MZ":
        raise ValueError("missing MZ header")
    pe = unpack("<I", 0x3C)[0]
    if data[pe:pe + 4] != b"PE\0\0":
        raise ValueError("missing PE signature")
    machine, sections, _, _, _, optional_size, _ = unpack("<HHIIIHH", pe + 4)
    optional = pe + 24
    magic = unpack("<H", optional)[0]
    if magic == 0x20B:
        image_base = unpack("<Q", optional + 24)[0]
        directory = optional + 112
    elif magic == 0x10B:
        image_base = unpack("<I", optional + 28)[0]
        directory = optional + 96
    else:
        raise ValueError(f"unsupported optional header 0x{magic:x}")
    image_size = unpack("<I", optional + 56)[0]
    alignment = unpack("<I", optional + 32)[0]
    dll_characteristics = unpack("<H", optional + 70)[0]
    directory_count = unpack("<I", directory - 4)[0]
    headers_size = unpack("<I", optional + 60)[0]
    section_table = optional + optional_size
    ranges = []
    for index in range(sections):
        offset = section_table + index * 40
        _, virtual_size, rva, raw_size, raw_offset = unpack("<8sIIII", offset)
        ranges.append((rva, max(virtual_size, raw_size), raw_offset, raw_size))

    def file_offset(rva: int) -> int:
        if rva < headers_size:
            return rva
        for start, size, raw, raw_size in ranges:
            if start <= rva < start + size and rva - start < raw_size:
                return raw + rva - start
        raise ValueError(f"RVA 0x{rva:x} is not backed by file data")

    def imports_at(index: int) -> list[str]:
        if directory_count <= index:
            return []
        rva, size = unpack("<II", directory + index * 8)
        if not rva or not size:
            return []
        imports = []
        count = 0
        while True:
            if count > 4096:
                raise ValueError("import descriptor limit exceeded")
            offset = file_offset(rva + count * 20)
            fields = unpack("<IIIII", offset)
            if not any(fields):
                return imports
            name_offset = file_offset(fields[3])
            end = data.find(b"\0", name_offset, min(len(data), name_offset + 512))
            if end < 0:
                raise ValueError("unterminated import name")
            imports.append(data[name_offset:end].decode("ascii", errors="replace"))
            count += 1

    imports = imports_at(1)
    relocations = unpack("<II", directory + 5 * 8) if directory_count > 5 else (0, 0)
    siblings = {item.name.lower() for item in path.parent.iterdir() if item.is_file()}
    return {
        "file": path.name,
        "sha256": hashlib.sha256(data).hexdigest(),
        "machine": f"0x{machine:04x}",
        "pe_magic": f"0x{magic:03x}",
        "image_base": f"0x{image_base:x}",
        "image_size": image_size,
        "section_alignment": alignment,
        "dll_characteristics": f"0x{dll_characteristics:04x}",
        "has_relocations": bool(relocations[0] and relocations[1]),
        "imports": imports,
        "sibling_imports": [name for name in imports if name.lower() in siblings],
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("images", nargs="+", type=Path)
    args = parser.parse_args()
    for image in args.images:
        print(json.dumps(inspect(image), sort_keys=True))


if __name__ == "__main__":
    main()
