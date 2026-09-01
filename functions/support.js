// 🎧 [고객지원] 1:1 문의 — 결제·환불처럼 개인정보가 오가는 문의는 공개 게시판에 쓸 수 없다.
//   community_posts(공개)와 별도로 support_tickets를 쓰며, 본인과 운영자만 조회 가능.
//
// GET  ?list=1                  내 문의 목록 (GM은 전체)
// GET  ?id=<티켓ID>             상세 + 답변 (본인/GM만)
// POST {action:"create", ...}   문의 작성
// POST {action:"reply", ...}    답변/추가문의 (본인 또는 GM)
// POST {action:"close", id}     처리 완료 (GM만)
// POST {action:"gmInv", id}     문의자 인벤토리 조회 (GM만)
// POST {action:"gmRevoke", ...} 아이템 회수 — 환불 처리용 (GM만, 로그 필수)
// POST {action:"gmDelete", id}  문의 삭제 (GM만, 답변까지 함께 삭제)

const {onRequest} = require("firebase-functions/v2/https");
const admin = require("firebase-admin");

const CATEGORIES = ["prize", "payment", "refund", "account", "game", "etc"];
const CAT_LABEL = {prize: "이벤트 당첨", payment: "결제", refund: "환불",
  account: "계정", game: "게임 이용", etc: "기타"};

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
      // ⚠️ where + orderBy 조합은 Firestore 복합색인을 요구한다.
      //    문의 건수가 많지 않으므로 색인을 만들지 않고 '정렬은 메모리에서' 처리한다.
      const s = u.isGm
        ? await col.orderBy("createdAt", "desc").limit(100).get()
        : await col.where("uid", "==", u.uid).limit(100).get();
      const rows = [];
      s.forEach((d) => {
        const v = d.data();
        rows.push({id: d.id, category: v.category, categoryLabel: CAT_LABEL[v.category] || "기타",
          title: v.title, status: v.status, nick: v.nick,
          replyCount: v.replyCount || 0,
          gmReplies: v.gmReplies || 0, userReplies: v.userReplies || 0,
          createdAt: v.createdAt ? v.createdAt.toMillis() : 0});
      });
      rows.sort((a, b) => b.createdAt - a.createdAt);
      return res.json({ok: true, isGm: u.isGm, rows: rows.slice(0, 50)});
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
      const mine = await col.where("uid", "==", u.uid).limit(100).get();
      let open = 0;
      mine.forEach((d) => { if (d.data().status === "open") open++; });
      if (open >= 5) {
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
      // ⚠️ 운영자 답변과 문의자의 추가 글을 한 숫자로 세면, 목록에서 '답변 1'로 보여
      //    답을 준 것처럼 착각하게 된다. 따로 센다.
      const upd = {
        replyCount: admin.firestore.FieldValue.increment(1),
        status: u.isGm ? "answered" : "open",     // 운영자가 답하면 답변완료, 유저가 쓰면 다시 대기
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      };
      upd[u.isGm ? "gmReplies" : "userReplies"] = admin.firestore.FieldValue.increment(1);
      await ref.update(upd);
      return res.json({ok: true});
    }

    // ── [운영자] 문의자의 인벤토리 조회 ──────────
    //   환불 처리 전, 회수할 아이템이 실제로 남아 있는지 확인하는 용도.
    if (action === "gmInv") {
      if (!u.isGm) return res.status(403).json({ok: false, err: "운영자만 가능합니다"});
      const doc = await col.doc(String(b.id || "")).get();
      if (!doc.exists) return res.status(404).json({ok: false, err: "문의를 찾을 수 없습니다"});
      const targetUid = doc.data().uid;
      const ud = await db.collection("users").doc(targetUid).get();
      if (!ud.exists) return res.status(404).json({ok: false, err: "회원 정보를 찾을 수 없습니다"});
      const uv = ud.data();
      const inv = Array.isArray(uv.inventory) ? uv.inventory : [];
      const rows = [];
      inv.forEach((i) => {
        if ((i.type || "") === "FISH") return;          // 물고기는 회수 대상 아님
        rows.push({name: String(i.name || ""), qty: Number(i.quantity || 1),
          cash: i.cash === true, category: String(i.category || "")});
      });
      rows.sort((a, b2) => (b2.cash - a.cash) || a.name.localeCompare(b2.name));
      return res.json({ok: true, uid: targetUid, nick: uv.nickname || "", items: rows});
    }

    // ── [운영자] 아이템 회수 ────────────────────
    //   ⚠️ 환불과 짝이 되는 동작이다. 되돌릴 수 있어야 하므로
    //      회수 전 수량을 item_revocations에 그대로 남긴다.
    if (action === "gmRevoke") {
      if (!u.isGm) return res.status(403).json({ok: false, err: "운영자만 가능합니다"});
      const tid = String(b.id || "");
      const itemName = String(b.itemName || "").trim();
      const count = Math.max(1, Math.min(99, parseInt(b.count, 10) || 0));
      const reason = String(b.reason || "").trim().slice(0, 200);
      if (!itemName) return res.status(400).json({ok: false, err: "회수할 아이템을 지정해 주세요"});
      if (!reason) return res.status(400).json({ok: false, err: "회수 사유를 입력해 주세요"});

      const tdoc = await col.doc(tid).get();
      if (!tdoc.exists) return res.status(404).json({ok: false, err: "문의를 찾을 수 없습니다"});
      const targetUid = tdoc.data().uid;
      const uref = db.collection("users").doc(targetUid);

      let before = 0; let after = 0; let nick = "";
      await db.runTransaction(async (tx) => {
        const ud = await tx.get(uref);
        if (!ud.exists) throw new Error("회원 정보를 찾을 수 없습니다");
        const uv = ud.data();
        nick = uv.nickname || "";
        const inv = Array.isArray(uv.inventory) ? [...uv.inventory] : [];
        const idx = inv.findIndex((i) => String(i.name || "") === itemName);
        if (idx < 0) throw new Error("인벤토리에 '" + itemName + "'이(가) 없습니다");
        before = Number(inv[idx].quantity || 1);
        if (before < count) {
          throw new Error("보유 수량이 " + before + "개뿐이라 " + count + "개를 회수할 수 없습니다");
        }
        after = before - count;
        if (after <= 0) { inv.splice(idx, 1); } else { inv[idx] = {...inv[idx], quantity: after}; }
        tx.update(uref, {inventory: inv});
      });

      await db.collection("item_revocations").add({
        uid: targetUid, nick, ticketId: tid, itemName, count, before, after, reason,
        byUid: u.uid, byNick: u.nick,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      return res.json({ok: true, itemName, count, before, after});
    }

    // ── [운영자] 문의 삭제 ──────────────────────
    //   테스트 글 정리용이자, 배송이 끝난 뒤 주소가 담긴 문의를 지우는 용도.
    //   되돌릴 수 없으므로 GM만, 답변까지 함께 지운다.
    if (action === "gmDelete") {
      if (!u.isGm) return res.status(403).json({ok: false, err: "운영자만 가능합니다"});
      const id = String(b.id || "");
      const ref = col.doc(id);
      const doc = await ref.get();
      if (!doc.exists) return res.status(404).json({ok: false, err: "문의를 찾을 수 없습니다"});
      const v = doc.data();
      const rs = await ref.collection("replies").get();
      const batch = db.batch();
      rs.forEach((d) => batch.delete(d.ref));
      batch.delete(ref);
      await batch.commit();
      console.log("[문의 삭제] " + id + " / " + (v.nick || "") + " / " + (v.title || "") +
                  " (by " + u.nick + ")");
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
