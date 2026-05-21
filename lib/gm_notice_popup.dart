import 'package:flutter/material.dart';
import 'dart:async'; // ⏱️ 타이머 부품 수입!

class GMNoticePopup extends StatefulWidget {
  final VoidCallback onClose;
  final String message; // 👈 추가!
  const GMNoticePopup({super.key, required this.onClose, required this.message});

  @override
  State<GMNoticePopup> createState() => _GMNoticePopupState();
}

class _GMNoticePopupState extends State<GMNoticePopup> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _slideAnimation; // 캐릭터 쓱~
  late Animation<double> _scaleAnimation; // 말풍선 짠~
       Timer? _autoCloseTimer; // ⏱️ [신규] 5초 타이머 변수 추가!
 
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));

    // 🏃‍♀️ 1. 가람 캐릭터 "쓱~" 등장 (왼쪽에서)
    _slideAnimation = Tween<Offset>(begin: const Offset(-1.5, 0), end: Offset.zero).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.0, 0.7, curve: Curves.easeOutCubic)),
    );

    // 💬 2. 말풍선 "짠~" 등장
    _scaleAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.6, 1.0, curve: Curves.elasticOut)),
    );

    _controller.forward();

    // ⏱️ [신규] 팝업이 뜨고 5초(5000밀리초) 뒤에 강제 퇴근(onClose) 시킵니다!
    _autoCloseTimer = Timer(const Duration(seconds: 30), () {
      widget.onClose(); 
    });
  }

  @override
  void dispose() {
    _autoCloseTimer?.cancel(); // 🧹 [신규] 만약 유저가 30초 전에 '닫기'를 직접 눌렀다면 타이머를 취소!
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 🚨 핵심 포인트: top 대신 bottom을 써서 채팅창 바로 위에 고정시킵니다!
    return Positioned(
      left: -90, // 채팅창 왼쪽 라인과 일치시킴
      top: 180, // 📏 [사장님 미션] 채팅창 탭(전체/귓속말) 높이에 딱 맞게 이 숫자를 조절하세요! (크면 위로, 작으면 아래로)
      child: SizedBox(
        width: 750, // 📏 [사장님 미션] 채팅창 가로 길이에 맞춰서 이 숫자를 조절하시면 말풍선이 우측 끝으로 이동합니다!
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end, // 캐릭터와 말풍선을 바닥 기준으로 줄맞춤!
         // mainAxisAlignment: MainAxisAlignment.spaceBetween, // 캐릭터는 왼쪽, 말풍선은 오른쪽 끝으로 쫙 벌림!
          children: [
            // 👩‍💼 [캐릭터 구역: 큼직하게 쓱~]
            SlideTransition(
              position: _slideAnimation,
              child: Container(
                height: 320, // 📏 캐릭터 키를 더 시원하게! 
                width: 430,  
                decoration: const BoxDecoration(
                  image: DecorationImage(
                    image: AssetImage('assets/images/gm_garam.png'), // 🚨 확장자 jpg 확인!
                    fit: BoxFit.contain, // 잘리지 않게 원본 비율 유지
                    alignment: Alignment.bottomCenter, // 사진이 아래쪽(채팅창 탭)에 딱 붙게 정렬
                  ),
                  // 그림자나 테두리는 캐릭터 원본 이미지를 살리기 위해 뺐습니다!
                ),
              ),
            ),


        
            
            // 💬 [말풍선 구역: 오른쪽 끝에 짠~]
        Transform.translate(                  // 👈 🚨 1. 여기에 이동 마법진 추가!
          offset: const Offset(-120, 0),       // 👈 🚨 2. 왼쪽으로 40만큼 당기기! (숫자 조절 가능)
          child: ScaleTransition(             // (이 원래 있던 코드가 child 안으로 쏙 들어갑니다)
            scale: _scaleAnimation,
            child: Container(
              width: 290,
              margin: const EdgeInsets.only(bottom: 150), // 말풍선이 캐릭터 바닥보다는 살짝 위로
              padding: const EdgeInsets.all(12),
              // ... (이 아래 margin, padding, decoration 등 기존 코드는 그대로 두시면 됩니다!) ...
                decoration: BoxDecoration(
                  color: const Color(0xFFFFDF00), 
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.black87, width: 2),
                  boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 6, offset: Offset(2, 4))],
                ),
                child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('GM 가람', style: TextStyle(fontWeight: FontWeight.w900, color: Colors.black, fontSize: 16)),
                const SizedBox(height: 4),
                // 🚨 닫기 버튼은 지우고 멘트만 남깁니다!
               Text(widget.message, style: const TextStyle(color: Colors.black87, fontSize: 20, height: 1.5)),
              ],
            ), // Column
              ),
            ),
           ),
         ],
        ),
      ),
    );
  }
}