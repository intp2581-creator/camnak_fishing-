// 🛒 [게임스토어 상품 관리] 상품을 코드가 아니라 Firestore로 관리한다.
//   지금까지 상품이 hub/store.html 안에 배열로 박혀 있어, 하나 추가하려면
//   코드를 고치고 배포해야 했다. 상품은 계속 늘어나므로 운영자가 직접
//   추가·수정할 수 있어야 한다(2026-09-02 신설).
//
//   GET  ?list=1            노출 상품 목록 (누구나 — 스토어 화면용)
//   GET  ?all=1             전체 목록 (GM만 — 숨김 포함)
//   POST {action:"save"}    추가·수정 (GM만)
//   POST {action:"delete"}  삭제 (GM만)
//   POST {action:"sort"}    순서 일괄 저장 (GM만)
//
//   ⚠️ 게임 안 KREFT 상점(낚싯대·릴·미끼)은 여기서 다루지 않는다.
//      파워·레벨게이트는 밸런스 수치라 코드에 두는 편이 안전하다.

const {onRequest} = require("firebase-functions/v2/https");
const admin = require("firebase-admin");

const COL = "store_products";
const CATS = ["ticket", "skin", "badge", "package", "etc"];

async function gm(req) {
  const m = String(req.get("Authorization") || "").match(/^Bearer\s+(.+)$/i);
  if (!m) throw new Error("로그인이 필요합니다");
  const dec = await admin.auth().verifyIdToken(m[1]);
  const d = await admin.firestore().collection("users").doc(dec.uid).get();
  if (!d.exists || d.data().isGm !== true) throw new Error("운영자만 가능합니다");
  return {uid: dec.uid, nick: d.data().nickname || ""};
}

function clean(b) {
  const cat = CATS.indexOf(String(b.c)) > -1 ? String(b.c) : "etc";
  return {
    c: cat,
    key: String(b.key || "").trim().slice(0, 40),
    n: String(b.n || "").trim().slice(0, 60),
    p: Math.max(0, parseInt(b.p, 10) || 0),
    lv: Math.max(0, parseInt(b.lv, 10) || 0),
    idx: Math.max(0, parseInt(b.idx, 10) || 0),   // 아임웹 상품번호(임시 결제 경로)
    img: String(b.img || "").trim().slice(0, 120),
    d: String(b.d || "").trim().slice(0, 500),
    detail: String(b.detail || "").trim().slice(0, 4000),
    hidden: b.hidden === true,
    soon: b.soon === true,      // 🕒 진열은 하되 아직 판매 전(구매 버튼 잠금)
    soonText: String(b.soonText || "").trim().slice(0, 40),  // 예: "9월 5일 판매 시작"
    order: Math.max(0, parseInt(b.order, 10) || 0),
  };
}

exports.storeApi = onRequest({region: "us-central1", cors: true}, async (req, res) => {
  res.set("Access-Control-Allow-Origin", "*");
  res.set("Access-Control-Allow-Headers", "Content-Type, Authorization");
  res.set("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
  if (req.method === "OPTIONS") return res.status(204).send("");

  const db = admin.firestore();
  const col = db.collection(COL);

  try {
    // ── 목록(공개) ─────────────────────────────
    if (req.method === "GET" && req.query.list) {
      const s = await col.limit(200).get();
      const rows = [];
      s.forEach((doc) => {
        const v = doc.data();
        if (v.hidden === true) return;              // 숨김 상품 제외
        rows.push({id: doc.id, ...v});
      });
      rows.sort((a, b) => (a.order || 0) - (b.order || 0));
      return res.json({ok: true, items: rows});
    }

    // ── 목록(운영자 — 숨김 포함) ────────────────
    if (req.method === "GET" && req.query.all) {
      await gm(req);
      const s = await col.limit(200).get();
      const rows = [];
      s.forEach((doc) => rows.push({id: doc.id, ...doc.data()}));
      rows.sort((a, b) => (a.order || 0) - (b.order || 0));
      return res.json({ok: true, items: rows});
    }

    if (req.method !== "POST") return res.status(405).json({ok: false, err: "method"});
    const u = await gm(req);
    const b = req.body || {};
    const action = String(b.action || "");

    if (action === "save") {
      const data = clean(b);
      if (!data.n) return res.status(400).json({ok: false, err: "상품명을 입력해 주세요"});
      if (!data.key) return res.status(400).json({ok: false, err: "지급 키를 입력해 주세요"});
      data.updatedAt = admin.firestore.FieldValue.serverTimestamp();
      data.updatedBy = u.nick;
      if (b.id) {
        await col.doc(String(b.id)).set(data, {merge: true});
        return res.json({ok: true, id: String(b.id)});
      }
      data.createdAt = admin.firestore.FieldValue.serverTimestamp();
      const doc = await col.add(data);
      return res.json({ok: true, id: doc.id});
    }

    if (action === "delete") {
      const id = String(b.id || "");
      if (!id) return res.status(400).json({ok: false, err: "id 없음"});
      await col.doc(id).delete();
      console.log("[상품 삭제] " + id + " (by " + u.nick + ")");
      return res.json({ok: true});
    }

    // 순서 일괄 저장 — [{id, order}, ...]
    if (action === "sort") {
      const rows = Array.isArray(b.rows) ? b.rows.slice(0, 200) : [];
      const batch = db.batch();
      rows.forEach((r) => {
        if (!r || !r.id) return;
        batch.update(col.doc(String(r.id)), {order: parseInt(r.order, 10) || 0});
      });
      await batch.commit();
      return res.json({ok: true, n: rows.length});
    }

    return res.status(400).json({ok: false, err: "알 수 없는 요청"});
  } catch (e) {
    return res.status(401).json({ok: false, err: String(e.message || e)});
  }
});
