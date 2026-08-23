// 📸 [게임 화면 스크린샷] 현재 화면을 JPG로 떠서 브라우저 다운로드.
//   · 주소창/상태바 없이 게임 화면만 깔끔하게 저장 → 홈페이지 조행기 업로드용.
//   · Flutter는 PNG만 뽑아주므로, rawRgba → 브라우저 canvas → toDataUrl('image/jpeg')로 변환한다.
//   · 사용법: 화면 최상위를 RepaintBoundary(key: myKey)로 감싸고 saveScreenshotJpg(myKey) 호출.
import 'dart:async';
import 'dart:html' as html;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// 화면 캡처 → JPG 다운로드. 성공하면 true.
///   [prefix] 파일명 앞부분(예: 'camnak_guild') · [quality] 0~1 (기본 0.92)
Future<bool> saveScreenshotJpg(
  GlobalKey boundaryKey, {
  String prefix = 'camnak',
  double pixelRatio = 2.0,
  double quality = 0.92,
}) async {
  try {
    final ctx = boundaryKey.currentContext;
    if (ctx == null) return false;
    final boundary = ctx.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return false;

    // 프레임이 아직 안 그려졌으면 한 프레임 기다림
    if (boundary.debugNeedsPaint) {
      await Future.delayed(const Duration(milliseconds: 40));
    }

    final ui.Image image = await boundary.toImage(pixelRatio: pixelRatio);
    final ByteData? raw = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (raw == null) return false;

    // rawRgba → canvas → JPEG
    final canvas = html.CanvasElement(width: image.width, height: image.height);
    final c2d = canvas.context2D;
    final imgData = c2d.createImageData(image.width, image.height);
    imgData.data.setAll(0, raw.buffer.asUint8List());
    c2d.putImageData(imgData, 0, 0);
    final String dataUrl = canvas.toDataUrl('image/jpeg', quality);
    image.dispose();

    // 다운로드
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final name = '${prefix}_${now.year}${two(now.month)}${two(now.day)}_'
        '${two(now.hour)}${two(now.minute)}${two(now.second)}.jpg';
    html.AnchorElement(href: dataUrl)
      ..setAttribute('download', name)
      ..click();
    return true;
  } catch (e) {
    debugPrint('📸 스크린샷 실패: $e');
    return false;
  }
}

/// 스크린샷 + 결과 안내(스낵바)까지 한 번에.
Future<void> takeScreenshot(BuildContext context, GlobalKey boundaryKey, {String prefix = 'camnak'}) async {
  final ok = await saveScreenshotJpg(boundaryKey, prefix: prefix);
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(ok ? '📸 스크린샷을 저장했어요! (다운로드 폴더)' : '📸 스크린샷을 저장하지 못했어요.'),
      backgroundColor: Colors.black87,
      duration: const Duration(seconds: 2),
    ));
}
