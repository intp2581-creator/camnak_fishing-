// ignore_for_file: deprecated_member_use, use_build_context_synchronously
// 🏛️ [광장 시스템] 낚시터별 광장(허브). 1단계: 나 혼자 걸어다니며 상점/아레나/포탈/낚시 진입.
//    2단계에서 RTDB로 다른 유저 실시간 표시 예정.
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
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
  // 🌐 실시간(2단계) — 같은 광장 다른 유저
  static final FirebaseDatabase _db = FirebaseDatabase.instanceFor(
    app: Firebase.app(),
    databaseURL: 'https://camnak-fishing-default-rtdb.asia-southeast1.firebasedatabase.app',
  );
  DatabaseReference? _myRef;
  StreamSubscription<DatabaseEvent>? _roomSub;
  Map<String, Map<String, dynamic>> _others = {};
  String get _roomKey => widget.isSea ? 'sea' : 'fresh';

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
    _roomSub?.cancel();
    _myRef?.remove();
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
    _initPresence();
  }

  // 🌐 실시간 접속/위치 송수신
  void _initPresence() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final uid = user.uid;
    _myRef = _db.ref('plaza/$_roomKey/$uid');
    _myRef!.onDisconnect().remove().catchError((Object e) => debugPrint('🌐 RTDB onDisconnect ERR: $e')); // 접속 끊기면 자동 사라짐
    _writeMe();
    _roomSub = _db.ref('plaza/$_roomKey').onValue.listen((event) {
      final val = event.snapshot.value;
      final next = <String, Map<String, dynamic>>{};
      if (val is Map) {
        val.forEach((k, v) {
          if (k.toString() == uid || v is! Map) return; // 나 제외
          next[k.toString()] = {
            'nick': v['nick']?.toString() ?? '조사',
            'img': v['img']?.toString() ?? 'assets/images/char_beginner.png',
            'x': (v['x'] is num) ? (v['x'] as num).toDouble() : 0.5,
            'y': (v['y'] is num) ? (v['y'] as num).toDouble() : 0.8,
            'face': v['face'] == true,
          };
        });
      }
      if (mounted) setState(() => _others = next);
    }, onError: (Object e) {
      debugPrint('🌐 RTDB READ ERR: $e');
    });
  }

  String _shortUid() {
    final u = FirebaseAuth.instance.currentUser?.uid ?? '?';
    return u.length > 6 ? u.substring(0, 6) : u;
  }

  void _writeMe() {
    _myRef?.set({
      'nick': widget.nickname,
      'img': _charImage,
      'x': _charPos.dx,
      'y': _charPos.dy,
      'face': _facingRight,
      't': ServerValue.timestamp,
    }).catchError((Object e) {
      debugPrint('🌐 RTDB WRITE ERR: $e');
    });
  }

  // 🌐 다른 유저 캐릭터 (실시간 위치로 부드럽게 이동)
  Widget _remoteAvatar(String uid, Map<String, dynamic> d, double w, double h) {
    final dx = (d['x'] as double).clamp(0.02, 0.98);
    final dy = (d['y'] as double).clamp(0.0, 1.0);
    final pT = ((dy - 0.22) / (0.96 - 0.22)).clamp(0.0, 1.0);
    final rH = h * (0.18 + pT * 0.16);
    final rW = rH * 0.55;
    final face = d['face'] == true;
    return AnimatedPositioned(
      key: ValueKey('remote_$uid'),
      duration: const Duration(milliseconds: 650),
      curve: Curves.linear,
      left: dx * w - rW / 2,
      top: dy * h - rH,
      width: rW,
      height: rH,
      child: IgnorePointer(
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.bottomCenter,
          children: [
            Positioned(
              bottom: 2,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _footShadow(rW),
                  SizedBox(width: rW * 0.07),
                  _footShadow(rW),
                ],
              ),
            ),
            Positioned.fill(
              child: Transform(
                alignment: Alignment.bottomCenter,
                transform: Matrix4.rotationY(face ? 0 : math.pi),
                child: Image.asset(d['img'] as String,
                    fit: BoxFit.contain,
                    alignment: Alignment.bottomCenter,
                    errorBuilder: (a, b, c) => const SizedBox.shrink()),
              ),
            ),
            Positioned(
              bottom: rH * 0.70,
              left: -150,
              right: -150,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.6),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: Text(d['nick'] as String,
                      maxLines: 1,
                      style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _footShadow(double charW) => Container(
        width: charW * 0.17,
        height: charW * 0.08,
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.3),
          borderRadius: BorderRadius.circular(40),
        ),
      );

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
    Offset(0.01, 1.00), Offset(0.01, 0.50), Offset(0.13, 0.43), Offset(0.20, 0.37),
    Offset(0.27, 0.34), Offset(0.38, 0.31), Offset(0.39, 0.25), Offset(0.44, 0.23),
    Offset(0.53, 0.23), Offset(0.60, 0.23), Offset(0.66, 0.26), Offset(0.69, 0.31),
    Offset(0.75, 0.32), Offset(0.80, 0.34), Offset(0.90, 0.33), Offset(0.99, 0.38),
    Offset(0.84, 0.38), Offset(0.83, 0.47), Offset(0.80, 0.51), Offset(0.82, 0.56),
    Offset(0.88, 0.64), Offset(0.99, 0.63), Offset(0.99, 0.99),
  ];
  static const List<Offset> _seaPoly = [
    Offset(0.01, 1.00), Offset(0.01, 0.50), Offset(0.10, 0.42), Offset(0.20, 0.37),
    Offset(0.30, 0.34), Offset(0.38, 0.33), Offset(0.45, 0.32), Offset(0.55, 0.32),
    Offset(0.63, 0.34), Offset(0.58, 0.42), Offset(0.66, 0.48), Offset(0.71, 0.53),
    Offset(0.75, 0.58), Offset(0.86, 0.55), Offset(0.85, 0.49), Offset(0.90, 0.42),
    Offset(0.99, 0.47), Offset(0.99, 0.99),
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
    });
    _myRef?.update({'x': _charPos.dx, 'y': _charPos.dy, 'face': _facingRight}).catchError((Object e) => debugPrint('🌐 RTDB UPDATE ERR: $e')); // 실시간 위치 전송
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
    String subCat = widget.isSea ? '갯바위' : '저수지'; // 현재 광장 타입의 첫 서브탭

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: const Color(0xFF141414),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: _kGold, width: 1.5)),
        child: StatefulBuilder(
          builder: (ctx, setDialog) {
            final bool isMainSea = (subCat == '갯바위' || subCat == '선상');
            final List<String> subs = isMainSea ? ['갯바위', '선상'] : ['저수지', '수로'];
            final List<Map<String, dynamic>> spots =
                List<Map<String, dynamic>>.from(locations[subCat] ?? []);

            Widget tab(String label, bool active, VoidCallback onTap, {double fontSize = 18}) {
              return Expanded(
                child: GestureDetector(
                  onTap: onTap,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      border: Border(
                          bottom: BorderSide(
                              color: active ? _kGold : Colors.transparent, width: 3)),
                    ),
                    child: Text(label,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: active ? _kGold : Colors.white54,
                            fontSize: fontSize,
                            fontWeight: active ? FontWeight.w900 : FontWeight.bold)),
                  ),
                ),
              );
            }

            return SizedBox(
              width: 720,
              height: 580,
              child: Column(
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
                    child: Text('🗺️  어느 낚시터로 떠날까요?',
                        style: TextStyle(color: _kGold, fontSize: 20, fontWeight: FontWeight.w900)),
                  ),
                  // 메인 탭: 민물 / 바다
                  Row(
                    children: [
                      tab('🏞️ 민물낚시', !isMainSea, () => setDialog(() => subCat = '저수지')),
                      tab('🌊 바다낚시', isMainSea, () => setDialog(() => subCat = '갯바위')),
                    ],
                  ),
                  // 서브 탭: 저수지/수로 또는 갯바위/선상
                  Container(
                    color: Colors.black26,
                    child: Row(
                      children: [
                        for (final c in subs)
                          tab(c, subCat == c, () => setDialog(() => subCat = c), fontSize: 15),
                      ],
                    ),
                  ),
                  const Divider(color: Colors.white12, height: 1),
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: spots.length,
                      itemBuilder: (c, i) {
                        final s = spots[i];
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
                            leading: Text(isMainSea ? '🌊' : '🏞️',
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
                                          isSea: isMainSea,
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
            );
          },
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
          // 🏞️ 원근감: 위(멀리)로 갈수록 작게, 아래(가까이)로 올수록 크게
          final perspT = ((_charPos.dy - 0.22) / (0.96 - 0.22)).clamp(0.0, 1.0);
          final charH = h * (0.18 + perspT * 0.16); // 멀리=0.18h ~ 가까이=0.34h
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
                          // 발밑 그림자 (두 발 — 스케이트보드 느낌 제거, 발보다 살짝 크게)
                          Positioned(
                            bottom: 2,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: charW * 0.17,
                                  height: charW * 0.08,
                                  decoration: BoxDecoration(
                                    color: Colors.black.withOpacity(0.32),
                                    borderRadius: BorderRadius.circular(40),
                                  ),
                                ),
                                SizedBox(width: charW * 0.07),
                                Container(
                                  width: charW * 0.17,
                                  height: charW * 0.08,
                                  decoration: BoxDecoration(
                                    color: Colors.black.withOpacity(0.32),
                                    borderRadius: BorderRadius.circular(40),
                                  ),
                                ),
                              ],
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
                            bottom: charH * 0.70,
                            left: -150,
                            right: -150,
                            child: Center(
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(0.6),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: _kGold.withOpacity(0.7)),
                                ),
                                child: Text(widget.nickname,
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

              // 🌐 다른 유저들 (실시간)
              ..._others.entries.map((e) => _remoteAvatar(e.key, e.value, w, h)),

              // 4) NPC / 시설들 (예당호 광장 그림 랜드마크에 맞춤)
              _npc(w, h, widget.isSea ? 0.75 : 0.90, widget.isSea ? 0.32 : 0.35,'🏪', '상점', _openStore),   // 카페 건물(오른쪽)
              _npc(w, h, widget.isSea ? 0.15 : 0.15, widget.isSea ? 0.28 : 0.20,'🏆', '랭킹', _openRanking), // 왼쪽
              _npc(w, h, widget.isSea ? 0.95 : 0.72, widget.isSea ? 0.54 : 0.22,'⚔️', '아레나', _openArena, iconWidget: _crossedRods()), // 중앙 좌측 광장
              _npc(w, h, widget.isSea ? 0.52 : 0.52, widget.isSea ? 0.22 : 0.16,'🌀', '낚시터', _openMinimap), // 출렁다리 입구(위 중앙)

              // 5) 상단 HUD
              _topHud(),

              // 🛠️ 디버그: 방/다른유저 수 (진단용, 곧 제거)
              Positioned(
                top: 72,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.7),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text('방:$_roomKey · 나:${_shortUid()} · 다른:${_others.length}',
                        style: const TextStyle(
                            color: Colors.yellowAccent, fontSize: 14, fontWeight: FontWeight.w900)),
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
  // 🎣 낚시대 두 개 교차 아이콘 (아레나용 — 칼싸움 아님 ㅋㅋ)
  Widget _crossedRods() {
    return SizedBox(
      width: 36,
      height: 32,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Transform.rotate(angle: -0.35, child: const Text('🎣', style: TextStyle(fontSize: 22))),
          Transform.flip(
            flipX: true,
            child: Transform.rotate(angle: -0.35, child: const Text('🎣', style: TextStyle(fontSize: 22))),
          ),
        ],
      ),
    );
  }

  Widget _npc(double w, double h, double cx, double cy, String emoji, String label, VoidCallback onTap, {Widget? iconWidget}) {
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
              child: Center(child: iconWidget ?? Text(emoji, style: const TextStyle(fontSize: 28))),
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
                Text(widget.isSea ? '바다낚시 광장' : '민물낚시 광장',
                    style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900)),
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
