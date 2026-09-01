
import 'dart:convert'; // 🔐 진입 파라미터(base64url) 디코드
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
        // 🍞 토스트(스낵바) 공통 스타일 — 화면이 어두워서 기본 검정 배경이면 글씨가 안 보였다(2026-09-01).
        //    앱 전체에서 16곳이 쓰므로 테마에서 한 번에 잡는다.
        //    floating + 아래 여백: 하단 채팅창·당기기 버튼에 가리지 않게 띄운다.
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xF01A1408),          // 짙은 갈색빛 검정(불투명)
          insetPadding: const EdgeInsets.fromLTRB(24, 0, 24, 96),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: const BorderSide(color: Color(0xFFD4AF37), width: 1.6), // 골드 테두리
          ),
          contentTextStyle: const TextStyle(
            color: Color(0xFFFFF3D0), fontSize: 16, fontWeight: FontWeight.w900, height: 1.35),
          elevation: 10,
        ),
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
          // 🔐 진입 식별값
          //   · k = base64url(이메일)  ← 신규(피싱 오탐 방지, 2026-08-29)
          //   · uid = 이메일 그대로     ← 구방식(기존 링크·북마크 하위호환)
          String? urlUid = Uri.base.queryParameters['uid'];
          final String? k = Uri.base.queryParameters['k'];
          if ((urlUid == null || urlUid.isEmpty) && k != null && k.isNotEmpty) {
            try {
              String t = k.replaceAll('-', '+').replaceAll('_', '/');
              while (t.length % 4 != 0) { t += '='; }
              urlUid = utf8.decode(base64.decode(t));
            } catch (_) {}
          }

          // 🛡️ 개발(디버그) 중 로컬 테스트용 자동 uid — 코드에 계정 이메일을 남기지 않도록 환경변수로 받음.
          //    로컬 실행 시 지정: flutter run -d chrome --dart-define=DEV_UID=<접속할 이메일>
          //    (release 빌드엔 포함 안 됨 = 배포본에 운영자 이메일 노출 없음)
          assert(() {
            const devUid = String.fromEnvironment('DEV_UID');
            if (devUid.isNotEmpty) urlUid ??= devUid;
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