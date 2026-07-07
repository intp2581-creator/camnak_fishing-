// ignore_for_file: non_constant_identifier_names
import 'dart:math' as math;
import 'package:flutter/material.dart';

// =========================================================================
// 📋 [일일 퀘스트] 민물/바다 2분리 — 민물 완료 후 바다 진행. 각 보상 500P.
// =========================================================================
const List<String> dailyFwFish = ['붕어', '떡붕어', '블루길', '살치', '베스', '강준치', '잉어', '메기', '가물치'];
const List<String> dailySeaFish = ['고등어', '우럭', '갈치', '참돔', '광어', '감성돔', '갑오징어', '주꾸미', '문어', '벵에돔'];
const int dailyMissionCount = 3;   // 각 미션 목표 마릿수
const int dailyMissionPrize = 500; // 각 미션 보상 포인트

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
const int bobaePtsPerFish = 200;   // 마리당 포인트

// 오늘의 보배 지정 어종 (민물+바다 통합, 다른 시드)
Map<String, dynamic> getTodayBobaeFish() {
  final n = DateTime.now();
  final seed = n.year * 10000 + n.month * 100 + n.day + 31337;
  return {'fish': bobaeFishPool[math.Random(seed).nextInt(bobaeFishPool.length)], 'count': bobaeCount};
}

// 🎖️ 가람 주간 개인 종합 랭킹 (레벨 + 어종별 최대어 보드 합산, 매주 월요일 정산)
//    각 보드 1위=10점 ... 10위=1점. 종합 top10이 1주일 동안 P/C/S 보너스 + 머리 위 순위마크.
const List<String> garamFwFish = ['붕어', '잉어', '가물치', '메기', '떡붕어', '강준치', '블루길', '베스', '살치', '자라'];
const List<String> garamSeaFish = ['참돔', '감성돔', '광어', '우럭', '갈치', '고등어', '벵에돔', '갑오징어', '주꾸미', '문어', '참치'];
int garamRankBonus(int rank) {
  if (rank == 1) return 10;
  if (rank >= 2 && rank <= 4) return 8;
  if (rank >= 5 && rank <= 7) return 5;
  if (rank >= 8 && rank <= 10) return 2;
  return 0;
}

// 🐟 어종별 판매가(마리당) — 잡은 고기를 보배에게 팔 때 (보너스 수입)
//    민물: 블루길/베스/살치 10 · 메기/강준치/떡붕어 15 · 붕어/잉어/가물치 35 · 자라 70
//    바다: 주꾸미/고등어/광어 10 · 갑오징어/갈치/우럭/벵에돔 15 · 감성돔/문어/참돔 35 · 참치 70
int fishSellPrice(String name) {
  const p30 = ['블루길', '베스', '살치', '주꾸미', '고등어', '광어'];
  const p50 = ['메기', '강준치', '떡붕어', '갑오징어', '갈치', '우럭', '벵에돔'];
  const p100 = ['붕어', '잉어', '가물치', '감성돔', '문어', '참돔'];
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
// 🆙 만렙 100레벨! 총 경험치(0~130만)는 그대로, 기존 30레벨 곡선을 100칸으로 잘게 보간.
//    레벨업이 더 자주 일어나 성취감↑ (만렙 경험치/획득량/밸런스 불변)
// =========================================================================
const int globalMaxLevel = 100;

// 기존 30레벨 누적 경험치(곡선 원본). 이 곡선 모양을 그대로 100칸으로 보간한다.
const List<int> _oldExpTable30 = [
  0, 0, 5000, 10000, 20000, 30000, 50000, 70000, 90000, 110000, 130000,
  160000, 190000, 210000, 240000, 270000, 310000, 350000, 390000, 430000, 500000,
  550000, 600000, 650000, 700000, 800000, 900000, 1000000, 1100000, 1200000, 1300000,
];

List<int> _buildExpTable() {
  final M = globalMaxLevel;
  // 1) 옛 30단계 곡선을 M단계로 보간
  final raw = List<double>.filled(M + 1, 0);
  for (int n = 1; n <= M; n++) {
    final p = 1 + (n - 1) * 29 / (M - 1);
    final lo = p.floor();
    final hi = (lo + 1) > 30 ? 30 : (lo + 1);
    final frac = p - lo;
    raw[n] = _oldExpTable30[lo] + (_oldExpTable30[hi] - _oldExpTable30[lo]) * frac;
  }
  // 2) 레벨당 증가폭(delta)을 '비감소'로 보정 → 중간에 필요경험치 줄어드는 굴곡 제거
  final delta = List<double>.filled(M + 1, 0);
  for (int n = 2; n <= M; n++) {
    delta[n] = raw[n] - raw[n - 1];
  }
  for (int n = 3; n <= M; n++) {
    if (delta[n] < delta[n - 1]) delta[n] = delta[n - 1];
  }
  // 3) 보정된 delta로 재누적
  final cum = List<double>.filled(M + 1, 0);
  for (int n = 2; n <= M; n++) {
    cum[n] = cum[n - 1] + delta[n];
  }
  // 4) 만렙이 정확히 1,300,000이 되도록 정규화 + 100단위 반올림
  final scale = (cum[M] > 0) ? 1300000 / cum[M] : 1.0;
  final table = List<int>.filled(M + 1, 0);
  for (int n = 1; n <= M; n++) {
    table[n] = (cum[n] * scale / 100).round() * 100;
  }
  for (int n = 2; n <= M; n++) {
    if (table[n] <= table[n - 1]) table[n] = table[n - 1] + 100;
  }
  // 5) 레벨당 증가폭(delta)도 '비감소' — 100단위 반올림으로 생기는 ±100 흔들림까지 제거.
  //    → 필요경험치가 중간에 줄어드는 일이 전혀 없음. (만렙 ≈ 1,300,800, 약 130만)
  for (int n = 3; n <= M; n++) {
    final pd = table[n - 1] - table[n - 2];
    final td = table[n] - table[n - 1];
    if (td < pd) table[n] = table[n - 1] + pd;
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

// 🏅 칭호: 레벨 breakpoint 기준 (실제 칭호는 승급 퀘스트 통과로 결정 — 이건 참고용).
//    하수15 → 중수30 → 고수50 → 프로70 → 마스터100 → 레전드130 → 낚시의 신150(만렙)
String calcRankFromLevel(int level) {
  if (level >= 150) return '낚시의 신';
  if (level >= 130) return '레전드';
  if (level >= 100) return '마스터';
  if (level >= 70) return '프로';
  if (level >= 50) return '고수';
  if (level >= 30) return '중수';
  if (level >= 15) return '하수';
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
  // 🏞️ 저수지형 (대장: 붕어·잉어): 붕어·잉어·떡붕어·메기·살치
  '저수지': {'붕어': _spotBoost, '잉어': _spotBoost, '떡붕어': _spotBoost, '메기': _spotBoost, '살치': _spotBoost},
  // 🌊 수로형 (대장: 가물치): 가물치·베스·블루길·강준치·자라
  '수로': {'가물치': _spotBoost, '베스': _spotBoost, '블루길': _spotBoost, '강준치': _spotBoost, '자라': _spotBoost},
  // 🪨 갯바위형 (대장: 감성돔·참돔): 감성돔·참돔·벵에돔·우럭·갑오징어
  '갯바위': {'감성돔': _spotBoost, '참돔': _spotBoost, '벵에돔': _spotBoost, '우럭': _spotBoost, '갑오징어': _spotBoost},
  // 🚢 선상형 (대장: 문어): 문어·갈치·고등어·광어·주꾸미·참치
  '선상': {'문어': _spotBoost, '갈치': _spotBoost, '고등어': _spotBoost, '광어': _spotBoost, '주꾸미': _spotBoost, '참치': _spotBoost},
};
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
  // 레전드(130)·낚시의 신(150) 승급 퀘스트는 발표 때 추가
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
// 🐟 [물고기 도감 및 확률/보상 데이터]
// 사장님 팁: min(최소어), max(최대어), weight(출현 확률 가중치), pts(지급 포인트)
// =========================================================================

// 🏞️ 민물 물고기
final List<Map<String, dynamic>> fwFishPool = [
  {'name': '붕어', 'weight': 50, 'unit': 'Cm', 'min': 15.0, 'max': 55.0, 'pts': 1, 'img': 'assets/images/fish_fw_01_crucian_carp.png'}, // 👑 6대장
  {'name': '떡붕어', 'weight': 50, 'unit': 'Cm', 'min': 15.0, 'max': 55.0, 'pts': 0, 'img': 'assets/images/fish_fw_04_herabuna.png'},
  {'name': '블루길', 'weight': 50, 'unit': 'Cm', 'min': 10.0, 'max': 25.0, 'pts': 0, 'img': 'assets/images/fish_fw_07_bluegill.png'},
  {'name': '살치', 'weight': 50, 'unit': 'Cm', 'min': 10.0, 'max': 25.0, 'pts': 0, 'img': 'assets/images/fish_fw_05_pale_chub.png'},
  {'name': '베스', 'weight': 50, 'unit': 'Cm', 'min': 15.0, 'max': 55.0, 'pts': 0, 'img': 'assets/images/fish_fw_08_bass.png'},
  {'name': '강준치', 'weight': 50, 'unit': 'Cm', 'min': 15.0, 'max': 55.0, 'pts': 0, 'img': 'assets/images/fish_fw_09_skygazer.png'},
  {'name': '잉어', 'weight': 50, 'unit': 'Cm', 'min': 15.0, 'max': 120.0, 'pts': 1, 'img': 'assets/images/fish_fw_02_carp.png'}, // 👑 6대장
  {'name': '자라', 'weight': 5, 'unit': 'Cm', 'min': 15.0, 'max': 25.0, 'pts': 0, 'expMult': 2.0, 'img': 'assets/images/fish_fw_10_turtle.png'},
  {'name': '메기', 'weight': 50, 'unit': 'Cm', 'min': 25.0, 'max': 150.0, 'pts': 0, 'img': 'assets/images/fish_fw_03_catfish.png'},
  {'name': '가물치', 'weight': 50, 'unit': 'Cm', 'min': 25.0, 'max': 120.0, 'pts': 1, 'img': 'assets/images/fish_fw_06_snakehead.png'}, // 👑 6대장
];

// 🌊 바다 물고기
final List<Map<String, dynamic>> seaFishPool = [
  {'name': '고등어', 'weight': 50, 'unit': 'Cm', 'min': 15.0, 'max': 80.0, 'pts': 0, 'img': 'assets/images/fish_sea_09_mackerel.png'},
  {'name': '우럭', 'weight': 50, 'unit': 'Cm', 'min': 15.0, 'max': 70.0, 'pts': 0, 'img': 'assets/images/fish_sea_08_rockfish.png'},
  {'name': '갈치', 'weight': 50, 'unit': 'Cm', 'min': 25.0, 'max': 150.0, 'pts': 0, 'img': 'assets/images/fish_sea_04_hairtail.png'},
  {'name': '참돔', 'weight': 50, 'unit': 'Cm', 'min': 15.0, 'max': 120.0, 'pts': 1, 'img': 'assets/images/fish_sea_02_red_seabream.png'}, // 👑 6대장
  {'name': '벵에돔', 'weight': 50, 'unit': 'Cm', 'min': 15.0, 'max': 60.0, 'pts': 0, 'img': 'assets/images/fish_sea_03_girella.png'},
  {'name': '갑오징어', 'weight': 50, 'unit': 'Cm', 'min': 15.0, 'max': 55.0, 'pts': 0, 'reqBait': '에기', 'img': 'assets/images/fish_sea_07_cuttlefish.png'},
  {'name': '주꾸미', 'weight': 50, 'unit': 'Cm', 'min': 10.0, 'max': 30.0, 'pts': 0, 'reqBait': '에기', 'img': 'assets/images/fish_sea_06_webfoot_octopus.png'},
  {'name': '광어', 'weight': 50, 'unit': 'Cm', 'min': 15.0, 'max': 120.0, 'pts': 0, 'img': 'assets/images/fish_sea_10_halibut.png'},
  {'name': '감성돔', 'weight': 50, 'unit': 'Cm', 'min': 15.0, 'max': 80.0, 'pts': 1, 'img': 'assets/images/fish_sea_01_black_porgy.png'}, // 👑 6대장
  {'name': '문어', 'weight': 50, 'unit': 'kg', 'min': 20, 'max': 120, 'pts': 1, 'reqBait': '에기', 'img': 'assets/images/fish_sea_05_octopus.png'}, // 👑 6대장
  {'name': '참치', 'weight': 5, 'unit': 'Cm', 'min': 30.0, 'max': 200.0, 'pts': 0, 'img': 'assets/images/fish_sea_11_tuna.png'},
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
  {'name': 'CF-30T', 'price': 10000, 'category': 'FW', 'type': 'ROD', 'stats': {'P': 10, 'C': 10, 'S': 10}, 'icon': 'rod_fw_cf30.png', 'desc': '입문자를 위한 밸런스형 민물대'},
  {'name': 'CF-40T', 'price': 30000, 'category': 'FW', 'type': 'ROD', 'stats': {'P': 20, 'C': 20, 'S': 20}, 'icon': 'rod_fw_cf40.png', 'desc': '중급 조사용 고탄성 민물대'},
  {'name': 'KT-20T', 'price': 50000, 'category': 'FW', 'type': 'ROD', 'stats': {'P': 30, 'C': 30, 'S': 30}, 'icon': 'rod_fw_kt20.png', 'desc': '프리미엄 KREFT 민물대'},
  {'name': 'KT-30T', 'price': 100000, 'category': 'FW', 'type': 'ROD', 'stats': {'P': 40, 'C': 40, 'S': 40}, 'icon': 'rod_fw_kt30.png', 'desc': '대물 붕어 제압용 프로 민물대'},
  {'name': 'KT-40T', 'price': 200000, 'category': 'FW', 'type': 'ROD', 'stats': {'P': 50, 'C': 50, 'S': 50}, 'icon': 'rod_fw_kt40.png', 'desc': '민물 낚시의 정점, 마스터 민물대'},
  {'name': 'CF250', 'price': 0, 'category': 'SEA', 'type': 'ROD', 'stats': {'P': 2, 'C': 2, 'S': 2}, 'icon': 'rod_sea_cf250.png', 'desc': '바다 낚시 입문용 기본대'},
  {'name': 'CF350', 'price': 10000, 'category': 'SEA', 'type': 'ROD', 'stats': {'P': 10, 'C': 10, 'S': 10}, 'icon': 'rod_sea_cf350.png', 'desc': '연안 방파제용 전천후 바다대'},
  {'name': 'CF500', 'price': 30000, 'category': 'SEA', 'type': 'ROD', 'stats': {'P': 20, 'C': 20, 'S': 10}, 'icon': 'rod_sea_cf500.png', 'desc': '원투 낚시에 최적화된 바다대'},
  {'name': 'KT250', 'price': 50000, 'category': 'SEA', 'type': 'ROD', 'stats': {'P': 30, 'C': 20, 'S': 10}, 'icon': 'rod_sea_kt250.png', 'desc': '선상 낚시의 표준, KREFT 바다대'},
  {'name': 'KT350', 'price': 100000, 'category': 'SEA', 'type': 'ROD', 'stats': {'P': 40, 'C': 40, 'S': 40}, 'icon': 'rod_sea_kt350.png', 'desc': '프로 앵글러를 위한 고강도 바다대'},
  {'name': 'KT500', 'price': 200000, 'category': 'SEA', 'type': 'ROD', 'stats': {'P': 50, 'C': 50, 'S': 50}, 'icon': 'rod_sea_kt500.png', 'desc': '심해 대물 제압용 마스터 바다대'},
];

// ⚙️ 상점: 릴 & 찌 목록
final List<Map<String, dynamic>> storeGearItems = [
  {'name': '일반찌', 'price': 0, 'category': 'FW', 'type': 'FLOAT', 'stats': {'P': 2, 'C': 2, 'S': 2}, 'icon': 'float_fw_normal.png', 'desc': '가장 기본적인 민물 찌'},
  {'name': '오동나무찌', 'price': 5000, 'category': 'FW', 'type': 'FLOAT', 'stats': {'P': 10, 'C': 10, 'S': 10}, 'icon': 'float_fw_wood.png', 'desc': '예민한 입질 파악을 위한 찌'},
  {'name': '수제찌', 'price': 10000, 'category': 'FW', 'type': 'FLOAT', 'stats': {'P': 15, 'C': 15, 'S': 15}, 'icon': 'float_fw_handmade.png', 'desc': '장인이 깎아 만든 고감도 수제찌'},
  {'name': '나노카본찌', 'price': 30000, 'category': 'FW', 'type': 'FLOAT', 'stats': {'P': 20, 'C': 20, 'S': 20}, 'icon': 'float_fw_nano.png', 'desc': '최첨단 소재로 만든 초정밀 찌'},
  {'name': 'CF 전자찌', 'price': 50000, 'category': 'FW', 'type': 'FLOAT', 'stats': {'P': 25, 'C': 25, 'S': 25}, 'icon': 'float_fw_elec_cf.png', 'desc': '야간 낚시의 필수품'},
  {'name': 'KT 전자찌', 'price': 100000, 'category': 'FW', 'type': 'FLOAT', 'stats': {'P': 30, 'C': 30, 'S': 30}, 'icon': 'float_fw_elec_kt.png', 'desc': '압도적인 시인성을 자랑하는 최고급 전자찌'},
  {'name': 'cf2000', 'price': 0, 'category': 'SEA', 'type': 'REEL', 'stats': {'P': 2, 'C': 2, 'S': 2}, 'icon': 'reel_sea_cf2000.png', 'desc': '기본 제공되는 바다 릴'},
  {'name': 'CF3000', 'price': 5000, 'category': 'SEA', 'type': 'REEL', 'stats': {'P': 10, 'C': 10, 'S': 10}, 'icon': 'reel_sea_cf3000.png', 'desc': '방파제용 경량 릴'},
  {'name': 'CF5000', 'price': 10000, 'category': 'SEA', 'type': 'REEL', 'stats': {'P': 15, 'C': 15, 'S': 15}, 'icon': 'reel_sea_cf5000.png', 'desc': '원투 낚시용 중형 릴'},
  {'name': 'KF5000', 'price': 30000, 'category': 'SEA', 'type': 'REEL', 'stats': {'P': 20, 'C': 20, 'S': 20}, 'icon': 'reel_sea_kf5000.png', 'desc': '선상 낚시용 고급 릴'},
  {'name': 'KF6000', 'price': 50000, 'category': 'SEA', 'type': 'REEL', 'stats': {'P': 25, 'C': 25, 'S': 25}, 'icon': 'reel_sea_kf6000.png', 'desc': '대형 어종 제압을 위한 강력한 릴'},
  {'name': 'KF8000', 'price': 100000, 'category': 'SEA', 'type': 'REEL', 'stats': {'P': 30, 'C': 30, 'S': 30}, 'icon': 'reel_sea_kf8000.png', 'desc': '괴물과 싸우기 위한 마스터급 대형 릴'},
];

// 🪱 상점: 미끼 목록
final List<Map<String, dynamic>> storeBaitItems = [
  {'name': '글루텐', 'price': 1000, 'category': 'FW', 'type': 'BAIT', 'quantity': 50, 'stats': {'S': 10}, 'icon': 'bait_fw_gluten.png', 'desc': '붕어 집어에 탁월한 미끼 (감도 +10)'},
  {'name': '옥수수', 'price': 1500, 'category': 'FW', 'type': 'BAIT', 'quantity': 50, 'stats': {'S': 15}, 'icon': 'bait_fw_corn.png', 'desc': '대물 붕어를 노리기 위한 미끼 (감도 +15)'},
  {'name': '지렁이', 'price': 2000, 'category': 'FW', 'type': 'BAIT', 'quantity': 50, 'stats': {'S': 20}, 'icon': 'bait_fw_worm.png', 'desc': '민물 잡어부터 붕어까지 만능 미끼 (감도 +20)'},
  {'name': '루어', 'price': 1000, 'category': 'SEA', 'type': 'BAIT', 'quantity': 50, 'stats': {'S': 10}, 'icon': 'bait_sea_lure.png', 'desc': '육식성 어종을 노리는 가짜 미끼 (감도 +10)'},
  {'name': '크릴', 'price': 1500, 'category': 'SEA', 'type': 'BAIT', 'quantity': 50, 'stats': {'S': 15}, 'icon': 'bait_sea_krill.png', 'desc': '다양한 어종을 유혹하는 미끼 (감도 +15)'},
  {'name': '에기', 'price': 2000, 'category': 'SEA', 'type': 'BAIT', 'quantity': 50, 'stats': {'S': 20}, 'icon': 'bait_sea_egi.png', 'desc': '두족류(오징어, 문어 등) 전용 미끼 (감도 +20)'},
  {'name': '갯지렁이', 'price': 2000, 'category': 'SEA', 'type': 'BAIT', 'quantity': 50, 'stats': {'S': 20}, 'icon': 'bait_sea_worm.png', 'desc': '바다 낚시의 기본 미끼 (감도 +20)'},
];

// 😎 상점: 스킨 및 악세서리 목록
// 🎒 보조장비 탭 — 착용 악세서리 · 도구 · P/C/S 스탯 장비
final List<Map<String, dynamic>> storeAuxItems = [
  {'name': '선글라스', 'price': 10000, 'category': 'COMMON', 'type': 'ETC', 'stats': {'P': 10, 'C': 10, 'S': 10}, 'icon': 'item_sunglasses.png', 'desc': '눈부심을 막아 찌를 잘 보게 해주는 장비'},
  {'name': '레인보우 편광 선글라스', 'price': 50000, 'category': 'COMMON', 'type': 'ETC', 'stats': {'P': 20, 'C': 20, 'S': 20}, 'icon': 'item_sunglasses_rainbow.png', 'desc': '무지개빛 편광 렌즈로 수면 반사광을 잡아 찌·물밑까지 또렷하게 보여주는 프리미엄 선글라스 (민물·바다 공용)'},
  {'name': '장갑', 'price': 20000, 'category': 'COMMON', 'type': 'GLOVES', 'stats': {'P': 10}, 'icon': 'gloves.png', 'desc': '그립을 단단히 잡아주는 조사 장갑 (힘 +10 · 민물·바다 공용)'},
  {'name': '바다 파워벨트', 'price': 20000, 'category': 'SEA', 'type': 'BELT', 'stats': {'P': 10}, 'icon': 'belt_sea.png', 'desc': '허리 힘을 실어주는 선상 파워벨트 (힘 +10 · 바다 전용)'},
  {'name': '민물 뜰채', 'price': 20000, 'category': 'FW', 'type': 'NET', 'stats': {'C': 10}, 'icon': 'net_fw.png', 'desc': '큰 물고기도 안정적으로 랜딩하는 민물 뜰채 (컨트롤 +10)'},
  {'name': '바다 뜰채', 'price': 20000, 'category': 'SEA', 'type': 'NET', 'stats': {'C': 10}, 'icon': 'net_sea.png', 'desc': '대물 랜딩용 튼튼한 바다 뜰채 (컨트롤 +10)'},
  // 🧵 낚시줄 — 힘 +10, 내구도 200m(랜딩 실패 시 −10m, 0m면 끊어짐)
  {'name': '민물 낚시줄', 'price': 10000, 'category': 'FW', 'type': 'LINE', 'quantity': 1, 'dur': 200, 'stats': {'P': 10}, 'icon': 'line_fw.png', 'desc': '고강도 민물 카본 라인 200m (힘 +10 · 랜딩 실패 시 −10m)'},
  {'name': '바다 낚시줄', 'price': 10000, 'category': 'SEA', 'type': 'LINE', 'quantity': 1, 'dur': 200, 'stats': {'P': 10}, 'icon': 'line_sea.png', 'desc': '대물용 바다 원줄 200m (힘 +10 · 랜딩 실패 시 −10m)'},
  // 🍚 밑밥 — 감도 +10(낚시터당 1개 소모, 세션 버프)
  {'name': '민물 밑밥', 'price': 5000, 'category': 'FW', 'type': 'GROUNDBAIT', 'quantity': 50, 'stats': {'S': 10}, 'icon': 'chum_fw.png', 'desc': '물고기를 불러 모으는 민물 밑밥 (감도 +10 · 낚시터당 1개 소모)'},
  {'name': '바다 밑밥', 'price': 5000, 'category': 'SEA', 'type': 'GROUNDBAIT', 'quantity': 50, 'stats': {'S': 10}, 'icon': 'chum_sea.png', 'desc': '집어 효과 확실한 바다 밑밥 (감도 +10 · 낚시터당 1개 소모)'},
  {'name': '새우 채집망', 'price': 5000, 'category': 'FW', 'type': 'TRAP', 'icon': 'item_shrimp_trap.png', 'desc': '민물에 던져두면 민물새우가 모여요. 낚시 중 던져놓고 미끼를 자동 채집! (1분에 2마리)'},
  {'name': '소형 아이스박스', 'price': 20000, 'category': 'COMMON', 'type': 'COOLER', 'stats': {'P': 5, 'C': 5, 'S': 5}, 'icon': 'cooler_s.png', 'desc': '잡은 고기를 신선하게 보관하는 휴대용 보냉 아이스박스 (민물·바다 공용)'},
  {'name': '중형 아이스박스', 'price': 40000, 'category': 'COMMON', 'type': 'COOLER', 'stats': {'P': 10, 'C': 10, 'S': 10}, 'icon': 'cooler_m.png', 'desc': '넉넉한 용량의 캠피싱 정품 아이스박스 (민물·바다 공용)'},
  {'name': '대형 아이스박스', 'price': 80000, 'category': 'COMMON', 'type': 'COOLER', 'stats': {'P': 20, 'C': 20, 'S': 20}, 'icon': 'cooler_l.png', 'desc': '바퀴까지 달린 프로 앵글러용 대형 아이스박스 (민물·바다 공용)'},
  {'name': '민물 휘장', 'price': 100000, 'category': 'FW', 'type': 'ETC', 'stats': {'P': 50, 'C': 50, 'S': 50}, 'icon': 'item_badge_fw.png', 'desc': '민물 낚시 명예의 증표'},
  {'name': '바다 휘장', 'price': 100000, 'category': 'SEA', 'type': 'ETC', 'stats': {'P': 50, 'C': 50, 'S': 50}, 'icon': 'item_badge_sea.png', 'desc': '바다 낚시 명예의 증표'},
];

// 👕 스킨/티켓 탭 — 조사 스킨 · 이용권 · 입장권
final List<Map<String, dynamic>> storeSkinItems = [
  {'name': '대회 1시간 이용권', 'price': 1000, 'category': 'TICKET', 'type': 'ETC', 'icon': 'item_ticket_1h.png', 'desc': '캠피싱 낚시대회 1시간 프리미엄 입장권입니다.\n(계정당 1일 1회 이용 가능)',},
  {'name': '아레나 입장권', 'price': 2000, 'category': 'TICKET', 'type': 'ETC', 'quantity': 1, 'icon': 'arena_ticket.png', 'desc': '아레나 무료 입장 2회를 다 쓴 뒤,\n하루 1회 더 참가할 수 있는 입장권이에요.\n🎟️ 낚시시간 10분을 채워줘서, 시간이 없어도 참가 가능!\n(하루 1장 사용 · 여러 장 보관 가능)',},
  {'name': '초보 조사', 'price': 0, 'category': 'SKIN', 'type': 'SKIN', 'stats': {'P': 10, 'C': 10, 'S': 10}, 'icon': '../images/skin_beginner.jpg', 'desc': '가장 기본적인 낚시꾼 복장'},
  {'name': '하수 조사', 'price': 2000, 'category': 'SKIN', 'type': 'SKIN', 'stats': {'P': 20, 'C': 20, 'S': 20}, 'icon': '../images/skin_novice.jpg', 'desc': '낚시에 맛을 들인 조사 (쇼핑몰 전용)', 'reqLevel': 15},
  {'name': '중수 조사', 'price': 5000, 'category': 'SKIN', 'type': 'SKIN', 'stats': {'P': 50, 'C': 50, 'S': 50}, 'icon': '../images/skin_intermediate.jpg', 'desc': '포인트 보는 눈이 생긴 조사 (쇼핑몰 전용)', 'reqLevel': 30},
  {'name': '고수 조사', 'price': 20000, 'category': 'SKIN', 'type': 'SKIN', 'stats': {'P': 100, 'C': 100, 'S': 100}, 'icon': '../images/skin_expert.jpg', 'desc': '어디서든 한 마리는 낚아내는 고수 (쇼핑몰 전용)', 'reqLevel': 50},
  {'name': '프로 조사', 'price': 50000, 'category': 'SKIN', 'type': 'SKIN', 'stats': {'P': 200, 'C': 200, 'S': 200}, 'icon': '../images/skin_pro.jpg', 'desc': '스폰서를 받는 프로 앵글러 (쇼핑몰 전용)', 'reqLevel': 70},
  {'name': '마스터 조사', 'price': 100000, 'category': 'SKIN', 'type': 'SKIN', 'stats': {'P': 300, 'C': 300, 'S': 300}, 'icon': '../images/skin_master.jpg', 'desc': '낚시계의 살아있는 전설 (쇼핑몰 전용)', 'reqLevel': 100},
];

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
  // 발표 전 스킨 임시값 (마스터 300 → 레전드 400 → 낚시의 신 500)
  if (name == '레전드 조사') return {'P': 400, 'C': 400, 'S': 400};
  if (name == '낚시의 신') return {'P': 500, 'C': 500, 'S': 500};
  return {'P': 10, 'C': 10, 'S': 10};
}

