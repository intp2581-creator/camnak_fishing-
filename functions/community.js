// ═══════════════════════════════════════════════════════════════
// 💬 [커뮤니티 API] camfishing.web.app 유저 게시판
//   컬렉션: community_posts / community_comments
//   GET  ?list=1&board=free[&limit=20][&after=<ms>]  → 목록
//   GET  ?id=<문서id>                                → 상세(+조회수, 댓글 포함)
//   POST (Authorization: Bearer <IdToken>)           → write/comment/delete/deleteComment
//   이미지: base64로 받아 Storage에 저장(admin SDK) → 공개 URL 반환. 보안규칙 불필요.
// ═══════════════════════════════════════════════════════════════
const functions = require("firebase-functions");
const admin = require("firebase-admin");

const BOARDS = ["free", "tip", "catch", "guild", "ask"];

async function requireUser(req) {
  const m = String(req.get("Authorization") || "").match(/^Bearer\s+(.+)$/i);
  if (!m) throw new Error("로그인이 필요합니다");
  let dec;
  try {
    dec = await admin.auth().verifyIdToken(m[1]);
  } catch (e) {
    throw new Error("인증 실패(다시 로그인해 주세요)");
  }
  const doc = await admin.firestore().collection("users").doc(dec.uid).get();
  const d = doc.exists ? doc.data() : {};
  return {
    uid: dec.uid,
    nick: (d.nickname || "조사님").toString(),
    rank: (d.rank || "초보").toString(),
    isGm: d.isGm === true,
  };
}

async function saveImages(postId, images) {
  if (!Array.isArray(images) || !images.length) return [];
  const bucket = admin.storage().bucket();
  const urls = [];
  for (let i = 0; i < Math.min(images.length, 5); i++) {
    const raw = String(images[i] || "");
    const m = raw.match(/^data:(image\/(?:jpeg|png|webp));base64,(.+)$/);
    if (!m) continue;
    const buf = Buffer.from(m[2], "base64");
    if (buf.length > 3 * 1024 * 1024) continue;
    const ext = m[1] === "image/png" ? "png" : (m[1] === "image/webp" ? "webp" : "jpg");
    const path = "community/" + postId + "/" + Date.now() + "_" + i + "." + ext;
    const file = bucket.file(path);
    await file.save(buf, {
      metadata: { contentType: m[1], cacheControl: "public,max-age=31536000" },
    });
    await file.makePublic();
    urls.push("https://storage.googleapis.com/" + bucket.name + "/" + path);
  }
  return urls;
}

exports.communityApi = functions.https.onRequest(async (req, res) => {
  res.set("Access-Control-Allow-Origin", "*");
  res.set("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
  res.set("Access-Control-Allow-Headers", "Content-Type, Authorization");
  if (req.method === "OPTIONS") return res.status(204).send("");

  const db = admin.firestore();
  const posts = db.collection("community_posts");
  const comments = db.collection("community_comments");

  try {
    // ── 조회 ───────────────────────────────
    if (req.method === "GET") {
      res.set("Cache-Control", "no-store");

      if (req.query.id) {
        const id = String(req.query.id);
        const doc = await posts.doc(id).get();
        if (!doc.exists || doc.data().deleted === true) {
          return res.status(404).json({ ok: false, err: "글을 찾을 수 없습니다" });
        }
        posts.doc(id).update({ views: admin.firestore.FieldValue.increment(1) }).catch(() => {});
        const d = doc.data();
        const cs = await comments.where("postId", "==", id).limit(200).get();
        const cList = [];
        cs.forEach((c) => {
          const v = c.data();
          if (v.deleted === true) return;
          cList.push({
            id: c.id, body: v.body || "", author: v.author || "", rank: v.rank || "",
            authorUid: v.authorUid || "", createdAt: v.createdAt ? v.createdAt.toMillis() : 0,
          });
        });
        cList.sort((a, b) => a.createdAt - b.createdAt);
        return res.json({
          ok: true,
          item: {
            id: doc.id, board: d.board, title: d.title, body: d.body, images: d.images || [],
            author: d.author, rank: d.rank || "", authorUid: d.authorUid || "",
            views: d.views || 0, createdAt: d.createdAt ? d.createdAt.toMillis() : 0,
          },
          comments: cList,
        });
      }

      const board = BOARDS.indexOf(String(req.query.board)) > -1 ? String(req.query.board) : null;
      let limit = parseInt(req.query.limit, 10);
      if (!Number.isFinite(limit) || limit < 1 || limit > 50) limit = 20;

      // 인덱스 없이 동작하도록: board 필터는 메모리에서 처리
      const snap = await posts.orderBy("createdAt", "desc").limit(200).get();
      const items = [];
      snap.forEach((doc) => {
        const d = doc.data();
        if (d.deleted === true) return;
        if (board && d.board !== board) return;
        if (items.length >= limit) return;
        items.push({
          id: doc.id, board: d.board, title: d.title || "",
          author: d.author || "", rank: d.rank || "",
          views: d.views || 0, comments: d.commentCount || 0,
          thumb: (Array.isArray(d.images) && d.images[0]) || "",
          hasImage: Array.isArray(d.images) && d.images.length > 0,
          createdAt: d.createdAt ? d.createdAt.toMillis() : 0,
        });
      });
      return res.json({ ok: true, items });
    }

    // ── 쓰기(로그인 필요) ────────────────────
    if (req.method !== "POST") return res.status(405).json({ ok: false, err: "method" });
    let me;
    try {
      me = await requireUser(req);
    } catch (e) {
      return res.status(401).json({ ok: false, err: e.message });
    }

    const b = req.body || {};
    const action = String(b.action || "write");

    if (action === "me") return res.json({ ok: true, me });

    if (action === "write") {
      const board = BOARDS.indexOf(String(b.board)) > -1 ? String(b.board) : "free";
      const title = String(b.title || "").trim();
      const body = String(b.body || "").trim();
      if (!title) return res.status(400).json({ ok: false, err: "제목을 입력해 주세요" });
      if (title.length > 100) return res.status(400).json({ ok: false, err: "제목은 100자 이내로 써주세요" });
      if (body.length > 5000) return res.status(400).json({ ok: false, err: "내용은 5000자 이내로 써주세요" });

      // 도배 방지: 최근 30초 내 재작성 차단
      const recent = await posts.where("authorUid", "==", me.uid).limit(20).get();
      let last = 0;
      recent.forEach((d) => {
        const t = d.data().createdAt;
        if (t && t.toMillis() > last) last = t.toMillis();
      });
      if (last && Date.now() - last < 30000) {
        return res.status(429).json({ ok: false, err: "잠시 후 다시 시도해 주세요 (연속 작성 제한)" });
      }

      const ref = await posts.add({
        board: board, title: title, body: body, images: [],
        author: me.nick, rank: me.rank, authorUid: me.uid,
        views: 0, commentCount: 0, deleted: false,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      let urls = [];
      try {
        urls = await saveImages(ref.id, b.images);
        if (urls.length) await ref.update({ images: urls });
      } catch (e) {
        console.error("[communityApi] image save failed", e);
      }
      return res.json({ ok: true, id: ref.id, images: urls.length });
    }

    if (action === "comment") {
      const postId = String(b.postId || "");
      const body = String(b.body || "").trim();
      if (!postId || !body) return res.status(400).json({ ok: false, err: "내용을 입력해 주세요" });
      if (body.length > 500) return res.status(400).json({ ok: false, err: "댓글은 500자 이내로 써주세요" });
      const pd = await posts.doc(postId).get();
      if (!pd.exists || pd.data().deleted === true) {
        return res.status(404).json({ ok: false, err: "글을 찾을 수 없습니다" });
      }
      await comments.add({
        postId: postId, body: body, author: me.nick, rank: me.rank, authorUid: me.uid,
        deleted: false, createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      await posts.doc(postId).update({ commentCount: admin.firestore.FieldValue.increment(1) });
      return res.json({ ok: true });
    }

    if (action === "delete") {
      const id = String(b.id || "");
      const doc = await posts.doc(id).get();
      if (!doc.exists) return res.status(404).json({ ok: false, err: "글을 찾을 수 없습니다" });
      if (doc.data().authorUid !== me.uid && !me.isGm) {
        return res.status(403).json({ ok: false, err: "본인 글만 삭제할 수 있습니다" });
      }
      await posts.doc(id).update({
        deleted: true, deletedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      return res.json({ ok: true, deleted: id });
    }

    if (action === "deleteComment") {
      const id = String(b.id || "");
      const doc = await comments.doc(id).get();
      if (!doc.exists) return res.status(404).json({ ok: false, err: "댓글을 찾을 수 없습니다" });
      const v = doc.data();
      if (v.authorUid !== me.uid && !me.isGm) {
        return res.status(403).json({ ok: false, err: "본인 댓글만 삭제할 수 있습니다" });
      }
      await comments.doc(id).update({ deleted: true });
      if (v.postId) {
        await posts.doc(v.postId)
          .update({ commentCount: admin.firestore.FieldValue.increment(-1) })
          .catch(() => {});
      }
      return res.json({ ok: true, deleted: id });
    }

    return res.status(400).json({ ok: false, err: "알 수 없는 요청" });
  } catch (e) {
    console.error("[communityApi]", e);
    return res.status(500).json({ ok: false, err: String(e) });
  }
});
