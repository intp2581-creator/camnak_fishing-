# 🚀 캠피싱 배포 가이드 (오픈 후 운영)

## 0. 작업 시작 전
```
git pull        # 두 컴퓨터 동기화 (집/회사)
```

## 1. 정식 배포 (프로덕션)
```
flutter build web
firebase deploy --only hosting
```
- 즉시·무중단 반영. 유저는 다음 접속 때 새 버전.
- 함수(결제·날씨 등) 수정 시: `firebase deploy --only functions`

### ⭐ 버전 알림 같이 올리기 (유저에게 "새로고침" 안내)
코드 수정 배포할 때, 아래 두 값을 **같은 새 값**으로 올린 뒤 배포:
1. `lib/app_version.dart` 의 `kBuildId`  (예: `20260701-1` → `20260701-2`)
2. `web/appver.json` 의 `"build"`        (똑같이 `20260701-2`)

→ 접속 중이던(캐시된) 유저에게 자동으로 "새 버전 나왔어요, 새로고침" 팝업이 뜸.
   (안 올리면 팝업은 안 뜨고, 유저는 재접속 때 조용히 최신 버전 받음)

## 2. 미리보기(테스트) 배포 — 실서비스 안 건드리고 확인
```
flutter build web
firebase hosting:channel:deploy test
```
- 임시 URL 나옴 (예: https://camnak-fishing--test-xxxx.web.app) → 여기서 먼저 확인
- 괜찮으면 위 "1. 정식 배포" 실행
- 미리보기 채널은 자동 만료(기본 7일). 유지 기간 지정: `--expires 30d`

## 3. 롤백 (문제 생기면 즉시 복구)
- Firebase 콘솔 → Hosting → 릴리스 목록 → 이전 버전 **⋮ → 롤백**
- 또는 콘솔에서 이전 버전으로 되돌리기 한 번.

## 4. 작업 끝나면
```
git add -A
git commit -m "작업 내용"
git push        # 두 컴퓨터 동기화
```

## 5. 유저 공지
- GM 공지 팝업(`lib/gm_notice_popup.dart`)으로 패치노트·점검 안내.

---

## 🔒 오픈 직전 체크리스트
- [ ] 레전드/낚시의 신 스킨 상점 미노출 재확인
- [ ] `functions/.env` 의 `IMWEB_WEBHOOK_SECRET` 설정 (결제 보안)
- [ ] 테스트 계정/데이터 정리
- [ ] 카카오맵 심사 승인 확인 (날씨 지역명)
- [ ] `kBuildId` / `web/appver.json` 초기값 일치 확인
