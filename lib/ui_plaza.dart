// ignore_for_file: deprecated_member_use, use_build_context_synchronously, avoid_web_libraries_in_flutter, use_null_aware_elements, curly_braces_in_flow_control_structures
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
import 'weather.dart'; // 🌧️ 실시간 날씨(기상청) 오버레이
import 'app_version.dart'; // 🔖 새 버전 알림(새로고침 안내)

const Color _kGold = Color(0xFFD4AF37);

class PlazaScreen extends StatefulWidget {
  final String nickname;
  final int level;
  final Map<String, dynamic> spot; // {name, target, stars, image}
  final bool isSea;
  final bool isFirstTime;
  final bool startTutorial; // 🎓 닉네임 설정을 거친 신규 계정 → 튜토리얼 강제 시작

  const PlazaScreen({
    super.key,
    required this.nickname,
    required this.level,
    required this.spot,
    this.isSea = false,
    this.isFirstTime = false,
    this.startTutorial = false,
  });

  // 🚪 기본 진입 광장 — 재접속 시 마지막에 있던 광장(민물/바다)으로
  factory PlazaScreen.defaultEntry({
    required String nickname,
    required int level,
    bool isFirstTime = false,
    bool startTutorial = false,
  }) {
    bool lastSea = false;
    try { lastSea = html.window.localStorage['lastPlazaSea'] == '1'; } catch (_) {}
    final spot = lastSea ? locations['갯바위']![0] : locations['저수지']![0];
    return PlazaScreen(
      nickname: nickname,
      level: level,
      spot: spot,
      isSea: lastSea,
      isFirstTime: isFirstTime,
      startTutorial: startTutorial,
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
  // 🎇 광장 중앙 시즌 조형물 — 시즌/이벤트마다 이 파일만 교체(그랜드오픈→크리스마스트리→벚꽃→야자수 등).
  //    민물·바다 광장 양쪽 중앙에 동일하게 표시. (assets/plaza/ 폴더)
  static const String kCenterpieceFile = 'center_monument_fw.png';
  static const double kCenterpieceHFrac = 0.48;
  int _skinPreviewIdx = 0;
  void _cycleSkinPreview() {
    setState(() {
      _skinPreviewIdx = (_skinPreviewIdx + 1) % _previewSkins.length;
      final nm = _previewSkins[_skinPreviewIdx];
      final st = skinStatsByName(nm); // 👕 스킨별 능력치도 함께 적용(낚시터별 확인용)
      globalEquippedSkin = {
        'name': nm, 'category': 'SKIN', 'type': 'SKIN', 'stats': st,
        'icon': skinIconByName(nm), // 🖼️ 슬롯 아이콘(없으면 낚시대 기본값으로 잘못 뜨는 버그 방지)
      };
    });
    final st = skinStatsByName(_previewSkins[_skinPreviewIdx]);
    _toast('스킨 미리보기 → ${_previewSkins[_skinPreviewIdx]} (💪${st['P']} 🎯${st['C']} 📡${st['S']})');
  }

  // 🚶 걷기 바운스용
  late final AnimationController _walkCtrl;
  bool _walking = false;
  Offset? _tapTarget;      // 🎯 탭 이동 목표(월드 0~1). 매 틱 한 걸음씩 접근
  Timer? _tapMoveTimer;    // 탭 이동 스텝 타이머(조이스틱과 동일 방식)

  // 🚶 원격 캐릭터 걷기 애니메이션 (위치가 바뀌는 동안 걷기 프레임 순환 → 강시 방지)
  final Map<String, Offset> _remotePrevPos = {};       // uid별 직전 위치(이동 감지용)
  final Map<String, DateTime> _remoteMovingUntil = {}; // uid별 '걷는 중' 만료시각
  Timer? _remoteWalkTimer;
  int _remoteWalkTick = 0;      // 걷기 프레임 카운터(150ms마다 +1)
  bool _remoteWalkDirty = false; // 멈춘 직후 한 프레임 더 그려 정지자세로
  bool _awayFromPlaza = false;  // 🚪 낚시터/아레나 등 다른 화면에 가 있음(고스트 방지: presence 재기록 중지)

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
  // 📍 친구·길드 목록에 표시할 내 접속 위치 (예: 'CH2·민물광장')
  String get _plazaLoc => 'CH$_channelNum·${widget.isSea ? '바다' : '민물'}광장';

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
  StreamSubscription<QuerySnapshot>? _incomingSub; // 🤝 나를 친구로 등록한 사람 알림(B안)

  // 🏆 주간 길드 리그 (1위 길드 챔피언 → 머리 위 👑 + 추가 버프)
  bool _isChampionGuild = false;
  String _champGuildId = '';
  String _champWeek = '';
  StreamSubscription<DocumentSnapshot>? _leagueSub;
  // 🎖️ 가람 주간 개인 종합 랭킹 (top10 = 1주일 PCS 보너스 + 머리 위 순위마크)
  StreamSubscription<DocumentSnapshot>? _garamSub;
  int _myGaramRank = 0; // 0=순위 없음, 1~10=이번 주 랭커
  // 🔒 중복 로그인 방지
  StreamSubscription<DatabaseEvent>? _sessionSub;
  bool _dupKicked = false;
  bool _levelSynced = false; // 🆙 첫 스냅샷 동기화 후에만 레벨업 팝업(초기 진입 오작동 방지)

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
    // 🎓 튜토리얼: 현재 퀘스트의 타겟 NPC면 미션 설명 팝업으로 가로채기
    final q = _tutQuestNow;
    if (q != null && !_tutCleared && q['npc'] == key) {
      setState(() { _tutMissionEnter = onEnter; _showTutMission = true; });
      return;
    }
    // 🛍️ 보배(상점): 보배 일일 정산/안내 우선 처리
    if (key == 'shop') {
      _onBobaeTap(onEnter);
      return;
    }
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

  // ───────────────────────── 🎓 튜토리얼 퀘스트 ─────────────────────────
  // 현재 진행 중 퀘스트(1~5 → 인덱스 0~4). 없으면 null
  Map<String, String>? get _tutQuestNow =>
      (_tutStep >= 1 && _tutStep <= _tutQuests.length) ? _tutQuests[_tutStep - 1] : null;

  Future<void> _setTut(Map<String, dynamic> data) async {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) return;
    await FirebaseFirestore.instance.collection('users').doc(u.uid).set(data, SetOptions(merge: true));
  }

  // 튜토리얼 시작 (인트로 '시작' 버튼) — 로컬 즉시 반영 + 저장
  void _startTutorial() {
    setState(() { _tutStep = 1; _tutCleared = false; });
    _setTut({'tutStep': 1, 'tutCleared': false});
  }

  // 아라 클릭 시: 튜토리얼 우선 처리(완료/미대상이면 일반 일일퀘스트)
  void _onAraTap() {
    if (_tutStep == 0) { setState(() => _showTutIntro = true); return; }
    if (_tutQuestNow != null) {
      if (_tutCleared) { setState(() => _showTutReward = true); }
      else { _toast('${_tutQuestNow!['name']} 을(를) 만나러 가보세요!'); }
      return;
    }
    setState(() => _showQuest = true); // 튜토리얼 끝 → 일반 일일퀘스트
  }

  // 🎓 NPC 이름 박스 위에 띄우는 빨간 느낌표
  Widget _tutBang() => const Padding(
        padding: EdgeInsets.only(bottom: 1),
        child: Text('❗',
            style: TextStyle(
              color: Color(0xFFFF3B30),
              fontSize: 22,
              fontWeight: FontWeight.w900,
              shadows: [Shadow(color: Colors.black, blurRadius: 4), Shadow(color: Colors.black, blurRadius: 4)],
            )),
      );

  // 타겟 NPC 미션 완료 처리 (랭킹/길드/아레나는 '열면 완료') — 로컬 즉시 반영 + 저장
  void _clearTutMission(String npcKey) {
    if (_tutQuestNow?['npc'] == npcKey && !_tutCleared) {
      setState(() => _tutCleared = true);
      _setTut({'tutCleared': true});
    }
  }

  // 아라에서 보상 받기 → 다음 퀘스트 — 로컬 즉시 반영 + 저장
  Future<void> _claimTutReward() async {
    final next = _tutStep + 1;
    setState(() { _tutStep = next; _tutCleared = false; });
    await _setTut({
      'exp': FieldValue.increment(_tutExp),
      'gold': FieldValue.increment(_tutPts),
      'tutStep': next,
      'tutCleared': false,
    });
    if (next > _tutQuests.length && mounted) {
      _toast('🎉 튜토리얼 완료! 이제 자유롭게 즐겨보세요 🎣');
    }
  }

  // 📋 일일 퀘스트 (아라 매니저) — 로비에서 광장으로 이전
  bool _showQuest = false;
  bool _showReward = false; // 🎁 오늘 첫 접속 보상 아라 팝업 표시
  // 🎓 튜토리얼 퀘스트 (신규 유저) — tutStep: 0=시작전, 1~5=진행중, 99=완료/미대상
  int _tutStep = 99;
  bool _tutCleared = false;   // 현재 퀘스트의 NPC 미션 완료(아라 가서 보상받기 대기)
  bool _tutIntroShown = false; // 접속 시 인트로 1회만
  bool _showTutIntro = false;   // 시작 안내(아라)
  bool _showTutMission = false; // 타겟 NPC 미션 설명
  bool _showTutReward = false;  // 아라 보상 받기
  VoidCallback? _tutMissionEnter; // 미션 팝업 버튼이 열 기능
  static const List<Map<String, String>> _tutQuests = [
    {'npc': 'rank',    'name': '가람', 'title': '랭킹 보는 법', 'desc': '경쟁 조사님들의 순위를 볼 수 있어요!\n순위표를 한 번 열어볼까요?', 'done': '순위표 잘 보셨죠? 😊'},
    {'npc': 'guild',   'name': '윤슬', 'title': '길드란?',     'desc': '조사님들이 모여 함께 크는 공동체예요!\n길드 화면을 열어보세요.', 'done': '길드를 둘러보셨네요! 👍'},
    {'npc': 'fishing', 'name': '나루', 'title': '첫 출조!',    'desc': '드디어 낚시예요!\n낚시터로 가서 첫 고기를 잡아오세요 🎣', 'done': '첫 고기 축하해요! 🎣'},
    {'npc': 'arena',   'name': '한별', 'title': '아레나 대회', 'desc': '실력을 겨루는 대회장이에요!\n아레나를 둘러보세요.', 'done': '아레나 구경 끝! ⚔️'},
    {'npc': 'shop',    'name': '서윤', 'title': '장비 장만',   'desc': '그동안 모은 포인트로\n상점에서 아이템을 1개 장만해보세요!', 'done': '아이템을 구매 하셨네요! 🎁'},
  ];
  static const int _tutExp = 200, _tutPts = 400; // 퀘스트당 보상
  bool _gotDailyReward = false; // 오늘 첫 접속 500P 지급됨
  bool _questDone = false; // #11 오늘 일일 퀘스트 완료(보상 수령)했는지
  String _rank = '초보'; // #13 승급 칭호(퀘스트 통과 결과)
  Map<String, int> _daejangCatch = {}; // #13 6대장 누적 카운트
  bool _fwDone = false; // 📋 오늘 민물 일일 완료
  bool _seaDone = false; // 📋 오늘 바다 일일 완료
  int _fwProg = 0, _seaProg = 0; // 진행도(표시용)
  bool _bobaeDone = false; // 🛍️ 오늘 보배 정산 완료
  int _bobaeCaught = 0; // 🛍️ 오늘 새로 잡은 지정 어종 수(퀘스트 진행도)
  int _bobaeCaughtFrom(dynamic bp, String today) =>
      (bp is Map && bp['date'] == today && bp['caught'] is num) ? (bp['caught'] as num).toInt() : 0;
  // 🥊 한별 아레나 일일 퀘스트: 오늘 승리 1회 → 보상. 2회 도전 다 지면 종료.
  bool _hanbyeolWon = false;     // 오늘 아레나 승리 기록
  bool _hanbyeolClaimed = false; // 오늘 한별 보상 수령
  int _arenaCount = 0;           // 오늘 아레나 입장 횟수(0~2)
  static const int hanbyeolExp = 200;
  static const int hanbyeolPts = 400;
  void _applyHanbyeol(Map<String, dynamic> d, String today) {
    _hanbyeolWon = d['hanbyeol_won_date'] == today;
    _hanbyeolClaimed = d['hanbyeol_reward_date'] == today;
    final ac = (d['arenaCount'] is num) ? (d['arenaCount'] as num).toInt() : 0;
    _arenaCount = (d['lastArenaDate'] == today) ? ac : 0;
  }

  String _greeting() {
    final h = DateTime.now().hour;
    return h >= 5 && h < 12 ? '좋은 아침이에요! ☀️' : h >= 12 && h < 18 ? '안녕하세요! ☕' : '밤낚시 오셨군요! 🌙';
  }

  // 📋 일일 퀘스트 브리핑 — 민물 먼저, 완료하면 바다
  String _getBriefingText() {
    final fw = getTodayFwMission();
    final sea = getTodaySeaMission();
    final g = _greeting();
    if (_fwDone && _seaDone) {
      return '$g\n🎉 일일 퀘스트 2개 모두 완료!\n수고하셨어요, 내일도 도전해요!';
    }
    if (!_fwDone) {
      return '$g\n🏞️ [민물] 오늘의 일일 퀘스트\n🐟 ${fw['fish']} ${fw['count']}마리 잡기 ($_fwProg/${fw['count']})\n✅ 완료하면 ${dailyMissionPrize}P!\n\n(완료하면 바다 퀘스트가 열려요)';
    }
    return '$g\n🌊 [바다] 일일 퀘스트\n🐟 ${sea['fish']} ${sea['count']}마리 잡기 ($_seaProg/${sea['count']})\n✅ 완료하면 ${dailyMissionPrize}P!';
  }

  // 🎁 첫 접속 통합 인사: 인사 + 500P 보상 + 오늘의 미션(민물) 한 번에
  String _getWelcomeText() {
    final fw = getTodayFwMission();
    return '${widget.nickname} 님, 어서오세요! 😊\n'
        '🎁 접속 보상 500P 지급 완료!\n\n'
        '🏞️ 오늘의 민물 일일 퀘스트\n'
        '🐟 ${fw['fish']} ${fw['count']}마리 잡으세요\n'
        '✅ 민물 완료후 바다 퀘스트 열려요)\n\n'
        '(미션을 잊으셨다면 저에게 오세요~)';
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
    // 🔁 재접속 시 이 광장(민물/바다)으로 돌아오게 마지막 광장 기록
    try { html.window.localStorage['lastPlazaSea'] = widget.isSea ? '1' : '0'; } catch (_) {}
    _walkCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 340));
    // 🚶 원격 캐릭터 걷기 프레임 클럭 (움직이는 유저가 있을 때만 다시 그림)
    _remoteWalkTimer = Timer.periodic(const Duration(milliseconds: 150), (_) {
      if (!mounted) return;
      final now = DateTime.now();
      final anyMoving = _remoteMovingUntil.values.any((u) => now.isBefore(u));
      if (anyMoving || _remoteWalkDirty) {
        setState(() => _remoteWalkTick++);
        _remoteWalkDirty = anyMoving; // 방금 멈췄으면 한 번 더 그린 뒤 정지
      }
    });
    _loadUser();
    WeatherService.instance.refresh(); // 🌧️ 실시간 날씨(위치→기상청) 요청
    WidgetsBinding.instance.addPostFrameCallback((_) => checkAppUpdate(context)); // 🔖 새 버전 알림
    _maybeShowRankNotice(); // 🔰 초반: 랭킹 시스템 안내 1회
    // 🤝 나를 친구로 등록한 사람 알림(B안) — 접속 중 실시간 + 재접속 시 밀린 알림
    _incomingSub = FirebaseFirestore.instance
        .collection('friends')
        .doc(widget.nickname)
        .collection('incoming')
        .where('seen', isEqualTo: false)
        .snapshots()
        .listen((snap) {
      if (!mounted || snap.docs.isEmpty) return;
      final names = <String>[];
      for (final d in snap.docs) {
        names.add(((d.data())['nickname'] ?? '조사').toString());
        d.reference.set({'seen': true}, SetOptions(merge: true)); // 읽음 처리(다시 안 뜨게)
      }
      _showIncomingFriendPopup(names);
    }, onError: (Object e) => debugPrint('친구 알림 구독 실패: $e'));
    // 🔒 중복 로그인 방지: 내 세션 등록 + 다른 기기 접속 감시
    registerLoginSession();
    _sessionSub = watchLoginSession(_onDuplicateLogin);
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
    _cancelTapMove(); // 키보드 조작 중이면 탭 이동 종료
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

  // 상단 미니 버튼 (소리/전체화면) — 폰에서 탭하기 쉽게 크게(내정보 카드 높이에 맞춤)
  Widget _miniBtn(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 58,
        alignment: Alignment.center, // 세로는 IntrinsicHeight+stretch로 카드 높이만큼 늘어남
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.7),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _kGold, width: 1.5),
          boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 4)],
        ),
        child: Icon(icon, color: _kGold, size: 34),
      ),
    );
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onHwKey); // ⌨️ 키보드 핸들러 해제
    _remoteWalkTimer?.cancel();
    _walkCtrl.dispose();
    _joyTimer?.cancel();
    _tapMoveTimer?.cancel();
    for (final s in _presenceSubs) {
      s.cancel();
    }
    _presenceSubs.clear();
    _userSub?.cancel();
    _incomingSub?.cancel();
    _leagueSub?.cancel();
    _garamSub?.cancel();
    _sessionSub?.cancel();
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
      // 🎓 닉네임 설정을 거친 신규 계정 → 튜토리얼 표식 보장(생성 시 누락 대비)
      if (widget.startTutorial && !data.containsKey('tutStep')) {
        await doc.reference.set({'tutStep': 0, 'tutCleared': false}, SetOptions(merge: true));
        _tutStep = 0; _tutCleared = false;
      } else if (data.containsKey('tutStep')) {
        // 일회성 get으로 튜토리얼 상태 확정 읽기 (실시간 스트림보다 신뢰)
        _tutStep = (data['tutStep'] as num?)?.toInt() ?? 99;
        _tutCleared = data['tutCleared'] == true;
      }
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
    // 🎁 첫 접속 보상 안내 — 아라 매니저가 팝업으로 안내
    if (_gotDailyReward) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _showReward = true);
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
      final leveledUp = _levelSynced && newLevel > _level; // 🆙 광장에서 퀘스트 보상으로 레벨업
      final guildChanged = gid != _guildId || gname != _guildName;
      // #11 오늘 일일 퀘스트 완료 여부
      final today = DateTime.now().toIso8601String().substring(0, 10);
      // 📋 일일 2분리 진행/완료 읽기
      final mp = d['mission_progress'];
      bool fwDone = false, seaDone = false; int fwProg = 0, seaProg = 0;
      if (mp is Map && mp['date'] == today) {
        fwDone = mp['fwDone'] == true;
        seaDone = mp['seaDone'] == true;
        fwProg = (mp['fw'] is num) ? (mp['fw'] as num).toInt() : 0;
        seaProg = (mp['sea'] is num) ? (mp['sea'] as num).toInt() : 0;
      }
      final questDone = fwDone && seaDone;
      // 🛍️ 보배 일일 — 오늘 정산 완료 여부
      final bp = d['bobae_progress'];
      final bobaeDone = bp is Map && bp['date'] == today && bp['claimed'] == true;
      final bobaeCaught = _bobaeCaughtFrom(bp, today);
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
        _fwDone = fwDone; _seaDone = seaDone; _fwProg = fwProg; _seaProg = seaProg;
        _bobaeDone = bobaeDone;
        _bobaeCaught = bobaeCaught;
        _applyHanbyeol(d, today); // 🥊 한별 아레나 일일 상태(실시간)
        _rank = newRank;
        _daejangCatch = dc;
        // 🎓 튜토리얼 상태는 실시간 스트림으로 안 건드림(캐시 스냅샷 덮어쓰기 방지).
        //    초기값은 _loadUser 일회성 get, 이후 변경은 로컬 낙관적 업데이트로만.
        _inventory = (d['inventory'] ?? []) as List<dynamic>;
        if (guildChanged) {
          _guildId = gid;
          _guildName = gname;
          if (gid.isEmpty && _chatTab == 3) _chatTab = 0;
        }
      });
      _levelSynced = true;
      // 🆙 광장에서 레벨업 시 축하 팝업 (퀘스트 보상 등)
      if (leveledUp && mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) _showPlazaLevelUp(newLevel); });
      }
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
    _settleGaramIfNeeded(); // 🎖️ 가람 개인 종합 랭킹 주간 정산
    _leagueSub = FirebaseFirestore.instance
        .collection('guild_league')
        .doc('state')
        .snapshots()
        .listen((doc) {
      _champGuildId = (doc.data()?['championGuildId'] ?? '').toString();
      _champWeek = (doc.data()?['activeWeek'] ?? '').toString();
      _recomputeChampion();
    });
    // 🎖️ 가람 개인랭킹 상태 구독 → 내 순위(마크·보너스) 실시간 반영
    _garamSub = FirebaseFirestore.instance
        .collection('garam_rank')
        .doc('state')
        .snapshots()
        .listen((doc) {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      final ranks = doc.data()?['ranks'];
      int r = 0;
      if (uid != null && ranks is Map && ranks[uid] is Map) {
        r = ((ranks[uid]['rank'] ?? 0) as num).toInt();
      }
      if (r != _myGaramRank) {
        if (mounted) setState(() => _myGaramRank = r);
        _writeMe(); // 머리 위 순위마크 갱신
      }
    });
  }

  // 🎖️ 주차가 바뀌었으면 개인 종합 랭킹 스냅샷 정산 (서버 크론 없이 클라 지연 정산)
  //    종합점수 = 레벨 보드 + 어종별 최대어 보드(민물·바다 전어종), 각 보드 1위=10점...10위=1점
  Future<void> _settleGaramIfNeeded() async {
    final fs = FirebaseFirestore.instance;
    final cur = FishingLogic.weekKey(DateTime.now());
    final stateRef = fs.collection('garam_rank').doc('state');
    try {
      final snap = await stateRef.get();
      if ((snap.data()?['activeWeek'] ?? '') == cur) return; // 이미 이번 주 정산됨
      // 📅 직전 주 점수를 월간(→연간) 랭킹에 누적하고 월/연이 바뀌었으면 마감 스냅샷 저장
      final prevWeek = (snap.data()?['activeWeek'] ?? '').toString();
      final prevList = snap.data()?['list'];
      if (prevWeek.isNotEmpty && prevList is List && prevList.isNotEmpty) {
        await _accumulateGaramPeriod(prevWeek, prevList);
      }
      final Map<String, int> score = {};
      final Map<String, String> nick = {};
      void award(List<QueryDocumentSnapshot> docs) {
        for (int i = 0; i < docs.length && i < 10; i++) {
          final d = docs[i].data() as Map<String, dynamic>;
          score[docs[i].id] = (score[docs[i].id] ?? 0) + (10 - i);
          final n = (d['nickname'] ?? '').toString();
          if (n.isNotEmpty) nick[docs[i].id] = n;
        }
      }
      // 레벨(경험치) 보드
      final lv = await fs.collection('users').orderBy('exp', descending: true).limit(10).get();
      award(lv.docs);
      // 어종별 최대어 보드 (민물 + 바다 전어종)
      for (final f in [...garamFwFish, ...garamSeaFish]) {
        try {
          final q = await fs.collection('users').orderBy('maxCatch.$f.size', descending: true).limit(10).get();
          award(q.docs.where((d) {
            final s = d.data()['maxCatch']?[f]?['size'] ?? 0;
            return (s is num) && s > 0;
          }).toList());
        } catch (_) {}
      }
      final sorted = score.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
      final ranks = <String, dynamic>{};
      final list = <Map<String, dynamic>>[];
      for (int i = 0; i < sorted.length && i < 10; i++) {
        final e = sorted[i];
        ranks[e.key] = {'rank': i + 1, 'nickname': nick[e.key] ?? '', 'score': e.value};
        list.add({'uid': e.key, 'rank': i + 1, 'nickname': nick[e.key] ?? '', 'score': e.value});
      }
      await fs.runTransaction((tx) async {
        final s = await tx.get(stateRef);
        if ((s.data()?['activeWeek'] ?? '') == cur) return; // 다른 클라가 먼저 정산함
        tx.set(stateRef, {
          'activeWeek': cur,
          'ranks': ranks,
          'list': list,
          'settledAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      });
    } catch (e) {
      debugPrint('🎖️ 가람 개인랭킹 정산 실패: $e');
    }
  }

  // 📅 주간 점수 → 월간 누적, 월이 바뀌면 지난달 top10 마감(history_month_YYYY-MM) 후
  //    그 달 점수를 연간에 누적, 연이 바뀌면 지난해 top10 마감(history_year_YYYY).
  //    시상(쇼핑몰 보상 상품 구매자격 검증)은 이 history 문서를 기준으로 한다.
  Future<void> _accumulateGaramPeriod(String weekKey, List prevList) async {
    final fs = FirebaseFirestore.instance;
    final monthKey = weekKey.substring(0, 7); // 'YYYY-MM' (그 주 월요일 기준)
    final monthlyRef = fs.collection('garam_rank').doc('monthly');
    final yearlyRef = fs.collection('garam_rank').doc('yearly');

    List<Map<String, dynamic>> top10(Map scores) {
      final entries = scores.entries.toList()
        ..sort((a, b) => (((b.value['score'] ?? 0) as num)).compareTo(((a.value['score'] ?? 0) as num)));
      return [
        for (int i = 0; i < entries.length && i < 10; i++)
          {
            'uid': entries[i].key,
            'rank': i + 1,
            'nickname': (entries[i].value['nickname'] ?? '').toString(),
            'score': ((entries[i].value['score'] ?? 0) as num).toInt(),
          }
      ];
    }

    try {
      await fs.runTransaction((tx) async {
        final mSnap = await tx.get(monthlyRef);
        final ySnap = await tx.get(yearlyRef);
        final mData = mSnap.data() ?? {};
        final curMonthKey = (mData['monthKey'] ?? '').toString();
        List<String> addedWeeks = List<String>.from(mData['addedWeeks'] ?? []);
        if (addedWeeks.contains(weekKey)) return; // 이미 누적된 주 (중복 방지)
        Map<String, dynamic> mScores = Map<String, dynamic>.from(mData['scores'] ?? {});

        // 🔒 월이 바뀜 → 지난달 마감: top10 스냅샷 저장 + 그 달 점수를 연간에 합산
        if (curMonthKey.isNotEmpty && curMonthKey != monthKey && mScores.isNotEmpty) {
          tx.set(fs.collection('garam_rank').doc('history_month_$curMonthKey'), {
            'monthKey': curMonthKey,
            'list': top10(mScores),
            'settledAt': FieldValue.serverTimestamp(),
          });
          // 연간 누적 (지난달이 속한 해 기준)
          final lastMonthYear = curMonthKey.substring(0, 4);
          final yData = ySnap.data() ?? {};
          final curYearKey = (yData['yearKey'] ?? '').toString();
          Map<String, dynamic> yScores = Map<String, dynamic>.from(yData['scores'] ?? {});
          // 연이 바뀜 → 지난해 마감 스냅샷 저장 후 리셋
          if (curYearKey.isNotEmpty && curYearKey != lastMonthYear && yScores.isNotEmpty) {
            tx.set(fs.collection('garam_rank').doc('history_year_$curYearKey'), {
              'yearKey': curYearKey,
              'list': top10(yScores),
              'settledAt': FieldValue.serverTimestamp(),
            });
            yScores = {};
          }
          mScores.forEach((uid, v) {
            final prev = yScores[uid];
            final prevScore = (prev is Map && prev['score'] is num) ? (prev['score'] as num).toInt() : 0;
            yScores[uid] = {
              'score': prevScore + (((v is Map ? v['score'] : 0) ?? 0) as num).toInt(),
              'nickname': (v is Map ? (v['nickname'] ?? '') : '').toString(),
            };
          });
          tx.set(yearlyRef, {
            'yearKey': lastMonthYear,
            'scores': yScores,
            'updatedAt': FieldValue.serverTimestamp(),
          });
          mScores = {}; // 월간 리셋
          addedWeeks = [];
        }

        // 이번 주 점수를 월간에 합산
        for (final e in prevList) {
          if (e is! Map) continue;
          final uid = (e['uid'] ?? '').toString();
          if (uid.isEmpty) continue;
          final prev = mScores[uid];
          final prevScore = (prev is Map && prev['score'] is num) ? (prev['score'] as num).toInt() : 0;
          mScores[uid] = {
            'score': prevScore + ((e['score'] ?? 0) as num).toInt(),
            'nickname': (e['nickname'] ?? '').toString(),
          };
        }
        addedWeeks.add(weekKey);
        tx.set(monthlyRef, {
          'monthKey': monthKey,
          'addedWeeks': addedWeeks,
          'scores': mScores,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      });
    } catch (e) {
      debugPrint('📅 가람 월간/연간 누적 실패: $e');
    }
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
    guildGoOnline(nick: widget.nickname, loc: _plazaLoc); // 🟢 전역 접속표시(+채널 위치)
    _writeMe();
    // 말풍선 만료 처리용 1초 타이머
    _bubbleTimer ??= Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    // 💓 하트비트: 닉/이미지/접속상태를 12초마다 재기록 → 닉 누락("조사")·미표시·접속불 깜빡임 자가복구
    _heartbeatTimer ??= Timer.periodic(const Duration(seconds: 12), (_) {
      if (!mounted || _awayFromPlaza) return; // 낚시터/아레나 가 있으면 광장 presence 재기록 안 함
      _writeMe(); // presence 전체(닉·이미지·길드·위치) 재기록
      guildGoOnline(nick: widget.nickname, loc: _plazaLoc); // 접속 초록불 + 채널 위치 재확인
    });
    _subscribeChannel(); // 🧩 현재 채널 presence 구독
  }

  // 🧩 현재 _channelKey 채널의 실시간 presence 구독(초기 접속·채널 전환 공용)
  void _subscribeChannel() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
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
          final nx = (v['x'] is num) ? (v['x'] as num).toDouble() : 0.5;
          final ny = (v['y'] is num) ? (v['y'] as num).toDouble() : 0.8;
          // 🚶 직전 위치와 비교해 움직였으면 '걷는 중'으로 표시(원격 걷기 프레임 순환용)
          final prev = _remotePrevPos[kk];
          if (prev != null &&
              ((nx - prev.dx).abs() > 0.0015 || (ny - prev.dy).abs() > 0.0015)) {
            _remoteMovingUntil[kk] = DateTime.now().add(const Duration(milliseconds: 750));
          }
          _remotePrevPos[kk] = Offset(nx, ny);
          next[kk] = {
            'nick': v['nick']?.toString() ?? '조사',
            'img': v['img']?.toString() ?? 'assets/images/char_beginner.png',
            'guild': v['guild']?.toString() ?? '',
            'champ': v['champ'] == true,
            'garam': (v['garam'] is num) ? (v['garam'] as num).toInt() : 0, // 🎖️ 순위마크
            'x': nx,
            'y': ny,
            'face': v['face'] == true,
            'dir': (v['dir'] ?? 'down').toString(), // 🚶 이동방향 스프라이트
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
      // 🧹 떠난 유저의 이동 상태 정리(맵 무한 증가 방지)
      _remotePrevPos.removeWhere((k, _) => !next.containsKey(k));
      _remoteMovingUntil.removeWhere((k, _) => !next.containsKey(k));
      if (mounted) {
        setState(() {
          _others
            ..clear()
            ..addAll(next);
        });
      }
    }, onError: (Object e) => debugPrint('🌐 RTDB READ ERR: $e')));
  }

  // 🧩 채널 목록 조회: {채널번호: 인원수} (선택 다이얼로그용)
  Future<Map<int, int>> _fetchChannelCounts() async {
    final counts = <int, int>{};
    try {
      final snap = await _db.ref('plaza/$_roomKey').get();
      final val = snap.value;
      if (val is Map) {
        val.forEach((k, v) {
          final ks = k.toString();
          if (ks.startsWith('ch') && v is Map) {
            final n = int.tryParse(ks.substring(2));
            if (n != null) counts[n] = v.length;
          }
        });
      }
    } catch (e) {
      debugPrint('🌐 채널 목록 조회 실패: $e');
    }
    return counts;
  }

  // 🧩 다른 채널로 이동: 기존 채널에서 빠지고 새 채널로 재접속(친구끼리 모이기용)
  Future<void> _switchChannel(int targetNum) async {
    if (targetNum == _channelNum) return; // 같은 채널이면 무시
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    // 1) 기존 채널에서 나가기(구독 해제 + 내 노드 제거 + onDisconnect 취소)
    for (final s in _presenceSubs) {
      s.cancel();
    }
    _presenceSubs.clear();
    try { await _myRef?.onDisconnect().cancel(); } catch (_) {}
    try { await _myRef?.remove(); } catch (_) {}
    // 2) 화면·상태 초기화
    if (mounted) {
      setState(() {
        _others.clear();
        _remotePrevPos.clear();
        _remoteMovingUntil.clear();
      });
    }
    // 3) 새 채널로 재접속
    _channelNum = targetNum;
    _channelKey = '$_roomKey/ch$targetNum';
    _myRef = _db.ref('plaza/$_channelKey/$uid');
    _myRef!.onDisconnect().remove().catchError((Object e) => debugPrint('🌐 RTDB onDisconnect ERR: $e'));
    _writeMe();
    guildGoOnline(nick: widget.nickname, loc: _plazaLoc); // 📍 바뀐 채널 위치 즉시 반영
    _subscribeChannel();
    if (mounted) setState(() {}); // 채널 표시·채팅 필터 갱신
  }

  // 🧩 채널 선택 다이얼로그 (자동배정 유지 + 원하면 이동)
  Future<void> _openChannelPicker() async {
    final counts = await _fetchChannelCounts();
    if (!mounted) return;
    int maxN = _channelNum;
    counts.forEach((n, _) { if (n > maxN) maxN = n; });
    final int nextNew = maxN + 1; // '새 채널' 번호
    await showDialog(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: const BorderSide(color: _kGold, width: 1.2)),
        title: const Text('🧩 채널 이동',
            style: TextStyle(color: _kGold, fontWeight: FontWeight.bold, fontSize: 18)),
        content: SizedBox(
          width: 300,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('친구·길드원과 같은 채널에서 만날 수 있어요.\n(다른 채널의 조사는 서로 보이지 않아요)',
                  style: TextStyle(color: Colors.white60, fontSize: 12, height: 1.4)),
              const SizedBox(height: 10),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (int n = 1; n <= maxN; n++) _channelRow(c, n, counts[n] ?? 0),
                    _channelRow(c, nextNew, 0, isNew: true),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('닫기', style: TextStyle(color: Colors.white54))),
        ],
      ),
    );
  }

  Widget _channelRow(BuildContext c, int n, int count, {bool isNew = false}) {
    final bool isCurrent = n == _channelNum;
    final bool isFull = !isNew && count >= _plazaChannelCap;
    final bool canTap = !isCurrent && !isFull;
    final String label = isNew ? '➕ 새 채널 (CH$n)' : 'CH$n';
    final String sub = isCurrent
        ? '현재 채널'
        : (isNew ? '새로 열기' : (isFull ? '가득 참' : '$count/$_plazaChannelCap명'));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Material(
        color: isCurrent ? _kGold.withOpacity(0.15) : Colors.white10,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: canTap
              ? () async {
                  Navigator.pop(c);
                  await _switchChannel(n);
                  if (mounted) _toast('CH$n 채널로 이동했어요 🧩');
                }
              : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(children: [
              Icon(isNew ? Icons.add_circle_outline : Icons.groups,
                  color: canTap ? _kGold : Colors.white30, size: 18),
              const SizedBox(width: 10),
              Text(label,
                  style: TextStyle(
                      color: (canTap || isCurrent) ? Colors.white : Colors.white38,
                      fontWeight: FontWeight.bold,
                      fontSize: 15)),
              const Spacer(),
              Text(sub,
                  style: TextStyle(
                      color: isCurrent
                          ? _kGold
                          : (isFull ? Colors.redAccent : Colors.white54),
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
            ]),
          ),
        ),
      ),
    );
  }

  void _writeMe() {
    _myRef?.set({
      'nick': widget.nickname,
      'img': _charImage,
      'guild': _guildName,
      'champ': _isChampionGuild,
      'garam': _myGaramRank, // 🎖️ 주간 개인랭킹 순위마크(0=없음)
      'x': _charPos.dx,
      'y': _charPos.dy,
      'face': _facingRight,
      'dir': _moveDir, // 🚶 이동방향(remote 스프라이트용)
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
    final rH = sizeH * (0.19 + pT * 0.12); // 🧍 내 캐릭터와 동일한 크기 곡선
    final rW = rH * 0.55;
    final face = d['face'] == true;
    final dir = (d['dir'] ?? 'down').toString();
    final baseImg = d['img'] as String;
    final nick = d['nick'] as String;
    // 🚶 걷는 중이면 걷기 프레임(1↔2) 순환, 멈추면 정지자세(0) → 내 캐릭터와 동일하게 걷는 모습
    final moving = DateTime.now().isBefore(_remoteMovingUntil[uid] ?? DateTime(2000));
    final frame = moving ? (_remoteWalkTick.isEven ? 1 : 2) : 0;
    final bob = moving && _remoteWalkTick.isEven ? rH * 0.03 : 0.0; // 살짝 위아래 바운스
    final sprite = baseImg.replaceAll('.png', '_$dir$frame.png'); // 방향별 걷기/정지 스프라이트
    final flip = (dir == 'side' && !face); // 옆모습이고 왼쪽 보면 좌우반전
    return AnimatedPositioned(
      key: ValueKey('remote_$uid'),
      duration: const Duration(milliseconds: 650),
      curve: Curves.linear,
      left: dx * worldW - rW / 2,
      top: dy * worldH - rH,
      width: rW,
      height: rH,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.bottomCenter,
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _showUserMenu(nick), // 👆 캐릭터 클릭 → 귓속말/친구추가 메뉴
              child: Transform.translate(
                offset: Offset(0, -bob), // 🚶 걷기 바운스
                child: Transform(
                  alignment: Alignment.bottomCenter,
                  transform: Matrix4.rotationY(flip ? math.pi : 0),
                  // 🚶 내 캐릭터와 동일하게 방향별 걷기 스프라이트로 표시(낚시 포즈 풀이미지 대신).
                  //    스킨 등 스프라이트 없으면 원본 이미지로 폴백.
                  child: Image.asset(
                      sprite,
                      fit: BoxFit.contain,
                      alignment: Alignment.bottomCenter,
                      errorBuilder: (a, b, c) => Image.asset(baseImg,
                          fit: BoxFit.contain,
                          alignment: Alignment.bottomCenter,
                          errorBuilder: (a2, b2, c2) => const SizedBox.shrink())),
                ),
              ),
            ),
          ),
          // 이름표·말풍선은 탭을 통과시켜(IgnorePointer) 그 자리로 걷기가 가능하게
          Positioned(
            bottom: rH * 0.62, // 머리 위(내 캐릭터와 동일)
            left: -150,
            right: -150,
            child: IgnorePointer(
              child: Center(
                child: _nameTag(nick, (d['guild'] ?? '') as String,
                    champ: d['champ'] == true,
                    garamRank: (d['garam'] ?? 0) as int),
              ),
            ),
          ),
          // 💬 다른 유저 말풍선
          if (_bubbleUntil[uid] != null && DateTime.now().isBefore(_bubbleUntil[uid]!))
            Positioned(
              bottom: rH * 0.68,
              left: -150,
              right: -150,
              child: IgnorePointer(child: Center(child: _bubble(_bubbleMsg[uid] ?? ''))),
            ),
        ],
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
  // 월드 가로:세로 비율. 바다광장은 실제 이미지 비율(2760×1504)로 → 하단 안 잘림. 민물은 기존값 유지(배치 보존).
  double get _imgAspect => widget.isSea ? (2760 / 1504) : (3296 / 1700);
  static const double _baseFrac = 0.72; // 기본 줌(=캐릭터/NPC 크기 기준). 화면이 보여주는 월드 세로 비율
  double _zoomScale = 1.0; // 🔍 줌 배율 (1.0=기본 와이드 ~ 2.6=확대). Transform.scale 중앙 확대
  double _zoomStartScale = 1.0; // 핀치 시작 배율
  static const bool _devCoords = false; // 🔧 좌표 수집 모드. 다시 켜려면 => _isOperator
  Offset? _lastTapWorld;

  // 🗺️ 걷기 구역(섬 경계) 다각형 — 사용자 탭 좌표(시계방향 한 바퀴). 바다·민물 동일 구도라 공유.
  static const List<Offset> _freshPoly = [
    Offset(0.006, 0.495), Offset(0.165, 0.411), Offset(0.267, 0.331), Offset(0.421, 0.285),
    Offset(0.411, 0.230), Offset(0.472, 0.271), Offset(0.603, 0.246), Offset(0.710, 0.346),
    Offset(0.779, 0.398), Offset(0.823, 0.397), Offset(0.823, 0.332), Offset(0.983, 0.326),
    Offset(0.996, 0.490), Offset(0.784, 0.540), Offset(0.914, 0.668), Offset(0.994, 0.623),
    Offset(0.994, 0.992), Offset(0.006, 0.989),
  ];
  // 🌊 바다광장 걷기 경계 (계단 때문에 점 많음)
  static const List<Offset> _seaPoly = [
    Offset(0.008, 0.462), Offset(0.048, 0.467), Offset(0.063, 0.408), Offset(0.259, 0.303),
    Offset(0.288, 0.337), Offset(0.388, 0.342), Offset(0.420, 0.310), Offset(0.412, 0.269),
    Offset(0.583, 0.261), Offset(0.606, 0.322), Offset(0.690, 0.328), Offset(0.712, 0.284),
    Offset(0.878, 0.329), Offset(0.998, 0.398), Offset(0.998, 0.466), Offset(0.780, 0.492),
    Offset(0.780, 0.528), Offset(0.992, 0.547), Offset(0.995, 0.996), Offset(0.902, 0.973),
    Offset(0.793, 0.829), Offset(0.622, 0.800), Offset(0.598, 0.696), Offset(0.575, 0.702),
    Offset(0.589, 0.832), Offset(0.718, 0.832), Offset(0.819, 0.895), Offset(0.877, 0.998),
    Offset(0.176, 0.994), Offset(0.237, 0.880), Offset(0.349, 0.817), Offset(0.434, 0.820),
    Offset(0.452, 0.846), Offset(0.472, 0.834), Offset(0.490, 0.702), Offset(0.457, 0.691),
    Offset(0.431, 0.786), Offset(0.315, 0.802), Offset(0.205, 0.876), Offset(0.133, 0.995),
    Offset(0.003, 0.986),
  ];
  List<Offset> get _activePoly => widget.isSea ? _seaPoly : _freshPoly;

  // 🚫 못 가는 구역(화단·구조물) — 바깥 폴리곤 안에서도 여기 안이면 못 감
  static const List<List<Offset>> _freshObstacles = [
    // 🗼 기념탑
    [Offset(0.496, 0.550), Offset(0.578, 0.546), Offset(0.585, 0.593), Offset(0.511, 0.592)],
    // 📜 퀘스트 두루마리
    [Offset(0.535, 0.867), Offset(0.535, 0.918), Offset(0.457, 0.916), Offset(0.445, 0.864)],
    // 🏆 랭킹 트로피
    [Offset(0.166, 0.663), Offset(0.060, 0.664), Offset(0.059, 0.599), Offset(0.166, 0.581)],
    // 🛡️ 길드 방패
    [Offset(0.325, 0.405), Offset(0.256, 0.405), Offset(0.256, 0.370), Offset(0.321, 0.370)],
    // 🏛️ 아레나 탑 (외곽 경계 틈 보강)
    [Offset(0.779, 0.391), Offset(0.743, 0.392), Offset(0.705, 0.395), Offset(0.705, 0.302),
     Offset(0.807, 0.334), Offset(0.804, 0.390)],
    // (낚시터·상점은 외곽 경계로 이미 차단)
  ];
  // 🌊 바다광장 못 가는 구역 (낚시터·아레나·상점은 외곽 경계로 차단)
  static const List<List<Offset>> _seaObstacles = [
    // 🗼 기념탑
    [Offset(0.580, 0.490), Offset(0.501, 0.490), Offset(0.485, 0.452), Offset(0.570, 0.432)],
    // 📜 퀘스트 두루마리
    [Offset(0.705, 0.862), Offset(0.798, 0.897), Offset(0.782, 0.921), Offset(0.706, 0.912)],
    // 🏆 랭킹 트로피
    [Offset(0.234, 0.902), Offset(0.334, 0.856), Offset(0.348, 0.916), Offset(0.245, 0.941)],
    // 🛡️ 길드 방패
    [Offset(0.112, 0.416), Offset(0.120, 0.387), Offset(0.188, 0.379), Offset(0.191, 0.413)],
  ];
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

  // 🖱️ 지점 탭 → 조이스틱과 동일한 '매 틱 한 걸음씩' 이동.
  //    직선 순간이동(관통) 대신 걷기영역을 매 스텝 클램프 → 화단·구조물은 경계 따라 슬라이드.
  //    또 매 120ms 위치를 전송 → 원격 화면에서도 순간이동 없이 부드럽게 걸어옴.
  void _moveTo(Offset rawTarget, double w, double h) {
    audioManager.ensureRainPlaying(); // 🌧️ 첫 조작 시 빗소리 열기(자동재생 차단 우회)
    if (_devCoords) _lastTapWorld = rawTarget; // 🔧 좌표 수집
    if (_joyTimer != null) return; // 조이스틱/키보드 조작 중이면 탭 이동 무시
    _tapTarget = _devCoords ? rawTarget : _clampToPlaza(rawTarget); // 목적지는 걷기영역 안으로
    if (!_walkCtrl.isAnimating) _walkCtrl.repeat();
    _tapMoveTimer ??= Timer.periodic(const Duration(milliseconds: 16), (_) => _tapTick());
  }

  void _tapTick() {
    final target = _tapTarget;
    if (target == null || !mounted) { _stopTapMove(); return; }
    final w = _worldW, h = _worldH;
    final dxW = (target.dx - _charPos.dx) * w;
    final dyW = (target.dy - _charPos.dy) * h;
    final distPx = math.sqrt(dxW * dxW + dyW * dyW);
    if (distPx < 6) { _stopTapMove(); return; } // 도착
    const speedPxPerSec = 240.0; // 조이스틱과 동일 속도
    const dt = 16 / 1000.0;
    final step = speedPxPerSec * dt;
    final ux = dxW / distPx, uy = dyW / distPx; // 단위벡터
    var np = Offset(_charPos.dx + (ux * step) / w, _charPos.dy + (uy * step) / h);
    np = Offset(np.dx.clamp(0.0, 1.0), np.dy.clamp(0.0, 1.0));
    if (!_devCoords) np = _clampToPlaza(np); // 화단·구조물 밖으로 보정(경계 슬라이드)
    final movedPx = ((np.dx - _charPos.dx) * w).abs() + ((np.dy - _charPos.dy) * h).abs();
    setState(() {
      if (dxW.abs() >= dyW.abs()) { _moveDir = 'side'; _facingRight = dxW >= 0; }
      else { _moveDir = dyW < 0 ? 'up' : 'down'; }
      _charPos = np;
      _moveDuration = Duration.zero; // 보간 끔 → 매 틱 직접 이동
      _walking = true;
    });
    // 벽/장애물에 완전히 막혀 더 못 감(목적지가 화단 안/뒤) → 정지
    if (movedPx < 0.5) { _stopTapMove(); return; }
    final now = DateTime.now();
    if (now.difference(_lastNetSend).inMilliseconds > 120) {
      _lastNetSend = now;
      _sendPos();
    }
  }

  void _stopTapMove() {
    _tapMoveTimer?.cancel();
    _tapMoveTimer = null;
    _tapTarget = null;
    if (mounted) setState(() => _walking = false);
    _walkCtrl.stop();
    _walkCtrl.value = 0;
    _sendPos(); // 최종 위치 전송(원격 정지 동기화)
  }

  void _cancelTapMove() {
    _tapMoveTimer?.cancel();
    _tapMoveTimer = null;
    _tapTarget = null;
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
    audioManager.ensureRainPlaying(); // 🌧️ 첫 조작 시 빗소리 열기
    _joyMove(fromCenter);
    _cancelTapMove(); // 진행 중이던 탭 이동 종료(조이스틱 우선)
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
    const speedPxPerSec = 240.0; // 월드 스크린px 기준 이동 속도(절반으로 느리게)
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
    _myRef?.update({'x': _charPos.dx, 'y': _charPos.dy, 'face': _facingRight, 'dir': _moveDir}).catchError(
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
  // 🚪 낚시터/아레나 등 다른 화면으로 나갈 때: 광장 presence 제거(고스트 방지) + 하트비트 정지
  void _leavePlazaPresence() {
    _awayFromPlaza = true;
    _myRef?.remove().catchError((Object e) => debugPrint('🌐 광장 presence 제거 실패: $e'));
  }

  // 🚪 광장으로 복귀: presence 재등록 + 하트비트 재개
  void _returnPlazaPresence() {
    if (!mounted) return;
    _awayFromPlaza = false;
    _writeMe();
    guildGoOnline(nick: widget.nickname, loc: _plazaLoc);
  }

  // loc/sea를 주면 그 낚시터로 바로 출조, 없으면 현재 광장 spot
  void _goFishing({Map<String, dynamic>? loc, bool? sea}) {
    final spot = loc ?? widget.spot;
    final isSea = sea ?? widget.isSea;
    globalIsSeaMode = isSea;
    _leavePlazaPresence(); // 🚪 광장에서 사라짐(고스트 방지)
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
    ).then((result) {
      // 🗺️ 낚시터 리스트에서 '다른 낚시터로 이동' 요청 → 광장 복귀 없이 바로 다음 낚시터로
      if (result is Map && result['hopTo'] != null) {
        _goFishing(loc: Map<String, dynamic>.from(result['hopTo'] as Map), sea: result['sea'] == true);
        return;
      }
      // 🏛️ 낚시 종류에 맞는 광장으로 복귀 (바다낚시→바다광장). 현재 광장과 종류가 다르면 광장 교체.
      if (result is Map && result['toPlaza'] != null) {
        final wantSea = result['toPlaza'] == 'sea';
        if (wantSea != widget.isSea) { _switchPlazaWorld(wantSea); return; }
      }
      _returnPlazaPresence(); // 🚪 복귀 → 광장에 다시 등장
      if (mounted) { _playPlazaBgm(); _refreshTutFromDb(); } // 🎵 광장 BGM + 🎓 튜토리얼 상태 재읽기(나루 첫고기 완료 반영)
    });
  }

  // 🏛️ 광장 종류 전환 (민물광장 ↔ 바다광장) — 낚시 종류에 맞춰 해당 광장으로 교체
  void _switchPlazaWorld(bool sea) {
    if (!mounted) return;
    _leavePlazaPresence(); // 🚪 현재 광장에서 사라짐(고스트 방지)
    final spot = sea ? locations['갯바위']![0] : locations['저수지']![0];
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => PlazaScreen(
          nickname: widget.nickname,
          level: _level,
          spot: spot,
          isSea: sea,
        ),
      ),
    );
  }

  // 🎓 낚시/외부 화면에서 돌아왔을 때 튜토리얼 상태 일회성 재읽기
  Future<void> _refreshTutFromDb() async {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) return;
    try {
      final d = (await FirebaseFirestore.instance.collection('users').doc(u.uid).get()).data() ?? {};
      if (!mounted) return;
      final today = DateTime.now().toIso8601String().substring(0, 10);
      final bp = d['bobae_progress'];
      setState(() {
        if (d.containsKey('tutStep')) {
          _tutStep = (d['tutStep'] as num?)?.toInt() ?? _tutStep;
          _tutCleared = d['tutCleared'] == true;
        }
        _inventory = (d['inventory'] ?? _inventory) as List<dynamic>; // 🐟 보배 ❗용 마릿수 갱신
        _bobaeDone = bp is Map && bp['date'] == today && bp['claimed'] == true;
        _bobaeCaught = _bobaeCaughtFrom(bp, today);
        _applyHanbyeol(d, today); // 🥊 한별 아레나 일일 상태
      });
    } catch (_) {}
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
    ).then((_) {
      if (mounted) _refreshTutFromDb(); // 🎓 상점에서 돌아오면 튜토리얼 상태 재읽기(보배 구매 완료 대비)
    });
  }

  void _openArena() {
    _leavePlazaPresence(); // 🚪 광장에서 사라짐(고스트 방지)
    Navigator.push(context, MaterialPageRoute(builder: (_) => const ArenaScreen()))
        .then((_) {
      _returnPlazaPresence(); // 🚪 복귀 → 광장에 다시 등장
      if (mounted) { _playPlazaBgm(); _refreshTutFromDb(); } // 🎵 BGM 재개 + 🥊 한별 승리 상태 갱신
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
            // 🏷️ 이름 옆에 별점을 붙이고(한 줄), 설명은 바로 아래에 크게 → 모바일 가독성
                            title: Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Flexible(
                                  child: Text(s['name'],
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16.5)),
                                ),
                                const SizedBox(width: 8),
                                ...List.generate(
                                  5,
                                  (k) => Icon(
                                      k < (s['stars'] as int) ? Icons.star : Icons.star_border,
                                      color: _kGold,
                                      size: 13),
                                ),
                              ],
                            ),
                            subtitle: (s['target'] ?? '').toString().isNotEmpty
                                ? Padding(
                                    padding: const EdgeInsets.only(top: 5),
                                    child: Text('💡 ${s['target']}',
                                        style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.35, fontWeight: FontWeight.w500)),
                                  )
                                : null,
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
    final raw = _chatCtrl.text.trim();
    if (raw.isEmpty) return;
    final text = FishingLogic.cleanChat(raw); // 🛡️ 비속어 필터
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

  // 🏷️ 머리 위 이름표 (길드명 + 닉네임, 챔피언이면 👑, 주간랭커면 🏆N위)
  Widget _nameTag(String nick, String guild, {bool isMe = false, bool champ = false, int garamRank = 0}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 🎖️ 가람 주간 개인랭킹 순위마크 (top10, 1주일 유지)
        if (garamRank >= 1 && garamRank <= 10)
          Container(
            margin: const EdgeInsets.only(bottom: 2),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: const Color(0xCC4A3A00),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _kGold, width: 1.0),
            ),
            child: Text(
                garamRank == 1 ? '🥇 주간랭킹 1위' : (garamRank <= 3 ? (garamRank == 2 ? '🥈 주간랭킹 2위' : '🥉 주간랭킹 3위') : '🏆 주간랭킹 $garamRank위'),
                maxLines: 1,
                style: const TextStyle(color: _kGold, fontSize: 10, fontWeight: FontWeight.w900)),
          ),
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

  void _addFriend(String nick, {bool silent = false}) {
    if (nick == widget.nickname) {
      if (!silent) _infoPopup('친구 추가', '자기 자신은 친구로 추가할 수 없어요 😅');
      return;
    }
    final db = FirebaseFirestore.instance;
    db
        .collection('friends')
        .doc(widget.nickname)
        .collection('my_list')
        .doc(nick)
        .set({'nickname': nick, 'addedAt': FieldValue.serverTimestamp()}).then((_) {
      // 🤝 상대에게 "○○님이 친구로 등록했어요" 알림 남기기(B안: 단방향 + 알림)
      db
          .collection('friends')
          .doc(nick)
          .collection('incoming')
          .doc(widget.nickname)
          .set({'nickname': widget.nickname, 'addedAt': FieldValue.serverTimestamp(), 'seen': false})
          .catchError((Object e) => debugPrint('친구 알림 기록 실패: $e'));
      if (mounted && !silent) _infoPopup('친구 추가 완료 🤝', '[$nick]님을 친구 목록에 추가했어요!');
    }).catchError((Object e) {
      if (mounted && !silent) _infoPopup('친구 추가 실패', '잠시 후 다시 시도해주세요.');
    });
  }

  // 🤝 나를 친구로 등록한 사람 알림(B안). 접속 중 실시간 + 재접속 시 밀린 알림도 표시.
  void _showIncomingFriendPopup(List<String> names) {
    if (!mounted || names.isEmpty) return;
    final first = names.first;
    final more = names.length > 1 ? ' 외 ${names.length - 1}명' : '';
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: const BorderSide(color: _kGold, width: 1.2)),
        title: const Text('🤝 새 친구 알림',
            style: TextStyle(color: _kGold, fontSize: 17, fontWeight: FontWeight.bold)),
        content: Text('[$first]$more님이 회원님을 친구로 등록했어요!',
            style: const TextStyle(color: Colors.white70, fontSize: 15, height: 1.5)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('확인', style: TextStyle(color: Colors.white54))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _kGold, foregroundColor: Colors.black),
            onPressed: () {
              Navigator.pop(c);
              for (final n in names) {
                _addFriend(n, silent: true);
              }
              _infoPopup('친구 추가 완료 🤝', '${names.length}명을 친구로 추가했어요!');
            },
            child: const Text('나도 친구 추가', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
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
                                final fn = (f['nickname'] ?? '?').toString();
                                return ListTile(
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                                  visualDensity: VisualDensity.compact,
                                  leading: const Icon(Icons.person, color: Colors.greenAccent, size: 20),
                                  title: Row(children: [
                                    Flexible(
                                      child: Text(fn,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                              color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                                    ),
                                    const SizedBox(width: 6),
                                    userLocByNick(fn, fontSize: 10), // 📍 접속 채널·위치(접속 중일 때만)
                                  ]),
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
          final charH = sizeRef * (0.19 + perspT * 0.12); // NPC 크기에 맞춰 확대
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
                        // 🎭 깊이정렬 스프라이트: 시설 포털 + 내 캐릭터 + 원격 유저를
                        //    발높이(y)순으로 그려서, 캐릭터가 포털보다 위(뒤)면 포털에 가려지게 함.
                        ...(() {
                          final sprites = <MapEntry<double, Widget>>[];
                          // 🎇 중앙 시즌 조형물 — 민물/바다 양쪽 (kCenterpieceFile — 시즌마다 파일만 교체)
                          if (!widget.isSea) {
                            // 🏞️ 민물광장 시설 포털
                            sprites.add(MapEntry(0.590, _plazaPortal(worldW, worldH, sizeRef, 0.540, 0.590, kCenterpieceFile, kCenterpieceHFrac)));
                            sprites.add(MapEntry(0.663, _plazaPortal(worldW, worldH, sizeRef, 0.110, 0.663, 'portal_rank_fw.png', 0.42)));
                            sprites.add(MapEntry(0.405, _plazaPortal(worldW, worldH, sizeRef, 0.290, 0.405, 'portal_guild_fw.png', 0.40)));
                            sprites.add(MapEntry(0.256, _plazaPortal(worldW, worldH, sizeRef, 0.507, 0.256, 'portal_fishing_fw.png', 0.40)));
                            sprites.add(MapEntry(0.390, _plazaPortal(worldW, worldH, sizeRef, 0.760, 0.390, 'portal_arena_fw.png', 0.42)));
                            sprites.add(MapEntry(0.55, _plazaPortal(worldW, worldH, sizeRef, 0.910, 0.680, 'portal_shop_fw.png', 0.48))); // 깊이키=건물 앞바닥(렌더는 0.680), 앞 캐릭터 안 가리게
                            sprites.add(MapEntry(0.897, _plazaPortal(worldW, worldH, sizeRef, 0.480, 0.897, 'portal_quest_fw.png', 0.36)));
                          } else {
                            // 🌊 바다광장 시설 포털 (민물 포털 재활용, 좌표만 바다용 — 좌표모드로 미세조정 예정 · 추정값)
                            sprites.add(MapEntry(0.483, _plazaPortal(worldW, worldH, sizeRef, 0.533, 0.483, kCenterpieceFile, kCenterpieceHFrac)));
                            sprites.add(MapEntry(0.910, _plazaPortal(worldW, worldH, sizeRef, 0.287, 0.910, 'portal_rank_fw.png', 0.42)));
                            sprites.add(MapEntry(0.411, _plazaPortal(worldW, worldH, sizeRef, 0.154, 0.411, 'portal_guild_fw.png', 0.40)));
                            sprites.add(MapEntry(0.330, _plazaPortal(worldW, worldH, sizeRef, 0.350, 0.330, 'portal_fishing_fw.png', 0.40)));
                            sprites.add(MapEntry(0.310, _plazaPortal(worldW, worldH, sizeRef, 0.640, 0.310, 'portal_arena_fw.png', 0.42)));
                            sprites.add(MapEntry(0.52, _plazaPortal(worldW, worldH, sizeRef, 0.900, 0.650, 'portal_shop_fw.png', 0.48))); // 렌더 0.650(여백보정), 깊이키 0.52
                            sprites.add(MapEntry(0.913, _plazaPortal(worldW, worldH, sizeRef, 0.754, 0.913, 'portal_quest_fw.png', 0.36, flip: true)));
                          }
                          // 🧍 내 캐릭터 (탭 통과)
                          sprites.add(MapEntry(_charPos.dy, AnimatedPositioned(
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
                                              errorBuilder: (a, b, d) => Image.asset(
                                                _charImage,
                                                fit: BoxFit.contain,
                                                alignment: Alignment.bottomCenter,
                                                errorBuilder: (a2, b2, d2) => const SizedBox.shrink(),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                      Positioned(
                                        bottom: charH * 0.62,
                                        left: -150,
                                        right: -150,
                                        child: Center(
                                          child: _nameTag(widget.nickname, _guildName,
                                              isMe: true, champ: _isChampionGuild,
                                              garamRank: _myGaramRank),
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
                          )));
                          // 🌐 다른 유저들 (45초 이상 갱신 없는 고스트 숨김)
                          for (final e in _others.entries.where((e) =>
                              DateTime.now().millisecondsSinceEpoch - ((e.value['t'] as int?) ?? 0) < 45000)) {
                            final ry = (e.value['y'] is num) ? (e.value['y'] as num).toDouble() : 0.9;
                            sprites.add(MapEntry(ry, _remoteAvatar(e.key, e.value, worldW, worldH, sizeRef)));
                          }
                          // 발높이(y) 오름차순 → 위(뒤)부터 그림 → 아래(앞)가 위에 겹침
                          sprites.sort((a, b) => a.key.compareTo(b.key));
                          return sprites.map((e) => e.value).toList();
                        })(),
                        // 4) 시설 NPC (각 시설 앞에 한 명씩) — img 없으면 임시 fallback
                        _standNpc(worldW, worldH, sizeRef, widget.isSea ? 0.307 : 0.146,
                            widget.isSea ? 0.930 : 0.662, 'npc_rank.png', 'gm_garam.png', '가람', '🏆 랭킹',
                            _onGaramTap,
                            scale: 1.0),
                        _standNpc(worldW, worldH, sizeRef, widget.isSea ? 0.134 : 0.294,
                            widget.isSea ? 0.451 : 0.424, 'npc_guild.png', 'npc_manager_congrats.png', '윤슬', '🛡️ 길드',
                            () => _openNpcIntro('npc_guild.png', 'guild', '길드 보기', _openGuild),
                            scale: 0.85),
                        _standNpc(worldW, worldH, sizeRef, widget.isSea ? 0.350 : 0.500,
                            widget.isSea ? 0.340 : 0.270, 'npc_fishing.png', 'npc_girl_intro.png', '나루', '🌀 낚시터',
                            () => _openNpcIntro('npc_fishing.png', 'fishing', '낚시터 이동', _openMinimap),
                            scale: 0.9),
                        _standNpc(worldW, worldH, sizeRef, widget.isSea ? 0.610 : 0.725,
                            widget.isSea ? 0.310 : 0.391, 'npc_arena.png', 'npc_girl_point.png', '한별', '⚔️ 아레나',
                            _onHanbyeolTap,
                            scale: 0.82),
                        _standNpc(worldW, worldH, sizeRef, widget.isSea ? 0.900 : 0.910,
                            widget.isSea ? 0.600 : 0.630, 'npc_shop.png', 'npc_manager.png', '서윤', '🏪 상점',
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

              // 🎓 튜토리얼 — 시작 안내 (아라)
              if (_showTutIntro)
                Positioned.fill(
                  child: NpcTutorialOverlay(
                    text: '${widget.nickname} 조사님, 환영해요! 🎣\n저는 캠피싱 매니저 아라예요.\n\n첫걸음 튜토리얼을 준비했어요!\n느낌표❗를 따라 NPC를 만나 보세요\n지금 시작할까요?',
                    imagePath: 'assets/images/npc_manager_quest.png',
                    onTap: () {},
                    action: Row(mainAxisSize: MainAxisSize.min, children: [
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: _kGold, foregroundColor: Colors.black, padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14), textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
                        onPressed: () { setState(() => _showTutIntro = false); _startTutorial(); },
                        child: const Text('튜토리얼 시작 🚀'),
                      ),
                      const SizedBox(width: 12),
                      TextButton(onPressed: () => setState(() => _showTutIntro = false), child: const Text('나중에', style: TextStyle(color: Colors.white70, fontSize: 16, fontWeight: FontWeight.bold))),
                    ]),
                  ),
                ),

              // 🎓 튜토리얼 — 타겟 NPC 미션 설명
              if (_showTutMission && _tutQuestNow != null)
                Positioned.fill(
                  child: NpcTutorialOverlay(
                    text: '[${_tutQuestNow!['title']}]\n\n${_tutQuestNow!['desc']}',
                    imagePath: 'assets/images/npc_${_tutQuestNow!['npc']}.png',
                    onTap: () {},
                    action: ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: _kGold, foregroundColor: Colors.black, padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14), textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
                      onPressed: () {
                        final q = _tutQuestNow;
                        final enter = _tutMissionEnter;
                        setState(() => _showTutMission = false);
                        // 랭킹·길드·아레나는 '열면 완료' → 먼저 완료 처리 후 화면 열기(누락 방지).
                        //   낚시터(첫 고기)·상점(구매)은 별도 처리(해당 화면에서).
                        if (q != null && (q['npc'] == 'rank' || q['npc'] == 'guild' || q['npc'] == 'arena')) {
                          _clearTutMission(q['npc']!);
                        }
                        enter?.call(); // 기능 열기(랭킹/길드/아레나/상점/낚시터)
                      },
                      child: const Text('확인하러 가기 👉'),
                    ),
                  ),
                ),

              // 🎓 튜토리얼 — 아라 보상 받기
              if (_showTutReward && _tutQuestNow != null)
                Positioned.fill(
                  child: NpcTutorialOverlay(
                    text: '${_tutQuestNow!['done']}\n\n🎁 보상: 경험치 $_tutExp · 포인트 $_tutPts',
                    imagePath: 'assets/images/npc_manager_quest.png',
                    onTap: () {},
                    action: ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF7FFFB0), foregroundColor: Colors.black, padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14), textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
                      onPressed: () {
                        setState(() => _showTutReward = false);
                        _claimTutReward();
                        _toast('🎁 경험치 +$_tutExp · 포인트 +$_tutPts!');
                      },
                      child: const Text('보상 받기 🎁'),
                    ),
                  ),
                ),

              // 🎁 오늘 첫 접속 보상 안내 오버레이 (아라)
              if (_showReward)
                Positioned.fill(
                  child: NpcTutorialOverlay(
                    text: _getWelcomeText(),
                    imagePath: 'assets/images/npc_manager_quest.png',
                    onTap: () => setState(() => _showReward = false),
                    action: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                          backgroundColor: _kGold, foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                          textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                      onPressed: () {
                        setState(() => _showReward = false);
                        // 🎓 신규 유저면 환영 닫고 튜토리얼 시작 안내로
                        if (_tutStep == 0 && !_tutIntroShown) { _tutIntroShown = true; setState(() => _showTutIntro = true); }
                      },
                      child: const Text('낚시하러 가기 🎣'),
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

              // 🌧️ 실시간 날씨 오버레이(비/눈) + 지역·날씨 뱃지
              const Positioned.fill(
                child: IgnorePointer(child: WeatherOverlay()),
              ),
              const Positioned(
                top: 8, left: 0, right: 0,
                child: IgnorePointer(child: Center(child: WeatherBadge())),
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
    final cx = widget.isSea ? 0.734 : 0.513;
    final cy = widget.isSea ? 0.913 : 0.920; // 발 위치 (민물 / 바다=새 배치)
    // 🧍 원근 크기(아주 약하게)
    final double pT = ((cy - 0.22) / (0.96 - 0.22)).clamp(0.0, 1.0);
    final figH = sizeH * (0.27 + pT * 0.03);
    final figW = figH * 0.6;
    final araTut = _tutStep == 0 || (_tutQuestNow != null && _tutCleared); // ❗ 튜토리얼 표시 조건
    final araBang = araTut || (_tutStep == 99 && !_questDone); // 📋 일일 미션 미완료면 ❗
    return Positioned(
      left: cx * worldW - figW / 2,
      top: cy * worldH - figH, // 발이 cy에 오도록(그림 bottomCenter)
      width: figW,
      height: figH,
      child: GestureDetector(
        onTap: _onAraTap,
        behavior: HitTestBehavior.opaque,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // 🌊 바다광장이면 '_sea' 변형 먼저 시도 → 없으면 기본 이미지
            Positioned.fill(
              child: Image.asset('assets/images/${widget.isSea ? 'npc_manager_quest_sea.png' : 'npc_manager_quest.png'}',
                  fit: BoxFit.contain,
                  alignment: Alignment.bottomCenter,
                  errorBuilder: (a, b, c) => Image.asset('assets/images/npc_manager_quest.png',
                      fit: BoxFit.contain,
                      alignment: Alignment.bottomCenter,
                      errorBuilder: (a2, b2, c2) => const SizedBox.shrink())),
            ),
            // 🏷️ 이름만 (박스·부연설명 없이) — 머리 바로 위에 그림자로 띄움
            Positioned(
              bottom: figH * 0.62,
              left: -90,
              right: -90,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                if (araBang) Center(child: _tutBang()), // ❗ 고정 높이 없이(안 잘리게)
                if (araBang) const SizedBox(height: 2),
                const Center(
                  child: Text('아라',
                      style: TextStyle(
                        color: _kGold,
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        shadows: [
                          Shadow(color: Colors.black, blurRadius: 4, offset: Offset(0, 1)),
                          Shadow(color: Colors.black, blurRadius: 2),
                        ],
                      )),
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  // 🧍 시설 NPC (포털/시설 앞에 한 명씩 세움). img 없으면 fallback 이미지로.
  Widget _standNpc(double worldW, double worldH, double sizeH, double cx, double cy,
      String img, String fallback, String name, String label, VoidCallback onTap, {double scale = 1.0}) {
    // 🧍 원근 크기(아주 약하게): 나루(먼 쪽) 기존 크기 기준 + 가까울수록 살짝만 큼. scale=NPC별 보정.
    final double pT = ((cy - 0.22) / (0.96 - 0.22)).clamp(0.0, 1.0);
    final figH = sizeH * (0.27 + pT * 0.03) * scale;
    final figW = figH * 0.6;
    final bool isTutTarget = _tutQuestNow != null && !_tutCleared && _tutQuestNow!['name'] == name; // 🎓 현재 퀘스트 타겟
    // 🛡️ 윤슬(길드): Lv.3 이상 + 길드 미가입이면 '가입 가능' 퀘스트 느낌표
    final bool isJoinQuest = name == '윤슬' && _level >= 3 && _guildId.isEmpty;
    // 🛍️ 서윤: 오늘 지정어 배달 일일이 아직 안 끝났으면 접속 시 ❗ (완료하면 사라짐)
    final bool isBobaeQuest = name == '서윤' && _tutQuestNow == null && !_bobaeDone;
    // 🥊 한별: 오늘 아레나 일일 미완료면 ❗ (승리해서 보상받을 게 있거나, 아직 도전 기회 남음)
    final bool isHanbyeolQuest = name == '한별' && _tutQuestNow == null && !_hanbyeolClaimed && (_hanbyeolWon || _arenaCount < 2);
    final bool bang = isTutTarget || isJoinQuest || isBobaeQuest || isHanbyeolQuest;
    return Positioned(
      left: cx * worldW - figW / 2,
      top: cy * worldH - figH, // 발이 cy에 오도록(그림은 bottomCenter로 하단 정렬)
      width: figW,
      height: figH,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // NPC 그림 (발=하단). 바다광장이면 '_sea' 변형 먼저 시도.
            Positioned.fill(
              child: Image.asset('assets/images/${widget.isSea ? img.replaceFirst('.png', '_sea.png') : img}',
                  fit: BoxFit.contain,
                  alignment: Alignment.bottomCenter,
                  errorBuilder: (a, b, c) => Image.asset('assets/images/$img',
                      fit: BoxFit.contain,
                      alignment: Alignment.bottomCenter,
                      errorBuilder: (a1, b1, c1) => Image.asset('assets/images/$fallback',
                          fit: BoxFit.contain,
                          alignment: Alignment.bottomCenter,
                          errorBuilder: (a2, b2, c2) => const SizedBox.shrink()))),
            ),
            // 🏷️ 이름만 (박스·부연설명 없이) — 머리 바로 위에 그림자로 띄움
            Positioned(
              bottom: figH * 0.62,
              left: -90,
              right: -90,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                if (bang) Center(child: _tutBang()), // ❗ 고정 높이 없이(안 잘리게)
                if (bang) const SizedBox(height: 2),
                Center(
                  child: Text(name,
                      style: const TextStyle(
                        color: _kGold,
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        shadows: [
                          Shadow(color: Colors.black, blurRadius: 4, offset: Offset(0, 1)),
                          Shadow(color: Colors.black, blurRadius: 2),
                        ],
                      )),
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  // 🏞️ 시설 포털(배경 위 장식) — 바닥 중앙을 (cx,cy) 발높이에 맞춰 세움. 캐릭터/NPC보다 뒤에 그려짐.
  Widget _plazaPortal(double worldW, double worldH, double sizeRef, double cx, double cy, String file, double hFrac, {bool flip = false}) {
    return Positioned(
      left: cx * worldW,
      top: cy * worldH, // 포털 바닥 = 찍은 좌표(=NPC 발 위치). NPC의 -58은 이름표 높이라 포털엔 불필요.
      child: IgnorePointer(
        child: FractionalTranslation(
          translation: const Offset(-0.5, -1.0), // 바닥 중앙 앵커
          child: Transform.flip(
            flipX: flip, // 🔄 좌우 반전 옵션
            child: Image.asset('assets/plaza/$file',
              height: sizeRef * hFrac,
              fit: BoxFit.contain,
              errorBuilder: (a, b, c) => const SizedBox.shrink())),
        ),
      ),
    );
  }

  // 🎒 인벤토리 (읽기 전용 보기)
  String _itemIconPath(String icon) {
    if (icon.isEmpty) return 'assets/items/rod_fw_cf20.png';
    // 🐟 물고기 수집 이미지: 어떤 폴더로 저장됐든 실제 위치로 보정
    final file = icon.split('/').last;
    if (file.startsWith('fish_fw')) return 'assets/fish_fw/$file';
    if (file.startsWith('fish_sea')) return 'assets/fish_sea/$file';
    if (icon.startsWith('../images/')) return 'assets/${icon.substring(3)}';
    if (icon.startsWith('assets/')) return icon;
    return 'assets/items/$icon';
  }

  // 👕 이 아이템이 지금 착용 중인지(어느 슬롯이든 이름 일치) — 가방 체크표시용
  bool _isEquippedInPlaza(Map<String, dynamic> item) {
    final nm = item['name'];
    if (nm == null) return false;
    bool m(Map<String, dynamic>? g) => g != null && g['name'] == nm;
    return m(globalEquippedSkin) || m(globalEquippedRod) || m(globalEquippedFloat) ||
        m(globalEquippedReel) || m(globalEquippedSunglasses) || m(globalEquippedBadge) ||
        m(globalEquippedCooler) || m(globalEquippedBait) || m(globalEquippedNet) ||
        m(globalEquippedBelt) || m(globalEquippedGloves) || m(globalEquippedLine) ||
        m(globalEquippedGroundbait);
  }

  Widget _invItem(Map<String, dynamic> item) {
    final name = item['name']?.toString() ?? '';
    final qty = item['quantity'];
    final icon = _itemIconPath(item['icon']?.toString() ?? '');
    final equipped = _isEquippedInPlaza(item); // ✅ 착용 중이면 체크 표시
    return Container(
      decoration: BoxDecoration(
        color: equipped ? const Color(0xFF2A2410) : Colors.grey.shade900,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: equipped ? _kGold : Colors.white12, width: equipped ? 1.6 : 1),
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
                if (equipped)
                  const Positioned(
                    top: 4,
                    right: 4,
                    child: Icon(Icons.check_circle, color: _kGold, size: 18),
                  ),
                if (qty != null)
                  Positioned(
                    right: 4,
                    bottom: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                          color: Colors.black87, borderRadius: BorderRadius.circular(6)),
                      child: Text('$qty${(item['type'] ?? '') == 'FISH' ? '마리' : '개'}',
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
      const SizedBox(height: 3),
      Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w800)),
    ]);
  }

  Widget _statBreakRow(String name, Color color, int equipV, int levelV, int guildV, int champV, [int rankV = 0]) {
    final total = 10 + equipV + levelV + guildV + champV + rankV;
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
            if (rankV != 0) chip('🏆 +$rankV', const Color(0xFFFFE082)),
          ]),
        ),
      ]),
    );
  }

  Widget _statusStats(bool isSea) {
    // 👕 선택 모드(민물/바다)에 맞는 장비만 합산 (COMMON은 항상 포함) — 낚시터 실제 적용과 동일 기준
    Map<String, dynamic>? fm(Map<String, dynamic>? it) {
      if (it == null) return null;
      final c = (it['category'] ?? '').toString().toUpperCase();
      if (c == 'COMMON') return it;
      return c == (isSea ? 'SEA' : 'FW') ? it : null;
    }
    final equip = FishingLogic.getMyTotalStats(
      equippedSkin: globalEquippedSkin,     // 스킨은 공용(모드 무관)
      equippedRod: fm(globalEquippedRod),
      equippedFloat: isSea ? null : globalEquippedFloat,
      equippedReel: isSea ? globalEquippedReel : null,
      equippedSunglasses: globalEquippedSunglasses,
      equippedBadge: fm(globalEquippedBadge),
      equippedCooler: globalEquippedCooler,
      equippedBait: fm(globalEquippedBait),     // 🪱 미끼 감도(S)
      equippedNet: fm(globalEquippedNet),       // 🥅 뜰채(C)
      equippedBelt: fm(globalEquippedBelt),     // 🎽 파워벨트(P, 바다 전용)
      equippedGloves: globalEquippedGloves, // 🧤 장갑(P)
      equippedLine: fm(globalEquippedLine),           // 🧵 낚시줄(P)
      equippedGroundbait: fm(globalEquippedGroundbait), // 🍚 밑밥(S) — 미리보기(실제는 낚시터 세션에만)
    );
    final eP = (equip['strength'] ?? 10) - 10;
    final eC = (equip['control'] ?? 10) - 10;
    final eS = (equip['sensitivity'] ?? 10) - 10;

    Widget body(int gLevel) {
      final lvB = (_level - 1) < 0 ? 0 : (_level - 1); // 🆙 레벨 보너스(각 +1/레벨) — 낚시 전투력과 동일
      final gB = FishingLogic.guildStatBonus(gLevel);
      final cB = _isChampionGuild ? FishingLogic.guildChampionBonus : 0;
      final rB = garamRankBonus(_myGaramRank); // 🎖️ 주간 개인랭킹 보너스(1주일)
      final totP = 10 + eP + lvB + gB + cB + rB, totC = 10 + eC + lvB + gB + cB + rB, totS = 10 + eS + lvB + gB + cB + rB;
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text('Lv.$_level', style: const TextStyle(color: _kGold, fontSize: 17, fontWeight: FontWeight.w900)),
            const SizedBox(width: 8),
            Text(_rank,
                style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
            const Spacer(),
            // 💪 총 제압력 — 상단으로 올려 한눈에
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                  color: const Color(0xFF22301F),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFF7FFFB0).withOpacity(0.5))),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Text('총 제압력 ', style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold)),
                Text('${totP + totC + totS}',
                    style: const TextStyle(color: Color(0xFF7FFFB0), fontSize: 19, fontWeight: FontWeight.w900)),
              ]),
            ),
          ]),
          const SizedBox(height: 4),
          Row(children: [
            Flexible(
              child: Text('경험치 $currentExp · 포인트 $_gold',
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white54, fontSize: 11)),
            ),
            const SizedBox(width: 10),
            if (_guildName.isNotEmpty)
              Text(_isChampionGuild ? '👑〈$_guildName〉Lv.$gLevel' : '〈$_guildName〉Lv.$gLevel',
                  style: const TextStyle(color: Color(0xFF9FE0FF), fontSize: 12, fontWeight: FontWeight.bold)),
          ]),
          const Divider(color: Colors.white12, height: 18),
          const Text('능력치 (기본 + 장비 + 레벨 + 길드 + 챔피언 + 주간랭킹)',
              style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          _statBreakRow('💪 힘', const Color(0xFFFF8A80), eP, lvB, gB, cB, rB),
          _statBreakRow('🎯 컨트롤', const Color(0xFFFFD180), eC, lvB, gB, cB, rB),
          _statBreakRow('📡 감도', const Color(0xFF80D8FF), eS, lvB, gB, cB, rB),
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
    } else if (n.contains('뜰채')) {
      globalEquippedNet = same(globalEquippedNet) ? null : item;
    } else if (n.contains('벨트')) {
      globalEquippedBelt = same(globalEquippedBelt) ? null : item;
    } else if (n.contains('장갑')) {
      globalEquippedGloves = same(globalEquippedGloves) ? null : item;
    } else if (n.contains('낚시줄')) {
      globalEquippedLine = same(globalEquippedLine) ? null : item;
    } else if (n.contains('밑밥')) {
      globalEquippedGroundbait = same(globalEquippedGroundbait) ? null : item;
    } else {
      globalEquippedBait = same(globalEquippedBait) ? null : item;
    }
    setD(() {}); // 다이얼로그 슬롯·스텟 갱신
    setState(() {}); // 플라자 HUD(아바타/스킨) 갱신
  }

  void _openStatusWindow() {
    String invTab = '전체';
    String equipMode = (globalIsSeaMode == true) ? '바다' : '민물'; // 👕 광장 장비 미리보기 모드(민물/바다)
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
            // 👕 선택 모드(민물/바다)에 맞는 장비만 슬롯·능력치에 반영 (COMMON은 항상)
            final bool seaMode = equipMode == '바다';
            Map<String, dynamic>? forMode(Map<String, dynamic>? it) {
              if (it == null) return null;
              final c = (it['category'] ?? '').toString().toUpperCase();
              if (c == 'COMMON') return it;
              return c == (seaMode ? 'SEA' : 'FW') ? it : null;
            }
            final rodSlot = forMode(globalEquippedRod);
            final reelFloatSlot = seaMode ? globalEquippedReel : globalEquippedFloat;
            final baitSlot = forMode(globalEquippedBait);
            final netSlot = forMode(globalEquippedNet);
            final beltSlot = forMode(globalEquippedBelt);
            final lineSlot = forMode(globalEquippedLine);
            final gbSlot = forMode(globalEquippedGroundbait);
            final badgeSlot = forMode(globalEquippedBadge);
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
                  return (c == 'FW' && t != 'BAIT') || (t == 'ETC' && c != 'SEA') || t == 'COOLER' || (c == 'COMMON' && t != 'BAIT' && t != 'FISH' && t != 'SKIN');
                case '바다':
                  return (c == 'SEA' && t != 'BAIT') || (t == 'ETC' && c != 'FW') || t == 'COOLER' || (c == 'COMMON' && t != 'BAIT' && t != 'FISH' && t != 'SKIN');
                case '미끼':
                  return t == 'BAIT';
                case '물고기':
                  return t == 'FISH';
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
                      // 👕 민물/바다 미리보기 모드 토글 — 선택 모드 장비·제압력만 표시
                      Padding(
                        padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                        child: Row(children: [
                          for (final m in const ['민물', '바다'])
                            Expanded(
                              child: GestureDetector(
                                onTap: () => setD(() { equipMode = m; invTab = m; }),
                                child: Container(
                                  margin: EdgeInsets.only(right: m == '민물' ? 6 : 0),
                                  padding: const EdgeInsets.symmetric(vertical: 7),
                                  decoration: BoxDecoration(
                                    color: equipMode == m
                                        ? (m == '바다' ? const Color(0xFF123A5E) : const Color(0xFF16401F))
                                        : Colors.white10,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                        color: equipMode == m ? _kGold : Colors.white24,
                                        width: equipMode == m ? 1.5 : 1),
                                  ),
                                  child: Text(m == '민물' ? '🏞️ 민물' : '🌊 바다',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                          color: equipMode == m ? Colors.white : Colors.white54,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w900)),
                                ),
                              ),
                            ),
                        ]),
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
                          child: Row(children: [
                            // 🡐 왼쪽 2열
                            Column(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                              _equipSlot('스킨', Icons.checkroom, globalEquippedSkin),
                              _equipSlot('선글라스', Icons.remove_red_eye, globalEquippedSunglasses),
                              _equipSlot('뱃지', Icons.shield, badgeSlot),
                            ]),
                            const SizedBox(width: 4),
                            Column(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                              _equipSlot('낚시대', Icons.phishing, rodSlot),
                              _equipSlot('릴/찌', Icons.album, reelFloatSlot),
                              _equipSlot('미끼', Icons.bug_report, baitSlot),
                            ]),
                            // 캐릭터 (가운데)
                            Expanded(
                              child: Image.asset(_charImage,
                                  fit: BoxFit.contain,
                                  alignment: Alignment.bottomCenter,
                                  errorBuilder: (a, b, c) => const SizedBox.shrink()),
                            ),
                            // 오른쪽 2열 🡒
                            Column(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                              _equipSlot('아이스박스', Icons.ac_unit, globalEquippedCooler),
                              _equipSlot('뜰채', Icons.pool, netSlot),
                              _equipSlot('벨트', Icons.fitness_center, beltSlot),
                            ]),
                            const SizedBox(width: 4),
                            Column(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                              _equipSlot('장갑', Icons.back_hand, globalEquippedGloves),
                              _equipSlot('낚시줄', Icons.linear_scale, lineSlot),
                              _equipSlot('밑밥', Icons.grain, gbSlot),
                            ]),
                          ]),
                        ),
                      ),
                      const Divider(color: Colors.white12, height: 1),
                      // 능력치는 자연 높이로(스크롤 X) → 힘/컨트롤/감도 한 번에 보임. 캐릭터가 위 남는 공간 차지.
                      _statusStats(seaMode),
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
                        tabBtn('물고기'),
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
                                  onTap: () {
                                    _equipFromStatus(items[i], setD);
                                    // 모드 전용 장비를 착용하면 미리보기 모드도 그 모드로 전환
                                    final cc = (items[i]['category'] ?? '').toString().toUpperCase();
                                    if (cc == 'FW' || cc == 'SEA') {
                                      setD(() => equipMode = cc == 'SEA' ? '바다' : '민물');
                                    }
                                  },
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

  // 🗂️ (보관) 인벤토리 단독 보기 — 현재 '내정보' 버튼이 상태창+인벤 합본을 열어서 미사용. 추후 재사용 대비 유지.
  // ignore: unused_element
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
                            Row(children: [
                              Text('길드장 ${g['master'] ?? '-'}  ·  멤버 $mc/$cap명',
                                  style: const TextStyle(color: Colors.white54, fontSize: 11)),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                decoration: BoxDecoration(
                                    color: ((g['joinPolicy'] ?? 'approval') == 'open') ? const Color(0x224CAF50) : Colors.white10,
                                    borderRadius: BorderRadius.circular(5)),
                                child: Text(((g['joinPolicy'] ?? 'approval') == 'open') ? '자유가입' : '승인제',
                                    style: TextStyle(
                                        color: ((g['joinPolicy'] ?? 'approval') == 'open') ? const Color(0xFF7FFFB0) : Colors.white54,
                                        fontSize: 10, fontWeight: FontWeight.bold)),
                              ),
                            ]),
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
                        child: Text(full ? '만원' : (((g['joinPolicy'] ?? 'approval') == 'open') ? '바로가입' : '가입신청'), style: const TextStyle(fontWeight: FontWeight.bold)),
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
        return StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance
              .collection('guilds').doc(gid).collection('members').doc(uid).snapshots(),
          builder: (mctx, mySnap) {
          final myRole = ((mySnap.data?.data() as Map<String, dynamic>?)?['role'] ?? 'member').toString();
          final canManage = isMaster || myRole == 'vice';
          return StatefulBuilder(
          builder: (ctx2, setTab) {
            if (!canManage && _guildTab == 3) _guildTab = 0;
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
                  if (canManage) _guildApplyTabBtn(gid, 3, setTab),
                ]),
                const Divider(color: Colors.white12, height: 1),
                Expanded(
                  child: _guildTab == 1
                      ? _guildPerksTab(gLevel, guildExp)
                      : _guildTab == 2
                          ? _guildSettingsTab(ctx, uid, gid, isMaster, canManage, g)
                          : _guildTab == 3
                              ? _guildApplicationsTab(gid)
                              : _guildMembersTab(gid, uid, isMaster),
                ),
              ],
            );
          },
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

  Widget _guildMembersTab(String gid, String myUid, bool isMaster) {
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
        int rank(String? r) => r == 'master' ? 0 : (r == 'vice' ? 1 : 2);
        final members = msnap.data!.docs
            .map((d) => d.data() as Map<String, dynamic>)
            .toList()
          ..sort((a, b) {
            final ra = rank(a['role'] as String?), rb = rank(b['role'] as String?);
            if (ra != rb) return ra - rb;
            return ((b['contribution'] ?? 0) as num).compareTo((a['contribution'] ?? 0) as num);
          });
        final viceCount = members.where((m) => m['role'] == 'vice').length;
        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          itemCount: members.length,
          itemBuilder: (c, i) {
            final m = members[i];
            final role = (m['role'] ?? 'member').toString();
            final mUid = (m['uid'] ?? '').toString();
            final contrib = (m['contribution'] is num) ? (m['contribution'] as num).toInt() : 0;
            final isMasterRow = role == 'master';
            final isViceRow = role == 'vice';
            final roleColor = isMasterRow ? _kGold : (isViceRow ? const Color(0xFF9FC7FF) : Colors.white38);
            final roleLabel = isMasterRow ? '길드장' : (isViceRow ? '부길드장' : '길드원');
            // 길드장만 액션(위임/부길드장 임명), 대상이 길드장 본인/자기 자신이면 제외
            final canAct = isMaster && !isMasterRow && mUid != myUid;
            return Container(
              margin: const EdgeInsets.symmetric(vertical: 3),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                  color: const Color(0xFF2A2A2A), borderRadius: BorderRadius.circular(8)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  guildOnlineDot(mUid),
                  const SizedBox(width: 8),
                  Icon(isMasterRow ? Icons.military_tech : (isViceRow ? Icons.shield : Icons.person),
                      color: roleColor, size: 18),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(m['nickname']?.toString() ?? '',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(width: 6),
                  Text('Lv.${m['level'] ?? 1}', style: const TextStyle(color: Colors.white38, fontSize: 12)),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: roleColor.withOpacity(0.15), borderRadius: BorderRadius.circular(6)),
                    child: Text(roleLabel, style: TextStyle(color: roleColor, fontSize: 10, fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(width: 6),
                  userLocByUid(mUid, fontSize: 10), // 📍 접속 채널·위치(접속 중일 때만)
                  const Spacer(),
                  if (canAct)
                    SizedBox(
                      width: 28, height: 28,
                      child: PopupMenuButton<String>(
                        padding: EdgeInsets.zero,
                        icon: const Icon(Icons.more_vert, color: Colors.white54, size: 18),
                        color: const Color(0xFF2A2A2A),
                        onSelected: (v) {
                          if (v == 'vice') _toggleVice(gid, m, viceCount);
                          else if (v == 'master') _transferMaster(gid, myUid, m);
                          else if (v == 'kick') _kickMember(gid, m);
                        },
                        itemBuilder: (_) => [
                          PopupMenuItem(value: 'vice', child: Text(isViceRow ? '부길드장 해제' : '부길드장 임명',
                              style: const TextStyle(color: Colors.white, fontSize: 13))),
                          const PopupMenuItem(value: 'master', child: Text('길드장 위임',
                              style: TextStyle(color: _kGold, fontSize: 13))),
                          const PopupMenuItem(value: 'kick', child: Text('길드에서 추방',
                              style: TextStyle(color: Colors.redAccent, fontSize: 13))),
                        ],
                      ),
                    ),
                ]),
                const SizedBox(height: 4),
                Row(children: [
                  const SizedBox(width: 26),
                  const Icon(Icons.emoji_events, color: Color(0xFF7FBFFF), size: 13),
                  const SizedBox(width: 3),
                  Text('기여 $contrib', style: const TextStyle(color: Color(0xFF9FC7FF), fontSize: 11, fontWeight: FontWeight.w600)),
                  const SizedBox(width: 12),
                  const Icon(Icons.schedule, color: Colors.white24, size: 12),
                  const SizedBox(width: 3),
                  guildLastSeen(mUid),
                ]),
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

  Widget _guildSettingsTab(BuildContext ctx, String uid, String gid, bool isMaster, bool canManage, Map<String, dynamic> g) {
    final String policy = (g['joinPolicy'] ?? 'approval').toString(); // 기본 승인제(기존 호환)
    final bool isOpen = policy == 'open';
    Widget policyBtn(String label, String sub, bool active, VoidCallback onTap) {
      return Expanded(
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 4),
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
            decoration: BoxDecoration(
              color: active ? const Color(0x22D4AF37) : Colors.white10,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: active ? _kGold : Colors.white24, width: active ? 1.6 : 1),
            ),
            child: Column(children: [
              Text(label, style: TextStyle(color: active ? _kGold : Colors.white70, fontSize: 14, fontWeight: FontWeight.w900)),
              const SizedBox(height: 3),
              Text(sub, textAlign: TextAlign.center, style: TextStyle(color: active ? Colors.white70 : Colors.white38, fontSize: 11, height: 1.25)),
            ]),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 🚪 가입 방식 설정 (길드장만)
          if (isMaster) ...[
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('가입 방식', style: TextStyle(color: _kGold, fontSize: 14, fontWeight: FontWeight.w900)),
            ),
            const SizedBox(height: 8),
            Row(children: [
              policyBtn('✅ 자유 가입', '신청 즉시 바로 가입\n(승인 대기 없음)', isOpen, () { if (!isOpen) _setJoinPolicy(gid, 'open'); }),
              policyBtn('🔒 승인 후 가입', '길드장·부길드장이\n승인해야 가입', !isOpen, () { if (isOpen) _setJoinPolicy(gid, 'approval'); }),
            ]),
            const SizedBox(height: 8),
            Text(isOpen ? '지금은 누구나 승인 없이 바로 가입할 수 있어요.' : '지금은 승인을 받아야 가입할 수 있어요.',
                style: const TextStyle(color: Colors.white54, fontSize: 12)),
            const Divider(color: Colors.white12, height: 28),
          ],
          if (canManage) ...[
            // ⚔️ 길드전 (예약) — 길드장/부길드장 권한 자리
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white38,
                  side: const BorderSide(color: Colors.white24),
                  padding: const EdgeInsets.symmetric(vertical: 12)),
              icon: const Icon(Icons.sports_kabaddi, size: 18),
              label: const Text('길드전 신청 (준비 중)', style: TextStyle(fontWeight: FontWeight.bold)),
              onPressed: () => _infoPopup('길드전', '길드전(길드 대 길드 대전)은 곧 열릴 예정이에요! ⚔️\n길드장·부길드장이 신청할 수 있게 됩니다.'),
            ),
            const SizedBox(height: 16),
          ],
          Text(
              isMaster
                  ? '길드장은 길드원이 모두 나가 혼자 남았을 때만 해체할 수 있어요.\n길드를 넘기려면 길드원 목록에서 "길드장 위임"을 이용하세요.'
                  : '길드를 탈퇴할 수 있어요.\n언제든 다시 가입 신청할 수 있습니다.',
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

  // 📨 가입신청 탭 (길드장/부길드장만) — 승인/거절
  Widget _guildApplicationsTab(String gid) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('guilds').doc(gid).collection('applications').snapshots(),
      builder: (c, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator(color: _kGold));
        }
        final apps = snap.data!.docs.map((d) => d.data() as Map<String, dynamic>).toList();
        if (apps.isEmpty) {
          return const Center(
              child: Text('대기 중인 가입 신청이 없어요.',
                  style: TextStyle(color: Colors.white38, fontSize: 13)));
        }
        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          itemCount: apps.length,
          itemBuilder: (c, i) {
            final a = apps[i];
            final aUid = (a['uid'] ?? '').toString();
            return Container(
              margin: const EdgeInsets.symmetric(vertical: 3),
              padding: const EdgeInsets.only(left: 12, right: 4, top: 4, bottom: 4),
              decoration: BoxDecoration(
                  color: const Color(0xFF2A2A2A), borderRadius: BorderRadius.circular(8)),
              child: Row(children: [
                const Icon(Icons.person_add, color: Color(0xFF9FC7FF), size: 18),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(a['nickname']?.toString() ?? '',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                ),
                const SizedBox(width: 6),
                Text('Lv.${a['level'] ?? 1}', style: const TextStyle(color: Colors.white38, fontSize: 12)),
                const Spacer(),
                IconButton(
                    icon: const Icon(Icons.check_circle, color: Color(0xFF4CD964)),
                    iconSize: 26, tooltip: '승인',
                    onPressed: () => _approveApplication(gid, a)),
                IconButton(
                    icon: const Icon(Icons.cancel, color: Colors.redAccent),
                    iconSize: 24, tooltip: '거절',
                    onPressed: () => _rejectApplication(gid, aUid)),
              ]),
            );
          },
        );
      },
    );
  }

  // 가입신청 탭 버튼 (대기 건수 빨간 뱃지)
  Widget _guildApplyTabBtn(String gid, int index, void Function(void Function()) setTab) {
    return Expanded(
      child: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('guilds').doc(gid).collection('applications').snapshots(),
        builder: (c, s) {
          final n = s.data?.docs.length ?? 0;
          final active = _guildTab == index;
          return GestureDetector(
            onTap: () => setTab(() => _guildTab = index),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: active ? _kGold : Colors.transparent, width: 3)),
              ),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text('가입신청',
                    style: TextStyle(
                        color: active ? _kGold : Colors.white54,
                        fontSize: 14, fontWeight: active ? FontWeight.w900 : FontWeight.bold)),
                if (n > 0) ...[
                  const SizedBox(width: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(color: Colors.redAccent, borderRadius: BorderRadius.circular(8)),
                    child: Text('$n', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                  ),
                ],
              ]),
            ),
          );
        },
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
      _yunseulSay('길드를 만드시게요? 멋져요! 😊\n길드 생성은 Lv.10부터 가능해요.\n조금 더 성장한 뒤 도전하세요!\n\n(현재 Lv.$_level)');
      return;
    }
    if (_gold < 10000) {
      _yunseulSay('길드 생성에는 10,000 P가 필요해요. 💰\n포인트를 좀 더 모아서 와주세요!\n\n(현재 $_gold P)');
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
      'joinPolicy': 'approval', // 🚪 기본 승인제 (길드장이 설정에서 자유가입으로 변경 가능)
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

  // 🚪 가입 방식 변경 (길드장) — 'open'(자유) / 'approval'(승인제)
  Future<void> _setJoinPolicy(String gid, String policy) async {
    try {
      await FirebaseFirestore.instance.collection('guilds').doc(gid).update({'joinPolicy': policy});
      _toast(policy == 'open' ? '자유 가입으로 바꿨어요. (승인 없이 바로 가입) ✅' : '승인 후 가입으로 바꿨어요. 🔒');
    } catch (e) {
      _infoPopup('변경 실패', e.toString());
    }
  }

  Future<void> _joinGuild(String uid, String gid, String gname) async {
    // 🎓 길드 가입은 Lv.3부터 (저렙은 '좀 더 커서 오세요')
    if (_level < 3) {
      _yunseulSay('아직 일러요, 조사님! 🐣\n길드 가입은 Lv.3부터 가능해요.\n조금 더 키워서 다시 와주세요!\n\n(현재 Lv.$_level)');
      return;
    }
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
      final gsnap = await guildRef.get();
      if (!gsnap.exists) { _infoPopup('신청 불가', '길드가 사라졌어요.'); return; }
      final data = gsnap.data() ?? {};
      final mc = (data['memberCount'] is num) ? (data['memberCount'] as num).toInt() : 0;
      final gExp = (data['guildExp'] is num) ? (data['guildExp'] as num).toInt() : 0;
      final cap = FishingLogic.guildMaxMembers(FishingLogic.guildLevelFromExp(gExp));
      if (mc >= cap) {
        _infoPopup('신청 불가', '길드 인원이 가득 찼어요. (최대 $cap명)\n길드 레벨을 올리면 정원이 늘어나요.');
        return;
      }
      // 🚪 자유 가입(open) 길드 → 승인 없이 바로 가입 처리
      final policy = (data['joinPolicy'] ?? 'approval').toString();
      if (policy == 'open') {
        await fs.runTransaction((tx) async {
          final gs = await tx.get(guildRef);
          if (!gs.exists) throw '길드가 사라졌어요.';
          final dd = gs.data() ?? {};
          final mc2 = (dd['memberCount'] is num) ? (dd['memberCount'] as num).toInt() : 0;
          final ge2 = (dd['guildExp'] is num) ? (dd['guildExp'] as num).toInt() : 0;
          final cap2 = FishingLogic.guildMaxMembers(FishingLogic.guildLevelFromExp(ge2));
          if (mc2 >= cap2) throw '길드 인원이 가득 찼어요. (최대 $cap2명)';
          tx.set(guildRef.collection('members').doc(uid), {
            'uid': uid,
            'nickname': widget.nickname,
            'role': 'member',
            'level': _level,
            'contribution': 0,
            'joinedAt': FieldValue.serverTimestamp(),
          });
          tx.update(guildRef, {'memberCount': FieldValue.increment(1)});
          tx.update(fs.collection('users').doc(uid), {
            'guildId': gid,
            'guildName': dd['name'] ?? gname,
          });
          tx.delete(guildRef.collection('applications').doc(uid)); // 혹시 남아있던 신청 정리
        });
        _infoPopup('가입 완료', '"$gname" 길드에 바로 가입했어요! 🎉\n(자유 가입 길드)');
        return;
      }
      // 🔒 승인제(approval) → 가입 신청
      final appRef = guildRef.collection('applications').doc(uid);
      final appSnap = await appRef.get();
      if (appSnap.exists) {
        _infoPopup('신청 완료됨', '이미 가입 신청을 넣었어요. ⏳\n길드장/부길드장의 승인을 기다려주세요.');
        return;
      }
      await appRef.set({
        'uid': uid,
        'nickname': widget.nickname,
        'level': _level,
        'appliedAt': FieldValue.serverTimestamp(),
      });
      _infoPopup('가입 신청 완료', '"$gname" 길드에 가입 신청했어요! ⏳\n길드장·부길드장이 승인하면 가입됩니다.');
    } catch (e) {
      _infoPopup('신청 불가', e.toString());
    }
  }

  // ✅ 가입 신청 승인 (길드장/부길드장) — 정원 체크 후 멤버 추가 + 신청 삭제
  Future<void> _approveApplication(String gid, Map<String, dynamic> app) async {
    final fs = FirebaseFirestore.instance;
    final guildRef = fs.collection('guilds').doc(gid);
    final appUid = (app['uid'] ?? '').toString();
    if (appUid.isEmpty) return;
    try {
      await fs.runTransaction((tx) async {
        final gsnap = await tx.get(guildRef);
        if (!gsnap.exists) throw '길드가 사라졌어요.';
        final d = gsnap.data() ?? {};
        final mc = (d['memberCount'] is num) ? (d['memberCount'] as num).toInt() : 0;
        final gExp = (d['guildExp'] is num) ? (d['guildExp'] as num).toInt() : 0;
        final cap = FishingLogic.guildMaxMembers(FishingLogic.guildLevelFromExp(gExp));
        if (mc >= cap) throw '길드 인원이 가득 찼어요. (최대 $cap명)';
        tx.set(guildRef.collection('members').doc(appUid), {
          'uid': appUid,
          'nickname': app['nickname'] ?? '',
          'role': 'member',
          'level': app['level'] ?? 1,
          'contribution': 0,
          'joinedAt': FieldValue.serverTimestamp(),
        });
        tx.update(guildRef, {'memberCount': FieldValue.increment(1)});
        tx.update(fs.collection('users').doc(appUid), {
          'guildId': gid,
          'guildName': gsnap.data()?['name'] ?? '',
        });
        tx.delete(guildRef.collection('applications').doc(appUid));
      });
      _toast('${app['nickname']} 님의 가입을 승인했어요. 🎉');
    } catch (e) {
      _infoPopup('승인 불가', e.toString());
    }
  }

  // ❌ 가입 신청 거절
  Future<void> _rejectApplication(String gid, String appUid) async {
    try {
      await FirebaseFirestore.instance
          .collection('guilds').doc(gid)
          .collection('applications').doc(appUid).delete();
      _toast('신청을 거절했어요.');
    } catch (_) {}
  }

  // 🥈 부길드장 임명/해제 (길드장만, 최대 3명)
  Future<void> _toggleVice(String gid, Map<String, dynamic> m, int viceCount) async {
    final mUid = (m['uid'] ?? '').toString();
    if (mUid.isEmpty) return;
    final isVice = m['role'] == 'vice';
    if (!isVice && viceCount >= 3) {
      _infoPopup('임명 불가', '부길드장은 최대 3명까지만 둘 수 있어요.');
      return;
    }
    try {
      await FirebaseFirestore.instance
          .collection('guilds').doc(gid)
          .collection('members').doc(mUid)
          .update({'role': isVice ? 'member' : 'vice'});
      _toast(isVice ? '${m['nickname']} 님을 길드원으로 되돌렸어요.' : '${m['nickname']} 님을 부길드장으로 임명했어요. 🥈');
    } catch (_) {}
  }

  // 🚫 길드원 추방 (길드장만) — 장기 미접자 등 정리용
  Future<void> _kickMember(String gid, Map<String, dynamic> m) async {
    final mUid = (m['uid'] ?? '').toString();
    if (mUid.isEmpty) return;
    final nick = (m['nickname'] ?? '조사').toString();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: Colors.redAccent, width: 1.2)),
        title: const Text('길드원 추방', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 20)),
        content: Text('$nick 님을 길드에서 추방할까요?\n(추방돼도 나중에 다시 가입 신청은 가능해요)', style: const TextStyle(color: Colors.white, fontSize: 16, height: 1.5)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('취소', style: TextStyle(color: Colors.white54, fontSize: 15, fontWeight: FontWeight.bold))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12)),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('추방', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final fs = FirebaseFirestore.instance;
    final guildRef = fs.collection('guilds').doc(gid);
    try {
      final batch = fs.batch();
      batch.delete(guildRef.collection('members').doc(mUid));
      batch.update(guildRef, {'memberCount': FieldValue.increment(-1)});
      // 추방된 유저의 소속 해제 (다음 접속 시 반영). 추방은 24h 재가입 제한 없음.
      batch.set(fs.collection('users').doc(mUid), {'guildId': '', 'guildName': ''}, SetOptions(merge: true));
      await batch.commit();
      _toast('$nick 님을 길드에서 추방했어요.');
    } catch (e) {
      _infoPopup('추방 실패', e.toString());
    }
  }

  // 👑 길드장 위임 (길드장만) — 대상 멤버가 길드장이 되고 본인은 길드원으로
  Future<void> _transferMaster(String gid, String myUid, Map<String, dynamic> m) async {
    final targetUid = (m['uid'] ?? '').toString();
    if (targetUid.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('길드장 위임', style: TextStyle(color: Colors.white)),
        content: Text('${m['nickname']} 님에게 길드장을 넘길까요?\n위임하면 나는 길드원이 됩니다.',
            style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('취소', style: TextStyle(color: Colors.white54))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _kGold, foregroundColor: Colors.black),
            onPressed: () => Navigator.pop(c, true), child: const Text('위임')),
        ],
      ),
    );
    if (ok != true) return;
    final fs = FirebaseFirestore.instance;
    final guildRef = fs.collection('guilds').doc(gid);
    try {
      final batch = fs.batch();
      batch.update(guildRef.collection('members').doc(targetUid), {'role': 'master'});
      batch.update(guildRef.collection('members').doc(myUid), {'role': 'member'});
      batch.update(guildRef, {'masterUid': targetUid, 'master': m['nickname'] ?? ''});
      await batch.commit();
      _toast('${m['nickname']} 님에게 길드장을 위임했어요. 👑');
    } catch (e) {
      _infoPopup('위임 실패', e.toString());
    }
  }

  Future<void> _leaveGuild(BuildContext ctx, String uid, String gid, bool isMaster) async {
    final fs = FirebaseFirestore.instance;
    final guildRef = fs.collection('guilds').doc(gid);
    // 🚫 길드장은 길드원이 남아 있으면 해체 불가 (위임하거나 모두 나가야 함)
    if (isMaster) {
      final gs = await guildRef.get();
      final mc = (gs.data()?['memberCount'] is num) ? (gs.data()!['memberCount'] as num).toInt() : 0;
      if (mc > 1) {
        _infoPopup('해체 불가',
            '길드원이 남아 있으면 해체할 수 없어요.\n\n• 다른 길드원에게 길드장을 위임하거나\n• 길드원이 모두 나가 혼자 남았을 때\n해체할 수 있어요.\n\n(현재 $mc명)');
        return;
      }
    }
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

  // 🛡️ 윤슬(길드 NPC)이 말하는 캐릭터 팝업 (길드 가입/생성 제한 안내 등)
  void _yunseulSay(String msg) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (c) => NpcTutorialOverlay(
        text: msg,
        imagePath: 'assets/images/npc_guild.png',
        onTap: () => Navigator.pop(c),
        action: ElevatedButton(
          style: ElevatedButton.styleFrom(
              backgroundColor: _kGold, foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
              textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
          onPressed: () => Navigator.pop(c),
          child: const Text('알겠어요 👍'),
        ),
      ),
    );
  }

  // 🛍️ 보배 클릭 — 3마리 모았으면 정산, 아니면 의뢰 안내 (+ 상점 가기)
  void _onBobaeTap(VoidCallback enterStore) {
    if (!mounted) return;
    final b = getTodayBobaeFish();
    final fish = b['fish'].toString();
    final cnt = _bobaeCaught; // 오늘 새로 잡은 지정 어종 수(진행도)
    // 정산 가능: 오늘 3마리 잡음 + 오늘 미정산
    if (!_bobaeDone && cnt >= bobaeCount) {
      showDialog(
        context: context,
        builder: (c) => NpcTutorialOverlay(
          text: '🛍️ 오~ $fish $bobaeCount마리 다 잡아오셨네요!\n바로 정산해드릴게요. 👍\n\n💰 포인트 +${bobaePtsPerFish * bobaeCount} · 경험치 +$bobaeExp\n($fish $bobaeCount마리는 제가 가져갈게요)',
          imagePath: 'assets/images/npc_shop.png',
          onTap: () {},
          action: ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF7FFFB0), foregroundColor: Colors.black, padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 13), textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
            onPressed: () { Navigator.pop(c); _claimBobae(fish); },
            child: const Text('정산 받기 🎁'),
          ),
        ),
      );
      return;
    }
    // 안내 (진행도 + 상점 가기)
    final guide = _bobaeDone
        ? '오늘 의뢰는 이미 정산했어요! 내일 또 부탁해요 😊'
        : '오늘은 [$fish] $bobaeCount마리를 잡아다 주세요.\n(현재 $cnt/$bobaeCount 마리)\n\n💰 정산하면 포인트 +${bobaePtsPerFish * bobaeCount} · 경험치 +$bobaeExp';
    showDialog(
      context: context,
      builder: (c) => NpcTutorialOverlay(
        text: '🛍️ 서윤의 오늘 의뢰예요!\n\n$guide',
        imagePath: 'assets/images/npc_shop.png',
        onTap: () => Navigator.pop(c),
        action: Row(mainAxisSize: MainAxisSize.min, children: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _kGold, foregroundColor: Colors.black, padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 13), textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
            onPressed: () { Navigator.pop(c); enterStore(); },
            child: const Text('상점 가기 🛒'),
          ),
          const SizedBox(width: 12),
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('닫기', style: TextStyle(color: Colors.white70, fontSize: 15, fontWeight: FontWeight.bold))),
        ]),
      ),
    );
  }

  // 🛍️ 보배 정산 — 보상 지급 + 지정 어종 3마리 가방에서 차감 + 완료 기록
  Future<void> _claimBobae(String fish) async {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) return;
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final ref = FirebaseFirestore.instance.collection('users').doc(u.uid);
    // 정산 시 [지정 어종] 3마리를 넘겨야 함 — 가방에 없으면(상점에 판 경우) 안내
    try {
      final snap = await ref.get();
      final inv0 = List<dynamic>.from(snap.data()?['inventory'] ?? []);
      final have = inv0
          .where((i) => i['name'] == fish && (i['type'] ?? '') == 'FISH')
          .fold<int>(0, (s, i) => s + (((i['quantity'] ?? 0) as num).toInt()));
      if (have < bobaeCount) {
        if (mounted) _toast('정산할 [$fish] $bobaeCount마리가 가방에 없어요!\n상점에 팔지 말고 가지고 오셔야 해요 🐟');
        return;
      }
    } catch (_) {}
    try {
      await FirebaseFirestore.instance.runTransaction((tx) async {
        final data = (await tx.get(ref)).data() ?? {};
        final bp = data['bobae_progress'];
        if (bp is Map && bp['date'] == today && bp['claimed'] == true) return; // 중복 정산 방지
        final inv = List<dynamic>.from(data['inventory'] ?? []);
        final idx = inv.indexWhere((i) => i['name'] == fish && (i['type'] ?? '') == 'FISH');
        if (idx < 0 || ((inv[idx]['quantity'] ?? 0) as num) < bobaeCount) return; // 3마리 미만이면 정산 X
        final q = (inv[idx]['quantity'] as num).toInt() - bobaeCount;
        if (q <= 0) { inv.removeAt(idx); } else { inv[idx]['quantity'] = q; }
        tx.set(ref, {
          'gold': FieldValue.increment(bobaePtsPerFish * bobaeCount),
          'exp': FieldValue.increment(bobaeExp),
          'inventory': inv,
          'bobae_progress': {'date': today, 'claimed': true},
        }, SetOptions(merge: true));
      });
      if (mounted) _toast('🎁 정산 완료! 포인트 +${bobaePtsPerFish * bobaeCount} · 경험치 +$bobaeExp');
    } catch (e) {
      debugPrint('보배 정산 에러: $e');
    }
  }

  // 🆙 광장 레벨업 축하 팝업 (낚시 화면과 동일 스타일)
  void _showPlazaLevelUp(int newLevel) {
    if (!mounted) return;
    audioManager.playSfx("sfx_landing_success.mp3");
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        backgroundColor: Colors.black.withOpacity(0.9),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: _kGold, width: 3)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.stars, color: Colors.yellowAccent, size: 70),
          const SizedBox(height: 15),
          const Text('LEVEL UP!!!', style: TextStyle(color: _kGold, fontSize: 40, fontWeight: FontWeight.w900, fontStyle: FontStyle.italic, shadows: [Shadow(color: Colors.white24, blurRadius: 10)])),
          const SizedBox(height: 10),
          Text('Lv.$newLevel 달성!', style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold)),
          const SizedBox(height: 20),
          Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(10)), child: const Text('💪 힘·🎯컨트롤·📡감도 각 +1 상승! (제압력 +3)\n더 큰 대물에 도전하세요!', style: TextStyle(color: Colors.cyanAccent, fontSize: 15, height: 1.5), textAlign: TextAlign.center)),
          const SizedBox(height: 20),
          ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: _kGold, foregroundColor: Colors.black, padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))), onPressed: () => Navigator.pop(c), child: const Text('확인', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18))),
        ]),
      ),
    );
  }

  // 🔒 다른 기기(창)에서 같은 계정 접속 감지 → 이 화면 차단 (이중 보상 방지)
  void _onDuplicateLogin() {
    if (_dupKicked || !mounted) return;
    _dupKicked = true;
    try { FirebaseAuth.instance.signOut(); } catch (_) {} // 이후 서버 쓰기 차단
    showDialog(
      context: context,
      useRootNavigator: true, // 낚시터·상점 등 어떤 화면 위에도 덮이게
      barrierDismissible: false,
      builder: (c) => WillPopScope(
        onWillPop: () async => false,
        child: AlertDialog(
          backgroundColor: const Color(0xFF1A1A1A),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Colors.redAccent, width: 1.4)),
          title: const Text('⚠️ 중복 접속 감지', style: TextStyle(color: Colors.redAccent, fontSize: 22, fontWeight: FontWeight.bold)),
          content: const Text('다른 기기(창)에서 같은 계정으로 접속했어요.\n이 화면은 종료되었습니다.\n\n여기서 계속하려면 [다시 접속]을 눌러주세요.\n(그러면 다른 기기가 종료돼요)', style: TextStyle(color: Colors.white, fontSize: 17, height: 1.6)),
          actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          actions: [
            Center(
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: _kGold, foregroundColor: Colors.black, padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 14), textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                onPressed: () => html.window.location.reload(),
                child: const Text('다시 접속'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 🏆 가람(랭킹) 탭 — 랭킹 시스템 설명 팝업
  void _onGaramTap() {
    // 튜토리얼 중이면 기존 인트로(열면 튜토 완료 처리)
    if (_tutQuestNow != null) {
      _openNpcIntro('npc_rank.png', 'rank', '순위 보기', _openRanking);
      return;
    }
    _showRankGuide();
  }

  // 🏆 랭킹 시스템 안내 팝업 (가람 대사) — 초반엔 접속 시 1회 자동 표시
  void _showRankGuide() {
    showDialog(
      context: context,
      builder: (c) => NpcTutorialOverlay(
        text: '🏆 캠피싱 랭킹 대회, 제가 알려드릴게요!\n\n'
            '① 레벨·어종별 최대어 순위 10위 안에 들면\n'
            '부문마다 점수를 드려요 (1위 10점 ~ 10위 1점)\n\n'
            '② 매주 월요일 주간랭킹 발표!\n'
            'top10은 1주일간 능력치 보너스 + 랭킹마크 🥇\n\n'
            '③ 점수는 주간 → 월간 → 연간으로 계속 누적!\n'
            '꾸준한 조사님이 유리해요 😊\n\n'
            '🎁 월간·연간 상위 랭커에게는\n'
            'camnak.com 쇼핑몰 선물 이벤트도 준비 중!',
        imagePath: 'assets/images/npc_rank.png',
        onTap: () => Navigator.pop(c),
        action: Row(mainAxisSize: MainAxisSize.min, children: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _kGold, foregroundColor: Colors.black, padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 13), textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
            onPressed: () { Navigator.pop(c); _openRanking(); },
            child: const Text('랭킹 보기 🏆'),
          ),
          const SizedBox(width: 12),
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('닫기', style: TextStyle(color: Colors.white70, fontSize: 15, fontWeight: FontWeight.bold))),
        ]),
      ),
    );
  }

  // 🔰 초반 캠페인: 접속 시 랭킹 안내 1회 자동 표시 (계정당 1번, 기간 끝나면 false로 바꿔 배포)
  static const bool _kRankNoticeCampaign = true;
  Future<void> _maybeShowRankNotice() async {
    if (!_kRankNoticeCampaign) return;
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) return;
    try {
      final ref = FirebaseFirestore.instance.collection('users').doc(u.uid);
      final d = (await ref.get()).data() ?? {};
      if (d['rankNoticeSeen'] == true) return; // 이미 봄
      if (((d['tutStep'] as num?)?.toInt() ?? 0) != 99) return; // 튜토리얼 중엔 안 띄움(끝난 다음 접속에)
      // 📋 팝업 순서 정리: 접속보상(아라)·튜토리얼·NPC 안내가 모두 닫힐 때까지 대기 → 그 다음 차례로 등장
      await Future.delayed(const Duration(seconds: 3)); // 접속보상 팝업이 먼저 뜰 시간
      for (int i = 0; i < 120; i++) { // 최대 60초 대기(안 닫으면 이번 접속은 패스)
        if (!mounted) return;
        final onTop = ModalRoute.of(context)?.isCurrent ?? true; // 낚시터 등 다른 화면 위엔 안 띄움
        final busy = !onTop || _showReward || _showTutIntro || _showTutMission || _showTutReward || _npcIntro != null;
        if (!busy) break;
        if (i == 119) return; // 계속 열려있으면 다음 접속에 다시 시도(도장 안 찍음)
        await Future.delayed(const Duration(milliseconds: 500));
      }
      if (!mounted) return;
      await Future.delayed(const Duration(milliseconds: 800)); // 한 박자 쉬고
      if (!mounted || !(ModalRoute.of(context)?.isCurrent ?? true)) return;
      _showRankGuide();
      await ref.set({'rankNoticeSeen': true}, SetOptions(merge: true));
    } catch (_) {}
  }

  // 🥊 한별(아레나 일일) 탭
  void _onHanbyeolTap() {
    // 튜토리얼 중이면 기존 인트로(입장 시 튜토 완료 처리)
    if (_tutQuestNow != null) {
      _openNpcIntro('npc_arena.png', 'arena', '대회 입장', _openArena);
      return;
    }
    // 오늘 승리 + 보상 미수령 → 보상 정산 팝업
    if (_hanbyeolWon && !_hanbyeolClaimed) { _showHanbyeolClaim(); return; }
    // 일일 안내
    String guide;
    if (_hanbyeolClaimed) {
      guide = '오늘 아레나 일일 보상은 받으셨어요!\n대회는 계속 참가할 수 있어요 😊';
    } else if (_arenaCount >= 2) {
      guide = '오늘 도전(2회)을 다 쓰셨네요.\n아쉽지만 내일 다시 도전!\n\n🏆 우승 보상: 경험치 +$hanbyeolExp · 포인트 +$hanbyeolPts';
    } else {
      guide = '오늘의 아레나 미션!\n대회에서 우승하면 보상을 드려요.\n(오늘 도전 $_arenaCount/2)\n\n🏆 우승 보상: 경험치 +$hanbyeolExp · 포인트 +$hanbyeolPts';
    }
    showDialog(
      context: context,
      builder: (c) => NpcTutorialOverlay(
        text: '⚔️ 한별의 아레나 대회예요!\n\n$guide',
        imagePath: 'assets/images/npc_arena.png',
        onTap: () => Navigator.pop(c),
        action: Row(mainAxisSize: MainAxisSize.min, children: [
          // 대회 입장은 일일 보상과 무관하게 항상 가능(입장 제한은 아레나 안에서 처리)
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _kGold, foregroundColor: Colors.black, padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 13), textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
            onPressed: () { Navigator.pop(c); _openArena(); },
            child: const Text('대회 입장 ⚔️'),
          ),
          const SizedBox(width: 12),
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('닫기', style: TextStyle(color: Colors.white70, fontSize: 15, fontWeight: FontWeight.bold))),
        ]),
      ),
    );
  }

  void _showHanbyeolClaim() {
    showDialog(
      context: context,
      builder: (c) => NpcTutorialOverlay(
        text: '⚔️ 우승 축하해요!! 🏆\n오늘 아레나에서 이기셨네요.\n약속한 보상을 드릴게요!\n\n🎁 경험치 +$hanbyeolExp · 포인트 +$hanbyeolPts',
        imagePath: 'assets/images/npc_arena.png',
        onTap: () {},
        action: ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF7FFFB0), foregroundColor: Colors.black, padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 13), textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
          onPressed: () { Navigator.pop(c); _claimHanbyeol(); },
          child: const Text('보상 받기 🎁'),
        ),
      ),
    );
  }

  // 🥊 한별 보상 정산 — 오늘 승리했고 미수령이면 경험치/포인트 지급
  Future<void> _claimHanbyeol() async {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) return;
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final ref = FirebaseFirestore.instance.collection('users').doc(u.uid);
    try {
      await FirebaseFirestore.instance.runTransaction((tx) async {
        final data = (await tx.get(ref)).data() ?? {};
        if (data['hanbyeol_reward_date'] == today) return; // 중복 방지
        if (data['hanbyeol_won_date'] != today) return;    // 오늘 승리 안 함
        tx.set(ref, {
          'gold': FieldValue.increment(hanbyeolPts),
          'exp': FieldValue.increment(hanbyeolExp),
          'hanbyeol_reward_date': today,
        }, SetOptions(merge: true));
      });
      if (mounted) {
        setState(() { _hanbyeolClaimed = true; }); // 낙관적 ❗ 제거
        _toast('🎁 아레나 보상! 경험치 +$hanbyeolExp · 포인트 +$hanbyeolPts');
      }
    } catch (e) {
      debugPrint('한별 정산 에러: $e');
    }
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
                Text('6대장 각 $need마리 잡기 (승급 후 새로 시작)', style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold)),
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
          {'rank': targetRank, 'gold': FieldValue.increment(reward), 'daejangCatch': FieldValue.delete()}, SetOptions(merge: true));
      if (mounted) setState(() { _rank = targetRank; _daejangCatch = {}; }); // 🎖️ 승급 후 다음 등급 퀘스트는 0부터 새로 시작
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
                  // 🧩 채널 뱃지 — 탭하면 채널 목록에서 이동(친구끼리 모이기)
                  InkWell(
                    onTap: _openChannelPicker,
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                          color: _kGold.withOpacity(0.18),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: _kGold, width: 0.8)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Text('CH$_channelNum',
                            style: const TextStyle(color: _kGold, fontSize: 11, fontWeight: FontWeight.w900)),
                        const Icon(Icons.expand_more, color: _kGold, size: 13),
                      ]),
                    ),
                  ),
                  const SizedBox(width: 6),
                  // 🔀 광장 전환 (민물↔바다 바로가기)
                  InkWell(
                    onTap: () => _switchPlazaWorld(!widget.isSea),
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                          color: (widget.isSea ? const Color(0xFF2E7D32) : const Color(0xFF1565C0)).withOpacity(0.9),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.white70, width: 0.8)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Text(widget.isSea ? '🏞️' : '🌊', style: const TextStyle(fontSize: 12)),
                        const SizedBox(width: 3),
                        Text(widget.isSea ? '민물광장' : '바다광장',
                            style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w900)),
                        const SizedBox(width: 2),
                        const Icon(Icons.swap_horiz, color: Colors.white, size: 13),
                      ]),
                    ),
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
          IntrinsicHeight(
          child: Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
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
                // (캐릭터 원형 제거 — 폰에서 잘 안 보여 '내정보' 버튼으로 일원화)
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
                _iconBtn(Icons.person, '내정보', _openStatusWindow), // 🎒→👤 상태창+인벤 합본 진입
              ],
            ),
          ),
          ])),
        ],
      ),
    );
  }
}
