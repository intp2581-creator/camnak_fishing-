// 🏪 [길드 상점] 길드 전용 아이템 상점 — 뼈대(준비중).
//   판매 아이템/화폐(길드 기여도? 포인트?)는 운영자가 확정 후 채운다.
//   지금은 관리인 텔레포터에서 진입되는 진입점 + 안내 화면만.
import 'package:flutter/material.dart';

const Color _kGold = Color(0xFFD4AF37);

class GuildShopScreen extends StatelessWidget {
  final String guildName;
  const GuildShopScreen({super.key, required this.guildName});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF14110C),
      body: SafeArea(
        child: Stack(children: [
          // 나가기
          Positioned(top: 8, left: 8, child: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white70),
            onPressed: () => Navigator.pop(context),
          )),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Text('🏪', style: TextStyle(fontSize: 64)),
                const SizedBox(height: 12),
                const Text('길드 상점', style: TextStyle(color: _kGold, fontSize: 28, fontWeight: FontWeight.w900)),
                const SizedBox(height: 6),
                Text('[$guildName] 전용', style: const TextStyle(color: Colors.white54, fontSize: 14)),
                const SizedBox(height: 24),
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 24),
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.4),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: _kGold.withOpacity(0.4)),
                  ),
                  child: const Column(children: [
                    Text('곧 열려요! 🔧',
                        style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900)),
                    SizedBox(height: 12),
                    Text(
                      '길드 기여로 얻는 포인트로\n길드 전용 아이템을 살 수 있는 상점이에요.\n\n판매 품목을 준비 중이에요.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white70, fontSize: 14, height: 1.6),
                    ),
                  ]),
                ),
                const SizedBox(height: 28),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: _kGold, foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 14)),
                  onPressed: () => Navigator.pop(context),
                  child: const Text('돌아가기', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                ),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}
