# -*- coding: utf-8 -*-
"""
📦 성장패키지 '상자'를 한 사람에게 넣어준다 (결제 흐름 확인용)

functions/payment.js 의 grantItem() 이 만드는 것과 '똑같은' 상자를 넣는다.
모양이 다르면 확인이 의미가 없다 — 필드 하나라도 어긋나면 안 된다.

  상자를 누르면 → 안의 5종이 가방에 풀린다
  gid 에 주문번호가 들어가 CS 때 '이 주문 상자가 아직 있나'를 볼 수 있다

사용법:
    python tools/grant_growth_box.py 미르페스카            # 미리보기
    python tools/grant_growth_box.py 미르페스카 --apply    # 실제 지급
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
NL = chr(10)

args = [a for a in sys.argv[1:] if not a.startswith("--")]
APPLY = "--apply" in sys.argv
if not args:
    print("받을 사람 닉네임을 적어주세요. 예: python tools/grant_growth_box.py 미르페스카")
    sys.exit(1)
TARGET = args[0]


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
    if isinstance(x, bool):  return {"booleanValue": x}
    if isinstance(x, int):   return {"integerValue": str(x)}
    if isinstance(x, str):   return {"stringValue": x}
    if isinstance(x, dict):  return {"mapValue": {"fields": {k: sv(v) for k, v in x.items()}}}
    if isinstance(x, list):  return {"arrayValue": {"values": [sv(v) for v in x]}}
    raise TypeError(str(type(x)))


# ── functions/payment.js 의 growth_pack 과 글자 하나까지 같아야 한다 ──
BUNDLE = [
    {"name": "경험치 물약", "qty": 10, "quantity": 10, "category": "BOOST", "type": "BOOST",
     "boost": "exp", "icon": "item_potion_exp.png",
     "desc": "마시면 10분 동안 경험치가 2배로 들어와요." + NL + "(아레나에서는 적용되지 않아요)"},
    {"name": "KREFT 2배 카드", "qty": 10, "quantity": 10, "category": "BOOST", "type": "BOOST",
     "boost": "pts", "icon": "item_card_kreft.png",
     "desc": "사용하면 10분 동안 KREFT가 2배로 들어와요." + NL + "(아레나에서는 적용되지 않아요)"},
    {"name": "능력치 엠블럼", "qty": 1, "quantity": 1, "category": "COMMON", "type": "EVENT",
     "icon": "item_emblem_boost.png", "stats": {"P": 10, "C": 10, "S": 10},
     "secLeft": 3600, "active": False,
     "desc": "눌러서 활성화하면 1시간 동안 힘·컨트롤·감도가 각각 +10 올라가요." + NL +
             "낚시터에 있는 동안에만 시간이 줄어요. (휘장과 함께 적용)"},
    {"name": "낚시 1시간 이용권", "qty": 1, "quantity": 1, "category": "TICKET", "type": "ETC",
     "icon": "item_ticket_1h.png",
     "desc": "낚시 시간을 1시간 추가해주는 이용권이에요." + NL + "(계정당 1일 1회 사용 가능)"},
    {"name": "아레나 입장권", "qty": 1, "quantity": 1, "category": "TICKET", "type": "ETC",
     "icon": "arena_ticket.png",
     "desc": "아레나 무료 입장을 다 쓴 뒤 하루 1회 더 참가할 수 있어요."},
]

BOX_MSG = "성장에 필요한 것을 한 번에 담았습니다." + NL + "눌러서 열어보세요."
GID = "TEST-" + datetime.datetime.now().strftime("%Y%m%d-%H%M%S")

BOX = {
    "name": "성장패키지 상자",
    "category": "BOX", "type": "BOX", "quantity": 1, "cash": True,
    "icon": "item_box_growth.png",
    "gid": GID,
    "giftTitle": "KREFT 성장패키지",
    "giftMsg": BOX_MSG,
    "gift": BUNDLE,
    "desc": "KREFT 성장패키지" + NL + BOX_MSG + NL + NL + "눌러서 열어보세요.",
}


def main():
    tok = token()
    found = None
    page = None
    while True:
        u = BASE + "/users?pageSize=300" + ("&pageToken=" + page if page else "")
        j = call(u, tok)
        for doc in j.get("documents", []):
            f = doc.get("fields", {})
            if f.get("nickname", {}).get("stringValue") == TARGET:
                found = doc
                break
        page = j.get("nextPageToken")
        if found or not page:
            break

    if not found:
        print("'" + TARGET + "' 닉네임을 찾지 못했습니다.")
        sys.exit(1)

    uid = found["name"].split("/")[-1]
    f = found.get("fields", {})
    inv = list(f.get("inventory", {}).get("arrayValue", {}).get("values", []))

    have = [v for v in inv
            if v.get("mapValue", {}).get("fields", {})
                .get("name", {}).get("stringValue") == "성장패키지 상자"]

    print("받는 사람 : " + TARGET + " (" + uid + ")")
    print("가방      : " + str(len(inv)) + "칸, 이미 가진 성장패키지 상자 " + str(len(have)) + "개")
    print("넣을 것   : 성장패키지 상자 1개  gid=" + GID)
    print("            안에 " + ", ".join(
        b["name"] + " " + str(b["quantity"]) for b in BUNDLE))
    print("모드      : " + ("실제 지급" if APPLY else "미리보기(아무것도 안 바꿈)"))

    if not APPLY:
        return

    inv.append(sv(BOX))
    body = {"fields": {"inventory": {"arrayValue": {"values": inv}}}}
    call(BASE + "/users/" + uid + "?updateMask.fieldPaths=inventory",
         tok, json.dumps(body).encode("utf-8"), "PATCH")
    print(NL + "지급 완료. 가방 " + str(len(inv)) + "칸.")


main()
