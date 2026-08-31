# -*- coding: utf-8 -*-
"""8월 랭킹전 추첨 — 9/1 코스피 종가를 넣으면 당첨자 10명이 나온다.
   사용법:  python 문서/추첨계산.py 2734.56
   규칙: 시작=시드%N+1, 이후 +7. 1~3위 수상자 번호는 건너뛴다."""
import io, re, sys

TOP3 = ["낚시의왕", "아레투사", "빨강테리"]      # 지정 상품 수상자 = 추첨 제외

names = []
for ln in io.open("문서/이벤트_8월랭킹전_추첨명단_공개용.txt", encoding="utf-8"):
    m = re.match(r"\s*(\d+)\.\s+(\S.*?)\s*$", ln)
    if m and int(m.group(1)) <= 300:
        names.append(m.group(2))
N = len(names)

close = sys.argv[1] if len(sys.argv) > 1 else input("9/1 코스피 종가 (예 2734.56): ")
seed = int(re.sub(r"\D", "", close))
start = seed % N + 1

print("명단 %d명 / 시드 %d / 시작번호 %d\n" % (N, seed, start))
cur, won, skipped = start, [], []
while len(won) < 10:
    if names[cur - 1] in TOP3:
        skipped.append("%d번 %s" % (cur, names[cur - 1]))
    else:
        won.append(cur)
        print("%2d  %3d번  %s" % (len(won), cur, names[cur - 1]))
    cur += 7
    if cur > N:
        cur -= N
if skipped:
    print("\n건너뜀(1~3위): " + ", ".join(skipped))
print("\n검증용 번호 순서: " + " → ".join(map(str, won)))
