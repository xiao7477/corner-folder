#!/usr/bin/env python3
import math
import os
import struct
import sys
import zlib


def write_png(path, width, height, pixels):
    raw = bytearray()
    for y in range(height):
        raw.append(0)
        row = pixels[y * width:(y + 1) * width]
        for r, g, b, a in row:
            raw.extend([r, g, b, a])

    def chunk(kind, data):
        body = kind + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)

    data = b"\x89PNG\r\n\x1a\n"
    data += chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
    data += chunk(b"IDAT", zlib.compress(bytes(raw), 9))
    data += chunk(b"IEND", b"")
    with open(path, "wb") as handle:
        handle.write(data)


def rounded_rect_alpha(x, y, left, top, right, bottom, radius):
    if x < left or x > right or y < top or y > bottom:
        return 0.0
    cx = min(max(x, left + radius), right - radius)
    cy = min(max(y, top + radius), bottom - radius)
    dist = math.hypot(x - cx, y - cy)
    return max(0.0, min(1.0, radius + 1.0 - dist))


def blend(dst, src):
    dr, dg, db, da = dst
    sr, sg, sb, sa = src
    a = sa / 255.0
    inv = 1.0 - a
    return (
        int(sr * a + dr * inv),
        int(sg * a + dg * inv),
        int(sb * a + db * inv),
        int(min(255, sa + da * inv)),
    )


def icon(size):
    pixels = [(0, 0, 0, 0)] * (size * size)
    for y in range(size):
        for x in range(size):
            u = x / max(1, size - 1)
            v = y / max(1, size - 1)
            base_alpha = rounded_rect_alpha(x, y, size * 0.08, size * 0.08, size * 0.92, size * 0.92, size * 0.2)
            if base_alpha <= 0:
                continue
            r = int(28 + 36 * u)
            g = int(38 + 78 * (1 - v))
            b = int(78 + 120 * u)
            pixels[y * size + x] = (r, g, b, int(255 * base_alpha))

    folder_top = (size * 0.22, size * 0.31, size * 0.47, size * 0.42)
    folder_body = (size * 0.18, size * 0.38, size * 0.82, size * 0.72)
    for y in range(size):
        for x in range(size):
            alpha_top = rounded_rect_alpha(x, y, *folder_top, size * 0.04)
            alpha_body = rounded_rect_alpha(x, y, *folder_body, size * 0.08)
            alpha = max(alpha_top, alpha_body)
            if alpha <= 0:
                continue
            u = x / max(1, size - 1)
            v = y / max(1, size - 1)
            color = (70 + int(45 * u), 187 + int(34 * (1 - v)), 238, int(255 * alpha))
            pixels[y * size + x] = blend(pixels[y * size + x], color)

    # Side shelf mark.
    for y in range(int(size * 0.28), int(size * 0.76)):
        for x in range(int(size * 0.72), int(size * 0.79)):
            alpha = rounded_rect_alpha(x, y, size * 0.72, size * 0.28, size * 0.79, size * 0.76, size * 0.035)
            if alpha > 0:
                pixels[y * size + x] = blend(pixels[y * size + x], (255, 255, 255, int(210 * alpha)))

    return pixels


def main():
    if len(sys.argv) != 2:
        raise SystemExit("usage: create_icon.py ICONSET_DIR")

    out_dir = sys.argv[1]
    os.makedirs(out_dir, exist_ok=True)
    targets = [
        ("icon_16x16.png", 16),
        ("icon_16x16@2x.png", 32),
        ("icon_32x32.png", 32),
        ("icon_32x32@2x.png", 64),
        ("icon_128x128.png", 128),
        ("icon_128x128@2x.png", 256),
        ("icon_256x256.png", 256),
        ("icon_256x256@2x.png", 512),
        ("icon_512x512.png", 512),
        ("icon_512x512@2x.png", 1024),
    ]
    for name, size in targets:
        write_png(os.path.join(out_dir, name), size, size, icon(size))


if __name__ == "__main__":
    main()
