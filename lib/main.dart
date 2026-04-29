// ignore_for_file: unused_element, unnecessary_non_null_assertion, deprecated_member_use, avoid_print, curly_braces_in_flow_control_structures, empty_catches, use_build_context_synchronously
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'firebase_options.dart';
import 'dart:math' as math;
import 'package:flutter/services.dart'; 
import 'dart:async'; 
import 'package:audioplayers/audioplayers.dart';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

// 🏢 앱 초기화 및 전역 변수 (Global)
// 🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    debugPrint("파이어베이스 초기화 에러: $e");
  }
  runApp(const MyApp());
}

// =========================================================================
// 🌍 [캠피싱 중앙 통제소 전역 변수]
int currentExp = 0;
int currentPoints = 0;
int remainingTime = 3600; 

// 💡 핫스팟을 민물/바다 각각 1곳씩 뽑도록 변수 2개로 나눕니다!
String? fwHotSpot;   
String? seaHotSpot; // 핫스팟일 때 대물 확률/가중치 보너스 배율
// =========================================================================

class AudioManager {
  static final AudioManager _instance = AudioManager._internal();
  factory AudioManager() { return _instance; }
  AudioManager._internal();

  final AudioPlayer bgmPlayer = AudioPlayer();
  final AudioPlayer efxPlayer = AudioPlayer();
  bool isMuted = false;
  String currentBgm = "";

  Future<void> playBgm(String fileName) async {
    if (isMuted) return;
    if (currentBgm == fileName) return; 
    
    currentBgm = fileName;
    await bgmPlayer.setReleaseMode(ReleaseMode.loop);
    await bgmPlayer.play(AssetSource('sound/$fileName'));
  }

  Future<void> playSfx(String fileName) async {
    if (isMuted) return;
    if (fileName.contains('landing') && efxPlayer.state == PlayerState.playing) return;
    await efxPlayer.play(AssetSource('sound/$fileName'));
  }

  void stopEfx() { efxPlayer.stop(); }
  Future<void> stopBgm() async { currentBgm = ""; await bgmPlayer.stop(); }
  Future<void> toggleMute() async {
    isMuted = !isMuted;
    if (isMuted) { await bgmPlayer.pause(); await efxPlayer.stop(); } 
    else { if (currentBgm.isNotEmpty) await bgmPlayer.resume(); }
  }
}

final audioManager = AudioManager();

// 🏢 [별관] 시스템 및 로비 구역 (로그인, 프로필, 맵 선택)
// 🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '캠피싱',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        scaffoldBackgroundColor: Colors.black,
        colorScheme: const ColorScheme.dark(primary: Color(0xFFD4AF37)),
      ),
      builder: (context, child) {
        return Container(
          color: Colors.black,
          child: Center(
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: ClipRect(
                child: FittedBox(
                  fit: BoxFit.contain,
                  child: SizedBox(width: 1280, height: 720, child: child!),
                ),
              ),
            ),
          ),
        );
      },
      home: Builder(
       builder: (context) {
          String? urlUid = Uri.base.queryParameters['uid'];
          
          // 이메일이 달려서 오면 하이패스 톨게이트(2문/3문)로 이동!
          if (urlUid != null && urlUid.trim().isNotEmpty) {
            return AutoLoginScreen(email: urlUid.trim()); 
          }
          
          // 🚪 이메일이 없으면 (로그인을 안 했으면) 1의 문으로 이동!
          return const GuestWarningScreen();
        },
      ),
    );
  }
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _auth = FirebaseAuth.instance;
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nicknameController = TextEditingController();
  final String _selectedFishingType = 'freshwater';
  bool isLoginMode = true;
  bool isLoading = false;

  void showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message), backgroundColor: Colors.redAccent));
  }

  // 💡 12종 캠피싱 스타터 팩
  List<Map<String, dynamic>> _getInitialStarterPack() {
    return [
      {'name': '초보 조사', 'category': 'SKIN', 'type': 'SKIN', 'stats': {'P': 10, 'C': 10, 'S': 10}, 'icon': '../images/skin_novice.jpg', 'desc': 'KREFT 조사의 기본 복장'},
      {'name': 'CF-20T', 'category': 'FW', 'type': 'ROD', 'stats': {'P': 0, 'C': 0, 'S': 0}, 'icon': 'rod_fw_cf20.png', 'desc': '초보 조사용 기본 민물대'},
      {'name': '일반찌', 'category': 'FW', 'type': 'FLOAT', 'stats': {'S': 0}, 'icon': 'float_fw_normal.png', 'desc': '가장 기본적인 민물 찌'},
      {'name': '글루텐', 'category': 'FW', 'type': 'BAIT', 'quantity': 50, 'icon': 'bait_fw_gluten.png', 'desc': '붕어 집어에 탁월한 미끼 (20)'},
      {'name': '지렁이', 'category': 'FW', 'type': 'BAIT', 'quantity': 50, 'icon': 'bait_fw_worm.png', 'desc': '민물 만능 미끼 (10)'},
      {'name': '옥수수', 'category': 'FW', 'type': 'BAIT', 'quantity': 50, 'icon': 'bait_fw_corn.png', 'desc': '대물 붕어용 미끼 (30)'},
      {'name': 'CF250', 'category': 'SEA', 'type': 'ROD', 'stats': {'P': 0, 'C': 0, 'S': 0}, 'icon': 'rod_sea_cf250.png', 'desc': '바다 낚시 입문용 기본대'},
      {'name': 'cf2000', 'category': 'SEA', 'type': 'REEL', 'stats': {'P': 0}, 'icon': 'reel_sea_cf2000.png', 'desc': '기본 제공되는 바다 릴'},
      {'name': '갯지렁이', 'category': 'SEA', 'type': 'BAIT', 'quantity': 50, 'icon': 'bait_sea_worm.png', 'desc': '바다 낚시 기본 미끼 (10)'},
      {'name': '크릴', 'category': 'SEA', 'type': 'BAIT', 'quantity': 50, 'icon': 'bait_sea_krill.png', 'desc': '전천후 바다 미끼 (20)'},
      {'name': '루어', 'category': 'SEA', 'type': 'BAIT', 'quantity': 50, 'icon': 'bait_sea_lure.png', 'desc': '육식성 어종 전용 (30)'},
      {'name': '에기', 'category': 'SEA', 'type': 'BAIT', 'quantity': 50, 'icon': 'bait_sea_egi.png', 'desc': '두족류 전용 미끼 (30)'},
    ];
  }

  Future<void> submitAuth() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    final nickname = _nicknameController.text.trim();

    // 1️⃣ 이메일/비밀번호 빈칸 검사
    if (email.isEmpty || password.isEmpty) { 
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: Colors.grey.shade900,
          title: const Text('안내', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          content: const Text('이메일과 비밀번호를 모두 입력해주세요!', style: TextStyle(color: Colors.white70)),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('확인', style: TextStyle(color: Color(0xFFD4AF37))))],
        ),
      );
      return; 
    }

    // 2️⃣ 닉네임 빈칸 검사 (회원가입 시)
    if (!isLoginMode && nickname.isEmpty) { 
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: Colors.grey.shade900,
          title: const Text('안내', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          content: const Text('멋진 닉네임을 입력해주세요!', style: TextStyle(color: Colors.white70)),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('확인', style: TextStyle(color: Color(0xFFD4AF37))))],
        ),
      );
      return; 
    }
    setState(() { isLoading = true; });

    try {
      if (isLoginMode) {
        await _auth.signInWithEmailAndPassword(email: email, password: password);
        if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const ProfileCheckScreen()));
      } else {
        final userCredential = await _auth.createUserWithEmailAndPassword(email: email, password: password);
        int todayWeekday = DateTime.now().weekday;
        int initialPlayTime = (todayWeekday == DateTime.saturday || todayWeekday == DateTime.sunday) ? 20 : 10;

        await FirebaseFirestore.instance.collection('users').doc(userCredential.user!.uid).set({
          'nickname': nickname, 'fishingType': _selectedFishingType, 'level': 1, 'rank': '초보', 'gold': 1000,
          'inventory': _getInitialStarterPack(), 'playTimeRemaining': initialPlayTime,
          'lastPlayDate': DateTime.now().toIso8601String().substring(0, 10), 'createdAt': FieldValue.serverTimestamp(),
        });

        if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
  SnackBar(
    content: const Text("🎉 캐릭터 생성 완료!\n스타터 팩이 인벤토리에 지급되었습니다.", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16), textAlign: TextAlign.center),
    backgroundColor: const Color(0xFFD4AF37), // 영롱한 KREFT 골드
    behavior: SnackBarBehavior.floating,
    elevation: 10,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
    margin: const EdgeInsets.only(bottom: 50, left: 100, right: 100),
    padding: const EdgeInsets.symmetric(vertical: 15),
  )
);  
          setState(() { isLoginMode = true; _passwordController.clear(); });
        }
      }
    } on FirebaseAuthException catch (e) {
      showSnackBar("오류: ${e.message}");
    } finally {
      if (mounted) setState(() { isLoading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      resizeToAvoidBottomInset: true,
      body: Stack(
        children: [
          // 1. 호수 배경
          Positioned.fill(
            child: Image.asset(
              'assets/fields/bg_yedang.jpg', 
              fit: BoxFit.cover,
              errorBuilder: (c, e, s) => Container(color: Colors.black87), // 혹시 못 찾을 경우 대비
            ),
          ),
          Positioned.fill(child: Container(color: Colors.black.withOpacity(0.4))), // 텍스트가 잘 보이게 살짝 어둡게

          // 2. 메인 UI (블랙 & 골드 로그인 박스)
          Center(
            child: SingleChildScrollView(
              child: Container( 
                width: 400, 
                padding: const EdgeInsets.all(30),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.7), 
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFD4AF37).withOpacity(0.6), width: 1.5),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 20)],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                   Image.asset(
                      'assets/images/symbol.png', 
                      width: 180, 
                      errorBuilder: (c,e,s) => const Icon(Icons.shield, color: Color(0xFFD4AF37), size: 80)
                    ),
                    const SizedBox(height: 40),

                    // 타이틀
                    Text(isLoginMode ? 'MEMBER LOGIN' : 'NEW CHARACTER', style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: 2)),
                    const SizedBox(height: 30),

                    // 아이디(이메일) 입력창
                    _buildInputField(_emailController, 'ID / E-mail', Icons.person),
                    const SizedBox(height: 15),
                    
                    // 비밀번호 입력창
                    _buildInputField(_passwordController, 'Password', Icons.lock, isObscure: true),
                    
                    // 캐릭터 생성 모드일 때만 나오는 닉네임 입력창
                    if (!isLoginMode) ...[
                      const SizedBox(height: 15),
                      _buildInputField(_nicknameController, '조사님 닉네임 (2~8자)', Icons.badge),
                    ],
                    
                    const SizedBox(height: 30),

                    // 로그인 / 생성 버튼
                    SizedBox(
                      width: double.infinity, height: 50,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFD4AF37), foregroundColor: Colors.black,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: isLoading ? null : submitAuth,
                        child: isLoading 
                          ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 3))
                          : Text(isLoginMode ? '로그인' : '캐릭터 생성 완료', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(height: 20),

                      TextButton(
                      onPressed: () { setState(() { isLoginMode = !isLoginMode; _passwordController.clear(); }); },
                      child: Text(isLoginMode ? '신규 캐릭터 생성하기' : '이미 계정이 있으신가요? 로그인', style: TextStyle(color: Colors.grey.shade400, decoration: TextDecoration.underline)),
                    )
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputField(TextEditingController ctrl, String hint, IconData icon, {bool isObscure = false}) {
    return TextField(
      controller: ctrl, obscureText: isObscure, style: const TextStyle(color: Colors.white),
      cursorColor: const Color(0xFFD4AF37),
      decoration: InputDecoration(
        filled: true, fillColor: Colors.black45,
        hintText: hint, hintStyle: TextStyle(color: Colors.grey.shade600),
        prefixIcon: Icon(icon, color: const Color(0xFFD4AF37)),
        contentPadding: const EdgeInsets.symmetric(vertical: 18),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade800)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFD4AF37), width: 2)),
      ),
    );
  }
}

class ProfileCheckScreen extends StatelessWidget {
  const ProfileCheckScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const LoginPage();

    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance.collection('users').doc(user.uid).get(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Scaffold(backgroundColor: Colors.black, body: Center(child: CircularProgressIndicator(color: Color(0xFFD4AF37))));
        if (snapshot.hasData && snapshot.data!.exists) {
          var userData = snapshot.data!.data() as Map<String, dynamic>;
          String dbNickname = userData['nickname'] ?? '조사님';
          int dbLevel = userData['level'] ?? 1; // 💡 첫 번째 에러 해결: DB에서 레벨 가져오기!
          return LobbyScreen(nickname: dbNickname, level: dbLevel); 
        }
        return const LoginPage();
      },
    );
  }
}

// 🏡 [KREFT 매니지먼트 센터] - 인벤토리/상점/정비 우선형 로비
// 🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩
class LobbyScreen extends StatefulWidget {
  final String nickname;
  final int level;
  const LobbyScreen({super.key, required this.nickname, required this.level});

  @override
  State<LobbyScreen> createState() => _LobbyScreenState();
}


class _LobbyScreenState extends State<LobbyScreen> {
  String currentFilter = 'ALL';
  final ScrollController invScrollCtrl = ScrollController();

  String selectedTab = '레벨'; // 기본값은 레벨!
  String selectedFish = '배스'; // 기본값은 배스!

  @override
  void initState() {
    super.initState();
    audioManager.playBgm('bgm_menu.mp3'); 
  }
   
   // 🏆 [핵심] 동점자 선착순 원칙이 적용된 실시간 랭킹 보드
  Widget _buildRankingBoard() {
  return Expanded(
    child: Container(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.8),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.cyanAccent.withOpacity(0.6), width: 2),
      ),
      child: Column(
        children: [
          // 🏆 [1] 3단 탭 메뉴 (레벨 | 민물 | 바다)
          Row(
            children: [
              _buildTabButton('레벨'),
              _buildTabButton('민물'),
              _buildTabButton('바다'),
            ],
          ),
          const SizedBox(height: 10),

          // 🐟 [2] 어종 드롭다운 (레벨이 아닐 때만 등장)
          if (selectedTab != '레벨')
            Align(
              alignment: Alignment.centerRight,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(5),
                  border: Border.all(color: const Color(0xFFD4AF37).withOpacity(0.5)),
                ),
                child: DropdownButton<String>(
                  value: selectedFish,
                  dropdownColor: Colors.black87,
                  underline: const SizedBox(),
                  icon: const Icon(Icons.arrow_drop_down, color: Color(0xFFD4AF37)),
                  style: const TextStyle(color: Color(0xFFD4AF37), fontSize: 13, fontWeight: FontWeight.bold),
                  items: (selectedTab == '민물' ? ['배스', '붕어', '잉어'] : ['참돔', '방어', '광어'])
                      .map((f) => DropdownMenuItem(value: f, child: Text(f))).toList(),
                  onChanged: (val) {
                    setState(() { selectedFish = val!; });
                  },
                ),
              ),
            ),
          
          const Divider(color: Colors.cyanAccent, height: 20),

          // 📜 [3] 동적 스트림 빌더 (선택된 탭에 따라 쿼리가 바뀜!)
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: selectedTab == '레벨'
                  ? FirebaseFirestore.instance.collection('users').orderBy('level', descending: true).limit(10).snapshots()
                  : FirebaseFirestore.instance.collection('users').orderBy('maxCatch.$selectedFish.size', descending: true).limit(10).snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                var docs = snapshot.data!.docs;
                return ListView.builder(
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    var data = docs[index].data() as Map<String, dynamic>;
                    String name = data['nickname'] ?? '조사님';
                    // 레벨일 때는 레벨값을, 물고기일 때는 사이즈값을 전달
                    double val = selectedTab == '레벨' 
                        ? (data['level'] ?? 1).toDouble() 
                        : (data['maxCatch']?[selectedFish]?['size'] ?? 0.0).toDouble();
                    bool isMe = docs[index].id == FirebaseAuth.instance.currentUser?.uid;
                    return _buildRankItem(index + 1, name, val, isMe);
                  },
                );
              },
            ),
          ),
          const Divider(color: Colors.white24, height: 20),
          _buildMyStaticRank(), // 내 순위 고정 바
        ],
      ),
    ),
  );
}

  // 🥇 등수별 아이템 디자인
  Widget _buildRankItem(int rank, String name, double size, bool isMe) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 3),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: isMe ? Colors.cyanAccent.withOpacity(0.1) : Colors.transparent,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Row(
        children: [
          Text('$rank위', style: TextStyle(
            color: rank <= 3 ? Colors.amberAccent : Colors.white70, 
            fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(width: 15),
          Text(name, style: TextStyle(color: isMe ? Colors.cyanAccent : Colors.white, fontWeight: isMe ? FontWeight.bold : FontWeight.normal)),
          const Spacer(),
          Text('${size.toStringAsFixed(1)}Cm', 
            style: TextStyle(color: rank <= 3 ? Colors.amberAccent : Colors.white, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  // 👤 내 순위 표시용 (하단 고정)
  Widget _buildMyStaticRank() {
    final user = FirebaseAuth.instance.currentUser;
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('users').doc(user?.uid).snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox();
        var myData = snapshot.data!.data() as Map<String, dynamic>;
        double mySize = (myData['maxCatch']?['배스']?['size'] ?? 0.0).toDouble();
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.cyanAccent.withOpacity(0.15),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.cyanAccent.withOpacity(0.3)),
          ),
          child: Row(
            children: [
              const Text('MY', style: TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold)),
              const SizedBox(width: 15),
              Text(myData['nickname'] ?? '나', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              const Spacer(),
              Text('${mySize.toStringAsFixed(1)}Cm', style: const TextStyle(color: Colors.cyanAccent, fontSize: 18, fontWeight: FontWeight.bold)),
            ],
          ),
        );
      },
    );
  }
   Widget _buildTabButton(String title) {
    bool isSelected = selectedTab == title;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            selectedTab = title;
            selectedFish = (title == '민물' ? '배스' : '참돔');
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: isSelected ? const Color(0xFFD4AF37) : Colors.transparent, 
                width: 2
              )
            ),
          ),
          child: Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isSelected ? const Color(0xFFD4AF37) : Colors.white54,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              fontSize: 14,
            ),
          ),
        ),
      ),
    );
  }
  // 💡 명품 브랜드(CF, KT) 이름에 맞춘 아이콘 매핑 함수
  String? _getIconImagePath(Map<String, dynamic>? item) {
    if (item == null) return null;
    String name = item['name'].toString();
    String cleanName = name.replaceAll(' ', '').replaceAll('-', '').toUpperCase();

    // ==========================================
    // 💡 모든 아이템 통합 매핑 (Line 380 ~ 421 교체용)
    // ==========================================

    // 1. 스킨/조사 등급 (이미지 폴더)
    if (cleanName.contains('초보')) return 'assets/images/skin_novice.jpg';
    if (cleanName.contains('하수')) return 'assets/images/skin_beginner.jpg';
    if (cleanName.contains('중수')) return 'assets/images/skin_intermediate.jpg';
    if (cleanName.contains('고수')) return 'assets/images/skin_expert.jpg';
    if (cleanName.contains('프로')) return 'assets/images/skin_pro.jpg';
    if (cleanName.contains('마스터')) return 'assets/images/skin_master.jpg';

    // 2. 낚싯대 (민물 시리즈)
    if (cleanName == 'CF20T') return 'assets/items/rod_fw_cf20.png';
    if (cleanName == 'CF30T') return 'assets/items/rod_fw_cf30.png';
    if (cleanName == 'CF40T') return 'assets/items/rod_fw_cf40.png';
    if (cleanName == 'KT20T') return 'assets/items/rod_fw_kt20.png';
    if (cleanName == 'KT30T') return 'assets/items/rod_fw_kt30.png';
    if (cleanName == 'KT40T') return 'assets/items/rod_fw_kt40.png';

    // 3. 낚싯대 (바다 시리즈)
    if (cleanName == 'CF250') return 'assets/items/rod_sea_cf250.png';
    if (cleanName == 'CF350') return 'assets/items/rod_sea_cf350.png';
    if (cleanName == 'CF500') return 'assets/items/rod_sea_cf500.png';
    if (cleanName == 'KT250') return 'assets/items/rod_sea_kt250.png';
    if (cleanName == 'KT350') return 'assets/items/rod_sea_kt350.png';
    if (cleanName == 'KT500') return 'assets/items/rod_sea_kt500.png';

    // 4. 바다 릴 시리즈
    if (cleanName == 'CF2000' || cleanName == '일반릴') return 'assets/items/reel_sea_cf2000.png';
    if (cleanName.contains('CF3000')) return 'assets/items/reel_sea_cf3000.png';
    if (cleanName.contains('CF5000')) return 'assets/items/reel_sea_cf5000.png';
    if (cleanName.contains('KF5000')) return 'assets/items/reel_sea_kf5000.png';
    if (cleanName.contains('KF6000')) return 'assets/items/reel_sea_kf6000.png';
    if (cleanName.contains('KF8000')) return 'assets/items/reel_sea_kf8000.png';

    // 5. 민물 찌 시리즈
    if (cleanName.contains('일반찌')) return 'assets/items/float_fw_normal.png';
    if (cleanName.contains('오동나무')) return 'assets/items/float_fw_wood.png';
    if (cleanName.contains('수제찌')) return 'assets/items/float_fw_handmade.png';
    if (cleanName.contains('나노카본')) return 'assets/items/float_fw_nano.png';
    if (cleanName.contains('CF전자찌')) return 'assets/items/float_fw_elec_cf.png';
    if (cleanName.contains('KT전자찌')) return 'assets/items/float_fw_elec_kt.png';

    // 6. 휘장 (민물/바다)
    if (cleanName.contains('휘장')) {
      return cleanName.contains('민물') 
          ? 'assets/items/item_badge_fw.png' 
          : 'assets/items/item_badge_sea.png';
    }

    // 7. 미끼 (민물/바다)
    if (cleanName == '글루텐') return 'assets/items/bait_fw_gluten.png';
    if (cleanName == '지렁이') return 'assets/items/bait_fw_worm.png';
    if (cleanName == '옥수수') return 'assets/items/bait_fw_corn.png';
    if (cleanName == '갯지렁이') return 'assets/items/bait_sea_worm.png';
    if (cleanName == '크릴') return 'assets/items/bait_sea_krill.png';
    if (cleanName == '루어') return 'assets/items/bait_sea_lure.png';
    if (cleanName == '에기') return 'assets/items/bait_sea_egi.png';

    // 8. 선글라스
    if (cleanName.contains('선글라스')) return 'assets/items/item_sunglasses.png';

    // 예외 상황 시 기본 아이콘
    return 'assets/items/rod_fw_basic_icon.png';
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
          Navigator.push(context, MaterialPageRoute(builder: (context) => LocationSelectScreen(nickname: widget.nickname, level: widget.level, initialIsSeaMode: isSea)));
        },
        child: Container(
          height: 120,
          decoration: BoxDecoration(color: Colors.grey.shade900, borderRadius: BorderRadius.circular(15), border: Border.all(color: const Color(0xFFD4AF37))),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(icon, color: const Color(0xFFD4AF37), size: 40), const SizedBox(height: 10), Text(txt, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))]),
        ),
      ),
    );
  }

  // 💡  아이템 시원하게 확대된 인벤토리!
  Widget _buildLobbyInventory() {
    final user = FirebaseAuth.instance.currentUser;
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('users').doc(user?.uid).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Container(decoration: BoxDecoration(gradient: const RadialGradient(center: Alignment(-0.5, -0.5), radius: 1.5, colors: [Color(0xFF3A3A3A), Color(0xFF0F0F0F)]), border: Border.all(color: const Color(0xFFD4AF37), width: 4), borderRadius: BorderRadius.circular(15)), child: const Center(child: CircularProgressIndicator(color: Color(0xFFD4AF37))));
        }

        List<dynamic> inventory = []; int myLevel = 1; int myGold = 0;
        if (snapshot.hasData && snapshot.data!.data() != null) {
          var userData = snapshot.data!.data() as Map<String, dynamic>;
          inventory = userData['inventory'] ?? []; myLevel = userData['level'] ?? 1; myGold = userData['gold'] ?? 0;
        }

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

        int totalSlots = math.max(60, (filteredItems.length ~/ 4 + 1) * 4);

        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(gradient: const RadialGradient(center: Alignment(-0.5, -0.5), radius: 1.5, colors: [Color(0xFF3A3A3A), Color(0xFF0F0F0F)]), border: Border.all(color: const Color(0xFFD4AF37), width: 4), borderRadius: BorderRadius.circular(15)),
          child: Column(
            children: [
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [const Icon(Icons.stars, color: Color(0xFFD4AF37), size: 20), const SizedBox(width: 8), const Text('KREFT 인벤토리', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFFD4AF37))), const Spacer(), Text('내 포인트: $myGold P', style: const TextStyle(color: Colors.yellowAccent, fontWeight: FontWeight.bold))]),
              const SizedBox(height: 15),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: ['ALL', 'FW', 'SEA', 'BAIT', 'SKIN'].map((filter) {
                  String label = filter == 'ALL' ? '전체' : filter == 'FW' ? '민물' : filter == 'SEA' ? '바다' : filter == 'BAIT' ? '미끼' : '스킨';
                  bool isSelected = currentFilter == filter;
                  return Expanded(
                    child: GestureDetector(
                      onTap: () { audioManager.playSfx('sfx_click.mp3'); setState(() => currentFilter = filter); },
                      child: Container(margin: const EdgeInsets.symmetric(horizontal: 2), padding: const EdgeInsets.symmetric(vertical: 6), decoration: BoxDecoration(color: isSelected ? const Color(0xFFD4AF37) : Colors.black45, borderRadius: BorderRadius.circular(5), border: Border.all(color: isSelected ? Colors.white : Colors.grey.shade800)), child: Center(child: Text(label, style: TextStyle(color: isSelected ? Colors.black : Colors.grey, fontWeight: FontWeight.bold, fontSize: 12)))),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: Scrollbar(
                  controller: invScrollCtrl, thumbVisibility: true, thickness: 8, radius: const Radius.circular(10),
                  child: GridView.builder(
                    controller: invScrollCtrl,
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 4, mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: 0.9),
                    itemCount: totalSlots,
                    itemBuilder: (context, index) {
                      if (index >= filteredItems.length) return Container(decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.white10)));
                      var itemToShow = filteredItems[index];
                      return Container(
                        decoration: BoxDecoration(
                          color: Colors.black54, 
                          borderRadius: BorderRadius.circular(8), 
                          border: Border.all(color: Colors.grey.shade800, width: 2)
                        ),
                        child: Stack(
                          alignment: Alignment.center, 
                          children: [
                            Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                if (_getIconImagePath(itemToShow) != null)
                                  Expanded(
                                    child: Padding(
                                      padding: const EdgeInsets.all(12.0),
                                      child: Image.asset(
                                        _getIconImagePath(itemToShow)!, 
                                        fit: BoxFit.contain,
                                      ),
                                    ),
                                  )
                                else
                                  const Expanded(child: Icon(Icons.inventory_2, color: Colors.white54, size: 50)),
                                
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 8.0),
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown, 
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 4.0), 
                                      child: Text(
                                        itemToShow['name'], 
                                        style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold), 
                                        textAlign: TextAlign.center
                                      )
                                    )
                                  ),
                                )
                              ]
                            ),
                            if (itemToShow['quantity'] != null && itemToShow['type'] == 'BAIT')
                              Positioned(
                                top: 5, right: 5,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), 
                                  decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(4), border: Border.all(color: Colors.white54, width: 0.5)), 
                                  child: Text('${itemToShow['quantity']}개', style: const TextStyle(color: Colors.yellowAccent, fontSize: 11, fontWeight: FontWeight.bold))
                                )
                              )
                          ]
                        )
                      );
                    }
                  ),
                ),
              ),
              const SizedBox(height: 10),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.black, foregroundColor: const Color(0xFFD4AF37), side: const BorderSide(color: Color(0xFFD4AF37), width: 1.5), padding: const EdgeInsets.symmetric(vertical: 12), minimumSize: const Size(double.infinity, 45), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                onPressed: () { audioManager.playSfx("sfx_click.mp3"); Navigator.push(context, MaterialPageRoute(builder: (context) => StoreScreen(currentGold: myGold, currentLevel: myLevel))); },
                child: const Text('🛒 KREFT 상점 입장', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15))
              )
            ],
          ),
        );
      }
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Row(
        children: [
          Expanded(
            flex: 2,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 200, height: 200,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.black, border: Border.all(color: const Color(0xFFD4AF37), width: 3), image: const DecorationImage(image: AssetImage('assets/images/char_novice.png'), fit: BoxFit.cover, alignment: Alignment.topCenter)),
                ),
                const SizedBox(height: 20),
                Text('Lv.${widget.level} ${widget.nickname}', style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold)),
                const SizedBox(height: 40),
                SizedBox(
                  width: 250, height: 70,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFD4AF37), foregroundColor: Colors.black, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(35))),
                    onPressed: _showLocationTypeSelect,
                    child: const Text('🎣 출 조 하 기', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
                  ),
                ),
                const SizedBox(height: 20),
          const Text(
            '🏆 실시간 대물 랭킹 1위에 도전해보세요!',
            style: TextStyle(color: Colors.grey, fontSize: 14),
          ),
        ], 
            ),
          ),
          Expanded(
          flex: 3,
          child: Padding(
            padding: const EdgeInsets.all(30.0),
            child: Center(
              child: _buildRankingBoard(), // 🏆 랭킹판으로 전격 교체!
            ),
          ),
        ),
        ],
      ),
    );
  }
}

// 🗺️ [낚시터 선택 화면] - 전국 출조지 리스트
// 🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩
class LocationSelectScreen extends StatefulWidget {
  final String nickname;
  final int level;
  final bool initialIsSeaMode;

  const LocationSelectScreen({super.key, required this.nickname, required this.level, required this.initialIsSeaMode});

  @override
  State<LocationSelectScreen> createState() => _LocationSelectScreenState();
}

class _LocationSelectScreenState extends State<LocationSelectScreen> {
  late bool isSeaMode;
  String selectedSubCategory = '저수지';

  @override
  void initState() {
    super.initState();
    isSeaMode = widget.initialIsSeaMode;
    selectedSubCategory = isSeaMode ? '갯바위' : '저수지';
    audioManager.playBgm('bgm_menu.mp3'); 
    _pickTodayHotSpot(); 
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

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(backgroundColor: Colors.black, title: const Text('어디로 떠나시겠습니까?', style: TextStyle(fontSize: 16, color: Colors.white)), centerTitle: true, leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () { audioManager.playSfx('sfx_click.mp3'); Navigator.pop(context); })),
      body: Column(
        children: [
          Container(padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 20), color: Colors.black, child: Row(mainAxisAlignment: MainAxisAlignment.start, children: isSeaMode ? [_subTab('갯바위'), const SizedBox(width: 15), _subTab('선상')] : [_subTab('저수지'), const SizedBox(width: 15), _subTab('수로')])),
          Expanded(child: ListView.builder(padding: const EdgeInsets.all(16), itemCount: currentList.length, itemBuilder: (context, index) { return _locationCard(currentList[index]); })),
          Container(padding: const EdgeInsets.all(12), color: Colors.black, child: const Text('✨ 다음 달 업데이트 예정: 고흥 내만권 선상낚시 오픈!', style: TextStyle(color: Color(0xFFD4AF37), fontSize: 12, fontWeight: FontWeight.bold))),
        ],
      ),
    );
  }

  Widget _subTab(String title) {
    bool isSelected = selectedSubCategory == title;
    return GestureDetector(
      onTap: () { audioManager.playSfx('sfx_click.mp3'); setState(() => selectedSubCategory = title); },
      child: Container(padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 8), decoration: BoxDecoration(color: isSelected ? const Color(0xFFD4AF37) : Colors.transparent, borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFFD4AF37))), child: Text(title, style: TextStyle(color: isSelected ? Colors.black : Colors.white, fontWeight: FontWeight.bold, fontSize: 15))),
    );
  }

  // 💡 오픈월드 낚시터 카드 (별점 UI 적용 완료!)
  Widget _locationCard(Map<String, dynamic> loc) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.grey.shade900,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10, width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // 왼쪽 영역: 낚시터 정보 (이름, 별점, 타겟)
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 1. 낚시터 이름
                  Text(
                    loc['name'], 
                    style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)
                  ),
                  const SizedBox(height: 6),
                  
                  // 2. ⭐ 난이도 별점 (노란색 5칸)
                  Row(
                    children: List.generate(5, (index) {
                      // loc['stars'] 개수만큼 꽉 찬 별, 나머지는 빈 별
                      return Icon(
                        index < (loc['stars'] as int) ? Icons.star : Icons.star_border,
                        color: const Color(0xFFD4AF37), // 버튼 색이랑 맞춘 KREFT 골드!
                        size: 16,
                      );
                    }),
                  ),
                  const SizedBox(height: 6),

                  // 3. 🎯 꿀팁 및 타겟 어종
                  Text(
                    '💡 ${loc['target']}', 
                    style: TextStyle(color: Colors.grey.shade400, fontSize: 13, height: 1.3)
                  ),
                ],
              ),
            ),
            
            const SizedBox(width: 10), // 정보와 버튼 사이 간격

            // 오른쪽 영역: 출조하기 버튼
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFD4AF37),
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              onPressed: () {
                audioManager.playSfx('sfx_click.mp3');
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (context) => FishingScreen(
                    nickname: widget.nickname, 
                    locationName: loc['name'],
                    title: loc['name'], 
                    bgImagePath: loc['image'],
                    isSea: isSeaMode,    
                  )),
                );
              },
              child: const Text('출조하기', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}

class FishingScreen extends StatefulWidget {
  final String nickname;
  final String locationName;
  final String title;
  final String bgImagePath;
  final String characterImagePath;
  final bool isSea;

  const FishingScreen({super.key, required this.nickname, this.locationName = '안성 고삼저수지', this.title = '안성 고삼저수지', this.bgImagePath = 'assets/fields/bg_gosam.jpg', this.characterImagePath = 'assets/images/character.png', this.isSea = false});

  @override
  State<FishingScreen> createState() => _FishingScreenState();
}

class _FishingScreenState extends State<FishingScreen> with TickerProviderStateMixin {
  
  void toggleFullScreen() {
    try {
      if (html.document.fullscreenElement == null) {
        // 🖥️ 전체화면 모드로 진입!
        html.document.documentElement?.requestFullscreen();
      } else {
        // 🔙 전체화면 탈출!
        html.document.exitFullscreen();
      }
    } catch (e) {
      print("전체화면 전환 실패: $e");
    }
  }
  
  

  // 🏢 Data: 물고기 도감 및 기본 세팅값
  // 🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩
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

  final double setupReelOffsetX = 0.0;  // 릴 좌우 위치
  final double setupReelOffsetY = 0.0;  // 릴 상하 위치
  final double setupReelScale = 0.5;    // 릴 크기        

  final double fieldFloatBottomOffset = 290.0; 
  final double fieldFloatSpacing = 0.0;        
  final double fieldFloatDepthOffset = 0.0;    
  
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

    // 🐟 [민물 물고기 도감]
final List<Map<String, dynamic>> fwFishPool = [
  {'name': '붕어', 'weight': 50, 'unit': 'Cm', 'min': 15.0, 'max': 55.0, 'pts': 1, 'img': 'assets/images/fish_fw_01_crucian_carp.png'}, // 👑 6대장
  {'name': '떡붕어', 'weight': 50, 'unit': 'Cm', 'min': 15.0, 'max': 55.0, 'pts': 0, 'img': 'assets/images/fish_fw_04_herabuna.png'},
  {'name': '블루길', 'weight': 50, 'unit': 'Cm', 'min': 7.0, 'max': 25.0, 'pts': 0, 'img': 'assets/images/fish_fw_07_bluegill.png'},
  {'name': '살치', 'weight': 50, 'unit': 'Cm', 'min': 7.0, 'max': 25.0, 'pts': 0, 'img': 'assets/images/fish_fw_05_pale_chub.png'},
  {'name': '베스', 'weight': 50, 'unit': 'Cm', 'min': 15.0, 'max': 55.0, 'pts': 0, 'img': 'assets/images/fish_fw_08_bass.png'},
  {'name': '강준치', 'weight': 50, 'unit': 'Cm', 'min': 15.0, 'max': 55.0, 'pts': 0, 'img': 'assets/images/fish_fw_09_skygazer.png'},
  {'name': '잉어', 'weight': 50, 'unit': 'Cm', 'min': 15.0, 'max': 120.0, 'pts': 1, 'img': 'assets/images/fish_fw_02_carp.png'}, // 👑 6대장
  {'name': '자라', 'weight': 5, 'unit': 'Cm', 'min': 15.0, 'max': 25.0, 'pts': 0, 'expMult': 2.0, 'img': 'assets/images/fish_fw_10_turtle.png'},
  {'name': '메기', 'weight': 50, 'unit': 'Cm', 'min': 25.0, 'max': 150.0, 'pts': 0, 'img': 'assets/images/fish_fw_03_catfish.png'},
  {'name': '가물치', 'weight': 50, 'unit': 'Cm', 'min': 25.0, 'max': 120.0, 'pts': 1, 'img': 'assets/images/fish_fw_06_snakehead.png'}, // 👑 6대장
];

// 🌊 [바다 물고기 도감]
final List<Map<String, dynamic>> seaFishPool = [
  {'name': '고등어', 'weight': 50, 'unit': 'Cm', 'min': 15.0, 'max': 90.0, 'pts': 0, 'img': 'assets/images/fish_sea_09_mackerel.png'},
  {'name': '우럭', 'weight': 50, 'unit': 'Cm', 'min': 15.0, 'max': 70.0, 'pts': 0, 'img': 'assets/images/fish_sea_08_rockfish.png'},
  {'name': '갈치', 'weight': 50, 'unit': 'Cm', 'min': 25.0, 'max': 150.0, 'pts': 0, 'img': 'assets/images/fish_sea_04_hairtail.png'},
  {'name': '참돔', 'weight': 50, 'unit': 'Cm', 'min': 15.0, 'max': 120.0, 'pts': 1, 'img': 'assets/images/fish_sea_02_red_seabream.png'}, // 👑 6대장
  {'name': '벵에돔', 'weight': 50, 'unit': 'Cm', 'min': 15.0, 'max': 60.0, 'pts': 0, 'img': 'assets/images/fish_sea_03_girella.png'},
  {'name': '갑오징어', 'weight': 50, 'unit': 'Cm', 'min': 15.0, 'max': 55.0, 'pts': 0, 'reqBait': '에기', 'img': 'assets/images/fish_sea_07_cuttlefish.png'},
  {'name': '쭈꾸미', 'weight': 50, 'unit': 'Cm', 'min': 3.0, 'max': 30.0, 'pts': 0, 'reqBait': '에기', 'img': 'assets/images/fish_sea_06_webfoot_octopus.png'},
  {'name': '광어', 'weight': 50, 'unit': 'Cm', 'min': 5.0, 'max': 120.0, 'pts': 0, 'img': 'assets/images/fish_sea_10_halibut.png'},
  {'name': '감성돔', 'weight': 50, 'unit': 'Cm', 'min': 15.0, 'max': 75.0, 'pts': 1, 'img': 'assets/images/fish_sea_01_black_porgy.png'}, // 👑 6대장
  {'name': '문어', 'weight': 50, 'unit': 'kg', 'min': 1.0, 'max': 12.0, 'pts': 1, 'reqBait': '에기', 'img': 'assets/images/fish_sea_05_octopus.png'}, // 👑 6대장
  {'name': '참치', 'weight': 5, 'unit': 'Cm', 'min': 30.0, 'max': 200.0, 'pts': 0, 'img': 'assets/images/fish_sea_11_tuna.png'},
];

  // 🏢 State: 상태 변수들
  // 🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩
  bool isSettingUp = true;    
  int selectedRodCount = 2;   
  Color selectedChemiColor = Colors.green; 
  String selectedBait = '지렁이'; 

  bool isCasting = false; 
  bool isFloatInWater = false; 
  bool isRodEquipped = false;
  
  Map<String, dynamic>? equippedRod;  
  Map<String, dynamic>? equippedFloat; 
  Map<String, dynamic>? equippedBait;  
  Map<String, dynamic>? equippedSkin;
  Map<String, dynamic>? equippedSunglasses;
  Map<String, dynamic>? equippedBadge;
  Map<String, dynamic>? equippedReel;  

  bool isFighting = false;
  bool isPulling = false; 
  double tension = 0.5;
  Timer? fightTimer;
  int fightTicks = 0;
  Map<String, dynamic>? currentFishInfo;

  Timer? gameTimer;
  int? bitingRodIndex; 
  Timer? biteTimer;    
  late AnimationController _rodController; 
  late AnimationController _castController; 


  // 🏢 Logic: 핵심 동작 함수들 (입질, 파이팅, 데미지 계산 등)
  // 🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩
  @override
  void initState() {
    super.initState();
    _rodController = AnimationController(vsync: this, duration: const Duration(milliseconds: 150))..repeat(reverse: true);
    _castController = AnimationController(vsync: this, duration: const Duration(milliseconds: 300));
    _playBGM("bgm_menu.mp3");
  }

  @override
  void dispose() {
    gameTimer?.cancel();
    fightTimer?.cancel();
    biteTimer?.cancel();
    _rodController.dispose();
    _castController.dispose();
    super.dispose();
  }

  void _playBGM(String fileName) => audioManager.playBgm(fileName);
  void _playSFX(String fileName) => audioManager.playSfx(fileName);
  void _toggleMute() => audioManager.toggleMute().then((_) => setState(() {}));

  int _getLevelIndex() {
    int lv = forcedLevel; 
    if (lv >= 26) return 5; 
    if (lv >= 21) return 4; 
    if (lv >= 16) return 3; 
    if (lv >= 11) return 2; 
    if (lv >= 6) return 1;  
    return 0;               
  }

  Map<String, dynamic> _generateFish() {
    List<Map<String, dynamic>> pool = widget.isSea ? seaFishPool : fwFishPool;
    String currentBait = equippedBait != null ? equippedBait!['name'].toString() : '';
    
    List<Map<String, dynamic>> availableFishes = pool.where((fish) {
      if (fish['reqBait'] != null && !currentBait.contains(fish['reqBait'])) return false;
      return true;
    }).toList();

    bool isHotSpot = (widget.locationName == fwHotSpot || widget.locationName == seaHotSpot);

    String currentTarget = '';
    int currentStars = 1; 
    locations.forEach((category, locList) {
      for (var loc in locList) {
        if (loc['name'] == widget.locationName) {
          currentTarget = loc['target'] ?? '';
          currentStars = loc['stars'] ?? 1;
        }
      }
    });

    // 가중치 룰렛
    int totalWeight = 0;
    for (var fish in availableFishes) {
      int w = fish['weight'] as int? ?? 10;
      if (currentTarget.contains(fish['name'])) w = w * 5; 
      if (isHotSpot && w <= 15) w = (w * 2);
      totalWeight += w;
    }

    int randomWeight = math.Random().nextInt(totalWeight);
    Map<String, dynamic>? selectedFish;
    int currentWeight = 0;
    for (var fish in availableFishes) {
      int w = fish['weight'] as int? ?? 10;
      if (currentTarget.contains(fish['name'])) w = w * 5; 
      if (isHotSpot && w <= 15) w = (w * 2); 
      currentWeight += w;
      if (randomWeight < currentWeight) {
        selectedFish = fish;
        break;
      }
    }
    selectedFish ??= availableFishes.first;

    // ==========================================
    // 🎛️ [사장님 전용 밸런스 컨트롤 패널 2.0]
    // ==========================================
    double minFactor = 0.0; // 최소어 하한선 배수
    double sizeCap = 1.0;   // 최대어 제한 배수
    double expMult = 1.0;   // 경험치 배수
    double ptsMult = 1.0;   // 포인트 배수

    switch (currentStars) {
      case 1:
        minFactor = 0.0; // 최소어 제한 없음 (0%)
        sizeCap = 0.2;   // 최대 20%
        expMult = 2.0; ptsMult = 1.0;
        break;
      case 2:
        minFactor = 0.1; // 최소어 10%부터 시작
        sizeCap = 0.4;   // 최대 40%
        expMult = 2.2; ptsMult = 1.2;
        break;
      case 3:
        minFactor = 0.2; // 최소어 20%부터 시작
        sizeCap = 0.6;   // 최대 60%
        expMult = 2.4; ptsMult = 1.4;
        break;
      case 4:
        minFactor = 0.3; // 최소어 30%부터 시작
        sizeCap = 0.8;   // 최대 80%
        expMult = 2.6; ptsMult = 1.6;
        break;
      case 5:
      default:
        minFactor = 0.4; // 최소어 40%부터 시작 (대물 전용!)
        sizeCap = 1.0;   // 최대 100%
        expMult = 2.8; ptsMult = 1.8;
        break;
    }

    // ==========================================
    // 💡 [확률 로직] 사이즈 및 보상 최종 계산
    // ==========================================
    double baseMin = double.tryParse(selectedFish!['min'].toString()) ?? 10.0;
    double baseMax = double.tryParse(selectedFish!['max'].toString()) ?? 50.0;
    double range = baseMax - baseMin;
    
    // 1. 기본 운빨 주사위
    double randValue = math.Random().nextDouble();
    double bellCurveRandom = (math.Random().nextInt(100) < 10) 
        ? randValue 
        : (randValue + math.Random().nextDouble() + math.Random().nextDouble()) / 3;
    if (isHotSpot) bellCurveRandom = math.pow(bellCurveRandom, 0.7).toDouble();
    
    // 2. [사장님 기획] 별점별 최소/최대 범위(effective range) 적용!
    double effectiveMin = baseMin + (range * minFactor);
    double effectiveMax = baseMin + (range * sizeCap);
    
    // 안전장치: 최대치가 최소치보다 낮아지지 않게 조절
    if (effectiveMax < effectiveMin) effectiveMax = effectiveMin + (range * 0.1);

    double size = effectiveMin + (bellCurveRandom * (effectiveMax - effectiveMin));
    size = double.parse(size.toStringAsFixed(1));

    // 3. 경험치 & 포인트 계산 (6대장 보너스 포함)
    double fishBaseExpMult = selectedFish!['expMult'] ?? 1.0;
    int exp = (size * expMult * fishBaseExpMult).round();
    int pts = (size * ptsMult).round();

    List<String> bossFishes = ['붕어', '잉어', '가물치', '참돔', '감성돔', '문어'];
    if (bossFishes.contains(selectedFish!['name'])) {
      exp = (exp * 1.1).round();
      pts = (pts * 1.1).round();
    }

    return {
      'name': selectedFish!['name'], 'img': selectedFish!['img'], 'size': size.toString(),
      'unit': selectedFish!['unit'], 'exp': exp, 'pts': pts,
    };
  }

// 🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩
  // 📥 1. 파이어베이스에서 남은 시간 불러오기 (웹 새로고침 대응 완료!)
  Future<void> _loadDailyTimeFromFirebase() async {
    // 🚨 [핵심 패치] 웹 새로고침 직후 유저 정보가 null이 되는 현상 방어!
    // 유저 정보를 가져올 때까지 0.3초씩 계속 찔러보며 기다립니다. (최대 10번 = 3초)
    User? user = FirebaseAuth.instance.currentUser;
    int retry = 0;
    while (user == null && retry < 10) {
      await Future.delayed(const Duration(milliseconds: 300));
      user = FirebaseAuth.instance.currentUser;
      retry++;
    }

    // 기다렸는데도 유저 정보가 들어왔다면? DB를 엽니다!
    if (user != null) {
      String today = DateTime.now().toString().substring(0, 10);
      var doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      
      // 화면이 넘어가기 전에만 setState 실행 (안전장치)
      if (mounted) {
        if (doc.exists && doc.data()!.containsKey('lastPlayedDate')) {
          String lastDate = doc.data()!['lastPlayedDate'];
          if (lastDate == today) {
            // DB에 저장된 시간으로 강제 세팅!
            setState(() { remainingTime = doc.data()!['remainingTime'] ?? 3600; });
          } else {
            // 날짜가 다르면 60분 리셋
            setState(() { remainingTime = 3600; });
            _saveDailyTimeToFirebase(3600);
          }
        } else {
          // 최초 접속
          setState(() { remainingTime = 3600; });
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

  // ⏱️ 3. 타이머 메인 함수
  void _startGameTimer() {
    if (gameTimer != null && gameTimer!.isActive) return;

    // 💡 시작하자마자 DB 스캔 (이제 안 쌩까고 기다려줍니다!)
    _loadDailyTimeFromFirebase();

    gameTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) { timer.cancel(); return; }
      
      setState(() {
        if (!mounted) return;
        // 물에 찌가 들어가 있거나 파이팅 중일 때만 시간 감소!
        if (isCasting || isFloatInWater || isFighting) {
          if (remainingTime > 0) { 
            remainingTime--; 
            
            // 💾 10초에 한 번씩 파이어베이스에 몰래 저장! 
            if (remainingTime % 10 == 0) {
              _saveDailyTimeToFirebase(remainingTime);
            }
          } else {
            timer.cancel(); biteTimer?.cancel(); fightTimer?.cancel();
            _showNotificationPopup(
              '⏱ 일일 낚시 시간 종료!', 
              '오늘 허용된 60분의 낚시 시간을 모두 소진했습니다.\n내일 다시 찾아주세요.', 
              Colors.redAccent
            );
          }
        }
      });
    });
  }

  void _startBiteTimer() {
    biteTimer?.cancel();
    biteTimer = Timer(Duration(seconds: 3 + math.Random().nextInt(5)), () {
      if (!mounted || !isFloatInWater || isFighting) return;
      setState(() { bitingRodIndex = math.Random().nextInt(selectedRodCount); });
      HapticFeedback.lightImpact();
    });
  }

  void _handleMainActionButton() {
    if (isFloatInWater && !isFighting) {
      if (bitingRodIndex != null) {
        HapticFeedback.heavyImpact(); _playSFX("sfx_hit.mp3"); 
        var caughtFish = _generateFish();
_startFight(caughtFish); // 경험치는 진짜로 잡았을 때만 주도록 수정!
      } else {
        _playSFX("sfx_click.mp3"); 
        _showNotificationPopup('헛챔질!', '타이밍이 맞지 않았습니다.\n찌가 변하며 올라올 때 챔질하세요.', Colors.orangeAccent);
      }
    } else if (isFighting) {
      _pullLine(); 
    }
  }

  void _startFight(Map<String, dynamic> fish) {
    biteTimer?.cancel();
    setState(() {
      isFloatInWater = false; // 찌는 물 밖으로 나옴
      bitingRodIndex = null;
    });

    // 1. 내 캐릭터의 총 능력치 합산 (힘 + 컨트롤 + 감도)
    Map<String, int> myStats = getMyTotalStats();
    double totalStats = (myStats['strength'] ?? 0) + (myStats['control'] ?? 0) + (myStats['sensitivity'] ?? 0).toDouble();

    // 2. 신형 파이팅 엔진(오버레이) 화면에 띄우기!
    showDialog(
      context: context,
      barrierDismissible: false, // 🚨 바깥쪽 터치해서 꼼수로 도망가는 것 방지!
      builder: (context) {
        return Material(
          color: Colors.transparent, // 배경은 투명하게 해서 뒤에 낚시터가 보이게!
          child: FishingFightingOverlay(
            fish: fish,
            playerTotalStats: totalStats,
            onFinished: (bool isSuccess, double size) {
                    Navigator.pop(context); // 30초 승부가 끝나면 파이팅 창 닫기!

                    // 3. 승패 결과 처리!
                    if (isSuccess) {
                      // 🎉 [승리] 진짜로 뜰채로 올렸을 때만 보상 지급!!
                      final user = FirebaseAuth.instance.currentUser;
                      if (user != null) {
                        // 🚀 파이어베이스 창고에 경험치와 포인트(gold) 즉시 누적 저장!
                        FirebaseFirestore.instance.collection('users').doc(user.uid).update({
                          'exp': FieldValue.increment(fish['exp'] as int),
                          'gold': FieldValue.increment(fish['pts'] as int),
                        });
                      }

                      HapticFeedback.heavyImpact();
                      _playSFX("sfx_landing_success.mp3");
                      _showResultPopup(fish); // "잡았습니다!" 결과창 띄우기
                    } else {
                      // 💥 [패배] 줄이 터지거나 바늘이 털렸을 때!
                      _playSFX("sfx_break.mp3");

                      // 💡 1. 억울한 유저를 위한 다양한 위로(?) 멘트 리스트! (원하시는 대로 더 추가하셔도 됩니다)
                      List<String> failMessages = [
                        '와우~ 대물인데 아쉽습니다!\n상점에서 장비를 업그레이드 해보세요.',
                        '앗! 바늘털이에 당했습니다.\n다음엔 텐션 조절을 조금 더 신중히 해보시죠!',
                        '팅! 줄이 터져버렸네요...\n제압력이 더 높은 낚싯대가 필요할지도?',
                        '아슬아슬했는데 코앞에서 놓쳤습니다!\n심호흡 한 번 하고 다시 캐스팅해 보시죠.',
                        '물고기의 힘이 너무 압도적이네요!\n장비의 한계가 온 것 같습니다.',
                        '수초를 감아버렸습니다!\n채비를 정비하고 다시 도전하세요.'
                      ];
                      
                      // 🎲 2. 리스트 중에서 랜덤으로 멘트 하나를 뽑습니다!
                      String randomMsg = failMessages[math.Random().nextInt(failMessages.length)];

                      _showNotificationPopup(
                        '💥 줄이 터졌습니다...', 
                        randomMsg, // 👈 고정된 텍스트 대신 방금 뽑은 랜덤 멘트를 쏙!
                        Colors.redAccent, 
                        onConfirm: _recast // 다시 던지기
                      );
                    }
                  },
          ),
        );
      }
    );
  }

  void _pullLine() {
    if (!isFighting) return;
    HapticFeedback.mediumImpact();
    _playSFX(widget.isSea ? "sfx_sea_landing.mp3" : "sfx_fresh_landing.mp3");

    double rodPower = (equippedRod?['power'] ?? 0).toDouble();
    double baitPower = (equippedBait?['power'] ?? 0).toDouble();
    double totalPull = 0.06 + ((rodPower + baitPower) * 0.002);

    setState(() { tension -= totalPull; });
  }
// 💡 캐스팅 시 가방에서 미끼를 1개 차감하는 함수
  Future<void> _useBaitOne() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || equippedBait == null) return;

    try {
      final userDoc = FirebaseFirestore.instance.collection('users').doc(user.uid);
      final snapshot = await userDoc.get();
      if (!snapshot.exists) return;

      List<dynamic> inventory = List.from(snapshot.data()?['inventory'] ?? []);
      String targetBaitName = equippedBait!['name'];

      // 가방에서 장착된 미끼 찾아서 1개 빼기
      for (int i = 0; i < inventory.length; i++) {
        if (inventory[i]['name'] == targetBaitName) {
          int q = inventory[i]['quantity'] ?? 0;
          if (q > 0) {
            inventory[i]['quantity'] = q - 1;
            // 0개가 되면 가방에서 삭제하거나, 0개임을 표시
            if (inventory[i]['quantity'] == 0) {
              inventory.removeAt(i); 
              setState(() { equippedBait = null; });
              _showNotificationPopup('🛑 미끼 소진!', '준비한 미끼를 모두 사용했습니다.\n가방에서 새로 장착하세요!', Colors.orangeAccent);
            }
            break;
          }
        }
      }

      await userDoc.update({'inventory': inventory});
    } catch (e) { print("미끼 소모 중 에러: $e"); }
  }
  void _recast() {
    if (!mounted || remainingTime <= 0) return; 
    _useBaitOne(); 
    setState(() { isCasting = true; isFighting = false; bitingRodIndex = null; });
    _playSFX("sfx_casting.mp3"); _castController.forward(from: 0.0); 

    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted) { setState(() { isCasting = false; isFloatInWater = true; }); _startBiteTimer(); }
    });
  }

  int _getMaxRods() {
    if (widget.isSea) return 1; 
    if (forcedLevel >= 6) return 14;
    String skinName = equippedSkin != null ? equippedSkin!['name'].toString() : '초보 조사';
    if (skinName.contains('마스터')) return 14; if (skinName.contains('프로')) return 10; if (skinName.contains('고수')) return 8; if (skinName.contains('중수')) return 5; if (skinName.contains('하수')) return 3; return 2; 
  }

  Color _getBiteColor(Color color) {
    if (color == Colors.green) return Colors.redAccent; if (color == Colors.red) return Colors.greenAccent; if (color == Colors.blue) return Colors.orangeAccent; if (color == Colors.yellow) return Colors.purpleAccent; return Colors.white;
  }

  String? _getEquipImagePath(Map<String, dynamic>? item) {
    if (item == null) return null;
    String name = item['name'].toString();
    if (name.contains('민물대')) return 'assets/items/rod_fw_basic_equip.png';
    if (name.contains('오션') || name.contains('스타터')) return 'assets/items/rod_sea_basic_icon.png';
    return null;
  }

  // 💡DB의 icon 데이터를 바로 읽어오는 탐색기!
  String? _getIconImagePath(Map<String, dynamic>? item) {
    if (item == null || item['icon'] == null) return 'assets/items/rod_fw_basic_icon.png';
    
    String iconName = item['icon'].toString();
    
    // 1. 이미 전체 경로가 포함된 경우 (../ 찌꺼기만 청소)
    if (iconName.contains('assets/')) {
      return iconName.replaceAll('../', 'assets/');
    }
    
    // 2. 스킨/캐릭터 이미지 (.jpg) -> images 폴더에서 찾기
    if (iconName.contains('.jpg') || iconName.contains('skin_')) {
      return 'assets/images/$iconName';
    }
    
    // 3. 일반 장비/미끼 (.png) -> items 폴더에서 찾기
    return 'assets/items/$iconName';
  }

  Map<String, int> getMyTotalStats() {
    // 💡 [수정] 0에서 시작하던 걸 인벤토리랑 똑같이 기본값 10에서 시작하도록 변경!
    int totalStr = 10; int totalCtrl = 10; int totalSens = 10;

    void addStats(Map<String, dynamic>? item) {
      if (item == null || item['stats'] == null) return;
      var s = item['stats'];
      totalStr += int.tryParse(s['P']?.toString() ?? s['힘']?.toString() ?? '0') ?? 0;
      totalCtrl += int.tryParse(s['C']?.toString() ?? s['컨트롤']?.toString() ?? '0') ?? 0;
      totalSens += int.tryParse(s['S']?.toString() ?? s['감도']?.toString() ?? '0') ?? 0;
    }

    // 장착된 모든 부위의 스탯을 싹 긁어모읍니다.
    addStats(equippedSkin);       
    addStats(equippedRod);        
    addStats(equippedFloat);      
    addStats(equippedReel);       
    addStats(equippedSunglasses); 
    addStats(equippedBadge);      

    return {'strength': totalStr, 'control': totalCtrl, 'sensitivity': totalSens};
  }
  
  // 📈 사장님 기획 반영! 경험치로 레벨 및 보너스 스탯(+10) 계산
  Map<String, dynamic> _calculatePlayerProgress(int totalExp) {
    int level = 1;
    
    // ⏳ 타임라인 밸런스 패치 (1일 -> 3일 -> 5일 -> 10일)
    if (totalExp >= 350000) level = 5;      // 5레벨(하수)
    else if (totalExp >= 150000) level = 4; // 4레벨
    else if (totalExp >= 60000) level = 3;  // 3레벨
    else if (totalExp >= 15000) level = 2;  // 2레벨
    else level = 1;                         // 1레벨(초보)

    // 레벨당 스텟 보너스 (1레벨은 0, 2레벨부터 +10씩)
    int levelBonus = (level - 1) * 10;
    
    // 현재 장착된 장비의 '힘(strength)' 능력치를 안전하게 가져옵니다.
    int myEquipPower = getMyTotalStats()['strength'] ?? 0;
    
    return {
      'level': level,
      'levelBonus': levelBonus,
      'totalPower': myEquipPower + levelBonus,
    };
  }

  // 🏢 UI - Main: 화면 뼈대 그리기 (배경, 도화지, 인벤토리 패널)
  // 🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩
  
  Widget _buildRodOverlay(Map<String, dynamic>? rodItem) {
    
    // 1. 낚싯대 파일명 매핑
    String equipRodFileName = '';
    if (rodItem != null) {
      String rawName = rodItem['name'].toString().replaceAll(' ', '').replaceAll('-', '').replaceAll('_', '').toUpperCase();
      if (rawName == 'CF20T') equipRodFileName = 'rod_fw_cf20_equip.png';
      else if (rawName == 'CF30T') equipRodFileName = 'rod_fw_cf30_equip.png';
      else if (rawName == 'CF40T') equipRodFileName = 'rod_fw_cf40_equip.png';
      else if (rawName == 'KT20T') equipRodFileName = 'rod_fw_kt20_equip.png';
      else if (rawName == 'KT30T') equipRodFileName = 'rod_fw_kt30_equip.png';
      else if (rawName == 'KT40') equipRodFileName = 'rod_fw_kt40_equip.png';

      // 🌊 [추가] 바다 낚싯대 무적 매칭! (기호 무시!)
      else if (rawName.contains('KT') && rawName.contains('500')) equipRodFileName = 'rod_sea_kt500_equip.png';
      else if (rawName.contains('KT') && rawName.contains('350')) equipRodFileName = 'rod_sea_kt350_equip.png';
      else if (rawName.contains('KT') && rawName.contains('250')) equipRodFileName = 'rod_sea_kt250_equip.png';
      else if (rawName.contains('CF') && rawName.contains('500')) equipRodFileName = 'rod_sea_cf500_equip.png';
      else if (rawName.contains('CF') && rawName.contains('350')) equipRodFileName = 'rod_sea_cf350_equip.png';
      else if (rawName.contains('CF') && rawName.contains('250')) equipRodFileName = 'rod_sea_cf250_equip.png';

      // 만약 이름이 아예 안 맞으면 빈 화면 출력
      if (equipRodFileName.isEmpty) return const SizedBox.shrink();
    }

    // 2. 🛡️ 플러터의 크기 0 버그를 때려잡는 독불장군 Stack 소환!
    return Positioned.fill(
      child: Stack(
        // alignment: Alignment.bottomCenter, // Important: must align overlays from bottom-center
        children: [
          
          // 💡 1층: 베이스 캐릭터 이미지
          Builder(
            builder: (c) {
           
          // 💡 스킨 자판기에서 알아서 사진 뽑아오기! (중복 제거 완료)
          String currentCharacterImg = 'assets/images/char_novice.png';
          if (equippedSkin != null) {
            currentCharacterImg = getLobbyCharacterImage(equippedSkin!['name'].toString());
          }    
              
              return Image.asset(
                currentCharacterImg,
                height: 400,
                fit: BoxFit.contain,
                errorBuilder: (c,e,s)=>const SizedBox.shrink(),
              );
            }
          ),

          // ==========================================
          // 💡 2층: 😎 선글라스 덧씌우기
          _buildItemOverlay('assets/items/sunglasses_overlay.png', bottom: 250, left: 160, width: 80),

          // ==========================================
          // 💡 3층: 🐟 왼쪽 가슴 민물휘장 덧씌우기
          _buildItemOverlay('assets/items/badge_fw_overlay.png', bottom: 200, left: 130, width: 50),

          // ==========================================
          // 💡 4층: 🌊 오른쪽 가슴 바다휘장 덧씌우기
          _buildItemOverlay('assets/items/badge_sea_overlay.png', bottom: 200, left: 220, width: 50),

          // ==========================================
          // 💡 5층: 🎣 낚싯대 최종 덧씌우기
          if (equipRodFileName.isNotEmpty)
            _buildItemOverlay('assets/items/$equipRodFileName', bottom: 0, left: 10, width: 300),

          // ==========================================
// 💡 6층: ⚙️ 릴 스티커 덧씌우기 (무조건 소환 모드!)
if (equippedReel != null || equippedBait != null) // 👈 미끼칸에 들어가 있어도 일단 그려라!!
  _buildItemOverlay(
    'assets/items/reel_sea_kf8000.png', // 👈 사장님 폴더에 있는 KF8000 사진 이름 
    bottom: 230,  // 👈 대충 낚싯대 손잡이 높이 (숫자 요리조리 바꿔보기!)
    left: 140,    // 👈 대충 낚싯대 손잡이 좌우 (숫자 요리조리 바꿔보기!)
    width: 40,    // 👈 릴 크기 (숫자 요리조리 바꿔보기!)
  ),

        ],
      ),
    );
  }

  // 🛠️ 오버레이 이미지를 그리는 공통 도우미 함수 (크기 0 버그 철벽 방어!)
  Widget _buildItemOverlay(String path, {required double bottom, required double left, double? width}) {
    return Positioned(
      bottom: bottom, 
      left: left,
      child: Image.asset(
        path,
        width: width,
        fit: BoxFit.contain,
        errorBuilder: (c, e, s) => const SizedBox.shrink()
      ),
    );
  }

  @override
  @override
  Widget build(BuildContext context) {
    String currentCharacterImg = 'assets/images/char_novice.png';
    if (equippedSkin != null) {
      currentCharacterImg = getLobbyCharacterImage(equippedSkin!['name'].toString());
    } 
    
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(child: Transform.scale(scaleX: widget.isSea ? -1 : 1, child: Image.asset(widget.bgImagePath, fit: BoxFit.cover, errorBuilder: (c, e, s) => Container(color: Colors.grey.shade900, child: const Center(child: Icon(Icons.broken_image, color: Colors.white24, size: 100)))))), 
          Positioned.fill(child: Container(color: const Color(0x3A000000))),

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
                          scale: 1.20,
                          alignment: Alignment.bottomLeft,
                          child: Image.asset(
                            currentCharacterImg, 
                            fit: BoxFit.contain,
                            errorBuilder: (c, e, s) => const SizedBox.shrink(),
                          ),
                        ),
                        if (equippedSunglasses != null)
                          Positioned(
                            bottom: 350, left:221,
                            child: Image.asset('assets/items/item_sunglasses.png', width: 38, errorBuilder: (c,e,s)=>const SizedBox.shrink()),
                          ),
                        if (equippedBadge != null)
                          Positioned(
                            bottom: 290, left: 250,
                            child: Image.asset(equippedBadge!['name'].toString().contains('민물') ? 'assets/items/item_badge_fw.png' : 'assets/items/item_badge_sea.png', width: 28, errorBuilder: (c,e,s)=>const SizedBox.shrink()),
                          ),
                        if (equippedRod != null)
                          Transform.translate(
                            offset: const Offset(76.0, -255.0), 
                            child: Transform.scale(
                              scale: 0.45, 
                              alignment: Alignment.bottomLeft,
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

          if (!isSettingUp) ...[
            if (!widget.isSea || (!isCasting && !isFighting)) _buildFieldRods(),
            if (isCasting) _buildCastingScene() else if (isFighting) _buildFightScene(),
            if (widget.isSea && isFloatInWater && bitingRodIndex != null) Positioned.fill(child: Center(child: const Text("입질 !!", style: TextStyle(color: Colors.redAccent, fontSize: 120, fontWeight: FontWeight.w900, fontStyle: FontStyle.italic, shadows: [Shadow(color: Colors.black, blurRadius: 20, offset: Offset(5, 5))])))),
            if (isFloatInWater || isFighting) Positioned(bottom: 40, right: 40, child: _buildMainActionButton()),
          ],
          
          // 🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩
          // [상단 UI 리모델링: 성장 시스템 & 신뢰의 HUD]
          Positioned(
            top: 15, left: 15, right: 15,
            child: SafeArea(
              child: StreamBuilder<DocumentSnapshot>(
                stream: FirebaseFirestore.instance.collection('users').doc(FirebaseAuth.instance.currentUser!.uid).snapshots(),
                builder: (context, snapshot) {
                  int realExp = 0;
                  int realGold = 0;
                  String realRank = '초보';
                  String realNickname = widget.nickname;

                  if (snapshot.hasData && snapshot.data!.exists) {
                    var userData = snapshot.data!.data() as Map<String, dynamic>;
                    realExp = userData['exp'] ?? 0;
                    realGold = userData['gold'] ?? 0;
                    realRank = userData['rank'] ?? '초보';
                    realNickname = userData['nickname'] ?? widget.nickname;
                  }

                  int realLevel = 1;
                  int nextLevelExp = 3000;
                  int prevLevelExp = 0;

                  if (realExp >= 102000) { realLevel = 5; nextLevelExp = 102000; prevLevelExp = 102000; realRank = '하수'; }
                  else if (realExp >= 42000) { realLevel = 4; nextLevelExp = 102000; prevLevelExp = 42000; }
                  else if (realExp >= 12000) { realLevel = 3; nextLevelExp = 42000; prevLevelExp = 12000; }
                  else if (realExp >= 3000) { realLevel = 2; nextLevelExp = 12000; prevLevelExp = 3000; }
                  else { realLevel = 1; nextLevelExp = 3000; prevLevelExp = 0; }

                  int levelBonus = (realLevel - 1) * 10;
                  
                  Map<String, int> currentStats = getMyTotalStats();
                  int equipP = currentStats['strength'] ?? 0;
                  int equipC = currentStats['control'] ?? 0;
                  int equipS = currentStats['sensitivity'] ?? 0;
                  
                  int myEquipSum = equipP + equipC + equipS;
                  int myTotalPower = myEquipSum + levelBonus;

                  double expPercent = (realLevel < 5) ? (realExp - prevLevelExp) / (nextLevelExp - prevLevelExp) : 1.0;

                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              IconButton(
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                icon: const Icon(Icons.arrow_back_ios, color: Colors.white, size: 22),
                                onPressed: () { audioManager.playSfx("sfx_click.mp3"); Navigator.pop(context); }
                              ),
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
                                  Text(' (💪$equipP  🎯$equipC  📡$equipS)', style: const TextStyle(color: Colors.white54, fontSize: 11)),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Container(
                            width: 180, height: 8, 
                            decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(4), border: Border.all(color: Colors.white24, width: 0.5)),
                            child: FractionallySizedBox(
                              alignment: Alignment.centerLeft,
                              widthFactor: expPercent.clamp(0.0, 1.0),
                              child: Container(decoration: BoxDecoration(color: const Color(0xFFD4AF37), borderRadius: BorderRadius.circular(4))),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text('$realExp / $nextLevelExp EXP', style: const TextStyle(color: Colors.white54, fontSize: 10)),
                          const SizedBox(height: 10),
                          Text('point $realGold', style: const TextStyle(color: Colors.cyanAccent, fontSize: 16, fontWeight: FontWeight.bold)),
                        ],
                      ),

                      Positioned(
                        right: 0, top: 0,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFFD4AF37), width: 1.5)),
                          child: Row(
                            children: [
                              Text(realRank, style: const TextStyle(color: Color(0xFFD4AF37), fontSize: 13, fontWeight: FontWeight.bold)),
                              const SizedBox(width: 8),
                              Text('$realNickname 조사님', style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                      ),
                      
                      Positioned(
                        right: 0, top: 40,
                        child: IconButton(
                          icon: Icon(audioManager.isMuted ? Icons.volume_off : Icons.volume_up, color: Colors.white70, size: 20),
                          onPressed: () { setState(() { audioManager.toggleMute(); }); },
                        ),
                      ),
                      // ⏲️ [신규] 60분 세션 타이머 (중앙 배치)
          Positioned(
            top: 0, left: 0, right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(color: const Color(0xFFD4AF37).withOpacity(0.5), width: 1),
                  boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 4, offset: Offset(0, 2))]
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.timer_outlined, color: Color(0xFFD4AF37), size: 16),
                    const SizedBox(width: 6),
                    Text(
                      '${(remainingTime ~/ 60).toString().padLeft(2, '0')}:${(remainingTime % 60).toString().padLeft(2, '0')}', 
                      style: const TextStyle(
                        color: Colors.white, 
                        fontSize: 18, 
                        fontWeight: FontWeight.bold,
                        fontFamily: 'monospace', // 숫자 간격 일정하게!
                      ),
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
        ],
      ),
    );
  }

  Widget _buildSetupOverlay() {
    // 💡 [수정 완료] 장착한 스킨(호칭)에 따라 대편성
    int maxRods = 2; // 초보는 얄짤없이 2대!
    if (widget.isSea) {
      maxRods = 1; // 🌊 바다낚시는 1대 고정!
    } else {
      // 장착 중인 스킨(캐릭터)의 이름을 확인해서 갯수를 팍팍 늘려줍니다!
     String skinName = equippedSkin != null ? equippedSkin!['name'].toString() : '초보';
      
      if (skinName.contains('마스터')) maxRods = 14;
      else if (skinName.contains('프로')) maxRods = 10;
      else if (skinName.contains('고수')) maxRods = 8;
      else if (skinName.contains('중수')) maxRods = 6;
      else if (skinName.contains('하수')) maxRods = 4;
    }
    // 유저가 편법으로 더 많이 펴놨으면 강제로 깎아버립니다 
    if (selectedRodCount > maxRods) selectedRodCount = maxRods;
    return Container(
      width: 350, padding: const EdgeInsets.all(24), decoration: BoxDecoration(color: Colors.black.withOpacity(0.85), borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFFD4AF37), width: 3)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('🎣 출조 셋팅', style: TextStyle(color: Color(0xFFD4AF37), fontSize: 26, fontWeight: FontWeight.bold)), const SizedBox(height: 24),
          Text('대편성 갯수: $selectedRodCount대', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          if (maxRods > 1) Slider(value: selectedRodCount.toDouble(), min: 1, max: maxRods.toDouble(), divisions: maxRods - 1, activeColor: const Color(0xFFD4AF37), inactiveColor: Colors.grey.shade800, onChanged: (v) { _playSFX("sfx_click.mp3"); setState(() => selectedRodCount = v.toInt()); }),
          if (maxRods == 1) const Padding(padding: EdgeInsets.symmetric(vertical: 10), child: Text('바다 낚시는 1대만 지원됩니다.', style: TextStyle(color: Colors.grey, fontSize: 12))),
          const SizedBox(height: 15), const Text('케미라이트 색상', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)), const SizedBox(height: 10),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [ _chemiCircle(Colors.green), const SizedBox(width: 10), _chemiCircle(Colors.red), const SizedBox(width: 10), _chemiCircle(Colors.blue), const SizedBox(width: 10), _chemiCircle(Colors.yellow) ]), const SizedBox(height: 20),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [ const Text('현재 장착 미끼: ', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)), Text(equippedBait != null ? equippedBait!['name'] : '가방에서 터치!', style: TextStyle(color: equippedBait != null ? const Color(0xFFD4AF37) : Colors.redAccent, fontSize: 16, fontWeight: FontWeight.bold)) ]), const SizedBox(height: 20),
          if (widget.isSea) ...[
  const SizedBox(height: 10), // 미끼랑 릴 이름 사이에 간격 살짝!
  Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      const Text('현재 장착 릴: ', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
      Text(
        equippedReel != null ? equippedReel!['name'] : '가방에서 터치!',
        style: TextStyle(
          color: equippedReel != null ? const Color(0xFFD4AF37) : Colors.redAccent,
          fontSize: 16,
          fontWeight: FontWeight.bold,
        ),
      ),
    ],
  ),
],
                    ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFD4AF37), minimumSize: const Size(double.infinity, 50)),
            onPressed: () {
              if (remainingTime <= 0) { _showNotificationPopup('⏱️ 일일 한도 초과', '오늘 허용된 낚시 시간을 모두 소진했습니다.', Colors.redAccent); return; }
              if (equippedRod == null || equippedBait == null) {
                setState(() {
                  equippedRod ??= widget.isSea ? {'name': '오션 스타터', 'category': 'SEA'} : {'name': '베이직 민물대', 'category': 'FW'};
                  equippedFloat ??= {'name': '기본 찌'};
                  equippedBait ??= {'name': '지렁이 (기본)'};
              if (widget.isSea) equippedReel ??= {'name': '기본 릴', 'category': 'SEA'};
                  isRodEquipped = true;
                });
                _showNotificationPopup('✨ 기본 장비 장착 완료!', '빈손이시군요!\n창고에 있던 기본 장비를 쥐여드렸습니다.', const Color(0xFFD4AF37));
              }
             _useBaitOne(); // 💡 처음 던질 때 미끼 1개 소모! 
              _playSFX("sfx_casting.mp3"); _castController.forward(from: 0.0);
              setState(() { isSettingUp = false; isCasting = true; bitingRodIndex = null; });
              Future.delayed(const Duration(milliseconds: 300), () { if (!mounted) return; _playBGM(widget.isSea ? "bgm_sea_fishing.mp3" : "bgm_fresh_fishing.mp3"); _startGameTimer(); });
              Future.delayed(const Duration(milliseconds: 1500), () { if (mounted) { setState(() { isCasting = false; isFloatInWater = true; }); _startBiteTimer(); } });
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
                String castImage = widget.isSea ? 'assets/images/cast_sea.png' : 'assets/images/cast_fw.png';
                return Transform.rotate(angle: swingAngle, origin: Offset(castingOriginX, castingOriginY), child: Image.asset(castImage, height: castingImageSize, fit: BoxFit.contain, errorBuilder: (c,e,s) => const Icon(Icons.waves, size: 200, color: Colors.white10)));
              }
            )
          ),
        ],
      ),
    );
  }

  Widget _chemiCircle(Color color) {
    bool isSelected = selectedChemiColor == color;
    return GestureDetector(onTap: () { _playSFX("sfx_click.mp3"); setState(() => selectedChemiColor = color); }, child: Container(width: 45, height: 45, decoration: BoxDecoration(color: color, shape: BoxShape.circle, border: Border.all(color: isSelected ? Colors.white : Colors.transparent, width: 3), boxShadow: isSelected ? [BoxShadow(color: color, blurRadius: 10, spreadRadius: 2)] : [])));
  }

  Widget _buildFieldRods() {
    if (widget.isSea) {
      return Positioned.fill(child: Stack(children: [Positioned(right: seaWaitingRightOffset, bottom: seaWaitingBottomOffset, child: Transform.rotate(angle: seaWaitingAngle, alignment: Alignment.bottomRight, child: Image.asset('assets/images/waiting_sea.png', height: seaWaitingImageSize, fit: BoxFit.contain, errorBuilder: (c,e,s) => const Icon(Icons.waves, size: 200, color: Colors.white10))))]));
    }
    return Positioned(
      bottom: 0, left: 0, right: 0,
      child: Stack(
        alignment: Alignment.bottomCenter, clipBehavior: Clip.none, 
        children: [
          Positioned(bottom: platformBottomOffset, child: Image.asset('assets/items/platform_fw.png', width: platformWidth, height: platformHeight, fit: BoxFit.fill, color: Colors.black.withOpacity(platformDarkness), colorBlendMode: BlendMode.srcATop, errorBuilder: (c,e,s) => Container())),
          Row(
            mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end,
            children: List.generate(selectedRodCount, (index) {
              bool isBiting = (index == bitingRodIndex); Color currentColor = isBiting ? _getBiteColor(selectedChemiColor) : selectedChemiColor;
              double centerIndex = (selectedRodCount - 1) / 2; double angle = (index - centerIndex) * rodFanAngleStep;
              return Padding(
                padding: EdgeInsets.symmetric(horizontal: fieldFloatSpacing), 
                child: Transform.rotate(
                  angle: angle, alignment: Alignment.bottomCenter, 
                  child: Stack(
                    clipBehavior: Clip.none, alignment: Alignment.bottomCenter,
                    children: [
                      Image.asset('assets/items/rod_fw_basic_deployed.png', height: fieldRodLength, fit: BoxFit.contain, alignment: Alignment.bottomCenter),
                      Positioned(
                        bottom: fieldFloatBottomOffset + fieldFloatDepthOffset, 
                        child: Transform.rotate(
                          angle: -angle, 
                          child: Opacity(
                            opacity: isFloatInWater ? 1.0 : 0.0,
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 6000), curve: Curves.easeOutCubic, width: 30, height: isBiting ? (selectedRodCount >= 8 ? 47.0 : 40.0) : 10.0,
                              child: Stack(alignment: Alignment.topCenter, clipBehavior: Clip.none, children: [Container(width: 2, height: 5, decoration: BoxDecoration(color: currentColor, borderRadius: BorderRadius.circular(5), boxShadow: [BoxShadow(color: currentColor.withOpacity(0.8), blurRadius: 5, spreadRadius: 2)])), Transform.translate(offset: const Offset(0, 5), child: Image.asset(_getIconImagePath(equippedFloat) ?? 'assets/images/float_default.png', height: selectedRodCount >= 8 ? 40 : 65, fit: BoxFit.contain, alignment: Alignment.topCenter))]),
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
    String fightRodImage = widget.isSea ? 'assets/images/hand_rod_sea.png' : 'assets/images/hand_rod_fw.png';
    return Positioned.fill(
      child: Stack(
        children: [
          Positioned(
            right: fightArmRightOffset, bottom: fightArmBottomOffset,
            child: AnimatedBuilder(
                animation: _rodController, 
                builder: (context, child) { 
                  double fightAngle = fightBaseAngle + (math.Random().nextDouble() - 0.5) * (0.05 + (tension * 0.1));
                  return Transform.rotate(angle: fightAngle, origin: Offset(fightOriginX, fightOriginY), child: Image.asset(fightRodImage, height: fightImageSize, fit: BoxFit.contain, errorBuilder: (c,e,s) => const Icon(Icons.waves, size: 200, color: Colors.white10))); 
                }
            )
          ),
          Positioned(
            bottom: 50, left: 100, right: 200,
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
    String label = isFighting ? '당기기' : '챔질!'; 
    Color btnColor = isFighting ? (isPulling ? Colors.red : Colors.orangeAccent) : Colors.redAccent; 
    IconData icon = isFighting ? Icons.arrow_downward : Icons.catching_pokemon;
    
    return GestureDetector(
      onTapDown: (_) {
        if (isFloatInWater && !isFighting) {
          _handleMainActionButton();
        } else if (isFighting) {
          // 💡 [안전장치 1] 이미 당기고 있으면 무시! 화면 그릴 때 안 겹치게 번호표 발급!
          if (!isPulling) {
            Future.microtask(() {
              if (mounted) setState(() { isPulling = true; });
            });
            HapticFeedback.lightImpact();
          }
        }
      },
      onTapUp: (_) { 
        if (isFighting && isPulling) {
          // 💡 [안전장치 2] 손 뗄 때도 안전하게!
          Future.microtask(() {
            if (mounted) setState(() { isPulling = false; });
          });
        }
      },
      onTapCancel: () { 
        if (isFighting && isPulling) {
          // 💡 [안전장치 3] 화면 밖으로 손가락이 삐져나갔을 때도 안전하게!
          Future.microtask(() {
            if (mounted) setState(() { isPulling = false; });
          });
        }
      },
      child: Container(
        width: 120, height: 120, 
        decoration: BoxDecoration(color: btnColor, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 5), boxShadow: const [BoxShadow(blurRadius: 15, spreadRadius: 2, color: Colors.black54)]), 
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(icon, size: 40, color: Colors.white), const SizedBox(height: 5), Text(label, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900))])
      )
    );
  }

  Widget _statText(String title, int value) { return Row(children: [ Text('$title : ', style: const TextStyle(color: Colors.grey, fontSize: 12)), Text('$value', style: const TextStyle(color: Color(0xFFD4AF37), fontSize: 14, fontWeight: FontWeight.bold)) ]); }

  Widget buildInventoryPanel(BuildContext context) {
   
   // 🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩
    // 💡 [여기에 1단계 코드 붙여넣기!] 화면 그리기 전에 미리 스탯부터 계산!
    int totalP = 10; 
    int totalC = 10; 
    int totalS = 10; 
    void calcStat(Map<String, dynamic>? item) {
      if (item == null || item['stats'] == null) return;
      var s = item['stats'];
      totalP += int.tryParse(s['P']?.toString() ?? s['힘']?.toString() ?? '0') ?? 0;
      totalC += int.tryParse(s['C']?.toString() ?? s['컨트롤']?.toString() ?? '0') ?? 0;
      totalS += int.tryParse(s['S']?.toString() ?? s['감도']?.toString() ?? '0') ?? 0;
    }

    calcStat(equippedSkin);
    calcStat(equippedRod);
    calcStat(equippedFloat);
    calcStat(equippedSunglasses);
    calcStat(equippedBadge);
    calcStat(equippedBait);
    // ======================================================== 
    final user = FirebaseAuth.instance.currentUser;
    final ScrollController invScrollCtrl = ScrollController();
    String currentFilter = 'ALL'; 

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('users').doc(user?.uid).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) { return Container(width: 530, height: 500, padding: const EdgeInsets.all(12), decoration: BoxDecoration(gradient: const RadialGradient(center: Alignment(-0.5, -0.5), radius: 1.5, colors: [Color(0xFF3A3A3A), Color(0xFF0F0F0F)]), border: Border.all(color: const Color(0xFFD4AF37), width: 4), borderRadius: BorderRadius.circular(15)), child: const Center(child: CircularProgressIndicator(color: Color(0xFFD4AF37)))); }
        
        List<dynamic> inventory = []; int myLevel = 1; int myGold = 0;
        if (snapshot.hasData && snapshot.data!.data() != null) { var userData = snapshot.data!.data() as Map<String, dynamic>; inventory = userData['inventory'] ?? []; myLevel = userData['level'] ?? 1; myGold = userData['gold'] ?? 0; }
        
        bool isBait(String name) { return name.contains('지렁이') || name.contains('글루텐') || name.contains('옥수수') || name.contains('크릴') || name.contains('에기') || name.contains('루어') || name.contains('미끼'); }

        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setInvState) {
            
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
                    children: ['ALL', 'FW', 'SEA', 'BAIT', 'SKIN'].map((filter) {
                      String label = filter == 'ALL' ? '전체' : filter == 'FW' ? '민물' : filter == 'SEA' ? '바다' : filter == 'BAIT' ? '미끼' : '스킨';
                      bool isSelected = currentFilter == filter;
                      return Expanded(
                        child: GestureDetector(
                          onTap: () { audioManager.playSfx('sfx_click.mp3'); setInvState(() => currentFilter = filter); },
                          child: Container(margin: const EdgeInsets.symmetric(horizontal: 2), padding: const EdgeInsets.symmetric(vertical: 6), decoration: BoxDecoration(color: isSelected ? const Color(0xFFD4AF37) : Colors.black45, borderRadius: BorderRadius.circular(5), border: Border.all(color: isSelected ? Colors.white : Colors.grey.shade800)), child: Center(child: Text(label, style: TextStyle(color: isSelected ? Colors.black : Colors.grey, fontWeight: FontWeight.bold, fontSize: 12)))),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 10),

                  Expanded(
                    child: Scrollbar(
                      controller: invScrollCtrl,
                      thumbVisibility: true, thickness: 8, radius: const Radius.circular(10), 
                      child: GridView.builder(
                        controller: invScrollCtrl, 
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 4, mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: 0.9),
                        itemCount: totalSlots, 
                        itemBuilder: (context, index) {
                          Map<String, dynamic>? itemToShow;
                          if (index < filteredItems.length) itemToShow = filteredItems[index];
                          
                          if (itemToShow == null) {
                            return Container(decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.white10)));
                          }

                          bool isCurrentlyEquipped = false; 
        String iName = itemToShow['name'].toString();
        
        // 💡 [수정 완료] 선글라스랑 휘장도 장착 확인 리스트에 추가!
        if (equippedRod != null && equippedRod!['name'] == iName) isCurrentlyEquipped = true;
        if (equippedFloat != null && equippedFloat!['name'] == iName) isCurrentlyEquipped = true;
        if (equippedSkin != null && equippedSkin!['name'] == iName) isCurrentlyEquipped = true;
        if (equippedBait != null && equippedBait!['name'] == iName) isCurrentlyEquipped = true;
        if (equippedSunglasses != null && equippedSunglasses!['name'] == iName) isCurrentlyEquipped = true;
        if (equippedBadge != null && equippedBadge!['name'] == iName) isCurrentlyEquipped = true;
        if (equippedReel != null && equippedReel!['name'] == iName) isCurrentlyEquipped = true;
                          
                          return GestureDetector(
                            onTap: () => _showEquipPopup(itemToShow!), 
                            child: Container(
                              decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(8), border: Border.all(color: isCurrentlyEquipped ? const Color(0xFFD4AF37) : Colors.grey.shade800, width: 2)), 
                              child: Stack(alignment: Alignment.center, children: [ 
                                Column(
                                  mainAxisAlignment: MainAxisAlignment.center, 
                                  children: [ 
                                    _getIconImagePath(itemToShow) != null 
                                      ? ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.asset(_getIconImagePath(itemToShow)!, width: 75, height: 75, fit: BoxFit.contain)) 
                                      : const Icon(Icons.inventory_2, color: Colors.white54, size: 40), 
                                    const SizedBox(height: 6), 
                                    FittedBox(fit: BoxFit.scaleDown, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4.0), child: Text(itemToShow['name'], style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold), textAlign: TextAlign.center))) 
                                  ]
                                ), 
                                if (isCurrentlyEquipped) const Positioned(top: 4, right: 4, child: Icon(Icons.check_circle, color: Color(0xFFD4AF37), size: 18)),
                                // 💡 [수량 뱃지 추가된 부분]
                                if (itemToShow['quantity'] != null && itemToShow['type'] == 'BAIT')
                                  Positioned(
                                    bottom: 4, right: 4, 
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2), 
                                      decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(4), border: Border.all(color: Colors.white54, width: 0.5)), 
                                      child: Text('${itemToShow['quantity']}개', style: const TextStyle(color: Colors.yellowAccent, fontSize: 10, fontWeight: FontWeight.bold))
                                    )
                                  )
                              ])
                            )
                          );
                        }
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  // 💡 [버튼 100% 유지 구역]
                  Row(children: [ 
  // 1. KREFT 상점 버튼 (그대로 유지)
  Expanded(child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.black, foregroundColor: const Color(0xFFD4AF37), side: const BorderSide(color: Color(0xFFD4AF37), width: 1.5), padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))), onPressed: () { _playSFX("sfx_click.mp3"); Navigator.push(context, MaterialPageRoute(builder: (context) => StoreScreen(currentGold: myGold, currentLevel: myLevel))); }, child: const Text('🛒 KREFT 상점', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)))), 
  
  const SizedBox(width: 8), 
  
  // ⚡ 스마트 자동 장착 버튼
  Expanded(child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.grey.shade800, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))), onPressed: () { 
    _playSFX("sfx_click.mp3"); 
    setState(() { 
      List<dynamic> validItems = inventory.where((item) { 
        String cat = item['category'] ?? ''; 
        if (widget.isSea && cat == 'FW') return false; 
        if (!widget.isSea && cat == 'SEA') return false; 
        return true; 
      }).toList(); 
      
      // 1. 모든 장착 슬롯 초기화
      equippedRod = null; equippedFloat = null; equippedBait = null; 
      equippedSunglasses = null; equippedBadge = null; equippedSkin = null;
      equippedReel = null; 

      // 2. 최고 등급/수량 판별용 변수
      Map<String, dynamic>? bestSkin;
      Map<String, dynamic>? bestBait;
      Map<String, dynamic>? bestFloat;
      Map<String, dynamic>? bestRod;
      Map<String, dynamic>? bestReel;
      int maxBaitQty = -1;

      // 💡 스킨 등급 판독기 (숫자가 높을수록 고인물!)
      int getSkinTier(String name) {
        if (name.contains('마스터')) return 5;
        if (name.contains('프로') || name.contains('고수')) return 4;
        if (name.contains('중수')) return 3;
        if (name.contains('하수') || name.contains('초보')) return 2;
        return 1;
      }

// 🚨 [추가!] 낚싯대 등급 판독기 (숫자가 높을수록 명품!)
      int getRodTier(String name) {
        String n = name.replaceAll(' ', '').replaceAll('-', '').toUpperCase();
        if (n.contains('KT40')) return 60;
        if (n.contains('KT30')) return 50;
        if (n.contains('KT20')) return 40;
        if (n.contains('CF40')) return 30;
        if (n.contains('CF30')) return 20;
        if (n.contains('CF20')) return 10;
        return 1; // 일반 낚싯대
      }

      // 🎈 찌 등급 판독기 (띄어쓰기 무시!)
      int getFloatTier(String name) {
        String n = name.replaceAll(' ', '').toUpperCase(); 
        if (n.contains('KT전자')) return 60;
        if (n.contains('CF전자')) return 50;
        if (n.contains('나노')) return 40;
        if (n.contains('수제')) return 30;
        if (n.contains('오동')) return 20;
        return 1;
      }

     // 🎣 바다 낚싯대 계급표 (250, 350, 500 시리즈)
      int getSeaRodTier(String name) {
        String n = name.replaceAll(' ', '').toUpperCase();
        if (n.contains('KT500')) return 60;
        if (n.contains('KT350')) return 50;
        if (n.contains('KT250')) return 40;
        if (n.contains('CF500')) return 30;
        if (n.contains('CF350')) return 20;
        if (n.contains('CF250')) return 10;
        return 1;
      }

      // ⚙️ 릴 계급표 (3000, 5000, 6000, 8000 시리즈)
      int getReelTier(String name) {
        String n = name.replaceAll(' ', '').toUpperCase();
        if (n.contains('KF8000')) return 80;
        if (n.contains('KF6000')) return 60;
        if (n.contains('KF5000')) return 50;
        if (n.contains('CF5000')) return 40;
        if (n.contains('CF3000')) return 30;
        return 1;
      } 

      for (var item in validItems) { 
        String name = item['name'].toString(); 

        // 👕 스킨: 보유 스킨 중 가장 등급이 높은 것 장착!
        if (name.contains('스킨') || name.contains('조사') || name.contains('마스터')) {
          if (bestSkin == null || getSkinTier(name) > getSkinTier(bestSkin!['name'].toString())) {
            bestSkin = item;
          }
        } 
        
        // 🎈 찌: 보유 찌 중 가장 등급이 높은 것 장착!
        else if (name.contains('찌')) {
          if (bestFloat == null || getFloatTier(name) > getFloatTier(bestFloat!['name'].toString())) {
            bestFloat = item;
          }
        }

        // ⚙️ 릴: 등급이 제일 높은 놈으로!
        else if (item['type'] == 'REEL' || name.contains('000') || name.contains('릴')) {
          if (bestReel == null || getReelTier(name) > getReelTier(bestReel!['name'].toString())) {
            bestReel = item;
          }
        } 
        
        // 🎣 낚싯대: 바다 vs 민물 구분해서 눈치껏 장착!
        else if ((name.contains('대') || name.contains('CF') || name.contains('KT')) && !name.contains('찌') && !name.contains('릴')) {
          
          // 이름에 250, 350, 500이 들어가면 바다 낚싯대!
          bool isSeaRod = name.contains('250') || name.contains('350') || name.contains('500');

          if (widget.isSea) { 
            // 🌊 [바다 모드] 바다 낚싯대 중에서 제일 좋은 거!
            if (isSeaRod) {
              if (bestRod == null || getSeaRodTier(name) > getSeaRodTier(bestRod!['name'].toString())) {
                bestRod = item;
              }
            }
          } else { 
            // 🏞️ [민물 모드] 민물 낚싯대 중에서 제일 좋은 거!
            if (!isSeaRod) {
              if (bestRod == null || getRodTier(name) > getRodTier(bestRod!['name'].toString())) {
                bestRod = item;
              }
            }
          }
        }
        // 😎 선글라스
        else if (name.contains('선글라스') && equippedSunglasses == null) {
          equippedSunglasses = item;
        } 
        // 🎖️ 휘장: 맵(바다/민물)에 맞는 휘장 장착!
        else if (name.contains('휘장')) {
          if (widget.isSea && name.contains('바다')) equippedBadge = item;
          if (!widget.isSea && name.contains('민물')) equippedBadge = item;
        }
        // 🪱 미끼: 수량이 가장 많은 미끼 장착!
        else if (name.contains('미끼') || name.contains('지렁이') || name.contains('글루텐') || name.contains('옥수수') || name.contains('크릴') || name.contains('에기')) {
          int qty = item['quantity'] as int? ?? 0;
          if (qty > maxBaitQty) {
            maxBaitQty = qty;
            bestBait = item;
          }
        } 
      } 
      
      // 판독 끝! 최종 장착
      equippedSkin = bestSkin;
      equippedBait = bestBait;
      equippedRod = bestRod;
      equippedReel = bestReel;
      equippedFloat = bestFloat; // 👈 찾아낸 최고급 명품을 쥐여줍니다!
      isRodEquipped = equippedRod != null; 
    }); 
    
    _showNotificationPopup('⚡ 세팅 완료!', '현재 맵에 맞는 최고 효율 장비로\n완벽하게 세팅되었습니다.', const Color(0xFFD4AF37)); 
  }, child: const Text('⚡ 자동 장착', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)))) 
]),
                ],
              ),
            );
          }
        );
      },
    );
  }

  // 🏢 [1층] UI - Popup: 팝업창 및 알림
  // =========================================================================
  void _showNotificationPopup(String title, String content, Color color, {VoidCallback? onConfirm}) {
    showDialog(
      context: context, barrierDismissible: false, 
      builder: (context) => AlertDialog(backgroundColor: Colors.grey.shade900, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15), side: BorderSide(color: color, width: 2)), title: Text(title, style: TextStyle(color: color, fontWeight: FontWeight.bold), textAlign: TextAlign.center), content: Text(content, style: const TextStyle(color: Colors.white, fontSize: 16), textAlign: TextAlign.center), actions: [ Center(child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: color, foregroundColor: Colors.black), onPressed: () { audioManager.playSfx("sfx_click.mp3"); Navigator.pop(context); if (onConfirm != null) onConfirm(); }, child: const Text('확인', style: TextStyle(fontWeight: FontWeight.bold)))) ]),
    );
  }

  void _showEquipPopup(Map<String, dynamic> item) {
    _playSFX("sfx_click.mp3"); 

    // 💡 [새로 추가된 안전장치] 맵에 안 맞는 장비 컷!
    String category = item['category'] ?? '';
    if (widget.isSea && category == 'FW') {
      _showNotificationPopup('착용 불가 🚫', '바다 낚시터에서는 민물 장비/미끼를 쓸 수 없습니다!', Colors.redAccent);
      return;
    }
    if (!widget.isSea && category == 'SEA') {
      _showNotificationPopup('착용 불가 🚫', '민물 낚시터에서는 바다 장비/미끼를 쓸 수 없습니다!', Colors.redAccent);
      return;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey.shade900, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15), side: const BorderSide(color: Color(0xFFD4AF37))),
        title: const Text('🎧 아이템 장착', style: TextStyle(color: Color(0xFFD4AF37), fontWeight: FontWeight.bold)),
        content: Text('${item['name']}\n\n${item['desc'] ?? ''}\n${item['stats'] ?? ''}\n\n이 아이템을 장착하시겠습니까?', style: const TextStyle(color: Colors.white)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('취소', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFD4AF37), foregroundColor: Colors.black),
            onPressed: () {
              _playSFX("sfx_click.mp3");
              setState(() {
            String itemName = item['name'].toString();
            // 💡 대문자로 싹 통일해서 소문자 cf2000 도망 못 가게 검문 강화!
            String cleanName = itemName.replaceAll(' ', '').toUpperCase();

            if (cleanName.contains('찌')) {
              equippedFloat = item;
            } else if (cleanName.contains('스킨') || cleanName.contains('조사') || cleanName.contains('초보') || cleanName.contains('마스터')) {
              equippedSkin = item;
            } else if ((cleanName.contains('릴') && !cleanName.contains('크릴')) || cleanName.contains('2000') || cleanName.contains('3000') || cleanName.contains('5000') || cleanName.contains('6000') || cleanName.contains('8000')) {
  equippedReel = item; 
            } else if (cleanName.contains('대') || cleanName.contains('CF') || cleanName.contains('KT')) {
              // 위에서 릴(2000, 3000 등)을 먼저 걸러냈기 때문에, 여기 남는 CF나 KT는 진짜 낚싯대뿐입니다!
              equippedRod = item;
              isRodEquipped = true;
            } else if (cleanName.contains('선글라스')) {
              equippedSunglasses = item;
            } else if (cleanName.contains('휘장')) {
              equippedBadge = item;
            } else {
              // 위에서 다 걸러지고 진짜 남은 갯지렁이, 옥수수 같은 것만 미끼로!
              equippedBait = item;
            }
          });
              Navigator.pop(context);
            },
            child: const Text('장착하기', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showResultPopup(Map<String, dynamic> caughtFish) {
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
            Container(
              decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.white24)), 
              padding: const EdgeInsets.all(10), 
              child: Image.asset(
                imagePath, height: 160, fit: BoxFit.contain, 
                errorBuilder: (c,e,s) {
                  debugPrint('🚨 [사진 실종] 경로 확인 요망: $imagePath');
                  return const Icon(Icons.set_meal, color: Colors.white54, size: 100);
                }
              )
            ),
            const SizedBox(height: 15),
            Text('${caughtFish['name']}', style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold)),
            Text('${caughtFish['size']} ${caughtFish['unit']}', style: const TextStyle(color: Colors.cyanAccent, fontSize: 38, fontWeight: FontWeight.w900)),
            const SizedBox(height: 10), 
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
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.grey.shade800, foregroundColor: Colors.white),
            onPressed: () {
              Navigator.pop(context); 
              gameTimer?.cancel(); fightTimer?.cancel(); biteTimer?.cancel();
              setState(() { isSettingUp = true; isCasting = false; isFighting = false; isFloatInWater = false; bitingRodIndex = null; });
            },
            icon: const Icon(Icons.build, size: 18), label: const Text('채비 변경'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFD4AF37), foregroundColor: Colors.black),
            onPressed: () {
              Navigator.pop(context); 
              setState(() { isSettingUp = false; isFighting = false; isFloatInWater = false; isCasting = true; bitingRodIndex = null; });
              try { _playSFX("sfx_casting.mp3"); _castController.forward(from: 0.0); } catch (e) {}
              Future.delayed(const Duration(milliseconds: 1500), () { if (mounted) { setState(() { isCasting = false; isFloatInWater = true; }); try { _startBiteTimer(); } catch (e) {} } });
            },
            child: const Text('캐스팅', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      )
    );
  }
}

// 🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩
// 🛒 [6. KREFT 공식 상점] - 상품 데이터 통제실 (민물/바다 분리형)

class StoreScreen extends StatefulWidget {
  final int currentGold;
  final int currentLevel;
  const StoreScreen({super.key, required this.currentGold, required this.currentLevel});

  @override
  State<StoreScreen> createState() => _StoreScreenState();
}

class _StoreScreenState extends State<StoreScreen> {
  late int myDisplayGold;
  String currentTab = 'ROD'; 

  @override
  void initState() {
    super.initState();
    myDisplayGold = widget.currentGold;
  }

  void _showNotificationPopup(String t, String c, Color col, {VoidCallback? onConfirm}) {
    showDialog(
      context: context, 
      barrierDismissible: false, 
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.grey.shade900, 
        title: Text(t, style: TextStyle(color: col, fontWeight: FontWeight.bold)), 
        content: Text(c, style: const TextStyle(color: Colors.white)), 
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFD4AF37), foregroundColor: Colors.black),
            onPressed: () { 
              Navigator.pop(ctx); 
              onConfirm?.call(); 
            }, 
            child: const Text('확인', style: TextStyle(fontWeight: FontWeight.bold))
          )
        ]
      )
    );
  }

  void _launchMall() async {
    _showNotificationPopup('쇼핑몰 이동', 'Camping Fishing 공식 쇼핑몰(camnak.com)로 이동하여\n멋진 스킨을 구매하시겠습니까?', const Color(0xFFD4AF37));
  }

  final List<Map<String, dynamic>> rodItems = [
    {'name': 'CF-20T', 'price': 0, 'category': 'FW', 'type': 'ROD', 'stats': {'P': 0, 'C': 0, 'S': 0}, 'icon': 'rod_fw_cf20.png', 'desc': '초보 조사용 기본 민물대'},
    {'name': 'CF-30T', 'price': 1, 'category': 'FW', 'type': 'ROD', 'stats': {'P': 10, 'C': 10, 'S': 10}, 'icon': 'rod_fw_cf30.png', 'desc': '입문자를 위한 밸런스형 민물대'},
    {'name': 'CF-40T', 'price': 2, 'category': 'FW', 'type': 'ROD', 'stats': {'P': 20, 'C': 20, 'S': 20}, 'icon': 'rod_fw_cf40.png', 'desc': '중급 조사용 고탄성 민물대'},
    {'name': 'KT-20T', 'price': 5, 'category': 'FW', 'type': 'ROD', 'stats': {'P': 30, 'C': 30, 'S': 30}, 'icon': 'rod_fw_kt20.png', 'desc': '프리미엄 KREFT 민물대'},
    {'name': 'KT-30T', 'price': 1, 'category': 'FW', 'type': 'ROD', 'stats': {'P': 40, 'C': 40, 'S': 40}, 'icon': 'rod_fw_kt30.png', 'desc': '대물 붕어 제압용 프로 민물대'},
    {'name': 'KT-40', 'price': 2, 'category': 'FW', 'type': 'ROD', 'stats': {'P': 50, 'C': 50, 'S': 50}, 'icon': 'rod_fw_kt40.png', 'desc': '민물 낚시의 정점, 마스터 민물대'},
    {'name': 'CF250', 'price': 0, 'category': 'SEA', 'type': 'ROD', 'stats': {'P': 0, 'C': 0, 'S': 0}, 'icon': 'rod_sea_cf250.png', 'desc': '바다 낚시 입문용 기본대'},
    {'name': 'CF350', 'price': 1, 'category': 'SEA', 'type': 'ROD', 'stats': {'P': 10, 'C': 10, 'S': 10}, 'icon': 'rod_sea_cf350.png', 'desc': '연안 방파제용 전천후 바다대'},
    {'name': 'CF500', 'price': 2, 'category': 'SEA', 'type': 'ROD', 'stats': {'P': 20, 'C': 20, 'S': 10}, 'icon': 'rod_sea_cf500.png', 'desc': '원투 낚시에 최적화된 바다대'},
    {'name': 'KT250', 'price': 5, 'category': 'SEA', 'type': 'ROD', 'stats': {'P': 30, 'C': 20, 'S': 10}, 'icon': 'rod_sea_kt250.png', 'desc': '선상 낚시의 표준, KREFT 바다대'},
    {'name': 'KT350', 'price': 1, 'category': 'SEA', 'type': 'ROD', 'stats': {'P': 40, 'C': 40, 'S': 40}, 'icon': 'rod_sea_kt350.png', 'desc': '프로 앵글러를 위한 고강도 바다대'},
    {'name': 'KT500', 'price': 2, 'category': 'SEA', 'type': 'ROD', 'stats': {'P': 50, 'C': 50, 'S': 50}, 'icon': 'rod_sea_kt500.png', 'desc': '심해 대물 제압용 마스터 바다대'},
  ];

  final List<Map<String, dynamic>> gearItems = [
    {'name': '일반찌', 'price': 0, 'category': 'FW', 'type': 'FLOAT', 'stats': {'S': 0}, 'icon': 'float_fw_normal.png', 'desc': '가장 기본적인 민물 찌'},
    {'name': '오동나무찌', 'price': 5, 'category': 'FW', 'type': 'FLOAT', 'stats': {'S': 10}, 'icon': 'float_fw_wood.png', 'desc': '예민한 입질 파악을 위한 찌'},
    {'name': '수제찌', 'price': 1, 'category': 'FW', 'type': 'FLOAT', 'stats': {'S': 20}, 'icon': 'float_fw_handmade.png', 'desc': '장인이 깎아 만든 고감도 수제찌'},
    {'name': '나노카본찌', 'price': 2, 'category': 'FW', 'type': 'FLOAT', 'stats': {'S': 30}, 'icon': 'float_fw_nano.png', 'desc': '최첨단 소재로 만든 초정밀 찌'},
    {'name': 'CF 전자찌', 'price': 5, 'category': 'FW', 'type': 'FLOAT', 'stats': {'S': 40}, 'icon': 'float_fw_elec_cf.png', 'desc': '야간 낚시의 필수품'},
    {'name': 'KT 전자찌', 'price': 1, 'category': 'FW', 'type': 'FLOAT', 'stats': {'S': 50}, 'icon': 'float_fw_elec_kt.png', 'desc': '압도적인 시인성을 자랑하는 최고급 전자찌'},
    {'name': 'cf2000', 'price': 0, 'category': 'SEA', 'type': 'REEL', 'stats': {'P': 0}, 'icon': 'reel_sea_cf2000', 'desc': '기본 제공되는 바다 릴'},
    {'name': 'CF3000', 'price': 1, 'category': 'SEA', 'type': 'REEL', 'stats': {'P': 10, 'C': 10, 'S': 10}, 'icon': 'reel_sea_cf3000.png', 'desc': '방파제용 경량 릴'},
    {'name': 'CF5000', 'price': 2, 'category': 'SEA', 'type': 'REEL', 'stats': {'P': 20, 'C': 20, 'S': 20}, 'icon': 'reel_sea_cf5000.png', 'desc': '원투 낚시용 중형 릴'},
    {'name': 'KF5000', 'price': 5, 'category': 'SEA', 'type': 'REEL', 'stats': {'P': 30, 'C': 30, 'S': 30}, 'icon': 'reel_sea_kf5000.png', 'desc': '선상 낚시용 고급 릴'},
    {'name': 'KF6000', 'price': 1, 'category': 'SEA', 'type': 'REEL', 'stats': {'P': 40, 'C': 40, 'S': 40}, 'icon': 'reel_sea_kf6000.png', 'desc': '대형 어종 제압을 위한 강력한 릴'},
    {'name': 'KF8000', 'price': 2, 'category': 'SEA', 'type': 'REEL', 'stats': {'P': 50, 'C': 50, 'S': 40}, 'icon': 'reel_sea_kf8000.png', 'desc': '괴물과 싸우기 위한 마스터급 대형 릴'},
  ];

  final List<Map<String, dynamic>> baitItems = [
    {'name': '지렁이', 'price': 5, 'category': 'FW', 'type': 'BAIT', 'quantity': 50, 'icon': 'bait_fw_worm.png', 'desc': '민물 잡어부터 붕어까지 만능 미끼 (집어력 10)'},
    {'name': '글루텐', 'price': 1, 'category': 'FW', 'type': 'BAIT', 'quantity': 50, 'icon': 'bait_fw_gluten.png', 'desc': '붕어 집어에 탁월한 미끼 (집어력 20)'},
    {'name': '옥수수', 'price': 2, 'category': 'FW', 'type': 'BAIT', 'quantity': 50, 'icon': 'bait_fw_corn.png', 'desc': '대물 붕어를 노리기 위한 미끼 (집어력 30)'},
    {'name': '갯지렁이', 'price': 5, 'category': 'SEA', 'type': 'BAIT', 'quantity': 50, 'icon': 'bait_sea_worm.png', 'desc': '바다 낚시의 기본 미끼 (집어력 10)'},
    {'name': '크릴', 'price': 1, 'category': 'SEA', 'type': 'BAIT', 'quantity': 50, 'icon': 'bait_sea_krill.png', 'desc': '다양한 어종을 유혹하는 미끼 (집어력 20)'},
    {'name': '루어', 'price': 2, 'category': 'SEA', 'type': 'BAIT', 'quantity': 50, 'icon': 'bait_sea_lure.png', 'desc': '육식성 어종을 노리는 가짜 미끼 (집어력 30)'},
    {'name': '에기', 'price': 2, 'category': 'SEA', 'type': 'BAIT', 'quantity': 50, 'icon': 'bait_sea_egi.png', 'desc': '두족류(오징어, 문어 등) 전용 미끼 (집어력 30)'},
  ];

  final List<Map<String, dynamic>> skinItems = [
    {'name': '초보 조사', 'price': 0, 'category': 'SKIN', 'type': 'SKIN', 'stats': {'P': 10, 'C': 10, 'S': 10}, 'icon': '../images/skin_novice.jpg', 'desc': '가장 기본적인 낚시꾼 복장'},
    {'name': '하수 조사', 'price': 5000, 'category': 'SKIN', 'type': 'SKIN', 'stats': {'P': 20, 'C': 20, 'S': 20}, 'icon': '../images/skin_beginner.jpg', 'desc': '낚시에 맛을 들인 조사 (쇼핑몰 전용)'},
    {'name': '중수 조사', 'price': 10000, 'category': 'SKIN', 'type': 'SKIN', 'stats': {'P': 50, 'C': 50, 'S': 50}, 'icon': '../images/skin_intermediate.jpg', 'desc': '포인트 보는 눈이 생긴 조사 (쇼핑몰 전용)'},
    {'name': '고수 조사', 'price': 20000, 'category': 'SKIN', 'type': 'SKIN', 'stats': {'P': 100, 'C': 100, 'S': 100}, 'icon': '../images/skin_expert.jpg', 'desc': '어디서든 한 마리는 낚아내는 고수 (쇼핑몰 전용)'},
    {'name': '프로 조사', 'price': 50000, 'category': 'SKIN', 'type': 'SKIN', 'stats': {'P': 150, 'C': 150, 'S': 150}, 'icon': '../images/skin_pro.jpg', 'desc': '스폰서를 받는 프로 앵글러 (쇼핑몰 전용)'},
    {'name': '마스터 조사', 'price': 100000, 'category': 'SKIN', 'type': 'SKIN', 'stats': {'P': 300, 'C': 300, 'S': 300}, 'icon': '../images/skin_master.jpg', 'desc': '낚시계의 살아있는 전설 (쇼핑몰 전용)'},
    {'name': '선글라스', 'price': 1, 'category': 'COMMON', 'type': 'ETC', 'stats': {'S': 50}, 'icon': 'item_sunglasses.png', 'desc': '눈부심을 막아 찌를 잘 보게 해주는 장비'},
    {'name': '민물 휘장', 'price': 2, 'category': 'FW', 'type': 'ETC', 'stats': {'P': 20, 'C': 20, 'S': 20}, 'icon': 'item_badge_fw.png', 'desc': '민물 낚시 명예의 증표'},
    {'name': '바다 휘장', 'price': 5, 'category': 'SEA', 'type': 'ETC', 'stats': {'P': 50, 'C': 50, 'S': 50}, 'icon': 'item_badge_sea.png', 'desc': '바다 낚시 명예의 증표'},
  ];

  @override
  Widget build(BuildContext context) {
    List<Map<String, dynamic>> displayList = [];
    if (currentTab == 'ROD') displayList = rodItems;
    if (currentTab == 'GEAR') displayList = gearItems;
    if (currentTab == 'BAIT') displayList = baitItems;
    if (currentTab == 'SKIN') displayList = skinItems;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('🛒 KREFT OFFICIAL STORE', style: TextStyle(color: Color(0xFFD4AF37), fontWeight: FontWeight.bold)),
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          Center(child: Padding(padding: const EdgeInsets.only(right: 20), child: Text('내 포인트: $myDisplayGold P', style: const TextStyle(color: Colors.yellowAccent, fontWeight: FontWeight.bold, fontSize: 16)))),
        ],
      ),
      body: Column(
        children: [
          // 💡 [수정] Expanded를 빼고 왼쪽(start)으로 싹 몰아준 명품관 스타일 탭!
        Container(
          padding: const EdgeInsets.only(left: 20), // 전체 좌측 여백을 살짝 줍니다
          child: Row(
            mainAxisAlignment: MainAxisAlignment.start, // 👈 [핵심] 왼쪽 끝으로 정렬!
            children: ['ROD', 'GEAR', 'BAIT', 'SKIN'].map((tab) {
              String label = tab == 'ROD' ? '낚싯대' : tab == 'GEAR' ? '릴/찌' : tab == 'BAIT' ? '미끼' : '스킨/기타';
              bool isSelected = currentTab == tab; // 현재 선택된 탭인지 확인
              
              return GestureDetector(
                onTap: () { setState(() => currentTab = tab); },
                child: Container(
                  margin: const EdgeInsets.only(right: 40), // 👈 탭과 탭 사이의 간격 (널찍하게)
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  decoration: BoxDecoration(
                    // 선택된 탭만 아래에 금색 밑줄 쫙!
                    border: Border(bottom: BorderSide(color: isSelected ? const Color(0xFFD4AF37) : Colors.transparent, width: 3)),
                  ),
                  child: Text(
                    label, 
                    style: TextStyle(
                      color: isSelected ? const Color(0xFFD4AF37) : Colors.grey, 
                      fontWeight: FontWeight.bold, 
                      fontSize: 16
                    )
                  ),
                ),
              );
            }).toList(), // map 끝에 toList() 잊지 마세요!
          ),
        ),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(20),
              // 💡 찌그러짐 방지! 아이템 박스 크기 고정 (1줄 배치)
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 1, 
                mainAxisSpacing: 20, 
                crossAxisSpacing: 20, 
                mainAxisExtent: 160 
              ),
              itemCount: displayList.length,
              itemBuilder: (context, index) {
                return _buildStoreItem(displayList[index]);
              },
            ),
          ),
        ],
      ),
    );
  }

 // 💡 스탯을 예쁜 박스(배지)로 만들어주는 함수
  Widget _buildStatBadge(String label, int val, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15), 
        borderRadius: BorderRadius.circular(6), 
        border: Border.all(color: color.withOpacity(0.5))
      ),
      child: Text('$label $val', style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold)),
    );
  }
    // 💡 4분할 명품관 UI 2.0 (고급진 스킨 버튼 & 럭셔리 알림 적용)
  Widget _buildStoreItem(Map<String, dynamic> item) {
    bool isBait = item['type'] == 'BAIT';
    bool isSkin = item['type'] == 'SKIN';
    String itemName = item['name'].toString();

    // 경로 보정 (안전장치)
    String imgPath = item['icon']?.toString() ?? '';
    if (imgPath.contains('../')) imgPath = imgPath.replaceAll('../', 'assets/');
    if (!imgPath.startsWith('assets/')) imgPath = imgPath.contains('.jpg') ? 'assets/images/$imgPath' : 'assets/items/$imgPath';

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF151515),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: isSkin ? const Color(0xFFD4AF37).withOpacity(0.8) : Colors.white10, width: isSkin ? 1.5 : 1.0),
      ),
      child: Row(
        children: [
          // 🟥 [1칸] 아이템 썸네일
          Container(
            width: 140, 
            padding: const EdgeInsets.all(15),
            decoration: const BoxDecoration(color: Colors.black38, borderRadius: BorderRadius.only(topLeft: Radius.circular(15), bottomLeft: Radius.circular(15))),
            child: Image.asset(imgPath, fit: BoxFit.contain, errorBuilder: (c, e, s) => const Icon(Icons.broken_image, color: Colors.white24, size: 40)),
          ),
          Container(width: 1, color: Colors.white10),

          // 🟨 [2칸] 아이템 이름 & 스탯
          Expanded(
            flex: 3,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(itemName, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900), overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 12),
                  if (item['stats'] != null)
                    Row(
                      children: [
                        _buildStatBadge('파워', item['stats']['P'] ?? 0, Colors.redAccent),
                        const SizedBox(width: 6),
                        _buildStatBadge('컨트롤', item['stats']['C'] ?? 0, Colors.blueAccent),
                        const SizedBox(width: 6),
                        _buildStatBadge('감도', item['stats']['S'] ?? 0, Colors.greenAccent),
                      ],
                    )
                  else if (isBait)
                    Text('수량: x${item['quantity']}개', style: const TextStyle(color: Colors.yellowAccent, fontSize: 14, fontWeight: FontWeight.bold))
                  else
                    const Text('기본 장비', style: TextStyle(color: Colors.grey, fontSize: 13)),
                ],
              ),
            ),
          ),
          Container(width: 1, color: Colors.white10),

          // 🟩 [3칸] 착용 효과
          Expanded(
            flex: 4,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.auto_awesome, color: Color(0xFFD4AF37), size: 16),
                      SizedBox(width: 6),
                      Text('장비 효과', style: TextStyle(color: Color(0xFFD4AF37), fontSize: 13, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(item['desc'] ?? '', style: TextStyle(color: Colors.grey.shade300, fontSize: 14, height: 1.4), maxLines: 2, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          ),
          Container(width: 1, color: Colors.white10),

          // 🟦 [4칸] 가격 명시 & 고급진 구매/이동 버튼 분리!
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.all(15.0),
              child: isSkin 
                // 💎 [스킨 전용 UI] 대빵만했던 노란 네모 삭제! 고급진 스타일로 변경
                ? Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: itemName.contains('초보') 
                      ? [ // 초보 조사인 경우
                          const Center(child: Text('기본 지급', style: TextStyle(color: Colors.grey, fontSize: 16, fontWeight: FontWeight.bold))),
                          const SizedBox(height: 10),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.grey.shade900, foregroundColor: Colors.grey, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                            onPressed: null, // 클릭 방지
                            child: const Text('보유 중', style: TextStyle(fontWeight: FontWeight.bold)),
                          )
                        ]
                      : [ // 일반 스킨인 경우
                          Center(child: Text('상점 구매불가', style: TextStyle(color: Colors.redAccent.shade100, fontSize: 14, fontWeight: FontWeight.bold))),
                          const SizedBox(height: 10),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.black, // 블랙 베이스
                              foregroundColor: const Color(0xFFD4AF37), // 골드 텍스트
                              side: const BorderSide(color: Color(0xFFD4AF37), width: 1.5), // 골드 테두리
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            onPressed: () => _launchMall(),
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [Icon(Icons.open_in_new, size: 16), SizedBox(width: 6), Text('쇼핑몰 가기', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14))],
                            ),
                          )
                        ],
                  )
                // 🛒 [일반 장비 전용 UI] 촌스러운 녹색 팝업 안녕! 
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(child: Text('${item['price']} P', style: const TextStyle(color: Color(0xFFD4AF37), fontSize: 22, fontWeight: FontWeight.w900))),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            flex: 1,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.grey.shade800, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                              onPressed: () {
                                // 💡 [수정] 촌스러운 녹색 팝업 -> KREFT 명품관 럭셔리 알림으로 교체!
                                ScaffoldMessenger.of(context).hideCurrentSnackBar(); // 기존꺼 숨기기
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                  content: Row(children: [const Icon(Icons.check_circle, color: Color(0xFFD4AF37)), const SizedBox(width: 10), Expanded(child: Text('$itemName 장바구니 담기 완료!', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)))]),
                                  backgroundColor: Colors.grey.shade900,
                                  behavior: SnackBarBehavior.floating, // 화면 아래에 둥둥 뜨게
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: const BorderSide(color: Color(0xFFD4AF37))),
                                  duration: const Duration(seconds: 2),
                                ));
                              },
                              child: const Icon(Icons.add_shopping_cart, size: 20),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 2,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFD4AF37), foregroundColor: Colors.black, padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                              onPressed: () => _buyItem(item),
                              child: const Text('구매하기', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
            ),
          ),
        ],
      ),
    );
  }
  void _buyItem(Map<String, dynamic> item) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    
    if (item['price'] > 0 && myDisplayGold < item['price']) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('🚫 포인트가 부족합니다! 열심히 고기를 잡으세요!')));
      return;
    }

    try {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
        'gold': FieldValue.increment(-item['price']),
        'inventory': FieldValue.arrayUnion([{
          'name': item['name'],
          'category': item['category'],
          'type': item['type'],
          'stats': item['stats'],
          'icon': item['icon'],
          'quantity': item['quantity'] ?? 1,
        }])
      });
      setState(() { myDisplayGold -= (item['price'] as int); });
      // 💡 [수정 완료] 기존 SnackBar 삭제하고 VIP 명품관 팝업으로 교체!
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: Colors.grey.shade900,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15), 
            side: const BorderSide(color: Color(0xFFD4AF37), width: 1.5)
          ),
          title: const Row(
            children: [
              Icon(Icons.shopping_bag, color: Color(0xFFD4AF37)),
              SizedBox(width: 8),
              Text('결제 완료', style: TextStyle(color: Color(0xFFD4AF37), fontWeight: FontWeight.bold)),
            ],
          ),
          content: Text(
            '🎉 ${item['name']}\n성공적으로 구매하셨습니다!\n인벤토리에서 장착해 보세요.',
            style: const TextStyle(color: Colors.white, height: 1.5),
          ),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFD4AF37),
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () => Navigator.pop(context),
              child: const Text('확인', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );
    } catch (e) { print(e); }
  }
}

// 💡 내 등급(스킨)에 맞는 캐릭터 투명(누끼) 이미지 찾아주는 자판기!
    String getLobbyCharacterImage(String skinName) {
    String cleanName = skinName.replaceAll(' ', '').toUpperCase();
    
    if (cleanName.contains('하수')) return 'assets/images/char_beginner.png';
    if (cleanName.contains('중수')) return 'assets/images/char_intermediate.png';
    if (cleanName.contains('고수')) return 'assets/images/char_expert.png';
    if (cleanName.contains('프로')) return 'assets/images/char_pro.png';
    if (cleanName.contains('마스터')) return 'assets/images/char_master.png';
    
    // 아무것도 안 입었거나 초보일 때는 기본 옷!
    return 'assets/images/char_novice.png'; 
  }


// 🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩
// 🚇 새로운 로직 대기실! (추가될 힘/체력/제압력 공식)


// -----------------------------------------------------------------
// 🎣 KREFT 다이내믹 파이팅 시스템 (디자인 리뉴얼 시안)
// -----------------------------------------------------------------
class FishingFightingOverlay extends StatefulWidget {
  final Map<String, dynamic> fish;
  final double playerTotalStats;
  final Function(bool, double) onFinished;

  const FishingFightingOverlay({
    super.key,
    required this.fish,
    required this.playerTotalStats,
    required this.onFinished,
  });

  @override
  State<FishingFightingOverlay> createState() => _FishingFightingOverlayState();
}

// -----------------------------------------------------------------
// 🎣 KREFT 하이퍼 다이내믹 파이팅 엔진 (리듬 펌핑 & 물고기 AI 발악)
// -----------------------------------------------------------------
class _FishingFightingOverlayState extends State<FishingFightingOverlay> with TickerProviderStateMixin {
  double gaugeValue = 0.5;
  int remainingTime = 30;
  bool isPressing = false;
  Timer? gameTimer;
  
  DateTime? lastReleaseTime;
  
  // 🌟 [사장님 기획] 리듬 기어 & 패널티 시스템
  int playerGear = 1; // 1단, 2단, 3단
  bool isMashingPenalty = false; // 다다다 연타 패널티
  
  // 🐟 [물고기 AI] 발악 시스템
  int fishGear = 0; // 0: 평온, 1: 1단 저항, 2: 2단 발악
  int fishSkillDuration = 0; // 물고기 발악 남은 시간

  double fishBasePower = 0.0;
  double fishCurrentMove = 0.0;
  Random random = Random();

  late AnimationController _rodController;

  @override
  void initState() {
    super.initState();
    _rodController = AnimationController(vsync: this, duration: const Duration(milliseconds: 250))..repeat(reverse: true);
    _prepareFishStats();
    _startGame();
  }

  void _prepareFishStats() {
    double size = double.tryParse(widget.fish['size'].toString()) ?? 20.0;
    
    // 👑 [패치 1] 6대장이면 숨겨진 근력(파워) 1.5배 뻥튀기!
    List<String> bossFishes = ['붕어', '잉어', '가물치', '참돔', '감성돔', '문어'];
    double bossMult = bossFishes.contains(widget.fish['name']) ? 1.5 : 1.0;

    double fishDifficultyMultiplier = 0.85; 
    fishBasePower = (size * size) * fishDifficultyMultiplier * bossMult; 
    
    // 내 제압력과 물고기의 힘 차이
    double powerDiff = fishBasePower - widget.playerTotalStats;
    
    // 🚨 [패치 2] 밸런스 붕괴 방지! (압도적인 힘의 차이 구현)
    if (powerDiff > 500) {
      // 물고기가 나보다 파워가 500 이상 강하면, 기존의 캡(제한)을 무시하고 미친 속도로 도망갑니다!
      fishCurrentMove = powerDiff / 30000; 
    } else if (powerDiff > 0) {
      fishCurrentMove = powerDiff / 100000;
    } else {
      // 내 제압력이 더 높으면 물고기가 힘을 못 씀
      fishCurrentMove = 0.002; 
    }
  }

  void _startGame() {
    gameTimer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
      if (!mounted) return;

      setState(() {
        if (timer.tick % 20 == 0) {
          remainingTime--;
          if (remainingTime <= 0) _endGame(gaugeValue <= 0.5);
        }

        if (fishSkillDuration > 0) {
          fishSkillDuration--;
          if (fishSkillDuration == 0) fishGear = 0; 
        } else {
          if (random.nextInt(100) < 4) {
            fishGear = random.nextBool() ? 2 : 1; 
            fishSkillDuration = 30 + random.nextInt(30); 
          }
        }

        double pMult = isMashingPenalty ? 0.5 : (playerGear == 3 ? 1.8 : playerGear == 2 ? 1.6 : 1.4);
        double fMult = fishGear == 2 ? 1.8 : fishGear == 1 ? 1.4 : 1.0;
        double wildFactor = (random.nextDouble() - 0.3) * 0.005; 
        
        if (isPressing) {
          // 🏋️‍♂️ [패치 3] 플레이어의 제압력이 높을수록 릴링 파워가 세짐! (고정값 삭제)
          double statBonus = (widget.playerTotalStats / 150000);
          double myPull = ((0.003 + statBonus) * pMult);
          
          double resistance = (fishCurrentMove * fMult);
          
          // 내 제압력이 후달리는데 물고기가 저항하면 아무리 눌러도 게이지가 확 밀림!
          gaugeValue -= (myPull - (resistance * 0.8)); 
        } else {
          // 텐션 풀었을 때 물고기가 도망가는 속도
          gaugeValue += (0.002 + ((fishCurrentMove * fMult) * 0.8) + wildFactor);
        }

        if (gaugeValue <= 0.0) {
          gaugeValue = 0.0;
          _endGame(true); // 낚시 성공
        } else if (gaugeValue >= 1.0) {
          gaugeValue = 1.0;
          _endGame(false); // 줄 터짐 (패배)
        }
      });
    });
  }

  void _endGame(bool isSuccess) {
    gameTimer?.cancel();
    widget.onFinished(isSuccess, double.tryParse(widget.fish['size'].toString()) ?? 0.0);
  }

  @override
  void dispose() {
    gameTimer?.cancel();
    _rodController.dispose(); 
    super.dispose();
  }

  // ⚙️ [핵심] 리듬 펌핑 변속기 (잃어버린 함수 복구!)
  void _updatePlayerGear(int msDiff) {
    if (msDiff < 120) {
      // 🚫 너무 빨리 누름 (무지성 광클) -> 릴 엉킴 패널티!
      isMashingPenalty = true;
      playerGear = 1; 
    } else if (msDiff < 1200) {
      // ✅ 정확한 리듬 펌핑! (기어 업)
      isMashingPenalty = false;
      if (playerGear < 3) playerGear++;
    } else {
      // 🐢 너무 늦게 누름 -> 1단으로 초기화
      isMashingPenalty = false;
      playerGear = 1;
    }
    
    // 기어에 맞춰 낚싯대 진동 속도 변경
    int speed = isMashingPenalty ? 400 : (playerGear == 3 ? 60 : playerGear == 2 ? 120 : 250);
    _rodController.duration = Duration(milliseconds: speed);
    if (_rodController.isAnimating) _rodController.repeat(reverse: true);
  }

  // 👇 펌핑 시작 (누를 때)
  void _onPullDown() {
    // 💦 [패치] 잃어버린 물보라 사운드와 짜릿한 진동 복구!
    bool isSea = widget.fish['img'].toString().contains('sea');
    audioManager.playSfx(isSea ? "sfx_sea_landing.mp3" : "sfx_fresh_landing.mp3");
    HapticFeedback.mediumImpact();

    setState(() {
      isPressing = true;
      if (lastReleaseTime != null) {
        int diff = DateTime.now().difference(lastReleaseTime!).inMilliseconds;
        _updatePlayerGear(diff);
      } else {
        playerGear = 1;
        isMashingPenalty = false;
      }
    });
  }
  void _onPullUp() {
    setState(() {
      isPressing = false;
      lastReleaseTime = DateTime.now();
    });
  }

  @override
  Widget build(BuildContext context) {
    bool isSea = widget.fish['img'].toString().contains('sea');
    String fightRodImage = isSea ? 'assets/images/hand_rod_sea.png' : 'assets/images/hand_rod_fw.png';

    return Container(
      color: Colors.transparent, 
      child: Stack(
        children: [
          // 🎣 흔들리는 낚싯대 애니메이션
          Positioned(
            right: -30.0, bottom: -50.0,
            child: AnimatedBuilder(
                animation: _rodController,
                builder: (context, child) {
                  double fightAngle = 0.0 + (random.nextDouble() - 0.5) * (0.05 + (gaugeValue * 0.1));
                  return Transform.rotate(
                    angle: fightAngle, 
                    origin: const Offset(150.0, 150.0), 
                    child: Image.asset(fightRodImage, height: 450.0, fit: BoxFit.contain, errorBuilder: (c,e,s) => const SizedBox.shrink())
                  );
                }
            )
          ),

          // 🚨 [추가] 물고기 발악 경고등!
          if (fishGear > 0)
            Positioned(
              top: 350, left: 0, right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  decoration: BoxDecoration(
                    color: fishGear == 2 ? Colors.redAccent.withOpacity(0.8) : Colors.orange.withOpacity(0.8),
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(color: Colors.white, width: 2)
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 24),
                      const SizedBox(width: 8),
                      Text(
                        fishGear == 2 ? '🚨 물고기의 발악!!' : '🐟 물고기의 저항!',
                        style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold, fontStyle: FontStyle.italic),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // 📺 상단 타이머 및 게이지 바
          Positioned(
            top: 450, left: 0, right: 0,
            child: Column(
              children: [
                Text('제한시간: 00:${remainingTime.toString().padLeft(2, '0')}', 
                    style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold, shadows: [Shadow(color: Colors.black45, blurRadius: 5)])),
                const SizedBox(height: 20),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 50),
                  child: Stack(
                alignment: Alignment.center,
                clipBehavior: Clip.none, // 슬라이더 그림자가 짤리지 않게 해줍니다.
                children: [
                  // 1. 기존 게이지 배경 (이건 사장님 원래 코드 그대로!)
                  Container(
                    height: 15,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      gradient: const LinearGradient(colors: [Colors.blueAccent, Colors.white, Colors.redAccent]),
                      boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
                    ),
                  ),
                  
                  // 🎯 2. [추가] 정중앙 목표 기준선
                  Align(
                    alignment: Alignment.center,
                    child: Container(
                      width: 3, 
                      height: 25, // 게이지 두께(15)보다 위아래로 살짝 튀어나오게!
                      color: Colors.white.withOpacity(0.6), // 반투명 하얀색
                    ),
                  ),

                  // 💊 3. [수정] 얇은 짝대기 -> KREFT 골드 알약 슬라이더로 진화!
                  AnimatedAlign(
                    duration: const Duration(milliseconds: 50),
                    alignment: Alignment(gaugeValue * 2 - 1, 0),
                    child: Container(
                      width: 42, // 가로로 살짝 통통하게
                      height: 23, // 게이지보다 크게 해서 입체감 뿜뿜
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(15), // 완벽한 타원형
                        border: Border.all(color: const Color(0xFFD4AF37), width: 2.5), // 황금 테두리
                        boxShadow: const [
                          BoxShadow(color: Colors.black54, blurRadius: 4, offset: Offset(0, 2))
                        ],
                      ),
                    ),
                  ),
                ],
              ), // Stack
                ),
              ],
            ),
          ),

          // ⚙️ [추가] 내 기어 상태 및 릴 엉킴 경고 표시!
          Positioned(
            bottom: 200, right: 30,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (isMashingPenalty)
                  const Text('⚠️ 줄 엉킴! (연타 금지)', style: TextStyle(color: Colors.redAccent, fontSize: 22, fontWeight: FontWeight.w900, shadows: [Shadow(color: Colors.black, blurRadius: 4)])),
                if (!isMashingPenalty)
                  Text(
                    // 🔥 바다(isSea)면 '릴링', 민물이면 '제압'으로 찰떡같이 변신!
                    playerGear == 3 
                        ? (isSea ? '🔥 3단 폭풍 릴링!!' : '🔥 3단 최고치 제압!!') 
                        : (isSea ? '$playerGear단 릴링!' : '$playerGear단 제압!'), 
                    style: TextStyle(
                      color: playerGear == 3 ? Colors.redAccent : (playerGear == 2 ? Colors.orangeAccent : Colors.yellow), 
                      fontSize: playerGear == 3 ? 30 : 26, 
                      fontWeight: FontWeight.w900, 
                      fontStyle: FontStyle.italic, 
                      shadows: const [Shadow(color: Colors.black, blurRadius: 4)]
                    )
                  ),
              ],
            )
          ),

          // 🔘 당기기 버튼
          Positioned(
            bottom: 50, right: 30,
            child: GestureDetector(
              onTapDown: (_) => _onPullDown(),
              onTapUp: (_) => _onPullUp(),
              onTapCancel: () => _onPullUp(),
              child: Container(
                width: 100, height: 100,
                decoration: BoxDecoration(
                  color: isMashingPenalty ? Colors.grey : const Color(0xFFD4AF37),
                  shape: BoxShape.circle, 
                  boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 10, offset: Offset(0, 4))],
                  border: Border.all(color: Colors.white, width: 3)
                ),
                alignment: Alignment.center,
                child: const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                     Icon(Icons.sports_esports, color: Colors.white, size: 30),
                     Text('당기기', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

final Map<String, List<Map<String, dynamic>>> locations = {
  '저수지': [
    {'name': '예산 예당지', 'target': '낚시 학교, 붕어 마릿수, 글루텐 추천', 'stars': 1, 'image': 'assets/fields/bg_yedang.jpg'},
    {'name': '안성 고삼지', 'target': '월척급 붕어, 지렁이 추천', 'stars': 2, 'image': 'assets/fields/bg_gosam.jpg'},
    {'name': '진천 백곡지', 'target': '허릿급 붕어, 레벨업 낚시터, 글루텐 추천', 'stars': 3, 'image': 'assets/fields/bg_baekgok.jpg'},
    {'name': '춘천 파로호', 'target': '4짜급 붕어, 손맛 일품, 옥수수 추천', 'stars': 4, 'image': 'assets/fields/bg_paro.jpg'},
    {'name': '충주 충주호', 'target': '대물 붕어, 랭킹 도전, 옥수수 추천', 'stars': 5, 'image': 'assets/fields/bg_chungju.jpg'}
  ],
  '수로': [
    {'name': '예산 신양수로', 'target': '붕어 마릿수, 지렁이 추천', 'stars': 1, 'image': 'assets/fields/bg_sinyang.jpg'},
    {'name': '청양 지천', 'target': '월척급 붕어, 글루텐 추천', 'stars': 2, 'image': 'assets/fields/bg_jicheon.jpg'},
    {'name': '인천 청라수로', 'target': '씨알 좋은 붕어, 지렁이 추천', 'stars': 3, 'image': 'assets/fields/bg_chungla.jpg'},
    {'name': '해남 금자천', 'target': '겨울 붕어 명당, 글루텐 추천', 'stars': 4, 'image': 'assets/fields/bg_gumja.jpg'},
    {'name': '충주 달천', 'target': '대물 붕어, 랭킹 도전, 옥수수 추천', 'stars': 5, 'image': 'assets/fields/bg_dalchun.jpg'}
  ],
  '갯바위': [
    {'name': '통영 척포 갯바위', 'target': '감성돔, 참돔, 루어 추천', 'stars': 1, 'image': 'assets/fields/bg_chukpo.jpg'},
    {'name': '신안 가거도', 'target': '참돔, 감성돔, 갯지렁이 추천', 'stars': 2, 'image': 'assets/fields/bg_gageo.jpg'},
    {'name': '완도 청산도', 'target': '두족류, 갈치, 에기 추천', 'stars': 3, 'image': 'assets/fields/bg_cheongsan.jpg'},
    {'name': '여수 거문도', 'target': '씨알 좋은 여러 어종, 크릴 추천', 'stars': 4, 'image': 'assets/fields/bg_geumo.jpg'},
    {'name': '제주 섶섬', 'target': '미터급 참치, 대형 문어, 크릴, 루어 추천 ', 'stars': 5, 'image': 'assets/fields/bg_seop.jpg'}
  ],
  '선상': [
    {'name': '거제 선상', 'target': '고등어,참돔, 갯지렁이 추천', 'stars': 1, 'image': 'assets/fields/bg_geo_ship.jpg'},
    {'name': '오천항 선상', 'target': '쭈꾸미, 갑오징어, 에기 추천', 'stars': 2, 'image': 'assets/fields/bg_ocheon_ship.jpg'},
    {'name': '대천 선상', 'target': '대물 우럭, 갯지렁이 추천', 'stars': 3, 'image': 'assets/fields/bg_daecheon_ship.jpg'},
    {'name': '통영 선상', 'target': '대물 갈치, 크릴 추천', 'stars': 4, 'image': 'assets/fields/bg_tong_ship.jpg'},
    {'name': '완도 선상', 'target': '대형 참치, 랭킹 도전, 루어, 크릴 추천', 'stars': 5, 'image': 'assets/fields/bg_wando_ship.jpg'}
  ],
};

// 🚗 [제 3의 문] KREFT 하이패스 톨게이트 (자동 분기점)
class AutoLoginScreen extends StatefulWidget {
  final String email;
  const AutoLoginScreen({super.key, required this.email});

  @override
  State<AutoLoginScreen> createState() => _AutoLoginScreenState();
}

class _AutoLoginScreenState extends State<AutoLoginScreen> {
  @override
  void initState() {
    super.initState();
    _silentLogin(); 
  }

  Future<void> _silentLogin() async {
    String secretPassword = "KreftMasterPassword123!"; 

    try {
      UserCredential uc = await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: widget.email, 
          password: secretPassword
      );
      
      DocumentSnapshot doc = await FirebaseFirestore.instance.collection('users').doc(uc.user!.uid).get();
      
      if (mounted) {
        if (doc.exists && (doc.data() as Map<String, dynamic>).containsKey('nickname')) {
          // 🟢 [제 3의 문] 기존 유저: 다이렉트로 안 가고 '캠피싱 낚시대회 (터치 화면)'으로 먼저 보냅니다! (수정 완료)
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const TouchToStartScreen()));
        } else {
          // 🟡 닉네임이 없는 경우 (신규 유저): 닉네임 설정 화면으로!
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => NicknameSetupScreen(uid: uc.user!.uid, email: widget.email)));
        }
      }
    } on FirebaseAuthException catch (e) {
      if (e.code == 'user-not-found' || e.code == 'invalid-credential') {
        try {
          UserCredential uc = await FirebaseAuth.instance.createUserWithEmailAndPassword(
              email: widget.email, 
              password: secretPassword
          );
          if (mounted) {
            Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => NicknameSetupScreen(uid: uc.user!.uid, email: widget.email)));
          }
        } catch(e) {
          print("가입 에러: $e");
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Color(0xFFD4AF37)), 
            SizedBox(height: 20),
            Text("🎣 KREFT 회원 정보 확인 중...", style: TextStyle(color: Colors.white, fontSize: 16)),
          ],
        ),
      ),
    );
  }
}

// 📛 [제 2의 문] 신규 유저 닉네임 설정 화면
class NicknameSetupScreen extends StatefulWidget {
  final String uid;
  final String email;
  const NicknameSetupScreen({super.key, required this.uid, required this.email});

  @override
  State<NicknameSetupScreen> createState() => _NicknameSetupScreenState();
}

class _NicknameSetupScreenState extends State<NicknameSetupScreen> {
  final TextEditingController _nickController = TextEditingController();
  bool isChecked = false; // 중복확인 통과 여부
  String checkMessage = "";

  // 닉네임 중복 검사 로직
  Future<void> _checkDuplicate() async {
    String nick = _nickController.text.trim();
    if (nick.isEmpty || nick.length < 2) {
      setState(() => checkMessage = "닉네임은 2글자 이상 입력해주세요.");
      return;
    }

    // 파이어베이스에서 똑같은 닉네임이 있는지 싹 다 뒤져보기
    var snapshot = await FirebaseFirestore.instance.collection('users').where('nickname', isEqualTo: nick).get();
    
    setState(() {
      if (snapshot.docs.isNotEmpty) {
        checkMessage = "❌ 이미 누군가 사용 중인 닉네임입니다.";
        isChecked = false;
      } else {
        checkMessage = "✅ 사용 가능한 닉네임입니다!";
        isChecked = true;
      }
    });
  }

  // 닉네임 확정 및 기초 장비 지급 후 출발!
  Future<void> _saveAndStart() async {
    if (!isChecked) return;
    
    // 🎁 사장님의 진짜 12종 KREFT 스타터 팩!
    List<Map<String, dynamic>> realStarterPack = [
      {'name': '초보 조사', 'category': 'SKIN', 'type': 'SKIN', 'stats': {'P': 10, 'C': 10, 'S': 10}, 'icon': '../images/skin_novice.jpg', 'desc': 'KREFT 조사의 기본 복장'},
      {'name': 'CF-20T', 'category': 'FW', 'type': 'ROD', 'stats': {'P': 0, 'C': 0, 'S': 0}, 'icon': 'rod_fw_cf20.png', 'desc': '초보 조사용 기본 민물대'},
      {'name': '일반찌', 'category': 'FW', 'type': 'FLOAT', 'stats': {'S': 0}, 'icon': 'float_fw_normal.png', 'desc': '가장 기본적인 민물 찌'},
      {'name': '글루텐', 'category': 'FW', 'type': 'BAIT', 'quantity': 50, 'icon': 'bait_fw_gluten.png', 'desc': '붕어 집어에 탁월한 미끼 (20)'},
      {'name': '지렁이', 'category': 'FW', 'type': 'BAIT', 'quantity': 50, 'icon': 'bait_fw_worm.png', 'desc': '민물 만능 미끼 (10)'},
      {'name': '옥수수', 'category': 'FW', 'type': 'BAIT', 'quantity': 50, 'icon': 'bait_fw_corn.png', 'desc': '대물 붕어용 미끼 (30)'},
      {'name': 'CF250', 'category': 'SEA', 'type': 'ROD', 'stats': {'P': 0, 'C': 0, 'S': 0}, 'icon': 'rod_sea_cf250.png', 'desc': '바다 낚시 입문용 기본대'},
      {'name': 'CF2000', 'category': 'SEA', 'type': 'REEL', 'stats': {'P': 0}, 'icon': 'reel_sea_cf2000.png', 'desc': '기본 제공되는 바다 릴'},
      {'name': '갯지렁이', 'category': 'SEA', 'type': 'BAIT', 'quantity': 50, 'icon': 'bait_sea_worm.png', 'desc': '바다 낚시 기본 미끼 (10)'},
      {'name': '크릴', 'category': 'SEA', 'type': 'BAIT', 'quantity': 50, 'icon': 'bait_sea_krill.png', 'desc': '전천후 바다 미끼 (20)'},
      {'name': '루어', 'category': 'SEA', 'type': 'BAIT', 'quantity': 50, 'icon': 'bait_sea_lure.png', 'desc': '육식성 어종 전용 (30)'},
      {'name': '에기', 'category': 'SEA', 'type': 'BAIT', 'quantity': 50, 'icon': 'bait_sea_egi.png', 'desc': '두족류 전용 미끼 (30)'},
    ];

    // DB에 유저 기초 데이터(초급자 세팅) 생성!
    await FirebaseFirestore.instance.collection('users').doc(widget.uid).set({
      'nickname': _nickController.text.trim(),
      'email': widget.email,
      'level': 1,
      'gold': 1000, 
      'createdAt': FieldValue.serverTimestamp(),
      'inventory': realStarterPack, // 👈 12종 세트가 유저 가방으로 쏙 들어갑니다!
    });

    if (mounted) {
      // 세팅 끝났으니 로비로 패스!
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const ProfileCheckScreen()));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Container(
          width: 400,
          padding: const EdgeInsets.all(40),
          decoration: BoxDecoration(color: const Color(0xFF1A1A1A), border: Border.all(color: const Color(0xFFD4AF37), width: 2), borderRadius: BorderRadius.circular(15)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text("환영합니다, 예비 조사님!", style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              const Text("낚시터에서 사용할 멋진 닉네임을 정해주세요.", style: TextStyle(color: Colors.grey, fontSize: 14)),
              const SizedBox(height: 30),
              
              // 닉네임 입력칸 & 중복확인 버튼
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _nickController,
                      style: const TextStyle(color: Colors.white),
                      onChanged: (_) => setState(() { isChecked = false; checkMessage = ""; }), // 글자 바뀌면 다시 확인하게 만듦
                      decoration: const InputDecoration(
                        hintText: "예: 도시어부, 대물사냥꾼",
                        hintStyle: TextStyle(color: Colors.white38),
                        enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.grey)),
                        focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFFD4AF37))),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFD4AF37), foregroundColor: Colors.black),
                    onPressed: _checkDuplicate,
                    child: const Text("중복확인", style: TextStyle(fontWeight: FontWeight.bold)),
                  )
                ],
              ),
              const SizedBox(height: 15),
              Text(checkMessage, style: TextStyle(color: isChecked ? Colors.greenAccent : Colors.redAccent, fontSize: 13)),
              const SizedBox(height: 30),
              
              // 시작하기 버튼 (중복확인 통과해야만 눌림!)
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isChecked ? const Color(0xFFD4AF37) : Colors.grey.shade800,
                    foregroundColor: isChecked ? Colors.black : Colors.grey,
                  ),
                  onPressed: isChecked ? _saveAndStart : null,
                  child: const Text("KREFT 낚시 시작하기", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              )
            ],
          ),
        ),
      ),
    );
  }
}

// 🚪 [제 1의 문] 비회원/로그아웃 유저 안내 화면 (복구됨!)
class GuestWarningScreen extends StatelessWidget {
  const GuestWarningScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Container(
          padding: const EdgeInsets.all(40),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A1A), 
            border: Border.all(color: const Color(0xFFD4AF37), width: 2), 
            borderRadius: BorderRadius.circular(15),
          ),
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_outline, color: Color(0xFFD4AF37), size: 60), 
              SizedBox(height: 20),
              Text(
                "회원 전용 구역",
                style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 20),
              Text(
                "캠피싱 낚시대회에 참석하기 위해서는\n홈페이지 회원가입 및 로그인이 필요합니다.",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey, fontSize: 16, height: 1.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// 👆 [제 3.5의 문] 크롬 오디오 에러 방어용 '터치 투 스타트' 화면
class TouchToStartScreen extends StatelessWidget {
  const TouchToStartScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      // 화면 어디든 터치(클릭)하는 순간! 크롬의 오디오 봉인이 해제되며 진짜 로비로 입장!
      onTap: () {
        Navigator.pushReplacement(
            context, 
            MaterialPageRoute(builder: (_) => const ProfileCheckScreen())
        );
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.shield, color: Color(0xFFD4AF37), size: 80), // KREFT 느낌의 방패 아이콘
              const SizedBox(height: 30),
              const Text(
                "캠피싱 낚시대회 준비 완료",
                style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 40),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
                decoration: BoxDecoration(
                  border: Border.all(color: const Color(0xFFD4AF37), width: 1.5),
                  borderRadius: BorderRadius.circular(30),
                  color: const Color(0xFFD4AF37).withOpacity(0.1),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.touch_app, color: Color(0xFFD4AF37)),
                    SizedBox(width: 10),
                    Text(
                      "화면을 터치하여 입장하세요",
                      style: TextStyle(color: Color(0xFFD4AF37), fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
// 🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩
// 여기에 사장님의 참치(100만P) 공식과 레벨 로직을 이식할 예정입니다!