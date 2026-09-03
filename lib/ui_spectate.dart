// ignore_for_file: deprecated_member_use
// 🎣👀 [친구 낚시 라이브 관전 화면] 친구가 낚시하는 상태를 RTDB로 받아 재구성해 보여준다.
//   · 보이는 것: 낚시 장면(대기/입질/밀당·발악/저항/제압단계/시간/HIT) + 채팅 + 좌상단 낚시장소 + 우상단 등급/닉.
//   · 숨기는 것(개인정보): 제압력·경험치·포인트, 인벤/미끼/채집망/밑밥/설정/길드/카메라/미션/전체화면 버튼.
//   · 읽기 전용(챔질/당기기 버튼은 친구 동작을 비추기만). 채팅만 입력 가능.
import 'dart:async';
import 'package:flutter/foundation.dart' show mapEquals;
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'fishing_live.dart';
import 'fishing_logic.dart'; // cleanChat(비속어 필터)
import 'game_config.dart' show chatSessionStart; // 이번 접속 이후 대화만 보기
import 'weather.dart'; // 🌧️ 친구 날씨 미러(WeatherOverlay + WeatherInfo)
import 'ui_fishing.dart'; // 🎣 실제 파이팅 오버레이 재사용(FishingFightingOverlay)

const Color _kGold = Color(0xFFD4AF37);
const String _specDbUrl =
    'https://camnak-fishing-default-rtdb.asia-southeast1.firebasedatabase.app';
FirebaseDatabase _specDb() =>
    FirebaseDatabase.instanceFor(app: Firebase.app(), databaseURL: _specDbUrl);
const int _specFreshMs = 40000; // presence 신선도(ui_guild와 동일)

/// 👀 친구목록에 붙는 "구경" 버튼 — 친구가 '낚시 중(아레나 아님)'일 때만 노출.
///   status_nick/{nick} 를 실시간 구독해 fishing==true + 신선하면 버튼을 보여주고,
///   탭하면 그 친구의 uid로 관전 화면을 연다.
class SpectateFriendButton extends StatefulWidget {
  final String nick; // 친구 닉네임(status_nick 키)
  final String myNickname; // 내 닉네임(관전 화면 채팅 발신용)
  const SpectateFriendButton({super.key, required this.nick, required this.myNickname});
  @override
  State<SpectateFriendButton> createState() => _SpectateFriendButtonState();
}

class _SpectateFriendButtonState extends State<SpectateFriendButton> {
  StreamSubscription<DatabaseEvent>? _sub;
  bool _fishing = false;
  String _uid = '';

  @override
  void initState() {
    super.initState();
    _sub = _specDb().ref('status_nick/${widget.nick}').onValue.listen((e) {
      final v = e.snapshot.value;
      bool fishing = false;
      String uid = '';
      if (v is Map) {
        final bool on = v['online'] == true;
        final int t = (v['t'] is int) ? v['t'] as int : 0;
        final bool fresh = (DateTime.now().millisecondsSinceEpoch - t) < _specFreshMs;
        fishing = on && fresh && v['fishing'] == true;
        uid = (v['uid'] ?? '').toString();
      }
      if (mounted) setState(() { _fishing = fishing; _uid = uid; });
    }, onError: (Object _) {});
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_fishing || _uid.isEmpty) return const SizedBox.shrink();
    return IconButton(
      icon: const Icon(Icons.visibility, color: Color(0xFF7FFFB0), size: 20),
      tooltip: '낚시 구경',
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      onPressed: () {
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => SpectateFishingScreen(
            fisherUid: _uid,
            fisherNick: widget.nick,
            myNickname: widget.myNickname,
          ),
        ));
      },
    );
  }
}

class SpectateFishingScreen extends StatefulWidget {
  final String fisherUid; // 관전 대상 친구 uid
  final String fisherNick; // 친구 닉네임(로딩/종료 안내용)
  final String myNickname; // 내 닉네임(채팅 발신용)
  const SpectateFishingScreen({
    super.key,
    required this.fisherUid,
    required this.fisherNick,
    required this.myNickname,
  });

  @override
  State<SpectateFishingScreen> createState() => _SpectateFishingScreenState();
}

class _SpectateFishingScreenState extends State<SpectateFishingScreen> {
  SpectateSession? _session;
  final TextEditingController _chatCtrl = TextEditingController();
  Map<String, dynamic> _meta = {};
  Map<String, dynamic> _state = {};
  bool _gotAny = false;
  // 🎣 실제 파이팅 오버레이에 전투 프레임 공급용 스트림
  final StreamController<Map<String, dynamic>> _fightCtrl =
      StreamController<Map<String, dynamic>>.broadcast();
  // 💬 관전방 채팅 스트림 — build()에서 만들면 화면이 새로 그려질 때마다 재구독되므로 1회만 만든다
  late final Stream<QuerySnapshot> _chatStream = FirebaseFirestore.instance
      .collection('spectate_chat')
      .doc(widget.fisherUid)
      .collection('messages')
      // 이번 접속 이후 대화만 — 재접속하면 지난 대화는 안 보인다(전체·길드 채팅과 같은 기준)
      .where('timestamp', isGreaterThanOrEqualTo: chatSessionStart())
      .orderBy('timestamp', descending: true)
      .limit(30)
      .snapshots();

  @override
  void initState() {
    super.initState();
    final myUid = FirebaseAuth.instance.currentUser?.uid ?? '_none_';
    _session = SpectateSession(widget.fisherUid, myUid, myNick: widget.myNickname);
    _session!.stream().listen((snap) {
      if (!mounted) return;
      final Map<String, dynamic> newMeta = (snap['meta'] is Map)
          ? Map<String, dynamic>.from(
              (snap['meta'] as Map).map((k, v) => MapEntry(k.toString(), v)))
          : {};
      final Map<String, dynamic> newState = (snap['state'] is Map)
          ? Map<String, dynamic>.from(
              (snap['state'] as Map).map((k, v) => MapEntry(k.toString(), v)))
          : {};
      // 🚀 파이팅 중엔 초당 10프레임이 들어온다. 그때마다 화면 전체(배경·날씨·채팅)를
      //    다시 그리면 낭비이므로, 눈에 보이는 게 실제로 바뀔 때만 setState 한다.
      final bool changed = !_gotAny
          || !mapEquals(_meta, newMeta)
          || (newState['phase'] ?? '') != (_state['phase'] ?? '')
          || (newState['rod'] ?? -1) != (_state['rod'] ?? -1);
      _meta = newMeta;
      _state = newState;
      if (changed) setState(() { _gotAny = true; });
      // 🎣 파이팅 프레임을 실제 오버레이로 전달
      if ((_state['phase'] ?? '') == 'fighting' && !_fightCtrl.isClosed) {
        _fightCtrl.add(_state);
      }
    });
  }

  @override
  void dispose() {
    _session?.dispose();
    _chatCtrl.dispose();
    _fightCtrl.close();
    super.dispose();
  }

  void _sendChat() {
    final text = FishingLogic.cleanChat(_chatCtrl.text.trim()); // 🛡️ 비속어 필터(낚시화면·광장과 동일)
    if (text.isEmpty) return;
    FirebaseFirestore.instance
        .collection('spectate_chat')
        .doc(widget.fisherUid) // 👀 낚시꾼 1명 = 관전방 1개
        .collection('messages')
        .add({
      'nickname': widget.myNickname,
      'message': text,
      'timestamp': FieldValue.serverTimestamp(),
    });
    _chatCtrl.clear();
  }

  int _toI(dynamic v, [int def = 0]) =>
      (v is num) ? v.toInt() : (int.tryParse('$v') ?? def);

  @override
  Widget build(BuildContext context) {
    final bool active = _meta['active'] == true;
    final String spot = (_meta['spot'] ?? '낚시터').toString();
    final String rank = (_meta['rank'] ?? '').toString();
    final String nick = (_meta['nick'] ?? widget.fisherNick).toString();
    final String bg = (_meta['bg'] ?? '').toString();
    final bool sea = _meta['sea'] == true;
    final int pty = _toI(_meta['pty'], 0);
    final String phase = (_state['phase'] ?? 'waiting').toString();

    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: FittedBox(
          fit: BoxFit.contain,
          child: SizedBox(
            width: 1280,
            height: 720,
            child: Stack(
              children: [
                // 🌄 배경
                Positioned.fill(
                  child: bg.isEmpty
                      ? _bgFallback()
                      : Image.asset(bg, fit: BoxFit.cover,
                          errorBuilder: (c, e, s) => _bgFallback()),
                ),
                // 🌧️ 친구 날씨 미러(비/눈) — 방송된 pty로 강제(내 위치 무시)
                if (pty > 0)
                  Positioned.fill(child: IgnorePointer(
                    child: WeatherOverlay(isSea: sea, forceWeather: WeatherInfo(pty: pty)),
                  )),

                // 상단 가독성 그라데이션
                Positioned(
                  top: 0, left: 0, right: 0, height: 130,
                  child: IgnorePointer(
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter, end: Alignment.bottomCenter,
                          colors: [Colors.black.withOpacity(0.55), Colors.transparent],
                        ),
                      ),
                    ),
                  ),
                ),

                // 🎣 중앙 낚시 장면(단계별) — 민물=찌 그림 / 바다=입질 텍스트
                Positioned.fill(child: _phaseContent(phase, sea)),

                // 👀 관전 배지(상단 중앙)
                Positioned(
                  top: 16, left: 0, right: 0,
                  child: Center(child: _spectateBadge()),
                ),

                // ↩️ 좌상단: 뒤로 + 낚시장소
                Positioned(
                  top: 18, left: 18,
                  child: Row(children: [
                    _circleBtn(Icons.arrow_back_ios_new, () => Navigator.of(context).maybePop()),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.5),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: _kGold.withOpacity(0.7), width: 1),
                      ),
                      child: Text(spot, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                    ),
                  ]),
                ),

                // 🎖️ 우상단: 등급 + 닉네임 조사님
                Positioned(
                  top: 18, right: 18,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: _kGold.withOpacity(0.8), width: 1.2),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      if (rank.isNotEmpty) ...[
                        Text(rank, style: const TextStyle(color: _kGold, fontSize: 14, fontWeight: FontWeight.bold)),
                        const SizedBox(width: 8),
                      ],
                      Text('$nick 조사님', style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
                    ]),
                  ),
                ),

                // 💬 좌하단: 전체채팅(입력 가능)
                Positioned(
                  left: 24, bottom: 24,
                  child: _chatPanel(),
                ),

                // ⛔ 친구가 낚시를 마쳤거나 아직 연결 전
                if (!active) Positioned.fill(child: _endedOverlay()),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _bgFallback() => Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter, end: Alignment.bottomCenter,
            colors: [Color(0xFF0B1A2A), Color(0xFF0E2436)],
          ),
        ),
      );

  Widget _spectateBadge() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.redAccent.withOpacity(0.85),
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Text('👀 관전 중', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
      );

  Widget _circleBtn(IconData ic, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.5), shape: BoxShape.circle,
            border: Border.all(color: _kGold.withOpacity(0.7), width: 1),
          ),
          child: Icon(ic, color: Colors.white, size: 18),
        ),
      );

  // 🎣 단계별 중앙 장면 (민물=찌 그림 / 바다=입질 텍스트)
  Widget _phaseContent(String phase, bool sea) {
    switch (phase) {
      case 'bite':
        return _rodsScene(raised: true);
      case 'fighting':
        // 🎣 실제 게임 파이팅 오버레이를 관전 모드로 재사용(낚싯대·바·손·노브 그대로)
        return FishingFightingOverlay(
          // 📦 상자를 당기는 중이면 물고기가 아니라 상자 그림이 끌려와야 한다
          key: ValueKey('spectate-fight-${_state['isBox'] == true ? 'box' : 'fish'}'),
          isBox: _state['isBox'] == true,
          fish: <String, dynamic>{'img': (_state['img'] ?? '').toString()},
          playerTotalStats: 0,
          locationStars: 0,
          onFinished: (_, __) {},
          rodImageSuffix: (_meta['rodSuffix'] ?? '').toString(),
          lureRodKey: (_meta['lureKey'] ?? '').toString(),
          isSea: sea,
          spectator: true,
          spectatorStream: _fightCtrl.stream,
        );
      case 'landed':
        return _landedCard();
      case 'casting':
        return _hint('친구가 캐스팅 중...');
      case 'setup':
        return _hint('친구가 낚시 준비 중이에요...'); // 대기실에서 대편성·미끼 고르는 중
      case 'waiting':
        return _rodsScene(raised: false);
      default: // 아직 아무 신호도 못 받음 — 섣불리 낚싯대를 그리지 않는다
        return _hint('친구 낚시터에 들어가는 중...');
    }
  }

  // 🌊 바다: 입질 텍스트
  Widget _biteText() => const Center(
        child: Text('입질 !!',
            style: TextStyle(color: Colors.redAccent, fontSize: 120, fontWeight: FontWeight.w900, fontStyle: FontStyle.italic,
                shadows: [Shadow(color: Colors.black, blurRadius: 20, offset: Offset(5, 5))])),
      );

  // 🎣 민물: 물 위의 찌(대기=가라앉음 / 입질=올라옴+찌올림 안내) + 물 파문
  // ── 낚시꾼 화면(ui_fishing 의 _buildFieldRods)과 같은 값. 그쪽을 바꾸면 여기도 같이 바꿀 것 ──
  static const double _kFloatBottom = 290.0;   // fieldFloatBottomOffset
  static const double _kFloatDepth = -12.0;    // fieldFloatDepthOffset
  static const double _kFloatSpacing = 0.0;    // fieldFloatSpacing
  static const double _kPlatformW = 1000.0;
  static const double _kPlatformH = 200.0;
  static const double _kPlatformBottom = -120.0;
  static const double _kPlatformDark = 0.7;
  static const double _kFanStep = 0.06;        // rodFanAngleStep
  static const double _kRodLen = 240.0;        // fieldRodLength
  static const double _kSeaRight = -30.0;
  static const double _kSeaBottom = -50.0;
  static const double _kSeaSize = 450.0;

  // 입질 시 케미 반전색 — ui_fishing 의 _getBiteColor 와 동일.
  //   ⚠️ 방송으로 받은 값은 일반 Color, Colors.green 등은 MaterialColor 라
  //      '=='로는 절대 같아지지 않는다(타입이 다름). 반드시 색값으로 비교할 것.
  Color _biteColor(Color c) {
    final int v = c.value;
    if (v == Colors.green.value) return Colors.redAccent;
    if (v == Colors.red.value) return Colors.greenAccent;
    if (v == Colors.blue.value) return Colors.orangeAccent;
    if (v == Colors.yellow.value) return Colors.purpleAccent;
    return Colors.white;
  }

  /// 🎣 친구의 실제 낚시 장면을 그대로 재현.
  ///   민물 = 좌대 + 방송된 대편성 갯수만큼 부채꼴 낚싯대 + 친구가 장착한 찌 그림.
  ///          입질 온 그 대의 찌만 케미색이 바뀌며 스르륵 올라온다(낚시꾼 화면과 같은 6초 곡선).
  ///   바다/루어 = 장착 낚싯대별 대기 그림 + 입질 텍스트.
  Widget _rodsScene({required bool raised}) {
    final bool sea = _meta['sea'] == true;
    final bool lure = _meta['lure'] == true;
    final String lureKey = (_meta['lureKey'] ?? '').toString();
    final String rodSfx = (_meta['rodSuffix'] ?? '').toString();

    // 🎣 루어 / 바다 — 손낚싯대 대기 그림(낚싯대별)
    if (lure || sea) {
      final String img = lure
          ? 'assets/images/waiting_lure_bc-$lureKey.png'
          : (rodSfx.isEmpty ? 'assets/images/waiting_sea.png' : 'assets/images/waiting_sea_$rodSfx.png');
      return Stack(children: [
        Positioned(
          right: _kSeaRight, bottom: _kSeaBottom,
          child: Image.asset(img, height: _kSeaSize, fit: BoxFit.contain,
              errorBuilder: (c, e, s) => Image.asset('assets/images/waiting_sea.png',
                  height: _kSeaSize, fit: BoxFit.contain,
                  errorBuilder: (c2, e2, s2) => const Icon(Icons.waves, size: 200, color: Colors.white10))),
        ),
        if (raised) _biteText(),
      ]);
    }

    // 🎣 민물 — 좌대 + 대편성
    final int rods = _toI(_meta['rods'], 1).clamp(1, 20);
    final int bitingRod = _toI(_state['rod'], -1);
    final String floatIcon = (_meta['floatIcon'] ?? '').toString();
    final Color chemi = Color(_toI(_meta['chemi'], Colors.green.value));
    final double centerIndex = (rods - 1) / 2;

    return Stack(
      clipBehavior: Clip.none, // 좌대가 화면 아래로 걸치는 구조(낚시꾼 화면과 동일) → 넘침 경고 방지
      children: [
      Positioned(
        bottom: 0, left: 0, right: 0,
        child: Stack(
          alignment: Alignment.bottomCenter, clipBehavior: Clip.none,
          children: [
            Positioned(
              bottom: _kPlatformBottom,
              child: Image.asset('assets/items/platform_fw.png',
                  width: _kPlatformW, height: _kPlatformH, fit: BoxFit.fill,
                  color: Colors.black.withOpacity(_kPlatformDark), colorBlendMode: BlendMode.srcATop,
                  errorBuilder: (c, e, s) => Container()),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List.generate(rods, (index) {
                // 입질 대 번호가 안 실려오면(옛 버전 방송) 가운데 대가 올라온 것으로 본다
                final bool isBiting =
                    raised && (bitingRod < 0 ? index == rods ~/ 2 : index == bitingRod);
                final Color cur = isBiting ? _biteColor(chemi) : chemi;
                final double angle = (index - centerIndex) * _kFanStep;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: _kFloatSpacing),
                  child: Transform.rotate(
                    angle: angle, alignment: Alignment.bottomCenter,
                    child: Stack(
                      clipBehavior: Clip.none, alignment: Alignment.bottomCenter,
                      children: [
                        Image.asset('assets/items/rod_fw_basic_deployed.png',
                            height: _kRodLen, fit: BoxFit.contain, alignment: Alignment.bottomCenter,
                            errorBuilder: (c, e, s) => const Icon(Icons.phishing, color: Colors.white24, size: 80)),
                        Positioned(
                          bottom: _kFloatBottom + _kFloatDepth,
                          child: Transform.rotate(
                            angle: -angle,
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 6000),
                              curve: Curves.easeOutCubic,
                              width: 30,
                              height: isBiting ? (rods >= 8 ? 25.0 : 22.0) : 7.0,
                              child: Stack(
                                alignment: Alignment.topCenter, clipBehavior: Clip.none,
                                children: [
                                  Container(width: 3, height: 5, decoration: BoxDecoration(
                                    color: cur, borderRadius: BorderRadius.circular(5),
                                    boxShadow: [BoxShadow(color: cur.withOpacity(0.8), blurRadius: 5, spreadRadius: 2)],
                                  )),
                                  Transform.translate(
                                    offset: const Offset(0, 5),
                                    child: Image.asset(
                                      floatIcon.isEmpty ? 'assets/images/float_default.png' : floatIcon,
                                      height: rods >= 8 ? 40 : 65, fit: BoxFit.contain, alignment: Alignment.topCenter,
                                      errorBuilder: (c, e, s) => _drawnFloat(isBiting),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ),
          ],
        ),
      ),
    ]);
  }

  // 찌 이미지가 없을 때 대비: 간단히 그린 전자찌(발광 팁 + 몸통)
  Widget _drawnFloat(bool raised) {
    final Color tip = raised ? Colors.redAccent : Colors.orangeAccent;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 12, height: 12,
        decoration: BoxDecoration(shape: BoxShape.circle, color: tip,
            boxShadow: [BoxShadow(color: tip.withOpacity(0.85), blurRadius: 12)]),
      ),
      Container(width: 5, height: raised ? 96 : 80,
          decoration: BoxDecoration(color: Colors.white.withOpacity(0.85), borderRadius: BorderRadius.circular(3))),
    ]);
  }

  Widget _hint(String txt) => Align(
        alignment: const Alignment(0, 0.55),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(color: Colors.black.withOpacity(0.35), borderRadius: BorderRadius.circular(16)),
          child: Text(txt, style: const TextStyle(color: Colors.white70, fontSize: 18, fontWeight: FontWeight.w600)),
        ),
      );

  // 🎉 HIT 랜딩 카드
  Widget _landedCard() {
    final fish = (_state['fish'] is Map)
        ? Map<String, dynamic>.from((_state['fish'] as Map).map((k, v) => MapEntry(k.toString(), v)))
        : {};
    if (fish.isEmpty) return _hint('친구가 물고기를 낚았어요!');
    final bool bExp = fish['boostExp'] == true; // ⚡ 친구가 경험치 물약 사용 중
    final bool bPts = fish['boostPts'] == true; // 🪙 친구가 KREFT 카드 사용 중
    final String img = (fish['img'] ?? '').toString();
    final int exp = _toI(fish['exp'], 0);
    final int pts = _toI(fish['pts'], 0);
    return Center(
      child: Container(
        // ⚠️ mainAxisSize.min을 줘도 아래 Row가 max폭이면 카드가 전체폭이 됨 → Row도 min으로.
        padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 22),
        decoration: BoxDecoration(
          color: const Color(0xFF0A0A0A), // 불투명(배경 달 비침 방지)
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _kGold, width: 2.5),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('HIT !!!', style: TextStyle(color: Colors.redAccent, fontSize: 34, fontWeight: FontWeight.w900, fontStyle: FontStyle.italic,
              shadows: [Shadow(color: Colors.black, blurRadius: 10, offset: Offset(2, 2))])),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.white24)),
            padding: const EdgeInsets.all(8),
            child: Image.asset(img, height: 118, fit: BoxFit.contain,
                errorBuilder: (c, e, s) => const Icon(Icons.set_meal, color: Colors.white54, size: 80)),
          ),
          const SizedBox(height: 12),
          Text('${fish['name'] ?? ''}', style: const TextStyle(color: Colors.white, fontSize: 25, fontWeight: FontWeight.bold)),
          Text('${fish['size'] ?? ''} ${fish['unit'] ?? ''}', style: const TextStyle(color: Colors.cyanAccent, fontSize: 29, fontWeight: FontWeight.w900)),
          const SizedBox(height: 10),
          Row(mainAxisSize: MainAxisSize.min, children: [
            Text('+ $exp EXP', style: const TextStyle(color: Colors.lightGreenAccent, fontSize: 18, fontWeight: FontWeight.bold)),
            if (pts > 0) ...[
              const SizedBox(width: 14),
              Text('+ $pts KREFT', style: const TextStyle(color: Colors.yellowAccent, fontSize: 18, fontWeight: FontWeight.bold)),
            ],
          ]),
          // ⚡ 친구가 물약·카드를 쓰고 있으면 2배로 받는 게 보이도록(낚시꾼 화면과 같은 문구)
          if (bExp || bPts) ...[
            const SizedBox(height: 5),
            Text(
              bExp && bPts
                  ? '⚡ 경험치 x2 · 🪙 KREFT x2 적용!'
                  : bExp ? '⚡ 경험치 x2 적용!' : '🪙 KREFT x2 적용!',
              style: const TextStyle(color: Color(0xFF9C6BFF), fontSize: 13, fontWeight: FontWeight.bold),
            ),
          ],
        ]),
      ),
    );
  }

  // ⛔ 종료/연결대기 오버레이
  Widget _endedOverlay() {
    final bool loading = !_gotAny;
    return Container(
      color: Colors.black.withOpacity(0.72),
      child: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (loading) ...[
            const CircularProgressIndicator(color: _kGold),
            const SizedBox(height: 18),
            Text('${widget.fisherNick}님 화면을 불러오는 중...',
                style: const TextStyle(color: Colors.white70, fontSize: 18, fontWeight: FontWeight.w600)),
          ] else ...[
            const Text('🎣', style: TextStyle(fontSize: 48)),
            const SizedBox(height: 12),
            Text('${widget.fisherNick}님이 낚시를 마쳤어요',
                style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 18),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: _kGold, foregroundColor: Colors.black),
              onPressed: () => Navigator.of(context).maybePop(),
              child: const Text('닫기', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ),
          ],
        ]),
      ),
    );
  }

  // 💬 관전방 채팅 패널(입력 가능) — spectate_chat/{fisherUid}/messages
  //    낚시꾼 + 그를 구경 중인 사람들만 보는 방. 전체채팅으로 새어나가지 않는다.
  Widget _chatPanel() {
    return Container(
      width: 380, height: 216,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.6),
        border: Border.all(color: Colors.amber, width: 1.5),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(children: [
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: _chatStream,
            builder: (c, snap) {
              if (!snap.hasData) return const SizedBox.shrink();
              final docs = snap.data!.docs;
              return ListView.builder(
                reverse: true,
                itemCount: docs.length,
                itemBuilder: (c, i) {
                  final d = docs[i].data() as Map<String, dynamic>;
                  final sender = (d['nickname'] ?? '조사님').toString();
                  final msg = (d['message'] ?? '').toString();
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: RichText(
                      text: TextSpan(children: [
                        const TextSpan(text: '관전> ', style: TextStyle(color: Color(0xFF7FFFB0), fontSize: 12, fontWeight: FontWeight.bold)),
                        TextSpan(text: '$sender: ', style: const TextStyle(color: _kGold, fontSize: 12, fontWeight: FontWeight.bold)),
                        TextSpan(text: msg, style: const TextStyle(color: Colors.white, fontSize: 12)),
                      ]),
                    ),
                  );
                },
              );
            },
          ),
        ),
        const SizedBox(height: 6),
        Row(children: [
          Expanded(
            child: SizedBox(
              height: 34,
              child: TextField(
                controller: _chatCtrl,
                style: const TextStyle(color: Colors.white, fontSize: 13),
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _sendChat(),
                decoration: InputDecoration(
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  hintText: '메시지를 입력하세요...',
                  hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
                  filled: true, fillColor: Colors.white10,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide.none),
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: _sendChat,
            child: Container(
              width: 34, height: 34,
              decoration: BoxDecoration(color: _kGold, borderRadius: BorderRadius.circular(6)),
              child: const Icon(Icons.send, color: Colors.black, size: 18),
            ),
          ),
        ]),
      ]),
    );
  }
}
