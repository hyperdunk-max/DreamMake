"""Extract frame labels from SWF DefineSprite tags."""
import struct, sys, os
from pathlib import Path
from collections import defaultdict

def read_swf_labels(filepath):
    """Parse SWF binary and extract DefineSprite frame labels."""
    with open(filepath, 'rb') as f:
        data = f.read()

    # SWF header: signature (3), version (1), file_length (4)
    if data[0:3] not in (b'FWS', b'CWS'):
        return {}

    compressed = data[0] == ord('C')
    if compressed:
        import zlib
        # Skip 8-byte header + 4-byte decompressed size
        data = data[:8] + zlib.decompress(data[8:])

    # Read rect (variable length)
    pos = 8  # skip signature + version + file_length
    nbits = (data[pos] >> 3) & 0x1f
    pos += (5 + nbits * 4 + 7) // 8  # skip rect

    # Skip frame_rate (2) + frame_count (2)
    pos += 4

    labels = defaultdict(dict)  # character_id -> {frame_num: label}

    while pos < len(data) - 6:
        tag_code_and_len = struct.unpack_from('<H', data, pos)[0]
        tag_code = tag_code_and_len >> 6
        tag_len = tag_code_and_len & 0x3F
        pos += 2

        if tag_len == 0x3F:
            tag_len = struct.unpack_from('<I', data, pos)[0]
            pos += 4

        if pos + tag_len > len(data):
            break

        tag_data = data[pos:pos + tag_len]
        pos += tag_len

        # Tag 39 = DefineSprite
        # Tag 87 = DefineSprite (SWF 9+)
        if tag_code in (39, 87):
            char_id = struct.unpack_from('<H', tag_data, 0)[0]
            frame_count = struct.unpack_from('<H', tag_data, 2)[0]
            tag_pos = 4

            for frame_num in range(frame_count):
                # Each frame: sub_tags until ShowFrame (tag 1)
                while tag_pos < len(tag_data):
                    sub_code_and_len = struct.unpack_from('<H', tag_data, tag_pos)[0]
                    sub_code = sub_code_and_len >> 6
                    sub_len = sub_code_and_len & 0x3F
                    tag_pos += 2

                    if sub_len == 0x3F:
                        sub_len = struct.unpack_from('<I', tag_data, tag_pos)[0]
                        tag_pos += 4

                    if tag_pos + sub_len > len(tag_data):
                        break

                    sub_data = tag_data[tag_pos:tag_pos + sub_len]
                    tag_pos += sub_len

                    if sub_code == 1:  # ShowFrame
                        break
                    elif sub_code == 43:  # FrameLabel
                        # Parse null-terminated string
                        null_pos = sub_data.find(b'\x00')
                        if null_pos >= 0:
                            label = sub_data[1:null_pos].decode('utf-8', errors='replace')
                            labels[char_id][frame_num] = label

        if tag_code == 0:  # End
            break

    return dict(labels)


def analyze_monster_swf(swf_path, symbol_id=None):
    """Find frame labels for monster symbols in a SWF."""
    labels = read_swf_labels(swf_path)
    result = {}
    for char_id, frame_labels in sorted(labels.items()):
        if symbol_id and char_id != symbol_id:
            continue
        if frame_labels:
            result[char_id] = dict(sorted(frame_labels.items()))
    return result


if __name__ == '__main__':
    decoded_dir = Path("D:/DreamMake/sources/decoded/zmxiyou2")
    all_labels = {}

    for swf_file in sorted(decoded_dir.glob("*.swf")):
        labels = analyze_monster_swf(str(swf_file))
        if labels:
            print(f"\n{swf_file.name}:")
            for char_id, frames in sorted(labels.items()):
                frame_ranges = []
                for fnum, flabel in sorted(frames.items()):
                    frame_ranges.append(f"  f{fnum}: {flabel}")
                print(f"  Symbol {char_id}:")
                for r in frame_ranges:
                    print(r)
                all_labels[f"{swf_file.name}::{char_id}"] = frames

    if all_labels:
        with open("D:/DreamMake/.tools/zmxiyou2_frame_labels.json", "w", encoding="utf-8") as f:
            import json
            json.dump(all_labels, f, ensure_ascii=False, indent=2)
        print(f"\nSaved {len(all_labels)} symbol frame label sets to .tools/zmxiyou2_frame_labels.json")
    else:
        print("No frame labels found in any SWF")
