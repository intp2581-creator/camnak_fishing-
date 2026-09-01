// 🔐 캠피싱 홈페이지 공용 로그인 (게임과 동일 방식)
//   camnak.com → game.camnak.com/?uid=이메일 로 들어오면 자동 로그인.
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

// 🔐 진입 시 회원 식별값 수신
//   ⚠️ 예전에는 ?uid=이메일 을 그대로 URL에 실었는데, 이 형태가 피싱 패턴으로 오인되어
//      Google 세이프브라우징에 '사기성 페이지'로 차단됨(2026-08-29).
//      이제는 #k=<base64url(이메일)> 로 받는다. '#' 뒤는 서버로 전송되지 않고 로그에도 안 남는다.
function b64urlDecode(v) {
  try {
    var t = String(v).replace(/-/g, '+').replace(/_/g, '/');
    while (t.length % 4) t += '=';
    return decodeURIComponent(escape(atob(t)));
  } catch (e) { return ''; }
}

function readIncomingEmail() {
  // 1) 신규 방식: #k=<base64url>
  var h = (location.hash || '').replace(/^#/, '');
  var m = h.match(/(?:^|&)k=([^&]+)/);
  if (m) return { email: b64urlDecode(m[1]), from: 'hash' };
  // 2) 구방식 하위호환(기존 북마크·캐시 대응) — 곧 제거
  var p = new URLSearchParams(location.search);
  var e = (p.get('uid') || p.get('email') || '').trim();
  if (e) return { email: e, from: 'query' };
  return { email: '', from: '' };
}

async function autoLoginFromUrl() {
  var got = readIncomingEmail();
  var email = (got.email || '').trim();
  // 흔적은 무조건 지운다(성공/실패 무관) — 주소창·히스토리에 계정이 남지 않도록
  function scrub() {
    var p = new URLSearchParams(location.search);
    p.delete('uid'); p.delete('email');
    var q = p.toString();
    history.replaceState(null, '', location.pathname + (q ? '?' + q : ''));
  }
  if (!email || !email.includes('@')) { if (got.from) scrub(); return; }
  try {
    await setPersistence(auth, browserLocalPersistence);
    if (!auth.currentUser || auth.currentUser.email !== email) {
      await signInWithEmailAndPassword(auth, email, SHARED_PW);
    }
  } catch (e) {
    console.warn('자동 로그인 실패:', e.code || e);
  } finally {
    scrub();
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
    // 🔓 캠피싱(아임웹) 세션도 함께 로그아웃.
    //    ⚠️ ?gohub=1 을 절대 붙이지 않음(붙이면 아임웹 스크립트가 되돌려보내 재로그인됨)
    try {
      const w = window.open('https://camnak.com/logout.cm', 'camnakLogout',
                            'width=420,height=300,left=20,top=20');
      if (w) { setTimeout(() => { try { w.close(); } catch (e) {} }, 2000); }
      else {
        // 팝업이 차단된 경우: 숨은 iframe으로 시도(쿠키 정책상 실패할 수 있음)
        const f = document.createElement('iframe');
        f.style.display = 'none';
        f.src = 'https://camnak.com/logout.cm';
        document.body.appendChild(f);
        setTimeout(() => { try { f.remove(); } catch (e) {} }, 3000);
      }
    } catch (e) {}
    return;
  }
  const inn = e.target.closest('[data-do-login]');
  if (inn) { e.preventDefault(); location.href = LOGIN_URL; }
});

autoLoginFromUrl();

/* ═══════════════════════════════════════════════════════════════════════
   🔔 새 글 N 배지 (2026-08-30)
      공지·커뮤니티에 '내가 아직 안 본 글'이 있으면 메뉴에 빨간 N을 띄운다.
      · 해당 페이지를 열면 읽은 것으로 보고 N이 사라진다(기기별 localStorage).
      · 처음 오신 분은 '최근 하루' 글만 새 글로 취급 — 옛날 글 때문에 N이
        영영 붙어 있는 걸 막는다.
      · 예전엔 index.html에 <span class="n">N</span>이 그냥 박혀 있어서
        새 글이 있든 없든 항상 떠 있었다(=아무 의미 없는 표시).
      💰 함수 호출을 아끼려고 결과를 5분간 캐시한다(페이지 이동마다 호출 X).
   ═══════════════════════════════════════════════════════════════════════ */
(function () {
  var FN = 'https://us-central1-camnak-fishing.cloudfunctions.net/';
  var SRC = [
    { api: FN + 'noticesApi?list=1&limit=10',   key: 'cf_seen_notice',    file: 'notice.html' },
    { api: FN + 'communityApi?list=1&limit=10', key: 'cf_seen_community', file: 'community.html' }
  ];
  var DAY = 86400000;
  var CACHE_MS = 5 * 60 * 1000;

  function num(k) { try { return parseInt(localStorage.getItem(k) || '0', 10) || 0; } catch (e) { return 0; } }
  function put(k, v) { try { localStorage.setItem(k, String(v)); } catch (e) {} }

  var st = document.createElement('style');
  st.textContent =
    '.cf-n{display:inline-block;margin-left:3px;color:#ff3b30;font-size:10px;font-weight:900;' +
    'vertical-align:super;line-height:1;animation:cfNblink 1.5s ease-in-out infinite}' +
    '@keyframes cfNblink{0%,100%{opacity:1}50%{opacity:.3}}';
  document.head.appendChild(st);

  function badge(file, on, text) {
    // 상단 메뉴 + 스크롤 시 내려오는 컴팩트 메뉴(.navmini) 둘 다. 푸터 링크는 제외.
    var links = document.querySelectorAll(
      'nav a[href$="' + file + '"], .navmini a[href$="' + file + '"]');
    for (var i = 0; i < links.length; i++) {
      var cur = links[i].querySelector('.cf-n');
      if (on && !cur) {
        var s = document.createElement('span');
        s.className = 'cf-n';
        s.textContent = text || 'N';
        links[i].appendChild(s);
      } else if (on && cur) {
        cur.textContent = text || 'N';
      } else if (!on && cur) {
        cur.parentNode.removeChild(cur);
      }
    }
  }

  function newestOf(items) {
    var m = 0;
    for (var i = 0; i < (items || []).length; i++) {
      var t = +items[i].createdAt || 0;
      if (t > m) m = t;
    }
    return m;
  }

  // 최신 글 시각을 얻는다 — 5분 이내면 캐시 사용(함수 호출 절감)
  function newest(src) {
    var ck = 'cf_last_' + src.key;
    var c = num(ck + '_t');
    if (c && Date.now() - c < CACHE_MS) return Promise.resolve(num(ck));
    return fetch(src.api)
      .then(function (r) { return r.json(); })
      .then(function (j) {
        if (!j || !j.ok) return 0;
        var v = newestOf(j.items);
        if (v) { put(ck, v); put(ck + '_t', Date.now()); }
        return v;
      })
      .catch(function () { return num(ck); });
  }

  function run() {
    var here = (location.pathname || '').split('/').pop() || 'index.html';
    SRC.forEach(function (src) {
      // 이 페이지를 보고 있다 = 읽음 처리
      if (here === src.file) {
        put(src.key, Date.now());
        badge(src.file, false);
        return;
      }
      newest(src).then(function (v) {
        if (!v) return;
        var seen = num(src.key) || (Date.now() - DAY); // 첫 방문자는 최근 하루치만
        badge(src.file, v > seen);
      });
    });
  }

  /* 🎧 고객지원 미확인 건수
       운영자 = 답변 대기중인 문의 수 / 회원 = 답변이 달린 내 문의 수.
       로그인해야 알 수 있는 값이라 인증이 끝난 뒤 한 번만 조회한다.
       (공지·커뮤니티 배지와 달리 '읽음 시각'이 아니라 서버가 센 실제 건수) */
  function supportBadge() {
    var here = (location.pathname || '').split('/').pop() || 'index.html';
    var auth = window.__auth;
    if (!auth || !auth.currentUser) return;
    auth.currentUser.getIdToken().then(function (t) {
      return fetch(FN + 'supportApi?count=1', {headers: {Authorization: 'Bearer ' + t}});
    }).then(function (r) { return r.json(); }).then(function (j) {
      if (!j || !j.ok) return;
      // 고객지원 페이지를 보고 있어도, 남은 건수는 그대로 알려주는 편이 낫다
      // (여기서 처리하는 중이므로 숫자가 줄어드는 걸 보는 게 자연스럽다)
      badge('support.html', j.count > 0, j.count > 99 ? '99+' : String(j.count));
      if (here === 'support.html' && j.count === 0) badge('support.html', false);
    }).catch(function () {});
  }

  var _sbTried = 0;
  function waitAuth() {
    if (window.__auth && window.__auth.currentUser) { supportBadge(); return; }
    if (++_sbTried > 20) return;            // 최대 10초 대기 후 포기(비로그인)
    setTimeout(waitAuth, 500);
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', function () { run(); waitAuth(); });
  } else { run(); waitAuth(); }
})();
