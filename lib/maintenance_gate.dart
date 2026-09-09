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

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('config').doc('maintenance').snapshots(),
      builder: (c, snap) {
        final d = snap.data?.data() as Map<String, dynamic>?;
        final bool on = d?['on'] == true;

        if (!on) {
          if (_sawOn) {
            // 🔄 점검이 끝났다 → 새 버전을 받도록 새로고침(캐시버스터 부착)
            final uri = Uri.parse(html.window.location.href);
            final qp = Map<String, String>.from(uri.queryParameters)
              ..remove('_v')
              ..['_v'] = DateTime.now().millisecondsSinceEpoch.toString();
            html.window.location.replace(uri.replace(queryParameters: qp).toString());
            return const SizedBox.shrink();
          }
          return widget.child;
        }

        final String msg = (d?['msg'] ?? '').toString();
        final String until = (d?['until'] ?? '').toString();

        // 운영자는 통과(점검 중 확인용) — 상단에 띠만 붙인다
        final uid = FirebaseAuth.instance.currentUser?.uid;
        return StreamBuilder<DocumentSnapshot>(
          stream: uid == null
              ? const Stream.empty()
              : FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
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
        const Text('점검이 끝나면 이 화면이 자동으로 새로고침됩니다.',
            style: TextStyle(color: Colors.white38, fontSize: 12)),
      ]),
    );
  }
}
