from PIL import Image, ImageDraw

N = 32
OUT = (13, 10, 26, 255)
BG = (20, 32, 79)


def h(c):
    c = c.lstrip('#')
    return tuple(int(c[i:i + 2], 16) for i in (0, 2, 4)) + (255,)


class C:
    def __init__(self):
        self.im = Image.new('RGBA', (N, N), (0, 0, 0, 0))
        self.d = ImageDraw.Draw(self.im)
        self.fx = []  # pixels drawn after outline (sparkles, glow)

    def p(self, x, y, c):
        if 0 <= x < N and 0 <= y < N:
            self.im.putpixel((x, y), h(c))

    def ps(self, x, y, c):  # symmetric
        self.p(x, y, c); self.p(31 - x, y, c)

    def pts(self, lst, c, sym=False):
        for x, y in lst:
            (self.ps if sym else self.p)(x, y, c)

    def rect(self, x0, y0, x1, y1, c, sym=False):
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                (self.ps if sym else self.p)(x, y, c)

    def line(self, pts, c, w=1):
        self.d.line(pts, fill=h(c), width=w)

    def poly(self, pts, c, sym=False):
        self.d.polygon(pts, fill=h(c))
        if sym:
            self.d.polygon([(31 - x, y) for x, y in pts], fill=h(c))

    def ell(self, cx, cy, rx, ry, c, sh=None, d=1.3, lt=None):
        def inside(px, py):
            return ((px - cx) / rx) ** 2 + ((py - cy) / ry) ** 2 <= 1
        for y in range(N):
            for x in range(N):
                if inside(x + .5, y + .5):
                    col = c
                    if sh and not inside(x + .5 + d, y + .5 + d):
                        col = sh
                    elif lt and not inside(x + .5 - d, y + .5 - d):
                        col = lt
                    self.p(x, y, col)

    def ring(self, cx, cy, rx, ry, c, t=1.0):
        for y in range(N):
            for x in range(N):
                v = ((x + .5 - cx) / rx) ** 2 + ((y + .5 - cy) / ry) ** 2
                vi = ((x + .5 - cx) / max(rx - t, .1)) ** 2 + ((y + .5 - cy) / max(ry - t, .1)) ** 2
                if v <= 1 and vi > 1:
                    self.p(x, y, c)

    def eyes(self, y, x=12, c='#1a1020', w=2, hgt=2, shine=True):
        self.rect(x, y, x + w - 1, y + hgt - 1, c, sym=True)
        if shine:
            self.ps(x, y, '#ffffff')

    def glow(self, x, y, c):
        self.fx.append((x, y, h(c)))


def render(fn, accent, path):
    c = C()
    fn(c)
    im = c.im
    a = im.split()[3]
    out = Image.new('RGBA', (N, N), (0, 0, 0, 0))
    for y in range(N):
        for x in range(N):
            if a.getpixel((x, y)) == 0:
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    xx, yy = x + dx, y + dy
                    if 0 <= xx < N and 0 <= yy < N and a.getpixel((xx, yy)) > 0:
                        out.putpixel((x, y), OUT)
                        break
    out.alpha_composite(im)
    # fond : bleu nuit + halo pixel de la couleur d'accent
    ac = h(accent)
    bg = Image.new('RGBA', (N, N), BG + (255,))
    for y in range(N):
        for x in range(N):
            r = ((x + .5 - 16) ** 2 + (y + .5 - 14) ** 2) ** .5
            k = .34 if r < 11 else .2 if r < 14 else 0
            if k:
                bg.putpixel((x, y), tuple(int(BG[i] * (1 - k) + ac[i] * k) for i in range(3)) + (255,))
    bg.alpha_composite(out)
    for x, y, col in c.fx:
        bg.putpixel((x, y), col)
    bg.convert('RGB').resize((128, 128), Image.NEAREST).save(path, 'WEBP', lossless=True)
    return bg
