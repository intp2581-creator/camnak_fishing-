// ignore_for_file: deprecated_member_use
// ⚔️📋 [아레나 접속 기록] 대회 중 튕김을 나중에 확인할 수 있게 남긴다.
//
//   왜 필요한가 — 2026-09-05 낚시신동님이 "아레나 중에 두 번 튕겼다"고 제보하셨는데,
//   서버에 아무 기록이 없어 확인해 드릴 방법이 없었다. 방(arenas 문서)은 경기가 끝나면
//   지워지므로, 방과 별개인 곳에 남겨야 나중에 볼 수 있다.
//
//   어디에 — RTDB `arena_logs/{roomId}/{uid}`
//     joinedAt        입장 시각
//     beat            살아있음 신호(15초마다 갱신) + 그때의 남은시간·마릿수
//     exitAt/reason   정상 종료('finished') 또는 스스로 나감('left')
//     disconnectedAt  ⚠️ 브라우저가 끊겼을 때 서버가 찍는다(창 닫힘·크래시·네트워크 끊김)
//
//   읽는 법 — exitAt 없이 disconnectedAt만 있으면 '진짜 튕김'이다.
//   beat 가 마지막으로 찍힌 시각이 곧 마지막으로 살아있던 순간.
//   (onDisconnect 는 클라이언트가 아니라 서버가 실행하므로, 창을 강제로 닫아도 남는다)
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';

const String _logDbUrl =
    'https://camnak-fishing-default-rtdb.asia-southeast1.firebasedatabase.app';

FirebaseDatabase _logDb() =>
    FirebaseDatabase.instanceFor(app: Firebase.app(), databaseURL: _logDbUrl);

class ArenaLog {
  static DatabaseReference? _ref;
  static Timer? _beatTimer;
  static bool _closed = false;

  /// 아레나 낚시 화면 진입 시 1회.
  static void start({
    required String roomId,
    required String uid,
    required String nick,
    required String roomTitle,
    required int Function() timeLeft, // 남은 시간(초)을 그때그때 읽어온다
    required int Function() score, // 잡은 마릿수
  }) {
    stop(); // 이전 잔재 정리
    _closed = false;
    try {
      _ref = _logDb().ref('arena_logs/$roomId/$uid');
      _ref!.update({
        'nick': nick,
        'room': roomTitle,
        'joinedAt': ServerValue.timestamp,
      }).catchError((Object e) => debugPrint('⚔️📋 arena log start ERR: $e'));

      // ⚠️ 핵심 — 브라우저가 끊기면 '서버가' 이 값을 찍는다. 창을 그냥 닫아도 남는다.
      _ref!.onDisconnect().update({
        'disconnectedAt': ServerValue.timestamp,
      }).catchError((Object e) => debugPrint('⚔️📋 arena onDisconnect ERR: $e'));

      _beat(timeLeft, score);
      _beatTimer = Timer.periodic(
          const Duration(seconds: 15), (_) => _beat(timeLeft, score));
    } catch (e) {
      debugPrint('⚔️📋 arena log start 실패: $e');
    }
  }

  static void _beat(int Function() timeLeft, int Function() score) {
    if (_ref == null || _closed) return;
    _ref!.update({
      'beat': ServerValue.timestamp,
      'left': timeLeft(),
      'score': score(),
    }).catchError((Object e) => debugPrint('⚔️📋 arena beat ERR: $e'));
  }

  /// 화면을 정상적으로 빠져나갈 때(종료·이탈 모두). 여기까지 오면 '튕김'이 아니다.
  static void finish({required bool endedNaturally, required int timeLeft, required int score}) {
    final ref = _ref;
    if (ref == null || _closed) return;
    _closed = true;
    _beatTimer?.cancel();
    _beatTimer = null;
    // 정상 종료인데 창을 닫았다고 '튕김'으로 기록되면 안 되므로 예약을 취소한다.
    ref.onDisconnect().cancel().catchError((_) {});
    ref.update({
      'exitAt': ServerValue.timestamp,
      'reason': endedNaturally ? 'finished' : 'left',
      'left': timeLeft,
      'score': score,
    }).catchError((Object e) => debugPrint('⚔️📋 arena finish ERR: $e'));
    _ref = null;
  }

  static void stop() {
    _beatTimer?.cancel();
    _beatTimer = null;
    _ref = null;
    _closed = false;
  }
}
