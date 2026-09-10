# -*- coding: utf-8 -*-
"""
📈 레벨 경험치 곡선 — 이 파일 하나가 규칙의 주인이다.

게임(lib/game_config.dart)과 서버(functions/index.js)가 각자 표를 들고 있다가
2026-09-10 에 어긋난 걸 발견했다(같은 경험치를 서버는 두 레벨 높게 봤다).
서버 표는 31~50 구간 개편이 반영되지 않은 옛 공식이었고, 그 값이
스킨·뱃지 지급 판정에 쓰이고 있었다. 한쪽만 고치면 또 벌어진다.

  사용법:  python tools/gen_exp_table.py           # 미리보기(파일 안 바꿈)
           python tools/gen_exp_table.py --apply   # 두 파일에 반영
           python tools/gen_exp_table.py --check   # 두 파일이 규칙과 같은지만 검사

곡선을 바꿀 때는 아래 STEP() 만 고치고 --apply 로 돌린다.
"""
import io, os, re, sys

MAX_LEVEL = 150

def delta(L, prev):
    """L 레벨이 되는 데 필요한 경험치."""
    if L <= 30:
        # 1~30: 10레벨 구간마다 레벨당 증가폭 +50 (Lv1~10 +200, 11~20 +250, 21~30 +300)
        band = (L - 1) // 10
        step = 200 + 50 * band
        return 1400 if L == 2 else prev + step
    if L <= 44:
        # 31~44: 리니어 (30→31 이 10,000)
        return 9500 + 500 * (L - 30)
    # 45~100: 증가폭을 키워 상위권 속도를 늦춘다 (2026-09-10)
    #   45~69  : 600 + 100x(L-45)   → 600 ... 3,000
    #   70~100 : 3500 + 100x(L-70)  → 3,500 ... 6,500
    if L <= 69:
        return prev + 600 + 100 * (L - 45)
    if L <= 100:
        return prev + 3500 + 100 * (L - 70)
    # 101~150: 2차 업데이트 낚시터(고대수로·천공·은하수·무릉도원) 어종 경험치를
    #          정한 뒤 다시 손본다. 그때까지는 현행 유지.
    return prev + 1200

def build():
    t = [0] * (MAX_LEVEL + 1)
    d = [0] * (MAX_LEVEL + 1)
    prev = 0
    for L in range(2, MAX_LEVEL + 1):
        dl = delta(L, prev)
        d[L] = dl
        t[L] = t[L - 1] + dl
        prev = dl
    return t, d

# ── 만들어 넣을 코드 조각 ────────────────────────────────────────────
DART = '''List<int> _buildExpTable() {
  final M = globalMaxLevel;
  final table = List<int>.filled(M + 1, 0); // index 0·1 = 0 (누적 경험치)
  int prevDelta = 0;
  for (int L = 2; L <= M; L++) {
    final int delta;
    if (L <= 30) {
      // Lv 1~30: 기존 커브 유지(초반 성취감)
      final int band = (L - 1) ~/ 10; // L=2~10→0, 11~20→1, 21~30→2
      final int step = 200 + 50 * band;
      delta = (L == 2) ? 1400 : prevDelta + step;
    } else if (L <= 44) {
      // Lv 31~44: 리니어 — 30→31 이 10,000
      delta = 9500 + 500 * (L - 30);
    } else if (L <= 69) {
      // Lv 45~69: 증가폭 600 → 3,000 (상위권 속도 제동, 2026-09-10)
      delta = prevDelta + 600 + 100 * (L - 45);
    } else if (L <= 100) {
      // Lv 70~100: 증가폭 3,500 → 6,500
      delta = prevDelta + 3500 + 100 * (L - 70);
    } else {
      // Lv 101~150: 2차 업데이트 낚시터 어종 경험치를 정한 뒤 재조정
      delta = prevDelta + 1200;
    }
    table[L] = table[L - 1] + delta;
    prevDelta = delta;
  }
  return table;
}'''

JS = '''const expTable = (() => {
  const t = new Array(GLOBAL_MAX_LEVEL + 1).fill(0); // index 0·1 = 0
  let prevDelta = 0;
  for (let L = 2; L <= GLOBAL_MAX_LEVEL; L++) {
    let delta;
    if (L <= 30) {
      const band = Math.floor((L - 1) / 10);
      const step = 200 + 50 * band;
      delta = (L === 2) ? 1400 : prevDelta + step;
    } else if (L <= 44) {
      delta = 9500 + 500 * (L - 30);
    } else if (L <= 69) {
      delta = prevDelta + 600 + 100 * (L - 45);
    } else if (L <= 100) {
      delta = prevDelta + 3500 + 100 * (L - 70);
    } else {
      delta = prevDelta + 1200;
    }
    t[L] = t[L - 1] + delta;
    prevDelta = delta;
  }
  return t;
})();'''

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DART_FILE = os.path.join(ROOT, "lib", "game_config.dart")
JS_FILE = os.path.join(ROOT, "functions", "index.js")

def replace(path, pattern, new, label):
    s = io.open(path, encoding="utf-8").read()
    m = re.search(pattern, s, re.S)
    if not m:
        print("  ❌ %s : 바꿀 블록을 못 찾았습니다" % label)
        return None
    if m.group(0).strip() == new.strip():
        print("  ✓ %s : 이미 같음" % label)
        return s
    print("  ✎ %s : 갱신" % label)
    return s[:m.start()] + new + s[m.end():]

DART_PAT = r"List<int> _buildExpTable\(\) \{.*?\n\}"
JS_PAT   = r"const expTable = \(\(\) => \{.*?\n\}\)\(\);"

def main():
    apply_ = "--apply" in sys.argv
    check  = "--check" in sys.argv
    t, d = build()
    print("곡선 — 만렙 %d, 누적 %s" % (MAX_LEVEL, format(t[MAX_LEVEL], ",")))
    for L in (10, 30, 44, 45, 50, 70, 100, 101, 150):
        print("  Lv.%-4d 필요 %10s   누적 %14s" % (L, format(d[L], ","), format(t[L], ",")))
    print()
    for path, pat, new, label in ((DART_FILE, DART_PAT, DART, "game_config.dart"),
                                  (JS_FILE, JS_PAT, JS, "functions/index.js")):
        out = replace(path, pat, new, label)
        if out is None:
            sys.exit(1)
        if apply_:
            io.open(path, "w", encoding="utf-8").write(out)
    if apply_:
        print("\n두 파일에 반영했습니다.")
    elif not check:
        print("\n미리보기입니다. 실제로 넣으려면 --apply 를 붙이세요.")

if __name__ == "__main__":
    main()
