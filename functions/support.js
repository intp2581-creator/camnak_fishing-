// 🎧 [고객지원] 1:1 문의 — 결제·환불처럼 개인정보가 오가는 문의는 공개 게시판에 쓸 수 없다.
//   community_posts(공개)와 별도로 support_tickets를 쓰며, 본인과 운영자만 조회 가능.
//
// GET  ?list=1                  내 문의 목록 (GM은 전체)
// GET  ?id=<티켓ID>             상세 + 답변 (본인/GM만)
// POST {action:"create", ...}   문의 작성
// POST {action:"reply", ...}    답변/추가문의 (본인 또는 GM)
// POST {action:"close", id}     처리 완료 (GM만)

const {onRequest} = require("firebase-functions/v2/https");
const admin = require("firebase-admin");

const CATEGORIES = ["payment", "refund", "account", "game", "etc"];
const CAT_LABEL = {payment: "결제", refund: "환불", account: "계정", game: "게임 이용", etc: "기타"};

async function me(req) {
  const m = String(req.get("Authorization") || "").match(/^Bearer\s+(.+)$/i);
  if (!m) throw new Error("로그인이 필요합니다");
  const dec = await admin.auth().verifyIdToken(m[1]);
  const d = await admin.firestore().collection("users").doc(dec.uid).get();
  const v = d.exists ? d.data() : {};
  return {uid: dec.uid, email: (dec.email || "").toLowerCase(),
    nick: v.nickname || "조사님", isGm: v.isGm === true};
}

exports.supportApi = onRequest({region: "us-central1", cors: true}, async (req, res) => {
  res.set("Access-Control-Allow-Origin", "*");
  res.set("Access-Control-Allow-Headers", "Content-Type, Authorization");
  res.set("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
  if (req.method === "OPTIONS") return res.status(204).send("");

  const db = admin.firestore();
  const col = db.collection("support_tickets");

  try {
    const u = await me(req);

    // ── 목록 ──────────────────────────────────
    if (req.method === "GET" && req.query.list) {
      let q = col.orderBy("createdAt", "desc").limit(50);
      if (!u.isGm) q = col.where("uid", "==", u.uid).orderBy("createdAt", "desc").limit(50);
      const s = await q.get();
      const rows = [];
      s.forEach((d) => {
        const v = d.data();
        rows.push({id: d.id, category: v.category, categoryLabel: CAT_LABEL[v.category] || "기타",
          title: v.title, status: v.status, nick: v.nick,
          replyCount: v.replyCount || 0,
          createdAt: v.createdAt ? v.createdAt.toMillis() : 0});
      });
      return res.json({ok: true, isGm: u.isGm, rows});
    }

    // ── 상세 ──────────────────────────────────
    if (req.method === "GET" && req.query.id) {
      const doc = await col.doc(String(req.query.id)).get();
      if (!doc.exists) return res.status(404).json({ok: false, err: "문의를 찾을 수 없습니다"});
      const v = doc.data();
      // 🔒 본인 또는 운영자만
      if (v.uid !== u.uid && !u.isGm) {
        return res.status(403).json({ok: false, err: "본인 문의만 확인하실 수 있습니다"});
      }
      const rs = await col.doc(doc.id).collection("replies").orderBy("createdAt", "asc").get();
      const replies = [];
      rs.forEach((r) => {
        const rv = r.data();
        replies.push({body: rv.body, byGm: rv.byGm === true, nick: rv.nick,
          createdAt: rv.createdAt ? rv.createdAt.toMillis() : 0});
      });
      return res.json({ok: true, isGm: u.isGm,
        ticket: {id: doc.id, category: v.category, categoryLabel: CAT_LABEL[v.category] || "기타",
          title: v.title, body: v.body, orderId: v.orderId || "", status: v.status,
          nick: v.nick, email: u.isGm ? v.email : "",
          createdAt: v.createdAt ? v.createdAt.toMillis() : 0},
        replies});
    }

    if (req.method !== "POST") return res.status(405).json({ok: false, err: "method"});
    const b = req.body || {};
    const action = String(b.action || "");

    // ── 문의 작성 ──────────────────────────────
    if (action === "create") {
      const category = CATEGORIES.indexOf(String(b.category)) > -1 ? String(b.category) : "etc";
      const title = String(b.title || "").trim().slice(0, 80);
      const body = String(b.body || "").trim().slice(0, 3000);
      if (!title || !body) return res.status(400).json({ok: false, err: "제목과 내용을 입력해 주세요"});

      // 🚫 도배 방지 — 처리 대기중인 문의가 5건 넘으면 막는다
      const openCnt = await col.where("uid", "==", u.uid).where("status", "==", "open").get();
      if (openCnt.size >= 5) {
        return res.status(429).json({ok: false, err: "답변 대기중인 문의가 많습니다. 답변 후 이용해 주세요."});
      }
      const doc = await col.add({
        uid: u.uid, email: u.email, nick: u.nick,
        category, title, body, orderId: String(b.orderId || "").trim().slice(0, 40),
        status: "open", replyCount: 0,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      return res.json({ok: true, id: doc.id});
    }

    // ── 답변 / 추가 문의 ────────────────────────
    if (action === "reply") {
      const id = String(b.id || "");
      const body = String(b.body || "").trim().slice(0, 3000);
      if (!id || !body) return res.status(400).json({ok: false, err: "내용을 입력해 주세요"});
      const ref = col.doc(id);
      const doc = await ref.get();
      if (!doc.exists) return res.status(404).json({ok: false, err: "문의를 찾을 수 없습니다"});
      if (doc.data().uid !== u.uid && !u.isGm) {
        return res.status(403).json({ok: false, err: "권한이 없습니다"});
      }
      await ref.collection("replies").add({
        body, byGm: u.isGm, nick: u.isGm ? "캠피싱 운영자" : u.nick,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      await ref.update({
        replyCount: admin.firestore.FieldValue.increment(1),
        status: u.isGm ? "answered" : "open",     // 운영자가 답하면 답변완료, 유저가 쓰면 다시 대기
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      return res.json({ok: true});
    }

    // ── 처리 완료(운영자) ───────────────────────
    if (action === "close") {
      if (!u.isGm) return res.status(403).json({ok: false, err: "운영자만 가능합니다"});
      await col.doc(String(b.id || "")).update({status: "closed"});
      return res.json({ok: true});
    }

    return res.status(400).json({ok: false, err: "알 수 없는 요청"});
  } catch (e) {
    return res.status(401).json({ok: false, err: String(e.message || e)});
  }
});
