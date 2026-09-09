// ⚔️🎟️ 아레나 입장 슬롯 판정 — 무료 칸과 입장권 칸은 서로 다른 칸이다.
import 'package:flutter_test/flutter_test.dart';
import 'package:camnak_fishing/game_config.dart';

const T = '2026-09-09';   // 오늘
const Y = '2026-09-08';   // 어제

Map<String, dynamic> u({
  String freeDate = '', String ticketDate = '',
  int tickets = 0, String lastArena = '', int count = 0,
}) => {
  if (freeDate.isNotEmpty) 'arenaFreeDate': freeDate,
  'arenaTicketDate': ticketDate,
  'lastArenaDate': lastArena,
  'arenaCount': count,
  'inventory': [
    if (tickets > 0)
      {'name': '아레나 입장권', 'quantity': tickets, 'type': 'ETC'},
  ],
};

void main() {
  group('시간이 넉넉할 때(10분 이상)', () {
    test('무료가 남았으면 무료', () {
      expect(pickArenaSlot(u(tickets: 2), T, 3600), 'free');
    });
    test('무료를 썼으면 입장권', () {
      expect(pickArenaSlot(u(freeDate: T, tickets: 2), T, 3600), 'ticket');
    });
    test('무료도 입장권도 다 썼으면 못 들어간다', () {
      expect(pickArenaSlot(u(freeDate: T, ticketDate: T, tickets: 1), T, 3600), null);
    });
    test('무료 썼는데 입장권이 없으면 못 들어간다', () {
      expect(pickArenaSlot(u(freeDate: T, tickets: 0), T, 3600), null);
    });
  });

  group('시간이 모자랄 때(10분 미만) — 비상님 상황', () {
    test('입장권이 있으면 입장권으로 (무료는 남겨둔다)', () {
      expect(pickArenaSlot(u(tickets: 2), T, 552), 'ticket');
    });
    test('입장권이 없으면 못 들어간다', () {
      expect(pickArenaSlot(u(tickets: 0), T, 552), null);
    });
    test('입장권을 이미 오늘 썼으면 못 들어간다', () {
      expect(pickArenaSlot(u(ticketDate: T, tickets: 1), T, 552), null);
    });
  });

  group('입장권으로 먼저 들어간 뒤 — 사장님이 원한 흐름', () {
    // 9:12 → 입장권 사용 → +20분 → 대회 10분 → 19:12 남음, 무료는 그대로
    final after = u(ticketDate: T, tickets: 1, lastArena: T, count: 1);
    test('무료 1회가 아직 살아 있다', () {
      expect(arenaFreeUsedToday(after, T), false);
      expect(pickArenaSlot(after, T, 1152), 'free');
    });
  });

  group('날짜가 바뀌면 초기화', () {
    test('어제 다 썼어도 오늘은 무료', () {
      expect(pickArenaSlot(u(freeDate: Y, ticketDate: Y, tickets: 1), T, 3600), 'free');
    });
  });

  group('옛 계정 역산(arenaFreeDate 없음)', () {
    test('오늘 1회 참가 + 입장권 사용 → 무료는 안 썼다', () {
      final d = u(ticketDate: T, tickets: 1, lastArena: T, count: 1);
      expect(arenaFreeUsedToday(d, T), false);
    });
    test('오늘 1회 참가 + 입장권 안 씀 → 무료를 썼다', () {
      final d = u(tickets: 1, lastArena: T, count: 1);
      expect(arenaFreeUsedToday(d, T), true);
    });
    test('오늘 2회 참가 → 둘 다 썼다', () {
      final d = u(ticketDate: T, tickets: 0, lastArena: T, count: 2);
      expect(arenaFreeUsedToday(d, T), true);
      expect(pickArenaSlot(d, T, 3600), null);
    });
  });
}
