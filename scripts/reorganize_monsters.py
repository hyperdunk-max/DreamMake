"""整理怪物素材目录层级：去完整时间轴中间层、扁平化、清理空目录"""

import shutil
from pathlib import Path

BASE = Path("D:/DreamMake/assets/extracted/classified/zmxiyou1/怪物")

def reorganize():
    stats = {"flattened": 0, "single_merged": 0, "empty_deleted": 0, "parts_renamed": 0}

    for monster_dir in sorted(BASE.iterdir()):
        if not monster_dir.is_dir():
            continue

        for action_dir in sorted(monster_dir.iterdir()):
            if not action_dir.is_dir():
                continue

            # === Step 1: Flatten 完整时间轴 ===
            tl_dir = action_dir / "完整时间轴"
            if tl_dir.is_dir():
                elements = [d for d in tl_dir.iterdir() if d.is_dir()]
                for elem in elements:
                    dest = action_dir / elem.name
                    if not dest.exists():
                        shutil.move(str(elem), str(dest))
                        stats["flattened"] += 1
                # Remove empty 完整时间轴
                if not any(tl_dir.iterdir()):
                    tl_dir.rmdir()

            # === Step 2: Single-element action → merge up ===
            subdirs = [d for d in action_dir.iterdir() if d.is_dir()]
            files = [f for f in action_dir.iterdir() if f.is_file()]
            if len(subdirs) == 1 and not files:
                elem = subdirs[0]
                # Move contents up
                for item in elem.iterdir():
                    shutil.move(str(item), str(action_dir / item.name))
                elem.rmdir()
                stats["single_merged"] += 1

            # === Step 3: Delete empty action dirs ===
            if not any(action_dir.iterdir()):
                action_dir.rmdir()
                stats["empty_deleted"] += 1

        # === Step 4: Rename 组成元件/其他 → parts ===
        parts_dir = monster_dir / "组成元件" / "其他"
        target = monster_dir / "parts"
        if parts_dir.is_dir():
            # Move contents of 其他 to parts/
            target.mkdir(exist_ok=True)
            for item in parts_dir.iterdir():
                shutil.move(str(item), str(target / item.name))
            # Clean up
            parts_dir.rmdir()
            parent = parts_dir.parent  # 组成元件
            if not any(parent.iterdir()):
                parent.rmdir()
            stats["parts_renamed"] += 1

        # Also handle 特效/组成元件/其他 → effects/parts
        fx_dir = monster_dir / "特效" / "组成元件" / "其他"
        fx_target = monster_dir / "特效" / "parts"
        if fx_dir.is_dir():
            fx_target.mkdir(parents=True, exist_ok=True)
            for item in fx_dir.iterdir():
                shutil.move(str(item), str(fx_target / item.name))
            fx_dir.rmdir()
            mid = fx_dir.parent  # 特效/组成元件
            if not any(mid.iterdir()):
                mid.rmdir()

    # === Step 5: Also handle top-level 公共特效/组成元件/其他 ===
    for fx_other in BASE.rglob("组成元件/其他"):
        if fx_other.is_dir() and fx_other.parent.name == "组成元件":
            target = fx_other.parent.parent / "parts"
            target.mkdir(exist_ok=True)
            for item in fx_other.iterdir():
                shutil.move(str(item), str(target / item.name))
            fx_other.rmdir()
            parent = fx_other.parent
            if not any(parent.iterdir()):
                parent.rmdir()

    print("=== 整理完成 ===")
    print(f"Flatten 完整时间轴: {stats['flattened']} elements")
    print(f"单元件合并:        {stats['single_merged']} actions")
    print(f"删除空目录:        {stats['empty_deleted']} dirs")
    print(f"Parts 重命名:      {stats['parts_renamed']} monsters")

    # Show final structure stats
    files = list(BASE.rglob("*"))
    pngs = [f for f in files if f.suffix == ".png"]
    jsons = [f for f in files if f.suffix == ".json"]
    svgs = [f for f in files if f.suffix == ".svg"]
    dirs = [f for f in files if f.is_dir()]
    print(f"\n最终: {len(dirs)} dirs, {len(pngs)} PNGs, {len(jsons)} JSONs, {len(svgs)} SVGs")


if __name__ == "__main__":
    reorganize()
