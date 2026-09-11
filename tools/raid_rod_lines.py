# -*- coding: utf-8 -*-
"""보스레이드 1인칭 낚싯대 그림에서 '낚싯대 끝 너머로 늘어진 줄'만 지운다 (2026-09-11)
원본: tools/raid_rod_orig/*.png (한 번만 복사) → 결과: assets/images/*.png
줄은 게임이 낚싯대 끝에서 수면까지 직접 긋는다(ui_boss_raid.dart kRaidRodTip).
"""
import cv2, numpy as np, os, json
from PIL import Image
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ORIG = os.path.join(ROOT, 'tools', 'raid_rod_orig'); OUT = os.path.join(ROOT, 'assets', 'images')
# 자동으로 못 찾는 그림은 손으로(그림 픽셀 좌표 1024×559). hand_rod_2 는 번개가 줄 역할이라 지우지 않고 번개 끝에서 잇는다.
MANUAL = {'hand_rod_raid_2': None}
tips = {}
def save(bgra, path):
    # 원본처럼 팔레트 PNG 로(용량 유지 — 그냥 저장하면 3~4배 커진다)
    rgba = Image.fromarray(cv2.cvtColor(bgra, cv2.COLOR_BGRA2RGBA))
    rgba.quantize(colors=256, method=Image.Quantize.FASTOCTREE).save(path, optimize=True)

for a in ('waiting', 'hand_rod'):
    for t in (1, 2, 3):
        name = f'{a}_raid_{t}'
        im = cv2.imdecode(np.fromfile(os.path.join(ORIG, name + '.png'), np.uint8), cv2.IMREAD_UNCHANGED)
        al = im[..., 3]
        if name in MANUAL:
            ys, xs = np.where(al[:300] > 40)                  # 번개가 뻗은 가장 오른쪽 끝
            k = np.argmax(xs); tips[name] = (int(xs[k]), int(ys[k]))
            continue                                            # 손대지 않은 원본 그대로 둔다
        solid = (al > 200).astype(np.uint8)
        thick = cv2.morphologyEx(solid, cv2.MORPH_OPEN, np.ones((5, 5), np.uint8))
        n, lab, st, _ = cv2.connectedComponentsWithStats(thick, 8)
        body = lab == (np.argmax(st[1:, cv2.CC_STAT_AREA]) + 1)
        ys, xs = np.where(body); k = np.argmax(xs - 0.35 * ys)
        tx, ty = int(xs[k]), int(ys[k]); tips[name] = (tx, ty)
        near = cv2.dilate(body.astype(np.uint8), np.ones((9, 9), np.uint8)) > 0
        yy, xx = np.mgrid[0:al.shape[0], 0:al.shape[1]]
        kill = (al > 0) & ~near & (xx >= tx - 4) & (yy >= ty - 6)
        out = im.copy(); out[..., 3][kill] = 0
        # 지운 뒤 남은 그림에서 다시 끝점을 잡는다(가는 낚싯대 끝까지)
        ys2, xs2 = np.where(out[..., 3] > 120); k2 = np.argmax(xs2 - 0.35 * ys2)
        tips[name] = (int(xs2[k2]), int(ys2[k2]))
        save(out, os.path.join(OUT, name + '.png'))
print(json.dumps(tips))
