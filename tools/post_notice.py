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
    "type": "devlog",
    "title": "2차 업데이트 예고 — FANTASY KREFT",
    "body": "[page:devlog-s2.html]",
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
