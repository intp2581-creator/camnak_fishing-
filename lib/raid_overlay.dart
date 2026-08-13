// 🐋 [보스레이드] 아마존 모임터 오버레이 — 아레나 대기방 시스템 재활용(Firestore raids/{길드ID}).
//   광장(레이드 모드) 위에 얹혀서: 상단 타이틀/나가기 + 하단 레디(길드원)/시작(길드장) 버튼.
//   길드원 각자 raids/{길드ID}/participants/{uid} 에 isReady 기록 → 길드장이 전원 레디 확인 후 START.
//   status=='raiding' 되면 onStart(endAt) 콜백 → 광장이 전원 보스전으로 입장(아레나 playEndAt 공유와 동일 패턴).
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';

const Color _kGold = Color(0xFFD4AF37);
const int kRaidBossHp = 4000000; // 피라루크 필요 제압치(400만)
const int kRaidSeconds = 600;    // 제한 10분

class RaidOverlay extends StatefulWidget {
  final String guildId;
  final String guildName;
  final bool isLeader;   // 길드장/부길드장 = 시작 권한
  final String myNick;
  final String myRank;
  final bool isSea;      // 민물(피라루크)/바다(백상아리)
  final void Function(int endAt) onStart; // status=raiding 감지 → 보스전 입장
  final VoidCallback onClose; // 패널 닫기(길드홀로 복귀)

  const RaidOverlay({
    super.key,
    required this.guildId,
    required this.guildName,
    required this.isLeader,
    required this.myNick,
    required this.myRank,
    required this.isSea,
    required this.onStart,
    required this.onClose,
  });

  @override
  State<RaidOverlay> createState() => _RaidOverlayState();
}

class _RaidOverlayState extends State<RaidOverlay> {
  final _uid = FirebaseAuth.instance.currentUser?.uid ?? '';
  DocumentReference<Map<String, dynamic>> get _roomRef =>
      FirebaseFirestore.instance.collection('raids').doc(widget.guildId);
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _join();
    _watchRoom();
  }

  @override
  void dispose() {
    // 모임터 나가면 참가자 목록에서 빠짐(대기 상태일 때만 — 전투 중이면 유지)
    if (_uid.isNotEmpty) {
      _roomRef.get().then((snap) {
        if ((snap.data()?['status'] ?? 'waiting') == 'waiting') {
          _roomRef.collection('participants').doc(_uid).delete().catchError((_) {});
        }
      }).catchError((_) {});
    }
    super.dispose();
  }

  // 🐟 모임터 입장 = 참가자 등록 (isReady: 길드장은 자동 준비)
  Future<void> _join() async {
    if (_uid.isEmpty) return;
    try {
      // 방 문서 없으면 대기 상태로 생성(merge — 먼저 들어온 사람이 만들되 기존 진행중 상태는 안 건드림)
      await _roomRef.set({
        'guildName': widget.guildName,
        'isSea': widget.isSea,
        if (widget.isLeader) 'hasLeader': true,
      }, SetOptions(merge: true));
      final snap = await _roomRef.get();
      if ((snap.data()?['status'] ?? 'waiting') == 'waiting') {
        await _roomRef.collection('participants').doc(_uid).set({
          'nick': widget.myNick,
          'rank': widget.myRank,
          'isReady': widget.isLeader, // 길드장은 자동 레디
          'isLeader': widget.isLeader,
          'joinedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    } catch (e) {
      debugPrint('🐋 raid join err: $e');
    }
  }

  void _watchRoom() {
    _roomRef.snapshots().listen((snap) {
      if (!mounted) return;
      final d = snap.data();
      final status = (d?['status'] ?? 'waiting').toString();
      if (status == 'raiding' && !_started) {
        _started = true;
        final endAt = (d?['endAt'] is num) ? (d!['endAt'] as num).toInt() : 0;
        widget.onStart(endAt);
      } else if (status == 'waiting') {
        _started = false; // 레이드 끝나 대기로 리셋되면 다음 판 재입장 가능
      }
    });
  }

  // 🟢 레디 토글(길드원)
  Future<void> _toggleReady(bool cur) async {
    if (_uid.isEmpty) return;
    try {
      await _roomRef.collection('participants').doc(_uid).set(
          {'isReady': !cur}, SetOptions(merge: true));
    } catch (_) {}
  }

  // 🚀 레이드 시작(길드장) — 전원 레디 확인 후 status=raiding + 공유 종료시각/보스HP 세팅
  Future<void> _startRaid() async {
    final ps = await _roomRef.collection('participants').get();
    final total = ps.docs.length;
    final notReady = ps.docs.where((p) => p.data()['isReady'] != true).length;
    if (notReady > 0) {
      _snack('아직 준비 안 된 길드원이 $notReady명 있어요.');
      return;
    }
    if (total < 1) { _snack('모인 길드원이 없어요.'); return; }
    final endAt = DateTime.now().add(const Duration(seconds: kRaidSeconds)).millisecondsSinceEpoch;
    // 💥 공유 데미지 누적값 초기화(지난 판 잔여 제거) — 전투 시작 전에 반드시
    try {
      await FirebaseDatabase.instanceFor(
        app: Firebase.app(),
        databaseURL: 'https://camnak-fishing-default-rtdb.asia-southeast1.firebasedatabase.app',
      ).ref('raid_battle/${widget.guildId}/dmg').set(0);
    } catch (e) {
      debugPrint('🐋 dmg reset err: $e');
    }
    await _roomRef.set({
      'status': 'raiding',
      'endAt': endAt,
      'bossHp': kRaidBossHp,     // 공유 보스 체력(전투에서 각자 제압력만큼 깎음)
      'startedAt': FieldValue.serverTimestamp(),
      'memberCount': total,
    }, SetOptions(merge: true));
    // (onStart는 _watchRoom 리스너가 전원 공통으로 처리 → 길드장도 동일 경로로 입장)
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(m), backgroundColor: Colors.black87, duration: const Duration(seconds: 2)));
  }

  @override
  Widget build(BuildContext context) {
    if (_uid.isEmpty || widget.guildId.isEmpty) return const SizedBox.shrink(); // 안전 가드(.doc('') 크래시 방지)
    return Stack(children: [
      // 반투명 배경(패널 강조)
      Positioned.fill(child: GestureDetector(
        onTap: () {}, // 뒤 클릭 차단
        child: Container(color: Colors.black.withOpacity(0.4)),
      )),
      // 상단 타이틀 + 나가기
      Positioned(
        top: 12, left: 12, right: 12,
        child: Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.5),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _kGold, width: 1.2),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Text('🐋 ', style: TextStyle(fontSize: 18)),
              Text('[${widget.guildName}] 보스 레이드 모임터',
                  style: const TextStyle(color: _kGold, fontSize: 15, fontWeight: FontWeight.w900)),
            ]),
          ),
          const Spacer(),
          // (모임/레디 인원 카운터는 하단 버튼 위로 이동 — 우측상단 HUD와 겹침 방지)
          GestureDetector(
            onTap: widget.onClose, // 패널 닫기(길드홀로)
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.5),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white24),
              ),
              child: const Icon(Icons.close, color: Colors.white70, size: 22),
            ),
          ),
        ]),
      ),

      // 하단 중앙: 인원수 + 레디(길드원) / 시작(길드장)
      Positioned(
        left: 0, right: 0, bottom: 24,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _roomRef.collection('participants').snapshots(),
              builder: (c, ps) {
                final docs = ps.data?.docs ?? [];
                final total = docs.length;
                final readyCnt = docs.where((d) => d.data()['isReady'] == true).length;
                final allReady = total > 0 && readyCnt == total;
                return Column(mainAxisSize: MainAxisSize.min, children: [
                  // 🎣 모임/레디 인원 (버튼 위)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    margin: const EdgeInsets.only(bottom: 10),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.55),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: _kGold.withOpacity(0.6)),
                    ),
                    child: Text('🎣 모임 $total명   ·   ✅ 레디 $readyCnt / $total명',
                        style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w900)),
                  ),
                  // 길드원 레디 토글 (내 상태)
                  StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                    stream: _roomRef.collection('participants').doc(_uid).snapshots(),
                    builder: (c2, s) {
                      final ready = s.data?.data()?['isReady'] == true;
                      return SizedBox(
                        width: double.infinity, height: 52,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: ready ? const Color(0xFF7FFFB0) : Colors.black.withOpacity(0.55),
                            foregroundColor: ready ? Colors.black : Colors.white,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                                side: const BorderSide(color: Color(0xFF7FFFB0), width: 1.4)),
                          ),
                          onPressed: () => _toggleReady(ready),
                          child: Text(ready ? '✅ 레디 완료 (탭하면 취소)' : '준비되면 레디!',
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
                        ),
                      );
                    },
                  ),
                  if (widget.isLeader) ...[
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity, height: 56,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: allReady ? _kGold : _kGold.withOpacity(0.45),
                          foregroundColor: Colors.black,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        onPressed: _startRaid,
                        child: Text('🚀 보스전 시작!  (레디 $readyCnt/$total)',
                            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: Text('길드장/부길드장만 시작할 수 있어요',
                          style: TextStyle(color: Colors.white60, fontSize: 11)),
                    ),
                  ],
                ]);
              },
            ),
          ),
        ),
      ),
    ]);
  }
}
