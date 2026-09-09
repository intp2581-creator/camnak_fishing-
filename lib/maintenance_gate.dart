// ignore_for_file: avoid_web_libraries_in_flutter
// 🔧 서버 점검 게이트 — Firestore config/maintenance 문서 하나로 게임을 잠근다.
//
//   문서 모양: config/maintenance
//     on    : true 면 점검 중(게임 전체를 점검 화면으로 덮음)
//     msg   : 안내 문구(선택, 기본 문구 있음)
//     until : "11:50" 같은 종료 예정 표기(선택, 문구 그대로 보여줌)
//
//   · 실시간 구독이라 접속 중인 유저도 점검을 켜는 순간 막힌다(재접속 불필요).
//   · 운영자(users/{uid}.isGm)는 통과 — 점검 중에 직접 확인할 수 있게. 상단에 띠 표시.
//   · 점검이 풀리면(on: true → false) 페이지를 새로고침한다 — 점검 중 새 버전을
//     배포했을 테니, 이어서 놀게 두면 옛 코드로 노는 셈이라 반드시 새로 받게 한다.
//
//   운영 절차(다음 점검부터): 줄광고·공지 예고 → config/maintenance on:true →
//   배포 → on:false (유저 화면이 자동 새로고침되며 새 버전으로 들어옴)
import 'dart:async';
import 'dart:html' as html;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class MaintenanceGate extends StatefulWidget {
  final Widget child;
  const MaintenanceGate({super.key, required this.child});

  @override
  State<MaintenanceGate> createState() => _MaintenanceGateState();
}

class _MaintenanceGateState extends State<MaintenanceGate> {
  bool _sawOn = false; // 점검 화면을 본 적 있으면, 풀릴 때 새로고침
  bool _blocking = false; // 지금 점검 화면을 띄우고 있나(복귀 재확인용)
  StreamSubscription<html.Event>? _visSub;

  @override
  void initState() {
    super.initState();
    // 📱 모바일은 탭이 뒤로 가거나 화면이 꺼지면 실시간 연결을 재운다.
    //   그 사이 점검이 풀리면 해제 신호를 못 받아 점검 화면에 갇힌다
    //   (2026-09-09 첫 점검에서 폰이 그대로 멈춰 있었다).
    //   화면으로 돌아왔을 때 한 번 직접 읽어 확인한다.
    _visSub = html.document.onVisibilityChange.listen((_) async {
      if (!_blocking) return;
      if (html.document.visibilityState != 'visible') return;
      try {
        final d = await FirebaseFirestore.instance
            .collection('config').doc('maintenance').get();
        if ((d.data()?['on'] == true)) return; // 아직 점검 중
        _reloadLatest();
      } catch (_) {}
    });
  }

  @override
  void dispose() {
    _visSub?.cancel();
    super.dispose();
  }

  /// 📢 점검 공지로 나간다 — 점검은 늘 공지를 먼저 올리므로, 게임 중이 아니던
  ///   사람이 "왜 점검이지?" 할 때 이유를 바로 볼 수 있는 곳으로 보낸다.
  ///   게임은 허브 안의 iframe 으로 도니 top 을 옮긴다(광장 '나가기'와 같은 방식).
  void _goHome() {
    const url = 'https://kreft.co.kr/notice.html';
    try {
      html.window.top?.location.href = url;
    } catch (_) {
      html.window.location.href = url;
    }
  }

  /// 🔄 새 버전을 받도록 새로고침(캐시버스터 부착)
  void _reloadLatest() {
    final uri = Uri.parse(html.window.location.href);
    final qp = Map<String, String>.from(uri.queryParameters)
      ..remove('_v')
      ..['_v'] = DateTime.now().millisecondsSinceEpoch.toString();
    html.window.location.replace(uri.replace(queryParameters: qp).toString());
  }

  @override
  Widget build(BuildContext context) {
    // ⚠️ 로그인이 끝난 뒤에 구독해야 한다.
    //   config/maintenance 는 '인증된 회원만' 읽을 수 있는데, 앱이 뜨자마자
    //   구독하면 아직 로그인 전이라 PERMISSION_DENIED 가 난다. Firestore 스트림은
    //   한 번 오류가 나면 스스로 되살아나지 않아서, 로그인 후에도 계속 죽어 있고
    //   문서를 못 읽으니 '점검 아님'으로 보여 전원 통과시켰다(2026-09-09 첫 점검에서
    //   아레투사가 그냥 들어와져 발견). 계정이 바뀌면 key 로 새로 구독한다.
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (c0, auth) {
        final String? uid = auth.data?.uid;
        // 로그인 전에는 어차피 게임을 못 한다(회원 전용 화면) — 그대로 통과.
        if (uid == null) return widget.child;
        return _gate(uid);
      },
    );
  }

  Widget _gate(String uid) {
    return StreamBuilder<DocumentSnapshot>(
      key: ValueKey('maint_$uid'),
      stream: FirebaseFirestore.instance
          .collection('config').doc('maintenance').snapshots(),
      builder: (c, snap) {
        final d = snap.data?.data() as Map<String, dynamic>?;
        final bool on = d?['on'] == true;

        if (!on) {
          if (_sawOn) {
            _blocking = false;
            _reloadLatest();   // 🔄 점검 끝 → 새 버전으로 다시 들어간다
            return const SizedBox.shrink();
          }
          return widget.child;
        }

        final String msg = (d?['msg'] ?? '').toString();
        final String until = (d?['until'] ?? '').toString();

        // 운영자는 통과(점검 중 확인용) — 상단에 띠만 붙인다
        return StreamBuilder<DocumentSnapshot>(
          key: ValueKey('maintgm_$uid'),
          stream: FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
          builder: (c2, us) {
            final bool isGm =
                (us.data?.data() as Map<String, dynamic>?)?['isGm'] == true;
            if (isGm) {
              return Stack(children: [
                widget.child,
                Positioned(top: 0, left: 0, right: 0, child: Container(
                  color: const Color(0xCCB71C1C),
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: const Text('🔧 점검 중 — 운영자 계정이라 통과 중입니다',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white, fontSize: 12,
                          fontWeight: FontWeight.bold)),
                )),
              ]);
            }
            _sawOn = true;
            _blocking = true;
            return _blockScreen(msg, until);
          },
        );
      },
    );
  }

  Widget _blockScreen(String msg, String until) {
    return Container(
      color: Colors.black,
      alignment: Alignment.center,
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Text('🔧', style: TextStyle(fontSize: 64)),
        const SizedBox(height: 18),
        const Text('서버 점검 중입니다',
            style: TextStyle(color: Color(0xFFD4AF37), fontSize: 28,
                fontWeight: FontWeight.w900)),
        const SizedBox(height: 14),
        Text(
            msg.isNotEmpty ? msg : '더 좋은 게임을 위해 점검하고 있어요.\n잠시 후 다시 만나요!',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, fontSize: 16, height: 1.6)),
        if (until.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text('종료 예정  $until',
              style: const TextStyle(color: Colors.white54, fontSize: 14)),
        ],
        const SizedBox(height: 26),
        // 🏠 점검 화면에 갇히지 않도록 나갈 길을 준다. 게임은 허브(kreft.co.kr)
        //   안의 iframe 으로 도니 top 을 옮겨야 한다(광장 '나가기'와 같은 방식).
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFD4AF37),
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 12)),
          onPressed: _goHome,
          icon: const Icon(Icons.campaign, size: 18),
          label: const Text('점검 공지 보기',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
        ),
        const SizedBox(height: 14),
        const Text('점검이 끝나면 이 화면이 자동으로 새로고침됩니다.\n자세한 내용은 [점검 공지 보기]에서 확인하실 수 있어요.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white38, fontSize: 12, height: 1.5)),
      ]),
    );
  }
}
