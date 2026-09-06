// 📍 지금 핫스팟이 어디인지 확인하는 도구 (운영용)
//
//    실행:  dart run tools/hotspot.dart
//
//    게임과 똑같은 계산식을 쓴다. 유저가 "오늘 여기 잘 나오던데요?" 하고
//    물어올 때 맞는 말인지 확인하는 용도. 유저에게는 알려주지 않는다.
import 'dart:math' as math;

const List<String> kHotSpotPool = [
  '예산 예당지', '안성 고삼지', '충주 충주호', '춘천 파로호', '진천 백곡지',
  '예산 신양수로', '청양 지천', '인천 청라수로', '해남 금자천', '충주 달천',
  '통영 척포 갯바위', '신안 가거도', '완도 청산도', '여수 거문도', '제주 섶섬',
  '거제 선상', '오천항 선상', '완도 선상', '통영 선상', '대천 선상',
];

String spotAt(DateTime kst) {
  final int seed = ((kst.year * 100 + kst.month) * 100 + kst.day) * 100 + kst.hour;
  return kHotSpotPool[math.Random(seed).nextInt(kHotSpotPool.length)];
}

String two(int n) => n.toString().padLeft(2, '0');

void main() {
  final now = DateTime.now().toUtc().add(const Duration(hours: 9));
  print('지금 (KST ${now.year}-${two(now.month)}-${two(now.day)} ${two(now.hour)}시)');
  final cur = spotAt(now);
  print('  ▶ ${kHotSpotPool.indexOf(cur) >= 10 ? "바다" : "민물"}  $cur');
  print('');
  print('앞으로 12시간');
  for (int i = 1; i <= 12; i++) {
    final t = DateTime(now.year, now.month, now.day, now.hour).add(Duration(hours: i));
    final s = spotAt(t);
    print('  ${two(t.month)}/${two(t.day)} ${two(t.hour)}시  '
        '${kHotSpotPool.indexOf(s) >= 10 ? "바다" : "민물"}  $s');
  }
}
