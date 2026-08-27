// 🔐 캠피싱 홈페이지 공용 로그인 (게임과 동일 방식)
//   camnak.com → camfishing.web.app/?uid=이메일 로 들어오면 자동 로그인.
//   한 번 로그인하면 브라우저에 유지되므로 다음부터는 uid 없이 들어와도 로그인 상태.
import { initializeApp } from "https://www.gstatic.com/firebasejs/10.12.0/firebase-app.js";
import { getAuth, signInWithEmailAndPassword, signOut, onAuthStateChanged,
         setPersistence, browserLocalPersistence }
  from "https://www.gstatic.com/firebasejs/10.12.0/firebase-auth.js";

const ME_API = 'https://us-central1-camnak-fishing.cloudfunctions.net/meApi';
const LOGIN_URL = 'https://camnak.com/login';   // 로그인하러 가는 곳(아임웹)
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
  if (out) { e.preventDefault(); signOut(auth); return; }
  const inn = e.target.closest('[data-do-login]');
  if (inn) { e.preventDefault(); location.href = LOGIN_URL; }
});

autoLoginFromUrl();
