// ignore_for_file: use_build_context_synchronously, avoid_print, deprecated_member_use, unnecessary_const
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'ui_arena_waiting.dart';
import 'game_config.dart';

class ArenaScreen extends StatefulWidget {
  const ArenaScreen({super.key});

  @override
  State<ArenaScreen> createState() => _ArenaScreenState();
}

class _ArenaScreenState extends State<ArenaScreen> {
  // 🎟️ 아레나 입장 판정: 무료 2회 + (입장권으로 하루 1회 추가)
  //   반환 null=입장 불가(팝업 표시됨) / {}=무료 입장 / {inventory,arenaTicketDate}=입장권 사용
  Future<Map<String, dynamic>?> _resolveArenaEntry(BuildContext ctx, Map<String, dynamic> userData, String today, int arenaCount) async {
    if (arenaCount < 2) return {}; // 무료 입장
    final String ticketDate = (userData['arenaTicketDate'] ?? '').toString();
    final bool usedTicketToday = ticketDate == today;
    final inv = List<dynamic>.from(userData['inventory'] ?? []);
    final ti = inv.indexWhere((i) => (i['name'] ?? '') == '아레나 입장권');
    final int qty = ti >= 0 ? ((inv[ti]['quantity'] ?? 0) as num).toInt() : 0;

    if (arenaCount >= 3 || usedTicketToday) {
      _arenaInfo(ctx, '입장 제한', '오늘 대회 참가(무료 2회 + 입장권 1회)를\n모두 사용하셨어요.\n내일 다시 도전해주세요! 🎣');
      return null;
    }
    if (qty <= 0) {
      _arenaInfo(ctx, '무료 입장 소진', '오늘 무료 입장 2회를 모두 쓰셨어요.\n\n상점에서 "아레나 입장권"을 구매하면\n하루 1회 더 참가할 수 있어요! 🎟️');
      return null;
    }
    final ok = await showDialog<bool>(
      context: ctx,
      builder: (c) => AlertDialog(
        backgroundColor: const Color(0xFF2A2A2A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Color(0xFFD4AF37), width: 1.2)),
        title: const Text('아레나 입장권 사용', style: TextStyle(color: Color(0xFFD4AF37), fontWeight: FontWeight.bold, fontSize: 22)),
        content: Text('오늘 무료 2회를 다 쓰셨어요.\n입장권 1장을 써서 한 번 더 참가할까요?\n(하루 1장 사용 · 보유 $qty장)', style: const TextStyle(color: Colors.white, fontSize: 18, height: 1.6)),
        actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('취소', style: TextStyle(color: Colors.white60, fontSize: 17, fontWeight: FontWeight.bold))),
          ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFD4AF37), foregroundColor: Colors.black, padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14), textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)), onPressed: () => Navigator.pop(c, true), child: const Text('입장권 사용')),
        ],
      ),
    );
    if (ok != true) return null;
    if (qty <= 1) { inv.removeAt(ti); } else { inv[ti]['quantity'] = qty - 1; }
    return {'inventory': inv, 'arenaTicketDate': today};
  }

  void _arenaInfo(BuildContext ctx, String title, String msg) {
    showDialog(
      context: ctx,
      builder: (c) => AlertDialog(
        backgroundColor: const Color(0xFF2A2A2A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Colors.redAccent, width: 1.2)),
        title: Text(title, style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 22)),
        content: Text(msg, style: const TextStyle(color: Colors.white, fontSize: 18, height: 1.6)),
        actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        actions: [Center(child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.amber, foregroundColor: Colors.black, padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 13), textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)), onPressed: () => Navigator.pop(c), child: const Text('확인')))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1E1E1E),
      appBar: AppBar(
        backgroundColor: Colors.black87,
        title: const Text(
          '🏆 KREFT 아레나',
          // 📈 [수정] 타이틀 폰트 크기를 26으로 떡상!!
          style: TextStyle(color: Color(0xFFD4AF37), fontWeight: FontWeight.bold, fontSize: 30), 
        ),
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16), // 📈 상하 여백도 빵빵하게!
            color: Colors.grey.shade900,
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.campaign, color: Colors.amber, size: 28), // 📈 확성기 아이콘도 키움!
                SizedBox(width: 10),
                Text(
                  '대회 입장 시 캠핑피싱 최상급 장비 자동 착용!',
                  // 📈 [수정] 안내 문구 폰트 크기를 18로 떡상!!
                  style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 20), 
                ),
              ],
            ),
          ),

          // 🚀 [수술 1] 파이어베이스 인덱스 에러 우회 + 로비 노출 완벽 처리!

          // 🚀 [수술 1] 파이어베이스 인덱스 에러 우회 + 로비 노출 완벽 처리!
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('arenas').where('status', isEqualTo: 'waiting').snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(child: Text('데이터 오류: ${snapshot.error}', style: const TextStyle(color: Colors.redAccent)));
                }

                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(color: Color(0xFFD4AF37)));
                }

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // 💡 큼직한 확성기 배경 아이콘 추가! (빈 공간 채우기 용도)
                        const Icon(Icons.campaign_outlined, size: 120, color: Colors.white12), 
                        const SizedBox(height: 30),
                        const Text(
                          '현재 대기 중인 대회가 없습니다.\n직접 대회를 개최해 보세요!',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white70, 
                            fontSize: 26, // 📈 폰트 16 -> 26 떡상!!
                            fontWeight: FontWeight.bold, 
                            height: 1.5
                          ), 
                        ),
                      ],
                    ),
                  );
                }

                var docs = snapshot.data!.docs.toList();
                docs.sort((a, b) {
                  var aData = a.data() as Map<String, dynamic>;
                  var bData = b.data() as Map<String, dynamic>;
                  var aTime = aData['createdAt'] as Timestamp?;
                  var bTime = bData['createdAt'] as Timestamp?;
                  
                  if (aTime == null && bTime == null) return 0;
                  if (aTime == null) return -1; 
                  if (bTime == null) return 1;
                  return bTime.compareTo(aTime); 
                });

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    var data = docs[index].data() as Map<String, dynamic>;
                    String hostName = data['hostName'] ?? '알 수 없음';
                    
                    return Card(
                      color: Colors.grey.shade900,
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(
                        side: const BorderSide(color: Colors.white12, width: 1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ListTile(
                        leading: const Icon(Icons.emoji_events, color: Color(0xFFD4AF37), size: 40),
                        title: Text(data['title'] ?? '아레나 대회', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Text(
                            '[${data['type'] ?? '민물'}] ${data['winCondition'] ?? '마릿수전'} | 참가비: ${data['entryFee'] ?? 1000}P\n모집: ${data['currentPlayers'] ?? 1}/${data['maxPlayers'] ?? 5}명 | 시간: 10분 | 개설자: $hostName',
                            style: const TextStyle(color: Colors.grey, height: 1.4, fontSize: 13),
                          ),
                        ),
                        trailing: ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFD4AF37), foregroundColor: Colors.black),
                          onPressed: () async {
                            final user = FirebaseAuth.instance.currentUser;
                            if (user == null) return;

                            bool isHost = data['hostId'] == user.uid;
                            if (isHost) {
                              Navigator.push(context, MaterialPageRoute(builder: (context) => ArenaWaitingRoomScreen(roomData: data, roomId: docs[index].id)));
                              return; 
                            }

                            int requiredFee = data['entryFee'] ?? 1000;
                            String today = DateTime.now().toString().substring(0, 10);
                            var docRef = FirebaseFirestore.instance.collection('users').doc(user.uid);
                            var docSnap = await docRef.get();
                            
                            if (!docSnap.exists) return;
                            var userData = docSnap.data()!;
                            int myGold = userData['gold'] ?? 0;
                            int myTime = userData['remainingTime'] ?? 3600;
                            String lastArenaDate = userData['lastArenaDate'] ?? '';
                            int arenaCount = userData['arenaCount'] ?? 0;

                            if (lastArenaDate != today) arenaCount = 0;

                            final ticketExtra = await _resolveArenaEntry(context, userData, today, arenaCount);
                            if (ticketExtra == null) return; // 입장 불가(무료소진·입장권없음/이미사용 → 팝업 표시됨)
                            if (myGold < requiredFee) {
                              if (!context.mounted) return;
                              showDialog(context: context, builder: (ctx) => AlertDialog(backgroundColor: const Color(0xFF2A2A2A), title: const Text('잔액 부족 😅', style: TextStyle(color: Colors.redAccent)), content: Text('참가비가 부족합니다.\n(보유: $myGold P)', style: const TextStyle(color: Colors.white)), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('확인', style: TextStyle(color: Colors.amber)))]));
                              return;
                            }
                            if (myTime < 600) {
                              if (!context.mounted) return;
                              showDialog(context: context, builder: (ctx) => AlertDialog(backgroundColor: const Color(0xFF2A2A2A), title: const Text('시간 부족 ⏳', style: TextStyle(color: Colors.redAccent)), content: const Text('대회에 참가하려면 최소 10분의 낚시 시간이 필요합니다.', style: const TextStyle(color: Colors.white)), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('확인', style: TextStyle(color: Colors.amber)))]));
                              return;
                            }

                            await docRef.update({
                              'gold': myGold - requiredFee,
                              'remainingTime': myTime - 600,
                              'lastArenaDate': today,
                              'arenaCount': arenaCount + 1,
                              ...ticketExtra, // 입장권 사용 시 inventory/arenaTicketDate 반영
                            });
                            remainingTimeNotifier.value -= 600; 

                            if (!context.mounted) return;
                            Navigator.push(context, MaterialPageRoute(builder: (context) => ArenaWaitingRoomScreen(roomData: data, roomId: docs[index].id)));
                          },
                          child: const Text('입장', style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),

          Padding(
            // 💡 좌우 여백을 빼고, 아래쪽 여백만 깔끔하게 남깁니다!
            padding: const EdgeInsets.only(bottom: 40.0),
            child: Center(
              child: SizedBox(
                width: 350, // 📉 무한대(double.infinity)에서 350으로 다이어트! (스낵바 탈출!)
                height: 65, // 📉 높이도 80에서 65로 슬림해집니다!
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFD4AF37),
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(35)), // 양옆을 더 둥글고 예쁘게!
                    elevation: 5, // 💡 버튼에 그림자를 살짝 줘서 스낵바가 아니라 진짜 버튼처럼 보이게!
                  ),
                  onPressed: () {
                    _showCreateRoomDialog(context);
                  },
                  // 📉 글씨 크기도 너무 부담스럽지 않게 26 -> 22로 밸런스 패치!
                  child: const Text('대회 개설하기 (방 만들기)', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showCreateRoomDialog(BuildContext context) {
    // 🌟 1. 방 이름 비워두기 (직접 입력 유도)
    final TextEditingController nameController = TextEditingController();

    // 🌟 2. 맵 리스트 (사장님 DB 'locations' 완벽 반영!)
    final List<String> freshwaterLocations = ['예산 예당지', '안성 고삼지', '진천 백곡지', '춘천 파로호', '충주 충주호', '예산 신양수로', '청양 지천', '인천 청라수로', '해남 금자천', '충주 달천'];
    final List<String> saltwaterLocations = ['통영 척포 갯바위', '신안 가거도', '완도 청산도', '여수 거문도', '제주 섶섬', '거제 선상', '오천항 선상', '대천 선상', '통영 선상', '완도 선상'];

    // 🌟 3. 대상 어종 리스트 (사장님 DB 'fwFishPool', 'seaFishPool' 완벽 반영!)
    final List<String> freshwaterFish = ['모든 어종', '붕어', '떡붕어', '블루길', '살치', '베스', '강준치', '잉어', '자라', '메기', '가물치'];
    final List<String> saltwaterFish = ['모든 어종', '고등어', '우럭', '갈치', '참돔', '벵에돔', '갑오징어', '주꾸미', '광어', '감성돔', '문어', '참치'];
    
    // 초기 상태 세팅
    String selectedType = '민물';
    String selectedLocation = freshwaterLocations[0];
    String winCondition = '마릿수';
    String selectedTargetFish = freshwaterFish[0];

    double timeMin = 10.0;
    double maxPlayers = 5.0; // 🌟 최대 인원 5명으로 밸런스 패치!
    int entryFee = 500; // 🌟 참가비 500P부터 시작!

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF2A2A2A),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              title: const Row(
                children: [
                  Icon(Icons.settings, color: Color(0xFFD4AF37)),
                  SizedBox(width: 8),
                  Text('대회장 설정', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ],
              ),
              // 💡 [핵심 패치] 팝업창 가로 크기를 450으로 쫙 늘려서 시원하게 만듭니다!
              content: SizedBox(
                width: 450, 
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // --- [방 이름 입력] ---
                      const Text('대회장 이름', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      TextField(
                        controller: nameController,
                        style: const TextStyle(color: Colors.white, fontSize: 16),
                        decoration: InputDecoration(
                          hintText: '대회장 제목을 필수로 입력하세요!', 
                          hintStyle: const TextStyle(color: Colors.white38),
                          filled: true,
                          fillColor: Colors.black26,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // --- [낚시 종류 & 낚시터 선택] ---
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('낚시 종류', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                                DropdownButton<String>(
                                  isExpanded: true,
                                  value: selectedType,
                                  dropdownColor: Colors.grey.shade900,
                                  style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 16),
                                  items: ['민물', '바다'].map((String value) => DropdownMenuItem(value: value, child: Text(value))).toList(),
                                  onChanged: (String? newValue) {
                                    setState(() {
                                      selectedType = newValue!;
                                      selectedLocation = selectedType == '민물' ? freshwaterLocations[0] : saltwaterLocations[0];
                                      selectedTargetFish = selectedType == '민물' ? freshwaterFish[0] : saltwaterFish[0];
                                    });
                                  },
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 20),
                          Expanded(
                            flex: 2,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('낚시터 선택', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                                DropdownButton<String>(
                                  isExpanded: true,
                                  value: selectedLocation,
                                  dropdownColor: Colors.grey.shade900,
                                  style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 16),
                                  items: (selectedType == '민물' ? freshwaterLocations : saltwaterLocations)
                                      .map((String value) => DropdownMenuItem(value: value, child: Text(value))).toList(),
                                  onChanged: (String? newValue) => setState(() => selectedLocation = newValue!),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // --- [우승 조건 & 대상 어종 선택] ---
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('우승 조건', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                                DropdownButton<String>(
                                  isExpanded: true,
                                  value: winCondition,
                                  dropdownColor: Colors.grey.shade900,
                                  style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 16),
                                  items: ['마릿수', '최대어'].map((String value) => DropdownMenuItem(value: value, child: Text(value))).toList(),
                                  onChanged: (String? newValue) => setState(() => winCondition = newValue!),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 20),
                          Expanded(
                            flex: 2,
                            child: winCondition == '최대어'
                                ? Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text('대상 어종', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                                      DropdownButton<String>(
                                        isExpanded: true,
                                        value: selectedTargetFish,
                                        dropdownColor: Colors.grey.shade900,
                                        style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 16),
                                        items: (selectedType == '민물' ? freshwaterFish : saltwaterFish)
                                            .map((String value) => DropdownMenuItem(value: value, child: Text(value))).toList(),
                                        onChanged: (String? newValue) => setState(() => selectedTargetFish = newValue!),
                                      ),
                                    ],
                                  )
                                : const SizedBox(), 
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // --- [참가 인원과 참가비] ---
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            flex: 1,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('참가 인원: ${maxPlayers.toInt()}명', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                                Slider(
                                  value: maxPlayers,
                                  min: 2, max: 5, divisions: 3,
                                  activeColor: const Color(0xFFD4AF37),
                                  onChanged: (value) => setState(() => maxPlayers = value),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 20),
                          Expanded(
                            flex: 1,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('참가비', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                                DropdownButton<int>(
                                  isExpanded: true,
                                  value: entryFee,
                                  dropdownColor: Colors.grey.shade900,
                                  style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 16),
                                  items: [500, 1000].map((int value) => DropdownMenuItem<int>(value: value, child: Text('$value P'))).toList(),
                                  onChanged: (newValue) => setState(() => entryFee = newValue!),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // --- [경기 시간 설정] ---
                      const Text('경기 시간', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 15),
                        decoration: BoxDecoration(
                          color: Colors.black26,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFD4AF37).withOpacity(0.5)),
                        ),
                        child: const Text('⏱️ 대회 시간 10분', style: TextStyle(color: Color(0xFFD4AF37), fontWeight: FontWeight.bold, fontSize: 18)),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('취소', style: TextStyle(color: Colors.grey)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFD4AF37), foregroundColor: Colors.black),
                  onPressed: () async {
                    if (nameController.text.trim().isEmpty) {
                      if (!context.mounted) return;
                      showDialog(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          backgroundColor: const Color(0xFF2A2A2A),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                          title: const Row(
                            children: [
                              Icon(Icons.warning_amber_rounded, color: Colors.redAccent),
                              SizedBox(width: 8),
                              Text('입력 오류', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                            ],
                          ),
                          content: const Text('경기장 이름을 필수로 입력해 주세요!', style: TextStyle(color: Colors.white, fontSize: 16)),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx),
                              child: const Text('확인', style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 16)),
                            )
                          ],
                        ),
                      );
                      return;
                    }
                    final user = FirebaseAuth.instance.currentUser;
                    if (user == null) return;

                    final myRooms = await FirebaseFirestore.instance.collection('arenas').where('hostId', isEqualTo: user.uid).get();

                    if (myRooms.docs.isNotEmpty) {
                      await Future.wait(myRooms.docs.map((doc) => doc.reference.delete()));
                    }

                    var docRef = FirebaseFirestore.instance.collection('users').doc(user.uid);
                    var docSnap = await docRef.get();
                    if (!docSnap.exists) return;

                    var userData = docSnap.data() as Map<String, dynamic>;
                    int myGold = userData['gold'] ?? 0;
                    int myTime = userData['remainingTime'] ?? 3600;
                    String myName = userData['nickname'] ?? '이름없음'; 
                    
                    String today = DateTime.now().toString().substring(0, 10);
                    String lastArenaDate = userData['lastArenaDate'] ?? '';
                    int arenaCount = userData['arenaCount'] ?? 0;

                    if (lastArenaDate != today) arenaCount = 0;

                    final ticketExtra = await _resolveArenaEntry(context, userData, today, arenaCount);
                    if (ticketExtra == null) return; // 입장 불가(팝업 표시됨)

                    if (myGold < entryFee) {
                      if (!context.mounted) return;
                      showDialog(context: context, builder: (ctx) => AlertDialog(backgroundColor: const Color(0xFF2A2A2A), title: const Text('잔액 부족 😅', style: TextStyle(color: Colors.redAccent)), content: Text('참가비가 부족합니다.\n(보유 포인트: $myGold P)', style: const TextStyle(color: Colors.white)), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('확인', style: TextStyle(color: Colors.amber)))]));
                      return;
                    }

                    if (myTime < 600) {
                      if (!context.mounted) return;
                      showDialog(context: context, builder: (ctx) => AlertDialog(backgroundColor: const Color(0xFF2A2A2A), title: const Text('시간 부족 ⏳', style: TextStyle(color: Colors.redAccent)), content: const Text('대회를 개설하려면 최소 10분의 낚시 시간이 필요합니다.', style: const TextStyle(color: Colors.white)), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('확인', style: TextStyle(color: Colors.amber)))]));
                      return;
                    }

                    await docRef.update({
                      'gold': myGold - entryFee,
                      'remainingTime': myTime - 600,
                      'lastArenaDate': today,
                      'arenaCount': arenaCount + 1,
                      ...ticketExtra, // 입장권 사용 시 inventory/arenaTicketDate 반영
                    });
                    remainingTimeNotifier.value -= 600;

                    try {
                      DocumentReference docRefRoom = await FirebaseFirestore.instance.collection('arenas').add({
                        'hostId': user.uid,
                        'status': 'waiting',
                        'title': nameController.text,
                        'type': selectedType,
                        'locationName': selectedLocation, 
                        'targetFish': winCondition == '최대어' ? selectedTargetFish : '모든 어종', 
                        'winCondition': winCondition,
                        'timeLimit': timeMin.toInt(),
                        'maxPlayers': maxPlayers.toInt(),
                        'entryFee': entryFee,
                        'hostName': myName, 
                        'currentPlayers': 1,
                        'createdAt': FieldValue.serverTimestamp(),
                      });

                      if (!context.mounted) return;
                      Navigator.pop(context);

                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => ArenaWaitingRoomScreen(
                            roomId: docRefRoom.id,
                            roomData: {
                              'hostId': user.uid,
                              'title': nameController.text,
                              'type': selectedType,
                              'locationName': selectedLocation,
                              'winCondition': winCondition,
                              'targetFish': winCondition == '최대어' ? selectedTargetFish : '모든 어종',
                              'entryFee': entryFee,
                              'currentPlayers': 1,
                              'hostName': myName,
                            },
                          ),
                        ),
                      );
                    } catch (e) {
                      print("방 생성 실패: $e");
                    }
                  },
                  child: const Text('개설 완료', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );
  }
} // 👈 맨 마지막 괄호 2개까지 완벽합니다!
