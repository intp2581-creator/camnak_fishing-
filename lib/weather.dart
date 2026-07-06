// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter, curly_braces_in_flow_control_structures, unnecessary_underscores
// 🌧️ 실시간 날씨 연동 (기상청 초단기실황 → 게임 화면에 비/눈)
//   - 브라우저 위치(권한) → Firebase 함수 getWeather 호출 → 강수형태(PTY)
//   - 위치 거부/실패 시 함수가 서울 기본값 사용 → 게임은 정상 동작
//   ⚠️ 웹 전용(dart:html). 이 게임은 Flutter Web 이므로 문제 없음.
import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'fishing_logic.dart'; // 🌧️ audioManager(빗소리)

/// 날씨 정보 (강수형태 PTY 기반)
///   PTY: 0 없음 / 1 비 / 2 비·눈 / 3 눈 / 4 소나기 / 5 빗방울 / 6 진눈깨비 / 7 눈날림
class WeatherInfo {
  final int pty;
  final String? temp; // 기온(℃)
  final String region; // "서울특별시 강남구"
  const WeatherInfo({this.pty = 0, this.temp, this.region = ''});

  bool get isRain => pty == 1 || pty == 4 || pty == 5; // 순수 비
  bool get isSleet => pty == 2 || pty == 6; // 진눈깨비(비+눈)
  bool get isSnow => pty == 3 || pty == 7; // 눈
  bool get isClear => !isRain && !isSleet && !isSnow;

  String get label {
    switch (pty) {
      case 1:
      case 5:
        return '비';
      case 2:
      case 6:
        return '진눈깨비';
      case 3:
      case 7:
        return '눈';
      case 4:
        return '소나기';
      default:
        return '맑음';
    }
  }

  String get emoji {
    if (isSnow) return '❄️';
    if (isSleet) return '🌨️';
    if (isRain) return '🌧️';
    return '☀️';
  }
}

/// 날씨 서비스 (싱글턴). 게임 켤 때/화면 진입 시 refresh() 호출.
class WeatherService {
  WeatherService._();
  static final WeatherService instance = WeatherService._();

  // ⚠️ Firebase 함수 URL (리전 us-central1 기준). 리전 다르면 여기만 바꾸면 됨.
  static const String _fnUrl =
      'https://us-central1-camnak-fishing.cloudfunctions.net/getWeather';

  final ValueNotifier<WeatherInfo> notifier =
      ValueNotifier<WeatherInfo>(const WeatherInfo());

  DateTime? _lastFetch;
  bool _fetching = false;

  /// 30분 이내면 캐시 사용(중복 호출 방지). force=true 면 강제 갱신.
  Future<void> refresh({bool force = false}) async {
    // 🧪 운영자 미리보기: 주소 뒤에 ?wx=rain / ?wx=snow / ?wx=clear 붙이면 강제 적용
    //   (실제 날씨와 무관하게 비/눈 연출 확인용. 키 없이도 동작)
    final wx = Uri.base.queryParameters['wx'];
    if (wx != null && wx.isNotEmpty) {
      int p = 0;
      if (wx == 'rain') p = 1;
      else if (wx == 'snow') p = 3;
      else if (wx == 'sleet') p = 2;
      notifier.value = WeatherInfo(pty: p, temp: null, region: '미리보기($wx)');
      _lastFetch = DateTime.now();
      return;
    }

    if (_fetching) return;
    if (!force &&
        _lastFetch != null &&
        DateTime.now().difference(_lastFetch!) < const Duration(minutes: 30)) {
      return;
    }
    _fetching = true;
    try {
      final pos = await _getPosition();
      final q = pos == null ? '' : '?lat=${pos[0]}&lon=${pos[1]}';
      final resp = await html.HttpRequest.getString(_fnUrl + q);
      final data = json.decode(resp) as Map<String, dynamic>;
      final rawPty = data['pty'];
      final pty = rawPty is int ? rawPty : int.tryParse('$rawPty') ?? 0;
      notifier.value = WeatherInfo(
        pty: pty,
        temp: data['temp']?.toString(),
        region: (data['region'] ?? '').toString(),
      );
      _lastFetch = DateTime.now();
    } catch (_) {
      // 실패해도 게임엔 지장 없음(맑음 유지)
    } finally {
      _fetching = false;
    }
  }

  /// 브라우저 위치. 거부/실패 시 null → 함수가 서울 기본값 사용.
  Future<List<double>?> _getPosition() async {
    try {
      final pos = await html.window.navigator.geolocation.getCurrentPosition(
        enableHighAccuracy: false,
        timeout: const Duration(seconds: 8),
        maximumAge: const Duration(minutes: 30),
      );
      final c = pos.coords;
      if (c == null || c.latitude == null || c.longitude == null) return null;
      return [c.latitude!.toDouble(), c.longitude!.toDouble()];
    } catch (_) {
      return null;
    }
  }
}

/// 화면 위에 얹는 비/눈 오버레이.
/// 사용: Positioned.fill(child: IgnorePointer(child: WeatherOverlay()))
class WeatherOverlay extends StatefulWidget {
  final bool isSea; // 바다면 비를 살짝 더 세게
  const WeatherOverlay({super.key, this.isSea = false});
  @override
  State<WeatherOverlay> createState() => _WeatherOverlayState();
}

class _WeatherOverlayState extends State<WeatherOverlay>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  double _time = 0; // 경과 초(부드러운 애니메이션용)
  final List<_Drop> _drops = [];
  final math.Random _rnd = math.Random();
  WeatherInfo _w = const WeatherInfo();
  bool _holdingRain = false; // 🌧️ 이 오버레이가 빗소리 참조를 잡고 있는지

  @override
  void initState() {
    super.initState();
    _w = WeatherService.instance.notifier.value;
    _rebuildDrops();
    _updateRainSound();
    WeatherService.instance.notifier.addListener(_onWeather);
    _ticker = createTicker((elapsed) {
      _time = elapsed.inMicroseconds / 1e6;
      if (mounted && !_w.isClear) setState(() {});
    })..start();
  }

  void _onWeather() {
    if (!mounted) return;
    setState(() {
      _w = WeatherService.instance.notifier.value;
      _rebuildDrops();
    });
    _updateRainSound();
  }

  // 🌧️ 비/진눈깨비면 빗소리 켜고, 아니면 끔(참조 카운트로 화면 겹침 안전 처리)
  void _updateRainSound() {
    final bool wantRain = _w.isRain || _w.isSleet;
    if (wantRain && !_holdingRain) {
      _holdingRain = true;
      audioManager.requestRain();
    } else if (!wantRain && _holdingRain) {
      _holdingRain = false;
      audioManager.releaseRain();
    }
  }

  void _rebuildDrops() {
    _drops.clear();
    if (_w.isClear) return;
    final bool snow = _w.isSnow;
    final bool sleet = _w.isSleet;
    final int count =
        snow ? 80 : (sleet ? 90 : (widget.isSea ? 95 : 75));
    for (int i = 0; i < count; i++) {
      // 눈이면 전부 눈송이, 진눈깨비면 40%만 눈송이(나머지 빗줄기), 비면 전부 빗줄기
      final bool flake =
          snow ? true : (sleet ? _rnd.nextDouble() < 0.4 : false);
      _drops.add(_Drop(
        flake: flake,
        x: _rnd.nextDouble(),
        y: _rnd.nextDouble(),
        len: flake ? (4 + _rnd.nextDouble() * 4) : (9 + _rnd.nextDouble() * 12),
        speed: flake
            ? (0.05 + _rnd.nextDouble() * 0.08)
            : (0.35 + _rnd.nextDouble() * 0.25),
        drift: flake ? (_rnd.nextDouble() - 0.5) * 0.25 : 0.10,
      ));
    }
  }

  @override
  void dispose() {
    WeatherService.instance.notifier.removeListener(_onWeather);
    if (_holdingRain) { _holdingRain = false; audioManager.releaseRain(); } // 🌧️ 화면 나가면 참조 반납
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_w.isClear) return const SizedBox.shrink();
    final double darken = _w.isSnow ? 0.05 : 0.07;
    return CustomPaint(
      painter: _WeatherPainter(_drops, _time, darken),
      size: Size.infinite,
    );
  }
}

class _Drop {
  final bool flake; // true=눈송이, false=빗줄기
  double x, y, len, speed, drift;
  _Drop({
    required this.flake,
    required this.x,
    required this.y,
    required this.len,
    required this.speed,
    required this.drift,
  });
}

class _WeatherPainter extends CustomPainter {
  final List<_Drop> drops;
  final double time; // 경과 초
  final double darken;
  _WeatherPainter(this.drops, this.time, this.darken);

  @override
  void paint(Canvas canvas, Size size) {
    // 흐린 하늘 느낌으로 살짝 어둡게
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = Colors.black.withOpacity(darken),
    );
    final flakePaint = Paint()
      ..color = Colors.white.withOpacity(0.9)
      ..strokeWidth = 1.1
      ..strokeCap = StrokeCap.round;
    final linePaint = Paint()
      ..color = const Color(0x77CFE8FF)
      ..strokeWidth = 1.0
      ..strokeCap = StrokeCap.round;
    for (final d in drops) {
      final double prog = (d.y + time * d.speed) % 1.0;
      final double px = ((d.x + prog * d.drift) % 1.0) * size.width;
      final double py = prog * size.height;
      if (d.flake) {
        // ❄️ 6방향 눈 결정 모양(천천히 회전)
        final double rot = time * 0.5 + d.x * 6.28;
        _drawFlake(canvas, Offset(px, py), d.len, rot, flakePaint);
      } else {
        // 대각선 빗줄기
        canvas.drawLine(
          Offset(px, py),
          Offset(px - d.len * 0.25, py + d.len),
          linePaint,
        );
      }
    }
  }

  // 눈 결정: 중심에서 6개 가지 + 각 가지에 작은 곁가지
  void _drawFlake(Canvas c, Offset o, double r, double rot, Paint p) {
    for (int i = 0; i < 6; i++) {
      final double a = rot + i * (math.pi / 3);
      final double ex = o.dx + math.cos(a) * r;
      final double ey = o.dy + math.sin(a) * r;
      c.drawLine(o, Offset(ex, ey), p);
      // 곁가지(가지의 60% 지점에서 양쪽으로)
      final double bx = o.dx + math.cos(a) * r * 0.6;
      final double by = o.dy + math.sin(a) * r * 0.6;
      final double bl = r * 0.38;
      for (final int s in const [1, -1]) {
        final double a2 = a + s * (math.pi / 6);
        c.drawLine(Offset(bx, by),
            Offset(bx + math.cos(a2) * bl, by + math.sin(a2) * bl), p);
      }
    }
  }

  @override
  bool shouldRepaint(_WeatherPainter old) => true;
}

/// 지역명 + 날씨 뱃지 (친구끼리 "너 거기 비 와?" 비교용).
/// 데이터 없으면 아무것도 안 보임.
class WeatherBadge extends StatelessWidget {
  const WeatherBadge({super.key});
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<WeatherInfo>(
      valueListenable: WeatherService.instance.notifier,
      builder: (_, w, __) {
        final hasData = w.region.isNotEmpty || w.temp != null;
        if (!hasData) return const SizedBox.shrink();
        final parts = <String>[];
        if (w.region.isNotEmpty) parts.add('📍 ${w.region}');
        parts.add('${w.emoji} ${w.label}');
        if (w.temp != null) parts.add('${w.temp}℃');
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.45),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white24),
          ),
          child: Text(
            parts.join('   ·   '),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        );
      },
    );
  }
}
