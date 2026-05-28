// 📢 미션 1등 달성 전체 공지 (로비 / 낚시 화면 공용)
// 한 곳만 고치면 양쪽에 똑같이 반영되도록 공용 함수로 분리!
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'fishing_logic.dart'; // 🔊 audioManager 사용

// 🏆 1등 독식 룰 — 미션 달성자 닉네임을 받아 전 유저에게 속보 팝업 + 아라 음성 안내
void showGlobalWinnerAnnouncement(BuildContext context, String name) {
  audioManager.playSfx("sfx_mission_alert.mp3");

  const String prizeText = "상금 2,000P 지급 완료! 💰";

  // 🎙️ 아라 매니저가 긴급 속보 읽어주기
  FlutterTts tts = FlutterTts();
  tts.setLanguage("ko-KR");
  tts.setSpeechRate(0.8);
  tts.setPitch(1.2);
  tts.setVolume(1.0);
  tts.speak("이벤트 알림!! $name 조사님이 미션을 달성하셨습니다!\n상금 이천 포인트를 받으셨습니다!\n축하합니다!\n오늘의 이벤트가 종료되었습니다!");

  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext context) {
      return Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: GestureDetector(
          onTap: () {
            Navigator.of(context).pop();
          },
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              // 1. 고급스러운 종이 질감 말풍선 배경
              Container(
                padding: const EdgeInsets.fromLTRB(20, 70, 20, 20),
                margin: const EdgeInsets.only(top: 30),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF6D8),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFD4AF37), width: 3),
                  boxShadow: const [
                    BoxShadow(color: Colors.black54, blurRadius: 10, offset: Offset(0, 5))
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '[$name] 조사님\n오늘의 1등 달성!!',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.black87),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      prizeText,
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.blueAccent),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      '핫타임 실시간 속보입니다! 🚨',
                      style: TextStyle(fontSize: 16, color: Colors.redAccent, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      '[ 화면을 터치해서 닫기 👆 ]',
                      style: TextStyle(fontSize: 14, color: Colors.grey[700], fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
              // 2. 축하용 아라 캐릭터
              Positioned(
                top: -60,
                left: -10,
                child: Image.asset(
                  'assets/images/npc_manager_congrats.png',
                  width: 160,
                  height: 160,
                  fit: BoxFit.contain,
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
