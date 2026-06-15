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
import 'ui_ranking.dart'; // RankingScreen (명예의 전당)

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

class _PlazaScreenState extends State<PlazaScreen> with SingleTickerProviderStateMixin {
  bool _loading = true;
  int _gold = 0;
  int _level = 1;
  List<dynamic> _inventory = [];

  // 캐릭터 위치 (0~1 비율 좌표, dy는 발 위치 기준)
  Offset _charPos = const Offset(0.5, 0.74);
  bool _facingRight = true;
  Duration _moveDuration = const Duration(milliseconds: 500);

  // 🚶 걷기 바운스용
  late final AnimationController _walkCtrl;
  bool _walking = false;
  int _moveToken = 0;
  Offset? _lastTap; // 🛠️ 개발용: 마지막 탭 좌표(NPC 위치 잡기용, 추후 제거)

  @override
  void initState() {
    super.initState();
    _level = widget.level;
    _walkCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 340));
    _loadUser();
  }

  @override
  void dispose() {
    _walkCtrl.dispose();
    super.dispose();
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

  // 광장 배경: 타입별 공용 1장 (민물=plaza_fw, 바다=plaza_sea). 파일 없으면 build에서 낚시 배경으로 폴백.
  String get _plazaBg => widget.isSea
      ? 'assets/plaza/plaza_sea.jpg'
      : 'assets/plaza/plaza_fw.jpg';

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

  // 🗺️ 걷기 구역(섬 경계) 다각형 — 타입별. 민물=예당호 광장 빨간라인 좌표.
  static const List<Offset> _freshPoly = [
    Offset(0.00, 1.00), Offset(0.00, 0.58), Offset(0.10, 0.52), Offset(0.23, 0.50),
    Offset(0.28, 0.46), Offset(0.30, 0.34), Offset(0.35, 0.30), Offset(0.48, 0.28),
    Offset(0.56, 0.28), Offset(0.63, 0.30), Offset(0.56, 0.34), Offset(0.57, 0.38),
    Offset(0.66, 0.44), Offset(0.72, 0.46), Offset(0.79, 0.43), Offset(0.80, 0.40),
    Offset(0.89, 0.44), Offset(0.78, 0.48), Offset(0.87, 0.55), Offset(1.00, 1.00),
  ];
  // 바다 광장 임시 경계(넓은 사다리꼴) — 실제 바다 광장 그림 나오면 좌표로 교체
  static const List<Offset> _seaPoly = [
    Offset(0.00, 1.00), Offset(0.05, 0.62), Offset(0.30, 0.50), Offset(0.50, 0.48),
    Offset(0.70, 0.50), Offset(0.95, 0.62), Offset(1.00, 1.00),
  ];
  List<Offset> get _activePoly => widget.isSea ? _seaPoly : _freshPoly;

  // 점이 다각형 안인지 (ray casting)
  bool _inPoly(Offset p) {
    bool inside = false;
    final poly = _activePoly;
    for (int i = 0, j = poly.length - 1; i < poly.length; j = i++) {
      final pi = poly[i], pj = poly[j];
      if (((pi.dy > p.dy) != (pj.dy > p.dy)) &&
          (p.dx < (pj.dx - pi.dx) * (p.dy - pi.dy) / (pj.dy - pi.dy) + pi.dx)) {
        inside = !inside;
      }
    }
    return inside;
  }

  Offset _nearestOnSeg(Offset p, Offset a, Offset b) {
    final dx = b.dx - a.dx, dy = b.dy - a.dy;
    final len2 = dx * dx + dy * dy;
    double t = len2 == 0 ? 0 : ((p.dx - a.dx) * dx + (p.dy - a.dy) * dy) / len2;
    t = t.clamp(0.0, 1.0);
    return Offset(a.dx + t * dx, a.dy + t * dy);
  }

  // 다각형 안이면 그대로, 밖이면 가장 가까운 가장자리 점으로
  Offset _clampToPlaza(Offset p) {
    if (_inPoly(p)) return p;
    final poly = _activePoly;
    Offset best = poly.first;
    double bestD = double.infinity;
    for (int i = 0, j = poly.length - 1; i < poly.length; j = i++) {
      final q = _nearestOnSeg(p, poly[j], poly[i]);
      final d = (q - p).distanceSquared;
      if (d < bestD) {
        bestD = d;
        best = q;
      }
    }
    return best;
  }

  void _moveTo(Offset rawTarget, double w, double h) {
    final dest = _clampToPlaza(rawTarget); // 섬 안으로 보정
    final dx = (dest.dx - _charPos.dx) * w;
    final dy = (dest.dy - _charPos.dy) * h;
    final dist = math.sqrt(dx * dx + dy * dy);
    final ms = (dist / 0.32).clamp(350, 2200).toInt(); // 걷기 속도(등속)
    final moveDur = Duration(milliseconds: ms);
    setState(() {
      _facingRight = dest.dx >= _charPos.dx;
      _charPos = dest;
      _moveDuration = moveDur;
      _walking = true;
      _lastTap = rawTarget;
    });
    // 걷기 바운스 시작, 도착하면 멈춤
    final token = ++_moveToken;
    if (!_walkCtrl.isAnimating) _walkCtrl.repeat();
    Future.delayed(moveDur, () {
      if (!mounted || token != _moveToken) return;
      setState(() => _walking = false);
      _walkCtrl.stop();
      _walkCtrl.value = 0;
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
    Navigator.push(context, MaterialPageRoute(builder: (_) => const RankingScreen()));
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
          final charH = h * 0.28;
          final charW = charH * 0.55;

          return Stack(
            children: [
              // 1) 배경: 광장 전용 그림(plaza_OOO.jpg) 우선, 없으면 낚시 배경으로 폴백
              Positioned.fill(
                child: Image.asset(
                  _plazaBg,
                  fit: BoxFit.cover,
                  errorBuilder: (a, b, d) => Image.asset(
                    widget.spot['image'],
                    fit: BoxFit.cover,
                    errorBuilder: (a2, b2, d2) => Container(color: const Color(0xFF11202E)),
                  ),
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
                curve: Curves.linear,
                left: _charPos.dx * w - charW / 2,
                top: _charPos.dy * h - charH,
                width: charW,
                height: charH,
                child: IgnorePointer(
                  child: AnimatedBuilder(
                    animation: _walkCtrl,
                    builder: (context, _) {
                      final phase = _walkCtrl.value * 2 * math.pi;
                      final bob = _walking ? math.sin(phase).abs() * 2.5 : 0.0; // 작은 들썩
                      final tilt = _walking ? math.sin(phase) * 0.035 : 0.0;     // 좌우 기우뚱
                      return Stack(
                        clipBehavior: Clip.none,
                        alignment: Alignment.bottomCenter,
                        children: [
                          // 발밑 그림자
                          Positioned(
                            bottom: 2,
                            child: Container(
                              width: charW * 0.4,
                              height: 8,
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.35),
                                borderRadius: BorderRadius.circular(20),
                              ),
                            ),
                          ),
                          // 캐릭터 (들썩 + 기우뚱 + 방향)
                          Positioned.fill(
                            child: Transform.translate(
                              offset: Offset(0, -bob),
                              child: Transform.rotate(
                                angle: tilt,
                                alignment: Alignment.bottomCenter,
                                child: Transform(
                                  alignment: Alignment.bottomCenter,
                                  transform: Matrix4.rotationY(_facingRight ? 0 : math.pi),
                                  child: Image.asset(
                                    _charImage,
                                    fit: BoxFit.contain,
                                    alignment: Alignment.bottomCenter,
                                    errorBuilder: (a, b, d) => const SizedBox.shrink(),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          // 닉네임/레벨 머리표 (머리 바로 위로)
                          Positioned(
                            bottom: charH * 0.78,
                            left: 0,
                            right: 0,
                            child: Center(
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(0.6),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: _kGold.withOpacity(0.7)),
                                ),
                                child: Text('Lv.$_level ${widget.nickname}',
                                    maxLines: 1,
                                    style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),

              // 4) NPC / 시설들 (예당호 광장 그림 랜드마크에 맞춤)
              _npc(w, h, 0.68, 0.35,'🏪', '상점', _openStore),   // 카페 건물(오른쪽)
              _npc(w, h, 0.27, 0.37,'🏆', '랭킹', _openRanking), // 왼쪽
              _npc(w, h, 0.90, 0.55,'⚔️', '아레나', _openArena), // 중앙 좌측 광장
              _npc(w, h, 0.50, 0.32,'🌀', '포탈', _openMinimap), // 출렁다리 입구(위 중앙)

              // 5) 상단 HUD
              _topHud(),

              // 🛠️ (개발용) 마지막 탭 좌표 — NPC 위치 잡을 때 참고. 추후 제거.
              if (_lastTap != null)
                Positioned(
                  left: 12,
                  bottom: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.6),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '좌표 ${_lastTap!.dx.toStringAsFixed(2)}, ${_lastTap!.dy.toStringAsFixed(2)}',
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ),
                ),

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
