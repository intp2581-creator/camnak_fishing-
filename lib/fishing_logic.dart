import 'dart:math' as math;
import 'package:audioplayers/audioplayers.dart';
import 'game_config.dart'; // 1탄에서 만든 중앙 통제실 연결!

// =========================================================================
// 🎵 [캠피싱 사운드 매니저] 
// BGM과 효과음을 통제하는 방송실입니다.
// =========================================================================
class AudioManager {
  static final AudioManager _instance = AudioManager._internal();
  factory AudioManager() { return _instance; }
  AudioManager._internal();

  final AudioPlayer bgmPlayer = AudioPlayer();
  final AudioPlayer efxPlayer = AudioPlayer();
  bool isMuted = false;
  String currentBgm = "";

  Future<void> playBgm(String fileName) async {
    if (isMuted) return;
    if (currentBgm == fileName) return; 
    
    currentBgm = fileName;
    await bgmPlayer.setReleaseMode(ReleaseMode.loop);
    await bgmPlayer.setVolume(0.7);
    await bgmPlayer.play(AssetSource('sound/$fileName'));
  }

  Future<void> playSfx(String fileName) async {
    if (isMuted) return;
    if (fileName.contains('landing') && efxPlayer.state == PlayerState.playing) return;

    try {
      // 💡 1차 방어: 다른 소리가 나고 있으면 확실하게 먼저 입을 막는다!
      if (efxPlayer.state == PlayerState.playing) {
        await efxPlayer.stop();
      }
      
      // 소리 재생!
      await efxPlayer.play(AssetSource('sound/$fileName'));
      
    } catch (e) {
      // 💡 2차 방어 (핵심): 연타 때문에 웹에서 AbortError가 터져도, 
      // 앱이 멈추지 않고 그냥 소리 하나 씹힌 걸로 자연스럽게 넘어가게 만듭니다!
   }
  }

  void stopEfx() { efxPlayer.stop(); }
  Future<void> stopBgm() async { currentBgm = ""; await bgmPlayer.stop(); }
  Future<void> toggleMute() async {
    isMuted = !isMuted;
    if (isMuted) { await bgmPlayer.pause(); await efxPlayer.stop(); } 
    else { if (currentBgm.isNotEmpty) await bgmPlayer.resume(); }
  }
}

final audioManager = AudioManager();

// =========================================================================
// 🧠 [캠피싱 게임 두뇌 (로직 센터)]
// 물고기 생성, 스탯 계산 등 복잡한 수학 공식이 모여있는 곳입니다.
// =========================================================================
class FishingLogic {
  
  // 🗺️ [어종 대통합 도감] 민물은 모든 민물고기! 바다는 모든 바다고기!
  static final Map<String, List<String>> locationFishMap = {
    // 🏞️ [민물] 저수지 & 수로 (민물고기 10종 총출동!)
    '예산 예당지': ['붕어', '떡붕어', '블루길', '베스', '살치', '잉어', '메기', '자라', '가물치', '강준치'],
    '안성 고삼지': ['붕어', '떡붕어', '블루길', '베스', '살치', '잉어', '메기', '자라', '가물치', '강준치'],
    '진천 백곡지': ['붕어', '떡붕어', '블루길', '베스', '살치', '잉어', '메기', '자라', '가물치', '강준치'],
    '춘천 파로호': ['붕어', '떡붕어', '블루길', '베스', '살치', '잉어', '메기', '자라', '가물치', '강준치'],
    '충주 충주호': ['붕어', '떡붕어', '블루길', '베스', '살치', '잉어', '메기', '자라', '가물치', '강준치'],
    '예산 신양수로': ['붕어', '떡붕어', '블루길', '베스', '살치', '잉어', '메기', '자라', '가물치', '강준치'],
    '청양 지천': ['붕어', '떡붕어', '블루길', '베스', '살치', '잉어', '메기', '자라', '가물치', '강준치'],
    '인천 청라수로': ['붕어', '떡붕어', '블루길', '베스', '살치', '잉어', '메기', '자라', '가물치', '강준치'],
    '해남 금자천': ['붕어', '떡붕어', '블루길', '베스', '살치', '잉어', '메기', '자라', '가물치', '강준치'],
    '충주 달천': ['붕어', '떡붕어', '블루길', '베스', '살치', '잉어', '메기', '자라', '가물치', '강준치'],

    // 🌊 [바다] 갯바위 & 선상 (바다고기 11종 총출동!)
    '통영 척포 갯바위': ['고등어', '우럭', '갈치', '참돔', '광어', '감성돔', '갑오징어', '주꾸미', '문어', '벵에돔', '참치'],
    '신안 가거도': ['고등어', '우럭', '갈치', '참돔', '광어', '감성돔', '갑오징어', '주꾸미', '문어', '벵에돔', '참치'],
    '완도 청산도': ['고등어', '우럭', '갈치', '참돔', '광어', '감성돔', '갑오징어', '주꾸미', '문어', '벵에돔', '참치'],
    '여수 거문도': ['고등어', '우럭', '갈치', '참돔', '광어', '감성돔', '갑오징어', '주꾸미', '문어', '벵에돔', '참치'],
    '제주 섶섬': ['고등어', '우럭', '갈치', '참돔', '광어', '감성돔', '갑오징어', '주꾸미', '문어', '벵에돔', '참치'],
    '거제 선상': ['고등어', '우럭', '갈치', '참돔', '광어', '감성돔', '갑오징어', '주꾸미', '문어', '벵에돔', '참치'],
    '오천항 선상': ['고등어', '우럭', '갈치', '참돔', '광어', '감성돔', '갑오징어', '주꾸미', '문어', '벵에돔', '참치'],
    '대천 선상': ['고등어', '우럭', '갈치', '참돔', '광어', '감성돔', '갑오징어', '주꾸미', '문어', '벵에돔', '참치'],
    '통영 선상': ['고등어', '우럭', '갈치', '참돔', '광어', '감성돔', '갑오징어', '주꾸미', '문어', '벵에돔', '참치'],
    '완도 선상': ['고등어', '우럭', '갈치', '참돔', '광어', '감성돔', '갑오징어', '주꾸미', '문어', '벵에돔', '참치'],
  };

  // 🐟 1. 물고기 생성기 (입질 왔을 때 어떤 고기인지, 사이즈는 몇인지 계산)
  static Map<String, dynamic>? generateFish({
    required bool isSea, 
    required String locationName, 
    required String currentBaitName
  }) {
    List<Map<String, dynamic>> pool = isSea ? seaFishPool : fwFishPool;
    List<String> allowedFishes = locationFishMap[locationName] ?? [];
    
    // 🎯 [핵심 패치] 미끼 + 서식지 팩트폭행 필터링!
    List<Map<String, dynamic>> availableFishes = pool.where((fish) {
      String fName = fish['name'];

      // 🚨 룰 1: 해당 낚시터 명단에 없는 고기면 가차 없이 탈락! (명단이 있을 때만)
      if (allowedFishes.isNotEmpty && !allowedFishes.contains(fName)) return false;

      // 🚨 룰 2: 육식성(블루길, 베스, 메기)은 지렁이가 아니면 쳐다도 안 봄!
      if ((fName == '블루길' || fName == '베스' || fName == '메기') && !currentBaitName.contains('지렁이')) return false;

      // 🚨 룰 3: 두족류(갑오징어, 주꾸미, 문어)는 에기가 아니면 안 붙음!
      if ((fName == '갑오징어' || fName == '주꾸미' || fName == '문어') && !currentBaitName.contains('에기')) return false;

      // 🚨 룰 4: 원래 사장님 DB(reqBait)에 걸려있던 조건도 당연히 지킴!
      if (fish['reqBait'] != null && !currentBaitName.contains(fish['reqBait'])) return false;

      return true; // 모든 깐깐한 심사를 통과한 녀석만 합격! 
    }).toList();

    // 💡 최후의 방어막: 0마리 에러 뿜는 것 방지용!
    if (availableFishes.isEmpty) {
      availableFishes = pool.where((f) => f['name'] == (isSea ? '우럭' : '붕어')).toList();
      if (availableFishes.isEmpty) availableFishes = [pool.first]; 
    }

    bool isHotSpot = (locationName == fwHotSpot || locationName == seaHotSpot);

    String currentTarget = '';
    int currentStars = 1; 
    locations.forEach((category, locList) {
      for (var loc in locList) {
        if (loc['name'] == locationName) {
          currentTarget = loc['target'] ?? '';
          currentStars = loc['stars'] ?? 1;
        }
      }
    });

    // 🎯 [미끼-어종 상성 테이블]
final Map<String, Map<String, double>> baitAffinity = {
  '글루텐': {'붕어': 2.0, '떡붕어': 2.0, '블루길': 0.5, '살치': 1.0, '베스': 0.5, '강준치': 1.5, '잉어': 1.5, '자라': 0.5, '메기': 0.5, '가물치': 0.5},
  '지렁이': {'붕어': 1.0, '떡붕어': 1.0, '블루길': 2.0, '살치': 1.5, '베스': 2.0, '강준치': 1.0, '잉어': 1.0, '자라': 2.0, '메기': 2.0, '가물치': 2.0},
  '옥수수': {'붕어': 1.5, '떡붕어': 1.5, '블루길': 0.5, '살치': 1.0, '베스': 0.5, '강준치': 2.0, '잉어': 2.0, '자라': 0.5, '메기': 0.5, '가물치': 1.0},
  '갯지렁이': {'고등어': 1.0, '우럭': 1.5, '갈치': 1.0, '참돔': 1.5, '광어': 2.0, '감성돔': 2.0, '갑오징어': 0.5, '주꾸미': 0.5, '문어': 0.5, '벵에돔': 1.0, '참치': 1.0},
  '크릴': {'고등어': 2.0, '우럭': 1.5, '갈치': 2.0, '참돔': 2.0, '광어': 1.0, '감성돔': 1.5, '갑오징어': 0.5, '주꾸미': 0.5, '문어': 0.5, '벵에돔': 2.0, '참치': 1.5},
  '루어': {'고등어': 1.0, '우럭': 2.0, '갈치': 1.5, '참돔': 1.0, '광어': 1.5, '감성돔': 1.0, '갑오징어': 0.5, '주꾸미': 0.5, '문어': 0.5, '벵에돔': 1.5, '참치': 2.0},
  '에기': {'고등어': 0.5, '우럭': 0.5, '갈치': 0.5, '참돔': 0.5, '광어': 0.5, '감성돔': 0.5, '갑오징어': 2.0, '주꾸미': 2.0, '문어': 2.0, '벵에돔': 0.5, '참치': 0.5},
};

// 🎣 가중치(확률) 룰렛 돌리기
int totalWeight = 0;
for (var fish in availableFishes) {
  int w = fish['weight'] as int? ?? 10;
  if (currentTarget.contains(fish['name'])) w = w * 5;
  if (isHotSpot && w <= 15) w = (w * 2);
  
  // 🎯 미끼 상성 보너스 적용
  String fName = fish['name'];
  double baitBonus = 1.0;
  baitAffinity.forEach((baitKey, fishMap) {
    if (currentBaitName.contains(baitKey) && fishMap.containsKey(fName)) {
      baitBonus = fishMap[fName]!;
    }
  });
  w = (w * baitBonus).round();
  
  totalWeight += w;
}


    int randomWeight = math.Random().nextInt(totalWeight);
Map<String, dynamic>? selectedFish;
int currentWeight = 0;
for (var fish in availableFishes) {
  int w = fish['weight'] as int? ?? 10;
  if (currentTarget.contains(fish['name'])) w = w * 5;
  if (isHotSpot && w <= 15) w = (w * 2);
  
  // 🎯 미끼 상성 보너스 (위와 동일하게!)
  String fName = fish['name'];
  double baitBonus = 1.0;
  baitAffinity.forEach((baitKey, fishMap) {
    if (currentBaitName.contains(baitKey) && fishMap.containsKey(fName)) {
      baitBonus = fishMap[fName]!;
    }
  });
  w = (w * baitBonus).round();
  
  currentWeight += w;
  if (randomWeight < currentWeight) {
    selectedFish = fish;
    break;
  }
}
       selectedFish ??= availableFishes.first;

    // 🎛️ 난이도(별점)에 따른 최소/최대 사이즈 및 보상 배율 설정
    double minFactor = 0.0; double sizeCap = 1.0; 
    double expMult = 1.0; double ptsMult = 1.0;

    switch (currentStars) {
      case 1: minFactor = 0.0; sizeCap = 0.2; expMult = 2.0; ptsMult = 1.0; break;
      case 2: minFactor = 0.1; sizeCap = 0.4; expMult = 2.2; ptsMult = 1.2; break;
      case 3: minFactor = 0.2; sizeCap = 0.6; expMult = 2.4; ptsMult = 1.4; break;
      case 4: minFactor = 0.3; sizeCap = 0.8; expMult = 2.6; ptsMult = 1.6; break;
      case 5:
      default: minFactor = 0.4; sizeCap = 1.0; expMult = 2.8; ptsMult = 1.8; break;
    }

    double baseMin = double.tryParse(selectedFish['min'].toString()) ?? 10.0;
    double baseMax = double.tryParse(selectedFish['max'].toString()) ?? 50.0;
    double range = baseMax - baseMin;

    double randValue = math.Random().nextDouble();
    double bellCurveRandom = (math.Random().nextInt(100) < 10) 
    ? randValue 
    : (randValue + math.Random().nextDouble() + math.Random().nextDouble()) / 3;
if (isHotSpot) bellCurveRandom = math.pow(bellCurveRandom, 0.7).toDouble();
    double effectiveMin = baseMin + (range * minFactor);
    double effectiveMax = baseMin + (range * sizeCap);
if (effectiveMax < effectiveMin) effectiveMax = effectiveMin + (range * 0.1);

    double size = effectiveMin + (bellCurveRandom * (effectiveMax - effectiveMin));

// 🎣 [별점별 상위 구간 확률 급감]
    double effectiveRange = effectiveMax - effectiveMin;
    double sizeRatioInRange = (size - effectiveMin) / effectiveRange; // 0.0 ~ 1.0

// 상위 10% 구간 진입 시 확률 급감
if (sizeRatioInRange > 0.9) {
    double overRatio = (sizeRatioInRange - 0.9) / 0.1; // 0.0 ~ 1.0
  // 지수적으로 재추첨 확률 증가 (최상위는 99% 재추첨)
    double rerollChance = math.pow(overRatio, 1.5).toDouble() * 0.99;
  if (math.Random().nextDouble() < rerollChance) {
    // 재추첨 → 해당 범위의 70~90% 구간으로 이동
    double safeRandom = 0.70 + math.Random().nextDouble() * 0.20;
    size = effectiveMin + (safeRandom * effectiveRange);
  }
}

size = double.parse(size.toStringAsFixed(1));

    // 💰 보상 계산
    double fishBaseExpMult = selectedFish['expMult'] ?? 1.0;
    int exp = (size * expMult * fishBaseExpMult).round();
    int pts = (size * ptsMult).round();

    List<String> bossFishes = ['붕어', '잉어', '가물치', '참돔', '감성돔', '문어'];
    if (bossFishes.contains(selectedFish['name'])) {
      exp = (exp * 1.2).round();
      pts = (pts * 1.2).round();
    }

    return {
      'name': selectedFish['name'], 'img': selectedFish['img'], 'size': size.toString(),
      'unit': selectedFish['unit'], 'exp': exp, 'pts': pts,
    };
  }

  // 💪 2. 내 캐릭터 총 능력치 계산기 (인벤토리용)
  static Map<String, int> getMyTotalStats({
    Map<String, dynamic>? equippedSkin,
    Map<String, dynamic>? equippedRod,
    Map<String, dynamic>? equippedFloat,
    Map<String, dynamic>? equippedReel,
    Map<String, dynamic>? equippedSunglasses,
    Map<String, dynamic>? equippedBadge,
  }) {
    int totalStr = 10; int totalCtrl = 10; int totalSens = 10;

    void addStats(Map<String, dynamic>? item) {
      if (item == null || item['stats'] == null) return;
      var s = item['stats'];
      totalStr += int.tryParse(s['P']?.toString() ?? s['힘']?.toString() ?? '0') ?? 0;
      totalCtrl += int.tryParse(s['C']?.toString() ?? s['컨트롤']?.toString() ?? '0') ?? 0;
      totalSens += int.tryParse(s['S']?.toString() ?? s['감도']?.toString() ?? '0') ?? 0;
    }

    addStats(equippedSkin);       
    addStats(equippedRod);        
    addStats(equippedFloat);      
    addStats(equippedReel);       
    addStats(equippedSunglasses); 
    addStats(equippedBadge);      

    return {'strength': totalStr, 'control': totalCtrl, 'sensitivity': totalSens};
  }

  // 🛡️ 길드 레벨/버프 (광장·낚시 공용 계산식)
  // guildExpTable[레벨] = 그 레벨이 되기 위한 누적 길드 경험치(=누적 마릿수) (index 0 미사용, 최대 Lv30)
  static const List<int> guildExpTable = [
    0,      // 0 (미사용)
    0,      // Lv1
    50,     // Lv2
    150,    // Lv3
    300,    // Lv4
    500,    // Lv5
    800,    // Lv6
    1200,   // Lv7
    1700,   // Lv8
    2300,   // Lv9
    3000,   // Lv10
    3900,   // Lv11
    5000,   // Lv12
    6300,   // Lv13
    7800,   // Lv14
    9500,   // Lv15
    11500,  // Lv16
    13800,  // Lv17
    16400,  // Lv18
    19300,  // Lv19
    22500,  // Lv20
    26100,  // Lv21
    30100,  // Lv22
    34500,  // Lv23
    39300,  // Lv24
    44500,  // Lv25
    50200,  // Lv26
    56400,  // Lv27
    63100,  // Lv28
    70300,  // Lv29
    78000,  // Lv30
  ];
  static const int guildMaxLevel = 30;
  static const int guildExpPerCatch = 1; // 길드원이 물고기 1마리 잡을 때마다 누적

  static int guildLevelFromExp(int exp) {
    int lv = 1;
    for (int l = 2; l < guildExpTable.length; l++) {
      if (exp >= guildExpTable[l]) {
        lv = l;
      } else {
        break;
      }
    }
    return lv;
  }

  // 길드 레벨이 주는 능력치 보너스(힘/컨트롤/감도 각각 +레벨)
  static int guildStatBonus(int guildLevel) => guildLevel.clamp(0, guildMaxLevel);

  // 👤 3. 스킨(호칭)에 맞는 투명 캐릭터 이미지 찾아주기
  static String getLobbyCharacterImage(String skinName) {
    String cleanName = skinName.replaceAll(' ', '').toUpperCase();
    if (cleanName.contains('하수')) return 'assets/images/char_novice.png';
    if (cleanName.contains('중수')) return 'assets/images/char_intermediate.png';
    if (cleanName.contains('고수')) return 'assets/images/char_expert.png';
    if (cleanName.contains('프로')) return 'assets/images/char_pro.png';
    if (cleanName.contains('마스터')) return 'assets/images/char_master.png';
    
    return 'assets/images/char_beginner.png'; 
  }
}