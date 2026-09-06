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
  "skin_novice": {name: "하수 조사",   price: 2200,  limitType: "ONCE", reqLevel: 10,  reqRank: "하수"},
  "skin_mid":    {name: "중수 조사",   price: 5500,  limitType: "ONCE", reqLevel: 30,  reqRank: "중수"},
  "skin_expert": {name: "고수 조사",   price: 11000, limitType: "ONCE", reqLevel: 50,  reqRank: "고수"},
  "skin_pro":    {name: "프로 조사",   price: 22000, limitType: "ONCE", reqLevel: 70,  reqRank: "프로"},
  "skin_master": {name: "마스터 조사", price: 55000, limitType: "ONCE", reqLevel: 100, reqRank: "마스터"},
  "badge_1":     {name: "캠피싱 뱃지",      price: 2200,  limitType: "ONCE", reqLevel: 10},
  "badge_2":     {name: "캠피싱 휘장",      price: 5500,  limitType: "ONCE", reqLevel: 30},
  "badge_3":     {name: "KREFT 정예 휘장", price: 11000, limitType: "ONCE", reqLevel: 50},
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

// 🚧 테스트 채널 동안은 GM 계정만 결제 가능
async function requirePayable(user) {
  if (!TEST_MODE_GM_ONLY) return;
  const d = await admin.firestore().collection("users").doc(user.uid).get();
  if (!d.exists || d.data().isGm !== true) {
    throw new Error("결제 준비 중입니다. 잠시 후 다시 이용해 주세요.");
  }
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
      if (inv.some((i) => i && i.name === p.name)) {
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

    const ref = db.collection("orders").doc(orderId);
    const snap = await ref.get();
    if (!snap.exists) return res.status(404).json({ok: false, err: "주문을 찾을 수 없습니다"});
    const order = snap.data();
    if (order.uid !== user.uid) return res.status(403).json({ok: false, err: "본인 주문이 아닙니다"});
    if (order.status === "paid") return res.json({ok: true, already: true}); // 멱등

    // 🔎 포트원에서 실제 결제 내역 조회
    const r = await fetch(PORTONE_API + "/payments/" + encodeURIComponent(orderId),
        {headers: portoneHeaders()});
    if (!r.ok) {
      await ref.update({status: "failed", note: "조회실패 " + r.status});
      return res.status(400).json({ok: false, err: "결제 조회 실패"});
    }
    const pay = await r.json();
    const paidAmount = ((pay.amount || {}).total) || 0;
    const paidStatus = pay.status;

    // ⭐ 금액·상태 대조 — 하나라도 어긋나면 지급하지 않고 즉시 취소
    if (paidStatus !== "PAID" || paidAmount !== order.amount) {
      await ref.update({status: "failed", paidAmount, paidStatus,
        note: "금액/상태 불일치 (기대 " + order.amount + ")"});
      try {
        await fetch(PORTONE_API + "/payments/" + encodeURIComponent(orderId) + "/cancel",
            {method: "POST", headers: portoneHeaders(),
              body: JSON.stringify({reason: "금액 불일치 - 자동 취소"})});
      } catch (_) {}
      return res.status(400).json({ok: false, err: "결제 금액이 일치하지 않아 취소되었습니다"});
    }

    // ✅ 검증 통과 → 지급 (트랜잭션으로 중복 지급 차단)
    const granted = await grantItem(db, order, orderId);
    await ref.update({
      status: "paid", paidAmount, paidStatus,
      pgProvider: (pay.channel || {}).pgProvider || "",
      method: ((pay.method || {}).type) || "",
      granted, grantedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return res.json({ok: true, itemName: order.itemName, qty: order.qty});
  } catch (e) {
    return res.status(500).json({ok: false, err: String(e.message || e)});
  }
});

// 🎁 인벤토리 지급 — 서버만 수행. STACK은 수량 누적, ONCE는 1개.
async function grantItem(db, order, orderId) {
  const p = PRODUCTS[order.itemKey];
  if (!p) return false;
  const uref = db.collection("users").doc(order.uid);
  return db.runTransaction(async (tx) => {
    const u = await tx.get(uref);
    const inv = ((u.data() || {}).inventory || []).slice();
    // 📦 묶음 상품 — 낱개가 아니라 '상자' 하나로 넣는다. 유저가 눌러 열면 내용물이 풀린다.
    //    gid 에 주문번호를 넣어 두면, 환불 문의 때 '이 주문의 상자가 아직 있나'를 바로 볼 수 있다.
    if (Array.isArray(p.bundle)) {
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
      return true;
    }
    const idx = inv.findIndex((i) => i && i.name === p.name);
    if (p.limitType === "ONCE") {
      if (idx >= 0) return false;                       // 이미 보유
      inv.push({name: p.name, quantity: 1, cash: true});
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
