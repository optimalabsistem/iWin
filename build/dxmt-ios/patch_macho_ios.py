#!/usr/bin/env python3
import struct
import sys
import os

def patch_macho_to_ios(filepath):
    try:
        with open(filepath, "r+b") as f:
            data = bytearray(f.read())
            if len(data) < 32:
                return False
            magic = struct.unpack_from("<I", data, 0)[0]
            if magic != 0xfeedfacf: # MH_MAGIC_64
                return False
            ncmds = struct.unpack_from("<I", data, 16)[0]
            offset = 32 # mach_header_64 size
            patched = False
            for _ in range(ncmds):
                if offset + 8 > len(data):
                    break
                cmd, cmdsize = struct.unpack_from("<II", data, offset)
                if cmd == 0x32: # LC_BUILD_VERSION
                    platform = struct.unpack_from("<I", data, offset + 8)[0]
                    if platform != 2: # not iOS
                        struct.pack_into("<I", data, offset + 8, 2) # PLATFORM_IOS
                        struct.pack_into("<I", data, offset + 12, (17 << 16)) # minos 17.0.0
                        struct.pack_into("<I", data, offset + 16, (17 << 16)) # sdk 17.0.0
                        patched = True
                elif cmd == 0x24: # LC_VERSION_MIN_MACOSX
                    struct.pack_into("<I", data, offset, 0x25) # LC_VERSION_MIN_IPHONEOS
                    struct.pack_into("<I", data, offset + 8, (17 << 16))
                    struct.pack_into("<I", data, offset + 12, (17 << 16))
                    patched = True
                offset += cmdsize
            if patched:
                f.seek(0)
                f.write(data)
                f.truncate()
                return True
    except Exception as e:
        print(f"Error patching {filepath}: {e}", file=sys.stderr)
    return False

def main():
    if len(sys.argv) < 2:
        print("Usage: patch_macho_ios.py <dir_or_file> ...")
        sys.exit(1)
    
    count = 0
    for target in sys.argv[1:]:
        if os.path.isdir(target):
            for root, _, files in os.walk(target):
                for file in files:
                    if file.endswith(".o"):
                        p = os.path.join(root, file)
                        if patch_macho_to_ios(p):
                            count += 1
        elif os.path.isfile(target):
            if patch_macho_to_ios(target):
                count += 1
    print(f"Successfully patched {count} object files to iOS platform.")

if __name__ == "__main__":
    main()
