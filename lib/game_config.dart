// ignore_for_file: non_constant_identifier_names
import 'package:flutter/material.dart';

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
bool? globalIsSeaMode; // 민물/바다 모드가 바뀌었는지 체크용


// =========================================================================
// 📈 [경험치 & 레벨 밸런스 테이블]
// 사장님! 이제 여기서 경험치 통을 한 번에 조절하세요! (HUD와 계산 로직 통합용)
// =========================================================================
final List<int> globalExpTable = [
  0,        // 인덱스 0 (안 씀)
  0,        // Lv.1
  5000,     // Lv.2
  10000,    // Lv.3
  20000,    // Lv.4
  30000,    // Lv.5 (하수 스킨!)
  50000,    // Lv.6 
  70000,   // Lv.7
  90000,   // Lv.8
  110000,   // Lv.9
  130000,   // Lv.10 (중수 스킨!)
  160000,   // Lv.11 
  190000,   // Lv.12
  210000,   // Lv.13
  240000,   // Lv.14
  270000,   // Lv.15 (고수 스킨!)
  310000,   // Lv.16 
  350000,   // Lv.17
  390000,  // Lv.18
  430000,  // Lv.19
  500000,  // Lv.20 (프로 스킨!)
  550000,  // Lv.21 
  600000,  // Lv.22
  650000,  // Lv.23
  700000,  // Lv.24
  800000,  // Lv.25 (마스터 스킨!)
  900000,  // Lv.26 
  1000000,  // Lv.27
  1100000,  // Lv.28
  1200000,  // Lv.29
  1300000,   // Lv.30 (현재 만렙!)
];

// 전역 레벨 계산기 함수
int calcLevelFromExp(int exp) {
  for (int i = 30; i >= 1; i--) {
    if (exp >= globalExpTable[i]) return i;
  }
  return 1;
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
      {'name': '예산 예당지', 'target': '국민 낚시터! 메기/베스를 원하면 지렁이 필수', 'stars': 1, 'image': 'assets/fields/bg_yedang.jpg'},
      {'name': '안성 고삼지', 'target': '월척급 붕어와 가물치! 육식어종은 지렁이 추천', 'stars': 2, 'image': 'assets/fields/bg_gosam.jpg'},
      {'name': '진천 백곡지', 'target': '허릿급 붕어 명당! 메기/가물치는 지렁이 추천', 'stars': 3, 'image': 'assets/fields/bg_baekgok.jpg'},
      {'name': '춘천 파로호', 'target': '4짜 붕어와 강준치! 다양한 어종의 천국', 'stars': 4, 'image': 'assets/fields/bg_paro.jpg'},
      {'name': '충주 충주호', 'target': '대물 붕어 랭킹 도전! (🚨최대어 출연 주의)', 'stars': 5, 'image': 'assets/fields/bg_chungju.jpg'}
    ],
    '수로': [
      {'name': '예산 신양수로', 'target': '붕어 마릿수! 메기/베스는 지렁이 껴주세요', 'stars': 1, 'image': 'assets/fields/bg_sinyang.jpg'},
      {'name': '청양 지천', 'target': '씨알 좋은 붕어와 강준치! 지렁이 추천', 'stars': 2, 'image': 'assets/fields/bg_jicheon.jpg'},
      {'name': '인천 청라수로', 'target': '수도권 붕어 핫스팟! 블루길/베스는 지렁이', 'stars': 3, 'image': 'assets/fields/bg_chungla.jpg'},
      {'name': '해남 금자천', 'target': '겨울 붕어 명당! 지렁이 달면 메기/베스 입질', 'stars': 4, 'image': 'assets/fields/bg_gumja.jpg'},
      {'name': '충주 달천', 'target': '풍부한 어종! 미끼에 따라 입질이 완벽히 갈림', 'stars': 5, 'image': 'assets/fields/bg_dalchun.jpg'}
    ],
    '갯바위': [
      {'name': '통영 척포 갯바위', 'target': '감성돔, 참돔 대물 포인트! 두족류는 에기 필수', 'stars': 1, 'image': 'assets/fields/bg_chukpo.jpg'},
      {'name': '신안 가거도', 'target': '벵에돔과 감성돔 성지! 갑오징어는 에기 추천', 'stars': 2, 'image': 'assets/fields/bg_gageo.jpg'},
      {'name': '완도 청산도', 'target': '다양한 돔류와 문어 서식지! 에기 챙겨가세요', 'stars': 3, 'image': 'assets/fields/bg_cheongsan.jpg'},
      {'name': '여수 거문도', 'target': '씨알 좋은 돔과 👑참치 등장! 두족류는 에기', 'stars': 4, 'image': 'assets/fields/bg_geumo.jpg'},
      {'name': '제주 섶섬', 'target': '미터급 👑참치 랭킹 도전! 문어 타작은 에기', 'stars': 5, 'image': 'assets/fields/bg_seop.jpg'}
    ],
    '선상': [
      {'name': '거제 선상', 'target': '참돔, 광어 선상 낚시! 두족류 3형제는 에기 필수', 'stars': 1, 'image': 'assets/fields/bg_geo_ship.jpg'},
      {'name': '오천항 선상', 'target': '주꾸미, 갑오징어 선상 타작 명당! 에기 필수', 'stars': 2, 'image': 'assets/fields/bg_ocheon_ship.jpg'},
      {'name': '대천 선상', 'target': '대물 우럭과 문어 핫스팟! 문어는 무조건 에기', 'stars': 3, 'image': 'assets/fields/bg_daecheon_ship.jpg'},
      {'name': '통영 선상', 'target': '은빛 대물 갈치와 👑참치 등장! 주꾸미는 에기', 'stars': 4, 'image': 'assets/fields/bg_tong_ship.jpg'},
      {'name': '완도 선상', 'target': '대형 👑참치 랭킹 도전! 두족류 싹쓸이는 에기 추천', 'stars': 5, 'image': 'assets/fields/bg_wando_ship.jpg'}
    ]
  };


// =========================================================================
// 🛒 [KREFT 상점 및 초기 지급 장비 데이터]
// =========================================================================

// 🎁 신규 유저에게 지급되는 12종 스타터 팩!
List<Map<String, dynamic>> getInitialStarterPack() {
  return [
    {'name': '초보 조사', 'category': 'SKIN', 'type': 'SKIN', 'stats': {'P': 10, 'C': 10, 'S': 10}, 'icon': '../images/skin_beginner.jpg', 'desc': 'KREFT 조사의 기본 복장'},
    {'name': 'CF-20T', 'category': 'FW', 'type': 'ROD', 'stats': {'P': 0, 'C': 0, 'S': 0}, 'icon': 'rod_fw_cf20.png', 'desc': '초보 조사용 기본 민물대'},
    {'name': '일반찌', 'category': 'FW', 'type': 'FLOAT', 'stats': {'S': 0}, 'icon': 'float_fw_normal.png', 'desc': '가장 기본적인 민물 찌'},
    {'name': '글루텐', 'category': 'FW', 'type': 'BAIT', 'quantity': 50, 'icon': 'bait_fw_gluten.png', 'desc': '붕어 집어에 탁월한 미끼 (20)'},
    {'name': '지렁이', 'category': 'FW', 'type': 'BAIT', 'quantity': 50, 'icon': 'bait_fw_worm.png', 'desc': '민물 만능 미끼 (10)'},
    {'name': '옥수수', 'category': 'FW', 'type': 'BAIT', 'quantity': 50, 'icon': 'bait_fw_corn.png', 'desc': '대물 붕어용 미끼 (30)'},
    {'name': 'CF250', 'category': 'SEA', 'type': 'ROD', 'stats': {'P': 0, 'C': 0, 'S': 0}, 'icon': 'rod_sea_cf250.png', 'desc': '바다 낚시 입문용 기본대'},
    {'name': 'CF2000', 'category': 'SEA', 'type': 'REEL', 'stats': {'P': 0}, 'icon': 'reel_sea_cf2000.png', 'desc': '기본 제공되는 바다 릴'},
    {'name': '갯지렁이', 'category': 'SEA', 'type': 'BAIT', 'quantity': 50, 'icon': 'bait_sea_worm.png', 'desc': '바다 낚시 기본 미끼 (10)'},
    {'name': '크릴', 'category': 'SEA', 'type': 'BAIT', 'quantity': 50, 'icon': 'bait_sea_krill.png', 'desc': '전천후 바다 미끼 (20)'},
    {'name': '루어', 'category': 'SEA', 'type': 'BAIT', 'quantity': 50, 'icon': 'bait_sea_lure.png', 'desc': '육식성 어종 전용 (30)'},
    {'name': '에기', 'category': 'SEA', 'type': 'BAIT', 'quantity': 50, 'icon': 'bait_sea_egi.png', 'desc': '두족류 전용 미끼 (30)'},
  ];
}

// 🎣 상점: 낚싯대 목록
final List<Map<String, dynamic>> storeRodItems = [
  {'name': 'CF-20T', 'price': 0, 'category': 'FW', 'type': 'ROD', 'stats': {'P': 0, 'C': 0, 'S': 0}, 'icon': 'rod_fw_cf20.png', 'desc': '초보 조사용 기본 민물대'},
  {'name': 'CF-30T', 'price': 10000, 'category': 'FW', 'type': 'ROD', 'stats': {'P': 10, 'C': 10, 'S': 10}, 'icon': 'rod_fw_cf30.png', 'desc': '입문자를 위한 밸런스형 민물대'},
  {'name': 'CF-40T', 'price': 30000, 'category': 'FW', 'type': 'ROD', 'stats': {'P': 20, 'C': 20, 'S': 20}, 'icon': 'rod_fw_cf40.png', 'desc': '중급 조사용 고탄성 민물대'},
  {'name': 'KT-20T', 'price': 50000, 'category': 'FW', 'type': 'ROD', 'stats': {'P': 30, 'C': 30, 'S': 30}, 'icon': 'rod_fw_kt20.png', 'desc': '프리미엄 KREFT 민물대'},
  {'name': 'KT-30T', 'price': 100000, 'category': 'FW', 'type': 'ROD', 'stats': {'P': 40, 'C': 40, 'S': 40}, 'icon': 'rod_fw_kt30.png', 'desc': '대물 붕어 제압용 프로 민물대'},
  {'name': 'KT-40T', 'price': 200000, 'category': 'FW', 'type': 'ROD', 'stats': {'P': 50, 'C': 50, 'S': 50}, 'icon': 'rod_fw_kt40.png', 'desc': '민물 낚시의 정점, 마스터 민물대'},
  {'name': 'CF250', 'price': 0, 'category': 'SEA', 'type': 'ROD', 'stats': {'P': 0, 'C': 0, 'S': 0}, 'icon': 'rod_sea_cf250.png', 'desc': '바다 낚시 입문용 기본대'},
  {'name': 'CF350', 'price': 10000, 'category': 'SEA', 'type': 'ROD', 'stats': {'P': 10, 'C': 10, 'S': 10}, 'icon': 'rod_sea_cf350.png', 'desc': '연안 방파제용 전천후 바다대'},
  {'name': 'CF500', 'price': 30000, 'category': 'SEA', 'type': 'ROD', 'stats': {'P': 20, 'C': 20, 'S': 10}, 'icon': 'rod_sea_cf500.png', 'desc': '원투 낚시에 최적화된 바다대'},
  {'name': 'KT250', 'price': 50000, 'category': 'SEA', 'type': 'ROD', 'stats': {'P': 30, 'C': 20, 'S': 10}, 'icon': 'rod_sea_kt250.png', 'desc': '선상 낚시의 표준, KREFT 바다대'},
  {'name': 'KT350', 'price': 100000, 'category': 'SEA', 'type': 'ROD', 'stats': {'P': 40, 'C': 40, 'S': 40}, 'icon': 'rod_sea_kt350.png', 'desc': '프로 앵글러를 위한 고강도 바다대'},
  {'name': 'KT500', 'price': 200000, 'category': 'SEA', 'type': 'ROD', 'stats': {'P': 50, 'C': 50, 'S': 50}, 'icon': 'rod_sea_kt500.png', 'desc': '심해 대물 제압용 마스터 바다대'},
];

// ⚙️ 상점: 릴 & 찌 목록
final List<Map<String, dynamic>> storeGearItems = [
  {'name': '일반찌', 'price': 0, 'category': 'FW', 'type': 'FLOAT', 'stats': {'S': 0}, 'icon': 'float_fw_normal.png', 'desc': '가장 기본적인 민물 찌'},
  {'name': '오동나무찌', 'price': 5000, 'category': 'FW', 'type': 'FLOAT', 'stats': {'P': 10, 'C': 10, 'S': 10}, 'icon': 'float_fw_wood.png', 'desc': '예민한 입질 파악을 위한 찌'},
  {'name': '수제찌', 'price': 10000, 'category': 'FW', 'type': 'FLOAT', 'stats': {'P': 15, 'C': 15, 'S': 15}, 'icon': 'float_fw_handmade.png', 'desc': '장인이 깎아 만든 고감도 수제찌'},
  {'name': '나노카본찌', 'price': 30000, 'category': 'FW', 'type': 'FLOAT', 'stats': {'P': 20, 'C': 20, 'S': 20}, 'icon': 'float_fw_nano.png', 'desc': '최첨단 소재로 만든 초정밀 찌'},
  {'name': 'CF 전자찌', 'price': 50000, 'category': 'FW', 'type': 'FLOAT', 'stats': {'P': 25, 'C': 25, 'S': 25}, 'icon': 'float_fw_elec_cf.png', 'desc': '야간 낚시의 필수품'},
  {'name': 'KT 전자찌', 'price': 100000, 'category': 'FW', 'type': 'FLOAT', 'stats': {'P': 30, 'C': 30, 'S': 30}, 'icon': 'float_fw_elec_kt.png', 'desc': '압도적인 시인성을 자랑하는 최고급 전자찌'},
  {'name': 'cf2000', 'price': 0, 'category': 'SEA', 'type': 'REEL', 'stats': {'P': 0}, 'icon': 'reel_sea_cf2000.png', 'desc': '기본 제공되는 바다 릴'},
  {'name': 'CF3000', 'price': 5000, 'category': 'SEA', 'type': 'REEL', 'stats': {'P': 10, 'C': 10, 'S': 10}, 'icon': 'reel_sea_cf3000.png', 'desc': '방파제용 경량 릴'},
  {'name': 'CF5000', 'price': 10000, 'category': 'SEA', 'type': 'REEL', 'stats': {'P': 15, 'C': 15, 'S': 15}, 'icon': 'reel_sea_cf5000.png', 'desc': '원투 낚시용 중형 릴'},
  {'name': 'KF5000', 'price': 30000, 'category': 'SEA', 'type': 'REEL', 'stats': {'P': 20, 'C': 20, 'S': 20}, 'icon': 'reel_sea_kf5000.png', 'desc': '선상 낚시용 고급 릴'},
  {'name': 'KF6000', 'price': 50000, 'category': 'SEA', 'type': 'REEL', 'stats': {'P': 25, 'C': 25, 'S': 25}, 'icon': 'reel_sea_kf6000.png', 'desc': '대형 어종 제압을 위한 강력한 릴'},
  {'name': 'KF8000', 'price': 100000, 'category': 'SEA', 'type': 'REEL', 'stats': {'P': 30, 'C': 30, 'S': 30}, 'icon': 'reel_sea_kf8000.png', 'desc': '괴물과 싸우기 위한 마스터급 대형 릴'},
];

// 🪱 상점: 미끼 목록
final List<Map<String, dynamic>> storeBaitItems = [
  {'name': '지렁이', 'price': 500, 'category': 'FW', 'type': 'BAIT', 'quantity': 50, 'icon': 'bait_fw_worm.png', 'desc': '민물 잡어부터 붕어까지 만능 미끼 (집어력 10)'},
  {'name': '글루텐', 'price': 600, 'category': 'FW', 'type': 'BAIT', 'quantity': 50, 'icon': 'bait_fw_gluten.png', 'desc': '붕어 집어에 탁월한 미끼 (집어력 20)'},
  {'name': '옥수수', 'price': 700, 'category': 'FW', 'type': 'BAIT', 'quantity': 50, 'icon': 'bait_fw_corn.png', 'desc': '대물 붕어를 노리기 위한 미끼 (집어력 30)'},
  {'name': '갯지렁이', 'price': 500, 'category': 'SEA', 'type': 'BAIT', 'quantity': 50, 'icon': 'bait_sea_worm.png', 'desc': '바다 낚시의 기본 미끼 (집어력 10)'},
  {'name': '크릴', 'price': 600, 'category': 'SEA', 'type': 'BAIT', 'quantity': 50, 'icon': 'bait_sea_krill.png', 'desc': '다양한 어종을 유혹하는 미끼 (집어력 20)'},
  {'name': '루어', 'price': 700, 'category': 'SEA', 'type': 'BAIT', 'quantity': 50, 'icon': 'bait_sea_lure.png', 'desc': '육식성 어종을 노리는 가짜 미끼 (집어력 30)'},
  {'name': '에기', 'price': 700, 'category': 'SEA', 'type': 'BAIT', 'quantity': 50, 'icon': 'bait_sea_egi.png', 'desc': '두족류(오징어, 문어 등) 전용 미끼 (집어력 30)'},
];

// 😎 상점: 스킨 및 악세서리 목록
final List<Map<String, dynamic>> storeSkinItems = [
  {'name': '대회 1시간 이용권', 'price': 1000, 'category': 'TICKET', 'type': 'ETC', 'icon': 'item_ticket_1h.png', 'desc': '캠피싱 낚시대회 1시간 프리미엄 입장권입니다.\n(계정당 1일 1회 이용 가능)',},
  {'name': '선글라스', 'price': 10000, 'category': 'COMMON', 'type': 'ETC', 'stats': {'P': 10, 'C': 10, 'S': 10}, 'icon': 'item_sunglasses.png', 'desc': '눈부심을 막아 찌를 잘 보게 해주는 장비'},
  {'name': '민물 휘장', 'price': 100000, 'category': 'FW', 'type': 'ETC', 'stats': {'P': 50, 'C': 50, 'S': 50}, 'icon': 'item_badge_fw.png', 'desc': '민물 낚시 명예의 증표'},
  {'name': '바다 휘장', 'price': 100000, 'category': 'SEA', 'type': 'ETC', 'stats': {'P': 50, 'C': 50, 'S': 50}, 'icon': 'item_badge_sea.png', 'desc': '바다 낚시 명예의 증표'},
  {'name': '초보 조사', 'price': 0, 'category': 'SKIN', 'type': 'SKIN', 'stats': {'P': 10, 'C': 10, 'S': 10}, 'icon': '../images/skin_beginner.jpg', 'desc': '가장 기본적인 낚시꾼 복장'},
  {'name': '하수 조사', 'price': 2000, 'category': 'SKIN', 'type': 'SKIN', 'stats': {'P': 20, 'C': 20, 'S': 20}, 'icon': '../images/skin_novice.jpg', 'desc': '낚시에 맛을 들인 조사 (쇼핑몰 전용)', 'reqLevel': 5},
  {'name': '중수 조사', 'price': 5000, 'category': 'SKIN', 'type': 'SKIN', 'stats': {'P': 50, 'C': 50, 'S': 50}, 'icon': '../images/skin_intermediate.jpg', 'desc': '포인트 보는 눈이 생긴 조사 (쇼핑몰 전용)', 'reqLevel': 10},
  {'name': '고수 조사', 'price': 20000, 'category': 'SKIN', 'type': 'SKIN', 'stats': {'P': 100, 'C': 100, 'S': 100}, 'icon': '../images/skin_expert.jpg', 'desc': '어디서든 한 마리는 낚아내는 고수 (쇼핑몰 전용)', 'reqLevel': 15},
  {'name': '프로 조사', 'price': 50000, 'category': 'SKIN', 'type': 'SKIN', 'stats': {'P': 200, 'C': 200, 'S': 200}, 'icon': '../images/skin_pro.jpg', 'desc': '스폰서를 받는 프로 앵글러 (쇼핑몰 전용)', 'reqLevel': 20},
  {'name': '마스터 조사', 'price': 100000, 'category': 'SKIN', 'type': 'SKIN', 'stats': {'P': 300, 'C': 300, 'S': 300}, 'icon': '../images/skin_master.jpg', 'desc': '낚시계의 살아있는 전설 (쇼핑몰 전용)', 'reqLevel': 25},
];

