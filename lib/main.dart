
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'game_config.dart'; // 🎉 이벤트 설정 로더(loadGameEvent)

// 👇 방금 우리가 만든 로그인/출입문 파일 하나만 딱 불러오면 끝!
// (나머지는 지들끼리 꼬리에 꼬리를 물고 알아서 연결됩니다 ㅋㅋ)
import 'ui_login.dart';

// 🏢 앱 초기화 및 심장부 (Global Entry Point)
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
  await loadGameEvent(); // 🎉 이벤트 설정 로드(실패해도 게임엔 지장 없음 — 이벤트만 미적용)
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '캠피싱',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        scaffoldBackgroundColor: Colors.black,
        colorScheme: const ColorScheme.dark(primary: Color(0xFFD4AF37)), // 영롱한 KREFT 골드!
      ),
      // 🖼️ 사장님 시안 비율(16:9)을 어떤 폰/모니터에서든 강제로 맞춰주는 마법의 액자!
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
      // main.dart의 home 부분 수정
      home: Builder(
        builder: (context) {
          // 🌐 실제 운영 환경에서는 kDebugMode 조건을 지우고 URL 파라미터만 확인합니다.
          String? urlUid = Uri.base.queryParameters['uid'];

          // 🛡️ 사장님 컴퓨터(개발 테스트 중)에서만 몰래 실행되는 무적 방패!
          assert(() {
            urlUid ??= 'test_admin@camnak.com';
            return true;
          }());

          // 💡 안전한 '새 변수(safeUid)'로 옮겨 담기
          final String safeUid = urlUid ?? '';

          // 🚀 이메일이 정상적으로 들어왔는지 확인하고 하이패스 가동!
          if (safeUid.trim().isNotEmpty && safeUid.contains('@')) {
            return AutoLoginScreen(email: safeUid.trim());
          }

          // 파라미터가 없거나 비정상적이면 접속 제한(자물쇠) 화면으로 이동
          return const GuestWarningScreen(); // 🌟 문제의 's'를 뺐습니다!
        },
      ), // Builder
    ); // MaterialApp
  }
}