// 🐋 [보스레이드] 아마존 모임터 오버레이 — 아레나 대기방 시스템 재활용(Firestore raids/{길드ID}).
//   광장(레이드 모드) 위에 얹혀서: 상단 타이틀/나가기 + 하단 레디(길드원)/시작(길드장) 버튼.
//   길드원 각자 raids/{길드ID}/participants/{uid} 에 isReady 기록 → 길드장이 전원 레디 확인 후 START.
//   status=='raiding' 되면 onStart(endAt) 콜백 → 광장이 전원 보스전으로 입장(아레나 playEndAt 공유와 동일 패턴).
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'game_config.dart';    // raidBossById, raidBosses
import 'fishing_logic.dart'; // resolveRaidGearPower (전투화면과 동일한 제압력 계산)

const Color _kGold = Color(0xFFD4AF37);
// 🐲 보스 HP는 game_config.raidBosses[*].hp 하나만 본다(예전 kRaidBossHp 상수는 미사용이라 제거, 2026-08-30).
const int kRaidSeconds = 600;    // 🐲 보스당 10분(건틀릿 — 클리어하면 다음 보스 새 10분)

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

  // 🎣 레이드 셋팅(출조 셋팅과 동일 룩) — 장착된 레이드 낚싯대
  Map<String, dynamic>? _raidRod;
  int _myPower = 0;
  List<Map<String, dynamic>> _gearList = []; // 🎒 레이드에 쓰일 장비(읽기 전용 요약)
  bool _gearLoading = true;
  String _hostUid = '';        // 🎖️ 이번 레이드를 연 사람(길드장/부길드장 1명) — 이 사람만 시작 가능
  bool get _isHost => _hostUid.isNotEmpty && _hostUid == _uid;
  String _bossId = 'murgadon'; // 🐲 이번에 도전할 보스(클리어하면 방 문서에 다음 보스가 기록됨)

  // 💬 레이드 대기중 소통 — 길드 채팅(guilds/{gid}/chat)을 그대로 쓴다.
  //    새 컬렉션을 만들면 보안규칙(콘솔 관리)을 건드려야 하고, 어차피 참가자는 전원 같은 길드다.
  final TextEditingController _chatCtrl = TextEditingController();
  final FocusNode _chatFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _join();
    _watchRoom();
    _autoEquipRaidRod();
  }

  // ⚡ 자동 장착 — 전투화면과 동일 규칙(resolveRaidGearPower)으로 레이드대 + 제압력 산출.
  //   내 제압력을 참가자 문서에 기록 → 모임터에서 '레디한 길드원 합산 제압력' 표시.
  Future<void> _autoEquipRaidRod({bool notify = false}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) { if (mounted) setState(() => _gearLoading = false); return; }
    try {
      final d = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      // 🛡️ 길드레벨 + 길드리그랭킹 + 개인랭킹(가람) 보너스 — 전투화면과 동일하게 제압력에 반영
      int statBonus = 0;
      try {
        if (widget.guildId.isNotEmpty) {
          final gdoc = await FirebaseFirestore.instance.collection('guilds').doc(widget.guildId).get();
          final gexp = (gdoc.data()?['guildExp'] is num) ? (gdoc.data()!['guildExp'] as num).toInt() : 0;
          statBonus += FishingLogic.guildStatBonus(FishingLogic.guildLevelFromExp(gexp));
          final gBossCnt = (gdoc.data()?['clearedBosses'] is List) ? (gdoc.data()!['clearedBosses'] as List).length : 0;
          statBonus += FishingLogic.guildBossBonus(gBossCnt); // 🏴 보스 처치 깃발 보너스(마리당 +5, 최대 +25)
          final st = await FirebaseFirestore.instance.collection('guild_league').doc('state').get();
          final active = (st.data()?['activeWeek'] ?? '') == FishingLogic.weekKey(DateTime.now());
          final lr = st.data()?['leagueRanks'];
          if (active && lr is Map && lr[widget.guildId] is num) {
            statBonus += FishingLogic.guildLeagueBonus((lr[widget.guildId] as num).toInt());
          }
        }
        final gr = await FirebaseFirestore.instance.collection('garam_rank').doc('state').get();
        final ranks = gr.data()?['ranks'];
        if (ranks is Map && ranks[user.uid] is Map && ranks[user.uid]['rank'] is num) {
          statBonus += garamRankBonus((ranks[user.uid]['rank'] as num).toInt());
        }
      } catch (_) {}
      final g = resolveRaidGearPower(d.data() ?? {}, statBonus: statBonus);
      final rod = g['raidRod'] as Map<String, dynamic>?;
      final int power = (g['power'] as num).toInt();
      final gl = (g['gearList'] as List?)?.cast<Map<String, dynamic>>() ?? <Map<String, dynamic>>[];
      if (!mounted) return;
      setState(() { _raidRod = rod; _myPower = power; _gearList = gl; _gearLoading = false; });
      // 참가자 문서에 내 제압력 기록(레이드대 없으면 0 — 합산에서 제외)
      if (_uid.isNotEmpty) {
        _roomRef.collection('participants').doc(_uid)
            .set({'power': rod != null ? power : 0}, SetOptions(merge: true)).catchError((_) {});
      }
      if (notify) {
        _snack(rod != null ? '⚡ 자동장착 완료 — ${rod['name']} (제압력 $power)' : '레이드 전용 낚싯대가 없어요! (길드상점)');
      }
    } catch (e) {
      if (mounted) setState(() => _gearLoading = false);
    }
  }

  @override
  void dispose() {
    _chatCtrl.dispose();
    _chatFocus.dispose();
    // 모임터 나가면 참가자 목록에서 빠짐(대기 상태일 때만 — 전투 중이면 유지)
    if (_uid.isNotEmpty) {
      _roomRef.get().then((snap) {
        if ((snap.data()?['status'] ?? 'waiting') == 'waiting') {
          _roomRef.collection('participants').doc(_uid).delete().catchError((_) {});
          // 주최자가 나가면 주최 자리를 비워 다른 길드장이 다시 열 수 있게 함
          if ((snap.data()?['hostUid'] ?? '') == _uid) {
            _roomRef.set({'hostUid': '', 'hostNick': ''}, SetOptions(merge: true)).catchError((_) => _roomRef);
          }
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
      // 🎖️ 주최자 선점 — 길드장/부길드장이 셋팅창을 '먼저 연' 한 명만 시작 권한을 갖는다.
      //    (여러 리더가 각자 시작해 따로 도는 문제 방지)
      final String curHost = (snap.data()?['hostUid'] ?? '').toString();
      if (widget.isLeader && curHost.isEmpty && (snap.data()?['status'] ?? 'waiting') == 'waiting') {
        await _roomRef.set({'hostUid': _uid, 'hostNick': widget.myNick,
            'openedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
      }
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
      final hu = (d?['hostUid'] ?? '').toString();
      if (hu != _hostUid) setState(() => _hostUid = hu);
      final bid = (d?['bossId'] ?? '').toString();
      if (bid.isNotEmpty && bid != _bossId) setState(() => _bossId = bid); // 진행도 반영
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

  // ═══════════════════════════════════════════════════════════════
  // 👥 [참가자 명단] 누가 레디했는지 한눈에 — 숫자(6/7)만으론 누굴 불러야 할지 모른다.
  //    길드장은 각 줄의 ✕로 유령 참가자(접속 끊고 목록에 남은 사람)를 뺄 수 있다.
  // ═══════════════════════════════════════════════════════════════
  Widget _rosterPanel() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _roomRef.collection('participants').snapshots(),
      builder: (c, ps) {
        final docs = [...(ps.data?.docs ?? [])];
        // 레디 안 한 사람을 위로 — 길드장이 바로 연락할 수 있게
        docs.sort((a, b) {
          final ar = a.data()['isReady'] == true ? 1 : 0;
          final br = b.data()['isReady'] == true ? 1 : 0;
          if (ar != br) return ar - br;
          return ((b.data()['power'] as num?) ?? 0).compareTo((a.data()['power'] as num?) ?? 0);
        });
        final readyCnt = docs.where((d) => d.data()['isReady'] == true).length;
        final allReady = docs.isNotEmpty && readyCnt == docs.length;

        return Container(
          decoration: BoxDecoration(
            color: const Color(0xFF14110C).withOpacity(0.92),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _kGold.withOpacity(0.55), width: 1.2),
          ),
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              const Text('👥 참가자', style: TextStyle(color: _kGold, fontSize: 15, fontWeight: FontWeight.w900)),
              const Spacer(),
              Text('레디 $readyCnt/${docs.length}',
                  style: TextStyle(
                      color: allReady ? const Color(0xFF7FFFB0) : Colors.orangeAccent,
                      fontSize: 13, fontWeight: FontWeight.w900)),
              const SizedBox(width: 4),
            ]),
            const SizedBox(height: 6),
            Divider(color: _kGold.withOpacity(0.2), height: 1),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.only(top: 4),
                itemCount: docs.length,
                itemBuilder: (c2, i) {
                  final d = docs[i].data();
                  final ready = d['isReady'] == true;
                  final nick = (d['nick'] ?? '?').toString();
                  final pow = ((d['power'] as num?) ?? 0).toInt();
                  final isMe = docs[i].id == _uid;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3.5),
                    child: Row(children: [
                      Text(ready ? '✅' : '⏳', style: const TextStyle(fontSize: 13)),
                      const SizedBox(width: 6),
                      if (d['isLeader'] == true) const Text('👑 ', style: TextStyle(fontSize: 11)),
                      Expanded(
                        child: Text(nick,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: ready ? rankColor((d['rank'] ?? '').toString()) : Colors.white38,
                                fontSize: 13,
                                fontWeight: isMe ? FontWeight.w900 : FontWeight.w700)),
                      ),
                      if (pow > 0)
                        Text('$pow',
                            style: TextStyle(
                                color: ready ? const Color(0xFF7FFFB0) : Colors.white24,
                                fontSize: 12, fontWeight: FontWeight.w900)),
                      if (_isHost && !isMe)
                        InkWell(
                          onTap: () => _kick(docs[i].id, nick),
                          child: const Padding(
                            padding: EdgeInsets.only(left: 6, right: 2),
                            child: Icon(Icons.close, color: Colors.white24, size: 15),
                          ),
                        )
                      else
                        const SizedBox(width: 6),
                    ]),
                  );
                },
              ),
            ),
          ]),
        );
      },
    );
  }

  // 👑 길드장이 참가자를 목록에서 뺀다 — 접속이 끊겼는데 남아 있어 '전원 레디'가 안 될 때.
  Future<void> _kick(String uid, String nick) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14), side: const BorderSide(color: _kGold, width: 1.2)),
        title: const Text('참가자 빼기', style: TextStyle(color: _kGold, fontSize: 17, fontWeight: FontWeight.bold)),
        content: Text('$nick 님을 이번 레이드 참가자에서 뺄까요?\n\n접속이 끊겼는데 목록에 남아 있으면\n전원 레디가 안 돼 시작할 수 없어요.',
            style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.5)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false),
              child: const Text('취소', style: TextStyle(color: Colors.white54, fontWeight: FontWeight.bold))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _kGold, foregroundColor: Colors.black),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('빼기', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _roomRef.collection('participants').doc(uid).delete();
      _snack('$nick 님을 참가자에서 뺐어요.');
    } catch (e) {
      _snack('빼기에 실패했어요. 잠시 후 다시 시도해 주세요.');
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // 💬 [레이드 채팅] 레디해두고 기다리는 동안 대화가 안 됐다(셋팅창을 닫아야만 채팅 가능).
  //    길드 채팅(guilds/{gid}/chat)을 그대로 띄워 창을 닫지 않고 소통하게 한다.
  //    ⚠️ 새 컬렉션을 만들면 콘솔에서 관리하는 보안규칙을 건드려야 한다 — 기존 것 재사용이 안전.
  // ═══════════════════════════════════════════════════════════════
  Widget _chatPanel() {
    final col = FirebaseFirestore.instance
        .collection('guilds').doc(widget.guildId).collection('chat');
    return Container(
      height: 196,
      decoration: BoxDecoration(
        color: const Color(0xFF14110C).withOpacity(0.92),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kGold.withOpacity(0.55), width: 1.2),
      ),
      padding: const EdgeInsets.fromLTRB(12, 9, 10, 9),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('💬 길드 채팅', style: TextStyle(color: _kGold, fontSize: 14, fontWeight: FontWeight.w900)),
        const SizedBox(height: 5),
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: col.orderBy('timestamp', descending: true).limit(30).snapshots(),
            builder: (c, snap) {
              final docs = snap.data?.docs ?? [];
              if (docs.isEmpty) {
                return const Center(
                  child: Text('레이드 전에 인사 한마디! 🎣',
                      style: TextStyle(color: Colors.white24, fontSize: 12.5, fontWeight: FontWeight.w700)),
                );
              }
              return ListView.builder(
                reverse: true,
                itemCount: docs.length,
                itemBuilder: (c2, i) {
                  final d = docs[i].data();
                  final nick = (d['nickname'] ?? '?').toString();
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: RichText(
                      text: TextSpan(style: const TextStyle(fontSize: 12.5, height: 1.35), children: [
                        TextSpan(text: '$nick ',
                            style: TextStyle(
                                color: nick == widget.myNick ? _kGold : const Color(0xFF7FFFB0),
                                fontWeight: FontWeight.w900)),
                        TextSpan(text: (d['message'] ?? '').toString(),
                            style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w600)),
                      ]),
                    ),
                  );
                },
              );
            },
          ),
        ),
        const SizedBox(height: 5),
        SizedBox(
          height: 32,
          child: TextField(
            controller: _chatCtrl,
            focusNode: _chatFocus,
            maxLength: 60,
            style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w700),
            decoration: InputDecoration(
              counterText: '',
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              hintText: '메시지 입력 후 엔터',
              hintStyle: const TextStyle(color: Colors.white24, fontSize: 12.5),
              filled: true,
              fillColor: Colors.black38,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(9),
                  borderSide: BorderSide(color: _kGold.withOpacity(0.4))),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(9),
                  borderSide: BorderSide(color: _kGold.withOpacity(0.3))),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(9),
                  borderSide: BorderSide(color: _kGold.withOpacity(0.8))),
            ),
            onSubmitted: (_) => _sendChat(),
          ),
        ),
      ]),
    );
  }

  void _sendChat() {
    final raw = _chatCtrl.text.trim();
    if (raw.isEmpty) return;
    FirebaseFirestore.instance
        .collection('guilds').doc(widget.guildId).collection('chat')
        .add({
      'nickname': widget.myNick,
      'message': FishingLogic.cleanChat(raw), // 🛡️ 광장 채팅과 동일한 비속어 필터
      'timestamp': FieldValue.serverTimestamp(),
    });
    _chatCtrl.clear();
    _chatFocus.requestFocus(); // 연달아 쓰기 편하게 포커스 유지
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
      // 🐲 현재 도전 보스(1존부터 시작 · 클리어하면 다음 존이 기록돼 있음)
      'bossHp': (raidBossById(_bossId)['hp'] as num).toInt(),
      'bossId': _bossId,
      'bossTier': (raidBossById(_bossId)['tier'] as num).toInt(),
      'startedAt': FieldValue.serverTimestamp(),
      'memberCount': total,
    }, SetOptions(merge: true));
    // (onStart는 _watchRoom 리스너가 전원 공통으로 처리 → 길드장도 동일 경로로 입장)
  }

  // 🎒 내 장비 요약 — 자동장착이 고른 최상급 장비(레이드에 그대로 적용됨)
  Widget _myGearPanel() {
    if (_gearLoading || _gearList.isEmpty) return const SizedBox.shrink();
    return Container(
      width: 288,
      constraints: const BoxConstraints(maxHeight: 620),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: const Color(0xFF14110C).withOpacity(0.94),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kGold.withOpacity(0.75), width: 1.4),
        boxShadow: const [BoxShadow(color: Colors.black87, blurRadius: 16)],
      ),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Center(child: Text('🎒 내 장비',
            style: TextStyle(color: _kGold, fontSize: 19, fontWeight: FontWeight.w900))),
        const SizedBox(height: 3),
        const Center(child: Text('자동장착 — 최상급으로 적용됨',
            style: TextStyle(color: Colors.white38, fontSize: 12, fontWeight: FontWeight.w700))),
        const SizedBox(height: 10),
        Flexible(child: SingleChildScrollView(child: Column(children: [
          for (final g in _gearList) Padding(
            padding: const EdgeInsets.only(bottom: 7),
            child: Row(children: [
              Container(width: 46, height: 46,
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(9)),
                child: Padding(padding: const EdgeInsets.all(3),
                  child: Image.asset('assets/items/${g['icon']}', fit: BoxFit.contain,
                      errorBuilder: (a, b, c) => Image.asset('assets/images/${g['icon']}', fit: BoxFit.contain,
                          errorBuilder: (a2, b2, c2) => const Icon(Icons.inventory_2, color: Colors.white24, size: 24)))),
              ),
              const SizedBox(width: 9),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(g['slot'] as String, style: const TextStyle(color: Colors.white38, fontSize: 11.5, fontWeight: FontWeight.w700)),
                Text(g['name'] as String, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 14.5, fontWeight: FontWeight.w800)),
              ])),
            ]),
          ),
        ]))),
      ]),
    );
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

      // 👥💬 [왼쪽 열] 참가자 명단 + 길드 채팅 — 셋팅창을 닫지 않고도 누가 안 왔는지 보고 대화한다.
      //     (예전엔 레디 숫자만 보여서 누굴 불러야 할지 몰랐고, 채팅하려면 창을 닫아야 했다 — 2026-08-30)
      Positioned(
        left: 16, top: 92, bottom: 14, width: 268,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Flexible(child: _rosterPanel()),
          const SizedBox(height: 10),
          _chatPanel(),
        ]),
      ),

      // 🎒 [내 장비] 레이드에 실제로 쓰일 장비(자동장착 결과) — 셋팅 패널 왼쪽
      Positioned(
        right: 130, top: 92, bottom: 0, // 셋팅 패널 옆 + 우측상단 HUD(설정/내정보)와 안 겹치게 아래로
        child: Center(child: _myGearPanel()),
      ),

      // 🎣 [레이드 셋팅] 일반 낚시 '출조 셋팅'과 동일 구조 — 낚싯대 이미지 + 자동장착 + 레디 + 시작
      Center(
        child: SingleChildScrollView(
          child: Container(
            width: 430,
            margin: const EdgeInsets.symmetric(vertical: 60),
            padding: const EdgeInsets.fromLTRB(22, 18, 22, 18),
            decoration: BoxDecoration(
              color: const Color(0xFF14110C).withOpacity(0.94),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: _kGold, width: 1.6),
              boxShadow: const [BoxShadow(color: Colors.black87, blurRadius: 20)],
            ),
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _roomRef.collection('participants').snapshots(),
              builder: (c, ps) {
                final docs = ps.data?.docs ?? [];
                final total = docs.length;
                final readyCnt = docs.where((d) => d.data()['isReady'] == true).length;
                final allReady = total > 0 && readyCnt == total;
                final boss = raidBossById(_bossId); // 현재 도전 보스(클리어할수록 다음 존)
                final bool hasRod = _raidRod != null;
                // 💪 레디한 길드원들의 합산 제압력 (요구치 비교는 노출 안 함 — 심리적 포기 유발)
                int readyPower = 0;
                for (final d in docs) {
                  if (d.data()['isReady'] != true) continue;
                  final p = d.data()['power'];
                  if (p is num) readyPower += p.toInt();
                }

                return Column(mainAxisSize: MainAxisSize.min, children: [
                  const Text('🐲 레이드 셋팅',
                      style: TextStyle(color: _kGold, fontSize: 23, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 4),
                  Text('${boss['tier']}. ${boss['zone']} · ${boss['name']}',
                      style: const TextStyle(color: Colors.white54, fontSize: 13, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 12),
                  Divider(color: _kGold.withOpacity(0.25), height: 1),
                  const SizedBox(height: 12),

                  // 🎣 레이드 전용 낚싯대 (자동장착 버튼 위)
                  if (_gearLoading)
                    const Padding(padding: EdgeInsets.symmetric(vertical: 30),
                        child: CircularProgressIndicator(color: _kGold))
                  else if (hasRod) ...[
                    Container(
                      height: 118,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.04),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Image.asset('assets/items/${_raidRod!['icon']}', fit: BoxFit.contain,
                          errorBuilder: (a, b, c2) => const Icon(Icons.phishing, color: _kGold, size: 60)),
                    ),
                    const SizedBox(height: 8),
                    Text('${_raidRod!['name']}',
                        style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 3),
                    Text('💪 제압 ${_raidRod!['stats']?['P'] ?? 0}   🎯 컨트롤 ${_raidRod!['stats']?['C'] ?? 0}   📡 감도 ${_raidRod!['stats']?['S'] ?? 0}',
                        style: const TextStyle(color: _kGold, fontSize: 12.5, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text('⚔️ 내 총 제압력  $_myPower',
                        style: const TextStyle(color: Color(0xFF7FFFB0), fontSize: 14, fontWeight: FontWeight.w900)),
                  ] else ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
                      decoration: BoxDecoration(
                        color: Colors.black26, borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.orangeAccent.withOpacity(0.5)),
                      ),
                      child: const Column(children: [
                        Icon(Icons.warning_amber_rounded, color: Colors.orangeAccent, size: 34),
                        SizedBox(height: 6),
                        Text('레이드 전용 낚싯대가 없어요!\n길드 상점에서 먼저 구매해 주세요.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.orangeAccent, fontSize: 13.5, fontWeight: FontWeight.w800, height: 1.4)),
                      ]),
                    ),
                  ],
                  const SizedBox(height: 14),

                  // ⚡ 자동 장착
                  SizedBox(width: double.infinity, height: 46, child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black.withOpacity(0.6), foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: _kGold.withOpacity(0.7), width: 1.3)),
                    ),
                    onPressed: () => _autoEquipRaidRod(notify: true),
                    child: const Text('⚡ 자동 장착', style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w900)),
                  )),
                  const SizedBox(height: 8),

                  // ✅ 레디
                  StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                    stream: _roomRef.collection('participants').doc(_uid).snapshots(),
                    builder: (c2, s) {
                      final ready = s.data?.data()?['isReady'] == true;
                      return SizedBox(width: double.infinity, height: 50, child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: ready ? const Color(0xFF7FFFB0) : Colors.black.withOpacity(0.55),
                          foregroundColor: ready ? Colors.black : Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12),
                              side: const BorderSide(color: Color(0xFF7FFFB0), width: 1.4)),
                        ),
                        onPressed: hasRod ? () => _toggleReady(ready) : () => _snack('레이드 낚싯대가 있어야 참여할 수 있어요!'),
                        child: Text(ready ? '✅ 레디 완료 (탭하면 취소)' : '준비되면 레디!',
                            style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w900)),
                      ));
                    },
                  ),

                  // 🚀 시작 — '이 레이드를 연' 길드장/부길드장 한 명만. 나머지는 대기 안내.
                  if (_isHost) ...[
                    const SizedBox(height: 8),
                    SizedBox(width: double.infinity, height: 54, child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: allReady ? _kGold : _kGold.withOpacity(0.45),
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: _startRaid,
                      child: Text('🚀 레이드 시작!  (레디 $readyCnt/$total)',
                          style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w900)),
                    )),
                    const Padding(padding: EdgeInsets.only(top: 6),
                        child: Text('레이드를 연 길드장/부길드장만 시작할 수 있어요',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w700))),
                  ] else ...[
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      decoration: BoxDecoration(
                        color: Colors.black26, borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: Text(
                        _hostUid.isEmpty
                            ? '⏳ 길드장이 레이드를 열면 시작돼요'
                            : '⏳ 길드장의 시작을 기다리는 중...',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white60, fontSize: 14.5, fontWeight: FontWeight.w800)),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Text('🎣 모임 $total명   ·   ✅ 레디 $readyCnt / $total명',
                      style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 8),
                  // 💪 레디한 길드원 합산 제압력 (요구치·판정문구 미표시 — 심리적 포기 유발 방지)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.black38,
                      borderRadius: BorderRadius.circular(11),
                      border: Border.all(color: const Color(0xFF7FFFB0).withOpacity(0.55), width: 1.3),
                    ),
                    child: Text('💪 레디 길드원 합산 제압력  $readyPower',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Color(0xFF7FFFB0),
                            fontSize: 19, fontWeight: FontWeight.w900)),
                  ),
                ]);
              },
            ),
          ),
        ),
      ),
    ]);
  }
}
