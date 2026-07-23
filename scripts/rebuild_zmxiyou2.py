"""Rebuild ZMX2 monsters from ffdec-exported sprite frames with correct labels."""
import json, re, math, struct, zlib, shutil
from pathlib import Path
from PIL import Image
Image.MAX_IMAGE_PIXELS = None

# === Step 1: Extract frame labels from decoded SWFs (SymbolClass + FrameLabel) ===
def parse_swf(filepath):
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
    labels = {}; names = {}
    while pos < len(data) - 6:
        tag_code_and_len = struct.unpack_from('<H', data, pos)[0]
        tag_code = tag_code_and_len >> 6
        tag_len = tag_code_and_len & 0x3F
        pos += 2
        if tag_len == 0x3F:
            tag_len = struct.unpack_from('<I', data, pos)[0]; pos += 4
        if pos + tag_len > len(data): break
        tag_data = data[pos:pos + tag_len]; pos += tag_len
        if tag_code in (39, 87):
            char_id = struct.unpack_from('<H', tag_data, 0)[0]
            frame_count = struct.unpack_from('<H', tag_data, 2)[0]
            tp, fn = 4, 0; fl = {}
            while tp < len(tag_data) and fn < frame_count:
                sc = struct.unpack_from('<H', tag_data, tp)[0]
                st = sc >> 6; sl = sc & 0x3F; tp += 2
                if sl == 0x3F: sl = struct.unpack_from('<I', tag_data, tp)[0]; tp += 4
                if tp + sl > len(tag_data): break
                sd = tag_data[tp:tp + sl]; tp += sl
                if st == 1: fn += 1
                elif st == 43: fl[fn] = sd[1:].rstrip(b'\x00').decode('latin-1')
            if fl: labels[char_id] = {'frames': frame_count, 'labels': dict(sorted(fl.items()))}
        elif tag_code == 76:
            ns = struct.unpack_from('<H', tag_data, 0)[0]; sp = 2
            for _ in range(ns):
                cid = struct.unpack_from('<H', tag_data, sp)[0]; sp += 2
                np = tag_data.find(b'\x00', sp)
                names[cid] = tag_data[sp:np].decode('latin-1'); sp = np + 1
        if tag_code == 0: break
    return labels, names

FIX = {'ait': 'wait', 'alk': 'walk', 'urt': 'hurt', 'ead': 'dead',
       'it1': 'hit1', 'it2': 'hit2', 'it3': 'hit3', 'it4': 'hit4', 'it5': 'hit5',
       'it6': 'hit6', 'it7': 'hit7', 'it1-1': 'hit1-1', 'it2-1': 'hit2-1',
       'it2-2': 'hit2-2', 'it2-3': 'hit2-3', 'it2-4': 'hit2-4',
       'it3-1': 'hit3-1', 'it3-2': 'hit3-2',
       'eburn': 'reburn', 'enshen': 'shenfen', 'all': 'fall', 'un': 'run', 'eady': 'ready'}

monster_labels = {}
for swf in sorted(Path('sources/decoded/zmxiyou2').glob('*.swf')):
    labels, names = parse_swf(str(swf))
    for cid, name in names.items():
        m = re.search(r'Monster(\d+)', name)
        if m and cid in labels:
            mon_num = int(m.group(1))
            lbls = labels[cid]['labels']
            fixed = {f: FIX.get(l, l) for f, l in lbls.items()}
            monster_labels[mon_num] = {'swf': swf.name, 'symbol_id': cid,
                'name': name, 'frames': labels[cid]['frames'], 'labels': fixed}

ACTION_MAP = {'walk': 'walk', 'wait': 'idle', 'hurt': 'hurt', 'dead': 'death',
    'hit1': 'attack1', 'hit2': 'attack2', 'hit3': 'attack3', 'hit4': 'attack4', 'hit5': 'attack5',
    'hit6': 'attack6', 'hit7': 'attack7',
    'hit1-1': 'attack1a', 'hit2-1': 'attack2a', 'hit2-2': 'attack2b',
    'hit2-3': 'attack2c', 'hit2-4': 'attack2d', 'hit3-1': 'attack3a', 'hit3-2': 'attack3b',
    'reburn': 'reburn', 'fall': 'fall', 'run': 'run', 'ready': 'ready', 'shenfen': 'shenfen'}

# === Step 2: Copy ffdec frames to classified, pack, trim ===
EXPORT = Path('.tools/temp_zmxiyou2_export')
BASE = Path('assets/extracted/classified/zmxiyou2/怪物')
SELECTED = Path('assets/selected/zmxiyou2/monsters')
if SELECTED.exists(): shutil.rmtree(SELECTED)
SELECTED.mkdir(parents=True)

# Build export lookup: find sprite dir by monster number in class name
export_map = {}
for swf_dir in sorted(EXPORT.iterdir()):
    if not swf_dir.is_dir(): continue
    for sprite_dir in sorted(swf_dir.iterdir()):
        if not sprite_dir.is_dir(): continue
        m = re.search(r'Monster(\d+)', sprite_dir.name)
        if m:
            mon_num = int(m.group(1))
            export_map[mon_num] = sprite_dir

print(f'Export map: {len(export_map)} monsters')

configs = {}
for mdir in sorted(BASE.iterdir()):
    if not mdir.is_dir(): continue
    mname = mdir.name
    mm = re.search(r'M(\d+)', mname)
    if not mm: continue
    mon_num = int(mm.group(1))

    if mon_num not in monster_labels or mon_num not in export_map:
        print(f'  SKIP {mname}: no labels or no export')
        continue

    info = monster_labels[mon_num]
    labels = info['labels']
    src_dir = export_map[mon_num]

    # Clean existing dir contents
    for old in list(mdir.iterdir()):
        if old.is_dir(): shutil.rmtree(old)
        else: old.unlink()

    # Copy frames to body/
    body_dir = mdir / 'body'
    body_dir.mkdir()
    pngs = sorted(src_dir.glob('*.png'))
    for i, png in enumerate(pngs):
        shutil.copy2(str(png), str(body_dir / f'frame_{i+1:03d}.png'))

    # Pack
    from sprite_packer import pack_sprites
    pack_sprites(str(body_dir))

    # Read sprite sheet
    sf = body_dir / 'sprite.png'
    jf = body_dir / 'sprite.json'
    if not sf.exists() or not jf.exists(): continue
    with open(jf) as f:
        meta = json.load(f)

    actual = meta['meta']['frameCount']
    img = Image.open(sf)
    fw = meta['meta']['frameSize']['w']
    fh = meta['meta']['frameSize']['h']
    cols = meta['meta']['columns']

    # Build action ranges from labels
    sorted_labels = sorted(labels.items())
    actions = {}
    for i, (fn, label) in enumerate(sorted_labels):
        start, end = fn, (sorted_labels[i+1][0] - 1 if i+1 < len(sorted_labels) else actual - 1)
        if start >= actual: continue
        end = min(end, actual - 1)
        if end - start < 1: continue
        gd = ACTION_MAP.get(label, label.replace('-', '_'))
        actions[gd] = (start, end)

    # Split frames into per-action sprite sheets
    new_actions = {}
    for gd, (start, end) in actions.items():
        nf = end - start + 1
        frames = []
        for fi in range(start, end + 1):
            r, c = divmod(fi, cols)
            frames.append(img.crop((c * fw, r * fh, c * fw + fw, r * fh + fh)))

        new_cols = math.ceil(math.sqrt(nf))
        new_rows = math.ceil(nf / new_cols)
        ns = Image.new('RGBA', (new_cols * fw, new_rows * fh), (0, 0, 0, 0))
        nm = {}
        for i, frame in enumerate(frames):
            nr, nc = divmod(i, new_cols)
            nx, ny = nc * fw, nr * fh
            ns.paste(frame, (nx, ny), frame if frame.mode == 'RGBA' else None)
            nm[f'{gd}_{i+1:03d}'] = {'x': nx, 'y': ny, 'w': fw, 'h': fh}

        ad = mdir / gd; ad.mkdir(exist_ok=True)
        ns.save(ad / 'sprite.png', optimize=True)
        with open(ad / 'sprite.json', 'w', encoding='utf-8') as f:
            json.dump({'frames': nm, 'meta': {'image': 'sprite.png',
                'size': {'w': new_cols*fw, 'h': new_rows*fh}, 'frameSize': {'w': fw, 'h': fh},
                'columns': new_cols, 'rows': new_rows, 'frameCount': nf}}, f, ensure_ascii=False, indent=2)

        # Also extract individual frames for Godot
        safe = re.sub(r'[^\w]', '_', mname).lower()
        if safe[0].isdigit(): safe = 'm' + safe
        od = SELECTED / safe / gd; od.mkdir(parents=True)
        for fi, frame in enumerate(frames):
            frame.save(od / f'frame_{fi+1:03d}.png')

        new_actions[gd] = nf

    try: shutil.rmtree(body_dir)
    except PermissionError: pass
    configs[mname] = {'sname': safe, 'actions': new_actions}
    print(f'  OK {mname} (M{mon_num}): {actual}fr -> {list(new_actions.keys())}')

with open('.tools/zmxiyou2_monster_configs.json', 'w', encoding='utf-8') as f:
    json.dump(configs, f, ensure_ascii=False, indent=2)
print(f'\nRebuilt {len(configs)} monsters')
total = sum(sum(a.values()) for a in (c["actions"] for c in configs.values())); print(f"Total extracted frames: {total}")
