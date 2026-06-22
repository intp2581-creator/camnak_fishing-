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
import 'package:flutter/gestures.dart'; // 채팅 닉네임 탭
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

  // 💬 채팅 (낚시터와 동일한 global_chat / friends 공유)
  int _chatTab = 0; // 0 전체 / 1 귓속말 / 2 친구 / 3 길드
  String? _whisperTarget;
  final TextEditingController _chatCtrl = TextEditingController();
  final DateTime _joinTime = DateTime.now(); // 입장 이후 메시지만 표시

  // 🛡️ 길드 (users 문서 실시간 구독으로 가입 상태 추적)
  String _guildId = '';
  String _guildName = '';
  StreamSubscription<DocumentSnapshot>? _userSub;

  // 💬 말풍선 (전체 채팅을 캐릭터 머리 위에 잠깐 표시)
  final Map<String, String> _bubbleMsg = {};
  final Map<String, DateTime> _bubbleUntil = {};
  final Map<String, int> _lastMsgT = {};
  String? _myBubble;
  DateTime? _myBubbleUntil;
  Timer? _bubbleTimer;

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
    _userSub?.cancel();
    _myRef?.remove();
    _chatCtrl.dispose();
    _bubbleTimer?.cancel();
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
    // 🛡️ 길드 가입 상태 실시간 추적
    _userSub = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .snapshots()
        .listen((doc) {
      final d = doc.data() ?? {};
      final gid = (d['guildId'] ?? '').toString();
      final gname = (d['guildName'] ?? '').toString();
      if (!mounted) return;
      if (gid != _guildId || gname != _guildName) {
        setState(() {
          _guildId = gid;
          _guildName = gname;
          // 길드 나가면 길드 채팅 탭에서 전체로 복귀
          if (gid.isEmpty && _chatTab == 3) _chatTab = 0;
        });
      }
    });
  }

  // 🌐 실시간 접속/위치 송수신
  void _initPresence() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final uid = user.uid;
    _myRef = _db.ref('plaza/$_roomKey/$uid');
    _myRef!.onDisconnect().remove().catchError((Object e) => debugPrint('🌐 RTDB onDisconnect ERR: $e')); // 접속 끊기면 자동 사라짐
    _writeMe();
    // 말풍선 만료 처리용 1초 타이머
    _bubbleTimer ??= Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    _roomSub = _db.ref('plaza/$_roomKey').onValue.listen((event) {
      final val = event.snapshot.value;
      final next = <String, Map<String, dynamic>>{};
      if (val is Map) {
        val.forEach((k, v) {
          if (k.toString() == uid || v is! Map) return; // 나 제외
          final kk = k.toString();
          next[kk] = {
            'nick': v['nick']?.toString() ?? '조사',
            'img': v['img']?.toString() ?? 'assets/images/char_beginner.png',
            'x': (v['x'] is num) ? (v['x'] as num).toDouble() : 0.5,
            'y': (v['y'] is num) ? (v['y'] as num).toDouble() : 0.8,
            'face': v['face'] == true,
          };
          // 💬 말풍선: 메시지 타임스탬프가 새로 바뀌면 5초 표시 (처음 본 유저의 옛 메시지는 무시)
          final mt = (v['msgT'] is num) ? (v['msgT'] as num).toInt() : 0;
          final mmsg = v['msg']?.toString() ?? '';
          if (mt != (_lastMsgT[kk] ?? -1)) {
            final firstSeen = !_lastMsgT.containsKey(kk);
            _lastMsgT[kk] = mt;
            if (!firstSeen && mt > 0 && mmsg.isNotEmpty) {
              _bubbleMsg[kk] = mmsg;
              _bubbleUntil[kk] = DateTime.now().add(const Duration(seconds: 5));
            }
          }
        });
      }
      if (mounted) setState(() => _others = next);
    }, onError: (Object e) {
      debugPrint('🌐 RTDB READ ERR: $e');
    });
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
              bottom: rH * 0.50,
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
            // 💬 다른 유저 말풍선
            if (_bubbleUntil[uid] != null && DateTime.now().isBefore(_bubbleUntil[uid]!))
              Positioned(
                bottom: rH * 0.68,
                left: -150,
                right: -150,
                child: Center(child: _bubble(_bubbleMsg[uid] ?? '')),
              ),
          ],
        ),
      ),
    );
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
            final List<Map<String, dynamic>> spots =
                List<Map<String, dynamic>>.from(locations[subCat] ?? []);

            Widget tab(String label, bool active, VoidCallback onTap, {double fontSize = 18}) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 4),
                child: GestureDetector(
                  onTap: onTap,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: active ? _kGold : Colors.grey.shade800,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: active ? _kGold : Colors.white24, width: 1),
                    ),
                    child: Text(label,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: active ? Colors.black : Colors.white70,
                            fontSize: fontSize,
                            fontWeight: FontWeight.w900)),
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
                  // 민물(저수지/수로) · 바다(갯바위/선상) 한눈에
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(children: [
                            Row(children: [
                              Expanded(
                                  child: tab('🏞️ 민물낚시', !isMainSea,
                                      () => setDialog(() => subCat = '저수지'))),
                            ]),
                            Row(children: [
                              Expanded(
                                  child: tab('저수지', subCat == '저수지',
                                      () => setDialog(() => subCat = '저수지'), fontSize: 14)),
                              Expanded(
                                  child: tab('수로', subCat == '수로',
                                      () => setDialog(() => subCat = '수로'), fontSize: 14)),
                            ]),
                          ]),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(children: [
                            Row(children: [
                              Expanded(
                                  child: tab('🌊 바다낚시', isMainSea,
                                      () => setDialog(() => subCat = '갯바위'))),
                            ]),
                            Row(children: [
                              Expanded(
                                  child: tab('갯바위', subCat == '갯바위',
                                      () => setDialog(() => subCat = '갯바위'), fontSize: 14)),
                              Expanded(
                                  child: tab('선상', subCat == '선상',
                                      () => setDialog(() => subCat = '선상'), fontSize: 14)),
                            ]),
                          ]),
                        ),
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
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        TextButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: const Text('닫기', style: TextStyle(color: Colors.white54))),
                        const Spacer(),
                        ElevatedButton.icon(
                          onPressed: () {
                            Navigator.pop(ctx);
                            _goFishing();
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _kGold,
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          icon: const Text('🎣', style: TextStyle(fontSize: 16)),
                          label: const Text('여기서 낚시 시작',
                              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  // ===== 💬 채팅 =====
  Widget _chatTabBtn(int index, String title) {
    final active = _chatTab == index;
    return GestureDetector(
      onTap: () => setState(() {
        _chatTab = index;
        if (index == 0) _whisperTarget = null;
      }),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
        margin: const EdgeInsets.only(right: 2),
        decoration: BoxDecoration(
          color: active ? _kGold : Colors.grey.shade700,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
        ),
        child: Text(title,
            style: TextStyle(
                color: active ? Colors.black : Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold)),
      ),
    );
  }

  void _sendChat() {
    final text = _chatCtrl.text.trim();
    if (text.isEmpty) return;
    // 🛡️ 길드 탭: 길드 전용 채팅으로 전송
    if (_chatTab == 3) {
      if (_guildId.isEmpty) return;
      FirebaseFirestore.instance
          .collection('guilds')
          .doc(_guildId)
          .collection('chat')
          .add({
        'nickname': widget.nickname,
        'message': text,
        'timestamp': FieldValue.serverTimestamp(),
      });
      _chatCtrl.clear();
      return;
    }
    String type = 'global';
    String receiver = '';
    if (_chatTab == 1 && _whisperTarget != null) {
      type = 'whisper';
      receiver = _whisperTarget!;
    }
    FirebaseFirestore.instance.collection('global_chat').add({
      'nickname': widget.nickname,
      'message': text,
      'type': type,
      'receiver': receiver,
      'timestamp': FieldValue.serverTimestamp(),
    });
    // 💬 전체 채팅이면 RTDB에 실어서 머리 위 말풍선으로 (귓속말은 제외)
    if (type == 'global') {
      _myRef?.update({'msg': text, 'msgT': ServerValue.timestamp})
          .catchError((Object e) => debugPrint('🌐 RTDB MSG ERR: $e'));
      setState(() {
        _myBubble = text;
        _myBubbleUntil = DateTime.now().add(const Duration(seconds: 5));
      });
    }
    _chatCtrl.clear();
  }

  // 💬 말풍선 위젯
  Widget _bubble(String text) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 160),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.35), blurRadius: 4)],
      ),
      child: Text(text,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.black, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }

  void _showUserMenu(String nick) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.black87,
        shape: RoundedRectangleBorder(
            side: const BorderSide(color: Colors.amber, width: 2),
            borderRadius: BorderRadius.circular(8)),
        title: Text('[$nick] 님',
            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.chat_bubble_outline, color: Colors.yellowAccent),
              title: const Text('귓속말 보내기', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(ctx);
                setState(() {
                  _whisperTarget = nick;
                  _chatTab = 1;
                });
              },
            ),
            ListTile(
              leading: const Icon(Icons.person_add_alt_1, color: Colors.greenAccent),
              title: const Text('친구 추가하기', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(ctx);
                _addFriend(nick);
              },
            ),
            ListTile(
              leading: const Icon(Icons.cancel_outlined, color: Colors.grey),
              title: const Text('취소', style: TextStyle(color: Colors.grey)),
              onTap: () => Navigator.pop(ctx),
            ),
          ],
        ),
      ),
    );
  }

  void _addFriend(String nick) {
    FirebaseFirestore.instance
        .collection('friends')
        .doc(widget.nickname)
        .collection('my_list')
        .doc(nick)
        .set({'nickname': nick, 'addedAt': FieldValue.serverTimestamp()}).then((_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('[$nick]님을 친구 목록에 추가했습니다! 🤝'),
          backgroundColor: Colors.blueGrey,
          duration: const Duration(seconds: 2),
        ));
      }
    });
  }

  // 🛡️ 길드 채팅 목록
  Widget _guildChatView() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('guilds')
          .doc(_guildId)
          .collection('chat')
          .orderBy('timestamp', descending: true)
          .limit(30)
          .snapshots(),
      builder: (c, snap) {
        if (!snap.hasData) return const SizedBox.shrink();
        final docs = snap.data!.docs;
        if (docs.isEmpty) {
          return Center(
              child: Text('[$_guildName] 길드 채팅\n첫 인사를 남겨보세요!',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white54, fontSize: 12)));
        }
        final me = widget.nickname;
        return ListView.builder(
          reverse: true,
          itemCount: docs.length,
          itemBuilder: (c, i) {
            final d = docs[i].data() as Map<String, dynamic>;
            final sender = d['nickname'] ?? '길드원';
            final msg = d['message'] ?? '';
            return Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: RichText(
                text: TextSpan(children: [
                  const TextSpan(
                      text: '길드> ',
                      style: TextStyle(color: Color(0xFF7FD4FF), fontSize: 13)),
                  TextSpan(
                    text: '$sender: ',
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                    recognizer: TapGestureRecognizer()
                      ..onTap = () {
                        if (sender != me) _showUserMenu(sender);
                      },
                  ),
                  TextSpan(text: msg, style: const TextStyle(color: Colors.white, fontSize: 13)),
                ]),
              ),
            );
          },
        );
      },
    );
  }

  Widget _chatPanel() {
    return Positioned(
      left: 16,
      bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            _chatTabBtn(0, '전체'),
            _chatTabBtn(1, '귓속말'),
            _chatTabBtn(2, '친구'),
            if (_guildId.isNotEmpty) _chatTabBtn(3, '길드'),
          ]),
          Container(
            width: 360,
            height: 170,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.65),
              border: Border.all(color: Colors.amber, width: 2),
            ),
            child: Column(
              children: [
                Expanded(
                  child: _chatTab == 2
                      ? StreamBuilder<QuerySnapshot>(
                          stream: FirebaseFirestore.instance
                              .collection('friends')
                              .doc(widget.nickname)
                              .collection('my_list')
                              .orderBy('addedAt', descending: true)
                              .snapshots(),
                          builder: (c, snap) {
                            if (!snap.hasData) {
                              return const Center(child: CircularProgressIndicator(color: Colors.amber));
                            }
                            final docs = snap.data!.docs;
                            if (docs.isEmpty) {
                              return const Center(
                                  child: Text('아직 친구가 없습니다.\n채팅에서 닉네임을 눌러 추가하세요!',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(color: Colors.white54, fontSize: 12)));
                            }
                            return ListView.builder(
                              itemCount: docs.length,
                              itemBuilder: (c, i) {
                                final f = docs[i].data() as Map<String, dynamic>;
                                final fn = f['nickname'] ?? '?';
                                return ListTile(
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                                  visualDensity: VisualDensity.compact,
                                  leading: const Icon(Icons.person, color: Colors.greenAccent, size: 20),
                                  title: Text(fn,
                                      style: const TextStyle(
                                          color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                                  trailing: IconButton(
                                    icon: const Icon(Icons.chat_bubble, color: Colors.yellowAccent, size: 20),
                                    onPressed: () => setState(() {
                                      _whisperTarget = fn;
                                      _chatTab = 1;
                                    }),
                                  ),
                                );
                              },
                            );
                          },
                        )
                      : _chatTab == 3
                      ? _guildChatView()
                      : StreamBuilder<QuerySnapshot>(
                          stream: FirebaseFirestore.instance
                              .collection('global_chat')
                              .where('timestamp', isGreaterThanOrEqualTo: _joinTime)
                              .orderBy('timestamp', descending: true)
                              .limit(30)
                              .snapshots(),
                          builder: (c, snap) {
                            if (!snap.hasData) return const SizedBox.shrink();
                            final docs = snap.data!.docs;
                            final me = widget.nickname;
                            return ListView.builder(
                              reverse: true,
                              itemCount: docs.length,
                              itemBuilder: (c, i) {
                                final d = docs[i].data() as Map<String, dynamic>;
                                final type = d['type'] ?? 'global';
                                final receiver = d['receiver'] ?? '';
                                final sender = d['nickname'] ?? '조사';
                                final msg = d['message'] ?? '';
                                if (_chatTab == 1) {
                                  if (type != 'whisper') return const SizedBox.shrink();
                                  if (sender != me && receiver != me) return const SizedBox.shrink();
                                } else {
                                  // 전체 탭: 남의 귓속말은 숨김
                                  if (type == 'whisper' && sender != me && receiver != me) {
                                    return const SizedBox.shrink();
                                  }
                                }
                                Color pc = Colors.white;
                                String pt = '전체>';
                                if (type == 'notice') {
                                  pc = Colors.amber;
                                  pt = '공지>';
                                } else if (type == 'whisper') {
                                  pc = Colors.yellowAccent;
                                  pt = '귓속말>';
                                }
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 4),
                                  child: RichText(
                                    text: TextSpan(children: [
                                      TextSpan(text: '$pt ', style: TextStyle(color: pc, fontSize: 13)),
                                      TextSpan(
                                        text: '$sender: ',
                                        style: const TextStyle(
                                            color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                                        recognizer: TapGestureRecognizer()
                                          ..onTap = () {
                                            if (sender != me) _showUserMenu(sender);
                                          },
                                      ),
                                      TextSpan(
                                          text: msg,
                                          style: TextStyle(
                                              color: type == 'notice' ? Colors.amber : Colors.white,
                                              fontSize: 13)),
                                    ]),
                                  ),
                                );
                              },
                            );
                          },
                        ),
                ),
                const SizedBox(height: 6),
                SizedBox(
                  height: 34,
                  child: TextField(
                    controller: _chatCtrl,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: (_chatTab == 1 && _whisperTarget != null)
                          ? '[$_whisperTarget]님에게 귓속말...'
                          : _chatTab == 3
                              ? '[$_guildName] 길드원에게...'
                              : '메시지를 입력하세요...',
                      hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                      border: const OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _sendChat(),
                  ),
                ),
              ],
            ),
          ),
        ],
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
                            bottom: charH * 0.50,
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
                          // 💬 내 말풍선
                          if (_myBubble != null &&
                              _myBubbleUntil != null &&
                              DateTime.now().isBefore(_myBubbleUntil!))
                            Positioned(
                              bottom: charH * 0.68,
                              left: -150,
                              right: -150,
                              child: Center(child: _bubble(_myBubble!)),
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
              _npc(w, h, widget.isSea ? 0.34 : 0.33, widget.isSea ? 0.25 : 0.17,'🛡️', '길드', _openGuild), // 랭킹과 낚시터 사이

              // 5) 상단 HUD
              _topHud(),

              // 💬 채팅 패널 (낚시터와 동일)
              _chatPanel(),
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

  // 🎒 인벤토리 (읽기 전용 보기)
  String _itemIconPath(String icon) {
    if (icon.isEmpty) return 'assets/items/rod_fw_cf20.png';
    if (icon.startsWith('../images/')) return 'assets/${icon.substring(3)}';
    if (icon.startsWith('assets/')) return icon;
    return 'assets/items/$icon';
  }

  Widget _invItem(Map<String, dynamic> item) {
    final name = item['name']?.toString() ?? '';
    final qty = item['quantity'];
    final icon = _itemIconPath(item['icon']?.toString() ?? '');
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade900,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Image.asset(icon,
                        fit: BoxFit.contain,
                        errorBuilder: (a, b, c) =>
                            const Icon(Icons.inventory_2, color: Colors.white24, size: 30)),
                  ),
                ),
                if (qty != null)
                  Positioned(
                    right: 4,
                    bottom: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                          color: Colors.black87, borderRadius: BorderRadius.circular(6)),
                      child: Text('$qty개',
                          style: const TextStyle(
                              color: _kGold, fontSize: 10, fontWeight: FontWeight.bold)),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 6, left: 4, right: 4),
            child: Text(name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  void _openInventory() {
    String tab = '전체';
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: const Color(0xFF141414),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: _kGold, width: 1.5)),
        child: StatefulBuilder(
          builder: (ctx, setD) {
            int typeRank(Map<String, dynamic> it) {
              switch ((it['type'] ?? '').toString().toUpperCase()) {
                case 'SKIN':
                  return 0;
                case 'ROD':
                  return 1;
                case 'REEL':
                case 'FLOAT':
                  return 2;
                case 'ETC':
                  return 3;
                case 'BAIT':
                  return 4;
              }
              return 5;
            }

            int catRank(Map<String, dynamic> it) {
              final c = (it['category'] ?? '').toString().toUpperCase();
              if (c == 'FW') return 0;
              if (c == 'SEA') return 1;
              return 2;
            }

            bool match(Map<String, dynamic> it) {
              final cat = (it['category'] ?? '').toString().toUpperCase();
              final type = (it['type'] ?? '').toString().toUpperCase();
              switch (tab) {
                case '민물':
                  return (cat == 'FW' && type != 'BAIT') || (type == 'ETC' && cat != 'SEA');
                case '바다':
                  return (cat == 'SEA' && type != 'BAIT') || (type == 'ETC' && cat != 'FW');
                case '미끼':
                  return type == 'BAIT';
                case '스킨':
                  return type == 'SKIN' || cat == 'SKIN';
              }
              return true; // 전체
            }

            final items =
                _inventory.map((e) => e as Map<String, dynamic>).where(match).toList();
            items.sort((a, b) {
              if (tab == '미끼') {
                final c = catRank(a).compareTo(catRank(b)); // 민물 미끼 → 바다 미끼
                if (c != 0) return c;
                return (a['name'] ?? '').toString().compareTo((b['name'] ?? '').toString());
              }
              // 전체/민물/바다: 스킨>낚시대>릴찌>악세>미끼, 같으면 민물>바다
              final t = typeRank(a).compareTo(typeRank(b));
              if (t != 0) return t;
              return catRank(a).compareTo(catRank(b));
            });

            Widget tabBtn(String t) {
              final active = tab == t;
              return Expanded(
                child: GestureDetector(
                  onTap: () => setD(() => tab = t),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      border: Border(
                          bottom: BorderSide(
                              color: active ? _kGold : Colors.transparent, width: 3)),
                    ),
                    child: Text(t,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: active ? _kGold : Colors.white54,
                            fontSize: 15,
                            fontWeight: active ? FontWeight.w900 : FontWeight.bold)),
                  ),
                ),
              );
            }

            return SizedBox(
              width: 760,
              height: 560,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 14, 8, 4),
                    child: Row(
                      children: [
                        const Text('🎒 KREFT 인벤토리',
                            style: TextStyle(
                                color: _kGold, fontSize: 20, fontWeight: FontWeight.w900)),
                        const Spacer(),
                        IconButton(
                            onPressed: () => Navigator.pop(ctx),
                            icon: const Icon(Icons.close, color: Colors.white, size: 26)),
                      ],
                    ),
                  ),
                  Row(children: [
                    tabBtn('전체'),
                    tabBtn('민물'),
                    tabBtn('바다'),
                    tabBtn('미끼'),
                    tabBtn('스킨'),
                  ]),
                  const Divider(color: Colors.white12, height: 1),
                  Expanded(
                    child: items.isEmpty
                        ? const Center(
                            child: Text('이 분류에 아이템이 없어요',
                                style: TextStyle(color: Colors.white54)))
                        : GridView.builder(
                            padding: const EdgeInsets.all(14),
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 5,
                              childAspectRatio: 0.85,
                              mainAxisSpacing: 10,
                              crossAxisSpacing: 10,
                            ),
                            itemCount: items.length,
                            itemBuilder: (c, i) => _invItem(items[i]),
                          ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  // ───────────────────────── 길드 시스템 ─────────────────────────
  Widget _iconBtn(IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(color: _kGold, borderRadius: BorderRadius.circular(8)),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: Colors.black, size: 22),
          Text(label, style: const TextStyle(color: Colors.black, fontSize: 9, fontWeight: FontWeight.bold)),
        ]),
      ),
    );
  }

  void _openGuild() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final uid = user.uid;
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: SizedBox(
          width: 460,
          height: 520,
          child: StreamBuilder<DocumentSnapshot>(
            stream: FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
            builder: (c, snap) {
              if (!snap.hasData) {
                return const Center(child: CircularProgressIndicator(color: _kGold));
              }
              final data = snap.data!.data() as Map<String, dynamic>? ?? {};
              final gid = (data['guildId'] ?? '').toString();
              if (gid.isEmpty) {
                return _guildBrowse(ctx, uid);
              }
              return _guildHome(ctx, uid, gid);
            },
          ),
        ),
      ),
    );
  }

  Widget _guildDialogHeader(String title, {Widget? trailing}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: Color(0xFF262626),
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Row(children: [
        const Icon(Icons.groups, color: _kGold, size: 22),
        const SizedBox(width: 8),
        Text(title, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900)),
        const Spacer(),
        if (trailing != null) trailing,
      ]),
    );
  }

  Widget _guildBrowse(BuildContext ctx, String uid) {
    return Column(
      children: [
        _guildDialogHeader('길드',
            trailing: IconButton(
                icon: const Icon(Icons.close, color: Colors.white54),
                onPressed: () => Navigator.pop(ctx))),
        Padding(
          padding: const EdgeInsets.all(12),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                  backgroundColor: _kGold,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 12)),
              icon: const Icon(Icons.add),
              label: const Text('길드 만들기 (10,000 P)',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
              onPressed: () => _createGuildDialog(uid),
            ),
          ),
        ),
        const Divider(color: Colors.white12, height: 1),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Align(
              alignment: Alignment.centerLeft,
              child: Text('길드 목록',
                  style: TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.bold))),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('guilds')
                .orderBy('memberCount', descending: true)
                .snapshots(),
            builder: (c, snap) {
              if (!snap.hasData) {
                return const Center(child: CircularProgressIndicator(color: _kGold));
              }
              final docs = snap.data!.docs;
              if (docs.isEmpty) {
                return const Center(
                    child: Text('아직 길드가 없어요.\n첫 길드를 만들어보세요!',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white38)));
              }
              return ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: docs.length,
                itemBuilder: (c, i) {
                  final g = docs[i].data() as Map<String, dynamic>;
                  final gid = docs[i].id;
                  return Container(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                        color: const Color(0xFF2A2A2A),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.white12)),
                    child: Row(children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(g['name']?.toString() ?? '',
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 15, fontWeight: FontWeight.w900)),
                            const SizedBox(height: 2),
                            Text('길드장 ${g['master'] ?? '-'}  ·  멤버 ${g['memberCount'] ?? 0}명',
                                style: const TextStyle(color: Colors.white54, fontSize: 11)),
                          ],
                        ),
                      ),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                            backgroundColor: _kGold,
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                            minimumSize: const Size(0, 0),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                        onPressed: () => _joinGuild(uid, gid, g['name']?.toString() ?? ''),
                        child: const Text('가입', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ]),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _guildHome(BuildContext ctx, String uid, String gid) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('guilds').doc(gid).snapshots(),
      builder: (c, gsnap) {
        if (!gsnap.hasData) {
          return const Center(child: CircularProgressIndicator(color: _kGold));
        }
        if (!gsnap.data!.exists) {
          // 길드가 해체됨 → 내 정보 정리
          FirebaseFirestore.instance
              .collection('users')
              .doc(uid)
              .update({'guildId': '', 'guildName': ''});
          return Column(children: [
            _guildDialogHeader('길드',
                trailing: IconButton(
                    icon: const Icon(Icons.close, color: Colors.white54),
                    onPressed: () => Navigator.pop(ctx))),
            const Expanded(
                child: Center(
                    child: Text('길드가 해체되었어요.',
                        style: TextStyle(color: Colors.white54)))),
          ]);
        }
        final g = gsnap.data!.data() as Map<String, dynamic>;
        final isMaster = (g['masterUid'] ?? '') == uid;
        return Column(
          children: [
            _guildDialogHeader(g['name']?.toString() ?? '길드',
                trailing: IconButton(
                    icon: const Icon(Icons.close, color: Colors.white54),
                    onPressed: () => Navigator.pop(ctx))),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(children: [
                const Icon(Icons.military_tech, color: _kGold, size: 16),
                const SizedBox(width: 4),
                Text('길드장 ${g['master'] ?? '-'}',
                    style: const TextStyle(color: Colors.white70, fontSize: 13)),
                const SizedBox(width: 12),
                const Icon(Icons.people, color: _kGold, size: 16),
                const SizedBox(width: 4),
                Text('멤버 ${g['memberCount'] ?? 0}명',
                    style: const TextStyle(color: Colors.white70, fontSize: 13)),
              ]),
            ),
            const Divider(color: Colors.white12, height: 1),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('guilds')
                    .doc(gid)
                    .collection('members')
                    .snapshots(),
                builder: (c, msnap) {
                  if (!msnap.hasData) {
                    return const Center(child: CircularProgressIndicator(color: _kGold));
                  }
                  final members = msnap.data!.docs
                      .map((d) => d.data() as Map<String, dynamic>)
                      .toList()
                    ..sort((a, b) {
                      final ra = (a['role'] == 'master') ? 0 : 1;
                      final rb = (b['role'] == 'master') ? 0 : 1;
                      if (ra != rb) return ra - rb;
                      return ((b['level'] ?? 0) as int).compareTo((a['level'] ?? 0) as int);
                    });
                  return ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    itemCount: members.length,
                    itemBuilder: (c, i) {
                      final m = members[i];
                      final mMaster = m['role'] == 'master';
                      return Container(
                        margin: const EdgeInsets.symmetric(vertical: 3),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                            color: const Color(0xFF2A2A2A),
                            borderRadius: BorderRadius.circular(8)),
                        child: Row(children: [
                          Icon(mMaster ? Icons.military_tech : Icons.person,
                              color: mMaster ? _kGold : Colors.white38, size: 18),
                          const SizedBox(width: 8),
                          Text(m['nickname']?.toString() ?? '',
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                          const SizedBox(width: 6),
                          Text('Lv.${m['level'] ?? 1}',
                              style: const TextStyle(color: Colors.white38, fontSize: 12)),
                          const Spacer(),
                          if (mMaster)
                            const Text('길드장',
                                style: TextStyle(color: _kGold, fontSize: 11, fontWeight: FontWeight.bold)),
                        ]),
                      );
                    },
                  );
                },
              ),
            ),
            const Divider(color: Colors.white12, height: 1),
            Padding(
              padding: const EdgeInsets.all(12),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.redAccent,
                      side: const BorderSide(color: Colors.redAccent),
                      padding: const EdgeInsets.symmetric(vertical: 10)),
                  icon: Icon(isMaster ? Icons.delete_forever : Icons.logout, size: 18),
                  label: Text(isMaster ? '길드 해체' : '길드 탈퇴',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  onPressed: () => _leaveGuild(ctx, uid, gid, isMaster),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  void _createGuildDialog(String uid) {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('길드 만들기', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: ctrl,
              maxLength: 12,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                hintText: '길드 이름 (최대 12자)',
                hintStyle: TextStyle(color: Colors.white38),
                counterStyle: TextStyle(color: Colors.white38),
                enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: _kGold)),
              ),
            ),
            const SizedBox(height: 6),
            const Text('생성 비용: 10,000 P',
                style: TextStyle(color: _kGold, fontSize: 12, fontWeight: FontWeight.bold)),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('취소', style: TextStyle(color: Colors.white54))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _kGold, foregroundColor: Colors.black),
            onPressed: () => _createGuild(ctx, uid, ctrl.text.trim()),
            child: const Text('만들기', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _createGuild(BuildContext ctx, String uid, String name) async {
    if (name.isEmpty) {
      _toast('길드 이름을 입력해주세요.');
      return;
    }
    if (_gold < 10000) {
      _toast('포인트가 부족해요. (10,000 P 필요)');
      return;
    }
    final fs = FirebaseFirestore.instance;
    // 중복 이름 확인
    final dup = await fs.collection('guilds').where('name', isEqualTo: name).limit(1).get();
    if (dup.docs.isNotEmpty) {
      _toast('이미 있는 길드 이름이에요.');
      return;
    }
    final guildRef = fs.collection('guilds').doc();
    final batch = fs.batch();
    batch.set(guildRef, {
      'name': name,
      'master': widget.nickname,
      'masterUid': uid,
      'memberCount': 1,
      'createdAt': FieldValue.serverTimestamp(),
    });
    batch.set(guildRef.collection('members').doc(uid), {
      'uid': uid,
      'nickname': widget.nickname,
      'role': 'master',
      'level': _level,
      'joinedAt': FieldValue.serverTimestamp(),
    });
    batch.update(fs.collection('users').doc(uid), {
      'gold': FieldValue.increment(-10000),
      'guildId': guildRef.id,
      'guildName': name,
    });
    await batch.commit();
    if (mounted) {
      setState(() {
        _gold -= 10000;
        currentPoints = _gold;
      });
    }
    if (ctx.mounted) Navigator.pop(ctx); // 생성 다이얼로그 닫기
    _toast('"$name" 길드를 만들었어요! 🎉');
  }

  Future<void> _joinGuild(String uid, String gid, String gname) async {
    final fs = FirebaseFirestore.instance;
    final guildRef = fs.collection('guilds').doc(gid);
    final batch = fs.batch();
    batch.set(guildRef.collection('members').doc(uid), {
      'uid': uid,
      'nickname': widget.nickname,
      'role': 'member',
      'level': _level,
      'joinedAt': FieldValue.serverTimestamp(),
    });
    batch.update(guildRef, {'memberCount': FieldValue.increment(1)});
    batch.update(fs.collection('users').doc(uid), {
      'guildId': gid,
      'guildName': gname,
    });
    await batch.commit();
    _toast('"$gname" 길드에 가입했어요!');
  }

  Future<void> _leaveGuild(BuildContext ctx, String uid, String gid, bool isMaster) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: Text(isMaster ? '길드 해체' : '길드 탈퇴',
            style: const TextStyle(color: Colors.white)),
        content: Text(
            isMaster
                ? '길드를 해체하면 모든 멤버가 나가게 돼요.\n정말 해체할까요?'
                : '정말 길드를 탈퇴할까요?',
            style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('취소', style: TextStyle(color: Colors.white54))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(c, true),
            child: Text(isMaster ? '해체' : '탈퇴'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final fs = FirebaseFirestore.instance;
    final guildRef = fs.collection('guilds').doc(gid);
    if (isMaster) {
      // 모든 멤버 정보 정리 + 길드 삭제
      final members = await guildRef.collection('members').get();
      final batch = fs.batch();
      for (final m in members.docs) {
        batch.update(fs.collection('users').doc(m.id), {'guildId': '', 'guildName': ''});
        batch.delete(m.reference);
      }
      batch.delete(guildRef);
      await batch.commit();
      _toast('길드를 해체했어요.');
    } else {
      final batch = fs.batch();
      batch.delete(guildRef.collection('members').doc(uid));
      batch.update(guildRef, {'memberCount': FieldValue.increment(-1)});
      batch.update(fs.collection('users').doc(uid), {'guildId': '', 'guildName': ''});
      await batch.commit();
      _toast('길드를 탈퇴했어요.');
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: const Color(0xFF333333),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Widget _topHud() {
    final lv = _level.clamp(1, 30);
    final curBase = globalExpTable[lv];
    final nextBase = lv < 30 ? globalExpTable[lv + 1] : globalExpTable[30];
    final span = nextBase - curBase;
    final prog = (lv >= 30 || span <= 0) ? 1.0 : ((currentExp - curBase) / span).clamp(0.0, 1.0);
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(children: [
                  Text(widget.isSea ? '🌊' : '🏞️', style: const TextStyle(fontSize: 16)),
                  const SizedBox(width: 6),
                  Text(widget.isSea ? '바다낚시 광장' : '민물낚시 광장',
                      style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900)),
                ]),
                const SizedBox(height: 3),
                Row(children: [
                  const Icon(Icons.place, color: _kGold, size: 14),
                  const SizedBox(width: 2),
                  Text(widget.spot['name'].toString(),
                      style: const TextStyle(color: _kGold, fontSize: 14, fontWeight: FontWeight.bold)),
                  const SizedBox(width: 6),
                  ...List.generate(widget.spot['stars'] as int,
                      (i) => const Icon(Icons.star, color: _kGold, size: 11)),
                ]),
              ],
            ),
          ),
          // 내 정보 카드 (스킨/레벨/경험치바/머니/가방)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.6),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _kGold.withOpacity(0.6)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: _kGold, width: 1.5),
                    image: DecorationImage(
                        image: AssetImage(_charImage),
                        fit: BoxFit.cover,
                        alignment: const Alignment(0, -0.7)),
                  ),
                ),
                const SizedBox(width: 10),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Text('Lv.$_level',
                          style: const TextStyle(color: _kGold, fontWeight: FontWeight.w900, fontSize: 15)),
                      const SizedBox(width: 6),
                      Text(widget.nickname,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                    ]),
                    const SizedBox(height: 4),
                    SizedBox(
                      width: 150,
                      child: Stack(children: [
                        Container(
                            height: 9,
                            decoration: BoxDecoration(
                                color: Colors.white24, borderRadius: BorderRadius.circular(5))),
                        FractionallySizedBox(
                          widthFactor: prog,
                          child: Container(
                              height: 9,
                              decoration: BoxDecoration(
                                  color: _kGold, borderRadius: BorderRadius.circular(5))),
                        ),
                      ]),
                    ),
                    const SizedBox(height: 2),
                    Text(lv >= 30 ? 'MAX LEVEL' : '$currentExp / $nextBase EXP',
                        style: const TextStyle(color: Colors.white70, fontSize: 10)),
                    const SizedBox(height: 3),
                    Row(children: [
                      const Text('포인트',
                          style: TextStyle(color: _kGold, fontWeight: FontWeight.bold, fontSize: 12)),
                      const SizedBox(width: 6),
                      Text('$_gold',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                    ]),
                  ],
                ),
                const SizedBox(width: 10),
                _iconBtn(Icons.backpack, '가방', _openInventory),
                const SizedBox(width: 6),
                _iconBtn(Icons.groups, '길드', _openGuild),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
