// ignore_for_file: avoid_print
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
  String myNickname = '무명조사';
  bool _isSettling = false;
  bool _hasTransitioned = false;
  bool _popupShown = false;

  @override
  void initState() {
    super.initState();
    _setupLobby();
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

    FirebaseFirestore.instance.collection('arenas').doc(widget.roomId).snapshots().listen((snapshot) {
      if (!mounted) return;
      if (snapshot.exists) {
        String status = snapshot.data()?['status'] ?? 'waiting';
        if (status == 'playing' && !_hasTransitioned) _goToFishing();
        if (status == 'finished' && !_popupShown) {
          String winner = snapshot.data()?['winnerNick'] ?? '누군가';
          int prize = snapshot.data()?['totalPrize'] ?? 0;
          _showSettlementDialog(winner, prize);
        }
      }
    });
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
        .orderBy('score', descending: true)
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
        ),
      ),
    );
    // ... 이하 동일

    if (mounted && widget.roomData['hostId'] == FirebaseAuth.instance.currentUser?.uid) {
      _runAutomaticSettlement();
    }
    setState(() { _hasTransitioned = false; });
  }

  Future<void> _runAutomaticSettlement() async {
    if (_isSettling) return;
    setState(() => _isSettling = true);
    try {
      final arenaRef = FirebaseFirestore.instance.collection('arenas').doc(widget.roomId);
      final participantsSnap = await arenaRef.collection('participants').orderBy('score', descending: true).get();
      if (participantsSnap.docs.isEmpty) return;
      final winner = participantsSnap.docs.first;
      int prize = (widget.roomData['entryFee'] ?? 1000) * participantsSnap.docs.length;
      
      // 💰 [국세청 출동] 상금에서 10% 수수료 징수 계산!
      int taxAmount = (prize * 0.1).toInt();
      int finalPrize = prize - taxAmount;

      await FirebaseFirestore.instance.runTransaction((tx) async {
        // 1. 우승자 지갑(users)에는 세금을 뗀 '최종 금액(finalPrize)'만 꽂아줍니다!
        tx.update(FirebaseFirestore.instance.collection('users').doc(winner.id), {'gold': FieldValue.increment(finalPrize)});
        
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
    bool isHost = widget.roomData['hostId'] == FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
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
                      if (status == 'finished') {
                        return ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.grey.shade800),
                          onPressed: () async {
                            // 🧨 [핵심 수술] 방장(Host)이 방을 나갈 때 파이어베이스에서 방을 완전히 폭파(삭제)합니다!
                            if (isHost) {
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
                      
                      return isHost 
                        ? ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: kreftGold), onPressed: () => FirebaseFirestore.instance.collection('arenas').doc(widget.roomId).update({'status': 'playing'}), child: const Text('대회 시작 (START)', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 18)))
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
    );
  }
}