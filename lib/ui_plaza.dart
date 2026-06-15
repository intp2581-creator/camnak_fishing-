// ignore_for_file: deprecated_member_use, use_build_context_synchronously
// 🏛️ [광장 시스템] 낚시터별 광장(허브). 1단계: 나 혼자 걸어다니며 상점/아레나/포탈/낚시 진입.
//    2단계에서 RTDB로 다른 유저 실시간 표시 예정.
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'game_config.dart';
import 'fishing_logic.dart';
import 'ui_fishing.dart';
import 'ui_lobby.dart'; // StoreScreen
import 'ui_arena.dart'; // ArenaScreen

const Color _kGold = Color(0xFFD4AF37);

class PlazaScreen extends StatefulWidget {
  final String nickname;
  final int level;
  final Map<String, dynamic> spot; // {name, target, stars, image}
  final bool isSea;
  final bool isFirstTime;

  const PlazaScreen({
    super.key,
    required this.nickname,
    required this.level,
    required this.spot,
    this.isSea = false,
    this.isFirstTime = false,
  });

  // 🚪 기본 진입 광장(예산 예당지)
  factory PlazaScreen.defaultEntry({
    required String nickname,
    required int level,
    bool isFirstTime = false,
  }) {
    final spot = locations['저수지']![0]; // 예산 예당지
    return PlazaScreen(
      nickname: nickname,
      level: level,
      spot: spot,
      isSea: false,
      isFirstTime: isFirstTime,
    );
  }

  @override
  State<PlazaScreen> createState() => _PlazaScreenState();
}

class _PlazaScreenState extends State<PlazaScreen> {
  bool _loading = true;
  int _gold = 0;
  int _level = 1;
  List<dynamic> _inventory = [];

  // 캐릭터 위치 (0~1 비율 좌표, dy는 발 위치 기준)
  Offset _charPos = const Offset(0.5, 0.82);
  bool _facingRight = true;
  Duration _moveDuration = const Duration(milliseconds: 500);

  @override
  void initState() {
    super.initState();
    _level = widget.level;
    _loadUser();
  }

  Future<void> _loadUser() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      final data = doc.data() ?? {};
      _gold = (data['gold'] ?? 0) is int ? (data['gold'] ?? 0) as int : 0;
      _inventory = (data['inventory'] ?? []) as List<dynamic>;
      final exp = (data['exp'] ?? 0) is int ? (data['exp'] ?? 0) as int : 0;
      currentExp = exp;
      currentPoints = _gold;
      _level = calcLevelFromExp(exp);
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  String get _charImage {
    if (globalEquippedSkin != null) {
      return FishingLogic.getLobbyCharacterImage(globalEquippedSkin!['name'].toString());
    }
    // 인벤토리에 보유한 최고 스킨 추정 (장착정보 없을 때 대비)
    final skinNames = _inventory
        .where((i) => (i['category'] == 'SKIN' || i['type'] == 'SKIN'))
        .map((i) => i['name'].toString())
        .toList();
    for (final tier in ['마스터', '프로', '고수', '중수', '하수']) {
      if (skinNames.any((n) => n.contains(tier))) {
        return FishingLogic.getLobbyCharacterImage(tier);
      }
    }
    return 'assets/images/char_beginner.png';
  }

  void _moveTo(Offset target, double w, double h) {
    final dx = (target.dx - _charPos.dx) * w;
    final dy = (target.dy - _charPos.dy) * h;
    final dist = math.sqrt(dx * dx + dy * dy);
    final ms = (dist / 0.5).clamp(250, 1500).toInt(); // 이동 속도
    setState(() {
      _facingRight = target.dx >= _charPos.dx;
      // dy는 바닥(걷는 구역)으로만 제한 — 너무 위로 못 올라가게
      final clampedY = target.dy.clamp(0.62, 0.92);
      _charPos = Offset(target.dx.clamp(0.05, 0.95), clampedY);
      _moveDuration = Duration(milliseconds: ms);
    });
  }

  // ---- 진입 액션들 (기존 화면 재활용) ----
  void _goFishing() {
    final loc = widget.spot;
    globalIsSeaMode = widget.isSea;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FishingScreen(
          nickname: widget.nickname,
          locationName: loc['name'],
          winCondition: '마릿수',
          title: loc['name'],
          bgImagePath: loc['image'],
          characterImagePath: 'assets/images/character.png',
          isSea: widget.isSea,
          isFirstTime: widget.isFirstTime,
        ),
      ),
    );
  }

  void _openStore() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StoreScreen(
          currentGold: _gold,
          currentLevel: _level,
          currentInventory: _inventory,
        ),
      ),
    );
  }

  void _openArena() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const ArenaScreen()));
  }

  void _openRanking() {
    // TODO(2단계 전): 전용 랭킹 화면으로 분리 예정. 지금은 안내만.
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.grey.shade900,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
            side: const BorderSide(color: _kGold)),
        title: const Text('🏆 랭킹', style: TextStyle(color: _kGold, fontWeight: FontWeight.bold)),
        content: const Text('랭킹 보드는 곧 광장 NPC로 들어옵니다.\n(다음 업데이트)',
            style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('확인', style: TextStyle(color: _kGold)))
        ],
      ),
    );
  }

  // 🗺️ 미니맵(세계지도) — 다른 낚시터 광장으로 이동
  void _openMinimap() {
    final entries = <Map<String, dynamic>>[];
    locations.forEach((category, spots) {
      final sea = (category == '갯바위' || category == '선상');
      for (final s in spots) {
        entries.add({'spot': s, 'category': category, 'isSea': sea});
      }
    });

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: const Color(0xFF141414),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: _kGold, width: 1.5)),
        child: SizedBox(
          width: 720,
          height: 560,
          child: Column(
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('🗺️  어느 낚시터로 떠날까요?',
                    style: TextStyle(color: _kGold, fontSize: 20, fontWeight: FontWeight.w900)),
              ),
              const Divider(color: Colors.white12, height: 1),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: entries.length,
                  itemBuilder: (c, i) {
                    final e = entries[i];
                    final s = e['spot'] as Map<String, dynamic>;
                    final isHere = s['name'] == widget.spot['name'];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: isHere ? _kGold.withOpacity(0.12) : Colors.grey.shade900,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: isHere ? _kGold : Colors.white10,
                            width: isHere ? 1.5 : 1),
                      ),
                      child: ListTile(
                        leading: Text(e['isSea'] as bool ? '🌊' : '🏞️',
                            style: const TextStyle(fontSize: 22)),
                        title: Text(s['name'],
                            style: const TextStyle(
                                color: Colors.white, fontWeight: FontWeight.bold, fontSize: 17)),
                        subtitle: Row(
                          children: List.generate(
                            5,
                            (k) => Icon(
                                k < (s['stars'] as int) ? Icons.star : Icons.star_border,
                                color: _kGold,
                                size: 15),
                          ),
                        ),
                        trailing: isHere
                            ? const Text('현재 위치',
                                style: TextStyle(color: _kGold, fontWeight: FontWeight.bold))
                            : const Icon(Icons.arrow_forward_ios, color: Colors.white38, size: 16),
                        onTap: isHere
                            ? null
                            : () {
                                Navigator.pop(ctx);
                                Navigator.pushReplacement(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => PlazaScreen(
                                      nickname: widget.nickname,
                                      level: _level,
                                      spot: s,
                                      isSea: e['isSea'] as bool,
                                    ),
                                  ),
                                );
                              },
                      ),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(10),
                child: TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('닫기', style: TextStyle(color: Colors.white54))),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: _kGold)),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: LayoutBuilder(
        builder: (context, c) {
          final w = c.maxWidth;
          final h = c.maxHeight;
          final charH = h * 0.34;
          final charW = charH * 0.55;

          return Stack(
            children: [
              // 1) 배경 (임시: 해당 낚시터 배경 + 어둠막) — 추후 광장 전용 그림으로 교체
              Positioned.fill(
                child: Image.asset(
                  widget.spot['image'],
                  fit: BoxFit.cover,
                  errorBuilder: (a, b, d) => Container(color: const Color(0xFF11202E)),
                ),
              ),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withOpacity(0.35),
                        Colors.black.withOpacity(0.15),
                        Colors.black.withOpacity(0.55),
                      ],
                    ),
                  ),
                ),
              ),

              // 2) 바닥 탭 → 캐릭터 이동
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapUp: (d) => _moveTo(Offset(d.localPosition.dx / w, d.localPosition.dy / h), w, h),
                ),
              ),

              // 3) 내 캐릭터 (탭 통과)
              AnimatedPositioned(
                duration: _moveDuration,
                curve: Curves.easeInOut,
                left: _charPos.dx * w - charW / 2,
                top: _charPos.dy * h - charH,
                width: charW,
                height: charH,
                child: IgnorePointer(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 닉네임/레벨 머리표
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.6),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: _kGold.withOpacity(0.7)),
                        ),
                        child: Text('Lv.$_level ${widget.nickname}',
                            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                      ),
                      Expanded(
                        child: Transform(
                          alignment: Alignment.center,
                          transform: Matrix4.rotationY(_facingRight ? 0 : math.pi),
                          child: Image.asset(_charImage,
                              fit: BoxFit.contain,
                              errorBuilder: (a, b, d) => const SizedBox.shrink()),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // 4) NPC / 시설들
              _npc(w, h, 0.16, 0.50, '🏪', '상점', _openStore),
              _npc(w, h, 0.37, 0.46, '🏆', '랭킹', _openRanking),
              _npc(w, h, 0.58, 0.46, '⚔️', '아레나', _openArena),
              _npc(w, h, 0.82, 0.52, '🌀', '포탈', _openMinimap),

              // 5) 상단 HUD
              _topHud(),

              // 6) 낚시 시작 버튼 (이 낚시터에서 바로 낚시)
              Positioned(
                left: 0,
                right: 0,
                bottom: 24,
                child: Center(
                  child: ElevatedButton.icon(
                    onPressed: _goFishing,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _kGold,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                      elevation: 8,
                    ),
                    icon: const Text('🎣', style: TextStyle(fontSize: 20)),
                    label: const Text('낚시 시작',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // NPC 한 명 (이모지 뱃지 + 라벨)
  Widget _npc(double w, double h, double cx, double cy, String emoji, String label, VoidCallback onTap) {
    const double npcW = 96;
    const double npcH = 96;
    return Positioned(
      left: cx * w - npcW / 2,
      top: cy * h - npcH / 2,
      width: npcW,
      height: npcH,
      child: GestureDetector(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.black.withOpacity(0.55),
                border: Border.all(color: _kGold, width: 2),
                boxShadow: [BoxShadow(color: _kGold.withOpacity(0.4), blurRadius: 10)],
              ),
              child: Center(child: Text(emoji, style: const TextStyle(fontSize: 28))),
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.7),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(label,
                  style: const TextStyle(color: _kGold, fontSize: 13, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _topHud() {
    return Positioned(
      top: 16,
      left: 16,
      right: 16,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // 현재 낚시터
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.6),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _kGold.withOpacity(0.6)),
            ),
            child: Row(
              children: [
                Text(widget.isSea ? '🌊' : '🏞️', style: const TextStyle(fontSize: 18)),
                const SizedBox(width: 8),
                Text(widget.spot['name'],
                    style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900)),
                const SizedBox(width: 8),
                ...List.generate(
                  widget.spot['stars'] as int,
                  (i) => const Icon(Icons.star, color: _kGold, size: 14),
                ),
              ],
            ),
          ),
          // 내 정보
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.6),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _kGold.withOpacity(0.6)),
            ),
            child: Row(
              children: [
                Text('Lv.$_level',
                    style: const TextStyle(color: _kGold, fontWeight: FontWeight.w900, fontSize: 16)),
                const SizedBox(width: 10),
                Text(widget.nickname,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(width: 12),
                const Icon(Icons.toll, color: _kGold, size: 16),
                const SizedBox(width: 4),
                Text('$_gold',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
