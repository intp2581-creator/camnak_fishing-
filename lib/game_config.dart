// ignore_for_file: non_constant_identifier_names
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// =========================================================================
// 🎖️ [게임물 등급분류 표시] GRAC 전체이용가 결정(2026-07-24). 게임물명: 캠피싱 낚시게임 KREFT.
//   게임산업진흥법 의무 표기 — 광장(내정보 아래) 진입 시 30초 노출 후 사라짐 + 낚시화면 우측상단.
//   내용정보 7항목(선정성·폭력성·공포·언어·약물·범죄·사행성) 전부 '무(없음)'.
// =========================================================================
const String kGameRatingNumber = 'GC-CC-NP-260724-005';

// 전체이용가 등급 마크 (공식 이미지, 없으면 초록 폴백)
Widget buildRatingMark({double size = 26}) {
  return Image.asset(
    'assets/images/rating_all.png',
    width: size,
    height: size,
    errorBuilder: (c, e, s) => Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: const Color(0xFF2E9E4F),
        borderRadius: BorderRadius.circular(4),
      ),
      child: const Center(
        child: Text('전체\n이용가',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.w900, height: 1.1)),
      ),
    ),
  );
}

// 등급분류 상세정보 팝업 (번호·내용정보·제작배급)
void showGameRatingDialog(BuildContext context) {
  showDialog(
    context: context,
    builder: (c) => AlertDialog(
      backgroundColor: const Color(0xFF1A1A1A),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Color(0xFFD4AF37), width: 1.2),
      ),
      title: Row(mainAxisSize: MainAxisSize.min, children: [
        buildRatingMark(size: 40),
        const SizedBox(width: 12),
        const Text('게임물 등급분류',
            style: TextStyle(color: Color(0xFFD4AF37), fontSize: 18, fontWeight: FontWeight.bold)),
      ]),
      content: const Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('게임물명   캠피싱 낚시게임 KREFT',
              style: TextStyle(color: Colors.white, fontSize: 14, height: 1.9)),
          Text('등급   전체이용가',
              style: TextStyle(color: Colors.white, fontSize: 14, height: 1.9)),
          Text('등급분류번호   $kGameRatingNumber',
              style: TextStyle(color: Colors.white70, fontSize: 14, height: 1.9)),
          Text('내용정보   없음\n(선정성·폭력성·공포·언어·약물·범죄·사행성 전부 해당없음)',
              style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.6)),
          Text('제작·배급   (주)안테모사',
              style: TextStyle(color: Colors.white54, fontSize: 14, height: 1.9)),
          SizedBox(height: 4),
          Text('등급분류기관   게임콘텐츠등급분류위원회(GCRB)',
              style: TextStyle(color: Colors.white38, fontSize: 12, height: 1.6)),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(c),
          child: const Text('닫기', style: TextStyle(color: Color(0xFFD4AF37), fontWeight: FontWeight.bold)),
        ),
      ],
    ),
  );
}

// =========================================================================
// 🎉 [이벤트 시스템] Firestore `config/event` 문서 하나로 운영(코드수정·재배포 없이 켜고 끔).
//    예) 광복절 하루 경험치 2배 → 콘솔에서 expMult:2.0, start/end 넣으면 그 기간에만 자동 적용.
//    문서 형식:
//    config/event {
//      active: true, name: "🎉 광복절 경험치 2배",
//      start: "2026-08-15 00:00", end: "2026-08-16 00:00",  (KST, "yyyy-MM-dd HH:mm")
//      expMult: 2.0, ptsMult: 1.0, bossMult: 1.0
//    }
//    expMult=전체경험치배율 · ptsMult=전체포인트배율 · bossMult=6대장 추가배율(경험치·포인트 공통)
// =========================================================================
class GameEvent {
  final bool active;
  final String name;
  final double expMult;
  final double ptsMult;
  final double bossMult;
  final String tickerMsg; // 📢 낚시화면 자막용 서술형 안내(비면 name 사용). 예: "캠피싱 오픈기념 이벤트 중! 상점에서 기념 뱃지를 구매하세요"
  // 🎁 기간제 이벤트 아이템 (상점 100P 등으로 판매 → 가방에 보유하면 효과 자동 적용 → 만료 시 자동 소멸)
  //    config/event 에 itemName/itemIcon/itemStats{P,C,S}/itemPrice/itemExpire("yyyy-MM-dd HH:mm") 추가하면 상점에 등장.
  final String itemName;
  final String itemIcon;
  final Map<String, int> itemStats;
  final int itemPrice;
  final DateTime? itemExpire;
  const GameEvent({
    this.active = false,
    this.name = '',
    this.expMult = 1.0,
    this.ptsMult = 1.0,
    this.bossMult = 1.0,
    this.tickerMsg = '',
    this.itemName = '',
    this.itemIcon = '',
    this.itemStats = const {},
    this.itemPrice = 0,
    this.itemExpire,
  });
  static const GameEvent none = GameEvent();
}

/// 🎁 이벤트 아이템의 상점 진열 목록(활성+아이템 정의+만료 전이면 1개, 아니면 빈 목록).
///    보조장비 탭 맨 앞에 끼워넣어 사용.
List<Map<String, dynamic>> eventStoreItems() {
  final ev = currentGameEvent;
  if (!ev.active || ev.itemName.isEmpty || ev.itemPrice <= 0) return [];
  if (ev.itemExpire != null && DateTime.now().isAfter(ev.itemExpire!)) return [];
  final String expireStr = ev.itemExpire != null ? ev.itemExpire.toString().substring(0, 16) : '';
  return [{
    'name': ev.itemName,
    'price': ev.itemPrice,
    'category': 'COMMON',
    'type': 'EVENT',
    'stats': ev.itemStats,
    'icon': ev.itemIcon,
    'desc': '🎁 기간제 이벤트 아이템! 가방에 있으면 효과가 자동 적용돼요.${expireStr.isNotEmpty ? '\n(⏳ $expireStr 까지 · 이후 자동 소멸)' : ''}',
    if (ev.itemExpire != null) 'expiresAt': ev.itemExpire!.toIso8601String(),
  }];
}

/// 🎁 가방 속 유효한(만료 전) 이벤트 아이템들의 P/C/S 합산 — 장착 불필요 '보유 버프'.
Map<String, int> eventItemBonus(List<dynamic> inventory) {
  int p = 0, c = 0, s = 0;
  final now = DateTime.now();
  for (final it in inventory) {
    if (it is! Map) continue;
    if ((it['type'] ?? '') != 'EVENT') continue;
    // 🛡️ secLeft 방식(엠블럼 등): 활성화한 뒤 낚시터에서만 줄어든다.
    //    활성화 전(active != true)이면 효과 없음 — 원할 때 켜서 쓰는 아이템.
    if (it.containsKey('secLeft')) {
      // 활성화 + 남은 시간은 전역 카운터를 기준으로 본다(화면·계산이 어긋나지 않게)
      if (!gEmblemOn || gEmblemSec <= 0) continue;
    } else {
      final exp = it['expiresAt'];
      if (exp != null) {
        final dt = DateTime.tryParse(exp.toString());
        if (dt != null && now.isAfter(dt)) continue; // ⏳ 만료 → 효과 없음(정리 전이어도)
      }
    }
    final st = it['stats'];
    if (st is Map) {
      p += (st['P'] is num) ? (st['P'] as num).toInt() : 0;
      c += (st['C'] is num) ? (st['C'] as num).toInt() : 0;
      s += (st['S'] is num) ? (st['S'] as num).toInt() : 0;
    }
  }
  return {'P': p, 'C': c, 'S': s};
}

// =========================================================================
// ⚡ [개인 버프] 물약·카드 — 클릭해서 쓰면 정해진 시간 동안 배율이 붙는다.
//    이벤트 배율(config/event)은 전체 유저 공통이라 '이 사람만 10분간 2배'를
//    표현할 수 없었다(2026-09-02 신설).
//    · users 문서에 만료 시각(millis)만 저장 → 계산이 단순하고 재접속에도 유지
//    · 아레나는 완전 평준화 콘텐츠라 개인 버프를 적용하지 않는다
// =========================================================================
const int kBoostExpMinutes = 10;   // ⚗️ 경험치 물약 지속(분)
const int kBoostPtsMinutes = 10;   // 🎴 KREFT 카드 지속(분)
const double kBoostExpMult = 2.0;
const double kBoostPtsMult = 2.0;

/// 내 버프 남은 시간(초). 낚시시간(remainingTime)과 같은 방식으로,
/// '낚시터에 있는 동안에만' 줄어든다. 광장·상점·아레나에서는 멈춘다.
/// (만료 시각으로 두면 장비 바꾸러 상점 다녀오는 사이에 다 까였다 — 유료템이라 더 문제)
int gBoostExpSec = 0;
int gBoostPtsSec = 0;

bool get boostExpOn => gBoostExpSec > 0;
bool get boostPtsOn => gBoostPtsSec > 0;

/// 🛡️ 엠블럼도 같은 방식 — 인벤 값을 그대로 읽으면 3초마다 뚝뚝 끊기고,
///    화면마다 읽는 곳이 달라 숫자가 어긋난다. 전역 하나로 1초씩 줄인다.
int gEmblemSec = 0;      // 남은 초
bool gEmblemOn = false;  // 활성화 여부
String gEmblemName = '';

int boostExpLeftSec() => gBoostExpSec > 0 ? gBoostExpSec : 0;
int boostPtsLeftSec() => gBoostPtsSec > 0 ? gBoostPtsSec : 0;

/// mm:ss 표기
String boostLeftStr(int sec) =>
    '${(sec ~/ 60).toString().padLeft(2, '0')}:${(sec % 60).toString().padLeft(2, '0')}';

/// 지급/판매용 아이템 정의. type:'BOOST' → 인벤에서 탭하면 사용 확인창.
const Map<String, dynamic> kItemPotionExp = {
  'name': '경험치 물약', 'price': 0, 'cash': true,
  'category': 'BOOST', 'type': 'BOOST', 'boost': 'exp', 'quantity': 1,
  'icon': 'item_potion_exp.png',
  'desc': '마시면 10분 동안 경험치가 2배로 들어와요.\n(아레나·보스레이드에서는 적용되지 않아요)',
};

const Map<String, dynamic> kItemCardKreft = {
  'name': 'KREFT 2배 카드', 'price': 0, 'cash': true,
  'category': 'BOOST', 'type': 'BOOST', 'boost': 'pts', 'quantity': 1,
  'icon': 'item_card_kreft.png',
  'desc': '사용하면 10분 동안 KREFT가 2배로 들어와요.\n(아레나·보스레이드에서는 적용되지 않아요)',
};

/// 🛡️ 능력치 엠블럼 — 태극기 뱃지·송편과 같은 '보유 버프'(type:EVENT).
///    지급할 때 expiresAt을 '지급 시각 + 1시간'으로 넣는다(사람마다 만료가 다름).
const int kEmblemMinutes = 60;   // 🛡️ 능력치 엠블럼 지속(분)

/// 🛡️ 능력치 엠블럼 — 받으면 잠자는 상태로 가방에 들어가고,
///    눌러서 활성화한 뒤 '낚시터에 있는 동안에만' 줄어든다(물약·카드와 같은 규칙).
///    받자마자 흐르면 바로 못 하는 사람은 그냥 날린다 — 유료 패키지 구성품이라 더 문제.
Map<String, dynamic> makeEmblemBoost() {
  return {
    'name': '능력치 엠블럼', 'price': 0, 'cash': true,
    'category': 'COMMON', 'type': 'EVENT',
    'stats': {'P': 10, 'C': 10, 'S': 10},
    'icon': 'item_emblem_boost.png',
    'secLeft': kEmblemMinutes * 60,
    'active': false,
    'quantity': 1,
    'desc': '눌러서 활성화하면 1시간 동안 힘·컨트롤·감도가 각각 +10 올라가요.\n낚시터에 있는 동안에만 시간이 줄어요.\n휘장과 함께 적용돼요. (아레나·보스레이드 제외)',
  };
}

/// 🛡️ 가방 속 기간제 이벤트 아이템의 남은 시간(초). 없으면 0.
///    여러 개면 가장 늦게 끝나는 것을 기준으로 한다.
int eventItemLeftSec(List<dynamic> inventory) {
  final now = DateTime.now();
  int best = 0;
  for (final it in inventory) {
    if (it is! Map) continue;
    if ((it['type'] ?? '') != 'EVENT') continue;
    if (it.containsKey('secLeft')) {
      if (!gEmblemOn) continue;                 // 아직 안 켠 것은 표시 안 함
      if (gEmblemSec > best) best = gEmblemSec;
      continue;
    }
    final exp = it['expiresAt'];
    if (exp == null) continue;
    final dt = DateTime.tryParse(exp.toString());
    if (dt == null) continue;
    final sec = dt.difference(now).inSeconds;
    if (sec > best) best = sec;
  }
  return best;
}

/// 🛡️ 가방 속 유효한 기간제 아이템 이름(표시용). 없으면 빈 문자열.
String eventItemName(List<dynamic> inventory) {
  final now = DateTime.now();
  for (final it in inventory) {
    if (it is! Map) continue;
    if ((it['type'] ?? '') != 'EVENT') continue;
    if (it.containsKey('secLeft')) {
      if (!gEmblemOn || gEmblemSec <= 0) continue;
      return (it['name'] ?? '').toString();
    }
    final exp = it['expiresAt'];
    if (exp != null) {
      final dt = DateTime.tryParse(exp.toString());
      if (dt != null && now.isAfter(dt)) continue;
    }
    return (it['name'] ?? '').toString();
  }
  return '';
}

/// 🛡️ 가방에서 엠블럼 상태를 전역으로 읽어온다(접속·화면 진입 시 1회).
void syncEmblemFromInventory(List<dynamic> inventory) {
  for (final it in inventory) {
    if (it is! Map) continue;
    if ((it['type'] ?? '') != 'EVENT' || !it.containsKey('secLeft')) continue;
    gEmblemSec = (it['secLeft'] is num) ? (it['secLeft'] as num).toInt() : 0;
    gEmblemOn = it['active'] == true;
    gEmblemName = (it['name'] ?? '').toString();
    return;
  }
  gEmblemSec = 0; gEmblemOn = false; gEmblemName = '';
}

/// 🎁 만료된 이벤트 아이템을 제거한 인벤 반환. 변화 없으면 null(쓰기 불필요).
List<dynamic>? removeExpiredEventItems(List<dynamic> inventory) {
  final now = DateTime.now();
  bool changed = false;
  final out = <dynamic>[];
  for (final it in inventory) {
    if (it is Map && (it['type'] ?? '') == 'EVENT') {
      if (it.containsKey('secLeft')) {
        // 🛡️ 활성화해서 다 쓴 것만 소멸. 아직 안 켠 것은 계속 보관한다.
        final int sl = (it['secLeft'] is num) ? (it['secLeft'] as num).toInt() : 0;
        if (it['active'] == true && sl <= 0) { changed = true; continue; }
      } else {
        final exp = it['expiresAt'];
        final dt = exp != null ? DateTime.tryParse(exp.toString()) : null;
        if (dt != null && now.isAfter(dt)) { changed = true; continue; } // 소멸
      }
    }
    out.add(it);
  }
  return changed ? out : null;
}

// =========================================================================
// 🎤 [GM 윤슬 공지 멘트] Firestore `config/gmnotice` 문서로 관리 → 콘솔에서 실시간 수정(재배포 불필요).
//    문서 형식: config/gmnotice { messages: ["멘트1\n둘째줄", "멘트2", ...] }  (각 멘트 2~3줄 권장)
//    낚시 중 GM 윤슬이 이 목록을 ~7초마다 순서대로 브리핑. messages 없거나 비면 아래 기본값 사용.
// =========================================================================
const List<String> kDefaultGmNotices = [
  "🎣 캠피싱 정식 서비스 중입니다!\n게임스토어 아이템 구매·길드 보스레이드\n지금 바로 즐겨보세요!",
  "스킨, 뱃지 등 캐시 아이템은\n게임 내 상점 또는 홈페이지\n게임 스토어에 있습니다.",
  "물고기는 미끼와 낚시터에 따라\n조과가 달라집니다.",
  "친구들과 아레나 낚시대회를\n진행해 보세요.\n경험치·KREFT 1.5배!",
];

/// 현재 GM 윤슬 공지 멘트(전역). 낚시터 입장 시 loadGmNotice()로 최신화. 항상 1개 이상 보장.
List<String> gmNoticeMessages = List<String>.from(kDefaultGmNotices);

/// config/gmnotice 읽어 gmNoticeMessages 갱신. 문서 없거나 비면 기본값 유지(항상 비어있지 않게).
Future<void> loadGmNotice() async {
  try {
    final d = (await FirebaseFirestore.instance.collection('config').doc('gmnotice').get()).data();
    final raw = d?['messages'];
    if (raw is List) {
      final msgs = raw.map((e) => e.toString()).where((s) => s.trim().isNotEmpty).toList();
      gmNoticeMessages = msgs.isNotEmpty ? msgs : List<String>.from(kDefaultGmNotices);
    } else {
      gmNoticeMessages = List<String>.from(kDefaultGmNotices);
    }
  } catch (_) {
    gmNoticeMessages = List<String>.from(kDefaultGmNotices);
  }
}

/// 현재 활성 이벤트(전역). 앱 시작 시 loadGameEvent()로 채움. 기본=이벤트 없음.
GameEvent currentGameEvent = GameEvent.none;

/// 🎣 낚시터 별점별 물고기 힘 배율 (Firestore config/event.starMult, 실시간). 비면 전부 1.0(변화 없음).
///   예: {3:1.05, 4:1.10, 5:1.15} → ★3 물고기 힘 ×1.05 … 며칠에 걸쳐 콘솔에서 살짝씩 상향(제압력 인플레 대응).
///   이벤트 active 여부와 무관하게 항상 적용(gBetaNotice처럼 상시 읽음).
Map<int, double> gStarPowerMult = {};

/// 💎 보물상자 이벤트(명절 한정) 스위치. 메인 이벤트(active)와 '독립' —
///    지금 오픈기념 배지 때문에 active가 켜져 있어도 여기 영향 안 받음.
///    config/event 문서에 boxEvent:true 넣으면 켜짐. boxEventEnd("yyyy-MM-dd HH:mm")
///    지정하면 그 시각 지나 자동 종료(켜는 건 수동). 수상한 상자는 상시라 이 값과 무관.
bool gTreasureBoxOn = false;
// 📢 상단 자막 상시 안내(오픈베타 버그제보 등) — 이벤트 active/기간과 무관하게 항상 표시. config/event 의 betaNotice.
String gBetaNotice = '';

/// 💬 채팅 세션 시작 시각(로그인~로그아웃/새로고침 동안 고정).
///    광장↔낚시터를 오가도 화면마다 리셋되지 않고 '이번 접속' 내내 채팅이 유지되게 하는 공용 기준.
///    페이지 새로고침(=재접속) 하면 전역이 초기화돼 자동으로 다시 세팅된다.
DateTime? _chatSessionStart;
DateTime chatSessionStart() => _chatSessionStart ??= DateTime.now();

/// "yyyy-MM-dd HH:mm"(KST) 또는 "yyyy-MM-dd" 문자열 → DateTime(로컬=KST). 실패 시 null.
DateTime? _parseKst(dynamic v) {
  if (v == null) return null;
  final s = v.toString().trim();
  if (s.isEmpty) return null;
  try {
    return DateTime.parse(s.length <= 10 ? '$s 00:00:00' : s.replaceFirst('T', ' '));
  } catch (_) { return null; }
}

/// Firestore config/event 를 읽어 현재 시각 기준으로 활성 이벤트를 전역에 반영.
/// 앱 시작(main) + 낚시터 입장 시 호출하면 됨. 실패해도 게임엔 지장 없음(이벤트만 미적용).
Future<void> loadGameEvent() async {
  try {
    final doc = await FirebaseFirestore.instance.collection('config').doc('event').get();
    final d = doc.data();
    // 💎 보물상자 이벤트는 메인 이벤트(active)와 독립 → active 판정 '전에' 먼저 결정.
    {
      final bool boxOn = (d?['boxEvent'] == true);
      final DateTime? boxEnd = _parseKst(d?['boxEventEnd']);
      gTreasureBoxOn = boxOn && (boxEnd == null || DateTime.now().isBefore(boxEnd));
    }
    gBetaNotice = (d?['betaNotice'] ?? '').toString(); // 📢 이벤트 active와 무관하게 항상 읽음
    // 🎣 별점별 물고기 힘 배율(이벤트 active와 무관하게 항상 적용) — config/event.starMult:{"3":1.05,...}
    {
      final raw = d?['starMult'];
      final Map<int, double> m = {};
      if (raw is Map) {
        raw.forEach((k, v) {
          final s = int.tryParse(k.toString());
          final val = (v is num) ? v.toDouble() : null;
          if (s != null && val != null && val > 0) m[s] = val;
        });
      }
      gStarPowerMult = m;
    }
    if (d == null || d['active'] != true) { currentGameEvent = GameEvent.none; return; }
    final now = DateTime.now();
    final start = _parseKst(d['start']);
    final end = _parseKst(d['end']);
    // 기간 지정돼 있으면 그 안에서만 적용(둘 다 없으면 상시)
    if (start != null && now.isBefore(start)) { currentGameEvent = GameEvent.none; return; }
    if (end != null && now.isAfter(end)) { currentGameEvent = GameEvent.none; return; }
    double mult(dynamic x) => (x is num && x > 0) ? x.toDouble() : 1.0;
    // 🎁 기간제 이벤트 아이템 파싱
    final Map<String, int> iStats = {};
    final rawStats = d['itemStats'];
    if (rawStats is Map) {
      for (final k in ['P', 'C', 'S']) {
        final v = rawStats[k];
        if (v is num && v != 0) iStats[k] = v.toInt();
      }
    }
    currentGameEvent = GameEvent(
      active: true,
      name: (d['name'] ?? '').toString(),
      expMult: mult(d['expMult']),
      ptsMult: mult(d['ptsMult']),
      bossMult: mult(d['bossMult']),
      tickerMsg: (d['tickerMsg'] ?? '').toString(),
      itemName: (d['itemName'] ?? '').toString(),
      itemIcon: (d['itemIcon'] ?? '').toString(),
      itemStats: iStats,
      itemPrice: (d['itemPrice'] is num) ? (d['itemPrice'] as num).toInt() : 0,
      itemExpire: _parseKst(d['itemExpire']),
    );
  } catch (_) {
    currentGameEvent = GameEvent.none;
    gTreasureBoxOn = false;
    gStarPowerMult = {}; // 오류 시 안전하게 배율 없음(=쉬운 쪽)
  }
}

// =========================================================================
// 📋 [일일 퀘스트] 민물/바다 2분리 — 민물 완료 후 바다 진행. 각 보상 500P.
// =========================================================================
const List<String> dailyFwFish = ['붕어', '떡붕어', '블루길', '살치', '베스', '강준치', '잉어', '메기', '가물치'];
const List<String> dailySeaFish = ['고등어', '우럭', '갈치', '참돔', '광어', '감성돔', '갑오징어', '주꾸미', '문어', '벵에돔'];
const int dailyMissionCount = 3;   // 각 미션 목표 마릿수
const int dailyMissionPrize = 500; // 각 미션 보상 KREFT

// ⚔️ 아레나 = '경험치 던전': 잡은 물고기 exp·포인트를 일반 낚시터의 이 배율로 지급(마스터 장비 10분 파밍).
//    (maxCatch 개인기록엔 반영 안 함=평준화 장비라 기록 오염 방지)
// 📌 2026-09-02: '2배 이상'은 배율이 아니라 '10분 총 획득량' 이야기였다(제압력 1410 +
//    별점 제한 없음). 배율 자체는 1.5가 맞고, 잘못된 건 홈페이지 문구였으므로 그쪽을 고쳤다.
const double arenaRewardMult = 1.5;

// 오늘의 민물 일일 미션 (날짜 시드 → 전 유저 동일)
Map<String, dynamic> getTodayFwMission() {
  final n = DateTime.now();
  final seed = n.year * 10000 + n.month * 100 + n.day;
  return {'fish': dailyFwFish[math.Random(seed).nextInt(dailyFwFish.length)], 'count': dailyMissionCount, 'cat': 'FW'};
}

// 오늘의 바다 일일 미션 (다른 시드)
Map<String, dynamic> getTodaySeaMission() {
  final n = DateTime.now();
  final seed = n.year * 10000 + n.month * 100 + n.day + 7777;
  return {'fish': dailySeaFish[math.Random(seed).nextInt(dailySeaFish.length)], 'count': dailyMissionCount, 'cat': 'SEA'};
}

// =========================================================================
// 🛍️ [보배 일일 퀘스트] 지정 어종 3마리 → 트로피(물고기 이미지) 수집 + 보상
// =========================================================================
const List<String> bobaeFishPool = [...dailyFwFish, ...dailySeaFish];
const int bobaeCount = 3;          // 목표 마릿수
const int bobaeExp = 200;          // 완료 보상 경험치
const int bobaePtsPerFish = 200;   // 마리당 KREFT

// 오늘의 보배 지정 어종 (민물+바다 통합, 다른 시드)
Map<String, dynamic> getTodayBobaeFish() {
  final n = DateTime.now();
  final seed = n.year * 10000 + n.month * 100 + n.day + 31337;
  return {'fish': bobaeFishPool[math.Random(seed).nextInt(bobaeFishPool.length)], 'count': bobaeCount};
}

// 🎖️ 가람 주간 개인 종합 랭킹 (레벨 + 어종별 최대어 보드 합산, 매주 월요일 정산)
//    각 보드 1위=10점 ... 10위=1점. 종합 top10이 1주일 동안 P/C/S 보너스 + 머리 위 순위마크.
const List<String> garamFwFish = ['붕어', '잉어', '가물치', '메기', '떡붕어', '강준치', '블루길', '베스', '살치', '자라', '쏘가리', '꺽지', '무지개송어', '향어', '민물장어', '동자개'];
const List<String> garamSeaFish = ['참돔', '감성돔', '광어', '우럭', '갈치', '고등어', '벵에돔', '갑오징어', '주꾸미', '문어', '참치', '볼락', '학꽁치', '성대', '농어', '부시리', '돌돔'];
int garamRankBonus(int rank) {
  // 🎖️ 종합순위별 P/C/S 각 보너스(선형): 1위+10, 2위+9, 3위+8 ... 10위+1
  if (rank >= 1 && rank <= 10) return 11 - rank;
  return 0;
}

// 🐟 어종별 판매가(마리당) — 잡은 고기를 보배에게 팔 때 (보너스 수입)
//    민물: 블루길/베스/살치 10 · 메기/강준치/떡붕어 15 · 붕어/잉어/가물치 35 · 자라 70
//    바다: 주꾸미/고등어/광어 10 · 갑오징어/갈치/우럭/벵에돔 15 · 감성돔/문어/참돔 35 · 참치 70
int fishSellPrice(String name) {
  const p30 = ['블루길', '베스', '살치', '주꾸미', '고등어', '광어', '동자개', '성대'];
  const p50 = ['메기', '강준치', '떡붕어', '갑오징어', '갈치', '우럭', '벵에돔'];
  const p100 = ['붕어', '잉어', '가물치', '감성돔', '문어', '참돔', '향어', '민물장어', '농어', '부시리', '돌돔'];
  const p200 = ['자라', '참치'];
  // 🔻 판매가 1/3 인하(경제 밸런스): 잡을 때 포인트가 메인, 판매는 보너스
  if (p200.contains(name)) return 70;
  if (p100.contains(name)) return 35;
  if (p30.contains(name)) return 10;
  if (p50.contains(name)) return 15;
  return 15; // 미분류 기본
}

// 어종 이름 → 이미지 경로 (수집품 아이콘용)
//  ⚠️ 풀의 'img'는 폴더가 assets/images/로 잘못돼 있어서, 실제 위치(assets/fish_fw|fish_sea/)로 보정.
String fishImageByName(String name) {
  for (final f in [...fwFishPool, ...seaFishPool]) {
    if (f['name'] == name) {
      final file = (f['img'] ?? '').toString().split('/').last; // 예: fish_sea_01_black_porgy.png
      if (file.isEmpty) return '';
      final folder = file.startsWith('fish_sea') ? 'fish_sea' : 'fish_fw';
      return 'assets/$folder/$file';
    }
  }
  return '';
}

// =========================================================================
// 🌍 [캠피싱 중앙 통제소 전역 변수] 
// 앱 전체에서 공통으로 기억해야 하는 정보들입니다.
// =========================================================================
int currentExp = 0;
int currentPoints = 0;
final ValueNotifier<int> remainingTimeNotifier = ValueNotifier<int>(3600);

// 🚨 전 화면 공용 핫타임 당첨자 기록 장부!
final Set<String> globalAnnouncedWinners = {};

// 📍 오늘의 핫스팟 (민물/바다)
String? fwHotSpot;   
String? seaHotSpot; 

// 🎒 낚시터 이동 시 장비 유지 시스템 (기억 장치)
Map<String, dynamic>? globalEquippedRod;
Map<String, dynamic>? globalEquippedFloat;
Map<String, dynamic>? globalEquippedBait;
Map<String, dynamic>? globalEquippedSkin;
Map<String, dynamic>? globalEquippedSunglasses;
Map<String, dynamic>? globalEquippedBadge;
Map<String, dynamic>? globalEquippedReel;
Map<String, dynamic>? globalEquippedCooler; // 🧊 발밑 슬롯(아이스박스/쿨러) — 신발 대신
Map<String, dynamic>? globalEquippedNet;    // 🥅 뜰채(민물/바다) — 컨트롤
Map<String, dynamic>? globalEquippedBelt;   // 🎽 파워벨트(바다 전용) — 힘
Map<String, dynamic>? globalEquippedGloves; // 🧤 장갑(공용) — 힘
Map<String, dynamic>? globalEquippedLine;   // 🧵 낚시줄(민물/바다) — 힘 + 내구도(m)
Map<String, dynamic>? globalEquippedGroundbait; // 🍚 밑밥(민물/바다) — 감도(세션 버프)
bool? globalIsSeaMode; // 민물/바다 모드가 바뀌었는지 체크용


// =========================================================================
// 📈 [경험치 & 레벨 밸런스 테이블]
// 🆙 만렙 150레벨. 후반일수록 가팔라지는 '가속 곡선'.
//    d(L)=레벨 L 도달에 필요한 경험치(직전 레벨 대비).
//    Lv 1~30: 기존 완만한 커브 유지(초반 성취감)
//    Lv 31~50: 리니어(9500+500×offset) — 5k EXP/일 pace 기준 30→31 2일, 40→41 3일, 50→51 4일
//    Lv 51~100: step 800/lv (아이템·이용권·레이드 대비 마진)
//    Lv 101~150: step 1200/lv (만렙 방어)
//    누적: Lv50≈43만, Lv100(마스터)≈243만, Lv120(전설)≈387만, Lv150(신)≈693만. (신 도달 ≈ 3~4년 목표)
//    ⚠️ 2026-08-16 v311 상향: 곧 나올 1시간 이용권·레이드 이용권·상자 EXP 상향·주간 레이드 3존 확정
//    등으로 실제 pace가 4444→13000/일까지 뛸 것 예상. Lv30 이상 유저 나오는 대로 재튜닝 예정.
// =========================================================================
const int globalMaxLevel = 150;

List<int> _buildExpTable() {
  final M = globalMaxLevel;
  final table = List<int>.filled(M + 1, 0); // index 0·1 = 0 (누적 경험치)
  int prevDelta = 0;
  for (int L = 2; L <= M; L++) {
    final int delta;
    if (L <= 30) {
      // Lv 1~30: 기존 커브 유지(초반 성취감)
      final int band = (L - 1) ~/ 10; // L=2~10→0, 11~20→1, 21~30→2
      final int step = 200 + 50 * band;
      delta = (L == 2) ? 1400 : prevDelta + step;
    } else if (L <= 50) {
      // Lv 31~50: 사용자 요청 리니어 — 30→31 10k, 40→41 15k, 50→51 20k EXP
      delta = 9500 + 500 * (L - 30);
    } else if (L <= 100) {
      // Lv 51~100: step 800/lv (아이템 대비 마진)
      delta = prevDelta + 800;
    } else {
      // Lv 101~150: step 1200/lv (만렙 방어)
      delta = prevDelta + 1200;
    }
    table[L] = table[L - 1] + delta;
    prevDelta = delta;
  }
  return table;
}

// 전역 경험치 테이블 (index 0 안 씀, 1~100)
final List<int> globalExpTable = _buildExpTable();

// 전역 레벨 계산기 함수
int calcLevelFromExp(int exp) {
  for (int i = globalMaxLevel; i >= 1; i--) {
    if (exp >= globalExpTable[i]) return i;
  }
  return 1;
}

// 🎣 낚싯대별 캐스팅/파이팅 씬 이미지 접미사 ('' = 기본 그림 사용).
//    이미지 파일명 규칙: cast_fw_cf20.png / hand_rod_fw_cf20.png (민물), cast_sea_cf250.png / hand_rod_sea_cf250.png (바다) 등.
//    assets/images/에 해당 파일이 없으면 자동으로 기본 그림(cast_fw.png 등)으로 폴백 → 그린 낚싯대부터 하나씩 추가하면 됨.
String rodSceneSuffix(Map<String, dynamic>? rod) {
  final n = (rod?['name'] ?? '').toString().toUpperCase().replaceAll('-', '').replaceAll(' ', '');
  const map = {
    'CF20T': 'cf20', 'CF30T': 'cf30', 'CF40T': 'cf40', 'KT20T': 'kt20', 'KT30T': 'kt30', 'KT40T': 'kt40',
    'CF250': 'cf250', 'CF350': 'cf350', 'CF500': 'cf500', 'KT250': 'kt250', 'KT350': 'kt350', 'KT500': 'kt500',
  };
  return map[n] ?? '';
}

// 🏅 승급 칭호 순서 (스킨 구매 자격 판정 — 웹훅 RANK_ORDER와 동일하게 유지!)
const List<String> kRankOrder = ['초보', '하수', '중수', '고수', '프로', '마스터', '레전드', '낚시의 신'];

// 🎨 등급(칭호)별 닉네임 색 — 초보 흰 → 마스터 금색으로 서열이 한눈에 보이게.
Color rankColor(String? rank) {
  switch (rank) {
    case '하수': return const Color(0xFF7CE38B);      // 연두
    case '중수': return const Color(0xFF56C7F5);      // 하늘
    case '고수': return const Color(0xFFB98BFF);      // 보라
    case '프로': return const Color(0xFFFF9E5A);      // 주황
    case '마스터': return const Color(0xFFFFD54A);    // 금색
    case '레전드': return const Color(0xFFFF6B6B);    // 붉은금(발표 후)
    case '낚시의 신': return const Color(0xFFFF4FD8); // 마젠타(발표 후)
    default: return Colors.white;                     // 초보
  }
}
// 칭호 → 순서 인덱스 (미등록/알 수 없으면 0=초보 취급)
int rankIndex(String rank) {
  final i = kRankOrder.indexOf(rank);
  return i < 0 ? 0 : i;
}
// 스킨 이름('하수 조사')에서 요구 칭호('하수') 추출. 스킨 아니면 빈 문자열.
String skinReqRank(String skinName) {
  for (final r in kRankOrder) {
    if (skinName.startsWith('$r 조사')) return r;
  }
  return '';
}

// 🎖️ 캐시 코스메틱(스킨·뱃지·휘장)의 요구 승급(칭호). 이름 기반이라 옛 인벤(reqRank 필드 없음)도 정상 판정.
//   스킨: 하수/중수/고수/프로/마스터 조사. 뱃지류: 캠피싱뱃지→하수 · 캠피싱휘장→중수 · KREFT정예휘장→고수.
//   (스킨과 짝: 뱃지=하수급 Lv10 · 휘장=중수급 Lv30 · 정예휘장=고수급 Lv50)
String cashReqRank(String name) {
  final sr = skinReqRank(name);
  if (sr.isNotEmpty) return sr;
  if (name.contains('정예')) return '고수';
  if (name.contains('휘장')) return '중수';
  if (name.contains('뱃지')) return '하수';
  return '';
}

// 🏅 칭호: 레벨 breakpoint 기준 (실제 칭호는 승급 퀘스트 통과로 결정 — 이건 참고용).
//    하수10 → 중수30 → 고수50 → 프로70 → 마스터100 → 레전드120 → 낚시의 신150(만렙)
String calcRankFromLevel(int level) {
  if (level >= 150) return '낚시의 신';
  if (level >= 120) return '레전드';
  if (level >= 100) return '마스터';
  if (level >= 70) return '프로';
  if (level >= 50) return '고수';
  if (level >= 30) return '중수';
  if (level >= 10) return '하수';
  return '초보';
}

// 🎖️ [승급 퀘스트] 6대장(민물3+바다3)을 잡아서 승급 → 칭호 변경 + 보상 + 스킨 구매 자격
const List<String> daejangFish = ['붕어', '잉어', '가물치', '참돔', '감성돔', '문어'];

// 칭호 순서 (index로 다음 등급 판단)
const List<String> rankOrder = ['초보', '하수', '중수', '고수', '프로', '마스터', '레전드', '낚시의 신'];

// 🗺️ 낚시터 종류별 어종 출현 가중치(약간의 차이). 표에 없는 어종 = 1.0(변화 없음).
//    미끼 상성처럼 룰렛 가중치에 곱해짐. 장소마다 개성 부여용.
const Map<String, String> spotTypeByName = {
  '예산 예당지': '저수지', '안성 고삼지': '저수지', '진천 백곡지': '저수지', '춘천 파로호': '저수지', '충주 충주호': '저수지',
  '예산 신양수로': '수로', '청양 지천': '수로', '인천 청라수로': '수로', '해남 금자천': '수로', '충주 달천': '수로',
  '통영 척포 갯바위': '갯바위', '신안 가거도': '갯바위', '완도 청산도': '갯바위', '여수 거문도': '갯바위', '제주 섶섬': '갯바위',
  '거제 선상': '선상', '오천항 선상': '선상', '대천 선상': '선상', '통영 선상': '선상', '완도 선상': '선상',
};
// 어종을 종류별로 5:5로 나눠, 해당 그룹이 소폭(1.3배)만 더 잘 나오게 — 격차 작게(초보 배려).
//   나머지 어종은 1.0(변화 없음). 특정 낚시터가 아니라 '종류' 기준으로 통일.
const double _spotBoost = 1.3;
const Map<String, Map<String, double>> spotTypeAffinity = {
  // 🏞️ 저수지형 (대장: 붕어·잉어): 붕어·잉어·떡붕어·메기·살치·블루길·향어
  '저수지': {'붕어': _spotBoost, '잉어': _spotBoost, '떡붕어': _spotBoost, '메기': _spotBoost, '살치': _spotBoost, '블루길': _spotBoost, '향어': _spotBoost},
  // 🌊 수로형 (대장: 가물치): 가물치·베스·쏘가리·강준치·자라·꺽지·동자개·민물장어
  '수로': {'가물치': _spotBoost, '베스': _spotBoost, '쏘가리': _spotBoost, '강준치': _spotBoost, '자라': _spotBoost, '꺽지': _spotBoost, '동자개': _spotBoost, '민물장어': _spotBoost},
  // 🪨 갯바위형 (대장: 감성돔·참돔): 감성돔·참돔·벵에돔·우럭·갑오징어·학꽁치·돌돔·농어
  '갯바위': {'감성돔': _spotBoost, '참돔': _spotBoost, '벵에돔': _spotBoost, '우럭': _spotBoost, '갑오징어': _spotBoost, '학꽁치': _spotBoost, '돌돔': _spotBoost, '농어': _spotBoost},
  // 🚢 선상형 (대장: 문어): 문어·갈치·고등어·광어·주꾸미·볼락·참치·부시리·성대
  '선상': {'문어': _spotBoost, '갈치': _spotBoost, '고등어': _spotBoost, '광어': _spotBoost, '주꾸미': _spotBoost, '볼락': _spotBoost, '참치': _spotBoost, '부시리': _spotBoost, '성대': _spotBoost},
};
// ℹ️ 무지개송어는 특정 낚시터 편중 없이 민물 전역에서 루어에 물림(spot 부스트 없음=중립).
double spotFishMult(String locationName, String fishName) {
  final type = spotTypeByName[locationName];
  if (type == null) return 1.0;
  return spotTypeAffinity[type]?[fishName] ?? 1.0;
}

// ⚔️ 아레나 방: 방장 등급 ±1단계까지만 입장 허용 (실력 격차 완화)
bool canJoinArenaRank(String hostRank, String myRank) {
  final h = rankOrder.indexOf(hostRank);
  final m = rankOrder.indexOf(myRank);
  if (h < 0 || m < 0) return true; // 알 수 없으면 허용(안전)
  return (m - h).abs() <= 1;
}

// 방장 등급 기준 입장 가능 등급 범위 라벨 (로비 표시용)
String arenaRankBandLabel(String hostRank) {
  final h = rankOrder.indexOf(hostRank);
  if (h < 0) return '전체';
  final lo = (h - 1) < 0 ? 0 : (h - 1);
  final hi = (h + 1) >= rankOrder.length ? rankOrder.length - 1 : (h + 1);
  return lo == hi ? rankOrder[h] : '${rankOrder[lo]}~${rankOrder[hi]}';
}

// 승급 티어: 해당 레벨 도달 + 6대장 각 need마리(누적) → 승급 가능 + reward 지급
const List<Map<String, dynamic>> promotionTiers = [
  {'rank': '하수', 'level': 10, 'need': 5, 'reward': 5000},
  {'rank': '중수', 'level': 30, 'need': 10, 'reward': 10000},
  {'rank': '고수', 'level': 50, 'need': 15, 'reward': 50000},
  {'rank': '프로', 'level': 70, 'need': 20, 'reward': 100000},
  {'rank': '마스터', 'level': 100, 'need': 30, 'reward': 200000},
  // 레전드(120)·낚시의 신(150) 승급 퀘스트는 발표 때 추가
];

// 현재 칭호(promoRank) 기준 '다음 승급' 정보 (없으면 null = 더 승급 없음/미구현)
Map<String, dynamic>? nextPromotion(String currentRank) {
  final idx = rankOrder.indexOf(currentRank);
  for (final t in promotionTiers) {
    if (rankOrder.indexOf(t['rank'] as String) == idx + 1) return t;
  }
  return null;
}

// =========================================================================
// 🐲 [보스레이드 로스터] 판타지 존 5단계 — 순차 언락(앞 보스 클리어해야 다음 활성)
//   id: 진행 기록 키 · marker: 게이지 위 보스 이미지 · bg: 존 배경 · hp: 목표 제압치 · minutes: 제한시간
//   ⚠️ hp/minutes 는 밸런스 테스트로 조정. 이미지 없으면 폴백(안 깨짐).
// =========================================================================
// 🐲 건틀릿: 매주 1존부터, 보스당 10분. 클리어하면 다음 보스 자동(새 10분). 실패=길드홀 강퇴·종료. 주 1회.
//    hp는 존별로 상승(난이도). minutes는 전부 10(건틀릿).
// 🐲 power = 안내용 '필요 합산 제압력(/초)' · hp = 실제 목표 제압치.
//   ⚠️ 실측 제압 효율 약 75%(2026-08-30 붕애다: 합산 2,648로 950,000을 8분에 처리).
//      → 10분 커트라인 = hp ÷ 450. 'power' 표기는 이 커트라인과 같게 둔다(안내와 실제를 일치).
//   🎯 [2026-08-30 재설계] 존마다 '인접한 두 등급 10명씩 20명'이 10분에 간신히 잡는 난이도.
//      1존=맛보기(신규 길드 서비스) · 2존=하수10+중수10 · 3존=중수10+고수10
//      4존=고수10+프로10 · 5존=프로10+마스터10. (다음: 마스터+레전드 22M · 레전드+신 29M)
//      1인 제압력 기준: 하수480 · 중수720 · 고수1095 · 프로1485 · 마스터2010 (길드버프 별도 +90)
//      → hp = power × 600초 × 0.5 (= power × 300). 표기 power = 실제 필요 합산 제압력.
//   water: [멀리, 중간, 가까이] 수면선(화면 높이 비율) — 배경마다 물 높이가 달라 존별로 지정.
//   sea: 그 존이 바다인지(true=바다장비만, false=민물장비만 적용). 홈페이지 guild.html 안내와 일치시킬 것.
//     1 늪=민물 · 2 신비한바다=바다 · 3 수로=민물 · 4 폭풍호수=바다(이미지상 바다) · 5 용암심연=민물
//   📊 난이도는 '오늘 기준'이 아니라 성장 목표로 설계 — 오픈 초반엔 1존도 벅차고,
//      길드원이 렙업·장비·레이드대 티어업(20→60)으로 제압력을 올리면서 한 존씩 뚫는다.
//      (실유저 평균 제압력 250 기준: 1존 16명 · 2존 32명 — 성장하면 같은 인원으로 도달)
const List<Map<String, dynamic>> raidBosses = [
  {'id': 'murgadon', 'sea': false, 'tier': 1, 'zone': '신성한 늪',   'name': '태고의 무르가돈', 'marker': 'assets/images/boss_murgadon.png', 'thumb': 'assets/images/thumb_raid_murgadon.png', 'bgm': 'boss_murgadon.mp3', 'bg': 'assets/fields/bg_raid_murgadon.jpg', 'power': 3300,  'hp': 1500000,  'minutes': 10, 'water': [0.66, 0.74, 0.82]},
  {'id': 'abykura', 'sea': true,  'tier': 2, 'zone': '신비한 바다', 'name': '심연의 아비쿠라', 'marker': 'assets/images/boss_abykura.png', 'thumb': 'assets/images/thumb_raid_abykura.png', 'bgm': 'boss_abykura.mp3',  'bg': 'assets/fields/bg_raid_abykura.jpg', 'power': 13800,  'hp': 6200000,  'minutes': 10, 'water': [0.42, 0.54, 0.66]},
  {'id': 'basragon', 'sea': false, 'tier': 3, 'zone': '고대의 수로', 'name': '천년 바스라곤',   'marker': 'assets/images/boss_basragon.png', 'thumb': 'assets/images/thumb_raid_basragon.png', 'bgm': 'boss_basragon.mp3', 'bg': 'assets/fields/bg_raid_basragon.jpg','power': 20000, 'hp': 9000000,  'minutes': 10, 'water': [0.58, 0.68, 0.78]},
  {'id': 'kargon', 'sea': true,   'tier': 4, 'zone': '폭풍호수',   'name': '폭풍 카르곤',     'marker': 'assets/images/boss_kargon.png', 'thumb': 'assets/images/thumb_raid_kargon.png', 'bgm': 'boss_kargon.mp3',   'bg': 'assets/fields/bg_raid_kargon.jpg',  'power': 27600, 'hp': 12400000, 'minutes': 10, 'water': [0.60, 0.70, 0.80]},
  {'id': 'volkar', 'sea': false,   'tier': 5, 'zone': '용암의 심연', 'name': '화염 볼카르',     'marker': 'assets/images/boss_volkar.png', 'thumb': 'assets/images/thumb_raid_volkar.png', 'bgm': 'boss_volkar.mp3',   'bg': 'assets/fields/bg_raid_volkar.jpg',  'power': 36700, 'hp': 16500000, 'minutes': 10, 'water': [0.75, 0.85, 0.95]},
];

// 🎁 [보스레이드 보상] 존 클리어 시 참가 길드원 전원 지급 (사용자 확정 2026-08-15 상향)
//   key=boss id · exp/point=지급량 · mystery=수상한상자 개수 · treasure=보물상자 개수
//   ※ 5존 합계(exp 30,000/p 150,000/수상 30/보물 6)=각 존 누적 결과(별도 완전클리어 보너스 없음)
const Map<String, Map<String, dynamic>> raidRewards = {
  'murgadon': {'exp': 2000,  'point': 10000, 'mystery': 2,  'treasure': 0},
  'abykura':  {'exp': 4000,  'point': 20000, 'mystery': 4,  'treasure': 0},
  'basragon': {'exp': 6000,  'point': 30000, 'mystery': 6,  'treasure': 1},
  'kargon':   {'exp': 8000,  'point': 40000, 'mystery': 8,  'treasure': 2},
  'volkar':   {'exp': 10000, 'point': 50000, 'mystery': 10, 'treasure': 3},
};

// 🌊 그 보스 존이 바다인지. 레이드 장비 판정(민물/바다)에 쓴다.
bool raidBossIsSea(String id) => (raidBossById(id)['sea'] ?? false) == true;

// 보스 id로 로스터 항목 조회. 없으면 첫 보스(무르가돈) 폴백.
Map<String, dynamic> raidBossById(String id) {
  for (final b in raidBosses) {
    if (b['id'] == id) return b;
  }
  return raidBosses.first;
}

// 다음 존(현재 클리어한 보스의 tier+1). 없으면 null(전존 클리어 = 완전 클리어).
Map<String, dynamic>? nextRaidBoss(String clearedBossId) {
  final cur = raidBossById(clearedBossId);
  final nextTier = (cur['tier'] as num).toInt() + 1;
  for (final b in raidBosses) {
    if ((b['tier'] as num).toInt() == nextTier) return b;
  }
  return null;
}

// 🗓️ 이번 주 레이드 키(KST 기준 월요일 날짜 'YYYY-MM-DD')
//   길드당 주 1회 도전 게이트에 쓰임. 매주 월요일 00:00 KST 자동 리셋(키가 바뀌면 새 주).
String currentRaidWeekKey() {
  final kst = DateTime.now().toUtc().add(const Duration(hours: 9));
  final d = DateTime(kst.year, kst.month, kst.day);
  final monday = d.subtract(Duration(days: d.weekday - 1)); // weekday: 1=Mon..7=Sun
  return '${monday.year}-${monday.month.toString().padLeft(2, '0')}-${monday.day.toString().padLeft(2, '0')}';
}

// 길드가 클리어한 보스 id 목록으로 '현재 도전 가능한 최고 tier' 판정 (순차 언락).
//   clearedIds에 앞 tier가 다 있으면 다음 tier 열림. 반환 = 도전 가능한 tier들.
List<Map<String, dynamic>> unlockedRaidBosses(List<dynamic> clearedIds) {
  final cleared = clearedIds.map((e) => e.toString()).toSet();
  final List<Map<String, dynamic>> out = [];
  for (final b in raidBosses) {
    out.add(b);
    if (!cleared.contains(b['id'])) break; // 이 보스 아직 못 깼으면 여기까지만 열림
  }
  return out;
}


// =========================================================================
// 🐟 [물고기 도감 및 확률/보상 데이터]
// 사장님 팁: min(최소어), max(최대어), weight(출현 확률 가중치), pts(지급 포인트)
// =========================================================================

// 🏞️ 민물 물고기
final List<Map<String, dynamic>> fwFishPool = [
  {'name': '붕어', 'weight': 50, 'unit': 'Cm', 'min': 15.0, 'max': 55.0, 'pts': 1, 'img': 'assets/images/fish_fw_01_crucian_carp.png'}, // 👑 6대장
  {'name': '떡붕어', 'weight': 50, 'unit': 'Cm', 'min': 15.0, 'max': 55.0, 'pts': 0, 'img': 'assets/images/fish_fw_04_herabuna.png'},
  {'name': '블루길', 'weight': 50, 'unit': 'Cm', 'min': 15.0, 'max': 30.0, 'pts': 0, 'img': 'assets/images/fish_fw_07_bluegill.png'},
  {'name': '살치', 'weight': 50, 'unit': 'Cm', 'min': 15.0, 'max': 30.0, 'pts': 0, 'img': 'assets/images/fish_fw_05_pale_chub.png'},
  {'name': '베스', 'weight': 50, 'unit': 'Cm', 'min': 15.0, 'max': 55.0, 'pts': 0, 'img': 'assets/images/fish_fw_08_bass.png'},
  {'name': '강준치', 'weight': 50, 'unit': 'Cm', 'min': 15.0, 'max': 55.0, 'pts': 0, 'img': 'assets/images/fish_fw_09_skygazer.png'},
  {'name': '잉어', 'weight': 50, 'unit': 'Cm', 'min': 15.0, 'max': 120.0, 'pts': 1, 'img': 'assets/images/fish_fw_02_carp.png'}, // 👑 6대장
  {'name': '자라', 'weight': 5, 'unit': 'Cm', 'min': 15.0, 'max': 30.0, 'pts': 0, 'img': 'assets/images/fish_fw_10_turtle.png'},
  {'name': '메기', 'weight': 50, 'unit': 'Cm', 'min': 25.0, 'max': 150.0, 'pts': 0, 'img': 'assets/images/fish_fw_03_catfish.png'},
  {'name': '가물치', 'weight': 50, 'unit': 'Cm', 'min': 25.0, 'max': 120.0, 'pts': 1, 'img': 'assets/images/fish_fw_06_snakehead.png'}, // 👑 6대장
  // 🎣 [루어 신규] 쏘가리·꺽지·무지개송어 — 루어 미끼(스푼/웜/플라이)에만 물림(baitAffinity 0.0으로 제한)
  {'name': '쏘가리', 'weight': 50, 'unit': 'Cm', 'min': 15.0, 'max': 55.0, 'pts': 0, 'img': 'assets/fish_fw/fish_fw_12_mandarin.png'},
  {'name': '꺽지', 'weight': 50, 'unit': 'Cm', 'min': 15.0, 'max': 30.0, 'pts': 0, 'img': 'assets/fish_fw/fish_fw_11_kkeokji.png'},
  {'name': '무지개송어', 'weight': 50, 'unit': 'Cm', 'min': 15.0, 'max': 55.0, 'pts': 0, 'img': 'assets/fish_fw/fish_fw_13_rainbow_trout.png'},
  // 🐟 [신규 2026-08-16] 향어(저수지·떡밥강세) · 민물장어(수로·지렁이 야행성) · 동자개(수로·새우강세)
  {'name': '향어', 'weight': 50, 'unit': 'Cm', 'min': 20.0, 'max': 100.0, 'pts': 0, 'img': 'assets/fish_fw/fish_fw_14_israeli_carp.png'},
  {'name': '민물장어', 'weight': 50, 'unit': 'Cm', 'min': 30.0, 'max': 120.0, 'pts': 0, 'img': 'assets/fish_fw/fish_fw_15_eel.png'},
  {'name': '동자개', 'weight': 50, 'unit': 'Cm', 'min': 15.0, 'max': 30.0, 'pts': 0, 'img': 'assets/fish_fw/fish_fw_16_bullhead.png'},
];

// 🌊 바다 물고기
final List<Map<String, dynamic>> seaFishPool = [
  {'name': '고등어', 'weight': 50, 'unit': 'Cm', 'min': 15.0, 'max': 80.0, 'pts': 0, 'img': 'assets/images/fish_sea_09_mackerel.png'},
  {'name': '우럭', 'weight': 50, 'unit': 'Cm', 'min': 15.0, 'max': 70.0, 'pts': 0, 'img': 'assets/images/fish_sea_08_rockfish.png'},
  {'name': '갈치', 'weight': 50, 'unit': 'Cm', 'min': 25.0, 'max': 150.0, 'pts': 0, 'img': 'assets/images/fish_sea_04_hairtail.png'},
  {'name': '참돔', 'weight': 50, 'unit': 'Cm', 'min': 15.0, 'max': 120.0, 'pts': 1, 'img': 'assets/images/fish_sea_02_red_seabream.png'}, // 👑 6대장
  {'name': '벵에돔', 'weight': 50, 'unit': 'Cm', 'min': 15.0, 'max': 60.0, 'pts': 0, 'img': 'assets/images/fish_sea_03_girella.png'},
  {'name': '갑오징어', 'weight': 50, 'unit': 'Cm', 'min': 15.0, 'max': 55.0, 'pts': 0, 'reqBait': '에기', 'img': 'assets/images/fish_sea_07_cuttlefish.png'},
  {'name': '주꾸미', 'weight': 50, 'unit': 'Cm', 'min': 5.0, 'max': 15.0, 'pts': 0, 'reqBait': '에기', 'img': 'assets/images/fish_sea_06_webfoot_octopus.png'},
  {'name': '광어', 'weight': 50, 'unit': 'Cm', 'min': 15.0, 'max': 120.0, 'pts': 0, 'img': 'assets/images/fish_sea_10_halibut.png'},
  {'name': '감성돔', 'weight': 50, 'unit': 'Cm', 'min': 15.0, 'max': 80.0, 'pts': 1, 'img': 'assets/images/fish_sea_01_black_porgy.png'}, // 👑 6대장
  {'name': '문어', 'weight': 50, 'unit': 'kg', 'min': 1, 'max': 50, 'pts': 1, 'reqBait': '에기', 'img': 'assets/images/fish_sea_05_octopus.png'}, // 👑 6대장 (현실감 1~50kg · 2026-08-24 기록 리셋, 힘 계산표도 50 정렬)
  {'name': '참치', 'weight': 5, 'unit': 'Cm', 'min': 40.0, 'max': 200.0, 'pts': 0, 'img': 'assets/images/fish_sea_11_tuna.png'},
  // 🎣 [루어/신규] 볼락(갯지렁이·웜에 강함) · 학꽁치(크릴에 강함)
  {'name': '볼락', 'weight': 50, 'unit': 'Cm', 'min': 15.0, 'max': 30.0, 'pts': 0, 'img': 'assets/fish_sea/fish_sea_12_mebaru.png'},
  {'name': '학꽁치', 'weight': 50, 'unit': 'Cm', 'min': 15.0, 'max': 45.0, 'pts': 0, 'img': 'assets/fish_sea/fish_sea_13_halfbeak.png'},
  // 🐟 [신규 2026-08-16] 성대(선상·갯지렁이) · 농어(갯바위·루어강세) · 부시리(선상·대물·고등어생미끼) · 돌돔(갯바위·갯지렁이)
  {'name': '성대', 'weight': 50, 'unit': 'Cm', 'min': 15.0, 'max': 40.0, 'pts': 0, 'img': 'assets/fish_sea/fish_sea_15_gurnard.png'},
  {'name': '농어', 'weight': 50, 'unit': 'Cm', 'min': 30.0, 'max': 70.0, 'pts': 0, 'img': 'assets/fish_sea/fish_sea_14_seabass.png'},
  {'name': '부시리', 'weight': 50, 'unit': 'Cm', 'min': 40.0, 'max': 120.0, 'pts': 0, 'img': 'assets/fish_sea/fish_sea_16_amberjack.png'},
  {'name': '돌돔', 'weight': 50, 'unit': 'Cm', 'min': 25.0, 'max': 60.0, 'pts': 0, 'img': 'assets/fish_sea/fish_sea_17_rock_bream.png'},
];


// =========================================================================
  // 🗺️ [낚시터(오픈월드) 데이터] - 팩트 100% 반영 완료!
  // =========================================================================
  final Map<String, List<Map<String, dynamic>>> locations = {
    '저수지': [
      {'name': '예산 예당지', 'target': '수초 바닥을 노려라. 단내 나는 미끼에 붕어가 붙는다.', 'stars': 1, 'image': 'assets/fields/bg_yedang.jpg'},
      {'name': '안성 고삼지', 'target': '곡물엔 대물 붕어·잉어, 바닥의 사나운 놈은 생미끼로.', 'stars': 2, 'image': 'assets/fields/bg_gosam.jpg'},
      {'name': '진천 백곡지', 'target': '깊은 골자리가 명당. 노란 알갱이에 씨알이 굵어진다.', 'stars': 3, 'image': 'assets/fields/bg_baekgok.jpg'},
      {'name': '춘천 파로호', 'target': '어종 천국. 미끼 하나로 입질이 완전히 갈린다.', 'stars': 4, 'image': 'assets/fields/bg_paro.jpg'},
      {'name': '충주 충주호', 'target': '댐 대물터. 단·곡물 미끼로 4짜를 노려라. (대물 주의)', 'stars': 5, 'image': 'assets/fields/bg_chungju.jpg'}
    ],
    '수로': [
      {'name': '예산 신양수로', 'target': '물풀 언저리에 사냥꾼이 숨는다. 살아 움직이는 미끼로.', 'stars': 1, 'image': 'assets/fields/bg_sinyang.jpg'},
      {'name': '청양 지천', 'target': '흐름 느린 자리, 곡물엔 강준치·붕어가 반응한다.', 'stars': 2, 'image': 'assets/fields/bg_jicheon.jpg'},
      {'name': '인천 청라수로', 'target': '베스·블루길 소굴. 꿈틀대는 미끼에 사족을 못 쓴다.', 'stars': 3, 'image': 'assets/fields/bg_chungla.jpg'},
      {'name': '해남 금자천', 'target': '겨울 대물터. 바닥에 붙는 육식어는 생미끼가 답.', 'stars': 4, 'image': 'assets/fields/bg_gumja.jpg'},
      {'name': '충주 달천', 'target': '미끼 궁합이 극명한 곳. 노리는 어종에 맞춰 골라라.', 'stars': 5, 'image': 'assets/fields/bg_dalchun.jpg'}
    ],
    '갯바위': [
      {'name': '통영 척포 갯바위', 'target': '여(礁) 주변을 노려라. 갯내 나는 생미끼에 돔이 붙는다.', 'stars': 1, 'image': 'assets/fields/bg_chukpo.jpg'},
      {'name': '신안 가거도', 'target': '벵에돔·감성돔 성지. 먹물 뿜는 놈은 채비부터 다르다.', 'stars': 2, 'image': 'assets/fields/bg_gageo.jpg'},
      {'name': '완도 청산도', 'target': '돔과 두족류가 공존. 노리는 대상에 채비를 바꿔라.', 'stars': 3, 'image': 'assets/fields/bg_cheongsan.jpg'},
      {'name': '여수 거문도', 'target': '조류 센 명당. 굵은 돔과 큰 손님이 오른다.', 'stars': 4, 'image': 'assets/fields/bg_geumo.jpg'},
      {'name': '제주 섶섬', 'target': '미터급이 노니는 물. 큰 놈은 작은 물고기를 통째 삼킨다.', 'stars': 5, 'image': 'assets/fields/bg_seop.jpg'}
    ],
    '선상': [
      {'name': '거제 선상', 'target': '바닥 여를 찍어라. 여덟 다리는 눈이 밝아 채비를 탄다.', 'stars': 1, 'image': 'assets/fields/bg_geo_ship.jpg'},
      {'name': '오천항 선상', 'target': '두족류 타작터. 색과 움직임에 민감하게 반응한다.', 'stars': 2, 'image': 'assets/fields/bg_ocheon_ship.jpg'},
      {'name': '대천 선상', 'target': '여 주변 우럭 핫스팟. 반짝이는 가짜 먹이에 덤빈다.', 'stars': 3, 'image': 'assets/fields/bg_daecheon_ship.jpg'},
      {'name': '통영 선상', 'target': '은빛 갈치가 오르는 밤바다. 갯내 나는 생미끼로 태워라.', 'stars': 4, 'image': 'assets/fields/bg_tong_ship.jpg'},
      {'name': '완도 선상', 'target': '미터급 참치터. 큰 놈일수록 작은 물고기를 통째 삼킨다.', 'stars': 5, 'image': 'assets/fields/bg_wando_ship.jpg'}
    ]
  };


// =========================================================================
// 🛒 [KREFT 상점 및 초기 지급 장비 데이터]
// =========================================================================

// 🎁 신규 유저에게 지급되는 12종 스타터 팩!
List<Map<String, dynamic>> getInitialStarterPack() {
  return [
    {'name': '초보 조사', 'category': 'SKIN', 'type': 'SKIN', 'stats': {'P': 10, 'C': 10, 'S': 10}, 'icon': '../images/skin_beginner.jpg', 'desc': 'KREFT 조사의 기본 복장'},
    {'name': 'CF-20T', 'category': 'FW', 'type': 'ROD', 'stats': {'P': 2, 'C': 2, 'S': 2}, 'icon': 'rod_fw_cf20.png', 'desc': '초보 조사용 기본 민물대'},
    {'name': '일반찌', 'category': 'FW', 'type': 'FLOAT', 'stats': {'P': 2, 'C': 2, 'S': 2}, 'icon': 'float_fw_normal.png', 'desc': '가장 기본적인 민물 찌'},
    {'name': '글루텐', 'category': 'FW', 'type': 'BAIT', 'quantity': 50, 'stats': {'S': 10}, 'icon': 'bait_fw_gluten.png', 'desc': '붕어 집어에 탁월한 미끼 (감도 +10)'},
    {'name': '지렁이', 'category': 'FW', 'type': 'BAIT', 'quantity': 50, 'stats': {'S': 20}, 'icon': 'bait_fw_worm.png', 'desc': '민물 만능 미끼 (감도 +20)'},
    {'name': '옥수수', 'category': 'FW', 'type': 'BAIT', 'quantity': 50, 'stats': {'S': 15}, 'icon': 'bait_fw_corn.png', 'desc': '대물 붕어용 미끼 (감도 +15)'},
    {'name': 'CF250', 'category': 'SEA', 'type': 'ROD', 'stats': {'P': 2, 'C': 2, 'S': 2}, 'icon': 'rod_sea_cf250.png', 'desc': '바다 낚시 입문용 기본대'},
    {'name': 'CF2000', 'category': 'SEA', 'type': 'REEL', 'stats': {'P': 2, 'C': 2, 'S': 2}, 'icon': 'reel_sea_cf2000.png', 'desc': '기본 제공되는 바다 릴'},
    {'name': '갯지렁이', 'category': 'SEA', 'type': 'BAIT', 'quantity': 50, 'stats': {'S': 20}, 'icon': 'bait_sea_worm.png', 'desc': '바다 낚시 기본 미끼 (감도 +20)'},
    {'name': '크릴', 'category': 'SEA', 'type': 'BAIT', 'quantity': 50, 'stats': {'S': 15}, 'icon': 'bait_sea_krill.png', 'desc': '전천후 바다 미끼 (감도 +15)'},
    {'name': '루어', 'category': 'SEA', 'type': 'BAIT', 'quantity': 50, 'stats': {'S': 10}, 'icon': 'bait_sea_lure.png', 'desc': '육식성 어종 전용 (감도 +10)'},
    {'name': '에기', 'category': 'SEA', 'type': 'BAIT', 'quantity': 50, 'stats': {'S': 20}, 'icon': 'bait_sea_egi.png', 'desc': '두족류 전용 미끼 (감도 +20)'},
  ];
}

// 🎣 상점: 낚싯대 목록
final List<Map<String, dynamic>> storeRodItems = [
  {'name': 'CF-20T', 'price': 0, 'category': 'FW', 'type': 'ROD', 'stats': {'P': 2, 'C': 2, 'S': 2}, 'icon': 'rod_fw_cf20.png', 'desc': '초보 조사용 기본 민물대'},
  {'name': 'CF-30T', 'price': 20000, 'reqLevel': 5, 'category': 'FW', 'type': 'ROD', 'stats': {'P': 10, 'C': 10, 'S': 10}, 'icon': 'rod_fw_cf30.png', 'desc': '입문자를 위한 밸런스형 민물대'},
  {'name': 'CF-40T', 'price': 50000, 'reqLevel': 10, 'category': 'FW', 'type': 'ROD', 'stats': {'P': 20, 'C': 20, 'S': 20}, 'icon': 'rod_fw_cf40.png', 'desc': '중급 조사용 고탄성 민물대'},
  {'name': 'KT-20T', 'price': 100000, 'reqLevel': 30, 'category': 'FW', 'type': 'ROD', 'stats': {'P': 30, 'C': 30, 'S': 30}, 'icon': 'rod_fw_kt20.png', 'desc': '프리미엄 KREFT 민물대'},
  {'name': 'KT-30T', 'price': 300000, 'reqLevel': 50, 'category': 'FW', 'type': 'ROD', 'stats': {'P': 40, 'C': 40, 'S': 40}, 'icon': 'rod_fw_kt30.png', 'desc': '대물 붕어 제압용 프로 민물대'},
  {'name': 'KT-40T', 'price': 600000, 'reqLevel': 70, 'category': 'FW', 'type': 'ROD', 'stats': {'P': 50, 'C': 50, 'S': 50}, 'icon': 'rod_fw_kt40.png', 'desc': '민물 낚시의 정점, 마스터 민물대'},
  // 🎣 루어 베이트캐스팅 세트(릴+대 일체형) — 쏘가리·꺽지·무지개송어 공략용. 루어 미끼(스푼/웜/플라이)와 함께.
  {'name': 'BC-200', 'price': 20000, 'reqLevel': 5, 'category': 'FW', 'type': 'ROD', 'stats': {'P': 10, 'C': 10, 'S': 10}, 'icon': 'rod_fw_lure_01.png', 'desc': '루어 입문용 베이트캐스팅 세트 (릴+대 일체형)'},
  {'name': 'BC-400', 'price': 100000, 'reqLevel': 30, 'category': 'FW', 'type': 'ROD', 'stats': {'P': 30, 'C': 30, 'S': 30}, 'icon': 'rod_fw_lure_02.png', 'desc': '중급 루어 앵글러용 베이트캐스팅 세트'},
  {'name': 'BC-600', 'price': 600000, 'reqLevel': 70, 'category': 'FW', 'type': 'ROD', 'stats': {'P': 50, 'C': 50, 'S': 50}, 'icon': 'rod_fw_lure_03.png', 'desc': '루어 낚시의 정점, 프로 베이트캐스팅 세트'},
  {'name': 'CF250', 'price': 0, 'category': 'SEA', 'type': 'ROD', 'stats': {'P': 2, 'C': 2, 'S': 2}, 'icon': 'rod_sea_cf250.png', 'desc': '바다 낚시 입문용 기본대'},
  {'name': 'CF350', 'price': 20000, 'reqLevel': 5, 'category': 'SEA', 'type': 'ROD', 'stats': {'P': 10, 'C': 10, 'S': 10}, 'icon': 'rod_sea_cf350.png', 'desc': '연안 방파제용 전천후 바다대'},
  {'name': 'CF500', 'price': 50000, 'reqLevel': 10, 'category': 'SEA', 'type': 'ROD', 'stats': {'P': 20, 'C': 20, 'S': 20}, 'icon': 'rod_sea_cf500.png', 'desc': '원투 낚시에 최적화된 바다대'},
  {'name': 'KT250', 'price': 100000, 'reqLevel': 30, 'category': 'SEA', 'type': 'ROD', 'stats': {'P': 30, 'C': 30, 'S': 30}, 'icon': 'rod_sea_kt250.png', 'desc': '선상 낚시의 표준, KREFT 바다대'},
  {'name': 'KT350', 'price': 300000, 'reqLevel': 50, 'category': 'SEA', 'type': 'ROD', 'stats': {'P': 40, 'C': 40, 'S': 40}, 'icon': 'rod_sea_kt350.png', 'desc': '프로 앵글러를 위한 고강도 바다대'},
  {'name': 'KT500', 'price': 600000, 'reqLevel': 70, 'category': 'SEA', 'type': 'ROD', 'stats': {'P': 50, 'C': 50, 'S': 50}, 'icon': 'rod_sea_kt500.png', 'desc': '심해 대물 제압용 마스터 바다대'},
];

// 🐲 [길드상점 전용] 보스레이드 낚싯대 — 레이드 참여 입장권 겸 제압력.
//   category 'RAID' + type 'ROD'. 일반 상점엔 안 뜨고 길드상점에서만 포인트로 판매.
//   raidTier(1~3) → 파이팅 이미지 cast_raid_N/waiting_raid_N/hand_rod_raid_N 매핑.
//   제압력은 일반 낚시와 동일 계산(낚싯대 슬롯만 이 대로 교체). 이 대 없으면 레이드 참여 불가.
final List<Map<String, dynamic>> storeGuildRaidRods = [
  {'name': '에인션트 KREFT', 'price': 10000,  'category': 'RAID', 'type': 'ROD', 'raidTier': 1, 'stats': {'P': 30,  'C': 30,  'S': 30},  'icon': 'rod_raid_1.png', 'desc': '태고의 룬이 새겨진 레이드 입문용 낚싯대'},
  {'name': '라이트닝 KREFT', 'price': 300000, 'reqLevel': 50,  'category': 'RAID', 'type': 'ROD', 'raidTier': 2, 'stats': {'P': 50,  'C': 50,  'S': 50},  'icon': 'rod_raid_2.png', 'desc': '번개의 힘이 깃든 중급 레이드 낚싯대'},
  {'name': '인페르노 KREFT', 'price': 600000, 'reqLevel': 100, 'category': 'RAID', 'type': 'ROD', 'raidTier': 3, 'stats': {'P': 100, 'C': 100, 'S': 100}, 'icon': 'rod_raid_3.png', 'desc': '화염을 다스리는 최상급 레이드 낚싯대'},
];

// 아이템이 레이드 전용 낚싯대인지 판별
bool isRaidRod(Map<dynamic, dynamic>? item) =>
    item != null && (item['category'] ?? '') == 'RAID' && (item['type'] ?? '') == 'ROD';

// 레이드대 이름 → 티어(1~3). 없으면 0. (인벤 아이템엔 raidTier가 없을 수 있어 이름으로도 역참조)
int raidRodTierByName(String name) {
  for (final r in storeGuildRaidRods) {
    if (r['name'] == name) return (r['raidTier'] as num).toInt();
  }
  return 0;
}

// ⚙️ 상점: 릴 & 찌 목록
final List<Map<String, dynamic>> storeGearItems = [
  {'name': '일반찌', 'price': 0, 'category': 'FW', 'type': 'FLOAT', 'stats': {'P': 2, 'C': 2, 'S': 2}, 'icon': 'float_fw_normal.png', 'desc': '가장 기본적인 민물 찌'},
  {'name': '오동나무찌', 'price': 10000, 'reqLevel': 5, 'category': 'FW', 'type': 'FLOAT', 'stats': {'P': 10, 'C': 10, 'S': 10}, 'icon': 'float_fw_wood.png', 'desc': '예민한 입질 파악을 위한 찌'},
  {'name': '수제찌', 'price': 20000, 'reqLevel': 10, 'category': 'FW', 'type': 'FLOAT', 'stats': {'P': 15, 'C': 15, 'S': 15}, 'icon': 'float_fw_handmade.png', 'desc': '장인이 깎아 만든 고감도 수제찌'},
  {'name': '나노카본찌', 'price': 50000, 'reqLevel': 30, 'category': 'FW', 'type': 'FLOAT', 'stats': {'P': 20, 'C': 20, 'S': 20}, 'icon': 'float_fw_nano.png', 'desc': '최첨단 소재로 만든 초정밀 찌'},
  {'name': 'CF 전자찌', 'price': 100000, 'reqLevel': 50, 'category': 'FW', 'type': 'FLOAT', 'stats': {'P': 25, 'C': 25, 'S': 25}, 'icon': 'float_fw_elec_cf.png', 'desc': '야간 낚시의 필수품'},
  {'name': 'KT 전자찌', 'price': 200000, 'reqLevel': 70, 'category': 'FW', 'type': 'FLOAT', 'stats': {'P': 30, 'C': 30, 'S': 30}, 'icon': 'float_fw_elec_kt.png', 'desc': '압도적인 시인성을 자랑하는 최고급 전자찌'},
  {'name': 'cf2000', 'price': 0, 'category': 'SEA', 'type': 'REEL', 'stats': {'P': 2, 'C': 2, 'S': 2}, 'icon': 'reel_sea_cf2000.png', 'desc': '기본 제공되는 바다 릴'},
  {'name': 'CF3000', 'price': 10000, 'reqLevel': 5, 'category': 'SEA', 'type': 'REEL', 'stats': {'P': 10, 'C': 10, 'S': 10}, 'icon': 'reel_sea_cf3000.png', 'desc': '방파제용 경량 릴'},
  {'name': 'CF5000', 'price': 20000, 'reqLevel': 10, 'category': 'SEA', 'type': 'REEL', 'stats': {'P': 15, 'C': 15, 'S': 15}, 'icon': 'reel_sea_cf5000.png', 'desc': '원투 낚시용 중형 릴'},
  {'name': 'KF5000', 'price': 50000, 'reqLevel': 30, 'category': 'SEA', 'type': 'REEL', 'stats': {'P': 20, 'C': 20, 'S': 20}, 'icon': 'reel_sea_kf5000.png', 'desc': '선상 낚시용 고급 릴'},
  {'name': 'KF6000', 'price': 100000, 'reqLevel': 50, 'category': 'SEA', 'type': 'REEL', 'stats': {'P': 25, 'C': 25, 'S': 25}, 'icon': 'reel_sea_kf6000.png', 'desc': '대형 어종 제압을 위한 강력한 릴'},
  {'name': 'KF8000', 'price': 200000, 'reqLevel': 70, 'category': 'SEA', 'type': 'REEL', 'stats': {'P': 30, 'C': 30, 'S': 30}, 'icon': 'reel_sea_kf8000.png', 'desc': '괴물과 싸우기 위한 마스터급 대형 릴'},
];

// 🪱 상점: 미끼 목록
final List<Map<String, dynamic>> storeBaitItems = [
  {'name': '글루텐', 'price': 1000, 'category': 'FW', 'type': 'BAIT', 'quantity': 50, 'stats': {'S': 10}, 'icon': 'bait_fw_gluten.png', 'desc': '붕어 집어에 탁월한 미끼 (감도 +10)'},
  {'name': '옥수수', 'price': 1500, 'category': 'FW', 'type': 'BAIT', 'quantity': 50, 'stats': {'S': 15}, 'icon': 'bait_fw_corn.png', 'desc': '대물 붕어를 노리기 위한 미끼 (감도 +15)'},
  {'name': '지렁이', 'price': 2000, 'category': 'FW', 'type': 'BAIT', 'quantity': 50, 'stats': {'S': 20}, 'icon': 'bait_fw_worm.png', 'desc': '민물 잡어부터 붕어까지 만능 미끼 (감도 +20)'},
  // 🎣 루어 미끼 — 쏘가리·꺽지·무지개송어 등 루어어종 전용. 웜은 민물·바다 공용(COMMON).
  {'name': '플라이', 'price': 1000, 'category': 'FW', 'type': 'BAIT', 'quantity': 50, 'stats': {'S': 10}, 'icon': 'bait_fw_lure_fly.png', 'desc': '꺽지·계류어에 강한 루어 미끼 (감도 +10)'},
  {'name': '웜', 'price': 1500, 'category': 'COMMON', 'type': 'BAIT', 'quantity': 50, 'stats': {'S': 15}, 'icon': 'bait_fw_lure_worm.png', 'desc': '민물·바다 공용 소프트웜 루어 (감도 +15)'},
  {'name': '스푼', 'price': 2000, 'category': 'FW', 'type': 'BAIT', 'quantity': 50, 'stats': {'S': 20}, 'icon': 'bait_fw_lure_spoon.png', 'desc': '쏘가리·배스에 강한 스푼 루어 (감도 +20)'},
  {'name': '루어', 'price': 1000, 'category': 'SEA', 'type': 'BAIT', 'quantity': 50, 'stats': {'S': 10}, 'icon': 'bait_sea_lure.png', 'desc': '육식성 어종을 노리는 가짜 미끼 (감도 +10)'},
  {'name': '크릴', 'price': 1500, 'category': 'SEA', 'type': 'BAIT', 'quantity': 50, 'stats': {'S': 15}, 'icon': 'bait_sea_krill.png', 'desc': '다양한 어종을 유혹하는 미끼 (감도 +15)'},
  {'name': '에기', 'price': 2000, 'category': 'SEA', 'type': 'BAIT', 'quantity': 50, 'stats': {'S': 20}, 'icon': 'bait_sea_egi.png', 'desc': '두족류(오징어, 문어 등) 전용 미끼 (감도 +20)'},
  {'name': '갯지렁이', 'price': 2000, 'category': 'SEA', 'type': 'BAIT', 'quantity': 50, 'stats': {'S': 20}, 'icon': 'bait_sea_worm.png', 'desc': '바다 낚시의 기본 미끼 (감도 +20)'},
];

// 😎 상점: 스킨 및 악세서리 목록
// 🎒 보조장비 탭 — 착용 악세서리 · 도구 · P/C/S 스탯 장비
final List<Map<String, dynamic>> storeAuxItems = [
  {'name': '선글라스', 'price': 20000, 'reqLevel': 5, 'category': 'COMMON', 'type': 'ETC', 'stats': {'P': 10, 'C': 10, 'S': 10}, 'icon': 'item_sunglasses.png', 'desc': '눈부심을 막아 찌를 잘 보게 해주는 장비'},
  {'name': '레인보우 편광 선글라스', 'price': 50000, 'reqLevel': 30, 'category': 'COMMON', 'type': 'ETC', 'stats': {'P': 20, 'C': 20, 'S': 20}, 'icon': 'item_sunglasses_rainbow.png', 'desc': '무지개빛 편광 렌즈로 수면 반사광을 잡아 찌·물밑까지 또렷하게 보여주는 프리미엄 선글라스 (민물·바다 공용)'},
  {'name': '장갑', 'price': 10000, 'reqLevel': 10, 'category': 'COMMON', 'type': 'GLOVES', 'stats': {'P': 10}, 'icon': 'gloves.png', 'desc': '그립을 단단히 잡아주는 조사 장갑 (힘 +10 · 민물·바다 공용)'},
  {'name': '바다 파워벨트', 'price': 20000, 'reqLevel': 10, 'category': 'SEA', 'type': 'BELT', 'stats': {'P': 10}, 'icon': 'belt_sea.png', 'desc': '허리 힘을 실어주는 선상 파워벨트 (힘 +10 · 바다 전용)'},
  {'name': '민물 뜰채', 'price': 10000, 'reqLevel': 5, 'category': 'FW', 'type': 'NET', 'stats': {'C': 10}, 'icon': 'net_fw.png', 'desc': '큰 물고기도 안정적으로 랜딩하는 민물 뜰채 (컨트롤 +10)'},
  {'name': '바다 뜰채', 'price': 10000, 'reqLevel': 5, 'category': 'SEA', 'type': 'NET', 'stats': {'C': 10}, 'icon': 'net_sea.png', 'desc': '대물 랜딩용 튼튼한 바다 뜰채 (컨트롤 +10)'},
  // 🧵 낚시줄 — 힘 +10, 내구도 200m(랜딩 실패 시 −10m, 0m면 끊어짐)
  {'name': '민물 낚시줄', 'price': 20000, 'reqLevel': 10, 'category': 'FW', 'type': 'LINE', 'quantity': 1, 'dur': 200, 'stats': {'P': 10}, 'icon': 'line_fw.png', 'desc': '고강도 민물 카본 라인 200m (힘 +10 · 랜딩 실패 시 −10m)'},
  {'name': '바다 낚시줄', 'price': 20000, 'reqLevel': 10, 'category': 'SEA', 'type': 'LINE', 'quantity': 1, 'dur': 200, 'stats': {'P': 10}, 'icon': 'line_sea.png', 'desc': '대물용 바다 원줄 200m (힘 +10 · 랜딩 실패 시 −10m)'},
  // 🍚 밑밥 — 감도 +10(낚시터당 1개 소모, 세션 버프)
  {'name': '민물 밑밥', 'price': 3000, 'reqLevel': 10, 'category': 'FW', 'type': 'GROUNDBAIT', 'quantity': 50, 'stats': {'S': 10}, 'icon': 'chum_fw.png', 'desc': '물고기를 불러 모으는 민물 밑밥 (감도 +10 · 낚시터당 1개 소모)'},
  {'name': '바다 밑밥', 'price': 3000, 'reqLevel': 10, 'category': 'SEA', 'type': 'GROUNDBAIT', 'quantity': 50, 'stats': {'S': 10}, 'icon': 'chum_sea.png', 'desc': '집어 효과 확실한 바다 밑밥 (감도 +10 · 낚시터당 1개 소모)'},
  {'name': '새우 채집망', 'price': 20000, 'reqLevel': 10, 'category': 'FW', 'type': 'TRAP', 'icon': 'item_shrimp_trap.png', 'desc': '민물에 던져두면 민물새우가 모여요. 낚시 중 던져놓고 미끼를 자동 채집! (1분에 2마리)'},
  {'name': '소형 아이스박스', 'price': 10000, 'reqLevel': 5, 'category': 'COMMON', 'type': 'COOLER', 'stats': {'P': 5, 'C': 5, 'S': 5}, 'icon': 'cooler_s.png', 'desc': '잡은 고기를 신선하게 보관하는 휴대용 보냉 아이스박스 (민물·바다 공용)'},
  {'name': '중형 아이스박스', 'price': 50000, 'reqLevel': 20, 'category': 'COMMON', 'type': 'COOLER', 'stats': {'P': 10, 'C': 10, 'S': 10}, 'icon': 'cooler_m.png', 'desc': '넉넉한 용량의 캠피싱 정품 아이스박스 (민물·바다 공용)'},
  {'name': '대형 아이스박스', 'price': 100000, 'reqLevel': 50, 'category': 'COMMON', 'type': 'COOLER', 'stats': {'P': 20, 'C': 20, 'S': 20}, 'icon': 'cooler_l.png', 'desc': '바퀴까지 달린 프로 앵글러용 대형 아이스박스 (민물·바다 공용)'},
  // 🎖️ 휘장(배지) — 민물/바다 통합 '범용(COMMON)' 5등급 체계. 'cash':true → 쇼핑몰 구매 플로우.
  //    (2026-07-27 재구성) 지금은 1~3등급만 오픈, 4~5등급은 추후 공개. 능력치 P/C/S 동일값.
  {'name': '캠피싱 뱃지',      'price': 2200,  'cash': true, 'category': 'COMMON', 'type': 'ETC', 'stats': {'P': 10, 'C': 10, 'S': 10}, 'icon': 'item_badge_1.png', 'desc': '캠피싱 조사임을 증명하는 입문 뱃지 (민물·바다 공용 · Lv.10↑ · 쇼핑몰 전용)\n\n💳 2,200원(VAT포함) · 1개 지급 · 사용처: 게임 내 캐릭터 장착 · 판매 (주)안테모사 · 이용조건 Lv.10↑ · 제공기간 구매일로부터 1년 · 청약철회: 구매 후 7일 내 미장착 시 전액환불(장착=사용개시 시 제한)', 'reqLevel': 10},
  {'name': '캠피싱 휘장',      'price': 5500,  'cash': true, 'category': 'COMMON', 'type': 'ETC', 'stats': {'P': 30, 'C': 30, 'S': 30}, 'icon': 'item_badge_2.png', 'desc': '한 단계 성장한 캠피싱 조사의 휘장 (민물·바다 공용 · Lv.30↑ · 쇼핑몰 전용)\n\n💳 5,500원(VAT포함) · 1개 지급 · 사용처: 게임 내 캐릭터 장착 · 판매 (주)안테모사 · 이용조건 Lv.30↑ · 제공기간 구매일로부터 1년 · 청약철회: 구매 후 7일 내 미장착 시 전액환불(장착=사용개시 시 제한)', 'reqLevel': 30},
  {'name': 'KREFT 정예 휘장', 'price': 11000, 'cash': true, 'category': 'COMMON', 'type': 'ETC', 'stats': {'P': 50, 'C': 50, 'S': 50}, 'icon': 'item_badge_3.png', 'desc': 'KREFT 정예 조사임을 증명하는 휘장 (민물·바다 공용 · Lv.50↑ · 쇼핑몰 전용)\n\n💳 11,000원(VAT포함) · 1개 지급 · 사용처: 게임 내 캐릭터 장착 · 판매 (주)안테모사 · 이용조건 Lv.50↑ · 제공기간 구매일로부터 1년 · 청약철회: 구매 후 7일 내 미장착 시 전액환불(장착=사용개시 시 제한)', 'reqLevel': 50},
  // 🔒 [추후 공개] 4등급 KREFT 명장 휘장(22,000·Lv70·P/C/S 70) / 5등급 KREFT 명인 휘장(55,000·Lv100·P/C/S 100)
];

// 👕 스킨/티켓 탭 — 조사 스킨 · 이용권 · 입장권
// 🛒 게임 내 상점 "쇼핑몰 구매" 버튼이 여는 주소 (스킨·이용권 캐시 구매처)
//    정확한 게임스토어 페이지 URL이 있으면 여기만 바꾸면 됨.
// ⚠️ camnak.com/137(구 게임스토어)은 사이트 2분화로 숨김 처리됨(2026-08-30).
//    → 게임 전용 홈페이지의 게임스토어로 연결.
const String kGameStoreUrl = 'https://kreft.co.kr/store.html';

// 🛒 상품별 쇼핑몰 상세페이지 딥링크 — 게임 아이템명 → 아임웹 상품번호(idx)
//    구매 버튼 누르면 목록이 아니라 해당 상품 구매창으로 바로 이동.
//    새 상품 추가 시 여기에 이름:idx 만 넣으면 됨. (idx = 아임웹 shop_view idx = prodNo)
const String kMallItemBase = 'https://camnak.com/shop_view/?idx=';
const Map<String, int> kMallProductIdx = {
  '낚시 1시간 이용권': 223,
  '아레나 입장권': 245,
  '캠피싱 뱃지': 244,
  '캠피싱 휘장': 242,
  'KREFT 정예 휘장': 243,
  '하수 조사': 224,
  '중수 조사': 225,
  '고수 조사': 226,
  '프로 조사': 227,
  '마스터 조사': 228,
};
// 아이템명으로 상세페이지 URL 반환 (매핑에 없으면 게임스토어 목록으로 폴백)
String mallUrlForItem(String itemName) {
  final exact = kMallProductIdx[itemName];
  if (exact != null) return '$kMallItemBase$exact';
  for (final e in kMallProductIdx.entries) {
    if (itemName.contains(e.key) || e.key.contains(itemName)) {
      return '$kMallItemBase${e.value}';
    }
  }
  return kGameStoreUrl;
}

// 💳 게임아이템 결제 오픈 스위치. 토스페이먼츠 승인되면 true로 바꿔 배포하면
//    상점 버튼이 "🔜 결제 오픈 예정"(구매 막힘) → "🛒 쇼핑몰 구매"로 전환된다.
const bool kPaymentOpen = true; // 🟢 2026-08-23 전체 오픈 (토스 승인 + 자동지급 검증 완료)

// =========================================================================
// 🛒 [서버 상품] 관리자 페이지에서 추가한 상품을 게임 상점에도 띄운다.
//    지금까지 상품이 코드(storeSkinItems)에 박혀 있어, 하나 늘릴 때마다
//    빌드·배포가 필요했다(2026-09-02 신설).
//
//    ⚠️ 기존 상품(스킨·이용권)은 코드에 그대로 둔다.
//       능력치·레벨조건이 걸린 밸런스 데이터라 서버에서 잘못 바꾸면
//       게임이 흔들린다. 코드에 없는 '새 상품'만 서버에서 가져와 덧붙인다.
//
//    아이콘은 파일명 하나로 양쪽을 맞춘다:
//      홈페이지  hub/assets/st-package.jpg
//      게임      assets/images/st-package.jpg  → '../images/st-package.jpg'
// =========================================================================
List<Map<String, dynamic>> gServerStoreItems = [];

/// 💰 5500 → '5,500'
String _won(int n) => n.toString()
    .replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+\b)'), (m) => '${m[1]},');

Future<void> loadServerStoreItems() async {
  try {
    final snap = await FirebaseFirestore.instance
        .collection('store_products').limit(100).get();
    final out = <Map<String, dynamic>>[];
    // 🛒 코드에 이미 있는 상품 이름 전부(중복 방지 — 밸런스는 코드가 기준).
    //    예전엔 storeSkinItems만 봐서, storeAuxItems에 있는 뱃지·휘장 3종이
    //    상점 아래쪽에 한 번 더 뜨고 이미지도 깨졌다(2026-09-02).
    final Set<String> codeNames = {
      for (final l in [storeSkinItems, storeAuxItems, storeRodItems,
                       storeGearItems, storeBaitItems, storeGuildRaidRods])
        for (final c in l) (c['name'] ?? '').toString(),
    };
    for (final doc in snap.docs) {
      final v = doc.data();
      if (v['hidden'] == true) continue;                  // 숨김 상품 제외
      final String name = (v['n'] ?? '').toString();
      if (name.isEmpty) continue;
      if (codeNames.contains(name)) continue;

      final String img = (v['img'] ?? '').toString();
      final int price = (v['p'] is num) ? (v['p'] as num).toInt() : 0;
      final int lv = (v['lv'] is num) ? (v['lv'] as num).toInt() : 0;
      final String detail = (v['detail'] ?? '').toString();
      final String short = (v['d'] ?? '').toString();

      out.add({
        'name': name,
        'price': price,
        'cash': true,
        'category': 'PACKAGE',
        'type': 'ETC',
        'icon': img.isEmpty ? '' : '../images/$img',
        // 🛒 게임 상점은 설명을 3줄만 보여준다(ui_lobby maxLines:3).
        //    긴 상세를 먼저 쓰면 '[구성품 5종]'만 뜨고 잘리므로 짧은 소개를 앞에 둔다.
        //    법정 고지는 코드 상품(storeSkinItems)과 같은 형식으로 자동으로 붙인다.
        'desc': (short.isNotEmpty ? short : detail)
            + '\n\n💳 ${_won(price)}원(VAT포함) · 사용처: 캠피싱 게임 내 · 판매 (주)안테모사'
            + ' · 제공: 결제 즉시 지급 · 유효기간: 구매일로부터 1년(미사용 시 소멸)'
            + ' · 청약철회: 사용 개시 후 제한',
        if (lv > 0) 'reqLevel': lv,
        // 🕒 진열은 하되 아직 판매 전 — 게임 상점도 구매 버튼을 잠근다.
        if (v['soon'] == true) 'soon': true,
        if ((v['soonText'] ?? '').toString().isNotEmpty)
          'soonText': (v['soonText']).toString(),
        'order': (v['order'] is num) ? (v['order'] as num).toInt() : 999,
      });
    }
    out.sort((a, b) => (a['order'] as int).compareTo(b['order'] as int));
    gServerStoreItems = out;
  } catch (_) {
    // 못 불러와도 상점은 기존 목록으로 정상 동작한다
  }
}

final List<Map<String, dynamic>> storeSkinItems = [
  {'name': '낚시 1시간 이용권', 'price': 1100, 'category': 'TICKET', 'type': 'ETC', 'icon': 'item_ticket_1h.png', 'desc': '낚시 시간을 1시간 추가해주는 이용권이에요.\n(계정당 1일 1회 사용 가능)\n\n💳 1,100원(VAT포함) · 1회분 지급 · 사용처: 캠피싱 게임 내 · 판매 (주)안테모사 · 제공: 결제 즉시 지급 · 유효기간: 구매일로부터 1년(미사용 시 소멸) · 청약철회: 사용 개시 후 제한, 미사용분 전액환불',},
  {'name': '아레나 입장권', 'price': 1100, 'cash': true, 'category': 'TICKET', 'type': 'ETC', 'quantity': 1, 'icon': 'arena_ticket.png', 'desc': '아레나 무료 입장 1회를 다 쓴 뒤,\n하루 1회 더 참가할 수 있는 입장권이에요.\n🎟️ 낚시시간 20분을 채워줘서, 시간이 없어도 참가 가능!\n(하루 1장 사용 · 여러 장 보관 가능 · 쇼핑몰 전용)\n\n💳 1,100원(VAT포함) · 1장 지급 · 사용처: 게임 내 아레나 · 판매 (주)안테모사 · 제공: 결제 즉시 지급 · 유효기간: 구매일로부터 1년(미사용 시 소멸) · 청약철회: 사용 개시 후 제한, 미사용분 전액환불',},
  {'name': '초보 조사', 'price': 0, 'category': 'SKIN', 'type': 'SKIN', 'stats': {'P': 10, 'C': 10, 'S': 10}, 'icon': '../images/skin_beginner.jpg', 'desc': '가장 기본적인 낚시꾼 복장'},
  {'name': '하수 조사', 'price': 2200, 'category': 'SKIN', 'type': 'SKIN', 'stats': {'P': 20, 'C': 20, 'S': 20}, 'icon': '../images/skin_novice.jpg', 'desc': '낚시에 맛을 들인 조사 (쇼핑몰 전용)\n\n💳 2,200원(VAT포함) · 1개 지급 · 사용처: 게임 내 캐릭터 장착 · 판매 (주)안테모사 · 이용조건 Lv.10↑ · 제공기간 구매일로부터 1년 · 청약철회: 구매 후 7일 내 미장착 시 전액환불(장착=사용개시 시 제한)', 'reqLevel': 10},
  {'name': '중수 조사', 'price': 5500, 'category': 'SKIN', 'type': 'SKIN', 'stats': {'P': 50, 'C': 50, 'S': 50}, 'icon': '../images/skin_intermediate.jpg', 'desc': '포인트 보는 눈이 생긴 조사 (쇼핑몰 전용)\n\n💳 5,500원(VAT포함) · 1개 지급 · 사용처: 게임 내 캐릭터 장착 · 판매 (주)안테모사 · 이용조건 Lv.30↑ · 제공기간 구매일로부터 1년 · 청약철회: 구매 후 7일 내 미장착 시 전액환불(장착=사용개시 시 제한)', 'reqLevel': 30},
  {'name': '고수 조사', 'price': 11000, 'category': 'SKIN', 'type': 'SKIN', 'stats': {'P': 100, 'C': 100, 'S': 100}, 'icon': '../images/skin_expert.jpg', 'desc': '어디서든 한 마리는 낚아내는 고수 (쇼핑몰 전용)\n\n💳 11,000원(VAT포함) · 1개 지급 · 사용처: 게임 내 캐릭터 장착 · 판매 (주)안테모사 · 이용조건 Lv.50↑ · 제공기간 구매일로부터 1년 · 청약철회: 구매 후 7일 내 미장착 시 전액환불(장착=사용개시 시 제한)', 'reqLevel': 50},
  {'name': '프로 조사', 'price': 22000, 'category': 'SKIN', 'type': 'SKIN', 'stats': {'P': 200, 'C': 200, 'S': 200}, 'icon': '../images/skin_pro.jpg', 'desc': '스폰서를 받는 프로 앵글러 (쇼핑몰 전용)\n\n💳 22,000원(VAT포함) · 1개 지급 · 사용처: 게임 내 캐릭터 장착 · 판매 (주)안테모사 · 이용조건 Lv.70↑ · 제공기간 구매일로부터 1년 · 청약철회: 구매 후 7일 내 미장착 시 전액환불(장착=사용개시 시 제한)', 'reqLevel': 70},
  {'name': '마스터 조사', 'price': 55000, 'category': 'SKIN', 'type': 'SKIN', 'stats': {'P': 300, 'C': 300, 'S': 300}, 'icon': '../images/skin_master.jpg', 'desc': '낚시계의 살아있는 전설 (쇼핑몰 전용)\n\n💳 55,000원(VAT포함) · 1개 지급 · 사용처: 게임 내 캐릭터 장착 · 판매 (주)안테모사 · 이용조건 Lv.100↑ · 제공기간 구매일로부터 1년 · 청약철회: 구매 후 7일 내 미장착 시 전액환불(장착=사용개시 시 제한)', 'reqLevel': 100},
];

// 👕 스킨 판정/등급 통합 헬퍼.
//    ⚠️ '낚시의 신'은 이름에 '조사'가 없어서, 예전 이름검사(contains '조사'/'마스터' 등)에서
//    통째로 누락돼 장착·자동장착이 안 됐음. 앞으로 스킨 판정·등급은 반드시 이 헬퍼로 한다.
int skinTierByName(String name) {
  if (name.contains('낚시의') || name.contains('낚시의신')) return 8; // 낚시의 신(최상)
  if (name.contains('레전드')) return 7;
  if (name.contains('마스터')) return 6;
  if (name.contains('프로')) return 5;
  if (name.contains('고수')) return 4;
  if (name.contains('중수')) return 3;
  if (name.contains('하수')) return 2;
  if (name.contains('초보')) return 1;
  return 0; // 스킨 아님
}

/// 👕 스킨 이름 → 목록/썸네일용 에셋(assets/images/skin_*.jpg).
///    ⚠️ 레전드 실제 파일명은 오타 있는 skin_regend.jpg. 예전 코드가 skin_legend.jpg(없음)를
///    가리켜 레전드 아이콘이 깨졌고, '전설' 문자로 검사해 '레전드 조사'가 매칭 안 됐음.
String skinListIconAsset(String name) {
  switch (skinTierByName(name)) {
    case 8: return 'assets/images/skin_god.jpg';
    case 7: return 'assets/images/skin_regend.jpg';
    case 6: return 'assets/images/skin_master.jpg';
    case 5: return 'assets/images/skin_pro.jpg';
    case 4: return 'assets/images/skin_expert.jpg';
    case 3: return 'assets/images/skin_intermediate.jpg';
    case 2: return 'assets/images/skin_novice.jpg';
    default: return 'assets/images/skin_beginner.jpg';
  }
}

/// 이 아이템이 스킨인가? (type/category='SKIN' 우선, 이름등급은 보조)
bool isSkinItem(Map<String, dynamic> item) =>
    item['type'] == 'SKIN' ||
    item['category'] == 'SKIN' ||
    skinTierByName((item['name'] ?? '').toString()) > 0;

// ⭐ 낚시터 이름 → 난이도 별점(1~5). locations 데이터의 stars와 동일 값.
//    (아레나 방생성 낚시터 선택 등 이름만으로 별점을 붙일 때 사용)
const Map<String, int> kSpotStars = {
  '예산 예당지': 1, '안성 고삼지': 2, '진천 백곡지': 3, '춘천 파로호': 4, '충주 충주호': 5,
  '예산 신양수로': 1, '청양 지천': 2, '인천 청라수로': 3, '해남 금자천': 4, '충주 달천': 5,
  '통영 척포 갯바위': 1, '신안 가거도': 2, '완도 청산도': 3, '여수 거문도': 4, '제주 섶섬': 5,
  '거제 선상': 1, '오천항 선상': 2, '대천 선상': 3, '통영 선상': 4, '완도 선상': 5,
};
int spotStars(String name) => kSpotStars[name] ?? 0;
/// 별점 문자열: 채운 별(★)만 갯수만큼 (예: 2 → "★★"). 모바일에서 빈 별 구분이 안 돼서 채운 별만 표시.
String spotStarStr(String name) => '★' * spotStars(name);

// 🗺️ 낚시터 이름 → 종류(저수지/수로/갯바위/선상). locations 데이터와 동일.
const Map<String, String> kSpotCategory = {
  '예산 예당지': '저수지', '안성 고삼지': '저수지', '진천 백곡지': '저수지', '춘천 파로호': '저수지', '충주 충주호': '저수지',
  '예산 신양수로': '수로', '청양 지천': '수로', '인천 청라수로': '수로', '해남 금자천': '수로', '충주 달천': '수로',
  '통영 척포 갯바위': '갯바위', '신안 가거도': '갯바위', '완도 청산도': '갯바위', '여수 거문도': '갯바위', '제주 섶섬': '갯바위',
  '거제 선상': '선상', '오천항 선상': '선상', '대천 선상': '선상', '통영 선상': '선상', '완도 선상': '선상',
};
String spotCategory(String name) => kSpotCategory[name] ?? '';

// 👕 스킨 이름 → 능력치(P/C/S). 상점 목록에 정의된 값을 우선 사용하고,
//    아직 미공개(레전드·낚시의 신)는 진행 패턴에 맞춘 임시 미리보기 값을 반환.
Map<String, int> skinStatsByName(String name) {
  for (final s in storeSkinItems) {
    if (s['name'] == name && s['stats'] is Map) {
      final st = s['stats'] as Map;
      return {
        'P': int.tryParse(st['P']?.toString() ?? '0') ?? 0,
        'C': int.tryParse(st['C']?.toString() ?? '0') ?? 0,
        'S': int.tryParse(st['S']?.toString() ?? '0') ?? 0,
      };
    }
  }
  // 발표 전 스킨 임시값 (마스터 300 → 레전드 500 → 낚시의 신 800)
  if (name == '레전드 조사') return {'P': 500, 'C': 500, 'S': 500};
  if (name == '낚시의 신') return {'P': 800, 'C': 800, 'S': 800};
  return {'P': 10, 'C': 10, 'S': 10};
}

// 👕 스킨 이름 → 아이콘 경로. 상점 목록 우선, 미공개(레전드·낚시의 신)는 에셋 직접 지정.
String skinIconByName(String name) {
  for (final s in storeSkinItems) {
    if (s['name'] == name && s['icon'] != null) return s['icon'].toString();
  }
  if (name == '레전드 조사') return '../images/skin_regend.jpg';
  if (name == '낚시의 신') return '../images/skin_god.jpg';
  return '../images/skin_beginner.jpg';
}

