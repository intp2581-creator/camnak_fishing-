// 📊 [접속 통계] 10분마다 '지금 접속 중인 사람'을 세어 하루치 문서에 쌓는다.
//
//   왜 이렇게 하는가 — 게임은 지금 상태만 실시간DB(status_nick)에 덮어쓴다.
//   지나간 것은 남지 않아서, 관리자가 시간대별로 직접 들여다보지 않으면 알 수가 없다.
//   게임을 고쳐 접속할 때마다 기록을 남기게 할 수도 있지만, 그러면 게임을 다시 배포해야 하고
//   유저 수만큼 쓰기가 늘어난다. 밖에서 10분마다 한 번 세는 쪽이 게임을 안 건드리고 싸다.
//
//   ⚠️ 하루 경계·시간대는 전부 한국시간(KST)이다. 서버는 UTC로 돌아서 그냥 두면
//      새벽 9시에 날짜가 바뀐다.
//
//   저장 모양 — stats_online/{YYYY-MM-DD}
//     hours : { "00": {max, sum, n}, ... }  시간대별 최대·평균 동시접속
//     nicks : { 닉네임: true }               그날 한 번이라도 접속한 사람(=DAU)
//     peak  : 그날 최대 동시접속
//     lastAt: 마지막으로 센 시각

const functions = require("firebase-functions/v2");
const admin = require("firebase-admin");
const {onRequest} = require("firebase-functions/v2/https");

const RTDB_URL =
  "https://camnak-fishing-default-rtdb.asia-southeast1.firebasedatabase.app";

/** 한국시간 기준 {날짜 'YYYY-MM-DD', 시 '00'~'23'} */
function kstNow() {
  const t = new Date(Date.now() + 9 * 60 * 60 * 1000); // UTC+9
  const p = (n) => String(n).padStart(2, "0");
  return {
    day: t.getUTCFullYear() + "-" + p(t.getUTCMonth() + 1) + "-" + p(t.getUTCDate()),
    hour: p(t.getUTCHours()),
  };
}

exports.collectOnlineStats = functions.scheduler.onSchedule(
    {schedule: "*/10 * * * *", timeZone: "Asia/Seoul", region: "us-central1"},
    async () => {
      const rtdb = admin.app().database(RTDB_URL);
      const snap = await rtdb.ref("status_nick").get();
      const v = snap.val() || {};

      // 접속이 끊기면 onDisconnect 로 online:false 가 되지만 기록은 남는다. 켜진 것만 센다.
      // ⚠️ online:true 인 채로 멈춘 '유령'도 걸러야 한다. 끊길 때 onDisconnect 가 못 돌면
      //    그대로 남아 34일 전 것이 접속 중으로 잡혔다. 게임은 어디서든 12초마다 다시
      //    적으므로(하트비트), 5분 넘게 소식이 없으면 접속이 아니다.
      const STALE = 5 * 60 * 1000;
      const now = Date.now();
      const online = Object.keys(v).filter((nick) => {
        const x = v[nick];
        return x && x.online === true && x.t && (now - x.t) < STALE;
      });
      const fishing = online.filter((nick) => v[nick].fishing === true);

      const {day, hour} = kstNow();
      const ref = admin.firestore().collection("stats_online").doc(day);

      await admin.firestore().runTransaction(async (tx) => {
        const cur = (await tx.get(ref)).data() || {};
        const hours = cur.hours || {};
        const h = hours[hour] || {max: 0, sum: 0, n: 0, fishMax: 0};

        h.max = Math.max(h.max || 0, online.length);
        h.sum = (h.sum || 0) + online.length;
        h.n = (h.n || 0) + 1;
        h.fishMax = Math.max(h.fishMax || 0, fishing.length);
        hours[hour] = h;

        // 그날 접속한 사람 모음 = DAU. 같은 사람이 여러 번 잡혀도 한 번만 남는다.
        const nicks = cur.nicks || {};
        online.forEach((nick) => { nicks[nick] = true; });

        tx.set(ref, {
          hours,
          nicks,
          dau: Object.keys(nicks).length,
          peak: Math.max(cur.peak || 0, online.length),
          lastAt: admin.firestore.FieldValue.serverTimestamp(),
        }, {merge: true});
      });

      console.log(`[접속통계] ${day} ${hour}시 · 접속 ${online.length} · 낚시 ${fishing.length}`);
    },
);


// ══════════════════════════════════════════════════════════════
// 🏠 [홈페이지 방문] 페이지가 열릴 때 한 번 알려온다(로그인 불필요).
//   저장 모양 — stats_site/{YYYY-MM-DD}
//     visits : 그날 열린 페이지 수
//     uniq   : 그날 처음 온 브라우저 수(브라우저가 first=1 로 알려줄 때만)
//     bySrc  : { insta: 12, youtube: 3, direct: 40, ... } 어디서 왔는가
//   ⚠️ 어디서 왔는지는 주소의 ?from= 값을 먼저 보고, 없으면 어느 사이트에서
//      눌러 들어왔는지(referrer)로 가른다. 둘 다 없으면 direct.
// ══════════════════════════════════════════════════════════════
function srcKey(raw, ref) {
  const v = String(raw || "").toLowerCase().slice(0, 20).replace(/[^a-z0-9_-]/g, "");
  if (v) return v;
  const r = String(ref || "").toLowerCase();
  if (!r) return "direct";
  if (r.includes("instagram")) return "insta";
  if (r.includes("youtube") || r.includes("youtu.be")) return "youtube";
  if (r.includes("naver")) return "naver";
  if (r.includes("google")) return "google";
  if (r.includes("kakao")) return "kakao";
  if (r.includes("camnak.com")) return "camnak";
  if (r.includes("kreft.co.kr") || r.includes("camfishing")) return "self";
  return "etc";
}

async function bumpSite(day, fields) {
  const ref = admin.firestore().collection("stats_site").doc(day);
  const inc = admin.firestore.FieldValue.increment(1);
  // ⚠️ set() 은 키의 점을 경로로 읽지 않는다("bySrc.insta" 라는 이름의 칸이 생긴다).
  //    묶음으로 넣으려면 실제 중첩 객체로 만들어야 한다.
  const upd = {lastAt: admin.firestore.FieldValue.serverTimestamp()};
  fields.forEach((f) => {
    const i = f.indexOf(".");
    if (i < 0) {
      upd[f] = inc;
    } else {
      const g = f.slice(0, i);
      upd[g] = Object.assign({}, upd[g], {[f.slice(i + 1)]: inc});
    }
  });
  await ref.set(upd, {merge: true});
}

exports.siteHit = onRequest({region: "us-central1", cors: true}, async (req, res) => {
  res.set("Access-Control-Allow-Origin", "*");
  res.set("Access-Control-Allow-Headers", "Content-Type");
  if (req.method === "OPTIONS") return res.status(204).send("");
  try {
    const b = req.body || {};
    const key = srcKey(b.src, b.ref);
    const {day} = kstNow();
    const f = ["visits", "bySrc." + key];
    if (b.first) f.push("uniq", "uniqBySrc." + key);
    await bumpSite(day, f);
    return res.json({ok: true});
  } catch (e) {
    return res.status(200).json({ok: false});           // 방문 기록 실패가 화면을 막지 않는다
  }
});

// 🆕 [가입 집계] 게임 계정이 만들어지면 그날 칸에 +1. 어디서 온 사람인지(src)도 같이 센다.
exports.onUserCreated = require("firebase-functions/v2/firestore").onDocumentCreated(
    {document: "users/{uid}", region: "us-central1"},
    async (event) => {
      const d = event.data && event.data.data ? event.data.data() : {};
      const key = srcKey(d.src, "");
      const {day} = kstNow();
      await bumpSite(day, ["signups", "signupBySrc." + key]);
    },
);

// ── 📊 통계 읽기(운영자) ─────────────────────────────
//   GET ?days=14  최근 며칠치. 닉네임 목록은 무겁고 볼 일도 없어서 빼고 숫자만 준다.

async function requireGm(req) {
  const m = String(req.get("Authorization") || "").match(/^Bearer\s+(.+)$/i);
  if (!m) throw new Error("로그인이 필요합니다");
  const dec = await admin.auth().verifyIdToken(m[1]);
  const d = await admin.firestore().collection("users").doc(dec.uid).get();
  if (!d.exists || d.data().isGm !== true) throw new Error("운영자만 가능합니다");
  return dec.uid;
}

exports.statsApi = onRequest({region: "us-central1", cors: true}, async (req, res) => {
  res.set("Access-Control-Allow-Origin", "*");
  res.set("Access-Control-Allow-Headers", "Content-Type, Authorization");
  if (req.method === "OPTIONS") return res.status(204).send("");
  try {
    await requireGm(req);
    const days = Math.min(60, Math.max(1, parseInt(req.query.days, 10) || 14));

    // 오늘부터 거꾸로 날짜를 만든다(한국시간).
    const ids = [];
    for (let i = 0; i < days; i++) {
      const t = new Date(Date.now() + 9 * 3600 * 1000 - i * 86400 * 1000);
      const p = (n) => String(n).padStart(2, "0");
      ids.push(t.getUTCFullYear() + "-" + p(t.getUTCMonth() + 1) + "-" + p(t.getUTCDate()));
    }
    const col = admin.firestore().collection("stats_online");
    const docs = await admin.firestore().getAll(...ids.map((id) => col.doc(id)));

    // 🏠 같은 날짜의 홈페이지 방문·가입 문서도 같이 읽는다
    const scol = admin.firestore().collection("stats_site");
    const sdocs = await admin.firestore().getAll(...ids.map((id) => scol.doc(id)));
    const site = {};
    sdocs.forEach((d, i) => {
      site[ids[i]] = d.exists ? d.data() : {};
    });

    // 🧮 전체 계정 수 — 문서를 다 읽지 않고 세기만 한다(요금 적음)
    let total = 0;
    try {
      const agg = await admin.firestore().collection("users").count().get();
      total = agg.data().count || 0;
    } catch (e) { /* 세기 실패해도 나머지는 보여준다 */ }

    // 📅 지난 날짜의 가입자 수 — 집계가 없던 날은 createdAt 으로 직접 센다
    const users = admin.firestore().collection("users");
    for (const id of ids) {
      if (site[id] && typeof site[id].signups === "number") continue;
      const s0 = new Date(id + "T00:00:00+09:00");
      const s1 = new Date(s0.getTime() + 86400 * 1000);
      try {
        const agg = await users.where("createdAt", ">=", s0).where("createdAt", "<", s1).count().get();
        site[id] = Object.assign({}, site[id], {signups: agg.data().count || 0, signupsCalc: true});
      } catch (e) { /* 옛 계정은 createdAt 이 없을 수 있다 */ }
    }

    const out = docs.map((d, i) => {
      const v = d.exists ? d.data() : {};
      const hours = v.hours || {};
      // 시간대별로 '그 시간의 최대 동시접속'만 보낸다. 그래프를 그리는 데 그거면 된다.
      const byHour = [];
      for (let h = 0; h < 24; h++) {
        const k = String(h).padStart(2, "0");
        byHour.push(hours[k] ? (hours[k].max || 0) : 0);
      }
      const w = site[ids[i]] || {};
      return {
        day: ids[i], dau: v.dau || 0, peak: v.peak || 0, hours: byHour,
        visits: w.visits || 0, uniq: w.uniq || 0, signups: w.signups || 0,
        bySrc: w.bySrc || {}, uniqBySrc: w.uniqBySrc || {}, signupBySrc: w.signupBySrc || {},
      };
    });
    return res.json({ok: true, days: out, totalAccounts: total});
  } catch (e) {
    return res.status(400).json({ok: false, err: e.message});
  }
});
