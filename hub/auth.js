// 🔐 캠피싱 홈페이지 공용 로그인 (게임과 동일 방식)
//   camnak.com → camfishing.web.app/?uid=이메일 로 들어오면 자동 로그인.
//   한 번 로그인하면 브라우저에 유지되므로 다음부터는 uid 없이 들어와도 로그인 상태.
import { initializeApp } from "https://www.gstatic.com/firebasejs/10.12.0/firebase-app.js";
import { getAuth, signInWithEmailAndPassword, signOut, onAuthStateChanged,
         setPersistence, browserLocalPersistence }
  from "https://www.gstatic.com/firebasejs/10.12.0/firebase-auth.js";

const ME_API = 'https://us-central1-camnak-fishing.cloudfunctions.net/meApi';
// 🔑 로그인: 아임웹의 "홈페이지 이동" 페이지로 보냄.
//    그 페이지는 회원전용이라 → 미로그인 시 아임웹 로그인(네이버/카카오/구글/이메일) → 로그인 후 자동 복귀
//    → 그 페이지의 스크립트가 window.MEMBER_UID(이메일)를 붙여 홈페이지로 되돌려보냄 → 자동 로그인 완료
//    ⚠️ 아임웹에 그 페이지를 만든 뒤 아래 주소(페이지 번호)를 실제 값으로 바꿔주세요.
const LOGIN_URL = 'https://camnak.com/?gohub=1';  // 아임웹 로그인 → 공통스크립트가 로그인 후 홈페이지로 자동 복귀(uid 동반)
const SHARED_PW = 'KreftMasterPassword123!';    // 게임과 동일한 공용 비밀번호

const app = initializeApp({
  apiKey: "AIzaSyD5yu1DAIAiMXmZWB03ddZsZYgNmECRtwc",
  authDomain: "camnak-fishing.firebaseapp.com",
  projectId: "camnak-fishing",
  storageBucket: "camnak-fishing.firebasestorage.app",
  messagingSenderId: "755892653855",
  appId: "1:755892653855:web:3d959549607ea08be5aa2a"
});
const auth = getAuth(app);
window.__auth = auth;

// URL의 ?uid=이메일 로 자동 로그인 (게임과 같은 진입 방식)
async function autoLoginFromUrl() {
  const p = new URLSearchParams(location.search);
  const email = (p.get('uid') || p.get('email') || '').trim();
  if (!email || !email.includes('@')) return;
  try {
    await setPersistence(auth, browserLocalPersistence);
    if (!auth.currentUser || auth.currentUser.email !== email) {
      await signInWithEmailAndPassword(auth, email, SHARED_PW);
    }
  } catch (e) {
    console.warn('자동 로그인 실패:', e.code || e);
  } finally {
    // 주소창에서 uid 제거(이메일 노출 방지)
    p.delete('uid'); p.delete('email');
    const q = p.toString();
    history.replaceState(null, '', location.pathname + (q ? '?' + q : '') + location.hash);
  }
}

function renderLoggedOut() {
  document.querySelectorAll('[data-auth-in]').forEach(el => el.style.display = 'none');
  document.querySelectorAll('[data-auth-out]').forEach(el => el.style.display = '');
  document.querySelectorAll('[data-gm-only]').forEach(el => el.style.display = 'none');
}
function renderLoggedIn(me) {
  document.querySelectorAll('[data-auth-out]').forEach(el => el.style.display = 'none');
  document.querySelectorAll('[data-auth-in]').forEach(el => el.style.display = '');
  document.querySelectorAll('[data-me-nick]').forEach(el => {
    el.textContent = me.nickname ? `${me.rank} ${me.nickname} 조사님` : (me.email || '조사님');
  });
  document.querySelectorAll('[data-gm-only]').forEach(el => {
    el.style.display = me.isGm ? '' : 'none';
  });
  window.__me = me;
  document.dispatchEvent(new CustomEvent('camfishing:login', { detail: me }));
}

onAuthStateChanged(auth, async (u) => {
  if (!u) { renderLoggedOut(); return; }
  try {
    const t = await u.getIdToken();
    const r = await fetch(ME_API, { headers: { Authorization: 'Bearer ' + t } });
    const j = await r.json();
    if (j.ok) renderLoggedIn(j); else renderLoggedOut();
  } catch (e) { renderLoggedOut(); }
});

// 로그인/로그아웃 버튼 연결
document.addEventListener('click', (e) => {
  const out = e.target.closest('[data-do-logout]');
  if (out) {
    e.preventDefault();
    signOut(auth);
    // 🔓 캠피싱(아임웹) 세션도 함께 로그아웃 — 백그라운드 탭에서 처리 후 자동 닫기
    try {
      const w = window.open('https://camnak.com/logout', 'camnakLogout', 'width=480,height=360');
      if (w) setTimeout(() => { try { w.close(); } catch (e) {} }, 2500);
    } catch (e) {}
    return;
  }
  const inn = e.target.closest('[data-do-login]');
  if (inn) { e.preventDefault(); location.href = LOGIN_URL; }
});

autoLoginFromUrl();
