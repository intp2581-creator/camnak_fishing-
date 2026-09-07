# -*- coding: utf-8 -*-
"""
📝 공지/업데이트/개발 일지 글을 site_notices 에 올린다.

본문이 [page:파일명] 하나면 devlog.html 이 그 페이지로 넘긴다.
디자인이 센 글은 CSS 가 홈페이지 전체를 덮어써서 본문에 못 넣기 때문이다.

사용법:
    python tools/post_notice.py            # 미리보기
    python tools/post_notice.py --apply    # 실제 등록
"""
import datetime
import io
import json
import os
import sys
import urllib.parse
import urllib.request

PROJECT = "camnak-fishing"
BASE = ("https://firestore.googleapis.com/v1/projects/" + PROJECT +
        "/databases/(default)/documents")
APPLY = "--apply" in sys.argv

# ── 올릴 글 ────────────────────────────────────────────────────────
DOC = {
    "type": "update",
    "title": "9월 7일 업데이트 — 제보해 주신 문제를 고쳤습니다",
    "body": """안녕하세요, 캠피싱 KREFT입니다.

주말 사이 조사님들께서 알려주신 문제들을 확인하고 오늘 한 번에 고쳤습니다.

🐛 고친 것

· 엠블럼이 사라지던 문제
엠블럼을 두 개 이상 가지고 계실 때, 하나를 다 쓰면 남은 엠블럼까지 함께 사라졌습니다. 이제 각각 따로 인식되고, 하나를 다 쓰셔도 나머지는 그대로 남습니다.

· 아레나가 끝나면 화면이 멈추던 문제
경기가 끝난 뒤 화면이 까맣게 변하며 아무것도 보이지 않던 문제를 고쳤습니다. 지난 토요일부터 발생한 문제였습니다.

· 골라둔 미끼가 다른 미끼로 바뀌던 문제
장비가 자동으로 맞춰질 때 직접 고르신 미끼까지 함께 바뀌고 있었습니다. 이제 고르신 미끼는 그대로 유지됩니다.

· 입질이 오지 않던 문제
사투 중에 미끼가 떨어진 뒤 다시 캐스팅하면, 찌는 물에 있는데 입질이 영영 오지 않는 경우가 있었습니다.

· 그 밖에 아이템 그림이 잘못 보이던 문제, 자막이 가려지던 문제를 함께 고쳤습니다.

⏱️ 낚시 시간이 아깝지 않게

여러 조사님께서 같은 말씀을 주셨습니다. 이제 찌를 던진 뒤부터 시간이 흐릅니다.

장비를 맞추고 미끼를 고르는 시간은 차감되지 않습니다
미끼가 떨어져 상점에 다녀오시는 시간도 차감되지 않습니다
낚시 중 전화가 오거나 다른 앱으로 넘어가시면 자동으로 멈춥니다

다만 낚시중 찌를 던져두신 채로 가방이나 상점을 여실 때는 입질이 계속 오기 때문에 시간이 흐릅니다.

✂️ 줄 끊기

가망이 없다 싶을 때 줄을 끊고 빠져나올 수 있습니다. 사투가 10초 이상 진행되면 게이지 아래에 버튼이 나타납니다.
더 일찍 끊고 싶으시면 기존 방식대로 당기기 버튼을 풀림으로 밀고 계셔도 됩니다.

⚓ 바닥걸림

챔질했을 때 물고기가 아니라 바닥이 걸리는 일이 생깁니다. 게이지가 가운데 멈추고, 줄을 끊어야 벗어날 수 있습니다. 던지고 감는 낚시일수록 더 잘 걸립니다.

🎣 루어·에기는 이제 닳지 않습니다

루어·에기·스푼·웜·플라이는 먹는 미끼가 아니라 채비입니다. 물고기를 잡아도 그대로 있습니다. 줄이 터지거나 바닥에 걸렸을 때만 잃습니다.

🧵 낚싯줄

가방에서 남은 길이(m)가 바로 보입니다. 얼마 안 남으면 색이 바뀝니다
「일반 낚싯줄」을 새로 준비했습니다. 능력치는 없지만 저렴하고, 민물·바다 어디서나 쓸 수 있습니다
선물함에 하나 넣어두었으니 꼭 받아 가세요

🎁 선물함에 보상을 넣어두었습니다

불편을 드린 점 사과드리며 작은 보상을 준비했습니다.

일반 낚싯줄 · 능력치 엠블럼 1개 · 경험치 물약 3개 · KREFT 2배 카드 3장

홈페이지 「선물함」에서 받기를 눌러주세요. 9월 14일까지입니다.

알려주신 덕분에 빠르게 바로잡을 수 있었습니다.

앞으로도 불편한 점은 고객지원 → 1:1 문의로 알려주세요.

조사님들과 함께 만들어가는 캠피싱이 되겠습니다.

감사합니다. 🎣""",
    "author": "캠피싱",
    "date": datetime.datetime.now().strftime("%Y-%m-%d"),
    "pinned": True,
    "published": True,
    "views": 0,
}


def token():
    cfg = json.load(io.open(os.path.join(os.path.expanduser("~"), ".config",
                                         "configstore", "firebase-tools.json"),
                            encoding="utf-8"))
    data = urllib.parse.urlencode({
        "client_id": "563584335869-fgrhgmd47bqnekij5i8b5pr03ho849e6.apps.googleusercontent.com",
        "client_secret": "j9iVZfS8kkCEFUPaAeJV0sAi",
        "refresh_token": cfg["tokens"]["refresh_token"],
        "grant_type": "refresh_token"}).encode()
    return json.load(urllib.request.urlopen(
        "https://www.googleapis.com/oauth2/v4/token", data))["access_token"]


def call(url, tok, data=None, method="GET"):
    r = urllib.request.Request(url, data=data, method=method)
    r.add_header("Authorization", "Bearer " + tok)
    if data:
        r.add_header("Content-Type", "application/json")
    return json.load(urllib.request.urlopen(r))


def sv(x):
    if isinstance(x, bool): return {"booleanValue": x}
    if isinstance(x, int):  return {"integerValue": str(x)}
    if isinstance(x, str):  return {"stringValue": x}
    raise TypeError(str(type(x)))


tok = token()

# 같은 제목이 이미 있으면 두 번 올리지 않는다.
j = call(BASE + "/site_notices?pageSize=100", tok)
for d in j.get("documents", []):
    if d.get("fields", {}).get("title", {}).get("stringValue") == DOC["title"]:
        print("이미 올라와 있습니다: " + d["name"].split("/")[-1])
        sys.exit(0)

print("종류 : " + DOC["type"])
print("제목 : " + DOC["title"])
print("본문 : " + DOC["body"])
print("상단 고정 : " + ("예" if DOC["pinned"] else "아니오"))
print("모드 : " + ("실제 등록" if APPLY else "미리보기(아무것도 안 바꿈)"))

if not APPLY:
    sys.exit(0)

fields = {k: sv(v) for k, v in DOC.items()}
fields["createdAt"] = {"timestampValue":
                       datetime.datetime.now(datetime.timezone.utc)
                       .strftime("%Y-%m-%dT%H:%M:%SZ")}
res = call(BASE + "/site_notices", tok,
           json.dumps({"fields": fields}).encode("utf-8"), "POST")
nid = res["name"].split("/")[-1]
print("")
print("등록 완료  id=" + nid)
print("https://kreft.co.kr/devlog.html?id=" + nid)
