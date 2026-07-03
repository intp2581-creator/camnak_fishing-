// ignore_for_file: avoid_print, deprecated_member_use
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'ui_fishing.dart';
import 'package:firebase_auth/firebase_auth.dart';

// 👑 KREFT 아레나 공식 찐 황금색 (눈 아픈 샛노란색 컷!)
const Color kreftGold = Color(0xFFD4AF37);

class ArenaWaitingRoomScreen extends StatefulWidget {
  final Map<String, dynamic> roomData;
  final String roomId;

  const ArenaWaitingRoomScreen({super.key, required this.roomData, required this.roomId});

  @override
  State<ArenaWaitingRoomScreen> createState() => _ArenaWaitingRoomScreenState();
}

class _ArenaWaitingRoomScreenState extends State<ArenaWaitingRoomScreen> {
  final TextEditingController _chatController = TextEditingController();
  bool _leftRoom = false; // 방 나가기 정리 중복 방지
  bool _charged = false;  // 대회 시작 차감 1회만
  String _status = 'waiting'; // 현재 대회 상태(뒤로가기 확인용)
  String myNickname = '무명조사';
  bool _isSettling = false;
  bool _hasTransitioned = false;
  bool _popupShown = false;

  @override
  void initState() {
    super.initState();
    _setupLobby();
  }

  @override
  void dispose() {
    _leaveRoom(); // 🏠 화면 나갈 때 방 정리(방장이면 삭제/위임) — fire-and-forget
    _chatController.dispose();
    super.dispose();
  }

  // 🪙 대회 시작 시점에 '나 자신' 차감 (시간 600초 · 참가비 · 입장횟수, 필요 시 입장권 1장)
  Future<void> _chargeArenaEntry() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final ref = FirebaseFirestore.instance.collection('users').doc(uid);
    try {
      final data = (await ref.get()).data() ?? {};
      final today = DateTime.now().toString().substring(0, 10);
      final feeRaw = widget.roomData['entryFee'];
      final int fee = (feeRaw is num) ? feeRaw.toInt() : 0;
      final lastDate = (data['lastArenaDate'] ?? '').toString();
      final int arenaCount = (lastDate == today) ? ((data['arenaCount'] ?? 0) as num).toInt() : 0;
      final update = <String, dynamic>{
        'gold': FieldValue.increment(-fee),
        'lastArenaDate': today,
        'arenaCount': arenaCount + 1,
      };
      int timeCost = 600; // 기본: 낚시시간 10분 차감
      // 무료 2회 초과분은 입장권 1장 사용 → 입장권이 낚시시간 10분을 대신 충전(차감 상쇄)
      if (arenaCount >= 2) {
        final inv = List<dynamic>.from(data['inventory'] ?? []);
        final ti = inv.indexWhere((i) => (i['name'] ?? '') == '아레나 입장권');
        final int qty = ti >= 0 ? ((inv[ti]['quantity'] ?? 0) as num).toInt() : 0;
        if (qty > 0) {
          if (qty <= 1) { inv.removeAt(ti); } else { inv[ti]['quantity'] = qty - 1; }
          update['inventory'] = inv;
          update['arenaTicketDate'] = today;
          timeCost = 0; // 🎟️ 입장권이 낚시시간 10분을 채워줘서 시간 차감 없음(시간 없어도 참가 가능)
        }
      }
      update['remainingTime'] = FieldValue.increment(-timeCost);
      await ref.update(update);
    } catch (e) {
      debugPrint('아레나 시작 차감 에러: $e');
    }
  }

  // 🏠 대기실에서 나갈 때: 내 참가 삭제 + (방장이면) 방 삭제 또는 남은 사람에게 위임
  Future<void> _leaveRoom() async {
    if (_leftRoom) return;
    _leftRoom = true;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final arenaRef = FirebaseFirestore.instance.collection('arenas').doc(widget.roomId);
    try {
      final snap = await arenaRef.get();
      if (!snap.exists) return; // 이미 삭제된 방
      final status = (snap.data()?['status'] ?? 'waiting').toString();
      if (status != 'waiting') return; // 진행/종료 중이면 정산·기록 보존
      final amHost = (snap.data()?['hostId'] ?? '') == uid;
      await arenaRef.collection('participants').doc(uid).delete();
      final remain = await arenaRef.collection('participants').get();
      if (amHost) {
        if (remain.docs.isEmpty) {
          await arenaRef.delete(); // 방장 혼자였음 → 방 폭파
        } else {
          // 👑 남은 첫 참가자에게 방장 위임
          final next = remain.docs.first;
          await arenaRef.update({'hostId': next.id, 'currentPlayers': remain.docs.length});
          await arenaRef.collection('participants').doc(next.id)
              .set({'isHost': true, 'isReady': true}, SetOptions(merge: true));
          await arenaRef.collection('messages').add({
            'text': '👑 방장이 나가 [${next.data()['nickname'] ?? '조사'}]님이 새 방장이 되었습니다.',
            'sender': '시스템', 'createdAt': FieldValue.serverTimestamp(),
          });
        }
      } else {
        await arenaRef.update({'currentPlayers': remain.docs.length});
      }
    } catch (e) {
      debugPrint('아레나 나가기 정리 에러: $e');
    }
  }

  void _setupLobby() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
    if (userDoc.exists) {
      setState(() { myNickname = userDoc.data()?['nickname'] ?? '무명조사'; });
    }

    await FirebaseFirestore.instance.collection('arenas').doc(widget.roomId).collection('participants').doc(user.uid).set({
      'nickname': myNickname,
      'isReady': widget.roomData['hostId'] == user.uid,
      'joinedAt': FieldValue.serverTimestamp(),
      'isHost': widget.roomData['hostId'] == user.uid,
      'score': 0,
    }, SetOptions(merge: true));

    // 실제 참가자 수로 모집 인원 동기화(로비 표시용)
    try {
      final cnt = (await FirebaseFirestore.instance.collection('arenas').doc(widget.roomId).collection('participants').get()).docs.length;
      await FirebaseFirestore.instance.collection('arenas').doc(widget.roomId).update({'currentPlayers': cnt});
    } catch (_) {}

    FirebaseFirestore.instance.collection('arenas').doc(widget.roomId).snapshots().listen((snapshot) {
      if (!mounted) return;
      if (snapshot.exists) {
        String status = snapshot.data()?['status'] ?? 'waiting';
        _status = status;
        if (status == 'playing' && !_hasTransitioned) {
          if (!_charged) { _charged = true; _chargeArenaEntry(); } // 🪙 시작 시 각자 차감(시간·포인트·입장횟수)
          _goToFishing();
        }
        if (status == 'finished' && !_popupShown) {
          if (snapshot.data()?['voided'] == true) {
            _showVoidDialog(); // ⚔️ 참가자 부족(혼자) → 무효
          } else {
            String winner = snapshot.data()?['winnerNick'] ?? '누군가';
            int prize = snapshot.data()?['totalPrize'] ?? 0;
            _showSettlementDialog(winner, prize);
          }
        }
      }
    });
  }

  // 🔙 뒤로가기 확인 — 대기 중이면 "정말 나갈래?" 팝업(입장 1회 소진 안내)
  Future<bool> _confirmLeave() async {
    if (_status != 'waiting') return true; // 진행/종료 중이면 그냥 나감
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF2A2A2A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Colors.amber, width: 1.2)),
        contentPadding: const EdgeInsets.fromLTRB(28, 22, 28, 10),
        title: const Text('대기실 나가기', style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 24)),
        content: const Text('대기실에서 나가시겠어요?\n입장 1회는 이미 사용되어\n복구되지 않아요.\n\n(방장이면 방이 삭제되거나\n다른 참가자에게 넘어가요)', style: TextStyle(color: Colors.white, height: 1.6, fontSize: 18)),
        actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
        actions: [
          TextButton(
            style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14)),
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('머무르기', style: TextStyle(color: Colors.white60, fontSize: 17, fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14), textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('나가기'),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  // ⚔️ 대회 시작 가드 — 2명 이상 모여야 시작 가능(혼자 시작 방지)
  Future<void> _tryStartMatch() async {
    final arenaRef = FirebaseFirestore.instance.collection('arenas').doc(widget.roomId);
    final ps = await arenaRef.collection('participants').get();
    if (ps.docs.length < 2) {
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF2A2A2A),
          title: const Text('시작 불가', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
          content: const Text('대회는 2명 이상 모여야 시작할 수 있어요.\n다른 조사님이 입장하길 기다려주세요! 🎣', style: TextStyle(color: Colors.white, height: 1.5)),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('확인', style: TextStyle(color: Colors.amber)))],
        ),
      );
      return;
    }
    // ✅ 전원 준비 완료 확인(방장은 자동 준비)
    final notReady = ps.docs.where((d) => (d.data()['isReady'] != true)).length;
    if (notReady > 0) {
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF2A2A2A),
          title: const Text('시작 불가', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
          content: Text('아직 준비 안 된 참가자가 $notReady명 있어요.\n모두 "준비(READY)"를 눌러야 시작할 수 있어요! 🎣', style: const TextStyle(color: Colors.white, height: 1.5)),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('확인', style: TextStyle(color: Colors.amber)))],
        ),
      );
      return;
    }
    // ⏱️ 경기 종료 시각 기록(10분) — 정산은 이 시각 이후에만(조기 이탈로 조기정산 방지)
    await arenaRef.update({
      'status': 'playing',
      'playEndAt': DateTime.now().add(const Duration(seconds: 600)).millisecondsSinceEpoch,
    });
  }

  // ⚔️ 참가자 부족(혼자) → 무효 안내 + 참가비 환불됨
  void _showVoidDialog() {
    if (_popupShown) return;
    setState(() => _popupShown = true);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF2A2A2A),
        title: const Text('대회 무효 ⚠️', style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold)),
        content: const Text('참가자가 부족해 대회가 무효 처리되었어요.\n혼자서는 우승/보상이 없어요.\n참가비는 환불됩니다. 🙏', style: TextStyle(color: Colors.white, height: 1.5)),
        actions: [
          TextButton(
            onPressed: () { Navigator.pop(ctx); if (mounted) Navigator.pop(context); },
            child: const Text('나가기', style: TextStyle(color: Colors.amber)),
          ),
        ],
      ),
    );
  }

  void _showSettlementDialog(String winner, int prize) async {
    if (_popupShown) return;
    setState(() => _popupShown = true);

    // 1. 💰 [국세청 패치] 수수료 계산
    int taxAmount = (prize * 0.1).toInt();
    int finalPrize = prize - taxAmount;

    // 2. 🎣 [핵심 패치] 참가자들 세부 성적 불러오기!
    var participantsSnapshot = await FirebaseFirestore.instance
        .collection('arenas')
        .doc(widget.roomId)
        .collection('participants')
        .orderBy((widget.roomData['winCondition'] == '최대어') ? 'maxSize' : 'score', descending: true)
        .get();

    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: Colors.amber, width: 2)),
        title: const Column(children: [Icon(Icons.emoji_events, color: Colors.amber, size: 50), SizedBox(height: 10), Text('🏆 대회 정산 완료', style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold))]),
        content: SizedBox(
          width: 400,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('우승자: [$winner]', style: const TextStyle(color: Colors.amber, fontSize: 22, fontWeight: FontWeight.bold)),
                const Divider(color: Colors.white24, height: 30),
                
                // 📋 [참가자 상세 내역]
                const Text('📊 참가자 상세 성적', style: TextStyle(color: Colors.white70, fontSize: 14)),
                const SizedBox(height: 10),
                ...participantsSnapshot.docs.map((doc) {
                  var data = doc.data();
                  String name = data['nickname'] ?? '무명';
                  var score = data['score'] ?? 0;
                  var maxSize = data['maxSize'] ?? 0.0;
                  
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(name, style: const TextStyle(color: Colors.white, fontSize: 16)),
                        Text(widget.roomData['winCondition'] == '최대어' ? '$maxSize cm' : '$score 마리', 
                             style: const TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold, fontSize: 16)),
                      ],
                    ),
                  );
                }),
                
                const Divider(color: Colors.white24, height: 30),
                
                // 💸 [세금 명세서]
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.white24)),
                  child: Column(
                    children: [
                      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('총 상금:', style: TextStyle(color: Colors.grey)), Text('${prize}P', style: const TextStyle(color: Colors.grey))]),
                      const SizedBox(height: 6),
                      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('운영 수수료 (10%):', style: TextStyle(color: Colors.redAccent)), Text('-${taxAmount}P', style: const TextStyle(color: Colors.redAccent))]),
                      const Divider(color: Colors.white24, height: 20),
                      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('우승자 지급액:', style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold)), Text('${finalPrize}P', style: const TextStyle(color: Colors.amber, fontSize: 18, fontWeight: FontWeight.bold))]),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          Center(
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.amber, foregroundColor: Colors.black),
              onPressed: () {
                Navigator.pop(ctx);
                // 🏠 다 보고 나면 대기실에서 나갈 수 있게 처리
                if (widget.roomData['hostId'] == FirebaseAuth.instance.currentUser?.uid) {
                  FirebaseFirestore.instance.collection('arenas').doc(widget.roomId).delete();
                }
                Navigator.pop(context);
              }, 
              child: const Text('확인', style: TextStyle(fontWeight: FontWeight.bold))
            )
          )
        ],
      ),
    );
  }

  void _goToFishing() async {
    setState(() { _hasTransitioned = true; _popupShown = false; });
    
    // 💡 [수술 1] 사장님 DB의 모든 낚시터를 다 넣어주는 만능 지도입니다!
    final Map<String, String> locationMap = {
      '예산 예당지': 'assets/fields/bg_yedang.jpg', '안성 고삼지': 'assets/fields/bg_gosam.jpg',
      '진천 백곡지': 'assets/fields/bg_baekgok.jpg', '춘천 파로호': 'assets/fields/bg_paro.jpg',
      '충주 충주호': 'assets/fields/bg_chungju.jpg', '예산 신양수로': 'assets/fields/bg_sinyang.jpg',
      '청양 지천': 'assets/fields/bg_jicheon.jpg', '인천 청라수로': 'assets/fields/bg_chungla.jpg',
      '해남 금자천': 'assets/fields/bg_gumja.jpg', '충주 달천': 'assets/fields/bg_dalchun.jpg',
      '통영 척포 갯바위': 'assets/fields/bg_chukpo.jpg', '신안 가거도': 'assets/fields/bg_gageo.jpg',
      '완도 청산도': 'assets/fields/bg_cheongsan.jpg', '여수 거문도': 'assets/fields/bg_geumo.jpg',
      '제주 섶섬': 'assets/fields/bg_seop.jpg', '거제 선상': 'assets/fields/bg_geo_ship.jpg',
      '오천항 선상': 'assets/fields/bg_ocheon_ship.jpg', '대천 선상': 'assets/fields/bg_daecheon_ship.jpg',
      '통영 선상': 'assets/fields/bg_tong_ship.jpg', '완도 선상': 'assets/fields/bg_wando_ship.jpg',
    };

    String locName = widget.roomData['locationName'] ?? '예산 예당지';
    String bgPath = locationMap[locName] ?? 'assets/fields/bg_yedang.jpg';

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => FishingScreen(
          nickname: myNickname,
          locationName: locName,  
          winCondition: widget.roomData['winCondition'] ?? '마릿수',
          title: widget.roomData['title'] ?? '아레나',
          bgImagePath: bgPath, 
          characterImagePath: 'assets/images/char_beginner.png',
          isSea: widget.roomData['type'] == '바다',
          roomId: widget.roomId,
          targetFish: widget.roomData['targetFish']?.toString(), // ⚔️ 최대어 대상 어종
        ),
      ),
    );
    // 낚시에서 돌아옴 → 정산 시도(누구나. 단, 경기 시간 끝난 뒤에만 실제 정산됨)
    // _hasTransitioned는 true로 유지 → 경기 도중 돌아온(이탈) 사람이 다시 낚시로 끌려가지 않음
    if (mounted) _runAutomaticSettlement();
  }

  Future<void> _runAutomaticSettlement() async {
    if (_isSettling) return;
    final arenaRef = FirebaseFirestore.instance.collection('arenas').doc(widget.roomId);
    // ⏱️ 경기 시간이 끝났을 때만 정산 (조기 이탈자가 트리거해도 시간 전이면 무시 → 남은 사람은 계속)
    try {
      final aSnap = await arenaRef.get();
      if (!aSnap.exists) return;
      if ((aSnap.data()?['status'] ?? '') != 'playing') return; // 이미 정산됨/종료됨
      final playEndAt = (aSnap.data()?['playEndAt'] is num) ? (aSnap.data()!['playEndAt'] as num).toInt() : 0;
      if (playEndAt > 0 && DateTime.now().millisecondsSinceEpoch < playEndAt - 1500) return; // 아직 경기 중
    } catch (_) { return; }
    setState(() => _isSettling = true);
    try {
      final orderField = (widget.roomData['winCondition'] == '최대어') ? 'maxSize' : 'score';
      final allSnap = await arenaRef.collection('participants').orderBy(orderField, descending: true).get();
      if (allSnap.docs.isEmpty) return;
      // ⚔️ 실격(도중 이탈) 제외
      final valid = allSnap.docs.where((d) => (d.data() as Map)['forfeit'] != true).toList();

      final feeRaw = widget.roomData['entryFee'];
      final fee = (feeRaw is num) ? feeRaw.toInt() : 0;

      // 완주자(실격 아닌 사람)가 없으면 무효
      if (valid.isEmpty) {
        await arenaRef.update({'status': 'finished', 'voided': true, 'winnerNick': '', 'totalPrize': 0});
        await arenaRef.collection('messages').add({'text': '⚠️ 완주한 참가자가 없어 대회가 무효 처리되었습니다.', 'sender': '시스템', 'createdAt': FieldValue.serverTimestamp()});
        return;
      }
      // 처음부터 혼자였던 방(참가자 1명) → 무효 + 참가비 환불
      if (allSnap.docs.length < 2) {
        final soloId = allSnap.docs.first.id;
        await FirebaseFirestore.instance.runTransaction((tx) async {
          tx.update(arenaRef, {'status': 'finished', 'voided': true, 'winnerNick': '', 'totalPrize': 0});
          if (fee > 0) {
            tx.update(FirebaseFirestore.instance.collection('users').doc(soloId), {'gold': FieldValue.increment(fee)});
          }
        });
        await arenaRef.collection('messages').add({'text': '⚠️ 참가자가 부족해 대회가 무효 처리되었습니다. (참가비 환불)', 'sender': '시스템', 'createdAt': FieldValue.serverTimestamp()});
        return;
      }

      final winner = valid.first; // 완주자 중 1위(최대어=maxSize / 마릿수=score)
      final participantsSnap = allSnap;
      int prize = (widget.roomData['entryFee'] ?? 1000) * participantsSnap.docs.length;
      
      // 💰 [국세청 출동] 상금에서 10% 수수료 징수 계산!
      int taxAmount = (prize * 0.1).toInt();
      int finalPrize = prize - taxAmount;
      final todayKst = DateTime.now().toIso8601String().substring(0, 10);

      await FirebaseFirestore.instance.runTransaction((tx) async {
        // 1. 우승자 지갑(users)에는 세금을 뗀 '최종 금액(finalPrize)'만 꽂아줍니다!
        //    + 🥊 한별 아레나 일일 퀘스트: 오늘 승리 기록(광장에서 보상 정산)
        tx.update(FirebaseFirestore.instance.collection('users').doc(winner.id), {
          'gold': FieldValue.increment(finalPrize),
          'hanbyeol_won_date': todayKst,
        });
        
        // 2. 대회 기록(arenas)에는 '원래 총상금(prize)'을 적어둬야 아까 만든 영수증 팝업이 세금 명세서를 예쁘게 그립니다.
        tx.update(arenaRef, {'status': 'finished', 'winnerNick': winner['nickname'], 'totalPrize': prize});
      });
      
      // 3. 채팅창 시스템 메시지도 '세금 뗀 실제 획득 금액'으로 안내!
      await arenaRef.collection('messages').add({'text': '🏆 [정산 완료] ${winner['nickname']}님 ${finalPrize}P 획득! (수수료 제외)', 'sender': '시스템', 'createdAt': FieldValue.serverTimestamp()});
    } catch (e) { print("정산 에러: $e"); }
    finally { if (mounted) setState(() => _isSettling = false); }
  }

  void _sendMessage() async {
    if (_chatController.text.trim().isEmpty) return;
    String text = _chatController.text.trim();
    _chatController.clear();
    await FirebaseFirestore.instance.collection('arenas').doc(widget.roomId).collection('messages').add({'text': text, 'sender': myNickname, 'createdAt': FieldValue.serverTimestamp()});
  }

  @override
  Widget build(BuildContext context) {

    return WillPopScope(
      onWillPop: _confirmLeave,
      child: Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text(widget.roomData['title'] ?? '방 제목', style: const TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: Column(
        children: [
          // 💡 [수술 1] 상단 정보창을 가로로 시원하게 배치!
Container(
  width: double.infinity,
  margin: const EdgeInsets.all(15),
  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
  decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.white12)),
  child: Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween, // 양쪽 끝으로 배치!
    children: [
      Text('[${widget.roomData['type']}] ${widget.roomData['winCondition'] ?? '마릿수전'}', 
           style: const TextStyle(color: kreftGold, fontWeight: FontWeight.bold, fontSize: 18)), // 📈 글자 크기 UP!
      StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('arenas').doc(widget.roomId).collection('participants').snapshots(),
        builder: (context, snapshot) {
          int count = snapshot.hasData ? snapshot.data!.docs.length : 1;
          int total = (widget.roomData['entryFee'] ?? 0) * count;
          return Row(
            children: [
              const Icon(Icons.monetization_on, color: kreftGold, size: 20),
              Text(' 참가비: ${widget.roomData['entryFee']}P ', style: const TextStyle(color: Colors.white, fontSize: 18)),
              const Text('|', style: TextStyle(color: Colors.white24, fontSize: 18)),
              const Icon(Icons.emoji_events, color: kreftGold, size: 20),
              Text(' 총상금: ${total}P', style: const TextStyle(color: kreftGold, fontSize: 18, fontWeight: FontWeight.bold)),
            ],
          );
        },
      ),
    ],
  ),
),

          // 참가자 명단
          Container(
            height: 140, // 💡 전체 명단 칸 높이 대폭 확장!
            decoration: const BoxDecoration(color: Colors.black, border: Border(bottom: BorderSide(color: Colors.white12))),
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('arenas').doc(widget.roomId).collection('participants').orderBy('joinedAt').snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const SizedBox();
                final users = snapshot.data!.docs;
                return ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  itemCount: users.length,
                  itemBuilder: (context, index) {
                    var u = users[index].data() as Map<String, dynamic>;
                    bool ready = u['isReady'] ?? false;
                    bool host = u['isHost'] ?? false;

                    // 🎨 [핵심 변경] char_ -> skin_ 으로 변경, 확장자는 .jpg 로 통일!
                    String userSkinImagePath = 'assets/images/skin_beginner.jpg';
                    if (u.containsKey('equippedSkin') && u['equippedSkin'] != null) {
                      var skin = u['equippedSkin'];
                      String skinName = (skin is Map) ? (skin['name'] ?? '').toString() : skin.toString();
                      
                      if (skinName.contains('신')) {
                        userSkinImagePath = 'assets/images/skin_god.jpg';
                      } else if (skinName.contains('전설')) {
                        userSkinImagePath = 'assets/images/skin_legend.jpg';
                      } else if (skinName.contains('마스터')) {
                        userSkinImagePath = 'assets/images/skin_master.jpg';
                      } else if (skinName.contains('프로')) {
                        userSkinImagePath = 'assets/images/skin_pro.jpg';
                      } else if (skinName.contains('전문') || skinName.contains('고수')) {
                        userSkinImagePath = 'assets/images/skin_expert.jpg';
                      } else if (skinName.contains('중수')) {
                        userSkinImagePath = 'assets/images/skin_intermediate.jpg';
                      } else if (skinName.contains('하수')) {
                        userSkinImagePath = 'assets/images/skin_novice.jpg';
                      }
                    }

                    return Container(
                      width: 120, // 💡 개인 카드 너비 펌핑!
                      margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                      decoration: BoxDecoration(
                        color: host ? kreftGold.withValues(alpha: 0.1) : Colors.white10, 
                        border: Border.all(color: host ? kreftGold : (ready ? Colors.green : Colors.grey.shade700), width: 2.0), 
                        borderRadius: BorderRadius.circular(12)
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center, 
                        children: [
                          // 🎨 스킨 얼굴 크기 대폭 확대! (65x65)
                          Container(
                            width: 65, height: 65,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: host ? kreftGold : (ready ? Colors.green : Colors.white24), width: 2.5),
                              image: DecorationImage(
                                image: AssetImage(userSkinImagePath), 
                                fit: BoxFit.cover, 
                                alignment: const Alignment(0.0, -0.75),
                              )
                            ),
                          ),
                          const SizedBox(height: 8),
                          // 👑 닉네임과 방장 왕관
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (host) const Icon(Icons.workspace_premium, size: 18, color: kreftGold),
                              if (host) const SizedBox(width: 4),
                              Flexible( 
                                child: Text(
                                  u['nickname'] ?? '...', 
                                  style: TextStyle(color: host ? kreftGold : Colors.white, fontSize: 16, fontWeight: host ? FontWeight.bold : FontWeight.normal), 
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ],
                          ),
                        ]
                      ),
                    );
                  },
                );
              },
            ),
          ),

          // 💡 채팅창 (낚시터 메시지 통합 & 시스템 글씨색 복구!)
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('arenas').doc(widget.roomId).collection('messages').orderBy('createdAt', descending: true).snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const SizedBox();
                final docs = snapshot.data!.docs;
                return ListView.builder(
                  reverse: true, padding: const EdgeInsets.all(15),
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    var m = docs[index].data() as Map<String, dynamic>;
                    
                    // 🧨 1. [핵심 수술] 낚시터(message/nickname)와 대기실(text/sender) 변수 이름 통합!
                    String msgText = m['text'] ?? m['message'] ?? '';
                    String msgSender = m['sender'] ?? m['nickname'] ?? '무명조사';
                    
                    // 🧨 2. '시스템'이거나 '캠피싱'이면 무조건 가운데 정렬(시스템 팝업)로 처리!
                    bool isSystem = (msgSender == '시스템' || msgSender == '캠피싱');
                    bool isMe = msgSender == myNickname;

                    return Align(
                      alignment: isSystem ? Alignment.center : (isMe ? Alignment.centerRight : Alignment.centerLeft),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: Column(
                          crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                          children: [
                            if (!isSystem && !isMe)
                              Padding(padding: const EdgeInsets.only(left: 4, bottom: 4), child: Text(msgSender, style: const TextStyle(color: Colors.white60, fontSize: 12))),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(
                                color: isSystem ? Colors.black54 : (isMe ? kreftGold : Colors.white),
                                borderRadius: BorderRadius.only(topLeft: const Radius.circular(15), topRight: const Radius.circular(15), bottomLeft: Radius.circular(isMe || isSystem ? 15 : 0), bottomRight: Radius.circular(!isMe || isSystem ? 15 : 0)),
                                border: isSystem ? Border.all(color: kreftGold) : null,
                              ),
                              // 🧨 3. [핵심 수술] 시스템 메시지면 글씨를 황금색으로! 일반 채팅은 검정색으로!
                              child: Text(msgText, style: TextStyle(color: isSystem ? kreftGold : Colors.black, fontSize: 15, fontWeight: FontWeight.w500)),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),

          // 하단 입력창 및 컨트롤
          Container(
            padding: const EdgeInsets.all(12), color: Colors.black,
            child: Column(children: [
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: _chatController, 
                    style: const TextStyle(color: Colors.white), 
                    textInputAction: TextInputAction.send, 
                    onSubmitted: (_) => _sendMessage(), // 👈 엔터키 완벽 작동!
                    decoration: InputDecoration(
                      hintText: '메시지 입력...', 
                      filled: true, 
                      fillColor: Colors.white10, 
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(25), borderSide: BorderSide.none)
                    )
                  )
                ),
                const SizedBox(width: 8),
                CircleAvatar(backgroundColor: kreftGold, child: IconButton(icon: const Icon(Icons.send, color: Colors.black, size: 20), onPressed: _sendMessage)),
              ]),
              const SizedBox(height: 15),
              Center(
                child: SizedBox(
                  width: 250, height: 50,
                  child: StreamBuilder<DocumentSnapshot>(
                    stream: FirebaseFirestore.instance.collection('arenas').doc(widget.roomId).snapshots(),
                    builder: (context, snap) {
                      String status = snap.data?['status'] ?? 'waiting';
                      // 👑 실시간 방장 판정(위임되면 새 방장에게 START 버튼이 감)
                      final bool liveIsHost = snap.data?['hostId'] == FirebaseAuth.instance.currentUser?.uid;
                      if (status == 'finished') {
                        return ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.grey.shade800),
                          onPressed: () async {
                            // 🧨 [핵심 수술] 방장(Host)이 방을 나갈 때 파이어베이스에서 방을 완전히 폭파(삭제)합니다!
                            if (liveIsHost) {
                              try {
                                await FirebaseFirestore.instance.collection('arenas').doc(widget.roomId).delete();
                              } catch (e) {
                                print("방 폭파 에러: $e");
                              }
                            }
                            // 화면 닫고 대기실 목록으로 돌아가기
                            if (context.mounted) Navigator.pop(context);
                          },
                          child: const Text('대회 종료 (나가기)', style: TextStyle(color: Colors.white)),
                        );
                      }
                      
                      return liveIsHost
                        ? ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: kreftGold), onPressed: _tryStartMatch, child: const Text('대회 시작 (START)', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 18)))
                        : StreamBuilder<DocumentSnapshot>(
                            stream: FirebaseFirestore.instance.collection('arenas').doc(widget.roomId).collection('participants').doc(FirebaseAuth.instance.currentUser?.uid).snapshots(),
                            builder: (context, pSnap) {
                              bool isReady = pSnap.data?['isReady'] ?? false;
                              return ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: isReady ? Colors.green : Colors.grey.shade700), onPressed: () => FirebaseFirestore.instance.collection('arenas').doc(widget.roomId).collection('participants').doc(FirebaseAuth.instance.currentUser?.uid).update({'isReady': !isReady}), child: Text(isReady ? '준비 완료 (READY)' : '준비(READY) 하기', style: const TextStyle(color: Colors.white, fontSize: 16)));
                            },
                          );
                    },
                  ),
                ),
              ),
            ]),
          ),
        ],
      ),
    ));
  }
}