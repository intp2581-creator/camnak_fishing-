# -*- coding: utf-8 -*-
"""판타지 존 전신 캐릭터: 검은 배경 영상 프레임 → 배경 뺀 PNG (2026-09-11)

사용:  python tools/cut_frames.py "<프레임 폴더>" "<출력 폴더>" 대기:0-50 캐스팅:51-71 웨이팅:72-118 릴링:120-238
  · 프레임 폴더 = f000.png ... (영상에서 뽑은 1920×1080)
  · 출력 = 동작별 하위 폴더에 원본 번호 그대로(예: 대기/f000.png), 1480×1080 로 자름(오른쪽 워터마크 영역 제외)
규칙:
  · 밝기 40 이상 = 몸(불투명). 그 사이 막힌 틈이라도 30픽셀 넘으면 배경(낚싯대–줄 사이 틈)
  · 밝기 10~45 = 반투명(번개 빛·머리카락 끝). 10 미만은 압축 노이즈로 보고 버림
  · 오른쪽 아래 워터마크(✦) 칸은 지운다
"""
import sys, os, cv2, numpy as np

def cut(f):
    lum = f.max(2).astype(np.float32)
    core = (lum > 40).astype(np.uint8)
    core = cv2.morphologyEx(core, cv2.MORPH_CLOSE, np.ones((3, 3), np.uint8))
    n, lab, st, _ = cv2.connectedComponentsWithStats((core == 0).astype(np.uint8), 4)
    big = np.zeros(n, bool); big[1:] = st[1:, cv2.CC_STAT_AREA] > 30
    core = np.where(big[lab], 0, 1).astype(np.float32)
    a = np.maximum(core, np.clip((lum - 10) / 35, 0, 1))
    a[860:940, 1700:1780] = 0
    rgb = f.astype(np.float32)
    un = np.clip(rgb / np.maximum(a[..., None], 1e-3), 0, 255)       # 검은 배경을 뺀 색(빛 번짐 복원)
    un = np.where(core[..., None] > 0, rgb, un)
    return np.dstack([un, a * 255]).astype(np.uint8)

def main():
    src, dst, *ranges = sys.argv[1:]
    for r in ranges:
        name, span = r.split(':'); s, e = map(int, span.split('-'))
        out = os.path.join(dst, name); os.makedirs(out, exist_ok=True)
        for i in range(s, e + 1):
            f = cv2.imdecode(np.fromfile(os.path.join(src, f'f{i:03d}.png'), np.uint8), cv2.IMREAD_COLOR)
            c = cut(f)[0:1080, 0:1480]
            cv2.imencode('.png', c, [cv2.IMWRITE_PNG_COMPRESSION, 9])[1].tofile(os.path.join(out, f'f{i:03d}.png'))
        print(name, s, '~', e, '→', out)

if __name__ == '__main__':
    main()
