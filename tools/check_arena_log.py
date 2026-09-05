# -*- coding: utf-8 -*-
"""
⚔️📋 아레나 접속 기록 보기 — "대회 중에 튕겼다"는 제보를 확인할 때 쓴다.

  · 정상          : exitAt 있음 (reason=finished 경기 완주 / left 스스로 나감)
  · ⚠️ 튕김       : exitAt 없이 disconnectedAt 만 있음 (창 닫힘·네트워크 끊김·크래시)
  · ❓ 기록 미완  : 둘 다 없음 (아직 경기 중이거나 아주 옛날 기록)

  마지막으로 살아있던 순간은 beat 시각이다. left(남은시간)를 보면 몇 분에 끊겼는지 나온다.

사용법:
    python tools/check_arena_log.py                 # 최근 기록 전부
    python tools/check_arena_log.py 낚시신동         # 그 조사님 것만
    python tools/check_arena_log.py --drop          # 튕긴 것만
"""
import io
import json
import os
import sys
import datetime
import urllib.request
import urllib.parse

DB = "https://camnak-fishing-default-rtdb.asia-southeast1.firebasedatabase.app"


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


def kst(ms):
    if not ms:
        return "-"
    t = datetime.datetime.utcfromtimestamp(ms / 1000.0) + datetime.timedelta(hours=9)
    return t.strftime("%m/%d %H:%M:%S")


def mmss(sec):
    try:
        sec = int(sec)
    except (TypeError, ValueError):
        return "-"
    return "%d:%02d" % (sec // 60, sec % 60)


nick_filter = None
only_drop = "--drop" in sys.argv
for a in sys.argv[1:]:
    if not a.startswith("--"):
        nick_filter = a

tok = token()
url = DB + "/arena_logs.json?access_token=" + tok
data = json.load(urllib.request.urlopen(url)) or {}

rows = []
for room, players in data.items():
    if not isinstance(players, dict):
        continue
    for uid, v in players.items():
        if not isinstance(v, dict):
            continue
        rows.append((v.get("joinedAt") or 0, room, uid, v))
rows.sort(reverse=True)

print("아레나 접속 기록  (총 %d건)" % len(rows))
print("=" * 78)
shown = 0
for joined, room, uid, v in rows:
    nick = v.get("nick", "?")
    if nick_filter and nick != nick_filter:
        continue
    exit_at = v.get("exitAt")
    dis_at = v.get("disconnectedAt")
    if exit_at:
        mark, note = "정상", v.get("reason", "")
    elif dis_at:
        mark, note = "⚠️ 튕김", "끊김 " + kst(dis_at)
    else:
        mark, note = "❓ 미완", ""
    if only_drop and mark != "⚠️ 튕김":
        continue
    shown += 1
    print("%-10s %-8s %s  방[%s]" % (nick, mark, kst(joined), v.get("room", "")))
    print("    마지막 신호 %s / 남은시간 %s / 마릿수 %s%s"
          % (kst(v.get("beat")), mmss(v.get("left")), v.get("score", 0),
             ("  · " + note) if note else ""))
    print("    room=%s uid=%s" % (room, uid))
    print()

if shown == 0:
    print("(해당 기록 없음)")
