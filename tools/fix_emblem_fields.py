# -*- coding: utf-8 -*-
"""
🎖️ 선물함으로 받아 필드가 빠진 엠블럼을 채운다 (cash·price·active).

create_gift.py 의 item_emblem() 에 price·cash·active 가 빠져 있어,
그 선물을 받은 엠블럼만 '유료 아이템'으로 분류되지 않았다.
관리자 회수 목록에서 일반 장비들 사이로 밀려나 찾기 어렵다.
(게임 사용·판매 잠금에는 지장 없다 — type=EVENT 로 막고 있다)

사용법:
    python tools/fix_emblem_fields.py            # 미리보기
    python tools/fix_emblem_fields.py --apply    # 실제 수정

⚠️ 접속 중인 유저가 있을 수 있으므로 조건부 쓰기(updateTime)로 안전하게.
"""
import io
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request

BASE = ("https://firestore.googleapis.com/v1/projects/camnak-fishing"
        "/databases/(default)/documents")
APPLY = "--apply" in sys.argv


def token():
    cfg = json.load(io.open(os.path.join(os.path.expanduser("~"), ".config",
                                         "configstore", "firebase-tools.json"),
                            encoding="utf-8"))
    d = urllib.parse.urlencode({
        "client_id": ("563584335869-fgrhgmd47bqnekij5i8b5pr03ho849e6"
                      ".apps.googleusercontent.com"),
        "client_secret": "j9iVZfS8kkCEFUPaAeJV0sAi",
        "refresh_token": cfg["tokens"]["refresh_token"],
        "grant_type": "refresh_token"}).encode()
    return json.load(urllib.request.urlopen(
        "https://www.googleapis.com/oauth2/v4/token", d))["access_token"]


def call(url, tok, data=None, method="GET"):
    r = urllib.request.Request(url, data=data, method=method)
    r.add_header("Authorization", "Bearer " + tok)
    if data:
        r.add_header("Content-Type", "application/json")
    return json.load(urllib.request.urlopen(r))


def val(f, k):
    x = f.get(k)
    return list(x.values())[0] if x else None


tok = token()
page, targets = None, []
while True:
    j = call(BASE + "/users?pageSize=300" + ("&pageToken=" + page if page else ""), tok)
    for d in j.get("documents", []):
        fl = d.get("fields", {})
        inv = fl.get("inventory", {}).get("arrayValue", {}).get("values", [])
        hits = []
        for i, v in enumerate(inv):
            m = v.get("mapValue", {}).get("fields", {})
            if val(m, "type") != "EVENT" or "secLeft" not in m:
                continue
            if "cash" in m and "active" in m and "price" in m:
                continue
            hits.append(i)
        if hits:
            targets.append((d, hits))
    page = j.get("nextPageToken")
    if not page:
        break

if not targets:
    print("고칠 엠블럼이 없습니다.")
    sys.exit(0)

total = sum(len(h) for _, h in targets)
print("고칠 대상 : %d명 · 엠블럼 %d개" % (len(targets), total))
for d, hits in targets:
    nick = val(d["fields"], "nickname") or "(닉없음)"
    print("   %-14s %d개" % (nick, len(hits)))
print("모드 : " + ("실제 수정" if APPLY else "미리보기(아무것도 안 바꿈)"))

if not APPLY:
    print()
    print("실제로 고치려면 --apply 를 붙여 다시 실행하세요.")
    sys.exit(0)

ok = fail = 0
for d, hits in targets:
    uid = d["name"].split("/")[-1]
    nick = val(d["fields"], "nickname") or "(닉없음)"
    inv = list(d["fields"].get("inventory", {}).get("arrayValue", {}).get("values", []))
    for i in hits:
        mf = dict(inv[i]["mapValue"]["fields"])
        mf.setdefault("cash", {"booleanValue": True})
        mf.setdefault("price", {"integerValue": "0"})
        # active 가 없으면 '아직 안 켠 것' — 켜져 있었다면 이미 값이 있다.
        mf.setdefault("active", {"booleanValue": False})
        inv[i] = {"mapValue": {"fields": mf}}
    body = {"fields": {"inventory": {"arrayValue": {"values": inv}}}}
    url = (BASE + "/users/" + uid + "?updateMask.fieldPaths=inventory"
           "&currentDocument.updateTime=" + urllib.parse.quote(d["updateTime"]))
    try:
        call(url, tok, json.dumps(body).encode("utf-8"), "PATCH")
        print("   ✅ %s" % nick)
        ok += 1
    except urllib.error.HTTPError as e:
        if e.code == 400:
            print("   ⚠️ %s — 읽는 사이에 가방이 바뀌었습니다. 다시 실행해 주세요." % nick)
            fail += 1
        else:
            raise

print()
print("완료 — 성공 %d명 · 건너뜀 %d명" % (ok, fail))
