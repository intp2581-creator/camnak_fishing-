# -*- coding: utf-8 -*-
"""
🎁 한 사람에게 아이템 지급 — 테스트·보상·민원 처리용

닉네임으로 찾아서 인벤토리에 넣는다. 물약·카드는 이미 있으면 수량만 더한다.
기본은 미리보기(아무것도 안 바꿈), --apply 를 붙여야 실제로 들어간다.

사용법:
    python tools/grant_items.py --nick 아레투사 --potion 1 --card 1
    python tools/grant_items.py --nick 아레투사 --potion 1 --card 1 --apply
    python tools/grant_items.py --nick 홍길동 --emblem 1 --apply

옵션:
    --nick   지급 대상 닉네임(필수)
    --potion 경험치 물약 갯수
    --card   KREFT 2배 카드 갯수
    --emblem 능력치 엠블럼 갯수(각각 별개 항목으로 들어감)
"""
import io, json, os, sys, urllib.request, urllib.parse

PROJECT = "camnak-fishing"
BASE = ("https://firestore.googleapis.com/v1/projects/" + PROJECT +
        "/databases/(default)/documents")
APPLY = "--apply" in sys.argv
NL = chr(10)


def arg(name, default=""):
    if name in sys.argv:
        i = sys.argv.index(name)
        if i + 1 < len(sys.argv):
            return sys.argv[i + 1]
    return default


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


# ── 아이템 정의 (game_config.dart 와 같아야 한다) ────────────────────
def item_potion(n):
    return {"name": "경험치 물약", "price": 0, "cash": True,
            "category": "BOOST", "type": "BOOST", "boost": "exp", "quantity": n,
            "icon": "item_potion_exp.png",
            "desc": "마시면 10분 동안 경험치가 2배로 들어와요." + NL +
                    "(아레나·보스레이드에서는 적용되지 않아요)"}


def item_card(n):
    return {"name": "KREFT 2배 카드", "price": 0, "cash": True,
            "category": "BOOST", "type": "BOOST", "boost": "pts", "quantity": n,
            "icon": "item_card_kreft.png",
            "desc": "사용하면 10분 동안 KREFT가 2배로 들어와요." + NL +
                    "(아레나·보스레이드에서는 적용되지 않아요)"}


def item_emblem():
    return {"name": "능력치 엠블럼", "price": 0, "cash": True,
            "category": "COMMON", "type": "EVENT", "stats": {"P": 10, "C": 10, "S": 10},
            "icon": "item_emblem_boost.png", "secLeft": 3600, "active": False, "quantity": 1,
            "desc": "눌러서 활성화하면 1시간 동안 힘·컨트롤·감도가 각각 +10 올라가요." + NL +
                    "낚시터에 있는 동안에만 시간이 줄어요." + NL +
                    "휘장과 함께 적용돼요. (아레나·보스레이드 제외)"}


def main():
    nick = arg("--nick")
    if not nick:
        print("닉네임이 필요합니다:  --nick 아레투사")
        return
    n_potion = int(arg("--potion", "0") or 0)
    n_card = int(arg("--card", "0") or 0)
    n_emblem = int(arg("--emblem", "0") or 0)
    if n_potion + n_card + n_emblem <= 0:
        print("줄 아이템이 없습니다:  --potion 1 --card 1")
        return

    tok = token()

    # 닉네임으로 대상 찾기
    target = None
    page = None
    while True:
        u = BASE + "/users?pageSize=300" + ("&pageToken=" + page if page else "")
        j = call(u, tok)
        for doc in j.get("documents", []):
            f = doc.get("fields", {})
            if f.get("nickname", {}).get("stringValue", "") == nick:
                target = doc
                break
        if target:
            break
        page = j.get("nextPageToken")
        if not page:
            break

    if not target:
        print("'" + nick + "' 을(를) 찾지 못했습니다.")
        return

    uid = target["name"].split("/")[-1]
    f = target.get("fields", {})
    inv = list(f.get("inventory", {}).get("arrayValue", {}).get("values", []))

    print("대상: " + nick + " (" + uid[:8] + ")  현재 인벤 " + str(len(inv)) + "칸")
    print("모드: " + ("실제 지급" if APPLY else "미리보기(아무것도 안 바꿈)"))

    def add_stack(g):
        """물약·카드는 이미 있으면 수량만 더한다"""
        for v in inv:
            fl = v.get("mapValue", {}).get("fields", {})
            if fl.get("name", {}).get("stringValue") == g["name"]:
                cur = int(fl.get("quantity", {}).get("integerValue", 0) or 0)
                fl["quantity"] = {"integerValue": str(cur + g["quantity"])}
                print("  " + g["name"] + " " + str(cur) + " → " + str(cur + g["quantity"]) + "개")
                return
        inv.append(sv(g))
        print("  " + g["name"] + " 새로 " + str(g["quantity"]) + "개")

    if n_potion > 0:
        add_stack(item_potion(n_potion))
    if n_card > 0:
        add_stack(item_card(n_card))
    for _ in range(n_emblem):
        inv.append(sv(item_emblem()))
        print("  능력치 엠블럼 1개(개별 항목)")

    if not APPLY:
        print("")
        print("실제로 넣으려면 --apply 를 붙여 다시 실행하세요.")
        return

    body = {"fields": {"inventory": {"arrayValue": {"values": inv}}}}
    call(BASE + "/users/" + uid + "?updateMask.fieldPaths=inventory",
         tok, json.dumps(body).encode("utf-8"), "PATCH")
    print("")
    print("✅ 지급 완료 — " + nick + " 님 가방에 들어갔습니다.")


main()
