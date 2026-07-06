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
  final AudioPlayer ambientPlayer = AudioPlayer(); // 🌧️ 빗소리 등 앰비언트(BGM 위에 겹침)
  bool isMuted = false;
  String currentBgm = "";
  int _rainRefs = 0; // 🌧️ 빗소리를 원하는 화면 수(플라자·낚시터 겹침 대비 참조 카운트)

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

  // 🌧️ 빗소리: 비 오는 화면이 요청/해제. 참조가 1 이상이면 반복 재생.
  Future<void> requestRain() async {
    _rainRefs++;
    if (_rainRefs == 1) await _startRain();
  }
  Future<void> releaseRain() async {
    if (_rainRefs > 0) _rainRefs--;
    if (_rainRefs == 0) { try { await ambientPlayer.stop(); } catch (_) {} }
  }
  Future<void> _startRain() async {
    if (isMuted) return; // 음소거면 소리만 안 냄(참조는 유지 → 해제 시 정상 카운트)
    try {
      await ambientPlayer.setReleaseMode(ReleaseMode.loop);
      await ambientPlayer.setVolume(0.4);
      await ambientPlayer.play(AssetSource('sound/rain_loop.mp3'));
    } catch (_) {} // 파일 없거나 웹 오디오 에러여도 게임엔 지장 없음
  }

  Future<void> toggleMute() async {
    isMuted = !isMuted;
    if (isMuted) { await bgmPlayer.pause(); await efxPlayer.stop(); try { await ambientPlayer.stop(); } catch (_) {} }
    else {
      if (currentBgm.isNotEmpty) await bgmPlayer.resume();
      if (_rainRefs > 0) await _startRain(); // 🌧️ 음소거 해제 시 비 오는 중이면 빗소리 재개
    }
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

      // 🎯 [미끼 선호도 개편] 예전 하드락(블루길/베스/메기=지렁이, 두족류=에기, reqBait)은 제거.
      //    "전용 미끼 아니면 아예 안 물림" → "전용 미끼는 잘 물고, 다른 미끼는 확률만 낮게(가끔)"
      //    실제 보정은 아래 baitAffinity 배율(전용 어종 0.2 패널티)로 부드럽게 처리.

      return true; // 위치(룰1)만 통과하면 후보 — 미끼 적합도는 가중치로 반영
    }).toList();

    // 💡 최후의 방어막: 0마리 에러 뿜는 것 방지용!
    if (availableFishes.isEmpty) {
      availableFishes = pool.where((f) => f['name'] == (isSea ? '우럭' : '붕어')).toList();
      if (availableFishes.isEmpty) availableFishes = [pool.first]; 
    }

    bool isHotSpot = (locationName == fwHotSpot || locationName == seaHotSpot);

    int currentStars = 1;
    locations.forEach((category, locList) {
      for (var loc in locList) {
        if (loc['name'] == locationName) {
          currentStars = loc['stars'] ?? 1;
        }
      }
    });

    // 🎯 [미끼-어종 상성 테이블]
// 🎯 미끼별 어종 선호도(배율). 표에 없는 어종 = 1.0(중립). 전용 어종 미스매치 = 0.2(가끔만 물림).
//    숫자만 바꾸면 밸런스 조정 가능 (예: 더 잘 잡히게 ↑, 더 어렵게 ↓).
final Map<String, Map<String, double>> baitAffinity = {
  // ── 민물 ──
  '글루텐':   {'붕어': 2.0, '잉어': 1.5, '가물치': 0.3, '떡붕어': 2.0, '블루길': 0.2, '살치': 1.0, '베스': 0.2, '강준치': 1.5, '자라': 0.3, '메기': 0.2},
  '지렁이':   {'붕어': 1.0, '잉어': 1.0, '가물치': 2.0, '떡붕어': 1.0, '블루길': 2.0, '살치': 1.5, '베스': 2.0, '강준치': 1.0, '자라': 1.0, '메기': 2.0},
  '옥수수':   {'붕어': 1.5, '잉어': 2.0, '가물치': 0.5, '떡붕어': 1.5, '블루길': 0.2, '살치': 1.0, '베스': 0.2, '강준치': 2.0, '자라': 1.0, '메기': 0.2},
  '민물새우': {'붕어': 2.0, '잉어': 1.5, '가물치': 2.0, '떡붕어': 1.2, '블루길': 1.5, '살치': 0.5, '베스': 1.8, '강준치': 0.5, '자라': 0.5, '메기': 1.8}, // 🦐 생새우 = 육식·대물에 강함
  // ── 바다 ──
  '갯지렁이': {'참돔': 1.5, '감성돔': 1.5, '문어': 0.2, '고등어': 1.0, '우럭': 1.5, '갈치': 2.0, '광어': 1.5, '갑오징어': 0.2, '주꾸미': 0.2, '벵에돔': 2.0, '참치': 0.5},
  '크릴':     {'참돔': 2.0, '감성돔': 2.0, '문어': 0.2, '고등어': 2.0, '우럭': 1.5, '갈치': 1.5, '광어': 1.0, '갑오징어': 0.2, '주꾸미': 0.2, '벵에돔': 1.0, '참치': 0.5},
  '루어':     {'참돔': 1.5, '감성돔': 1.0, '문어': 0.2, '고등어': 1.0, '우럭': 2.0, '갈치': 1.5, '광어': 2.0, '갑오징어': 0.2, '주꾸미': 0.2, '벵에돔': 1.5, '참치': 1.0},
  '에기':     {'참돔': 0.3, '감성돔': 0.3, '문어': 2.0, '고등어': 0.3, '우럭': 0.3, '갈치': 0.3, '광어': 0.3, '갑오징어': 2.0, '주꾸미': 2.0, '벵에돔': 0.3, '참치': 0.3},
  // 🐟 특수 미끼: 잡은 고등어를 미끼로 쓰면 참치가 잘 물림(생미끼)
  '고등어':   {'참치': 1.5},
};

// 🎣 가중치(확률) 룰렛 돌리기
int totalWeight = 0;
for (var fish in availableFishes) {
  int w = fish['weight'] as int? ?? 10;
  // (지정어종 ×5 제거) — 이제 미끼 상성 + 장소 종류 + 별점 규칙만으로 출현 결정
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
  // 🗺️ 낚시터 종류(저수지/수로/갯바위/선상)별 어종 가중치
  w = (w * spotFishMult(locationName, fName)).round();

  totalWeight += w;
}


    int randomWeight = math.Random().nextInt(totalWeight);
Map<String, dynamic>? selectedFish;
int currentWeight = 0;
for (var fish in availableFishes) {
  int w = fish['weight'] as int? ?? 10;
  // (지정어종 ×5 제거) — 이제 미끼 상성 + 장소 종류 + 별점 규칙만으로 출현 결정
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
  // 🗺️ 낚시터 종류별 어종 가중치 (위와 동일하게!)
  w = (w * spotFishMult(locationName, fName)).round();

  currentWeight += w;
  if (randomWeight < currentWeight) {
    selectedFish = fish;
    break;
  }
}
       selectedFish ??= availableFishes.first;

    // 🎛️ 난이도(별점)에 따른 최소/최대 사이즈 및 보상 배율 설정
    double minFactor = 0.0; double sizeCap = 1.0;

    // 📏 minFactor/sizeCap = '최대어(baseMax) 대비' 비율. (★1 하한은 종 최소어)
    switch (currentStars) {
      case 1: minFactor = 0.0; sizeCap = 0.3; break; // 최소어 ~ 최대어 30%
      case 2: minFactor = 0.2; sizeCap = 0.4; break; // 20% ~ 40%
      case 3: minFactor = 0.3; sizeCap = 0.6; break; // 30% ~ 60%
      case 4: minFactor = 0.4; sizeCap = 0.8; break; // 40% ~ 80%
      case 5:
      default: minFactor = 0.5; sizeCap = 1.0; break; // 50% ~ 최대어
    }

    double baseMin = double.tryParse(selectedFish['min'].toString()) ?? 10.0;
    double baseMax = double.tryParse(selectedFish['max'].toString()) ?? 50.0;

    // 📏 사이즈 구간 = 최대어(baseMax) 대비 비율. 단, 종 최소어(baseMin)보다 작아지진 않음.
    double effectiveMin = math.max(baseMin, baseMax * minFactor);
    double effectiveMax = math.max(effectiveMin, baseMax * sizeCap);

    // 🎣 [출현 사이즈 분포] 삼각(텐트) 분포 — 중간이 가장 흔하고, 최소어·최대어로 갈수록 드묾.
    //    skew>1 → 최대어(상단)를 최소어보다 더 희귀하게(트로피). 숫자만 바꾸면 분포 조정 가능.
    double tri = (math.Random().nextDouble() + math.Random().nextDouble()) / 2.0; // 0.5에서 피크인 대칭 삼각
    double skew = 1.25;                       // 상단(최대어) 희귀도 (1.0=대칭, 클수록 대물 더 드묾)
    if (isHotSpot) skew = 0.75;               // 핫스팟(오늘의 명당)은 반대로 대물 잘 나오게
    double t = math.pow(tri, skew).toDouble();
    double size = effectiveMin + t * (effectiveMax - effectiveMin);

    size = double.parse(size.toStringAsFixed(1));

    // 💰 보상 계산
    //  경험치: 메타 완화용 완만 공식 = 기본 20 + 사이즈구간(5cm당 +1) + 별점(★1~5)
    //  포인트: 큰 고기=큰 돈(자연스러움) = 사이즈 × 2
    int sizeBand = (size / 5).floor();    // 5cm당 +1 (사이즈 비중 ↑)
    int starBonus = 6 - currentStars;      // 🔄 거꾸로: ★1→+5(저렙터 성장 지원) ... ★5→+1(대물 사이즈경험치로 보상)
    int exp = 25 + sizeBand + starBonus;   // 기본 25 (초반 페이스 회복)
    int pts = (size * 2).round();

    // 👑 6대장은 +20% (살짝 더 가치 있게)
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

  // 🪱 미끼 이름 → 감도(S) 보너스. stats 필드 없는 옛 미끼·민물새우도 착용 시 감도 적용되게.
  static int baitSensByName(String name) {
    if (['지렁이', '갯지렁이', '에기', '민물새우'].contains(name)) return 20;
    if (['옥수수', '크릴'].contains(name)) return 15;
    if (['글루텐', '루어'].contains(name)) return 10;
    return 0;
  }

  // 💪 2. 내 캐릭터 총 능력치 계산기 (인벤토리용)
  static Map<String, int> getMyTotalStats({
    Map<String, dynamic>? equippedSkin,
    Map<String, dynamic>? equippedRod,
    Map<String, dynamic>? equippedFloat,
    Map<String, dynamic>? equippedReel,
    Map<String, dynamic>? equippedSunglasses,
    Map<String, dynamic>? equippedBadge,
    Map<String, dynamic>? equippedCooler,
    Map<String, dynamic>? equippedBait, // 🪱 미끼도 감도(S) 등 스탯 제공(집어력 → 입질 속도)
    Map<String, dynamic>? equippedNet,    // 🥅 뜰채(C)
    Map<String, dynamic>? equippedBelt,   // 🎽 파워벨트(P)
    Map<String, dynamic>? equippedGloves, // 🧤 장갑(P)
    Map<String, dynamic>? equippedLine,       // 🧵 낚시줄(P)
    Map<String, dynamic>? equippedGroundbait, // 🍚 밑밥(S, 세션 버프)
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
    addStats(equippedCooler);     // 🧊 아이스박스
    // 🪱 미끼 감도(S): stats에 S가 있으면 그대로, 없으면(옛 미끼·민물새우) 이름 기반으로 부여
    if (equippedBait != null) {
      final bs = equippedBait['stats'];
      final byStat = (bs is Map && bs['S'] != null) ? (int.tryParse(bs['S'].toString()) ?? 0) : 0;
      totalSens += byStat > 0 ? byStat : baitSensByName((equippedBait['name'] ?? '').toString());
    }
    addStats(equippedNet);        // 🥅 뜰채(컨트롤)
    addStats(equippedBelt);       // 🎽 파워벨트(힘)
    addStats(equippedGloves);     // 🧤 장갑(힘)
    addStats(equippedLine);       // 🧵 낚시줄(힘)
    addStats(equippedGroundbait); // 🍚 밑밥(감도, 세션 버프)

    return {'strength': totalStr, 'control': totalCtrl, 'sensitivity': totalSens};
  }

  // 🛡️ 길드 레벨/버프 (광장·낚시 공용 계산식)
  // guildExpTable[레벨] = 그 레벨이 되기 위한 누적 길드 경험치(=누적 마릿수) (index 0 미사용, 최대 Lv30)
  // 🎣 누적 마릿수(=길드원 전체 잡은 마릿수). 1마리=1점.
  //    사장님 스케줄(30명·2마리/분 기준 ~1년): 초반 빠르게 → 점점 느려짐.
  //    인원 많을수록 잡는 사람 많아 빨리 도달(모집 보상), 적으면 천천히.
  static const List<int> guildExpTable = [
    0,          // 0 (미사용)
    0,          // Lv1
    4800,       // Lv2   ─┐ Lv1-10: 20명 기준(시작 정원)
    16800,      // Lv3    │
    40800,      // Lv4    │
    88800,      // Lv5    │
    146400,     // Lv6    │
    261600,     // Lv7    │
    434400,     // Lv8    │
    664800,     // Lv9    │
    952800,     // Lv10  ─┘
    1471200,    // Lv11  ─┐ Lv11-30: 30명 기준
    2076000,    // Lv12   │
    2767200,    // Lv13   │
    3544800,    // Lv14   │
    4408800,    // Lv15   │
    5359200,    // Lv16   │
    6396000,    // Lv17   │
    7519200,    // Lv18   │
    8728800,    // Lv19   │
    10024800,   // Lv20   │
    11752800,   // Lv21   │
    13480800,   // Lv22   │
    15208800,   // Lv23   │
    16936800,   // Lv24   │
    18664800,   // Lv25   │
    20824800,   // Lv26   │
    22984800,   // Lv27   │
    25144800,   // Lv28   │
    27736800,   // Lv29   │
    31192800,   // Lv30  ─┘
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

  // 길드 레벨에 비례한 최대 가입 인원 (Lv1~9:20, 10~19:30, 20~29:40, 30:50)
  static int guildMaxMembers(int guildLevel) {
    if (guildLevel >= 30) return 50;
    if (guildLevel >= 20) return 40;
    if (guildLevel >= 10) return 30;
    return 20;
  }

  // 🗓️ 주간 길드 리그: 그 주(월요일 시작)의 키. 월요일 00:00에 새 주 시작.
  static String weekKey(DateTime t) {
    final monday = t.subtract(Duration(days: t.weekday - 1)); // weekday: 월=1..일=7
    final d = DateTime(monday.year, monday.month, monday.day);
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  // 주간 리그 1위 길드가 다음 한 주 동안 받는 추가 능력치 보너스(힘/컨트롤/감도 각각)
  static const int guildChampionBonus = 5;

  // 👤 3. 스킨(호칭)에 맞는 투명 캐릭터 이미지 찾아주기
  static String getLobbyCharacterImage(String skinName) {
    String cleanName = skinName.replaceAll(' ', '').toUpperCase();
    if (cleanName.contains('하수')) return 'assets/images/char_novice.png';
    if (cleanName.contains('중수')) return 'assets/images/char_intermediate.png';
    if (cleanName.contains('고수')) return 'assets/images/char_expert.png';
    if (cleanName.contains('프로')) return 'assets/images/char_pro.png';
    if (cleanName.contains('마스터')) return 'assets/images/char_master.png';
    if (cleanName.contains('레전드')) return 'assets/images/char_legend.png';
    if (cleanName.contains('낚시의신') || cleanName.contains('신')) return 'assets/images/char_god.png';

    return 'assets/images/char_beginner.png';
  }
}