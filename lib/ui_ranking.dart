// ignore_for_file: deprecated_member_use
// 🏆 [명예의 전당] 광장 랭킹 NPC 전용 독립 화면. (로비 랭킹 보드를 그대로 가져와 자체 완결형으로 구성)
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'fishing_logic.dart'; // audioManager

const Color _kGold = Color(0xFFD4AF37);

class RankingScreen extends StatefulWidget {
  const RankingScreen({super.key});

  @override
  State<RankingScreen> createState() => _RankingScreenState();
}

class _RankingScreenState extends State<RankingScreen> {
  final List<String> fwFishList = ['붕어', '잉어', '가물치', '메기', '떡붕어', '강준치', '블루길', '베스', '살치', '자라'];
  final List<String> seaFishList = ['참돔', '감성돔', '광어', '우럭', '갈치', '고등어', '벵에돔', '갑오징어', '주꾸미', '문어', '참치'];

  String selectedTab = '레벨';
  String selectedFish = '붕어';

  int _calcLevelFromExp(int exp) {
    if (exp >= 1300000) return 30;
    if (exp >= 1200000) return 29;
    if (exp >= 1100000) return 28;
    if (exp >= 1000000) return 27;
    if (exp >= 900000) return 26;
    if (exp >= 800000) return 25;
    if (exp >= 700000) return 24;
    if (exp >= 650000) return 23;
    if (exp >= 600000) return 22;
    if (exp >= 550000) return 21;
    if (exp >= 500000) return 20;
    if (exp >= 430000) return 19;
    if (exp >= 390000) return 18;
    if (exp >= 350000) return 17;
    if (exp >= 310000) return 16;
    if (exp >= 270000) return 15;
    if (exp >= 240000) return 14;
    if (exp >= 210000) return 13;
    if (exp >= 190000) return 12;
    if (exp >= 160000) return 11;
    if (exp >= 130000) return 10;
    if (exp >= 110000) return 9;
    if (exp >= 90000) return 8;
    if (exp >= 70000) return 7;
    if (exp >= 50000) return 6;
    if (exp >= 30000) return 5;
    if (exp >= 20000) return 4;
    if (exp >= 10000) return 3;
    if (exp >= 5000) return 2;
    return 1;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xF20A0A0A),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 12, 0),
              child: Row(
                children: [
                  const Text('🏆 명예의 전당',
                      style: TextStyle(color: _kGold, fontSize: 26, fontWeight: FontWeight.w900)),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: Colors.white, size: 30),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 240),
                child: _buildRankingBoard(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRankingBoard() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      padding: const EdgeInsets.all(30),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.8),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.cyanAccent.withOpacity(0.6), width: 2),
      ),
      child: Column(
        children: [
          Row(
            children: [
              _buildTabButton('레벨'),
              _buildTabButton('민물'),
              _buildTabButton('바다'),
              _buildTabButton('길드'),
              _buildTabButton('리그'),
            ],
          ),
          const SizedBox(height: 30),
          if (selectedTab == '민물' || selectedTab == '바다')
            Container(
              margin: const EdgeInsets.only(bottom: 20),
              height: 55,
              child: ScrollConfiguration(
                behavior: ScrollConfiguration.of(context).copyWith(
                  dragDevices: {PointerDeviceKind.touch, PointerDeviceKind.mouse},
                ),
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: selectedTab == '민물' ? fwFishList.length : seaFishList.length,
                  itemBuilder: (context, index) {
                    String fishName = selectedTab == '민물' ? fwFishList[index] : seaFishList[index];
                    bool isSelected = selectedFish == fishName;
                    return GestureDetector(
                      onTap: () {
                        audioManager.playSfx("sfx_click.mp3");
                        setState(() => selectedFish = fishName);
                      },
                      child: Container(
                        margin: const EdgeInsets.only(right: 15),
                        padding: const EdgeInsets.symmetric(horizontal: 25),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: isSelected ? const Color(0xFFD4AF37) : Colors.black,
                          border: Border.all(color: const Color(0xFFD4AF37), width: 1.5),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          fishName,
                          style: TextStyle(
                            color: isSelected ? Colors.black : const Color(0xFFD4AF37),
                            fontWeight: FontWeight.bold,
                            fontSize: 20,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          if (selectedTab == '리그')
            Container(
              margin: const EdgeInsets.only(bottom: 6),
              child: const Text('⚔️ 이번 주 길드 리그 · 길드원이 잡은 마릿수 합산 · 월요일 00시 리셋',
                  style: TextStyle(color: Colors.amberAccent, fontSize: 15, fontWeight: FontWeight.bold)),
            ),
          const Divider(color: Colors.cyanAccent, height: 30, thickness: 2),
          Expanded(
            child: selectedTab == '리그'
                ? _buildLeagueList()
                : selectedTab == '길드' ? _buildGuildList() : StreamBuilder<QuerySnapshot>(
              stream: selectedTab == '레벨'
                  ? FirebaseFirestore.instance.collection('users').orderBy('exp', descending: true).limit(10).snapshots()
                  : FirebaseFirestore.instance.collection('users').orderBy('maxCatch.$selectedFish.size', descending: true).limit(10).snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(color: Color(0xFFD4AF37)));
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(child: Text('데이터가 없습니다.', style: TextStyle(color: Colors.white54)));
                }
                var docs = snapshot.data!.docs;
                return ListView.builder(
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    var data = docs[index].data() as Map<String, dynamic>;
                    String name = data['nickname'] ?? '조사님';
                    String displayVal = '';
                    if (selectedTab == '레벨') {
                      int exp = data['exp'] ?? 0;
                      displayVal = 'Lv.${_calcLevelFromExp(exp)}';
                    } else {
                      double size = (data['maxCatch']?[selectedFish]?['size'] ?? 0.0).toDouble();
                      displayVal = '${size.toStringAsFixed(1)}${selectedFish == '문어' ? 'Kg' : 'Cm'}';
                    }
                    bool isMe = docs[index].id == FirebaseAuth.instance.currentUser?.uid;

                    String userSkinImagePath = 'assets/images/skin_beginner.jpg';
                    if (data.containsKey('equippedSkin') && data['equippedSkin'] != null) {
                      var skin = data['equippedSkin'];
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
                    return _buildRankItem(index + 1, name, displayVal, isMe, userSkinImagePath);
                  },
                );
              },
            ),
          ),
          const Divider(color: Colors.white24, height: 30, thickness: 2),
          selectedTab == '리그'
              ? _buildMyLeagueRank()
              : selectedTab == '길드' ? _buildMyGuildRank() : _buildMyStaticRank(),
        ],
      ),
    );
  }

  // ⚔️ 주간 길드 리그 목록 (이번 주 마릿수 순)
  Widget _buildLeagueList() {
    final curWeek = FishingLogic.weekKey(DateTime.now());
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('guild_league').doc('state').snapshots(),
      builder: (context, stateSnap) {
        final champId =
            ((stateSnap.data?.data() as Map<String, dynamic>?)?['championGuildId'] ?? '').toString();
        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('guilds')
              .orderBy('weeklyScore', descending: true)
              .limit(20)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator(color: Color(0xFFD4AF37)));
            }
            final docs = (snapshot.data?.docs ?? []).where((d) {
              final dd = d.data() as Map<String, dynamic>;
              final ws = (dd['weeklyScore'] is num) ? (dd['weeklyScore'] as num).toInt() : 0;
              return (dd['weekKey'] ?? '') == curWeek && ws > 0;
            }).take(10).toList();
            if (docs.isEmpty) {
              return const Center(
                  child: Text('이번 주 기록이 아직 없습니다.\n길드원과 함께 낚시해서 1위에 도전하세요!',
                      textAlign: TextAlign.center, style: TextStyle(color: Colors.white54, fontSize: 18)));
            }
            final myUid = FirebaseAuth.instance.currentUser?.uid;
            return ListView.builder(
              itemCount: docs.length,
              itemBuilder: (context, index) {
                final data = docs[index].data() as Map<String, dynamic>;
                final name = data['name'] ?? '길드';
                final master = data['master'] ?? '-';
                final mc = (data['memberCount'] is num) ? (data['memberCount'] as num).toInt() : 0;
                final ws = (data['weeklyScore'] is num) ? (data['weeklyScore'] as num).toInt() : 0;
                final isChampion = docs[index].id == champId;
                final isMine = data['masterUid'] == myUid;
                return _buildLeagueItem(index + 1, name, master, mc, ws, isChampion, isMine);
              },
            );
          },
        );
      },
    );
  }

  Widget _buildLeagueItem(int rank, String name, String master, int members, int score, bool isChampion, bool isMine) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        color: isChampion
            ? const Color(0xFFD4AF37).withOpacity(0.12)
            : (isMine ? Colors.cyanAccent.withOpacity(0.1) : Colors.transparent),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 50,
            child: Text('$rank위',
                style: TextStyle(
                    color: rank <= 3 ? Colors.amberAccent : Colors.white70,
                    fontWeight: FontWeight.w900,
                    fontSize: 24)),
          ),
          const SizedBox(width: 10),
          Container(
            margin: const EdgeInsets.only(right: 15),
            width: 48,
            height: 48,
            alignment: Alignment.center,
            decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFFD4AF37)),
            child: Icon(isChampion ? Icons.emoji_events : Icons.shield, color: Colors.black, size: 26),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  if (isChampion) const Text('👑 ', style: TextStyle(fontSize: 18)),
                  Flexible(
                    child: Text(name,
                        style: TextStyle(
                            color: isChampion ? const Color(0xFFD4AF37) : (isMine ? Colors.cyanAccent : Colors.white),
                            fontSize: 22,
                            fontWeight: FontWeight.w900),
                        overflow: TextOverflow.ellipsis),
                  ),
                ]),
                Text('길드장 $master · $members명',
                    style: const TextStyle(color: Colors.white54, fontSize: 14)),
              ],
            ),
          ),
          Text('$score마리',
              style: TextStyle(
                  color: rank <= 3 ? Colors.amberAccent : Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }

  // ⚔️ 내 길드의 이번 주 리그 순위 (하단 고정)
  Widget _buildMyLeagueRank() {
    final user = FirebaseAuth.instance.currentUser;
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('users').doc(user?.uid).snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.data() == null) return const SizedBox();
        final myData = snapshot.data!.data() as Map<String, dynamic>;
        final gid = (myData['guildId'] ?? '').toString();
        if (gid.isEmpty) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 16),
            decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(12)),
            child: const Text('가입한 길드가 없습니다. 광장의 길드 건물에서 가입해보세요!',
                style: TextStyle(color: Colors.white54, fontSize: 18, fontWeight: FontWeight.bold)),
          );
        }
        return FutureBuilder<Map<String, dynamic>?>(
          future: _getMyLeagueRank(gid),
          builder: (context, snap) {
            final info = snap.data;
            final rank = (info?['rank'] ?? 0) as int;
            final rankText = rank > 0 ? '$rank위' : '기록 없음';
            final name = info?['name'] ?? myData['guildName'] ?? '내 길드';
            final score = (info?['score'] ?? 0) as int;
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 16),
              decoration: BoxDecoration(
                color: Colors.cyanAccent.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.cyanAccent.withOpacity(0.4), width: 2),
              ),
              child: Row(
                children: [
                  const Text('내 길드', style: TextStyle(color: Colors.cyanAccent, fontSize: 22, fontWeight: FontWeight.w900)),
                  const SizedBox(width: 16),
                  Text(rankText, style: TextStyle(color: (rank > 0 && rank <= 3) ? Colors.amberAccent : Colors.white, fontSize: 22, fontWeight: FontWeight.w900)),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(name, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900), overflow: TextOverflow.ellipsis),
                  ),
                  Text('$score마리', style: const TextStyle(color: Colors.cyanAccent, fontSize: 26, fontWeight: FontWeight.w900)),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<Map<String, dynamic>?> _getMyLeagueRank(String gid) async {
    final curWeek = FishingLogic.weekKey(DateTime.now());
    try {
      final q = await FirebaseFirestore.instance
          .collection('guilds')
          .orderBy('weeklyScore', descending: true)
          .limit(50)
          .get();
      final active = q.docs.where((d) {
        final dd = d.data();
        final ws = (dd['weeklyScore'] is num) ? (dd['weeklyScore'] as num).toInt() : 0;
        return (dd['weekKey'] ?? '') == curWeek && ws > 0;
      }).toList();
      int myScore = 0;
      String myName = '내 길드';
      int rank = 0;
      for (int i = 0; i < active.length; i++) {
        if (active[i].id == gid) {
          rank = i + 1;
          final dd = active[i].data();
          myScore = (dd['weeklyScore'] is num) ? (dd['weeklyScore'] as num).toInt() : 0;
          myName = (dd['name'] ?? '내 길드').toString();
          break;
        }
      }
      return {'rank': rank, 'score': myScore, 'name': myName};
    } catch (e) {
      return null;
    }
  }

  // 🛡️ 길드 랭킹 목록 (길드 경험치 순)
  Widget _buildGuildList() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('guilds')
          .orderBy('guildExp', descending: true)
          .limit(10)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: Color(0xFFD4AF37)));
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Center(child: Text('아직 길드가 없습니다.', style: TextStyle(color: Colors.white54)));
        }
        final myUid = FirebaseAuth.instance.currentUser?.uid;
        final docs = snapshot.data!.docs;
        return ListView.builder(
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final data = docs[index].data() as Map<String, dynamic>;
            final name = data['name'] ?? '길드';
            final master = data['master'] ?? '-';
            final mc = (data['memberCount'] is num) ? (data['memberCount'] as num).toInt() : 0;
            final gExp = (data['guildExp'] is num) ? (data['guildExp'] as num).toInt() : 0;
            final lv = FishingLogic.guildLevelFromExp(gExp);
            final isMine = data['masterUid'] == myUid; // 내가 길드장인 길드 강조
            return _buildGuildRankItem(index + 1, name, master, lv, mc, isMine);
          },
        );
      },
    );
  }

  Widget _buildGuildRankItem(int rank, String name, String master, int lv, int members, bool isMine) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        color: isMine ? Colors.cyanAccent.withOpacity(0.1) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 50,
            child: Text('$rank위',
                style: TextStyle(
                    color: rank <= 3 ? Colors.amberAccent : Colors.white70,
                    fontWeight: FontWeight.w900,
                    fontSize: 24)),
          ),
          const SizedBox(width: 10),
          Container(
            margin: const EdgeInsets.only(right: 15),
            width: 48,
            height: 48,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFFD4AF37),
            ),
            child: const Icon(Icons.shield, color: Colors.black, size: 26),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    style: TextStyle(
                        color: isMine ? Colors.cyanAccent : Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w900),
                    overflow: TextOverflow.ellipsis),
                Text('길드장 $master · $members명',
                    style: const TextStyle(color: Colors.white54, fontSize: 14)),
              ],
            ),
          ),
          Text('Lv.$lv',
              style: TextStyle(
                  color: rank <= 3 ? Colors.amberAccent : Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }

  // 🛡️ 내 길드 순위 (하단 고정)
  Widget _buildMyGuildRank() {
    final user = FirebaseAuth.instance.currentUser;
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('users').doc(user?.uid).snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.data() == null) return const SizedBox();
        final myData = snapshot.data!.data() as Map<String, dynamic>;
        final gid = (myData['guildId'] ?? '').toString();
        if (gid.isEmpty) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 16),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text('가입한 길드가 없습니다. 광장의 길드 건물에서 가입해보세요!',
                style: TextStyle(color: Colors.white54, fontSize: 18, fontWeight: FontWeight.bold)),
          );
        }
        return FutureBuilder<Map<String, dynamic>?>(
          future: _getMyGuildRank(gid),
          builder: (context, snap) {
            final info = snap.data;
            final rankText = (info != null && info['rank'] > 0) ? '${info['rank']}위' : '-';
            final name = info?['name'] ?? myData['guildName'] ?? '내 길드';
            final lv = info?['level'] ?? 1;
            final rank = info?['rank'] ?? 0;
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 16),
              decoration: BoxDecoration(
                color: Colors.cyanAccent.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.cyanAccent.withOpacity(0.4), width: 2),
              ),
              child: Row(
                children: [
                  const Text('내 길드', style: TextStyle(color: Colors.cyanAccent, fontSize: 22, fontWeight: FontWeight.w900)),
                  const SizedBox(width: 16),
                  Text(rankText, style: TextStyle(color: (rank > 0 && rank <= 3) ? Colors.amberAccent : Colors.white, fontSize: 22, fontWeight: FontWeight.w900)),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(name, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900), overflow: TextOverflow.ellipsis),
                  ),
                  Text('Lv.$lv', style: const TextStyle(color: Colors.cyanAccent, fontSize: 26, fontWeight: FontWeight.w900)),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<Map<String, dynamic>?> _getMyGuildRank(String gid) async {
    try {
      final gdoc = await FirebaseFirestore.instance.collection('guilds').doc(gid).get();
      if (!gdoc.exists) return null;
      final gExp = (gdoc.data()?['guildExp'] is num) ? (gdoc.data()!['guildExp'] as num).toInt() : 0;
      final agg = await FirebaseFirestore.instance
          .collection('guilds')
          .where('guildExp', isGreaterThan: gExp)
          .count()
          .get();
      return {
        'rank': (agg.count ?? 0) + 1,
        'name': gdoc.data()?['name'] ?? '내 길드',
        'level': FishingLogic.guildLevelFromExp(gExp),
      };
    } catch (e) {
      return null;
    }
  }

  Widget _buildTabButton(String title) {
    bool isSelected = selectedTab == title;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          audioManager.playSfx("sfx_click.mp3");
          setState(() {
            selectedTab = title;
            selectedFish = (title == '민물' ? fwFishList[0] : (title == '바다' ? seaFishList[0] : '붕어'));
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: isSelected ? const Color(0xFFD4AF37) : Colors.transparent, width: 4)),
          ),
          child: Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isSelected ? const Color(0xFFD4AF37) : Colors.white54,
              fontWeight: isSelected ? FontWeight.w900 : FontWeight.bold,
              fontSize: 24,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRankItem(int rank, String name, String displayVal, bool isMe, String userSkinImagePath) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        color: isMe ? Colors.cyanAccent.withOpacity(0.1) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 50,
            child: Text('$rank위', style: TextStyle(color: rank <= 3 ? Colors.amberAccent : Colors.white70, fontWeight: FontWeight.w900, fontSize: 24)),
          ),
          const SizedBox(width: 10),
          Container(
            margin: const EdgeInsets.only(right: 15),
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFFD4AF37), width: 2.0),
              image: DecorationImage(
                image: AssetImage(userSkinImagePath.isNotEmpty ? userSkinImagePath : 'assets/images/char_beginner.jpg'),
                fit: BoxFit.cover,
                alignment: const Alignment(0.0, -0.75),
              ),
            ),
          ),
          Expanded(
            child: Text(name, style: TextStyle(color: isMe ? Colors.cyanAccent : Colors.white, fontSize: 22, fontWeight: isMe ? FontWeight.w900 : FontWeight.bold), overflow: TextOverflow.ellipsis),
          ),
          Text(displayVal, style: TextStyle(color: rank <= 3 ? Colors.amberAccent : Colors.white, fontSize: 22, fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }

  Future<int> _getMyRank(Map<String, dynamic> myData) async {
    final col = FirebaseFirestore.instance.collection('users');
    try {
      if (selectedTab == '레벨') {
        int myExp = myData['exp'] ?? 0;
        final agg = await col.where('exp', isGreaterThan: myExp).count().get();
        return (agg.count ?? 0) + 1;
      } else {
        double mySize = (myData['maxCatch']?[selectedFish]?['size'] ?? 0.0).toDouble();
        final agg = await col.where('maxCatch.$selectedFish.size', isGreaterThan: mySize).count().get();
        return (agg.count ?? 0) + 1;
      }
    } catch (e) {
      return 0;
    }
  }

  Widget _buildMyStaticRank() {
    final user = FirebaseAuth.instance.currentUser;
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('users').doc(user?.uid).snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.data() == null) return const SizedBox();
        var myData = snapshot.data!.data() as Map<String, dynamic>;
        String displayVal = '';
        if (selectedTab == '레벨') {
          int exp = myData['exp'] ?? 0;
          displayVal = 'Lv.${_calcLevelFromExp(exp)}';
        } else {
          double mySize = (myData['maxCatch']?[selectedFish]?['size'] ?? 0.0).toDouble();
          displayVal = '${mySize.toStringAsFixed(1)}${selectedFish == '문어' ? 'Kg' : 'Cm'}';
        }
        return FutureBuilder<int>(
          future: _getMyRank(myData),
          builder: (context, rankSnap) {
            final int myRank = rankSnap.data ?? 0;
            final String rankText = myRank > 0 ? '$myRank위' : '-';
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 16),
              decoration: BoxDecoration(
                color: Colors.cyanAccent.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.cyanAccent.withOpacity(0.4), width: 2),
              ),
              child: Row(
                children: [
                  const Text('내 랭킹', style: TextStyle(color: Colors.cyanAccent, fontSize: 22, fontWeight: FontWeight.w900)),
                  const SizedBox(width: 16),
                  Text(rankText, style: TextStyle(color: (myRank > 0 && myRank <= 3) ? Colors.amberAccent : Colors.white, fontSize: 22, fontWeight: FontWeight.w900)),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(myData['nickname'] ?? '나', style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900), overflow: TextOverflow.ellipsis),
                  ),
                  Text(displayVal, style: const TextStyle(color: Colors.cyanAccent, fontSize: 26, fontWeight: FontWeight.w900)),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
