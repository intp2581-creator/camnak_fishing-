# -*- coding: utf-8 -*-
"""8월 랭킹전 추첨 — 9/1 코스피 종가를 넣으면 당첨자 10명이 나온다.
   사용법:  python 문서/추첨계산.py 2734.56
"""
import io, re, sys

names = []
for ln in io.open("문서/이벤트_8월랭킹전_추첨명단_공개용.txt", encoding="utf-8"):
    m = re.match(r"\s*(\d+)\.\s+(\S.*?)\s*$", ln)
    if m and int(m.group(1)) <= 200:
        names.append(m.group(2))
N = len(names)

close = sys.argv[1] if len(sys.argv) > 1 else input("9/1 코스피 종가 (예 2734.56): ")
seed = int(re.sub(r"\D", "", close))          # 소수점·쉼표 제거
start = seed % N + 1

print("모집단 %d명 / 시드 %d / 시작번호 %d\n" % (N, seed, start))
cur, won = start, []
for i in range(10):
    won.append(cur)
    print("%2d등  %3d번  %s" % (i + 1, cur, names[cur - 1]))
    cur = cur + 7
    if cur > N:
        cur -= N
assert len(set(won)) == 10, "중복 발생 — 확인 필요"
print("\n검증: 번호 순서 " + " → ".join(map(str, won)))
