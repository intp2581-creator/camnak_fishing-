# -*- coding: utf-8 -*-
"""접속 시 users 문서에서 버프 만료시각을 읽어 전역에 채운다.
   광장의 기존 정리 함수(_cleanupExpiredEventItems)가 이미 users 문서를
   읽고 있으므로 거기에 얹는다 — 읽기 횟수를 늘리지 않는다.
"""
import io

P = 'lib/ui_plaza.dart'
s = io.open(P, encoding='utf-8').read()

old = """  // 🎁 만료된 기간제 이벤트 아이템 자동 소멸(접속 시 1회 정리 — 효과는 만료 즉시 무시되므로 정리 지연 무해)
  Future<void> _cleanupExpiredEventItems() async {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) return;
    try {
      final ref = FirebaseFirestore.instance.collection('users').doc(u.uid);
      final inv = List<dynamic>.from(((await ref.get()).data() ?? {})['inventory'] ?? []);
      final cleaned = removeExpiredEventItems(inv);
      if (cleaned != null) await ref.update({'inventory': cleaned});
    } catch (_) {}
  }"""

new = """  // 🎁 만료된 기간제 이벤트 아이템 자동 소멸(접속 시 1회 정리 — 효과는 만료 즉시 무시되므로 정리 지연 무해)
  //    ⚡ 같은 읽기로 개인 버프(물약·카드) 만료시각도 함께 채운다(읽기 횟수 절감).
  Future<void> _cleanupExpiredEventItems() async {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) return;
    try {
      final ref = FirebaseFirestore.instance.collection('users').doc(u.uid);
      final data = (await ref.get()).data() ?? {};
      gBoostExpUntil = (data['boostExpUntil'] is num) ? (data['boostExpUntil'] as num).toInt() : 0;
      gBoostPtsUntil = (data['boostPtsUntil'] is num) ? (data['boostPtsUntil'] as num).toInt() : 0;
      final inv = List<dynamic>.from(data['inventory'] ?? []);
      final cleaned = removeExpiredEventItems(inv);
      if (cleaned != null) await ref.update({'inventory': cleaned});
    } catch (_) {}
  }"""

assert old in s, "광장 정리 함수 못 찾음"
s = s.replace(old, new, 1)
io.open(P, 'w', encoding='utf-8', newline='').write(s)
print("ui_plaza.dart — 버프 상태 로드 추가")

# 낚시터 진입 시에도 최신값을 읽는다 (광장을 안 거치고 들어오는 경우 대비)
P2 = 'lib/ui_fishing.dart'
s2 = io.open(P2, encoding='utf-8').read()
old2 = "    loadGameEvent().then((_) { if (mounted) setState(() {}); }); // 🎉 이벤트 설정 새로고침(배너·배율 반영)"
new2 = """    loadGameEvent().then((_) { if (mounted) setState(() {}); }); // 🎉 이벤트 설정 새로고침(배너·배율 반영)
    _loadMyBoosts(); // ⚡ 개인 버프(물약·카드) 남은 시간 불러오기"""
assert old2 in s2, "낚시터 진입 앵커 못 찾음"
s2 = s2.replace(old2, new2, 1)

# 로더 함수 추가
anchor2 = "  // ⚡ 물약·카드 사용 — 확인창 → 소모 + 만료시각 기록(users 문서)"
loader = """  // ⚡ 내 버프 만료시각 불러오기(낚시터 직행 대비 — 광장에서도 같은 값을 채운다)
  Future<void> _loadMyBoosts() async {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) return;
    try {
      final d = (await FirebaseFirestore.instance.collection('users').doc(u.uid).get()).data() ?? {};
      gBoostExpUntil = (d['boostExpUntil'] is num) ? (d['boostExpUntil'] as num).toInt() : 0;
      gBoostPtsUntil = (d['boostPtsUntil'] is num) ? (d['boostPtsUntil'] as num).toInt() : 0;
      if (mounted) setState(() {});
    } catch (_) {}
  }

  // ⚡ 물약·카드 사용 — 확인창 → 소모 + 만료시각 기록(users 문서)"""
assert anchor2 in s2, "버프 함수 앵커 못 찾음"
s2 = s2.replace(anchor2, loader, 1)
io.open(P2, 'w', encoding='utf-8', newline='').write(s2)
print("ui_fishing.dart — 버프 로더 추가")
