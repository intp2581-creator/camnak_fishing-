import 'package:flutter/material.dart';

// 👧 원할 때만 꺼내 쓰는 똑똑한 윤슬 가이드 부품! (수정 완료!)
class NpcTutorialOverlay extends StatelessWidget {
  final String text;       // 띄울 대사
  final String imagePath;  // 띄울 이미지
  final VoidCallback onTap; // 터치했을 때 할 행동

  const NpcTutorialOverlay({
    super.key,
    required this.text,
    required this.imagePath,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        color: Colors.black.withValues(alpha: 0.75), // 배경 블러
        child: Stack(
          children: [
            Center(
              child: SizedBox(
                width: 900,  
                height: 600, 
                child: Stack(
                  children: [
                    // 👧 1. 아리따운 캐릭터 이미지 (얼굴 안 가리게 맨 오른쪽으로!)
                    Positioned(
                      bottom: -10,
                      right: -70, 
                      child: Image.asset(
                        imagePath,
                        height: 600, 
                        fit: BoxFit.contain,
                      ),
                    ),
                    
                    // 🗨️ 2. 시원시원한 대형 말풍선 (왼쪽으로 바짝!)
                    Positioned(
                      top: 80,    
                      left: 50, 
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 400),
                        child: Container(
                          width: 440, 
                          padding: const EdgeInsets.all(20), 
                          decoration: BoxDecoration(
                            color: const Color(0xFFD4AF37), // KREFT 골드
                            borderRadius: BorderRadius.circular(15), 
                            boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 10, offset: Offset(2, 2))],
                          ),
                          child: SingleChildScrollView(
                            child: Text(
                              text,
                              style: const TextStyle(
                                fontSize: 28, // 📈 시원한 폰트 크기 유지!
                                color: Colors.black, 
                                fontWeight: FontWeight.bold, 
                                height: 1.5, 
                                decoration: TextDecoration.none, 
                              ),
                              textAlign: TextAlign.left, 
                            ),
                          ),
                        ),
                      ),
                    ),
                  ], 
                ), 
              ), 
            ),
            
            // 💡 3. 터치 유도 안내 (하단 고정)
            const Positioned(
              bottom: 30,
              left: 0, right: 0,
              child: Center(
                child: Text(
                  "화면을 터치해서 계속 진행 ▶", 
                  style: TextStyle(
                    color: Colors.white54, 
                    fontSize: 18, 
                    fontWeight: FontWeight.bold,
                    decoration: TextDecoration.none, 
                  )
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}