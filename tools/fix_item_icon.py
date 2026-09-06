# -*- coding: utf-8 -*-
"""🎒 인벤토리 아이템의 빠진 '아이콘' 값을 채워 넣는다.

아이콘 없이 지급된 아이템은 화면에서 엉뚱한 그림(예전에는 낚싯대)으로 보인다.
지급 스크립트가 icon 을 빠뜨렸을 때 뒤늦게 고치는 용도.

사용법:
    python tools/fix_item_icon.py 빨강테리 "아레나 입장권" arena_ticket.png
    python tools/fix_item_icon.py --scan          # 아이콘 없는 항목 전수 조사

⚠️ 유저가 접속 중일 수 있으므로 '조건부 쓰기'(updateTime)를 쓴다.
   내가 읽은 뒤 유저가 뭔가 바꿨으면 쓰기가 실패한다 → 다시 실행하면 된다.
   (그냥 덮어쓰면 그 사이 얻은 아이템이 사라진다)
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


def token():
    cfg = json.load(io.open(os.path.join(os.path.expanduser("~"), ".config",
                                         "configstore", "firebase-tools.json"),
                            encoding="utf-8"))
    data = urllib.parse.urlencode({
        "client_id": ("563584335869-fgrhgmd47bqnekij5i8b5pr03ho849e6"
                      ".apps.googleusercontent.com"),
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


def val(fields, key):
    x = fields.get(key)
    return list(x.values())[0] if x else None


def all_users(tok):
    page, out = None, []
    while True:
        j = call(BASE + "/users?pageSize=300" +
                 ("&pageToken=" + page if page else ""), tok)
        out += j.get("documents", [])
        page = j.get("nextPageToken")
        if not page:
            break
    return out


tok = token()

# ── 전수 조사 ────────────────────────────────────────────────
if "--scan" in sys.argv:
    print("아이콘이 비어 있는 인벤토리 항목")
    n = 0
    for d in all_users(tok):
        nick = val(d.get("fields", {}), "nickname") or "(닉없음)"
        inv = d["fields"].get("inventory", {}).get("arrayValue", {}).get("values", [])
        for v in inv:
            mf = v.get("mapValue", {}).get("fields", {})
            if not val(mf, "icon"):
                n += 1
                print("  · %-14s %s" % (nick, val(mf, "name") or "(이름없음)"))
    print("  없음" if not n else "\n총 %d건" % n)
    sys.exit(0)

if len(sys.argv) < 4:
    print(__doc__)
    sys.exit(1)

nick, item_name, icon_file = sys.argv[1], sys.argv[2], sys.argv[3]

target = None
for d in all_users(tok):
    if val(d.get("fields", {}), "nickname") == nick:
        target = d
        break
if not target:
    print("'%s' 닉네임을 찾지 못했습니다." % nick)
    sys.exit(1)

uid = target["name"].split("/")[-1]
update_time = target["updateTime"]          # 🔒 조건부 쓰기용 도장
inv = target["fields"].get("inventory", {}).get("arrayValue", {}).get("values", [])

print("계정      : %s (%s)" % (nick, uid))
print("인벤 개수 : %d" % len(inv))

hits = 0
for v in inv:
    mf = v.get("mapValue", {}).get("fields", {})
    if val(mf, "name") == item_name and not val(mf, "icon"):
        mf["icon"] = {"stringValue": icon_file}
        hits += 1
        print("고칠 항목 : %s (수량 %s) → icon=%s"
              % (item_name, val(mf, "quantity"), icon_file))

if not hits:
    print("고칠 게 없습니다 (이미 아이콘이 있거나 그 아이템이 없음).")
    sys.exit(0)

body = {"fields": {"inventory": {"arrayValue": {"values": inv}}}}
url = (BASE + "/users/" + uid +
       "?updateMask.fieldPaths=inventory" +
       "&currentDocument.updateTime=" + urllib.parse.quote(update_time))
try:
    call(url, tok, json.dumps(body).encode("utf-8"), "PATCH")
except urllib.error.HTTPError as e:
    if e.code == 400:
        print()
        print("⚠️ 쓰기 실패 — 읽는 사이에 유저가 인벤토리를 바꿨습니다(접속 중).")
        print("   아무것도 안 바뀌었습니다. 다시 실행해 주세요.")
        sys.exit(2)
    raise

# ── 되읽어 확인 ──────────────────────────────────────────────
after = call(BASE + "/users/" + uid, tok)
inv2 = after["fields"].get("inventory", {}).get("arrayValue", {}).get("values", [])
ok = 0
for v in inv2:
    mf = v.get("mapValue", {}).get("fields", {})
    if val(mf, "name") == item_name:
        print("확인      : %s · 수량 %s · icon=%s"
              % (item_name, val(mf, "quantity"), val(mf, "icon")))
        if val(mf, "icon") == icon_file:
            ok += 1
print()
print("완료 — %d건 수정, 인벤 %d개 → %d개 (그대로여야 정상)"
      % (ok, len(inv), len(inv2)))
