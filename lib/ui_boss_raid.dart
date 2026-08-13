// 🐋 [길드 보스 레이드] 전투 — 낚시 파이팅 구조 그대로.
//   흐름: (길드홀서 길드장 시작) → 자동장착 → 자동 캐스팅 → 대기 → 입질(전원 동시) → 챔질 → 당기기.
//
//   ▸ 일반 낚시와 다른 점
//     · 게이지가 가운데(0.5)가 아니라 '맨 왼쪽(보스)'에서 시작 → 길드원 전원이 당겨 '맨 오른쪽 끝'까지 밀면 승리.
//     · 게이지 마커 = 물고기 대신 피라루크(바다=백상아리).
//     · 발악·저항 = 뒤로 밀리지만 줄은 안 터짐(스냅 패배 없음). 실패는 오직 '시간초과(10분)'뿐.
//     · 협동: 길드원 개개인 제압력의 '합산'이 게이지를 오른쪽으로. 누가 안 당기면 합산 제압력이 내려감.
//
//   ▸ 동기화
//     · 진행도(게이지): RTDB raid_battle/{길드ID}/dmg 를 각자 ServerValue.increment(0.3초 배치) → 전원 같은 위치.
//     · 합산 제압력: raid_battle/{길드ID}/pull/{uid} 에 각자 현재 제압력 기록 → 합산 표시.
//     · 입질/발악: '공유 시각(startAt)' 시드로 계산 → 전원 완전 동일 타이밍(트래픽 0).
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'game_config.dart';   // rodSceneSuffix, skinTierByName, isSkinItem
import 'fishing_logic.dart'; // getMyTotalStats + audioManager

const Color _kGold = Color(0xFFD4AF37);

class BossRaidScreen extends StatefulWidget {
  final String guildId;
  final String guildName;
  final bool isSea;      // 민물=피라루크 / 바다=백상아리
  final String nickname;
  final int endAt;       // 공유 종료시각(ms)
  final int bossHp;      // 공유 필요 제압치(기본 400만)

  const BossRaidScreen({
    super.key,
    required this.guildId,
    required this.guildName,
    required this.nickname,
    required this.endAt,
    this.isSea = false,
    this.bossHp = 4000000,
  });

  @override
  State<BossRaidScreen> createState() => _BossRaidScreenState();
}

enum _Phase { loading, casting, waiting, biting, fighting, done }

class _BossRaidScreenState extends State<BossRaidScreen> with TickerProviderStateMixin {
  static final FirebaseDatabase _db = FirebaseDatabase.instanceFor(
    app: Firebase.app(),
    databaseURL: 'https://camnak-fishing-default-rtdb.asia-southeast1.firebasedatabase.app',
  );
  DatabaseReference get _battleRef => _db.ref('raid_battle/${widget.guildId}');
  final String _uid = FirebaseAuth.instance.currentUser?.uid ?? '';

  _Phase _phase = _Phase.loading;
  int _power = 0;            // 내 제압력(자동장착 결과 · testPower 오버라이드)
  String _rodSfx = 'kt40';   // 파이팅 낚싯대 그림 접미사
  String _gearMsg = '';

  // ⏱️ 공유 타이머(10분)
  int _remain = 600;
  int get _startAt => widget.endAt - 600000; // 시작시각(ms) — 입질/발악 시드
  Timer? _secTimer;

  // 💥 공유 진행도(게이지)
  double _dmgTotal = 0;    // 길드 전체 누적(0..targetHP)
  double _pendingDmg = 0;  // 로컬 미전송분
  StreamSubscription? _dmgSub;
  Timer? _flushTimer;

  // 💪 합산 제압력
  int _combinedPower = 0;
  StreamSubscription? _pullSub;
  Timer? _pullReportTimer;

  int get _targetHP => widget.bossHp;

  // 🎣 전투 상태
  Timer? _tick;
  bool _isPressing = false;   // 당기기 홀드
  bool _armed = false;        // 풀기 후 장전 → 다음 당기기서 제압단계 +1
  int _playerGear = 1;        // 내 제압단계(1~3)
  int _fishGear = 0;          // 보스 상태 0잔잔 / 1저항 / 2발악
  double _shake = 0;
  late AnimationController _rodCtrl;
  final _rng = math.Random();

  @override
  void initState() {
    super.initState();
    _rodCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 250))..repeat(reverse: true);
    HardwareKeyboard.instance.addHandler(_onKey);
    _subscribeDamage();
    _subscribePull();
    _startClock();
    _loadGearAndPower().then((_) => _autoCast()); // 자동장착 → 자동 캐스팅
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    _secTimer?.cancel();
    _tick?.cancel();
    _flushTimer?.cancel();
    _pullReportTimer?.cancel();
    _dmgSub?.cancel();
    _pullSub?.cancel();
    _flushDamage();
    _battleRef.child('pull/$_uid').remove().catchError((_) {}); // 내 제압력 기여 제거
    _rodCtrl.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────
  // 🎒 자동장착 — 낚시터 '자동장착'과 동일 규칙으로 최상급 장비 → 제압력
  // ─────────────────────────────────────────────────────────────
  Future<void> _loadGearAndPower() async {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) return;
    try {
      final d = (await FirebaseFirestore.instance.collection('users').doc(u.uid).get()).data() ?? {};
      final inv = (d['inventory'] as List?) ?? [];
      final int level = (d['level'] is num) ? (d['level'] as num).toInt() : 1;

      int rodTierFw(String n) { n = n.replaceAll(' ', '').replaceAll('-', '').toUpperCase();
        if (n.contains('KT40')) return 60; if (n.contains('KT30')) return 50; if (n.contains('KT20')) return 40;
        if (n.contains('CF40')) return 30; if (n.contains('CF30')) return 20; if (n.contains('CF20')) return 10; return 1; }
      int rodTierSea(String n) { n = n.replaceAll(' ', '').toUpperCase();
        if (n.contains('KT500')) return 60; if (n.contains('KT350')) return 50; if (n.contains('KT250')) return 40;
        if (n.contains('CF500')) return 30; if (n.contains('CF350')) return 20; if (n.contains('CF250')) return 10; return 1; }
      int floatTier(String n) { n = n.replaceAll(' ', '').toUpperCase();
        if (n.contains('KT전자')) return 60; if (n.contains('CF전자')) return 50; if (n.contains('나노')) return 40;
        if (n.contains('수제')) return 30; if (n.contains('오동')) return 20; return 1; }
      int reelTier(String n) { n = n.replaceAll(' ', '').toUpperCase();
        if (n.contains('KF8000')) return 80; if (n.contains('KF6000')) return 60; if (n.contains('KF5000')) return 50;
        if (n.contains('CF5000')) return 40; if (n.contains('CF3000')) return 30; return 1; }
      int coolerTier(String n) { if (n.contains('대형')) return 3; if (n.contains('중형')) return 2; return 1; }

      Map<String, dynamic>? skin, rod, float, reel, cooler, sunglasses, badge, net, belt, gloves, line;
      for (final raw in inv) {
        if (raw is! Map) continue;
        final item = Map<String, dynamic>.from(raw);
        final name = (item['name'] ?? '').toString();
        final cat = (item['category'] ?? '').toString().toUpperCase();
        if (widget.isSea && cat == 'FW') continue;
        if (!widget.isSea && cat == 'SEA') continue;

        if (isSkinItem(item)) {
          if (skin == null || skinTierByName(name) > skinTierByName((skin['name'] ?? '').toString())) skin = item;
        } else if (name.contains('찌')) {
          if (float == null || floatTier(name) > floatTier((float['name'] ?? '').toString())) float = item;
        } else if (item['type'] == 'COOLER' || name.contains('아이스박스') || name.contains('쿨러') || name.contains('보냉')) {
          if (cooler == null || coolerTier(name) > coolerTier((cooler['name'] ?? '').toString())) cooler = item;
        } else if (item['type'] == 'REEL' || name.contains('릴')) {
          if (reel == null || reelTier(name) > reelTier((reel['name'] ?? '').toString())) reel = item;
        } else if ((name.contains('대') || name.contains('CF') || name.contains('KT')) &&
            !name.contains('찌') && !name.contains('릴') && !name.contains('아이스박스') && !name.contains('쿨러') && !name.contains('보냉')) {
          final isSeaRod = name.contains('250') || name.contains('350') || name.contains('500');
          if (widget.isSea == isSeaRod) {
            final t = widget.isSea ? rodTierSea(name) : rodTierFw(name);
            final bt = rod == null ? -1 : (widget.isSea ? rodTierSea((rod['name'] ?? '').toString()) : rodTierFw((rod['name'] ?? '').toString()));
            if (t > bt) rod = item;
          }
        }
        else if (name.contains('선글라스')) sunglasses ??= item;
        else if (name.contains('휘장') || name.contains('뱃지')) {
          final p = (item['stats']?['P'] as num?)?.toInt() ?? 0;
          final bp = (badge?['stats']?['P'] as num?)?.toInt() ?? -1;
          if (badge == null || p > bp) badge = item;
        }
        else if (name.contains('뜰채')) net ??= item;
        else if (name.contains('벨트')) belt ??= item;
        else if (name.contains('장갑')) gloves ??= item;
        else if (name.contains('낚시줄')) line ??= item;
      }

      final s = FishingLogic.getMyTotalStats(
        equippedSkin: skin, equippedRod: rod, equippedFloat: float, equippedReel: reel,
        equippedSunglasses: sunglasses, equippedBadge: badge, equippedCooler: cooler,
        equippedNet: net, equippedBelt: belt, equippedGloves: gloves, equippedLine: line,
      );
      final lvBonus = ((level > 0 ? level : 1) - 1) * 3;
      int power = (s['strength'] ?? 0) + (s['control'] ?? 0) + (s['sensitivity'] ?? 0) + lvBonus;
      final tp = (d['testPower'] is num) ? (d['testPower'] as num).toInt() : 0;
      if (tp > 0) power = tp;

      String sfx = rod != null ? rodSceneSuffix(rod) : '';
      if (sfx.isEmpty) sfx = widget.isSea ? 'kt500' : 'kt40';

      if (!mounted) return;
      setState(() {
        _power = power;
        _rodSfx = sfx;
        _gearMsg = '${rod?['name'] ?? '기본 장비'} · ${skin?['name'] ?? '기본 스킨'}';
      });
    } catch (e) {
      debugPrint('🐋 자동장착 실패: $e');
      if (mounted) setState(() => _power = 300);
    }
  }

  // ─────────────────────────────────────────────────────────────
  // 💥 진행도(공유 게이지) 동기화
  // ─────────────────────────────────────────────────────────────
  void _subscribeDamage() {
    _dmgSub = _battleRef.child('dmg').onValue.listen((e) {
      final v = e.snapshot.value;
      final total = (v is num) ? v.toDouble() : 0.0;
      if (!mounted) return;
      setState(() => _dmgTotal = total.clamp(0, _targetHP.toDouble()));
      if (total >= _targetHP && _phase != _Phase.done) _finish(true);
    });
    _flushTimer = Timer.periodic(const Duration(milliseconds: 300), (_) => _flushDamage());
  }

  void _flushDamage() {
    if (_pendingDmg == 0) return;
    final send = _pendingDmg;
    _pendingDmg = 0;
    _battleRef.child('dmg').set(ServerValue.increment(send))
        .catchError((Object e) => debugPrint('🐋 dmg flush: $e'));
  }

  // 💪 합산 제압력 — 각자 현재 제압력 기록 + 전체 합산 구독
  void _subscribePull() {
    _pullSub = _battleRef.child('pull').onValue.listen((e) {
      final v = e.snapshot.value;
      int sum = 0;
      if (v is Map) {
        final now = DateTime.now().millisecondsSinceEpoch;
        v.forEach((_, pv) {
          if (pv is Map) {
            final t = (pv['t'] is num) ? (pv['t'] as num).toInt() : 0;
            final p = (pv['p'] is num) ? (pv['p'] as num).toInt() : 0;
            if (now - t < 3000) sum += p; // 3초 내 신선한 기여만
          }
        });
      }
      if (mounted) setState(() => _combinedPower = sum);
    });
    // 내 현재 제압력(당기는 중이면 _power, 아니면 0)을 0.4초마다 보고
    _pullReportTimer = Timer.periodic(const Duration(milliseconds: 400), (_) {
      if (_phase != _Phase.fighting) return;
      _battleRef.child('pull/$_uid').set({
        'p': _isPressing ? _power : 0,
        't': ServerValue.timestamp,
      }).catchError((_) {});
    });
  }

  void _startClock() {
    _syncRemain();
    _secTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _syncRemain();
      if (_remain <= 0 && _phase != _Phase.done) _finish(false);
      // 🎣 공유 시각 기준 입질 — 시작 25초 뒤 전원 동시(캐스팅 끝난 뒤)
      final elapsed = 600 - _remain;
      if (_phase == _Phase.waiting && elapsed >= 25) {
        setState(() => _phase = _Phase.biting);
        audioManager.playSfx('sfx_hit.mp3');
      }
    });
  }

  void _syncRemain() {
    final left = ((widget.endAt - DateTime.now().millisecondsSinceEpoch) / 1000).floor();
    if (mounted) setState(() => _remain = left.clamp(0, 600));
  }

  // ─────────────────────────────────────────────────────────────
  // 🎣 자동 캐스팅 → 입질 대기
  // ─────────────────────────────────────────────────────────────
  void _autoCast() {
    if (!mounted) return;
    setState(() => _phase = _Phase.casting);
    audioManager.playSfx('sfx_casting.mp3');
    Future.delayed(const Duration(milliseconds: 1600), () {
      if (mounted && _phase == _Phase.casting) setState(() => _phase = _Phase.waiting);
    });
  }

  // ✊ 챔질 → 전투 시작
  void _strike() {
    if (_phase != _Phase.biting) return;
    setState(() => _phase = _Phase.fighting);
    audioManager.playSfx('sfx_landing_success.mp3');
    _isPressing = false; _armed = false; _playerGear = 1;
    _tick = Timer.periodic(const Duration(milliseconds: 50), (t) => _onTick(t));
  }

  // ─────────────────────────────────────────────────────────────
  // ⚔️ 전투 틱 — 내 net 기여를 공유 진행도에 누적(스냅 패배 없음)
  // ─────────────────────────────────────────────────────────────
  void _onTick(Timer t) {
    if (!mounted || _phase != _Phase.fighting) { t.cancel(); return; }
    _updateBossGear(); // 공유 시드 발악/저항

    final base = _power * 0.05; // 틱당 ≈ _power/초
    double delta;
    if (_fishGear == 0) {
      // 잔잔: 당기면 전진, 안 당기면 보스가 살짝 되돌림('안 당기면 내려감')
      delta = _isPressing ? base : -base * 0.05;
    } else {
      // 발악(2)/저항(1): 제압단계 맞춰야 전진, 아니면 밀림(단, 절대 안 터짐)
      final tgt = _fishGear == 2 ? 3 : 2;
      if (_isPressing && _playerGear >= tgt) {
        delta = base * (_fishGear == 2 ? 1.4 : 1.2); // 받아치면 강하게 전진
      } else if (_isPressing) {
        delta = -base * (_fishGear == 2 ? 0.8 : 0.5); // 단계 못 맞추고 당기면 밀림
      } else {
        delta = -base * 0.1; // 놓으면 살짝 밀림
      }
    }
    _pendingDmg += delta;
    // 밀려도 0 밑으로는 안 감(스냅/패배 없음)
    if (_dmgTotal + _pendingDmg < 0) _pendingDmg = -_dmgTotal;

    setState(() {});
  }

  // 🐟 발악/저항 — startAt 시드로 전원 동일 타이밍. 8초 주기: 0~5초 잔잔 / 5~8초 저항 or 발악.
  void _updateBossGear() {
    final elapsedMs = DateTime.now().millisecondsSinceEpoch - _startAt;
    const cycle = 8000;
    final phase = elapsedMs % cycle;
    final cycleNo = elapsedMs ~/ cycle;
    int gear = 0;
    if (elapsedMs > 3000 && phase >= 5000) {
      gear = (math.Random(_startAt + cycleNo).nextInt(100) < 45) ? 2 : 1;
    }
    if (gear != _fishGear) {
      if (gear > 0) {
        _playerGear = 1; _armed = false; _isPressing = false; // 발악 시작 = 단계 리셋, 다시 받아쳐야
        audioManager.playSfx(gear == 2 ? 'sfx_break.mp3' : 'sfx_hit.mp3');
      }
      _fishGear = gear;
    }
    _shake = _fishGear == 2 ? (_rng.nextDouble() - 0.5) * 12 : (_fishGear == 1 ? (_rng.nextDouble() - 0.5) * 5 : 0);
  }

  // 🕹️ 당기기(홀드) / 풀기(장전)
  void _pressPull(bool down) {
    if (_phase != _Phase.fighting) return;
    if (down) {
      if (_armed) { _playerGear = (_playerGear + 1).clamp(1, 3); _armed = false; }
      _isPressing = true;
    } else {
      _isPressing = false;
    }
    setState(() {});
  }

  void _tapRelease() {
    if (_phase != _Phase.fighting) return;
    _isPressing = false;
    _armed = true; // 풀었다 → 다음 당기기서 단계 +1
    setState(() {});
  }

  bool _onKey(KeyEvent e) {
    if (_phase == _Phase.biting && e is KeyDownEvent &&
        (e.logicalKey == LogicalKeyboardKey.keyD || e.logicalKey == LogicalKeyboardKey.space)) {
      _strike(); return true;
    }
    if (_phase != _Phase.fighting) return false;
    if (e.logicalKey == LogicalKeyboardKey.keyD) {
      if (e is KeyDownEvent) _pressPull(true);
      if (e is KeyUpEvent) _pressPull(false);
      return true;
    }
    if (e.logicalKey == LogicalKeyboardKey.keyA && e is KeyDownEvent) { _tapRelease(); return true; }
    return false;
  }

  // ─────────────────────────────────────────────────────────────
  // 🏁 종료 (보상 지급은 다음 단계)
  // ─────────────────────────────────────────────────────────────
  void _finish(bool win) {
    if (_phase == _Phase.done) return;
    setState(() => _phase = _Phase.done);
    _tick?.cancel(); _secTimer?.cancel();
    _flushDamage();
    Future.delayed(const Duration(milliseconds: 300), () { if (mounted) _showResult(win); });
  }

  void _showResult(bool win) {
    final bossName = widget.isSea ? '백상아리 8m' : '피라루크 4.5m';
    showDialog(
      context: context, barrierDismissible: false,
      builder: (c) => AlertDialog(
        backgroundColor: const Color(0xFF14110C),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18),
            side: BorderSide(color: win ? _kGold : Colors.white24, width: 2)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(win ? '🎉 레이드 성공!' : '⏱️ 레이드 실패',
              style: TextStyle(color: win ? _kGold : Colors.orangeAccent, fontSize: 26, fontWeight: FontWeight.w900)),
          const SizedBox(height: 14),
          if (win) ...[
            Image.asset(widget.isSea ? 'assets/fish_sea/fish_sea_boss_shark.png' : 'assets/fish_fw/fish_fw_boss_pirarucu.png',
                height: 140, fit: BoxFit.contain,
                errorBuilder: (a, b, c2) => const Icon(Icons.set_meal, color: Colors.white24, size: 100)),
            const SizedBox(height: 10),
            Text(bossName, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            const Text('보상 지급은 준비 중이에요 (다음 업데이트)', style: TextStyle(color: Colors.white54, fontSize: 12)),
          ] else ...[
            const Text('🏊', style: TextStyle(fontSize: 56)),
            const SizedBox(height: 8),
            Text('제압 ${(_dmgTotal / _targetHP * 100).toStringAsFixed(1)}% 까지 갔어요!\n길드원을 더 모으거나 장비를 올려 재도전!',
                textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70, fontSize: 15, height: 1.5)),
          ],
        ]),
        actions: [Center(child: ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: _kGold, foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 14)),
          onPressed: () { Navigator.pop(c); Navigator.pop(context); },
          child: const Text('모임터로', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
        ))],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final progress = (_dmgTotal / _targetHP).clamp(0.0, 1.0);
    final mm = (_remain ~/ 60).toString().padLeft(2, '0');
    final ss = (_remain % 60).toString().padLeft(2, '0');
    final bossImg = widget.isSea ? 'assets/fish_sea/fish_sea_boss_shark.png' : 'assets/fish_fw/fish_fw_boss_pirarucu.png';

    return Scaffold(
      body: Stack(fit: StackFit.expand, children: [
        // 배경
        Image.asset(widget.isSea ? 'assets/fields/bg_guild_sea.jpg' : 'assets/fields/bg_guild_fw.jpg',
            fit: BoxFit.cover, errorBuilder: (a, b, c) => Container(color: const Color(0xFF0B2A2E))),
        Container(color: Colors.black.withOpacity(0.12)),

        // (배경 보스 이미지 제거 — 물만. 나중에 이펙트/보스 연출 추가 예정)

        // 상단: 타이틀 + 타이머 + 나가기
        Positioned(top: 12, left: 14, right: 14, child: Row(children: [
          Expanded(child: Text('🐋 ${widget.isSea ? '백상아리' : '피라루크'}  [${widget.guildName}]',
              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900,
                  shadows: [Shadow(color: Colors.black, blurRadius: 6)]))),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(color: Colors.black.withOpacity(0.55), borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _remain <= 60 ? Colors.redAccent : _kGold)),
            child: Text('⏱️ $mm:$ss', style: TextStyle(color: _remain <= 60 ? Colors.redAccent : Colors.white,
                fontSize: 17, fontWeight: FontWeight.w900)),
          ),
          const SizedBox(width: 8),
          IconButton(icon: const Icon(Icons.close, color: Colors.white60, size: 24),
              onPressed: () => Navigator.pop(context)),
        ])),

        // 💪 합산 제압력 + 제압률 (상단 아래)
        Positioned(top: 52, left: 0, right: 0, child: Center(child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          decoration: BoxDecoration(color: Colors.black.withOpacity(0.5), borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _kGold.withOpacity(0.6))),
          child: Text('💪 합산 제압력 $_combinedPower/초   ·   제압 ${(progress * 100).toStringAsFixed(1)}%',
              style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w900,
                  shadows: [Shadow(color: Colors.black, blurRadius: 4)])))),
        ),

        // ⚠️ 발악/저항 경고 (전투 중)
        if (_phase == _Phase.fighting && _fishGear > 0)
          Positioned(top: 150, left: 0, right: 0, child: Center(child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
            decoration: BoxDecoration(color: Colors.black.withOpacity(0.5), borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _fishGear == 2 ? Colors.redAccent : Colors.orangeAccent, width: 2)),
            child: Text(_fishGear == 2 ? '💥 보스 발악! 풀었다 당겨서 3단!' : '💢 보스 저항! 풀었다 당겨서 2단!',
                style: TextStyle(color: _fishGear == 2 ? Colors.redAccent : Colors.orangeAccent,
                    fontSize: 22, fontWeight: FontWeight.w900)),
          ))),

        // 🎣 낚싯대 (전투 중, 당길 때 휨)
        if (_phase == _Phase.fighting || _phase == _Phase.casting || _phase == _Phase.waiting || _phase == _Phase.biting)
          Positioned(right: -28, bottom: 120, child: Transform.rotate(
            angle: (_isPressing && _fishGear == 0 ? -0.30 : -0.12) + _shake * 0.010,
            alignment: Alignment.bottomRight,
            child: Image.asset('assets/images/hand_rod_${widget.isSea ? 'sea' : 'fw'}_$_rodSfx.png',
                height: 300, fit: BoxFit.contain,
                errorBuilder: (a, b, c) => Image.asset('assets/images/hand_rod_${widget.isSea ? 'sea' : 'fw'}.png',
                    height: 300, fit: BoxFit.contain, errorBuilder: (a2, b2, c2) => const SizedBox.shrink())),
          )),

        // ── 하단 컨트롤/게이지 (단계별) ── 전체화면 레이어로(버튼 히트테스트 보장)
        Positioned.fill(child: _bottomLayer(progress, bossImg)),
      ]),
    );
  }

  Widget _bottomLayer(double progress, String bossImg) {
    switch (_phase) {
      case _Phase.loading:
        return const Center(child: Text('🎒 자동장착 중...', style: TextStyle(color: Colors.white70, fontSize: 18, fontWeight: FontWeight.w900)));
      case _Phase.casting:
        return Align(alignment: Alignment.bottomCenter, child: Padding(padding: const EdgeInsets.only(bottom: 40), child: _panel([
          Text('🎒 자동장착 완료 — $_gearMsg', style: const TextStyle(color: Color(0xFF7FFFB0), fontSize: 13, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          const Text('🎣 캐스팅...', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900)),
        ])));
      case _Phase.waiting:
        return Align(alignment: Alignment.bottomCenter, child: Padding(padding: const EdgeInsets.only(bottom: 40), child: _panel([
          const Text('🌊 입질을 기다리는 중...', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          const Text('곧 길드원 전원에게 동시에 입질이 와요!', style: TextStyle(color: Colors.white60, fontSize: 12)),
        ])));
      case _Phase.biting:
        // 화면 아무 데나 탭하면 챔질 (버튼 위치 무관 · 확실한 히트테스트)
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _strike,
          child: Stack(children: [
            const Positioned(top: 230, left: 0, right: 0, child: Center(child: Text('입질 !!',
                style: TextStyle(color: Colors.redAccent, fontSize: 90, fontWeight: FontWeight.w900, fontStyle: FontStyle.italic,
                    shadows: [Shadow(color: Colors.black, blurRadius: 16, offset: Offset(4, 4))])))),
            Positioned(right: 30, top: 130, child: Container(width: 118, height: 118,
              decoration: const BoxDecoration(color: Colors.redAccent, shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: Colors.black45, blurRadius: 8)]),
              child: const Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.catching_pokemon, size: 40, color: Colors.white),
                Text('챔질!', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900)),
              ]))),
            const Positioned(bottom: 60, left: 0, right: 0, child: Center(child: Text('화면을 탭해 챔질!',
                style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w900,
                    shadows: [Shadow(color: Colors.black, blurRadius: 6)])))),
          ]),
        );
      case _Phase.fighting:
        return _fightGauge(progress, bossImg);
      case _Phase.done:
        return const SizedBox.shrink();
    }
  }

  Widget _panel(List<Widget> children) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
        decoration: BoxDecoration(color: Colors.black.withOpacity(0.55), borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _kGold.withOpacity(0.6))),
        child: Column(mainAxisSize: MainAxisSize.min, children: children),
      );

  // 🎣 낚시식 좌우 게이지 (마커=피라루크) + 당기기/풀기
  Widget _fightGauge(double progress, String bossImg) {
    return Stack(children: [
      // 좌우 게이지 바 (왼=보스, 오른쪽 끝=승리) — 화면 하단
      Positioned(left: 20, right: 20, bottom: 150, child: SizedBox(height: 64, child: LayoutBuilder(
        builder: (context, box) {
          final w = box.maxWidth;
          const markerW = 56.0;
          final x = (progress * (w - markerW)).clamp(0.0, w - markerW);
          return Stack(clipBehavior: Clip.none, children: [
            // 바탕 (좌 붉음 → 우 푸름)
            Positioned(top: 26, left: 0, right: 0, child: Container(height: 14,
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(7),
                gradient: const LinearGradient(colors: [Color(0xFFE05555), Color(0xFF7FA8FF)])))),
            // 채워진 진행(왼→현재)
            Positioned(top: 26, left: 0, child: Container(height: 14, width: x + markerW / 2,
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(7),
                gradient: const LinearGradient(colors: [Color(0xFF7B2FF7), Color(0xFFFF4FD8)])))),
            // 오른쪽 끝 '승리선'
            Positioned(top: 18, right: 0, child: Column(children: const [
              Text('🏁', style: TextStyle(fontSize: 16)),
            ])),
            // 🐟 피라루크 마커
            Positioned(left: x, top: 0, child: Transform.translate(offset: Offset(0, _shake * 0.3),
              child: Image.asset(bossImg, width: markerW, height: 56, fit: BoxFit.contain,
                  errorBuilder: (a, b, c) => const Icon(Icons.set_meal, color: Colors.white, size: 44)))),
          ]);
        },
      ))),
      // 안내
      Positioned(left: 0, right: 0, bottom: 128, child: Center(child: Text(
        _fishGear == 2 && _isPressing && _playerGear >= 3 ? '🔥 3단 최대제압!' :
        (_fishGear > 0 ? '◀ 풀기 → 당기기 반복!  (제압 $_playerGear단)' : '💪 당겨서 오른쪽 끝까지!'),
        style: TextStyle(color: _fishGear > 0 ? Colors.orangeAccent : Colors.white70,
            fontSize: 13, fontWeight: FontWeight.w900, shadows: const [Shadow(color: Colors.black, blurRadius: 4)]),
      ))),
      // 풀기(발악 때만 강조) + 당기기 버튼 (우하단)
      Positioned(right: 24, bottom: 30, child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        // 풀기
        GestureDetector(
          onTap: _tapRelease,
          child: Container(width: 92, height: 56, margin: const EdgeInsets.only(right: 12),
            decoration: BoxDecoration(
              color: _armed ? Colors.white24 : Colors.black.withOpacity(0.5),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _fishGear > 0 ? Colors.orangeAccent : Colors.white38, width: 2)),
            child: Center(child: Text('◀ 풀기',
                style: TextStyle(color: _fishGear > 0 ? Colors.orangeAccent : Colors.white70, fontSize: 16, fontWeight: FontWeight.w900))),
          ),
        ),
        // 당기기 (홀드)
        GestureDetector(
          onTapDown: (_) => _pressPull(true),
          onTapUp: (_) => _pressPull(false),
          onTapCancel: () => _pressPull(false),
          child: Container(width: 120, height: 88,
            decoration: BoxDecoration(
              color: _isPressing ? _kGold : Colors.black.withOpacity(0.55),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: _isPressing ? Colors.white : _kGold, width: 2.5)),
            child: Center(child: Text(_isPressing ? '💪\n당기는중' : '당기기 ▶',
                textAlign: TextAlign.center,
                style: TextStyle(color: _isPressing ? Colors.black : Colors.white, fontSize: 20, fontWeight: FontWeight.w900))),
          ),
        ),
      ])),
      const Positioned(left: 0, right: 0, bottom: 8, child: Center(child: Text('PC: D키 당기기 · A키 풀기',
          style: TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.bold)))),
    ]);
  }
}
