// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
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
import 'dart:js_util' as js_util;
import 'package:flutter/material.dart';

/// ⚠️ 배포마다 올리는 빌드 식별자 (web/appver.json 과 같은 값으로 유지)
const String kBuildId = '20260701-543';

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
    if (serverBuild.isEmpty || serverBuild == kBuildId) {
      // 최신이면 조용히 끝 + 이전에 남긴 새로고침 흔적 정리
      try { html.window.localStorage.remove('reloadedFor'); } catch (_) {}
      return;
    }
    // 🔁 [루프 방지] 이미 이 서버버전으로 새로고침을 시도했는데도 여전히 옛 버전이면
    //    (CDN/서비스워커 지연) → 팝업 다시 안 띄움. SW가 다음 방문에 알아서 갱신함.
    try {
      if (html.window.localStorage['reloadedFor'] == serverBuild) return;
    } catch (_) {}
    if (!context.mounted) return;
    // 🔒 넘길 수 없게 한다 — 예전엔 [나중에]와 바깥 터치로 빠져나갈 수 있어서,
    //    고쳐서 배포해도 옛 버전으로 계속 플레이하다 "또 안 되는데요"가 나왔다
    //    (2026-09-09 카피바라님 물약 건 · 하루에 일곱 번 배포한 날).
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (c) => PopScope(
        canPop: false, // 뒤로가기로도 못 닫는다
        child: AlertDialog(
          backgroundColor: const Color(0xFF1A1A1A),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: const BorderSide(color: Color(0xFFD4AF37), width: 1.2)),
          title: const Text('🎉 새 버전이 나왔어요!',
              style: TextStyle(color: Color(0xFFD4AF37), fontSize: 17, fontWeight: FontWeight.bold)),
          content: const Text(
              '업데이트가 있어요.\n새로고침하면 최신 버전으로 즐길 수 있어요!\n\n'
              '이전 버전으로는 이미 고쳐진 문제가 그대로 보일 수 있어요.',
              style: TextStyle(color: Colors.white70, fontSize: 15, height: 1.5)),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFD4AF37), foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 13)),
              onPressed: () => forceReloadLatest(serverBuild),
              child: const Text('새로고침',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  } catch (_) {
    // appver.json 없음/네트워크 실패 → 무시(게임엔 지장 없음)
  }
}

/// 서비스워커+캐시를 지운 뒤 새로고침 → 캐시된 옛 버전이 아니라 '진짜 최신'을 받게 함.
/// 새로고침해도 여전히 옛 버전이면(전파 지연) 루프 방지를 위해 시도한 버전을 기록해둔다.
Future<void> forceReloadLatest(String serverBuild) async {
  try { html.window.localStorage['reloadedFor'] = serverBuild; } catch (_) {}
  // 1) 서비스워커 해제
  try {
    final sw = html.window.navigator.serviceWorker;
    if (sw != null) {
      final regs = await sw.getRegistrations();
      for (final r in regs) {
        try { await r.unregister(); } catch (_) {}
      }
    }
  } catch (_) {}
  // 2) CacheStorage 전부 삭제 — SW가 캐싱한 옛 main.dart.js/에셋 제거(새로고침해도 옛 버전 뜨던 원인)
  try {
    final caches = js_util.getProperty(html.window, 'caches');
    if (caches != null) {
      final keys = await js_util.promiseToFuture<dynamic>(js_util.callMethod(caches, 'keys', []));
      for (final k in (keys as List)) {
        try { await js_util.promiseToFuture(js_util.callMethod(caches, 'delete', [k])); } catch (_) {}
      }
    }
  } catch (_) {}
  // 3) 캐시버스터 쿼리(_v=타임스탬프)를 붙여 '새 URL'로 이동 → 브라우저가 index.html·부팅파일을
  //    HTTP 캐시에서 못 꺼내고 네트워크에서 새로 받음. (location.reload()는 캐시된 옛 버전을 그대로
  //    다시 띄우는 경우가 있어 "새로고침 눌러도 그대로" 버그의 원인이었음 — iframe 임베드+SW 조합.)
  try {
    final Uri cur = Uri.parse(html.window.location.href);
    // 기존 쿼리에서 _v 제거 후(무한 증식 방지) 새 타임스탬프 부여
    final Map<String, String> qp = Map<String, String>.from(cur.queryParameters)
      ..remove('_v')
      ..['_v'] = DateTime.now().millisecondsSinceEpoch.toString();
    final String bust = cur.replace(queryParameters: qp).toString();
    html.window.location.replace(bust); // replace = 히스토리 안 쌓임
  } catch (_) {
    html.window.location.reload();       // 폴백
  }
}
