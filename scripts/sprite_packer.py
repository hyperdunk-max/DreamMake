"""Sprite Sheet Packer - 将序列帧 PNG 打包为 sprite sheet + JSON 坐标文件"""

import json
import math
import sys
from pathlib import Path
from PIL import Image


def pack_sprites(input_dir: str, output_path: str = None, columns: int = None):
    """将目录下所有 PNG 打包成 sprite sheet。

    Args:
        input_dir: 输入目录路径
        output_path: 输出文件前缀（不含扩展名），默认在输入目录下生成 "sprite"
        columns: 每行列数，不指定则自动算为接近正方形
    """
    in_dir = Path(input_dir)
    # Exclude previously generated sprite.png to avoid self-repacking
    frames = sorted(f for f in in_dir.glob("*.png") if f.name != "sprite.png")
    if not frames:
        print(f"目录 {input_dir} 下没有 PNG 文件")
        return

    # 读取第一张获取尺寸
    first = Image.open(frames[0])
    fw, fh = first.size
    mode = first.mode
    count = len(frames)

    if columns is None:
        columns = math.ceil(math.sqrt(count))
    rows = math.ceil(count / columns)

    sheet_w = columns * fw
    sheet_h = rows * fh

    # 输出路径
    if output_path is None:
        output_path = str(in_dir / "sprite")
    out_dir = Path(output_path).parent
    out_stem = Path(output_path).stem
    png_path = out_dir / f"{out_stem}.png"
    json_path = out_dir / f"{out_stem}.json"

    # 生成 sprite sheet
    sheet = Image.new(mode, (sheet_w, sheet_h), (0, 0, 0, 0))
    frames_meta = {}

    for i, fpath in enumerate(frames):
        row = i // columns
        col = i % columns
        x, y = col * fw, row * fh
        img = Image.open(fpath)
        # The destination is already transparent. Passing the RGBA image as
        # its own mask multiplies alpha a second time and darkens every
        # antialiased edge. A direct paste preserves the source RGBA bytes.
        sheet.paste(img, (x, y))
        img.close()

        name = fpath.stem
        frames_meta[name] = {"x": x, "y": y, "w": fw, "h": fh}

    # 保存
    sheet.save(png_path, optimize=True)
    meta = {
        "frames": frames_meta,
        "meta": {
            "image": f"{out_stem}.png",
            "size": {"w": sheet_w, "h": sheet_h},
            "frameSize": {"w": fw, "h": fh},
            "columns": columns,
            "rows": rows,
            "frameCount": count,
        },
    }
    with open(json_path, "w", encoding="utf-8") as f:
        json.dump(meta, f, ensure_ascii=False, indent=2)

    print(f"[OK] Done!")
    print(f"  Input:  {count} frames ({fw}x{fh}, {mode})")
    print(f"  Layout: {columns}x{rows}")
    print(f"  Sprite: {png_path} ({sheet_w}x{sheet_h})")
    print(f"  Meta:   {json_path}")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("用法: python sprite_packer.py <输入目录> [输出前缀] [列数]")
        print("示例: python sprite_packer.py ./frames ./output/sprite 6")
        sys.exit(1)

    input_dir = sys.argv[1]
    output = sys.argv[2] if len(sys.argv) > 2 else None
    cols = int(sys.argv[3]) if len(sys.argv) > 3 else None
    pack_sprites(input_dir, output_path=output, columns=cols)
