// ignore_for_file: deprecated_member_use
// 🎣👀 [친구 낚시 라이브 관전 화면] 친구가 낚시하는 상태를 RTDB로 받아 재구성해 보여준다.
//   · 보이는 것: 낚시 장면(대기/입질/밀당·발악/저항/제압단계/시간/HIT) + 채팅 + 좌상단 낚시장소 + 우상단 등급/닉.
//   · 숨기는 것(개인정보): 제압력·경험치·포인트, 인벤/미끼/채집망/밑밥/설정/길드/카메라/미션/전체화면 버튼.
//   · 읽기 전용(챔질/당기기 버튼은 친구 동작을 비추기만). 채팅만 입력 가능.
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'fishing_live.dart';
import 'game_config.dart'; // chatSessionStart()
import 'weather.dart'; // 🌧️ 친구 날씨 미러(WeatherOverlay + WeatherInfo)

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

  @override
  void initState() {
    super.initState();
    final myUid = FirebaseAuth.instance.currentUser?.uid ?? '_none_';
    _session = SpectateSession(widget.fisherUid, myUid, myNick: widget.myNickname);
    _session!.stream().listen((snap) {
      if (!mounted) return;
      setState(() {
        _gotAny = true;
        _meta = (snap['meta'] is Map)
            ? Map<String, dynamic>.from(
                (snap['meta'] as Map).map((k, v) => MapEntry(k.toString(), v)))
            : {};
        _state = (snap['state'] is Map)
            ? Map<String, dynamic>.from(
                (snap['state'] as Map).map((k, v) => MapEntry(k.toString(), v)))
            : {};
      });
    });
  }

  @override
  void dispose() {
    _session?.dispose();
    _chatCtrl.dispose();
    super.dispose();
  }

  void _sendChat() {
    final text = _chatCtrl.text.trim();
    if (text.isEmpty) return;
    FirebaseFirestore.instance.collection('global_chat').add({
      'nickname': widget.myNickname,
      'message': text,
      'type': 'global',
      'receiver': '',
      'channel': '',
      'rank': '',
      'timestamp': FieldValue.serverTimestamp(),
    });
    _chatCtrl.clear();
  }

  double _toD(dynamic v, [double def = 0]) =>
      (v is num) ? v.toDouble() : (double.tryParse('$v') ?? def);
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
        return sea ? _biteText() : _floatScene(raised: true);
      case 'fighting':
        return _fightScene();
      case 'landed':
        return _landedCard();
      case 'casting':
        return _hint('친구가 캐스팅 중...');
      default: // waiting / idle
        return sea ? _hint('친구가 입질을 기다리는 중...') : _floatScene(raised: false);
    }
  }

  // 🌊 바다: 입질 텍스트
  Widget _biteText() => const Center(
        child: Text('입질 !!',
            style: TextStyle(color: Colors.redAccent, fontSize: 120, fontWeight: FontWeight.w900, fontStyle: FontStyle.italic,
                shadows: [Shadow(color: Colors.black, blurRadius: 20, offset: Offset(5, 5))])),
      );

  // 🎣 민물: 물 위의 찌(대기=가라앉음 / 입질=올라옴+찌올림 안내) + 물 파문
  Widget _floatScene({required bool raised}) {
    return AnimatedAlign(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOut,
      alignment: raised ? const Alignment(0, 0.12) : const Alignment(0, 0.30),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (raised)
          Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(color: Colors.redAccent.withOpacity(0.9), borderRadius: BorderRadius.circular(12)),
            child: const Text('🎣 찌 올림!', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          ),
        Image.asset('assets/items/float_fw_normal.png',
            height: raised ? 96 : 76, fit: BoxFit.contain,
            errorBuilder: (c, e, s) => _drawnFloat(raised)),
        // 🌊 물 파문(찌가 물에 떠 있는 느낌 — 덩그러니 방지)
        _ripple(),
      ]),
    );
  }

  Widget _ripple() => SizedBox(
        width: 130, height: 34,
        child: Stack(alignment: Alignment.center, children: [
          _ring(120, 30, 0.07),
          _ring(80, 20, 0.12),
          _ring(44, 12, 0.20),
        ]),
      );
  Widget _ring(double w, double h, double op) => Container(
        width: w, height: h,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.all(Radius.elliptical(w, h)),
          border: Border.all(color: Colors.white.withOpacity(op), width: 1.4),
        ),
      );

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

  // ⚔️ 밀당 전투 장면 재구성
  Widget _fightScene() {
    final double bar = _toD(_state['bar'], 0.5).clamp(0.0, 1.0);
    final int stage = _toI(_state['stage'], 1);
    final String mode = (_state['mode'] ?? 'calm').toString();
    final int timeLeft = _toI(_state['timeLeft'], 0);
    final bool pulling = _state['pulling'] == true;

    Widget? modeChip;
    if (mode == 'rage') {
      modeChip = _chip('⚠️  🐟 물고기의 발악!!', Colors.redAccent);
    } else if (mode == 'resist') {
      modeChip = _chip('⚠️  🐟 물고기의 저항!', Colors.orangeAccent);
    }

    return Stack(children: [
      // 상단 중앙: 발악/저항 칩 + 제한시간
      Positioned(
        top: 175, left: 0, right: 0,
        child: Column(children: [
          if (modeChip != null) modeChip,
          const SizedBox(height: 10),
          Text('제한시간: $timeLeft초',
              style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold,
                  shadows: [Shadow(color: Colors.black45, blurRadius: 5)])),
        ]),
      ),
      // 우측: N단 제압 (바 위 오른쪽)
      Positioned(
        right: 60, bottom: 300,
        child: Text('$stage단 제압!',
            style: const TextStyle(color: _kGold, fontSize: 30, fontWeight: FontWeight.w900, fontStyle: FontStyle.italic,
                shadows: [Shadow(color: Colors.black, blurRadius: 8, offset: Offset(2, 2))])),
      ),
      // 🎣 밀당 바 — 게임과 동일(bottom230/left50/right50, 빨강-흰-파랑 + 중앙눈금 + fighting_fish)
      Positioned(
        bottom: 230, left: 50, right: 50,
        child: Stack(alignment: Alignment.center, clipBehavior: Clip.none, children: [
          Container(
            height: 15,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              gradient: const LinearGradient(colors: [Colors.redAccent, Colors.white, Colors.blueAccent]),
              boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
            ),
          ),
          Container(width: 3, height: 25, color: Colors.white.withOpacity(0.6)),
          Align(
            alignment: Alignment(bar * 2 - 1, 0), // 0=빨강(왼쪽) ~ 1=파랑(오른쪽)
            child: Image.asset('assets/images/fighting_fish.png', width: 64, fit: BoxFit.contain,
                errorBuilder: (c, e, s) => const Text('🐟', style: TextStyle(fontSize: 34))),
          ),
        ]),
      ),
      // 우하단: 풀기 / 당기기 (친구 동작 미러, 비활성)
      Positioned(
        right: 40, bottom: 60,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: pulling ? Colors.white12 : Colors.orange.withOpacity(0.85),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text('◀ 풀기', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 12),
          Container(
            width: 88, height: 88,
            decoration: BoxDecoration(
              color: pulling ? _kGold : _kGold.withOpacity(0.5),
              shape: BoxShape.circle,
              boxShadow: pulling ? [BoxShadow(color: _kGold.withOpacity(0.6), blurRadius: 18)] : null,
            ),
            child: const Center(
              child: Text('당기기', style: TextStyle(color: Colors.black, fontSize: 20, fontWeight: FontWeight.w900)),
            ),
          ),
        ]),
      ),
    ]);
  }

  Widget _chip(String txt, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
        decoration: BoxDecoration(color: c.withOpacity(0.9), borderRadius: BorderRadius.circular(22)),
        child: Text(txt, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
      );

  // 🎉 HIT 랜딩 카드
  Widget _landedCard() {
    final fish = (_state['fish'] is Map)
        ? Map<String, dynamic>.from((_state['fish'] as Map).map((k, v) => MapEntry(k.toString(), v)))
        : {};
    if (fish.isEmpty) return _hint('친구가 물고기를 낚았어요!');
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
              Text('+ $pts Pts', style: const TextStyle(color: Colors.yellowAccent, fontSize: 18, fontWeight: FontWeight.bold)),
            ],
          ]),
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

  // 💬 전체채팅 패널(입력 가능) — global_chat 재사용
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
            stream: FirebaseFirestore.instance
                .collection('global_chat')
                .where('timestamp', isGreaterThanOrEqualTo: chatSessionStart())
                .orderBy('timestamp', descending: true)
                .limit(30)
                .snapshots(),
            builder: (c, snap) {
              if (!snap.hasData) return const SizedBox.shrink();
              final docs = snap.data!.docs;
              return ListView.builder(
                reverse: true,
                itemCount: docs.length,
                itemBuilder: (c, i) {
                  final d = docs[i].data() as Map<String, dynamic>;
                  if ((d['type'] ?? 'global') == 'whisper') return const SizedBox.shrink();
                  final sender = (d['nickname'] ?? '조사님').toString();
                  final msg = (d['message'] ?? '').toString();
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: RichText(
                      text: TextSpan(children: [
                        const TextSpan(text: '전체> ', style: TextStyle(color: Color(0xFF7FB2FF), fontSize: 12, fontWeight: FontWeight.bold)),
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
