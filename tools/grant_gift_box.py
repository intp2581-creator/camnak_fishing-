# -*- coding: utf-8 -*-
"""
🎁 선물 상자 지급 — 운영자 보상·민원·이벤트용

아이템을 가방에 슬그머니 꽂아 넣는 대신 '선물 상자'로 준다.
받는 사람이 눌러서 여는 순간이 생기고, 무엇을 받았는지 목록으로 보여준다.

기본은 미리보기(아무것도 안 바꿈), --apply 를 붙여야 실제로 들어간다.

사용법:
    # 한 사람에게 프리셋으로
    python tools/grant_gift_box.py --nick 아레투사 --preset welcome
    python tools/grant_gift_box.py --nick 아레투사 --preset welcome --apply

    # 내용을 직접 지정
    python tools/grant_gift_box.py --nick 아레투사 --potion 3 --card 3 --title "제보 감사 선물" --apply

    # KREFT·경험치도 함께
    python tools/grant_gift_box.py --nick 아레투사 --kreft 50000 --exp 10000 --title "랭킹 시상" --apply

    # 전체 유저에게 (경고: 되돌리기 어렵다. 반드시 미리보기 먼저)
    python tools/grant_gift_box.py --all --preset welcome --once --apply

옵션:
    --nick    대상 닉네임        --all    전체 유저
    --preset  welcome | thanks | sorry
    --potion  경험치 물약 개수    --card   KREFT 2배 카드 개수
    --emblem  능력치 엠블럼 개수  --hour   낚시 1시간 이용권 개수
    --arena   아레나 입장권 개수
    --kreft   KREFT(포인트)      --exp    경험치
    --title   상자 제목          --msg    인사말
    --once    같은 제목의 상자를 이미 받은 사람은 건너뛴다(중복 지급 방지)
"""
import io
import json
import os
import sys
import time
import urllib.parse
import urllib.request

PROJECT = "camnak-fishing"
BASE = ("https://firestore.googleapis.com/v1/projects/" + PROJECT +
        "/databases/(default)/documents")
APPLY = "--apply" in sys.argv
ALL = "--all" in sys.argv
ONCE = "--once" in sys.argv
NL = chr(10)
GIFT_BOX_NAME = "선물 상자"
GIFT_BOX_ICON = "item_box_gift.png"


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
    return json.load(urllib.request.urlopen(r))


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


# ── 상자에 담을 아이템 (game_config.dart 와 같아야 한다) ──────────────
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
            "icon": "item_emblem_boost.png", "secLeft": 3600, "active": False,
            "quantity": 1,
            "desc": "눌러서 활성화하면 1시간 동안 힘·컨트롤·감도가 각각 +10 올라가요." + NL +
                    "낚시터에 있는 동안에만 시간이 줄어요." + NL +
                    "휘장과 함께 적용돼요. (아레나·보스레이드 제외)"}


def item_hour(n):
    return {"name": "낚시 1시간 이용권", "price": 0, "cash": True,
            "category": "TICKET", "type": "ETC", "quantity": n,
            "icon": "item_ticket_1h.png",
            "desc": "낚시 시간을 1시간 추가해주는 이용권이에요." + NL +
                    "(계정당 1일 1회 사용 가능)"}


def item_arena(n):
    return {"name": "아레나 입장권", "price": 0, "cash": True,
            "category": "TICKET", "type": "ETC", "quantity": n,
            "icon": "arena_ticket.png",
            "desc": "아레나 무료 입장을 다 쓴 뒤 하루 1회 더 참가할 수 있어요."}


def rod(name, cat, icon):
    return {"name": name, "category": cat, "type": "ROD", "reqLevel": 5,
            "stats": {"P": 10, "C": 10, "S": 10}, "icon": icon,
            "desc": "🎁 신규 조사 환영 선물이에요." + NL +
                    "Lv.5가 되면 바로 장착할 수 있어요."}


# ── 프리셋 ────────────────────────────────────────────────────────
PRESETS = {
    "welcome": {
        "title": "신규 조사 환영 선물",
        "msg": "캠피싱에 오신 것을 환영합니다!" + NL + "즐거운 낚시 되세요.",
        "items": [item_potion(5), item_card(5), item_emblem(),
                  rod("CF-30T", "FW", "rod_fw_cf30.png"),
                  rod("CF350", "SEA", "rod_sea_cf350.png")],
    },
    "thanks": {
        "title": "제보 감사 선물",
        "msg": "제보 주셔서 감사합니다." + NL + "보상으로 선물상자를 보내 드립니다.",
        "items": [item_potion(3), item_card(3)],
    },
    "sorry": {
        "title": "불편을 드려 죄송합니다",
        "msg": "이용에 불편을 드려 죄송합니다." + NL + "작은 사과의 뜻입니다.",
        "items": [item_hour(2), item_potion(3), item_card(3)],
    },
    "event": {
        "title": "이벤트 선물",
        "msg": "이벤트에 참여해 주셔서 고맙습니다!" + NL + "작은 선물을 준비했어요.",
        "items": [item_potion(3), item_card(3), item_hour(1), item_arena(1)],
    },
    # 🌕 추석 전날(2026-09-24 목) 전 유저 일괄. 반드시 --all --once 로.
    #    물약·카드를 3개로 줄인 이유: 성장 패키지(5,500원)가 물약10·카드10 구성이라
    #    같은 양을 공짜로 뿌리면 살 이유가 없어진다. 맛보기 양이라야 판매로 이어진다.
    "chuseok": {
        "title": "추석 선물",
        "msg": "가족들과 함께 즐거운 한가위 되세요!" + NL + "캠피싱이 작은 선물을 준비했습니다.",
        "items": [item_potion(3), item_card(3), item_emblem(),
                  item_hour(1), item_arena(1)],
    },
}


def build_box(title, msg, items, exp, gold, gid):
    box = {"name": GIFT_BOX_NAME, "category": "BOX", "type": "BOX",
           "icon": GIFT_BOX_ICON, "quantity": 1, "gid": gid,
           "giftTitle": title, "giftMsg": msg,
           "gift": items,
           "desc": title + NL + msg + NL + NL + "눌러서 열어보세요."}
    if exp > 0:
        box["giftExp"] = exp
    if gold > 0:
        box["giftGold"] = gold
    return box


def fetch_users(tok, nick):
    """닉네임 하나 또는 전체. [(uid, nickname, fields)] 반환"""
    out = []
    page = None
    while True:
        u = BASE + "/users?pageSize=300" + ("&pageToken=" + page if page else "")
        j = call(u, tok)
        for doc in j.get("documents", []):
            f = doc.get("fields", {})
            nm = f.get("nickname", {}).get("stringValue", "")
            uid = doc["name"].split("/")[-1]
            if nick:
                if nm == nick:
                    return [(uid, nm, f)]
            else:
                out.append((uid, nm, f))
        page = j.get("nextPageToken")
        if not page:
            break
    return [] if nick else out


def has_same_box(inv, title):
    """같은 제목의 선물 상자를 이미 가지고 있는지 — 중복 지급 방지용"""
    for v in inv:
        fl = v.get("mapValue", {}).get("fields", {})
        if (fl.get("name", {}).get("stringValue") == GIFT_BOX_NAME and
                fl.get("giftTitle", {}).get("stringValue") == title):
            return True
    return False


def main():
    nick = arg("--nick")
    if not nick and not ALL:
        print("대상이 없습니다:  --nick 아레투사   또는   --all")
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

    if not items and exp <= 0 and gold <= 0:
        print("상자에 담을 것이 없습니다. --preset 이나 --potion 등을 지정하세요.")
        return
    if not title:
        print("상자 제목이 필요합니다:  --title 보상선물")
        return

    print("🎁 " + title)
    if msg:
        print("   " + msg.replace(NL, " / "))
    for i in items:
        print("   · " + i["name"] + " x" + str(i.get("quantity", 1)))
    if exp > 0:
        print("   · 경험치 +" + str(exp))
    if gold > 0:
        print("   · KREFT +" + str(gold))
    print("모드: " + ("실제 지급" if APPLY else "미리보기(아무것도 안 바꿈)"))
    print("")

    tok = token()
    targets = fetch_users(tok, None if ALL else nick)
    if not targets:
        print("대상을 찾지 못했습니다.")
        return
    print("대상 " + str(len(targets)) + "명")

    done = 0
    skipped = 0
    for uid, nm, f in targets:
        inv = list(f.get("inventory", {}).get("arrayValue", {}).get("values", []))
        if ONCE and has_same_box(inv, title):
            skipped += 1
            continue

        gid = "g" + str(int(time.time() * 1000000)) + uid[:4]
        inv.append(sv(build_box(title, msg, items, exp, gold, gid)))

        if not APPLY:
            done += 1
            if done <= 5:
                print("  (미리보기) " + (nm or uid[:8]))
            continue

        body = {"fields": {"inventory": {"arrayValue": {"values": inv}}}}
        try:
            call(BASE + "/users/" + uid + "?updateMask.fieldPaths=inventory",
                 tok, json.dumps(body).encode("utf-8"), "PATCH")
            done += 1
            if len(targets) <= 10 or done % 25 == 0:
                print("  " + str(done) + "명 완료")
        except Exception as e:
            print("  ! " + (nm or uid[:8]) + " 실패: " + str(e))

    print("")
    tail = ("  (건너뜀 " + str(skipped) + "명)") if skipped else ""
    if APPLY:
        print("✅ " + str(done) + "명에게 선물 상자를 넣었습니다." + tail)
    else:
        print(str(done) + "명이 받게 됩니다." + tail)
        print("실제로 넣으려면 --apply 를 붙여 다시 실행하세요.")


main()
