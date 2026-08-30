import 'dart:math' as math;
import 'dart:html' as html; // 🔊 사운드 설정 저장(localStorage)
import 'package:audioplayers/audioplayers.dart';
import 'game_config.dart'; // 1탄에서 만든 중앙 통제실 연결!

// 📱 모바일 브라우저 감지 — Fullscreen API 호출 시 크롬 모바일이 강제로 띄우는
//    "전체화면 종료하려면 상단에서 드래그" 안내 배너가 폰 화면 절반 가림.
//    이걸 안 뜨게 하려면 아예 requestFullscreen()을 호출하지 않는 게 답.
//    (모바일 크롬은 스크롤하면 주소창 자동으로 숨겨져서 pseudo-fullscreen 됨)
bool isMobileWeb() {
  try {
    final ua = html.window.navigator.userAgent.toLowerCase();
    return RegExp(r'iphone|ipod|android|windows phone|blackberry|opera mini|mobile').hasMatch(ua);
  } catch (_) { return false; }
}

// =========================================================================
// 🎵 [캠피싱 사운드 매니저] 
// BGM과 효과음을 통제하는 방송실입니다.
// =========================================================================
class AudioManager {
  static final AudioManager _instance = AudioManager._internal();
  factory AudioManager() { return _instance; }
  AudioManager._internal() {
    _loadSettings();
    // 🔁 [BGM 루프 보정] 웹에서 ReleaseMode.loop가 안 먹는 경우가 있어(브라우저/코덱에 따라 1회만 재생)
    //    곡이 끝나면 현재 곡을 다시 틀어준다. 루프가 정상이면 이 콜백은 애초에 안 불린다.
    bgmPlayer.onPlayerComplete.listen((_) async {
      if (isMuted || !bgmOn || currentBgm.isEmpty) return;
      try {
        await bgmPlayer.setReleaseMode(ReleaseMode.loop);
        await bgmPlayer.setVolume(_outBgmVol);
        await bgmPlayer.play(AssetSource('sound/$currentBgm'));
      } catch (_) {}
    });
  }

  final AudioPlayer bgmPlayer = AudioPlayer();
  final AudioPlayer efxPlayer = AudioPlayer();
  final AudioPlayer ambientPlayer = AudioPlayer(); // 🌧️ 빗소리 등 앰비언트(BGM 위에 겹침)
  bool isMuted = false;

  // 🔊 [사운드 설정] 배경음·효과음 개별 on/off + 볼륨(0~1). localStorage에 저장 → 새로고침 유지.
  bool bgmOn = true;
  bool sfxOn = true;
  double bgmVol = 0.7;
  double sfxVol = 1.0;
  // 🔉 [BGM 마스터 게인] 배경음이 커서 매번 끄게 된다는 피드백 → 실제 출력만 낮춤.
  //   유저 슬라이더(bgmVol)는 그대로 두고 여기에 곱해 재생 → 이미 저장된 설정(0.7)도 함께 작아진다.
  static const double kBgmGain = 0.5;
  double get _outBgmVol => (bgmVol * kBgmGain).clamp(0.0, 1.0);
  int combatAssist = 2; // ⚔️ 제압 방식: 0 수동 / 1 자동(잡고) / 2 완전자동(기본값). localStorage 저장.

  void _loadSettings() {
    try {
      final ls = html.window.localStorage;
      bgmOn = ls['snd_bgm'] != '0';
      sfxOn = ls['snd_sfx'] != '0';
      bgmVol = double.tryParse(ls['snd_bgmv'] ?? '') ?? 0.7;
      sfxVol = double.tryParse(ls['snd_sfxv'] ?? '') ?? 1.0;
      combatAssist = int.tryParse(ls['combat_assist'] ?? '') ?? 2; // 설정 안 만진 유저는 완전자동 기본
    } catch (_) {}
  }
  void _saveSettings() {
    try {
      final ls = html.window.localStorage;
      ls['snd_bgm'] = bgmOn ? '1' : '0';
      ls['snd_sfx'] = sfxOn ? '1' : '0';
      ls['snd_bgmv'] = bgmVol.toStringAsFixed(2);
      ls['snd_sfxv'] = sfxVol.toStringAsFixed(2);
      ls['combat_assist'] = '$combatAssist';
    } catch (_) {}
  }
  void setCombatAssist(int m) { combatAssist = m.clamp(0, 2); _saveSettings(); }

  // 🎚️ 설정 변경(즉시 반영 + 저장)
  Future<void> setBgmOn(bool on) async {
    bgmOn = on; _saveSettings();
    if (!on) {
      try { await bgmPlayer.pause(); } catch (_) {}
      return;
    }
    if (isMuted) return;
    if (currentBgm.isNotEmpty) {
      try {
        await bgmPlayer.setVolume(_outBgmVol);
        if (bgmPlayer.state != PlayerState.playing) {              // 재생 중이 아니면
          await bgmPlayer.setReleaseMode(ReleaseMode.loop);
          if (bgmPlayer.state == PlayerState.paused) { await bgmPlayer.resume(); }  // 일시정지 → 재개
          else { await bgmPlayer.play(AssetSource('sound/$currentBgm')); }          // 처음 재생
        }
      } catch (_) {}
    }
  }
  Future<void> setSfxOn(bool on) async {
    sfxOn = on; _saveSettings();
    // 🌧️ 빗소리를 효과음에 묶음: 효과음 끄면 정지, 켜면 비 오는 중이면 재개
    if (!on) { try { await ambientPlayer.stop(); } catch (_) {} }
    else if (_rainRefs > 0 && !isMuted) { await _startRain(); }
  }
  Future<void> setBgmVol(double v) async {
    bgmVol = v.clamp(0.0, 1.0); _saveSettings();
    try { await bgmPlayer.setVolume(_outBgmVol); } catch (_) {}
  }
  Future<void> setSfxVol(double v) async {
    sfxVol = v.clamp(0.0, 1.0); _saveSettings();
    try { await ambientPlayer.setVolume(sfxVol * 0.85); } catch (_) {} // 🌧️ 빗소리도 효과음 볼륨 따라감
  }
  String currentBgm = "";
  int _rainRefs = 0; // 🌧️ 빗소리를 원하는 화면 수(플라자·낚시터 겹침 대비 참조 카운트)
  bool _rainUnlocked = false; // 🌧️ 첫 사용자 조작으로 빗소리 재생을 한 번 강제로 열었는지

  Future<void> playBgm(String fileName) async {
    if (currentBgm == fileName) return;
    currentBgm = fileName; // 재생돼야 할 곡을 항상 기억(설정 켤 때 이 곡을 틀 수 있게)
    if (isMuted || !bgmOn) return; // 배경음 꺼져있으면 곡만 기억하고 재생 안 함
    await bgmPlayer.setReleaseMode(ReleaseMode.loop);
    await bgmPlayer.setVolume(_outBgmVol);
    await bgmPlayer.play(AssetSource('sound/$fileName'));
  }

  Future<void> playSfx(String fileName) async {
    if (isMuted || !sfxOn) return;
    if (fileName.contains('landing') && efxPlayer.state == PlayerState.playing) return;

    try {
      // 💡 1차 방어: 다른 소리가 나고 있으면 확실하게 먼저 입을 막는다!
      if (efxPlayer.state == PlayerState.playing) {
        await efxPlayer.stop();
      }
      
      // 소리 재생! (효과음 볼륨 반영)
      await efxPlayer.setVolume(sfxVol);
      await efxPlayer.play(AssetSource('sound/$fileName'));

    } catch (e) {
      // 💡 2차 방어 (핵심): 연타 때문에 웹에서 AbortError가 터져도, 
      // 앱이 멈추지 않고 그냥 소리 하나 씹힌 걸로 자연스럽게 넘어가게 만듭니다!
   }
  }

  // 🎉 짜잔~ (상자 공개 등) — 'landing' 가드 무시하고 확실히 재생(직전 소리 끊고 재생)
  Future<void> playTada() async {
    if (isMuted || !sfxOn) return;
    try {
      if (efxPlayer.state == PlayerState.playing) await efxPlayer.stop();
      await efxPlayer.setVolume(sfxVol);
      await efxPlayer.play(AssetSource('sound/sfx_landing_success.mp3'));
    } catch (_) {}
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
    if (_rainRefs == 0) { _rainUnlocked = false; try { await ambientPlayer.stop(); } catch (_) {} }
  }
  // 🌧️ 사용자 조작(터치) 시 호출 — 자동재생 차단으로 못 켜진 빗소리를 그때 켬.
  //   첫 조작 때는 상태와 무관하게 '정지→재생'으로 확실히 열고(차단됐던 재생이 상태만 남는 경우 대비),
  //   그 뒤엔 이미 재생 중이면 건너뜀(중복·끊김 방지).
  Future<void> ensureRainPlaying() async {
    if (_rainRefs <= 0 || isMuted || !sfxOn) return;
    if (_rainUnlocked && ambientPlayer.state == PlayerState.playing) return;
    _rainUnlocked = true;
    try { await ambientPlayer.stop(); } catch (_) {}
    await _startRain();
  }
  Future<void> _startRain() async {
    if (isMuted || !sfxOn) return; // 🌧️ 음소거·효과음off면 소리만 안 냄(참조는 유지 → 켤 때 정상 카운트)
    try {
      await ambientPlayer.setReleaseMode(ReleaseMode.loop);
      await ambientPlayer.setVolume(sfxVol * 0.85); // 🔊 빗소리 = 효과음 볼륨 따라감
      await ambientPlayer.play(AssetSource('sound/rain_sound.mp3'));
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
    '예산 예당지': ['붕어', '떡붕어', '블루길', '베스', '살치', '잉어', '메기', '자라', '가물치', '강준치', '쏘가리', '꺽지', '무지개송어', '향어', '민물장어', '동자개'],
    '안성 고삼지': ['붕어', '떡붕어', '블루길', '베스', '살치', '잉어', '메기', '자라', '가물치', '강준치', '쏘가리', '꺽지', '무지개송어', '향어', '민물장어', '동자개'],
    '진천 백곡지': ['붕어', '떡붕어', '블루길', '베스', '살치', '잉어', '메기', '자라', '가물치', '강준치', '쏘가리', '꺽지', '무지개송어', '향어', '민물장어', '동자개'],
    '춘천 파로호': ['붕어', '떡붕어', '블루길', '베스', '살치', '잉어', '메기', '자라', '가물치', '강준치', '쏘가리', '꺽지', '무지개송어', '향어', '민물장어', '동자개'],
    '충주 충주호': ['붕어', '떡붕어', '블루길', '베스', '살치', '잉어', '메기', '자라', '가물치', '강준치', '쏘가리', '꺽지', '무지개송어', '향어', '민물장어', '동자개'],
    '예산 신양수로': ['붕어', '떡붕어', '블루길', '베스', '살치', '잉어', '메기', '자라', '가물치', '강준치', '쏘가리', '꺽지', '무지개송어', '향어', '민물장어', '동자개'],
    '청양 지천': ['붕어', '떡붕어', '블루길', '베스', '살치', '잉어', '메기', '자라', '가물치', '강준치', '쏘가리', '꺽지', '무지개송어', '향어', '민물장어', '동자개'],
    '인천 청라수로': ['붕어', '떡붕어', '블루길', '베스', '살치', '잉어', '메기', '자라', '가물치', '강준치', '쏘가리', '꺽지', '무지개송어', '향어', '민물장어', '동자개'],
    '해남 금자천': ['붕어', '떡붕어', '블루길', '베스', '살치', '잉어', '메기', '자라', '가물치', '강준치', '쏘가리', '꺽지', '무지개송어', '향어', '민물장어', '동자개'],
    '충주 달천': ['붕어', '떡붕어', '블루길', '베스', '살치', '잉어', '메기', '자라', '가물치', '강준치', '쏘가리', '꺽지', '무지개송어', '향어', '민물장어', '동자개'],

    // 🌊 [바다] 갯바위 & 선상 (바다고기 11종 총출동!)
    '통영 척포 갯바위': ['고등어', '우럭', '갈치', '참돔', '광어', '감성돔', '갑오징어', '주꾸미', '문어', '벵에돔', '참치', '볼락', '학꽁치', '성대', '농어', '부시리', '돌돔'],
    '신안 가거도': ['고등어', '우럭', '갈치', '참돔', '광어', '감성돔', '갑오징어', '주꾸미', '문어', '벵에돔', '참치', '볼락', '학꽁치', '성대', '농어', '부시리', '돌돔'],
    '완도 청산도': ['고등어', '우럭', '갈치', '참돔', '광어', '감성돔', '갑오징어', '주꾸미', '문어', '벵에돔', '참치', '볼락', '학꽁치', '성대', '농어', '부시리', '돌돔'],
    '여수 거문도': ['고등어', '우럭', '갈치', '참돔', '광어', '감성돔', '갑오징어', '주꾸미', '문어', '벵에돔', '참치', '볼락', '학꽁치', '성대', '농어', '부시리', '돌돔'],
    '제주 섶섬': ['고등어', '우럭', '갈치', '참돔', '광어', '감성돔', '갑오징어', '주꾸미', '문어', '벵에돔', '참치', '볼락', '학꽁치', '성대', '농어', '부시리', '돌돔'],
    '거제 선상': ['고등어', '우럭', '갈치', '참돔', '광어', '감성돔', '갑오징어', '주꾸미', '문어', '벵에돔', '참치', '볼락', '학꽁치', '성대', '농어', '부시리', '돌돔'],
    '오천항 선상': ['고등어', '우럭', '갈치', '참돔', '광어', '감성돔', '갑오징어', '주꾸미', '문어', '벵에돔', '참치', '볼락', '학꽁치', '성대', '농어', '부시리', '돌돔'],
    '대천 선상': ['고등어', '우럭', '갈치', '참돔', '광어', '감성돔', '갑오징어', '주꾸미', '문어', '벵에돔', '참치', '볼락', '학꽁치', '성대', '농어', '부시리', '돌돔'],
    '통영 선상': ['고등어', '우럭', '갈치', '참돔', '광어', '감성돔', '갑오징어', '주꾸미', '문어', '벵에돔', '참치', '볼락', '학꽁치', '성대', '농어', '부시리', '돌돔'],
    '완도 선상': ['고등어', '우럭', '갈치', '참돔', '광어', '감성돔', '갑오징어', '주꾸미', '문어', '벵에돔', '참치', '볼락', '학꽁치', '성대', '농어', '부시리', '돌돔'],
  };

  // 🐟 1. 물고기 생성기 (입질 왔을 때 어떤 고기인지, 사이즈는 몇인지 계산)
  // ═══════════════════════════════════════════════════════════════════
  // 📦 랜덤 상자 보상 (인벤토리에서 '열기' 시 호출). 실제 아이템 정의와 필드 일치.
  //    되팔기(30%)·레벨제한 동작 위해 gear는 price·reqLevel 포함.
  // ═══════════════════════════════════════════════════════════════════
  // 🎣 미끼 10종(민물6+바다4) — 상자 미끼 보상 풀 (2026-08-16 추석이벤트 개편: 루어미끼 스푼/웜/플라이 추가)
  static const List<Map<String, dynamic>> _boxBaits = [
    {'name': '글루텐', 'price': 1000, 'category': 'FW', 'type': 'BAIT', 'quantity': 50, 'stats': {'S': 10}, 'icon': 'bait_fw_gluten.png'},
    {'name': '옥수수', 'price': 1500, 'category': 'FW', 'type': 'BAIT', 'quantity': 50, 'stats': {'S': 15}, 'icon': 'bait_fw_corn.png'},
    {'name': '지렁이', 'price': 2000, 'category': 'FW', 'type': 'BAIT', 'quantity': 50, 'stats': {'S': 20}, 'icon': 'bait_fw_worm.png'},
    {'name': '플라이', 'price': 1000, 'category': 'FW', 'type': 'BAIT', 'quantity': 50, 'stats': {'S': 10}, 'icon': 'bait_fw_lure_fly.png'},
    {'name': '웜', 'price': 1500, 'category': 'COMMON', 'type': 'BAIT', 'quantity': 50, 'stats': {'S': 15}, 'icon': 'bait_fw_lure_worm.png'},
    {'name': '스푼', 'price': 2000, 'category': 'FW', 'type': 'BAIT', 'quantity': 50, 'stats': {'S': 20}, 'icon': 'bait_fw_lure_spoon.png'},
    {'name': '루어', 'price': 1000, 'category': 'SEA', 'type': 'BAIT', 'quantity': 50, 'stats': {'S': 10}, 'icon': 'bait_sea_lure.png'},
    {'name': '크릴', 'price': 1500, 'category': 'SEA', 'type': 'BAIT', 'quantity': 50, 'stats': {'S': 15}, 'icon': 'bait_sea_krill.png'},
    {'name': '에기', 'price': 2000, 'category': 'SEA', 'type': 'BAIT', 'quantity': 50, 'stats': {'S': 20}, 'icon': 'bait_sea_egi.png'},
    {'name': '갯지렁이', 'price': 2000, 'category': 'SEA', 'type': 'BAIT', 'quantity': 50, 'stats': {'S': 20}, 'icon': 'bait_sea_worm.png'},
  ];
  static const List<Map<String, dynamic>> _boxChum = [
    {'name': '민물 밑밥', 'price': 3000, 'reqLevel': 10, 'category': 'FW', 'type': 'GROUNDBAIT', 'quantity': 50, 'stats': {'S': 10}, 'icon': 'chum_fw.png'},
    {'name': '바다 밑밥', 'price': 3000, 'reqLevel': 10, 'category': 'SEA', 'type': 'GROUNDBAIT', 'quantity': 50, 'stats': {'S': 10}, 'icon': 'chum_sea.png'},
  ];
  static const List<Map<String, dynamic>> _boxLines = [
    {'name': '민물 낚시줄', 'price': 20000, 'reqLevel': 10, 'category': 'FW', 'type': 'LINE', 'quantity': 1, 'dur': 200, 'stats': {'P': 10}, 'icon': 'line_fw.png'},
    {'name': '바다 낚시줄', 'price': 20000, 'reqLevel': 10, 'category': 'SEA', 'type': 'LINE', 'quantity': 1, 'dur': 200, 'stats': {'P': 10}, 'icon': 'line_sea.png'},
  ];
  // 🎣 찌·릴 4종 (2026-08-16 개편: 나노카본찌·CF전자찌·CF5000·KF5000)
  static const List<Map<String, dynamic>> _boxFloatReel = [
    {'name': '나노카본찌', 'price': 50000, 'reqLevel': 30, 'category': 'FW', 'type': 'FLOAT', 'quantity': 1, 'stats': {'P': 20, 'C': 20, 'S': 20}, 'icon': 'float_fw_nano.png'},
    {'name': 'CF 전자찌', 'price': 100000, 'reqLevel': 50, 'category': 'FW', 'type': 'FLOAT', 'quantity': 1, 'stats': {'P': 25, 'C': 25, 'S': 25}, 'icon': 'float_fw_elec_cf.png'},
    {'name': 'CF5000', 'price': 20000, 'reqLevel': 10, 'category': 'SEA', 'type': 'REEL', 'quantity': 1, 'stats': {'P': 15, 'C': 15, 'S': 15}, 'icon': 'reel_sea_cf5000.png'},
    {'name': 'KF5000', 'price': 50000, 'reqLevel': 30, 'category': 'SEA', 'type': 'REEL', 'quantity': 1, 'stats': {'P': 20, 'C': 20, 'S': 20}, 'icon': 'reel_sea_kf5000.png'},
  ];
  // 🎣 낚싯대 4종 (2026-08-16 개편: CF-40T·KT-20T·CF500·KT250)
  static const List<Map<String, dynamic>> _boxRods = [
    {'name': 'CF-40T', 'price': 50000, 'reqLevel': 10, 'category': 'FW', 'type': 'ROD', 'quantity': 1, 'stats': {'P': 20, 'C': 20, 'S': 20}, 'icon': 'rod_fw_cf40.png'},
    {'name': 'KT-20T', 'price': 100000, 'reqLevel': 30, 'category': 'FW', 'type': 'ROD', 'quantity': 1, 'stats': {'P': 30, 'C': 30, 'S': 30}, 'icon': 'rod_fw_kt20.png'},
    {'name': 'CF500', 'price': 50000, 'reqLevel': 10, 'category': 'SEA', 'type': 'ROD', 'quantity': 1, 'stats': {'P': 20, 'C': 20, 'S': 20}, 'icon': 'rod_sea_cf500.png'},
    {'name': 'KT250', 'price': 100000, 'reqLevel': 30, 'category': 'SEA', 'type': 'ROD', 'quantity': 1, 'stats': {'P': 30, 'C': 30, 'S': 30}, 'icon': 'rod_sea_kt250.png'},
  ];
  // 🧊🕶️ 단품 장비 (중형 아이스박스 · 레인보우 편광 선글라스) — 보물상자 추가(2026-08-16)
  static const Map<String, dynamic> _boxCooler = {'name': '중형 아이스박스', 'price': 50000, 'reqLevel': 20, 'category': 'COMMON', 'type': 'COOLER', 'quantity': 1, 'stats': {'P': 10, 'C': 10, 'S': 10}, 'icon': 'cooler_m.png'};
  static const Map<String, dynamic> _boxSunglasses = {'name': '레인보우 편광 선글라스', 'price': 50000, 'reqLevel': 30, 'category': 'COMMON', 'type': 'ETC', 'quantity': 1, 'stats': {'P': 20, 'C': 20, 'S': 20}, 'icon': 'item_sunglasses_rainbow.png'};
  static const Map<String, dynamic> _boxArenaTicket = {'name': '아레나 입장권', 'price': 1100, 'cash': true, 'category': 'TICKET', 'type': 'ETC', 'quantity': 1, 'icon': 'arena_ticket.png'};
  static const Map<String, dynamic> _boxHourTicket = {'name': '낚시 1시간 이용권', 'price': 1100, 'category': 'TICKET', 'type': 'ETC', 'quantity': 1, 'icon': 'item_ticket_1h.png'};

  /// 📦 상자 하나를 열었을 때의 보상 1건.
  ///   반환: {'kind':'exp'|'point'|'item', 'amount':int, 'item':Map, 'gear':bool, 'label':String}
  ///   - exp/point: amount 만큼 지급.  item: 해당 아이템(gear=true면 rod/reel/float=중복 시 되팔기 처리 대상).
  static final math.Random _boxRng = math.Random(); // 🎲 공용 시드(매번 new Random()하면 웹에서 같은 ms=같은 결과 버그)
  static Map<String, dynamic> rollBoxReward(String boxType) {
    final r = _boxRng;
    Map<String, dynamic> pick(List<Map<String, dynamic>> pool) =>
        Map<String, dynamic>.from(pool[r.nextInt(pool.length)]);
    if (boxType == 'mystery') {
      final k = r.nextInt(100);
      if (k < 45) { // 경험치 45%
        final v = const [100, 200, 300, 400, 500][r.nextInt(5)];
        return {'kind': 'exp', 'amount': v, 'label': '경험치 +$v'};
      } else if (k < 90) { // 포인트 45%
        final v = const [200, 400, 600, 800, 1000][r.nextInt(5)];
        return {'kind': 'point', 'amount': v, 'label': '$v 포인트'};
      } else { // 미끼 10%
        final b = pick(_boxBaits);
        return {'kind': 'item', 'item': b, 'gear': false, 'label': '${b['name']} 50개'};
      }
    }
    // 🎁 보물상자 (추석이벤트 개편 2026-08-16) — 미끼10·밑밥2·낚시줄2·아이스박스·선글라스·낚싯대4·찌릴4·이용권2
    //    확률: 미끼25 · 밑밥20 · 낚시줄13 · 아이스박스8 · 선글라스8 · 찌릴12 · 낚싯대6 · 아레나권4 · 1시간권4
    //    (낚싯대=최상급템이라 찌/릴보다 귀하게: 낚싯대6% < 찌릴12%)
    final k = r.nextInt(100);
    if (k < 25) { final b = pick(_boxBaits); return {'kind': 'item', 'item': b, 'gear': false, 'label': '${b['name']} 50개'}; }
    if (k < 45) { final g = pick(_boxChum); return {'kind': 'item', 'item': g, 'gear': false, 'label': '${g['name']} 50개'}; }
    if (k < 58) { final l = pick(_boxLines); return {'kind': 'item', 'item': l, 'gear': false, 'label': l['name']}; }
    if (k < 66) { return {'kind': 'item', 'item': Map<String, dynamic>.from(_boxCooler), 'gear': true, 'label': '중형 아이스박스'}; }
    if (k < 74) { return {'kind': 'item', 'item': Map<String, dynamic>.from(_boxSunglasses), 'gear': true, 'label': '레인보우 편광 선글라스'}; }
    if (k < 86) { final f = pick(_boxFloatReel); return {'kind': 'item', 'item': f, 'gear': true, 'label': f['name']}; }
    if (k < 92) { final rod = pick(_boxRods); return {'kind': 'item', 'item': rod, 'gear': true, 'label': rod['name']}; }
    if (k < 96) { return {'kind': 'item', 'item': Map<String, dynamic>.from(_boxArenaTicket), 'gear': false, 'label': '아레나 입장권'}; }
    return {'kind': 'item', 'item': Map<String, dynamic>.from(_boxHourTicket), 'gear': false, 'label': '낚시 1시간 이용권'};
  }

  /// 📦 인벤토리에서 상자 count개 개봉(집계). inventory를 복사·수정한 결과 + 보상 합계 반환.
  ///   낚시터·광장 공용. 반환: {'inv':List, 'opened':int, 'exp':int, 'gold':int, 'sellback':int, 'items':Map<String,int>}
  ///   - gold = 포인트 보상 + 중복장비 되팔기(30%) 합산.  items = 표시용(아이템만) 카운트.
  static Map<String, dynamic> openBoxes(List<dynamic> inventory, String boxName, int count) {
    final inv = List<dynamic>.from(inventory.map((e) => e is Map ? Map<String, dynamic>.from(e) : e));
    final bi = inv.indexWhere((i) => (i is Map) && (i['name'] ?? '') == boxName);
    if (bi < 0 || count <= 0) {
      return {'inv': inv, 'opened': 0, 'exp': 0, 'gold': 0, 'sellback': 0, 'items': <String, int>{}};
    }
    final int owned = ((inv[bi]['quantity'] ?? 0) as num).toInt();
    count = count.clamp(1, owned);
    final String boxType = boxName == '수상한 상자' ? 'mystery' : 'treasure';
    int expDelta = 0, goldDelta = 0, sellbackGold = 0;
    final Map<String, int> itemCounts = {};
    void addStack(Map<String, dynamic> item) {
      final idx = inv.indexWhere((i) => (i is Map) && (i['name'] ?? '') == item['name']);
      final int addQ = ((item['quantity'] ?? 1) as num).toInt();
      if (idx >= 0) {
        inv[idx]['quantity'] = (((inv[idx]['quantity'] ?? 0) as num).toInt()) + addQ;
      } else {
        inv.add(Map<String, dynamic>.from(item));
      }
    }
    for (int n = 0; n < count; n++) {
      final rw = rollBoxReward(boxType);
      final kind = rw['kind'];
      if (kind == 'exp') {
        expDelta += (rw['amount'] as int);
      } else if (kind == 'point') {
        goldDelta += (rw['amount'] as int);
      } else {
        // 🎁 미끼·밑밥·낚시줄·찌·릴·낚싯대·이용권 모두 인벤토리에 지급.
        //   (장비도 자동 판매 안 함 — 중복이면 유저가 직접 상점에서 되팔기)
        final item = Map<String, dynamic>.from(rw['item']);
        addStack(item);
        final int q = ((item['quantity'] ?? 1) as num).toInt();
        final key = q > 1 ? '${item['name']} $q개' : '${item['name']}';
        itemCounts[key] = (itemCounts[key] ?? 0) + 1;
      }
    }
    final int remain = owned - count;
    if (remain <= 0) { inv.removeAt(bi); } else { inv[bi]['quantity'] = remain; }
    return {'inv': inv, 'opened': count, 'exp': expDelta, 'gold': goldDelta, 'sellback': sellbackGold, 'items': itemCounts};
  }

  static Map<String, dynamic>? generateFish({
    required bool isSea,
    required String locationName,
    required String currentBaitName,
    bool allowBoxes = false, // 📦 상자 드랍 허용(아레나·튜토리얼은 false로 제외)
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
// 🎯 [2026-08 개편] 사용자 상성표 그대로 반영. 0.0=안 물림(루어전용어종 차단), 0.1~0.5=가끔.
//    루어 미끼(스푼/플라이=민물전용, 웜=민물·바다 공용). 웜은 민물+바다 어종 모두 포함(공용).
final Map<String, Map<String, double>> baitAffinity = {
  // ── 민물 미끼 ── (2026-08-16 강준치 재조정=육식성으로 + 향어/민물장어/동자개 3종 추가)
  '글루텐':   {'붕어': 2.0, '잉어': 1.5, '가물치': 0.0, '떡붕어': 2.0, '블루길': 0.0, '살치': 1.0, '베스': 0.0, '강준치': 0.0, '자라': 0.2, '메기': 0.0, '쏘가리': 0.0, '꺽지': 0.0, '무지개송어': 0.0, '향어': 2.0, '민물장어': 0.0, '동자개': 0.0},
  '지렁이':   {'붕어': 1.5, '잉어': 1.0, '가물치': 1.0, '떡붕어': 1.0, '블루길': 2.0, '살치': 1.0, '베스': 0.5, '강준치': 1.5, '자라': 0.5, '메기': 2.0, '쏘가리': 0.1, '꺽지': 0.1, '무지개송어': 0.1, '향어': 0.5, '민물장어': 2.0, '동자개': 1.5},
  '옥수수':   {'붕어': 1.5, '잉어': 2.0, '가물치': 0.0, '떡붕어': 1.0, '블루길': 0.0, '살치': 1.5, '베스': 0.0, '강준치': 0.0, '자라': 0.0, '메기': 0.0, '쏘가리': 0.0, '꺽지': 0.0, '무지개송어': 0.0, '향어': 1.0, '민물장어': 0.0, '동자개': 0.0},
  '민물새우': {'붕어': 1.5, '잉어': 1.0, '가물치': 1.0, '떡붕어': 1.5, '블루길': 1.5, '살치': 0.0, '베스': 0.5, '강준치': 1.0, '자라': 0.5, '메기': 1.5, '쏘가리': 0.1, '꺽지': 0.1, '무지개송어': 0.1, '향어': 0.5, '민물장어': 1.5, '동자개': 2.0},
  // ── 루어 미끼(민물) ──
  '스푼':     {'붕어': 0.0, '잉어': 0.0, '가물치': 2.0, '떡붕어': 0.0, '블루길': 0.0, '살치': 0.0, '베스': 2.0, '강준치': 2.0, '자라': 0.0, '메기': 0.0, '쏘가리': 1.0, '꺽지': 0.0, '무지개송어': 1.5, '향어': 0.0, '민물장어': 0.0, '동자개': 0.0},
  '플라이':   {'붕어': 0.0, '잉어': 0.0, '가물치': 0.5, '떡붕어': 0.0, '블루길': 0.0, '살치': 0.0, '베스': 0.2, '강준치': 0.5, '자라': 0.0, '메기': 0.0, '쏘가리': 0.2, '꺽지': 2.0, '무지개송어': 0.5, '향어': 0.0, '민물장어': 0.0, '동자개': 0.0},
  // ── 웜(민물·바다 공용) — 두 영역 어종 모두 포함 ──
  '웜': {
    '붕어': 0.0, '잉어': 0.0, '가물치': 1.0, '떡붕어': 0.0, '블루길': 0.0, '살치': 0.0, '베스': 1.5, '강준치': 1.0, '자라': 0.0, '메기': 0.0, '쏘가리': 2.0, '꺽지': 1.0, '무지개송어': 2.0, '향어': 0.0, '민물장어': 0.0, '동자개': 0.0,
    '참돔': 0.1, '감성돔': 0.1, '문어': 0.5, '고등어': 0.0, '우럭': 0.0, '갈치': 1.0, '광어': 2.0, '갑오징어': 1.0, '주꾸미': 0.5, '벵에돔': 0.5, '볼락': 1.0, '학꽁치': 0.0, '참치': 0.0, '성대': 1.0, '농어': 0.0, '부시리': 1.0, '돌돔': 0.0,
  },
  // ── 바다 미끼 ── (2026-08-16 성대/농어/부시리/돌돔 4종 추가)
  '갯지렁이': {'참돔': 1.5, '감성돔': 0.5, '문어': 0.0, '고등어': 0.0, '우럭': 2.0, '갈치': 0.5, '광어': 1.0, '갑오징어': 0.0, '주꾸미': 0.0, '벵에돔': 0.0, '볼락': 2.0, '학꽁치': 1.0, '참치': 0.0, '성대': 2.0, '농어': 1.5, '부시리': 0.0, '돌돔': 1.5},
  '크릴':     {'참돔': 2.0, '감성돔': 2.0, '문어': 0.0, '고등어': 2.0, '우럭': 0.5, '갈치': 1.0, '광어': 1.0, '갑오징어': 0.0, '주꾸미': 0.0, '벵에돔': 2.0, '볼락': 1.0, '학꽁치': 2.0, '참치': 0.0, '성대': 1.0, '농어': 1.0, '부시리': 0.0, '돌돔': 1.0},
  '루어':     {'참돔': 0.5, '감성돔': 1.0, '문어': 0.5, '고등어': 1.0, '우럭': 1.0, '갈치': 2.0, '광어': 0.5, '갑오징어': 1.0, '주꾸미': 0.5, '벵에돔': 1.5, '볼락': 0.5, '학꽁치': 0.0, '참치': 1.0, '성대': 0.5, '농어': 2.0, '부시리': 1.5, '돌돔': 0.0},
  '에기':     {'참돔': 0.0, '감성돔': 0.0, '문어': 2.0, '고등어': 0.0, '우럭': 0.0, '갈치': 0.0, '광어': 0.0, '갑오징어': 2.0, '주꾸미': 2.0, '벵에돔': 0.0, '볼락': 0.0, '학꽁치': 0.0, '참치': 0.0, '성대': 0.0, '농어': 0.0, '부시리': 0.0, '돌돔': 0.0},
  // 🐟 특수 미끼: 잡은 고등어를 미끼로 쓰면 참치·부시리가 잘 물림(생미끼)
  '고등어':   {'참치': 1.5, '부시리': 1.5},
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

// 📦 상자 드랍 — 물고기 룰렛과 **독립** 롤(2026-08-15 개편).
//    이유: 이전엔 물고기 totalWeight에 상자 weight를 얹어서, 미끼 상성으로 어종 폭이 좁아지면
//         (예: 루어=스푼/플라이) totalWeight가 낮아져 상자 상대확률이 훅 뛰는 문제(아들 제보 12개/시간).
//    목표: 미끼·낚시터·어종 폭 무관, 50분 낚시(≈100-150회 시도)에 평균 2-4개.
//    수상한 상자 = 2% (상시) · 보물상자 = 1% (이벤트 gTreasureBoxOn 켜졌을 때만).
//    아레나·튜토리얼은 allowBoxes=false로 제외.
// 🧪 kBoxTestMode=true 면 상자 자주 드랍 + 보물상자 강제 ON (테스트용, 배포 전 false로!)
const bool kBoxTestMode = false;
if (allowBoxes) {
  final double mysteryP = kBoxTestMode ? 0.30 : 0.02;
  final double treasureP = (gTreasureBoxOn || kBoxTestMode)
      ? (kBoxTestMode ? 0.30 : 0.01)
      : 0.0;
  final double boxRoll = math.Random().nextDouble();
  if (boxRoll < mysteryP + treasureP) {
    final bool isMystery = boxRoll < mysteryP;
    return {
      'name': isMystery ? '수상한 상자' : '보물상자',
      'isBox': true,
      'boxType': isMystery ? 'mystery' : 'treasure',
      'icon': isMystery ? '수상한 상자.png' : '보물상자.png',
      'img': isMystery ? 'assets/items/수상한 상자.png' : 'assets/items/보물상자.png',
      'unit': '개', 'size': 0.0, 'min': 0.0, 'max': 1.0, 'weightKg': 0.0, 'exp': 0, 'pts': 0,
    };
  }
}
if (totalWeight < 1) totalWeight = 1;

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
    // 🎣 [v2 밸런스 2026-07-26] 별점=실력 관문. 하한↑ → 고별점일수록 평균 사이즈↑ → 저랩은 터짐 잦아 아랫단계로 자기조절.
    //   (작은어종=어디서든 방해꾼 유지, 큰어종이 도전. 실유저 데이터 보고 미세조정 가능)
    switch (currentStars) {
      case 1: minFactor = 0.0;  sizeCap = 0.32; break; // 잡어터: 최소어 ~ 최대어 32% (누구나)
      case 2: minFactor = 0.45; sizeCap = 0.65; break; // 초보터: 45% ~ 65% (난이도 살짝↑ · 큰어종은 팽팽)
      case 3: minFactor = 0.55; sizeCap = 0.78; break; // 중급터: 55% ~ 78% (초보만렙엔 벽)
      case 4: minFactor = 0.68; sizeCap = 0.90; break; // 고급터: 68% ~ 90%
      case 5:
      default: minFactor = 0.70; sizeCap = 1.00; break; // 최상급: 70% ~ 최대어 (하한 80→70 완화, 대물은 유지)
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

    // 💰 [v217 바다·민물 보상 통일] 절대 cm가 아니라 '최대어 대비 상대크기(rel)'로 보상 계산.
    //   기존: EXP·포인트가 절대사이즈 기준 → 최대어 큰 바다어종(참치200·참돔120)이 같은 노력에 보상 더 받음 → 민물 버려짐.
    //   개선: rel=(size−최소어)/(최대어−최소어), 0(최소어)~1(최대어). 어종 무관 같은 %면 같은 보상.
    //   ⚠️ 2026-08: '15' 고정 → 어종별 baseMin 기준으로 변경(갈치=지·주꾸미·문어=kg 등 단위/스케일 달라도 정상 동작).
    double rel = (baseMax > baseMin) ? ((size - baseMin) / (baseMax - baseMin)).clamp(0.0, 1.0) : 1.0;
    int sizeBand = (rel * 12).round();     // 상대크기 0~12 (절대 size/5 대체)
    int starBonus = currentStars * 4;      // ⭐ [v218] ★1→+4 ... ★5→+20 (고별점 EXP 보상 강화 — 오픈 후 레벨업 속도 보고 조정)
    int exp = 15 + sizeBand + starBonus;   // 기본 15 (초반 랩업 속도 완화)
    int pts = (25 + rel * 100).round();    // 최소어 25 ~ 최대어 125 (상대크기 기준)

    // 👑 6대장은 +20% (살짝 더 가치 있게)
    List<String> bossFishes = ['붕어', '잉어', '가물치', '참돔', '감성돔', '문어'];
    if (bossFishes.contains(selectedFish['name'])) {
      exp = (exp * 1.2).round();
      pts = (pts * 1.2).round();
    }

    // 🎰 레어 잭팟 어종(자라·참치) — 출현확률 낮음(weight 5), 1시간에 한 마리 볼까말까.
    //    크기 무관 EXP·포인트 ×3 (사이즈 비례라 큰 놈일수록 자연히 더 큰 잭팟)
    const List<String> rareFishes = ['자라', '참치'];
    if (rareFishes.contains(selectedFish['name'])) {
      exp = (exp * 3).round();
      pts = (pts * 3).round();
    }

    // 🎉 이벤트 배율(Firestore config/event) — 전체 경험치·포인트 배율 + 6대장 추가 배율.
    //    이벤트 없으면 전부 1.0이라 영향 없음. currentGameEvent는 loadGameEvent()로 갱신됨.
    final ev = currentGameEvent;
    if (ev.active) {
      if (ev.expMult != 1.0) exp = (exp * ev.expMult).round();
      if (ev.ptsMult != 1.0) pts = (pts * ev.ptsMult).round();
      if (ev.bossMult != 1.0 && bossFishes.contains(selectedFish['name'])) {
        exp = (exp * ev.bossMult).round();
        pts = (pts * ev.bossMult).round();
      }
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

  // 🛡️ 채팅 비속어 필터 (등급심사 언어관리 정책) — 매칭되면 같은 길이의 *로 치환
  //    한글/영문 공용, 대소문자 무시. 오탐을 줄이려 '명백한 욕설' 위주로 구성.
  static const List<String> _badWords = [
    // 한글 욕설·변형
    '시발', '씨발', '시팔', '씨팔', '씨빨', '시빨', '씨바', '시바', '슈발', '쉬발', '씌발', '싀발',
    'ㅅㅂ', 'ㅆㅂ', 'ㅄ', 'ㅂㅅ', 'ㅈㄹ', 'ㅄ끼',
    '병신', '븅신', '병1신', '지랄', '지럴', '개지랄',
    '좆', '좇', '좃', '존나', '존내', '졸라', '조낸', '존니',
    '개새끼', '개색끼', '개세끼', '개쉐이', '새끼', '색끼', '쌔끼', '쉐끼', '썅', '쌍놈', '쌍년',
    '니미', '니애미', '니에미', '애미', '애비', '엄창', '느금마', '느금',
    '보지', '자지', '섹스', '창녀', '걸레년', '호로', '후장',
    '닥쳐', '닥치', '꺼져', '엿먹', '뒤져', '뒈져', '디져라',
    '미친놈', '미친년', '또라이', '등신', '머저리', '호구새끼',
    // 영문 욕설
    'fuck', 'fuckyou', 'fuckin', 'shit', 'bitch', 'asshole', 'dick', 'pussy',
    'nigger', 'motherfucker', 'bastard',
  ];

  static String cleanChat(String input) {
    if (input.isEmpty) return input;
    String out = input;
    for (final w in _badWords) {
      if (w.isEmpty) continue;
      final re = RegExp(RegExp.escape(w), caseSensitive: false);
      out = out.replaceAllMapped(re, (m) => '*' * m.group(0)!.runes.length);
    }
    return out;
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
    List<dynamic>? ownedInventory,            // 💳 넘기면: 보유한 캐시템(스킨·휘장·뱃지) 능력치 전부 합산(장착 불필요)
    int myLevel = 999999,                     // 🎖️ 캐시템 착용조건(레벨) 판정용 — 미달이면 능력치 미적용
    String myRank = '',                       // 🎖️ 스킨 착용조건(승급) 판정용
    bool isArena = false,                     // ⚔️ 아레나=평준화: 지급된 마스터 스킨·휘장을 조건 무시하고 적용
  }) {
    int totalStr = 30; int totalCtrl = 30; int totalSens = 30; // 🔧 기본 스텟 10→30(2026-08-27, 착용기반 전환 보상 +60 제압력)

    void addStats(Map<String, dynamic>? item) {
      if (item == null || item['stats'] == null) return;
      var s = item['stats'];
      totalStr += int.tryParse(s['P']?.toString() ?? s['힘']?.toString() ?? '0') ?? 0;
      totalCtrl += int.tryParse(s['C']?.toString() ?? s['컨트롤']?.toString() ?? '0') ?? 0;
      totalSens += int.tryParse(s['S']?.toString() ?? s['감도']?.toString() ?? '0') ?? 0;
    }

    // 💳 [2026-08-24] 캐시템 능력치 = 보유한 것 중 '착용조건(레벨/승급) 충족한 최고등급' 스킨1+뱃지1만(보유합산·스택 폐지).
    //    착용 안 해도 자동으로 최고 1개 반영(유저 편의 — 예전 보유자 능력치 유지). 조건 미달은 제외(홈페이지 레벨우회 차단).
    //    아레나(ownedInventory null)는 평준화라 캐시 스탯 제외.
    bool statEligible(Map<String, dynamic>? it) {
      if (it == null) return false;
      final int rl = (it['reqLevel'] is num) ? (it['reqLevel'] as num).toInt() : 0;
      if (rl > 0 && myLevel < rl) return false;
      final String rr = cashReqRank((it['name'] ?? '').toString()); // 🎖️ 뱃지/휘장도 승급 요구(이름 기반)
      if (rr.isNotEmpty && (myRank.isEmpty ? 999 : rankIndex(myRank)) < rankIndex(rr)) return false;
      return true;
    }
    // 💳 [착용기반] 착용한 스킨1+뱃지1만, 그것도 착용조건(레벨+승급) 충족 시에만 능력치 적용.
    //    (보유합산 폐지 — 착용/해제하면 제압력이 바뀜. 로그인 시 조건 되는 최고를 자동 착용해 예전 보유자 유지.)
    // ⚔️ 아레나는 평준화 — 지급된 마스터 스킨·정예휘장을 '조건 무시'하고 적용.
    //    (안 그러면 저랩 유저는 마스터스킨(300)·정예휘장(50) 조건 미달로 빠져 1350→300이 됨)
    if (isArena) {
      addStats(equippedSkin);
      addStats(equippedBadge);
    } else {
      if (statEligible(equippedSkin)) addStats(equippedSkin);
      if (statEligible(equippedBadge)) addStats(equippedBadge);
    }
    addStats(equippedRod);
    addStats(equippedFloat);
    addStats(equippedReel);
    addStats(equippedSunglasses);
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

  // 💳 보유한 캐시 코스메틱(스킨 SKIN · 휘장/뱃지 COMMON) 능력치 전부 합산.
  //    못 팔게 막은 영구 소장품이라 장착 안 해도 보유만 하면 다 적용(P/C/S).
  static Map<String, int> ownedCashStats(List<dynamic>? inventory, {int myLevel = 999999, String myRank = ''}) {
    int p = 0, c = 0, s = 0;
    if (inventory == null) return {'P': 0, 'C': 0, 'S': 0};
    final int myRankIdx = myRank.isEmpty ? 999 : rankIndex(myRank);
    for (final raw in inventory) {
      if (raw is! Map) continue;
      if ((raw['type'] ?? '').toString().toUpperCase() == 'EVENT') continue; // 🎁 이벤트 아이템은 eventItemBonus가 만료체크로 따로 처리(만료 시 0)
      final cat = (raw['category'] ?? '').toString().toUpperCase();
      if (cat != 'SKIN' && cat != 'COMMON') continue; // 캐시 코스메틱만(이용권 등 TICKET 제외)
      // 🎖️ 착용 조건(레벨·승급) 미달 = 능력치 미적용. 홈페이지선 조건 미달로도 구매 가능하니
      //    (구매=항상 지급, 계정당 1개라 exploit 없음) 조건 충족 전까지는 효과 X. 충족하면 자동 적용.
      final reqLv = (raw['reqLevel'] is num) ? (raw['reqLevel'] as num).toInt() : 0;
      if (reqLv > 0 && myLevel < reqLv) continue;
      final reqRank = (raw['reqRank'] ?? '').toString();
      if (reqRank.isNotEmpty && myRankIdx < rankIndex(reqRank)) continue;
      final st = raw['stats'];
      if (st is Map) {
        p += int.tryParse((st['P'] ?? st['힘'] ?? '0').toString()) ?? 0;
        c += int.tryParse((st['C'] ?? st['컨트롤'] ?? '0').toString()) ?? 0;
        s += int.tryParse((st['S'] ?? st['감도'] ?? '0').toString()) ?? 0;
      }
    }
    return {'P': p, 'C': c, 'S': s};
  }

  // 🛡️ 길드 레벨/버프 (광장·낚시 공용 계산식)
  // guildExpTable[레벨] = 그 레벨이 되기 위한 누적 길드 경험치(=누적 마릿수) (index 0 미사용, 최대 Lv30)
  // 🎣 누적 마릿수(=길드원 전체 잡은 마릿수). 1마리=1점.
  //    [2026-08 재설계] 레벨당 필요치: 1→2=1000, 이후 증가폭 Lv1~10 +100 / Lv10~20 +200 / Lv20~30 +300.
  //    (1000→1100→…→1800→2000→…→3800→4100→…→6800). 만렙 Lv30 누적 96,100마리.
  //    인원 많을수록 다같이 잡아 빨리 도달(모집 보상), 적으면 천천히.
  static const List<int> guildExpTable = [
    0,        // 0 (미사용)
    0,        // Lv1
    1000,     // Lv2   ─┐ Lv1~10: 레벨당 +100 (1000→1100→…→1800)
    2100,     // Lv3    │
    3300,     // Lv4    │
    4600,     // Lv5    │
    6000,     // Lv6    │
    7500,     // Lv7    │
    9100,     // Lv8    │
    10800,    // Lv9    │
    12600,    // Lv10  ─┘
    14600,    // Lv11  ─┐ Lv10~20: 레벨당 +200 (2000→…→3800)
    16800,    // Lv12   │
    19200,    // Lv13   │
    21800,    // Lv14   │
    24600,    // Lv15   │
    27600,    // Lv16   │
    30800,    // Lv17   │
    34200,    // Lv18   │
    37800,    // Lv19   │
    41600,    // Lv20  ─┘
    45700,    // Lv21  ─┐ Lv20~30: 레벨당 +300 (4100→…→6800)
    50100,    // Lv22   │
    54800,    // Lv23   │
    59800,    // Lv24   │
    65100,    // Lv25   │
    70700,    // Lv26   │
    76600,    // Lv27   │
    82800,    // Lv28   │
    89300,    // Lv29   │
    96100,    // Lv30  ─┘
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

  // 🏴 [2026-08-27] 보스 처치 깃발 보너스: 길드가 클리어한 보스(clearedBosses) 1마리당 힘/컨/감 각 +5(누적, 길드원 전체).
  //    보스 총 5마리 → 최대 각 +25(총 제압력 +75). 중복(같은 보스 재처치)은 clearedBosses가 arrayUnion(distinct)이라 한 번만.
  static int guildBossBonus(int clearedCount) => (clearedCount * 5).clamp(0, 25);

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

  // 주간 리그 top3 길드가 다음 한 주 동안 소속원 전원에게 주는 P/C/S 각 보너스.
  //   1위+10(제압력+30) / 2위+5(+15) / 3위+2(+6). 전원 적용이라 개인랭킹보다 보수적으로.
  static int guildLeagueBonus(int rank) {
    if (rank == 1) return 10;
    if (rank == 2) return 5;
    if (rank == 3) return 2;
    return 0;
  }

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

// =========================================================================
// 🐲 [보스레이드 제압력 계산] 모임터(레이드 셋팅)와 전투화면이 같은 값을 쓰도록 공용화.
//   userData = users/{uid} 문서. 낚시터 '자동장착'과 동일 규칙으로 최상급 장비를 고르되,
//   낚싯대 슬롯만 레이드 전용대(category RAID)로 대체한다(있으면).
//   반환: power(합산 제압력) · raidTier(1~3, 0=없음) · rodName · skinName · rodSfx(폴백 그림용)
// =========================================================================
// statBonus = 길드레벨 + 길드리그랭킹 + 개인랭킹(가람) 보너스의 합(스탯 1개당). 일반 낚시와 동일하게 3스탯 각각에 더해진다.
Map<String, dynamic> resolveRaidGearPower(Map<String, dynamic> userData, {bool isSea = false, int statBonus = 0}) {
  final inv = (userData['inventory'] as List?) ?? [];
  // 🆕 users.level은 가입 시 1로 박힌 뒤 갱신되지 않는다(2026-08-30 발견).
  //    화면의 레벨·등급은 전부 exp에서 계산하므로 여기도 exp 기준으로 맞춘다.
  //    ⚠️ 1로 굳어 있으면 레벨 보너스가 0이 되고, reqLevel 있는 휘장·스킨이 통째로 무효화됐다.
  final int level = calcLevelFromExp((userData['exp'] is num) ? (userData['exp'] as num).toInt() : 0);
  final String myRankStr = (userData['rank'] ?? '초보').toString();

  // 🎖️ 착용조건(레벨·승급) 미달 캐시템은 능력치가 안 붙는다(getMyTotalStats.statEligible).
  //    그러니 선택 단계에서도 걸러야 '내 장비' 패널과 실제 제압력이 어긋나지 않는다.
  //    (예전엔 조건 미달인 중수 스킨·휘장이 패널에 뜨는데 제압력 기여는 0이었음 — 2026-08-30 수정)
  bool cashEligible(Map<String, dynamic> it) {
    final int rl = (it['reqLevel'] is num) ? (it['reqLevel'] as num).toInt() : 0;
    if (rl > 0 && level < rl) return false;
    final String rr = cashReqRank((it['name'] ?? '').toString());
    if (rr.isNotEmpty && rankIndex(myRankStr) < rankIndex(rr)) return false;
    return true;
  }

  int rodTierFw(String n) { n = n.replaceAll(' ', '').replaceAll('-', '').toUpperCase();
    if (n.contains('KT40')) return 60; if (n.contains('KT30')) return 50; if (n.contains('KT20')) return 40;
    if (n.contains('CF40')) return 30; if (n.contains('CF30')) return 20; if (n.contains('CF20')) return 10; return 1; }
  int rodTierSea(String n) { n = n.replaceAll(' ', '').toUpperCase();
    if (n.contains('KT500')) return 60; if (n.contains('KT350')) return 50; if (n.contains('KT250')) return 40;
    if (n.contains('CF500')) return 30; if (n.contains('CF350')) return 20; if (n.contains('CF250')) return 10; return 1; }
  int floatTier(String n) { n = n.replaceAll(' ', '').toUpperCase();
    if (n.contains('KT전자')) return 60; if (n.contains('CF전자')) return 50; if (n.contains('나노')) return 40;
    if (n.contains('수제')) return 30; if (n.contains('오동')) return 20; return 1; }
  int reelTier(String n) { n = n.replaceAll(' ', '').toUpperCase();
    if (n.contains('KF8000')) return 80; if (n.contains('KF6000')) return 60; if (n.contains('KF5000')) return 50;
    if (n.contains('CF5000')) return 40; if (n.contains('CF3000')) return 30; return 1; }
  int coolerTier(String n) { if (n.contains('대형')) return 3; if (n.contains('중형')) return 2; return 1; }

  Map<String, dynamic>? skin, rod, raidRod, float, reel, cooler, sunglasses, badge, net, belt, gloves, line;
  for (final raw in inv) {
    if (raw is! Map) continue;
    final item = Map<String, dynamic>.from(raw);
    final name = (item['name'] ?? '').toString();
    final cat = (item['category'] ?? '').toString().toUpperCase();
    // 🐲 레이드대(category RAID)는 물/바다 구분 없이 최고 티어 → 낚싯대 슬롯 대체
    if (isRaidRod(item)) {
      if (raidRod == null || raidRodTierByName(name) > raidRodTierByName((raidRod['name'] ?? '').toString())) raidRod = item;
      continue;
    }
    if (isSea && cat == 'FW') continue;
    if (!isSea && cat == 'SEA') continue;

    if (isSkinItem(item)) {
      if (!cashEligible(item)) continue; // 🎖️ 조건 미달 스킨은 아예 후보에서 제외(표시·계산 일치)
      if (skin == null || skinTierByName(name) > skinTierByName((skin['name'] ?? '').toString())) skin = item;
    } else if (name.contains('찌')) {
      if (float == null || floatTier(name) > floatTier((float['name'] ?? '').toString())) float = item;
    } else if (item['type'] == 'COOLER' || name.contains('아이스박스') || name.contains('쿨러') || name.contains('보냉')) {
      if (cooler == null || coolerTier(name) > coolerTier((cooler['name'] ?? '').toString())) cooler = item;
    } else if (item['type'] == 'REEL' || name.contains('릴')) {
      if (reel == null || reelTier(name) > reelTier((reel['name'] ?? '').toString())) reel = item;
    } else if ((name.contains('대') || name.contains('CF') || name.contains('KT')) &&
        !name.contains('찌') && !name.contains('릴') && !name.contains('아이스박스') && !name.contains('쿨러') && !name.contains('보냉')) {
      final isSeaRod = name.contains('250') || name.contains('350') || name.contains('500');
      if (isSea == isSeaRod) {
        final t = isSea ? rodTierSea(name) : rodTierFw(name);
        final bt = rod == null ? -1 : (isSea ? rodTierSea((rod['name'] ?? '').toString()) : rodTierFw((rod['name'] ?? '').toString()));
        if (t > bt) rod = item;
      }
    }
    // 🕶️ 선글라스도 등급 비교(레인보우 편광 20/20/20 > 일반 10/10/10).
    //    ⚠️ 예전엔 `??=`라 인벤토리에서 먼저 나온 것이 잡혀, 상급을 갖고도 하급이 적용됐음(2026-08-30 수정).
    else if (name.contains('선글라스')) {
      final p = (item['stats']?['P'] as num?)?.toInt() ?? 0;
      final bp = (sunglasses?['stats']?['P'] as num?)?.toInt() ?? -1;
      if (sunglasses == null || p > bp) sunglasses = item;
    }
    else if (name.contains('휘장') || name.contains('뱃지')) {
      if (!cashEligible(item)) continue; // 🎖️ 조건 미달 휘장·뱃지 제외
      final p = (item['stats']?['P'] as num?)?.toInt() ?? 0;
      final bp = (badge?['stats']?['P'] as num?)?.toInt() ?? -1;
      if (badge == null || p > bp) badge = item;
    }
    else if (name.contains('뜰채')) net ??= item;
    else if (name.contains('벨트')) belt ??= item;
    else if (name.contains('장갑')) gloves ??= item;
    else if (name.contains('낚시줄')) line ??= item;
  }

  final Map<String, dynamic>? rodForCalc = raidRod ?? rod;
  final s = FishingLogic.getMyTotalStats(
    equippedSkin: skin, equippedRod: rodForCalc, equippedFloat: float, equippedReel: reel,
    equippedSunglasses: sunglasses, equippedBadge: badge, equippedCooler: cooler,
    equippedNet: net, equippedBelt: belt, equippedGloves: gloves, equippedLine: line,
    ownedInventory: null, // 💳 착용기반 — 자동장착이 고른 스킨·뱃지(조건 충족)만
    myLevel: level, myRank: myRankStr,
  );
  final lvBonus = (level > 0 ? level : 1) * 3; // 🆙 Lv당 +3(각 스탯 +레벨), Lv과 일치(2026-08-24)
  // 🛡️ 길드레벨·길드랭킹·개인랭킹 보너스(statBonus)는 일반 낚시처럼 3스탯 각각에 적용 → power엔 ×3
  int power = (s['strength'] ?? 0) + (s['control'] ?? 0) + (s['sensitivity'] ?? 0) + lvBonus + statBonus * 3;
  final tp = (userData['testPower'] is num) ? (userData['testPower'] as num).toInt() : 0;
  if (tp > 0) power = tp;

  String sfx = rod != null ? rodSceneSuffix(rod) : '';
  if (sfx.isEmpty) sfx = isSea ? 'kt500' : 'kt40';

  // 🎒 레이드에 실제로 쓰일 장비 목록(모임터 '내 장비' 패널용). null 슬롯은 제외.
  final List<Map<String, dynamic>> gearList = [];
  void addGear(String slot, Map<String, dynamic>? it) {
    if (it == null) return;
    gearList.add({'slot': slot, 'name': (it['name'] ?? '').toString(), 'icon': (it['icon'] ?? '').toString()});
  }
  addGear('낚싯대', rodForCalc);
  addGear('스킨', skin);
  addGear('릴', reel);
  addGear('찌', float);
  addGear('휘장', badge);
  addGear('선글라스', sunglasses);
  addGear('뜰채', net);
  addGear('벨트', belt);
  addGear('장갑', gloves);
  addGear('낚시줄', line);
  addGear('쿨러', cooler);

  return {
    'power': power,
    'raidTier': raidRod != null ? raidRodTierByName((raidRod['name'] ?? '').toString()) : 0,
    'raidRod': raidRod,
    'rodName': rodForCalc?['name'] ?? '기본 장비',
    'skinName': skin?['name'] ?? '기본 스킨',
    'rodSfx': sfx,
    'gearList': gearList,
    'level': level,
    // HUD 표시용 스탯 분해(레벨+길드/랭킹 보너스 포함 — 합=power와 동일)
    'p': (s['strength'] ?? 0) + lvBonus ~/ 3 + statBonus,
    'c': (s['control'] ?? 0) + lvBonus ~/ 3 + statBonus,
    's': (s['sensitivity'] ?? 0) + (lvBonus - (lvBonus ~/ 3) * 2) + statBonus,
  };
}
