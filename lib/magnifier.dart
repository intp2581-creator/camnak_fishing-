// 🔍 [돋보기] 폰 가로화면에서 글씨가 작아 안 보인다는 요청(2026-09-05).
//
//   왜 이런 방식인가 —
//     · 게임은 1280x720 고정 화면을 통째로 줄여 그린다. 폰에서는 글씨도 같이 작아진다.
//     · 브라우저의 두 손가락 확대는 못 쓴다. Flutter 엔진이 터치마다 preventDefault()를
//       호출해서 브라우저가 확대 제스처를 시작조차 못 한다(2026-09-05 확인).
//     · 확대를 상시로 켜두면 한 손가락 끌기가 밀당·캐릭터 이동과 부딪히고,
//       광장은 두 손가락을 이미 '캐릭터 줌'이 쓰고 있다.
//   → 그래서 '모드'로 나눈다. 돋보기를 켠 동안만 확대/이동, 그동안 게임 조작은 잠긴다.
//
//   ⚠️ 구조 주의 — 이 위젯은 앱 전체(Navigator)를 자식으로 감싼다.
//      켜고 끌 때 자식의 위젯 종류가 바뀌면 앱이 통째로 다시 만들어져 상태가 날아간다.
//      그래서 자식은 항상 같은 Transform 아래 두고, 제스처를 받는 판만 위에 덮었다 뗀다.
import 'dart:html' as html;
import 'package:flutter/material.dart';

class MagnifierShell extends StatefulWidget {
  final Widget child;
  const MagnifierShell({super.key, required this.child});

  @override
  State<MagnifierShell> createState() => _MagnifierShellState();
}

class _MagnifierShellState extends State<MagnifierShell> {
  static const double _maxScale = 4.0;

  /// 🖥️ PC에서는 쓸모가 없다 — 확대·이동이 두 손가락 제스처라 마우스로는 안 된다.
  ///    (pointer: coarse) = 손가락으로 조작하는 기기. 폰·태블릿에서만 돋보기를 띄운다.
  static final bool _touchDevice = _isTouch();
  static bool _isTouch() {
    try {
      return html.window.matchMedia('(pointer: coarse)').matches == true;
    } catch (_) {
      return false;
    }
  }

  bool _on = false;
  double _scale = 1.0;
  Offset _off = Offset.zero;

  double _startScale = 1.0;
  Offset _startOff = Offset.zero;
  Offset _startFocal = Offset.zero;
  Size _size = Size.zero;

  void _toggle() {
    setState(() {
      _on = !_on;
      if (!_on) {
        _scale = 1.0;
        _off = Offset.zero;
      }
    });
  }

  /// 확대한 만큼만 움직이게 — 여백이 보이도록 끌려나가지 않게 막는다.
  Offset _clamp(Offset o, double s) {
    final double mx = (_size.width * (s - 1)) / 2;
    final double my = (_size.height * (s - 1)) / 2;
    return Offset(o.dx.clamp(-mx, mx), o.dy.clamp(-my, my));
  }

  @override
  Widget build(BuildContext context) {
    // PC면 아무것도 감싸지 않고 그대로 통과 — 화면에 버튼도 안 뜬다.
    if (!_touchDevice) return widget.child;
    return LayoutBuilder(builder: (ctx, c) {
      _size = Size(c.maxWidth, c.maxHeight);
      return Stack(
        children: [
          // 게임 본체 — 위젯 종류가 바뀌지 않으므로 확대를 켜고 꺼도 상태가 유지된다.
          Positioned.fill(
            child: Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()
                ..translate(_off.dx, _off.dy)
                ..scale(_scale),
              child: widget.child,
            ),
          ),

          // 돋보기가 켜져 있을 때만 덮는 조작판. 이 판이 모든 터치를 받으므로
          // 게임 조작은 자연스럽게 잠긴다(따로 막을 필요 없음).
          if (_on)
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onScaleStart: (d) {
                  _startScale = _scale;
                  _startOff = _off;
                  _startFocal = d.localFocalPoint;
                },
                onScaleUpdate: (d) {
                  // 두 손가락 벌리기 = 확대 / 손가락 끌기 = 이동. 둘 다 이 콜백으로 온다.
                  final double s = (_startScale * d.scale).clamp(1.0, _maxScale);
                  final Offset moved = _startOff + (d.localFocalPoint - _startFocal);
                  setState(() {
                    _scale = s;
                    _off = _clamp(moved, s);
                  });
                },
                onDoubleTap: () => setState(() {
                  _scale = _scale > 1.05 ? 1.0 : 2.0;
                  _off = _clamp(_off, _scale);
                }),
              ),
            ),

          // 🔍 버튼 — 팝업 위에도 뜬다(앱 전체를 감싸고 있으므로).
          //    높이 40% 지점. 화면 한가운데 두었더니 광장 조이스틱(좌하단)에 붙어
          //    이동하다 자꾸 눌렸다(2026-09-05). 위로는 상단 HUD·길드바, 아래로는
          //    조이스틱과 채팅창이 있어 이 언저리가 양쪽 화면 모두에서 비어 있다.
          Positioned(
            left: 4,
            top: c.maxHeight * 0.40 - 17,
            child: _button(),
          ),

          if (_on)
            Positioned(
              left: 0,
              right: 0,
              top: 6,
              child: IgnorePointer(
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.72),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFFD4AF37), width: 1.2),
                    ),
                    child: Text(
                      '🔍 확대 보기  ·  두 손가락으로 크기 조절 · 끌어서 이동 · 두 번 눌러 원래대로'
                      '${_scale > 1.05 ? '   (${_scale.toStringAsFixed(1)}배)' : ''}',
                      style: const TextStyle(
                          color: Color(0xFFFFE9A8), fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ),
            ),
        ],
      );
    });
  }

  Widget _button() {
    return GestureDetector(
      onTap: _toggle,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: _on ? const Color(0xFFD4AF37) : Colors.black.withOpacity(0.45),
          shape: BoxShape.circle,
          border: Border.all(
              color: _on ? Colors.black : const Color(0xFFD4AF37).withOpacity(0.7), width: 1.4),
        ),
        child: Icon(
          _on ? Icons.close : Icons.zoom_in,
          size: 20,
          color: _on ? Colors.black : const Color(0xFFD4AF37).withOpacity(0.85),
        ),
      ),
    );
  }
}
