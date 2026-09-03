// ignore_for_file: deprecated_member_use
// 🎣👀 [친구 낚시 라이브 관전] 방송(낚시하는 쪽) + 관전(구경하는 쪽) RTDB 헬퍼.
//   · 낚시 상태를 RTDB `fishing_live/{fisherUid}`에 실어, 친구가 관전 화면에서 재구성해 본다.
//   · 서버비 절감: state(전투 프레임)는 '관전자가 있을 때만' 방송. meta는 진입 즉시 1회.
//   · 아레나는 방송하지 않는다(호출측에서 roomId==null일 때만 start).
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';

const String _liveDbUrl =
    'https://camnak-fishing-default-rtdb.asia-southeast1.firebasedatabase.app';

FirebaseDatabase _liveDb() =>
    FirebaseDatabase.instanceFor(app: Firebase.app(), databaseURL: _liveDbUrl);

/// 🎣 방송측(낚시하는 사람) — 한 클라이언트당 낚시 세션은 하나이므로 static 상태로 관리.
class FishingLive {
  static String? _uid; // 현재 방송 중인 내 uid(null이면 방송 안 함)
  static DatabaseReference? _ref; // fishing_live/{uid}
  static StreamSubscription<DatabaseEvent>? _watchSub; // watchers 구독
  static bool _hasWatchers = false; // 관전자 1명 이상?
  static int _watcherCount = 0;
  static final ValueNotifier<int> watcherCountNotifier = ValueNotifier<int>(0);
  static List<String> _watcherNames = []; // 현재 관전자 닉 목록
  static final ValueNotifier<List<String>> watcherNamesNotifier =
      ValueNotifier<List<String>>(const []);
  static void Function(String nick)? onWatcherJoined; // 새 관전자 입장 콜백(토스트용)
  static DateTime _lastFightPush = DateTime.fromMillisecondsSinceEpoch(0);

  /// 낚시터 진입 시 1회 호출(아레나 제외). meta 기록 + 관전자 감시 시작.
  static void start(
    String uid, {
    required String spot,
    required bool sea,
    required String bg,
    required String rank,
    required String nick,
    int pty = 0, // 🌧️ 현재 날씨(강수형태) — 관전 화면 미러용
    String rodSuffix = '', // 🎣 파이팅 낚싯대 그림 접미사(관전 전투 화면 일치용)
    String lureKey = '', // 🎣 루어대 키
    int rods = 1, // 🎣 대편성 갯수(민물 좌대 미러용)
    String floatIcon = '', // 🎣 장착 찌 이미지 경로(관전 화면에서 같은 찌를 그림)
    int chemi = 0, // 🎣 케미 색(Color.value) — 0이면 기본 초록
    bool lure = false, // 🎣 루어모드 여부
  }) {
    // 이전 세션 잔재 정리 후 새로 시작
    if (_uid != null && _uid != uid) stop();
    _uid = uid;
    _ref = _liveDb().ref('fishing_live/$uid');
    // 접속 끊기면 통째로 삭제(고스트 방송 방지)
    _ref!.onDisconnect().remove().catchError(
        (Object e) => debugPrint('🎣👀 live onDisconnect ERR: $e'));
    _ref!.child('meta').set({
      'spot': spot,
      'sea': sea,
      'bg': bg,
      'rank': rank,
      'nick': nick,
      'pty': pty,
      'rodSuffix': rodSuffix,
      'lureKey': lureKey,
      'rods': rods,
      'floatIcon': floatIcon,
      'chemi': chemi,
      'lure': lure,
      'active': true,
      't': ServerValue.timestamp,
    }).catchError((Object e) => debugPrint('🎣👀 meta set ERR: $e'));

    // 👀 관전자 감시 → state 방송 게이팅 + 관전자 닉 목록/입장 감지
    _watcherNames = [];
    watcherNamesNotifier.value = const [];
    _watchSub?.cancel();
    _watchSub = _ref!.child('watchers').onValue.listen((e) {
      final v = e.snapshot.value;
      final List<String> names = [];
      if (v is Map) {
        v.forEach((k, val) {
          if (val is Map && val['nick'] != null) {
            names.add(val['nick'].toString());
          } else {
            names.add('조사'); // 닉 없는 옛 형식 방어
          }
        });
      }
      // 새로 들어온 관전자 → 토스트 콜백
      for (final n in names) {
        if (!_watcherNames.contains(n)) onWatcherJoined?.call(n);
      }
      _watcherNames = names;
      _watcherCount = names.length;
      _hasWatchers = _watcherCount > 0;
      watcherCountNotifier.value = _watcherCount;
      watcherNamesNotifier.value = names;
    }, onError: (Object e) => debugPrint('🎣👀 watchers sub ERR: $e'));
  }

  /// 🎣 장비/편성 갱신 — 대편성 수·찌·케미는 낚시 도중에도 바뀌므로 캐스팅마다 meta를 맞춰준다.
  ///   (관전 화면이 낚시꾼과 똑같은 좌대·찌 그림을 그리기 위한 값)
  static void updateGear({
    required int rods,
    required String floatIcon,
    required int chemi,
    required bool lure,
  }) {
    if (_uid == null) return;
    _ref?.child('meta').update({
      'rods': rods,
      'floatIcon': floatIcon,
      'chemi': chemi,
      'lure': lure,
    }).catchError((_) {});
  }

  /// 현재 날씨(pty) 갱신 — 낚시 중 날씨가 바뀌면 meta 패치(관전 화면 반영).
  static void updateWeather(int pty) {
    if (_uid == null) return;
    _ref?.child('meta').update({'pty': pty}).catchError((_) {});
  }

  /// 낚시 단계 전환 방송(캐스팅/대기/입질/파이팅/랜딩 등). 관전자 있을 때만 기록.
  static void setPhase(String phase, {Map<String, dynamic>? extra}) {
    if (_uid == null || !_hasWatchers) return;
    final data = <String, dynamic>{
      'phase': phase,
      't': ServerValue.timestamp,
    };
    if (extra != null) data.addAll(extra);
    _ref?.child('state').update(data).catchError(
        (Object e) => debugPrint('🎣👀 setPhase ERR: $e'));
  }

  /// 전투(밀당) 프레임 방송. 기존 전투 틱에서 호출 → 여기서 스로틀+게이팅.
  static void pushFight(
      double bar, int stage, String mode, int timeLeft, bool pulling) {
    if (_uid == null || !_hasWatchers) return;
    final now = DateTime.now();
    if (now.difference(_lastFightPush).inMilliseconds < 100) return; // ~10fps 스로틀
    _lastFightPush = now;
    _ref?.child('state').update({
      'phase': 'fighting',
      'bar': bar,
      'stage': stage,
      'mode': mode,
      'timeLeft': timeLeft,
      'pulling': pulling,
      't': ServerValue.timestamp,
    }).catchError((Object e) => debugPrint('🎣👀 pushFight ERR: $e'));
  }

  /// 물고기 잡음(HIT). 관전 화면에 랜딩 카드 표시용.
  static void landed(Map<String, dynamic> fish) {
    if (_uid == null || !_hasWatchers) return;
    _ref?.child('state').update({
      'phase': 'landed',
      'fish': fish,
      't': ServerValue.timestamp,
    }).catchError((Object e) => debugPrint('🎣👀 landed ERR: $e'));
  }

  /// 낚시터 이탈/화면 종료 시 방송 정리.
  static void stop() {
    final ref = _ref;
    _watchSub?.cancel();
    _watchSub = null;
    _hasWatchers = false;
    _watcherCount = 0;
    watcherCountNotifier.value = 0;
    _watcherNames = [];
    watcherNamesNotifier.value = const [];
    onWatcherJoined = null;
    _uid = null;
    _ref = null;
    if (ref != null) {
      ref.onDisconnect().cancel().catchError((_) {});
      ref.remove().catchError((Object e) => debugPrint('🎣👀 stop remove ERR: $e'));
    }
  }
}

/// 👀 관전측(구경하는 사람) — 친구의 fishing_live/{uid}를 구독하고 watchers에 나를 등록.
class SpectateSession {
  final String fisherUid;
  final String myUid;
  final String myNick; // 관전자 닉(방송자 화면에 "누가 보는지" 표시용)
  DatabaseReference? _root; // fishing_live/{fisherUid}
  DatabaseReference? _myWatcherRef; // .../watchers/{myUid}
  StreamSubscription<DatabaseEvent>? _sub;

  SpectateSession(this.fisherUid, this.myUid, {this.myNick = '조사'});

  /// meta+state 전체를 하나의 스냅샷 맵으로 흘려보낸다.
  /// { meta: {...}, state: {...} } 형태(없으면 빈 맵).
  Stream<Map<String, dynamic>> stream() {
    _root = _liveDb().ref('fishing_live/$fisherUid');
    // 나를 관전자로 등록(끊기면 자동 제거)
    _myWatcherRef = _root!.child('watchers/$myUid');
    _myWatcherRef!.onDisconnect().remove().catchError((_) {});
    _myWatcherRef!
        .set({'nick': myNick, 't': ServerValue.timestamp})
        .catchError((Object e) => debugPrint('🎣👀 watcher reg ERR: $e'));

    final controller = StreamController<Map<String, dynamic>>();
    _sub = _root!.onValue.listen((e) {
      final v = e.snapshot.value;
      if (v is Map) {
        controller.add(Map<String, dynamic>.from(
            v.map((k, val) => MapEntry(k.toString(), val))));
      } else {
        controller.add(<String, dynamic>{});
      }
    }, onError: (Object e) => debugPrint('🎣👀 spectate sub ERR: $e'));
    controller.onCancel = () => _sub?.cancel();
    return controller.stream;
  }

  /// 관전 종료 — 내 watcher 등록 해제.
  void dispose() {
    _sub?.cancel();
    _myWatcherRef?.onDisconnect().cancel().catchError((_) {});
    _myWatcherRef?.remove().catchError((_) {});
  }
}
