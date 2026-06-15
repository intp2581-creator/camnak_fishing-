// ignore_for_file: deprecated_member_use, unused_element, unused_import, unnecessary_import, use_build_context_synchronously, avoid_print
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html; 
import 'package:flutter/services.dart'; 
import 'game_config.dart'; 
import 'ui_lobby.dart';    
import 'ui_tutorial_npc.dart'; // 👧 윤슬 가이드 부품 장착!
import 'ui_plaza.dart';    // 🏛️ 광장 (메인 허브)

// 🏢 [별관] 시스템 및 로비 구역 (로그인, 프로필, 맵 선택)
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

  Future<void> submitAuth() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    final nickname = _nicknameController.text.trim();

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
          'inventory': getInitialStarterPack(), 'playTimeRemaining': initialPlayTime,
          'lastPlayDate': DateTime.now().toIso8601String().substring(0, 10), 'createdAt': FieldValue.serverTimestamp(),
        });

        if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text("🎉 캐릭터 생성 완료!\n스타터 팩이 인벤토리에 지급되었습니다.", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16), textAlign: TextAlign.center),
            backgroundColor: const Color(0xFFD4AF37), 
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
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              'assets/fields/bg_yedang.jpg', 
              fit: BoxFit.cover,
              errorBuilder: (c, e, s) => Container(color: Colors.black87), 
            ),
          ),
          Positioned.fill(child: Container(color: Colors.black.withOpacity(0.4))), 

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
                    Text(isLoginMode ? 'MEMBER LOGIN' : 'NEW CHARACTER', style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: 2)),
                    const SizedBox(height: 30),
                    _buildInputField(_emailController, 'ID / E-mail', Icons.person),
                    const SizedBox(height: 15),
                    _buildInputField(_passwordController, 'Password', Icons.lock, isObscure: true),
                    if (!isLoginMode) ...[
                      const SizedBox(height: 15),
                      _buildInputField(_nicknameController, '조사님 닉네임 (2~8자)', Icons.badge),
                    ],
                    const SizedBox(height: 30),
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
          int dbLevel = userData['level'] ?? 1; 
          return PlazaScreen.defaultEntry(nickname: dbNickname, level: dbLevel);
        }
        return const LoginPage();
      },
    );
  }
}

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
      await FirebaseAuth.instance.signOut();
      UserCredential uc = await FirebaseAuth.instance.signInWithEmailAndPassword(email: widget.email, password: secretPassword);
      DocumentSnapshot doc = await FirebaseFirestore.instance.collection('users').doc(uc.user!.uid).get();

      if (mounted) {
        // ✨ 다시 진짜 유저 검사 로직으로 완벽 복구!
        if (doc.exists) { 
          // [기존 유저] 로비로 직행!
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const TouchToStartScreen(nextScreen: ProfileCheckScreen())));
        } else {
          // 👉 [신규 유저] 윤슬 가이드(닉네임 설정)로!
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => TouchToStartScreen(nextScreen: NicknameSetupScreen(uid: uc.user!.uid, email: widget.email))));
        }
      }
    } on FirebaseAuthException catch (e) {
      if (e.code == 'user-not-found' || e.code == 'invalid-credential') {
        try {
          await FirebaseAuth.instance.createUserWithEmailAndPassword(email: widget.email, password: secretPassword);
          if (mounted) {
            // 👉 [핵심] 쌩 신규: 터치 화면 거쳐서 -> 윤슬 가이드로!
            Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => TouchToStartScreen(nextScreen: NicknameSetupScreen(uid: FirebaseAuth.instance.currentUser!.uid, email: widget.email))));
          }
        } catch(e) {
          debugPrint("자동 회원가입 실패: $e");
        }
      } else {
        debugPrint("로그인 에러: ${e.code}");
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
            Text("🎣 캠피싱 회원 정보 확인 중...", style: TextStyle(color: Colors.white, fontSize: 16)),
          ],
        ),
      ),
    );
  }
}

// 📛 [제 2의 문] 신규 유저 닉네임 설정 화면 (세로 모드 철벽 방어!)
class NicknameSetupScreen extends StatefulWidget {
  final String uid;
  final String email;
  const NicknameSetupScreen({super.key, required this.uid, required this.email});

  @override
  State<NicknameSetupScreen> createState() => _NicknameSetupScreenState();
}

class _NicknameSetupScreenState extends State<NicknameSetupScreen> {
  final TextEditingController _nickController = TextEditingController();
  bool isChecked = false; 
  String checkMessage = "";
  int _tutorialStep = -1; // 윤슬 튜토리얼 전부 제거 (광장 개편)

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  @override
  void dispose() {
    _nickController.dispose();
    super.dispose();
  }

  Future<void> _checkDuplicate() async {
    String nick = _nickController.text.trim();
    if (nick.isEmpty || nick.length < 2) {
      setState(() => checkMessage = "닉네임은 2글자 이상 입력해주세요.");
      return;
    }
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

  void _showSuccessTutorial() {
    setState(() { _tutorialStep = 3; });
  }

  Future<void> _realSaveAndStart() async {
    if (!isChecked) return;
    
    await FirebaseFirestore.instance.collection('users').doc(widget.uid).set({
      'nickname': _nickController.text.trim(),
      'email': widget.email,
      'level': 1,
      'gold': 0, 
      'createdAt': FieldValue.serverTimestamp(),
      'inventory': getInitialStarterPack(), 
    });

    if (mounted) {
      // 🚀 [해결 완료] "나 처음 왔어!" (isFirstTime: true) 쪽지를 쥐어주고 바로 로비로 꽂아버리기!
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => PlazaScreen.defaultEntry(
        nickname: _nickController.text.trim(),
        level: 1,
        isFirstTime: false, // 윤슬 튜토리얼 제거 → 낚시 화면 튜토리얼도 안 뜸
      )));
    }
  }

  @override
  Widget build(BuildContext context) {
    // 📱 화면 너비가 높이보다 좁으면 무조건 세로 모드로 간주! (가장 확실한 방법)
    bool isPortrait = MediaQuery.of(context).size.width < MediaQuery.of(context).size.height;

    // 🚨 세로 모드 경고창
    if (isPortrait) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.screen_rotation, color: Color(0xFFD4AF37), size: 100),
              const SizedBox(height: 30),
              const Text("원활한 낚시를 위해\n휴대폰을 가로로 눕혀주세요!", textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold, height: 1.5)),
              const SizedBox(height: 20),
              const Text("가로로 돌리면 아리따운 윤슬 가이드가 나타납니다 😊", style: TextStyle(color: Colors.grey, fontSize: 16)),
            ],
          ),
        ),
      );
    }

    // 🌟 가로 모드일 때 나타나는 진짜 화면
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Center(
            child: Container(
              width: 450,
              padding: const EdgeInsets.all(40),
              decoration: BoxDecoration(color: const Color(0xFF1A1A1A), border: Border.all(color: const Color(0xFFD4AF37), width: 2), borderRadius: BorderRadius.circular(15)),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text("환영합니다, 예비 조사님!", style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  const Text("낚시터에서 사용할 멋진 닉네임을 정해주세요.", style: TextStyle(color: Colors.grey, fontSize: 14)),
                  const SizedBox(height: 30),
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          height: 70,
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          decoration: BoxDecoration(color: Colors.white.withOpacity(0.1), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFD4AF37), width: 2)),
                          child: TextField(
                            controller: _nickController,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold),
                            onChanged: (_) => setState(() { isChecked = false; checkMessage = ""; }), 
                            decoration: const InputDecoration(hintText: "터치해서 입력", hintStyle: TextStyle(color: Colors.white38, fontSize: 16), border: InputBorder.none, contentPadding: EdgeInsets.symmetric(vertical: 18)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 15),
                      SizedBox(
                        height: 70,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFD4AF37), foregroundColor: Colors.black, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                          onPressed: _checkDuplicate,
                          child: const Text("중복확인", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        ),
                      )
                    ],
                  ),
                  const SizedBox(height: 15),
                  Text(checkMessage, style: TextStyle(color: isChecked ? Colors.greenAccent : Colors.redAccent, fontSize: 15, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 30),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: isChecked ? const Color(0xFFD4AF37) : Colors.grey.shade800, foregroundColor: isChecked ? Colors.black : Colors.grey, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                      onPressed: isChecked ? _realSaveAndStart : null, // 윤슬 성공 안내 건너뛰고 바로 입장
                      child: const Text("캠피싱 낚시대회 시작하기", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    ),
                  )
                ],
              ),
            ),
          ),
          
          if (_tutorialStep == 0)
            NpcTutorialOverlay(
              text: "안녕하세요!\n'캠피싱 낚시대회'에 오신 걸 환영합니다!\n저는 캠피싱 가이드 윤슬이라고 해요. 😊",
              imagePath: "assets/images/npc_girl_intro.png",
              onTap: () => setState(() => _tutorialStep = 1), 
            ),
          if (_tutorialStep == 1)
            NpcTutorialOverlay(
              text: "낚시 전에 조사님을 뭐라고 부르면 좋을지\n타블렛에 닉네임을 적어주시겠어요? ",
              imagePath: "assets/images/npc_girl_point.png",
              onTap: () => setState(() => _tutorialStep = 2), 
            ),
          if (_tutorialStep == 3)
            NpcTutorialOverlay(
              text: "와우! 정말 멋진 이름이네요!\n이제 월척 낚으러 가볼까요? 출발!! 👍",
              imagePath: "assets/images/npc_girl_success.png",
              onTap: _realSaveAndStart, 
            ),
        ],
      ),
    );
  }
}

// 🚪 [제 1의 문] 비회원 안내 화면 (방패 로고 & 가로 모드 적용!)
class GuestWarningScreen extends StatefulWidget { // 👈 회전 기능을 위해 StatefulWidget으로 승격!
  const GuestWarningScreen({super.key});

  @override
  State<GuestWarningScreen> createState() => _GuestWarningScreenState();
}

class _GuestWarningScreenState extends State<GuestWarningScreen> {
  @override
  void initState() {
    super.initState();
    // 🚀 이 화면에 들어오자마자 폰을 가로로 눕히라고 명령!
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ==========================================================
              // 🛡️ [수술 완료] 자물쇠 대신 큼직한 방패 로고 등판!!
              // ==========================================================
              Image.asset(
                'assets/images/symbol.png',
                width: 280, // 👈 사장님이 원하시는 웅장한 크기!
                fit: BoxFit.contain,
                errorBuilder: (c, e, s) => const Icon(Icons.shield, color: Color(0xFFD4AF37), size: 100),
              ),
              const SizedBox(height: 30),
              const Text(
                "회원 전용 구역",
                style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 15),
              const Text(
                "캠피싱 낚시대회에 참여하시려면\n홈페이지 로그인이 필요합니다.",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey, fontSize: 16, height: 1.5),
              ),
              const SizedBox(height: 30), 
              ElevatedButton(
                onPressed: () async {
                  final Uri url = Uri.parse('https://camnak.com/login');
                  if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
                    throw Exception('Could not launch $url');
                  }
                  if (context.mounted) Navigator.of(context).pop(); 
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFD4AF37), 
                  padding: const EdgeInsets.symmetric(horizontal: 50, vertical: 18),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: const Text(
                  "로그인 하러 가기",
                  style: TextStyle(color: Colors.black, fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
             ] 
          ),
        ),
      ),
    );
  }
}

// 👆 [제 3.5의 문] 터치 투 스타트 화면 (화면 웅장하게 벌크업 완료!)
class TouchToStartScreen extends StatelessWidget {
  final Widget nextScreen; // 👈 목적지 변수
  const TouchToStartScreen({super.key, required this.nextScreen});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        try { if (html.document.fullscreenElement == null) html.document.documentElement?.requestFullscreen(); } catch (e) { debugPrint("전체화면 에러: $e"); }
        SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
        // 🚀 유저가 터치하면 지정된 목적지로 출발!
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => nextScreen));
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // 📈 [확대 1] KREFT 방패 로고 대폭 키움! (180 -> 280)
              Image.asset('assets/images/symbol.png', width: 280, errorBuilder: (c, e, s) => const Icon(Icons.shield, color: Color(0xFFD4AF37), size: 120)),
              const SizedBox(height: 50), // 여백도 시원하게!
              
              // 📈 [확대 2] 준비 완료 텍스트 떡상! (24 -> 32)
              const Text("캠피싱 낚시대회 준비 완료", style: TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold)),
              const SizedBox(height: 50),

              // 📈 [확대 3] 터치 버튼(박스) 시원하게 확대!
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 25), // 내부 여백 팍팍!
                decoration: BoxDecoration(
                  border: Border.all(color: const Color(0xFFD4AF37), width: 3.0), // 테두리도 더 굵고 진하게
                  borderRadius: BorderRadius.circular(40), 
                  color: const Color(0xFFD4AF37).withOpacity(0.15)
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.touch_app, color: Color(0xFFD4AF37), size: 36), // 아이콘도 크게!
                    SizedBox(width: 15),
                    Text("화면을 터치하여 입장하세요", style: TextStyle(color: Color(0xFFD4AF37), fontSize: 26, fontWeight: FontWeight.w900)), // 글씨 폭풍 성장! (18 -> 26)
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