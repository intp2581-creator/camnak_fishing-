# -*- coding: utf-8 -*-
"""엠블럼: 인벤에서 눌러 활성화 + 낚시터에서만 차감 + 다 쓰면 삭제."""
import io

P = 'lib/ui_fishing.dart'
s = io.open(P, encoding='utf-8').read()

# ── 1) 인벤 탭: EVENT 아이템 분기 교체 ──────────────
old_tap = """    // 🎁 이벤트 아이템은 가방 보유만으로 자동 적용 — 장착 불필요(미끼 슬롯 오장착·소모 버그 방지)
    if ((item['type'] ?? '') == 'EVENT') {
      _showNotificationPopup('🎁 이벤트 아이템', '${item['name']}은(는) 가방에 있으면\\n효과가 자동으로 적용돼요.\\n따로 장착하지 않아도 됩니다!', const Color(0xFFD4AF37));
      return;
    }"""
new_tap = """    // 🎁 이벤트 아이템
    if ((item['type'] ?? '') == 'EVENT') {
      // 🛡️ secLeft 방식(엠블럼 등)은 눌러서 활성화하는 아이템
      if (item.containsKey('secLeft')) { _useEmblem(item); return; }
      _showNotificationPopup('🎁 이벤트 아이템', '${item['name']}은(는) 가방에 있으면\\n효과가 자동으로 적용돼요.\\n따로 장착하지 않아도 됩니다!', const Color(0xFFD4AF37));
      return;
    }"""
assert old_tap in s, "EVENT 탭 분기 못 찾음"
s = s.replace(old_tap, new_tap, 1)

# ── 2) 활성화 함수 ─────────────────────────────────
anchor = "  // ⚡ 버프 표시 칩"
fn = """// 🛡️ 엠블럼 활성화 — 받으면 잠자고 있다가, 눌러야 시간이 흐른다.
  void _useEmblem(Map<String, dynamic> item) {
    audioManager.playSfx('sfx_click.mp3');
    final int sec = (item['secLeft'] is num) ? (item['secLeft'] as num).toInt() : 0;
    final bool on = item['active'] == true;
    final st = item['stats'] is Map ? item['stats'] as Map : const {};
    final int p = (st['P'] is num) ? (st['P'] as num).toInt() : 0;

    if (on) {
      _showNotificationPopup('🛡️ ${item['name']}',
          '이미 사용 중이에요.\\n남은 시간 ${boostLeftStr(sec)}\\n\\n낚시터에 있는 동안에만 줄어들어요.',
          const Color(0xFF6BE58A));
      return;
    }
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.grey.shade900,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
            side: const BorderSide(color: Color(0xFFD4AF37))),
        title: Text('${item['name']} 사용',
            style: const TextStyle(color: Color(0xFFD4AF37), fontWeight: FontWeight.bold)),
        content: Text(
            '${item['name']}을(를) 사용하시겠습니까?\\n\\n'
            '🛡️ ${(sec / 60).round()}분 동안 힘·컨트롤·감도가 각각 +$p 올라갑니다.\\n'
            '낚시터에 있는 동안에만 시간이 줄어들어요.\\n\\n'
            '⚔️ 아레나에서는 적용되지 않아요.',
            style: const TextStyle(color: Colors.white, height: 1.5)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('취소', style: TextStyle(color: Colors.grey))),
          TextButton(
              style: TextButton.styleFrom(foregroundColor: const Color(0xFFD4AF37)),
              onPressed: () async {
                Navigator.pop(ctx);
                await _activateEmblem(item);
              },
              child: const Text('사용하기', style: TextStyle(fontWeight: FontWeight.bold))),
        ],
      ),
    );
  }

  Future<void> _activateEmblem(Map<String, dynamic> item) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final ref = FirebaseFirestore.instance.collection('users').doc(user.uid);
      final inv = List<dynamic>.from(((await ref.get()).data() ?? {})['inventory'] ?? []);
      final i = inv.indexWhere((x) =>
          x is Map && (x['name'] ?? '') == item['name'] && x['active'] != true);
      if (i < 0) return;
      inv[i] = {...inv[i] as Map, 'active': true};
      await ref.update({'inventory': inv});
      if (!mounted) return;
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('🛡️ ${item['name']} 사용! 낚시터에서 시간이 줄어들어요'),
      ));
    } catch (e) {
      debugPrint('엠블럼 활성화 실패: $e');
    }
  }

  // ⚡ 버프 표시 칩"""
assert anchor in s, "칩 앵커 못 찾음"
s = s.replace(anchor, fn, 1)

# ── 3) 낚시터 1초 틱에서 엠블럼도 차감 ──────────────
old_tick = """        if (remainingTimeNotifier.value % 3 == 0) {
          _saveDailyTimeToFirebase(remainingTimeNotifier.value);
          _saveBoostsToFirebase();   // ⚡ 버프 남은 시간도 같은 주기로
        }"""
new_tick = """        if (remainingTimeNotifier.value % 3 == 0) {
          _saveDailyTimeToFirebase(remainingTimeNotifier.value);
          _saveBoostsToFirebase();   // ⚡ 버프 남은 시간도 같은 주기로
          if (!arenaNow) _tickEmblem(3);   // 🛡️ 활성화된 엠블럼 3초씩 차감
        }"""
assert old_tick in s, "저장 주기 앵커 못 찾음"
s = s.replace(old_tick, new_tick, 1)

# ── 4) 엠블럼 차감 함수 ────────────────────────────
anchor2 = """  // ⚡ 버프 남은 시간 저장 — 낚시시간과 같은 3초 주기(F5 익스플로잇 차단)"""
ticker = """  // 🛡️ 활성화된 엠블럼 차감 — 낚시터에 있는 동안에만. 다 쓰면 인벤에서 삭제.
  //    인벤 안의 값이라 물약처럼 전역으로 못 두고, 저장 주기에 맞춰 함께 처리한다.
  Future<void> _tickEmblem(int sec) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final ref = FirebaseFirestore.instance.collection('users').doc(user.uid);
      final inv = List<dynamic>.from(_latestInventory);
      bool changed = false;
      for (int i = inv.length - 1; i >= 0; i--) {
        final it = inv[i];
        if (it is! Map) continue;
        if ((it['type'] ?? '') != 'EVENT') continue;
        if (!it.containsKey('secLeft') || it['active'] != true) continue;
        final int left = ((it['secLeft'] is num) ? (it['secLeft'] as num).toInt() : 0) - sec;
        if (left <= 0) { inv.removeAt(i); } else { inv[i] = {...it, 'secLeft': left}; }
        changed = true;
      }
      if (changed) await ref.update({'inventory': inv});
    } catch (_) {}
  }

  // ⚡ 버프 남은 시간 저장 — 낚시시간과 같은 3초 주기(F5 익스플로잇 차단)"""
assert anchor2 in s, "저장 함수 앵커 못 찾음"
s = s.replace(anchor2, ticker, 1)

io.open(P, 'w', encoding='utf-8', newline='').write(s)
print("ui_fishing.dart — 엠블럼 활성화·차감 적용")
