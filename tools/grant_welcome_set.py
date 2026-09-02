# -*- coding: utf-8 -*-
"""
🎁 신규 조사 환영 세트 — 기존 유저 일괄 지급

신규 유저는 가입 시 스타터팩으로 자동 지급된다(game_config.kWelcomeSetOn).
기존 유저는 자동 경로가 없으므로 이 스크립트로 한 번 지급한다.
낚싯대(CF-30T·CF350)는 신규 전용이라 여기서는 주지 않는다 — 사용자 결정.

  지급: 경험치 물약 5 · KREFT 2배 카드 5 · 능력치 엠블럼 1

⚠️ 두 번 주지 않도록 users/{uid}.welcomeSetGrantedAt 를 표식으로 쓴다.
   이 필드가 있으면 건너뛴다.

사용법:
    python tools/grant_welcome_set.py            # 미리보기(아무것도 안 바꿈)
    python tools/grant_welcome_set.py --apply    # 실제 지급
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


# ── 지급할 아이템 (game_config.dart 정의와 동일해야 한다) ─────────────
def sv(x):
    """파이썬 값 → Firestore Value"""
    if isinstance(x, bool):   return {"booleanValue": x}
    if isinstance(x, int):    return {"integerValue": str(x)}
    if isinstance(x, str):    return {"stringValue": x}
    if isinstance(x, dict):   return {"mapValue": {"fields": {k: sv(v) for k, v in x.items()}}}
    if isinstance(x, list):   return {"arrayValue": {"values": [sv(v) for v in x]}}
    raise TypeError(str(type(x)))


# 🚫 제외 — 이미 환영 세트를 받은 계정(가입 경로 테스트용).
#    스타터팩으로 자동 지급받았으므로 여기서 또 주면 물약이 10개가 된다.
SKIP_EMAILS = {"anthemosa@naver.com"}   # 제주왕갈치(테스트)

GIFTS = [
    {"name": "경험치 물약", "price": 0, "cash": True,
     "category": "BOOST", "type": "BOOST", "boost": "exp", "quantity": 5,
     "icon": "item_potion_exp.png",
     "desc": "마시면 10분 동안 경험치가 2배로 들어와요." + NL + "(아레나·보스레이드에서는 적용되지 않아요)"},
    {"name": "KREFT 2배 카드", "price": 0, "cash": True,
     "category": "BOOST", "type": "BOOST", "boost": "pts", "quantity": 5,
     "icon": "item_card_kreft.png",
     "desc": "사용하면 10분 동안 KREFT가 2배로 들어와요." + NL + "(아레나·보스레이드에서는 적용되지 않아요)"},
    {"name": "능력치 엠블럼", "price": 0, "cash": True,
     "category": "COMMON", "type": "EVENT", "stats": {"P": 10, "C": 10, "S": 10},
     "icon": "item_emblem_boost.png", "secLeft": 3600, "active": False, "quantity": 1,
     "desc": "눌러서 활성화하면 1시간 동안 힘·컨트롤·감도가 각각 +10 올라가요." + NL +
             "낚시터에 있는 동안에만 시간이 줄어요." + NL +
             "휘장과 함께 적용돼요. (아레나·보스레이드 제외)"},
]


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

        if "welcomeSetGrantedAt" in f:
            skip += 1
            continue
        if f.get("email", {}).get("stringValue", "") in SKIP_EMAILS:
            print("  건너뜀(제외 목록) " + nick)
            skip += 1
            continue

        inv = list(f.get("inventory", {}).get("arrayValue", {}).get("values", []))
        for g in GIFTS:
            if g["type"] == "EVENT":
                inv.append(sv(g))                      # 엠블럼은 각자 시간을 세므로 개별 항목
                continue
            hit = None
            for v in inv:                              # 물약·카드는 수량 합산
                nm = v.get("mapValue", {}).get("fields", {}).get("name", {}).get("stringValue")
                if nm == g["name"]:
                    hit = v
                    break
            if hit:
                fl = hit["mapValue"]["fields"]
                cur = int(fl.get("quantity", {}).get("integerValue", 0) or 0)
                fl["quantity"] = {"integerValue": str(cur + g["quantity"])}
            else:
                inv.append(sv(g))

        if not APPLY:
            print("  [미리보기] " + nick + " (" + uid[:8] + ") ← 물약5·카드5·엠블럼1")
            done += 1
            continue

        body = {"fields": {
            "inventory": {"arrayValue": {"values": inv}},
            "welcomeSetGrantedAt": {"timestampValue":
                datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")},
        }}
        url = (BASE + "/users/" + uid +
               "?updateMask.fieldPaths=inventory&updateMask.fieldPaths=welcomeSetGrantedAt")
        try:
            call(url, tok, json.dumps(body).encode("utf-8"), "PATCH")
            done += 1
            print("  지급 완료  " + nick)
        except Exception as e:
            fail += 1
            print("  ⚠️ 실패  " + nick + " : " + str(e))

    print("")
    print("대상 " + str(done) + "명 / 이미 받음 " + str(skip) + "명 / 실패 " + str(fail) + "명")
    if not APPLY:
        print("실제로 주려면: python tools/grant_welcome_set.py --apply")


main()
