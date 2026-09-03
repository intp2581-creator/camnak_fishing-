# -*- coding: utf-8 -*-
"""
🎁 KREFT 성장 패키지 — 전 유저 일괄 지급 (결제 시스템 변경 보상)

구성은 functions/index.js 의 packageDatabase["성장 패키지"] 와 반드시 같아야 한다.
유료로 산 사람과 다른 걸 받으면 그게 바로 민원이 된다.

  경험치 물약 10 · KREFT 2배 카드 10 · 능력치 엠블럼 1
  낚시 1시간 이용권 1 · 아레나 입장권 1

⚠️ 두 번 주지 않도록 users/{uid}.growthPackGrantedAt 를 표식으로 쓴다.

사용법:
    python tools/grant_growth_package.py            # 미리보기(아무것도 안 바꿈)
    python tools/grant_growth_package.py --apply    # 실제 지급
"""
import io, json, os, sys, datetime, urllib.request, urllib.parse

PROJECT = "camnak-fishing"
BASE = ("https://firestore.googleapis.com/v1/projects/" + PROJECT +
        "/databases/(default)/documents")
APPLY = "--apply" in sys.argv
NL = chr(10)


def token():
    home = os.path.expanduser("~")
    cfg = json.load(io.open(os.path.join(home, ".config", "configstore",
                                         "firebase-tools.json"), encoding="utf-8"))
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
    if isinstance(x, bool):   return {"booleanValue": x}
    if isinstance(x, int):    return {"integerValue": str(x)}
    if isinstance(x, str):    return {"stringValue": x}
    if isinstance(x, dict):   return {"mapValue": {"fields": {k: sv(v) for k, v in x.items()}}}
    if isinstance(x, list):   return {"arrayValue": {"values": [sv(v) for v in x]}}
    raise TypeError(str(type(x)))


# ── 성장 패키지 구성 (functions/index.js packageDatabase 와 동일) ──────
GIFTS = [
    {"name": "경험치 물약", "quantity": 10, "category": "BOOST", "type": "BOOST",
     "boost": "exp", "icon": "item_potion_exp.png", "price": 0, "cash": True,
     "desc": "마시면 10분 동안 경험치가 2배로 들어와요." + NL + "(아레나에서는 적용되지 않아요)"},
    {"name": "KREFT 2배 카드", "quantity": 10, "category": "BOOST", "type": "BOOST",
     "boost": "pts", "icon": "item_card_kreft.png", "price": 0, "cash": True,
     "desc": "사용하면 10분 동안 KREFT가 2배로 들어와요." + NL + "(아레나에서는 적용되지 않아요)"},
    {"name": "능력치 엠블럼", "quantity": 1, "category": "COMMON", "type": "EVENT",
     "icon": "item_emblem_boost.png", "stats": {"P": 10, "C": 10, "S": 10},
     "secLeft": 3600, "active": False, "price": 0, "cash": True,
     "desc": "눌러서 활성화하면 1시간 동안 힘·컨트롤·감도가 각각 +10 올라가요." + NL +
             "낚시터에 있는 동안에만 시간이 줄어요. (휘장과 함께 적용)"},
    {"name": "낚시 1시간 이용권", "quantity": 1, "category": "TICKET", "type": "ETC",
     "icon": "item_ticket_1h.png", "price": 0, "cash": True,
     "desc": "낚시 시간을 1시간 추가해주는 이용권이에요." + NL + "(계정당 1일 1회 사용 가능)"},
    {"name": "아레나 입장권", "quantity": 1, "category": "TICKET", "type": "ETC",
     "icon": "arena_ticket.png", "price": 0, "cash": True,
     "desc": "아레나 무료 입장을 다 쓴 뒤 하루 1회 더 참가할 수 있어요."},
]

# 수량을 합산하는 항목(같은 이름이 이미 있으면 개수만 더한다)
STACKABLE = {"경험치 물약", "KREFT 2배 카드", "낚시 1시간 이용권", "아레나 입장권"}


def main():
    tok = token()
    users, page = [], None
    while True:
        u = BASE + "/users?pageSize=300" + ("&pageToken=" + page if page else "")
        j = call(u, tok)
        users += j.get("documents", [])
        page = j.get("nextPageToken")
        if not page:
            break

    print("전체 유저 " + str(len(users)) + "명")
    print("모드: " + ("실제 지급" if APPLY else "미리보기(아무것도 안 바꿈)"))
    print("")

    done = skip = fail = 0
    for doc in users:
        uid = doc["name"].split("/")[-1]
        f = doc.get("fields", {})
        nick = f.get("nickname", {}).get("stringValue", "(닉없음)")

        if "growthPackGrantedAt" in f:
            skip += 1
            continue

        inv = list(f.get("inventory", {}).get("arrayValue", {}).get("values", []))
        for g in GIFTS:
            if g["name"] in STACKABLE:
                hit = None
                for v in inv:
                    nm = v.get("mapValue", {}).get("fields", {}).get("name", {}).get("stringValue")
                    if nm == g["name"]:
                        hit = v
                        break
                if hit:
                    fl = hit["mapValue"]["fields"]
                    cur = int(fl.get("quantity", {}).get("integerValue", 0) or 0)
                    fl["quantity"] = {"integerValue": str(cur + g["quantity"])}
                    continue
            inv.append(sv(g))          # 엠블럼은 각자 시간을 세므로 항상 개별 항목

        if not APPLY:
            print("  [미리보기] " + nick + " (" + uid[:8] + ")")
            done += 1
            continue

        body = {"fields": {
            "inventory": {"arrayValue": {"values": inv}},
            "growthPackGrantedAt": {"timestampValue":
                datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")},
        }}
        url = (BASE + "/users/" + uid +
               "?updateMask.fieldPaths=inventory&updateMask.fieldPaths=growthPackGrantedAt")
        try:
            call(url, tok, json.dumps(body).encode("utf-8"), "PATCH")
            done += 1
            if done % 25 == 0:
                print("  ... " + str(done) + "명 지급")
        except Exception as e:
            fail += 1
            print("  ⚠️ 실패 " + nick + " : " + str(e))

    print("")
    print("지급 " + str(done) + "명 / 건너뜀(이미받음) " + str(skip) + "명 / 실패 " + str(fail) + "명")


main()
