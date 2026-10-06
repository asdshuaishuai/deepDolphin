#!/usr/bin/env python3
"""bmp2png.py —— 无依赖的 BMP→PNG 转换（本机没有 PIL/ImageMagick/sips）。

CUI 的 --snapshot 落的是 BMP（24/32bpp，自底向上 BGR 行序）；
Read 工具与人眼审查吃 PNG。用法：
    python3 scripts/bmp2png.py <in.bmp> <out.png>
只支持常见的未压缩 BMP（BI_RGB），覆盖 SDL 的输出就够。
"""
import struct
import sys
import zlib
from pathlib import Path


def bmp_to_png(src: str, dst: str) -> None:
    data = Path(src).read_bytes()
    if data[:2] != b"BM":
        raise SystemExit(f"{src}: 不是 BMP（magic={data[:2]!r}）")
    pixel_offset = struct.unpack_from("<I", data, 10)[0]
    header_size = struct.unpack_from("<I", data, 14)[0]
    if header_size < 40:
        raise SystemExit(f"{src}: 不支持的 BMP 头（{header_size}）")
    w, h = struct.unpack_from("<ii", data, 18)
    planes, bpp = struct.unpack_from("<HH", data, 26)
    compression = struct.unpack_from("<I", data, 30)[0]
    if compression != 0 or bpp not in (24, 32):
        raise SystemExit(f"{src}: 只支持未压缩 24/32bpp（bpp={bpp}, comp={compression}）")
    top_down = h < 0
    h = abs(h)
    row_raw = ((w * bpp + 31) // 32) * 4  # 行按 4 字节对齐

    # 解出 RGB 行（自底向上 → 翻成自顶向下）
    rows = []
    for y in range(h):
        src_y = (h - 1 - y) if not top_down else y
        base = pixel_offset + src_y * row_raw
        row = bytearray()
        for x in range(w):
            o = base + x * (bpp // 8)
            b, g, r = data[o], data[o + 1], data[o + 2]
            row += bytes((r, g, b))
        rows.append(bytes(row))

    def chunk(tag: bytes, payload: bytes) -> bytes:
        return (
            struct.pack(">I", len(payload))
            + tag
            + payload
            + struct.pack(">I", zlib.crc32(tag + payload) & 0xFFFFFFFF)
        )

    ihdr = struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)  # 8bit truecolor
    raw = b"".join(b"\x00" + row for row in rows)  # 每行 filter 0
    png = (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", ihdr)
        + chunk(b"IDAT", zlib.compress(raw, 6))
        + chunk(b"IEND", b"")
    )
    Path(dst).write_bytes(png)
    print(f"✓ {src} → {dst}（{w}x{h}）")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        raise SystemExit(__doc__)
    bmp_to_png(sys.argv[1], sys.argv[2])
