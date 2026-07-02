// ignore_for_file: deprecated_member_use
// 🛡️ [길드 공용] 접속상태(presence) + 길드 정보 다이얼로그 (광장/낚시터 공용, 읽기 전용)
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'fishing_logic.dart';

const Color _kGold = Color(0xFFD4AF37);
const String _dbUrl =
    'https://camnak-fishing-default-rtdb.asia-southeast1.firebasedatabase.app';

FirebaseDatabase _statusDb() =>
    FirebaseDatabase.instanceFor(app: Firebase.app(), databaseURL: _dbUrl);

// 🔒 [중복 로그인 방지] 페이지 로드마다 고유 세션ID 1개.
//    새 기기(창)가 접속해 세션을 덮어쓰면, 기존 기기가 감지하고 스스로 차단 → 이중 보상 원천 봉쇄.
final String appSessionId =
    '${DateTime.now().millisecondsSinceEpoch}_${DateTime.now().microsecond}';

// 내 세션 등록 (광장 진입 시 호출) — 마지막 로그인 기기가 주도권을 가짐
void registerLoginSession() {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return;
  _statusDb().ref('login_session/$uid').set({'s': appSessionId, 't': ServerValue.timestamp});
}

// 세션 감시 — 다른 기기가 세션을 덮어쓰면 onKicked 호출 (호출측에서 구독 해제 관리)
StreamSubscription<DatabaseEvent> watchLoginSession(void Function() onKicked) {
  final uid = FirebaseAuth.instance.currentUser?.uid ?? '_none_';
  return _statusDb().ref('login_session/$uid').onValue.listen((e) {
    final v = e.snapshot.value;
    if (v is Map && v['s'] != null && v['s'].toString() != appSessionId) {
      onKicked();
    }
  });
}

// 🟢 전역 접속표시: 앱 화면(광장/낚시터)에서 호출. 연결 끊기면 자동 offline.
void guildGoOnline() {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return;
  final ref = _statusDb().ref('status/$uid');
  ref.onDisconnect().update({'online': false, 't': ServerValue.timestamp});
  ref.set({'online': true, 't': ServerValue.timestamp});
}

// 길드원 접속 점(초록=접속/회색=비접속)
// 🛡️ 유령접속 방지: online 불리언이 아니라 '마지막 하트비트(t) 신선도'로 판정.
// 탭 강제종료 등으로 onDisconnect가 안 먹어도 40초 지나면 자동 회색.
const int _onlineFreshMs = 40000; // 하트비트 12초 → 40초 넘으면 오프라인 처리

Widget guildOnlineDot(String memberUid, {double size = 9}) =>
    _GuildOnlineDot(uid: memberUid, size: size);

class _GuildOnlineDot extends StatefulWidget {
  final String uid;
  final double size;
  const _GuildOnlineDot({required this.uid, this.size = 9});
  @override
  State<_GuildOnlineDot> createState() => _GuildOnlineDotState();
}

class _GuildOnlineDotState extends State<_GuildOnlineDot> {
  StreamSubscription<DatabaseEvent>? _sub;
  Timer? _ticker;
  bool _isOn = false;
  int _t = 0;

  @override
  void initState() {
    super.initState();
    _sub = _statusDb().ref('status/${widget.uid}').onValue.listen((e) {
      final v = e.snapshot.value;
      if (v is Map) {
        _isOn = v['online'] == true;
        _t = (v['t'] is int) ? v['t'] as int : 0;
      } else {
        _isOn = false;
        _t = 0;
      }
      if (mounted) setState(() {});
    });
    // RTDB 이벤트가 안 와도(상대가 그냥 끊긴 경우) 신선도 재판정하도록 주기 갱신
    _ticker = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final online = _isOn &&
        (DateTime.now().millisecondsSinceEpoch - _t) < _onlineFreshMs;
    return Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: online ? const Color(0xFF4CD964) : Colors.grey.shade600,
        boxShadow: online
            ? [BoxShadow(color: const Color(0xFF4CD964).withOpacity(0.6), blurRadius: 5)]
            : null,
      ),
    );
  }
}

// ⏱️ 길드원 마지막 접속(종료) 시간 텍스트. 접속 중이면 '접속 중', 아니면 't'(마지막 하트비트/종료) 기준 상대시간.
Widget guildLastSeen(String memberUid, {double fontSize = 11}) =>
    _GuildLastSeen(uid: memberUid, fontSize: fontSize);

class _GuildLastSeen extends StatefulWidget {
  final String uid;
  final double fontSize;
  const _GuildLastSeen({required this.uid, this.fontSize = 11});
  @override
  State<_GuildLastSeen> createState() => _GuildLastSeenState();
}

class _GuildLastSeenState extends State<_GuildLastSeen> {
  StreamSubscription<DatabaseEvent>? _sub;
  Timer? _ticker;
  bool _isOn = false;
  int _t = 0;

  @override
  void initState() {
    super.initState();
    _sub = _statusDb().ref('status/${widget.uid}').onValue.listen((e) {
      final v = e.snapshot.value;
      if (v is Map) {
        _isOn = v['online'] == true;
        _t = (v['t'] is int) ? v['t'] as int : 0;
      } else {
        _isOn = false;
        _t = 0;
      }
      if (mounted) setState(() {});
    });
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _ticker?.cancel();
    super.dispose();
  }

  String _ago(int ms) {
    if (ms <= 0) return '기록 없음';
    final d = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(ms));
    if (d.inMinutes < 1) return '방금 전';
    if (d.inMinutes < 60) return '${d.inMinutes}분 전';
    if (d.inHours < 24) return '${d.inHours}시간 전';
    if (d.inDays < 30) return '${d.inDays}일 전';
    return '오래 전';
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final online = _isOn && (now - _t) < _onlineFreshMs;
    return Text(
      online ? '접속 중' : _ago(_t),
      style: TextStyle(
        color: online ? const Color(0xFF4CD964) : Colors.white38,
        fontSize: widget.fontSize,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

// 📋 길드 정보 보기 (읽기 전용) — 가입/탈퇴는 광장 길드 포탈에서만
void showGuildInfoDialog(BuildContext context) {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return;
  final uid = user.uid;
  showDialog(
    context: context,
    builder: (ctx) => Dialog(
      backgroundColor: const Color(0xFF1A1A1A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: 460,
        height: 540,
        child: StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
          builder: (c, snap) {
            if (!snap.hasData) {
              return const Center(child: CircularProgressIndicator(color: _kGold));
            }
            final gid =
                ((snap.data!.data() as Map<String, dynamic>?)?['guildId'] ?? '').toString();
            if (gid.isEmpty) {
              return Column(children: [
                _header(ctx, '길드'),
                const Expanded(
                  child: Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('가입한 길드가 없습니다.\n광장의 길드 건물에서 가입하세요!',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white54, fontSize: 15, height: 1.5)),
                    ),
                  ),
                ),
              ]);
            }
            return _GuildInfoBody(gid: gid, onClose: () => Navigator.pop(ctx));
          },
        ),
      ),
    ),
  );
}

Widget _header(BuildContext ctx, String title, {bool champ = false}) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    decoration: const BoxDecoration(
      color: Color(0xFF262626),
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    child: Row(children: [
      const Icon(Icons.groups, color: _kGold, size: 22),
      const SizedBox(width: 8),
      if (champ) const Text('👑 ', style: TextStyle(fontSize: 16)),
      Flexible(
        child: Text(title,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900)),
      ),
      const Spacer(),
      IconButton(
          icon: const Icon(Icons.close, color: Colors.white54),
          onPressed: () => Navigator.pop(ctx)),
    ]),
  );
}

class _GuildInfoBody extends StatelessWidget {
  final String gid;
  final VoidCallback onClose;
  const _GuildInfoBody({required this.gid, required this.onClose});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('guilds').doc(gid).snapshots(),
      builder: (c, gsnap) {
        if (!gsnap.hasData) {
          return const Center(child: CircularProgressIndicator(color: _kGold));
        }
        if (!gsnap.data!.exists) {
          return Column(children: [
            _header(context, '길드'),
            const Expanded(
                child: Center(
                    child: Text('길드가 해체되었어요.', style: TextStyle(color: Colors.white54)))),
          ]);
        }
        final g = gsnap.data!.data() as Map<String, dynamic>;
        final name = g['name']?.toString() ?? '길드';
        final guildExp = (g['guildExp'] is num) ? (g['guildExp'] as num).toInt() : 0;
        final gLevel = FishingLogic.guildLevelFromExp(guildExp);
        final mc = (g['memberCount'] is num) ? (g['memberCount'] as num).toInt() : 0;
        final cap = FishingLogic.guildMaxMembers(gLevel);
        final levelBonus = FishingLogic.guildStatBonus(gLevel);

        return StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance.collection('guild_league').doc('state').snapshots(),
          builder: (c2, st) {
            final champId =
                ((st.data?.data() as Map<String, dynamic>?)?['championGuildId'] ?? '').toString();
            final isChamp = champId == gid;
            final bonus = levelBonus + (isChamp ? FishingLogic.guildChampionBonus : 0);
            return Column(
              children: [
                _header(context, name, champ: isChamp),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration:
                          BoxDecoration(color: _kGold, borderRadius: BorderRadius.circular(8)),
                      child: Text('Lv.$gLevel',
                          style: const TextStyle(
                              color: Colors.black, fontSize: 13, fontWeight: FontWeight.w900)),
                    ),
                    const SizedBox(width: 10),
                    const Icon(Icons.military_tech, color: _kGold, size: 16),
                    const SizedBox(width: 4),
                    Text('${g['master'] ?? '-'}',
                        style: const TextStyle(color: Colors.white70, fontSize: 13)),
                    const SizedBox(width: 12),
                    const Icon(Icons.people, color: _kGold, size: 16),
                    const SizedBox(width: 4),
                    Text('$mc/$cap명',
                        style: const TextStyle(color: Colors.white70, fontSize: 13)),
                  ]),
                ),
                // 혜택 요약
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                      color: const Color(0xFF22301F),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFF3A6B33))),
                  child: Row(children: [
                    const Icon(Icons.bolt, color: Color(0xFF7FFFB0), size: 18),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                          isChamp
                              ? '👑 챔피언 길드! 힘·컨트롤·감도 각 +$bonus'
                              : '길드원 능력치 보너스: 힘·컨트롤·감도 각 +$bonus',
                          style: const TextStyle(
                              color: Color(0xFF7FFFB0), fontSize: 13, fontWeight: FontWeight.bold)),
                    ),
                  ]),
                ),
                const SizedBox(height: 4),
                const Divider(color: Colors.white12, height: 1),
                Expanded(child: _members(gid)),
              ],
            );
          },
        );
      },
    );
  }

  Widget _members(String gid) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('guilds')
          .doc(gid)
          .collection('members')
          .snapshots(),
      builder: (c, msnap) {
        if (!msnap.hasData) {
          return const Center(child: CircularProgressIndicator(color: _kGold));
        }
        final members = msnap.data!.docs.map((d) {
          final m = d.data() as Map<String, dynamic>;
          return {'uid': d.id, ...m};
        }).toList()
          ..sort((a, b) {
            final ra = (a['role'] == 'master') ? 0 : 1;
            final rb = (b['role'] == 'master') ? 0 : 1;
            if (ra != rb) return ra - rb;
            return ((b['level'] ?? 0) as int).compareTo((a['level'] ?? 0) as int);
          });
        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          itemCount: members.length,
          itemBuilder: (c, i) {
            final m = members[i];
            final mMaster = m['role'] == 'master';
            return Container(
              margin: const EdgeInsets.symmetric(vertical: 3),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                  color: const Color(0xFF2A2A2A), borderRadius: BorderRadius.circular(8)),
              child: Row(children: [
                guildOnlineDot(m['uid'].toString()),
                const SizedBox(width: 8),
                Icon(mMaster ? Icons.military_tech : Icons.person,
                    color: mMaster ? _kGold : Colors.white38, size: 18),
                const SizedBox(width: 6),
                Text(m['nickname']?.toString() ?? '',
                    style: const TextStyle(
                        color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                const SizedBox(width: 6),
                Text('Lv.${m['level'] ?? 1}',
                    style: const TextStyle(color: Colors.white38, fontSize: 12)),
                const Spacer(),
                if (mMaster)
                  const Text('길드장',
                      style:
                          TextStyle(color: _kGold, fontSize: 11, fontWeight: FontWeight.bold)),
              ]),
            );
          },
        );
      },
    );
  }
}
