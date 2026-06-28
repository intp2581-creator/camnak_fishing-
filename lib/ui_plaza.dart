// ignore_for_file: deprecated_member_use, use_build_context_synchronously
// 🏛️ [광장 시스템] 낚시터별 광장(허브). 1단계: 나 혼자 걸어다니며 상점/아레나/포탈/낚시 진입.
//    2단계에서 RTDB로 다른 유저 실시간 표시 예정.
import 'dart:async';
import 'dart:html' as html; // 전체화면 토글
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // ⌨️ 키보드(WASD) 이동
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
import 'ui_tutorial_npc.dart'; // NpcTutorialOverlay (아라 일일퀘스트)
import 'ui_guild.dart'; // 길드 접속표시(presence) + 접속 점

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
  String _moveDir = 'down'; // 'down'(앞) / 'up'(뒤) / 'side'(옆) — 걷기 방향 스프라이트
  Duration _moveDuration = const Duration(milliseconds: 500);

  // 🔧 운영자 전용 스킨 미리보기 (가방/상점 안 건드리고 캐릭터만 바꿔봄)
  bool get _isOperator =>
      ['intp2581@gmail.com', 'test_admin@camnak.com']
          .contains(FirebaseAuth.instance.currentUser?.email);
  static const List<String> _previewSkins = [
    '초보 조사', '하수 조사', '중수 조사', '고수 조사', '프로 조사', '마스터 조사', '레전드 조사', '낚시의 신'
  ];
  int _skinPreviewIdx = 0;
  void _cycleSkinPreview() {
    setState(() {
      _skinPreviewIdx = (_skinPreviewIdx + 1) % _previewSkins.length;
      globalEquippedSkin = {
        'name': _previewSkins[_skinPreviewIdx], 'category': 'SKIN', 'type': 'SKIN'
      };
    });
    _toast('스킨 미리보기 → ${_previewSkins[_skinPreviewIdx]}');
  }

  // 🚶 걷기 바운스용
  late final AnimationController _walkCtrl;
  bool _walking = false;
  int _moveToken = 0;

  // 🕹️ 가상 조이스틱 (우하단, 드래그 방향으로 연속 이동)
  static const double _joyRadius = 55;
  Offset _joyKnob = Offset.zero; // 노브 오프셋(화면px)
  Offset _joyDir = Offset.zero; // 방향*세기 (길이 0~1)
  Timer? _joyTimer;
  double _worldW = 1, _worldH = 1; // build에서 갱신 (조이스틱 이동 환산용)
  DateTime _lastNetSend = DateTime.fromMillisecondsSinceEpoch(0);
  // 🌐 실시간(2단계) — 같은 광장 다른 유저
  static final FirebaseDatabase _db = FirebaseDatabase.instanceFor(
    app: Firebase.app(),
    databaseURL: 'https://camnak-fishing-default-rtdb.asia-southeast1.firebasedatabase.app',
  );
  DatabaseReference? _myRef;
  final List<StreamSubscription<DatabaseEvent>> _presenceSubs = []; // 채널 child 이벤트 구독들
  final Map<String, Map<String, dynamic>> _others = {};
  String get _roomKey => widget.isSea ? 'sea' : 'fresh';

  // 🧩 광장 채널 샤딩: 정원 차면 자동으로 ch2, ch3… 생성 (스파이크 대비)
  //    평소(소수 접속)엔 전원 ch1 → 지금과 체감 동일.
  static const int _plazaChannelCap = 50; // 채널당 정원
  String? _channelKey; // 실제 구독 경로 (예: 'fresh/ch3')
  int _channelNum = 1; // 현재 채널 번호 (UI 표시용)

  // 💬 채팅 (낚시터와 동일한 global_chat / friends 공유)
  int _chatTab = 0; // 0 전체 / 1 귓속말 / 2 친구 / 3 길드
  String? _whisperTarget;
  final TextEditingController _chatCtrl = TextEditingController();
  final FocusNode _chatFocus = FocusNode(); // ⌨️ 채팅 입력 포커스(키보드 이동과 구분)
  final DateTime _joinTime = DateTime.now(); // 입장 이후 메시지만 표시

  // 🛡️ 길드 (users 문서 실시간 구독으로 가입 상태 추적)
  String _guildId = '';
  String _guildName = '';
  StreamSubscription<DocumentSnapshot>? _userSub;

  // 🏆 주간 길드 리그 (1위 길드 챔피언 → 머리 위 👑 + 추가 버프)
  bool _isChampionGuild = false;
  String _champGuildId = '';
  String _champWeek = '';
  StreamSubscription<DocumentSnapshot>? _leagueSub;

  // 🧍 시설 NPC 인사말 오버레이 (클릭 → 전체화면 인사 → 입장하기)
  Map<String, dynamic>? _npcIntro; // {img, msg, label, onEnter}
  final Map<String, List<String>> _npcGreetings = {
    'rank': [
      '안녕하세요! 명예의 전당에 오신 걸 환영해요 🏆',
      '오늘의 최고 조사는 누구일까요?',
      '당신의 순위, 궁금하지 않으세요?',
    ],
    'guild': [
      '길드에 관심 있으신가요? 🛡️',
      '함께 낚시할 동료를 찾고 계신가요?',
      '좋은 길드는 큰 힘이 된답니다!',
    ],
    'fishing': [
      '어느 낚시터로 떠나볼까요? 🌀',
      '오늘은 어디서 손맛을 보실 건가요?',
      '포탈 너머에 명당이 기다려요!',
    ],
    'arena': [
      '실력을 겨뤄볼 준비 되셨나요? ⚔️',
      '대회에서 1등에 도전해보세요!',
      '긴장되시죠? 화이팅이에요!',
    ],
    'shop': [
      '필요한 장비 있으세요? 🏪',
      '싱싱한 미끼 많이 들어왔어요!',
      '구경만 하셔도 언제나 환영이에요~',
    ],
  };

  void _openNpcIntro(String img, String key, String label, VoidCallback onEnter) {
    final list = _npcGreetings[key] ?? ['안녕하세요!'];
    setState(() {
      _npcIntro = {
        'img': img,
        'msg': list[math.Random().nextInt(list.length)],
        'label': label,
        'onEnter': onEnter,
      };
    });
  }

  // 📋 일일 퀘스트 (아라 매니저) — 로비에서 광장으로 이전
  bool _showQuest = false;
  bool _gotDailyReward = false; // 오늘 첫 접속 500P 지급됨
  bool _questDone = false; // #11 오늘 일일 퀘스트 완료(보상 수령)했는지
  String _rank = '초보'; // #13 승급 칭호(퀘스트 통과 결과)
  Map<String, int> _daejangCatch = {}; // #13 6대장 누적 카운트
  final List<Map<String, dynamic>> _missionPool = [
    {'loc': '예산 예당지', 'fish': '붕어', 'count': 3},
    {'loc': '예산 예당지', 'fish': '떡붕어', 'count': 3},
    {'loc': '예산 예당지', 'fish': '블루길', 'count': 3},
    {'loc': '예산 예당지', 'fish': '살치', 'count': 3},
    {'loc': '예산 예당지', 'fish': '베스', 'count': 3},
    {'loc': '예산 예당지', 'fish': '잉어', 'count': 3},
    {'loc': '예산 예당지', 'fish': '메기', 'count': 3},
    {'loc': '예산 신양수로', 'fish': '붕어', 'count': 3},
    {'loc': '예산 신양수로', 'fish': '떡붕어', 'count': 3},
    {'loc': '예산 신양수로', 'fish': '베스', 'count': 3},
    {'loc': '예산 신양수로', 'fish': '잉어', 'count': 3},
    {'loc': '예산 신양수로', 'fish': '메기', 'count': 3},
    {'loc': '예산 신양수로', 'fish': '가물치', 'count': 3},
    {'loc': '통영 척포 갯바위', 'fish': '고등어', 'count': 3},
    {'loc': '통영 척포 갯바위', 'fish': '우럭', 'count': 3},
    {'loc': '통영 척포 갯바위', 'fish': '갈치', 'count': 3},
    {'loc': '통영 척포 갯바위', 'fish': '참돔', 'count': 3},
    {'loc': '통영 척포 갯바위', 'fish': '광어', 'count': 3},
    {'loc': '통영 척포 갯바위', 'fish': '감성돔', 'count': 3},
    {'loc': '통영 척포 갯바위', 'fish': '갑오징어', 'count': 3},
    {'loc': '통영 척포 갯바위', 'fish': '주꾸미', 'count': 3},
    {'loc': '통영 척포 갯바위', 'fish': '문어', 'count': 3},
    {'loc': '거제 선상', 'fish': '고등어', 'count': 3},
    {'loc': '거제 선상', 'fish': '우럭', 'count': 3},
    {'loc': '거제 선상', 'fish': '갈치', 'count': 3},
    {'loc': '거제 선상', 'fish': '참돔', 'count': 3},
    {'loc': '거제 선상', 'fish': '광어', 'count': 3},
    {'loc': '거제 선상', 'fish': '감성돔', 'count': 3},
    {'loc': '거제 선상', 'fish': '갑오징어', 'count': 3},
    {'loc': '거제 선상', 'fish': '주꾸미', 'count': 3},
    {'loc': '거제 선상', 'fish': '문어', 'count': 3},
  ];

  Map<String, dynamic> _getTodayMission() {
    final now = DateTime.now();
    final seed = now.year * 10000 + now.month * 100 + now.day;
    return _missionPool[math.Random(seed).nextInt(_missionPool.length)];
  }

  String _getBriefingText() {
    final mission = _getTodayMission();
    final currentHour = DateTime.now().hour;
    String greeting = '안녕하세요! 😊';
    if (currentHour >= 5 && currentHour < 12) {
      greeting = '좋은 아침이에요! ☀️';
    } else if (currentHour >= 12 && currentHour < 18) {
      greeting = '안녕하세요! ☕';
    } else {
      greeting = '밤낚시 오셨군요! 🌙';
    }
    // #11 오늘 미션 완료했으면 완료 메시지
    if (_questDone) {
      return '$greeting\n'
          '🎉 오늘 일일 퀘스트 완료!\n'
          '🐟 ${mission['fish']} ${mission['count']}마리 달성\n'
          '💰 보상 500P 수령 완료! 내일도 도전해요!';
    }
    // 🧩 개인별 일일 퀘스트: 어느 낚시터든 해당 고기만 잡으면 OK (장소 무관)
    return '$greeting\n'
        '🏆 오늘의 일일 퀘스트!\n'
        '🐟 ${mission['fish']} ${mission['count']}마리 잡기\n'
        '🎣 어느 낚시터든 OK!\n'
        '✅ 오늘 안에 완료하면 500P 지급!';
  }

  // 💬 말풍선 (전체 채팅을 캐릭터 머리 위에 잠깐 표시)
  final Map<String, String> _bubbleMsg = {};
  final Map<String, DateTime> _bubbleUntil = {};
  final Map<String, int> _lastMsgT = {};
  String? _myBubble;
  DateTime? _myBubbleUntil;
  Timer? _bubbleTimer;
  Timer? _heartbeatTimer; // 💓 presence/접속상태 주기적 재기록(자가복구)

  @override
  void initState() {
    super.initState();
    _level = widget.level;
    _walkCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 340));
    _loadUser();
    _playPlazaBgm(); // 🎵 광장 배경음악 (옛 로비 BGM)
    HardwareKeyboard.instance.addHandler(_onHwKey); // ⌨️ PC 키보드(WASD/화살표) 이동
  }

  // ⌨️ PC 키보드 이동 (WASD + 화살표). 채팅 입력 중엔 무시.
  final Set<LogicalKeyboardKey> _pressedKeys = {};
  bool _onHwKey(KeyEvent e) {
    // 채팅/다이얼로그 등 텍스트 입력 중이면 이동 안 함(타이핑 우선)
    if (_chatFocus.hasFocus) return false;
    // 다이얼로그 등 다른 텍스트필드 입력 중이면 이동 안 함
    final pf = FocusManager.instance.primaryFocus;
    bool editing = pf?.context?.widget is EditableText;
    pf?.context?.visitAncestorElements((el) {
      if (el.widget is EditableText) { editing = true; return false; }
      return true;
    });
    if (editing) return false;
    final moveKeys = <LogicalKeyboardKey>{
      LogicalKeyboardKey.keyW, LogicalKeyboardKey.keyA, LogicalKeyboardKey.keyS, LogicalKeyboardKey.keyD,
      LogicalKeyboardKey.arrowUp, LogicalKeyboardKey.arrowDown, LogicalKeyboardKey.arrowLeft, LogicalKeyboardKey.arrowRight,
    };
    if (!moveKeys.contains(e.logicalKey)) return false;
    if (e is KeyDownEvent || e is KeyRepeatEvent) {
      _pressedKeys.add(e.logicalKey);
    } else if (e is KeyUpEvent) {
      _pressedKeys.remove(e.logicalKey);
    }
    _applyKeyboardMove();
    return true; // 방향키 페이지 스크롤 방지
  }

  void _applyKeyboardMove() {
    bool down(LogicalKeyboardKey a, LogicalKeyboardKey b) =>
        _pressedKeys.contains(a) || _pressedKeys.contains(b);
    double dx = 0, dy = 0;
    if (down(LogicalKeyboardKey.keyA, LogicalKeyboardKey.arrowLeft)) dx -= 1;
    if (down(LogicalKeyboardKey.keyD, LogicalKeyboardKey.arrowRight)) dx += 1;
    if (down(LogicalKeyboardKey.keyW, LogicalKeyboardKey.arrowUp)) dy -= 1;
    if (down(LogicalKeyboardKey.keyS, LogicalKeyboardKey.arrowDown)) dy += 1;
    if (dx == 0 && dy == 0) {
      _joyTimer?.cancel();
      _joyTimer = null;
      if (mounted) setState(() { _joyDir = Offset.zero; _walking = false; });
      _walkCtrl.stop();
      _walkCtrl.value = 0;
      _sendPos();
      return;
    }
    var dir = Offset(dx, dy);
    if (dir.distance > 1) dir = dir / dir.distance; // 대각선 정규화
    if (mounted) setState(() => _joyDir = dir);
    _moveToken++;
    if (!_walkCtrl.isAnimating) _walkCtrl.repeat();
    _joyTimer ??= Timer.periodic(const Duration(milliseconds: 16), (_) => _joyTick());
  }

  // 🎵 광장 배경음악 (낚시/아레나 다녀오면 다시 재생)
  void _playPlazaBgm() {
    audioManager.playBgm('bgm_menu.mp3');
  }

  // 🖥️ 전체화면 토글 (낚시 화면과 동일)
  void _toggleFullScreen() {
    try {
      if (html.document.fullscreenElement == null) {
        html.document.documentElement?.requestFullscreen().then((_) {
          html.window.screen?.orientation?.lock('landscape');
        }).catchError((Object e) {
          debugPrint('가로 고정 실패: $e');
        });
      } else {
        html.document.exitFullscreen();
        html.window.screen?.orientation?.unlock();
      }
    } catch (e) {
      debugPrint('전체화면 전환 실패: $e');
    }
  }

  // 상단 미니 버튼 (소리/전체화면)
  Widget _miniBtn(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.7),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _kGold, width: 1.5),
          boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 4)],
        ),
        child: Icon(icon, color: _kGold, size: 24),
      ),
    );
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onHwKey); // ⌨️ 키보드 핸들러 해제
    _walkCtrl.dispose();
    _joyTimer?.cancel();
    for (final s in _presenceSubs) {
      s.cancel();
    }
    _presenceSubs.clear();
    _userSub?.cancel();
    _leagueSub?.cancel();
    _myRef?.remove();
    _chatCtrl.dispose();
    _chatFocus.dispose();
    _bubbleTimer?.cancel();
    _heartbeatTimer?.cancel();
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
      // 💰 매일 첫 접속 500P 보상 (로비에서 광장으로 이전)
      final today = DateTime.now().toIso8601String().substring(0, 10);
      if ((data['lastLoginDate'] ?? '').toString() != today) {
        await doc.reference.set(
            {'gold': FieldValue.increment(500), 'lastLoginDate': today},
            SetOptions(merge: true));
        _gold += 500;
        currentPoints = _gold;
        _gotDailyReward = true;
      }
      // 🛡️ 길드원 목록에 저장된 내 레벨 최신화 (가입 때 박제된 옛 레벨 갱신)
      final gidForLevel = (data['guildId'] ?? '').toString();
      if (gidForLevel.isNotEmpty) {
        FirebaseFirestore.instance
            .collection('guilds')
            .doc(gidForLevel)
            .collection('members')
            .doc(user.uid)
            .set({'level': _level, 'nickname': widget.nickname}, SetOptions(merge: true))
            .catchError((Object e) => debugPrint('🛡️ 길드원 레벨 갱신 실패: $e'));
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
    // 🎁 첫 접속 보상 안내 + 일일 퀘스트 자동 안내
    if (_gotDailyReward) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _toast('🎁 오늘 첫 접속 보상 500P 지급!');
      });
    }
    _initPresence();
    // 🛡️ 길드 가입 상태 실시간 추적
    _userSub = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .snapshots()
        .listen((doc) {
      final d = doc.data() ?? {};
      if (!mounted) return;
      final gid = (d['guildId'] ?? '').toString();
      final gname = (d['guildName'] ?? '').toString();
      // 💰 #10/#12: 포인트·경험치·레벨·인벤토리 실시간 반영 (구매/판매/획득 즉시)
      final newGold = (d['gold'] ?? 0) is num ? (d['gold'] as num).toInt() : 0;
      final newExp = (d['exp'] ?? 0) is num ? (d['exp'] as num).toInt() : 0;
      final newLevel = calcLevelFromExp(newExp);
      final levelChanged = newLevel != _level;
      final guildChanged = gid != _guildId || gname != _guildName;
      // #11 오늘 일일 퀘스트 완료 여부
      final today = DateTime.now().toIso8601String().substring(0, 10);
      final mp = d['mission_progress'];
      final questDone = mp is Map && mp['date'] == today && mp['rewarded'] == true;
      // 🎖️ #13 승급: 저장된 칭호 + 6대장 누적
      final newRank = (d['rank'] ?? '초보').toString();
      final dc = <String, int>{};
      if (d['daejangCatch'] is Map) {
        (d['daejangCatch'] as Map).forEach((k, v) {
          dc[k.toString()] = (v is num) ? v.toInt() : 0;
        });
      }
      setState(() {
        _gold = newGold;
        currentPoints = newGold;
        currentExp = newExp;
        _level = newLevel;
        _questDone = questDone;
        _rank = newRank;
        _daejangCatch = dc;
        _inventory = (d['inventory'] ?? []) as List<dynamic>;
        if (guildChanged) {
          _guildId = gid;
          _guildName = gname;
          if (gid.isEmpty && _chatTab == 3) _chatTab = 0;
        }
      });
      // 🛡️ #1: 레벨 바뀌면 길드원 목록의 내 레벨도 즉시 갱신
      if (levelChanged && _guildId.isNotEmpty) {
        FirebaseFirestore.instance
            .collection('guilds').doc(_guildId).collection('members').doc(user.uid)
            .set({'level': newLevel, 'nickname': widget.nickname}, SetOptions(merge: true))
            .catchError((Object e) => debugPrint('🛡️ 길드원 레벨 갱신 실패: $e'));
      }
      if (guildChanged) {
        _recomputeChampion();
        _writeMe();
      }
    });
    // 🏆 주간 길드 리그: 주차 넘어갔으면 정산 + 챔피언 상태 구독
    _settleLeagueIfNeeded();
    _leagueSub = FirebaseFirestore.instance
        .collection('guild_league')
        .doc('state')
        .snapshots()
        .listen((doc) {
      _champGuildId = (doc.data()?['championGuildId'] ?? '').toString();
      _champWeek = (doc.data()?['activeWeek'] ?? '').toString();
      _recomputeChampion();
    });
  }

  void _recomputeChampion() {
    final isChamp = _guildId.isNotEmpty &&
        _champGuildId == _guildId &&
        _champWeek == FishingLogic.weekKey(DateTime.now());
    if (isChamp != _isChampionGuild) {
      if (mounted) setState(() => _isChampionGuild = isChamp);
      _writeMe(); // 👑 머리 위 왕관 갱신
    }
  }

  // 🏆 주차가 바뀌었으면 지난주 1위 길드를 챔피언으로 확정 (서버 크론 없이 클라가 지연 정산)
  Future<void> _settleLeagueIfNeeded() async {
    final fs = FirebaseFirestore.instance;
    final cur = FishingLogic.weekKey(DateTime.now());
    final stateRef = fs.collection('guild_league').doc('state');
    try {
      final snap = await stateRef.get();
      final activeWeek = (snap.data()?['activeWeek'] ?? '').toString();
      if (activeWeek == cur) return; // 이미 이번 주
      String champId = '', champName = '';
      if (activeWeek.isNotEmpty) {
        // 지난주(activeWeek) 최고 점수 길드 = 챔피언
        final q = await fs
            .collection('guilds')
            .orderBy('weeklyScore', descending: true)
            .limit(10)
            .get();
        for (final d in q.docs) {
          final dd = d.data();
          final ws = (dd['weeklyScore'] is num) ? (dd['weeklyScore'] as num).toInt() : 0;
          if ((dd['weekKey'] ?? '') == activeWeek && ws > 0) {
            champId = d.id;
            champName = (dd['name'] ?? '').toString();
            break;
          }
        }
      }
      await fs.runTransaction((tx) async {
        final s = await tx.get(stateRef);
        if ((s.data()?['activeWeek'] ?? '') == cur) return; // 다른 클라가 먼저 정산함
        tx.set(stateRef, {
          'activeWeek': cur,
          'championGuildId': champId,
          'championGuildName': champName,
          'championWeek': cur,
          'settledAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      });
    } catch (e) {
      debugPrint('🏆 길드 리그 정산 실패: $e');
    }
  }

  // 🧩 정원 안 찬 채널을 찾아 배정(없으면 새 채널). 평소엔 ch1.
  //    멤버는 onDisconnect로 자동 제거되므로 자식 수가 곧 실시간 인원 → 별도 카운터 불필요(드리프트 없음).
  Future<String> _pickChannel(String mode, String uid) async {
    try {
      final snap = await _db.ref('plaza/$mode').get();
      final val = snap.value;
      if (val is Map) {
        for (int n = 1; n <= 100000; n++) {
          final ch = val['ch$n'];
          if (ch is! Map) {
            _channelNum = n;
            return '$mode/ch$n';
          }
          if (ch.containsKey(uid)) {
            _channelNum = n;
            return '$mode/ch$n'; // 재접속이면 같은 채널 유지
          }
          if (ch.length < _plazaChannelCap) {
            _channelNum = n;
            return '$mode/ch$n';
          }
        }
      }
    } catch (e) {
      debugPrint('🌐 채널 선택 실패(ch1 기본): $e');
    }
    _channelNum = 1;
    return '$mode/ch1';
  }

  // 🌐 실시간 접속/위치 송수신
  Future<void> _initPresence() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final uid = user.uid;
    // 🧩 채널 배정 (정원 차면 자동 분할)
    _channelKey = await _pickChannel(_roomKey, uid);
    if (!mounted) return;
    setState(() {}); // 채널 표시 갱신
    _myRef = _db.ref('plaza/$_channelKey/$uid');
    _myRef!.onDisconnect().remove().catchError((Object e) => debugPrint('🌐 RTDB onDisconnect ERR: $e')); // 접속 끊기면 자동 사라짐
    guildGoOnline(); // 🟢 전역 접속표시
    _writeMe();
    // 말풍선 만료 처리용 1초 타이머
    _bubbleTimer ??= Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    // 💓 하트비트: 닉/이미지/접속상태를 12초마다 재기록 → 닉 누락("조사")·미표시·접속불 깜빡임 자가복구
    _heartbeatTimer ??= Timer.periodic(const Duration(seconds: 12), (_) {
      if (!mounted) return;
      _writeMe(); // presence 전체(닉·이미지·길드·위치) 재기록
      guildGoOnline(); // 접속 초록불 재확인
    });
    // 🧩 채널 단위 구독(onValue). 채널당 정원 50이라 페이로드는 항상 한정(샤딩 효과).
    //    ※ child 이벤트 방식은 멀티 표시 이슈가 있어 검증된 onValue로 복구.
    final ref = _db.ref('plaza/$_channelKey');
    _presenceSubs.add(ref.onValue.listen((event) {
      final val = event.snapshot.value;
      final next = <String, Map<String, dynamic>>{};
      if (val is Map) {
        val.forEach((k, v) {
          if (k.toString() == uid || v is! Map) return; // 나 제외
          final kk = k.toString();
          next[kk] = {
            'nick': v['nick']?.toString() ?? '조사',
            'img': v['img']?.toString() ?? 'assets/images/char_beginner.png',
            'guild': v['guild']?.toString() ?? '',
            'champ': v['champ'] == true,
            'x': (v['x'] is num) ? (v['x'] as num).toDouble() : 0.5,
            'y': (v['y'] is num) ? (v['y'] as num).toDouble() : 0.8,
            'face': v['face'] == true,
            't': (v['t'] is num) ? (v['t'] as num).toInt() : 0, // 마지막 갱신 시각(고스트 필터용)
          };
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
      if (mounted) {
        setState(() {
          _others
            ..clear()
            ..addAll(next);
        });
      }
    }, onError: (Object e) => debugPrint('🌐 RTDB READ ERR: $e')));
  }

  void _writeMe() {
    _myRef?.set({
      'nick': widget.nickname,
      'img': _charImage,
      'guild': _guildName,
      'champ': _isChampionGuild,
      'x': _charPos.dx,
      'y': _charPos.dy,
      'face': _facingRight,
      't': ServerValue.timestamp,
    }).catchError((Object e) {
      debugPrint('🌐 RTDB WRITE ERR: $e');
    });
  }

  // 🌐 다른 유저 캐릭터 (실시간 위치로 부드럽게 이동)
  Widget _remoteAvatar(String uid, Map<String, dynamic> d, double worldW, double worldH, double sizeH) {
    final dx = (d['x'] as double).clamp(0.02, 0.98);
    final dy = (d['y'] as double).clamp(0.0, 1.0);
    final pT = ((dy - 0.22) / (0.96 - 0.22)).clamp(0.0, 1.0);
    final rH = sizeH * (0.18 + pT * 0.16);
    final rW = rH * 0.55;
    final face = d['face'] == true;
    return AnimatedPositioned(
      key: ValueKey('remote_$uid'),
      duration: const Duration(milliseconds: 650),
      curve: Curves.linear,
      left: dx * worldW - rW / 2,
      top: dy * worldH - rH,
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
                child: _nameTag(d['nick'] as String, (d['guild'] ?? '') as String,
                    champ: d['champ'] == true),
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

  // 🚶 4방향 걷기 스프라이트 경로 (예: char_beginner_up1.png).
  //    이미지 없으면 build의 errorBuilder가 기본 _charImage로 폴백.
  String get _charSprite {
    final base = _charImage.replaceAll('.png', ''); // assets/images/char_beginner
    final frame = _walking ? (_walkCtrl.value < 0.5 ? 1 : 2) : 0; // 걷기A/B, 멈추면 서있기
    return '${base}_$_moveDir$frame.png';
  }

  // 🗺️ 카메라/월드: 큰 광장 그림(3296x1700)을 두고 카메라가 캐릭터를 따라 스크롤
  static const double _imgAspect = 3296 / 1700; // 월드 가로:세로 비율
  static const double _baseFrac = 0.72; // 기본 줌(=캐릭터/NPC 크기 기준). 화면이 보여주는 월드 세로 비율
  double _zoomScale = 1.0; // 🔍 줌 배율 (1.0=기본 와이드 ~ 2.6=확대). Transform.scale 중앙 확대
  double _zoomStartScale = 1.0; // 핀치 시작 배율
  static const bool _devCoords = false; // 🔧 좌표 수집 모드(걷기제한 해제+탭좌표 표시). 좌표 받으면 false
  Offset? _lastTapWorld;

  // 🗺️ 걷기 구역(섬 경계) 다각형 — 사용자 탭 좌표(시계방향 한 바퀴). 바다·민물 동일 구도라 공유.
  static const List<Offset> _freshPoly = [
    Offset(0.007, 0.387), Offset(0.090, 0.364), Offset(0.094, 0.419), Offset(0.130, 0.432),
    Offset(0.182, 0.413), Offset(0.180, 0.336), Offset(0.210, 0.321), Offset(0.251, 0.372),
    Offset(0.349, 0.383), Offset(0.297, 0.399), Offset(0.238, 0.430), Offset(0.264, 0.527),
    Offset(0.294, 0.521), Offset(0.379, 0.470), Offset(0.431, 0.440), Offset(0.460, 0.466),
    Offset(0.573, 0.487), Offset(0.624, 0.535), Offset(0.666, 0.535), Offset(0.750, 0.585),
    Offset(0.806, 0.541), Offset(0.819, 0.562), Offset(0.870, 0.589), Offset(0.906, 0.595),
    Offset(0.864, 0.713), Offset(0.776, 0.857), Offset(0.879, 0.996), Offset(0.782, 0.998),
    Offset(0.741, 0.945), Offset(0.735, 0.997), Offset(0.631, 0.998), Offset(0.556, 0.820),
    Offset(0.523, 0.836), Offset(0.473, 0.921), Offset(0.329, 0.911), Offset(0.208, 0.861),
    Offset(0.003, 0.826), Offset(0.009, 0.775), Offset(0.057, 0.767), Offset(0.148, 0.773),
    Offset(0.150, 0.780), Offset(0.156, 0.662), Offset(0.218, 0.571), Offset(0.202, 0.532),
    Offset(0.188, 0.427), Offset(0.083, 0.489), Offset(0.068, 0.429), Offset(0.038, 0.401),
  ];
  static const List<Offset> _seaPoly = _freshPoly; // 동일 구도 — 다르면 바다 좌표 따로 받아 교체
  List<Offset> get _activePoly => widget.isSea ? _seaPoly : _freshPoly;

  // 🚫 못 가는 구역(화단·구조물) — 바깥 폴리곤 안에서도 여기 안이면 못 감
  static const List<List<Offset>> _freshObstacles = [
    // 화단1
    [Offset(0.347, 0.641), Offset(0.401, 0.553), Offset(0.432, 0.496), Offset(0.438, 0.530),
     Offset(0.504, 0.532), Offset(0.496, 0.592), Offset(0.444, 0.599), Offset(0.418, 0.646)],
    // 화단2
    [Offset(0.450, 0.742), Offset(0.448, 0.660), Offset(0.517, 0.645), Offset(0.527, 0.561),
     Offset(0.554, 0.601), Offset(0.593, 0.613), Offset(0.575, 0.699)],
    // 화단3
    [Offset(0.729, 0.746), Offset(0.741, 0.674), Offset(0.780, 0.667), Offset(0.790, 0.621),
     Offset(0.804, 0.613), Offset(0.818, 0.677), Offset(0.841, 0.696), Offset(0.763, 0.781)],
    // 상점앞 포탈
    [Offset(0.703, 0.826), Offset(0.697, 0.651), Offset(0.670, 0.636), Offset(0.642, 0.702),
     Offset(0.637, 0.809), Offset(0.635, 0.852), Offset(0.664, 0.876)],
    // 퀘스트 용지
    [Offset(0.295, 0.699), Offset(0.277, 0.554), Offset(0.239, 0.557), Offset(0.239, 0.723)],
  ];
  static const List<List<Offset>> _seaObstacles = _freshObstacles;
  List<List<Offset>> get _activeObstacles => widget.isSea ? _seaObstacles : _freshObstacles;

  // 점이 다각형 안인지 (ray casting)
  bool _inPolyOf(Offset p, List<Offset> poly) {
    bool inside = false;
    for (int i = 0, j = poly.length - 1; i < poly.length; j = i++) {
      final pi = poly[i], pj = poly[j];
      if (((pi.dy > p.dy) != (pj.dy > p.dy)) &&
          (p.dx < (pj.dx - pi.dx) * (p.dy - pi.dy) / (pj.dy - pi.dy) + pi.dx)) {
        inside = !inside;
      }
    }
    return inside;
  }

  bool _inPoly(Offset p) => _inPolyOf(p, _activePoly);

  // 걸을 수 있는 곳 = 바깥 폴리곤 안 + 모든 장애물 밖
  bool _inWalkable(Offset p) {
    if (!_inPoly(p)) return false;
    for (final o in _activeObstacles) {
      if (_inPolyOf(p, o)) return false;
    }
    return true;
  }

  Offset _nearestOnSeg(Offset p, Offset a, Offset b) {
    final dx = b.dx - a.dx, dy = b.dy - a.dy;
    final len2 = dx * dx + dy * dy;
    double t = len2 == 0 ? 0 : ((p.dx - a.dx) * dx + (p.dy - a.dy) * dy) / len2;
    t = t.clamp(0.0, 1.0);
    return Offset(a.dx + t * dx, a.dy + t * dy);
  }

  // 걸을 수 있으면 그대로, 아니면 가장 가까운 경계(바깥+장애물)로 보정
  Offset _clampToPlaza(Offset p) {
    if (_inWalkable(p)) return p;
    Offset best = p;
    double bestD = double.infinity;
    void consider(List<Offset> poly) {
      for (int i = 0, j = poly.length - 1; i < poly.length; j = i++) {
        final q = _nearestOnSeg(p, poly[j], poly[i]);
        final d = (q - p).distanceSquared;
        if (d < bestD) {
          bestD = d;
          best = q;
        }
      }
    }
    consider(_activePoly);
    for (final o in _activeObstacles) {
      consider(o);
    }
    // 경계선 위 점은 살짝 현재 위치 쪽으로 밀어 walkable 안으로
    final nudged = Offset(
        best.dx + (_charPos.dx - best.dx) * 0.04, best.dy + (_charPos.dy - best.dy) * 0.04);
    return _inWalkable(nudged) ? nudged : best;
  }

  void _moveTo(Offset rawTarget, double w, double h) {
    if (_devCoords) _lastTapWorld = rawTarget; // 🔧 좌표 수집
    final dest = _devCoords ? rawTarget : _clampToPlaza(rawTarget); // 섬 안으로 보정(수집모드는 자유 이동)
    final dx = (dest.dx - _charPos.dx) * w;
    final dy = (dest.dy - _charPos.dy) * h;
    final dist = math.sqrt(dx * dx + dy * dy);
    final ms = (dist / 0.16).clamp(700, 4400).toInt(); // 걷기 속도(절반으로 느리게)
    final moveDur = Duration(milliseconds: ms);
    setState(() {
      // 🚶 이동 방향 → 스프라이트 방향 (가로 우세=옆, 세로=위/아래)
      if (dx.abs() >= dy.abs()) {
        _moveDir = 'side';
        _facingRight = dx >= 0;
      } else {
        _moveDir = dy < 0 ? 'up' : 'down';
      }
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

  // 🕹️ 조이스틱 ---------------------------------------------------------
  void _joyMove(Offset fromCenter) {
    var v = fromCenter;
    final len = v.distance;
    if (len > _joyRadius) v = v / len * _joyRadius; // 베이스 밖으로 안 나가게
    setState(() {
      _joyKnob = v;
      _joyDir = v / _joyRadius; // 길이 0~1 (방향+세기)
    });
  }

  void _joyStart(Offset fromCenter) {
    _joyMove(fromCenter);
    _moveToken++; // 진행 중이던 탭 이동 종료
    if (!_walkCtrl.isAnimating) _walkCtrl.repeat();
    _joyTimer ??= Timer.periodic(const Duration(milliseconds: 16), (_) => _joyTick());
  }

  void _joyEnd() {
    _joyTimer?.cancel();
    _joyTimer = null;
    setState(() {
      _joyKnob = Offset.zero;
      _joyDir = Offset.zero;
      _walking = false;
    });
    _walkCtrl.stop();
    _walkCtrl.value = 0;
    _sendPos(); // 멈춘 위치 전송
  }

  void _joyTick() {
    if (_joyDir == Offset.zero || !mounted) return;
    const speedPxPerSec = 160.0; // 월드 스크린px 기준 이동 속도(절반으로 느리게)
    const dt = 16 / 1000.0;
    final movePx = _joyDir * speedPxPerSec * dt; // 방향*세기
    var np = Offset(
      _charPos.dx + movePx.dx / _worldW,
      _charPos.dy + movePx.dy / _worldH,
    );
    np = Offset(np.dx.clamp(0.0, 1.0), np.dy.clamp(0.0, 1.0));
    if (!_devCoords) np = _clampToPlaza(np); // 정식 모드에선 걷기 영역 안으로
    setState(() {
      // 🚶 조이스틱 방향 → 스프라이트 방향 (가로 우세=옆, 세로=위/아래). 데드존으로 깜빡임 방지
      if (_joyDir.dx.abs() >= _joyDir.dy.abs()) {
        if (_joyDir.dx.abs() > 0.2) {
          _moveDir = 'side';
          _facingRight = _joyDir.dx >= 0;
        }
      } else {
        _moveDir = _joyDir.dy < 0 ? 'up' : 'down';
      }
      _charPos = np;
      _moveDuration = Duration.zero; // 보간 끔 → 캐릭터·카메라(배경) 같은 프레임에 이동(싱크)
      _walking = true;
    });
    final now = DateTime.now();
    if (now.difference(_lastNetSend).inMilliseconds > 120) {
      _lastNetSend = now;
      _sendPos();
    }
  }

  void _sendPos() {
    _myRef?.update({'x': _charPos.dx, 'y': _charPos.dy, 'face': _facingRight}).catchError(
        (Object e) => debugPrint('🌐 RTDB UPDATE ERR: $e'));
  }

  // 🔍 줌 (작을수록 확대). 휠마다 즉시 조금씩 — 애니메이션 출렁임 없음
  void _zoom(double delta) {
    setState(() => _zoomScale = (_zoomScale + delta).clamp(1.0, 2.6));
  }

  Widget _joystick() {
    return Positioned(
      right: 70,
      bottom: 110, // 모바일 엄지로 조작하기 편하게 구석에서 안쪽·위로

      child: GestureDetector(
        onPanDown: (d) => _joyStart(d.localPosition - const Offset(_joyRadius, _joyRadius)),
        onPanUpdate: (d) => _joyMove(d.localPosition - const Offset(_joyRadius, _joyRadius)),
        onPanEnd: (_) => _joyEnd(),
        onPanCancel: _joyEnd,
        child: Container(
          width: _joyRadius * 2,
          height: _joyRadius * 2,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.black.withOpacity(0.32),
            border: Border.all(color: _kGold.withOpacity(0.55), width: 2),
          ),
          child: Center(
            child: Transform.translate(
              offset: _joyKnob,
              child: Container(
                width: _joyRadius,
                height: _joyRadius,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _kGold.withOpacity(0.85),
                  boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 6)],
                ),
                child: const Icon(Icons.open_with, color: Colors.black54, size: 24),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ---- 진입 액션들 (기존 화면 재활용) ----
  // loc/sea를 주면 그 낚시터로 바로 출조, 없으면 현재 광장 spot
  void _goFishing({Map<String, dynamic>? loc, bool? sea}) {
    final spot = loc ?? widget.spot;
    final isSea = sea ?? widget.isSea;
    globalIsSeaMode = isSea;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FishingScreen(
          nickname: widget.nickname,
          locationName: spot['name'],
          winCondition: '마릿수',
          title: spot['name'],
          bgImagePath: spot['image'],
          characterImagePath: 'assets/images/character.png',
          isSea: isSea,
          isFirstTime: widget.isFirstTime,
        ),
      ),
    ).then((_) {
      if (mounted) _playPlazaBgm(); // 🎵 낚시터에서 돌아오면 광장 BGM 재개
    });
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
    Navigator.push(context, MaterialPageRoute(builder: (_) => const ArenaScreen()))
        .then((_) {
      if (mounted) _playPlazaBgm(); // 🎵 아레나(낚시 BGM) 다녀오면 광장 BGM 재개
    });
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
                                ? const Text('🎣 출조',
                                    style: TextStyle(color: _kGold, fontWeight: FontWeight.bold))
                                : const Icon(Icons.arrow_forward_ios, color: Colors.white38, size: 16),
                            // 🎣 리스트에서 낚시터 클릭 = 그 낚시터로 바로 출조 (광장 거치지 않음)
                            onTap: () {
                              Navigator.pop(ctx);
                              _goFishing(loc: s, sea: isMainSea);
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
      'channel': _channelKey ?? '', // 🧩 전체 채팅은 같은 채널끼리만
      'timestamp': FieldValue.serverTimestamp(),
    });
    // 💬 전체 채팅(탭0)만 머리 위 말풍선 — 귓속말/길드챗/친구는 말풍선 X
    if (_chatTab == 0) {
      _myRef?.update({'msg': text, 'msgT': ServerValue.timestamp})
          .catchError((Object e) => debugPrint('🌐 RTDB MSG ERR: $e'));
      setState(() {
        _myBubble = text;
        _myBubbleUntil = DateTime.now().add(const Duration(seconds: 5));
      });
    }
    _chatCtrl.clear();
  }

  // 🏷️ 머리 위 이름표 (길드명 + 닉네임, 챔피언이면 👑)
  Widget _nameTag(String nick, String guild, {bool isMe = false, bool champ = false}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (guild.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(bottom: 2),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: champ ? const Color(0xCC4A3A00) : const Color(0xCC123A52),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                  color: champ ? _kGold : const Color(0xFF7FD4FF), width: champ ? 1.0 : 0.8),
            ),
            child: Text(champ ? '👑〈$guild〉' : '〈$guild〉',
                maxLines: 1,
                style: TextStyle(
                    color: champ ? _kGold : const Color(0xFF9FE0FF),
                    fontSize: 10,
                    fontWeight: FontWeight.bold)),
          ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.6),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: isMe ? _kGold.withOpacity(0.7) : Colors.white24),
          ),
          child: Text(nick,
              maxLines: 1,
              style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
        ),
      ],
    );
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
          .where('timestamp', isGreaterThanOrEqualTo: _joinTime) // 입장 이후만 (재접속 시 클리어)
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
                              .limit(20)
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
                                  // 전체 탭: 귓속말은 아예 숨김 + 같은 채널 전체채팅만 (공지는 전 채널)
                                  if (type == 'whisper') return const SizedBox.shrink();
                                  if (type != 'notice' &&
                                      (d['channel'] ?? '') != (_channelKey ?? '')) {
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
                    focusNode: _chatFocus,
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
      body: Listener(
        onPointerSignal: (e) {
          if (e is PointerScrollEvent) {
            _zoom(e.scrollDelta.dy > 0 ? -0.18 : 0.18); // 휠 위=확대, 아래=축소
          }
        },
        child: LayoutBuilder(
        builder: (context, c) {
          final w = c.maxWidth;
          final h = c.maxHeight;
          // 🗺️ 월드 크기(스크린px): 기본 줌 고정. 줌은 Transform.scale로 중앙 확대(아래)
          final worldH = h / _baseFrac;
          final worldW = worldH * _imgAspect;
          _worldW = worldW; // 조이스틱 이동 환산용
          _worldH = worldH;
          final sizeRef = h; // 캐릭터/NPC 기본 크기(줌은 Transform.scale로)
          // 🏞️ 원근감: 위(멀리)로 갈수록 작게, 아래(가까이)로 올수록 크게
          final perspT = ((_charPos.dy - 0.22) / (0.96 - 0.22)).clamp(0.0, 1.0);
          final charH = sizeRef * (0.13 + perspT * 0.115); // 줄임(꽉찬 캔버스 스프라이트라 작게)
          final charW = charH * 0.55;
          // 📷 카메라: 캐릭터 중심, 맵 가장자리에서 멈춤(검은 영역 안 보이게)
          final maxCamX = (worldW - w) > 0 ? (worldW - w) : 0.0;
          final maxCamY = (worldH - h) > 0 ? (worldH - h) : 0.0;
          final camX = (_charPos.dx * worldW - w / 2).clamp(0.0, maxCamX);
          final camY = (_charPos.dy * worldH - h / 2).clamp(0.0, maxCamY);

          return Stack(
            children: [
              // 🌍 월드 레이어 — 카메라(클램프)로 캐릭터 따라가고, 줌은 Transform.scale로 화면 중앙 확대
              Positioned.fill(
                child: ClipRect(
                  child: Transform.scale(
                    scale: _zoomScale,
                    child: SizedBox.expand(
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
              Positioned(
                left: -camX,
                top: -camY,
                width: worldW,
                height: worldH,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                        // 배경(큰 광장 그림). 없으면 낚시 배경으로 폴백
                        Positioned.fill(
                          child: Image.asset(
                            _plazaBg,
                            fit: BoxFit.cover,
                            errorBuilder: (a, b, d) => Image.asset(
                              widget.spot['image'],
                              fit: BoxFit.cover,
                              errorBuilder: (a2, b2, d2) =>
                                  Container(color: const Color(0xFF11202E)),
                            ),
                          ),
                        ),
                        // 바닥 탭 → 캐릭터 이동 (월드 좌표) + 두 손가락 핀치 줌
                        Positioned.fill(
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTapUp: (d) => _moveTo(
                                Offset(d.localPosition.dx / worldW, d.localPosition.dy / worldH),
                                worldW, worldH),
                            onScaleStart: (_) => _zoomStartScale = _zoomScale,
                            onScaleUpdate: (d) {
                              if (d.pointerCount >= 2) {
                                final v = (_zoomStartScale * d.scale).clamp(1.0, 2.6);
                                setState(() => _zoomScale = v);
                              }
                            },
                          ),
                        ),
                        // 🔧 좌표 수집 마커
                        if (_devCoords && _lastTapWorld != null)
                          Positioned(
                            left: _lastTapWorld!.dx * worldW - 7,
                            top: _lastTapWorld!.dy * worldH - 7,
                            child: IgnorePointer(
                              child: Container(
                                width: 14,
                                height: 14,
                                decoration: BoxDecoration(
                                  color: Colors.redAccent,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.white, width: 2),
                                ),
                              ),
                            ),
                          ),
                        // 내 캐릭터 (탭 통과)
                        AnimatedPositioned(
                          duration: _moveDuration,
                          curve: Curves.linear,
                          left: _charPos.dx * worldW - charW / 2,
                          top: _charPos.dy * worldH - charH,
                          width: charW,
                          height: charH,
                          child: IgnorePointer(
                            child: AnimatedBuilder(
                              animation: _walkCtrl,
                              builder: (context, _) {
                                final phase = _walkCtrl.value * 2 * math.pi;
                                final bob = _walking ? math.sin(phase).abs() * 2.0 : 0.0;
                                // 옆모습일 때만 좌우반전(왼쪽). 앞/뒤는 반전 안 함
                                final flip = (_moveDir == 'side' && !_facingRight);
                                return Stack(
                                  clipBehavior: Clip.none,
                                  alignment: Alignment.bottomCenter,
                                  children: [
                                    Positioned.fill(
                                      child: Transform.translate(
                                        offset: Offset(0, -bob),
                                        child: Transform(
                                          alignment: Alignment.bottomCenter,
                                          transform: Matrix4.rotationY(flip ? math.pi : 0),
                                          child: Image.asset(
                                            _charSprite,
                                            fit: BoxFit.contain,
                                            alignment: Alignment.bottomCenter,
                                            // 방향 스프라이트 없으면 기본 이미지로 폴백
                                            errorBuilder: (a, b, d) => Image.asset(
                                              _charImage,
                                              fit: BoxFit.contain,
                                              alignment: Alignment.bottomCenter,
                                              errorBuilder: (a2, b2, d2) =>
                                                  const SizedBox.shrink(),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    Positioned(
                                      bottom: charH * 0.62, // 머리 위(스프라이트 상단 여백 고려)
                                      left: -150,
                                      right: -150,
                                      child: Center(
                                        child: _nameTag(widget.nickname, _guildName,
                                            isMe: true, champ: _isChampionGuild),
                                      ),
                                    ),
                                    if (_myBubble != null &&
                                        _myBubbleUntil != null &&
                                        DateTime.now().isBefore(_myBubbleUntil!))
                                      Positioned(
                                        bottom: charH * 0.80,
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
                        // 🌐 다른 유저들 (실시간) — 45초 이상 갱신 없는 고스트는 숨김(onDisconnect 누락 대비)
                        ..._others.entries
                            .where((e) =>
                                DateTime.now().millisecondsSinceEpoch -
                                    ((e.value['t'] as int?) ?? 0) <
                                45000)
                            .map((e) => _remoteAvatar(e.key, e.value, worldW, worldH, sizeRef)),
                        // 4) 시설 NPC (각 시설 앞에 한 명씩) — img 없으면 임시 fallback
                        _standNpc(worldW, worldH, sizeRef, widget.isSea ? 0.150 : 0.156,
                            widget.isSea ? 0.492 : 0.485, 'npc_rank.png', 'gm_garam.png', '🏆 랭킹',
                            () => _openNpcIntro('npc_rank.png', 'rank', '순위 보기', _openRanking),
                            scale: 0.9),
                        _standNpc(worldW, worldH, sizeRef, widget.isSea ? 0.396 : 0.407,
                            widget.isSea ? 0.551 : 0.550, 'npc_guild.png', 'npc_manager_congrats.png', '🛡️ 길드',
                            () => _openNpcIntro('npc_guild.png', 'guild', '길드 보기', _openGuild),
                            scale: 0.85),
                        _standNpc(worldW, worldH, sizeRef, widget.isSea ? 0.585 : 0.599,
                            widget.isSea ? 0.598 : 0.593, 'npc_fishing.png', 'npc_girl_intro.png', '🌀 낚시터',
                            () => _openNpcIntro('npc_fishing.png', 'fishing', '낚시터 이동', _openMinimap),
                            scale: 0.9),
                        _standNpc(worldW, worldH, sizeRef, widget.isSea ? 0.834 : 0.846,
                            widget.isSea ? 0.657 : 0.648, 'npc_arena.png', 'npc_girl_point.png', '⚔️ 아레나',
                            () => _openNpcIntro('npc_arena.png', 'arena', '대회 입장', _openArena),
                            scale: 0.82),
                        _standNpc(worldW, worldH, sizeRef, widget.isSea ? 0.809 : 0.809,
                            widget.isSea ? 0.945 : 0.945, 'npc_shop.png', 'npc_manager.png', '🏪 상점',
                            () => _openNpcIntro('npc_shop.png', 'shop', '상점 들어가기', _openStore),
                            scale: 1.1),
                        // 📋 일일퀘스트 매니저 '아라'
                        _araNpc(worldW, worldH, sizeRef),
                      ],
                    ),
              ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // 화면 고정 비네트(가장자리 어둡게)
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withOpacity(0.30),
                          Colors.black.withOpacity(0.10),
                          Colors.black.withOpacity(0.45),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // 5) 상단 HUD
              _topHud(),
              // 💬 채팅 패널
              _chatPanel(),

              // 🔧 운영자 전용: 스킨 미리보기 버튼
              if (_isOperator)
                Positioned(
                  left: 14,
                  top: 92,
                  child: GestureDetector(
                    onTap: _cycleSkinPreview,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.6),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: _kGold, width: 1.2),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.checkroom, color: _kGold, size: 16),
                        const SizedBox(width: 6),
                        Text('스킨 미리보기 (${_previewSkins[_skinPreviewIdx]})',
                            style: const TextStyle(
                                color: _kGold, fontSize: 12, fontWeight: FontWeight.bold)),
                      ]),
                    ),
                  ),
                ),

              // 🕹️ 가상 조이스틱 (우하단)
              _joystick(),

              // 🔧 좌표 수집 표시 (개발용 — 좌표 다 받으면 _devCoords=false)
              if (_devCoords)
                Positioned(
                  bottom: 150,
                  right: 14,
                  child: IgnorePointer(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.7),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.redAccent),
                      ),
                      child: Text(
                        _lastTapWorld == null
                            ? '🔧 좌표: 화면을 탭하세요'
                            : '🔧 Offset(${_lastTapWorld!.dx.toStringAsFixed(3)}, ${_lastTapWorld!.dy.toStringAsFixed(3)})',
                        style: const TextStyle(
                            color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ),

              // 📋 일일퀘스트 안내 오버레이 (아라)
              if (_showQuest)
                Positioned.fill(
                  child: NpcTutorialOverlay(
                    text: _getBriefingText(),
                    imagePath: 'assets/images/npc_manager_quest.png',
                    onTap: () => setState(() => _showQuest = false),
                    action: Row(mainAxisSize: MainAxisSize.min, children: [
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                            backgroundColor: _kGold, foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12)),
                        onPressed: () {
                          setState(() => _showQuest = false);
                          _openPromotion();
                        },
                        child: const Text('🎖️ 승급 퀘스트', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      ),
                      const SizedBox(width: 12),
                      TextButton(
                        onPressed: () => setState(() => _showQuest = false),
                        child: const Text('닫기', style: TextStyle(color: Colors.white70, fontSize: 16, fontWeight: FontWeight.bold)),
                      ),
                    ]),
                  ),
                ),

              // 🧍 시설 NPC 인사말 오버레이 (입장하기 버튼)
              if (_npcIntro != null)
                Positioned.fill(
                  child: NpcTutorialOverlay(
                    text: _npcIntro!['msg'] as String,
                    imagePath: 'assets/images/${_npcIntro!['img']}',
                    onTap: () => setState(() => _npcIntro = null),
                    action: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _kGold,
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                            textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                          ),
                          onPressed: () {
                            final f = _npcIntro!['onEnter'] as VoidCallback;
                            setState(() => _npcIntro = null);
                            f();
                          },
                          child: Text(_npcIntro!['label'] as String),
                        ),
                        const SizedBox(width: 12),
                        TextButton(
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.white70,
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                            textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                          onPressed: () => setState(() => _npcIntro = null),
                          child: const Text('닫기'),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
        ),
      ),
    );
  }

  // 📋 일일퀘스트 매니저 '아라' (클릭하면 오늘의 미션 안내) — 위치=월드, 크기=뷰포트
  Widget _araNpc(double worldW, double worldH, double sizeH) {
    final figH = sizeH * 0.21; // 캐릭터와 비슷한 크기
    final figW = figH * 0.6;
    const cx = 0.281;
    const cy = 0.837; // 발 위치 (민물·바다 동일 구도)
    return Positioned(
      left: cx * worldW - figW / 2,
      top: cy * worldH - figH - 26, // 라벨 높이만큼 위로 보정
      child: GestureDetector(
        onTap: () => setState(() => _showQuest = true),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.7),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _questDone ? const Color(0xFF7FFFB0) : _kGold),
                boxShadow: [BoxShadow(color: (_questDone ? const Color(0xFF7FFFB0) : _kGold).withOpacity(0.5), blurRadius: 8)],
              ),
              child: Text(_questDone ? '✅ 퀘스트 완료' : '📋 일일퀘스트',
                  style: TextStyle(color: _questDone ? const Color(0xFF7FFFB0) : _kGold, fontSize: 12, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 2),
            SizedBox(
              width: figW,
              height: figH,
              child: Image.asset('assets/images/npc_manager_quest.png',
                  fit: BoxFit.contain,
                  alignment: Alignment.topCenter,
                  errorBuilder: (a, b, c) => const SizedBox.shrink()),
            ),
          ],
        ),
      ),
    );
  }

  // 🧍 시설 NPC (포털/시설 앞에 한 명씩 세움). img 없으면 fallback 이미지로.
  Widget _standNpc(double worldW, double worldH, double sizeH, double cx, double cy,
      String img, String fallback, String label, VoidCallback onTap, {double scale = 1.0}) {
    final figH = sizeH * 0.21 * scale;
    final figW = figH * 0.6;
    return Positioned(
      left: cx * worldW - figW / 2,
      top: cy * worldH - figH - 26, // cy=발 위치, 라벨 높이 보정
      child: GestureDetector(
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.65),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _kGold),
                boxShadow: [BoxShadow(color: _kGold.withOpacity(0.4), blurRadius: 7)],
              ),
              child: Text(label,
                  style: const TextStyle(color: _kGold, fontSize: 12, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 2),
            SizedBox(
              width: figW,
              height: figH,
              child: Image.asset('assets/images/$img',
                  fit: BoxFit.contain,
                  alignment: Alignment.topCenter,
                  errorBuilder: (a, b, c) => Image.asset('assets/images/$fallback',
                      fit: BoxFit.contain,
                      alignment: Alignment.topCenter,
                      errorBuilder: (a2, b2, c2) => const SizedBox.shrink())),
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

  // ───────────────── 📋 내 정보(상태창) ─────────────────
  Widget _equipSlot(String label, IconData fallback, Map<String, dynamic>? item) {
    final hasItem = item != null;
    final iconPath = hasItem ? _itemIconPath(item['icon']?.toString() ?? '') : '';
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.55),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: hasItem ? _kGold : Colors.white24, width: 1.5),
        ),
        child: hasItem
            ? Padding(
                padding: const EdgeInsets.all(4),
                child: Image.asset(iconPath,
                    fit: BoxFit.contain,
                    errorBuilder: (a, b, c) => Icon(fallback, color: _kGold, size: 20)))
            : Icon(fallback, color: Colors.white30, size: 22),
      ),
      const SizedBox(height: 2),
      Text(label, style: const TextStyle(color: Colors.white60, fontSize: 9, fontWeight: FontWeight.bold)),
    ]);
  }

  Widget _statBreakRow(String name, Color color, int equipV, int levelV, int guildV, int champV) {
    final total = 10 + equipV + levelV + guildV + champV;
    Widget chip(String t, Color c) => Text(t,
        style: TextStyle(color: c, fontSize: 11, fontWeight: FontWeight.w600));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        SizedBox(
            width: 74,
            child: Text(name,
                maxLines: 1,
                overflow: TextOverflow.visible,
                softWrap: false,
                style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w900))),
        Text('$total',
            style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900)),
        const SizedBox(width: 10),
        Expanded(
          child: Wrap(spacing: 6, children: [
            chip('기본 10', Colors.white54),
            if (equipV != 0) chip('장비 +$equipV', const Color(0xFF7FB0FF)),
            if (levelV != 0) chip('레벨 +$levelV', const Color(0xFFFFC078)),
            if (guildV != 0) chip('길드 +$guildV', const Color(0xFF7FFFB0)),
            if (champV != 0) chip('👑 +$champV', _kGold),
          ]),
        ),
      ]),
    );
  }

  Widget _statusStats() {
    final equip = FishingLogic.getMyTotalStats(
      equippedSkin: globalEquippedSkin,
      equippedRod: globalEquippedRod,
      equippedFloat: globalEquippedFloat,
      equippedReel: globalEquippedReel,
      equippedSunglasses: globalEquippedSunglasses,
      equippedBadge: globalEquippedBadge,
      equippedCooler: globalEquippedCooler,
    );
    final eP = (equip['strength'] ?? 10) - 10;
    final eC = (equip['control'] ?? 10) - 10;
    final eS = (equip['sensitivity'] ?? 10) - 10;

    Widget body(int gLevel) {
      final lvB = (_level - 1) < 0 ? 0 : (_level - 1); // 🆙 레벨 보너스(각 +1/레벨) — 낚시 전투력과 동일
      final gB = FishingLogic.guildStatBonus(gLevel);
      final cB = _isChampionGuild ? FishingLogic.guildChampionBonus : 0;
      final totP = 10 + eP + lvB + gB + cB, totC = 10 + eC + lvB + gB + cB, totS = 10 + eS + lvB + gB + cB;
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text('Lv.$_level', style: const TextStyle(color: _kGold, fontSize: 17, fontWeight: FontWeight.w900)),
            const SizedBox(width: 8),
            Text(_rank,
                style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
            const Spacer(),
            if (_guildName.isNotEmpty)
              Text(_isChampionGuild ? '👑〈$_guildName〉Lv.$gLevel' : '〈$_guildName〉Lv.$gLevel',
                  style: const TextStyle(color: Color(0xFF9FE0FF), fontSize: 12, fontWeight: FontWeight.bold)),
          ]),
          const SizedBox(height: 2),
          Text('경험치 $currentExp · 포인트 $_gold',
              style: const TextStyle(color: Colors.white54, fontSize: 11)),
          const Divider(color: Colors.white12, height: 18),
          const Text('능력치 (기본 + 장비 + 레벨 + 길드 + 챔피언)',
              style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          _statBreakRow('💪 힘', const Color(0xFFFF8A80), eP, lvB, gB, cB),
          _statBreakRow('🎯 컨트롤', const Color(0xFFFFD180), eC, lvB, gB, cB),
          _statBreakRow('📡 감도', const Color(0xFF80D8FF), eS, lvB, gB, cB),
          const Divider(color: Colors.white12, height: 18),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
                color: const Color(0xFF22301F), borderRadius: BorderRadius.circular(10)),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('총 제압력', style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold)),
              Text('${totP + totC + totS}',
                  style: const TextStyle(color: Color(0xFF7FFFB0), fontSize: 20, fontWeight: FontWeight.w900)),
            ]),
          ),
        ]),
      );
    }

    if (_guildId.isEmpty) return body(0);
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('guilds').doc(_guildId).snapshots(),
      builder: (c, snap) {
        final gExp = (snap.data?.data() as Map<String, dynamic>?)?['guildExp'];
        final lv = FishingLogic.guildLevelFromExp((gExp is num) ? gExp.toInt() : 0);
        return body(lv);
      },
    );
  }

  // 인벤토리 아이템 클릭 → 장착/해제 토글 (광장에선 민물·바다 다 착용 가능 — 미리보기)
  void _equipFromStatus(Map<String, dynamic> item, void Function(void Function()) setD) {
    final n = item['name'].toString().replaceAll(' ', '').toUpperCase();
    final t = (item['type'] ?? '').toString().toUpperCase();
    bool same(Map<String, dynamic>? cur) => cur != null && cur['name'] == item['name'];
    if (t == 'COOLER' || n.contains('아이스박스') || n.contains('쿨러') || n.contains('보냉')) {
      globalEquippedCooler = same(globalEquippedCooler) ? null : item;
    } else if (n.contains('찌')) {
      if (same(globalEquippedFloat)) {
        globalEquippedFloat = null;
      } else {
        globalEquippedFloat = item;
        globalEquippedReel = null; // 릴/찌 한 슬롯
      }
    } else if (n.contains('스킨') || n.contains('조사') || n.contains('초보') || n.contains('마스터')) {
      globalEquippedSkin = same(globalEquippedSkin) ? null : item;
    } else if ((n.contains('릴') && !n.contains('크릴')) ||
        n.contains('2000') || n.contains('3000') || n.contains('5000') ||
        n.contains('6000') || n.contains('8000')) {
      if (same(globalEquippedReel)) {
        globalEquippedReel = null;
      } else {
        globalEquippedReel = item;
        globalEquippedFloat = null; // 릴/찌 한 슬롯
      }
    } else if (n.contains('대') || n.contains('CF') || n.contains('KT')) {
      globalEquippedRod = same(globalEquippedRod) ? null : item;
    } else if (n.contains('선글라스')) {
      globalEquippedSunglasses = same(globalEquippedSunglasses) ? null : item;
    } else if (n.contains('휘장')) {
      globalEquippedBadge = same(globalEquippedBadge) ? null : item;
    } else {
      globalEquippedBait = same(globalEquippedBait) ? null : item;
    }
    setD(() {}); // 다이얼로그 슬롯·스텟 갱신
    setState(() {}); // 플라자 HUD(아바타/스킨) 갱신
  }

  void _openStatusWindow() {
    String invTab = '전체';
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: const Color(0xFF161616),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: _kGold, width: 1.2)),
        child: SizedBox(
          width: 900,
          height: 600,
          child: StatefulBuilder(builder: (ctx, setD) {
            final reelOrFloat = globalEquippedReel ?? globalEquippedFloat;
            // 인벤토리 필터/정렬 (가방과 동일)
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
                case 'COOLER':
                  return 4;
                case 'BAIT':
                  return 5;
              }
              return 6;
            }

            bool match(Map<String, dynamic> it) {
              final c = (it['category'] ?? '').toString().toUpperCase();
              final t = (it['type'] ?? '').toString().toUpperCase();
              switch (invTab) {
                case '민물':
                  return (c == 'FW' && t != 'BAIT') || (t == 'ETC' && c != 'SEA') || t == 'COOLER';
                case '바다':
                  return (c == 'SEA' && t != 'BAIT') || (t == 'ETC' && c != 'FW') || t == 'COOLER';
                case '미끼':
                  return t == 'BAIT';
                case '스킨':
                  return t == 'SKIN' || c == 'SKIN';
              }
              return true;
            }

            // 🦐 민물새우 보유 여부 → 있으면 미끼만, 없으면 채집망(도구)만 표시
            final hasShrimp = _inventory.any((i) => ((i['name'] ?? '').toString()) == '민물새우' && ((i['quantity'] ?? 0) as num) > 0);
            final items = _inventory.map((e) => e as Map<String, dynamic>).where(match).where((it) {
              final nm = (it['name'] ?? '').toString();
              // 🦐 새우 있으면 민물새우(미끼) 표시·채집망 숨김 / 새우 없으면 채집망만 표시
              if (nm == '민물새우' && !hasShrimp) return false;
              if (nm == '새우 채집망' && hasShrimp) return false;
              return true;
            }).toList()
              ..sort((a, b) => typeRank(a).compareTo(typeRank(b)));

            Widget tabBtn(String t) {
              final active = invTab == t;
              return Expanded(
                child: GestureDetector(
                  onTap: () => setD(() => invTab = t),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                        border: Border(
                            bottom: BorderSide(
                                color: active ? _kGold : Colors.transparent, width: 3))),
                    child: Text(t,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: active ? _kGold : Colors.white54,
                            fontSize: 13,
                            fontWeight: active ? FontWeight.w900 : FontWeight.bold)),
                  ),
                ),
              );
            }

            return Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 12, 8, 4),
                child: Row(children: [
                  const Icon(Icons.badge, color: _kGold, size: 22),
                  const SizedBox(width: 8),
                  Text('${widget.nickname} 조사님 — 장비/능력치',
                      style: const TextStyle(color: _kGold, fontSize: 17, fontWeight: FontWeight.w900)),
                  const Spacer(),
                  IconButton(
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(Icons.close, color: Colors.white54)),
                ]),
              ),
              const Divider(color: Colors.white12, height: 1),
              Expanded(
                child: Row(children: [
                  // 왼쪽: 캐릭터 + 슬롯 + 스텟
                  Expanded(
                    flex: 5,
                    child: Column(children: [
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
                          child: Row(children: [
                            // 왼쪽 슬롯 열
                            Column(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                              _equipSlot('스킨', Icons.checkroom, globalEquippedSkin),
                              _equipSlot('선글라스', Icons.remove_red_eye, globalEquippedSunglasses),
                              _equipSlot('뱃지', Icons.shield, globalEquippedBadge),
                              _equipSlot('낚시대', Icons.phishing, globalEquippedRod),
                            ]),
                            // 캐릭터 (가운데, 크게)
                            Expanded(
                              child: Image.asset(_charImage,
                                  fit: BoxFit.contain,
                                  alignment: Alignment.bottomCenter,
                                  errorBuilder: (a, b, c) => const SizedBox.shrink()),
                            ),
                            // 오른쪽 슬롯 열
                            Column(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                              _equipSlot('릴/찌', Icons.album, reelOrFloat),
                              _equipSlot('미끼', Icons.bug_report, globalEquippedBait),
                              _equipSlot('아이스박스', Icons.ac_unit, globalEquippedCooler),
                            ]),
                          ]),
                        ),
                      ),
                      const Divider(color: Colors.white12, height: 1),
                      SizedBox(
                        height: 210,
                        child: SingleChildScrollView(child: _statusStats()),
                      ),
                    ]),
                  ),
                  const VerticalDivider(color: Colors.white12, width: 1),
                  // 오른쪽: 인벤토리 (클릭하면 장착)
                  Expanded(
                    flex: 6,
                    child: Column(children: [
                      const Padding(
                        padding: EdgeInsets.fromLTRB(12, 8, 12, 0),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text('가방 — 아이템을 누르면 장착돼요',
                              style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.bold)),
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
                                padding: const EdgeInsets.all(12),
                                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 4,
                                  childAspectRatio: 0.82,
                                  mainAxisSpacing: 10,
                                  crossAxisSpacing: 10,
                                ),
                                itemCount: items.length,
                                itemBuilder: (c, i) => GestureDetector(
                                  onTap: () => _equipFromStatus(items[i], setD),
                                  child: _invItem(items[i]),
                                ),
                              ),
                      ),
                    ]),
                  ),
                ]),
              ),
            ]);
          }),
        ),
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
              label: const Text('길드 만들기 (Lv.10, 10,000 P)',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
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
                  final mc = (g['memberCount'] is num) ? (g['memberCount'] as num).toInt() : 0;
                  final gExp = (g['guildExp'] is num) ? (g['guildExp'] as num).toInt() : 0;
                  final cap = FishingLogic.guildMaxMembers(FishingLogic.guildLevelFromExp(gExp));
                  final full = mc >= cap;
                  return Container(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                        color: const Color(0xFF2A2A2A),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.white12)),
                    child: Row(children: [
                      Container(
                        margin: const EdgeInsets.only(right: 10),
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                            color: _kGold, borderRadius: BorderRadius.circular(6)),
                        child: Text('Lv.${FishingLogic.guildLevelFromExp(gExp)}',
                            style: const TextStyle(
                                color: Colors.black, fontSize: 11, fontWeight: FontWeight.w900)),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(g['name']?.toString() ?? '',
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 15, fontWeight: FontWeight.w900)),
                            const SizedBox(height: 2),
                            Text('길드장 ${g['master'] ?? '-'}  ·  멤버 $mc/$cap명',
                                style: const TextStyle(color: Colors.white54, fontSize: 11)),
                          ],
                        ),
                      ),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                            backgroundColor: full ? Colors.grey.shade700 : _kGold,
                            foregroundColor: full ? Colors.white54 : Colors.black,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                            minimumSize: const Size(0, 0),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                        onPressed: full ? null : () => _joinGuild(uid, gid, g['name']?.toString() ?? ''),
                        child: Text(full ? '만원' : '가입', style: const TextStyle(fontWeight: FontWeight.bold)),
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

  int _guildTab = 0; // 0 길드원 / 1 혜택 / 2 설정

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
        final guildExp = (g['guildExp'] is num) ? (g['guildExp'] as num).toInt() : 0;
        final gLevel = FishingLogic.guildLevelFromExp(guildExp);
        return StatefulBuilder(
          builder: (ctx2, setTab) {
            return Column(
              children: [
                _guildDialogHeader(g['name']?.toString() ?? '길드',
                    trailing: IconButton(
                        icon: const Icon(Icons.close, color: Colors.white54),
                        onPressed: () => Navigator.pop(ctx))),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                          color: _kGold, borderRadius: BorderRadius.circular(8)),
                      child: Text('Lv.$gLevel',
                          style: const TextStyle(
                              color: Colors.black, fontSize: 13, fontWeight: FontWeight.w900)),
                    ),
                    const SizedBox(width: 10),
                    const Icon(Icons.military_tech, color: _kGold, size: 16),
                    const SizedBox(width: 4),
                    Text('${g['master'] ?? '-'}',
                        style: const TextStyle(color: Colors.white70, fontSize: 13)),
                    const SizedBox(width: 12),
                    const Icon(Icons.people, color: _kGold, size: 16),
                    const SizedBox(width: 4),
                    Text('${g['memberCount'] ?? 0}/${FishingLogic.guildMaxMembers(gLevel)}명',
                        style: const TextStyle(color: Colors.white70, fontSize: 13)),
                  ]),
                ),
                Row(children: [
                  _guildTabBtn('길드원', 0, setTab),
                  _guildTabBtn('혜택', 1, setTab),
                  _guildTabBtn('설정', 2, setTab),
                ]),
                const Divider(color: Colors.white12, height: 1),
                Expanded(
                  child: _guildTab == 1
                      ? _guildPerksTab(gLevel, guildExp)
                      : _guildTab == 2
                          ? _guildSettingsTab(ctx, uid, gid, isMaster)
                          : _guildMembersTab(gid),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _guildTabBtn(String label, int index, void Function(void Function()) setTab) {
    final active = _guildTab == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setTab(() => _guildTab = index),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            border: Border(
                bottom: BorderSide(color: active ? _kGold : Colors.transparent, width: 3)),
          ),
          child: Text(label,
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: active ? _kGold : Colors.white54,
                  fontSize: 14,
                  fontWeight: active ? FontWeight.w900 : FontWeight.bold)),
        ),
      ),
    );
  }

  Widget _guildMembersTab(String gid) {
    return StreamBuilder<QuerySnapshot>(
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
                  color: const Color(0xFF2A2A2A), borderRadius: BorderRadius.circular(8)),
              child: Row(children: [
                guildOnlineDot((m['uid'] ?? '').toString()),
                const SizedBox(width: 8),
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
    );
  }

  Widget _guildPerksTab(int gLevel, int guildExp) {
    final levelBonus = FishingLogic.guildStatBonus(gLevel);
    final champBonus = _isChampionGuild ? FishingLogic.guildChampionBonus : 0;
    final bonus = levelBonus + champBonus;
    final isMax = gLevel >= FishingLogic.guildMaxLevel;
    final curBase = FishingLogic.guildExpTable[gLevel];
    final nextBase = isMax
        ? FishingLogic.guildExpTable[FishingLogic.guildMaxLevel]
        : FishingLogic.guildExpTable[gLevel + 1];
    final span = nextBase - curBase;
    final prog = isMax || span <= 0 ? 1.0 : ((guildExp - curBase) / span).clamp(0.0, 1.0);
    Widget statRow(IconData icon, String name, int v) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(children: [
          Icon(icon, color: _kGold, size: 20),
          const SizedBox(width: 10),
          Text(name, style: const TextStyle(color: Colors.white, fontSize: 15)),
          const Spacer(),
          Text('+$v',
              style: const TextStyle(
                  color: Color(0xFF7FFFB0), fontSize: 17, fontWeight: FontWeight.w900)),
        ]),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text('길드 레벨 $gLevel',
                style: const TextStyle(color: _kGold, fontSize: 18, fontWeight: FontWeight.w900)),
            const SizedBox(width: 8),
            if (isMax)
              const Text('MAX',
                  style: TextStyle(color: Colors.orangeAccent, fontSize: 12, fontWeight: FontWeight.bold)),
          ]),
          const SizedBox(height: 8),
          Stack(children: [
            Container(
                height: 12,
                decoration: BoxDecoration(
                    color: Colors.white24, borderRadius: BorderRadius.circular(6))),
            FractionallySizedBox(
              widthFactor: prog,
              child: Container(
                  height: 12,
                  decoration: BoxDecoration(
                      color: _kGold, borderRadius: BorderRadius.circular(6))),
            ),
          ]),
          const SizedBox(height: 4),
          Text(isMax ? '최고 레벨 달성!' : '길드 경험치 $guildExp / $nextBase',
              style: const TextStyle(color: Colors.white54, fontSize: 11)),
          if (_isChampionGuild) ...[
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                  color: const Color(0xCC4A3A00),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _kGold)),
              child: Text('👑 이번 주 길드 리그 챔피언!  전 능력치 +$champBonus (1주일)',
                  style: const TextStyle(color: _kGold, fontSize: 13, fontWeight: FontWeight.w900)),
            ),
          ],
          const SizedBox(height: 16),
          Text(
              _isChampionGuild
                  ? '길드원 전체 능력치 보너스 (레벨 +$levelBonus, 챔피언 +$champBonus)'
                  : '길드원 전체 능력치 보너스',
              style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
                color: const Color(0xFF22301F),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF3A6B33))),
            child: Column(children: [
              statRow(Icons.fitness_center, '힘', bonus),
              statRow(Icons.sports_esports, '컨트롤', bonus),
              statRow(Icons.graphic_eq, '감도', bonus),
            ]),
          ),
          const SizedBox(height: 14),
          Row(children: [
            const Icon(Icons.groups, color: _kGold, size: 18),
            const SizedBox(width: 8),
            const Text('최대 가입 인원',
                style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold)),
            const Spacer(),
            Text('${FishingLogic.guildMaxMembers(gLevel)}명',
                style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w900)),
          ]),
          const SizedBox(height: 12),
          const Text('💡 길드원이 물고기를 잡을 때마다 길드 경험치가 쌓이고,\n레벨이 오르면 능력치 보너스와 최대 인원이 늘어납니다.\n(Lv10→30명, Lv20→40명, Lv30→50명)',
              style: TextStyle(color: Colors.white38, fontSize: 11, height: 1.4)),
        ],
      ),
    );
  }

  Widget _guildSettingsTab(BuildContext ctx, String uid, String gid, bool isMaster) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
              isMaster
                  ? '길드장은 길드를 해체할 수 있어요.\n해체하면 모든 길드원이 나가게 됩니다.'
                  : '길드를 탈퇴할 수 있어요.\n언제든 다시 가입할 수 있습니다.',
              style: const TextStyle(color: Colors.white54, fontSize: 13, height: 1.5)),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
                foregroundColor: Colors.redAccent,
                side: const BorderSide(color: Colors.redAccent),
                padding: const EdgeInsets.symmetric(vertical: 12)),
            icon: Icon(isMaster ? Icons.delete_forever : Icons.logout, size: 18),
            label: Text(isMaster ? '길드 해체' : '길드 탈퇴',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            onPressed: () => _leaveGuild(ctx, uid, gid, isMaster),
          ),
        ],
      ),
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
            const Text('조건: Lv.10 이상 · 생성 비용 10,000 P',
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
    if (_level < 10) {
      _toast('Lv.10부터 길드를 만들 수 있어요. (현재 Lv.$_level)');
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
      'guildExp': 0,
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
    // #9 탈퇴 후 24시간 재가입 제한
    try {
      final usnap = await fs.collection('users').doc(uid).get();
      final leftAt = usnap.data()?['leftGuildAt'];
      if (leftAt is Timestamp) {
        final diff = DateTime.now().difference(leftAt.toDate());
        if (diff.inHours < 24) {
          final remainH = 24 - diff.inHours;
          final remainM = (60 - (diff.inMinutes % 60)) % 60;
          _infoPopup('가입 제한', '길드 탈퇴 후 24시간이 지나야\n다시 가입할 수 있어요.\n\n(약 $remainH시간 $remainM분 남음)');
          return;
        }
      }
    } catch (_) {}
    try {
      await fs.runTransaction((tx) async {
        final gsnap = await tx.get(guildRef);
        if (!gsnap.exists) throw '길드가 사라졌어요.';
        final data = gsnap.data() ?? {};
        final mc = (data['memberCount'] is num) ? (data['memberCount'] as num).toInt() : 0;
        final gExp = (data['guildExp'] is num) ? (data['guildExp'] as num).toInt() : 0;
        final cap = FishingLogic.guildMaxMembers(FishingLogic.guildLevelFromExp(gExp));
        if (mc >= cap) {
          throw '길드 인원이 가득 찼어요. (최대 $cap명)\n길드 레벨을 올리면 정원이 늘어나요.';
        }
        tx.set(guildRef.collection('members').doc(uid), {
          'uid': uid,
          'nickname': widget.nickname,
          'role': 'member',
          'level': _level,
          'joinedAt': FieldValue.serverTimestamp(),
        });
        tx.update(guildRef, {'memberCount': FieldValue.increment(1)});
        tx.update(fs.collection('users').doc(uid), {
          'guildId': gid,
          'guildName': gname,
        });
      });
      _infoPopup('가입 완료', '"$gname" 길드에 가입했어요! 🎉');
    } catch (e) {
      _infoPopup('가입 불가', e.toString());
    }
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
        // 해체한 길드장(본인)만 24h 재가입 제한 / 강제로 나가게 된 멤버는 제한 없음
        batch.update(fs.collection('users').doc(m.id), {
          'guildId': '', 'guildName': '',
          if (m.id == uid) 'leftGuildAt': FieldValue.serverTimestamp(),
        });
        batch.delete(m.reference);
      }
      batch.delete(guildRef);
      await batch.commit();
      _toast('길드를 해체했어요.');
    } else {
      final batch = fs.batch();
      batch.delete(guildRef.collection('members').doc(uid));
      batch.update(guildRef, {'memberCount': FieldValue.increment(-1)});
      batch.update(fs.collection('users').doc(uid),
          {'guildId': '', 'guildName': '', 'leftGuildAt': FieldValue.serverTimestamp()}); // #9
      await batch.commit();
      _toast('길드를 탈퇴했어요.');
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold, height: 1.4)),
        backgroundColor: const Color(0xF21A1A1A),
        behavior: SnackBarBehavior.floating,
        // 채팅창·하단 잘림 피해서 화면 중앙 하단쯤에 잘 보이게 띄움
        margin: const EdgeInsets.only(bottom: 160, left: 60, right: 60),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: _kGold, width: 1.2)),
        elevation: 8,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  // 모달(길드창 등) 위에서도 잘 보이는 안내 팝업 — 토스트가 모달 뒤로 가려지는 문제 대응
  void _infoPopup(String title, String msg) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: const BorderSide(color: _kGold, width: 1.2)),
        title: Text(title, style: const TextStyle(color: _kGold, fontSize: 17, fontWeight: FontWeight.bold)),
        content: Text(msg, style: const TextStyle(color: Colors.white70, fontSize: 15, height: 1.5)),
        actions: [
          Center(
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: _kGold, foregroundColor: Colors.black),
              onPressed: () => Navigator.pop(c),
              child: const Text('확인', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  // 🎖️ #13 승급 퀘스트 패널 (아라 → 승급 퀘스트)
  void _openPromotion() {
    final tier = nextPromotion(_rank);
    showDialog(
      context: context,
      builder: (ctx) {
        if (tier == null) {
          return AlertDialog(
            backgroundColor: const Color(0xFF1A1A1A),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: _kGold, width: 1.2)),
            title: const Text('🎖️ 승급 퀘스트', style: TextStyle(color: _kGold, fontWeight: FontWeight.bold)),
            content: Text('$_rank 조사님은 현재 최고 단계예요!\n(레전드·낚시의 신은 준비 중)', style: const TextStyle(color: Colors.white70, height: 1.5)),
            actions: [Center(child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: _kGold, foregroundColor: Colors.black), onPressed: () => Navigator.pop(ctx), child: const Text('확인', style: TextStyle(fontWeight: FontWeight.bold))))],
          );
        }
        final need = tier['need'] as int;
        final reqLevel = tier['level'] as int;
        final reward = tier['reward'] as int;
        final targetRank = tier['rank'] as String;
        final levelOk = _level >= reqLevel;
        bool fishAllOk = true;
        final rows = <Widget>[];
        for (final f in daejangFish) {
          final c = _daejangCatch[f] ?? 0;
          final ok = c >= need;
          if (!ok) fishAllOk = false;
          rows.add(Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(children: [
              Icon(ok ? Icons.check_circle : Icons.radio_button_unchecked, color: ok ? const Color(0xFF7FFFB0) : Colors.white30, size: 16),
              const SizedBox(width: 8),
              Text(f, style: const TextStyle(color: Colors.white, fontSize: 14)),
              const Spacer(),
              Text('${c.clamp(0, need)} / $need', style: TextStyle(color: ok ? const Color(0xFF7FFFB0) : Colors.white54, fontSize: 14, fontWeight: FontWeight.bold)),
            ]),
          ));
        }
        final canClaim = levelOk && fishAllOk;
        return AlertDialog(
          backgroundColor: const Color(0xFF1A1A1A),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: _kGold, width: 1.4)),
          title: Text('🎖️ 승급 → $targetRank 조사', style: const TextStyle(color: _kGold, fontSize: 18, fontWeight: FontWeight.w900)),
          content: SizedBox(
            width: 320,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(levelOk ? Icons.check_circle : Icons.radio_button_unchecked, color: levelOk ? const Color(0xFF7FFFB0) : Colors.white30, size: 16),
                  const SizedBox(width: 8),
                  const Text('필요 레벨', style: TextStyle(color: Colors.white, fontSize: 14)),
                  const Spacer(),
                  Text('Lv.$reqLevel (현재 $_level)', style: TextStyle(color: levelOk ? const Color(0xFF7FFFB0) : Colors.white54, fontSize: 14, fontWeight: FontWeight.bold)),
                ]),
                const Divider(color: Colors.white12, height: 18),
                Text('6대장 각 $need마리 잡기 (누적)', style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                ...rows,
                const Divider(color: Colors.white12, height: 18),
                Text('🎁 보상: +$reward P\n👕 [$targetRank 조사] 스킨 구매 자격', style: const TextStyle(color: Color(0xFFD4AF37), fontSize: 13, fontWeight: FontWeight.bold, height: 1.5)),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('닫기', style: TextStyle(color: Colors.grey))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: canClaim ? _kGold : Colors.grey.shade800, foregroundColor: canClaim ? Colors.black : Colors.white38),
              onPressed: canClaim ? () { Navigator.pop(ctx); _claimPromotion(tier); } : null,
              child: Text(canClaim ? '승급하기 🎉' : '조건 미달', style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  void _claimPromotion(Map<String, dynamic> tier) async {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) return;
    final targetRank = tier['rank'].toString();
    final reward = tier['reward'] as int;
    try {
      await FirebaseFirestore.instance.collection('users').doc(u.uid).set(
          {'rank': targetRank, 'gold': FieldValue.increment(reward)}, SetOptions(merge: true));
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (c) => AlertDialog(
          backgroundColor: Colors.black.withOpacity(0.95),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: const BorderSide(color: _kGold, width: 3)),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('🎖️ 승급! 🎖️', style: TextStyle(color: _kGold, fontSize: 28, fontWeight: FontWeight.w900)),
            const SizedBox(height: 10),
            Text('$targetRank 조사 달성!', style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(color: _kGold.withOpacity(0.15), borderRadius: BorderRadius.circular(10), border: Border.all(color: _kGold)),
              child: Text('보상 +$reward P', style: const TextStyle(color: Colors.yellowAccent, fontSize: 20, fontWeight: FontWeight.w900)),
            ),
            const SizedBox(height: 10),
            Text('이제 쇼핑몰에서 [$targetRank 조사] 스킨을\n구매할 수 있어요!', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white54, fontSize: 13, fontWeight: FontWeight.bold)),
          ]),
          actions: [Center(child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: _kGold, foregroundColor: Colors.black), onPressed: () => Navigator.pop(c), child: const Text('확인', style: TextStyle(fontWeight: FontWeight.bold))))],
        ),
      );
    } catch (e) {
      _toast('승급 처리 실패: $e');
    }
  }

  Widget _topHud() {
    final lv = _level.clamp(1, globalMaxLevel);
    final curBase = globalExpTable[lv];
    final nextBase = lv < globalMaxLevel ? globalExpTable[lv + 1] : globalExpTable[globalMaxLevel];
    final span = nextBase - curBase;
    final prog = (lv >= globalMaxLevel || span <= 0) ? 1.0 : ((currentExp - curBase) / span).clamp(0.0, 1.0);
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
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                        color: _kGold.withOpacity(0.18),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: _kGold, width: 0.8)),
                    child: Text('CH$_channelNum',
                        style: const TextStyle(color: _kGold, fontSize: 11, fontWeight: FontWeight.w900)),
                  ),
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
          // 🔊 소리/전체화면 + 내 정보 카드 (오른쪽에 함께)
          Row(mainAxisSize: MainAxisSize.min, children: [
            _miniBtn(audioManager.isMuted ? Icons.volume_off : Icons.volume_up,
                () => setState(() => audioManager.toggleMute())),
            const SizedBox(width: 8),
            _miniBtn(Icons.fullscreen, _toggleFullScreen),
            const SizedBox(width: 12),
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
                GestureDetector(
                  onTap: _openStatusWindow, // 캐릭터 누르면 상태창
                  child: Container(
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
                    Text(lv >= globalMaxLevel ? 'MAX LEVEL' : '$currentExp / $nextBase EXP',
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
              ],
            ),
          ),
          ]),
        ],
      ),
    );
  }
}
