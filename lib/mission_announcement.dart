// 📢 미션 1등 달성 전체 공지 (로비 / 낚시 화면 공용)
// 한 곳만 고치면 양쪽에 똑같이 반영되도록 공용 함수로 분리!
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'fishing_logic.dart'; // 🔊 audioManager 사용

// 🏆 1등 독식 룰 — 미션 달성자 닉네임을 받아 전 유저에게 속보 팝업 + 아라 음성 안내
void showGlobalWinnerAnnouncement(BuildContext context, String name) {
  audioManager.playSfx("sfx_mission_alert.mp3");

  // 🎙️ 아라 매니저가 긴급 속보 읽어주기
  FlutterTts tts = FlutterTts();
  tts.setLanguage("ko-KR");
  tts.setSpeechRate(0.8);
  tts.setPitch(1.2);
  tts.setVolume(1.0);
  tts.speak("핫타임 실시간 속보입니다!\n$name 조사님이 오늘의 미션을 최초로 달성하셨습니다!\n오늘의 미션이 종료되었습니다!\n내일도 기대해 주세요!");

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
                    // 1. 핫타임 속보 헤드라인
                    const Text(
                      '핫타임 실시간 속보입니다! 🚨',
                      style: TextStyle(fontSize: 18, color: Colors.redAccent, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    // 2. 닉네임 + 최초 달성
                    Text(
                      '[$name] 조사님\n오늘의 미션 최초 달성!',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.black87),
                    ),
                    const SizedBox(height: 10),
                    // 3. 미션 종료 안내
                    const Text(
                      '오늘의 미션이 종료되었습니다.',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87),
                    ),
                    const SizedBox(height: 6),
                    // 4. 내일 기대
                    const Text(
                      '내일도 기대해 주세요!',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.black54),
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
