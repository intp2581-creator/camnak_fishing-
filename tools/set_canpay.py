# -*- coding: utf-8 -*-
"""
🎫 PG 심사용 계정에 '결제 허용' 표시를 켜고 끈다.

   테스트 채널 동안은 운영자(isGm)만 결제가 진행된다.
   심사자에게 isGm 을 주면 관리자 화면까지 열리므로, canPay 만 따로 켠다.
     · canPay = 결제창까지 갈 수 있다
     · 관리자 화면(공지·환불·주문 조회)은 못 들어간다

⚠️ 테스트 채널이라 결제해도 돈이 안 나간다.
   이 표시를 켠 계정은 공짜로 아이템을 가져갈 수 있으므로,
   심사가 끝나면 반드시 --off 로 꺼야 한다.

사용법:
    python tools/set_canpay.py 닉네임            # 지금 상태만 보기
    python tools/set_canpay.py 닉네임 --on       # 켜기
    python tools/set_canpay.py 닉네임 --off      # 끄기
    python tools/set_canpay.py --list            # 켜져 있는 계정 모두 보기
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

args = [a for a in sys.argv[1:] if not a.startswith("--")]
ON = "--on" in sys.argv
OFF = "--off" in sys.argv
LIST = "--list" in sys.argv


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


def users(tok):
    page, out = None, []
    while True:
        u = BASE + "/users?pageSize=300" + ("&pageToken=" + page if page else "")
        j = call(u, tok)
        out += j.get("documents", [])
        page = j.get("nextPageToken")
        if not page:
            break
    return out


def field(f, k):
    x = f.get(k)
    return list(x.values())[0] if x else None


tok = token()

if LIST:
    print("결제 허용(canPay)이 켜진 계정")
    n = 0
    for d in users(tok):
        f = d.get("fields", {})
        if field(f, "canPay") is True:
            n += 1
            print("  · %-14s %s  (켠 시각 %s)"
                  % (field(f, "nickname") or "(닉없음)",
                     field(f, "email") or "",
                     str(field(f, "canPayAt") or "")[:19]))
    if not n:
        print("  없음")
    print()
    print("운영자(isGm)")
    for d in users(tok):
        f = d.get("fields", {})
        if field(f, "isGm") is True:
            print("  · %-14s %s" % (field(f, "nickname") or "(닉없음)",
                                    field(f, "email") or ""))
    sys.exit(0)

if not args:
    print("닉네임을 적어주세요. 예: python tools/set_canpay.py 심사용")
    sys.exit(1)

target = args[0]
found = None
for d in users(tok):
    if field(d.get("fields", {}), "nickname") == target:
        found = d
        break

if not found:
    print("'" + target + "' 닉네임을 찾지 못했습니다.")
    sys.exit(1)

uid = found["name"].split("/")[-1]
f = found.get("fields", {})
print("계정   : %s (%s)" % (target, field(f, "email") or ""))
print("uid    : " + uid)
print("지금   : 결제허용 %s · 운영자 %s"
      % (field(f, "canPay") is True, field(f, "isGm") is True))

if not (ON or OFF):
    print()
    print("바꾸려면 --on 또는 --off 를 붙여 다시 실행하세요.")
    sys.exit(0)

body = {"fields": {
    "canPay": {"booleanValue": bool(ON)},
    "canPayAt": {"timestampValue":
                 datetime.datetime.now(datetime.timezone.utc)
                 .strftime("%Y-%m-%dT%H:%M:%SZ")},
}}
call(BASE + "/users/" + uid +
     "?updateMask.fieldPaths=canPay&updateMask.fieldPaths=canPayAt",
     tok, json.dumps(body).encode("utf-8"), "PATCH")
print()
print("결제 허용을 " + ("켰습니다." if ON else "껐습니다."))
if ON:
    print("⚠️ 테스트 채널이라 결제해도 돈이 안 나갑니다.")
    print("   심사가 끝나면 --off 로 꼭 꺼주세요.")
