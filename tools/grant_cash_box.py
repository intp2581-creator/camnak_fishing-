# -*- coding: utf-8 -*-
"""
📦 착용 아이템 상자 지급 — 결제로 지급되는 것과 똑같은 모양으로 넣는다.

결제를 거치지 않고 테스트하거나, 민원으로 재지급할 때 쓴다.
functions/payment.js 의 PRODUCTS 와 같은 구성이라 실제 구매와 결과가 같다.

사용법:
    python tools/grant_cash_box.py --nick 아레투사 --item badge_1
    python tools/grant_cash_box.py --nick 아레투사 --item badge_1 --apply
    python tools/grant_cash_box.py --list           # 지급 가능한 상품 목록

옵션:
    --nick   대상 닉네임        --item  상품 키(아래 --list 참고)
    --gid    주문번호(생략하면 test-날짜시각). 환불 회수 때 이 값으로 찾는다.
"""
import datetime
import io
import json
import os
import sys
import urllib.parse
import urllib.request

BASE = ("https://firestore.googleapis.com/v1/projects/camnak-fishing"
        "/databases/(default)/documents")
APPLY = "--apply" in sys.argv
NL = "\n"

# 📦 functions/payment.js 의 PRODUCTS 와 같은 구성 (스킨 5 · 뱃지 3)
SKIN = [
    ("skin_novice", "하수 조사",   20,  "skin_novice.jpg"),
    ("skin_mid",    "중수 조사",   50,  "skin_intermediate.jpg"),
    ("skin_expert", "고수 조사",   100, "skin_expert.jpg"),
    ("skin_pro",    "프로 조사",   200, "skin_pro.jpg"),
    ("skin_master", "마스터 조사", 300, "skin_master.jpg"),
]
BADGE = [
    ("badge_1", "캠피싱 뱃지",      10, "item_badge_1.png"),
    ("badge_2", "캠피싱 휘장",      30, "item_badge_2.png"),
    ("badge_3", "KREFT 정예 휘장", 50, "item_badge_3.png"),
]

PRODUCTS = {}
for k, n, st, ic in SKIN:
    PRODUCTS[k] = {"name": n, "boxMsg": "눌러서 열면 스킨을 받습니다." + NL +
                   "열기 전에는 환불하실 수 있어요.",
                   "item": {"name": n, "quantity": 1, "cash": True,
                            "category": "SKIN", "type": "SKIN",
                            "stats": {"P": st, "C": st, "S": st},
                            "icon": "../images/" + ic}}
for k, n, st, ic in BADGE:
    PRODUCTS[k] = {"name": n, "boxMsg": "눌러서 열면 아이템을 받습니다." + NL +
                   "열기 전에는 환불하실 수 있어요.",
                   "item": {"name": n, "quantity": 1, "cash": True,
                            "category": "COMMON", "type": "ETC",
                            "stats": {"P": st, "C": st, "S": st}, "icon": ic}}


def arg(name, default=""):
    if name in sys.argv:
        i = sys.argv.index(name)
        if i + 1 < len(sys.argv):
            return sys.argv[i + 1]
    return default


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


def to_fs(v):
    """파이썬 값 → Firestore REST 표현."""
    if isinstance(v, bool):
        return {"booleanValue": v}
    if isinstance(v, int):
        return {"integerValue": str(v)}
    if isinstance(v, float):
        return {"doubleValue": v}
    if isinstance(v, str):
        return {"stringValue": v}
    if isinstance(v, list):
        return {"arrayValue": {"values": [to_fs(x) for x in v]}}
    if isinstance(v, dict):
        return {"mapValue": {"fields": {k: to_fs(x) for k, x in v.items()}}}
    return {"nullValue": None}


if "--list" in sys.argv:
    print("지급 가능한 상품")
    for k, p in PRODUCTS.items():
        print("   %-13s %s" % (k, p["name"]))
    sys.exit(0)

nick = arg("--nick")
key = arg("--item")
if not nick or key not in PRODUCTS:
    print(__doc__)
    sys.exit(1)

p = PRODUCTS[key]
gid = arg("--gid") or ("test-" + datetime.datetime.now().strftime("%Y%m%d%H%M%S"))

box = {
    "name": p["name"] + " 상자",
    "category": "BOX", "type": "BOX", "quantity": 1, "cash": True,
    "icon": "item_box_cash.png",
    "gid": gid,
    "giftTitle": p["name"],
    "giftMsg": p["boxMsg"],
    "gift": [p["item"]],
    "desc": p["name"] + NL + p["boxMsg"] + NL + NL + "눌러서 열어보세요.",
}

print("📦 " + box["name"])
print("   담긴 것 : " + p["item"]["name"])
print("   주문번호 : " + gid)
print("   대상    : " + nick)
print("모드 : " + ("실제 지급" if APPLY else "미리보기(아무것도 안 바꿈)"))
print()

tok = token()
page, target = None, None
while True:
    j = call(BASE + "/users?pageSize=300" + ("&pageToken=" + page if page else ""), tok)
    for d in j.get("documents", []):
        if val(d.get("fields", {}), "nickname") == nick:
            target = d
            break
    if target:
        break
    page = j.get("nextPageToken")
    if not page:
        break

if not target:
    print("'" + nick + "' 닉네임을 찾지 못했습니다.")
    sys.exit(1)

uid = target["name"].split("/")[-1]
inv = target["fields"].get("inventory", {}).get("arrayValue", {}).get("values", [])
print("계정 : %s (%s) · 가방 %d개" % (nick, uid, len(inv)))

if not APPLY:
    print()
    print("실제로 넣으려면 --apply 를 붙여 다시 실행하세요.")
    sys.exit(0)

inv2 = inv + [to_fs(box)]
body = {"fields": {"inventory": {"arrayValue": {"values": inv2}}}}
url = (BASE + "/users/" + uid + "?updateMask.fieldPaths=inventory"
       "&currentDocument.updateTime=" + urllib.parse.quote(target["updateTime"]))
try:
    call(url, tok, json.dumps(body).encode("utf-8"), "PATCH")
except urllib.error.HTTPError as e:
    if e.code == 400:
        print("⚠️ 읽는 사이에 유저가 가방을 바꿨습니다. 아무것도 안 바뀌었으니 다시 실행해 주세요.")
        sys.exit(2)
    raise

print("✅ 넣었습니다. 가방 %d개 → %d개" % (len(inv), len(inv2)))
