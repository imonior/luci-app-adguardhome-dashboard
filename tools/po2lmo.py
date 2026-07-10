#!/usr/bin/env python3
"""
po2lmo.py - Convert .po files to LuCI .lmo format.

LuCI LMO binary format:
  [entry_table]  - sorted by FNV1a hash, each entry: hash(4B) + offset(4B) + length(4B)
  [string_pool]  - null-terminated msgid\0msgstr\0 pairs
  [footer]       - entry_table_offset(4B LE) + magic "LMO\\0"(4B)

Reference: luci-base/src/po2lmo.c / lmo.c
"""

import struct
import sys
import os
import re

def fnv1a_32(data):
    """FNV-1a 32-bit hash."""
    h = 0x811c9dc5
    for b in data:
        h ^= b
        h = (h * 0x01000193) & 0xFFFFFFFF
    return h

def parse_po(filepath):
    """Parse a .po file and return list of (msgid, msgstr) tuples."""
    entries = []
    current_msgid = None
    current_msgstr = None
    in_msgid = False
    in_msgstr = False

    with open(filepath, 'r', encoding='utf-8') as f:
        for line in f:
            line = line.rstrip('\n')

            if line.startswith('msgid '):
                if current_msgid is not None and current_msgstr is not None:
                    if current_msgid and current_msgstr:  # skip empty msgid (header)
                        entries.append((current_msgid, current_msgstr))
                current_msgid = extract_string(line[6:])
                current_msgstr = None
                in_msgid = True
                in_msgstr = False

            elif line.startswith('msgstr '):
                current_msgstr = extract_string(line[7:])
                in_msgid = False
                in_msgstr = True

            elif line.startswith('"') and line.endswith('"'):
                s = extract_string(line)
                if in_msgid:
                    current_msgid += s
                elif in_msgstr:
                    current_msgstr += s

            else:
                in_msgid = False
                in_msgstr = False

        # Don't forget the last entry
        if current_msgid is not None and current_msgstr is not None:
            if current_msgid and current_msgstr:
                entries.append((current_msgid, current_msgstr))

    return entries

def extract_string(s):
    """Extract the string value from a quoted .po string."""
    s = s.strip()
    if s.startswith('"') and s.endswith('"'):
        s = s[1:-1]
    # Unescape
    s = s.replace('\\n', '\n')
    s = s.replace('\\t', '\t')
    s = s.replace('\\"', '"')
    s = s.replace('\\\\', '\\')
    return s

def build_lmo(entries):
    """Build LMO binary data from (msgid, msgstr) entries."""
    # Build entries with hashes
    hashed = []
    for msgid, msgstr in entries:
        msgid_bytes = msgid.encode('utf-8')
        msgstr_bytes = msgstr.encode('utf-8')
        h = fnv1a_32(msgid_bytes)
        hashed.append((h, msgid_bytes, msgstr_bytes))

    # Sort by hash (required for binary search in lmo.c)
    hashed.sort(key=lambda x: x[0])

    # Build string pool
    string_pool = bytearray()
    pool_entries = []  # (hash, offset, length) - length includes both msgid+msgstr+nulls

    for h, msgid_bytes, msgstr_bytes in hashed:
        offset = len(string_pool)
        # msgid + null + msgstr + null
        string_pool.extend(msgid_bytes)
        string_pool.append(0)  # null terminator for msgid
        string_pool.extend(msgstr_bytes)
        string_pool.append(0)  # null terminator for msgstr
        # length = len(msgid) + 1 (null) + len(msgstr) + 1 (null)
        # But actually, lmo.c stores: offset to msgid, and the length field
        # Let me check: lmo_change_catalog reads msgstr as (data + offset + msgid_len + 1)
        # So the entry stores: offset to start of (msgid\0msgstr\0), and total length
        total_len = len(msgid_bytes) + 1 + len(msgstr_bytes) + 1
        pool_entries.append((h, offset, total_len))

    # Build entry table (12 bytes per entry)
    entry_table = bytearray()
    for h, offset, length in pool_entries:
        entry_table.extend(struct.pack('<III', h, offset, length))

    # Assemble: entry_table + string_pool + footer
    idx_offset = len(entry_table)  # offset to entry table from start of data

    output = bytearray()
    output.extend(entry_table)
    output.extend(string_pool)
    # Footer: entry_table_offset (4B LE) + magic (4B)
    output.extend(struct.pack('<I', idx_offset))
    output.extend(b'LMO\x00')

    return bytes(output)

def main():
    if len(sys.argv) != 3:
        print(f"Usage: {sys.argv[0]} input.po output.lmo", file=sys.stderr)
        sys.exit(1)

    po_file = sys.argv[1]
    lmo_file = sys.argv[2]

    entries = parse_po(po_file)
    if not entries:
        print(f"Warning: No translation entries found in {po_file}", file=sys.stderr)

    lmo_data = build_lmo(entries)

    with open(lmo_file, 'wb') as f:
        f.write(lmo_data)

    print(f"Compiled {len(entries)} entries -> {lmo_file} ({len(lmo_data)} bytes)")

if __name__ == '__main__':
    main()
