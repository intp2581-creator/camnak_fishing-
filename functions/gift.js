// 🎁 [선물함] 홈페이지에서 '받기'를 눌러야 게임 인벤토리로 들어가는 기간 한정 선물.
//
//   왜 바로 안 넣고 받으러 오게 하는가(2026-09-04 사용자 결정):
//     · 전원에게 그냥 넣으면 휴면 유저 가방에 안 열린 상자만 쌓인다.
//     · 받으러 오는 김에 공지·커뮤니티를 보게 된다(홈페이지 체류·활성화).
//     · 기간을 정해두면 "지금 들어와야 할 이유"가 생긴다.
//   ⚠️ 기간 안에 안 받으면 못 받는다. 이건 버그가 아니라 설계다.
//
//   신규 가입 환영 선물은 이것과 무관하다 — 그건 가입 즉시 가방에 들어간다.
//
//   GET  ?list=1              내가 받을 수 있는 선물 + 받은 선물 (로그인 필요)
//   POST {action:"claim"}     받기 → 인벤토리에 선물 상자 지급
//   GET  ?all=1               전체 목록 (GM)
//   POST {action:"save"}      선물 등록·수정 (GM)
//   POST {action:"delete"}    삭제 (GM)

const {onRequest} = require("firebase-functions/v2/https");
const admin = require("firebase-admin");

const COL = "gifts";

// 🕒 한국 시간 기준 현재 시각(ms). 기간 판정은 전부 KST로 한다.
//    서버는 UTC로 도는데 운영자는 "9월 24일"이라고 생각하므로 여기서 맞춘다.
function nowKST() {
  return Date.now() + (9 * 60 * 60 * 1000);
}

// "2026-09-24" 또는 "2026-09-24 18:00" → KST 기준 ms
function parseKST(s, endOfDay) {
  const t = String(s || "").trim();
  if (!t) return endOfDay ? 8640000000000000 : 0;
  const m = t.match(/^(\d{4})-(\d{2})-(\d{2})(?:[ T](\d{2}):(\d{2}))?$/);
  if (!m) return endOfDay ? 8640000000000000 : 0;
  const hh = m[4] !== undefined ? +m[4] : (endOfDay ? 23 : 0);
  const mi = m[5] !== undefined ? +m[5] : (endOfDay ? 59 : 0);
  const ss = (m[4] === undefined && endOfDay) ? 59 : 0;
  return Date.UTC(+m[1], +m[2] - 1, +m[3], hh, mi, ss);
}

async function requireUser(req) {
  const m = String(req.get("Authorization") || "").match(/^Bearer\s+(.+)$/i);
  if (!m) throw new Error("로그인이 필요합니다");
  const dec = await admin.auth().verifyIdToken(m[1]);
  return {uid: dec.uid, email: (dec.email || "").toLowerCase()};
}

async function requireGm(uid) {
  const d = await admin.firestore().collection("users").doc(uid).get();
  if (!d.exists || d.data().isGm !== true) throw new Error("운영자만 가능합니다");
}

function clean(b) {
  const items = Array.isArray(b.items) ? b.items.slice(0, 30) : [];
  return {
    title: String(b.title || "").trim().slice(0, 60),
    msg: String(b.msg || "").trim().slice(0, 300),
    items: items.map((i) => ({
      name: String(i.name || "").slice(0, 40),
      quantity: Math.max(1, parseInt(i.quantity, 10) || 1),
      category: String(i.category || "COMMON").slice(0, 20),
      type: String(i.type || "ETC").slice(0, 20),
      icon: String(i.icon || "").slice(0, 80),
      desc: String(i.desc || "").slice(0, 300),
      ...(i.stats ? {stats: i.stats} : {}),
      ...(i.boost ? {boost: String(i.boost).slice(0, 10)} : {}),
      ...(i.secLeft ? {secLeft: parseInt(i.secLeft, 10) || 0, active: false} : {}),
    })),
    exp: Math.max(0, parseInt(b.exp, 10) || 0),
    gold: Math.max(0, parseInt(b.gold, 10) || 0),
    startAt: String(b.startAt || "").trim().slice(0, 20),
    endAt: String(b.endAt || "").trim().slice(0, 20),
    active: b.active !== false,
  };
}

// 🎁 게임 인벤토리에 들어갈 '선물 상자' 한 개 (game_config.makeGiftBox 와 같은 모양)
function buildBox(id, g) {
  const box = {
    name: "선물 상자",
    category: "BOX",
    type: "BOX",
    icon: "item_box_gift.png",
    quantity: 1,
    gid: "h" + id,          // h = 홈페이지에서 받은 것
    giftTitle: g.title,
    giftMsg: g.msg || "",
    gift: g.items || [],
    desc: g.title + "\n" + (g.msg || "") + "\n\n눌러서 열어보세요.",
  };
  if (g.exp > 0) box.giftExp = g.exp;
  if (g.gold > 0) box.giftGold = g.gold;
  return box;
}

exports.giftApi = onRequest({region: "us-central1", cors: true}, async (req, res) => {
  res.set("Access-Control-Allow-Origin", "*");
  res.set("Access-Control-Allow-Headers", "Content-Type, Authorization");
  res.set("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
  if (req.method === "OPTIONS") return res.status(204).send("");

  const db = admin.firestore();
  const col = db.collection(COL);

  try {
    const user = await requireUser(req);

    // ── 내 선물함 ──────────────────────────────
    if (req.method === "GET" && req.query.list) {
      const snap = await col.limit(50).get();
      const now = nowKST();
      const rows = [];
      for (const doc of snap.docs) {
        const g = doc.data();
        if (g.active === false) continue;
        const from = parseKST(g.startAt, false);
        const to = parseKST(g.endAt, true);
        if (now < from) continue;                 // 아직 시작 전 — 숨김
        const expired = now > to;
        // 받았는지는 서브컬렉션으로 본다(한 문서에 214명을 넣으면 금방 터진다)
        const c = await col.doc(doc.id).collection("claims").doc(user.uid).get();
        const claimed = c.exists;
        if (expired && !claimed) continue;        // 놓친 선물은 보여줘도 소용없다
        rows.push({
          id: doc.id, title: g.title, msg: g.msg || "",
          items: g.items || [], exp: g.exp || 0, gold: g.gold || 0,
          startAt: g.startAt || "", endAt: g.endAt || "",
          claimed, claimedAt: claimed ? (c.data().at || null) : null,
        });
      }
      rows.sort((a, b) => (a.claimed === b.claimed) ?
        String(b.endAt).localeCompare(String(a.endAt)) : (a.claimed ? 1 : -1));
      return res.json({ok: true, rows});
    }

    // ── 전체 목록(GM) ──────────────────────────
    if (req.method === "GET" && req.query.all) {
      await requireGm(user.uid);
      const snap = await col.limit(100).get();
      const rows = [];
      for (const doc of snap.docs) {
        const cs = await col.doc(doc.id).collection("claims").count().get();
        rows.push({id: doc.id, ...doc.data(), claims: cs.data().count});
      }
      rows.sort((a, b) => String(b.startAt).localeCompare(String(a.startAt)));
      return res.json({ok: true, rows});
    }

    if (req.method !== "POST") return res.status(405).json({ok: false, err: "method"});
    const b = req.body || {};
    const action = String(b.action || "");

    // ── 받기 ───────────────────────────────────
    if (action === "claim") {
      const id = String(b.id || "");
      if (!id) return res.status(400).json({ok: false, err: "선물을 찾을 수 없습니다"});

      const gref = col.doc(id);
      const gsnap = await gref.get();
      if (!gsnap.exists) return res.status(404).json({ok: false, err: "선물을 찾을 수 없습니다"});
      const g = gsnap.data();
      if (g.active === false) return res.status(400).json({ok: false, err: "받을 수 없는 선물입니다"});

      const now = nowKST();
      if (now < parseKST(g.startAt, false)) {
        return res.status(400).json({ok: false, err: "아직 받으실 수 없습니다"});
      }
      if (now > parseKST(g.endAt, true)) {
        return res.status(400).json({ok: false, err: "받기 기간이 끝났습니다"});
      }

      const cref = gref.collection("claims").doc(user.uid);
      const uref = db.collection("users").doc(user.uid);

      // 🔒 두 번 받기 방지 — 수령기록 생성과 인벤 지급을 한 트랜잭션으로 묶는다.
      //    버튼 연타·새로고침·두 탭에서 동시에 눌러도 한 번만 들어간다.
      const out = await db.runTransaction(async (tx) => {
        const c = await tx.get(cref);
        if (c.exists) return {dup: true};
        const u = await tx.get(uref);
        if (!u.exists) throw new Error("게임 계정을 찾을 수 없습니다");
        const inv = Array.isArray(u.data().inventory) ? u.data().inventory.slice() : [];
        inv.push(buildBox(id, g));
        tx.update(uref, {inventory: inv});
        tx.set(cref, {
          at: admin.firestore.FieldValue.serverTimestamp(),
          nick: u.data().nickname || "",
        });
        return {dup: false};
      });

      if (out.dup) return res.json({ok: true, already: true, err: "이미 받으신 선물입니다"});
      console.log(`[선물 지급] ${user.email} ← ${g.title} (${id})`);
      return res.json({ok: true, title: g.title});
    }

    // ── 등록·수정(GM) ──────────────────────────
    if (action === "save") {
      await requireGm(user.uid);
      const data = clean(b);
      if (!data.title) return res.status(400).json({ok: false, err: "선물 제목을 입력해 주세요"});
      if (!data.items.length && !data.exp && !data.gold) {
        return res.status(400).json({ok: false, err: "선물에 담을 것이 없습니다"});
      }
      if (b.id) {
        await col.doc(String(b.id)).set(data, {merge: true});
        return res.json({ok: true, id: String(b.id)});
      }
      const ref = await col.add({
        ...data, createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      return res.json({ok: true, id: ref.id});
    }

    if (action === "delete") {
      await requireGm(user.uid);
      // ⚠️ 수령기록(claims)은 남긴다 — 지운 뒤 같은 id로 다시 만들 일이 없고,
      //    누가 받았는지는 나중에 문의가 들어왔을 때 확인할 근거가 된다.
      await col.doc(String(b.id || "")).delete();
      return res.json({ok: true});
    }

    return res.status(400).json({ok: false, err: "알 수 없는 요청"});
  } catch (e) {
    const msg = String(e.message || e);
    const code = /로그인|운영자/.test(msg) ? 401 : 500;
    return res.status(code).json({ok: false, err: msg});
  }
});
