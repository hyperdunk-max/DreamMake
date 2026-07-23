"""Fix ZMX2: use SymbolClass names for exact monster-to-label matching."""
import json, re, struct, zlib, math, shutil
from pathlib import Path
from PIL import Image
Image.MAX_IMAGE_PIXELS = None

# === Step 1: Extract correct labels with symbol names ===
def parse_swf_symbols(filepath):
    with open(filepath, 'rb') as f:
        data = f.read()
    if data[0:3] not in (b'FWS', b'CWS'): return {}, {}
    compressed = data[0] == ord('C')
    if compressed:
        data = data[:8] + zlib.decompress(data[8:])
    pos = 8
    nbits = (data[pos] >> 3) & 0x1f
    pos += (5 + nbits * 4 + 7) // 8
    pos += 4
    labels = {}
    symbol_names = {}
    while pos < len(data) - 6:
        tag_code_and_len = struct.unpack_from('<H', data, pos)[0]
        tag_code = tag_code_and_len >> 6
        tag_len = tag_code_and_len & 0x3F
        pos += 2
        if tag_len == 0x3F:
            tag_len = struct.unpack_from('<I', data, pos)[0]
            pos += 4
        if pos + tag_len > len(data): break
        tag_data = data[pos:pos + tag_len]
        pos += tag_len
        if tag_code in (39, 87):
            char_id = struct.unpack_from('<H', tag_data, 0)[0]
            frame_count = struct.unpack_from('<H', tag_data, 2)[0]
            tag_pos = 4
            frame_num = 0
            frame_labels = {}
            while tag_pos < len(tag_data) and frame_num < frame_count:
                sub_code_and_len = struct.unpack_from('<H', tag_data, tag_pos)[0]
                sub_code = sub_code_and_len >> 6
                sub_len = sub_code_and_len & 0x3F
                tag_pos += 2
                if sub_len == 0x3F:
                    sub_len = struct.unpack_from('<I', tag_data, tag_pos)[0]
                    tag_pos += 4
                if tag_pos + sub_len > len(tag_data): break
                sub_data = tag_data[tag_pos:tag_pos + sub_len]
                tag_pos += sub_len
                if sub_code == 1:
                    frame_num += 1
                elif sub_code == 43:
                    label_str = sub_data[1:].rstrip(b'\x00').decode('latin-1')
                    frame_labels[frame_num] = label_str
            if frame_labels:
                labels[char_id] = {'frames': frame_count, 'labels': dict(sorted(frame_labels.items()))}
        elif tag_code == 76:
            num_symbols = struct.unpack_from('<H', tag_data, 0)[0]
            sp = 2
            for _ in range(num_symbols):
                char_id = struct.unpack_from('<H', tag_data, sp)[0]
                sp += 2
                null_pos = tag_data.find(b'\x00', sp)
                name = tag_data[sp:null_pos].decode('latin-1')
                sp = null_pos + 1
                symbol_names[char_id] = name
        if tag_code == 0: break
    return labels, symbol_names

# Build monster number -> {swf, symbol_id, labels} mapping
all_labels = {}
for swf in sorted(Path('sources/decoded/zmxiyou2').glob('*.swf')):
    labels, names = parse_swf_symbols(str(swf))
    for char_id, name in names.items():
        m = re.search(r'Monster(\d+)', name)
        if m and char_id in labels:
            mon_num = int(m.group(1))
            all_labels[mon_num] = {
                'swf': swf.name,
                'symbol_id': char_id,
                'symbol_name': name,
                'frames': labels[char_id]['frames'],
                'labels': labels[char_id]['labels'],
            }

# Fix truncated labels
FIX = {
    'ait': 'wait', 'alk': 'walk', 'urt': 'hurt', 'ead': 'dead',
    'it1': 'hit1', 'it2': 'hit2', 'it3': 'hit3', 'it4': 'hit4', 'it5': 'hit5',
    'it6': 'hit6', 'it7': 'hit7',
    'it1-1': 'hit1-1', 'it2-1': 'hit2-1', 'it2-2': 'hit2-2',
    'it2-3': 'hit2-3', 'it2-4': 'hit2-4',
    'it3-1': 'hit3-1', 'it3-2': 'hit3-2',
    'eburn': 'reburn', 'enshen': 'shenfen', 'all': 'fall', 'un': 'run', 'eady': 'ready',
}

print(f'Found {len(all_labels)} monster symbol mappings')
for mon_num in sorted(all_labels):
    info = all_labels[mon_num]
    labels = info['labels']
    fixed = {frame: FIX.get(lbl, lbl) for frame, lbl in labels.items()}
    info['fixed_labels'] = fixed
    info2 = all_labels[mon_num]; print("  Monster{}: {}::{} {}fr labels={}".format(mon_num, info2["swf"], info2["symbol_id"], info2["frames"], list(fixed.values())))

# === Step 2: Match classified monster dirs to Monster numbers ===
BASE = Path('assets/extracted/classified/zmxiyou2/怪物')
CLASSIFIED_MAP = {}  # dir_name -> monster_number
for mdir in sorted(BASE.iterdir()):
    if not mdir.is_dir(): continue
    m = re.search(r'M(\d+)', mdir.name)
    if m:
        mon_num = int(m.group(1))
        CLASSIFIED_MAP[mdir.name] = mon_num

print(f'\nClassified dirs: {len(CLASSIFIED_MAP)}')

# === Step 3: Regenerate per-action sprite sheets with correct labels ===
ACTION_MAP = {
    'walk': 'walk', 'wait': 'idle', 'hurt': 'hurt', 'dead': 'death',
    'hit1': 'attack1', 'hit2': 'attack2', 'hit3': 'attack3',
    'hit4': 'attack4', 'hit5': 'attack5', 'hit6': 'attack6', 'hit7': 'attack7',
    'hit1-1': 'attack1a', 'hit2-1': 'attack2a', 'hit2-2': 'attack2b',
    'hit2-3': 'attack2c', 'hit2-4': 'attack2d',
    'hit3-1': 'attack3a', 'hit3-2': 'attack3b',
    'reburn': 'reburn', 'fall': 'fall', 'run': 'run', 'ready': 'ready',
    'shenfen': 'shenfen', 'fixed': 'fixed',
}

SELECTED = Path('assets/selected/zmxiyou2/monsters')
if SELECTED.exists():
    shutil.rmtree(SELECTED)
SELECTED.mkdir(parents=True)

MONSTER_CONFIGS = {}
fixed_count = 0

for mdir_name, mon_num in sorted(CLASSIFIED_MAP.items()):
    if mon_num not in all_labels:
        print(f'  SKIP {mdir_name}: Monster{mon_num} not in SWF labels')
        continue

    info = all_labels[mon_num]
    labels = info['fixed_labels']

    # Read the original body sprite sheet
    body_dir = BASE / mdir_name / 'body'
    if not body_dir.is_dir():
        # Check if already split (from previous wrong run)
        # Delete old per-action dirs
        for old_action in sorted(BASE.glob(f'{mdir_name}/*')):
            if old_action.is_dir() and old_action.name != 'body':
                shutil.rmtree(old_action)
        # Need to repack from original sprites? They should still be in selected/
        # Actually, body dir was deleted. Let's check selected/ for the unsplit version
        print(f'  WARN {mdir_name}: body dir missing, checking selected...')
        continue

    sf = body_dir / 'sprite.png'
    jf = body_dir / 'sprite.json'
    if not sf.exists() or not jf.exists():
        print(f'  SKIP {mdir_name}: no body sprite sheet')
        continue

    with open(jf) as f:
        meta = json.load(f)

    actual_frames = meta['meta']['frameCount']
    label_frames = info['frames']

    if actual_frames != label_frames:
        print(f'  MISMATCH {mdir_name}: sprite={actual_frames}fr, SWF label={label_frames}fr')

    img = Image.open(sf)
    fw = meta['meta']['frameSize']['w']
    fh = meta['meta']['frameSize']['h']
    cols = meta['meta']['columns']

    # Build frame ranges from labels
    sorted_labels = sorted(labels.items())  # [(frame_num, label_name), ...]
    actions = {}

    for i, (frame_num, label) in enumerate(sorted_labels):
        start = frame_num
        end = sorted_labels[i+1][0] - 1 if i+1 < len(sorted_labels) else actual_frames - 1
        if end >= actual_frames:
            end = actual_frames - 1
        if start >= actual_frames:
            continue
        if end - start < 1:
            continue  # Skip single-frame transitions

        gd_action = ACTION_MAP.get(label, label)
        actions[gd_action] = (start, end)

    # Split frames and create per-action sprite sheets
    safe_name = re.sub(r'[^\w]', '_', mdir_name).lower()
    if safe_name[0].isdigit(): safe_name = 'm' + safe_name
    new_actions = {}

    for gd_action, (start, end) in actions.items():
        frame_count = end - start + 1

        frames = []
        for fi in range(start, end + 1):
            row, col = divmod(fi, cols)
            x, y = col * fw, row * fh
            frames.append(img.crop((x, y, x + fw, y + fh)))

        if len(frames) < 2:
            continue

        # Pack into sprite sheet
        new_cols = math.ceil(math.sqrt(len(frames)))
        new_rows = math.ceil(len(frames) / new_cols)
        new_sheet = Image.new('RGBA', (new_cols * fw, new_rows * fh), (0, 0, 0, 0))
        new_frames_meta = {}

        for i, frame in enumerate(frames):
            nr, nc = divmod(i, new_cols)
            nx, ny = nc * fw, nr * fh
            new_sheet.paste(frame, (nx, ny), frame if frame.mode == 'RGBA' else None)
            new_frames_meta[f'{gd_action}_{i+1:03d}'] = {'x': nx, 'y': ny, 'w': fw, 'h': fh}

        action_dir = BASE / mdir_name / gd_action
        action_dir.mkdir(exist_ok=True)
        new_sheet.save(action_dir / 'sprite.png', optimize=True)

        new_meta = {
            'frames': new_frames_meta,
            'meta': {'image': 'sprite.png', 'size': {'w': new_cols*fw, 'h': new_rows*fh},
                     'frameSize': {'w': fw, 'h': fh}, 'columns': new_cols, 'rows': new_rows,
                     'frameCount': len(frames)},
        }
        with open(action_dir / 'sprite.json', 'w', encoding='utf-8') as f:
            json.dump(new_meta, f, ensure_ascii=False, indent=2)

        # Extract for Godot
        out_dir = SELECTED / safe_name / gd_action
        out_dir.mkdir(parents=True, exist_ok=True)
        for fi in range(len(frames)):
            frames[fi].save(out_dir / f'frame_{fi+1:03d}.png')

        new_actions[gd_action] = len(frames)

    # Delete old body dir
    shutil.rmtree(body_dir)

    MONSTER_CONFIGS[mdir_name] = {'sname': safe_name, 'actions': new_actions}
    fixed_count += 1
    print(f'  OK {mdir_name} (Monster{mon_num}): {list(new_actions.keys())}')

print(f'\nFixed {fixed_count} monsters with correct labels')

with open('.tools/zmxiyou2_monster_configs.json', 'w', encoding='utf-8') as f:
    json.dump(MONSTER_CONFIGS, f, ensure_ascii=False, indent=2)
print('Config saved')
