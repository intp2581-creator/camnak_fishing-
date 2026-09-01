// 📬 [운영자 알림] 새 문의·커뮤니티 글이 올라오면 메일로 알린다.
//   지금까지는 운영자가 직접 로그인해서 들어가 봐야만 새 글이 있는지 알 수 있었다.
//   답변이 늦으면 그대로 방치되므로, 올라오는 즉시 알린다.
//
//   ⚠️ 메일 설정(.env)이 없으면 조용히 넘어간다 — 알림 때문에 글쓰기가 실패하면 안 된다.
//      MAIL_USER : 보내는 지메일 주소
//      MAIL_PASS : 구글 '앱 비밀번호' 16자리 (일반 로그인 비밀번호 아님)
//      MAIL_TO   : 받을 주소 (없으면 MAIL_USER로 보냄)

const {onDocumentCreated} = require("firebase-functions/v2/firestore");
const admin = require("firebase-admin");
const nodemailer = require("nodemailer");

const HUB = "https://game.camnak.com";
const REGION = "us-central1";

function mailer() {
  const user = process.env.MAIL_USER;
  const pass = process.env.MAIL_PASS;
  if (!user || !pass) return null;
  return nodemailer.createTransport({
    service: "gmail",
    auth: {user, pass},
  });
}

function cut(s, n) {
  const t = String(s || "").replace(/\s+/g, " ").trim();
  return t.length > n ? t.slice(0, n) + "…" : t;
}

async function send(subject, lines, link) {
  const tx = mailer();
  if (!tx) {
    console.warn("[알림 건너뜀] MAIL_USER/MAIL_PASS 미설정");
    return;
  }
  const to = process.env.MAIL_TO || process.env.MAIL_USER;
  const body = lines.map((l) =>
    "<p style=\"margin:6px 0;font-size:15px;line-height:1.7\">" + l + "</p>").join("");
  try {
    await tx.sendMail({
      from: "\"캠피싱 KREFT\" <" + process.env.MAIL_USER + ">",
      to,
      subject,
      html:
        "<div style=\"font-family:'Malgun Gothic',sans-serif;max-width:560px\">" +
        body +
        "<p style=\"margin:20px 0 0\"><a href=\"" + link + "\" " +
        "style=\"display:inline-block;background:#0f766e;color:#fff;text-decoration:none;" +
        "padding:12px 22px;border-radius:10px;font-weight:700\">바로 확인하기</a></p>" +
        "<p style=\"margin:18px 0 0;font-size:12px;color:#8b9aa3\">" +
        "이 메일은 캠피싱 KREFT 운영자에게 자동으로 발송됩니다.</p></div>",
    });
    console.log("[알림 발송] " + subject);
  } catch (e) {
    // 메일이 실패해도 원래 동작(문의 접수·글쓰기)에는 영향을 주지 않는다.
    console.error("[알림 실패]", e.message);
  }
}

// ── 1:1 문의가 새로 접수됨 ─────────────────────────
exports.notifyTicket = onDocumentCreated(
  {region: REGION, document: "support_tickets/{id}"},
  async (event) => {
    const v = event.data && event.data.data();
    if (!v) return;
    const CAT = {prize: "이벤트 당첨", payment: "결제", refund: "환불",
      account: "계정", game: "게임 이용", etc: "기타"};
    const cat = CAT[v.category] || "기타";
    await send(
      "[고객지원] " + cat + " · " + cut(v.title, 40),
      ["<b>" + cat + "</b> 문의가 접수되었습니다.",
        "작성자 : <b>" + (v.nick || "-") + "</b>",
        "제목 : " + cut(v.title, 80),
        "내용 : " + cut(v.body, 200)],
      HUB + "/support.html");
  });

// ── 문의자가 답변을 기다리다 글을 더 남김 ───────────
//   운영자 답변은 알릴 필요가 없으므로 byGm이면 건너뛴다.
exports.notifyTicketReply = onDocumentCreated(
  {region: REGION, document: "support_tickets/{id}/replies/{rid}"},
  async (event) => {
    const v = event.data && event.data.data();
    if (!v || v.byGm === true) return;
    let title = "";
    try {
      const t = await admin.firestore()
        .collection("support_tickets").doc(event.params.id).get();
      title = t.exists ? (t.data().title || "") : "";
    } catch (e) { /* 제목을 못 읽어도 알림은 보낸다 */ }
    await send(
      "[고객지원] 추가 문의 · " + cut(title, 40),
      ["문의자가 <b>글을 더 남겼습니다.</b>",
        "작성자 : <b>" + (v.nick || "-") + "</b>",
        "문의 : " + cut(title, 80),
        "내용 : " + cut(v.body, 200)],
      HUB + "/support.html");
  });

// ── 커뮤니티 새 글 ─────────────────────────────────
exports.notifyPost = onDocumentCreated(
  {region: REGION, document: "community_posts/{id}"},
  async (event) => {
    const v = event.data && event.data.data();
    if (!v || v.deleted === true) return;
    await send(
      "[커뮤니티] " + (v.board || "글") + " · " + cut(v.title, 40),
      ["커뮤니티에 새 글이 올라왔습니다.",
        "게시판 : <b>" + (v.board || "-") + "</b>",
        "작성자 : <b>" + (v.author || "-") + "</b>",
        "제목 : " + cut(v.title, 80),
        "내용 : " + cut(v.body, 200)],
      HUB + "/community.html");
  });
