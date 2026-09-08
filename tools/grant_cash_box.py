# -*- coding: utf-8 -*-
"""
📦 착용 아이템 상자 지급 — 결제로 지급되는 것과 똑같은 모양으로 넣는다.

결제를 거치지 않고 테스트하거나, 민원으로 재지급할 때 쓴다.
functions/payment.js 의 PRODUCTS 와 같은 구성이라 실제 구매와 결과가 같다.

사용법:
    python tools/grant_cash_box.py --nick 아레투사 --all           # 전부 하나씩(미리보기)
    python tools/grant_cash_box.py --nick 아레투사 --all --apply   # 실제 지급
    python tools/grant_cash_box.py --nick 아레투사 --item badge_1 --apply
    python tools/grant_cash_box.py --list           # 지급 가능한 상품 목록

옵션:
    --nick   대상 닉네임        --item  상품 키(아래 --list 참고)
    --all    지급표에 있는 상품을 전부 하나씩
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

# 📦 지급표를 여기에 베껴 두지 않는다 — functions/payment.js 를 그대로 읽는다.
#    예전엔 스킨·뱃지 8종을 손으로 적어 뒀는데, 이용권이 상자로 바뀌어도(2026-09-08)
#    이 목록엔 반영되지 않아 '지급표엔 있는데 도구엔 없는' 상품이 생겼다.
def load_products():
    import subprocess
    here = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    out = subprocess.run(
        ["node", "-e",
         "console.log(JSON.stringify(require('./functions/payment.js').PRODUCTS))"],
        cwd=here, capture_output=True, text=True, encoding="utf-8", shell=True)
    if out.returncode != 0:
        print("지급표를 읽지 못했습니다:", (out.stderr or "").strip()[:200])
        sys.exit(1)
    raw = json.loads(out.stdout)
    # 상자로 지급되는 것만 다룬다(구성품이 있는 것 = 상자).
    return {k: v for k, v in raw.items() if isinstance(v.get("bundle"), list)}


PRODUCTS = load_products()


def make_box(key, p, gid):
    """functions/payment.js cashBox() 와 같은 모양이어야 한다.
       다르면 '산 것'과 '받은 것'이 가방에서 다르게 보인다."""
    return {
        "name": p.get("boxName") or p["name"],
        "category": "BOX", "type": "BOX", "quantity": 1, "cash": True,
        "icon": p.get("boxIcon") or "item_box_cash.png",
        "gid": gid,
        "giftTitle": p["name"],
        "giftMsg": p.get("boxMsg", ""),
        "gift": [dict(b, quantity=b.get("qty", 1)) for b in p["bundle"]],
        "desc": p["name"] + NL + p.get("boxMsg", "") + NL + NL + "눌러서 열어보세요.",
    }


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
ALL = "--all" in sys.argv
if not nick or (not ALL and key not in PRODUCTS):
    print(__doc__)
    sys.exit(1)

gid0 = arg("--gid") or ("test-" + datetime.datetime.now().strftime("%Y%m%d%H%M%S"))
keys = list(PRODUCTS.keys()) if ALL else [key]

boxes = []
for i, k in enumerate(keys):
    p = PRODUCTS[k]
    boxes.append(make_box(k, p, gid0 + ("-" + str(i + 1) if len(keys) > 1 else "")))

for b in boxes:
    print("📦 " + b["name"])
    print("   담긴 것 : " + ", ".join(
        "%s %d개" % (g["name"], g.get("quantity", 1)) for g in b["gift"]))
print()
print("대상 : " + nick + "  ·  상자 " + str(len(boxes)) + "개")
print("주문번호 : " + gid0)
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

inv2 = inv + [to_fs(b) for b in boxes]
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

# 🧾 채팅창 '시스템' 탭에도 남긴다 — 운영자가 넣어준 것도 유저가 알아야 한다.
#    유저 문서의 systemLog 배열(payment.js sysLog 와 같은 모양). 50건만 남긴다.
now = datetime.datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ")
log = target["fields"].get("systemLog", {}).get("arrayValue", {}).get("values", [])
for b in boxes:
    log.append(to_fs({"kind": "admin", "msg": b["name"] + "를 받았습니다."}))
    log[-1]["mapValue"]["fields"]["t"] = {"timestampValue": now}
log = log[-50:]
try:
    call(BASE + "/users/" + uid + "?updateMask.fieldPaths=systemLog", tok,
         json.dumps({"fields": {"systemLog": {"arrayValue": {"values": log}}}}).encode("utf-8"),
         "PATCH")
    print("🧾 시스템 알림 %d건을 남겼습니다." % len(boxes))
except Exception as e:
    print("   (알림 남기기 실패: %s)" % e)
