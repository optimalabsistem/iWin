#!/usr/bin/env python3
import sys, struct, os

def rename_symbols_in_macho(filepath, renames):
    with open(filepath, 'rb') as f:
        data = bytearray(f.read())

    if len(data) < 32:
        return

    magic = struct.unpack_from('<I', data, 0)[0]
    if magic != 0xfeedfacf: # MH_MAGIC_64
        return

    ncmds, sizeofcmds = struct.unpack_from('<II', data, 16)
    offset = 32

    symtab_offset = None
    for _ in range(ncmds):
        cmd, cmdsize = struct.unpack_from('<II', data, offset)
        if cmd == 0x2: # LC_SYMTAB
            symtab_offset = offset
            break
        offset += cmdsize

    if not symtab_offset:
        return

    _, _, symoff, nsyms, stroff, strsize = struct.unpack_from('<IIIIII', data, symtab_offset)

    strtab = bytes(data[stroff:stroff + strsize])
    new_strtab = bytearray(strtab)

    # For fast lookup:
    nlist_struct = struct.Struct('<IBBHQ')
    for i in range(nsyms):
        nlist_off = symoff + i * 16
        n_strx, n_type, n_sect, n_desc, n_value = nlist_struct.unpack_from(data, nlist_off)
        if n_strx >= len(strtab):
            continue

        end = strtab.find(b'\0', n_strx)
        if end == -1: end = len(strtab)
        sym_name = strtab[n_strx:end].decode('latin1')

        if sym_name in renames:
            new_name = renames[sym_name].encode('latin1') + b'\0'
            new_offset = len(new_strtab)
            new_strtab.extend(new_name)
            struct.pack_into('<I', data, nlist_off, new_offset)

    if len(new_strtab) != strsize:
        # Update string table in data
        old_end = stroff + strsize
        data[stroff:old_end] = new_strtab
        new_strsize = len(new_strtab)
        struct.pack_into('<I', data, symtab_offset + 20, new_strsize)

    with open(filepath, 'wb') as f:
        f.write(data)

if __name__ == '__main__':
    renames = {}
    files = []
    i = 1
    while i < len(sys.argv):
        arg = sys.argv[i]
        if arg == '--redefine-sym' and i + 1 < len(sys.argv):
            old, new = sys.argv[i + 1].split('=')
            renames[old] = new
            i += 2
        elif arg.startswith('--redefine-sym='):
            old, new = arg.split('=', 1)[1].split('=')
            renames[old] = new
            i += 1
        else:
            files.append(arg)
            i += 1

    for f in files:
        if os.path.isfile(f) and f.endswith('.o'):
            rename_symbols_in_macho(f, renames)
