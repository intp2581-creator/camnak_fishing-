// ignore_for_file: deprecated_member_use, use_build_context_synchronously
// 🏛️ [광장 시스템] 낚시터별 광장(허브). 1단계: 나 혼자 걸어다니며 상점/아레나/포탈/낚시 진입.
//    2단계에서 RTDB로 다른 유저 실시간 표시 예정.
import 'dart:async';
import 'dart:html' as html; // 전체화면 토글
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
  Duration _moveDuration = const Duration(milliseconds: 500);

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

  // 🏆 주간 길드 리그 (1위 길드 챔피언 → 머리 위 👑 + 추가 버프)
  bool _isChampionGuild = false;
  String _champGuildId = '';
  String _champWeek = '';
  StreamSubscription<DocumentSnapshot>? _leagueSub;

  // 📋 일일 퀘스트 (아라 매니저) — 로비에서 광장으로 이전
  bool _showQuest = false;
  bool _gotDailyReward = false; // 오늘 첫 접속 500P 지급됨
  final List<int> _eventHours = [14, 15, 16, 19, 20, 21];
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

  int _getTodayEventHour() {
    final now = DateTime.now();
    return _eventHours[(now.day + now.month) % _eventHours.length];
  }

  String _getBriefingText() {
    final mission = _getTodayMission();
    final eventHour = _getTodayEventHour();
    final currentHour = DateTime.now().hour;
    final amPm = eventHour >= 12 ? '오후' : '오전';
    final displayHour = eventHour >= 12 ? (eventHour == 12 ? 12 : eventHour - 12) : eventHour;
    final endHour = eventHour + 1;
    final displayEndHour = endHour >= 12 ? (endHour == 12 ? 12 : endHour - 12) : endHour;
    String greeting = '안녕하세요! 😊';
    if (currentHour >= 5 && currentHour < 12) {
      greeting = '좋은 아침이에요! ☀️';
    } else if (currentHour >= 12 && currentHour < 18) {
      greeting = '안녕하세요! ☕';
    } else {
      greeting = '밤낚시 오셨군요! 🌙';
    }
    if (currentHour < eventHour) {
      return '$greeting\n'
          '🏆 오늘의 미션입니다.\n'
          '⏰ $amPm $displayHour시 ~ $displayEndHour시 (1시간)\n'
          '🎣 ${mission['loc']}\n'
          '🐟 ${mission['fish']} ${mission['count']}마리 먼저 잡기!\n'
          '1등 상금은 2,000P 입니다.';
    } else if (currentHour == eventHour) {
      return '$greeting\n'
          '🔥 지금 바로! ($amPm $displayEndHour시 까지)\n'
          '🎣 ${mission['loc']}\n'
          '🐟 ${mission['fish']} ${mission['count']}마리\n'
          '선착순 1명 2,000P!';
    } else {
      return '$greeting\n'
          '오늘 미션 종료 😊\n'
          '내일 미션도\n기대해 주세요!';
    }
  }

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
    _playPlazaBgm(); // 🎵 광장 배경음악 (옛 로비 BGM)
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
    _walkCtrl.dispose();
    _joyTimer?.cancel();
    _roomSub?.cancel();
    _userSub?.cancel();
    _leagueSub?.cancel();
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
        _recomputeChampion(); // 길드 바뀌면 챔피언 여부 재계산
        // 머리 위 길드명 즉시 갱신(다른 유저에게도 반영)
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

  // 🌐 실시간 접속/위치 송수신
  void _initPresence() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final uid = user.uid;
    _myRef = _db.ref('plaza/$_roomKey/$uid');
    _myRef!.onDisconnect().remove().catchError((Object e) => debugPrint('🌐 RTDB onDisconnect ERR: $e')); // 접속 끊기면 자동 사라짐
    guildGoOnline(); // 🟢 전역 접속표시
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
            'guild': v['guild']?.toString() ?? '',
            'champ': v['champ'] == true,
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

  // 🗺️ 카메라/월드: 큰 광장 그림(3296x1700)을 두고 카메라가 캐릭터를 따라 스크롤
  static const double _imgAspect = 3296 / 1700; // 월드 가로:세로 비율
  static const double _viewFracH = 0.72; // 화면이 보여주는 월드 세로 비율(나머지는 스크롤)
  static const bool _devCoords = true; // 🔧 좌표 수집 모드: 걷기제한 해제 + 탭 좌표 표시 (좌표 다 받으면 false)
  Offset? _lastTapWorld;

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
    if (_devCoords) _lastTapWorld = rawTarget; // 🔧 좌표 수집
    final dest = _devCoords ? rawTarget : _clampToPlaza(rawTarget); // 섬 안으로 보정(수집모드는 자유 이동)
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
    _joyTimer ??= Timer.periodic(const Duration(milliseconds: 33), (_) => _joyTick());
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
    const speedPxPerSec = 320.0; // 월드 스크린px 기준 이동 속도
    const dt = 33 / 1000.0;
    final movePx = _joyDir * speedPxPerSec * dt; // 방향*세기
    var np = Offset(
      _charPos.dx + movePx.dx / _worldW,
      _charPos.dy + movePx.dy / _worldH,
    );
    np = Offset(np.dx.clamp(0.0, 1.0), np.dy.clamp(0.0, 1.0));
    if (!_devCoords) np = _clampToPlaza(np); // 정식 모드에선 걷기 영역 안으로
    setState(() {
      // 좌우 데드존: 상하로 갈 땐 dx가 0 근처라 좌우 반전이 깜빡여서 떨림 → 충분히 좌우일 때만 전환
      if (_joyDir.dx.abs() > 0.3) _facingRight = _joyDir.dx >= 0;
      _charPos = np;
      _moveDuration = const Duration(milliseconds: 33);
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

  Widget _joystick() {
    return Positioned(
      right: 34,
      bottom: 34,
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
          // 🗺️ 월드 크기(스크린px): 화면은 월드 세로의 _viewFracH만큼만, 나머지는 카메라가 스크롤
          final worldH = h / _viewFracH;
          final worldW = worldH * _imgAspect;
          _worldW = worldW; // 조이스틱 이동 환산용
          _worldH = worldH;
          // 🏞️ 원근감: 위(멀리)로 갈수록 작게, 아래(가까이)로 올수록 크게
          final perspT = ((_charPos.dy - 0.22) / (0.96 - 0.22)).clamp(0.0, 1.0);
          final charH = h * (0.18 + perspT * 0.16); // 멀리=0.18h ~ 가까이=0.34h
          final charW = charH * 0.55;
          // 📷 카메라: 캐릭터 중심, 월드 가장자리 클램프
          final maxCamX = (worldW - w) > 0 ? (worldW - w) : 0.0;
          final maxCamY = (worldH - h) > 0 ? (worldH - h) : 0.0;
          final camX = (_charPos.dx * worldW - w / 2).clamp(0.0, maxCamX);
          final camY = (_charPos.dy * worldH - h / 2).clamp(0.0, maxCamY);

          return Stack(
            children: [
              // 🌍 월드 레이어 (카메라가 캐릭터 따라 스크롤). 바깥 Stack이 뷰포트로 클립
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
                        // 바닥 탭 → 캐릭터 이동 (월드 좌표)
                        Positioned.fill(
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTapUp: (d) => _moveTo(
                                Offset(d.localPosition.dx / worldW, d.localPosition.dy / worldH),
                                worldW, worldH),
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
                                final bob = _walking ? math.sin(phase).abs() * 2.5 : 0.0;
                                final tilt = _walking ? math.sin(phase) * 0.035 : 0.0;
                                return Stack(
                                  clipBehavior: Clip.none,
                                  alignment: Alignment.bottomCenter,
                                  children: [
                                    Positioned.fill(
                                      child: Transform.translate(
                                        offset: Offset(0, -bob),
                                        child: Transform.rotate(
                                          angle: tilt,
                                          alignment: Alignment.bottomCenter,
                                          child: Transform(
                                            alignment: Alignment.bottomCenter,
                                            transform: Matrix4.rotationY(
                                                _facingRight ? 0 : math.pi),
                                            child: Image.asset(
                                              _charImage,
                                              fit: BoxFit.contain,
                                              alignment: Alignment.bottomCenter,
                                              errorBuilder: (a, b, d) =>
                                                  const SizedBox.shrink(),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    Positioned(
                                      bottom: charH * 0.50,
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
                        ..._others.entries
                            .map((e) => _remoteAvatar(e.key, e.value, worldW, worldH, h)),
                        // 4) NPC / 시설들 (좌표는 새 그림 좌표 받으면 조정)
                        _npc(worldW, worldH, widget.isSea ? 0.75 : 0.90,
                            widget.isSea ? 0.32 : 0.35, '🏪', '상점', _openStore),
                        _npc(worldW, worldH, widget.isSea ? 0.15 : 0.15,
                            widget.isSea ? 0.28 : 0.20, '🏆', '랭킹', _openRanking),
                        _npc(worldW, worldH, widget.isSea ? 0.95 : 0.72,
                            widget.isSea ? 0.54 : 0.22, '⚔️', '아레나', _openArena,
                            iconWidget: _crossedRods()),
                        _npc(worldW, worldH, widget.isSea ? 0.52 : 0.52,
                            widget.isSea ? 0.22 : 0.16, '🌀', '낚시터', _openMinimap),
                        _npc(worldW, worldH, widget.isSea ? 0.34 : 0.33,
                            widget.isSea ? 0.25 : 0.17, '🛡️', '길드', _openGuild),
                        // 📋 일일퀘스트 매니저 '아라'
                        _araNpc(worldW, worldH, h),
                      ],
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

  // 📋 일일퀘스트 매니저 '아라' (클릭하면 오늘의 미션 안내) — 위치=월드, 크기=뷰포트
  Widget _araNpc(double worldW, double worldH, double sizeH) {
    final figH = sizeH * 0.21; // 캐릭터와 비슷한 크기
    final figW = figH * 0.6;
    const cx = 0.075;
    const cy = 0.73; // 발 위치
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
                border: Border.all(color: _kGold),
                boxShadow: [BoxShadow(color: _kGold.withOpacity(0.5), blurRadius: 8)],
              ),
              child: const Text('📋 일일퀘스트',
                  style: TextStyle(color: _kGold, fontSize: 12, fontWeight: FontWeight.bold)),
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
      _toast('"$gname" 길드에 가입했어요!');
    } catch (e) {
      _toast(e.toString());
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
