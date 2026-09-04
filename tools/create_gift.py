# -*- coding: utf-8 -*-
"""
🎁 홈페이지 선물함에 선물 등록 — 기간 안에 '받기'를 눌러야 지급된다

가방에 바로 꽂아 넣는 grant_gift_box.py 와 다르다.
이건 홈페이지(kreft.co.kr/gift.html)에 선물을 걸어두고, 유저가 와서
받기를 눌러야 게임 가방으로 들어간다. 기간이 지나면 못 받는다.

  · 휴면 유저 가방에 안 열린 상자가 쌓이지 않는다
  · 받으러 오는 김에 공지·커뮤니티를 본다
  · 기간이 있어야 "지금 들어와야 할 이유"가 생긴다

사용법:
    # 추석 선물 (9/21 ~ 9/27)
    python tools/create_gift.py --preset chuseok --start 2026-09-21 --end 2026-09-27
    python tools/create_gift.py --preset chuseok --start 2026-09-21 --end 2026-09-27 --apply

    # 직접 지정
    python tools/create_gift.py --title "출석 감사 선물" --msg "고맙습니다" \
        --potion 3 --card 3 --kreft 50000 --start 2026-09-10 --end 2026-09-14 --apply

    # 등록된 선물 목록 / 삭제
    python tools/create_gift.py --list
    python tools/create_gift.py --delete <문서ID> --apply

옵션:
    --preset  chuseok | event | thanks
    --title   선물 제목            --msg    인사말
    --potion --card --emblem --hour --arena   담을 아이템 개수
    --kreft   KREFT               --exp    경험치
    --start   받기 시작일 YYYY-MM-DD (없으면 즉시)
    --end     받기 마감일 YYYY-MM-DD (없으면 무기한 — 권장하지 않음)
    --off     등록하되 아직 안 보이게(active=false)
"""
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
NL = chr(10)


def arg(name, default=""):
    if name in sys.argv:
        i = sys.argv.index(name)
        if i + 1 < len(sys.argv):
            return sys.argv[i + 1]
    return default


def num(name, d=0):
    try:
        return int(arg(name, str(d)) or d)
    except ValueError:
        return d


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
    body = urllib.request.urlopen(r).read()
    return json.loads(body.decode("utf-8")) if body else {}


def sv(x):
    if isinstance(x, bool):
        return {"booleanValue": x}
    if isinstance(x, int):
        return {"integerValue": str(x)}
    if isinstance(x, str):
        return {"stringValue": x}
    if isinstance(x, dict):
        return {"mapValue": {"fields": {k: sv(v) for k, v in x.items()}}}
    if isinstance(x, list):
        return {"arrayValue": {"values": [sv(v) for v in x]}}
    raise TypeError(str(type(x)))


def gv(f, k, d=None):
    v = f.get(k)
    if v is None:
        return d
    for t in ("stringValue", "booleanValue"):
        if t in v:
            return v[t]
    if "integerValue" in v:
        return int(v["integerValue"])
    return d


# ── 상자에 담을 아이템 (game_config.dart 와 같아야 한다) ──────────────
def item_potion(n):
    return {"name": "경험치 물약", "category": "BOOST", "type": "BOOST",
            "boost": "exp", "quantity": n, "icon": "item_potion_exp.png",
            "desc": "마시면 10분 동안 경험치가 2배로 들어와요." + NL +
                    "(아레나·보스레이드에서는 적용되지 않아요)"}


def item_card(n):
    return {"name": "KREFT 2배 카드", "category": "BOOST", "type": "BOOST",
            "boost": "pts", "quantity": n, "icon": "item_card_kreft.png",
            "desc": "사용하면 10분 동안 KREFT가 2배로 들어와요." + NL +
                    "(아레나·보스레이드에서는 적용되지 않아요)"}


def item_emblem():
    return {"name": "능력치 엠블럼", "category": "COMMON", "type": "EVENT",
            "stats": {"P": 10, "C": 10, "S": 10}, "quantity": 1,
            "icon": "item_emblem_boost.png", "secLeft": 3600,
            "desc": "눌러서 활성화하면 1시간 동안 힘·컨트롤·감도가 각각 +10 올라가요." + NL +
                    "낚시터에 있는 동안에만 시간이 줄어요." + NL +
                    "휘장과 함께 적용돼요. (아레나·보스레이드 제외)"}


def item_hour(n):
    return {"name": "낚시 1시간 이용권", "category": "TICKET", "type": "ETC",
            "quantity": n, "icon": "item_ticket_1h.png",
            "desc": "낚시 시간을 1시간 추가해주는 이용권이에요." + NL +
                    "(계정당 1일 1회 사용 가능)"}


def item_arena(n):
    return {"name": "아레나 입장권", "category": "TICKET", "type": "ETC",
            "quantity": n, "icon": "arena_ticket.png",
            "desc": "아레나 무료 입장을 다 쓴 뒤 하루 1회 더 참가할 수 있어요."}


PRESETS = {
    # 🌕 물약·카드가 3개인 이유: 성장 패키지(5,500원)가 물약10·카드10 구성이라
    #    같은 양을 공짜로 뿌리면 살 이유가 없어진다. 맛보기 양이라야 판매로 이어진다.
    "chuseok": {
        "title": "추석 선물",
        "msg": "가족들과 함께 즐거운 한가위 되세요!" + NL +
               "캠피싱이 작은 선물을 준비했습니다.",
        "items": [item_potion(3), item_card(3), item_emblem(),
                  item_hour(1), item_arena(1)],
    },
    "event": {
        "title": "이벤트 선물",
        "msg": "이벤트에 참여해 주셔서 고맙습니다!" + NL + "작은 선물을 준비했어요.",
        "items": [item_potion(3), item_card(3), item_hour(1), item_arena(1)],
    },
    "thanks": {
        "title": "감사 선물",
        "msg": "캠피싱을 찾아 주셔서 고맙습니다." + NL + "작은 선물을 준비했어요.",
        "items": [item_potion(3), item_card(3)],
    },
}


def show_list(tok):
    try:
        j = call(BASE + "/gifts?pageSize=100", tok)
    except urllib.error.HTTPError as e:
        if e.code == 404:
            print("등록된 선물이 없습니다.")
            return
        raise
    docs = j.get("documents", [])
    if not docs:
        print("등록된 선물이 없습니다.")
        return
    print("등록된 선물 " + str(len(docs)) + "건")
    print("")
    for d in docs:
        f = d.get("fields", {})
        did = d["name"].split("/")[-1]
        items = f.get("items", {}).get("arrayValue", {}).get("values", [])
        names = []
        for it in items:
            fl = it.get("mapValue", {}).get("fields", {})
            q = fl.get("quantity", {}).get("integerValue", "1")
            names.append(gv(fl, "name", "") + ("x" + q if int(q) > 1 else ""))
        print("  [" + did + "]  " + str(gv(f, "title", "")))
        print("     기간: " + str(gv(f, "startAt", "(즉시)")) + " ~ " +
              str(gv(f, "endAt", "(무기한)")) +
              ("   ⛔ 꺼짐" if gv(f, "active", True) is False else ""))
        print("     내용: " + ", ".join(names) +
              (("  KREFT+" + str(gv(f, "gold", 0))) if gv(f, "gold", 0) else "") +
              (("  경험치+" + str(gv(f, "exp", 0))) if gv(f, "exp", 0) else ""))
        print("")


def main():
    tok = token()

    if "--list" in sys.argv:
        show_list(tok)
        return

    if "--delete" in sys.argv:
        did = arg("--delete")
        if not did:
            print("삭제할 문서ID가 필요합니다:  --delete <ID>")
            return
        if not APPLY:
            print("[" + did + "] 를 삭제합니다. 실제로 지우려면 --apply 를 붙이세요.")
            return
        call(BASE + "/gifts/" + did, tok, method="DELETE")
        print("✅ 삭제했습니다.")
        return

    preset = arg("--preset")
    if preset and preset not in PRESETS:
        print("모르는 프리셋: " + preset + "   (" + ", ".join(PRESETS) + ")")
        return

    items = []
    title = arg("--title")
    msg = arg("--msg")
    if preset:
        p = PRESETS[preset]
        items = [dict(i) for i in p["items"]]
        title = title or p["title"]
        msg = msg or p["msg"]

    if num("--potion") > 0:
        items.append(item_potion(num("--potion")))
    if num("--card") > 0:
        items.append(item_card(num("--card")))
    for _ in range(num("--emblem")):
        items.append(item_emblem())
    if num("--hour") > 0:
        items.append(item_hour(num("--hour")))
    if num("--arena") > 0:
        items.append(item_arena(num("--arena")))

    exp = num("--exp")
    gold = num("--kreft")
    start = arg("--start")
    end = arg("--end")

    if not title:
        print("선물 제목이 필요합니다:  --title 추석선물   또는  --preset chuseok")
        return
    if not items and exp <= 0 and gold <= 0:
        print("선물에 담을 것이 없습니다.")
        return

    doc = {"title": title, "msg": msg, "items": items,
           "exp": exp, "gold": gold,
           "startAt": start, "endAt": end,
           "active": "--off" not in sys.argv}

    print("🎁 " + title)
    if msg:
        print("   " + msg.replace(NL, " / "))
    for i in items:
        print("   · " + i["name"] + " x" + str(i.get("quantity", 1)))
    if exp > 0:
        print("   · 경험치 +" + str(exp))
    if gold > 0:
        print("   · KREFT +" + str(gold))
    print("   기간: " + (start or "(즉시)") + " ~ " + (end or "(무기한)"))
    if not end:
        print("   ⚠️ 마감일이 없습니다. 기간을 정하는 편이 좋습니다(--end).")
    print("   상태: " + ("숨김(active=false)" if "--off" in sys.argv else "공개"))
    print("모드: " + ("실제 등록" if APPLY else "미리보기(아무것도 안 바꿈)"))
    print("")

    if not APPLY:
        print("실제로 등록하려면 --apply 를 붙여 다시 실행하세요.")
        return

    body = {"fields": {k: sv(v) for k, v in doc.items()}}
    r = call(BASE + "/gifts", tok, json.dumps(body).encode("utf-8"), "POST")
    did = r["name"].split("/")[-1]
    print("✅ 등록했습니다.  ID: " + did)
    print("   https://kreft.co.kr/gift.html 에서 확인하세요.")


main()
