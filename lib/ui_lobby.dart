// ignore_for_file: deprecated_member_use, unused_element, unused_import, unnecessary_import, use_build_context_synchronously, avoid_print, use_full_hex_values_for_flutter_colors
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/gestures.dart'; 
import 'game_config.dart';    
import 'fishing_logic.dart';  
import 'ui_fishing.dart';     
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'ui_arena.dart';
import 'ui_tutorial_npc.dart'; // 👧 윤슬 가이드 부품 장착!
import 'ui_guild.dart'; // 🟢 길드 접속표시(presence)
import 'package:flutter_tts/flutter_tts.dart'; // 🎙️ 목소리 부품 가져오기
import 'mission_announcement.dart'; // 📢 미션 1등 공지 (낚시 화면과 공용)

// 🏡 [KREFT 매니지먼트 센터] - 인벤토리/상점/정비 우선형 로비
// 🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩
class LobbyScreen extends StatefulWidget {
  final String nickname;
  final int level;
  final bool isFirstTime; // 🚀 처음 온 유저 확인용!

  const LobbyScreen({
    super.key, 
    required this.nickname, 
    required this.level,
    this.isFirstTime = false, // 🚀 기본값 설정
  });

  @override
  State<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends State<LobbyScreen> {
  // 💡 윤슬 가이드 튜토리얼 스텝 (-1: 안 함, 0: 인사, 1: 랭킹, 2: 버튼안내)
  int _lobbyStep = -1;

  String currentFilter = 'ALL';
  final ScrollController invScrollCtrl = ScrollController();

  String selectedTab = '레벨'; 
  String selectedFish = '베스'; 

  // 📅 출석체크 매니저 등판용 변수
  bool _showDailyBriefing = false;
  
  
  // 🎰 [초보자 배려 완벽판] 1성급 낚시터 전용 핫타임 미션! (자라 제외, 3마리 고정)
  final List<Map<String, dynamic>> _missionPool = [
    // 🏞️ [1성 민물] 예산 예당지
    {'loc': '예산 예당지', 'fish': '붕어', 'count': 3},
    {'loc': '예산 예당지', 'fish': '떡붕어', 'count': 3},
    {'loc': '예산 예당지', 'fish': '블루길', 'count': 3},
    {'loc': '예산 예당지', 'fish': '살치', 'count': 3},
    {'loc': '예산 예당지', 'fish': '베스', 'count': 3},
    {'loc': '예산 예당지', 'fish': '잉어', 'count': 3},
    {'loc': '예산 예당지', 'fish': '메기', 'count': 3},

    // 🏞️ [1성 민물] 예산 신양수로
    {'loc': '예산 신양수로', 'fish': '붕어', 'count': 3},
    {'loc': '예산 신양수로', 'fish': '떡붕어', 'count': 3},
    {'loc': '예산 신양수로', 'fish': '베스', 'count': 3},
    {'loc': '예산 신양수로', 'fish': '잉어', 'count': 3},
    {'loc': '예산 신양수로', 'fish': '메기', 'count': 3},
    {'loc': '예산 신양수로', 'fish': '가물치', 'count': 3},

    // 🌊 [1성 바다] 통영 척포 갯바위
    {'loc': '통영 척포 갯바위', 'fish': '고등어', 'count': 3},
    {'loc': '통영 척포 갯바위', 'fish': '우럭', 'count': 3},
    {'loc': '통영 척포 갯바위', 'fish': '갈치', 'count': 3},
    {'loc': '통영 척포 갯바위', 'fish': '참돔', 'count': 3},
    {'loc': '통영 척포 갯바위', 'fish': '광어', 'count': 3},
    {'loc': '통영 척포 갯바위', 'fish': '감성돔', 'count': 3},
    {'loc': '통영 척포 갯바위', 'fish': '갑오징어', 'count': 3},
    {'loc': '통영 척포 갯바위', 'fish': '주꾸미', 'count': 3},
    {'loc': '통영 척포 갯바위', 'fish': '문어', 'count': 3},

    // 🌊 [1성 바다] 거제 선상
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

  // ⏰ 이벤트 후보 시간 (오후 2, 3, 4, 저녁 7, 8, 9시)
  final List<int> _eventHours = [14, 15, 16, 19, 20, 21];

  Map<String, dynamic> _getTodayMission() {
  DateTime now = DateTime.now();
  int dailySeed = now.year * 10000 + now.month * 100 + now.day;
  var dailyRandom = math.Random(dailySeed);
  return _missionPool[dailyRandom.nextInt(_missionPool.length)];
}

  // ⏰ 이벤트 시간 계산 함수 (아까 넣으셨던 것)
  int _getTodayEventHour() {
    int day = DateTime.now().day;
    int month = DateTime.now().month;
    return _eventHours[(day + month) % _eventHours.length];
  }

  String _getBriefingText() {
  final mission = _getTodayMission();
  final currentHour = DateTime.now().hour;

  // 시간대별 인사말
  String greeting = "안녕하세요! 😊";
  if (currentHour >= 5 && currentHour < 12) { greeting = "좋은 아침이에요! ☀️"; }
else if (currentHour >= 12 && currentHour < 18) { greeting = "안녕하세요! ☕"; }
else { greeting = "밤낚시 오셨군요! 🌙"; }

  // 🧩 개인별 일일 퀘스트: 오늘 안에 완료하면 누구나 보상 (선착순/이벤트시간 없음)
  return "$greeting\n"
         "🏆 오늘의 일일 퀘스트!\n"
         "🐟 ${mission['fish']} ${mission['count']}마리 잡기\n"
         "🎣 어느 낚시터든 OK!\n"
         "✅ 오늘 안에 완료하면 500P 지급!";
}
  
  // 💰 매일 첫 접속 500P 지급 & 날짜 체크 로직
  Future<void> _checkDailyLogin() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // 오늘 날짜 구하기 (예: "2024-05-22")
    String today = DateTime.now().toIso8601String().substring(0, 10);
    final docRef = FirebaseFirestore.instance.collection('users').doc(user.uid);
    final doc = await docRef.get();

    if (doc.exists) {
      final userData = doc.data() as Map<String, dynamic>;

      // 🚀 [1단계 철벽!] 내 경험치(exp)가 1이라도 있으면 윤슬이 강제 퇴장!
      int myExp = userData.containsKey('exp') ? userData['exp'] : 0;
      if (myExp > 0) {
        if (mounted) {
          setState(() {
            _lobbyStep = -1; // 🚫 튜토리얼 끝났으니 집에 가라!
          });
        }
      }

      // DB에 저장된 마지막 접속일 가져오기
      String lastLogin = userData.containsKey('lastLoginDate') ? userData['lastLoginDate'] : '';
      
      // 마지막 접속일이 오늘이랑 다르면? (오늘 첫 접속이다!)
      if (lastLogin != today) {
        // 1. 500P 입금하고 마지막 접속일 오늘로 도장 쾅!
        await docRef.set({
          'gold': FieldValue.increment(500),
          'lastLoginDate': today,
        }, SetOptions(merge: true));
      }

      // 🚨 [핵심 패치] 500P 보상은 하루 한 번만 주더라도, 아라 매니저 공지는 올 때마다 무조건 띄운다! (자물쇠 밖으로 탈출!)
      if (mounted) {
        setState(() {
       _showDailyBriefing = true; // 매니저 무조건 등판!
        });
      }
    }
  }

  Timer? _onlineHeartbeat; // 💓 #6 접속상태 유지(로비에 머무는 회원 초록불)

  @override
  void initState() {
    super.initState();
    _checkDailyLogin(); // 🚀 [여기에 2단계 딱 1줄 추가!]
    audioManager.playBgm('bgm_menu.mp3');
    guildGoOnline(); // 🟢 #6 로비에서도 접속표시(시간 소진 후 머무는 화면)
    _onlineHeartbeat = Timer.periodic(const Duration(seconds: 12), (_) {
      if (mounted) guildGoOnline(); // 접속 초록불 주기적 재확인
    });

    // 🚀 처음 온 유저면 튜토리얼 스텝을 0으로 시작!
    if (widget.isFirstTime) {
      _lobbyStep = 0;
    }
  }

  @override
  void dispose() {
    _onlineHeartbeat?.cancel();
    super.dispose();
  }


  final List<String> fwFishList = ['붕어', '잉어', '가물치', '메기', '떡붕어', '강준치', '블루길', '베스', '살치', '자라'];
  final List<String> seaFishList = ['참돔', '감성돔', '광어', '우럭', '갈치', '고등어', '벵에돔', '갑오징어', '주꾸미', '문어', '참치'];

 // 🆙 100레벨 공용 계산 사용 (game_config)
  int _calcLevelFromExp(int exp) => calcLevelFromExp(exp);
  Widget _buildRankingBoard() {
    return Container( 
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10), 
      padding: const EdgeInsets.all(30), // 💡 안쪽 전체 여백 25 -> 30 더 빵빵하게!
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.8),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.cyanAccent.withOpacity(0.6), width: 2),
      ),
      child: Column(
        children: [
          Row(
            children: [
              _buildTabButton('레벨'),
              _buildTabButton('민물'),
              _buildTabButton('바다'),
            ],
          ),
          const SizedBox(height: 30), // 💡 탭 아래 간격 25 -> 30

          if (selectedTab != '레벨')
            Container(
              margin: const EdgeInsets.only(bottom: 20),
              height: 55, // 💡 서브 탭(물고기 버튼) 높이 45 -> 55 대폭발!
              child: ScrollConfiguration(
                behavior: ScrollConfiguration.of(context).copyWith(
                  dragDevices: { PointerDeviceKind.touch, PointerDeviceKind.mouse },
                ),
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: selectedTab == '민물' ? fwFishList.length : seaFishList.length,
                  itemBuilder: (context, index) {
                    String fishName = selectedTab == '민물' ? fwFishList[index] : seaFishList[index];
                    bool isSelected = selectedFish == fishName;
                    
                    return GestureDetector(
                      onTap: () {
                        audioManager.playSfx("sfx_click.mp3");
                        setState(() { selectedFish = fishName; });
                      },
                      child: Container(
                        margin: const EdgeInsets.only(right: 15), // 💡 버튼 사이 간격 12 -> 15
                        padding: const EdgeInsets.symmetric(horizontal: 25), // 💡 버튼 좌우 여백 20 -> 25
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: isSelected ? const Color(0xFFD4AF37) : Colors.black, 
                          border: Border.all(color: const Color(0xFFD4AF37), width: 1.5), 
                          borderRadius: BorderRadius.circular(8), 
                        ),
                        child: Text(
                          fishName,
                          style: TextStyle(
                            color: isSelected ? Colors.black : const Color(0xFFD4AF37), 
                            fontWeight: FontWeight.bold,
                            fontSize: 20, // 💡 서브 탭 글자 18 -> 20 떡상!
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          
          const Divider(color: Colors.cyanAccent, height: 30, thickness: 2), // 💡 구분선 굵기 1.5 -> 2

          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: selectedTab == '레벨'
                  ? FirebaseFirestore.instance.collection('users').orderBy('exp', descending: true).limit(10).snapshots()
                  : FirebaseFirestore.instance.collection('users').orderBy('maxCatch.$selectedFish.size', descending: true).limit(10).snapshots(),
              builder: (context, snapshot) {
                // 1. 데이터가 오고 있거나 없으면 처리
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(color: Color(0xFFD4AF37)));
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(child: Text('데이터가 없습니다.', style: TextStyle(color: Colors.white54)));
                }
                // 2. ⚡ [핵심] 랭킹 데이터를 여기서 정의합니다! (이 줄이 빠져서 에러가 났던 겁니다)
                var docs = snapshot.data!.docs;

                // 3. 리스트 생성
                return ListView.builder(
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    var data = docs[index].data() as Map<String, dynamic>;
                    String name = data['nickname'] ?? '조사님';
                    
                    String displayVal = '';
                    if (selectedTab == '레벨') {
                      int exp = data['exp'] ?? 0;
                      displayVal = 'Lv.${_calcLevelFromExp(exp)}';
                    } else {
                      double size = (data['maxCatch']?[selectedFish]?['size'] ?? 0.0).toDouble();
                      displayVal = '${size.toStringAsFixed(1)}${selectedFish == '문어' ? 'Kg' : 'Cm'}';
                    }
                    
                    bool isMe = docs[index].id == FirebaseAuth.instance.currentUser?.uid;

                   // 4. 스킨 경로 가져오기 (skin_xxx.jpg 로 완벽 통일!)
        String userSkinImagePath = 'assets/images/skin_beginner.jpg';
        if (data.containsKey('equippedSkin') && data['equippedSkin'] != null) {
          var skin = data['equippedSkin'];
          String skinName = (skin is Map) ? (skin['name'] ?? '').toString() : skin.toString();
          
          if (skinName.contains('신')) {
            userSkinImagePath = 'assets/images/skin_god.jpg';
          } else if (skinName.contains('전설')) {
            userSkinImagePath = 'assets/images/skin_legend.jpg';
          } else if (skinName.contains('마스터')) {
            userSkinImagePath = 'assets/images/skin_master.jpg';
          } else if (skinName.contains('프로')) {
            userSkinImagePath = 'assets/images/skin_pro.jpg';
          } else if (skinName.contains('전문') || skinName.contains('고수')) {
            userSkinImagePath = 'assets/images/skin_expert.jpg';
          } else if (skinName.contains('중수')) {
            userSkinImagePath = 'assets/images/skin_intermediate.jpg';
          } else if (skinName.contains('하수')) {
            userSkinImagePath = 'assets/images/skin_novice.jpg';
          }
        }
                    return _buildRankItem(index + 1, name, displayVal, isMe, userSkinImagePath);
                  },
                );
              },
            ),
          ),
          const Divider(color: Colors.white24, height: 30, thickness: 2),
          _buildMyStaticRank(), 
        ],
      ),
    );
  }

  Widget _buildTabButton(String title) {
    bool isSelected = selectedTab == title;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          audioManager.playSfx("sfx_click.mp3");
          setState(() {
            selectedTab = title;
            selectedFish = (title == '민물' ? fwFishList[0] : (title == '바다' ? seaFishList[0] : '붕어'));
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16), // 💡 탭 위아래 여백 12 -> 16
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: isSelected ? const Color(0xFFD4AF37) : Colors.transparent, width: 4)), // 💡 밑줄 3 -> 4
          ),
          child: Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isSelected ? const Color(0xFFD4AF37) : Colors.white54,
              fontWeight: isSelected ? FontWeight.w900 : FontWeight.bold,
              fontSize: 24, // 💡 메인 탭 글자 22 -> 24 초대형 떡상!
            ),
          ),
        ),
      ),
    );
  }

  // 🌟 [수술 완료] userSkinImagePath 매개변수를 추가했습니다!
Widget _buildRankItem(int rank, String name, String displayVal, bool isMe, String userSkinImagePath) {
  return Container(
    margin: const EdgeInsets.symmetric(vertical: 4), 
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10), 
    decoration: BoxDecoration(
      color: isMe ? Colors.cyanAccent.withOpacity(0.1) : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      children: [
        SizedBox(
          width: 50, 
          child: Text('$rank위', style: TextStyle(color: rank <= 3 ? Colors.amberAccent : Colors.white70, fontWeight: FontWeight.w900, fontSize: 24)),
        ),
        const SizedBox(width: 10),
        
        // 🎨 [여기가 핵심!] 하드코딩된 char_god.jpg를 지우고, userSkinImagePath를 사용합니다!
        Container(
          margin: const EdgeInsets.only(right: 15),
          width: 48, height: 48,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFFD4AF37), width: 2.0),
            image: DecorationImage(
              // 🎯 매개변수 값 사용! 만약 빈 값이면 초보자 스킨으로Fallback!
              image: AssetImage(userSkinImagePath.isNotEmpty ? userSkinImagePath : 'assets/images/char_beginner.jpg'),
              fit: BoxFit.cover, 
              alignment: Alignment(0.0, -0.75), 
            )
          ),
        ),

        Expanded(
          child: Text(name, style: TextStyle(color: isMe ? Colors.cyanAccent : Colors.white, fontSize: 22, fontWeight: isMe ? FontWeight.w900 : FontWeight.bold), overflow: TextOverflow.ellipsis), 
        ),
        
        Text(displayVal, style: TextStyle(color: rank <= 3 ? Colors.amberAccent : Colors.white, fontSize: 22, fontWeight: FontWeight.w900)), 
      ],
    ),
  );
}

  // 🏅 내 등수 계산: 나보다 점수가 높은 사람 수 + 1 (10위 밖이어도 정확한 등수 표시)
  Future<int> _getMyRank(Map<String, dynamic> myData) async {
    final col = FirebaseFirestore.instance.collection('users');
    try {
      if (selectedTab == '레벨') {
        int myExp = myData['exp'] ?? 0;
        final agg = await col.where('exp', isGreaterThan: myExp).count().get();
        return (agg.count ?? 0) + 1;
      } else {
        double mySize = (myData['maxCatch']?[selectedFish]?['size'] ?? 0.0).toDouble();
        final agg = await col.where('maxCatch.$selectedFish.size', isGreaterThan: mySize).count().get();
        return (agg.count ?? 0) + 1;
      }
    } catch (e) {
      return 0; // 실패 시 0 → 화면엔 '-' 로 표시
    }
  }

  Widget _buildMyStaticRank() {
    final user = FirebaseAuth.instance.currentUser;
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('users').doc(user?.uid).snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.data() == null) return const SizedBox();
        var myData = snapshot.data!.data() as Map<String, dynamic>;

        String displayVal = '';
        if (selectedTab == '레벨') {
          int exp = myData['exp'] ?? 0;
          displayVal = 'Lv.${_calcLevelFromExp(exp)}';
        } else {
          double mySize = (myData['maxCatch']?[selectedFish]?['size'] ?? 0.0).toDouble();
          displayVal = '${mySize.toStringAsFixed(1)}${selectedFish == '문어' ? 'Kg' : 'Cm'}';
        }

        return FutureBuilder<int>(
          future: _getMyRank(myData),
          builder: (context, rankSnap) {
            final int myRank = rankSnap.data ?? 0;
            final String rankText = myRank > 0 ? '$myRank위' : '-';
            return Container(
              // 💡 하단 내 랭킹 박스도 살짝 슬림하게 다이어트!
              padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 16),
              decoration: BoxDecoration(
                color: Colors.cyanAccent.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.cyanAccent.withOpacity(0.4), width: 2),
              ),
              child: Row(
                children: [
                  const Text('내 랭킹', style: TextStyle(color: Colors.cyanAccent, fontSize: 22, fontWeight: FontWeight.w900)),
                  const SizedBox(width: 16),
                  // 🏅 실제 등수 표시 (10위 밖이어도 정확히 보여줌)
                  Text(rankText, style: TextStyle(color: (myRank > 0 && myRank <= 3) ? Colors.amberAccent : Colors.white, fontSize: 22, fontWeight: FontWeight.w900)),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(myData['nickname'] ?? '나', style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900), overflow: TextOverflow.ellipsis),
                  ),
                  Text(displayVal, style: const TextStyle(color: Colors.cyanAccent, fontSize: 26, fontWeight: FontWeight.w900)),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showLocationTypeSelect() {
    audioManager.playSfx('sfx_click.mp3');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.black.withOpacity(0.9),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: Color(0xFFD4AF37), width: 2)),
        title: const Center(child: Text('어디로 출조하시겠습니까?', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
        content: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _typeBtn(ctx, '민물 낚시', Icons.location_on, false),
            const SizedBox(width: 20),
            _typeBtn(ctx, '바다 낚시', Icons.sailing, true),
          ],
        ),
      ),
    );
  }

  Widget _typeBtn(BuildContext ctx, String txt, IconData icon, bool isSea) {
    return Expanded(
      child: GestureDetector(
        onTap: () {
          Navigator.pop(ctx);
          Navigator.push(context, MaterialPageRoute(builder: (context) => LocationSelectScreen(
            nickname: widget.nickname, 
            level: widget.level, 
            initialIsSeaMode: isSea,
            isFirstTime: widget.isFirstTime, // 🚀 [핵심] 낚시터 리스트 화면으로 튜토리얼 꼬리표 전달!
          )));
        },
        child: Container(
          height: 120,
          decoration: BoxDecoration(color: Colors.grey.shade900, borderRadius: BorderRadius.circular(15), border: Border.all(color: const Color(0xFFD4AF37))),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(icon, color: const Color(0xFFD4AF37), size: 40), const SizedBox(height: 10), Text(txt, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))]),
        ),
      ),
    );
  }

// 🎒 [신규 추가] 로비 전용 인벤토리 팝업!
  void _showLobbyInventoryPopup() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        String currentFilter = 'ALL';

        return StatefulBuilder(
          builder: (context, setPopupState) {
            return Dialog(
              backgroundColor: Colors.transparent,
              alignment: const Alignment(0.4, 0.0), 
              child: Container(
                width: 530,
                height: 600, // 넉넉한 높이
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: const RadialGradient(center: Alignment(-0.5, -0.5), radius: 1.5, colors: [Color(0xFF3A3A3A), Color(0xFF0F0F0F)]),
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(color: const Color(0xFFD4AF37), width: 3),
                ),
                child: StreamBuilder<DocumentSnapshot>(
                  stream: FirebaseFirestore.instance.collection('users').doc(FirebaseAuth.instance.currentUser?.uid).snapshots(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) return const Center(child: CircularProgressIndicator(color: Color(0xFFD4AF37)));
                    
                    var userData = snapshot.data!.data() as Map<String, dynamic>? ?? {};
                    List<dynamic> inventory = userData['inventory'] ?? [];
                    int myGold = userData['gold'] ?? 0;
                    int realExp = userData['exp'] ?? 0;

                    // 🏆 1. 경험치 & 레벨 계산기 (최신 30레벨 패치 적용)
                    int realLevel = 1; int nextLevelExp = 5000; int prevLevelExp = 0;
                    if (realExp >= 1300000) { realLevel = 30; nextLevelExp = 1300000; prevLevelExp = 1300000; }
                    else if (realExp >= 1200000) { realLevel = 29; nextLevelExp = 1300000; prevLevelExp = 1200000; }
                    else if (realExp >= 1100000) { realLevel = 28; nextLevelExp = 1200000; prevLevelExp = 1100000; }
                    else if (realExp >= 1000000) { realLevel = 27; nextLevelExp = 1100000; prevLevelExp = 1000000; }
                    else if (realExp >= 900000)  { realLevel = 26; nextLevelExp = 1000000; prevLevelExp = 900000; }
                    else if (realExp >= 800000)  { realLevel = 25; nextLevelExp = 900000; prevLevelExp = 800000; }
                    else if (realExp >= 700000)  { realLevel = 24; nextLevelExp = 800000; prevLevelExp = 700000; }
                    else if (realExp >= 650000)  { realLevel = 23; nextLevelExp = 700000; prevLevelExp = 650000; }
                    else if (realExp >= 600000)  { realLevel = 22; nextLevelExp = 650000; prevLevelExp = 600000; }
                    else if (realExp >= 550000)  { realLevel = 21; nextLevelExp = 600000; prevLevelExp = 550000; }
                    else if (realExp >= 500000)  { realLevel = 20; nextLevelExp = 550000; prevLevelExp = 500000; }
                    else if (realExp >= 430000)  { realLevel = 19; nextLevelExp = 500000; prevLevelExp = 430000; }
                    else if (realExp >= 390000)  { realLevel = 18; nextLevelExp = 430000; prevLevelExp = 390000; }
                    else if (realExp >= 350000)  { realLevel = 17; nextLevelExp = 390000; prevLevelExp = 350000; }
                    else if (realExp >= 310000)  { realLevel = 16; nextLevelExp = 350000; prevLevelExp = 310000; }
                    else if (realExp >= 270000)  { realLevel = 15; nextLevelExp = 310000; prevLevelExp = 270000; }
                    else if (realExp >= 240000)  { realLevel = 14; nextLevelExp = 270000; prevLevelExp = 240000; }
                    else if (realExp >= 210000)  { realLevel = 13; nextLevelExp = 240000; prevLevelExp = 210000; }
                    else if (realExp >= 190000)  { realLevel = 12; nextLevelExp = 210000; prevLevelExp = 190000; }
                    else if (realExp >= 160000)  { realLevel = 11; nextLevelExp = 190000; prevLevelExp = 160000; }
                    else if (realExp >= 130000)  { realLevel = 10; nextLevelExp = 160000; prevLevelExp = 130000; }
                    else if (realExp >= 110000)  { realLevel = 9;  nextLevelExp = 130000; prevLevelExp = 110000; }
                    else if (realExp >= 90000)   { realLevel = 8;  nextLevelExp = 110000; prevLevelExp = 90000; }
                    else if (realExp >= 70000)   { realLevel = 7;  nextLevelExp = 90000; prevLevelExp = 70000; }
                    else if (realExp >= 50000)   { realLevel = 6;  nextLevelExp = 70000; prevLevelExp = 50000; }
                    else if (realExp >= 30000)   { realLevel = 5;  nextLevelExp = 50000; prevLevelExp = 30000; }
                    else if (realExp >= 20000)   { realLevel = 4;  nextLevelExp = 30000; prevLevelExp = 20000; }
                    else if (realExp >= 10000)   { realLevel = 3;  nextLevelExp = 20000; prevLevelExp = 10000; }
                    else if (realExp >= 5000)    { realLevel = 2;  nextLevelExp = 10000; prevLevelExp = 5000; }
                    else                         { realLevel = 1;  nextLevelExp = 5000; prevLevelExp = 0; }

                    int myLevel = realLevel; // 기존 스토어 호출용 변수 유지
                    double expPercent = (realLevel < 30) ? (realExp - prevLevelExp) / (nextLevelExp - prevLevelExp) : 1.0;
                    int expLeft = (realLevel < 30) ? (nextLevelExp - realExp) : 0;

                    // 🎯 2. 제압력(스탯) 완벽 계산기 (오류 방지용 직접 합산)
                    int equipP = 0; int equipC = 0; int equipS = 0;
                    void addStats(Map<String, dynamic>? item) {
                      if (item != null && item['stats'] != null) {
                        equipP += (item['stats']['P'] as num?)?.toInt() ?? 0;
                        equipC += (item['stats']['C'] as num?)?.toInt() ?? 0;
                        equipS += (item['stats']['S'] as num?)?.toInt() ?? 0;
                      }
                    }
                    // 장착된 장비들 합산 (game_config.dart의 글로벌 변수 활용)
                    addStats(globalEquippedSkin); addStats(globalEquippedRod); addStats(globalEquippedFloat);
                    addStats(globalEquippedReel); addStats(globalEquippedSunglasses); addStats(globalEquippedBadge);

                    int levelBonus = (realLevel - 1) * 10;
                    int myTotalPower = equipP + equipC + equipS + levelBonus;

                    bool isBait(String name) { return name.contains('지렁이') || name.contains('글루텐') || name.contains('옥수수') || name.contains('크릴') || name.contains('에기') || name.contains('루어') || name.contains('미끼'); }

                    List<dynamic> filteredItems = inventory.where((item) {
                      String cat = item['category'] ?? '';
                      bool isSkin = item['name'].toString().contains('조사') || item['name'].toString().contains('마스터') || item['name'].toString().contains('프로') || item['name'].toString().contains('세트');
                      if (currentFilter == 'ALL') return true;
                      if (currentFilter == 'FW' && (cat == 'FW' || cat == 'COMMON') && !isSkin && !isBait(item['name'].toString())) return true;
                      if (currentFilter == 'SEA' && (cat == 'SEA' || cat == 'COMMON') && !isSkin && !isBait(item['name'].toString())) return true;
                      if (currentFilter == 'BAIT' && isBait(item['name'].toString())) return true;
                      if (currentFilter == 'SKIN' && isSkin) return true;
                      return false;
                    }).toList();

                    // 🎯 [정리 정돈 2차 패치] 누락 데이터 강제 분류형 정렬!
filteredItems.sort((a, b) {
  // 아이템 타입을 알아내는 초능력 함수!
  String getType(Map<String, dynamic> item) {
    String t = (item['type']?.toString().toUpperCase() ?? '');
    String n = (item['name']?.toString() ?? '');
    String c = (item['category']?.toString().toUpperCase() ?? '');
    
    // 이미 타입이 있으면 그대로 사용
    if (t.isNotEmpty) return t;
    
    // 타입이 없으면 이름/카테고리로 추리 (DB 복구용)
    if (n.contains('대') || n.contains('CF') || n.contains('KT')) return 'ROD';
    if (n.contains('릴') || c == 'REEL') return 'REEL';
    if (n.contains('찌') || c == 'FLOAT') return 'FLOAT';
    if (n.contains('지렁이') || n.contains('글루텐') || n.contains('옥수수') || n.contains('미끼') || n.contains('에기')) return 'BAIT';
    if (n.contains('스킨') || n.contains('조사')) return 'SKIN';
    return 'ETC';
  }

  const priority = {'ROD': 1, 'REEL': 2, 'FLOAT': 3, 'BAIT': 4, 'SKIN': 5, 'ETC': 6};
  
  int pA = priority[getType(a)] ?? 99;
  int pB = priority[getType(b)] ?? 99;
  
  // 🎙️ [디버그용] 정렬이 진짜 도는지 궁금하면 아래 주석 풀어보세요! (콘솔창에 뜹니다)
  // print("정렬 확인: ${a['name']}($pA) vs ${b['name']}($pB)");

  if (pA != pB) return pA.compareTo(pB);
  return a['name'].toString().compareTo(b['name'].toString());
});

                    int totalSlots = math.max(20, (filteredItems.length ~/ 4 + 1) * 4);

                    return Column(
                      children: [
                        // 🌟 3. 유저 피드백 완벽 반영! [가방 타이틀 + 스탯 + 포인트] 통합 헤더
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // 왼쪽: 내 가방 아이콘
                            const Row(
                              children: [
                                Icon(Icons.backpack, color: Color(0xFFD4AF37), size: 28),
                                SizedBox(width: 8),
                                Text('내 가방', style: TextStyle(color: Color(0xFFD4AF37), fontSize: 24, fontWeight: FontWeight.bold)),
                              ],
                            ),
                            // 오른쪽: 레벨, 스탯, 포인트 
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Row(
                                  children: [
                                    Text('Lv.$realLevel', style: const TextStyle(color: Colors.yellowAccent, fontSize: 13, fontWeight: FontWeight.bold)),
                                    const SizedBox(width: 6),
                                    Text('제압력: $myTotalPower', style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                                    Text(' (💪$equipP 🎯$equipC 📡$equipS)', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text('point $myGold', style: const TextStyle(color: Colors.cyanAccent, fontSize: 16, fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        
                        // 🚀 [신규 추가] 경험치 바 (레벨업까지 남은 수치 직관적 표시!)
                        Container(
                          width: double.infinity,
                          height: 24,
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.white24, width: 1),
                          ),
                          child: Stack(
                            children: [
                              FractionallySizedBox(
                                alignment: Alignment.centerLeft,
                                widthFactor: expPercent.clamp(0.0, 1.0),
                                child: Container(decoration: BoxDecoration(color: const Color(0xFFD4AF37), borderRadius: BorderRadius.circular(7))),
                              ),
                              Center(
                                child: Text(
                                  realLevel < 30 ? '다음 레벨까지 $expLeft EXP' : '최고 레벨 달성!',
                                  style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold, shadows: [Shadow(color: Colors.black, blurRadius: 2)]),
                                ),
                              ),
                            ],
                          ),
                        ),
                        
                        const SizedBox(height: 10),
                        const Text('※ 장비 장착은 낚시터 입장 후 셋팅 화면에서 환경에 맞게 진행해주세요.', style: TextStyle(color: Colors.grey, fontSize: 13)),
                        const SizedBox(height: 15),
                        
                        // 1. 탭 버튼 (여기서부터 기존 코드 쭉 이어짐!)
                        Row(
                      
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: ['ALL', 'FW', 'SEA', 'BAIT', 'SKIN'].map((filter) {
                            String label = filter == 'ALL' ? '전체' : filter == 'FW' ? '민물' : filter == 'SEA' ? '바다' : filter == 'BAIT' ? '미끼' : '스킨';
                            bool isSelected = currentFilter == filter;
                            return Expanded(
                              child: GestureDetector(
                                onTap: () { audioManager.playSfx('sfx_click.mp3'); setPopupState(() => currentFilter = filter); },
                                child: Container(margin: const EdgeInsets.symmetric(horizontal: 2), padding: const EdgeInsets.symmetric(vertical: 8), decoration: BoxDecoration(color: isSelected ? const Color(0xFFD4AF37) : Colors.black45, borderRadius: BorderRadius.circular(5), border: Border.all(color: isSelected ? Colors.white : Colors.grey.shade800)), child: Center(child: Text(label, style: TextStyle(color: isSelected ? Colors.black : Colors.grey, fontWeight: FontWeight.bold, fontSize: 12)))),
                              ),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 15),
                        // 2. 아이템 그리드 (표시 전용)
                        Expanded(
                          child: GridView.builder(
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 4, mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 0.9),
                            itemCount: totalSlots,
                            itemBuilder: (context, index) {
                              if (index >= filteredItems.length) {
                                return Container(decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.white10)));
                              }
                              var item = filteredItems[index];
                              String iconPath = item['icon'] ?? '';
                              if (iconPath.contains('../')) iconPath = iconPath.replaceAll('../', 'assets/');
                              if (!iconPath.startsWith('assets/')) iconPath = iconPath.contains('.jpg') ? 'assets/images/$iconPath' : 'assets/items/$iconPath';

                              return Container(
                                decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade800, width: 2)),
                                child: Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Image.asset(iconPath, width: 45, height: 45, fit: BoxFit.contain, errorBuilder: (c,e,s) => const Icon(Icons.inventory_2, color: Colors.white54, size: 30)),
                                        const SizedBox(height: 5),
                                        FittedBox(fit: BoxFit.scaleDown, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 2), child: Text(item['name'], style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)))),
                                      ],
                                    ),
                                    if (item['quantity'] != null && item['type'] == 'BAIT')
                                      Positioned(bottom: 2, right: 2, child: Container(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2), decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(4)), child: Text('${item['quantity']}개', style: const TextStyle(color: Colors.yellowAccent, fontSize: 10, fontWeight: FontWeight.bold)))),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 15),
                        // 3. 하단 버튼 구역 (상점 가기 / 닫기)
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(backgroundColor: Colors.black, foregroundColor: const Color(0xFFD4AF37), side: const BorderSide(color: Color(0xFFD4AF37), width: 1.5), padding: const EdgeInsets.symmetric(vertical: 15), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                                onPressed: () {
                                  audioManager.playSfx("sfx_click.mp3");
                                  Navigator.pop(context); // 가방 먼저 닫기
                                  Navigator.push(context, MaterialPageRoute(builder: (context) => StoreScreen(currentGold: myGold, currentLevel: myLevel, currentInventory: inventory)));
                                },
                                child: const Text('🛒 상점 가기', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(backgroundColor: Colors.grey.shade800, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 15), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                                onPressed: () { audioManager.playSfx("sfx_click.mp3"); Navigator.pop(context); },
                                child: const Text('닫기', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                              ),
                            ),
                          ],
                        ),
                      ],
                    );
                  },
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser; 

    // 💡 투명 필름 (Stack) 깔기 시작!
    return Stack(
      children: [
        // ==========================================================
        // 1. 사장님의 완벽한 로비 화면
        // ==========================================================
        Scaffold(
          backgroundColor: Colors.black,
          body: Row(
            children: [
              Expanded(
                flex: 2,
                child: StreamBuilder<DocumentSnapshot>(
                  stream: FirebaseFirestore.instance.collection('users').doc(user?.uid).snapshots(),
                  builder: (context, snapshot) {
                    int realLevel = widget.level; 
                    String charImgPath = 'assets/images/char_beginner.png'; 

                    if (snapshot.hasData && snapshot.data!.data() != null) {
                      var myData = snapshot.data!.data() as Map<String, dynamic>;
                      int exp = myData['exp'] ?? 0;
                      realLevel = _calcLevelFromExp(exp); 

                      // 🎨 [수정] 레벨로 자동 변경 X — 스킨을 구매/장착해야만 캐릭터 이미지 변경!
                      if (myData['equippedSkin'] != null) {
                        charImgPath = FishingLogic.getLobbyCharacterImage(myData['equippedSkin']['name'].toString());
                      } else {
                        charImgPath = 'assets/images/char_beginner.png';
                      }

                      // 🚩 [수술 완료] 화면 전체를 Stack으로 묶어서 모서리에 강제 고정!
                      return Stack(
                        fit: StackFit.expand, // 💡 화면 꽉 채우기 (그래야 모서리로 갑니다!)
                        children: [
                          // 1️⃣ 기존 중앙 정렬 요소들 (닉네임 옆 딱지 제거 완료)
                          Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                width: 200, height: 200,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle, 
                                  color: Colors.black, 
                                  border: Border.all(color: const Color(0xFFD4AF37), width: 3),
                                  image: DecorationImage(image: AssetImage(charImgPath), fit: BoxFit.cover, alignment: Alignment.topCenter) 
                                ),
                              ), 
                              const SizedBox(height: 20),
                              Text('Lv.$realLevel ${widget.nickname}', style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 40),
                              
                              // 🎣 [1. 출조하기 버튼]
                              SizedBox(
                                width: 250, height: 70,
                                child: OutlinedButton(
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: const Color(0xFFD4AF37), 
                                    side: const BorderSide(color: Color(0xFFD4AF37), width: 3), 
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100)),
                                    backgroundColor: Colors.transparent, 
                                  ),
                                  onPressed: _showLocationTypeSelect,
                                  child: const Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text('🎣 ', style: TextStyle(fontSize: 24)), 
                                      Text('출 조 하 기', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
                                    ],
                                  ),
                                ),
                              ),
                              
                              const SizedBox(height: 16), 

                              // 🏆 [2. KREFT 아레나 버튼]
                              SizedBox(
                                width: 250, height: 70, 
                                child: OutlinedButton(
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: const Color(0xFFD4AF37), 
                                    side: const BorderSide(color: Color(0xFFD4AF37), width: 3), 
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100)),
                                    backgroundColor: Colors.transparent, 
                                  ),
                                  onPressed: () {
                                    Navigator.push(context, MaterialPageRoute(builder: (context) => const ArenaScreen()));
                                  },
                                  child: const Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.emoji_events, size: 28), 
                                      SizedBox(width: 8),
                                      Text('KREFT 아레나', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
                                    ],
                                  ),
                                ),
                              ),
                              
                              const SizedBox(height: 16),
                              
                              // 🎒 [3. 내 가방 버튼]
                              SizedBox(
                                width: 250, height: 70, 
                                child: OutlinedButton(
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: const Color(0xFFD4AF37), 
                                    side: const BorderSide(color: Color(0xFFD4AF37), width: 3), 
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100)),
                                    backgroundColor: Colors.transparent, 
                                  ),
                                  onPressed: () {
                                    audioManager.playSfx("sfx_click.mp3");
                                    _showLobbyInventoryPopup(); 
                                  },
                                  child: const Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.backpack, size: 28),
                                      SizedBox(width: 8),
                                      Text('내 가방 (인벤토리)', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                                    ],
                                  ),
                                ),
                              ),

                              const SizedBox(height: 20),
                              const Text('🏆 실시간 대물 랭킹 1위에 도전해보세요!', style: TextStyle(color: Color.fromARGB(255, 241, 241, 241), fontSize: 18)),
                            ],
                          ),

                          // 2️⃣ 🚩 [로비 배지 벌크업 수정 완료!]
                          Positioned(
                            top: 40, // 💡 기존 30에서 모서리 여백을 조금 더 여유 있게
                            left: 40, // 💡 기존 30에서 모서리 여백을 조금 더 여유 있게
                            child: Container(
                              // 👇 💡 패딩을 확 늘려서 박스 크기를 키웁니다! (14/6 -> 24/12)
                              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                              decoration: BoxDecoration(
                                color: const Color(0xFFD4AF37).withValues(alpha: 0.2), 
                                // 👇 💡 박스가 커지니 둥근 테두리도 조금 더 둥글게 (8 -> 12)
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: const Color(0xFFD4AF37), width: 2.0), // 테두리 두께도 살짝 보강 (1.5 -> 2.0)
                              ),
                              child: const Text(
                                '로비',
                                style: TextStyle(
                                  color: Color(0xFFD4AF37),
                                  // 👇 💡 폰트 크기를 대폭 확대!! (16 -> 24)
                                  fontSize: 24, 
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ], 
                      );
                    }
                    return const Center(child: CircularProgressIndicator());
                  },
                ),
              ),
              Expanded(
                flex: 3,
                child: Padding(
                  padding: const EdgeInsets.all(30.0),
                  child: Center(
                    child: _buildRankingBoard(), 
                  ),
                ),
              ),
            ],
          ),
        ), // Scaffold 끝

        // ==========================================================
        // 2. 👧 윤슬 가이드 투어 레이어 (화면 제일 위에!)
        // ==========================================================
        if (_lobbyStep == 0)
          NpcTutorialOverlay(
            text: "조사님, 여기가 로비예요! ✨\n오른쪽에 [명예의 전당] 보이시죠? \n실시간 랭킹을 확인하실 수 있어요! 🏆",
            imagePath: "assets/images/npc_girl_intro.png",
            onTap: () => setState(() => _lobbyStep = 1),
          ),
        if (_lobbyStep == 1)
          NpcTutorialOverlay(
            text: "왼쪽 [출조하기] [KREFT아레나] 보이시죠.\n화면 왼쪽의 [출조하기] 버튼을 누르고\n'민물 낚시'를 선택해 볼까요? 😊",
            imagePath: "assets/images/npc_girl_point.png",
            onTap: () => setState(() => _lobbyStep = -1), // 🚀 여기서 윤슬님 퇴장! (유저가 직접 클릭하게 유도)
          ),
       
       // ==========================================================
        // 📅 매일 1회 출석체크 & 핫타임 미션 브리핑 (아라 등장!)
        // ==========================================================
       if (_showDailyBriefing)
          Stack(
            children: [
              // 1. 원래 뜨던 아라 매니저 팝업창
              NpcTutorialOverlay(
                text: _getBriefingText(), 
                imagePath: "assets/images/npc_manager.png",
                onTap: () {
                  FlutterTts().stop(); // 혹시 말하다가 닫으면 입 막기!
                  setState(() => _showDailyBriefing = false);
                },
              ),
              
              // 2. 🔊 [UI 대수술] 모바일 하단바 간섭 없는 안전지대로 이동!
              Positioned(
                bottom: 110, // 🚨 기존 40 -> 130으로 확 올려서 사파리/크롬 주소창 완벽 회피!
                left: -550,
                right: 0, // 🚨 좌우 0으로 주면 '가운데 정렬'이 됩니다!
                child: Center(
                  child: SizedBox(
                    width: 220, // 버튼을 뚱뚱하게! (오터치 방지)
                    height: 55, // 버튼을 큼직하게!
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.volume_up, color: Colors.white, size: 28),
                      label: const Text('음성으로 듣기', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.white)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blueAccent,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                        elevation: 10, // 그림자를 빡! 줘서 눈에 띄게
                      ),
                      onPressed: () async {
                        // 🎙️ 대본에서 특수문자 청소!
                        String cleanText = _getBriefingText()
                            .replaceAll('☀️', '')
                            .replaceAll('☕', '')
                            .replaceAll('🌙', '')
                            .replaceAll('🏆', '')
                            .replaceAll('🥇', '')
                            .replaceAll('🥈', '')
                            .replaceAll('🥉', '')
                            .replaceAll('⏰', '')
                            .replaceAll('📍', '')
                            .replaceAll('🎣', '')
                            .replaceAll('🐟', '')
                            .replaceAll('🔥', '')
                            .replaceAll('😊', '')
                            .replaceAll('✨', '')
                            .replaceAll('☀', '')
                            .replaceAll('P', '포인트');

                        try {
                          // 🚨 웹 전용 순정 마이크 소환!
                          html.window.speechSynthesis?.cancel(); // 혹시 말하던 중이면 멈춤
                          final utterance = html.SpeechSynthesisUtterance(cleanText);
                          utterance.lang = 'ko-KR';
                          utterance.rate = 1.2;
                          utterance.pitch = 1.0;
                          html.window.speechSynthesis?.speak(utterance);
                        } catch (e) {
                          // 혹시라도 웹 마이크가 에러나면 플러터 기본 마이크로 백업 가동!
                          FlutterTts tts = FlutterTts();
                          await tts.setLanguage("ko-KR");
                          await tts.speak(cleanText);
                        }
                      },
                    ),
                  ),
                ),
              ),
            ],
          ), // 아라 팝업 Stack 끝
      ], // 전체 화면 Stack 끝
    );
  }
}

// 🗺️ [낚시터 선택 화면] - 전국 출조지 리스트
// 🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩
class LocationSelectScreen extends StatefulWidget {
  final String nickname;
  final int level;
  final bool initialIsSeaMode;
  final bool isFirstTime; // 🚀 로비에서 넘어온 꼬리표 받기!

  const LocationSelectScreen({
    super.key, 
    required this.nickname, 
    required this.level, 
    required this.initialIsSeaMode,
    this.isFirstTime = false, // 🚀 기본값 false
  });

  @override
  State<LocationSelectScreen> createState() => _LocationSelectScreenState();
}

class _LocationSelectScreenState extends State<LocationSelectScreen> {
  late bool isSeaMode;
  String selectedSubCategory = '저수지';
  int _locStep = -1; // 💡 낚시터 화면 전용 윤슬님 스텝!

  @override
  void initState() {
    super.initState();
    isSeaMode = widget.initialIsSeaMode;
    selectedSubCategory = isSeaMode ? '갯바위' : '저수지';
    audioManager.playBgm('bgm_menu.mp3'); 
    _pickTodayHotSpot(); 

    // 🚀 [2단계 철벽!] 서버에서 진짜 내 경험치를 몰래 확인해서 윤슬이를 띄울지 결정합니다.
    _checkExpForTutorial();
  }

  // 🚀 [새로 추가된 함수] 튜토리얼 윤슬이 등장 여부를 완벽하게 결정!
  Future<void> _checkExpForTutorial() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    
    final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
    if (doc.exists) {
      int myExp = doc.data()!.containsKey('exp') ? doc.data()!['exp'] : 0;
      
      // 경험치가 딱 '0'이고, '민물낚시' 화면일 때만 윤슬이가 등장합니다! (바다에서는 절대 안 나옴!)
      if (myExp == 0 && !isSeaMode) {
        if (mounted) {
          setState(() => _locStep = 0);
        }
      } else {
        // 경험치가 있거나 바다낚시면 윤슬이 강제 퇴근!
        if (mounted) {
          setState(() => _locStep = -1);
        }
      }
    }
  }

  void _pickTodayHotSpot() {
    if (fwHotSpot != null && seaHotSpot != null) return;
    List<String> fwNames = ['예산 예당지', '안성 고삼지', '충주 충주호', '춘천 파로호', '진천 백곡지', '예산 신양수로', '청양 지천', '인천 청라수로', '해남 금자천', '충주 달천'];
    List<String> seaNames = ['통영 척포 갯바위', '신안 가거도', '완도 청산도', '여수 거문도', '제주 섶섬', '거제 선상', '오천항 선상', '완도 선상', '통영 선상', '대천 선상'];
    fwHotSpot = fwNames[math.Random().nextInt(fwNames.length)];
    seaHotSpot = seaNames[math.Random().nextInt(seaNames.length)];
  }

  @override
  Widget build(BuildContext context) {
    List<Map<String, dynamic>> currentList = locations[selectedSubCategory] ?? [];

    return Stack( // 🚀 윤슬님 띄우려고 Stack으로 감쌌습니다!
      children: [
        Scaffold(
          backgroundColor: const Color(0xFF121212),
          appBar: AppBar(backgroundColor: Colors.black, title: const Text('어디로 떠나시겠습니까?', style: TextStyle(fontSize: 20, color: Colors.white)), centerTitle: true, leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () { audioManager.playSfx('sfx_click.mp3'); Navigator.pop(context); })),
          body: Column(
            children: [
              // 🏆 [수술 완료] 밋밋했던 상단 탭을 대형 럭셔리 카드로 교체!
              // 🏆 [가로 다이어트 완료] 좌우 여백을 늘려 박스 크기 반토막!
              Container(
                padding: const EdgeInsets.symmetric(vertical: 1, horizontal: 400), // 📉 [핵심] 좌우 여백(60)을 줘서 가운데로 몰아넣음!
                color: Colors.black, 
                child: Row(
                  children: isSeaMode 
                    ? [
                        _buildLargeLocationTypeButton('갯바위', Icons.terrain, const Color(0xFF2A3441)), 
                        const SizedBox(width: 10), // 버튼 간격도 15 -> 10으로 슬림하게!
                        _buildLargeLocationTypeButton('선상', Icons.directions_boat, const Color(0xFF0D1E3A))
                      ] 
                    : [
                        _buildLargeLocationTypeButton('저수지', Icons.landscape, const Color(0xFF0D1E3A)), 
                        const SizedBox(width: 10), 
                        _buildLargeLocationTypeButton('수로', Icons.water, const Color(0xFF133F2B))
                      ]
                )
              ),
              // 🚨 사장님이 실수로 날려버리신 낚시터 리스트 복구!!
              Expanded(child: ListView.builder(padding: const EdgeInsets.all(16), itemCount: currentList.length, itemBuilder: (context, index) { return _locationCard(currentList[index]); })),
              Container(padding: const EdgeInsets.all(12), color: Colors.black, child: const Text('✨ 다음 업데이트 예정: 포인트 선택 기능 !', style: TextStyle(color: Color(0xFFD4AF37), fontSize: 12, fontWeight: FontWeight.bold))),
            ],
          ),
        ),

        // ==========================================================
        // 👧 낚시터 선택 윤슬 가이드 레이어
        // ==========================================================
        if (_locStep == 0)
          NpcTutorialOverlay(
            text: "민물낚시는 저수지5곳 수로5곳이 있어요.\n낚시터 아래 [별점⭐]은 난이도랍니다!\n별이 많을 수록 난이도가 높아요!",
            imagePath: "assets/images/npc_girl_intro.png",
            onTap: () => setState(() => _locStep = 1),
          ),
        if (_locStep == 1)
          NpcTutorialOverlay(
            text: "초보 때는 난이도가 낮은 곳이 좋아요.\n[예당지]에서 낚시방법을 알려드릴께요.\n자, 그럼 예당저수지의 [출조하기]를 눌러서 출발해 볼까요? 🎣",
            imagePath: "assets/images/npc_girl_point.png",
            onTap: () => setState(() => _locStep = -1), 
          ),
      ],
    );
  }

  // 🎨 [신규 대형 카드 버튼] 다이어트 완료 버전!
  Widget _buildLargeLocationTypeButton(String title, IconData icon, Color bgColor) {
    bool isSelected = selectedSubCategory == title;
    return Expanded( 
      child: GestureDetector(
        onTap: () { 
          audioManager.playSfx('sfx_click.mp3'); 
          setState(() => selectedSubCategory = title); 
        },
        child: Container(
          height: 75, // 📉 [다이어트 1] 껍데기 높이를 110 -> 75로 대폭 축소!
          decoration: BoxDecoration(
            color: isSelected ? bgColor : bgColor.withOpacity(0.3), 
            borderRadius: BorderRadius.circular(12), // 모서리도 살짝 덜 둥글게(15->12)
            border: Border.all(
              color: isSelected ? const Color(0xFFD4AF37) : const Color(0xFFD4AF37).withOpacity(0.3),
              width: isSelected ? 2.5 : 1.0, // 선택됐을 때 테두리 두께도 살짝 슬림하게(3.0->2.5)
            ),
            boxShadow: isSelected ? [ 
              BoxShadow(color: const Color(0xFFD4AF37).withOpacity(0.4), blurRadius: 10, spreadRadius: 1),
            ] : null,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: isSelected ? const Color(0xFFD4AF37) : Colors.white54, size: 30), // 📉 [다이어트 2] 아이콘 크기 45 -> 30 축소
              const SizedBox(height: 4), // 📉 [다이어트 3] 아이콘과 글자 사이 여백 10 -> 4 축소
              Text(
                title, 
                style: TextStyle(
                  color: isSelected ? const Color(0xFFD4AF37) : Colors.white54, 
                  fontWeight: FontWeight.w900, 
                  fontSize: 18 // 📉 [다이어트 4] 폰트 크기 22 -> 18 축소
                )
              ),
            ]
          ),
        ),
      ),
    );
  }

  Widget _locationCard(Map<String, dynamic> loc) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.grey.shade900,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFD4AF37).withOpacity(0.5), width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 24.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // 1️⃣ 첫 번째 칸: 낚시터 이름 (폰트 28 + 두께 최고치 + 쌩 화이트!)
            Expanded(
              flex: 2, 
              child: Text(
                loc['name'], 
                style: const TextStyle(
                  color: Colors.white, // 완전 쌩 흰색 보장!
                  fontSize: 28, // 📈 기존 24 -> 28로 떡상!
                  fontWeight: FontWeight.w900 // 글씨 두께도 제일 두껍게!
                )
              ),
            ),
            
            // 2️⃣ 두 번째 칸: 난이도 (글자도 키우고, 별 크기도 키움!)
            Expanded(
              flex: 2, 
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('난이도', style: TextStyle(color: Colors.white70, fontSize: 18, fontWeight: FontWeight.bold)), // 📈 기존 14 -> 18!
                  const SizedBox(height: 6), 
                  Row(
                    children: List.generate(5, (index) { 
                      return Icon(
                        index < (loc['stars'] as int) ? Icons.star : Icons.star_border, 
                        color: const Color(0xFFD4AF37), 
                        size: 30 // 📈 별 크기 기존 22 -> 26!
                      ); 
                    })
                  ),
                ],
              ),
            ),

            // 3️⃣ 세 번째 칸: 낚시터 설명 (쌩 화이트 + 폰트 20으로 떡상!)
            Expanded(
              flex: 4, 
              child: Text(
                '💡 ${loc['target']}', 
                style: const TextStyle(
                  color: Colors.white, // 투명도 다 빼고 완전 흰색!
                  fontSize: 20, // 📈 기존 16 -> 20!
                  height: 1.4,
                  fontWeight: FontWeight.w600 // 설명도 살짝 두껍게 처리!
                )
              ),
            ),

            // 4️⃣ 네 번째 칸: 출조하기 버튼 (글자가 커진 만큼 버튼도 살짝 더 벌크업!)
            SizedBox(
              width: 150, // 📈 기존 140 -> 150
              height: 60, // 📈 기존 55 -> 60
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFD4AF37), 
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () {
                  audioManager.playSfx('sfx_click.mp3');
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (context) => FishingScreen(
                      nickname: widget.nickname, 
                      locationName: loc['name'],
                      winCondition: '마릿수', 
                      title: loc['name'], 
                      bgImagePath: loc['image'],
                      characterImagePath: 'assets/images/character.png', 
                      isSea: isSeaMode,
                      isFirstTime: widget.isFirstTime,
                    )),
                  );
                },
                child: const Text('출조하기', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)), // 📈 버튼 글씨 18 -> 20
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// 🛒 [KREFT 공식 상점]
// 🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩
class StoreScreen extends StatefulWidget {
  final int currentGold;
  final int currentLevel;
  final List<dynamic> currentInventory; 

  const StoreScreen({super.key, required this.currentGold, required this.currentLevel, required this.currentInventory});

  @override
  State<StoreScreen> createState() => _StoreScreenState();
} 

class _StoreScreenState extends State<StoreScreen> {
  late int myDisplayGold;
  late List<dynamic> myInventory; // 판매 탭에서 쓰는 내 인벤토리(상태로 관리)
  String _sellTab = '장비'; // 💰 판매 탭 안의 서브탭: 장비 / 물고기
  String currentTab = 'ROD';

  @override
  void initState() {
    super.initState();
    myDisplayGold = widget.currentGold;
    myInventory = List.from(widget.currentInventory);
  }

  // 상점 정가 조회(이름으로) — 판매가 계산에 사용
  int? _storePriceOf(String name) {
    for (final list in [storeRodItems, storeGearItems, storeBaitItems, storeSkinItems]) {
      for (final it in list) {
        if (it['name'] == name) return (it['price'] as int?) ?? 0;
      }
    }
    return null;
  }

  bool _isBaitItem(Map<String, dynamic> item) {
    final t = (item['type'] ?? '').toString().toUpperCase();
    final c = (item['category'] ?? '').toString().toUpperCase();
    return t.contains('BAIT') || c.contains('BAIT') ||
        ['지렁이', '글루텐', '옥수수', '크릴', '갯지렁이', '루어'].contains((item['name'] ?? '').toString());
  }

  // 판매가: 정가의 50%(없으면 기본 100P). 미끼는 개당 5P × 수량(묶음 전체).
  int _sellPrice(Map<String, dynamic> item) {
    final name = (item['name'] ?? '').toString();
    final qty = (item['quantity'] is num) ? (item['quantity'] as num).toInt() : 1;
    if ((item['type'] ?? '') == 'FISH') return fishSellPrice(name) * qty; // 🐟 잡은 고기: 어종별 마리당 가격 × 수량
    if (_isBaitItem(item)) return (5 * qty).clamp(5, 999999);
    final p = _storePriceOf(name);
    // 무료 지급품(0P)도 인벤 정리용으로 팔 수 있게 (구매는 막아서 되팔이 악용 방지)
    final unit = (p != null && p > 0) ? (p * 0.5).floor() : 100;
    return unit < 10 ? 10 : unit;
  }

  // 부위 분류(최상급 보호 판단용)
  String _slotType(Map<String, dynamic> item) {
    final n = (item['name'] ?? '').toString().replaceAll(' ', '').toUpperCase();
    if (n.contains('찌')) return 'float';
    if (n.contains('스킨') || n.contains('조사') || n.contains('초보') || n.contains('마스터')) return 'skin';
    if ((n.contains('릴') && !n.contains('크릴')) ||
        n.contains('2000') || n.contains('3000') || n.contains('5000') ||
        n.contains('6000') || n.contains('8000')) {
      return 'reel';
    }
    if (n.contains('대') || n.contains('CF') || n.contains('KT')) return 'rod';
    if (n.contains('선글라스')) return 'sun';
    if (n.contains('휘장')) return 'badge';
    if (_isBaitItem(item)) return 'bait';
    return 'etc';
  }

  // 등급(정가 우선, 없으면 스탯 합)
  int _gradeOf(Map<String, dynamic> item) {
    final p = _storePriceOf((item['name'] ?? '').toString());
    if (p != null && p > 0) return p;
    final s = item['stats'];
    if (s is Map) {
      int v(String k) => (s[k] is num) ? (s[k] as num).toInt() : 0;
      return v('P') + v('C') + v('S');
    }
    return 0;
  }

  // 보유 중 같은 부위에서 가장 좋은(최상급) 아이템인가? (실수 판매 방지)
  bool _isTopGrade(Map<String, dynamic> item) {
    final type = _slotType(item);
    if (!['rod', 'reel', 'float', 'skin', 'sun', 'badge'].contains(type)) return false;
    final myGrade = _gradeOf(item);
    if (myGrade <= 0) return false;
    int maxGrade = 0;
    for (final o in myInventory) {
      final om = o as Map<String, dynamic>;
      if (_slotType(om) == type) {
        final g = _gradeOf(om);
        if (g > maxGrade) maxGrade = g;
      }
    }
    return myGrade >= maxGrade;
  }

  void _showNotificationPopup(String t, String c, Color col, {VoidCallback? onConfirm}) {
    showDialog(context: context, barrierDismissible: false, builder: (ctx) => AlertDialog(backgroundColor: Colors.grey.shade900, title: Text(t, style: TextStyle(color: col, fontWeight: FontWeight.bold)), content: Text(c, style: const TextStyle(color: Colors.white)), actions: [ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFD4AF37), foregroundColor: Colors.black), onPressed: () { Navigator.pop(ctx); onConfirm?.call(); }, child: const Text('확인', style: TextStyle(fontWeight: FontWeight.bold)))]));
  }

  @override
  Widget build(BuildContext context) {
    List<Map<String, dynamic>> displayList = [];
    if (currentTab == 'ROD') displayList = storeRodItems;
    if (currentTab == 'GEAR') displayList = storeGearItems;
    if (currentTab == 'BAIT') displayList = storeBaitItems;
    if (currentTab == 'SKIN') displayList = storeSkinItems;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('🛒 KREFT OFFICIAL STORE', style: TextStyle(color: Color(0xFFD4AF37), fontWeight: FontWeight.bold)), backgroundColor: Colors.black, iconTheme: const IconThemeData(color: Colors.white),
        actions: [Center(child: Padding(padding: const EdgeInsets.only(right: 20), child: Text('내 포인트: $myDisplayGold P', style: const TextStyle(color: Colors.yellowAccent, fontWeight: FontWeight.bold, fontSize: 16))))],
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.only(left: 20), 
            child: Row(
              mainAxisAlignment: MainAxisAlignment.start, 
              children: ['ROD', 'GEAR', 'BAIT', 'SKIN', 'SELL'].map((tab) {
                String label = tab == 'ROD' ? '낚싯대' : tab == 'GEAR' ? '릴/찌' : tab == 'BAIT' ? '미끼' : tab == 'SKIN' ? '스킨/기타' : '💰 팔기';
                bool isSelected = currentTab == tab;
                return GestureDetector(
                  onTap: () { setState(() => currentTab = tab); },
                  child: Container(margin: const EdgeInsets.only(right: 40), padding: const EdgeInsets.symmetric(vertical: 15), decoration: BoxDecoration(border: Border(bottom: BorderSide(color: isSelected ? const Color(0xFFD4AF37) : Colors.transparent, width: 3))), child: Text(label, style: TextStyle(color: isSelected ? const Color(0xFFD4AF37) : Colors.grey, fontWeight: FontWeight.bold, fontSize: 16))),
                );
              }).toList(), 
            ),
          ),
          Expanded(
            child: currentTab == 'SELL'
                ? _buildSellList()
                : GridView.builder(padding: const EdgeInsets.all(20), gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 1, mainAxisSpacing: 20, crossAxisSpacing: 20, mainAxisExtent: 160), itemCount: displayList.length, itemBuilder: (context, index) { return _buildStoreItem(displayList[index]); }),
          ),
        ],
      ),
    );
  }

  Widget _buildSellList() {
    final all = myInventory.map((e) => e as Map<String, dynamic>).toList();
    final gear = all.where((i) => (i['type'] ?? '') != 'FISH').toList();
    final fishes = all.where((i) => (i['type'] ?? '') == 'FISH').toList();
    final showFish = _sellTab == '물고기';
    final list = showFish ? fishes : gear;
    final fishTotal = fishes.fold<int>(0, (s, i) => s + _sellPrice(i)); // 물고기 일괄판매 총액

    Widget subTab(String label, int count) {
      final active = _sellTab == label;
      return Expanded(
        child: GestureDetector(
          onTap: () => setState(() => _sellTab = label),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 4),
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: active ? const Color(0xFFD4AF37) : Colors.grey.shade800,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text('$label ($count)',
                textAlign: TextAlign.center,
                style: TextStyle(color: active ? Colors.black : Colors.white70, fontSize: 15, fontWeight: FontWeight.w900)),
          ),
        ),
      );
    }

    return Column(children: [
      // 서브탭: 장비 / 물고기
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
        child: Row(children: [subTab('장비', gear.length), subTab('물고기', fishes.length)]),
      ),
      // 안내 + (물고기 탭) 일괄판매 버튼
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
        child: showFish
            ? Row(children: [
                const Expanded(child: Text('🐟 잡은 고기를 팔아 포인트로! (마리당 가격)', style: TextStyle(color: Colors.white60, fontSize: 13, fontWeight: FontWeight.bold))),
                if (fishes.isNotEmpty)
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2E7D32), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10)),
                    onPressed: () => _confirmSellAllFish(fishes, fishTotal),
                    child: Text('전부 팔기 (+$fishTotal P)', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
                  ),
              ])
            : const Text('💡 필요 없는 장비를 팔아 포인트로! (판매가 = 정가의 50%)', style: TextStyle(color: Colors.white60, fontSize: 13, fontWeight: FontWeight.bold)),
      ),
      Expanded(
        child: list.isEmpty
            ? Center(child: Text(showFish ? '잡은 물고기가 없어요.\n낚시하러 가볼까요?' : '판매할 장비가 없어요.', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white54, fontSize: 16)))
            : GridView.builder(
                padding: const EdgeInsets.all(20),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 1, mainAxisSpacing: 14, crossAxisSpacing: 14, mainAxisExtent: 110),
                itemCount: list.length,
                itemBuilder: (context, index) => _buildSellItem(list[index]),
              ),
      ),
    ]);
  }

  // 🐟 물고기 일괄판매 (모든 어종)
  void _confirmSellAllFish(List<Map<String, dynamic>> fishes, int total) {
    audioManager.playSfx("sfx_click.mp3");
    final totalCount = fishes.fold<int>(0, (s, i) => s + ((i['quantity'] is num) ? (i['quantity'] as num).toInt() : 1));
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.grey.shade900,
        title: const Text('🐟 물고기 전부 팔기', style: TextStyle(color: Color(0xFFD4AF37), fontWeight: FontWeight.bold)),
        content: Text('가방의 물고기 $totalCount마리를 모두 팔고\n$total P를 받습니다.\n판매하시겠습니까?', style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소', style: TextStyle(color: Colors.grey))),
          TextButton(onPressed: () { Navigator.pop(ctx); _sellAllFish(total); }, child: const Text('전부 판매', style: TextStyle(color: Color(0xFF7FFFB0), fontWeight: FontWeight.bold))),
        ],
      ),
    );
  }

  void _sellAllFish(int total) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      List<dynamic> inventory = List.from(userDoc.data()?['inventory'] ?? []);
      inventory.removeWhere((i) => (i['type'] ?? '') == 'FISH'); // 모든 물고기 제거
      await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
        'gold': FieldValue.increment(total),
        'inventory': inventory,
      });
      if (!mounted) return;
      setState(() {
        myInventory.removeWhere((i) => (i['type'] ?? '') == 'FISH');
        myDisplayGold += total;
      });
      _showNotificationPopup('🎉 일괄 판매 완료', '물고기를 모두 팔고\n$total P를 받았습니다!', const Color(0xFF7FFFB0));
    } catch (e) {
      debugPrint('일괄판매 에러: $e');
    }
  }

  Widget _buildSellItem(Map<String, dynamic> item) {
    String itemName = item['name'].toString();
    String imgPath = item['icon']?.toString() ?? '';
    // 🐟 물고기 이미지는 어떤 폴더로 저장됐든 실제 위치로 보정
    final iconFile = imgPath.split('/').last;
    if (iconFile.startsWith('fish_fw')) { imgPath = 'assets/fish_fw/$iconFile'; }
    else if (iconFile.startsWith('fish_sea')) { imgPath = 'assets/fish_sea/$iconFile'; }
    else {
      if (imgPath.contains('../')) imgPath = imgPath.replaceAll('../', 'assets/');
      if (!imgPath.startsWith('assets/')) imgPath = imgPath.contains('.jpg') ? 'assets/images/$imgPath' : 'assets/items/$imgPath';
    }
    final qty = (item['quantity'] is num) ? (item['quantity'] as num).toInt() : 1;
    final bait = _isBaitItem(item);
    final price = _sellPrice(item);
    final isBeginner = itemName.contains('초보');
    final isTop = !isBeginner && _isTopGrade(item); // 부위별 최상급 → 판매 완전 차단
    final sellable = !isBeginner && !isTop;

    return Container(
      decoration: BoxDecoration(color: const Color(0xFF151515), borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.white10)),
      child: Row(children: [
        Container(width: 100, padding: const EdgeInsets.all(12), decoration: const BoxDecoration(color: Colors.black38, borderRadius: BorderRadius.only(topLeft: Radius.circular(15), bottomLeft: Radius.circular(15))), child: Image.asset(imgPath, fit: BoxFit.contain, errorBuilder: (c, e, s) => const Icon(Icons.broken_image, color: Colors.white24, size: 32))),
        Container(width: 1, color: Colors.white10),
        Expanded(
          flex: 3,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(itemName, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900), overflow: TextOverflow.ellipsis),
              const SizedBox(height: 6),
              if (isTop)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                      color: const Color(0xFFD4AF37).withOpacity(0.18),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFD4AF37))),
                  child: const Text('⭐ 보유 최상급 — 판매 잠금',
                      style: TextStyle(color: Color(0xFFD4AF37), fontSize: 12, fontWeight: FontWeight.bold)),
                )
              else if ((item['type'] ?? '') == 'FISH')
                Text('보유 수량: $qty마리  (마리당 ${fishSellPrice(itemName)}P)', style: const TextStyle(color: Colors.yellowAccent, fontSize: 13, fontWeight: FontWeight.bold))
              else if (bait)
                Text('보유 수량: x$qty개', style: const TextStyle(color: Colors.yellowAccent, fontSize: 13, fontWeight: FontWeight.bold)),
            ]),
          ),
        ),
        Container(width: 1, color: Colors.white10),
        Expanded(
          flex: 2,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Center(child: Text(sellable ? '+$price P' : (isTop ? '🔒 잠금' : '판매 불가'), style: TextStyle(color: sellable ? const Color(0xFF7FFFB0) : (isTop ? const Color(0xFFD4AF37) : Colors.white38), fontSize: 18, fontWeight: FontWeight.w900))),
              const SizedBox(height: 8),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: sellable ? const Color(0xFF2E7D32) : Colors.grey.shade800,
                    foregroundColor: sellable ? Colors.white : Colors.white38,
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                onPressed: sellable ? () => _confirmSell(item, price, bait, qty) : null,
                child: Text(sellable ? '팔기' : (isTop ? '최상급 보호' : '기본 지급'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              ),
            ]),
          ),
        ),
      ]),
    );
  }

  void _confirmSell(Map<String, dynamic> item, int price, bool bait, int qty) {
    audioManager.playSfx("sfx_click.mp3");
    final name = item['name'].toString();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.grey.shade900,
        title: const Text('💰 아이템 판매', style: TextStyle(color: Color(0xFFD4AF37), fontWeight: FontWeight.bold)),
        content: Text(
            bait
                ? '$name x$qty개를 팔고 $price P를 받습니다.\n판매하시겠습니까?'
                : '$name 을(를) 팔고 $price P를 받습니다.\n판매하시겠습니까?',
            style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소', style: TextStyle(color: Colors.grey))),
          TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                _sellItem(item, price);
              },
              child: const Text('판매', style: TextStyle(color: Color(0xFF7FFFB0), fontWeight: FontWeight.bold))),
        ],
      ),
    );
  }

  void _sellItem(Map<String, dynamic> item, int price) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final name = item['name'].toString();
    try {
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      List<dynamic> inventory = List.from(userDoc.data()?['inventory'] ?? []);
      inventory.removeWhere((i) => i['name'] == name); // 묶음 전체 판매

      await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
        'gold': FieldValue.increment(price),
        'inventory': inventory,
      });

      // 장착 중이던 장비면 장착 해제(이미지/스텟 꼬임 방지)
      if (globalEquippedRod?['name'] == name) globalEquippedRod = null;
      if (globalEquippedReel?['name'] == name) globalEquippedReel = null;
      if (globalEquippedFloat?['name'] == name) globalEquippedFloat = null;
      if (globalEquippedBait?['name'] == name) globalEquippedBait = null;
      if (globalEquippedSkin?['name'] == name) globalEquippedSkin = null;
      if (globalEquippedSunglasses?['name'] == name) globalEquippedSunglasses = null;
      if (globalEquippedBadge?['name'] == name) globalEquippedBadge = null;

      if (!mounted) return;
      setState(() {
        myInventory.removeWhere((i) => i['name'] == name);
        myDisplayGold += price;
      });
      _showNotificationPopup('🎉 판매 완료', '$name 을(를) 팔고\n$price P를 받았습니다!', const Color(0xFF7FFFB0));
    } catch (e) {
      print(e);
      _showNotificationPopup('오류', '판매 처리 중 문제가 발생했습니다.', Colors.redAccent);
    }
  }

  Widget _buildStatBadge(String label, int val, Color color) {
    return Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(10), border: Border.all(color: color.withOpacity(0.5))), child: Text('$label $val', style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.bold)));
  }

  Widget _buildStoreItem(Map<String, dynamic> item) {
    bool isBait = item['type'] == 'BAIT';
    bool isSkin = item['type'] == 'SKIN';
    String itemName = item['name'].toString();
    String imgPath = item['icon']?.toString() ?? '';
    if (imgPath.contains('../')) imgPath = imgPath.replaceAll('../', 'assets/');
    if (!imgPath.startsWith('assets/')) imgPath = imgPath.contains('.jpg') ? 'assets/images/$imgPath' : 'assets/items/$imgPath';

    return Container(
      decoration: BoxDecoration(color: const Color(0xFF151515), borderRadius: BorderRadius.circular(15), border: Border.all(color: isSkin ? const Color(0xFFD4AF37).withOpacity(0.8) : Colors.white10, width: isSkin ? 1.5 : 1.0)),
      child: Row(
        children: [
          Container(width: 140, padding: const EdgeInsets.all(15), decoration: const BoxDecoration(color: Colors.black38, borderRadius: BorderRadius.only(topLeft: Radius.circular(15), bottomLeft: Radius.circular(15))), child: Image.asset(imgPath, fit: BoxFit.contain, errorBuilder: (c, e, s) => const Icon(Icons.broken_image, color: Colors.white24, size: 40))),
          Container(width: 1, color: Colors.white10),
          Expanded(flex: 3, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15), child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [Text(itemName, style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w900), overflow: TextOverflow.ellipsis), const SizedBox(height: 12), if (item['stats'] != null) Row(children: [_buildStatBadge('파워', item['stats']['P'] ?? 0, Colors.redAccent), const SizedBox(width: 6), _buildStatBadge('컨트롤', item['stats']['C'] ?? 0, Colors.blueAccent), const SizedBox(width: 6), _buildStatBadge('감도', item['stats']['S'] ?? 0, Colors.greenAccent)]) else if (isBait) Text('수량: x${item['quantity']}개', style: const TextStyle(color: Colors.yellowAccent, fontSize: 14, fontWeight: FontWeight.bold)) else const Text('기본 장비', style: TextStyle(color: Colors.grey, fontSize: 13))]))),
          Container(width: 1, color: Colors.white10),
          Expanded(flex: 4, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15), child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [const Row(children: [Icon(Icons.auto_awesome, color: Color(0xFFD4AF37), size: 16), SizedBox(width: 6), Text('장비 효과', style: TextStyle(color: Color(0xFFD4AF37), fontSize: 13, fontWeight: FontWeight.bold))]), const SizedBox(height: 8), Text((item['desc'] ?? '').toString().replaceAll('(쇼핑몰 전용)', '(OBT 스페셜)'), style: TextStyle(color: Colors.grey.shade300, fontSize: 14, height: 1.4), maxLines: 2, overflow: TextOverflow.ellipsis)]))),
          Container(width: 1, color: Colors.white10),
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.all(15.0),
              child: Builder(
                builder: (context) {
                  // 🚫 무료 지급품(0P)은 구매 불가 — 캐릭터 생성 시 지급되는 기본 장비 (되팔이 악용 방지)
                  final isFreeStarter = (item['price'] is num) && (item['price'] as num) <= 0;
                  if (isFreeStarter || (isSkin && itemName.contains('초보'))) return Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.stretch, children: [const Center(child: Text('기본 지급', style: TextStyle(color: Colors.grey, fontSize: 16, fontWeight: FontWeight.bold))), const SizedBox(height: 10), ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.grey.shade900, foregroundColor: Colors.grey, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))), onPressed: null, child: const Text('구매 불가', style: TextStyle(fontWeight: FontWeight.bold)))]);
                  bool isMallOnly = isSkin || itemName.contains('1시간 이용권');
                  if (isMallOnly) {
                    return Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.stretch, children: [const Center(child: Text('9,999,999 P', style: TextStyle(color: Color(0xFFD4AF37), fontSize: 20, fontWeight: FontWeight.w900))), const SizedBox(height: 10), ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.grey.shade800, foregroundColor: Colors.redAccent, padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: Colors.redAccent.withOpacity(0.5)))), onPressed: () { audioManager.playSfx("sfx_click.mp3"); _showNotificationPopup('🚧 오픈 베타 테스트 안내', '현재 OBT 기간으로 해당 상품은\n임시 구매 제한 상태입니다.\n\n(테스트 종료 후 데이터 초기화 방침에 따라\n정식 오픈 이후부터 획득이 가능합니다.)', Colors.amberAccent); }, child: const Text('[OBT] 구매 불가', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)))]);
                  }
                  return Column(
                    mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(child: Text('${item['price']} P', style: const TextStyle(color: Color(0xFFD4AF37), fontSize: 20, fontWeight: FontWeight.w900))), const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(flex: 1, child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.grey.shade800, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))), onPressed: () { ScaffoldMessenger.of(context).hideCurrentSnackBar(); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Row(children: [const Icon(Icons.check_circle, color: Color(0xFFD4AF37)), const SizedBox(width: 10), Expanded(child: Text('$itemName 장바구니 담기 완료!', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)))]), backgroundColor: Colors.grey.shade900, behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: const BorderSide(color: Color(0xFFD4AF37))), duration: const Duration(seconds: 2))); }, child: const Icon(Icons.add_shopping_cart, size: 20))), const SizedBox(width: 8),
                          Expanded(
                            flex: 2,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFD4AF37), foregroundColor: Colors.black, padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                              onPressed: () {
                                String itemCategory = item['category']?.toString().toUpperCase() ?? ''; String itemType = item['type']?.toString().toUpperCase() ?? '';
                                bool isBait = itemCategory.contains('BAIT') || itemCategory.contains('미끼') || itemType.contains('BAIT') || itemType.contains('미끼') || ['지렁이', '글루텐', '옥수수'].contains(itemName);
                                int price = item['price'];
                                if (isBait) { showDialog(context: context, builder: (context) => AlertDialog(backgroundColor: Colors.grey.shade900, title: const Text('🛒 미끼 구매', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)), content: Text('$itemName 구매로 $price P가 차감됩니다.\n구매하시겠습니까?', style: const TextStyle(color: Colors.white70)), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('취소', style: TextStyle(color: Colors.grey))), TextButton(onPressed: () { Navigator.pop(context); _buyItem(item); }, child: const Text('확인', style: TextStyle(color: Color(0xFFD4AF37), fontWeight: FontWeight.bold)))])); } else {
                                  bool isAlreadyOwned = myInventory.any((myItem) => myItem['name'] == itemName);
                                  if (isAlreadyOwned) { _showNotificationPopup('🛑 구매 불가!', '이미 보유 중인 장비입니다!\n인벤토리를 확인해주세요.', Colors.orangeAccent); return; } _buyItem(item);
                                }
                              },
                              child: const Text('🛒 구매하기', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                            ),
                          ),
                        ],
                      ),
                    ],
                  );
                }
              )
            ),
          ),
        ],
      ),
    );
  }

  void _buyItem(Map<String, dynamic> item) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    
    // 🛑 포인트 부족 시 럭셔리 팝업!
    if (item['price'] > 0 && myDisplayGold < item['price']) {
      _showNotificationPopup('🚫 구매 불가', '포인트가 부족합니다!\n열심히 고기를 잡으세요!', Colors.redAccent);
      return;
    }

    try {
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      List<dynamic> inventory = List.from(userDoc.data()?['inventory'] ?? []);
      int existingIndex = inventory.indexWhere((i) => i['name'] == item['name']);
      
      if (existingIndex >= 0) {
        int currentQty = inventory[existingIndex]['quantity'] ?? 0;
        int addQty = item['quantity'] ?? 1;
        inventory[existingIndex]['quantity'] = currentQty + addQty;
      } else {
        inventory.add({
          'name': item['name'], 
          'category': item['category'], 
          'type': item['type'], 
          'stats': item['stats'], 
          'icon': item['icon'], 
          'quantity': item['quantity'] ?? 1
        });
      }
      
      await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
        'gold': FieldValue.increment(-item['price']),
        'inventory': inventory
      });

      // 🎓 튜토리얼 '장비 장만'(보배, tutStep 5) — 아이템 구매하면 미션 완료 기록
      if (((userDoc.data()?['tutStep']) as num?)?.toInt() == 5) {
        await FirebaseFirestore.instance.collection('users').doc(user.uid)
            .set({'tutCleared': true}, SetOptions(merge: true));
      }

      setState(() {
        myDisplayGold -= (item['price'] as int);
        myInventory = List.from(inventory); // 🔄 구매 즉시 내 인벤 갱신(판매탭/중복체크 반영)
      });

      if (!mounted) return;

      // 🛒 결제 성공 시 럭셔리 팝업 발사!
      _showNotificationPopup(
        '🎉 결제 완료',
        '${item['name']}\n성공적으로 구매하셨습니다!\n인벤토리에서 장착해 보세요.', 
        const Color(0xFFD4AF37)
      );
      
    } catch (e) {
      print(e);
      _showNotificationPopup('오류', '구매 처리 중 문제가 발생했습니다.', Colors.redAccent);
    }
  }
}