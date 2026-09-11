# -*- coding: utf-8 -*-
# 발테리아(일반 크래프트) 판타지 존 낚시 흐름 영상 — 대기실 → 입질대기 → 당기기 (2026-09-11)
import cv2, numpy as np, os, sys
from PIL import Image, ImageDraw, ImageFont
BASE = os.path.expanduser('~') + r'/Desktop/게임 자료실/2차 업데이트/'
CUT = BASE + '사용장면_발테리아 크래프트/'
FOLDER = {**{i: '대기' for i in range(0, 51)}, **{i: '캐스팅' for i in range(51, 72)},
          **{i: '웨이팅' for i in range(72, 119)}, **{i: '릴링' for i in range(120, 239)}}
W, H, FPS = 1920, 1080, 24
K = 0.675                                   # 캐릭터 크기(1480×1080 → 999×729)
CW, CH = int(1480 * K), int(1080 * K)
FONT = ImageFont.truetype(r'C:\Windows\Fonts\malgunbd.ttf', 96)

def raw(i):
    return cv2.imdecode(np.fromfile(f'{CUT}{FOLDER[i]}/f{i:03d}.png', np.uint8), cv2.IMREAD_UNCHANGED)

def trace(c):
    # 잘린 왼쪽 끝에서 줄을 따라 들어가 굵어지는 곳(낚싯대)에서 멈춘다 → 그 점이 줄이 시작되는 낚싯대 끝
    a = c[..., 3]; lum = c[..., :3].max(2); on = (a > 50) & (lum > 35)
    col = np.where(on[:, 2])[0]
    if not len(col): return None
    y = col.mean(); pts = [(2, y)]; miss = 0
    for x in range(3, 1480):
        lo = max(int(y - 6), 0); ys = np.where(on[lo:int(y + 7), x])[0]
        if len(np.where(on[max(int(y - 25), 0):int(y + 26), x])[0]) > 14: break
        if len(ys) == 0:
            miss += 1
            if miss > 15: break
            continue
        miss = 0; y = ys.mean() + lo; pts.append((x, y))
    return pts

TIP = {}
for i in list(range(72, 119)) + list(range(120, 239)):
    p = trace(raw(i))
    if p and len(p) > 10: TIP[i] = p
def tip_smooth(i):
    near = [TIP[j][-1] for j in range(i - 2, i + 3) if j in TIP and (j < 119) == (i < 119)]
    return np.mean(near, axis=0) if near else None

_cache = {}
def src(i):
    if i not in _cache:
        if len(_cache) > 40: _cache.clear()
        c = raw(i)
        if i in TIP:                                   # 영상 속 줄을 지운다(새로 그을 것)
            c = c.copy(); tx = TIP[i][-1][0]
            for x, y in TIP[i]:
                if x < tx - 2: c[max(int(y) - 4, 0):int(y) + 5, int(x), 3] = 0
        c = cv2.resize(c, (CW, CH), interpolation=cv2.INTER_AREA).astype(np.float32)
        c[..., :3] *= c[..., 3:4] / 255.0                  # premultiplied
        _cache[i] = c
    return _cache[i]

# 줄이 잘린 자리(원본 1480 기준 왼쪽 끝)의 높이·기울기 — 시간축으로 부드럽게
line = {}
for i in range(70, 239):
    if i == 119: continue
    c = cv2.imdecode(np.fromfile(f'{CUT}{FOLDER[i]}/f{i:03d}.png', np.uint8), cv2.IMREAD_UNCHANGED)
    a = c[..., 3]; lum = c[..., :3].max(2); pts = []
    for x in range(0, 80):
        ys = np.where((a[:, x] > 60) & (lum[:, x] > 50))[0]
        if len(ys): pts.append((x, ys.mean()))
    if len(pts) > 20:
        xs, ys = np.array(pts).T; k, b = np.polyfit(xs, ys, 1); line[i] = (b, k)
keys = sorted(line)
sm = {}
for i in keys:
    near = [line[j] for j in keys if abs(j - i) <= 2 and (j < 119) == (i < 119)]
    sm[i] = tuple(np.mean(near, axis=0))

def loop(s, e, C):
    n = e - s + 1; out = []
    for i in range(C, n):
        if i >= n - C: out.append((s + i, s + i - (n - C), (i - (n - C) + 1) / (C + 1)))
        else: out.append((s + i, None, 0))
    return out

# 영상은 반복 이음매를 섞지 않는다(움직임 큰 당기기에서 두 겹으로 보였다).
# 원본 순서대로 흘리고, 길이가 모자란 대기실·입질대기만 앞뒤로 되감아 늘린다(되감기는 티가 안 난다).
def seq(*spans):
    out = []
    for s, e in spans:
        step = 1 if e >= s else -1
        out += [(i, None, 0) for i in range(s, e + step, step)]
    return out
TL = [(f, '대기실') for f in seq((0, 50), (49, 30), (31, 50))] +      [(f, '입질대기') for f in seq((51, 118), (117, 95), (96, 118))] +      [(f, '당기기') for f in seq((120, 238))]

def render(name, bgfile, flip, cx, cy, anchor, lc=(225, 225, 232), rc=(235, 240, 255)):
    bg = cv2.imdecode(np.fromfile(BASE + bgfile, np.uint8), cv2.IMREAD_COLOR)
    h0, w0 = bg.shape[:2]; tw = int(h0 * 16 / 9); x0 = (w0 - tw) // 2
    bg = cv2.resize(bg[:, x0:x0 + tw], (W, H), interpolation=cv2.INTER_AREA).astype(np.float32)
    out = BASE + f'영상_{name}.mp4'
    vw = cv2.VideoWriter(out, cv2.VideoWriter_fourcc(*'mp4v'), FPS, (W, H))
    N = len(TL); prev_cap = None; cap_t0 = 0
    for fi, ((a, b, t), cap) in enumerate(TL):
        c = src(a) if b is None else src(a) * (1 - t) + src(b) * t
        if flip: c = c[:, ::-1]
        frame = bg.copy()
        # 줄 — 입질대기·당기기는 낚싯대 끝에서 물속 고정점까지(낚싯대가 움직여도 줄 끝은 제자리)
        tp = tip_smooth(a) if a in TIP else None
        if tp is not None:
            tx, ty = tp
            p0 = np.array([cx + (1480 - tx) * K if flip else cx + tx * K, cy + ty * K]); p1 = np.array(anchor, float)
            ov = frame.copy()
            cv2.line(ov, tuple(np.round(p0).astype(int)), tuple(np.round(p1).astype(int)), lc, 2, cv2.LINE_AA)
            # 줄이 물에 닿는 곳 파문 두 겹(1.5초 주기)
            for k2 in (0, 0.5):
                ph = ((fi / 36.0) + k2) % 1.0
                rx, ry = int(8 + 42 * ph), int(3 + 13 * ph)
                cv2.ellipse(ov, tuple(p1.astype(int)), (rx, ry), 0, 0, 360, rc, 2, cv2.LINE_AA)
            frame = frame * 0.25 + ov * 0.75
        elif a in sm:                                   # 캐스팅 막바지: 날아가는 줄은 뻗어 그림
            yb, k = sm[a]
            if flip: p0 = np.array([cx + CW, cy + yb * K]); d = np.array([1.0, -k])
            else:    p0 = np.array([cx, cy + yb * K]);      d = np.array([-1.0, -k])
            d /= np.linalg.norm(d); p1 = p0 + d * 300; ov = frame.copy()
            cv2.line(ov, tuple(np.round(p0).astype(int)), tuple(np.round(p1).astype(int)), lc, 2, cv2.LINE_AA)
            frame = frame * 0.25 + ov * 0.75
        # 캐릭터 얹기
        y1, x1 = int(cy), int(cx); reg = frame[y1:y1 + CH, x1:x1 + CW]
        cc = c[:reg.shape[0], :reg.shape[1]]
        reg[:] = cc[..., :3] + reg * (1 - cc[..., 3:4] / 255.0)
        # 자막(오른쪽 위, 바뀔 때 0.3초 페이드)
        if cap != prev_cap: prev_cap, cap_t0 = cap, fi
        alpha = min(1.0, (fi - cap_t0 + 1) / 7)
        img = Image.fromarray(np.clip(frame, 0, 255).astype(np.uint8)[..., ::-1])
        lay = Image.new('RGBA', img.size, (0, 0, 0, 0)); d2 = ImageDraw.Draw(lay)
        tw_ = d2.textlength(cap, font=FONT); X, Y = W - 90 - tw_, 70
        d2.text((X + 4, Y + 5), cap, font=FONT, fill=(0, 0, 0, int(120 * alpha)))       # 그림자
        d2.text((X, Y), cap, font=FONT, fill=(255, 255, 255, int(255 * alpha)),
                stroke_width=5, stroke_fill=(20, 20, 28, int(230 * alpha)))                # 밝은 배경에서도 읽히게
        img = Image.alpha_composite(img.convert('RGBA'), lay).convert('RGB')
        f = np.array(img)[..., ::-1].astype(np.float32)
        # 처음·끝 페이드
        g = min(1.0, (fi + 1) / 12, (N - fi) / 18)
        vw.write(np.clip(f * g, 0, 255).astype(np.uint8))
    vw.release()
    print(name, N, 'frames', round(N / FPS, 1), 's →', out, round(os.path.getsize(out) / 1e6, 1), 'MB')

which = sys.argv[1:] or ['galaxy', 'mureung']
if 'galaxy' in which:
    render('은하수바다_발테리아', '성운의 은하수 바다.jpg', True, 0.05 * W, H - CH - 174 * 1.5, (1480, 720))
if 'mureung' in which:
    render('무릉도원_발테리아', '무릉도원.png', False, 0.93 * W - CW, H - CH - 195 * 1.5, (600, 880), lc=(62, 60, 58), rc=(90, 110, 115))  # 먹색 줄(흰 안개 위)
