// ignore_for_file: unused_element, unnecessary_non_null_assertion, deprecated_member_use, avoid_print, curly_braces_in_flow_control_structures, empty_catches, use_build_context_synchronously
import 'dart:math' as math;
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'package:flutter/gestures.dart';
// 👇 우리가 1,2,3,4탄에서 쪼개놓은 피땀눈물 파일들 연결!
import 'game_config.dart';   
import 'fishing_logic.dart'; 
import 'gm_notice_popup.dart';
import 'ui_lobby.dart';     
import 'ui_tutorial_npc.dart'; // 👧 윤슬 가이드 부품 가져오기!
import 'ui_guild.dart'; // 🛡️ 길드 정보 보기 + 접속표시
import 'weather.dart'; // 🌧️ 실시간 날씨(기상청) 오버레이


// 🎣 [메인 낚시터 화면]
// 🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩
class FishingScreen extends StatefulWidget {
  final String nickname;
  final String locationName;
  final String winCondition;
  final String title;
  final String bgImagePath;
  final String characterImagePath;
  final bool isSea;
  final String? roomId;
  final String? targetFish; // ⚔️ 아레나 최대어 모드 대상 어종(이 어종만 카운트)
  final int? playEndAt; // ⏱️ 아레나 공유 종료시각(ms) — 전원 동시 종료용
  final bool isFirstTime; // 🚀 [추가] 튜토리얼 꼬리표 받기!

  const FishingScreen({
    super.key,
    required this.nickname,
    required this.locationName, // 🌟 기본값 지우고 required로 받아야 합니다!
    required this.winCondition, // 🌟 드디어 가방을 받습니다!
    required this.title,
    required this.bgImagePath,
    required this.characterImagePath,
    required this.isSea,
    this.roomId,
    this.targetFish,
    this.playEndAt,
    this.isFirstTime = false, // 🚀 [추가] 기본값은 false!
  });

  @override
  State<FishingScreen> createState() => _FishingScreenState();
}

class _FishingScreenState extends State<FishingScreen> with TickerProviderStateMixin {
  // 💡 낚시터 전용 윤슬님 튜토리얼 스텝 (-1: 퇴근, 0~3: 설명 중)
  int _fishingStep = -1;
  DateTime? _lastGaramTime;

// 👇 여기 추가!
final List<String> _garamMessages = [
  "지금은 오픈 베타 중입니다!\n즐거운 시간 되세요! 😊",
  "오늘 핫스팟은 어디일까요?\n랭킹 1위 도전해보세요! 🏆",
  "미끼 소진되면 상점에서\n바로 구매하세요! 💰",
  "친구랑 같이하면 더 재밌어요!\n친구 초대해보세요~ 👥",
];

  void toggleFullScreen() {
    try {
      // 🚨 브라우저가 전체화면이 아니라고 판단하면 (전화받고 왔을 때 등)
      if (html.document.fullscreenElement == null) {
        // 1. 전체화면을 다시 요청하고!
        html.document.documentElement?.requestFullscreen().then((_) {
          // 2. 🚀 화면이 꽉 차는 순간, 가로 모드(landscape)로 멱살 잡고 강제 고정!!
          html.window.screen?.orientation?.lock('landscape');
        }).catchError((e) {
          print("가로 고정 실패: $e");
        });
      } else {
        // 원래 전체화면이었다면 해제하고 고정도 풀어줍니다.
        html.document.exitFullscreen();
        html.window.screen?.orientation?.unlock();
      }
    } catch (e) {
      print("전체화면 전환 실패: $e");
    }
  }
// 💬 채팅 관련 상태 변수
  int _currentChatTab = 0; // 0: 전체, 1: 귓속말, 2: 친구
  String? _whisperTargetNickname; // 귓속말 보낼 대상의 닉네임

  int arenaTimeLeft = 600; // ⏱️ 아레나 전용 10분 타이머 (10분 = 600초) 추가!

  // 🏢 Data: 세팅값 (좌표, 앵글 등)
  final int forcedLevel = 6;            
  final int forcedGold = 1000000;       

  final double castingArmRightOffset = 0.0;  
  final double castingArmBottomOffset = 1.0; 
  final double castingBaseAngle = 1.0;       
  final double castingOriginX = 300.0;         
  final double castingOriginY = 150.0;         
  final double castingImageSize = 550.0;       

  final double fightArmRightOffset = -30.0;    
  final double fightArmBottomOffset = -50.0;   
  final double fightBaseAngle = 0.0;           
  final double fightOriginX = 150.0;           
  final double fightOriginY = 150.0;           
  final double fightImageSize = 450.0;         

  final double setupRodOffsetX = 150.0;         
  final double setupRodOffsetY = -220.0;       
  final double setupRodScale = 0.4;    

  final double setupReelOffsetX = 0.0;  
  final double setupReelOffsetY = 0.0;  
  final double setupReelScale = 0.5;            

  final double fieldFloatBottomOffset = 290.0; 
  final double fieldFloatSpacing = 0.0;        
  final double fieldFloatDepthOffset = -12.0;  // 찌 높이 미세조정: 음수면 더 깊이(아래로) 잠김
  
  final double platformWidth = 1000.0;         
  final double platformHeight = 200.0;         
  final double platformBottomOffset = -120.0;  
  final double platformDarkness = 0.7;         

  final double rodFanAngleStep = 0.06;         
  final double fieldRodLength = 240.0;         

  final double seaWaitingRightOffset = -30.0;  
  final double seaWaitingBottomOffset = -50.0; 
  final double seaWaitingImageSize = 450.0;    
  final double seaWaitingAngle = 0.0;  


  // ✨ [추가 1] 닉네임 터치 시 뜨는 미니 프로필 메뉴 팝업!
  void _showUserMenu(String targetNickname) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Colors.black87,
          shape: RoundedRectangleBorder(
            side: const BorderSide(color: Colors.amber, width: 2), // 낚시 게임 감성의 노란 테두리
            borderRadius: BorderRadius.circular(8),
          ),
          title: Text('[$targetNickname] 님', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 1. 귓속말 버튼
              ListTile(
                leading: const Icon(Icons.chat_bubble_outline, color: Colors.yellowAccent),
                title: const Text('귓속말 보내기', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(context); // 팝업 먼저 닫고
                  setState(() {
                    _whisperTargetNickname = targetNickname;
                    _currentChatTab = 1; // 귓속말 탭으로 자동 이동!
                  });
                },
              ),
              // 2. 친구 추가 버튼
              ListTile(
                leading: const Icon(Icons.person_add_alt_1, color: Colors.greenAccent),
                title: const Text('친구 추가하기', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(context); // 팝업 닫고
                  _addFriend(targetNickname); // DB 저장 함수 실행!
                },
              ),
              // 3. 닫기 버튼
              ListTile(
                leading: const Icon(Icons.cancel_outlined, color: Colors.grey),
                title: const Text('취소', style: TextStyle(color: Colors.grey)),
                onTap: () => Navigator.pop(context),
              ),
            ],
          ),
        );
      }
    );
  }

  // ✨ [추가 2] Firebase에 친구로 등록하는 함수
  void _addFriend(String targetNickname) {
    String myNickname = widget.nickname; // 사장님 닉네임

    // DB의 'friends' 컬렉션 -> 내 닉네임 -> 'my_list' 에 친구 저장!
    FirebaseFirestore.instance
        .collection('friends')
        .doc(myNickname)
        .collection('my_list')
        .doc(targetNickname)
        .set({
      'nickname': targetNickname,
      'addedAt': FieldValue.serverTimestamp(),
    }).then((_) {
      // 성공하면 화면 아래에 까만 알림창(스낵바) 띄우기
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('[$targetNickname]님을 친구 목록에 추가했습니다! 🤝'),
            backgroundColor: Colors.blueGrey,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    });
  }

// 🎒 전체 인벤토리 팝업 (낚시 중 장비/미끼/스킨 보기·장착)
  void _showFullInventoryDialog() {
    audioManager.playSfx("sfx_click.mp3");
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: SizedBox(
          width: 530, height: 560,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // 패널에 크기(530×560)를 딱 줘서 그리드(Expanded) 높이 확보
              Positioned.fill(child: buildInventoryPanel(context)),
              // ❌ 닫기 버튼(패널 안쪽 우측 상단)
              Positioned(
                top: 10, right: 10,
                child: GestureDetector(
                  onTap: () { audioManager.playSfx("sfx_click.mp3"); Navigator.pop(ctx); },
                  child: Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0xFFD4AF37), width: 1.5),
                    ),
                    child: const Icon(Icons.close, color: Color(0xFFD4AF37), size: 22),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

// 🎒 미끼 교체용 인벤토리 팝업
  void _showFishingInventoryPopup() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15), side: const BorderSide(color: Color(0xFFD4AF37), width: 2)),
        title: const Text('🎒 미끼 교체하기', style: TextStyle(color: Color(0xFFD4AF37), fontWeight: FontWeight.bold)),
        content: SizedBox(
          width: 300, height: 400,
          child: StreamBuilder<DocumentSnapshot>(
            stream: FirebaseFirestore.instance.collection('users').doc(user.uid).snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const Center(child: CircularProgressIndicator(color: Color(0xFFD4AF37)));
              
              var userData = snapshot.data!.data() as Map<String, dynamic>? ?? {};
              List<dynamic> inventory = userData['inventory'] ?? [];
              
              // 💡 미끼(Bait)만 + 현재 낚시터(민물/바다)에 맞는 것만 표시
              final wantCat = widget.isSea ? 'SEA' : 'FW';
              var baitList = inventory.where((item) {
                final isB = (item['type'] ?? '').toString().toUpperCase() == 'BAIT' ||
                            (item['category'] ?? '').toString().toUpperCase() == 'BAIT';
                if (!isB) return false;
                final c = (item['category'] ?? '').toString().toUpperCase();
                return c == wantCat || c == 'COMMON'; // 위치 카테고리 일치만 (에기 등 타지역 미끼 숨김)
              }).toList();

              if (baitList.isEmpty) return Center(child: Text('${widget.isSea ? '바다' : '민물'} 미끼가 없습니다.\n상점에서 구매하세요!', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white)));

              return ListView.builder(
                itemCount: baitList.length,
                itemBuilder: (context, index) {
                  var bait = baitList[index];
                  bool isEquipped = equippedBait != null && equippedBait!['name'] == bait['name'];
                  
                  return ListTile(
                    // 🎨 미끼 이미지 아이콘
                    leading: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: Image.asset(
                        _getIconImagePath(bait) ?? 'assets/items/bait_fw_worm.png',
                        width: 40, height: 40, fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const Icon(Icons.catching_pokemon, color: Colors.amber),
                      ),
                    ),
                    title: Text(bait['name'], style: const TextStyle(color: Colors.white)),
                    subtitle: Text('잔량: ${bait['quantity']}개', style: const TextStyle(color: Colors.grey)),
                    trailing: isEquipped ? const Icon(Icons.check_circle, color: Color(0xFFD4AF37)) : null,
                    onTap: () {
                      setState(() {
                        equippedBait = bait; 
                      });
                      Navigator.pop(ctx);
                      
                      // 🎨 [럭셔리 패치] 하얀 스낵바 버리고 KREFT 전용 황금 팝업창 발사!
                      _showNotificationPopup(
                        '✨ 미끼 교체 완료', 
                        '[${bait['name']}] (으)로 미끼를 변경했습니다.\n이제 대물을 낚아보세요! 🎣', 
                        const Color(0xFFD4AF37)
                      );
                    },
                  );
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('닫기', style: TextStyle(color: Colors.grey))),
        ],
      ),
    );
  }

Widget _buildChatTab(int index, String title) {
  bool isActive = _currentChatTab == index;
  return GestureDetector(
    onTap: () {
      setState(() {
        _currentChatTab = index;
        // 전체 탭으로 돌아가면 귓속말 타겟 초기화 (선택 사항)
        if (index == 0) _whisperTargetNickname = null; 
      });
    },
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      margin: const EdgeInsets.only(right: 2), // 탭 사이 간격
      decoration: BoxDecoration(
        color: isActive ? Colors.amber : Colors.grey[700], // 선택되면 노란색!
        borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
      ),
      child: Text(
        title, 
        style: TextStyle(
          color: isActive ? Colors.black : Colors.white, 
          fontSize: 12, 
          fontWeight: FontWeight.bold
        )
      ),
    ),
  );
}
  // 🏢 State: 상태 변수들
  bool isSettingUp = true;    
  int _currentLevel = 0;
  int selectedRodCount = 2;   
  Color selectedChemiColor = Colors.green; 
  String selectedBait = '지렁이'; 

  bool isCasting = false; 
  bool isFloatInWater = false; 
  bool isRodEquipped = false;

  bool _isStrikeLocked = false; // 🚨 [추가] 챔질 다다닥 연타(더블클릭) 방지 자물쇠!
  bool _isTutorialDone = false; // 🚀 [추가] 튜토리얼 보상 2번 받는 꼼수 방지용!

  // 👩‍💼 GM 강팀장님 출근 상태 변수! (테스트를 위해 일단 true로 켜둘게요!)
  bool gmNoticeVisible = false;

  
  Map<String, dynamic>? equippedRod;  
  Map<String, dynamic>? equippedFloat; 
  Map<String, dynamic>? equippedBait;  
  Map<String, dynamic>? equippedSkin;
  Map<String, dynamic>? equippedSunglasses;
  Map<String, dynamic>? equippedBadge;
  Map<String, dynamic>? equippedReel;
  Map<String, dynamic>? equippedCooler; // 🧊 아이스박스(발밑 슬롯, 민물·바다 공용)
  Map<String, dynamic>? equippedNet;    // 🥅 뜰채(컨트롤, 민물/바다)
  Map<String, dynamic>? equippedBelt;   // 🎽 파워벨트(힘, 바다 전용)
  Map<String, dynamic>? equippedGloves; // 🧤 장갑(힘, 공용)
  Map<String, dynamic>? equippedLine;   // 🧵 낚시줄(힘, 내구도 m)
  Map<String, dynamic>? equippedGroundbait; // 🍚 밑밥(감도, 세션 버프)
  bool _groundbaitActive = false; // 🍚 이번 낚시터 세션에 밑밥 효과 적용 중
  bool _trapDeployed = false; // 🦐 새우 채집망 던져둔 상태
  Timer? _trapTimer;          // 🦐 1분마다 민물새우 적립
  Timer? _guildHeartbeat;     // 💓 길드 접속 유지(낚시 중)
  String _myRank = '초보';      // 🎖️ 현재 칭호(승급 자격 레벨 판정용)
  int _myTutStep = 99;          // 🎓 튜토리얼 단계(3=첫고기 퀘스트)
  bool _tutFishDone = false;    // 🎓 이번 세션 튜토리얼 첫고기 완료 기록함

  // 📡 실시간 핫타임 중계 감시용 변수
 
  bool isFighting = false;
  bool isPulling = false; 
  double tension = 0.5;
  Timer? fightTimer;
  int fightTicks = 0;
// --- [✨ 신규 다대편성 & 3초 입질 시스템 변수들] ---
  Map<int, Timer> waitTimers = {};      // (레거시) 각 찌별 '입질 대기' 타이머
  Map<int, Timer> escapeTimers = {};    // (레거시) 각 찌별 '3초 도망' 카운트다운 타이머
  Timer? _biteTimer;                    // 🎣 단일 흐름: 다음 입질까지의 타이머(대수 무관, 바다와 동일 간격)
  Timer? _escapeTimer;                  // 🎣 단일 흐름: 올라온 찌가 내려가기까지(못 채면 놓침)
  Set<int> bitingRods = {};             // 현재 찌가 쭈욱! 올라와 있는 낚싯대 번호들
  Timer? gameTimer;
  int? fightingRodIndex; // 🎣 현재 물고기랑 사투(당기기) 중인 낚싯대 번호!
 
  late AnimationController _rodController; 
  late AnimationController _castController; 

  final TextEditingController _chatController = TextEditingController();

  // 🛡️ 길드 버프 (길드 레벨 + 주간 리그 챔피언)
  String _guildId = '';
  int _guildLevel = 0;
  bool _isChampionGuild = false; // 지난주 길드 리그 1위 → 이번주 추가 버프
  int _myGaramRank = 0; // 🎖️ 가람 주간 개인랭킹 순위(0=없음) → PCS 보너스
  bool _arenaEndedNaturally = false; // ⚔️ 아레나 10분 정상 종료(true) vs 도중 이탈(false=실격)
  bool _arenaWalkoverWin = false;    // 🏳️ 상대 전원 기권 → 혼자 남아 나감(기권승) → dispose에서 실격 처리 안 함

  Future<void> _loadGuildBuff() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    // 🎖️ 가람 주간 개인랭킹 보너스 (길드 여부와 무관)
    try {
      final gr = await FirebaseFirestore.instance.collection('garam_rank').doc('state').get();
      final ranks = gr.data()?['ranks'];
      int r = 0;
      if (ranks is Map && ranks[user.uid] is Map) {
        r = ((ranks[user.uid]['rank'] ?? 0) as num).toInt();
      }
      if (mounted) setState(() => _myGaramRank = r);
    } catch (_) {}
    try {
      final udoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      final gid = (udoc.data()?['guildId'] ?? '').toString();
      if (gid.isEmpty) return;
      final gdoc = await FirebaseFirestore.instance.collection('guilds').doc(gid).get();
      final gexp = (gdoc.data()?['guildExp'] is num) ? (gdoc.data()!['guildExp'] as num).toInt() : 0;
      // 🏆 주간 리그 챔피언 여부
      bool champ = false;
      try {
        final st = await FirebaseFirestore.instance.collection('guild_league').doc('state').get();
        champ = (st.data()?['championGuildId'] ?? '') == gid &&
            (st.data()?['activeWeek'] ?? '') == FishingLogic.weekKey(DateTime.now());
      } catch (_) {}
      if (mounted) {
        setState(() {
          _guildId = gid;
          _guildLevel = FishingLogic.guildLevelFromExp(gexp);
          _isChampionGuild = champ;
        });
      }
    } catch (_) {}
  }

  // 🏢 Helper: 능력치 긁어오기 (게임 두뇌로 연결!) + 길드 버프 합산
  Map<String, int> getMyTotalStats() {
    final s = FishingLogic.getMyTotalStats(
      equippedSkin: equippedSkin,
      equippedRod: equippedRod,
      equippedFloat: equippedFloat,
      equippedReel: equippedReel,
      equippedSunglasses: equippedSunglasses,
      equippedBadge: equippedBadge,
      equippedCooler: equippedCooler,
      equippedBait: (widget.roomId != null) ? null : equippedBait, // 🪱 미끼 감도(S) 반영 → 입질 속도 (아레나는 평준화 위해 제외)
      equippedNet: equippedNet,       // 🥅 뜰채(C)
      equippedBelt: equippedBelt,     // 🎽 파워벨트(P)
      equippedGloves: equippedGloves, // 🧤 장갑(P)
      equippedLine: equippedLine,     // 🧵 낚시줄(P)
      equippedGroundbait: _groundbaitActive ? equippedGroundbait : null, // 🍚 밑밥(S) — 세션 활성 시만
    );
    // 🏆 아레나는 완전 평준화: 길드/챔피언/주간랭킹/이벤트아이템 보너스도 미적용(전원 장비값만)
    if (widget.title != widget.locationName) return s;
    int b = FishingLogic.guildStatBonus(_guildLevel);
    if (_isChampionGuild) b += FishingLogic.guildChampionBonus;
    b += garamRankBonus(_myGaramRank); // 🎖️ 주간 개인랭킹 보너스(1주일)
    final evB = eventItemBonus(_latestInventory); // 🎁 이벤트 아이템 보유 버프(가방에 있으면 적용)
    if (b <= 0 && (evB['P'] ?? 0) == 0 && (evB['C'] ?? 0) == 0 && (evB['S'] ?? 0) == 0) return s;
    return {
      'strength': (s['strength'] ?? 0) + b + (evB['P'] ?? 0),
      'control': (s['control'] ?? 0) + b + (evB['C'] ?? 0),
      'sensitivity': (s['sensitivity'] ?? 0) + b + (evB['S'] ?? 0),
    };
  }

  // 🌟 1. initState() 바로 위에 이 줄을 추가해서 타이머 변수를 만듭니다.
  DateTime? _joinTime;

  @override
  void initState() {
  super.initState();
    WeatherService.instance.refresh(); // 🌧️ 실시간 날씨(위치→기상청) 요청
    loadGameEvent().then((_) { if (mounted) setState(() {}); }); // 🎉 이벤트 설정 새로고침(배너·배율 반영)
    _lastGaramTime = DateTime.now().add(const Duration(minutes: 10));

    // 🚀 [추가] 낚시터 입장 시 윤슬이 출입증 검사!
    _blockYunseulInFishing();

    // 🛡️ 길드 버프 불러오기 (능력치 보너스)
    _loadGuildBuff();
    final String presenceLoc = (widget.title != widget.locationName) ? '아레나' : '낚시터'; // 📍 접속 위치
    guildGoOnline(nick: widget.nickname, loc: presenceLoc); // 🟢 전역 접속표시(+위치)
    _guildHeartbeat = Timer.periodic(const Duration(seconds: 12), (_) { if (mounted) guildGoOnline(nick: widget.nickname, loc: presenceLoc); }); // 💓 낚시 중에도 접속 유지

    // 🚀 [추가] 튜토리얼 중인 쌩초보 유저면 윤슬님 출근시키기!
    if (widget.isFirstTime) {
      _fishingStep = 0;
    }
    
    // 🌟 2. 낚시터 입장하자마자 현재 시간을 딱! 찍어둡니다.
    _joinTime = DateTime.now(); 

    _rodController = AnimationController(vsync: this, duration: const Duration(milliseconds: 150))..repeat(reverse: true);
    _castController = AnimationController(vsync: this, duration: const Duration(milliseconds: 300));
    _startGameTimer();

    // 🌟 낚시터 입장 시 장비 쓱~ 불러오기!
    if (globalIsSeaMode == widget.isSea) {
      equippedRod = globalEquippedRod;
      equippedFloat = globalEquippedFloat;
      equippedBait = globalEquippedBait;
      equippedReel = globalEquippedReel;
      equippedNet = globalEquippedNet;   // 🥅 뜰채(모드별)
      equippedBelt = globalEquippedBelt; // 🎽 파워벨트(바다 전용)
      equippedLine = globalEquippedLine;             // 🧵 낚시줄(모드별)
      equippedGroundbait = globalEquippedGroundbait; // 🍚 밑밥(모드별)
    } else {
      globalIsSeaMode = widget.isSea;
      globalEquippedRod = null; globalEquippedFloat = null;
      globalEquippedBait = null; globalEquippedReel = null;
      globalEquippedNet = null; globalEquippedBelt = null;
      globalEquippedLine = null; globalEquippedGroundbait = null;
    }
    equippedSkin = globalEquippedSkin;
    equippedSunglasses = globalEquippedSunglasses;
    equippedBadge = globalEquippedBadge;
    equippedCooler = globalEquippedCooler;   // 🧊 공용(모드 무관)
    equippedGloves = globalEquippedGloves;   // 🧤 장갑 공용(모드 무관)

    // 🛡️ 위치(민물/바다)와 안 맞는 장비는 전부 자동 해제!
    //    (광장에서 민물 장비 착용 → 바다 낚시터에서 민물 낚싯대·찌·휘장 등이 그대로 먹히던 버그 방지)
    //    릴·벨트=바다 전용, 낚싯대·찌·뜰채·낚시줄·밑밥·휘장=민물/바다 구분. 장갑·아이스박스·선글라스=공용(COMMON) 유지.
    final String wantCat = widget.isSea ? 'SEA' : 'FW';
    bool wrongCat(Map<String, dynamic>? it) {
      if (it == null) return false;
      final c = (it['category'] ?? '').toString().toUpperCase();
      return c != wantCat && c != 'COMMON';
    }
    int strippedCount = 0;
    if (wrongCat(equippedRod))        { equippedRod = null;        globalEquippedRod = null;        strippedCount++; }
    if (wrongCat(equippedFloat))      { equippedFloat = null;      globalEquippedFloat = null;      strippedCount++; }
    if (wrongCat(equippedBait))       { equippedBait = null;       globalEquippedBait = null;       strippedCount++; }
    if (wrongCat(equippedReel))       { equippedReel = null;       globalEquippedReel = null;       strippedCount++; }
    if (wrongCat(equippedNet))        { equippedNet = null;        globalEquippedNet = null;        strippedCount++; }
    if (wrongCat(equippedBelt))       { equippedBelt = null;       globalEquippedBelt = null;       strippedCount++; }
    if (wrongCat(equippedLine))       { equippedLine = null;       globalEquippedLine = null;       strippedCount++; }
    if (wrongCat(equippedGroundbait)) { equippedGroundbait = null; globalEquippedGroundbait = null; _groundbaitActive = false; strippedCount++; }
    if (wrongCat(equippedBadge))      { equippedBadge = null;      globalEquippedBadge = null;      strippedCount++; }

    // 아레나(강제 세팅)가 아닌 일반 낚시터에서 실제로 해제된 게 있으면 안내
    if (strippedCount > 0 && widget.title == widget.locationName) {
      final String modeLabel = widget.isSea ? '바다' : '민물';
      final String otherLabel = widget.isSea ? '민물' : '바다';
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showNotificationPopup('🔄 장비 자동 정리',
            '$otherLabel 전용 장비는 $modeLabel 낚시터에서 쓸 수 없어\n자동으로 해제했어요.\n$modeLabel 장비로 다시 장착해 주세요.',
            const Color(0xFFD4AF37));
      });
    }

    isRodEquipped = equippedRod != null;

    // 🍚 일반 낚시터 입장 시 밑밥 1개 소모 → 이번 세션 감도 +10 (아레나는 method 내부에서 제외)
    _useGroundbaitOnEntry();

    // 👇 [여기서부터 덮어씌우기] 아레나 모드 진입 시 장비 강제 풀세팅!
    if (widget.title != widget.locationName) {
      _currentChatTab = 3;
      
      // 💡 사장님 요청: 기본 레벨 스탯 일괄 100으로 고정!
      // realLevel = 30;      // 👈 찾아내신 진짜 레벨 변수! (강제 Lv.100)
      

      // 💡 2. 공통 최상급 장비 (스킨, 선글라스)
      equippedSkin = {'name': '마스터 조사', 'price': 100000, 'category': 'SKIN', 'type': 'SKIN', 'stats': {'P': 300, 'C': 300, 'S': 300}, 'icon': '../images/skin_master.jpg', 'desc': '낚시계의 살아있는 전설'};
      equippedSunglasses = {'name': '선글라스', 'price': 5000, 'category': 'COMMON', 'type': 'ETC', 'stats': {'P': 10, 'C': 10, 'S': 10}, 'icon': 'item_sunglasses.png', 'desc': '눈부심을 막아 찌를 잘 보게 해주는 장비'};
      equippedCooler = null; // 🧊 아이스박스(발밑 슬롯)는 개인차가 나므로 아레나에선 제거 → 완전 평준화
      equippedNet = null; equippedBelt = null; equippedGloves = null; equippedBadge = null; // 🆕 P/C/S 장비(휘장 포함)도 아레나 평준화 위해 제거
      equippedLine = null; equippedGroundbait = null; _groundbaitActive = false; // 🧵🍚 낚시줄·밑밥도 아레나 제거

      // 💡 3. 민물 / 바다 완벽 분기 처리!
      if (widget.isSea) {
        // 🌊 [바다 모드] 심해 대물용 끝판왕 세팅
        equippedRod = {'name': 'KT500', 'price': 100000, 'category': 'SEA', 'type': 'ROD', 'stats': {'P': 50, 'C': 50, 'S': 50}, 'icon': 'rod_sea_kt500.png', 'desc': '심해 대물 제압용 마스터 바다대'};
        equippedReel = {'name': 'KF8000', 'price': 30000, 'category': 'SEA', 'type': 'REEL', 'stats': {'P': 30, 'C': 30, 'S': 30}, 'icon': 'reel_sea_kf8000.png', 'desc': '괴물과 싸우기 위한 마스터급 대형 릴'};
        equippedFloat = null; // 바다는 보통 릴+루어 위주!
        equippedBait = {'name': '에기', 'price': 500, 'category': 'SEA', 'type': 'BAIT', 'quantity': 50, 'icon': 'bait_sea_egi.png', 'desc': '두족류(오징어, 문어 등) 전용 미끼 (집어력 30)'};
        equippedBadge = {'name': '바다 휘장', 'price': 10000, 'category': 'SEA', 'type': 'ETC', 'stats': {'P': 50, 'C': 50, 'S': 50}, 'icon': 'item_badge_sea.png', 'desc': '바다 낚시 명예의 증표'};
      } else {
        // 🏞️ [민물 모드] 대물 붕어용 끝판왕 세팅
        equippedRod = {'name': 'KT-40T', 'price': 100000, 'category': 'FW', 'type': 'ROD', 'stats': {'P': 50, 'C': 50, 'S': 50}, 'icon': 'rod_fw_kt40.png', 'desc': '민물 낚시의 정점, 마스터 민물대'};
        equippedFloat = {'name': 'KT 전자찌', 'price': 30000, 'category': 'FW', 'type': 'FLOAT', 'stats': {'P': 30, 'C': 30, 'S': 30}, 'icon': 'float_fw_elec_kt.png', 'desc': '압도적인 시인성을 자랑하는 최고급 전자찌'};
        equippedReel = null; // 민물 대낚시는 릴 없음!
        equippedBait = {'name': '옥수수', 'price': 500, 'category': 'FW', 'type': 'BAIT', 'quantity': 50, 'icon': 'bait_fw_corn.png', 'desc': '대물 붕어를 노리기 위한 미끼 (집어력 30)'};
        equippedBadge = {'name': '민물 휘장', 'price': 10000, 'category': 'FW', 'type': 'ETC', 'stats': {'P': 50, 'C': 50, 'S': 50}, 'icon': 'item_badge_fw.png', 'desc': '민물 낚시 명예의 증표'};
      }
      
      isRodEquipped = true; // 낚싯대 강제 장착 완료!

      // 🚀 [추가할 코드] 아레나 모드 대편성 자동 세팅! (바다는 1대, 민물은 14대 팍!)
      if (widget.isSea) {
        selectedRodCount = 1; 
      } else {
        selectedRodCount = 14; 
      }

      // 💡 4. 화면이 다 그려진 직후에 웅장한 황금빛 팝업창 띄우기
      WidgetsBinding.instance.addPostFrameCallback((_) {
        showDialog(
          context: context,
          barrierDismissible: false, 
          builder: (BuildContext context) {
            return AlertDialog(
              backgroundColor: const Color(0xFF2A2A2A),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              contentPadding: const EdgeInsets.all(24),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.auto_awesome, color: Color(0xFFD4AF37), size: 60), 
                  const SizedBox(height: 16),
                  const Text(
                    '🏆 대회 전용 장비 지급!',
                    style: TextStyle(color: Color(0xFFD4AF37), fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    widget.isSea 
                        ? '🌊 [캠핑피싱] 바다용 끝판왕 풀세트가\n자동 착용되었습니다.'
                        : '🏞️ [캠핑피싱] 민물용 끝판왕 풀세트가\n자동 착용되었습니다.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 16, height: 1.4),
                  ),
                ],
              ),
              actions: [
                Center(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFD4AF37),
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                      padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 10),
                    ),
                    onPressed: () {
                      Navigator.pop(context); // 팝업 닫고 게임 시작!
                    },
                    child: const Text('확인', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  ),
                ),
              ],
            );
          },
        );
      });
    }
    // 👆 [여기까지 덮어씌우기 완료!]
  }
  
  @override
  void dispose() {
    // ⚔️ 아레나 경기 도중(시간 종료 전) 이탈 → 실격 기록 (실수든 고의든 종료 전 이탈 = 실격)
    //    단, 기권승(_arenaWalkoverWin)으로 나가는 사람은 실격 아님(유일 완주자로 정산받아야 함)
    if (widget.roomId != null && !_arenaEndedNaturally && !_arenaWalkoverWin) {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        FirebaseFirestore.instance.collection('arenas').doc(widget.roomId).collection('participants').doc(uid)
            .set({'forfeit': true}, SetOptions(merge: true)).catchError((Object _) {});
      }
    }
    // ⏱️ 아레나에서 '실제로 있던 시간'만큼 낚시 가능시간(remainingTime) 차감 — 5분만 하면 5분만 깎임.
    //    경과 = 10분(600) − 남은 아레나 시간(arenaTimeLeft). 완주(0)면 600, 5분 이탈이면 300 차감.
    if (widget.roomId != null) {
      final int elapsed = (600 - arenaTimeLeft).clamp(0, 600);
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (elapsed > 0 && uid != null) {
        final ref = FirebaseFirestore.instance.collection('users').doc(uid);
        // 음수 방지 위해 read→clamp→write (fire-and-forget)
        ref.get().then((snap) {
          final int cur = ((snap.data()?['remainingTime'] ?? 0) as num).toInt();
          final int next = (cur - elapsed) < 0 ? 0 : (cur - elapsed);
          ref.set({'remainingTime': next}, SetOptions(merge: true)).catchError((Object _) {});
        }).catchError((Object _) {});
      }
    }
    // 🚨 [버그 해결] 아레나 모드가 아닐 때(일반 낚시터)만 내 진짜 장비를 저장합니다!
    // 아레나에서 나갈 때는 엑스칼리버(임시 장비)를 전역 변수에 덮어씌우지 않고 쿨하게 버립니다.
    if (widget.title == widget.locationName) {
      globalEquippedRod = equippedRod;
      globalEquippedFloat = equippedFloat;
      globalEquippedBait = equippedBait;
      globalEquippedSkin = equippedSkin;
      globalEquippedSunglasses = equippedSunglasses;
      globalEquippedBadge = equippedBadge;
      globalEquippedReel = equippedReel;
      globalEquippedCooler = equippedCooler; // 🧊
      globalEquippedNet = equippedNet;       // 🥅
      globalEquippedBelt = equippedBelt;     // 🎽
      globalEquippedGloves = equippedGloves; // 🧤
      globalEquippedLine = equippedLine;             // 🧵
      globalEquippedGroundbait = equippedGroundbait; // 🍚
      globalIsSeaMode = widget.isSea;
    }

    
    fightTimer?.cancel();
    _clearAllBiteTimers();
    _rodController.dispose();
    _castController.dispose();
    _trapTimer?.cancel(); // 🦐 채집망 타이머 정리
    _guildHeartbeat?.cancel(); // 💓 길드 하트비트 정리
    // 🔇 효과음만 즉시 정지. 배경음(BGM)은 stop하지 않음 —
    //    광장 복귀 시 playBgm('bgm_menu')가 낚시 BGM을 '교체'하게 둬서
    //    stop↔play 경쟁(음악이 나오려다 끊김)을 방지한다.
    audioManager.stopEfx();
    super.dispose();
  }

// 🚫 바다, 타 지역 & 경력직 유저 윤슬이 접근 금지 로직
  Future<void> _blockYunseulInFishing() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
    if (doc.exists) {
      int myExp = doc.data()!.containsKey('exp') ? doc.data()!['exp'] : 0;
      
      // 🚀 [철벽 방어 업그레이드!] 
      // 1. 바다(widget.isSea)에 왔거나
      // 2. '예당지'가 아닌 다른 저수지로 도망(?)쳤거나
      // 3. 경험치가 1이라도 있으면 윤슬이 강제 퇴근!
      if (widget.isSea || !widget.locationName.contains('예당지') || myExp > 0) {
        if (mounted) {
          setState(() {
            _isTutorialDone = true; // "튜토리얼 이미 깼다"고 앱을 속임
            _fishingStep = -1;      // 윤슬이 강제 퇴장!
          });
        }
      }
    }
  }

  // 🚀 파이어베이스로 채팅 쏘기!
  void _sendMessage() {
    String text = _chatController.text.trim();
    if (text.isEmpty) return;
    text = FishingLogic.cleanChat(text); // 🛡️ 비속어 필터

    // 🏆 1. 아레나 탭(3번)일 때는 '아레나 전용 방'으로 바로 쏩니다!
    if (_currentChatTab == 3) {
      if (widget.roomId != null) {
        FirebaseFirestore.instance
            .collection('arenas')
            .doc(widget.roomId!) // 👈 현재 아레나 방 번호
            .collection('messages') // 👈 아레나 전용 메시지함!
            .add({
          'nickname': widget.nickname,
          'message': text,
          'type': 'arena',
          'createdAt': FieldValue.serverTimestamp(), 
        });
      }
      _chatController.clear();
      return; // 🚨 여기서 함수 종료! 전체 채팅으로 안 새어나가게 막음!
    }

    // 💬 2. 그 외 탭(전체/귓속말)은 기존처럼 글로벌 채팅으로!
    String type = 'global';
    String receiver = '';

    if (_currentChatTab == 1 && _whisperTargetNickname != null) {
      type = 'whisper';
      receiver = _whisperTargetNickname!;
    }

    FirebaseFirestore.instance.collection('global_chat').add({
      'nickname': widget.nickname,
      'message': text,
      'type': type,
      'receiver': receiver,
      'timestamp': FieldValue.serverTimestamp(),
    });

    _chatController.clear();
  }
  
  // 📥 1. 파이어베이스에서 남은 시간 불러오기 
  Future<void> _loadDailyTimeFromFirebase() async {
    User? user = FirebaseAuth.instance.currentUser;
    int retry = 0;
    while (user == null && retry < 10) {
      await Future.delayed(const Duration(milliseconds: 300));
      user = FirebaseAuth.instance.currentUser;
      retry++;
    }

    if (user != null) {
      String today = DateTime.now().toString().substring(0, 10);
      var doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      
      if (mounted) {
        if (doc.exists && doc.data()!.containsKey('lastPlayedDate')) {
          String lastDate = doc.data()!['lastPlayedDate'];
          if (lastDate == today) {
            setState(() { remainingTimeNotifier.value = doc.data()!['remainingTime'] ?? 3600; });
          } else {
            setState(() { remainingTimeNotifier.value = 3600; });
            _saveDailyTimeToFirebase(3600);
          }
        } else {
          setState(() { remainingTimeNotifier.value = 3600; });
          _saveDailyTimeToFirebase(3600);
        }
      }
    }
  }

  // 💾 2. 파이어베이스에 남은 시간 저장하기
  void _saveDailyTimeToFirebase(int timeToSave) {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      String today = DateTime.now().toString().substring(0, 10);
      FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'lastPlayedDate': today,
        'remainingTime': timeToSave,
      }, SetOptions(merge: true));
    }
  }

  void _startGameTimer() {
    if (gameTimer != null && gameTimer!.isActive) return;

    // ⚔️ [아레나 모드] 메인 시간 멈추고 10분 단판 타이머 가동!
    if (widget.title != widget.locationName) {
      // 🌟 1. 종료 시각을 못 박아둡니다. 공유 playEndAt이 있으면 그걸 써서 전원 '동시 종료'(입장 타이밍·클럭차 무관).
      DateTime arenaEndTime = (widget.playEndAt != null && widget.playEndAt! > 0)
          ? DateTime.fromMillisecondsSinceEpoch(widget.playEndAt!)
          : DateTime.now().add(Duration(seconds: arenaTimeLeft));

      gameTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted) { timer.cancel(); return; }

        setState(() {
          // 🌟 2. 1초씩 빼는 게 아니라, 목표 시간과 '지금 현실 시간'의 차이를 계산합니다!
          int realRemaining = arenaEndTime.difference(DateTime.now()).inSeconds;

          if (realRemaining > 0) {
            arenaTimeLeft = realRemaining; // 통화하느라 멈췄던 시간만큼 알아서 훅 건너뜁니다!
          } else {
            arenaTimeLeft = 0; // 마이너스로 떨어지는 것 방지
            _arenaEndedNaturally = true; // ⚔️ 정상 종료(완주) — 실격 아님
            // 🚨 10분 종료! 타이머들 싹 다 정지
        timer.cancel();
        _clearAllBiteTimers();
        fightTimer?.cancel();

        // 파이팅 중이었다면 파이팅 팝업 강제 종료
        if (isFighting) {
          isFighting = false;
          if (Navigator.canPop(context)) Navigator.pop(context); 
        }

        // 💡 [안전장치] 화면이 아직 살아있을 때만 종료 팝업 띄우기
        if (!mounted) return; 

        showDialog(
          context: context,
          barrierDismissible: false, // 💡 바깥쪽 터치해서 꼼수로 못 닫게 막음!
          builder: (dialogContext) => AlertDialog(
            backgroundColor: Colors.black87,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15), 
              side: const BorderSide(color: Colors.amber, width: 2)
            ),
            title: const Text('⏱️ 경기 종료!', style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold)),
            content: const Text('10분 경기가 모두 종료되었습니다.\n대기실로 돌아가 결과를 확인하세요!', style: TextStyle(color: Colors.white)),
            actions: [
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.amber, foregroundColor: Colors.black),
                onPressed: () {
                  // 1. 경기 종료 팝업 먼저 닫기
                  Navigator.of(dialogContext).pop();
                  
                  // 2. 0.1초 뒤에 낚시터 닫고 대기실로 강제 복귀! (안전한 화면 전환을 위해)
                  Future.delayed(const Duration(milliseconds: 100), () {
                    if (mounted) {
                      Navigator.of(context).pop(); 
                    }
                  });
                },
                child: const Text('대기실로 이동', style: TextStyle(fontWeight: FontWeight.bold)),
              )
            ],
          ),
        );
      }
        });
      });
      return; // 🚨 여기서 리턴시켜서 일반 60분 타이머가 안 돌아가게 막습니다!
    }

    // 🏞️ [일반 낚시터 모드] 사장님 기존 로직 그대로! (60분 깎기)
    _loadDailyTimeFromFirebase();
    gameTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) { timer.cancel(); return; }

      if (remainingTimeNotifier.value > 0) {
        remainingTimeNotifier.value--;
        if (remainingTimeNotifier.value % 10 == 0) {
          _saveDailyTimeToFirebase(remainingTimeNotifier.value);
        }
      } else {
        // ... (사장님의 기존 시간 소진 상점 이동 로직 유지) ...
        timer.cancel(); _clearAllBiteTimers(); fightTimer?.cancel();
        if (isFighting) {
          if (Navigator.canPop(context)) Navigator.pop(context);
          setState(() { isFighting = false; });
        }

        // 🚨 시간이 0초면 세팅 화면(상점 앞)으로 전환하고 안내창 띄우기!
        if (!isSettingUp) {
          setState(() { isSettingUp = true; });
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (context) {
              return AlertDialog(
                backgroundColor: Colors.black87,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15), side: const BorderSide(color: Colors.amber, width: 2)),
                title: const Row(
                  children: [
                    Icon(Icons.storefront, color: Colors.amber),
                    SizedBox(width: 10),
                    Text('낚시 시간 종료', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ],
                ),
                content: const Text(
                  '오늘의 낚시 시간이 모두 소진되었습니다.\n하지만 KREFT 상점은 24시간 열려있습니다!\n느긋하게 쇼핑을 즐겨보세요. 😎',
                  style: TextStyle(color: Colors.white70),
                ),
                actions: [
                  TextButton(
                    onPressed: () {
                      Navigator.pop(context); // 🚨 강제 퇴장 안 함! 상점에 머무르게 둠!
                    },
                    child: const Text('상점 구경하기', style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold)),
                  ),
                ],
              );
            },
          );
        }
      }
    });
  }

  // 1️⃣ 캐스팅 직후 '다음 입질' 예약 시작 (단일 흐름)
  void _startBiteTimer() {
    _clearAllBiteTimers(); // 혹시 도는 거 있으면 싹 청소
    _scheduleNextBite();
  }

  // 2️⃣ [단일 흐름 핵심] 입질 하나가 끝나면 바다와 같은 간격(10~20초) 뒤에
  //    펼쳐진 찌 중 '랜덤 하나'가 올라온다. → 낚시대 대수와 무관하게 입질 속도 동일(민물=바다 밸런스)
  void _scheduleNextBite() {
    _biteTimer?.cancel();
    _escapeTimer?.cancel();
    if (!mounted || !isFloatInWater) return;

    // 🎣 대수 무관, 바다와 동일한 입질 간격(기본 10~20초)
    const int baseMin = 10;
    const int baseMax = 20;
    // 🪝 [센서 감도 보정] 감도(S)가 높을수록 입질이 빨리 옴.
    //   초보 기준(S≈30) 0% → 감도가 높을수록 최대 30%까지 대기시간 단축.
    const int kSensBase = 30;    // 초보 기준 감도(보정 0%)
    const int kSensFull = 300;   // 이 이상이면 최대 단축
    const double kMaxCut = 0.30; // 최대 단축 비율(30%)
    final int sens = getMyTotalStats()['sensitivity'] ?? 0;
    final double cut =
        (((sens - kSensBase) / (kSensFull - kSensBase)).clamp(0.0, 1.0)) * kMaxCut;
    final int minWait = (baseMin * (1 - cut)).round();
    final int maxWait = (baseMax * (1 - cut)).round();
    final int waitTime = minWait + math.Random().nextInt(maxWait - minWait + 1);

    _biteTimer = Timer(Duration(seconds: waitTime), () {
      if (!mounted || !isFloatInWater) return;
      // 사투 중이거나 이미 찌가 올라와 있으면 이번 턴 스킵하고 다시 예약
      if (isFighting || fightingRodIndex != null || bitingRods.isNotEmpty) {
        _scheduleNextBite();
        return;
      }

      // 펼쳐진 낚싯대 중 랜덤으로 하나 선택해서 입질!
      final int rods = selectedRodCount < 1 ? 1 : selectedRodCount;
      final int rodIndex = math.Random().nextInt(rods);
      setState(() { bitingRods.add(rodIndex); });
      HapticFeedback.lightImpact();

      // 찌가 올라가 정점 찍고 약 4.5초 대기 → 못 채면 놓치고 다음 입질 예약
      _escapeTimer = Timer(const Duration(milliseconds: 4500), () {
        if (!mounted) return;
        setState(() { bitingRods.remove(rodIndex); });
        if (isFloatInWater) _scheduleNextBite();
      });
    });
  }

  // 3️⃣ 챔질 성공하거나 화면 나갈 때 타이머 싹 꺼주는 청소기
  void _clearAllBiteTimers() {
    _biteTimer?.cancel();
    _escapeTimer?.cancel();
    for (var timer in waitTimers.values) { timer.cancel(); }
    for (var timer in escapeTimers.values) { timer.cancel(); }
    waitTimers.clear();
    escapeTimers.clear();
    bitingRods.clear();
  }

  void _handleMainActionButton() {
    // 🚨 1. 자물쇠 확인 및 잠그기 (더블클릭 완벽 차단!)
    if (_isStrikeLocked) return; 
    _isStrikeLocked = true;

    if (isFloatInWater && !isFighting) {
      if (bitingRods.isNotEmpty) {
        int targetRod = bitingRods.first;

        setState(() {
          fightingRodIndex = targetRod; // 당기기 전담 낚싯대로 지정!
          bitingRods.remove(targetRod); // 입질 목록에서 뺌 (찌 내려감)
        });
        // 입질 흐름 타이머 정지 (전투 끝나면 _scheduleNextBite로 재개)
        _biteTimer?.cancel();
        _escapeTimer?.cancel();
        HapticFeedback.heavyImpact();
        audioManager.playSfx("sfx_hit.mp3");

        // 👉 [2탄] 게임 두뇌(FishingLogic)에 일 시키기!
        var caughtFish = FishingLogic.generateFish(
          isSea: widget.isSea,
          locationName: widget.locationName,
          currentBaitName: equippedBait != null ? equippedBait!['name'].toString() : ''
        );
        if (caughtFish != null) _startFight(caughtFish);
      } else {
      audioManager.playSfx("sfx_click.mp3");
      _showNotificationPopup('헛챔질!', '타이밍이 맞지 않았습니다.\n찌가 변하며 올라올 때 챔질하세요.', Colors.orangeAccent);
      
      // 🚨 핵심 포인트: isFloatInWater = false; 를 지웠습니다!
      setState(() { 
        isFighting = false; 
      });
    }
    } else if (isFighting) {
      _pullLine();
    }

    // 🚨 2. 0.5초 뒤에 스르륵 자물쇠 풀기!
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        setState(() {
          _isStrikeLocked = false; 
        });
      }
    });
  }

  void _startFight(Map<String, dynamic> fish) {
    setState(() {
      isFighting = true; // ⭐ 1. 앗! 고기 물었다! 파이팅 상태 켜기!
    });
    _useBaitOne(); // 🪱 #2 입질(파이팅 시작)마다 미끼 1개 소모 — 승리·실패 동일

    Map<String, int> myStats = getMyTotalStats();
    // 🏆 아레나는 완전 평준화(장비=마스터 지급 + 레벨 보너스 0) → 순수 실력 대결. 일반 낚시는 레벨 보너스 반영.
    final bool isArenaMode = widget.title != widget.locationName;
    final int lvBonus = isArenaMode ? 0 : ((_currentLevel > 0 ? _currentLevel : 1) - 1) * 3; // 🆙 레벨 보너스(제압력)
    double totalStats = ((myStats['strength'] ?? 0) + (myStats['control'] ?? 0) + (myStats['sensitivity'] ?? 0) + lvBonus).toDouble();

    // 🎣 [내부 함수] 실제 파이팅 미니게임을 띄우는 로직
    void launchFightOverlay() {
      showDialog(
        context: context,
        barrierDismissible: false, 
        builder: (context) {
          return Material(
            color: Colors.transparent, 
            child: FishingFightingOverlay(
              fish: fish,
              playerTotalStats: totalStats,
              locationStars: _getLocationStars(),
              rodImageSuffix: rodSceneSuffix(equippedRod), // 🎣 장착 낚싯대별 파이팅 그림

              onFinished: (bool isSuccess, double size) async { 
      Navigator.pop(context); 
      await Future.delayed(const Duration(milliseconds: 100));
      if (!mounted) return;
      setState(() { isFighting = false; });

      if (isSuccess) {
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          // 1. [아레나 모드] 기록 로직
          if (widget.roomId != null) {
            await FirebaseFirestore.instance.collection('arenas').doc(widget.roomId).collection('messages').add({
              'text': '📢 ${widget.nickname}님이 ${fish['name']} (${fish['size']}${fish['unit']})를 낚았습니다!', 
              'sender': '캠피싱', 
              'createdAt': FieldValue.serverTimestamp()
            });
            
            // ⚔️ 최대어 모드: 대상 어종만 카운트 (마릿수 모드는 모든 어종 카운트)
            final bool countsForArena = widget.winCondition != '최대어'
                || widget.targetFish == null
                || widget.targetFish == '모든 어종'
                || fish['name'].toString() == widget.targetFish;
            if (countsForArena) {
              double caughtSize = double.tryParse(fish['size'].toString()) ?? 0.0;
              var pRef = FirebaseFirestore.instance.collection('arenas').doc(widget.roomId).collection('participants').doc(user.uid);
              var pDoc = await pRef.get();

              double currentMaxSize = pDoc.exists && pDoc.data()!.containsKey('maxSize') ? (pDoc.data()!['maxSize'] ?? 0.0).toDouble() : 0.0;
              double bestSize = caughtSize > currentMaxSize ? caughtSize : currentMaxSize;

              await pRef.set({
                'nickname': widget.nickname,
                'score': FieldValue.increment(1),
                'maxSize': bestSize,
                'updatedAt': FieldValue.serverTimestamp()
              }, SetOptions(merge: true));
            }
          }
          // 2. [일반 낚시터 모드] 기록 로직
          else {
            final docRef = FirebaseFirestore.instance.collection('users').doc(user.uid);
            final doc = await docRef.get();
            if (doc.exists) {
              var data = doc.data() as Map<String, dynamic>;
              double currentMaxSize = 0.0;
              if (data.containsKey('maxCatch') && data['maxCatch'].containsKey(fish['name'])) {
                currentMaxSize = (data['maxCatch'][fish['name']]['size'] ?? 0.0).toDouble();
              }
              double caughtSize = double.tryParse(fish['size'].toString()) ?? 0.0;
              if (caughtSize > currentMaxSize) {
                await docRef.set({
                  'exp': FieldValue.increment(fish['exp'] as int), 
                  'gold': FieldValue.increment(fish['pts'] as int), 
                  'maxCatch': {fish['name']: {'size': caughtSize, 'date': DateTime.now().toIso8601String().substring(0, 10)}}
                }, SetOptions(merge: true));
              } else {
                await docRef.update({'exp': FieldValue.increment(fish['exp'] as int), 'gold': FieldValue.increment(fish['pts'] as int)});
              }
              // 🎓 튜토리얼 '첫 출조'(나루, tutStep 3) — 첫 고기 잡으면 미션 완료 기록
              //    안내 팝업은 광장 복귀 시 표시(_refreshTutFromDb) — 전투 오버레이 위 모달 충돌 방지
              if (_myTutStep == 3 && !_tutFishDone) {
                _tutFishDone = true;
                await docRef.set({'tutCleared': true}, SetOptions(merge: true));
              }
              // 🎖️ #13 6대장 누적 카운트 (승급 퀘스트용)
              //    ⛔ 다음 승급 자격 레벨에 도달한 뒤부터만 카운트 (저렙에서 미리 쌓이는 것 방지)
              if (daejangFish.contains(fish['name'])) {
                final nextTier = nextPromotion(_myRank);
                final reqLv = (nextTier?['level'] as int?) ?? 99999; // 최고 칭호면 카운트 안 함
                if (_currentLevel >= reqLv) {
                  await docRef.set({
                    'daejangCatch': {fish['name'].toString(): FieldValue.increment(1)}
                  }, SetOptions(merge: true));
                  // 🎉 방금 이 한 마리로 승급 조건(6대장 각 need마리)을 모두 채웠으면 안내 팝업
                  final need = (nextTier?['need'] as int?) ?? 99999;
                  final dcMap = (data['daejangCatch'] is Map)
                      ? Map<String, dynamic>.from(data['daejangCatch'])
                      : <String, dynamic>{};
                  int cnt(String n) => (dcMap[n] is num) ? (dcMap[n] as num).toInt() : 0;
                  final doneBefore = daejangFish.every((n) => cnt(n) >= need); // 잡기 전 이미 완료였나
                  final doneAfter = daejangFish
                      .every((n) => (cnt(n) + (n == fish['name'] ? 1 : 0)) >= need); // 이번 마리 포함
                  if (!doneBefore && doneAfter) {
                    _showNotificationPopup('🎖️ 승급 퀘스트 달성!',
                        '6대장을 모두 잡았어요! 🎉\n광장의 아라에게 가서\n[${nextTier?['rank']}] 승급을 받으세요!',
                        const Color(0xFFD4AF37));
                  }
                }
              }
              // 🛡️ 길드원이면 길드 경험치 + 주간 리그 점수 누적 (마릿수)
              if (_guildId.isNotEmpty) {
                final guildRef = FirebaseFirestore.instance.collection('guilds').doc(_guildId);
                final curWeek = FishingLogic.weekKey(DateTime.now());
                try {
                  await FirebaseFirestore.instance.runTransaction((tx) async {
                    final gs = await tx.get(guildRef);
                    if (!gs.exists) return;
                    final wk = (gs.data()?['weekKey'] ?? '').toString();
                    final prevWs = (gs.data()?['weeklyScore'] is num)
                        ? (gs.data()!['weeklyScore'] as num).toInt()
                        : 0;
                    final ws = (wk == curWeek) ? prevWs + 1 : 1; // 새 주면 1부터
                    tx.update(guildRef, {
                      'guildExp': FieldValue.increment(FishingLogic.guildExpPerCatch),
                      'weeklyScore': ws,
                      'weekKey': curWeek,
                    });
                    // 🏅 멤버 기여도(=길드에 쌓은 경험치) 누적 + 레벨 최신화
                    final myUid = FirebaseAuth.instance.currentUser?.uid;
                    if (myUid != null) {
                      tx.set(
                          guildRef.collection('members').doc(myUid),
                          {'contribution': FieldValue.increment(FishingLogic.guildExpPerCatch), 'level': _currentLevel},
                          SetOptions(merge: true));
                    }
                  });
                } catch (e) {
                  debugPrint('🛡️ 길드 점수 누적 실패: $e');
                }
              }
            }
          }
          // 성공 후 후속 처리
          HapticFeedback.heavyImpact(); 
          audioManager.playSfx("sfx_landing_success.mp3"); 
          // ⚔️ 아레나 모드에선 일일미션/인벤 저장 안 함(대회 점수만 반영). 일반 낚시터에서만.
          if (widget.roomId == null) {
            _checkDailyMission(fish['name'].toString());
            _storeCaughtFish(fish['name'].toString()); // 🐟 잡은 고기 가방에 보관(보배 판매·일일정산용)
          }
          if (widget.isFirstTime && !_isTutorialDone && fish['name'] == '붕어') {
            _showTutorialSuccessReward(fish);
          } else {
            _showResultPopup(fish);  
          }
        }
      } else {
        // 🚨 이 else가 아까 에러 났던 녀석입니다!
        _damageLineOnFail(); // 🧵 랜딩 실패 → 낚시줄 −10m (0m면 끊어짐)
        audioManager.playSfx("sfx_break.mp3");
        List<String> failMessages = ['와우~ 대물인데 아쉽습니다!\n상점에서 장비를 업그레이드 해보세요.', '앗! 바늘털이에 당했습니다.\n다음엔 텐션 조절을 조금 더 신중히 해보시죠!', '팅! 줄이 터져버렸네요...\n제압력이 더 높은 낚싯대가 필요할지도?', '아슬아슬했는데 코앞에서 놓쳤습니다!\n심호흡 한 번 하고 다시 캐스팅해 보시죠.', '물고기의 힘이 너무 압도적이네요!\n장비의 한계가 온 것 같습니다.', '수초를 감아버렸습니다!\n채비를 정비하고 다시 도전하세요.']; 
        String randomMsg = failMessages[math.Random().nextInt(failMessages.length)]; 
        _showNotificationPopup('💥 줄이 터졌습니다...', randomMsg, Colors.redAccent, onConfirm: _recast);
      }
    }, // 👈 onFinished 닫는 괄호!
            ),
          );
        }
      );
    } 

    // 🚀 [추가] 챔질 성공 직후! 파이팅 전 윤슬님 등판!
    if (widget.isFirstTime && !_isTutorialDone) {
      audioManager.playSfx('sfx_click.mp3');
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          child: Stack(
            clipBehavior: Clip.none, alignment: Alignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(25), 
                decoration: BoxDecoration(color: const Color(0xFFE4C766), borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white, width: 3)),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      "\n물고기가 걸렸어요!! 🐟\n\n당기기 버튼을 누르고 있으면 오른쪽으로 끌려와요.\n물고기가 저항할 때 손을 뗐다가 다시 누르고 있으면\n다시 왼쪽으로 끌려올 거예요!\n\n30초 안에 왼쪽 끝까지 가거나,\n중앙보다 왼쪽에 있으면 잡을 수 있어요!\n\n[붕어]를 낚으시면 선물을 드릴게요! 화이팅~~ 🎁", 
                      style: TextStyle(color: Colors.black, fontSize: 15, fontWeight: FontWeight.bold, height: 1.4),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.black, foregroundColor: const Color(0xFFE4C766),
                        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30))
                      ), 
                      onPressed: () { 
                        audioManager.playSfx('sfx_click.mp3');
                        Navigator.pop(ctx); 
                        launchFightOverlay(); // 설명 다 읽고 당기기 시작!
                      }, 
                      child: const Text('당기기 시작!', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18))
                    ),
                  ],
                ),
              ),
              Positioned(
                bottom: -60, right: -40, 
                child: Image.asset('assets/images/npc_girl_success.png', height: 180)
              ),
            ],
          ),
        ),
      );
    } else {
      launchFightOverlay(); 
    }
  } // 👈 🚨 [제 잘못!!] 아까 이 마지막 괄호(})를 빼먹어서 에러가 났던 겁니다 ㅠㅠ

  // 🎁 튜토리얼 붕어 잭팟 보상 함수! (무적 저장 버전!)
  Future<void> _showTutorialSuccessReward(Map<String, dynamic> fish) async {
    _isTutorialDone = true; // 원래 있던 튜토리얼 완료 처리

    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final userRef = FirebaseFirestore.instance.collection('users').doc(user.uid);
      try {
        // 🚀 update 대신 가장 강력하고 안전한 set(merge: true) 사용!
        // 다른 기록이 동시에 저장되더라도 절대 씹히지 않고 도장을 쾅 찍습니다.
        await userRef.set({
          'gold': FieldValue.increment(1000),
          'isFirstTime': false, 
        }, SetOptions(merge: true));
        
        print("✅ 튜토리얼 보상 지급 및 졸업 도장 완료!"); // 성공 확인용 로그
      } catch (e) {
        print("🚨 튜토리얼 보상 지급 에러: $e");
      }
    }

    if (!mounted) return;
    audioManager.playSfx('sfx_landing_success.mp3'); 
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.grey.shade900,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15), side: const BorderSide(color: Color(0xFFD4AF37), width: 2)),
        title: const Center(child: Text('🎊 튜토리얼 완료!', style: TextStyle(color: Color(0xFFD4AF37), fontWeight: FontWeight.bold))),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset('assets/images/npc_girl_success.png', width: 150),
            const SizedBox(height: 20),
            const Text('와아아!! 대박!! 진짜 붕어를 낚으셨네요! 🎊\n정말 잘하셨어요!', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            const Text('약속했던 1,000 P를 선물로 드립니다!\n캠피싱 낚시 대회에서 즐거운 시간 되세요~~ 🥰', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey, height: 1.5)),
          ],
        ),
        actions: [
          Center(
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFD4AF37), foregroundColor: Colors.black),
              onPressed: () {
                Navigator.pop(ctx);
                _showResultPopup(fish); 
              },
              child: const Text('보상 받고 계속하기', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          )
        ],
      ),
    );
  }

  void _pullLine() {
    if (!isFighting) return;
    HapticFeedback.mediumImpact();
    audioManager.playSfx(widget.isSea ? "sfx_sea_landing.mp3" : "sfx_fresh_landing.mp3");

    double rodPower = (equippedRod?['power'] ?? 0).toDouble();
    double baitPower = (equippedBait?['power'] ?? 0).toDouble();
    double totalPull = 0.06 + ((rodPower + baitPower) * 0.002);

    setState(() { tension -= totalPull; });
  }

  // 🍞 미끼 알림은 전투 중에도 안전하게 — 모달(다이얼로그) 금지, 비차단 스낵바 사용
  //    (전투 오버레이도 다이얼로그라, 위에 모달을 또 띄우면 Navigator.pop이 꼬여 전투가 멈춤)
  void _baitToast(String msg, Color color) {
    if (!mounted) return;
    final m = ScaffoldMessenger.maybeOf(context);
    if (m == null) return;
    m.hideCurrentSnackBar();
    m.showSnackBar(SnackBar(
      content: Text(msg, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black)),
      backgroundColor: color,
      duration: const Duration(seconds: 2),
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.only(bottom: 120, left: 60, right: 60),
    ));
  }

  Future<void> _useBaitOne() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || equippedBait == null) return;

    try {
      final userDoc = FirebaseFirestore.instance.collection('users').doc(user.uid);
      final snapshot = await userDoc.get();
      if (!snapshot.exists) return;

      List<dynamic> inventory = List.from(snapshot.data()?['inventory'] ?? []);
      String targetBaitName = equippedBait!['name'];

      for (int i = 0; i < inventory.length; i++) {
        if (inventory[i]['name'] == targetBaitName) {
          int q = inventory[i]['quantity'] ?? 0;
          if (q > 0) {
            inventory[i]['quantity'] = q - 1;
            if (inventory[i]['quantity'] == 0) {
              inventory.removeAt(i);
              // 🔁 같은 종류(민물/바다) 미끼가 가방에 남아있으면 자동 교체
              final wantCat = widget.isSea ? 'SEA' : 'FW';
              Map<String, dynamic>? nextBait;
              for (final it in inventory) {
                final m = it as Map<String, dynamic>;
                final t = (m['type'] ?? '').toString().toUpperCase();
                final c = (m['category'] ?? '').toString().toUpperCase();
                final qn = (m['quantity'] is num) ? (m['quantity'] as num).toInt() : 0;
                if (t == 'BAIT' && c == wantCat && qn > 0) { nextBait = m; break; }
              }
              setState(() { equippedBait = nextBait; });
              if (nextBait != null) {
                if (mounted) _showNotificationPopup('🔁 미끼 자동 교체', '$targetBaitName 이(가) 다 떨어져서\n${nextBait['name']}(으)로 자동 교체했어요.', const Color(0xFFD4AF37));
              } else {
                if (mounted) _showNotificationPopup('🛑 미끼 소진', '미끼가 모두 떨어졌어요.\n가방에서 장착하거나 상점에서 구매하세요.', Colors.orangeAccent);
              }
            }
            break;
          }
        }
      }
      await userDoc.update({'inventory': inventory});
    } catch (e) { print("미끼 소모 중 에러: $e"); }
  }

  // 🧵 낚시줄 내구도: 랜딩 실패마다 −10m, 0m 되면 끊어짐(자동 해제 + 안내)
  Future<void> _damageLineOnFail() async {
    if (equippedLine == null || widget.roomId != null) return; // 아레나 제외
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final lineName = equippedLine!['name'].toString();
    try {
      final userDoc = FirebaseFirestore.instance.collection('users').doc(user.uid);
      final snap = await userDoc.get();
      if (!snap.exists) return;
      List<dynamic> inv = List.from(snap.data()?['inventory'] ?? []);
      final idx = inv.indexWhere((it) => (it['name'] ?? '') == lineName && (it['type'] ?? '') == 'LINE');
      if (idx < 0) return;
      int dur = (inv[idx]['dur'] is num) ? (inv[idx]['dur'] as num).toInt() : 200;
      dur -= 10;
      if (dur <= 0) {
        inv.removeAt(idx); // 줄 끊어짐 → 인벤에서 제거
        if (mounted) setState(() => equippedLine = null);
        globalEquippedLine = null;
        await userDoc.update({'inventory': inv});
        if (mounted) _baitToast('🧵 낚시줄이 끊어졌어요! 상점에서 새 줄을 구매하세요', Colors.redAccent);
      } else {
        inv[idx]['dur'] = dur;
        if (mounted) setState(() => equippedLine!['dur'] = dur);
        globalEquippedLine = equippedLine;
        await userDoc.update({'inventory': inv});
        if (mounted && dur <= 30) _baitToast('🧵 낚시줄 잔여 ${dur}m — 곧 끊어져요!', Colors.orangeAccent);
      }
    } catch (e) { debugPrint('낚시줄 내구도 처리 에러: $e'); }
  }

  // 🍚 밑밥: 낚시터 입장 시 1개 소모 → 이번 세션 감도 +10. 재고 0이면 해제 + 팝업 안내.
  Future<void> _useGroundbaitOnEntry() async {
    if (equippedGroundbait == null || widget.roomId != null) return; // 아레나 제외
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final gbName = equippedGroundbait!['name'].toString();
    try {
      final userDoc = FirebaseFirestore.instance.collection('users').doc(user.uid);
      final snap = await userDoc.get();
      if (!snap.exists) return;
      List<dynamic> inv = List.from(snap.data()?['inventory'] ?? []);
      final idx = inv.indexWhere((it) => (it['name'] ?? '') == gbName && (it['type'] ?? '') == 'GROUNDBAIT');
      int q = idx >= 0 ? ((inv[idx]['quantity'] is num) ? (inv[idx]['quantity'] as num).toInt() : 0) : 0;
      if (idx < 0 || q <= 0) {
        // 재고 없음 → 해제 + 안내 팝업
        if (mounted) setState(() { equippedGroundbait = null; _groundbaitActive = false; });
        globalEquippedGroundbait = null;
        if (idx >= 0) { inv.removeAt(idx); await userDoc.update({'inventory': inv}); }
        if (mounted) _showNotificationPopup('🍚 밑밥이 다 떨어졌어요', '밑밥이 모두 소진됐어요.\n상점에서 구매해 다시 장착하세요.', Colors.orangeAccent);
        return;
      }
      q -= 1; // 1개 소모
      if (q <= 0) { inv.removeAt(idx); globalEquippedGroundbait = null; } // 마지막 1개 사용 → 다음 세션엔 없음
      else { inv[idx]['quantity'] = q; }
      await userDoc.update({'inventory': inv});
      if (mounted) setState(() => _groundbaitActive = true); // 이번 세션 감도 +10 ON
      if (mounted) _showNotificationPopup('🍚 밑밥을 뿌렸어요!', '이번 낚시터에 머무는 동안 감도 +10 효과가 적용돼요.\n(잔여 $q개)', const Color(0xFF7FFFB0));
    } catch (e) { debugPrint('밑밥 소모 에러: $e'); }
  }

  // 🦐 새우 채집망 보유 여부
  bool _hasShrimpTrap() {
    return _latestInventory.any((it) => (it['name'] ?? '').toString() == '새우 채집망');
  }

  // 🦐 채집망 던지기/건지기 토글
  void _toggleShrimpTrap() {
    if (!_hasShrimpTrap()) return;
    if (widget.isSea) { _showNotificationPopup('🦐 민물 전용', '새우 채집망은 민물에서만 사용할 수 있어요.', Colors.orangeAccent); return; } // 바다 차단
    audioManager.playSfx("sfx_click.mp3");
    if (_trapDeployed) {
      // 건지기
      _trapTimer?.cancel();
      _trapTimer = null;
      setState(() => _trapDeployed = false);
      _showNotificationPopup('🦐 채집망 회수', '새우 채집망을 건졌어요.\n모은 민물새우는 가방에 있어요!', const Color(0xFFD4AF37));
    } else {
      // 던지기 → 1분마다 민물새우 +2
      setState(() => _trapDeployed = true);
      _trapTimer = Timer.periodic(const Duration(minutes: 1), (_) => _collectShrimp());
      _showNotificationPopup('🦐 채집망 던지기!', '민물에 채집망을 던졌어요.\n1분마다 민물새우가 모여요. (건지기로 종료)', const Color(0xFFD4AF37));
    }
  }

  // 📋 진행 중인 퀘스트 + 진행현황 (일일 민물/바다 · 서윤 의뢰 · 승급)
  void _showQuestPopup() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final fwM = getTodayFwMission();
    final seaM = getTodaySeaMission();
    final bobaeM = getTodayBobaeFish();

    Widget section(String title, List<Widget> rows) => Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.04),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white12)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(color: Color(0xFFD4AF37), fontSize: 15, fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            ...rows,
          ]),
        );
    Widget qRow(String label, int cur, int target, bool done) {
      final p = target > 0 ? (cur / target).clamp(0.0, 1.0) : 1.0;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600))),
            done
                ? const Text('✅ 완료', style: TextStyle(color: Color(0xFF7FFFB0), fontSize: 13, fontWeight: FontWeight.bold))
                : Text('$cur/$target', style: const TextStyle(color: Color(0xFFD4AF37), fontSize: 14, fontWeight: FontWeight.bold)),
          ]),
          const SizedBox(height: 5),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
                value: p, minHeight: 7, backgroundColor: Colors.white12,
                valueColor: AlwaysStoppedAnimation(done ? const Color(0xFF7FFFB0) : const Color(0xFFD4AF37))),
          ),
        ]),
      );
    }
    Widget note(String text, {Color color = Colors.white60}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Text(text, style: TextStyle(color: color, fontSize: 13, height: 1.35)),
        );

    showDialog(
      context: context,
      builder: (dctx) => Dialog(
        backgroundColor: const Color(0xFF161616),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0xFFD4AF37), width: 1.2)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480, maxHeight: 640),
          child: StreamBuilder<DocumentSnapshot>(
            stream: FirebaseFirestore.instance.collection('users').doc(user.uid).snapshots(),
            builder: (c, snap) {
              final d = (snap.data?.data() as Map<String, dynamic>?) ?? {};
              // 일일(민물/바다)
              final mp = d['mission_progress'];
              final sd = mp is Map && mp['date'] == today;
              final int fwP = sd && mp['fw'] is num ? (mp['fw'] as num).toInt() : 0;
              final int seaP = sd && mp['sea'] is num ? (mp['sea'] as num).toInt() : 0;
              final bool fwDone = sd && mp['fwDone'] == true;
              final bool seaDone = sd && mp['seaDone'] == true;
              // 서윤(보배)
              final bp = d['bobae_progress'];
              final sdb = bp is Map && bp['date'] == today;
              final int bC = sdb && bp['caught'] is num ? (bp['caught'] as num).toInt() : 0;
              final bool bClaimed = sdb && bp['claimed'] == true;
              // 승급
              final rank = (d['rank'] ?? '초보').toString();
              final tier = nextPromotion(rank);
              final int lvl = calcLevelFromExp((d['exp'] is num) ? (d['exp'] as num).toInt() : 0);
              final dc = <String, int>{};
              if (d['daejangCatch'] is Map) {
                (d['daejangCatch'] as Map).forEach((k, v) { dc[k.toString()] = (v is num) ? v.toInt() : 0; });
              }
              final int bobaeTarget = bobaeM['count'] as int;

              return Column(mainAxisSize: MainAxisSize.min, children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 8, 6),
                  child: Row(children: [
                    const Icon(Icons.assignment_turned_in, color: Color(0xFFD4AF37), size: 22),
                    const SizedBox(width: 8),
                    const Text('진행 중인 퀘스트', style: TextStyle(color: Color(0xFFD4AF37), fontSize: 18, fontWeight: FontWeight.w900)),
                    const Spacer(),
                    IconButton(onPressed: () => Navigator.pop(dctx), icon: const Icon(Icons.close, color: Colors.white54)),
                  ]),
                ),
                const Divider(color: Colors.white12, height: 1),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
                    child: Column(children: [
                      // 📋 일일 퀘스트
                      section('📋 일일 퀘스트  ·  아라', [
                        qRow('🏞️ 민물 — ${fwM['fish']} 잡기', fwP, fwM['count'] as int, fwDone),
                        fwDone
                            ? qRow('🌊 바다 — ${seaM['fish']} 잡기', seaP, seaM['count'] as int, seaDone)
                            : note('🌊 바다 — 민물 완료 후 열려요 🔒'),
                        note('완료하면 아라에게 각 ${dailyMissionPrize}P!'),
                      ]),
                      // 🐟 서윤 의뢰
                      section('🐟 서윤 의뢰', [
                        bClaimed
                            ? note('오늘 의뢰 완료 · 정산까지 끝났어요! ✅', color: const Color(0xFF7FFFB0))
                            : qRow('${bobaeM['fish']} $bobaeTarget마리 잡기', bC, bobaeTarget, bC >= bobaeTarget),
                        if (!bClaimed && bC >= bobaeTarget) note('광장의 서윤에게 가서 정산받으세요!', color: const Color(0xFF7FFFB0)),
                      ]),
                      // 🎖️ 승급 퀘스트
                      section('🎖️ 승급 퀘스트  ·  아라', tier == null
                          ? [note('현재 최고 칭호예요! (레전드·낚시의 신 준비 중) 🏆', color: const Color(0xFF7FFFB0))]
                          : (lvl < (tier['level'] as int)
                              ? [note('Lv.${tier['level']} 도달 시 [${tier['rank']}] 승급 퀘스트가 열려요.\n(현재 Lv.$lvl)')]
                              : [
                                  note('6대장을 각 ${tier['need']}마리씩! (달성 후 아라에게 승급)'),
                                  const SizedBox(height: 6),
                                  Wrap(spacing: 8, runSpacing: 8, children: daejangFish.map((f) {
                                    final cur = dc[f] ?? 0;
                                    final need = tier['need'] as int;
                                    final ok = cur >= need;
                                    return Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: ok ? const Color(0x224CAF50) : Colors.white10,
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: ok ? const Color(0xFF7FFFB0) : Colors.white24),
                                      ),
                                      child: Text('$f ${cur > need ? need : cur}/$need${ok ? " ✅" : ""}',
                                          style: TextStyle(color: ok ? const Color(0xFF7FFFB0) : Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                                    );
                                  }).toList()),
                                ])),
                      const SizedBox(height: 4),
                    ]),
                  ),
                ),
              ]);
            },
          ),
        ),
      ),
    );
  }

  // ⚔️ 시스템/브라우저 뒤로가기(WillPopScope) — 아레나 경기 중이면 확인 후에만 나가기
  Future<bool> _onWillPopFishing() async {
    if (widget.roomId != null && !_arenaEndedNaturally) {
      return _confirmArenaLeave();
    }
    return true;
  }

  // ⚔️ 아레나 경기 도중 나가기 확인
  //    · 다른 참가자가 남아있으면 → 기권패 경고(참가비 환불 안 됨). 나가도 남은 사람들은 끝까지 진행.
  //    · 나 빼고 다 나갔으면(마지막 1인) → 기권승 안내 후 정산(전액-수수료 10%).
  Future<bool> _confirmArenaLeave() async {
    final rid = widget.roomId;
    if (rid == null || _arenaEndedNaturally) return true;

    final uid = FirebaseAuth.instance.currentUser?.uid;
    int total = 0;
    int activeOthers = 0;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('arenas').doc(rid).collection('participants').get();
      total = snap.docs.length;
      activeOthers = snap.docs
          .where((d) => d.id != uid && (d.data()['forfeit'] != true))
          .length;
    } catch (_) {}

    if (!mounted) return false;

    // 처음부터 혼자였던 방 → 페널티 없이 그냥 나가기(정산이 참가비 환불 처리)
    if (total < 2) return true;

    // 🏳️ 나 빼고 아무도 안 남음 → 기권승
    if (activeOthers == 0) {
      final ok = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (c) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A1A),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: const BorderSide(color: Color(0xFFD4AF37), width: 1.2)),
          title: const Text('🏳️ 상대가 모두 나갔어요!',
              style: TextStyle(color: Color(0xFFD4AF37), fontWeight: FontWeight.bold, fontSize: 17)),
          content: const Text('남은 참가자가 나뿐이에요.\n지금 종료하면 기권승으로 정산돼요! (수수료 10% 제외)',
              style: TextStyle(color: Colors.white70, fontSize: 15, height: 1.5)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false),
                child: const Text('계속하기', style: TextStyle(color: Colors.white54))),
            ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFD4AF37), foregroundColor: Colors.black),
                onPressed: () => Navigator.pop(c, true),
                child: const Text('종료하고 정산', style: TextStyle(fontWeight: FontWeight.bold))),
          ],
        ),
      );
      if (ok == true) { _arenaWalkoverWin = true; return true; }
      return false;
    }

    // ⚠️ 다른 참가자가 아직 남아있음 → 기권패 경고
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: const BorderSide(color: Colors.redAccent, width: 1.2)),
        title: const Text('⚠️ 경기 도중 나가기',
            style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 17)),
        content: const Text('경기 도중 나가면 참가비를 돌려받을 수 없어요.\n이기고 있어도 기권패로 처리됩니다.\n\n정말 나가시겠어요?',
            style: TextStyle(color: Colors.white70, fontSize: 15, height: 1.5)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false),
              child: const Text('계속 낚시', style: TextStyle(color: Colors.white54))),
          ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(c, true),
              child: const Text('기권하고 나가기', style: TextStyle(fontWeight: FontWeight.bold))),
        ],
      ),
    );
    return ok == true;
  }

  // 🗺️ 낚시터 리스트(뒤로가기·낚시터 이동에서 호출)
  //    다른 낚시터 탭 → 바로 이동(광장의 _goFishing이 처리) / '광장으로 가기' → 광장 복귀
  void _openMoveSpotList() {
    // 아레나(대회)에서는 이동 불가 → 그냥 나가기
    if (widget.roomId != null) { Navigator.pop(context); return; }
    String subCat = widget.isSea ? '갯바위' : '저수지';
    showDialog(
      context: context,
      builder: (dctx) => Dialog(
        backgroundColor: const Color(0xFF161616),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0xFFD4AF37), width: 1.2)),
        child: SizedBox(
          width: 720,
          height: 560,
          child: StatefulBuilder(builder: (dctx, setD) {
            final bool isMainSea = (subCat == '갯바위' || subCat == '선상');
            final spots = List<Map<String, dynamic>>.from(locations[subCat] ?? []);
            Widget tab(String label, bool active, VoidCallback onTap) {
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 4),
                  child: GestureDetector(
                    onTap: onTap,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      decoration: BoxDecoration(
                        color: active ? const Color(0xFFD4AF37) : Colors.grey.shade800,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: active ? const Color(0xFFD4AF37) : Colors.white24),
                      ),
                      child: Text(label,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: active ? Colors.black : Colors.white70,
                              fontSize: 14,
                              fontWeight: FontWeight.w900)),
                    ),
                  ),
                ),
              );
            }

            return Column(children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 6),
                child: Text('🗺️  낚시터 이동',
                    style: TextStyle(color: Color(0xFFD4AF37), fontSize: 20, fontWeight: FontWeight.w900)),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(children: [
                  tab('저수지', subCat == '저수지', () => setD(() => subCat = '저수지')),
                  tab('수로', subCat == '수로', () => setD(() => subCat = '수로')),
                  tab('갯바위', subCat == '갯바위', () => setD(() => subCat = '갯바위')),
                  tab('선상', subCat == '선상', () => setD(() => subCat = '선상')),
                ]),
              ),
              const Divider(color: Colors.white12, height: 12),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: spots.length,
                  itemBuilder: (c, i) {
                    final s = spots[i];
                    final isHere = s['name'] == widget.locationName;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: isHere ? const Color(0x22D4AF37) : Colors.grey.shade900,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: isHere ? const Color(0xFFD4AF37) : Colors.white10,
                            width: isHere ? 1.5 : 1),
                      ),
                      child: ListTile(
                        leading: Text(isMainSea ? '🌊' : '🏞️', style: const TextStyle(fontSize: 22)),
                        title: Row(children: [
                          Flexible(
                            child: Text(s['name'],
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16.5)),
                          ),
                          const SizedBox(width: 8),
                          ...List.generate(
                              5,
                              (k) => Icon(k < ((s['stars'] ?? 0) as int) ? Icons.star : Icons.star_border,
                                  color: const Color(0xFFD4AF37), size: 13)),
                        ]),
                        subtitle: (s['target'] ?? '').toString().isNotEmpty
                            ? Padding(
                                padding: const EdgeInsets.only(top: 5),
                                child: Text('💡 ${s['target']}',
                                    style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.3, fontWeight: FontWeight.w500)),
                              )
                            : null,
                        trailing: isHere
                            ? const Text('🎣 여기', style: TextStyle(color: Color(0xFFD4AF37), fontWeight: FontWeight.bold))
                            : const Icon(Icons.arrow_forward_ios, color: Colors.white38, size: 16),
                        onTap: () {
                          audioManager.playSfx('sfx_click.mp3');
                          if (isHere) { Navigator.pop(dctx); return; } // 현재 낚시터면 닫기만
                          Navigator.pop(dctx); // 리스트 닫고
                          Navigator.pop(context, {'hopTo': s, 'sea': isMainSea}); // 낚시 화면 나가며 이동 요청
                        },
                      ),
                    );
                  },
                ),
              ),
              const Divider(color: Colors.white12, height: 1),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(children: [
                  TextButton(
                      onPressed: () => Navigator.pop(dctx),
                      child: const Text('취소', style: TextStyle(color: Colors.white54))),
                  const Spacer(),
                  ElevatedButton.icon(
                    onPressed: () {
                      audioManager.playSfx('sfx_click.mp3');
                      Navigator.pop(dctx); // 리스트 닫고
                      // 🏛️ 낚시 종류에 맞는 광장으로 (바다낚시→바다광장 / 민물낚시→민물광장)
                      Navigator.pop(context, {'toPlaza': widget.isSea ? 'sea' : 'fresh'});
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2E7D32),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: Text(widget.isSea ? '🌊' : '🏞️', style: const TextStyle(fontSize: 16)),
                    label: Text(widget.isSea ? '바다광장으로' : '민물광장으로', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
                  ),
                ]),
              ),
            ]);
          }),
        ),
      ),
    );
  }

  // 🦐 1분마다 민물새우 +2 적립
  Future<void> _collectShrimp() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final ref = FirebaseFirestore.instance.collection('users').doc(user.uid);
      final snap = await ref.get();
      List<dynamic> inv = List.from(snap.data()?['inventory'] ?? []);
      final idx = inv.indexWhere((i) => (i['name'] ?? '') == '민물새우');
      if (idx >= 0) {
        final int cur = (inv[idx]['quantity'] is num) ? (inv[idx]['quantity'] as num).toInt() : 0;
        if (cur >= 50) return; // 🦐 최대 50개 — 가득 차면 더 안 모음(조용히 스킵, 스팸 방지)
        final int next = (cur + 2) > 50 ? 50 : (cur + 2);
        inv[idx]['quantity'] = next;
        if (next >= 50 && mounted) _baitToast('🦐 민물새우가 가득 찼어요! (50/50)\n채집망을 건지거나 미끼로 써주세요', const Color(0xFFD4AF37));
      } else {
        inv.add({'name': '민물새우', 'category': 'FW', 'type': 'BAIT', 'quantity': 2, 'icon': 'bait_fw_shrimp.png', 'desc': '채집망으로 잡은 신선한 생새우 미끼 (집어력 25, 베스·메기·가물치 등 육식·대물에 강함)'});
      }
      await ref.update({'inventory': inv});
    } catch (e) { debugPrint('🦐 새우 적립 실패: $e'); }
  }

  // 👇 여기에 추가
int _getLocationStars() {
  int stars = 1;
  locations.forEach((category, locList) {
    for (var loc in locList) {
      if (loc['name'] == widget.locationName) {
        stars = loc['stars'] ?? 1;
      }
    }
  });
  return stars;
}

void _recast() {  // 기존 코드
    audioManager.ensureRainPlaying(); // 🌧️ 낚시터에서도 조작 시 빗소리 열기(자동재생 우회)
    if (!mounted || remainingTimeNotifier.value <= 0) return;
    if (isSettingUp) return; // 🔒 셋팅 중엔 아예 실행 안 함!
    // 🪱 미끼 없으면 캐스팅 불가
    if (equippedBait == null) {
      _showNotificationPopup('🪱 미끼가 없어요!', '미끼를 장착해야 낚시를 할 수 있어요.\n가방에서 장착하거나 상점에서 구매하세요!', Colors.orangeAccent);
      return;
    }
    // (미끼 소모는 _startFight에서 입질마다 처리 — #2)

    // 👩‍💼 [신규 3단계] 캐스팅 시 가람이 출근 조건 체크!
    final now = DateTime.now();
    
    // 🚦 [교통정리] 튜토리얼 중(윤슬이가 떠들 때)에는 가람이 출근 방지!
    // (🚨 만약 여기서 빨간 줄이 뜨면 widget.isTutorial 대신 사장님이 쓰시는 튜토리얼 변수명으로 싹 바꿔주시면 됩니다!)
    if (widget.isFirstTime == false && !isSettingUp && isFloatInWater) {
  if (_lastGaramTime == null || now.difference(_lastGaramTime!).inMinutes >= 10) {
    if (!gmNoticeVisible && mounted) {
    _lastGaramTime = now; // 🔒 등장 전에 먼저 시간 기록 (중복 방지!)
    setState(() {
      gmNoticeVisible = true;
    });
     
          Future.delayed(const Duration(seconds: 20), () {
            if (mounted) {
              setState(() {
                gmNoticeVisible = false; // 가람이 퇴근!
              });
            }
          });
        }
      }
    } // 👈 🚦 [교통정리 끝] 윤슬이 보호막 괄호 완벽하게 닫힘! (참사 방어 완료)

    // 1. 일단 화면에 낚싯대를 짠! 하고 등장시킵니다.
    setState(() { 
      isCasting = true; 
      isFighting = false; 
      bitingRods.clear(); 
      fightingRodIndex = null; // 🚨 [버그 픽스] 실패 후 재캐스팅 시 사투 기록 완벽 리셋!
    });
    audioManager.playSfx("sfx_casting.mp3"); 
    
    // 🚨 2. [핵심 패치] 낚싯대가 무대에 올라올 시간 0.05초(50ms)를 주고 던집니다!
    Future.delayed(const Duration(milliseconds: 50), () {
      _castController.reset(); // 혹시 몰라 0으로 확실히 되감기!
      _castController.forward(); // 시원하게 캐스팅 휙~!
    });

    // 3. 1.5초 뒤에 찌가 물에 안착하는 로직 (기존과 동일)
    Future.delayed(const Duration(milliseconds: 1500), () { if (mounted) { setState(() { isCasting = false; isFloatInWater = true; if (widget.isFirstTime && !_isTutorialDone) _fishingStep = 4; if (widget.isFirstTime && !_isTutorialDone) _fishingStep = 4; }); _startBiteTimer(); } });
  }

  Color _getBiteColor(Color color) {
    if (color == Colors.green) return Colors.redAccent; 
    if (color == Colors.red) return Colors.greenAccent; 
    if (color == Colors.blue) return Colors.orangeAccent; 
    if (color == Colors.yellow) return Colors.purpleAccent; 
    return Colors.white;
  }

  String? _getIconImagePath(Map<String, dynamic>? item) {
    if (item == null || item['icon'] == null) return 'assets/items/rod_fw_basic_icon.png';
    String iconName = item['icon'].toString();
    // 🐟 물고기 수집 이미지: 어떤 폴더로 저장됐든 실제 위치로 보정
    final file = iconName.split('/').last;
    if (file.startsWith('fish_fw')) return 'assets/fish_fw/$file';
    if (file.startsWith('fish_sea')) return 'assets/fish_sea/$file';
    if (iconName.contains('assets/')) return iconName.replaceAll('../', 'assets/');
    if (iconName.contains('.jpg') || iconName.contains('skin_')) return 'assets/images/$iconName';
    return 'assets/items/$iconName';
  }

  // 🏢 UI - Main: 화면 뼈대 그리기
  Widget _buildRodOverlay(Map<String, dynamic>? rodItem) {
    String equipRodFileName = '';
    if (rodItem != null) {
      String rawName = rodItem['name'].toString().replaceAll(' ', '').replaceAll('-', '').replaceAll('_', '').toUpperCase();
      if (rawName == 'CF20T') equipRodFileName = 'rod_fw_cf20_equip.png';
      else if (rawName == 'CF30T') equipRodFileName = 'rod_fw_cf30_equip.png';
      else if (rawName == 'CF40T') equipRodFileName = 'rod_fw_cf40_equip.png';
      else if (rawName == 'KT20T') equipRodFileName = 'rod_fw_kt20_equip.png';
      else if (rawName == 'KT30T') equipRodFileName = 'rod_fw_kt30_equip.png';
      else if (rawName == 'KT40T') equipRodFileName = 'rod_fw_kt40_equip.png';

      else if (rawName.contains('KT') && rawName.contains('500')) equipRodFileName = 'rod_sea_kt500_equip.png';
      else if (rawName.contains('KT') && rawName.contains('350')) equipRodFileName = 'rod_sea_kt350_equip.png';
      else if (rawName.contains('KT') && rawName.contains('250')) equipRodFileName = 'rod_sea_kt250_equip.png';
      else if (rawName.contains('CF') && rawName.contains('500')) equipRodFileName = 'rod_sea_cf500_equip.png';
      else if (rawName.contains('CF') && rawName.contains('350')) equipRodFileName = 'rod_sea_cf350_equip.png';
      else if (rawName.contains('CF') && rawName.contains('250')) equipRodFileName = 'rod_sea_cf250_equip.png';

      if (equipRodFileName.isEmpty) return const SizedBox.shrink();
    }

    return Positioned.fill(
      child: Stack(
        children: [
          Builder(
            builder: (c) {
              String currentCharacterImg = 'assets/images/char_beginner.png';
              if (equippedSkin != null) {
                currentCharacterImg = FishingLogic.getLobbyCharacterImage(equippedSkin!['name'].toString());
              }    
              return Image.asset(currentCharacterImg, height: 400, fit: BoxFit.contain, errorBuilder: (c,e,s)=>const SizedBox.shrink());
            }
          ),
          _buildItemOverlay('assets/items/sunglasses_overlay.png', bottom: 250, left: 160, width: 80),
          _buildItemOverlay('assets/items/badge_fw_overlay.png', bottom: 200, left: 130, width: 50),
          _buildItemOverlay('assets/items/badge_sea_overlay.png', bottom: 200, left: 220, width: 50),
          if (equipRodFileName.isNotEmpty)
            _buildItemOverlay('assets/items/$equipRodFileName', bottom: 0, left: 10, width: 300),
          if (equippedReel != null || equippedBait != null) 
            _buildItemOverlay('assets/items/reel_sea_kf8000.png', bottom: 230, left: 140, width: 40),
        ],
      ),
    );
  }

  Widget _buildItemOverlay(String path, {required double bottom, required double left, double? width}) {
    return Positioned(
      bottom: bottom, 
      left: left,
      child: Image.asset(path, width: width, fit: BoxFit.contain, errorBuilder: (c, e, s) => const SizedBox.shrink()),
    );
  }

  @override
  Widget build(BuildContext context) {
    String currentCharacterImg = 'assets/images/char_beginner.png';
    if (equippedSkin != null) {
      currentCharacterImg = FishingLogic.getLobbyCharacterImage(equippedSkin!['name'].toString());
    } 
    
    // 🚀 1. 가장 바깥에 투명 필름(Stack)을 먼저 깝니다!
    //    ⚔️ 아레나 경기 중 시스템/브라우저 뒤로가기도 확인 팝업 거치게 WillPopScope로 감쌈
    return WillPopScope(
      onWillPop: _onWillPopFishing,
      child: Stack(
      children: [
        // ==========================================================
        // 1. 사장님의 기존 본게임 화면
        // ==========================================================
        Scaffold( // 👈 원래 있던 return Scaffold 에서 'return'만 빼고 살려둡니다!
          resizeToAvoidBottomInset: false, // 🛡️ 키보드 배경 찌그러짐 방지!
          body: Stack(
        children: [
          Positioned.fill(child: Transform.scale(scaleX: widget.isSea ? -1 : 1, child: Image.asset(widget.bgImagePath, fit: BoxFit.cover, errorBuilder: (c, e, s) => Container(color: Colors.grey.shade900, child: const Center(child: Icon(Icons.broken_image, color: Colors.white24, size: 100)))))), 
          Positioned.fill(child: Container(color: const Color(0x3A000000))),
          // (🦅 갈매기 등 자연 효과는 HUD 버튼에 안 가리도록 바깥 Stack 상단으로 이동 — Scaffold 밖)
          // 🌧️ 실시간 날씨 오버레이(비/눈) — 실제 그 지역에 비 오면 게임에도 비
          Positioned.fill(child: IgnorePointer(child: WeatherOverlay(isSea: widget.isSea))),
          // 🌦️ 날씨 뱃지(지역·기온) — 타이머 바로 아래에 딱 붙임
          const Positioned(top: 78, left: 0, right: 0, child: IgnorePointer(child: Center(child: WeatherBadge()))),
          // 🎉 이벤트 배너 (활성 이벤트일 때만) — 날씨뱃지 아래
          if (currentGameEvent.active && currentGameEvent.name.isNotEmpty)
            Positioned(top: 112, left: 0, right: 0, child: IgnorePointer(child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFFD4AF37).withOpacity(0.92),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 6)],
                ),
                child: Text(currentGameEvent.name, style: const TextStyle(color: Colors.black, fontSize: 13, fontWeight: FontWeight.w900)),
              ),
            ))),
          if (isCasting) _buildCastingScene(),
          if (isSettingUp)
            Positioned(
              top: 100, bottom: 30, left: -50, right: 30,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center, mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    flex: 3,
                    child: Stack(
                      alignment: Alignment.bottomLeft, 
                      children: [
                        Transform.scale(
                          scale: 1.20, alignment: Alignment.bottomLeft,
                          child: Image.asset(currentCharacterImg, fit: BoxFit.contain, errorBuilder: (c, e, s) => const SizedBox.shrink()),
                        ),
                        if (equippedSunglasses != null)
                          Positioned(bottom: 351, left:222, child: Image.asset('assets/items/${equippedSunglasses!['icon'] ?? 'item_sunglasses.png'}', width: 36, errorBuilder: (c,e,s)=>const SizedBox.shrink())),
                        if (equippedBadge != null)
                          Positioned(bottom: 290, left: 250, child: Image.asset(equippedBadge!['name'].toString().contains('민물') ? 'assets/items/item_badge_fw.png' : 'assets/items/item_badge_sea.png', width: 28, errorBuilder: (c,e,s)=>const SizedBox.shrink())),
                        if (equippedRod != null)
                          Transform.translate(
                            offset: const Offset(76.0, -255.0), 
                            child: Transform.scale(
                              scale: 0.45, alignment: Alignment.bottomLeft,
                              child: Builder(
                                builder: (context) {
                                  String rName = equippedRod!['name'].toString().toUpperCase();
                                  String rFile = ''; 
                                  if (rName.contains('KT') && rName.contains('500')) rFile = 'rod_sea_kt500_equip.png';
                                  else if (rName.contains('KT') && rName.contains('350')) rFile = 'rod_sea_kt350_equip.png';
                                  else if (rName.contains('KT') && rName.contains('250')) rFile = 'rod_sea_kt250_equip.png';
                                  else if (rName.contains('CF') && rName.contains('500')) rFile = 'rod_sea_cf500_equip.png';
                                  else if (rName.contains('CF') && rName.contains('350')) rFile = 'rod_sea_cf350_equip.png';
                                  else if (rName.contains('CF') && rName.contains('250')) rFile = 'rod_sea_cf250_equip.png';
                                  else if (rName.contains('KT') && rName.contains('40')) rFile = 'rod_fw_kt40_equip.png';
                                  else if (rName.contains('KT') && rName.contains('30')) rFile = 'rod_fw_kt30_equip.png';
                                  else if (rName.contains('KT') && rName.contains('20')) rFile = 'rod_fw_kt20_equip.png';
                                  else if (rName.contains('CF') && rName.contains('40')) rFile = 'rod_fw_cf40_equip.png';
                                  else if (rName.contains('CF') && rName.contains('30')) rFile = 'rod_fw_cf30_equip.png';
                                  else if (rName.contains('CF') && rName.contains('20')) rFile = 'rod_fw_cf20_equip.png';

                                  if (rFile.isEmpty) return const SizedBox.shrink();
                                  return Image.asset('assets/items/$rFile', fit: BoxFit.contain, errorBuilder: (c,e,s) => Container(color: Colors.red, child: Text('파일없음:\n$rFile', style: const TextStyle(color: Colors.white, fontSize: 10))));
                                }
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  _buildSetupOverlay(), const SizedBox(width: 20), buildInventoryPanel(context),
                ],
              ),
            ),

              if (gmNoticeVisible) GMNoticePopup(
                message: _garamMessages[math.Random().nextInt(_garamMessages.length)],
               onClose: () {
                 setState(() {
              gmNoticeVisible = false;
             });
            },
          ),

            if (!isSettingUp) ...[
            if (!widget.isSea || (!isCasting && !isFighting)) _buildFieldRods(),
            if (isCasting) _buildCastingScene(), // 👈 파이팅 장면 중복 렌더링 방지 (오버레이가 알아서 함)
            if (widget.isSea && isFloatInWater && bitingRods.isNotEmpty) Positioned.fill(child: Center(child: const Text("입질 !!", style: TextStyle(color: Colors.redAccent, fontSize: 120, fontWeight: FontWeight.w900, fontStyle: FontStyle.italic, shadows: [Shadow(color: Colors.black, blurRadius: 20, offset: Offset(5, 5))])))),
            if (isFloatInWater) Positioned(bottom: 40, right: 40, child: _buildMainActionButton()), // 👈 메인 버튼 중복 렌더링 방지
          ],

          // 🎒 [신규] 낚시 중 미끼교체 + 인벤토리 버튼 (세로 배치)
Positioned(
  top: 120, // 💡 상단바·채팅창 피한 위치
  right: 55,
  child: Row(mainAxisSize: MainAxisSize.min, children: [
    GestureDetector(
      onTap: _showFullInventoryDialog,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.amber, width: 2)),
        child: const Column(children: [
          Icon(Icons.backpack, color: Colors.amber, size: 28),
          SizedBox(height: 4),
          Text('인벤토리', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
        ]),
      ),
    ),
    const SizedBox(width: 10),
    GestureDetector(
      onTap: () { audioManager.playSfx("sfx_click.mp3"); _showFishingInventoryPopup(); },
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.amber, width: 2)),
        child: const Column(children: [
          Icon(Icons.bug_report, color: Colors.amber, size: 28),
          SizedBox(height: 4),
          Text('미끼교체', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
        ]),
      ),
    ),
  ]),
),
          
          Positioned(
            top: 40, left: 50, right: 15,
            child: SafeArea(
              child: StreamBuilder<DocumentSnapshot>(
                stream: FirebaseFirestore.instance.collection('users').doc(FirebaseAuth.instance.currentUser!.uid).snapshots(),
                builder: (context, snapshot) {
                  int realExp = 0; int realGold = 0; String realRank = '초보'; String realNickname = widget.nickname;

                  if (snapshot.hasData && snapshot.data!.exists) {
                    var userData = snapshot.data!.data() as Map<String, dynamic>;
                    realExp = userData['exp'] ?? 0; realGold = userData['gold'] ?? 0;
                    realRank = userData['rank'] ?? '초보'; realNickname = userData['nickname'] ?? widget.nickname;
                    _myRank = realRank; // 🎖️ 승급 자격 레벨 판정용 캐시
                    _myTutStep = (userData['tutStep'] as num?)?.toInt() ?? 99; // 🎓 튜토리얼 단계 캐시
                    _latestInventory = userData['inventory'] ?? []; // 🦐 채집망 보유 체크용 최신 인벤
                  }

    // 🆙 경험치→레벨. 칭호(realRank)는 저장된 승급 결과(rank 필드)를 그대로 사용 — #13 승급퀘스트 개편
    int realLevel = calcLevelFromExp(realExp);
    int prevLevelExp = globalExpTable[realLevel];
    int nextLevelExp = realLevel < globalMaxLevel ? globalExpTable[realLevel + 1] : globalExpTable[globalMaxLevel];

    // 🛡️ [수정] 가짜 데이터(0.1초)일 때는 무시하고, 진짜 DB 데이터가 도착했을 때만 레벨업 판독!
    if (snapshot.hasData && snapshot.data!.exists) {
      if (_currentLevel == 0) { 
        _currentLevel = realLevel; // 처음 입장 시 팝업 띄우지 말고 조용히 현재 레벨만 기억!
      } else if (realLevel > _currentLevel) {
        _currentLevel = realLevel; // 찐으로 고기 잡아서 렙업했을 때만 팝업 발사!
        Future.delayed(const Duration(milliseconds: 600), () { if (mounted) _showLevelUpPopup(realLevel); });
        // (승급은 레벨업 자동이 아니라 광장 아라의 '승급 퀘스트'로만 — #13 개편)
        // 🛡️ #1: 레벨업 즉시 길드원 목록의 내 레벨 갱신
        if (_guildId.isNotEmpty) {
          final u = FirebaseAuth.instance.currentUser;
          if (u != null) {
            FirebaseFirestore.instance.collection('guilds').doc(_guildId)
                .collection('members').doc(u.uid)
                .set({'level': realLevel, 'nickname': widget.nickname}, SetOptions(merge: true))
                .catchError((Object e) => debugPrint('🛡️ 길드원 레벨 갱신 실패: $e'));
          }
        }
      }
    }
                  
                  // 🏆 아레나는 완전 평준화 → 레벨 보너스 0으로 표시(실제 제압력과 일치)
                  int levelEach = (widget.title != widget.locationName) ? 0 : realLevel - 1; // 🆙 레벨업마다 힘·컨트롤·감도 각 +1 (제압력 +3)
                  Map<String, int> currentStats = getMyTotalStats();
                  int equipP = (currentStats['strength'] ?? 0) + levelEach;
                  int equipC = (currentStats['control'] ?? 0) + levelEach;
                  int equipS = (currentStats['sensitivity'] ?? 0) + levelEach;
                  int myTotalPower = equipP + equipC + equipS;
                  double expPercent = (realLevel < globalMaxLevel) ? (realExp - prevLevelExp) / (nextLevelExp - prevLevelExp) : 1.0;
                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              IconButton(padding: EdgeInsets.zero, constraints: const BoxConstraints(), icon: const Icon(Icons.arrow_back_ios, color: Colors.white, size: 22), onPressed: () async { audioManager.playSfx("sfx_click.mp3"); if (widget.roomId != null) { if (await _confirmArenaLeave() && mounted) { Navigator.pop(context); } } else { _openMoveSpotList(); } }),
                              const SizedBox(width: 5),
                              Text(widget.title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white, shadows: [Shadow(color: Colors.black, blurRadius: 2)])),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Padding(
                            padding: const EdgeInsets.only(left: 5),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFFD4AF37), width: 1)),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text('Lv.$realLevel', style: const TextStyle(color: Colors.yellowAccent, fontSize: 13, fontWeight: FontWeight.bold)),
                                  const SizedBox(width: 8),
                                  Text('제압력: $myTotalPower', style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                                  Text(' (💪$equipP  🎯$equipC  📡$equipS)', style: const TextStyle(color: Colors.white, fontSize: 13)),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Container(
                            width: 180, height: 12, 
                            decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.white24, width: 0.5)),
                            child: FractionallySizedBox(alignment: Alignment.centerLeft, widthFactor: expPercent.clamp(0.0, 1.0), child: Container(decoration: BoxDecoration(color: const Color(0xFFD4AF37), borderRadius: BorderRadius.circular(4)))),
                          ),
                          const SizedBox(height: 4),
                          Text('$realExp / $nextLevelExp EXP', style: const TextStyle(color: Colors.white, fontSize: 14)),
                          const SizedBox(height: 10),
                          Text('point $realGold', style: const TextStyle(color: Colors.cyanAccent, fontSize: 16, fontWeight: FontWeight.bold)),
                          // 🛡️ #3 길드 경험치 실시간 진행바 (길드원이 잡으면 바로 차오름)
                          if (_guildId.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: StreamBuilder<DocumentSnapshot>(
                                stream: FirebaseFirestore.instance.collection('guilds').doc(_guildId).snapshots(),
                                builder: (c, snap) {
                                  final gexp = (snap.data?.data() as Map<String, dynamic>?)?['guildExp'];
                                  final ge = (gexp is num) ? gexp.toInt() : 0;
                                  final glv = FishingLogic.guildLevelFromExp(ge);
                                  final tbl = FishingLogic.guildExpTable;
                                  final curBase = (glv < tbl.length) ? tbl[glv] : 0;
                                  final maxed = (glv + 1) >= tbl.length;
                                  final nextBase = maxed ? curBase : tbl[glv + 1];
                                  final span = nextBase - curBase;
                                  final prog = (span > 0) ? ((ge - curBase) / span).clamp(0.0, 1.0) : 1.0;
                                  return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Row(children: [
                                      const Icon(Icons.groups, color: Color(0xFF7FFFB0), size: 13),
                                      const SizedBox(width: 4),
                                      Text('길드 Lv.$glv', style: const TextStyle(color: Color(0xFF7FFFB0), fontSize: 12, fontWeight: FontWeight.bold)),
                                      const SizedBox(width: 6),
                                      Text(maxed ? 'MAX' : '$ge / $nextBase', style: const TextStyle(color: Colors.white54, fontSize: 11)),
                                    ]),
                                    const SizedBox(height: 3),
                                    Container(
                                      width: 180, height: 8,
                                      decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(5), border: Border.all(color: Colors.white24, width: 0.5)),
                                      child: FractionallySizedBox(alignment: Alignment.centerLeft, widthFactor: prog.toDouble(), child: Container(decoration: BoxDecoration(color: const Color(0xFF7FFFB0), borderRadius: BorderRadius.circular(4)))),
                                    ),
                                  ]);
                                },
                              ),
                            ),
                        ],
                      ),

                       Positioned(
                        right: 30, top: 0,
                        child: Row( 
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            // 🚀 [신규] 닉네임 바 왼쪽에 자리 잡을 황금 버튼 2인방!
              _buildTopMiniButton(
                icon: audioManager.isMuted ? Icons.volume_off : Icons.volume_up,
                onPressed: () {
                  setState(() {
                    audioManager.toggleMute();
                  });
                },
              ),
              const SizedBox(width: 8),
              
              _buildTopMiniButton(
                icon: Icons.fullscreen,
                onPressed: toggleFullScreen,
              ),
              const SizedBox(width: 8),
              // 🛡️ 길드 정보 보기 (방패 아이콘 — 광장 윤슬 방패 조형물과 통일)
              _buildTopMiniButton(
                icon: Icons.shield,
                onPressed: () => showGuildInfoDialog(context),
              ),
              // 📜 퀘스트 진행현황 (두루마리 아이콘 — 광장 아라 퀘스트 용지와 통일 · 일반 낚시터에서만)
              if (widget.roomId == null) ...[
                const SizedBox(width: 8),
                _buildTopMiniButton(
                  icon: Icons.receipt_long,
                  onPressed: () { audioManager.playSfx("sfx_click.mp3"); _showQuestPopup(); },
                ),
              ],
              // 🦐 새우 채집망 던지기/건지기 (민물 전용 · 보유 시에만 표시)
              if (_hasShrimpTrap() && !widget.isSea) ...[
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _toggleShrimpTrap,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: _trapDeployed ? const Color(0xCC1B5E20) : Colors.black87,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFFD4AF37), width: 1),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Text('🦐', style: TextStyle(fontSize: 14)),
                      const SizedBox(width: 6),
                      Text(_trapDeployed ? '건지기' : '채집망', style: const TextStyle(color: Color(0xFFD4AF37), fontSize: 13, fontWeight: FontWeight.bold)),
                    ]),
                  ),
                ),
              ],
              const SizedBox(width: 20), // 황금 버튼들과 닉네임 바 사이의 넉넉한 간격!

              // 👇 (기존의 1429번 줄 Container 시작 부분이 이 아래로 오면 됩니다!)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                              decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFFD4AF37), width: 1)),
                              child: Row(children: [Text(realRank, style: const TextStyle(color: Color(0xFFD4AF37), fontSize: 13, fontWeight: FontWeight.bold)), const SizedBox(width: 8), Text('$realNickname 조사님', style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold))]),
                            ),
                            
                          ],
                        ),
                      ),
                      
                      Positioned(
                        top: 0, left: 0, right: 0,
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                            decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(15), border: Border.all(color: const Color(0xFFD4AF37).withOpacity(0.5), width: 1), boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 4, offset: Offset(0, 2))]),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.timer_outlined, color: Color(0xFFD4AF37), size: 16),
                                const SizedBox(width: 6),
                                // 👇 1154번 줄부터 1159번 줄까지 덮어쓰기!
                      (widget.title != widget.locationName)
                        // 🏆 아레나 모드: 10분 카운트다운 (긴장감 넘치게 빨간색!)
                        ? Text('${(arenaTimeLeft ~/ 60).toString().padLeft(2, '0')}:${(arenaTimeLeft % 60).toString().padLeft(2, '0')}', 
                            style: const TextStyle(color: Colors.redAccent, fontSize: 18, fontWeight: FontWeight.bold, fontFamily: 'monospace'))
                        // 🏞️ 일반 모드: 사장님 원래 로직 (60분 타이머)
                        : ValueListenableBuilder<int>(
                            valueListenable: remainingTimeNotifier,
                            builder: (context, timeValue, child) {
                              return Text('${(timeValue ~/ 60).toString().padLeft(2, '0')}:${(timeValue % 60).toString().padLeft(2, '0')}', 
                                  style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold, fontFamily: 'monospace'));
                            },
                          ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                }
              ),
            ),
          ),
          if (!isSettingUp) 
            Positioned(
              bottom: 20 + MediaQuery.of(context).viewInsets.bottom,
              left: 20,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ✨ 1. 상단 탭 (전체 / 귓속말 / 친구)
                  Row(
                    children: [
                      _buildChatTab(0, '전체'),
                      _buildChatTab(1, '귓속말'),
                      _buildChatTab(2, '친구'),
                      _buildChatTab(3,'아레나'),
                    ],
                  ),
                  // ✨ 2. 메인 채팅창 컨테이너
                  Container(
                    width: 380, 
                    height: 180, 
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.8), 
                      border: Border.all(color: Colors.amber, width: 2), // 노란색 테두리
                    ),
                    child: Column(
                      children: [
                        Expanded(
                          child: _currentChatTab == 2
                              // ✨ [친구 탭 (2)] : 내 친구 목록 불러오기
                              ? StreamBuilder<QuerySnapshot>(
                                  stream: FirebaseFirestore.instance
                                      .collection('friends')
                                      .doc(widget.nickname) // 사장님 닉네임
                                      .collection('my_list')
                                      .orderBy('addedAt', descending: true)
                                      .snapshots(),
                                  builder: (context, snapshot) {
                                    if (!snapshot.hasData) return const Center(child: CircularProgressIndicator(color: Colors.amber));
                                    var docs = snapshot.data!.docs;

                                    if (docs.isEmpty) {
                                      return const Center(child: Text('아직 등록된 친구가 없습니다.\n채팅창에서 유저를 터치해 친구를 추가해 보세요!', textAlign: TextAlign.center, style: TextStyle(color: Colors.white54, fontSize: 12)));
                                    }

                                    return ListView.builder(
                                      itemCount: docs.length,
                                      itemBuilder: (context, index) {
                                        var friendData = docs[index].data() as Map<String, dynamic>;
                                        String friendName = friendData['nickname'] ?? '알 수 없음';

                                        return ListTile(
                                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                                          visualDensity: VisualDensity.compact,
                                          leading: const Icon(Icons.person, color: Colors.greenAccent, size: 20),
                                          title: Text(friendName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                                          trailing: IconButton(
                                            icon: const Icon(Icons.chat_bubble, color: Colors.yellowAccent, size: 20),
                                            tooltip: '귓속말 보내기',
                                            onPressed: () {
                                              // 💬 아이콘 누르면 바로 귓속말 모드로 전환!
                                              setState(() {
                                                _whisperTargetNickname = friendName;
                                                _currentChatTab = 1;
                                              });
                                            },
                                          ),
                                        );
                                      },
                                    );
                                  },
                                )
                              // ✨ [전체/귓속말 탭 (0, 1)] : 기존 채팅창 불러오기
                              : StreamBuilder<QuerySnapshot>(
                                  stream: _currentChatTab == 3
                              // 🏆 [아레나 탭]일 때 방 번호(roomId)가 진짜 있는지 안전하게 확인!
                                   ? (widget.roomId != null 
                                   ? FirebaseFirestore.instance.collection('arenas').doc(widget.roomId!).collection('messages')
                                     .where('createdAt', isGreaterThanOrEqualTo: _joinTime) 
                                     .orderBy('createdAt', descending: true).snapshots()
                                 : const Stream.empty()) // 🌟 방 번호가 없으면 에러 내지 말고 조용히 빈 화면 띄워!
                              // 💬 [그 외 탭]일 땐 전체 채팅!
                                 : FirebaseFirestore.instance.collection('global_chat')
                                     .where('timestamp', isGreaterThanOrEqualTo: _joinTime) 
                                     .orderBy('timestamp', descending: true).limit(30).snapshots(),
                                     builder: (context, snapshot) {
                                    if (!snapshot.hasData) return const SizedBox.shrink();
                                    var docs = snapshot.data!.docs;

                                    return ListView.builder(
                                      reverse: true,
                                      itemCount: docs.length,
                                      itemBuilder: (context, index) {
                                        var data = docs[index].data() as Map<String, dynamic>;

                                        String type, receiver, sender, msg;
                                        if (_currentChatTab == 3) {
                                          // 🏆 아레나 전용 메시지함: 유저채팅({nickname,message,type})과
                                          //    시스템 메시지(잡았다/정산 → {sender,text})가 섞여 있음 → 둘 다 표시
                                          type = 'arena';
                                          receiver = '';
                                          sender = (data['nickname'] ?? data['sender'] ?? '조사님').toString();
                                          msg = (data['message'] ?? data['text'] ?? '').toString();
                                        } else {
                                          type = data['type'] ?? 'global';
                                          receiver = data['receiver'] ?? '';
                                          sender = data['nickname'] ?? '조사님';
                                          msg = data['message'] ?? '';
                                        }

                                        String myNickname = widget.nickname;

                                        if (_currentChatTab == 1) {
                                          if (type != 'whisper') return const SizedBox.shrink();
                                          if (sender != myNickname && receiver != myNickname) return const SizedBox.shrink();
                                         }

                                        Color prefixColor = Colors.white;
                                        String prefixText = '전체>';
                                        if (type == 'notice') {
                                          prefixColor = Colors.amber;
                                          prefixText = '공지>';
                                        } else if (type == 'whisper') {
                                          prefixColor = Colors.yellowAccent;
                                          prefixText = '귓속말>';
                                        }
                                        // 👇 귓속말 로직 바로 밑에 아레나 색상 추가!
                                          else if (type == 'arena') {
                                          prefixColor = const Color(0xFFD4AF37); // 아레나 전용 골드 색상!
                                          prefixText = '아레나';
                                        }

                                        return Padding(
                                          padding: const EdgeInsets.only(bottom: 4.0),
                                          child: RichText(
                                            text: TextSpan(
                                              children: [
                                                TextSpan(text: '$prefixText ', style: TextStyle(color: prefixColor)),
                                                TextSpan(
                                                  text: '$sender: ',
                                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                                  recognizer: TapGestureRecognizer()..onTap = () {
                                                    if (sender == myNickname) return; 
                                                    _showUserMenu(sender); 
                                                  }
                                                ),
                                                TextSpan(text: msg, style: TextStyle(color: type == 'notice' ? Colors.amber : Colors.white)),
                                              ],
                                            ),
                                          ),
                                        );
                                      },
                                    );
                                  },
                                ),
                            ),
                        
                        const SizedBox(height: 8),
                        // ✨ 3. 채팅 입력창
                        SizedBox(
                          height: 35,
                          child: TextField(
                            controller: _chatController,
                            style: const TextStyle(color: Colors.white, fontSize: 13),
                            decoration: InputDecoration(
                              hintText: (_currentChatTab == 1 && _whisperTargetNickname != null)
                                  ? '[$_whisperTargetNickname]님에게 귓속말...'
                                  : '메시지를 입력하세요...',
                              hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                              border: const OutlineInputBorder(),
                            ),
                            onSubmitted: (_) => _sendMessage(),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    // ... 사장님의 엄청난 낚시 본게임 코드들 ...
          
        ), // 👈 기존 Scaffold가 끝나는 괄호! (여기를 잘 찾으셔야 합니다!)

        // 🦅 자연 효과(갈매기 등) — Scaffold HUD 위에 그려 버튼에 안 가림.
        //    IgnorePointer라 버튼 클릭도 안 막고, showDialog 팝업·낚시튜토는 이 위에 뜸.
        NatureAmbientEffects(isSea: widget.isSea),

        // ==========================================================
        // 2. 👧 윤슬 가이드 낚시 세팅 투어 레이어
        // ==========================================================
        if (_fishingStep == 0)
          NpcTutorialOverlay(
            text: "어서오세요 이곳은 예당지입니다.\n낚시를 시작하려면 채비를 준비해야 해요!\n오른쪽 인벤토리에 가입 선물로 받은 기본(공짜!) 아이템들이 들어있답니다 ^^.",
            imagePath: "assets/images/npc_girl_intro.png",
            onTap: () => setState(() => _fishingStep = 1),
          ),
        if (_fishingStep == 1)
          NpcTutorialOverlay(
            text: "아이템 착용은 수동과 자동이 있어요!\n가방에 있는 아이템을 클릭하거나 아래쪽에 자동장착을 누르시면 가장 좋은 아이템으로 자동으로 장착된답니다!",
            imagePath: "assets/images/npc_girl_point.png",
            onTap: () => setState(() => _fishingStep = 2),
          ),
        if (_fishingStep == 2)
          NpcTutorialOverlay(
            text: "왼쪽 상단은 상태창이에요.\n'<' 뒤로가기 로비로 나갈 수 있어요.\n'예산 예당지' 조사님의 현재 위치구요.\n다음은 레벨과 제압력(힘,컨트롤,감도)!\n'0/5000' 현재경험치/다음레벨 경험치\n'POINT'는 게임머니에요!",
            imagePath: "assets/images/npc_girl_point.png",
            onTap: () => setState(() => _fishingStep = 3),
          ),
        if (_fishingStep == 3)
          NpcTutorialOverlay(
            text: "참~ 쉽죠!! ^^\n자! 그럼 첫 고기를 낚으러 가보실까요..!\n자동장착 누르시고\n선호하는 케미라이트 색상 선택하시고\n'캐스팅 시작!' 🎣",
            imagePath: "assets/images/npc_girl_success.png",
            onTap: () => setState(() => _fishingStep = -1), 
          ),

        // 🚀👇 [여기부터 새로 끼워넣기!!] 👇🚀
        if (_fishingStep == 4)
          NpcTutorialOverlay(
            text: "화면 오른쪽 상단은 전체화면, 소리끄기 설정이에요!\n상단 중앙에 시계는 오늘 남은 시간이에요.\n 캠피싱 낚시대회는 하루 한시간 이용 가능하답니다. 12시에 초기화되요 ^^\n왼쪽 채팅창에서 다른 조사님들과 실시간 대화를 나눌 수 있어요.!\n자~! 찌 색깔이 바뀌며 올라오면 챔질 버튼을 '당기기'까지 내리세요! 🎣",
            imagePath: "assets/images/npc_girl_intro.png",
            onTap: () => setState(() => _fishingStep = -1), 
          ),
          
      ],
    ), // 🚀 2. 아까 위에서 열었던 Stack 필름을 최종적으로 닫아줍니다!
    ); // ⚔️ WillPopScope 닫기
  } // <-- build 함수 끝나는 괄호

// 🎟️ [여기에 추가!] 티켓 사용 확인 팝업
  void _useTicket(Map<String, dynamic> ticketItem) {
    audioManager.playSfx('sfx_click.mp3');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.grey.shade900,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15), side: const BorderSide(color: Color(0xFFD4AF37))),
        title: const Text('🎟️ 이용권 사용', style: TextStyle(color: Color(0xFFD4AF37), fontWeight: FontWeight.bold)),
        content: Text('${ticketItem['name']}을(를) 사용하시겠습니까?\n\n✨ 낚시 시간이 60분 추가됩니다.', style: const TextStyle(color: Colors.white, height: 1.5)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('아껴두기', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFD4AF37), foregroundColor: Colors.black),
            onPressed: () async {
              Navigator.pop(ctx);
              await _processTicketConsumption(ticketItem); // ⚡ 실제 소모 및 시간 추가 실행!
            },
            child: const Text('사용하기', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  // ⚡ 실제 티켓 소모 및 시간 추가 로직 (파이어베이스 연동)
  Future<void> _processTicketConsumption(Map<String, dynamic> ticketItem) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      var doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      // 🎟️ [1일 1회 제한] 오늘 이미 시간 이용권을 썼으면 차단 (현질 렙업 폭주 방지 / 인벤엔 그대로 보관)
      final String today = DateTime.now().toString().substring(0, 10);
      if (doc.data()?['lastTimeTicketDate'] == today) {
        if (mounted) {
          _showNotificationPopup('🎟️ 오늘은 이미 사용했어요',
              '시간 이용권은 하루에 한 번만 사용할 수 있어요.\n내일 다시 사용해 주세요!\n(이용권은 인벤토리에 그대로 남아있어요 😊)',
              const Color(0xFFD4AF37));
        }
        return;
      }
      List<dynamic> inv = doc.data()?['inventory'] ?? [];

      int index = inv.indexWhere((item) => item['name'] == ticketItem['name']);
      
      if (index != -1) {
         int currentQty = inv[index]['quantity'] ?? 1;
         
         if (currentQty > 1) {
           inv[index]['quantity'] = currentQty - 1;
         } else {
           inv.removeAt(index);
         }

         // ✨ 1. 내 폰 화면 타이머에 60분(3600초) 추가!
         remainingTimeNotifier.value += 3600;

         // ✨ 2. 파이어베이스(서버)에 인벤토리 차감 + 늘어난 시간 같이 저장!! (핵심)
         await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
           'inventory': inv,
           'remainingTime': remainingTimeNotifier.value, // 🚨 중요: 만약 파이어베이스에 저장되는 시간 필드명이 다르면 맞춰주세요! (예: dailyTime, timeLeft 등)
           'lastTimeTicketDate': today, // 🎟️ 오늘 사용 기록 → 1일 1회 제한(날짜 바뀌면 자동 해제)
         });
         
         // 5. 럭셔리 블랙&골드 성공 알림창 띄우기
         ScaffoldMessenger.of(context).showSnackBar(
           SnackBar(
             content: const Row(
               children: [
                 Icon(Icons.timer, color: Color(0xFFD4AF37)), // 골드색 타이머 아이콘
                 SizedBox(width: 10), 
                 Text('🎉 대회 시간이 60분 추가되었습니다!', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16))
               ]
             ),
             backgroundColor: Colors.grey.shade900, // 고급스러운 다크 그레이 배경
             behavior: SnackBarBehavior.floating,
             margin: const EdgeInsets.only(bottom: 20, left: 20, right: 20), // 화면 끝에 안 붙고 살짝 뜨게 마진 주기
             elevation: 10,
             shape: RoundedRectangleBorder(
               borderRadius: BorderRadius.circular(15),
               side: const BorderSide(color: Color(0xFFD4AF37), width: 1.5) // 영롱한 골드 테두리!
             ),
             duration: const Duration(seconds: 3), // 3초 뒤에 자연스럽게 사라짐
           )
         );
      }
    } catch (e) {
      print("티켓 사용 에러: $e");
    }
  }

    Widget _buildSetupOverlay() {
    int maxRods = widget.isSea ? 1 : 2; 
    if (!widget.isSea) {
     String skinName = equippedSkin != null ? equippedSkin!['name'].toString() : '초보';
      if (skinName.contains('마스터')) maxRods = 14;
      else if (skinName.contains('프로')) maxRods = 10;
      else if (skinName.contains('고수')) maxRods = 8;
      else if (skinName.contains('중수')) maxRods = 6;
      else if (skinName.contains('하수')) maxRods = 4;
    }
    if (selectedRodCount > maxRods) selectedRodCount = maxRods;

    return Container(
      width: 350, padding: const EdgeInsets.all(24), decoration: BoxDecoration(color: Colors.black.withOpacity(0.85), borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFFD4AF37), width: 3)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('🎣 출조 셋팅', style: TextStyle(color: Color(0xFFD4AF37), fontSize: 26, fontWeight: FontWeight.bold)), const SizedBox(height: 24),
          Text('대편성 갯수: $selectedRodCount대', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          if (maxRods > 1) Slider(value: selectedRodCount.toDouble(), min: 1, max: maxRods.toDouble(), divisions: maxRods - 1, activeColor: const Color(0xFFD4AF37), inactiveColor: Colors.grey.shade800, onChanged: (v) { audioManager.playSfx("sfx_click.mp3"); setState(() => selectedRodCount = v.toInt()); }),
          if (maxRods == 1) const Padding(padding: EdgeInsets.symmetric(vertical: 10), child: Text('바다 낚시는 1대만 지원됩니다.', style: TextStyle(color: Colors.grey, fontSize: 12))),
          if (!widget.isSea) ...[
            const SizedBox(height: 15), const Text('케미라이트 색상', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)), const SizedBox(height: 10),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [ _chemiCircle(Colors.green), const SizedBox(width: 10), _chemiCircle(Colors.red), const SizedBox(width: 10), _chemiCircle(Colors.blue), const SizedBox(width: 10), _chemiCircle(Colors.yellow) ]), const SizedBox(height: 20),
          ],
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [ const Text('현재 장착 미끼: ', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)), Text(equippedBait != null ? equippedBait!['name'] : '가방에서 터치!', style: TextStyle(color: equippedBait != null ? const Color(0xFFD4AF37) : Colors.redAccent, fontSize: 16, fontWeight: FontWeight.bold)) ]), const SizedBox(height: 20),
          if (widget.isSea) ...[
            const SizedBox(height: 10), 
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [const Text('현재 장착 릴: ', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)), Text(equippedReel != null ? equippedReel!['name'] : '가방에서 터치!', style: TextStyle(color: equippedReel != null ? const Color(0xFFD4AF37) : Colors.redAccent, fontSize: 16, fontWeight: FontWeight.bold))]),
          ],
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.black,
              foregroundColor: const Color(0xFFD4AF37),
              side: const BorderSide(color: Color(0xFFD4AF37), width: 1.5),
              minimumSize: const Size(double.infinity, 50),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: _runAutoEquip,
            child: const Text('⚡ 자동 장착', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFD4AF37), minimumSize: const Size(double.infinity, 50)),
            onPressed: () {
                            // 👇 [아레나 VIP 하이패스 적용 완료!]
                            if (widget.roomId == null) {
                              // 아레나가 아닐 때(일반 낚시터)만 시간 검사!
                              if (remainingTimeNotifier.value <= 0) {
                                showDialog(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    backgroundColor: Colors.black87,
                                    title: const Row(
                                      children: [
                                        Icon(Icons.warning_amber_rounded, color: Colors.redAccent),
                                        SizedBox(width: 10),
                                        Text('캐스팅 불가', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                                      ],
                                    ),
                                    content: const Text('낚시 시간이 부족합니다.\nKREFT 상점에서 낚시 시간을 충전해주세요! 💸', style: TextStyle(color: Colors.white)),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(context),
                                        child: const Text('확인', style: TextStyle(color: Colors.amber)),
                                      ),
                                    ],
                                  ),
                                );
                                return;
                             } // 👈 하이패스 게이트 종료
                           }
              if (equippedRod == null) {
      // 🎣 빈손이면 먼저 '보유한 최고 장비' 자동 장착 (조용히)
      _runAutoEquip(silent: true);
      // 그래도 비어있는 슬롯(장비를 다 팔았을 때)만 임시 기본 장비로 채움
      setState(() {
        equippedRod ??= widget.isSea
            ? {'name': '오션 스타터', 'category': 'SEA', 'stats': {'P': 2, 'C': 2, 'S': 2}, 'icon': 'assets/items/rod_sea_cf250.png'}
            : {'name': '베이직 민물대', 'category': 'FW', 'stats': {'P': 2, 'C': 2, 'S': 2}, 'icon': 'assets/items/rod_fw_cf20.png'};

        equippedFloat ??= {'name': '기본 찌', 'stats': {'P': 2, 'C': 2, 'S': 2}, 'icon': 'assets/items/float_fw_normal.png'};

        equippedBait ??= {'name': '지렁이 (기본)', 'icon': 'assets/items/bait_fw_worm.png'};

        if (widget.isSea) equippedReel ??= {'name': '기본 릴', 'category': 'SEA', 'stats': {'P': 2, 'C': 2, 'S': 2}, 'icon': 'assets/items/reel_sea_cf2000.png'};

        isRodEquipped = true;
      });
      _showNotificationPopup('🎣 장비 자동 세팅', '보유한 최고 장비로 세팅했어요!\n(없는 장비는 임시 기본으로 채웠어요)', const Color(0xFFD4AF37));
    } else if (equippedBait == null) {
      // 🪱 낚시대는 있는데 미끼만 없음 → 가짜 미끼 지급 X, 캐스팅 차단
      _showNotificationPopup('🪱 미끼가 없어요!', '미끼를 장착하거나 상점에서 구매하세요!', Colors.orangeAccent);
      return;
    }
              // (미끼 소모는 _startFight에서 입질마다 처리 — #2)
              audioManager.playSfx("sfx_casting.mp3"); _castController.forward(from: 0.0);
              setState(() { isSettingUp = false; isCasting = true; bitingRods.clear(); });
              Future.delayed(const Duration(milliseconds: 300), () { if (!mounted) return; audioManager.playBgm(widget.isSea ? "bgm_sea_fishing.mp3" : "bgm_fresh_fishing.mp3"); _startGameTimer(); });
              Future.delayed(const Duration(milliseconds: 1500), () { if (mounted) { setState(() { isCasting = false; isFloatInWater = true; if (widget.isFirstTime && !_isTutorialDone) _fishingStep = 4; }); _startBiteTimer(); } });
            },
            child: const Text('캐스팅 시작!', style: TextStyle(color: Colors.black, fontSize: 18, fontWeight: FontWeight.w900)),
          )
        ],
      ),
    );
  }

  Widget _buildCastingScene() {
    return Positioned.fill(
      child: Stack(
        children: [
          const Center(child: Text('캐스팅 중...', style: TextStyle(color: Colors.white, fontSize: 40, fontWeight: FontWeight.w900, fontStyle: FontStyle.italic, shadows: [Shadow(color: Colors.black, blurRadius: 10, offset: Offset(2, 2))]))),
          Positioned(
            right: castingArmRightOffset, bottom: castingArmBottomOffset,
            child: AnimatedBuilder(
              animation: _castController,
              builder: (context, child) {
                double swingAngle = castingBaseAngle + 0.5 - (_castController.value * 1.5); 
                // 🎣 장착 낚싯대별 캐스팅 그림 (파일 없으면 기본 그림 자동 폴백)
                final String castBase = widget.isSea ? 'assets/images/cast_sea' : 'assets/images/cast_fw';
                final String castSfx = rodSceneSuffix(equippedRod);
                final String castImage = castSfx.isEmpty ? '$castBase.png' : '${castBase}_$castSfx.png';
                return Transform.rotate(angle: swingAngle, origin: Offset(castingOriginX, castingOriginY), child: Image.asset(castImage, height: castingImageSize, fit: BoxFit.contain, errorBuilder: (c,e,s) => Image.asset('$castBase.png', height: castingImageSize, fit: BoxFit.contain, errorBuilder: (c2,e2,s2) => const Icon(Icons.waves, size: 200, color: Colors.white10))));
              }
            )
          ),
        ],
      ),
    );
  }

  Widget _chemiCircle(Color color) {
    bool isSelected = selectedChemiColor == color;
    return GestureDetector(onTap: () { audioManager.playSfx("sfx_click.mp3"); setState(() => selectedChemiColor = color); }, child: Container(width: 45, height: 45, decoration: BoxDecoration(color: color, shape: BoxShape.circle, border: Border.all(color: isSelected ? Colors.white : Colors.transparent, width: 3), boxShadow: isSelected ? [BoxShadow(color: color, blurRadius: 10, spreadRadius: 2)] : [])));
  }

  Widget _buildFieldRods() {
    if (widget.isSea) {
      // 🎣 장착 낚싯대별 바다 웨이팅 그림 (파일 없으면 기본 그림 자동 폴백)
      final String waitSfx = rodSceneSuffix(equippedRod);
      final String waitImage = waitSfx.isEmpty ? 'assets/images/waiting_sea.png' : 'assets/images/waiting_sea_$waitSfx.png';
      return Positioned.fill(child: Stack(children: [Positioned(right: seaWaitingRightOffset, bottom: seaWaitingBottomOffset, child: Transform.rotate(angle: seaWaitingAngle, alignment: Alignment.bottomRight, child: Image.asset(waitImage, height: seaWaitingImageSize, fit: BoxFit.contain, errorBuilder: (c,e,s) => Image.asset('assets/images/waiting_sea.png', height: seaWaitingImageSize, fit: BoxFit.contain, errorBuilder: (c2,e2,s2) => const Icon(Icons.waves, size: 200, color: Colors.white10)))))]));
    }
    // 🎣 장착 낚싯대별 민물 거치 실루엣 (파일 없으면 기본 자동 폴백)
    final String depSfx = rodSceneSuffix(equippedRod);
    final String deployedImage = depSfx.isEmpty ? 'assets/items/rod_fw_basic_deployed.png' : 'assets/items/rod_fw_${depSfx}_deployed.png';
    return Positioned(
      bottom: 0, left: 0, right: 0,
      child: Stack(
        alignment: Alignment.bottomCenter, clipBehavior: Clip.none,
        children: [
          Positioned(bottom: platformBottomOffset, child: Image.asset('assets/items/platform_fw.png', width: platformWidth, height: platformHeight, fit: BoxFit.fill, color: Colors.black.withOpacity(platformDarkness), colorBlendMode: BlendMode.srcATop, errorBuilder: (c,e,s) => Container())),
          Row(
            mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end,
            children: List.generate(selectedRodCount, (index) {
              bool isBiting = (bitingRods.contains(index)); Color currentColor = isBiting ? _getBiteColor(selectedChemiColor) : selectedChemiColor;
              double centerIndex = (selectedRodCount - 1) / 2; double angle = (index - centerIndex) * rodFanAngleStep;
              return Padding(
                padding: EdgeInsets.symmetric(horizontal: fieldFloatSpacing), 
                child: Transform.rotate(
                  angle: angle, alignment: Alignment.bottomCenter, 
                  child: Stack(
                    clipBehavior: Clip.none, alignment: Alignment.bottomCenter,
                    children: [
                      Image.asset(deployedImage, height: fieldRodLength, fit: BoxFit.contain, alignment: Alignment.bottomCenter, errorBuilder: (c,e,s) => Image.asset('assets/items/rod_fw_basic_deployed.png', height: fieldRodLength, fit: BoxFit.contain, alignment: Alignment.bottomCenter)),
                      Positioned(
                        bottom: fieldFloatBottomOffset + fieldFloatDepthOffset, 
                        child: Transform.rotate(
                          angle: -angle, 
                          child: Opacity(
                            opacity: isFloatInWater ? 1.0 : 0.0,
                            child: AnimatedContainer(
                              // 🌟 [찌올림 패치] 목표 높이(height)를 40 -> 80으로 대폭 올렸습니다!
                              // 이렇게 하면 4.5초의 입질 시간 동안 꼭대기까지 못 가고, 중간까지만 아주 '묵직~하게' 스르륵 밀어 올리다 멈춥니다!
                              duration: const Duration(milliseconds: 6000), curve: Curves.easeOutCubic, width: 30, height: isBiting ? (selectedRodCount >= 8 ? 25.0 : 22.0) : 7.0,
                              child: Stack(alignment: Alignment.topCenter, clipBehavior: Clip.none, children: [Container(width: 3, height: 5, decoration: BoxDecoration(color: currentColor, borderRadius: BorderRadius.circular(5), boxShadow: [BoxShadow(color: currentColor.withOpacity(0.8), blurRadius: 5, spreadRadius: 2)])), Transform.translate(offset: const Offset(0, 5), child: Image.asset(_getIconImagePath(equippedFloat) ?? 'assets/images/float_default.png', height: selectedRodCount >= 8 ? 40 : 65, fit: BoxFit.contain, alignment: Alignment.topCenter))]),
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
    );
  }

  Widget _buildFightScene() {
    // 🎣 장착 낚싯대별 파이팅 그림 (파일 없으면 기본 그림 자동 폴백)
    final String fightBase = widget.isSea ? 'assets/images/hand_rod_sea' : 'assets/images/hand_rod_fw';
    final String fightSfx = rodSceneSuffix(equippedRod);
    final String fightRodImage = fightSfx.isEmpty ? '$fightBase.png' : '${fightBase}_$fightSfx.png';
    return Positioned.fill(
      child: Stack(
        children: [
          Positioned(
            right: fightArmRightOffset, bottom: fightArmBottomOffset,
            child: AnimatedBuilder(
                animation: _rodController, 
                builder: (context, child) { 
                  double fightAngle = fightBaseAngle + (math.Random().nextDouble() - 0.5) * (0.05 + (tension * 0.1));
                  return Transform.rotate(angle: fightAngle, origin: Offset(fightOriginX, fightOriginY), child: Image.asset(fightRodImage, height: fightImageSize, fit: BoxFit.contain, errorBuilder: (c,e,s) => Image.asset('$fightBase.png', height: fightImageSize, fit: BoxFit.contain, errorBuilder: (c2,e2,s2) => const Icon(Icons.waves, size: 200, color: Colors.white10)))); 
                }
            )
          ),
          Positioned(
            bottom: 120, left: 100, right: 200,
            child: Column(
              children: [
                const Text("파이팅!!!", style: TextStyle(color: Colors.yellowAccent, fontSize: 50, fontWeight: FontWeight.w900, fontStyle: FontStyle.italic, shadows: [Shadow(color: Colors.black, blurRadius: 10, offset: Offset(2,2))])), const SizedBox(height: 25),
                Container(width: double.infinity, height: 35, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white54, width: 3)), child: FractionallySizedBox(alignment: Alignment.centerLeft, widthFactor: tension.clamp(0.0, 1.0), child: Container(decoration: BoxDecoration(color: (tension < 0.2 || tension > 0.8) ? Colors.red : Colors.cyanAccent, borderRadius: BorderRadius.circular(15))))),
              ],
            ),
          ),
        ],
      )
    );
  }

  Widget _buildMainActionButton() {
    // 파이팅(미니게임) 중일 때는 오버레이(팝업)가 뜨므로 이 버튼은 숨깁니다!
    if (isFighting) return const SizedBox.shrink();

    // 🎣 1. [캐스팅 상태] 찌가 물에 없을 때는 기존처럼 터치형 '캐스팅' 버튼 1개만!
    if (!isFloatInWater) {
      return GestureDetector(
        onTapDown: (_) {
          audioManager.playSfx("sfx_click.mp3");
          _recast(); 
        },
        child: Container(
          width: 120, height: 120, 
          decoration: BoxDecoration(color: Colors.redAccent, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 5), boxShadow: const [BoxShadow(blurRadius: 15, spreadRadius: 2, color: Colors.black54)]), 
          child: const Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.catching_pokemon, size: 40, color: Colors.white), SizedBox(height: 5), Text('캐스팅', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900))])
        )
      );
    }

    // 💥 2. [입질 대기 & 챔질 상태] 찌가 물에 있을 때 발동하는 '드래그 챔질' UI!
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 🔴 [위쪽] 손가락으로 잡고 끌어내릴 '챔질!' 버튼
        Draggable<String>(
          data: 'STRIKE',
          // 🚨 [핵심 패치 1] 좌우로 안 벗어나게 상하(1자)로만 고정! (레일 장착 완료)
          axis: Axis.vertical, 
          feedback: Material(
            color: Colors.transparent,
            child: Container(
              width: 120, height: 120,
              decoration: BoxDecoration(color: Colors.redAccent.withOpacity(0.9), shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 5), boxShadow: const [BoxShadow(blurRadius: 20, spreadRadius: 5, color: Colors.white70)]), 
              child: const Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.catching_pokemon, size: 40, color: Colors.white), SizedBox(height: 5), Text('챔질!', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900))])
            ),
          ),
          childWhenDragging: Container(
            width: 120, height: 120,
            decoration: BoxDecoration(color: Colors.black26, shape: BoxShape.circle, border: Border.all(color: Colors.white38, width: 5)), 
            child: const Icon(Icons.arrow_downward, color: Colors.white54, size: 40),
          ),
          child: Container(
            width: 120, height: 120,
            decoration: BoxDecoration(color: Colors.redAccent, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 5), boxShadow: const [BoxShadow(blurRadius: 15, spreadRadius: 2, color: Colors.black54)]), 
            child: const Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.catching_pokemon, size: 40, color: Colors.white), SizedBox(height: 5), Text('챔질!', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900))])
          ),
        ),

        // ... (위쪽 Draggable 챔질 버튼 코드는 그대로 두시고!) ...

        // 🚨 [수정 1] 여기 간격을 15 -> 100 으로 확 늘려줍니다!! (숫자가 클수록 위로 올라감!)
        const SizedBox(height: 40), 
        
        // ⬇️ 거리가 멀어졌으니 화살표를 2개로 이어서 궤적을 예쁘게 만들어줍니다!
        const Column(
          children: [
            Icon(Icons.keyboard_double_arrow_down, color: Colors.yellowAccent, size: 40, shadows: [Shadow(color: Colors.black, blurRadius: 5)]),
            Icon(Icons.keyboard_double_arrow_down, color: Colors.white54, size: 40, shadows: [Shadow(color: Colors.black, blurRadius: 5)]),
          ],
        ),
        
        // 🚨 [수정 2] 여기도 간격을 15 -> 100 으로 확 늘려줍니다!!
        const SizedBox(height: 80), 

        // 🟡 [아래쪽] 드래그해서 꽂아넣을 '당기기' 타겟 영역!
        DragTarget<String>(
       
          // 🚨 [핵심 패치 2] 당기기 버튼 영역에 "진입(Hover)하자마자" 즉시 챔질! (뗏다가 누를 필요 없음)
          onWillAccept: (data) {
            if (data == 'STRIKE') {
              _handleMainActionButton();
              return true;
            }
            return false;
          },
          // onAccept는 손을 뗐을 때 발동하는데, 이미 위에서 낚아챘으므로 비워둡니다.
          onAccept: (data) {}, 
          builder: (context, candidateData, rejectedData) {
            bool isHovered = candidateData.isNotEmpty; 
            
            return AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: isHovered ? 140 : 120, 
              height: isHovered ? 140 : 120,
              decoration: BoxDecoration(
                color: isHovered ? Colors.orangeAccent : const Color(0xFFD4AF37),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: isHovered ? 8 : 5),
                boxShadow: isHovered 
                    ? const [BoxShadow(blurRadius: 30, spreadRadius: 10, color: Colors.orangeAccent)] 
                    : const [BoxShadow(blurRadius: 15, spreadRadius: 2, color: Colors.black54)],
              ),
              // ...
              // 🚨 [수정] 헷갈리는 화살표 빼고 글씨만 정중앙에 뙇!
              child: Center(
                child: Text(
                  '당기기', 
                  style: TextStyle(
                    color: Colors.white, 
                    fontSize: isHovered ? 30 : 26, // 💡 아이콘이 빠진 만큼 글씨를 더 큼직하게 키웠습니다!
                    fontWeight: FontWeight.w900
                  )
                )
              )
            );
          },
        ),
      ],
    );
  }

  Widget _statText(String title, int value) { return Row(children: [ Text('$title : ', style: const TextStyle(color: Colors.grey, fontSize: 12)), Text('$value', style: const TextStyle(color: Color(0xFFD4AF37), fontSize: 14, fontWeight: FontWeight.bold)) ]); }

  // 👇 1. 인벤토리 상태가 매초 초기화되지 않도록 기억하는 변수들 (함수 바로 위에 빼두기!)
  Stream<DocumentSnapshot>? _inventoryStream;
  List<dynamic> _latestInventory = []; // ⚡ 자동 장착이 참조할 최신 인벤토리 캐시
  final ScrollController _invScrollCtrl = ScrollController();
  String _currentFilter = 'ALL';

  // 👇 2. 기존 buildInventoryPanel 함수 전체를 아래 코드로 덮어쓰기!
  // (끝나는 괄호 } 위치까지 잘 확인해서 덮어씌워 주세요!)
  Widget buildInventoryPanel(BuildContext context) {
    Map<String, int> totalStats = getMyTotalStats();
    int totalP = totalStats['strength'] ?? 0;
    int totalC = totalStats['control'] ?? 0;
    int totalS = totalStats['sensitivity'] ?? 0;

    final user = FirebaseAuth.instance.currentUser;
    
    // 💡 3. 매초 DB를 새로 불러오지 않도록 캐싱(기억)해 둡니다!
    _inventoryStream ??= FirebaseFirestore.instance.collection('users').doc(user?.uid).snapshots();

    return StreamBuilder<DocumentSnapshot>(
      stream: _inventoryStream,
      builder: (context, snapshot) {
        // 💡 4. 데이터가 처음 들어올 때 딱 한 번만 로딩 표시 (깜빡임 완벽 차단!)
        if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) { 
          return Container(width: 530, height: 500, padding: const EdgeInsets.all(12), decoration: BoxDecoration(gradient: const RadialGradient(center: Alignment(-0.5, -0.5), radius: 1.5, colors: [Color(0xFF3A3A3A), Color(0xFF0F0F0F)]), border: Border.all(color: const Color(0xFFD4AF37), width: 4), borderRadius: BorderRadius.circular(15)), child: const Center(child: CircularProgressIndicator(color: Color(0xFFD4AF37)))); 
        }
        
        List<dynamic> inventory = []; 
        int myLevel = 1; 
        int myGold = 0;

        if (snapshot.hasData && snapshot.data!.data() != null) { 
          var userData = snapshot.data!.data() as Map<String, dynamic>; 
          inventory = userData['inventory'] ?? []; 
          myGold = userData['gold'] ?? 0; 

          int exp = userData['exp'] ?? 0;
          myLevel = calcLevelFromExp(exp); // 🆙 공용 100레벨 계산 (옛 30레벨 하드코딩 제거)
        }
        
        bool isBait(String name) { return name.contains('지렁이') || name.contains('글루텐') || name.contains('옥수수') || name.contains('크릴') || name.contains('에기') || name.contains('루어') || name.contains('미끼') || name.contains('민물새우'); }

        _latestInventory = inventory; // ⚡ 자동 장착용으로 최신 인벤토리 기억
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setInvState) {
            // 🦐 민물새우 보유 여부 → 있으면 미끼만, 없으면 채집망(도구)만 표시
            bool hasShrimp = inventory.any((i) => (i['name']?.toString() ?? '') == '민물새우' && ((i['quantity'] ?? 0) as num) > 0);
            List<dynamic> filteredItems = inventory.where((item) {
              String cat = item['category'] ?? '';
              bool isSkin = item['name'].toString().contains('조사') || item['name'].toString().contains('마스터') || item['name'].toString().contains('프로') || item['name'].toString().contains('세트');
              // 🦐 새우 있으면 민물새우(미끼) 표시·채집망 숨김 / 새우 없으면 채집망만 표시
              if (item['name'].toString() == '민물새우' && !hasShrimp) return false;
              if (item['name'].toString() == '새우 채집망' && hasShrimp) return false;
              final isFish = (item['type'] ?? '') == 'FISH';
              if (_currentFilter == 'ALL') return true;
              if (_currentFilter == 'FW' && (cat == 'FW' || cat == 'COMMON') && !isSkin && !isFish && !isBait(item['name'].toString())) return true;
              if (_currentFilter == 'SEA' && (cat == 'SEA' || cat == 'COMMON') && !isSkin && !isFish && !isBait(item['name'].toString())) return true;
              if (_currentFilter == 'BAIT' && isBait(item['name'].toString())) return true;
              if (_currentFilter == 'SKIN' && isSkin) return true;
              if (_currentFilter == 'FISH' && isFish) return true;
              return false;
            }).toList();

            filteredItems.sort((a, b) {
                      String getType(Map<String, dynamic> item) {
                        String t = (item['type']?.toString().toUpperCase() ?? '');
                        String n = (item['name']?.toString() ?? '');
                        String c = (item['category']?.toString().toUpperCase() ?? '');
                        if (t.isNotEmpty) return t;
                        if (n.contains('대') || n.contains('CF') || n.contains('KT')) return 'ROD';
                        if (n.contains('릴') || c == 'REEL') return 'REEL';
                        if (n.contains('찌') || c == 'FLOAT') return 'FLOAT';
                        if (n.contains('지렁이') || n.contains('글루텐') || n.contains('옥수수') || n.contains('미끼') || n.contains('에기') || n.contains('민물새우')) return 'BAIT';
                        if (n.contains('스킨') || n.contains('조사')) return 'SKIN';
                        return 'ETC';
                      }
                      const priority = {'ROD': 1, 'REEL': 2, 'FLOAT': 3, 'BAIT': 4, 'SKIN': 5, 'ETC': 6};
                      int pA = priority[getType(a)] ?? 99;
                      int pB = priority[getType(b)] ?? 99;
                      if (pA != pB) return pA.compareTo(pB);
                      return a['name'].toString().compareTo(b['name'].toString());
                    });

            int totalSlots = math.max(60, (filteredItems.length ~/ 4 + 1) * 4);

            return Container(
              width: 530, padding: const EdgeInsets.all(12), decoration: BoxDecoration(gradient: const RadialGradient(center: Alignment(-0.5, -0.5), radius: 1.5, colors: [Color(0xFF3A3A3A), Color(0xFF0F0F0F)]), border: Border.all(color: const Color(0xFFD4AF37), width: 4), borderRadius: BorderRadius.circular(15)),
              child: Column(
                children: [
                  const Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.stars, color: Color(0xFFD4AF37), size: 20), SizedBox(width: 8), Text('KREFT 인벤토리', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFFD4AF37)))]),
                  const SizedBox(height: 10),
                  Container(padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10), decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade800)), child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [ _statText('💪 힘', totalP), _statText('🎯 컨트롤', totalC), _statText('📡 감도', totalS) ])),
                  const SizedBox(height: 10),
                  
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: ['ALL', 'FW', 'SEA', 'BAIT', 'FISH', 'SKIN'].map((filter) {
                      String label = filter == 'ALL' ? '전체' : filter == 'FW' ? '민물' : filter == 'SEA' ? '바다' : filter == 'BAIT' ? '미끼' : filter == 'FISH' ? '물고기' : '스킨';
                      bool isSelected = _currentFilter == filter; // 💡 바뀐 변수명 적용
                      return Expanded(
                        child: GestureDetector(
                          onTap: () { audioManager.playSfx('sfx_click.mp3'); setInvState(() => _currentFilter = filter); },
                          child: Container(margin: const EdgeInsets.symmetric(horizontal: 2), padding: const EdgeInsets.symmetric(vertical: 6), decoration: BoxDecoration(color: isSelected ? const Color(0xFFD4AF37) : Colors.black45, borderRadius: BorderRadius.circular(5), border: Border.all(color: isSelected ? Colors.white : Colors.grey.shade800)), child: Center(child: Text(label, style: TextStyle(color: isSelected ? Colors.black : Colors.grey, fontWeight: FontWeight.bold, fontSize: 12)))),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 10),

                  Expanded(
                    child: Scrollbar(
                      controller: _invScrollCtrl, thumbVisibility: true, thickness: 8, radius: const Radius.circular(10), // 💡 바뀐 변수명 적용
                      child: GridView.builder(
                        controller: _invScrollCtrl, gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 4, mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: 0.9), itemCount: totalSlots, 
                        itemBuilder: (context, index) {
                          Map<String, dynamic>? itemToShow;
                          if (index < filteredItems.length) itemToShow = filteredItems[index];
                          if (itemToShow == null) return Container(decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.white10)));

                          bool isCurrentlyEquipped = false; 
                          String iName = itemToShow['name'].toString();
                          if (equippedRod != null && equippedRod!['name'] == iName) isCurrentlyEquipped = true;
                          if (equippedFloat != null && equippedFloat!['name'] == iName) isCurrentlyEquipped = true;
                          if (equippedSkin != null && equippedSkin!['name'] == iName) isCurrentlyEquipped = true;
                          if (equippedBait != null && equippedBait!['name'] == iName) isCurrentlyEquipped = true;
                          if (equippedSunglasses != null && equippedSunglasses!['name'] == iName) isCurrentlyEquipped = true;
                          if (equippedBadge != null && equippedBadge!['name'] == iName) isCurrentlyEquipped = true;
                          if (equippedReel != null && equippedReel!['name'] == iName) isCurrentlyEquipped = true;
                          if (equippedCooler != null && equippedCooler!['name'] == iName) isCurrentlyEquipped = true;
                          if (equippedNet != null && equippedNet!['name'] == iName) isCurrentlyEquipped = true;
                          if (equippedBelt != null && equippedBelt!['name'] == iName) isCurrentlyEquipped = true;
                          if (equippedGloves != null && equippedGloves!['name'] == iName) isCurrentlyEquipped = true;
                          if (equippedLine != null && equippedLine!['name'] == iName) isCurrentlyEquipped = true;
                          if (equippedGroundbait != null && equippedGroundbait!['name'] == iName) isCurrentlyEquipped = true;
                          
                          return GestureDetector(
                            onTap: () {
                              if (itemToShow != null && itemToShow['category'] == 'TICKET') {
                                _useTicket(itemToShow!); 
                                return; 
                              }
                              _showEquipPopup(itemToShow!);
                            },
                            onDoubleTap: () => _quickEquipItem(itemToShow!),
                            child: Container(
                              decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(8), border: Border.all(color: isCurrentlyEquipped ? const Color(0xFFD4AF37) : Colors.grey.shade800, width: 2)), 
                              child: Stack(alignment: Alignment.center, children: [ 
                                Column(
                                  mainAxisAlignment: MainAxisAlignment.center, 
                                  children: [ 
                                    _getIconImagePath(itemToShow) != null
                                      ? ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.asset(_getIconImagePath(itemToShow)!, width: 75, height: 75, fit: BoxFit.contain, errorBuilder: (c, e, s) => const Icon(Icons.inventory_2, color: Colors.white30, size: 40)))
                                      : const Icon(Icons.inventory_2, color: Colors.white54, size: 40),
                                    const SizedBox(height: 6), 
                                    FittedBox(fit: BoxFit.scaleDown, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4.0), child: Text(itemToShow['name'], style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold), textAlign: TextAlign.center))) 
                                  ]
                                ), 
                                if (isCurrentlyEquipped) const Positioned(top: 4, right: 4, child: Icon(Icons.check_circle, color: Color(0xFFD4AF37), size: 18)),
                                if (itemToShow['quantity'] != null && (itemToShow['type'] == 'BAIT' || itemToShow['type'] == 'FISH'))
                                  Positioned(bottom: 4, right: 4, child: Container(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2), decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(4), border: Border.all(color: Colors.white54, width: 0.5)), child: Text('${itemToShow['quantity']}${itemToShow['type'] == 'FISH' ? '마리' : '개'}', style: const TextStyle(color: Colors.yellowAccent, fontSize: 10, fontWeight: FontWeight.bold))))
                              ])
                            )
                          );
                        }
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(children: [ 
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.black, 
                          foregroundColor: const Color(0xFFD4AF37), 
                          side: const BorderSide(color: Color(0xFFD4AF37), width: 2),
                          padding: const EdgeInsets.symmetric(vertical: 18),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))
                        ),
                        onPressed: () {
                          audioManager.playSfx("sfx_click.mp3");
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => StoreScreen(
                                currentGold: myGold,
                                currentLevel: myLevel,
                                currentInventory: inventory,
                                currentRank: _myRank
                              )
                            )
                          );
                        },
                        child: const Text('🛒 KREFT 상점', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16))
                      )
                    ), 
      ], 
    ), 
  ], 
), 
);
          }
        );
      },
    );
  }

  // ⚡ [자동 장착] 현재 맵에 맞는 최고 효율 장비로 자동 세팅 (출조 셋팅 패널에서 호출)
  void _runAutoEquip({bool silent = false}) {
    // 🛡️ [아레나 검문소] 대회 중에는 자동 장착 금지!
    if (widget.roomId != null) {
      if (!silent) _showNotificationPopup('🚫 장착 불가!', '아레나(대회) 중에는 제공된 대회용 장비만 사용해야 합니다!', Colors.redAccent);
      return;
    }
    if (!silent) audioManager.playSfx("sfx_click.mp3");
    setState(() {
      List<dynamic> validItems = _latestInventory.where((item) {
        String cat = item['category'] ?? '';
        if (widget.isSea && cat == 'FW') return false;
        if (!widget.isSea && cat == 'SEA') return false;
        return true;
      }).toList();

      equippedRod = null; equippedFloat = null; equippedBait = null;
      equippedSunglasses = null; equippedBadge = null; equippedSkin = null; equippedReel = null; equippedCooler = null;
      equippedNet = null; equippedBelt = null; equippedGloves = null; equippedLine = null; equippedGroundbait = null;

      Map<String, dynamic>? bestSkin; Map<String, dynamic>? bestBait; Map<String, dynamic>? bestFloat; Map<String, dynamic>? bestRod; Map<String, dynamic>? bestReel; Map<String, dynamic>? bestCooler;
      int maxBaitQty = -1;
      int getCoolerTier(String name) { if (name.contains('대형')) return 3; if (name.contains('중형')) return 2; if (name.contains('소형')) return 1; return 1; }

      int getSkinTier(String name) { if (name.contains('마스터')) return 5; if (name.contains('프로') || name.contains('고수')) return 4; if (name.contains('중수')) return 3; if (name.contains('하수') || name.contains('초보')) return 2; return 1; }
      int getRodTier(String name) { String n = name.replaceAll(' ', '').replaceAll('-', '').toUpperCase(); if (n.contains('KT40')) return 60; if (n.contains('KT30')) return 50; if (n.contains('KT20')) return 40; if (n.contains('CF40')) return 30; if (n.contains('CF30')) return 20; if (n.contains('CF20')) return 10; return 1; }
      int getFloatTier(String name) { String n = name.replaceAll(' ', '').toUpperCase(); if (n.contains('KT전자')) return 60; if (n.contains('CF전자')) return 50; if (n.contains('나노')) return 40; if (n.contains('수제')) return 30; if (n.contains('오동')) return 20; return 1; }
      int getSeaRodTier(String name) { String n = name.replaceAll(' ', '').toUpperCase(); if (n.contains('KT500')) return 60; if (n.contains('KT350')) return 50; if (n.contains('KT250')) return 40; if (n.contains('CF500')) return 30; if (n.contains('CF350')) return 20; if (n.contains('CF250')) return 10; return 1; }
      int getReelTier(String name) { String n = name.replaceAll(' ', '').toUpperCase(); if (n.contains('KF8000')) return 80; if (n.contains('KF6000')) return 60; if (n.contains('KF5000')) return 50; if (n.contains('CF5000')) return 40; if (n.contains('CF3000')) return 30; return 1; }

      for (var item in validItems) {
        String name = item['name'].toString();
        if (name.contains('스킨') || name.contains('조사') || name.contains('마스터')) { if (bestSkin == null || getSkinTier(name) > getSkinTier(bestSkin!['name'].toString())) { bestSkin = item; } }
        else if (name.contains('찌')) { if (bestFloat == null || getFloatTier(name) > getFloatTier(bestFloat!['name'].toString())) { bestFloat = item; } }
        else if (item['type'] == 'COOLER' || name.contains('아이스박스') || name.contains('쿨러') || name.contains('보냉')) { if (bestCooler == null || getCoolerTier(name) > getCoolerTier(bestCooler!['name'].toString())) { bestCooler = item; } }
        else if (item['type'] == 'REEL' || name.contains('000') || name.contains('릴')) { if (bestReel == null || getReelTier(name) > getReelTier(bestReel!['name'].toString())) { bestReel = item; } }
        else if ((name.contains('대') || name.contains('CF') || name.contains('KT')) && !name.contains('찌') && !name.contains('릴') && !name.contains('아이스박스') && !name.contains('쿨러') && !name.contains('보냉')) {
          bool isSeaRod = name.contains('250') || name.contains('350') || name.contains('500');
          if (widget.isSea) { if (isSeaRod) { if (bestRod == null || getSeaRodTier(name) > getSeaRodTier(bestRod!['name'].toString())) { bestRod = item; } } }
          else { if (!isSeaRod) { if (bestRod == null || getRodTier(name) > getRodTier(bestRod!['name'].toString())) { bestRod = item; } } }
        }
        else if (name.contains('선글라스') && equippedSunglasses == null) { equippedSunglasses = item; }
        else if (name.contains('휘장')) { if (widget.isSea && name.contains('바다')) equippedBadge = item; if (!widget.isSea && name.contains('민물')) equippedBadge = item; }
        else if (name.contains('뜰채') && equippedNet == null) { equippedNet = item; }
        else if (name.contains('벨트') && equippedBelt == null) { equippedBelt = item; }
        else if (name.contains('장갑') && equippedGloves == null) { equippedGloves = item; }
        else if (name.contains('낚시줄') && equippedLine == null) { equippedLine = item; }
        else if (name.contains('밑밥') && equippedGroundbait == null) { equippedGroundbait = item; }
        else if (name.contains('미끼') || name.contains('지렁이') || name.contains('글루텐') || name.contains('옥수수') || name.contains('크릴') || name.contains('에기')) {
          int qty = item['quantity'] as int? ?? 0;
          if (qty > maxBaitQty) { maxBaitQty = qty; bestBait = item; }
        }
      }
      equippedSkin = bestSkin;
      equippedBait = bestBait;
      equippedRod = bestRod;
      equippedReel = bestReel;
      equippedFloat = bestFloat;
      equippedCooler = bestCooler; // 🧊 아이스박스 자동 장착
      isRodEquipped = equippedRod != null;

      if (widget.isSea) {
        selectedRodCount = 1;
      } else {
        int autoMaxRods = 2;
        String skinName = equippedSkin != null ? equippedSkin!['name'].toString() : '초보';

        if (skinName.contains('마스터')) autoMaxRods = 14;
        else if (skinName.contains('프로')) autoMaxRods = 10;
        else if (skinName.contains('고수')) autoMaxRods = 8;
        else if (skinName.contains('중수')) autoMaxRods = 6;
        else if (skinName.contains('하수')) autoMaxRods = 4;

        selectedRodCount = autoMaxRods;
      }
    });

    if (!silent) _showNotificationPopup('⚡ 세팅 완료!', '현재 맵에 맞는 최고 효율 장비로\n완벽하게 세팅되었습니다. (대편성: $selectedRodCount대)', const Color(0xFFD4AF37));
  }

  void _showNotificationPopup(String title, String content, Color color, {VoidCallback? onConfirm}) {
    showDialog(
      context: context, barrierDismissible: false, 
      builder: (context) => AlertDialog(backgroundColor: Colors.grey.shade900, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15), side: BorderSide(color: color, width: 2)), title: Text(title, style: TextStyle(color: color, fontWeight: FontWeight.bold), textAlign: TextAlign.center), content: Text(content, style: const TextStyle(color: Colors.white, fontSize: 16), textAlign: TextAlign.center), actions: [ Center(child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: color, foregroundColor: Colors.black), onPressed: () { audioManager.playSfx("sfx_click.mp3"); Navigator.pop(context); if (onConfirm != null) onConfirm(); }, child: const Text('확인', style: TextStyle(fontWeight: FontWeight.bold)))) ]),
    );
  }

  void _showEquipPopup(Map<String, dynamic> item) {
    // 🛡️ [아레나 검문소] 대회 중에는 장비 변경 금지! (제공된 대회용 장비만 사용 → 완전 평준화 유지)
    if (widget.roomId != null) {
      _showNotificationPopup('🚫 장착 불가!', '아레나(대회) 중에는 제공된 대회용 장비만 사용해야 합니다!', Colors.redAccent);
      return;
    }
    // 🐟 잡은 물고기는 미끼 슬롯에 못 들어감(고등어만 참치용 생미끼로 예외)
    if ((item['type'] ?? '') == 'FISH' && !item['name'].toString().contains('고등어')) {
      _showNotificationPopup('미끼 불가 🐟', '잡은 물고기는 미끼로 쓸 수 없어요.\n(참치용 생미끼는 고등어만 가능)', Colors.orangeAccent);
      return;
    }
    audioManager.playSfx("sfx_click.mp3");
    String category = item['category'] ?? '';
    if (widget.isSea && category == 'FW') { _showNotificationPopup('착용 불가 🚫', '바다 낚시터에서는 민물 장비/미끼를 쓸 수 없습니다!', Colors.redAccent); return; }
    if (!widget.isSea && category == 'SEA') { _showNotificationPopup('착용 불가 🚫', '민물 낚시터에서는 바다 장비/미끼를 쓸 수 없습니다!', Colors.redAccent); return; }

    // 🚨 [핵심 패치] 현재 장착 중인 아이템인지 체크!
    bool isEquipped = false;
    String iName = item['name'].toString();
    if (equippedRod?['name'] == iName) isEquipped = true;
    if (equippedFloat?['name'] == iName) isEquipped = true;
    if (equippedSkin?['name'] == iName) isEquipped = true;
    if (equippedBait?['name'] == iName) isEquipped = true;
    if (equippedSunglasses?['name'] == iName) isEquipped = true;
    if (equippedBadge?['name'] == iName) isEquipped = true;
    if (equippedReel?['name'] == iName) isEquipped = true;
    if (equippedCooler?['name'] == iName) isEquipped = true;
    if (equippedNet?['name'] == iName) isEquipped = true;
    if (equippedBelt?['name'] == iName) isEquipped = true;
    if (equippedGloves?['name'] == iName) isEquipped = true;
    if (equippedLine?['name'] == iName) isEquipped = true;
    if (equippedGroundbait?['name'] == iName) isEquipped = true;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey.shade900, 
        // 장착 중이면 테두리 빨간색, 아니면 금색
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15), side: BorderSide(color: isEquipped ? Colors.redAccent : const Color(0xFFD4AF37))),
        title: Text(isEquipped ? '🔓 장착 해제' : '🎧 아이템 장착', style: TextStyle(color: isEquipped ? Colors.redAccent : const Color(0xFFD4AF37), fontWeight: FontWeight.bold)),
        content: Text('${item['name']}\n\n${item['desc'] ?? ''}\n${item['stats'] ?? ''}\n\n이 아이템을 ${isEquipped ? '해제' : '장착'}하시겠습니까?', style: const TextStyle(color: Colors.white)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('취소', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            // 장착 중이면 빨간색 버튼, 아니면 금색 버튼
            style: ElevatedButton.styleFrom(backgroundColor: isEquipped ? Colors.redAccent : const Color(0xFFD4AF37), foregroundColor: isEquipped ? Colors.white : Colors.black),
            onPressed: () {
              audioManager.playSfx("sfx_click.mp3");
              setState(() {
                String cleanName = iName.replaceAll(' ', '').toUpperCase();
                
                if (isEquipped) {
                  // 🗑️ [벗기] 장착 해제 로직
                  if (cleanName.contains('찌')) equippedFloat = null; 
                  else if (cleanName.contains('스킨') || cleanName.contains('조사') || cleanName.contains('초보') || cleanName.contains('마스터')) equippedSkin = null; 
                  else if ((cleanName.contains('릴') && !cleanName.contains('크릴')) || cleanName.contains('2000') || cleanName.contains('3000') || cleanName.contains('5000') || cleanName.contains('6000') || cleanName.contains('8000')) equippedReel = null; 
                  else if ((cleanName.contains('대') || cleanName.contains('CF') || cleanName.contains('KT')) && !cleanName.contains('아이스박스') && !cleanName.contains('쿨러') && !cleanName.contains('보냉')) { equippedRod = null; isRodEquipped = false; } 
                  else if (cleanName.contains('선글라스')) equippedSunglasses = null;
                  else if (cleanName.contains('휘장')) equippedBadge = null;
                  else if (cleanName.contains('아이스박스') || cleanName.contains('쿨러') || cleanName.contains('보냉')) equippedCooler = null;
                  else if (cleanName.contains('뜰채')) equippedNet = null;
                  else if (cleanName.contains('벨트')) equippedBelt = null;
                  else if (cleanName.contains('장갑')) equippedGloves = null;
                  else if (cleanName.contains('낚시줄')) equippedLine = null;
                  else if (cleanName.contains('밑밥')) { equippedGroundbait = null; _groundbaitActive = false; }
                  else equippedBait = null;
                } else {
                  // 🎒 [입기] 기존 장착 로직
                  if (cleanName.contains('찌')) { equippedFloat = item; } 
                  else if (cleanName.contains('스킨') || cleanName.contains('조사') || cleanName.contains('초보') || cleanName.contains('마스터')) { equippedSkin = item; } 
                  else if ((cleanName.contains('릴') && !cleanName.contains('크릴')) || cleanName.contains('2000') || cleanName.contains('3000') || cleanName.contains('5000') || cleanName.contains('6000') || cleanName.contains('8000')) { equippedReel = item; } 
                  else if ((cleanName.contains('대') || cleanName.contains('CF') || cleanName.contains('KT')) && !cleanName.contains('아이스박스') && !cleanName.contains('쿨러') && !cleanName.contains('보냉')) { equippedRod = item; isRodEquipped = true; } 
                  else if (cleanName.contains('선글라스')) { equippedSunglasses = item; }
                  else if (cleanName.contains('휘장')) { equippedBadge = item; }
                  else if (cleanName.contains('아이스박스') || cleanName.contains('쿨러') || cleanName.contains('보냉')) { equippedCooler = item; }
                  else if (cleanName.contains('뜰채')) { equippedNet = item; }
                  else if (cleanName.contains('벨트')) { equippedBelt = item; }
                  else if (cleanName.contains('장갑')) { equippedGloves = item; }
                  else if (cleanName.contains('낚시줄')) { equippedLine = item; }
                  else if (cleanName.contains('밑밥')) { equippedGroundbait = item; }
                  else { equippedBait = item; }
                }
              });
              Navigator.pop(context);
            },
            child: Text(isEquipped ? '해제하기' : '장착하기', style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _quickEquipItem(Map<String, dynamic> item) {
    // 🛡️ [아레나 검문소] 대회 중에는 장비 변경 금지! (완전 평준화 유지)
    if (widget.roomId != null) {
      _showNotificationPopup('🚫 장착 불가!', '아레나(대회) 중에는 제공된 대회용 장비만 사용해야 합니다!', Colors.redAccent);
      return;
    }
    // 🐟 잡은 물고기는 미끼 슬롯에 못 들어감(고등어만 참치용 생미끼로 예외)
    if ((item['type'] ?? '') == 'FISH' && !item['name'].toString().contains('고등어')) {
      _showNotificationPopup('미끼 불가 🐟', '잡은 물고기는 미끼로 쓸 수 없어요.\n(참치용 생미끼는 고등어만 가능)', Colors.orangeAccent);
      return;
    }
    String category = item['category'] ?? '';
    if (widget.isSea && category == 'FW') { _showNotificationPopup('착용 불가 🚫', '바다 낚시터에서는 민물 장비를 쓸 수 없습니다!', Colors.redAccent); return; }
    if (!widget.isSea && category == 'SEA') { _showNotificationPopup('착용 불가 🚫', '민물 낚시터에서는 바다 장비를 쓸 수 없습니다!', Colors.redAccent); return; }
    audioManager.playSfx("sfx_click.mp3"); 

    setState(() {
      String cleanName = item['name'].toString().replaceAll(' ', '').toUpperCase();
      if (cleanName.contains('찌')) equippedFloat = item;
      else if (cleanName.contains('스킨') || cleanName.contains('조사') || cleanName.contains('초보') || cleanName.contains('마스터')) equippedSkin = item;
      else if ((cleanName.contains('릴') && !cleanName.contains('크릴')) || cleanName.contains('2000') || cleanName.contains('3000') || cleanName.contains('5000') || cleanName.contains('6000') || cleanName.contains('8000')) equippedReel = item;
      else if ((cleanName.contains('대') || cleanName.contains('CF') || cleanName.contains('KT')) && !cleanName.contains('아이스박스') && !cleanName.contains('쿨러') && !cleanName.contains('보냉')) { equippedRod = item; isRodEquipped = true; }
      else if (cleanName.contains('선글라스')) equippedSunglasses = item;
      else if (cleanName.contains('휘장')) equippedBadge = item;
      else if (cleanName.contains('아이스박스') || cleanName.contains('쿨러') || cleanName.contains('보냉')) equippedCooler = item;
      else if (cleanName.contains('뜰채')) equippedNet = item;
      else if (cleanName.contains('벨트')) equippedBelt = item;
      else if (cleanName.contains('장갑')) equippedGloves = item;
      else if (cleanName.contains('낚시줄')) equippedLine = item;
      else if (cleanName.contains('밑밥')) equippedGroundbait = item;
      else equippedBait = item;
    });
    _showNotificationPopup('⚡ 장착 완료!', '${item['name']} 장비가\n완벽하게 세팅되었습니다.', const Color(0xFFD4AF37));
  }

  void _showLevelUpPopup(int newLevel) {
    audioManager.playSfx("sfx_landing_success.mp3"); 
    showDialog(
      context: context, barrierDismissible: false, 
      builder: (context) => AlertDialog(
        backgroundColor: Colors.black.withOpacity(0.9),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: Color(0xFFD4AF37), width: 3)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.stars, color: Colors.yellowAccent, size: 70), 
            const SizedBox(height: 15),
            const Text('LEVEL UP!!!', style: TextStyle(color: Color(0xFFD4AF37), fontSize: 40, fontWeight: FontWeight.w900, fontStyle: FontStyle.italic, shadows: [Shadow(color: Colors.white24, blurRadius: 10)])),
            const SizedBox(height: 10),
            Text('Lv.$newLevel 달성!', style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(10)), child: const Text('💪 힘·🎯컨트롤·📡감도 각 +1 상승! (제압력 +3)\n더 큰 대물에 도전하세요!', style: TextStyle(color: Colors.cyanAccent, fontSize: 15, height: 1.5), textAlign: TextAlign.center)),
            const SizedBox(height: 20),
            ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFD4AF37), foregroundColor: Colors.black, padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))), onPressed: () => Navigator.pop(context), child: const Text('확인', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18))),
          ],
        ),
      ),
    );
  }

void _showTodayMissionInfo() {
  DateTime now = DateTime.now();
  int dailySeed = now.year * 10000 + now.month * 100 + now.day;
  var dailyRandom = math.Random(dailySeed);
  
  final List<Map<String, dynamic>> missionPool = [
    // game_config의 미션 풀과 동일하게
  ];
  
  final mission = missionPool[dailyRandom.nextInt(missionPool.length)];
  
  // 이미 오늘 달성했는지 확인 후 안내
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: Colors.black87,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(15),
        side: const BorderSide(color: Color(0xFFD4AF37), width: 2),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset('assets/images/npc_manager.png', width: 120),
          const SizedBox(height: 10),
          const Text('📢 오늘의 미션!', style: TextStyle(color: Color(0xFFD4AF37), fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          Text('${mission['fish']} ${mission['count']}마리를 잡으세요!\n(어느 낚시터든 OK)\n\n완료 시 🏆 ${mission['prize']}P 지급!',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 16, height: 1.6)),
        ],
      ),
      actions: [
        Center(child: ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFD4AF37), foregroundColor: Colors.black),
          onPressed: () => Navigator.pop(ctx),
          child: const Text('확인!', style: TextStyle(fontWeight: FontWeight.bold)),
        ))
      ],
    ),
  );
}
  // ==========================================================
  // 🏆 오늘의 선착순 미션 심판 로직 (KREFT 매니저 아라의 임무!)
  // ==========================================================
  Future<void> _checkDailyMission(String fishName) async {
    // 📋 일일 2분리: 민물 미션 먼저 완료 → 바다 미션 진행. 각 보상 dailyMissionPrize.
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final fw = getTodayFwMission();
    final sea = getTodaySeaMission();
    final isFwTarget = fishName == fw['fish'];
    final isSeaTarget = fishName == sea['fish'];
    if (!isFwTarget && !isSeaTarget) return; // 오늘 미션 어종이 아니면 무시
    final need = dailyMissionCount;
    final prize = dailyMissionPrize;
    final userRef = FirebaseFirestore.instance.collection('users').doc(user.uid);

    try {
      Map<String, dynamic>? completed; // 방금 완료한 미션(팝업용)
      await FirebaseFirestore.instance.runTransaction((tx) async {
        final data = (await tx.get(userRef)).data() ?? {};
        final mp = data['mission_progress'];
        int fwCount = 0, seaCount = 0; bool fwDone = false, seaDone = false;
        if (mp is Map && mp['date'] == today) {
          fwCount = (mp['fw'] is num) ? (mp['fw'] as num).toInt() : 0;
          seaCount = (mp['sea'] is num) ? (mp['sea'] as num).toInt() : 0;
          fwDone = mp['fwDone'] == true;
          seaDone = mp['seaDone'] == true;
        }
        // 1) 민물 미션 먼저
        if (isFwTarget && !fwDone) {
          fwCount += 1;
          final done = fwCount >= need;
          tx.set(userRef, {
            if (done) 'gold': FieldValue.increment(prize),
            'mission_progress': {'date': today, 'fw': fwCount, 'fwDone': done, 'sea': seaCount, 'seaDone': seaDone},
          }, SetOptions(merge: true));
          if (done) completed = {'fish': fw['fish'], 'count': need, 'cat': '민물', 'prize': prize};
          return;
        }
        // 2) 민물 완료 후 바다 미션
        if (isSeaTarget && fwDone && !seaDone) {
          seaCount += 1;
          final done = seaCount >= need;
          tx.set(userRef, {
            if (done) 'gold': FieldValue.increment(prize),
            'mission_progress': {'date': today, 'fw': fwCount, 'fwDone': fwDone, 'sea': seaCount, 'seaDone': done},
          }, SetOptions(merge: true));
          if (done) completed = {'fish': sea['fish'], 'count': need, 'cat': '바다', 'prize': prize};
          return;
        }
      });

      if (completed != null && mounted) {
        _showMissionWinnerPopup(completed!); // 완료 축하 팝업 (보상은 이미 지급됨)
      }
    } catch (e) {
      print("미션 트랜잭션 에러: $e");
    }
  }

  // 🐟 잡은 고기를 가방에 '마리'로 보관 (어종별 누적). 보배에게 팔거나 일일 정산에 사용.
  Future<void> _storeCaughtFish(String fishName) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final fishImg = fishImageByName(fishName);
    if (fishImg.isEmpty) return; // 이미지 없는 어종은 스킵(안전)
    final userRef = FirebaseFirestore.instance.collection('users').doc(user.uid);
    try {
      bool claimedToday = false;
      int caughtToday = 0;
      final today = DateTime.now().toIso8601String().substring(0, 10);
      final bobaeFish = getTodayBobaeFish()['fish'];
      await FirebaseFirestore.instance.runTransaction((tx) async {
        final data = (await tx.get(userRef)).data() ?? {};
        final bp = data['bobae_progress'];
        final sameDay = bp is Map && bp['date'] == today;
        claimedToday = sameDay && bp['claimed'] == true; // 오늘 이미 정산?
        // 인벤 보관(판매·보유용)
        final inv = List<dynamic>.from(data['inventory'] ?? []);
        final idx = inv.indexWhere((i) => i['name'] == fishName && (i['type'] ?? '') == 'FISH');
        if (idx >= 0) {
          inv[idx]['quantity'] = (inv[idx]['quantity'] ?? 0) + 1;
        } else {
          inv.add({'name': fishName, 'category': 'FISH', 'type': 'FISH', 'icon': fishImg, 'quantity': 1, 'desc': '낚시로 잡은 $fishName 🐟 (서윤에게 판매 가능)'});
        }
        // 🛍️ 서윤 일일: '오늘 새로 잡은' 지정 어종만 카운트 (날짜 바뀌면 0부터)
        int caught = sameDay ? (((bp['caught'] ?? 0) as num).toInt()) : 0;
        if (fishName == bobaeFish) caught += 1;
        caughtToday = caught;
        tx.set(userRef, {
          'inventory': inv,
          'bobae_progress': {'date': today, 'caught': caught, 'claimed': sameDay ? (bp['claimed'] == true) : false},
        }, SetOptions(merge: true));
      });
      // 오늘 지정 어종을 새로 딱 3마리 잡으면 안내 (오늘 이미 정산했으면 안 뜸)
      if (mounted && !claimedToday && fishName == bobaeFish && caughtToday == bobaeCount) {
        _showNotificationPopup('🐟 서윤 의뢰 달성!', '$fishName $bobaeCount마리를 잡았어요!\n광장의 서윤에게 가서 정산받으세요!', const Color(0xFFD4AF37));
      }
    } catch (e) {
      print('물고기 보관 에러: $e');
    }
  }

  // 🏆 미션 정보(mission)를 받아서 알아서 글자를 바꿔치기 하는 팝업창!
  void _showMissionWinnerPopup(Map<String, dynamic> mission) {
    audioManager.playSfx("sfx_landing_success.mp3");
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.black.withOpacity(0.95),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Color(0xFFD4AF37), width: 2.5),
        ),
        contentPadding: const EdgeInsets.fromLTRB(25, 25, 25, 15),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 🎉 아라 매니저 등장
            Image.asset('assets/images/npc_manager.png', width: 150),
            const SizedBox(height: 16),
            const Text('🎉 축하합니다! 🎉', style: TextStyle(color: Color(0xFFD4AF37), fontSize: 24, fontWeight: FontWeight.w900)),
            const SizedBox(height: 12),
            Text(
              '[${widget.nickname}] 조사님!\n오늘의 ${mission['fish']} ${mission['count']}마리 미션을\n완료하셨습니다!',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold, height: 1.5),
            ),
            const SizedBox(height: 18),
            // 💰 상금 강조 박스
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              decoration: BoxDecoration(
                color: const Color(0xFFD4AF37).withOpacity(0.15),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFD4AF37), width: 2),
              ),
              child: Column(
                children: [
                  const Text('보상이 지급되었습니다 💰', style: TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  Text('+ ${mission['prize']} P', style: const TextStyle(color: Colors.yellowAccent, fontSize: 30, fontWeight: FontWeight.w900)),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Text('내일의 미션도 기대해 주세요! 🎣', textAlign: TextAlign.center, style: TextStyle(color: Colors.white54, fontSize: 13, fontWeight: FontWeight.bold)),
          ],
        ),
        actions: [
          Center(
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFD4AF37), foregroundColor: Colors.black),
              onPressed: () => Navigator.pop(ctx), // 보상은 트랜잭션에서 이미 지급됨
              child: const Text('확인', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ),
          )
        ],
      ),
    );
  }

  void _showResultPopup(Map<String, dynamic> caughtFish) {
    audioManager.stopBgm(); // 🔇 BGM 정지
    audioManager.stopEfx(); // 🔇 물소리 즉시 정지!
    String imagePath = caughtFish['img'] ?? '';
    imagePath = imagePath.replaceAll('assets/images/fish_fw', 'assets/fish_fw/fish_fw');
    imagePath = imagePath.replaceAll('assets/images/fish_sea', 'assets/fish_sea/fish_sea');

    showDialog(
      context: context, barrierDismissible: false, 
      builder: (context) => AlertDialog(
        backgroundColor: Colors.black.withOpacity(0.95), 
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: Color(0xFFD4AF37), width: 2.5)), 
        contentPadding: const EdgeInsets.all(25),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('HIT !!!', style: TextStyle(color: Colors.redAccent, fontSize: 45, fontWeight: FontWeight.w900, fontStyle: FontStyle.italic, shadows: [Shadow(color: Colors.black, blurRadius: 10, offset: Offset(2, 2))])),
            const SizedBox(height: 15),
            Container(decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.white24)), padding: const EdgeInsets.all(10), child: Image.asset(imagePath, height: 160, fit: BoxFit.contain, errorBuilder: (c,e,s) { return const Icon(Icons.set_meal, color: Colors.white54, size: 100); })),
            const SizedBox(height: 15),
            Text('${caughtFish['name']}', style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold)),
            Text('${caughtFish['size']} ${caughtFish['unit']}', style: const TextStyle(color: Colors.cyanAccent, fontSize: 38, fontWeight: FontWeight.w900)),
            const SizedBox(height: 10),
            // ⚔️ 아레나는 exp·포인트를 주지 않음(대회 상금이 보상) → 대회 기록만 표시
            if (widget.roomId != null)
              Builder(builder: (_) {
                final bool isMax = widget.winCondition == '최대어';
                final bool counts = !isMax
                    || widget.targetFish == null
                    || widget.targetFish == '모든 어종'
                    || caughtFish['name'].toString() == widget.targetFish;
                final String txt = !counts
                    ? '🎣 이 어종은 최대어 기록 대상이 아니에요'
                    : (isMax
                        ? '🏆 최대어 기록! ${caughtFish['size']}${caughtFish['unit']}'
                        : '🏆 대회 기록 반영! (마릿수 +1)');
                return Text(txt,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Color(0xFFD4AF37), fontSize: 18, fontWeight: FontWeight.bold));
              })
            else
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('+ ${caughtFish['exp']} EXP', style: const TextStyle(color: Colors.lightGreenAccent, fontSize: 22, fontWeight: FontWeight.bold)),
                  if ((caughtFish['pts'] ?? 0) > 0) ...[
                    const SizedBox(width: 15),
                    Text('+ ${caughtFish['pts']} Pts', style: const TextStyle(color: Colors.yellowAccent, fontSize: 22, fontWeight: FontWeight.bold)),
                  ]
                ],
              ),
          ]
        ),
        actionsAlignment: MainAxisAlignment.spaceEvenly,
        actions: [
         
          (widget.title != widget.locationName)
              ? ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueGrey.shade800,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () {
                    audioManager.playSfx("sfx_click.mp3");
                    // 💡 준비 중 문구는 지우고, 만들어둔 실시간 팝업 함수를 바로 호출!
                    _showRankingPopup(context, widget.roomId!, widget.isSea, widget.winCondition);
                  },
                  icon: const Icon(Icons.leaderboard, size: 18),
                  label: const Text('현재 순위'),
                )
              : ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.grey.shade800,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () {
                    audioManager.playSfx("sfx_click.mp3");
                    Navigator.pop(context); // 결과 팝업 닫고
                    _openMoveSpotList(); // 🗺️ 낚시터 리스트 열기(이동 또는 광장으로)
                  },
                  icon: const Icon(Icons.map, size: 18),
                  label: const Text('낚시터 이동'),
                ),
          // 👆 딱 여기까지입니다! 
          // 🚨 주의: 바로 밑에 있는 1895번 줄 `ElevatedButton(` (캐스팅 버튼)은 1mm도 건드리지 마세요!
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFD4AF37), foregroundColor: Colors.black),
            onPressed: () {
              Navigator.pop(context); 
              audioManager.playSfx("sfx_click.mp3"); 
              
              setState(() {
                isFighting = false; 
                
                // 🚨 [핵심 수정] 기존에 있던 isFloatInWater = false; 를 아예 지웠습니다!
                // 다른 낚싯대들의 찌는 물에 계속 떠 있어야 하니까요!
                isCasting = true; // 캐스팅 폼만 잡습니다.
              });

              // 🎣 낚싯대 휘두르는 소리와 애니메이션 실행
              audioManager.playSfx("sfx_casting.mp3"); 
              audioManager.playBgm(widget.isSea ? "bgm_sea_fishing.mp3" : "bgm_fresh_fishing.mp3"); // 🔊 BGM 재개!
               _castController.forward(from: 0.0);

              // ⏳ 1.5초 후 찌 안착 및 타이머 재시작
              Future.delayed(const Duration(milliseconds: 1500), () {
                if (mounted) {
                  setState(() {
                    isCasting = false;
                    isFloatInWater = true; if (widget.isFirstTime && !_isTutorialDone) _fishingStep = 4; // 안전장치 유지
                  });
                  
                  // 🎯 전투 종료 → 바다와 같은 간격으로 다음 입질(랜덤 찌) 재개
                  if (fightingRodIndex != null) {
                    fightingRodIndex = null;
                    _scheduleNextBite();
                  }
                }
              });
            },
            child: const Text('캐스팅', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      )
    );
  }
}

// 🎣 KREFT 다이내믹 파이팅 시스템 (오버레이)
// 🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩
class FishingFightingOverlay extends StatefulWidget {
  final Map<String, dynamic> fish;
  final double playerTotalStats;
  final int locationStars;
  final Function(bool, double) onFinished;
  final String rodImageSuffix; // 🎣 장착 낚싯대별 파이팅 그림 접미사('' = 기본)
  const FishingFightingOverlay({
    super.key, required this.fish, required this.playerTotalStats,
    required this.locationStars, required this.onFinished,
    this.rodImageSuffix = '',
  });
  @override
  State<FishingFightingOverlay> createState() => _FishingFightingOverlayState();
}

class _FishingFightingOverlayState extends State<FishingFightingOverlay> with TickerProviderStateMixin {
  final ValueNotifier<double> gaugeNotifier = ValueNotifier(0.5);
  final ValueNotifier<int> timeNotifier = ValueNotifier(30);
  final ValueNotifier<int> fishGearNotifier = ValueNotifier(0);
  
  final ValueNotifier<int> playerGearNotifier = ValueNotifier(1);
  final ValueNotifier<bool> penaltyNotifier = ValueNotifier(false);

  bool isPressing = false;
  Timer? gameTimer;
  DateTime? lastReleaseTime;
  DateTime? lastSoundTime;
  bool _isGameOver = false;

  int fishSkillDuration = 0;
  double fishCurrentMove = 0.0;
  math.Random random = math.Random();
  late AnimationController _rodController;

  @override
  void initState() {
    super.initState();
    _rodController = AnimationController(vsync: this, duration: const Duration(milliseconds: 250))..repeat(reverse: true);
    _prepareFishStats();
    _startGame();
  }

  void _prepareFishStats() {
  try {
    double size = double.tryParse(widget.fish['size'].toString()) ?? 20.0;
    
    // 🎣 [어종별 최대어 사이즈 테이블]
    final Map<String, double> fishMaxSize = {
      '붕어': 55.0, '떡붕어': 55.0, '블루길': 25.0, '살치': 25.0,
      '베스': 55.0, '강준치': 55.0, '잉어': 120.0, '자라': 25.0,
      '메기': 150.0, '가물치': 120.0,
      '고등어': 80.0, '우럭': 70.0, '갈치': 150.0, '참돔': 120.0,
      '벵에돔': 60.0, '갑오징어': 55.0, '주꾸미': 30.0, '광어': 120.0,
      '감성돔': 80.0, '문어': 120.0, '참치': 200.0,
    };
    
    String fishName = widget.fish['name']?.toString() ?? '';
    double maxSize = fishMaxSize[fishName] ?? 100.0;
    
    // 🎯 [#14] 절대 크기 위주 + 종별 상대크기 보조 → 큰 고기가 항상 더 힘셈(현실 반영)
    //    (예: 45cm 메기 > 11.8cm 블루길). 트로피(종별 만대)는 상대크기로 가산.
    double sizeRatio = size / maxSize;        // 종별 상대(트로피)
    // 🐟 큰 고기 힘 압축: 60cm까지는 사이즈대로, 그 위로는 절반만 힘에 반영.
    //    (120~200cm 어종이 과도하게 세지는 걸 방지 — 붕어 55cm 등 중소형은 영향 없음)
    const double capCm = 60.0, overRate = 0.5;
    double effSize = size <= capCm ? size : capCm + (size - capCm) * overRate;
    double absFactor = effSize / 120.0;       // 절대 크기 (압축 적용)
    double resistancePower = absFactor * 0.7 + math.pow(sizeRatio, 2.0).toDouble() * 0.3;
    
    // safeStats 먼저
double safeStats = (widget.playerTotalStats.isNaN || 
                    widget.playerTotalStats.isInfinite) 
                    ? 1000.0 : widget.playerTotalStats.toDouble();

// 물고기 고유 저항력 = 사이즈(종)로만 결정. 낚시터 ★·내 제압력과 무관!
// 같은 사이즈면 어디서 잡든 같은 힘. ★는 '어떤 사이즈가 나오냐'만 정함(큰 고기 = 자연히 힘셈).
double fishBasePower = math.pow(resistancePower, 2.0).toDouble() * 4000.0;

double powerDiff = fishBasePower - safeStats;

if (powerDiff > 500) fishCurrentMove = 0.015 + (powerDiff / 30000);
else if (powerDiff > 0) fishCurrentMove = 0.002 + (powerDiff / 20000);
else fishCurrentMove = math.max(0.001, 0.002 + powerDiff / 60000); // 🐛FIX: 내가 강할수록 느려짐(쉬움). 기존 -powerDiff는 역전 버그(압도할수록 더 빨라짐)

  } catch (e) {
    fishCurrentMove = 0.005;
  }
}

  bool _isFishFacingRight = true; // 🐟 물고기 머리 방향 기억 장치! (기본은 오른쪽)

  void _startGame() {
    gameTimer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
      try {
        if (!mounted || _isGameOver) {
          timer.cancel();
          return;
        }

        bool isFinished = false;
        bool isWin = false;

        if (timer.tick % 20 == 0) {
          timeNotifier.value--;
          if (timeNotifier.value <= 0) { isFinished = true; isWin = gaugeNotifier.value >= 0.5; }
        }

        // 🔊 [사운드 패치] 버튼을 꾹 누르고(당기고) 있을 때 0.4초마다 물 튀기는 소리 반복 재생!
        if (isPressing && timer.tick % 8 == 0) {
          bool isSea = widget.fish['img'].toString().contains('sea');
          audioManager.playSfx(isSea ? "sfx_sea_landing.mp3" : "sfx_fresh_landing.mp3");
        }

        if (!isFinished) {
          // 🐟 [리듬 패치] 밀당 패턴은 그대로 유지!
          if (fishSkillDuration > 0) {
            fishSkillDuration--;
            if (fishSkillDuration == 0) {
              fishGearNotifier.value = 0; 
              playerGearNotifier.value = 1; 
              fishSkillDuration = -15 - random.nextInt(20); 
            }
          } else if (fishSkillDuration < 0) {
            fishSkillDuration++; 
          } else {
            if (random.nextInt(100) < 30) {  
              fishGearNotifier.value = (random.nextInt(100) < 50) ? 2 : 1; 
              fishSkillDuration = 50 + random.nextInt(40); 
              playerGearNotifier.value = 1; 
            }
          }

          double newGauge = gaugeNotifier.value;
          double wildFactor = (random.nextDouble() - 0.3) * 0.002;
          double safeStats = (widget.playerTotalStats.isNaN || widget.playerTotalStats.isInfinite) ? 1000.0 : widget.playerTotalStats.toDouble();
          
          double statSpeedBonus = math.min(safeStats / 120000, 0.015); 
          double basePullSpeed = 0.0031 + statSpeedBonus; 
          // 🎣 물고기 속도 상한(0.012): 대물이라도 게이지를 순식간에 왼쪽 끝으로 끌고 가지 못하게 제한.
          //    → 당기기·밀당 리듬이 항상 통하도록(반응 불가로 '휙' 지는 현상 방지). 작은 고기는 원래대로 느림.
          double baseFishSpeed = fishCurrentMove.clamp(0.0023, 0.012);

          int pGear = playerGearNotifier.value;
          int fGear = fishGearNotifier.value;

          // 🚨 [핵심 패치] 좌우 방향 완벽 반전! (당기면 +, 도망가면 -)
          double change = 0.0;
          if (isPressing) {
            if (penaltyNotifier.value) {
              change = -(baseFishSpeed * 1.5); // 도망!
            } else {
              if (fGear == 2) {
                if (pGear < 3) {
                  change = -(baseFishSpeed * 1.8);
                } else {
                  change = -((baseFishSpeed * 0.8) - (basePullSpeed * 0.6));
                }
              } 
              else if (fGear == 1) {
                if (pGear < 2) {
                  change = -(baseFishSpeed * 1.2);
                } else {
                  double powerMult = (pGear == 3) ? 1.2 : 1.0; 
                  change = (basePullSpeed * powerMult) - (baseFishSpeed * 0.4); // 내 쪽으로!
                }
              } 
              else {
                double powerMult = (pGear == 3) ? 1.8 : (pGear == 2) ? 1.4 : 1.0;
                change = (basePullSpeed * powerMult); // 내 쪽으로 쭉쭉!
              }
            }
          } else {
            double escapeMult = (fGear == 2) ? 2.0 : (fGear == 1) ? 1.5 : 1.0;
            change = -(baseFishSpeed * escapeMult * 0.6); // 도망!
          }

          newGauge += (change + wildFactor); // 계산된 방향 적용!
          
          // 🚨 [추가!] 물고기가 이동하는 방향에 맞춰 고개 돌리기!
          if (change > 0) {
            _isFishFacingRight = true;  // 끌려올 땐 내 쪽(오른쪽) 보기!
          } else if (change < 0) {
            _isFishFacingRight = false; // 도망갈 땐 반대쪽(왼쪽) 보기!
          }

          if (newGauge.isNaN || newGauge.isInfinite) newGauge = 0.5;
          newGauge = newGauge.clamp(0.0, 1.0);
          gaugeNotifier.value = newGauge;

          // 🚨 [승리 조건 반전] 1.0 (오른쪽 끝)이 승리, 0.0 (왼쪽 끝)이 패배!
          if (newGauge <= 0.0) { gaugeNotifier.value = 0.0; isFinished = true; isWin = false; }
          else if (newGauge >= 1.0) { gaugeNotifier.value = 1.0; isFinished = true; isWin = true; }
        }

        if (isFinished) {
          gameTimer?.cancel();
          _endGame(isWin);
        }
      } catch (e) {
        debugPrint("게임 진행 오류 방어: $e");
      }
    });
  }

  void _endGame(bool isSuccess) {
    if (_isGameOver) return;
    _isGameOver = true;
    gameTimer?.cancel();
    widget.onFinished(isSuccess, double.tryParse(widget.fish['size'].toString()) ?? 0.0);
  }

  @override
  void dispose() {
    gameTimer?.cancel();
    _rodController.dispose();
    gaugeNotifier.dispose(); 
    timeNotifier.dispose();
    fishGearNotifier.dispose();
    playerGearNotifier.dispose();
    penaltyNotifier.dispose();
    super.dispose();
  }

  void _updatePlayerGear(int msDiff) {
    try {
      if (msDiff < 50) { 
        penaltyNotifier.value = true; 
        playerGearNotifier.value = 1; 
      } else if (msDiff < 1500) { 
        penaltyNotifier.value = false; 
        if (fishGearNotifier.value == 2) {
          playerGearNotifier.value = 3; 
        } else if (fishGearNotifier.value == 1) {
          playerGearNotifier.value = 2; 
        } else {
          playerGearNotifier.value = 1; 
        }
      } else { 
        penaltyNotifier.value = false; 
        playerGearNotifier.value = 1; 
      }

      int pGear = playerGearNotifier.value;
      int speed = penaltyNotifier.value ? 400 : (pGear == 3 ? 60 : pGear == 2 ? 120 : 250);
      _rodController.duration = Duration(milliseconds: speed);
      if (_rodController.isAnimating) _rodController.repeat(reverse: true);
    } catch (e) {}
  }

  void _onPullDown() {
    if (_isGameOver || !mounted) return;

    try {
      DateTime now = DateTime.now();
      if (lastSoundTime == null || now.difference(lastSoundTime!).inMilliseconds > 300) {
        bool isSea = widget.fish['img'].toString().contains('sea');
        audioManager.playSfx(isSea ? "sfx_sea_landing.mp3" : "sfx_fresh_landing.mp3");
        lastSoundTime = now;
      }
    } catch (e) {}

    try { HapticFeedback.mediumImpact(); } catch (e) {}

    Future.microtask(() {
      if (!mounted || _isGameOver) return;
      try {
        setState(() {
          isPressing = true;
          if (lastReleaseTime != null) {
            int diff = DateTime.now().difference(lastReleaseTime!).inMilliseconds;
            _updatePlayerGear(diff);
          } else {
            playerGearNotifier.value = 1; 
            penaltyNotifier.value = false;
          }
        });
      } catch (e) {}
    });
  }

  void _onPullUp() {
    if (_isGameOver || !mounted) return;
    Future.microtask(() {
      if (!mounted || _isGameOver) return;
      try { setState(() { isPressing = false; lastReleaseTime = DateTime.now(); }); } catch (e) {}
    });
  }

  @override
  Widget build(BuildContext context) {
    bool isSea = widget.fish['img'].toString().contains('sea');
    // 🎣 장착 낚싯대별 파이팅 그림 (파일 없으면 기본 그림 자동 폴백)
    final String fightBase = isSea ? 'assets/images/hand_rod_sea' : 'assets/images/hand_rod_fw';
    final String fightRodImage = widget.rodImageSuffix.isEmpty ? '$fightBase.png' : '${fightBase}_${widget.rodImageSuffix}.png';

    return Container(
      color: Colors.transparent,
      child: Stack(
        children: [
          Positioned(
            right: -30.0, bottom: -50.0,
            child: ValueListenableBuilder<double>(
              valueListenable: gaugeNotifier,
              builder: (context, gaugeVal, child) {
                double fightAngle = 0.0;
                try {
                  fightAngle = 0.0 + (random.nextDouble() - 0.5) * (0.05 + (gaugeVal * 0.1));
                  if (fightAngle.isNaN || fightAngle.isInfinite) fightAngle = 0.0;
                } catch (e) {}
                return Transform.rotate(angle: fightAngle, origin: const Offset(150.0, 150.0), child: Image.asset(fightRodImage, height: 450.0, fit: BoxFit.contain, errorBuilder: (c,e,s) => Image.asset('$fightBase.png', height: 450.0, fit: BoxFit.contain, errorBuilder: (c2,e2,s2) => const SizedBox.shrink())));
              }
            )
          ),
          Positioned(
            top: 350, left: 0, right: 0,
            child: ValueListenableBuilder<int>(
              valueListenable: fishGearNotifier,
              builder: (context, fishGearVal, child) {
                if (fishGearVal == 0) return const SizedBox.shrink();
                return Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    decoration: BoxDecoration(color: fishGearVal == 2 ? Colors.redAccent.withOpacity(0.8) : Colors.orange.withOpacity(0.8), borderRadius: BorderRadius.circular(30), border: Border.all(color: Colors.white, width: 2)),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 24), const SizedBox(width: 8),
                        Text(fishGearVal == 2 ? '🚨 물고기의 발악!!' : '🐟 물고기의 저항!', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold, fontStyle: FontStyle.italic)),
                      ],
                    ),
                  ),
                );
              }
            ),
          ),
          Positioned(
            top: 410, left: 0, right: 0,
            child: Center(
              child: ValueListenableBuilder<int>(
                valueListenable: timeNotifier,
                builder: (context, timeVal, child) {
                  return Text('제한시간: $timeVal초', style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold, shadows: [Shadow(color: Colors.black45, blurRadius: 5)]));
                }
              ),
            ),
          ),
          Positioned(
            bottom: 230, left: 50, right: 50,
            child: Stack(
              alignment: Alignment.center, clipBehavior: Clip.none,
              children: [
                Container(height: 15, decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), gradient: const LinearGradient(colors: [Colors.redAccent, Colors.white, Colors.blueAccent]), boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)])),
                Align(alignment: Alignment.center, child: Container(width: 3, height: 25, color: Colors.white.withOpacity(0.6))),
                ValueListenableBuilder<double>(
                  valueListenable: gaugeNotifier,
                  builder: (context, gaugeVal, child) {
                    return AnimatedAlign(
                      duration: const Duration(milliseconds: 50), alignment: Alignment(gaugeVal * 2 - 1, 0),
                      child: Transform(
                        alignment: Alignment.center,
                        transform: Matrix4.rotationY(_isFishFacingRight ? 0 : math.pi),
                        child: Image.asset(
                          'assets/images/fighting_fish.png',
                          width: 64,
                          fit: BoxFit.contain,
                        ),
                      ),
                    );
                  }
                ),
              ],
            ),
          ),
          Positioned(
            bottom: 200, right: 30,
            child: ValueListenableBuilder<bool>(
              valueListenable: penaltyNotifier,
              builder: (context, hasPenalty, child) {
                return ValueListenableBuilder<int>(
                  valueListenable: playerGearNotifier,
                  builder: (context, pGear, child) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        if (hasPenalty) const Text('⚠️ 줄 엉킴! (연타 금지)', style: TextStyle(color: Colors.redAccent, fontSize: 22, fontWeight: FontWeight.w900, shadows: [Shadow(color: Colors.black, blurRadius: 4)])),
                        if (!hasPenalty)
                          Text(
                            pGear == 3 ? (isSea ? '🔥 3단 폭풍 릴링!!' : '🔥 3단 최고치 제압!!') : (isSea ? '$pGear단 릴링!' : '$pGear단 제압!'),
                            style: TextStyle(color: pGear == 3 ? Colors.redAccent : (pGear == 2 ? Colors.orangeAccent : Colors.yellow), fontSize: pGear == 3 ? 30 : 26, fontWeight: FontWeight.w900, fontStyle: FontStyle.italic, shadows: const [Shadow(color: Colors.black, blurRadius: 4)])
                          ),
                      ],
                    );
                  }
                );
              }
            ),
          ),
          Positioned(
            bottom: 50, right: 30,
            child: ValueListenableBuilder<bool>(
              valueListenable: penaltyNotifier,
              builder: (context, hasPenalty, child) {
                return GestureDetector(
                    onTapDown: (_) => _onPullDown(),
                    onTapUp: (_) => _onPullUp(),
                    onTapCancel: () => _onPullUp(),
                    child: Container(
                    width: 140, height: 140,
                    // ✨ 원인 해결 2: 누를 때 주황색으로 번쩍이게 시각 효과 복구!
                    decoration: BoxDecoration(
                      color: hasPenalty ? Colors.grey : (isPressing ? Colors.orangeAccent : const Color(0xFFD4AF37)),
                      shape: BoxShape.circle, 
                      boxShadow: [
                        if (isPressing && !hasPenalty) const BoxShadow(color: Colors.white54, blurRadius: 15, spreadRadius: 5),
                        const BoxShadow(color: Colors.black45, blurRadius: 10, offset: Offset(0, 4))
                      ], 
                      border: Border.all(color: Colors.white, width: 3)
                    ),
                    alignment: Alignment.center,
                    child: const Text('당기기', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20)),
                  ),
                );
              }
            ),
          ),
        ],
      ),
    );
  }
}


// =================================================================
// 🌲 [안전 모듈] 배경 자연 효과 (기존 낚시 로직에 절대 영향을 주지 않음!)
// =================================================================
class NatureAmbientEffects extends StatefulWidget {
  final bool isSea; // 💡 "너 바다니?" 라고 물어볼 변수 추가!
  const NatureAmbientEffects({super.key, this.isSea = false}); // 기본값은 민물(false)

  @override
  State<NatureAmbientEffects> createState() => _NatureAmbientEffectsState();
}

class _NatureAmbientEffectsState extends State<NatureAmbientEffects> {
  final math.Random _random = math.Random();
  final List<Widget> _effects = [];

  @override
  void initState() {
    super.initState();
    _startNatureLoop();
  }

  void _startNatureLoop() async {
    while (mounted) {
      // 5초 ~ 15초 사이 랜덤으로 효과 발생
      await Future.delayed(Duration(seconds: 5 + _random.nextInt(10)));
      if (!mounted) break;
      _spawnEffect();
    }
  }

// 🎯 지휘 본부: 별똥별 쏠지, 물고기 뛰게 할지 결정!
  // 🎯 지휘 본부: 민물/바다 생태계 완벽 분리!
  void _spawnEffect() {
    if (widget.isSea) {
      // 🌊 바다라면? 갈매기 '떼' 출격 시퀀스 가동!
      _spawnSeagullFlock(); 
    } else {
      // 🌲 민물: 맑은 날에만 별똥별. (물고기 뛰는 연출은 위치가 배경과 안 맞아 제거)
      if (WeatherService.instance.notifier.value.isClear && _random.nextBool()) {
        _spawnShootingStar(); // ☄️ 유성 (맑을 때만)
      }
    }
  }

  // 🦅 갈매기 '떼'를 소환하는 지휘 본부!
  void _spawnSeagullFlock() async {
    if (_effects.length >= 7) return;
    int flockSize = 3 + _random.nextInt(5); // 총 3~7마리 출격
    bool isLeftToRight = _random.nextBool(); 

    // 💡 이번 무리에 섞을 '출렁 갈매기' 목표 마리 수 (1~3마리 랜덤)
    int maxWaveBirds = 1 + _random.nextInt(3); 
    int currentWaveCount = 0; // 현재까지 출격한 출렁 갈매기 수

    for (int i = 0; i < flockSize; i++) {
      // 갈매기들 사이의 간격 (0.2초 ~ 0.5초)
      await Future.delayed(Duration(milliseconds: 200 + _random.nextInt(300)));
      if (!mounted) return;

      // 💡 아직 목표치를 덜 채웠고, 50% 확률에 당첨되면 출렁 갈매기 출격!
      // (이렇게 해야 무리 선두, 중간, 후미에 자연스럽게 섞입니다)
      if (currentWaveCount < maxWaveBirds && _random.nextBool()) {
        _spawnCirclingSeagull(isLeftToRight); // 출렁 갈매기 소환!
        currentWaveCount++;
      } else {
        _spawnSingleSeagull(isLeftToRight); // 평범한 직선 갈매기 소환!
      }
    }
  }

  // 🌪️ [새로 추가] 곡예 갈매기를 화면에 띄우는 명령!
  void _spawnCirclingSeagull(bool isLeftToRight) {
    if (!mounted) return;
    Key effectKey = UniqueKey();
    setState(() {
      _effects.add(
        _CirclingSeagull(
          key: effectKey,
          isLeftToRight: isLeftToRight,
          onComplete: () {
            if (mounted) {
              setState(() => _effects.removeWhere((w) => w.key == effectKey));
            }
          },
        ),
      );
    });
  }

  // 🦅 2. 개별 갈매기 소환 (기존 _spawnBird 업그레이드 버전)
  void _spawnSingleSeagull(bool isLeftToRight) {
    if (!mounted) return;
    double screenWidth = MediaQuery.of(context).size.width;
    double screenHeight = MediaQuery.of(context).size.height;

    // 떼로 날지만 위치가 약간씩 달라야 자연스럽습니다
    double startX = isLeftToRight ? -100.0 - (_random.nextDouble() * 100) : screenWidth + 100.0 + (_random.nextDouble() * 100);
    double endX = isLeftToRight ? screenWidth + 200.0 : -200.0;
    
    double baseHeight = screenHeight * (0.05 + _random.nextDouble() * 0.15); 
    double startY = baseHeight + (_random.nextDouble() * 60 - 30); 
    double endY = startY + (_random.nextDouble() * 80 - 40);

    Key effectKey = UniqueKey();
    setState(() {
      _effects.add(
        _AnimatedEntity(
          key: effectKey,
          isBird: true,
          isLeftToRight: isLeftToRight,
          startX: startX,
          endX: endX,
          startY: startY,
          endY: endY,
          durationMs: 4000 + _random.nextInt(2000), 
          onComplete: () {
            if (mounted) {
              setState(() {
                _effects.removeWhere((e) => e.key == effectKey);
              });
            }
          },
        ),
      );
    });
  }
  // ====================================================================

  // 🐟 (제거됨) 물고기 뛰는 연출 — 배경과 위치가 안 맞아(도로·산에서 뜀) 삭제

  // ☄️ 진짜 낭만적인 하얀 별똥별 (디테일 업그레이드 버전!)
  void _spawnShootingStar() {
    if (!mounted) return;

    // 💡 1. 산 중턱 방지: 하늘 꼭대기(상단 15% 이내)에서만 나타나도록 고도 제한!
    double startX = _random.nextDouble() * (MediaQuery.of(context).size.width / 2); 
    double startY = _random.nextDouble() * (MediaQuery.of(context).size.height * 0.15); 

    Key starKey = UniqueKey();

    Widget star = Positioned(
      key: starKey,
      left: startX,
      top: startY,
      child: TweenAnimationBuilder(
        tween: Tween<double>(begin: 0, end: 1.0),
        duration: const Duration(milliseconds: 1200), // 날아가는 시간
        builder: (context, double value, child) {
          return Transform.translate(
            // 💡 2. 궤적 눕히기: 밑으로(Y) 떨어지는 것보다 옆으로(X) 훨씬 많이 가게 변경
            offset: Offset(value * 400, value * 120), 
            child: Opacity(
              opacity: (1.0 - value).clamp(0.0, 1.0), 
              // 💡 3. 각도 눕히기: 기존 0.6에서 0.35(약 20도)로 완만하게 꺾어줌
              child: Transform.rotate(
                angle: 0.30, 
                child: Container(
                  // 💡 4. 꼬리 연장: 길이를 120으로 대폭 늘림!
                  width: 100, 
                  height: 1.5, 
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.white, Colors.white.withOpacity(0)],
                      begin: Alignment.centerRight, // 머리는 하얗게
                      end: Alignment.centerLeft,    // 꼬리는 투명하게
                      stops: const [0.0, 0.8],      // 꼬리가 자연스럽게 길어 보이도록 조정
                    ),
                    boxShadow: [
                      BoxShadow(color: Colors.white.withOpacity(0.8), blurRadius: 6, spreadRadius: 1),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );

    setState(() {
      _effects.add(star);
    });

    // 1초 뒤에 화면에서 싹 치우기
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted) {
        setState(() {
          _effects.removeWhere((widget) => widget.key == starKey);
        });
      }
    });
  }  
  
  @override
  Widget build(BuildContext context) {
    // 🚨 IgnorePointer: 이 애니메이션들을 터치해도 챔질 버튼 등 뒤쪽 버튼이 눌리도록 방해를 막아줌!
    return IgnorePointer(
      child: Stack(children: _effects.toList()),
    );
  }
}

class _AnimatedEntity extends StatefulWidget {
  final bool isBird;
  final bool isLeftToRight;
  final double startX, endX, startY, endY;
  final int durationMs;
  final VoidCallback onComplete;

  // 💡 { 바로 다음에 'super.key,' 만 딱 꽂아주시면 됩니다!
const _AnimatedEntity({ super.key, required this.isBird, required this.isLeftToRight, required this.startX, required this.endX, required this.startY, required this.endY, required this.durationMs, required this.onComplete });
  @override
  State<_AnimatedEntity> createState() => _AnimatedEntityState();
}

class _AnimatedEntityState extends State<_AnimatedEntity> {
  bool _isMoved = false;

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 50), () {
      if (mounted) setState(() => _isMoved = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedPositioned(
      duration: Duration(milliseconds: widget.durationMs),
      curve: widget.isBird ? Curves.linear : Curves.easeOutCirc, // 물고기는 튀어오르는 느낌!
      left: _isMoved ? widget.endX : widget.startX,
      top: _isMoved ? widget.endY : widget.startY,
      onEnd: widget.onComplete,
      child: AnimatedOpacity(
        duration: Duration(milliseconds: widget.isBird ? 1000 : widget.durationMs),
        opacity: _isMoved ? (widget.isBird ? 1.0 : 0.0) : 1.0,
        child: Transform.scale(
          scaleX: widget.isBird ? (widget.isLeftToRight ? -1.0 : 1.0) : 1.0, 
          child: widget.isBird 
              ? Image.asset('assets/images/bird.gif', width: 80.0, fit: BoxFit.contain)
              : const Text('💦🐟', style: TextStyle(fontSize: 30)),
        ),
      ),
    ); // <-- 🚨 아까 아마 이 부분의 ); 가 날아갔을 겁니다!
  }
}
// =================================================================

// 🌪️ [특수 모듈] 빙빙 돌면서 날아가는 관종 갈매기!
// 🌪️ [특수 모듈 - 최종본] 빽스탭 금지! 확실하게 뱅글뱅글 도는 갈매기!
class _CirclingSeagull extends StatefulWidget {
  final bool isLeftToRight;
  final VoidCallback onComplete;

  // 💡 final Key? key; <-- 요 줄 지우셨으니 생성자도 요렇게 깔끔하게!
  const _CirclingSeagull({super.key, required this.isLeftToRight, required this.onComplete});

  @override
  State<_CirclingSeagull> createState() => _CirclingSeagullState();
}

class _CirclingSeagullState extends State<_CirclingSeagull> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    // 6초 동안 확실하게 쇼를 보여줍니다!
    _controller = AnimationController(vsync: this, duration: const Duration(seconds: 6));
    _controller.forward().then((_) => widget.onComplete());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
   // 🚀 [무적의 고정 해상도] 창 크기를 아무리 줄여도 절대 안에서 안 튀어나옵니다!
    double screenW = 2500.0; // 너비를 엄청 크게 줘서 무조건 화면 밖에서 시작하게 만듦
    double screenH = 1000.0; // 높이도 넉넉하게 고정 (하늘 높이 0.2비율 계산용)

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        double t = _controller.value; 

        // 👇 아까 지워져서 에러 났던 부분! 다시 살려줍니다!
        double baseX = widget.isLeftToRight
            ? -200 + (screenW + 400) * t
            : (screenW + 200) - (screenW + 400) * t;
        
        double baseY = screenH * 0.2; // 하늘 높이

        // 💡 1. X축은 빽스탭(cos) 없이 무조건 앞으로만 전진!
        double x = baseX; 
        
        // 💡 2. 사장님이 찾으신 황금비율 진폭 60!
        double amplitude = 60.0; 
        
        // 💡 3. 날아가는 동안 4번 정도(8파이) 부드럽게 위아래로 출렁입니다.
        double angle = t * math.pi * 4; 
        
        // 💡 4. Y축만 사인파를 적용해서 위아래로 부드럽게!
        double y = baseY + math.sin(angle) * amplitude; 

        return Positioned(
          left: x,
          top: y,
          child: Transform.scale(
            // 왼쪽에서 날아올 때만 이미지를 좌우로 뒤집습니다!
            scaleX: widget.isLeftToRight ? -1.0 : 1.0, 
            child: Image.asset('assets/images/bird.gif', width: 70), 
          ),
        );
      },
    );
  } 
}

// 🏆 [실시간 아레나 랭킹 전광판] 팝업 함수!
  void _showRankingPopup(BuildContext context, String roomId, bool isSea, String winCondition) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E1E1E),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
            side: const BorderSide(color: Color(0xFFD4AF37), width: 2), 
          ),
          title: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.leaderboard, color: Color(0xFFD4AF37)),
              SizedBox(width: 8),
              Text('실시간 아레나 순위', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            height: 350,
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('arenas')
                  .doc(roomId)
                  .collection('participants')
                  .orderBy(winCondition == '최대어' ? 'maxSize' : 'score', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator(color: Color(0xFFD4AF37)));
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return const Center(child: Text('아직 점수를 낸 조사님이 없습니다.', style: TextStyle(color: Colors.grey)));

                var docs = snapshot.data!.docs;
                return ListView.builder(
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                              var data = docs[index].data() as Map<String, dynamic>;
                              String nickname = data['nickname'] ?? '무명조사';
                              num score = data['score'] ?? 0; // 👈 랭킹 점수 확실하게 꺼내기!
                              num maxSize = data['maxSize'] ?? 0; // 🐟 최대어 모드용 최대 사이즈

                              Widget rankIcon;
                              if (index == 0) rankIcon = const Icon(Icons.emoji_events, color: Color(0xFFFFD700), size: 28);
                              else if (index == 1) rankIcon = const Icon(Icons.emoji_events, color: Color(0xFFC0C0C0), size: 28);
                              else if (index == 2) rankIcon = const Icon(Icons.emoji_events, color: Color(0xFFCD7F32), size: 28);
                              else rankIcon = Padding(padding: const EdgeInsets.only(left: 8.0), child: Text('${index + 1}', style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 16)));

                              // 🎨 [핵심] 스킨 이름 분석해서 정확한 JPG 이미지 연결!
                              String userSkinImagePath = 'assets/images/skin_beginner.jpg';
                              if (data.containsKey('equippedSkin') && data['equippedSkin'] != null) {
                                var skin = data['equippedSkin'];
                                String skinName = (skin is Map) ? (skin['name'] ?? '').toString() : skin.toString();
                                
                                if (skinName.contains('신')) userSkinImagePath = 'assets/images/skin_god.jpg';
                                else if (skinName.contains('전설')) userSkinImagePath = 'assets/images/skin_legend.jpg';
                                else if (skinName.contains('마스터')) userSkinImagePath = 'assets/images/skin_master.jpg';
                                else if (skinName.contains('프로')) userSkinImagePath = 'assets/images/skin_pro.jpg';
                                else if (skinName.contains('전문') || skinName.contains('고수')) userSkinImagePath = 'assets/images/skin_expert.jpg';
                                else if (skinName.contains('중수')) userSkinImagePath = 'assets/images/skin_intermediate.jpg';
                                else if (skinName.contains('하수')) userSkinImagePath = 'assets/images/skin_novice.jpg';
                              }

                              return Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                decoration: BoxDecoration(
                                  color: index == 0 ? Colors.amber.withValues(alpha: 0.1) : Colors.black45,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: index == 0 ? const Color(0xFFD4AF37) : Colors.white12),
                                ),
                                child: ListTile(
                                  leading: rankIcon,
                                  title: Row(
                                    children: [
                                      // 🎨 [수술 완료] 유저가 실제 장착한 스킨 동그라미 액자!
                                      Container(
                                        margin: const EdgeInsets.only(right: 12),
                                        width: 48, height: 48,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          border: Border.all(color: const Color(0xFFD4AF37), width: 2.0),
                                          image: DecorationImage(
                                            image: AssetImage(userSkinImagePath),
                                            fit: BoxFit.cover,
                                            alignment: const Alignment(0.0, -0.75),
                                          ),
                                        ),
                                      ),
                                      Text(
                                        nickname,
                                        style: TextStyle(
                                          color: index == 0 ? const Color(0xFFFFD700) : Colors.white,
                                          fontWeight: index == 0 ? FontWeight.bold : FontWeight.normal
                                        ),
                                      ),
                                    ],
                                  ),
                                  trailing: Text(
                                    winCondition == '최대어' ? '$maxSize cm' : '$score 마리',
                                    style: const TextStyle(color: Color(0xFFD4AF37), fontWeight: FontWeight.bold, fontSize: 16),
                                  ),
                                ),
                              );
                  },
                );
              },
            ),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('닫기', style: TextStyle(color: Colors.grey)))],
        );
      },
    );
 
  }

// 🎨 상단 전용 미니 블랙&골드 버튼 스타일
Widget _buildTopMiniButton({required IconData icon, required VoidCallback onPressed}) {
  return GestureDetector(
    onTap: onPressed,
    child: Container(
      width: 44,  // 📏 터치 쾌감을 위한 큼직한 사이즈!
      height: 44,
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.7),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFD4AF37), width: 1.5),
        boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 4)],
      ),
      child: Icon(icon, color: const Color(0xFFD4AF37), size: 26), 
    ),
  );
}