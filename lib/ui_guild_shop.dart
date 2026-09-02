// 🏪 [길드 상점] 길드 전용 아이템 상점.
//   판매 품목 = 보스레이드 전용 낚싯대 3종(storeGuildRaidRods). 화폐 = 포인트(gold).
//   레이드대는 보스레이드 참여 입장권 겸 제압력. 일반 상점엔 안 뜨고 여기서만 판매.
// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'game_config.dart';

const Color _kGold = Color(0xFFD4AF37);

class GuildShopScreen extends StatefulWidget {
  final String guildName;
  const GuildShopScreen({super.key, required this.guildName});

  @override
  State<GuildShopScreen> createState() => _GuildShopScreenState();
}

class _GuildShopScreenState extends State<GuildShopScreen> {
  bool _loading = true;
  bool _buying = false;
  int _gold = 0;
  int _level = 1; // 🆙 레벨(레이드대 reqLevel 체크용)
  List<dynamic> _inventory = [];

  @override
  void initState() {
    super.initState();
    _loadMe();
  }

  Future<void> _loadMe() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) { setState(() => _loading = false); return; }
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      final d = doc.data() ?? {};
      if (!mounted) return;
      setState(() {
        _gold = (d['gold'] is num) ? (d['gold'] as num).toInt() : 0;
        _level = calcLevelFromExp((d['exp'] is num) ? (d['exp'] as num).toInt() : 0);
        _inventory = List.from(d['inventory'] ?? []);
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool _owned(String name) => _inventory.any((i) => (i['name'] ?? '') == name);

  Future<void> _buy(Map<String, dynamic> item) async {
    if (_buying) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final int price = (item['price'] as num).toInt();
    if (_owned(item['name'])) { _popup('🛑 구매 불가', '이미 보유 중인 낚싯대예요!', Colors.orangeAccent); return; }
    // 🆙 레벨 제한 — 라이트닝 Lv.50 · 인페르노 Lv.100 (레벨 미달 시 구매 불가)
    final int reqLv = (item['reqLevel'] is num) ? (item['reqLevel'] as num).toInt() : 0;
    if (_level < reqLv) { _popup('🔒 레벨 부족', 'Lv.$reqLv 부터 구매할 수 있어요!\n(현재 Lv.$_level)\n레벨을 더 올려서 도전하세요 🎣', Colors.orangeAccent); return; }
    if (_gold < price) { _popup('🚫 KREFT 부족', 'KREFT가 부족해요!\n열심히 고기를 잡아 모아보세요.', Colors.redAccent); return; }

    setState(() => _buying = true);
    try {
      final ref = FirebaseFirestore.instance.collection('users').doc(user.uid);
      final snap = await ref.get();
      final List<dynamic> inv = List.from(snap.data()?['inventory'] ?? []);
      final int curGold = (snap.data()?['gold'] is num) ? (snap.data()!['gold'] as num).toInt() : 0;
      if (curGold < price) { setState(() => _buying = false); _popup('🚫 KREFT 부족', 'KREFT가 부족해요!', Colors.redAccent); return; }
      if (inv.any((i) => (i['name'] ?? '') == item['name'])) {
        setState(() { _buying = false; _inventory = inv; }); _popup('🛑 구매 불가', '이미 보유 중이에요!', Colors.orangeAccent); return;
      }
      inv.add({
        'name': item['name'], 'category': item['category'], 'type': item['type'],
        'stats': item['stats'], 'icon': item['icon'], 'quantity': 1,
      });
      await ref.update({'gold': FieldValue.increment(-price), 'inventory': inv});
      if (!mounted) return;
      setState(() { _gold = curGold - price; _inventory = inv; _buying = false; });
      _popup('🎉 구매 완료', '${item['name']}\n보스레이드에서 이 낚싯대로 도전하세요!\n인벤토리에서 장착할 수 있어요.', _kGold);
    } catch (e) {
      if (mounted) setState(() => _buying = false);
      _popup('오류', '구매 처리 중 문제가 발생했어요.', Colors.redAccent);
    }
  }

  void _popup(String title, String msg, Color c) {
    if (!mounted) return;
    showDialog(context: context, builder: (ctx) => AlertDialog(
      backgroundColor: const Color(0xFF1A1712),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: c.withOpacity(0.5))),
      title: Text(title, style: TextStyle(color: c, fontWeight: FontWeight.w900)),
      content: Text(msg, style: const TextStyle(color: Colors.white70, height: 1.5)),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('확인', style: TextStyle(color: _kGold, fontWeight: FontWeight.bold)))],
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF14110C),
      body: SafeArea(
        child: Stack(children: [
          Positioned(top: 8, left: 8, child: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white70),
            onPressed: () => Navigator.pop(context),
          )),
          Positioned(top: 16, right: 20, child: Text('내 KREFT: $_gold',
              style: const TextStyle(color: Colors.yellowAccent, fontWeight: FontWeight.bold, fontSize: 16))),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const SizedBox(height: 8),
                const Text('🏪 길드 상점', style: TextStyle(color: _kGold, fontSize: 26, fontWeight: FontWeight.w900)),
                const SizedBox(height: 4),
                Text('[${widget.guildName}] 전용 · 보스레이드 낚싯대',
                    style: const TextStyle(color: Colors.white54, fontSize: 13)),
                const SizedBox(height: 6),
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.35),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _kGold.withOpacity(0.3)),
                  ),
                  child: const Text('🐲 레이드 전용 낚싯대가 있어야 보스레이드에 참여할 수 있어요!',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Color(0xFFF3D874), fontSize: 13, fontWeight: FontWeight.w700)),
                ),
                const SizedBox(height: 6),
                if (_loading)
                  const Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator(color: _kGold))
                else
                  Flexible(child: SingleChildScrollView(
                    child: Column(children: [
                      for (final rod in storeGuildRaidRods) _rodCard(rod),
                    ]),
                  )),
                const SizedBox(height: 12),
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _rodCard(Map<String, dynamic> rod) {
    final int tier = (rod['raidTier'] as num).toInt();
    final int price = (rod['price'] as num).toInt();
    final stats = rod['stats'] as Map;
    final bool owned = _owned(rod['name']);
    final bool canAfford = _gold >= price;
    final int reqLv = (rod['reqLevel'] is num) ? (rod['reqLevel'] as num).toInt() : 0;
    final bool lvOk = _level >= reqLv;
    // 티어색: 1 초록 · 2 파랑 · 3 주황
    final Color tierColor = tier == 1 ? const Color(0xFF5FCf7A) : tier == 2 ? const Color(0xFF5FA8FF) : const Color(0xFFFF7A3C);
    final String iconPath = 'assets/items/${rod['icon']}';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.4),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: tierColor.withOpacity(0.55), width: 1.5),
      ),
      child: Row(children: [
        // 아이콘
        Container(
          width: 78, height: 78,
          decoration: BoxDecoration(color: Colors.white.withOpacity(0.04), borderRadius: BorderRadius.circular(10)),
          child: Image.asset(iconPath, fit: BoxFit.contain,
              errorBuilder: (c, e, s) => Icon(Icons.phishing, color: tierColor, size: 40)),
        ),
        const SizedBox(width: 12),
        // 정보
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(color: tierColor.withOpacity(0.2), borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: tierColor.withOpacity(0.6))),
              child: Text('TIER $tier', style: TextStyle(color: tierColor, fontSize: 11, fontWeight: FontWeight.w900)),
            ),
            const SizedBox(width: 8),
            Flexible(child: Text(rod['name'], style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900), overflow: TextOverflow.ellipsis)),
          ]),
          const SizedBox(height: 4),
          Text(rod['desc'], style: const TextStyle(color: Colors.white54, fontSize: 12), maxLines: 2, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 4),
          Text('제압 ${stats['P']}  ·  컨트롤 ${stats['C']}  ·  감도 ${stats['S']}',
              style: TextStyle(color: tierColor, fontSize: 12, fontWeight: FontWeight.bold)),
          if (reqLv > 0) ...[
            const SizedBox(height: 3),
            Text(lvOk ? '✅ Lv.$reqLv 이상' : '🔒 Lv.$reqLv 부터 구매 가능 (현재 Lv.$_level)',
                style: TextStyle(color: lvOk ? const Color(0xFF7FFFB0) : Colors.orangeAccent, fontSize: 11.5, fontWeight: FontWeight.w800)),
          ],
        ])),
        const SizedBox(width: 10),
        // 가격/구매
        Column(mainAxisSize: MainAxisSize.min, children: [
          Text('$price KREFT', style: TextStyle(color: canAfford || owned ? Colors.yellowAccent : Colors.redAccent, fontSize: 13, fontWeight: FontWeight.w900)),
          const SizedBox(height: 6),
          SizedBox(width: 88, height: 34, child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: owned ? Colors.grey.shade700 : (lvOk ? tierColor : Colors.grey.shade800),
              foregroundColor: owned ? Colors.white70 : (lvOk ? Colors.black : Colors.white38),
              padding: EdgeInsets.zero,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
            ),
            onPressed: owned || _buying || !lvOk ? null : () => _buy(rod),
            child: Text(owned ? '보유중' : (lvOk ? '구매' : '🔒'), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
          )),
        ]),
      ]),
    );
  }
}
