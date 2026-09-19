#!/usr/bin/env python3
"""把 PNG 降采样成字符画，用来在没有可视环境时检查界面布局。

背景：这个项目改的是 macOS 设置窗口，而开发环境看不到屏幕、
describe_image 又没有可用的视觉后端。于是「改完到底长什么样」一直靠猜。
本工具不依赖任何第三方库（纯 zlib 手写 PNG 解码），
把图缩小后按灰度铺成字符，布局有没有挤爆、控件有没有被裁，一眼能看出来。

用法：png_ascii.py <png> [宽字符数，默认 110]
"""
import sys, zlib, struct, subprocess, tempfile, os

RAMP = " .:-=+*#%@"


def load_png(path):
    data = open(path, 'rb').read()
    assert data[:8] == b'\x89PNG\r\n\x1a\n', '不是 PNG'
    pos, idat, plte = 8, b'', None
    w = h = bd = ct = None
    while pos < len(data):
        ln = struct.unpack('>I', data[pos:pos + 4])[0]
        typ = data[pos + 4:pos + 8]
        chunk = data[pos + 8:pos + 8 + ln]
        pos += 12 + ln
        if typ == b'IHDR':
            w, h, bd, ct, _comp, _filt, inter = struct.unpack('>IIBBBBB', chunk)
            assert bd == 8 and inter == 0, f'只支持 8 位非隔行，实际 bd={bd} inter={inter}'
        elif typ == b'IDAT':
            idat += chunk
        elif typ == b'PLTE':
            plte = chunk
        elif typ == b'IEND':
            break
    raw = zlib.decompress(idat)
    ch = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}[ct]
    stride = w * ch
    out = bytearray(h * stride)
    prev = bytearray(stride)
    p = 0
    for y in range(h):
        f = raw[p]; p += 1
        line = bytearray(raw[p:p + stride]); p += stride
        if f == 1:
            for i in range(ch, stride):
                line[i] = (line[i] + line[i - ch]) & 255
        elif f == 2:
            for i in range(stride):
                line[i] = (line[i] + prev[i]) & 255
        elif f == 3:
            for i in range(stride):
                a = line[i - ch] if i >= ch else 0
                line[i] = (line[i] + ((a + prev[i]) >> 1)) & 255
        elif f == 4:
            for i in range(stride):
                a = line[i - ch] if i >= ch else 0
                b = prev[i]
                c = prev[i - ch] if i >= ch else 0
                pp = a + b - c
                pa, pb, pc = abs(pp - a), abs(pp - b), abs(pp - c)
                pr = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                line[i] = (line[i] + pr) & 255
        out[y * stride:(y + 1) * stride] = line
        prev = line
    return w, h, ch, out, ct, plte


def load_any(path, maxdim=None):
    """读 PNG。给了 maxdim 就先交给 sips 缩小 —— 纯 python 解码 150 万像素太慢。"""
    if maxdim:
        tmp = tempfile.mktemp(suffix='.png')
        subprocess.run(['sips', '-Z', str(maxdim), path, '--out', tmp],
                       check=True, capture_output=True)
        path = tmp
    else:
        tmp = None
    res = load_png(path)
    if tmp:
        os.unlink(tmp)
    return res


def pixel(px, ch, ct, plte, w, x, y):
    """返回 (亮度, 是否不透明)。"""
    i = (y * w + x) * ch
    if ct in (4, 6) and px[i + ch - 1] < 8:
        return None
    if ct in (2, 6):
        return (px[i] * 299 + px[i + 1] * 587 + px[i + 2] * 114) // 1000
    if ct == 3:
        k = px[i] * 3
        return (plte[k] * 299 + plte[k + 1] * 587 + plte[k + 2] * 114) // 1000
    return px[i]


def row_profile(src, x0, x1, y0, y1, thresh=246):
    """逐像素行统计暗像素数。用来精确定位卡片边框线、以及内容实际占到哪里。

    这个数字回答的是「卡片底下空了多高」「标题到底压没压在边线上」这类
    光看截图说不清的问题 —— 之前靠肉眼估 rowH/chrome，估出来的高度和
    NSGridView 真实高度差了 40 多像素，卡片底部就空出一大块。
    """
    w, h, ch, px, ct, plte = load_any(src)
    print(f'{src}  {w}×{h}px   分析区 x=[{x0},{x1}) y=[{y0},{y1})')
    print('   y  暗像素  起止x      说明')
    prev_dark = False
    runs = []
    for y in range(max(0, y0), min(h, y1)):
        xs = [x for x in range(max(0, x0), min(w, x1))
              if (v := pixel(px, ch, ct, plte, w, x, y)) is not None and v < thresh]
        n = len(xs)
        dark = n > 0
        if dark and not prev_dark:
            runs.append([y, y, n, min(xs), max(xs)])
        elif dark:
            runs[-1][1] = y
            runs[-1][2] = max(runs[-1][2], n)
            runs[-1][3] = min(runs[-1][3], min(xs))
            runs[-1][4] = max(runs[-1][4], max(xs))
        prev_dark = dark
    for a, b, n, mn, mx in runs:
        span = mx - mn + 1
        # 横贯整个分析区且很薄的，几乎一定是边框线
        kind = '← 边框线' if span > (x1 - x0) * 0.75 and (b - a) <= 3 else ''
        print(f'  {a:4d}-{b:<4d} {n:6d}  {mn:4d}-{mx:<4d} {kind}')


def main():
    if len(sys.argv) < 2:
        print(__doc__); sys.exit(1)
    src = sys.argv[1]
    if len(sys.argv) > 2 and sys.argv[2] == '--rows':
        # 参数：x0 x1 y0 y1
        a = [int(v) for v in sys.argv[3:7]]
        row_profile(src, *a)
        return
    cols = int(sys.argv[2]) if len(sys.argv) > 2 else 110

    w, h, ch, px, ct, plte = load_any(src, maxdim=cols * 2)

    # 终端字符高约为宽的两倍，纵向再压一半
    rows = max(1, int(h / (w / cols) / 2))
    print(f'{src}')
    print(f'  原始 {w}×{h}px（此图为 sips 缩放后）  alpha={"有" if ct in (4, 6) else "无"}')
    print()
    for r in range(rows):
        line = []
        for c in range(cols):
            x0, x1 = c * w // cols, max(c * w // cols + 1, (c + 1) * w // cols)
            y0, y1 = r * h // rows, max(r * h // rows + 1, (r + 1) * h // rows)
            tot = n = 0
            for y in range(y0, y1):
                base = y * w * ch
                for x in range(x0, x1):
                    i = base + x * ch
                    if ct in (4, 6):
                        a = px[i + ch - 1]
                        if a < 8:
                            continue          # 全透明，不计入
                    if ct in (2, 6):
                        lum = (px[i] * 299 + px[i + 1] * 587 + px[i + 2] * 114) // 1000
                    elif ct == 3:
                        k = px[i] * 3
                        lum = (plte[k] * 299 + plte[k + 1] * 587 + plte[k + 2] * 114) // 1000
                    else:
                        lum = px[i]
                    tot += lum; n += 1
            if n == 0:
                line.append(' ')          # 全透明
            else:
                # 白底上的深色文字：越暗字符越重
                idx = int((255 - tot // n) / 255 * (len(RAMP) - 1))
                line.append(RAMP[idx])
        print(''.join(line))


if __name__ == '__main__':
    main()
