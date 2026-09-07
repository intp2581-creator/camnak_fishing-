// 💳 [자체 결제] 포트원 V2 — kreft.co.kr 단일 도메인에서 상품선택→결제→지급까지.
//   아임웹을 거치지 않으므로 지급이 폴링(최대 1분)이 아니라 '즉시'다.
//   설계 문서: 문서/설계_자체결제_kreft.md
//
// ⚠️ 절대 원칙
//   1. 금액은 '서버'에서만 정한다. 클라이언트가 보낸 금액은 참고도 하지 않는다.
//   2. 결제 후 포트원 API로 '실제 결제된 금액'을 다시 조회해 대조한다. 다르면 즉시 취소.
//   3. 같은 주문은 두 번 지급하지 않는다(orders 문서 상태로 멱등 보장).
//   4. 인벤토리 지급은 이 서버만 한다. 클라이언트는 못 건드린다.

const {onRequest} = require("firebase-functions/v2/https");
const admin = require("firebase-admin");
const crypto = require("crypto");

const PORTONE_API = "https://api.portone.io";
const STORE_ID = "store-e9532395-b849-4a65-9ef8-957c94000051";

// 🚧 [안전장치] 현재 포트원 '테스트 채널'이라 결제해도 돈이 안 나간다.
//    이 상태로 일반 유저에게 열면 공짜로 아이템을 가져갈 수 있으므로 GM만 허용한다.
//    ⚠️ 실연동 PG 심사가 끝나고 실채널로 바꾼 뒤에만 false로 내릴 것. (2026-09-01)
const TEST_MODE_GM_ONLY = true;

// 📦 판매 상품 — 가격의 '유일한 근거'. 홈페이지·게임 표시가 달라도 이 값이 기준이다.
//   limitType: ONCE=계정당 1개 · STACK=수량 누적
const PRODUCTS = {
  "ticket_1h":   {name: "낚시 1시간 이용권", price: 1100,  limitType: "STACK"},
  "ticket_arena":{name: "아레나 입장권",     price: 1100,  limitType: "STACK"},
  // 📦 장착형(스킨·뱃지·휘장)은 '상자'로 지급한다 — 열어야 실제로 손에 들어온다.
  //   약관이 "7일 이내 장착하지 않으신 상태면 전액 환불"인데, 낱개로 주면
  //   자동장착이 알아서 입혀버려 유저가 '미장착'을 유지할 수 없었다(2026-09-07).
  //   상자는 열었냐 아니냐로 딱 갈린다. ⛔ 약관 문구는 승인 문안이라 못 고친다.
  "skin_novice": {name: "하수 조사",        price: 2200, limitType: "ONCE", reqLevel: 10,  reqRank: "하수",
    boxName: "하수 조사 상자", boxIcon: "item_box_cash.png",
    boxMsg: "눌러서 열면 스킨을 받습니다.\n열기 전에는 환불하실 수 있어요.",
    bundle: [{name: "하수 조사", qty: 1, cash: true, category: "SKIN", type: "SKIN",
      stats: {P: 20, C: 20, S: 20}, icon: "../images/skin_novice.jpg"}]},
  "skin_mid": {name: "중수 조사",        price: 5500, limitType: "ONCE", reqLevel: 30,  reqRank: "중수",
    boxName: "중수 조사 상자", boxIcon: "item_box_cash.png",
    boxMsg: "눌러서 열면 스킨을 받습니다.\n열기 전에는 환불하실 수 있어요.",
    bundle: [{name: "중수 조사", qty: 1, cash: true, category: "SKIN", type: "SKIN",
      stats: {P: 50, C: 50, S: 50}, icon: "../images/skin_intermediate.jpg"}]},
  "skin_expert": {name: "고수 조사",        price: 11000, limitType: "ONCE", reqLevel: 50,  reqRank: "고수",
    boxName: "고수 조사 상자", boxIcon: "item_box_cash.png",
    boxMsg: "눌러서 열면 스킨을 받습니다.\n열기 전에는 환불하실 수 있어요.",
    bundle: [{name: "고수 조사", qty: 1, cash: true, category: "SKIN", type: "SKIN",
      stats: {P: 100, C: 100, S: 100}, icon: "../images/skin_expert.jpg"}]},
  "skin_pro": {name: "프로 조사",        price: 22000, limitType: "ONCE", reqLevel: 70,  reqRank: "프로",
    boxName: "프로 조사 상자", boxIcon: "item_box_cash.png",
    boxMsg: "눌러서 열면 스킨을 받습니다.\n열기 전에는 환불하실 수 있어요.",
    bundle: [{name: "프로 조사", qty: 1, cash: true, category: "SKIN", type: "SKIN",
      stats: {P: 200, C: 200, S: 200}, icon: "../images/skin_pro.jpg"}]},
  "skin_master": {name: "마스터 조사",       price: 55000, limitType: "ONCE", reqLevel: 100, reqRank: "마스터",
    boxName: "마스터 조사 상자", boxIcon: "item_box_cash.png",
    boxMsg: "눌러서 열면 스킨을 받습니다.\n열기 전에는 환불하실 수 있어요.",
    bundle: [{name: "마스터 조사", qty: 1, cash: true, category: "SKIN", type: "SKIN",
      stats: {P: 300, C: 300, S: 300}, icon: "../images/skin_master.jpg"}]},
  "badge_1": {name: "캠피싱 뱃지",       price: 2200, limitType: "ONCE", reqLevel: 10,
    boxName: "캠피싱 뱃지 상자", boxIcon: "item_box_cash.png",
    boxMsg: "눌러서 열면 아이템을 받습니다.\n열기 전에는 환불하실 수 있어요.",
    bundle: [{name: "캠피싱 뱃지", qty: 1, cash: true, category: "COMMON", type: "ETC",
      stats: {P: 10, C: 10, S: 10}, icon: "item_badge_1.png"}]},
  "badge_2": {name: "캠피싱 휘장",       price: 5500, limitType: "ONCE", reqLevel: 30,
    boxName: "캠피싱 휘장 상자", boxIcon: "item_box_cash.png",
    boxMsg: "눌러서 열면 아이템을 받습니다.\n열기 전에는 환불하실 수 있어요.",
    bundle: [{name: "캠피싱 휘장", qty: 1, cash: true, category: "COMMON", type: "ETC",
      stats: {P: 30, C: 30, S: 30}, icon: "item_badge_2.png"}]},
  "badge_3": {name: "KREFT 정예 휘장",  price: 11000, limitType: "ONCE", reqLevel: 50,
    boxName: "KREFT 정예 휘장 상자", boxIcon: "item_box_cash.png",
    boxMsg: "눌러서 열면 아이템을 받습니다.\n열기 전에는 환불하실 수 있어요.",
    bundle: [{name: "KREFT 정예 휘장", qty: 1, cash: true, category: "COMMON", type: "ETC",
      stats: {P: 50, C: 50, S: 50}, icon: "item_badge_3.png"}]},
  // 🎁 묶음 상품 — bundle 이 있으면 그 목록을 통째로 지급한다(단품 name 은 안 쓴다).
  //    아임웹 쪽 packageDatabase(index.js)와 구성이 같아야 한다.
  "growth_pack": {
    name: "KREFT 성장패키지", price: 5500, limitType: "STACK", maxQty: 1,
    // 📦 상자로 지급한다 — 열어야 내용물이 풀린다.
    //    낱개로 주면 "물약 하나 썼는데 환불되나요?"가 생긴다. 상자는 열었냐 아니냐로 딱 갈린다.
    boxName: "성장패키지 상자", boxIcon: "item_box_growth.png",
    boxMsg: "성장에 필요한 것을 한 번에 담았습니다.\n눌러서 열어보세요.",
    bundle: [
      {name: "경험치 물약", qty: 10, category: "BOOST", type: "BOOST", boost: "exp",
        icon: "item_potion_exp.png",
        desc: "마시면 10분 동안 경험치가 2배로 들어와요.\n(아레나에서는 적용되지 않아요)"},
      {name: "KREFT 2배 카드", qty: 10, category: "BOOST", type: "BOOST", boost: "pts",
        icon: "item_card_kreft.png",
        desc: "사용하면 10분 동안 KREFT가 2배로 들어와요.\n(아레나에서는 적용되지 않아요)"},
      {name: "능력치 엠블럼", qty: 1, category: "COMMON", type: "EVENT",
        icon: "item_emblem_boost.png", stats: {P: 10, C: 10, S: 10},
        secLeft: 3600, active: false,
        desc: "눌러서 활성화하면 1시간 동안 힘·컨트롤·감도가 각각 +10 올라가요.\n낚시터에 있는 동안에만 시간이 줄어요. (휘장과 함께 적용)"},
      {name: "낚시 1시간 이용권", qty: 1, category: "TICKET", type: "ETC",
        icon: "item_ticket_1h.png",
        desc: "낚시 시간을 1시간 추가해주는 이용권이에요.\n(계정당 1일 1회 사용 가능)"},
      {name: "아레나 입장권", qty: 1, category: "TICKET", type: "ETC",
        icon: "arena_ticket.png",
        desc: "아레나 무료 입장을 다 쓴 뒤 하루 1회 더 참가할 수 있어요."},
    ],
  },
};

const cors = (res) => {
  res.set("Access-Control-Allow-Origin", "*");
  res.set("Access-Control-Allow-Headers", "Content-Type, Authorization");
  res.set("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
};

// 🔐 로그인한 본인인지 확인 — 남의 계정으로 결제/조회 못 하게
async function requireUser(req) {
  const m = String(req.get("Authorization") || "").match(/^Bearer\s+(.+)$/i);
  if (!m) throw new Error("로그인이 필요합니다");
  const decoded = await admin.auth().verifyIdToken(m[1]);
  return {uid: decoded.uid, email: (decoded.email || "").toLowerCase()};
}

// 🚧 테스트 채널 동안은 '운영자' 또는 '결제 허용' 표시가 있는 계정만 결제 가능.
//
//   canPay 를 따로 둔 이유: PG 심사자에게 계정을 줘야 하는데,
//   isGm 을 주면 관리자 화면(공지 작성·환불·주문 조회)까지 열린다.
//   canPay 만 켜면 결제창까지는 가되 관리자 화면은 못 들어간다.
//
//   ⚠️ 테스트 채널이라 결제해도 돈이 안 나간다 → 이 표시를 켠 계정은
//      공짜로 아이템을 가져갈 수 있다. 심사가 끝나면 반드시 끈다.
//      (tools/set_canpay.py 로 켜고 끈다)
async function requirePayable(user) {
  if (!TEST_MODE_GM_ONLY) return;
  const d = await admin.firestore().collection("users").doc(user.uid).get();
  const v = d.exists ? d.data() : {};
  if (v.isGm !== true && v.canPay !== true) {
    throw new Error("결제 준비 중입니다. 잠시 후 다시 이용해 주세요.");
  }
}

// 🚫 이 상품을 이미 가지고 있는가 — '열지 않은 상자'도 보유로 친다.
//   스킨·뱃지는 상자로 지급되므로, 상자만 보고 있으면 '아직 없다'가 되어
//   같은 상품을 또 살 수 있게 된다(2026-09-07 상자 도입으로 생긴 구멍).
function alreadyOwned(inv, p, bought, key) {
  // 🧾 산 적이 있으면 팔았어도 다시 못 산다 — 계정당 1회이기 때문.
  //    (팔고 재구매가 되면 현금 → KREFT 환전 통로가 열린다)
  if (bought && key && bought[key] === true) return true;
  const boxName = p.boxName || "";
  return (inv || []).some((i) => {
    if (!i) return false;
    if (i.name === p.name) return true;                 // 열어서 손에 든 것
    if (boxName && i.name === boxName) return true;     // 아직 안 연 상자
    // 상자 안에 그 아이템이 들어 있나(상자 이름을 바꿔도 잡히게)
    return Array.isArray(i.gift) && i.gift.some((g) => g && g.name === p.name);
  });
}

function portoneHeaders() {
  const secret = process.env.PORTONE_API_SECRET;
  if (!secret) throw new Error("PORTONE_API_SECRET 미설정");
  return {Authorization: "PortOne " + secret, "Content-Type": "application/json"};
}

// ═══════════════════════════════════════════════════════════
// ① 결제 준비 — 주문번호와 '서버가 정한 금액'을 먼저 기록해 둔다.
//    클라이언트는 itemKey만 보낸다(금액은 보내도 무시).
// ═══════════════════════════════════════════════════════════
exports.payPrepare = onRequest({region: "us-central1", cors: true}, async (req, res) => {
  cors(res);
  if (req.method === "OPTIONS") return res.status(204).send("");
  try {
    const user = await requireUser(req);
    await requirePayable(user);            // 🚧 테스트 채널 동안 GM만
    const itemKey = String((req.body || {}).itemKey || "");
    const qty = Math.max(1, Math.min(10, parseInt((req.body || {}).qty || "1", 10)));
    const p = PRODUCTS[itemKey];
    if (!p) return res.status(400).json({ok: false, err: "없는 상품입니다"});
    if (p.limitType === "ONCE" && qty !== 1) {
      return res.status(400).json({ok: false, err: "이 상품은 1개만 구매할 수 있어요"});
    }

    const db = admin.firestore();
    // 🚫 ONCE 상품 중복 구매 차단 — 결제 전에 미리 막아 환불 사태를 줄인다.
    if (p.limitType === "ONCE") {
      const u = await db.collection("users").doc(user.uid).get();
      const inv = (u.data() || {}).inventory || [];
      const bought = (u.data() || {}).cashBought || {};
      if (alreadyOwned(inv, p, bought, key)) {
        return res.status(400).json({ok: false, err: "이미 보유한 상품입니다"});
      }
    }

    // 🔢 주문당 수량 상한 — 프론트를 고쳐 보내도 여기서 막는다.
    if (p.maxQty && qty > p.maxQty) {
      return res.status(400).json({ok: false, err: "이 상품은 한 번에 " + p.maxQty + "개까지 구매할 수 있습니다"});
    }

    const orderId = "KREFT" + Date.now() + Math.floor(Math.random() * 900 + 100);
    const amount = p.price * qty;              // ⭐ 금액은 여기서만 계산
    await db.collection("orders").doc(orderId).set({
      uid: user.uid, email: user.email,
      itemKey, itemName: p.name, qty, amount,
      status: "ready",
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return res.json({ok: true, orderId, amount, itemName: p.name, storeId: STORE_ID});
  } catch (e) {
    return res.status(401).json({ok: false, err: String(e.message || e)});
  }
});

// ═══════════════════════════════════════════════════════════
// ② 결제 검증 + 지급 — 이 함수가 보안의 핵심.
//    포트원에서 '실제 결제된 금액'을 조회해 우리가 기록한 금액과 대조한다.
// ═══════════════════════════════════════════════════════════
exports.payVerify = onRequest({region: "us-central1", cors: true}, async (req, res) => {
  cors(res);
  if (req.method === "OPTIONS") return res.status(204).send("");
  const db = admin.firestore();
  try {
    const user = await requireUser(req);
    await requirePayable(user);            // 🚧 테스트 채널 동안 GM만
    const orderId = String((req.body || {}).orderId || "");
    if (!orderId) return res.status(400).json({ok: false, err: "주문번호 없음"});

    const out = await settleOrder(db, orderId, {uid: user.uid});
    if (!out.ok) return res.status(out.code || 400).json({ok: false, err: out.err});
    return res.json(out.already
      ? {ok: true, already: true}
      : {ok: true, itemName: out.itemName, qty: out.qty});
  } catch (e) {
    return res.status(500).json({ok: false, err: String(e.message || e)});
  }
});

// ═══════════════════════════════════════════════════════════
// 🧮 [공용] 주문 하나를 검증하고 지급까지 끝낸다.
//    payVerify(브라우저)와 payWebhook(포트원) 둘 다 이것을 쓴다 —
//    두 벌로 두면 언젠가 어긋나고, 어긋나면 돈이 안 맞는다.
//
//    opts.uid 를 주면 '본인 주문인지'까지 본다(브라우저 호출).
//    웹훅은 포트원이 부르는 것이라 uid 가 없다 — 서명으로 이미 신원을 확인했다.
// ═══════════════════════════════════════════════════════════
async function settleOrder(db, orderId, opts) {
  const o = opts || {};
  const ref = db.collection("orders").doc(orderId);
  const snap = await ref.get();
  if (!snap.exists) return {ok: false, code: 404, err: "주문을 찾을 수 없습니다"};

  const order = snap.data();
  if (o.uid && order.uid !== o.uid) {
    return {ok: false, code: 403, err: "본인 주문이 아닙니다"};
  }
  // 이미 지급했으면 다시 하지 않는다. 웹훅과 브라우저가 동시에 와도 한 번만 나간다.
  if (order.status === "paid") return {ok: true, already: true};

  // 🔎 포트원에서 '실제 결제된 내역'을 다시 조회한다. 화면이 하는 말은 믿지 않는다.
  const r = await fetch(PORTONE_API + "/payments/" + encodeURIComponent(orderId),
      {headers: portoneHeaders()});
  if (!r.ok) {
    await ref.update({status: "failed", note: "조회실패 " + r.status});
    return {ok: false, code: 400, err: "결제 조회 실패"};
  }
  const pay = await r.json();
  const paidAmount = ((pay.amount || {}).total) || 0;
  const paidStatus = pay.status;

  // ⭐ 금액·상태가 하나라도 어긋나면 지급하지 않고 즉시 취소한다.
  if (paidStatus !== "PAID" || paidAmount !== order.amount) {
    await ref.update({status: "failed", paidAmount, paidStatus,
      note: "금액/상태 불일치 (기대 " + order.amount + ")"});
    try {
      await fetch(PORTONE_API + "/payments/" + encodeURIComponent(orderId) + "/cancel",
          {method: "POST", headers: portoneHeaders(),
            body: JSON.stringify({reason: "금액 불일치 - 자동 취소"})});
    } catch (_) {}
    return {ok: false, code: 400, err: "결제 금액이 일치하지 않아 취소되었습니다"};
  }

  const granted = await grantItem(db, order, orderId);
  await ref.update({
    status: "paid", paidAmount, paidStatus,
    pgProvider: (pay.channel || {}).pgProvider || "",
    method: ((pay.method || {}).type) || "",
    granted, grantedAt: admin.firestore.FieldValue.serverTimestamp(),
  });
  return {ok: true, itemName: order.itemName, qty: order.qty};
}

// ═══════════════════════════════════════════════════════════
// 🔔 [결제 웹훅] 포트원이 결제 결과를 서버로 직접 알려준다.
//
//    왜 필요한가: 지금은 브라우저가 payVerify 를 불러야 지급된다.
//    결제 직후 창을 닫거나 인터넷이 끊기면 '돈은 나갔는데 아이템이 없는' 상태가 된다.
//    웹훅은 그 구멍을 막는다 — 유저가 무엇을 하든 서버가 결과를 받는다.
//
//    ⚠️ 아무나 부를 수 있는 주소이므로 반드시 '서명'을 확인한다.
//       포트원 콘솔 → 결제연동 → 웹훅에서 주소를 등록하고,
//       거기서 준 시크릿을 functions/.env 의 PORTONE_WEBHOOK_SECRET 에 넣는다.
// ═══════════════════════════════════════════════════════════

// 📝 웹훅이 온 기록. 문제가 생겼을 때 '왔는데 처리를 못 한 건지'를 봐야 한다.
async function logHook(db, id, data) {
  try {
    await db.collection("webhook_logs").doc(id || String(Date.now())).set(
        Object.assign({at: admin.firestore.FieldValue.serverTimestamp()}, data),
        {merge: true});
  } catch (_) {}
}

// 🔐 서명 확인 — 포트원은 Standard Webhooks 규격을 쓴다.
//    서명 대상은 "{webhook-id}.{webhook-timestamp}.{본문}" 이고,
//    시크릿은 'whsec_' 뒤가 base64 다.
function verifyHookSignature(req, rawBody) {
  const secretRaw = process.env.PORTONE_WEBHOOK_SECRET || "";
  if (!secretRaw) return {ok: false, why: "PORTONE_WEBHOOK_SECRET 미설정"};

  const id = req.get("webhook-id") || "";
  const ts = req.get("webhook-timestamp") || "";
  const sigHeader = req.get("webhook-signature") || "";
  if (!id || !ts || !sigHeader) return {ok: false, why: "서명 헤더 없음"};

  // ⏱️ 너무 오래된 요청은 받지 않는다(가로채 다시 보내는 것을 막는다).
  const age = Math.abs(Date.now() / 1000 - Number(ts));
  if (!Number.isFinite(age) || age > 300) return {ok: false, why: "시각이 너무 벌어짐"};

  const key = Buffer.from(secretRaw.replace(/^whsec_/, ""), "base64");
  const expected = crypto.createHmac("sha256", key)
      .update(id + "." + ts + "." + rawBody).digest("base64");

  // 헤더에 여러 개가 들어올 수 있다: "v1,xxx v1,yyy"
  const given = sigHeader.split(" ")
      .map((v) => v.includes(",") ? v.split(",")[1] : v)
      .filter(Boolean);
  const eb = Buffer.from(expected);
  const hit = given.some((g) => {
    const gb = Buffer.from(g);
    return gb.length === eb.length && crypto.timingSafeEqual(gb, eb);
  });
  return hit ? {ok: true, id} : {ok: false, why: "서명 불일치"};
}

exports.payWebhook = onRequest({region: "us-central1"}, async (req, res) => {
  if (req.method !== "POST") return res.status(405).send("method");
  const db = admin.firestore();

  // rawBody 로 서명을 확인한다 — JSON 으로 다시 만들면 글자가 달라져 서명이 안 맞는다.
  const raw = req.rawBody ? req.rawBody.toString("utf8") : JSON.stringify(req.body || {});
  const v = verifyHookSignature(req, raw);
  if (!v.ok) {
    console.error("[payWebhook] 서명 실패:", v.why);
    await logHook(db, req.get("webhook-id"), {ok: false, why: v.why, raw: raw.slice(0, 500)});
    return res.status(401).send("bad signature");
  }

  let body = {};
  try { body = JSON.parse(raw); } catch (_) {}
  const type = String(body.type || "");
  const orderId = String(((body.data || {}).paymentId) || "");

  // ⚠️ 포트원은 200 을 못 받으면 계속 재시도한다.
  //    우리가 처리 못 하는 종류라도 200 으로 받아준다(재시도가 쌓이면 더 나쁘다).
  if (!orderId) {
    await logHook(db, v.id, {ok: true, type, note: "paymentId 없음"});
    return res.status(200).send("ok");
  }

  try {
    if (type === "Transaction.Paid") {
      const out = await settleOrder(db, orderId);
      await logHook(db, v.id, {ok: true, type, orderId,
        result: out.already ? "이미 지급됨" : (out.ok ? "지급" : ("실패: " + out.err))});
    } else if (type === "Transaction.Cancelled" || type === "Transaction.PartialCancelled") {
      // 환불·취소 — 아이템 회수는 사람이 판단해야 하므로 여기서는 '기록만' 한다.
      await db.collection("orders").doc(orderId).set({
        status: type === "Transaction.Cancelled" ? "canceled" : "partial_canceled",
        canceledAt: admin.firestore.FieldValue.serverTimestamp(),
      }, {merge: true});
      await logHook(db, v.id, {ok: true, type, orderId, result: "취소 기록"});
    } else {
      await logHook(db, v.id, {ok: true, type, orderId, result: "처리 대상 아님"});
    }
  } catch (e) {
    console.error("[payWebhook]", e);
    await logHook(db, v.id, {ok: false, type, orderId, why: String(e.message || e)});
    // 우리 쪽 일시 오류이므로 재시도를 받는다.
    return res.status(500).send("error");
  }
  return res.status(200).send("ok");
});

// 🎁 인벤토리 지급 — 서버만 수행. STACK은 수량 누적, ONCE는 1개.
async function grantItem(db, order, orderId) {
  const p = PRODUCTS[order.itemKey];
  if (!p) return false;
  const uref = db.collection("users").doc(order.uid);
  return db.runTransaction(async (tx) => {
    const u = await tx.get(uref);
    const inv = ((u.data() || {}).inventory || []).slice();
    const bought = (u.data() || {}).cashBought || {};
    // 📦 묶음 상품 — 낱개가 아니라 '상자' 하나로 넣는다. 유저가 눌러 열면 내용물이 풀린다.
    //    gid 에 주문번호를 넣어 두면, 환불 문의 때 '이 주문의 상자가 아직 있나'를 바로 볼 수 있다.
    if (Array.isArray(p.bundle)) {
      // 🚫 계정당 1개 상품은 여기서도 막는다. 예전엔 이 분기가 그냥 return 해서
      //    아래 ONCE 검사에 도달하지 못했다(상자 도입으로 생긴 구멍).
      if (p.limitType === "ONCE" &&
          alreadyOwned(inv, p, bought, order.itemKey)) return false;
      const n = Math.max(1, Number(order.qty || 1));
      for (let k = 0; k < n; k++) {
        inv.push({
          name: p.boxName || p.name,
          category: "BOX", type: "BOX", quantity: 1, cash: true,
          icon: p.boxIcon || "item_box_gift.png",
          gid: orderId + (n > 1 ? "-" + (k + 1) : ""),
          giftTitle: p.name,
          giftMsg: p.boxMsg || "",
          gift: p.bundle.map((b) => Object.assign({}, b, {quantity: b.qty || 1})),
          desc: p.name + "\n" + (p.boxMsg || "") + "\n\n눌러서 열어보세요.",
        });
      }
      tx.update(uref, {inventory: inv});
      // 🧾 계정당 1회 상품은 '샀다'를 남긴다(팔아도 재구매 불가).
      if (p.limitType === "ONCE") {
        tx.set(uref, {cashBought: {[order.itemKey]: true}}, {merge: true});
      }
      return true;
    }
    const idx = inv.findIndex((i) => i && i.name === p.name);
    if (p.limitType === "ONCE") {
      if (alreadyOwned(inv, p, bought, order.itemKey)) return false;  // 이미 보유·구매
      inv.push({name: p.name, quantity: 1, cash: true});
      tx.set(uref, {cashBought: {[order.itemKey]: true}}, {merge: true});
    } else if (idx >= 0) {
      const q = Number(inv[idx].quantity || 0) + order.qty;
      inv[idx] = Object.assign({}, inv[idx], {quantity: q});
    } else {
      inv.push({name: p.name, quantity: order.qty, cash: true});
    }
    tx.update(uref, {inventory: inv});
    return true;
  });
}

// ═══════════════════════════════════════════════════════════
// ③ 내 주문 내역
// ═══════════════════════════════════════════════════════════
// ═══════════════════════════════════════════════════════════
// 💸 [환불] 관리자만. 포트원에 취소를 넣고 우리 주문 기록도 함께 바꾼다.
//
//    콘솔에서만 환불하면 우리 orders 는 'paid' 인 채로 남는다 →
//    구매내역에는 결제완료로 보이고, CS 때 서로 다른 말을 하게 된다.
//
//    아이템 회수(reclaim)는 선택이다.
//      · 상자를 안 열었으면 gid 로 정확히 찾아 뺄 수 있다.
//      · 이미 열었거나 써버렸으면 뺄 것이 없다 — 그때는 '못 뺐다'고 알려준다.
// ═══════════════════════════════════════════════════════════
async function requireGm(req) {
  const user = await requireUser(req);
  const d = await admin.firestore().collection("users").doc(user.uid).get();
  if (!d.exists || d.data().isGm !== true) throw new Error("관리자만 사용할 수 있습니다");
  return user;
}

// 🔙 지급했던 것을 되돌린다. 되돌린 목록을 문자열로 반환(못 되돌린 것도 적는다).
async function reclaimItems(db, order, orderId) {
  const p = PRODUCTS[order.itemKey];
  if (!p) return "상품 정보 없음";

  const uref = db.collection("users").doc(order.uid);
  return await db.runTransaction(async (tx) => {
    const snap = await tx.get(uref);
    if (!snap.exists) return "계정 없음";
    const inv = Array.from(snap.data().inventory || []);
    const took = [];
    const left = [];

    if (Array.isArray(p.bundle)) {
      // 📦 상자 — gid 로 이 주문의 상자만 정확히 찾는다. 안 열었으면 그대로 있다.
      const before = inv.length;
      for (let i = inv.length - 1; i >= 0; i--) {
        const g = String((inv[i] || {}).gid || "");
        if (g === orderId || g.indexOf(orderId + "-") === 0) inv.splice(i, 1);
      }
      const n = before - inv.length;
      if (n > 0) took.push((p.boxName || p.name) + " " + n + "개");
      else left.push((p.boxName || p.name) + " (이미 열었거나 없음)");
    } else {
      const want = Math.max(1, Number(order.qty || 1));
      const i = inv.findIndex((it) => it && it.name === p.name);
      if (i < 0) {
        left.push(p.name + " (없음 — 이미 사용)");
      } else if (p.limitType === "ONCE") {
        inv.splice(i, 1);
        took.push(p.name);
      } else {
        const have = Number(inv[i].quantity || 0);
        const back = Math.min(have, want);
        if (back >= have) inv.splice(i, 1);
        else inv[i] = Object.assign({}, inv[i], {quantity: have - back});
        took.push(p.name + " " + back + "개");
        if (back < want) left.push(p.name + " " + (want - back) + "개 (이미 사용)");
      }
    }

    tx.update(uref, {inventory: inv});
    return (took.length ? "회수: " + took.join(", ") : "회수한 것 없음")
         + (left.length ? " / 못 회수: " + left.join(", ") : "");
  });
}

exports.payRefund = onRequest({region: "us-central1", cors: true}, async (req, res) => {
  cors(res);
  if (req.method === "OPTIONS") return res.status(204).send("");
  const db = admin.firestore();
  try {
    await requireGm(req);
    const b = req.body || {};
    const orderId = String(b.orderId || "").trim();
    const reason = String(b.reason || "고객 요청").trim().slice(0, 200);
    const reclaim = b.reclaim === true;
    if (!orderId) return res.status(400).json({ok: false, err: "주문번호 없음"});

    const ref = db.collection("orders").doc(orderId);
    const snap = await ref.get();
    if (!snap.exists) return res.status(404).json({ok: false, err: "주문을 찾을 수 없습니다"});
    const order = snap.data();
    if (order.status === "refunded") return res.json({ok: true, already: true});
    if (order.status !== "paid") {
      return res.status(400).json({ok: false, err: "결제완료 상태만 환불할 수 있습니다 (현재 " + order.status + ")"});
    }

    // ① 포트원에 취소를 넣는다. 여기서 실패하면 아무것도 바꾸지 않는다.
    const r = await fetch(PORTONE_API + "/payments/" + encodeURIComponent(orderId) + "/cancel",
        {method: "POST", headers: portoneHeaders(), body: JSON.stringify({reason})});
    const out = await r.json().catch(() => ({}));
    if (!r.ok) {
      return res.status(400).json({ok: false,
        err: "포트원 취소 실패 (" + r.status + ") " + JSON.stringify(out).slice(0, 200)});
    }

    // ② 아이템 회수 — 선택이다. 실패해도 환불 자체는 되돌리지 않는다(돈이 우선).
    let note = "회수 안 함";
    if (reclaim) {
      try { note = await reclaimItems(db, order, orderId); } catch (e) {
        note = "회수 실패: " + String(e.message || e);
      }
    }

    // 🧾 계정당 1회 상품이면 '샀다' 기록을 지운다.
    //   안 지우면 환불받고도 영영 다시 살 수 없다(구매 이력으로 막고 있으므로).
    const prod = PRODUCTS[order.itemKey];
    if (prod && prod.limitType === "ONCE") {
      try {
        await db.collection("users").doc(order.uid).set(
            {cashBought: {[order.itemKey]: admin.firestore.FieldValue.delete()}},
            {merge: true});
      } catch (e) { /* 기록 삭제 실패는 환불을 막지 않는다 */ }
    }

    await ref.update({
      status: "refunded", refundReason: reason, refundNote: note,
      refundedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return res.json({ok: true, note});
  } catch (e) {
    return res.status(400).json({ok: false, err: String(e.message || e)});
  }
});

// 🔎 [관리자] 주문 찾기 — 이메일·주문번호·상태로.
exports.adminOrders = onRequest({region: "us-central1", cors: true}, async (req, res) => {
  cors(res);
  if (req.method === "OPTIONS") return res.status(204).send("");
  try {
    await requireGm(req);
    const db = admin.firestore();
    const q = String(req.query.q || "").trim();

    let rows = [];
    if (q && q.indexOf("KREFT") === 0) {          // 주문번호로 바로
      const d = await db.collection("orders").doc(q).get();
      if (d.exists) rows = [Object.assign({orderId: d.id}, d.data())];
    } else {
      let ref = db.collection("orders");
      if (q) ref = ref.where("email", "==", q.toLowerCase());
      const snap = await ref.orderBy("createdAt", "desc").limit(50).get();
      snap.forEach((d) => rows.push(Object.assign({orderId: d.id}, d.data())));
    }

    return res.json({ok: true, rows: rows.map((v) => ({
      orderId: v.orderId, email: v.email || "", itemKey: v.itemKey || "",
      itemName: v.itemName || "", qty: v.qty || 1, amount: v.amount || 0,
      status: v.status || "", method: v.method || "",
      refundNote: v.refundNote || "",
      createdAt: v.createdAt ? v.createdAt.toMillis() : 0,
    }))});
  } catch (e) {
    return res.status(400).json({ok: false, err: String(e.message || e)});
  }
});

exports.myOrders = onRequest({region: "us-central1", cors: true}, async (req, res) => {
  cors(res);
  if (req.method === "OPTIONS") return res.status(204).send("");
  try {
    const user = await requireUser(req);
    const s = await admin.firestore().collection("orders")
        .where("uid", "==", user.uid).orderBy("createdAt", "desc").limit(50).get();
    const rows = [];
    s.forEach((d) => {
      const v = d.data();
      rows.push({orderId: d.id, itemName: v.itemName, qty: v.qty, amount: v.amount,
        status: v.status, method: v.method || "",
        createdAt: v.createdAt ? v.createdAt.toMillis() : 0});
    });
    return res.json({ok: true, rows});
  } catch (e) {
    return res.status(401).json({ok: false, err: String(e.message || e)});
  }
});

exports.PRODUCTS = PRODUCTS;
