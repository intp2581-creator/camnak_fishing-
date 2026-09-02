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
import 'dart:html' as html; // 전체화면 토글(웹 전용)
import 'game_config.dart';   // rodSceneSuffix, skinTierByName, isSkinItem
import 'sound_settings.dart'; // showSoundSettingsDialog
import 'ui_guild.dart';       // showGuildInfoDialog
import 'ui_fishing.dart';     // RankingTicker(흐르는 자막)
import 'fishing_logic.dart'; // getMyTotalStats + audioManager
import 'screenshot.dart';   // 📸 세러모니 기념샷(JPG 저장)

const Color _kGold = Color(0xFFD4AF37);

// 🎣 [레이드 낚싯대 화면 배치 튜닝] 숫자만 바꾸면 위치/크기 조정됨.
//   레이드대 이미지는 캐스팅/웨이팅/파이팅 포즈가 그려져 있어 회전 없이 우하단에 얹는다.
const double kRaidRodRight = 560;  // 오른쪽에서 띄울 거리(클수록 왼쪽으로 이동)
const double kRaidRodBottom = -34; // 아래에서 띄울 거리(작을수록/음수일수록 아래로 내려감)
const double kRaidRodHeight = 420; // 낚싯대 그림 높이(px)

// 🐲 [보스 등장 3단계 튜닝] 제압률에 따라 멀리→중간→가까이. 숫자만 바꾸면 구간별로 따로 조절됨.
//   waterY  : 수면선(화면 높이 비율 0~1). 클수록 아래(=앞쪽 물).
//   scale   : 보스 크기 배율.  opacity : 선명도 배율.  tint : 물빛(멀수록 짙게).
//   spread  : 좌우로 흩어지는 정도(멀수록 화면 중앙에 모임).
const double kZoneMidAt  = 0.35; // 이 제압률부터 '중간'
const double kZoneNearAt = 0.70; // 이 제압률부터 '가까이'

const double kFarWaterY = 0.66, kFarScale = 0.55, kFarOpacity = 0.55, kFarTint = 0.34, kFarSpread = 0.40;
const double kMidWaterY = 0.74, kMidScale = 0.85, kMidOpacity = 0.80, kMidTint = 0.18, kMidSpread = 0.70;
const double kNearWaterY = 0.82, kNearScale = 1.25, kNearOpacity = 1.00, kNearTint = 0.00, kNearSpread = 1.00;

// 🐟 [발악/저항 튜닝] 전원 동일 타이밍(공유 시계 기반)이라 주기로 제어.
//   일반 낚시 실측: 지속 2.5~4.5초(평균 3.5) + 쿨 0.75~1.75초 → 약 70%가 발악/저항 상태.
//   여기서도 같은 비율(3.5/5.0 = 70%)로 맞춤.
const int kGearCycleMs = 5000;   // 발악/저항 주기
const int kGearActiveMs = 3000;  // 한 번 뜰 때 지속시간 (= 주기의 60%, 살짝 완화)

class BossRaidScreen extends StatefulWidget {
  final String guildId;
  final String guildName;
  final bool isSea;      // (레거시) 민물/바다 폴백 이미지 구분용. 레이드는 boss config 우선.
  final String nickname;
  final int endAt;       // 공유 종료시각(ms)
  final int bossHp;      // 공유 필요 제압치(boss config hp)
  // 🐲 보스 config(로스터에서 선택된 존)
  final String bossId;   // 'murgadon' 등 · 진행/클리어 기록 키
  final String bossName; // '태고의 무르가돈'
  final String bossZone; // '신성한 늪'
  final String bossMarker; // 게이지 마커 + 결과 이미지 경로
  final String bossBg;   // 존 배경 경로
  final int bossTier;    // 1~5 (건틀릿 진행)
  final bool isLeader;   // 길드장/부길드장 = 체인 진행(다음 보스 문서 갱신) 권한
  final String bossBgm;  // 🎵 존 전용 BGM 파일명(assets/sound/). 없으면 기존 BGM 유지.
  // 🌊 존별 수면선 [멀리, 중간, 가까이] — 배경 그림마다 물 높이가 달라 보스 등장 위치를 따로 잡는다.
  final List<double> bossWater;

  const BossRaidScreen({
    super.key,
    required this.guildId,
    required this.guildName,
    required this.nickname,
    required this.endAt,
    this.isSea = false,
    this.bossHp = 4000000,
    this.bossId = 'murgadon',
    this.bossName = '태고의 무르가돈',
    this.bossZone = '신성한 늪',
    this.bossMarker = 'assets/images/boss_murgadon.png',
    this.bossBg = 'assets/fields/bg_raid_murgadon.jpg',
    this.bossTier = 1,
    this.isLeader = false,
    this.bossBgm = '',
    this.bossWater = const [kFarWaterY, kMidWaterY, kNearWaterY],
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
  DocumentReference<Map<String, dynamic>> get _roomRef =>
      FirebaseFirestore.instance.collection('raids').doc(widget.guildId);
  StreamSubscription? _roomSub;   // 🐲 건틀릿 체인: 방 문서 감시(다음 보스/종료)
  bool _chaining = false;         // 다음 존 전환 중(전환 배너 + 중복 팝 방지)
  final String _uid = FirebaseAuth.instance.currentUser?.uid ?? '';

  _Phase _phase = _Phase.loading;
  int _power = 0;            // 내 제압력(자동장착 결과 · testPower 오버라이드)
  String _rodSfx = 'kt40';   // 파이팅 낚싯대 그림 접미사(레이드대 없을 때 폴백)
  int _raidTier = 0;         // 장착한 레이드대 티어(1~3). >0이면 raid 이미지 사용
  String _gearMsg = '';

  // ⏱️ 공유 타이머(10분)
  int _remain = 600;
  int get _startAt => widget.endAt - 600000; // 시작시각(ms) — 입질/발악 시드 (10분 기준)
  Timer? _secTimer;

  // 💥 공유 진행도(게이지)
  double _dmgTotal = 0;    // 길드 전체 누적(0..targetHP)
  double _pendingDmg = 0;  // 로컬 미전송분
  StreamSubscription? _dmgSub;
  Timer? _flushTimer;

  // 💪 합산 제압력: 다른 사람 몫만 RTDB에서(_othersPower), 내 몫은 로컬(_isPressing ? _power : 0)
  int _othersPower = 0;
  int get _combinedPower => (_isPressing ? _power : 0) + _othersPower;
  StreamSubscription? _pullSub;
  Timer? _pullReportTimer;

  int get _targetHP => widget.bossHp;

  // 🎣 전투 상태
  Timer? _tick;
  bool _isPressing = false;   // 당기기 홀드
  bool _armed = false;        // 풀기 후 장전 → 다음 당기기서 제압단계 +1
  final ValueNotifier<double> _knob = ValueNotifier<double>(-1.0); // 🎣 당기기 노브 위치(-1 풀기 ~ 1 당김) — 일반낚시식
  int _playerGear = 1;        // 내 제압단계(1~3)
  int _fishGear = 0;          // 보스 상태 0잔잔 / 1저항 / 2발악
  double _shake = 0;
  DateTime? _lastSplash;      // 🔊 물 첨벙 소리 스로틀
  Timer? _flingTimer;         // 🎣 발악 3단용 — 목표 단계 못 채우면 한 번 더 챔
  String _prevBgm = '';       // 🎵 보스전 진입 전 BGM(나갈 때 복귀)
  // 🎉 레이드 성공 세러모니(전체화면 · 스샷 타임 — 버튼 누를 때까지 유지)
  bool _ceremony = false;
  bool _cerCleared = false;
  Map<String, dynamic>? _cerNext;
  // 🧾 좌측 정보창(일반 낚시터 HUD와 동일)
  int _level = 1, _statP = 0, _statC = 0, _statS = 0, _exp = 0, _gold = 0;
  late AnimationController _rodCtrl;
  final _rng = math.Random();
  final GlobalKey _shotKey = GlobalKey(); // 📸 세러모니 기념샷 캡처 범위
  int _repaintTick = 0;       // 🖼️ 전투 중 리페인트 솎아내기(렉 방지)
  // 🐲 [보스 등장 연출] 전투 중 물 위로 어렴풋이 떠올랐다 사라짐 / 머리만 슬쩍 / 발악 땐 바늘털이
  late AnimationController _surfaceCtrl;
  Timer? _surfaceTimer;
  int _surfaceType = 0;       // 0 어렴풋이 · 1 머리만 · 2 바늘털이(발악)
  double _surfaceX = 0;       // -0.7 ~ 0.7 (화면 가로 위치)
  bool _surfaceFlip = false;  // 좌우 반전(같은 포즈만 반복되지 않게)
  double _surfaceTilt = 0;    // 몸 기울기
  double _surfaceScale = 1.0; // 등장 크기
  double _surfaceCut = 0.5;   // 수면 위로 드러나는 비율(나머지는 물속)
  int _surfaceZone = 0;       // 0 멀리 · 1 중간 · 2 가까이 (제압률로 결정)
  double _surfaceWaterY = kFarWaterY, _surfaceDistScale = kFarScale;
  double _surfaceDistOp = kFarOpacity, _surfaceTint = kFarTint, _surfaceSpread = kFarSpread;

  @override
  void initState() {
    super.initState();
    _rodCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 250))..repeat(reverse: true);
    _surfaceCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 2600));
    HardwareKeyboard.instance.addHandler(_onKey);
    _subscribeDamage();
    _subscribePull();
    _watchRoomChain();
    _startClock();
    _startBossBgm();
    _loadGearAndPower().then((_) => _autoCast()); // 자동장착 → 자동 캐스팅
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    _secTimer?.cancel();
    _tick?.cancel();
    _flushTimer?.cancel();
    _pullReportTimer?.cancel();
    _flingTimer?.cancel();
    _dmgSub?.cancel();
    _pullSub?.cancel();
    _roomSub?.cancel();
    _flushDamage();
    _battleRef.child('pull/$_uid').remove().catchError((_) {}); // 내 제압력 기여 제거
    // 🎵 BGM 복귀 — 다음 존으로 체인 중이면 그대로 두고(다음 화면이 자기 BGM 재생), 레이드 종료 시에만 복귀
    if (!_chaining && widget.bossBgm.isNotEmpty && _prevBgm.isNotEmpty) {
      audioManager.playBgm(_prevBgm);
    }
    _surfaceTimer?.cancel();
    _surfaceCtrl.dispose();
    _rodCtrl.dispose();
    _knob.dispose();
    super.dispose();
  }

  // 🎵 존 전용 BGM 시작(파일 없으면 기존 BGM 유지). 나갈 때 _prevBgm으로 복귀.
  //   ⚠️ 재생 실패(에셋 미포함 등) 시 currentBgm이 보스곡으로 남아 이후 복귀가 꼬이므로 되돌린다.
  Future<void> _startBossBgm() async {
    if (widget.bossBgm.isEmpty) return;
    _prevBgm = audioManager.currentBgm;
    try {
      // 🔊 보스전은 연출상 배경음을 켠다(유저가 꺼놨어도). 시끄러우면 우측 상단 ⚙️에서 끄면 됨(안내 없음).
      if (!audioManager.bgmOn) {
        audioManager.currentBgm = ''; // 광장곡이 잠깐 되살아나지 않게 비우고 켬
        await audioManager.setBgmOn(true);
      }
      await audioManager.playBgm(widget.bossBgm);
    } catch (e) {
      // 아직 안 만든 존 BGM이면 정상 상황(기존 BGM 유지). 방금 넣은 파일이면 flutter run 재시작 필요.
      debugPrint('🎵 보스 BGM 없음/재생 실패(${widget.bossBgm}) — 파일 미제작이면 무시, 방금 추가했다면 flutter run 재시작. ($e)');
      audioManager.currentBgm = _prevBgm; // 상태 원복(안 그러면 복귀 BGM이 안 걸림)
      _prevBgm = '';
    }
  }

  // ─────────────────────────────────────────────────────────────
  // 🎒 자동장착 — 낚시터 '자동장착'과 동일 규칙으로 최상급 장비 → 제압력
  // ─────────────────────────────────────────────────────────────
  Future<void> _loadGearAndPower() async {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) return;
    try {
      final d = (await FirebaseFirestore.instance.collection('users').doc(u.uid).get()).data() ?? {};
      // 🛡️ 길드레벨 + 길드리그랭킹 + 개인랭킹(가람) 보너스 합산 — 일반 낚시와 동일하게 제압력에 반영
      int statBonus = 0;
      try {
        if (widget.guildId.isNotEmpty) {
          final gdoc = await FirebaseFirestore.instance.collection('guilds').doc(widget.guildId).get();
          final gexp = (gdoc.data()?['guildExp'] is num) ? (gdoc.data()!['guildExp'] as num).toInt() : 0;
          statBonus += FishingLogic.guildStatBonus(FishingLogic.guildLevelFromExp(gexp)); // 길드 레벨
          final gBossCnt = (gdoc.data()?['clearedBosses'] is List) ? (gdoc.data()!['clearedBosses'] as List).length : 0;
          statBonus += FishingLogic.guildBossBonus(gBossCnt); // 🏴 보스 처치 깃발 보너스(마리당 +5, 최대 +25)
          final st = await FirebaseFirestore.instance.collection('guild_league').doc('state').get();
          final active = (st.data()?['activeWeek'] ?? '') == FishingLogic.weekKey(DateTime.now());
          final lr = st.data()?['leagueRanks'];
          if (active && lr is Map && lr[widget.guildId] is num) {
            statBonus += FishingLogic.guildLeagueBonus((lr[widget.guildId] as num).toInt()); // 주간 길드 리그 순위
          }
        }
        final gr = await FirebaseFirestore.instance.collection('garam_rank').doc('state').get();
        final ranks = gr.data()?['ranks'];
        if (ranks is Map && ranks[u.uid] is Map && ranks[u.uid]['rank'] is num) {
          statBonus += garamRankBonus((ranks[u.uid]['rank'] as num).toInt()); // 개인 주간 랭킹
        }
      } catch (_) {}
      // 🐲 제압력/장비 판정은 모임터(레이드 셋팅)와 공용 — fishing_logic.resolveRaidGearPower
      final g = resolveRaidGearPower(d, isSea: widget.isSea, statBonus: statBonus);
      if (!mounted) return;
      setState(() {
        _power = (g['power'] as num).toInt();
        _rodSfx = g['rodSfx'] as String;
        _raidTier = (g['raidTier'] as num).toInt();
        _gearMsg = '${g['rodName']} · ${g['skinName']}';
        // 🧾 좌측 정보창(일반 낚시터와 동일)
        _level = (g['level'] as num).toInt();
        _statP = (g['p'] as num).toInt();
        _statC = (g['c'] as num).toInt();
        _statS = (g['s'] as num).toInt();
        _exp = (d['exp'] is num) ? (d['exp'] as num).toInt() : 0;
        _gold = (d['gold'] is num) ? (d['gold'] as num).toInt() : 0;
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

  // 💪 합산 제압력 — '다른 사람' 값만 RTDB에서 합산. 내 값은 로컬(_isPressing ? _power : 0) 즉시 반영.
  //    이유: RTDB 왕복+400ms 보고 주기 때문에 눌렀는데 표시 0/초 그대로거나, 놨는데 30000 남는 딜레이 있었음.
  void _subscribePull() {
    _pullSub = _battleRef.child('pull').onValue.listen((e) {
      final v = e.snapshot.value;
      int sum = 0;
      if (v is Map) {
        final now = DateTime.now().millisecondsSinceEpoch;
        v.forEach((k, pv) {
          if (k.toString() == _uid) return; // 🙋 내 몫은 로컬로 계산하므로 제외
          if (pv is Map) {
            final t = (pv['t'] is num) ? (pv['t'] as num).toInt() : 0;
            final p = (pv['p'] is num) ? (pv['p'] as num).toInt() : 0;
            if (now - t < 3000) sum += p; // 3초 내 신선한 기여만
          }
        });
      }
      if (mounted) setState(() => _othersPower = sum);
    });
    // 내 현재 제압력(당기는 중이면 _power, 아니면 0)을 0.4초마다 보고 — 다른 사람 화면에 표시용
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
      // 🎣 공유 시각 기준 입질 — 시작 10초 뒤 전원 동시(캐스팅 끝난 뒤)
      final elapsed = 600 - _remain;
      if (_phase == _Phase.waiting && elapsed >= 10) {
        setState(() => _phase = _Phase.biting);
        HapticFeedback.lightImpact(); // 🎣 일반 낚시와 동일 — 입질은 소리 없이 진동으로
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
    // 🎣 입질 전에 채면 '헛챔질'(일반 낚시와 동일) — 버튼은 처음부터 살아있고 안내만 뜬다.
    if (_phase == _Phase.casting || _phase == _Phase.waiting) {
      audioManager.playSfx('sfx_click.mp3');
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(
            content: Text('헛챔질! 입질이 올 때 채세요 🎣'),
            backgroundColor: Colors.black87,
            duration: Duration(milliseconds: 1200),
          ));
      }
      return;
    }
    if (_phase != _Phase.biting) return;
    setState(() => _phase = _Phase.fighting);
    // 🎣 일반 낚시와 동일한 챔질 사운드(sfx_hit) — 축하음(sfx_landing_success)은 성공 연출용이라 제외
    audioManager.playSfx('sfx_hit.mp3');
    HapticFeedback.heavyImpact();
    _isPressing = false; _armed = false; _playerGear = 1;
    _tick = Timer.periodic(const Duration(milliseconds: 50), (t) => _onTick(t));
    _scheduleSurface(); // 🐲 보스가 중간중간 물 위로 모습을 드러냄
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
    // 🔇 당기는 중 물 첨벙 소리 제거(2026-08-16) — 보스별 BGM(물소리+괴성 믹싱)에 무게감을 실었는데
    //    첨벙이 겹쳐 가벼워짐. 보스전은 BGM+진동으로 몰입, 일반 낚시터만 첨벙 유지.

    _pendingDmg += delta;
    // 밀려도 0 밑으로는 안 감(스냅/패배 없음)
    if (_dmgTotal + _pendingDmg < 0) _pendingDmg = -_dmgTotal;

    // 🖼️ 다시 그리기는 2틱(100ms)마다 — 데미지 계산은 50ms 그대로라 DPS 손실 없음.
    //    (매 틱 전체 리페인트가 프레임을 잡아먹어 타이머가 밀리던 문제 완화)
    _repaintTick = (_repaintTick + 1) % 2;
    if (_repaintTick == 0) setState(() {});
  }

  // 🐟 발악/저항 — startAt 시드로 전원 동일 타이밍(멀티 동기화).
  //   주기 kGearCycleMs 중 마지막 kGearActiveMs 동안만 발동 → 일반 낚시와 비슷한 체감으로 튜닝.
  void _updateBossGear() {
    final elapsedMs = DateTime.now().millisecondsSinceEpoch - _startAt;
    final phase = elapsedMs % kGearCycleMs;
    final cycleNo = elapsedMs ~/ kGearCycleMs;
    int gear = 0;
    if (elapsedMs > 3000 && phase >= (kGearCycleMs - kGearActiveMs)) {
      gear = (math.Random(_startAt + cycleNo).nextInt(100) < 45) ? 2 : 1;
    }
    if (gear != _fishGear) {
      if (gear > 0) {
        // 보스가 챔 → 노브 왼쪽 팅김 + 장전(다시 당겨야 제압). 일반 낚시와 동일.
        _playerGear = 1;
        _flingLeft();
        // 🔇 레이드는 줄이 안 끊어지므로 sfx_break(줄 끊김) 대신 진동으로만 알림
        if (gear == 2) {
          _triggerSurface(2); // 💥 발악 = 물 밖으로 튀어올라 바늘털이
          HapticFeedback.heavyImpact();
        } else {
          HapticFeedback.mediumImpact();
        }
      } else {
        // 발악/저항 종료 → 다시 1단 제압으로 복귀(일반 낚시와 동일)
        _playerGear = 1;
        _flingTimer?.cancel();
      }
      _fishGear = gear;
    }
    // 흔들림: 발악 > 저항 > 당기는 중(1단, 사투 중이라 부르르) > 놓음(정지)
    _shake = _fishGear == 2
        ? (_rng.nextDouble() - 0.5) * 14
        : _fishGear == 1
            ? (_rng.nextDouble() - 0.5) * 8
            : (_isPressing ? (_rng.nextDouble() - 0.5) * 9 : 0);
  }

  // 🎣 보스가 낚싯대를 왼쪽으로 챔 — 노브 왼쪽 + 장전. 다시 오른쪽으로 당기면 제압단계 상승(펌핑).
  void _flingLeft() {
    if (!mounted || _phase != _Phase.fighting) {
      _knob.value = -1.0; _armed = true; _isPressing = false; return;
    }
    _knob.value = -1.0;
    _armed = true;
    _isPressing = false;
    HapticFeedback.heavyImpact();
  }

  // 🎣 [일반낚시식 노브] x: -1(풀기/놓음) ~ 1(오른쪽 당김). 일반 낚시 밀당과 동일한 조작.
  //    오른쪽으로 당기면 = 당기기(당겼다 = 장전됐으면 제압단계 +1) / 놓으면(왼쪽) = 풀기+장전.
  void _applyPull(double x) {
    if (_phase != _Phase.fighting) return;
    x = x.clamp(-1.0, 1.0);
    _knob.value = x;
    if (x >= -0.25) {
      // ▶ 당기기 — 일반 낚시와 동일한 단계 구조
      //   잔잔=1단 · 저항(목표2단): 팅김→당김 = 2단 · 발악(목표3단): 팅김→당김(2단)→다시 팅김→당김(3단)
      final int fg = _fishGear;
      final int target = fg == 2 ? 3 : (fg == 1 ? 2 : 1);
      if (fg == 0) {
        _playerGear = 1; // 잔잔 = 그냥 당기기 1단
      } else if (_armed) {
        _playerGear = math.min(_playerGear + 1, target); // 풀었다 당김 = +1단
        _armed = false;
        // 아직 목표 단계에 못 미치면(발악 3단) 잠시 뒤 보스가 한 번 더 챔 → 다시 당겨야 함
        if (_playerGear < target) {
          _flingTimer?.cancel();
          _flingTimer = Timer(const Duration(milliseconds: 500), () {
            if (mounted && _phase == _Phase.fighting && _fishGear == fg && _playerGear < target) _flingLeft();
            if (mounted) setState(() {});
          });
        }
      }
      _isPressing = true;
    } else {
      // ◀ 풀기(장전) → 다음 당기기서 제압단계 +1
      _isPressing = false;
      _armed = true;
    }
    setState(() {});
  }

  bool _onKey(KeyEvent e) {
    if (_phase == _Phase.biting && e is KeyDownEvent &&
        (e.logicalKey == LogicalKeyboardKey.keyD || e.logicalKey == LogicalKeyboardKey.space)) {
      _strike(); return true;
    }
    if (_phase != _Phase.fighting) return false;
    // 🎣 일반낚시와 동일 — D 하나로: 누르면 당김, 떼면 풀기(장전)
    if (e.logicalKey == LogicalKeyboardKey.keyD) {
      if (e is KeyDownEvent) _applyPull(1.0);
      if (e is KeyUpEvent) _applyPull(-1.0);
      return true;
    }
    return false;
  }

  // ─────────────────────────────────────────────────────────────
  // 🏁 종료 (보상 지급은 다음 단계)
  // ─────────────────────────────────────────────────────────────
  void _finish(bool win) {
    if (_phase == _Phase.done || _chaining) return;
    setState(() => _phase = _Phase.done);
    _tick?.cancel(); _secTimer?.cancel();
    _flingTimer?.cancel();
    _surfaceTimer?.cancel();
    _isPressing = false;
    audioManager.stopEfx(); // 🔇 당기던 물첨벙 소리가 결과화면까지 이어지지 않게
    _flushDamage();

    if (win) {
      // 🏆 이 보스 클리어를 길드 문서에 '영구' 기록 → 길드홀 트로피 깃발용. (arrayUnion=중복 무해)
      FirebaseFirestore.instance.collection('guilds').doc(widget.guildId)
          .set({'clearedBosses': FieldValue.arrayUnion([widget.bossId])}, SetOptions(merge: true))
          .catchError((_) {});
      _grantReward(); // 🎁 이 존 보상(로컬 지급 · 중복 가드)
      final next = nextRaidBoss(widget.bossId);
      if (next != null) {
        // 🐲 다음 존은 '자동 연결'이 아니라 길드홀 복귀 → 다시 레디 → 시작.
        //    (못 온 길드원 합류·정비 시간을 주기 위함) 리더가 다음 보스를 방 문서에 기록만 해둔다.
        if (widget.isLeader) _advanceLeader(next);
        _broadcastClear(); // 📢 상단 뉴스창에 길드 레이드 성공 방송
        Future.delayed(const Duration(milliseconds: 300), () {
          if (mounted) setState(() { _ceremony = true; _cerNext = next; });
        });
        return;
      }
      // 🏆 볼카르까지 클리어 = 완전 클리어. 🔒 이번 주 게이트 잠금(주 1회 도전).
      if (widget.isLeader) _roomRef.set({
        'status': 'cleared', 'weekLocked': currentRaidWeekKey(),
      }, SetOptions(merge: true)).catchError((_) => _roomRef);
      _broadcastClear(finalClear: true);
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) setState(() { _ceremony = true; _cerCleared = true; });
      });
      return;
    }
    // ⏱️ 실패(시간초과) — 🔒 이번 주 게이트 잠금 → 모임터로 복귀(리더 복귀 시 waiting 리셋은 플라자가 처리)
    if (widget.isLeader) _roomRef.set({
      'weekLocked': currentRaidWeekKey(),
    }, SetOptions(merge: true)).catchError((_) => _roomRef);
    Future.delayed(const Duration(milliseconds: 300), () { if (mounted) _showResult(false); });
  }

  // 🐲 방 문서 감시 — 리더가 판을 끝내면(대기/클리어 전환) 아직 전투 중인 길드원을 길드홀로 보낸다.
  //   ⚠️ 결과창을 보는 중(_phase==done)에는 팝하지 않는다(보상 화면이 잘리지 않게).
  void _watchRoomChain() {
    _roomSub = _roomRef.snapshots().listen((snap) {
      if (!mounted || _phase == _Phase.done) return;
      final d = snap.data();
      final status = (d?['status'] ?? 'waiting').toString();
      if (status == 'waiting' || status == 'failed' || status == 'cleared') {
        if (!_chaining) { _chaining = true; _popResult(null); }
      }
    });
  }

  // 길드장 전용: 다음 보스를 방 문서에 기록 + 대기 상태로. (전투는 길드홀에서 다시 시작)
  Future<void> _advanceLeader(Map<String, dynamic> next) async {
    try {
      await _battleRef.child('dmg').set(0); // 다음 판을 위해 진행도 초기화
      await _roomRef.set({
        'status': 'waiting',
        'bossId': next['id'], 'bossTier': next['tier'], 'bossHp': next['hp'],
        'endAt': FieldValue.delete(),
      }, SetOptions(merge: true));
    } catch (e) { debugPrint('🐲 다음 존 기록 실패: $e'); }
  }

  void _popResult(Map<String, dynamic>? r) {
    _tick?.cancel(); _secTimer?.cancel();
    if (mounted) Navigator.of(context).pop(r);
  }

  // 📢 상단 뉴스 자막에 길드 레이드 성공 방송 (길드장만 1회 — 중복 방지)
  Future<void> _broadcastClear({bool finalClear = false}) async {
    if (!widget.isLeader) return;
    try {
      await FirebaseFirestore.instance.collection('ticker_news').add({
        'text': '🐲 [${widget.guildName}] 길드가 ${widget.bossZone}에서 ${widget.bossName} 레이드에 성공했습니다!',
        'nickname': widget.nickname,
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) { debugPrint('📢 레이드 방송 실패: $e'); }
  }

  // 🎁 이 존 클리어 보상(exp+포인트[+상자]) — 참가자 각자 로컬 지급, 판별키로 중복 방지.
  Future<void> _grantReward() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final r = raidRewards[widget.bossId];
    if (r == null) return;
    final claimKey = 'raid_${widget.guildId}_${widget.bossId}_${widget.endAt}'; // 이번 판·이 보스 1회
    try {
      final ref = FirebaseFirestore.instance.collection('users').doc(user.uid);
      await FirebaseFirestore.instance.runTransaction((tx) async {
        final snap = await tx.get(ref);
        final claims = List<dynamic>.from(snap.data()?['raidClaims'] ?? []);
        if (claims.contains(claimKey)) return; // 이미 받음
        claims.add(claimKey);
        if (claims.length > 40) claims.removeRange(0, claims.length - 40);
        final exp = (r['exp'] as num?)?.toInt() ?? 0;
        final pt = (r['point'] as num?)?.toInt() ?? 0;
        final mystery = (r['mystery'] as num?)?.toInt() ?? 0;
        final treasure = (r['treasure'] as num?)?.toInt() ?? 0;
        final Map<String, dynamic> upd = {
          'exp': FieldValue.increment(exp),
          'gold': FieldValue.increment(pt),
          'raidClaims': claims,
        };
        // 📦 상자 지급(수상한상자/보물상자) — 기존 랜덤상자 스키마와 동일
        if (mystery > 0 || treasure > 0) {
          final inv = List<dynamic>.from(snap.data()?['inventory'] ?? []);
          void addBox(String name, String icon, int qty) {
            if (qty <= 0) return;
            final idx = inv.indexWhere((i) => i is Map && i['name'] == name);
            if (idx >= 0) {
              inv[idx]['quantity'] = ((inv[idx]['quantity'] as num?)?.toInt() ?? 0) + qty;
            } else {
              inv.add({'name': name, 'category': 'BOX', 'type': 'BOX', 'icon': icon, 'quantity': qty});
            }
          }
          addBox('수상한 상자', '수상한 상자.png', mystery);
          addBox('보물상자', '보물상자.png', treasure);
          upd['inventory'] = inv;
        }
        tx.update(ref, upd);
      });
    } catch (e) { debugPrint('🎁 raid reward err: $e'); }
  }

  // 🎣 단계별 낚싯대 씬 이미지: 캐스팅→cast, 웨이팅/입질→waiting, 파이팅→hand_rod.
  //   레이드대(raidTier>0)면 raid 세트, 아니면(GM 폴백) 기존 손낚싯대(fighting 포즈만).
  //   ⚠️ 전투 중엔 '당길 때만' 휘는 파이팅 포즈(hand_rod). 저항·발악에 버틸 땐 곧게(waiting) —
  //      현실 낚시처럼 물고기가 저항할 땐 무리해서 당기지 않고 버티는 그림.
  String _rodSceneImage() {
    if (_raidTier > 0) {
      String act;
      if (_phase == _Phase.casting) {
        act = 'cast';
      } else if (_phase == _Phase.fighting) {
        // 저항·발악 = 보스가 강하게 차고나가 낚싯대가 크게 휨(hand_rod)
        // 잔잔한 1단 제압 = 곧게 세워 천천히 끌어옴(waiting)
        act = _fishGear > 0 ? 'hand_rod' : 'waiting';
      } else {
        act = 'waiting';
      }
      return 'assets/images/${act}_raid_$_raidTier.png';
    }
    return 'assets/images/hand_rod_${widget.isSea ? 'sea' : 'fw'}_$_rodSfx.png';
  }

  void _showResult(bool win, {bool cleared = false, Map<String, dynamic>? next}) {
    final bossName = widget.bossName;
    final r = raidRewards[widget.bossId];
    final int rExp = (r?['exp'] as num?)?.toInt() ?? 0;
    final int rPt = (r?['point'] as num?)?.toInt() ?? 0;
    final int rMys = (r?['mystery'] as num?)?.toInt() ?? 0;
    final int rTre = (r?['treasure'] as num?)?.toInt() ?? 0;
    final String boxTxt = '${rMys > 0 ? ' · 📦수상한상자 $rMys' : ''}${rTre > 0 ? ' · 💎보물상자 $rTre' : ''}';
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
            Image.asset(widget.bossMarker,
                height: 140, fit: BoxFit.contain,
                errorBuilder: (a, b, c2) => const Icon(Icons.set_meal, color: Colors.white24, size: 100)),
            const SizedBox(height: 10),
            Text(bossName, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900)),
            if (cleared) const Padding(padding: EdgeInsets.only(top: 4),
                child: Text('5개 존 전부 제압! 최강 길드 🐲', style: TextStyle(color: Color(0xFFF3D874), fontSize: 13, fontWeight: FontWeight.w800))),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _kGold.withOpacity(0.4))),
              child: Text('🎁 보상  +${rExp}EXP · +${rPt}P$boxTxt',
                  style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w800)),
            ),
            // 🐲 다음 존 안내 — 길드홀로 돌아가 다시 레디 후 도전
            if (next != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.black38, borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF7FFFB0).withOpacity(0.5)),
                ),
                child: Column(children: [
                  Text('다음 존 열림!  ${next['tier']}. ${next['zone']}',
                      style: const TextStyle(color: Color(0xFF7FFFB0), fontSize: 14, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 2),
                  Text('${next['name']}',
                      style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 4),
                  const Text('길드홀에서 정비하고 다시 레디 → 시작!',
                      style: TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.w700)),
                ]),
              ),
            ],
          ] else ...[
            const Text('🏊', style: TextStyle(fontSize: 56)),
            const SizedBox(height: 8),
            const Text('아쉽게 놓쳤어요!\n길드원을 더 모으거나 장비를 올려 재도전!',
                textAlign: TextAlign.center, style: TextStyle(color: Colors.white70, fontSize: 15, height: 1.5)),
          ],
        ]),
        actions: [Center(child: ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: _kGold, foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 14)),
          onPressed: () { Navigator.pop(c); Navigator.pop(context); },
          child: const Text('길드홀로', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
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
    final bossImg = widget.bossMarker;

    return Scaffold(
      body: RepaintBoundary(key: _shotKey, child: Stack(fit: StackFit.expand, children: [
        // 배경
        Image.asset(widget.bossBg,
            fit: BoxFit.cover, errorBuilder: (a, b, c) => Image.asset('assets/fields/bg_guild_fw.jpg',
                fit: BoxFit.cover, errorBuilder: (a2, b2, c2) => Container(color: const Color(0xFF0B2A2E)))),
        Container(color: Colors.black.withOpacity(0.12)),

        // (배경 보스 이미지 제거 — 물만. 나중에 이펙트/보스 연출 추가 예정)

        // 🐲 보스 등장 연출(물 위로 어렴풋이 / 머리만 / 바늘털이) — 배경 위, UI 아래
        if (_phase == _Phase.fighting) Positioned.fill(child: _bossSurfaceFx()),

        // 🧾 좌측 정보창 (일반 낚시터 HUD와 동일: 보스명 · 레벨/제압력 · EXP · 포인트)
        Positioned(top: 12, left: 18, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            IconButton(padding: EdgeInsets.zero, constraints: const BoxConstraints(),
                icon: const Icon(Icons.arrow_back_ios, color: Colors.white, size: 22),
                onPressed: () { audioManager.playSfx('sfx_click.mp3'); Navigator.pop(context); }),
            const SizedBox(width: 5),
            Text('🐲 ${widget.bossZone}',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white,
                    shadows: [Shadow(color: Colors.black, blurRadius: 2)])),
          ]),
          const SizedBox(height: 8),
          Padding(padding: const EdgeInsets.only(left: 5), child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _kGold, width: 1)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text('Lv.$_level', style: const TextStyle(color: Colors.yellowAccent, fontSize: 13, fontWeight: FontWeight.bold)),
              const SizedBox(width: 8),
              Text('제압력: $_power', style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
              Text(' (💪$_statP  🎯$_statC  📡$_statS)', style: const TextStyle(color: Colors.white, fontSize: 13)),
            ]),
          )),
          const SizedBox(height: 6),
          Text('$_exp EXP', style: const TextStyle(color: Colors.white, fontSize: 14)),
          const SizedBox(height: 6),
          Text('point $_gold', style: const TextStyle(color: Colors.cyanAccent, fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          // 🐲 보스 이름 + 길드
          Text('${widget.bossName}  [${widget.guildName}]',
              style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w800,
                  shadows: [Shadow(color: Colors.black, blurRadius: 4)])),
        ])),

        // ⏱️ 남은 시간 — 화면 상단 가운데(일반 낚시터와 동일 위치)
        Positioned(top: 12, left: 0, right: 0, child: Center(child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 7),
          decoration: BoxDecoration(color: Colors.black.withOpacity(0.7), borderRadius: BorderRadius.circular(22),
              border: Border.all(color: _remain <= 60 ? Colors.redAccent : _kGold, width: 1.4)),
          child: Text('⏱️ $mm:$ss', style: TextStyle(color: _remain <= 60 ? Colors.redAccent : Colors.white,
              fontSize: 20, fontWeight: FontWeight.w900)),
        ))),

        // ⚙️ 우측 상단 버튼 — 일반 낚시터와 동일(인벤/미끼교체 제외), 조금 크게
        Positioned(top: 10, right: 18, child: Row(children: [
          _hudButton(Icons.settings, () {
            audioManager.playSfx('sfx_click.mp3');
            showSoundSettingsDialog(context).then((_) { if (mounted) setState(() {}); });
          }),
          const SizedBox(width: 10),
          _hudButton(Icons.fullscreen, _toggleFullScreen), // 📱 모바일도 필요(전체화면 없으면 게임 불가)
          const SizedBox(width: 10),
          _hudButton(Icons.shield, () => showGuildInfoDialog(context)),
          const SizedBox(width: 10),
          _hudButton(Icons.close, () => Navigator.pop(context)),
        ])),

        // 📢 흐르는 광고/랭킹 자막 (일반 낚시터·광장과 동일)
        Positioned(top: 62, left: 0, right: 0, child: const IgnorePointer(child: RankingTicker())),

        // 💪 합산 제압력 — 제압률(%)은 심리적 포기 유발 요소라 표시 안 함(보스 등장 연출로 진행감 대체)
        Positioned(top: 92, left: 0, right: 0, child: Center(child: Container(
          width: 260,
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(color: Colors.black.withOpacity(0.5), borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _kGold.withOpacity(0.6))),
          child: Text('💪 합산 제압력 $_combinedPower/초',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w900,
                  shadows: [Shadow(color: Colors.black, blurRadius: 4)])),
        ))),

        // ⚠️ 발악/저항 경고 — 일반 낚시와 동일한 크기·위치(top 350 · 18pt 알약형)
        if (_phase == _Phase.fighting && _fishGear > 0)
          Positioned(top: 430, left: 0, right: 0, child: Center(child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            decoration: BoxDecoration(
              color: (_fishGear == 2 ? Colors.redAccent : Colors.orange).withOpacity(0.8),
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: Colors.white, width: 2),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 24),
              const SizedBox(width: 8),
              Text(_fishGear == 2 ? '🚨 보스의 발악!!' : '🐲 보스의 저항!',
                  style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold,
                      fontStyle: FontStyle.italic)),
            ]),
          ))),

        // 🎣 낚싯대 (전투 중, 당길 때 휨)
        //   레이드대: 이미지 자체가 캐스팅/웨이팅/파이팅 포즈라 회전 없이 우하단 고정(흔들림만).
        //   일반대(GM 폴백): 기존처럼 회전으로 휨 표현.
        if (_phase == _Phase.fighting || _phase == _Phase.casting || _phase == _Phase.waiting || _phase == _Phase.biting)
          Positioned(
            right: _raidTier > 0 ? kRaidRodRight : -28,
            bottom: _raidTier > 0 ? kRaidRodBottom : 120,
            child: Transform.translate(
              // 사투 중 낚싯대가 흔들리는 느낌(당길 때·발악/저항 때 진폭 커짐)
              offset: Offset(_shake * 0.9, _shake * 0.5),
              child: Transform.rotate(
              angle: _raidTier > 0
                  ? _shake * 0.012
                  : (_isPressing && _fishGear == 0 ? -0.30 : -0.12) + _shake * 0.010,
              alignment: Alignment.bottomRight,
              child: Image.asset(_rodSceneImage(),
                  height: _raidTier > 0 ? kRaidRodHeight : 300, fit: BoxFit.contain,
                  errorBuilder: (a, b, c) => Image.asset(
                      _raidTier > 0 ? 'assets/images/hand_rod_raid_$_raidTier.png' : 'assets/images/hand_rod_${widget.isSea ? 'sea' : 'fw'}.png',
                      height: _raidTier > 0 ? kRaidRodHeight : 300, fit: BoxFit.contain,
                      errorBuilder: (a2, b2, c2) => const SizedBox.shrink())),
            ))),

        // ── 하단 컨트롤/게이지 (단계별) ── 전체화면 레이어로(버튼 히트테스트 보장)
        Positioned.fill(child: _bottomLayer(progress, bossImg)),

        // 🎉 [레이드 성공 세러모니] 전체화면 — 버튼 누를 때까지 유지(스크린샷 타임)
        if (_ceremony) Positioned.fill(child: _ceremonyOverlay()),

      ])),
    );
  }

  Widget _bottomLayer(double progress, String bossImg) {
    switch (_phase) {
      case _Phase.loading:
        return const Center(child: Text('🎒 자동장착 중...', style: TextStyle(color: Colors.white70, fontSize: 18, fontWeight: FontWeight.w900)));
      case _Phase.casting:
        return Stack(children: [
          _strikeDragUI(active: true), // 🎣 챔질/당기기 버튼은 처음부터 활성(일찍 채면 '헛챔질' 안내)
          Align(alignment: Alignment.bottomCenter, child: Padding(padding: const EdgeInsets.only(bottom: 40), child: _panel([
          Text('🎒 자동장착 완료 — $_gearMsg', style: const TextStyle(color: Color(0xFF7FFFB0), fontSize: 13, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          const Text('🎣 캐스팅...', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900)),
        ]))),
        ]);
      case _Phase.waiting:
        return Stack(children: [
          _strikeDragUI(active: true),
          Align(alignment: Alignment.bottomCenter, child: Padding(padding: const EdgeInsets.only(bottom: 40), child: _panel([
          const Text('🌊 입질을 기다리는 중...', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          const Text('곧 길드원 전원에게 동시에 입질이 와요!', style: TextStyle(color: Colors.white60, fontSize: 12)),
        ]))),
        ]);
      case _Phase.biting:
        // 🎣 일반 낚시와 동일 — '챔질!' 버튼을 아래 '당기기' 존으로 끌어내려 챔질.
        return Stack(children: [
          const Positioned(top: 150, left: 0, right: 0, child: Center(child: Text('입질 !!',
              style: TextStyle(color: Colors.redAccent, fontSize: 84, fontWeight: FontWeight.w900, fontStyle: FontStyle.italic,
                  shadows: [Shadow(color: Colors.black, blurRadius: 16, offset: Offset(4, 4))])))),
          _strikeDragUI(active: true),
          const Positioned(bottom: 16, left: 0, right: 0, child: Center(child: Text(
              '🎣 챔질 버튼을 아래 당기기로 끌어내리세요!  (PC: D키 / Space)',
              style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w900,
                  shadows: [Shadow(color: Colors.black, blurRadius: 6)])))),
        ]);
      case _Phase.fighting:
        return _fightGauge(progress, bossImg);
      case _Phase.done:
        return const SizedBox.shrink();
    }
  }

  // 🎣 [챔질 → 당기기] 일반 낚시와 동일한 드래그 UI.
  //   캐스팅/입질대기 중에도 계속 보이되(active=false) 흐리게 · 입질 때만 동작.
  Widget _strikeDragUI({required bool active}) {
    final double op = active ? 1.0 : 0.45;
    return Positioned(right: 60, top: 60, bottom: 20, child: Center(child: Opacity(
      opacity: op,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // 🔴 [위] 끌어내릴 챔질 버튼
        IgnorePointer(
          ignoring: !active,
          child: Draggable<String>(
            data: 'STRIKE',
            axis: Axis.vertical,
            feedback: Material(color: Colors.transparent, child: Container(
              width: 104, height: 104,
              decoration: BoxDecoration(color: Colors.redAccent.withOpacity(0.9), shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 5),
                  boxShadow: const [BoxShadow(blurRadius: 20, spreadRadius: 5, color: Colors.white70)]),
              child: const Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.catching_pokemon, size: 38, color: Colors.white),
                Text('챔질!', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900)),
              ]),
            )),
            childWhenDragging: Container(width: 104, height: 104,
              decoration: BoxDecoration(color: Colors.black26, shape: BoxShape.circle,
                  border: Border.all(color: Colors.white38, width: 5)),
              child: const Icon(Icons.arrow_downward, color: Colors.white54, size: 40)),
            child: Container(width: 104, height: 104,
              decoration: BoxDecoration(
                  color: active ? Colors.redAccent : Colors.redAccent.withOpacity(0.6), shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 5),
                  boxShadow: const [BoxShadow(blurRadius: 15, spreadRadius: 2, color: Colors.black54)]),
              child: const Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.catching_pokemon, size: 34, color: Colors.white),
                Text('챔질!', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900)),
              ])),
          ),
        ),
        const SizedBox(height: 16),
        const Icon(Icons.keyboard_double_arrow_down, color: Colors.yellowAccent, size: 34,
            shadows: [Shadow(color: Colors.black, blurRadius: 5)]),
        const Icon(Icons.keyboard_double_arrow_down, color: Colors.white54, size: 34,
            shadows: [Shadow(color: Colors.black, blurRadius: 5)]),
        const SizedBox(height: 16),
        // 🟡 [아래] 끌어다 놓을 당기기 존 — 진입 즉시 챔질
        DragTarget<String>(
          onWillAcceptWithDetails: (d) { if (active && d.data == 'STRIKE') { _strike(); return true; } return false; },
          onAcceptWithDetails: (_) {},
          builder: (context, cand, rej) {
            final bool hover = cand.isNotEmpty;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: hover ? 120 : 104, height: hover ? 120 : 104,
              decoration: BoxDecoration(
                color: hover ? Colors.orangeAccent : _kGold, shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: hover ? 8 : 5),
                boxShadow: hover
                    ? const [BoxShadow(blurRadius: 30, spreadRadius: 10, color: Colors.orangeAccent)]
                    : const [BoxShadow(blurRadius: 15, spreadRadius: 2, color: Colors.black54)],
              ),
              child: Center(child: Text('당기기',
                  style: TextStyle(color: Colors.white, fontSize: hover ? 28 : 24, fontWeight: FontWeight.w900))),
            );
          },
        ),
      ]),
    )));
  }

  // ⛶ 전체화면 토글 (일반 낚시터/광장과 동일 — 웹 전용). 📱 모바일도 필요(전체화면 없으면 게임 불가).
  void _toggleFullScreen() {
    try {
      if (html.document.fullscreenElement == null) {
        html.document.documentElement?.requestFullscreen().then((_) {
          html.window.screen?.orientation?.lock('landscape');
        }).catchError((e) { debugPrint('전체화면 실패: $e'); });
      } else {
        html.document.exitFullscreen();
        html.window.screen?.orientation?.unlock();
      }
    } catch (e) { debugPrint('전체화면 오류: $e'); }
  }

  // 🎉 레이드 성공 세러모니 — 보스 이미지를 크게 띄우고 보상·다음 존 안내. 스샷 찍을 시간을 준다.
  Widget _ceremonyOverlay() {
    final r = raidRewards[widget.bossId];
    final int rExp = (r?['exp'] as num?)?.toInt() ?? 0;
    final int rPt = (r?['point'] as num?)?.toInt() ?? 0;
    final int rMys = (r?['mystery'] as num?)?.toInt() ?? 0;
    final int rTre = (r?['treasure'] as num?)?.toInt() ?? 0;

    return Container(
      color: Colors.black.withOpacity(0.72),
      child: SafeArea(child: Column(children: [
        const SizedBox(height: 10),
        // 🏆 타이틀
        const Text('🎉 RAID CLEAR!',
            style: const TextStyle(color: _kGold, fontSize: 40, fontWeight: FontWeight.w900,
                fontStyle: FontStyle.italic, letterSpacing: 1.5,
                shadows: [Shadow(color: Colors.black, blurRadius: 14, offset: Offset(3, 3))])),
        const SizedBox(height: 2),
        Text('[${widget.guildName}]  ·  ${widget.bossZone}',
            style: const TextStyle(color: Colors.white70, fontSize: 15, fontWeight: FontWeight.w800,
                shadows: [Shadow(color: Colors.black, blurRadius: 6)])),
        // 🐲 보스 이미지 (화면 꽉 차게)
        Expanded(child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 6),
          child: Image.asset(widget.bossMarker, fit: BoxFit.contain,
              errorBuilder: (a, b, c) => const Icon(Icons.set_meal, color: Colors.white24, size: 140)),
        )),
        Text(widget.bossName,
            style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w900,
                shadows: [Shadow(color: Colors.black, blurRadius: 10)])),
        const SizedBox(height: 10),
        // 🎁 보상 — 폰에서도 잘 보이게 크게 + 상자는 실제 아이템 이미지로
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 14),
          decoration: BoxDecoration(color: Colors.black.withOpacity(0.62), borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _kGold, width: 2)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Text('🎁 ', style: TextStyle(fontSize: 28)),
            Text('+$rExp EXP', style: const TextStyle(color: Color(0xFF7FFFB0), fontSize: 24, fontWeight: FontWeight.w900)),
            const Text('  ·  ', style: TextStyle(color: Colors.white38, fontSize: 22)),
            Text('+$rPt KREFT', style: const TextStyle(color: Colors.yellowAccent, fontSize: 21, fontWeight: FontWeight.w900)),
            if (rMys > 0) ...[
              const SizedBox(width: 16),
              Image.asset('assets/items/수상한 상자.png', width: 46, height: 46, fit: BoxFit.contain,
                  errorBuilder: (a, b, c) => const Text('📦', style: TextStyle(fontSize: 32))),
              Text(' ×$rMys', style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900)),
            ],
            if (rTre > 0) ...[
              const SizedBox(width: 16),
              Image.asset('assets/items/보물상자.png', width: 46, height: 46, fit: BoxFit.contain,
                  errorBuilder: (a, b, c) => const Text('💎', style: TextStyle(fontSize: 32))),
              Text(' ×$rTre', style: const TextStyle(color: Color(0xFFFFD86B), fontSize: 24, fontWeight: FontWeight.w900)),
            ],
          ]),
        ),
        const SizedBox(height: 8),
        // 🐲 다음 존 안내
        if (_cerNext != null)
          Text('다음 존 열림!  ${_cerNext!['tier']}. ${_cerNext!['zone']} · ${_cerNext!['name']}',
              style: const TextStyle(color: Color(0xFF7FFFB0), fontSize: 14, fontWeight: FontWeight.w900,
                  shadows: [Shadow(color: Colors.black, blurRadius: 6)]))
        else if (_cerCleared)
          const Text('5개 존 전부 제압! 최강 길드 🐲',
              style: TextStyle(color: Color(0xFFF3D874), fontSize: 15, fontWeight: FontWeight.w900)),
        const SizedBox(height: 10),
        // 📸 스샷 타임 안내 + 나가기
        const SizedBox(height: 4),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          // 📸 기념샷 저장 (JPG)
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.black.withOpacity(0.65), foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: _kGold.withOpacity(0.8), width: 1.3))),
            onPressed: () => takeScreenshot(context, _shotKey, prefix: 'camnak_raid_${widget.bossId}'),
            icon: const Icon(Icons.photo_camera, size: 20),
            label: const Text('기념샷 저장', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
          ),
          const SizedBox(width: 10),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _kGold, foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            onPressed: () => _popResult(null),
            child: const Text('길드홀로', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
          ),
        ]),
        const SizedBox(height: 10),
      ])),
    );
  }

  // ⚙️ 상단 미니 버튼 — 일반 낚시터와 같은 룩(조금 더 크게)
  Widget _hudButton(IconData icon, VoidCallback onPressed) => GestureDetector(
        onTap: onPressed,
        child: Container(
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            color: Colors.black87,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _kGold, width: 1.2),
          ),
          child: Icon(icon, color: _kGold, size: 26),
        ),
      );

  Widget _panel(List<Widget> children) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
        decoration: BoxDecoration(color: Colors.black.withOpacity(0.55), borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _kGold.withOpacity(0.6))),
        child: Column(mainAxisSize: MainAxisSize.min, children: children),
      );

  // 🎣 낚시식 좌우 게이지 (마커=피라루크) + 당기기/풀기
  // 존별 수면선(없거나 짧으면 전역 기본값)
  double _waterAt(int zone) {
    final w = widget.bossWater;
    if (w.length > zone) return w[zone];
    return zone == 2 ? kNearWaterY : (zone == 1 ? kMidWaterY : kFarWaterY);
  }

  // 🐲 [보스 등장 연출] 6~14초마다 물 위로 어렴풋이 떠오르거나 머리만 슬쩍 내밈.
  void _scheduleSurface() {
    _surfaceTimer?.cancel();
    _surfaceTimer = Timer(Duration(milliseconds: 6000 + _rng.nextInt(8000)), () {
      if (!mounted || _phase != _Phase.fighting) return;
      _triggerSurface(_rng.nextInt(2)); // 0 어렴풋이 / 1 머리만
      _scheduleSurface();
    });
  }

  void _triggerSurface(int type) {
    if (!mounted || _surfaceCtrl.isAnimating) return;
    _surfaceType = type;
    _surfaceX = -0.55 + _rng.nextDouble() * 1.1;
    _surfaceFlip = _rng.nextBool();                        // 좌우 방향 랜덤
    _surfaceTilt = (_rng.nextDouble() - 0.5) * 0.5;        // 몸 기울기 랜덤
    _surfaceScale = 0.85 + _rng.nextDouble() * 0.45;       // 크기 랜덤(멀리/가까이)
    _surfaceCut = 0.38 + _rng.nextDouble() * 0.24;         // 물 밖으로 드러나는 비율(38~62%)
    // 🎯 제압률로 '멀리/중간/가까이' 3단계 확정 (등장 도중엔 안 바뀜)
    final double prog = (_targetHP > 0 ? _dmgTotal / _targetHP : 0.0).clamp(0.0, 1.0);
    if (prog >= kZoneNearAt) {
      _surfaceZone = 2;
      _surfaceWaterY = _waterAt(2); _surfaceDistScale = kNearScale;
      _surfaceDistOp = kNearOpacity; _surfaceTint = kNearTint; _surfaceSpread = kNearSpread;
    } else if (prog >= kZoneMidAt) {
      _surfaceZone = 1;
      _surfaceWaterY = _waterAt(1); _surfaceDistScale = kMidScale;
      _surfaceDistOp = kMidOpacity; _surfaceTint = kMidTint; _surfaceSpread = kMidSpread;
    } else {
      _surfaceZone = 0;
      _surfaceWaterY = _waterAt(0); _surfaceDistScale = kFarScale;
      _surfaceDistOp = kFarOpacity; _surfaceTint = kFarTint; _surfaceSpread = kFarSpread;
    }
    _surfaceCtrl.duration = Duration(milliseconds: type == 2 ? 3200 : 2600);
    _surfaceCtrl.forward(from: 0).whenComplete(() { if (mounted) _surfaceCtrl.reset(); });
  }

  // 물 위로 떠오르는 보스 — 컨트롤러에만 붙어 있어 화면 전체를 다시 그리지 않는다(렉 방지).
  //   0 어렴풋이: 물속에 잠긴 실루엣이 흐릿하게 / 1 머리만: 고개를 들고 반쯤만 물 밖으로
  //   2 바늘털이: 몸 전체가 튀어올라 파르르 떨다 잠수 (발악 때)
  Widget _bossSurfaceFx() {
    return IgnorePointer(child: LayoutBuilder(builder: (context, box) {
      final double screenH = box.maxHeight;
      return AnimatedBuilder(
        animation: _surfaceCtrl,
        builder: (context, _) {
          final double t = _surfaceCtrl.value;
          if (t <= 0) return const SizedBox.shrink();
          final double rise = math.sin(t * math.pi); // 0 → 1 → 0 (떠올랐다 가라앉음)
          final bool thrash = _surfaceType == 2;
          final bool headOnly = _surfaceType == 1;

          // 🐲 3단계(멀리/중간/가까이) 값 — 등장 시점에 확정된 것 사용
          final double distOp = _surfaceDistOp;
          final double distScale = _surfaceDistScale;
          final double baseOp = (_surfaceType == 0 ? 0.24 : (headOnly ? 0.72 : 0.95)) * distOp;
          final double op = (baseOp * rise).clamp(0.0, 1.0);
          // 솟는 높이: 가까울수록 조금 더 시원하게 드러남(멀리선 거의 안 솟음)
          final double zoneUp = _surfaceZone == 2 ? 1.0 : (_surfaceZone == 1 ? 0.75 : 0.5);
          final double up = rise * (thrash ? 18 : (headOnly ? 13 : 5)) * zoneUp;
          final double shake = thrash ? math.sin(t * math.pi * 2) * 22 * rise : 0;
          // 🏊 떠 있는 동안 머리가 향한 쪽으로 스르륵 이동(헤엄치는 느낌). 멀수록 조금만 움직임.
          final double drift = (_surfaceFlip ? 1 : -1) * t * (thrash ? 26 : 48) * _surfaceSpread;
          final double tilt = thrash
              ? _surfaceTilt + math.sin(t * math.pi * 2) * 0.30 * rise
              : headOnly
                  ? _surfaceTilt - 0.42 * rise
                  : _surfaceTilt + math.sin(t * math.pi * 2) * 0.04;
          final double h = (thrash ? 250.0 : (headOnly ? 210.0 : 200.0)) * _surfaceScale * distScale;

          Widget boss = Image.asset(widget.bossMarker, height: h, fit: BoxFit.contain,
              errorBuilder: (a, b, c) => const SizedBox.shrink());

          final double tintA = ((_surfaceType == 0 ? 0.72 : (headOnly ? 0.22 : 0.0)) + _surfaceTint)
              .clamp(0.0, 0.92);
          if (tintA > 0) {
            boss = ColorFiltered(
              colorFilter: ColorFilter.mode(const Color(0xFF0E3B44).withOpacity(tintA), BlendMode.srcATop),
              child: boss,
            );
          }
          boss = Transform.rotate(angle: tilt, child: boss);

          // 🌊 수면 위로 드러나는 연출(머리만·바늘털이)만 아래를 잘라낸다.
          //    '어렴풋이'는 물속을 지나가는 그림자라 자르지 않고 몸 전체를 흐리게 보여준다.
          final bool clipped = headOnly || thrash;
          final double cut = clipped ? (_surfaceCut * (thrash ? 1.25 : 1.0)).clamp(0.25, 0.78) : 1.0;
          if (clipped) {
            boss = ClipRect(child: Align(alignment: Alignment.topCenter, heightFactor: cut, child: boss));
          }
          boss = Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()..scale(_surfaceFlip ? -1.0 : 1.0, 1.0),
            child: boss,
          );

          // 📐 '보이는 아래끝'이 수면선에 정확히 닿도록 배치.
          //    Align은 자식의 '중심'이 아니라 여백 비율로 놓이므로 역산해서 y를 구한다.
          //    (안 하면 가까이서 커질 때 물 밖 앞쪽까지 튀어나온다)
          final double visH = h * cut;
          final double waterLine = screenH * _surfaceWaterY; // 구간별 수면선(멀리/중간/가까이)
          final double denom = (screenH - visH).abs() < 1 ? 1 : (screenH - visH);
          final double alignY = (2 * (waterLine - visH) / denom - 1).clamp(-1.0, 1.0);

          return Align(
            alignment: Alignment(_surfaceX * _surfaceSpread, alignY),
            child: Transform.translate(
              offset: Offset(shake + drift, -up),
              child: Opacity(opacity: op, child: boss),
            ),
          );
        },
      );
    }));
  }

  // 🐲 보스가 오른쪽(승리선)으로 끌려오는 중인가? = 지금 실제로 전진 중인가.
  //    잔잔이면 당기기만 해도 끌려오고, 저항·발악은 단계를 맞춰 받아쳐야 머리가 돌아간다.
  bool get _bossFacingRight {
    if (!_isPressing) return false;
    if (_fishGear == 0) return true;
    final int need = _fishGear == 2 ? 3 : 2;
    return _playerGear >= need;
  }

  Widget _fightGauge(double progress, String bossImg) {
    return Stack(children: [
      // ❌ 진행 게이지·보스마커 제거 — "몇 % 남음" 시각화가 포기 심리를 유발.
      //    대신 실제 보스 등장 연출(_bossSurfaceFx: 멀리→가까이 확대·또렷)로 진행감 전달.
      // ❌ 조작 힌트("당겨서 오른쪽 끝까지"/"풀기→당기기 반복") 제거 — 보스 크기 변화·발악 팝업으로 충분히 유도됨.
      // 🔢 제압 단계 표시 — 일반 낚시와 동일(당기기 노브 위, 1단/2단/3단 최대제압)
      Positioned(bottom: 140, right: 24, child: SizedBox(width: 300, child: Center(
        child: ValueListenableBuilder<double>(
          valueListenable: _knob,
          builder: (context, kx, _) {
            if (kx < -0.3) {
              return const Text('오른쪽으로 당겨요! ▶',
                  style: TextStyle(color: Colors.orangeAccent, fontSize: 26, fontWeight: FontWeight.w900,
                      fontStyle: FontStyle.italic, shadows: [Shadow(color: Colors.black, blurRadius: 4)]));
            }
            final String t = _playerGear >= 3 ? '3단 최대제압!' : '$_playerGear단 제압!';
            final Color c = _playerGear >= 3 ? Colors.redAccent : (_playerGear == 2 ? Colors.orangeAccent : Colors.yellow);
            return Text(t, style: TextStyle(color: c, fontSize: _playerGear >= 3 ? 30 : 26,
                fontWeight: FontWeight.w900, fontStyle: FontStyle.italic,
                shadows: const [Shadow(color: Colors.black, blurRadius: 4)]));
          },
        ),
      ))),
      // 🎣 [일반낚시식] 당기기 노브 레일 — 오른쪽으로 드래그=당기기 / 놓으면=풀기(장전). 별도 버튼 없음.
      Positioned(bottom: 30, right: 24, child: SizedBox(
        width: 300,
        child: LayoutBuilder(builder: (context, box) {
          final double w = box.maxWidth;
          void handle(Offset local) => _applyPull(w <= 0 ? 1.0 : (local.dx / w) * 2 - 1);
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanDown: (d) => handle(d.localPosition),
            onPanStart: (d) => handle(d.localPosition),
            onPanUpdate: (d) => handle(d.localPosition),
            onPanEnd: (_) => _applyPull(-1.0),   // 놓으면 풀기(장전)
            onPanCancel: () => _applyPull(-1.0),
            child: SizedBox(height: 108, child: Stack(alignment: Alignment.center, clipBehavior: Clip.none, children: [
              // 레일 (좌 주황=풀기 / 우 파랑=당기기)
              Container(height: 44, margin: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(28),
                  gradient: const LinearGradient(colors: [Color(0xFFE07A2E), Color(0xFF2B2B2B), Color(0xFF243B66)]),
                  border: Border.all(color: Colors.white24, width: 2),
                  boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 6)])),
              const Positioned(left: 18, child: IgnorePointer(child: Text('◀ 풀기',
                  style: TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.bold)))),
              // 노브 = 당기기 (손가락 위치 따라감)
              ValueListenableBuilder<double>(
                valueListenable: _knob,
                builder: (context, kx, _) {
                  final bool releasing = kx < -0.3;
                  final Color knobColor = releasing
                      ? const Color(0xFFE07A2E)
                      : (_fishGear == 2 ? const Color(0xFFE53935) : _kGold);
                  return Align(
                    alignment: Alignment(kx.clamp(-1.0, 1.0), 0),
                    child: Container(width: 96, height: 96,
                      decoration: BoxDecoration(color: knobColor, shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 5),
                        boxShadow: [
                          if (_fishGear == 2 && !releasing) const BoxShadow(color: Colors.redAccent, blurRadius: 20, spreadRadius: 4),
                          const BoxShadow(color: Colors.black54, blurRadius: 10, offset: Offset(0, 4)),
                        ]),
                      alignment: Alignment.center,
                      child: Text(releasing ? '풀기' : '당기기',
                          style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900,
                              shadows: [Shadow(color: Colors.black45, blurRadius: 3)]))),
                  );
                },
              ),
            ])),
          );
        }),
      )),
      const Positioned(left: 0, right: 0, bottom: 6, child: Center(child: Text('PC: D키 — 누르면 당기기 · 떼면 풀기',
          style: TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.bold)))),
    ]);
  }
}
