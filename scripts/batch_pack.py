"""批量打包脚本：遍历怪物目录，将每个序列帧子目录打包为 sprite sheet，删除原 PNG"""

import sys
import os
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from sprite_packer import pack_sprites

# 这些目录名不参与打包（独立零件，非动画序列帧）
SKIP_DIRS = {"组成元件", "其他", "公共元件", "特效元件"}


def should_skip(path: Path) -> bool:
    """判断是否应跳过该目录"""
    for p in path.parts:
        if p in SKIP_DIRS:
            return True
    return False


def batch_pack(root_dir: str, dry_run: bool = True):
    root = Path(root_dir)
    all_targets = []
    already_packed = []

    for d in sorted(root.rglob("*")):
        if not d.is_dir():
            continue
        if should_skip(d):
            continue

        # 过滤掉之前可能生成的 sprite.png
        pngs = sorted(f for f in d.glob("*.png") if f.name != "sprite.png")
        if len(pngs) < 2:
            continue

        # 检查是否已经打包过
        if (d / "sprite.json").exists():
            already_packed.append((d, pngs))
            continue

        all_targets.append((d, pngs))

    total_new = sum(len(p[1]) for p in all_targets)
    total_old = sum(len(p[1]) for p in already_packed)

    print(f"待打包: {len(all_targets)} 个目录, {total_new} 帧")
    if already_packed:
        print(f"已打包(跳过): {len(already_packed)} 个目录, {total_old} 帧")
    print(f"模式: {'DRY RUN (预览)' if dry_run else '*** 正式执行 ***'}")
    print("-" * 60)

    if dry_run:
        for d, pngs in all_targets:
            rel = d.relative_to(root)
            print(f"  {rel}  ({len(pngs)} frames)")
        print("-" * 60)
        print(f"\n确认无误后运行:")
        print(f'  python3 "{__file__}" --execute')
        return

    # === 正式执行 ===
    ok, fail, deleted = 0, 0, 0
    for d, pngs in all_targets:
        rel = d.relative_to(root)
        print(f"  {rel}  ({len(pngs)} frames)", end=" ", flush=True)

        try:
            pack_sprites(str(d))
            # 删除原始 PNG
            for p in pngs:
                p.unlink()
            deleted += len(pngs)
            ok += 1
            print("[OK]")
        except Exception as e:
            fail += 1
            print(f"[FAIL] {e}")

    print("-" * 60)
    print(f"打包完成: {ok} 成功, {fail} 失败, 删除 {deleted} 张原图")

    if already_packed:
        print(f"跳过已打包: {len(already_packed)} 个目录")


if __name__ == "__main__":
    root = "D:/DreamMake/assets/extracted/classified/zmxiyou1/怪物"
    dry = "--execute" not in sys.argv
    batch_pack(root, dry_run=dry)
