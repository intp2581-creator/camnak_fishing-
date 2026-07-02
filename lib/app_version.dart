// 🔖 앱 버전 체크 — 오픈 후 "새 버전 나왔어요, 새로고침" 안내
//
// 사용법(배포할 때마다):
//   1) 아래 kBuildId 값을 새 값으로 올린다 (예: 20260701-1 → 20260701-2)
//   2) web/appver.json 의 "build" 값을 '똑같은 값'으로 맞춘다
//   3) flutter build web → firebase deploy --only hosting
//
// 원리: 실행 중인(=이전에 캐시된) 앱의 kBuildId 와, 서버 web/appver.json 의 build 가
//       다르면 = 새 버전이 배포된 것 → 유저에게 새로고침 안내.
import 'dart:convert';
import 'dart:html' as html;
import 'package:flutter/material.dart';

/// ⚠️ 배포마다 올리는 빌드 식별자 (web/appver.json 과 같은 값으로 유지)
const String kBuildId = '20260701-26';

bool _updateChecked = false;

/// 앱 시작 후 1회 호출. 서버 버전과 다르면 새로고침 안내 팝업.
Future<void> checkAppUpdate(BuildContext context) async {
  if (_updateChecked) return; // 세션당 1회만
  _updateChecked = true;
  try {
    // ?t= 로 캐시 우회(항상 최신 값 확인)
    final url = 'appver.json?t=${DateTime.now().millisecondsSinceEpoch}';
    final resp = await html.HttpRequest.getString(url);
    final data = json.decode(resp) as Map<String, dynamic>;
    final serverBuild = (data['build'] ?? '').toString();
    if (serverBuild.isEmpty || serverBuild == kBuildId) return; // 최신이면 조용히 끝
    if (!context.mounted) return;
    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (c) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: const BorderSide(color: Color(0xFFD4AF37), width: 1.2)),
        title: const Text('🎉 새 버전이 나왔어요!',
            style: TextStyle(color: Color(0xFFD4AF37), fontSize: 17, fontWeight: FontWeight.bold)),
        content: const Text('업데이트가 있어요.\n새로고침하면 최신 버전으로 즐길 수 있어요!',
            style: TextStyle(color: Colors.white70, fontSize: 15, height: 1.5)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('나중에', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFD4AF37), foregroundColor: Colors.black),
            onPressed: () => forceReloadLatest(),
            child: const Text('새로고침', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  } catch (_) {
    // appver.json 없음/네트워크 실패 → 무시(게임엔 지장 없음)
  }
}

/// 서비스워커를 강제 해제한 뒤 새로고침 → 캐시된 옛 버전이 아니라 '진짜 최신'을 받게 함.
Future<void> forceReloadLatest() async {
  try {
    final sw = html.window.navigator.serviceWorker;
    if (sw != null) {
      final regs = await sw.getRegistrations();
      for (final r in regs) {
        try {
          await r.unregister();
        } catch (_) {}
      }
    }
  } catch (_) {}
  html.window.location.reload();
}
