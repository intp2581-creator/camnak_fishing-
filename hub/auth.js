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
    // 📱 모바일은 폭이 좁아 '등급 닉 조사님'이 통째로 밀려난다.
    //    긴 형태는 그대로 두고, 짧은 형태를 data-short에 같이 심어
    //    좁은 화면에서는 CSS가 짧은 쪽을 보여주게 한다.
    const full  = me.nickname ? `${me.rank} ${me.nickname} 조사님` : (me.email || '조사님');
    const short = me.nickname ? me.nickname : (me.email || '조사님');
    el.textContent = full;
    el.setAttribute('data-short', short);
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
    // ⚠️ .cf-tabbar(하단 탭바)도 <nav>라 여기 걸리면 배지가 두 번 붙는다 → 제외
    var links = document.querySelectorAll(
      'nav:not(.cf-tabbar) a[href$="' + file + '"], .navmini a[href$="' + file + '"]');
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

/* ═══════════════════════════════════════════════════════════════════════
   📱 모바일 하단 탭바 (2026-09-02)
      홈 화면이 모바일에서 4,600px가 넘는다. 다른 곳으로 가려면 맨 위까지
      올라가 햄버거를 열어야 했다. 자주 가는 곳은 어디서든 한 번에 닿게 한다.
      · 768px 이하에서만 표시 (PC는 기존 상단 메뉴 그대로)
      · 페이지마다 넣지 않고 여기서 한 번에 — 두 곳을 고치다 한쪽을 빠뜨리는
        일이 실제로 있었다(고객지원이 모바일 메뉴에서 누락됐던 건)
      · 배지는 위의 N 배지 로직을 그대로 쓴다
   ═══════════════════════════════════════════════════════════════════════ */
(function () {
  var TABS = [
    { f: 'index.html',     i: '🏠', t: '홈' },
    { f: 'notice.html',    i: '📢', t: '공지' },
    { f: 'community.html', i: '💬', t: '커뮤니티' },
    { f: 'support.html',   i: '🎧', t: '고객지원' },
    { f: 'play.html',      i: '🎮', t: '플레이', play: true }
  ];

  var css = document.createElement('style');
  css.textContent =
    '.cf-tabbar{display:none}' +
    '@media(max-width:768px){' +
    '  body{padding-bottom:calc(62px + env(safe-area-inset-bottom,0px))}' +
    '  .cf-tabbar{display:flex;position:fixed;left:0;right:0;bottom:0;z-index:9000;' +
    '    background:rgba(255,255,255,.97);backdrop-filter:blur(10px);' +
    '    border-top:1px solid #dfe8ed;box-shadow:0 -2px 14px rgba(10,40,55,.08);' +
    '    padding-bottom:env(safe-area-inset-bottom,0px)}' +
    '  .cf-tabbar a{flex:1;display:flex;flex-direction:column;align-items:center;justify-content:center;' +
    '    gap:3px;height:62px;text-decoration:none;color:#7a8b95;font-size:11px;font-weight:700;' +
    '    position:relative;font-family:inherit}' +
    '  .cf-tabbar a i{font-style:normal;font-size:21px;line-height:1}' +
    '  .cf-tabbar a.on{color:#0f766e}' +
    '  .cf-tabbar a.play{color:#b8860b}' +
    '  .cf-tabbar a.on::before{content:"";position:absolute;top:0;left:24%;right:24%;height:3px;' +
    '    border-radius:0 0 3px 3px;background:#0f766e}' +
    '  .cf-tabbar .bg{position:absolute;top:7px;left:50%;margin-left:4px;min-width:16px;height:16px;' +
    '    padding:0 4px;border-radius:9px;background:#ff3b30;color:#fff;font-size:10px;font-weight:800;' +
    '    display:flex;align-items:center;justify-content:center;box-sizing:border-box}' +
    '}';
  document.head.appendChild(css);

  function build() {
    if (document.querySelector('.cf-tabbar')) return;
    var here = (location.pathname || '').split('/').pop() || 'index.html';
    var bar = document.createElement('nav');
    bar.className = 'cf-tabbar';
    bar.setAttribute('aria-label', '주요 메뉴');
    TABS.forEach(function (t) {
      var a = document.createElement('a');
      a.href = t.f;
      if (t.play) a.className = 'play';
      if (here === t.f) a.className = 'on';
      a.innerHTML = '<i>' + t.i + '</i><span>' + t.t + '</span>';
      bar.appendChild(a);
    });
    document.body.appendChild(bar);
  }

  // 배지 — 위쪽 N 배지 모듈이 메뉴에 심어둔 표시를 탭바에도 옮긴다
  function syncBadges() {
    var bar = document.querySelector('.cf-tabbar');
    if (!bar) return;
    [['notice.html', 'notice'], ['community.html', 'community'], ['support.html', 'support']]
      .forEach(function (p) {
        var tab = bar.querySelector('a[href="' + p[0] + '"]');
        if (!tab) return;
        var src = document.querySelector('nav:not(.cf-tabbar) a[href$="' + p[0] + '"] .cf-n');
        var old = tab.querySelector('.bg');
        if (src) {
          if (!old) { old = document.createElement('span'); old.className = 'bg'; tab.appendChild(old); }
          old.textContent = src.textContent;
        } else if (old) { old.parentNode.removeChild(old); }
      });
  }

  function start() { build(); syncBadges(); setInterval(syncBadges, 2000); }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', start);
  else start();
})();

/* ═══════════════════════════════════════════════════════════════════════
   🏠 대표 주소 통일 — kreft.co.kr (2026-09-02)
      같은 화면이 game.camnak.com · kreft.kr · camfishing.web.app 등
      여러 주소로 열리면 유저도 헷갈리고 검색엔진에도 좋지 않다.
      예전 주소로 들어와도 경로·검색어를 유지한 채 대표 주소로 보낸다.
      ⚠️ 예전 주소를 죽이면 안 된다 — 유저 북마크, 이미 올린 공지·커뮤니티
         글, 게임 안 '나가기' 버튼이 아직 그쪽을 가리킬 수 있다.
   ═══════════════════════════════════════════════════════════════════════ */
(function () {
  var HOME = 'kreft.co.kr';
  var OLD = ['game.camnak.com', 'kreft.kr', 'www.kreft.co.kr', 'www.kreft.kr',
             'camfishing.web.app', 'camfishing.firebaseapp.com'];
  var h = (location.hostname || '').toLowerCase();
  if (OLD.indexOf(h) < 0) return;                       // 대표 주소이거나 개발 환경 → 그대로
  if (location.protocol !== 'https:') return;           // 로컬 테스트 보호
  location.replace('https://' + HOME + location.pathname + location.search + location.hash);
})();


/* ═══════════════════════════════════════════════════════════════════════
   🔗 [친구에게 공유] 모든 허브 페이지 오른쪽 아래 떠 있는 버튼.
      쇼핑몰(camnak.com)에 있던 걸 게임 홈페이지에도 붙인다(2026-09-02).

      ⚠️ location.href를 그대로 공유하면 안 된다 — 자동로그인 토큰이
         해시(#k=...)에 실려 있어서 남의 계정으로 들어갈 수 있게 된다.
         그래서 origin+pathname만 쓰고 쿼리·해시는 전부 버린다.

      모바일은 OS 공유창(navigator.share), 데스크톱은 링크 복사로 떨어진다.
   ═══════════════════════════════════════════════════════════════════════ */
(function () {
  if (window.__cfShareReady) return;                 // 중복 주입 방지
  window.__cfShareReady = true;

  var TITLE = '캠피싱 KREFT — 손 안의 낚시터';
  var TEXT  = '🎣 전국 20개 낚시터, 어종 33종.'
    + '\n지금 가입하면 신규 조사 환영 세트를 드려요!';

  function shareUrl() {
    // 토큰이 붙을 수 있는 해시·쿼리는 제거. 대표 주소로 통일해서 내보낸다.
    var host = (location.hostname || '').toLowerCase();
    var origin = (host === 'kreft.co.kr') ? location.origin : 'https://kreft.co.kr';
    var path = location.pathname || '/';
    if (path === '/index.html') path = '/';
    return origin + path;
  }

  function toast(msg) {
    var t = document.createElement('div');
    t.className = 'cf-share-toast';
    t.textContent = msg;
    document.body.appendChild(t);
    setTimeout(function () { t.classList.add('on'); }, 10);
    setTimeout(function () {
      t.classList.remove('on');
      setTimeout(function () { if (t.parentNode) t.parentNode.removeChild(t); }, 300);
    }, 2000);
  }

  function copy(url) {
    if (navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(url)
        .then(function () { toast('링크를 복사했어요 📋'); })
        .catch(function () { legacy(url); });
    } else { legacy(url); }
  }

  function legacy(url) {
    try {
      var ta = document.createElement('textarea');
      ta.value = url;
      ta.setAttribute('readonly', '');
      ta.style.position = 'fixed';
      ta.style.left = '-9999px';
      document.body.appendChild(ta);
      ta.select();
      document.execCommand('copy');
      document.body.removeChild(ta);
      toast('링크를 복사했어요 📋');
    } catch (e) {
      toast('복사가 안 되면 주소창을 길게 눌러 복사해 주세요');
    }
  }

  function onClick() {
    var url = shareUrl();
    if (navigator.share) {
      navigator.share({ title: TITLE, text: TEXT, url: url })
        .catch(function () { /* 사용자가 취소한 것 — 조용히 넘어간다 */ });
    } else {
      copy(url);
    }
  }

  var css = document.createElement('style');
  css.textContent =
    '.cf-share{position:fixed;right:18px;bottom:20px;z-index:8800;' +
    '  display:inline-flex;align-items:center;gap:7px;' +
    '  padding:12px 18px;border:none;border-radius:999px;cursor:pointer;' +
    '  font-family:inherit;font-size:14px;font-weight:800;letter-spacing:-.2px;' +
    '  color:#20414d;background:linear-gradient(135deg,#ffd23f,#f7b500);' +
    '  box-shadow:0 6px 18px rgba(20,65,77,.22);transition:transform .15s,box-shadow .15s}' +
    '.cf-share:hover{transform:translateY(-2px);box-shadow:0 10px 24px rgba(20,65,77,.28)}' +
    '.cf-share:active{transform:translateY(0)}' +
    // 📱 모바일은 하단 탭바(62px) 위로 띄운다 — 겹치면 둘 다 못 누른다.
    '@media(max-width:768px){.cf-share{right:12px;font-size:13px;padding:11px 15px;' +
    '  bottom:calc(74px + env(safe-area-inset-bottom,0px))}}' +
    '@media print{.cf-share{display:none}}' +
    '.cf-share-toast{position:fixed;left:50%;bottom:96px;transform:translate(-50%,10px);' +
    '  z-index:9600;padding:12px 20px;border-radius:12px;font-size:14px;font-weight:700;' +
    '  color:#fff;background:rgba(16,34,43,.94);box-shadow:0 8px 22px rgba(10,40,55,.3);' +
    '  opacity:0;transition:opacity .25s,transform .25s;pointer-events:none;max-width:86vw;' +
    '  text-align:center;line-height:1.5}' +
    '.cf-share-toast.on{opacity:1;transform:translate(-50%,0)}';
  document.head.appendChild(css);

  function mount() {
    if (document.querySelector('.cf-share')) return;
    var b = document.createElement('button');
    b.className = 'cf-share';
    b.type = 'button';
    b.setAttribute('aria-label', '친구에게 공유하기');
    b.innerHTML = '<span aria-hidden="true">🔗</span><span>친구에게 공유</span>';
    b.onclick = onClick;
    document.body.appendChild(b);
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', mount);
  } else { mount(); }
})();
