# 캠피싱 낚시 게임 프로젝트

## 기본 정보
- Flutter 웹앱 (1280x720 고정 16:9 비율)
- Firebase (Auth + Firestore + Hosting) 연동
- 배포: Firebase Hosting
- 연동 사이트: camnak.com (아임웹 쇼핑몰)

## 로그인 구조
- camnak.com에서 로그인 후 `?uid=이메일` 파라미터로 게임 진입
- Firebase에 자동 로그인 처리 (AutoLoginScreen)
- 비회원 → GuestWarningScreen (camnak.com/login으로 이동 유도)
- 신규 회원 → 닉네임 설정(NicknameSetupScreen) → 로비
- 기존 회원 → 터치 화면 → 로비

## 주요 파일
- `lib/main.dart` - 앱 진입점, Firebase 초기화
- `lib/ui_login.dart` - 로그인/자동로그인/게스트 차단
- `lib/ui_lobby.dart` - 로비 화면
- `lib/ui_fishing.dart` - 낚시 메인 게임 화면
- `lib/fishing_logic.dart` - 게임 로직
- `lib/game_config.dart` - 게임 설정값
- `lib/ui_arena.dart` - 아레나 대전
- `lib/ui_tutorial_npc.dart` - 튜토리얼 NPC(윤슬)
- `lib/gm_notice_popup.dart` - GM 공지 팝업

## 작업 방식
- 코드 수정 후 VS Code 터미널에서 `r` 키로 hot reload
- 확인 완료 후 `flutter build web` → `firebase deploy --only hosting`
