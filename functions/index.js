const functions = require("firebase-functions");
const admin = require("firebase-admin");

admin.initializeApp();

// 📖 [아이템 사전 및 구매 조건 설정]
const itemDatabase = {
  "1시간 이용권": {
    name: "낚시 1시간 이용권",
    category: "TICKET", type: "ETC", icon: "item_ticket_1h.png",
    limitType: "STACK" // 🎟️ 무제한 구매(수량 누적·쟁여두기). 사용은 게임이 하루 1장 제한(lastTimeTicketDate)
  },
  "아레나 입장권": {
    name: "아레나 입장권",
    category: "TICKET", type: "ETC", icon: "arena_ticket.png",
    limitType: "STACK" // 🎟️ 무제한 구매(수량 누적). 사용은 게임이 하루 1장 제한
  },
  "스킨(하수)": {
    name: "하수 조사",
    reqLevel: 10, // 👈 착용 레벨(하수는 매출 위해 10으로 낮춤 · game_config와 일치)
    reqRank: "하수", // 👈 해당 승급 퀘스트 통과 필요(레벨만으론 불가)
    category: "SKIN", type: "SKIN", icon: "../images/skin_novice.jpg", stats: { P: 20, C: 20, S: 20 },
    limitType: "ONCE"  // 👈 계정당 1회 한정
  },
  "스킨(중수)": {
    name: "중수 조사",
    reqLevel: 30,
    reqRank: "중수",
    category: "SKIN", type: "SKIN", icon: "../images/skin_intermediate.jpg", stats: { P: 50, C: 50, S: 50 },
    limitType: "ONCE"
  },
  "스킨(고수)": {
    name: "고수 조사",
    reqLevel: 50,
    reqRank: "고수",
    category: "SKIN", type: "SKIN", icon: "../images/skin_expert.jpg", stats: { P: 100, C: 100, S: 100 },
    limitType: "ONCE"
  }
  ,
  "스킨(프로)": {
    name: "프로 조사",
    reqLevel: 70,
    reqRank: "프로",
    category: "SKIN", type: "SKIN", icon: "../images/skin_pro.jpg", stats: { P: 200, C: 200, S: 200 },
    limitType: "ONCE"
  },
  "스킨(마스터)": {
    name: "마스터 조사",
    reqLevel: 100,
    reqRank: "마스터",
    category: "SKIN", type: "SKIN", icon: "../images/skin_master.jpg", stats: { P: 300, C: 300, S: 300 },
    limitType: "ONCE"
  },
  // 🎖️ 휘장(배지) — 민물/바다 통합 '범용(COMMON)' 5등급. 스킨과 달리 '승급(reqRank)' 없이 레벨만 요구. 등급별 계정당 1개.
  //    (2026-07-27 재구성) 지금은 1~3등급만 오픈. 4~5등급(KREFT 명장/명인)은 상점 등록 시 추가.
  "캠피싱 뱃지": {
    name: "캠피싱 뱃지",
    reqLevel: 10, // 승급 불필요(reqRank 없음)
    category: "COMMON", type: "ETC", icon: "item_badge_1.png", stats: { P: 10, C: 10, S: 10 },
    limitType: "ONCE"  // 등급당 계정당 1개 한정
  },
  "캠피싱 휘장": {
    name: "캠피싱 휘장",
    reqLevel: 30,
    category: "COMMON", type: "ETC", icon: "item_badge_2.png", stats: { P: 30, C: 30, S: 30 },
    limitType: "ONCE"
  },
  "KREFT 정예 휘장": {
    name: "KREFT 정예 휘장",
    reqLevel: 50,
    category: "COMMON", type: "ETC", icon: "item_badge_3.png", stats: { P: 50, C: 50, S: 50 },
    limitType: "ONCE"
  }
};

// 🏅 승급 칭호 순서 (스킨 구매 자격 = 해당 승급 퀘스트 통과 여부 판정용)
//    레벨만 채우면 안 되고, 아라 NPC 승급 퀘스트(레벨+6대장)로 rank가 올라야 스킨 구매 가능.
const RANK_ORDER = ["초보", "하수", "중수", "고수", "프로", "마스터", "레전드", "낚시의 신"];

// 🕒 한국 시간(KST) 기준으로 오늘 날짜(YYYY-MM-DD) 구하는 함수
function getTodayKST() {
  const curr = new Date();
  const utc = curr.getTime() + (curr.getTimezoneOffset() * 60 * 1000);
  const kstTime = new Date(utc + (9 * 60 * 60 * 1000));
  return kstTime.toISOString().substring(0, 10);
}

// 📈 경험치 표 (⚠️ 클라이언트 game_config.dart의 globalExpTable 와 '반드시 동일한 공식'으로 유지!)
//    만렙 150. d(2)=1400, 10레벨 구간마다 레벨당 증가폭 +50 (Lv1~10 +200, 11~20 +250 ... 141~150 +900).
//    누적: Lv50≈38만, Lv100≈183만, Lv120≈285만, Lv150≈498만.
const GLOBAL_MAX_LEVEL = 150;
const expTable = (() => {
  const t = new Array(GLOBAL_MAX_LEVEL + 1).fill(0); // index 0·1 = 0
  let prevDelta = 0;
  for (let L = 2; L <= GLOBAL_MAX_LEVEL; L++) {
    const band = Math.floor((L - 1) / 10);              // L=2~10→0, 11~20→1 ...
    const step = 200 + 50 * band;                       // 구간별 레벨당 증가폭
    const delta = (L === 2) ? 1400 : prevDelta + step;  // 이번 레벨업 필요 경험치
    t[L] = t[L - 1] + delta;                            // 누적
    prevDelta = delta;
  }
  return t;
})();

// 🧠 경험치 기반 레벨 계산기 (클라이언트 calcLevelFromExp 와 동일)
function calcLevel(exp) {
  for (let i = GLOBAL_MAX_LEVEL; i >= 1; i--) {
    if (exp >= expTable[i]) return i;
  }
  return 1;
}

// 🔐 webhook 인증용 시크릿. functions/.env 파일에 IMWEB_WEBHOOK_SECRET=내가정한값 으로 설정.
//    아임웹 webhook URL 뒤에 ?token=내가정한값 을 붙여서 등록하면 됨.
const WEBHOOK_SECRET = process.env.IMWEB_WEBHOOK_SECRET || "";

// ⚠️ 결제는 됐는데 지급을 못 한 건을 기록 (운영자가 보고 수동 지급/확인)
async function logPaymentIssue(email, orderName, orderNo, reason) {
  await admin.firestore().collection("payment_issues").add({
    email: email || "(없음)",
    itemName: orderName || "(없음)",
    orderNo: orderNo || "(없음)",
    reason: reason,
    status: "확인 필요",
    createdAt: admin.firestore.FieldValue.serverTimestamp()
  });
  console.error(`[지급 실패] ${reason} | 이메일:${email} | 주문:${orderName} (${orderNo})`);
}

// ═══════════════════════════════════════════════════════════════
// 🔗 [아임웹 Open API V2] OAuth2 토큰 관리 + 주문 조회
//   .env 필요: IMWEB_CLIENT_ID, IMWEB_CLIENT_SECRET (개발자센터 앱 정보)
//   토큰 저장: Firestore config/imweb_oauth {accessToken, refreshToken, accessTokenExpiry}
//   최초 1회 인증: 아래 imwebOAuthCallback (authorize → code → token)
//   accessToken 2시간 / refreshToken 90일 → 만료 시 자동 갱신
// ═══════════════════════════════════════════════════════════════
const IMWEB_API_BASE = "https://openapi.imweb.me";
const IMWEB_CLIENT_ID = process.env.IMWEB_CLIENT_ID || "";
const IMWEB_CLIENT_SECRET = process.env.IMWEB_CLIENT_SECRET || "";
const IMWEB_REDIRECT_URI = process.env.IMWEB_OAUTH_REDIRECT ||
  "https://us-central1-camnak-fishing.cloudfunctions.net/imwebOAuthCallback";
const oauthDocRef = () => admin.firestore().collection("config").doc("imweb_oauth");

// POST /oauth2/token (application/x-www-form-urlencoded, camelCase 파라미터)
async function imwebTokenRequest(params) {
  const form = new URLSearchParams();
  for (const [k, v] of Object.entries(params)) form.append(k, v);
  const r = await fetch(IMWEB_API_BASE + "/oauth2/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: form.toString(),
  });
  const j = await r.json().catch(() => ({}));
  console.log("[토큰응답]", r.status, JSON.stringify(j).slice(0, 500));
  return j;
}

// 토큰 응답을 Firestore에 저장 (응답이 {data:{...}}로 감싸질 수 있어 방어적으로 파싱)
async function storeImwebTokens(tok) {
  const d = (tok && tok.data) ? tok.data : (tok || {});
  const accessToken = d.accessToken || d.access_token;
  const refreshToken = d.refreshToken || d.refresh_token;
  if (!accessToken) throw new Error("토큰 응답에 accessToken 없음: " + JSON.stringify(tok).slice(0, 300));
  await oauthDocRef().set({
    accessToken,
    refreshToken: refreshToken || null,
    scope: d.scope || null,
    accessTokenExpiry: Date.now() + (2 * 60 * 60 * 1000) - 60000, // 2시간 - 1분 버퍼
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, { merge: true });
  return accessToken;
}

// 유효한 accessToken 확보 (만료 시 refreshToken으로 자동 갱신)
async function getImwebAccessToken() {
  const snap = await oauthDocRef().get();
  if (!snap.exists) throw new Error("아임웹 OAuth 미인증 — 최초 인증(imwebOAuthCallback) 필요");
  const s = snap.data();
  if (s.accessToken && s.accessTokenExpiry && Date.now() < s.accessTokenExpiry) {
    return s.accessToken;
  }
  if (!s.refreshToken) throw new Error("refreshToken 없음 — 재인증 필요");
  const tok = await imwebTokenRequest({
    grantType: "refresh_token",
    clientId: IMWEB_CLIENT_ID,
    clientSecret: IMWEB_CLIENT_SECRET,
    refreshToken: s.refreshToken,
  });
  return await storeImwebTokens(tok);
}

// 주문번호로 주문 상세 조회 (GET /orders/{orderNo})
//   반환: { products:[상품명], ordererEmail(권위있는 실제 주문자), refunded(환불여부) }
//   실제 응답: data.sections[].sectionItems[].productInfo.prodName
// 주문 객체(sections 포함)에서 구매 상품명 목록 추출
//   실제 응답: data.sections[].sectionItems[].productInfo.prodName
function extractProductNames(order) {
  const sections = order.sections || order.orderSections || order.orderSectionList || [];
  const names = [];
  for (const sec of sections) {
    const items = sec.sectionItems || sec.orderSectionItems || sec.items || [];
    for (const it of items) {
      const nm = (it.productInfo && (it.productInfo.prodName || it.productInfo.name)) ||
                 it.prodName || it.name;
      if (!nm) continue;
      // 🎟️ 수량(qty) 반영 — 4개 사면 상품명을 4번 넣어 지급 로직이 4개 처리(STACK 누적).
      //    (예전엔 qty 무시로 항상 1개만 지급되던 버그 수정 — 2026-08-24)
      let q = Number(it.qty != null ? it.qty : (it.count != null ? it.count : (it.quantity != null ? it.quantity : 1)));
      if (!Number.isFinite(q) || q < 1) q = 1;
      if (q > 100) q = 100; // 안전 상한
      for (let k = 0; k < q; k++) names.push(String(nm));
    }
  }
  return names;
}

// 주문번호로 주문 상세 조회 (GET /orders/{orderNo}) → 주문 객체 반환
async function fetchOrder(orderNo) {
  const token = await getImwebAccessToken();
  const r = await fetch(IMWEB_API_BASE + "/orders/" + encodeURIComponent(orderNo), {
    method: "GET",
    headers: { "Authorization": "Bearer " + token, "Content-Type": "application/json" },
  });
  const j = await r.json().catch(() => ({}));
  if (r.status !== 200) {
    throw new Error("주문조회 실패 status=" + r.status + " " + JSON.stringify(j).slice(0, 300));
  }
  return (j && j.data) ? j.data : (j || {});
}

// 🎁 [공용 지급 처리] 웹훅·폴링이 함께 사용. 주문 1건(sections 포함 객체)을 받아 지급/환불기록/실패기록까지 처리.
//   ⚠️ 폴링이 매분 같은 주문을 재처리하지 않도록, "종료된" 모든 건은 processed_orders에 기록한다.
//   (일시적 오류만 기록 안 함 → 다음 폴링에 재시도). 반환: 결과 문자열.
async function processOrder(order, source) {
  const db = admin.firestore();
  const orderNo = String(order.orderNo || "");
  if (!orderNo) return "no-orderNo";

  const dedupSnap = await db.collection("processed_orders").doc(orderNo).get();
  if (dedupSnap.exists) return "already-processed";

  // ⚠️ 보안: 지급 대상 이메일은 API의 실제 주문자(ordererEmail) 사용
  const buyerEmail = order.ordererEmail || order.memberUid || "";
  const prodNames = extractProductNames(order);
  const purchasedLabel = prodNames.join(", ") || "(상품없음)";

  const recordProcessed = (granted, refunded, note) =>
    db.collection("processed_orders").doc(orderNo).set({
      email: buyerEmail, itemName: purchasedLabel,
      granted, refunded, note: note || null, source: source || null,
      processedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

  // 환불/취소(대기 포함) 주문은 지급 안 함
  const refunded = (Number(order.totalRefundedPrice) || 0) > 0 ||
                   (Number(order.totalRefundPendingPrice) || 0) > 0;
  if (refunded) { await recordProcessed(false, true, "환불(대기) 주문"); return "refunded"; }

  // 💰 0원(무료) 주문은 지급 안 함 (과거 테스트 주문 등 오지급 방지)
  const paid = (Number(order.totalPaymentPrice) || 0) > 0 || (Number(order.totalPrice) || 0) > 0;
  if (!paid) { await recordProcessed(false, false, "0원(무료) 주문"); return "zero-price"; }

  if (prodNames.length === 0) {
    await logPaymentIssue(buyerEmail, purchasedLabel, orderNo, "주문에 상품이 없음");
    await recordProcessed(false, false, "상품없음");
    return "empty";
  }

  const snapshot = await db.collection("users").where("email", "==", buyerEmail).get();
  if (snapshot.empty) {
    await logPaymentIssue(buyerEmail, purchasedLabel, orderNo, "결제 이메일과 일치하는 게임 계정 없음");
    await recordProcessed(false, false, "계정없음");
    return "user-not-found";
  }

  const userDoc = snapshot.docs[0];
  const userRef = userDoc.ref;
  const userData = userDoc.data();
  let inventory = userData.inventory || [];
  let realLevel = calcLevel(userData.exp || 0);
  const today = getTodayKST();
  let purchaseDates = userData.purchaseDates || {}; // 아이템별 마지막 구매일(1일 1회 구매 제한용)
  let isInventoryUpdated = false, needsRefund = false, refundReason = "", matchedKnownItem = false, newTicketDate = null, purchaseDatesChanged = false;

  const norm = (s) => String(s).replace(/\s+/g, ""); // 공백 무시 매칭('아레나입장권'='아레나 입장권')
  for (const prodName of prodNames) {
    const np = norm(prodName);
    for (const [key, itemTemplate] of Object.entries(itemDatabase)) {
      if (!np.includes(norm(key))) continue;
      matchedKnownItem = true;

      if (itemTemplate.limitType === "ONCE") {
        const alreadyOwns = inventory.some(i => i.name === itemTemplate.name);
        const meetsLevel = realLevel >= itemTemplate.reqLevel;
        const userRank = userData.rank || "초보";
        const reqRankIdx = itemTemplate.reqRank ? RANK_ORDER.indexOf(itemTemplate.reqRank) : -1;
        const userRankIdx = RANK_ORDER.indexOf(userRank);
        const meetsRank = reqRankIdx < 0 || userRankIdx >= reqRankIdx;
        if (alreadyOwns) { needsRefund = true; refundReason = "이미 보유 중인 스킨을 중복 구매함"; }
        else if (!meetsLevel) { needsRefund = true; refundReason = `레벨 미달 (요구: Lv.${itemTemplate.reqLevel}, 현재: Lv.${realLevel})`; }
        else if (!meetsRank) { needsRefund = true; refundReason = `승급 미달 (요구: ${itemTemplate.reqRank} 승급, 현재: ${userRank})`; }
        else { inventory.push({ ...itemTemplate }); isInventoryUpdated = true; }
      }
      else if (itemTemplate.limitType === "DAILY") {
        if ((userData.lastTicketDate || "") === today) { needsRefund = true; refundReason = "1시간 이용권 1일 1회 구매 제한 초과"; }
        else { const ni = { ...itemTemplate, quantity: 1 }; inventory.push(ni); newTicketDate = today; isInventoryUpdated = true; }
      }
      else if (itemTemplate.limitType === "STACK") {
        const idx = inventory.findIndex(i => i.name === itemTemplate.name);
        if (idx >= 0) inventory[idx].quantity = (Number(inventory[idx].quantity) || 0) + 1;
        else inventory.push({ ...itemTemplate, quantity: 1 });
        isInventoryUpdated = true;
      }
      // 🎟️ 1일 1회 구매 + 수량 누적 (이용권·입장권). 아이템별로 하루 1번만 구매 가능.
      else if (itemTemplate.limitType === "DAILY_STACK") {
        if (purchaseDates[itemTemplate.name] === today) {
          needsRefund = true;
          refundReason = `${itemTemplate.name} 1일 1회 구매 제한 초과`;
        } else {
          const idx = inventory.findIndex(i => i.name === itemTemplate.name);
          if (idx >= 0) inventory[idx].quantity = (Number(inventory[idx].quantity) || 0) + 1;
          else inventory.push({ ...itemTemplate, quantity: 1 });
          purchaseDates[itemTemplate.name] = today;
          purchaseDatesChanged = true;
          isInventoryUpdated = true;
        }
      }
    }
  }

  if (!matchedKnownItem) {
    await logPaymentIssue(buyerEmail, purchasedLabel, orderNo, "상품명이 등록된 키워드와 일치하지 않음: " + purchasedLabel);
    await recordProcessed(false, false, "키워드불일치");
    return "unknown-product";
  }
  if (needsRefund) {
    await db.collection("refund_requests").add({
      email: buyerEmail, itemName: purchasedLabel, orderNo, reason: refundReason,
      status: "환불 처리 대기중", requestedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    console.log(`[환불 요망] ${buyerEmail}: ${refundReason}`);
  }
  if (isInventoryUpdated) {
    const updates = { inventory };
    if (newTicketDate) updates.lastTicketDate = newTicketDate;
    if (purchaseDatesChanged) updates.purchaseDates = purchaseDates;
    await userRef.update(updates);
    console.log(`[지급 완료] ${buyerEmail} 주문 ${orderNo}: ${purchasedLabel} (${source})`);
  }
  await recordProcessed(isInventoryUpdated, needsRefund, null);
  return isInventoryUpdated ? "granted" : (needsRefund ? "rejected-refund" : "no-op");
}

// 🔐 [최초 1회] OAuth 인증 콜백 — authorize에서 redirect된 code로 토큰 발급·저장
//   앱 리다이렉트 URI로 이 함수 주소를 등록해두면, 인증 시 자동으로 토큰이 저장됨
exports.imwebOAuthCallback = functions.https.onRequest(async (req, res) => {
  try {
    const code = req.query.code || "";
    if (!code) return res.status(400).send("인가 코드(code)가 없습니다.");
    const tok = await imwebTokenRequest({
      grantType: "authorization_code",
      clientId: IMWEB_CLIENT_ID,
      clientSecret: IMWEB_CLIENT_SECRET,
      redirectUri: IMWEB_REDIRECT_URI,
      code: String(code),
    });
    await storeImwebTokens(tok);
    res.set("Content-Type", "text/html; charset=utf-8");
    return res.status(200).send("<html><body style='font-family:sans-serif;text-align:center;padding:60px'><h2>✅ 아임웹 연동 완료!</h2><p>이제 결제 시 게임 아이템이 자동 지급됩니다.<br>이 창은 닫으셔도 됩니다.</p></body></html>");
  } catch (e) {
    console.error("[OAuth 콜백 에러]", e);
    return res.status(500).send("OAuth 실패: " + e.message + " (로그 확인 필요)");
  }
});

exports.imwebWebhook = functions.https.onRequest(async (req, res) => {
  try {
    // 🔐 [보안 1] webhook 인증: 시크릿을 설정해 둔 경우에만 토큰을 검사 (공짜 지급 해킹 차단)
    //    - IMWEB_WEBHOOK_SECRET 미설정 시: 기존처럼 그냥 동작 (단, 경고 로그) → 작동 중인 연동이 안 끊김
    //    - 설정 시: 아임웹 webhook URL 뒤 ?token=값 이 일치해야만 처리
    if (WEBHOOK_SECRET) {
      const token = req.query.token || req.get("x-webhook-token") || "";
      if (token !== WEBHOOK_SECRET) {
        console.error("[보안 차단] 잘못된 토큰으로 webhook 호출됨");
        return res.status(401).send("Unauthorized");
      }
    } else {
      console.warn("[보안 경고] IMWEB_WEBHOOK_SECRET 미설정 → 인증 없이 동작 중입니다. 정식 오픈 전 반드시 설정하세요.");
    }

    // 📦 [V2 payload] 아임웹 새 웹훅 형식: { eventType, eventTime, data:{ orderNo, ordererEmail, ... } }
    const bodyV2 = req.body || {};
    const eventType = bodyV2.eventType || "";
    const eventData = bodyV2.data || {};

    // 결제(입금) 완료 이벤트만 처리 (그 외 주문 이벤트/테스트는 무시)
    if (eventType !== "ORDER_DEPOSIT_COMPLETE") {
      return res.status(200).send("Ignored (event: " + (eventType || "unknown") + ")");
    }

    const orderNo = String(eventData.orderNo || "");

    if (!orderNo) {
      console.warn("[경고] 주문번호(orderNo) 없음 → 처리 불가");
      return res.status(200).send("No orderNo");
    }

    // 🔁 중복 처리 방지 (아임웹 재전송 대비)
    const dedupSnap = await admin.firestore().collection("processed_orders").doc(orderNo).get();
    if (dedupSnap.exists) {
      console.log(`[중복 무시] 이미 처리된 주문: ${orderNo}`);
      return res.status(200).send("Already processed");
    }

    // 🛒 주문 상세를 아임웹 API로 조회 (웹훅엔 상품명이 안 와서 필요)
    //   ⚠️ 보안: 지급 대상 이메일은 payload가 아니라 API의 실제 주문자(ordererEmail)를 사용
    // 🛒 주문 상세 조회 후 공용 지급 처리(processOrder)로 위임
    let order;
    try {
      order = await fetchOrder(orderNo);
    } catch (e) {
      console.error("[주문조회 실패]", e);
      await logPaymentIssue(eventData.ordererEmail || "", "(주문조회 실패)", orderNo, "아임웹 주문조회 API 실패: " + e.message);
      return res.status(200).send("Order lookup failed (logged)");
    }
    const result = await processOrder(order, "webhook");
    return res.status(200).send("Webhook: " + result);

  } catch (error) {
    console.error("서버 처리 중 에러 발생:", error);
    return res.status(500).send("Server Error");
  }
});

// ═══════════════════════════════════════════════════════════════
// ⏱️ [폴링] 매 1분 최근 주문을 읽어 미처리 결제 자동 지급
//   웹훅이 자동 발송 안 되는 상태(테스트연동 등)에서도 확실히 지급되게 하는 안전장치.
//   최근 50건을 확인 → processed_orders에 없는 건만 processOrder로 지급/기록.
//   최대 지연 ≈ 1분. (order:read 권한 사용)
// ═══════════════════════════════════════════════════════════════
exports.imwebPollOrders = functions.scheduler.onSchedule(
  { schedule: "every 1 minutes", timeZone: "Asia/Seoul", region: "us-central1" },
  async (event) => {
    try {
      const token = await getImwebAccessToken();
      const r = await fetch(IMWEB_API_BASE + "/orders?page=1&limit=50", {
        method: "GET",
        headers: { "Authorization": "Bearer " + token, "Content-Type": "application/json" },
      });
      const j = await r.json().catch(() => ({}));
      if (r.status !== 200) {
        console.error("[폴링] 주문목록 조회 실패", r.status, JSON.stringify(j).slice(0, 300));
        return;
      }
      const list = (j.data && j.data.list) || [];
      let granted = 0, processed = 0;
      for (const order of list) {
        try {
          const result = await processOrder(order, "poll");
          if (result !== "already-processed") processed++;
          if (result === "granted") granted++;
        } catch (e) {
          console.error("[폴링] 주문처리 실패", order && order.orderNo, e.message);
        }
      }
      if (processed > 0) console.log(`[폴링] 신규 ${processed}건 처리(지급 ${granted}건) / 목록 ${list.length}건`);
    } catch (e) {
      console.error("[폴링] 실패", e);
    }
  }
);

// ═══════════════════════════════════════════════════════════════
// 🌧️ [날씨 연동] 위경도 → 기상청 초단기실황 → 강수형태(PTY) 반환
//   functions/.env 에 아래 두 줄 추가하세요:
//     KMA_SERVICE_KEY=기상청_일반인증키(Decoding)   ← 반드시 "디코딩(일반)" 키
//     KAKAO_REST_KEY=카카오_REST_API_키             ← 지역명 표시용(없어도 동작)
// ═══════════════════════════════════════════════════════════════
const KMA_KEY = process.env.KMA_SERVICE_KEY || "";
const KAKAO_KEY = process.env.KAKAO_REST_KEY || "";

// 위경도(WGS84) → 기상청 격자 nx,ny (기상청 공식 LCC DFS 변환)
function dfsXyConv(lat, lon) {
  const RE = 6371.00877, GRID = 5.0, SLAT1 = 30.0, SLAT2 = 60.0;
  const OLON = 126.0, OLAT = 38.0, XO = 43, YO = 136;
  const DEGRAD = Math.PI / 180.0;
  const re = RE / GRID;
  const slat1 = SLAT1 * DEGRAD, slat2 = SLAT2 * DEGRAD;
  const olon = OLON * DEGRAD, olat = OLAT * DEGRAD;
  let sn = Math.tan(Math.PI * 0.25 + slat2 * 0.5) / Math.tan(Math.PI * 0.25 + slat1 * 0.5);
  sn = Math.log(Math.cos(slat1) / Math.cos(slat2)) / Math.log(sn);
  let sf = Math.tan(Math.PI * 0.25 + slat1 * 0.5);
  sf = (Math.pow(sf, sn) * Math.cos(slat1)) / sn;
  let ro = Math.tan(Math.PI * 0.25 + olat * 0.5);
  ro = (re * sf) / Math.pow(ro, sn);
  let ra = Math.tan(Math.PI * 0.25 + lat * DEGRAD * 0.5);
  ra = (re * sf) / Math.pow(ra, sn);
  let theta = lon * DEGRAD - olon;
  if (theta > Math.PI) theta -= 2.0 * Math.PI;
  if (theta < -Math.PI) theta += 2.0 * Math.PI;
  theta *= sn;
  const nx = Math.floor(ra * Math.sin(theta) + XO + 0.5);
  const ny = Math.floor(ro - ra * Math.cos(theta) + YO + 0.5);
  return { nx, ny };
}

// 초단기실황 기준시각 (매시 40분 이후 제공 → 여유롭게 45분 컷, 못 미치면 한 시간 전)
function getKmaBase() {
  const kst = new Date(Date.now() + 9 * 3600 * 1000);
  let hour = kst.getUTCHours();
  const min = kst.getUTCMinutes();
  if (min < 45) hour -= 1;
  if (hour < 0) {
    kst.setUTCDate(kst.getUTCDate() - 1);
    hour = 23;
  }
  const y = kst.getUTCFullYear();
  const m = String(kst.getUTCMonth() + 1).padStart(2, "0");
  const d = String(kst.getUTCDate()).padStart(2, "0");
  return { baseDate: `${y}${m}${d}`, baseTime: String(hour).padStart(2, "0") + "00" };
}

exports.getWeather = functions.https.onRequest(async (req, res) => {
  // CORS (게임 웹에서 직접 호출)
  res.set("Access-Control-Allow-Origin", "*");
  res.set("Access-Control-Allow-Methods", "GET, OPTIONS");
  res.set("Access-Control-Allow-Headers", "Content-Type");
  if (req.method === "OPTIONS") return res.status(204).send("");

  try {
    let lat = parseFloat(req.query.lat);
    let lon = parseFloat(req.query.lon);
    // 위치 못 받으면 서울시청 기본값
    if (isNaN(lat) || isNaN(lon)) { lat = 37.5665; lon = 126.9780; }

    if (!KMA_KEY) {
      return res.json({ pty: 0, temp: null, region: "", error: "KMA_SERVICE_KEY 미설정" });
    }

    const { nx, ny } = dfsXyConv(lat, lon);
    const { baseDate, baseTime } = getKmaBase();

    const params = new URLSearchParams({
      serviceKey: KMA_KEY, // .env 에는 Decoding(일반) 인증키를 넣으세요
      numOfRows: "60",
      pageNo: "1",
      dataType: "JSON",
      base_date: baseDate,
      base_time: baseTime,
      nx: String(nx),
      ny: String(ny),
    });
    const url = "https://apis.data.go.kr/1360000/VilageFcstInfoService_2.0/getUltraSrtNcst?" + params.toString();

    let pty = 0, temp = null, rain = null;
    try {
      const r = await fetch(url);
      const j = await r.json();
      const items = (j && j.response && j.response.body && j.response.body.items && j.response.body.items.item) || [];
      for (const it of items) {
        if (it.category === "PTY") pty = parseInt(it.obsrValue, 10);
        else if (it.category === "T1H") temp = it.obsrValue;
        else if (it.category === "RN1") rain = it.obsrValue;
      }
    } catch (e) {
      console.error("[날씨] 기상청 호출 실패:", e);
    }

    // 지역명 (카카오 역지오코딩, 키 있을 때만)
    let region = "";
    if (KAKAO_KEY) {
      try {
        const kurl = `https://dapi.kakao.com/v2/local/geo/coord2regioncode.json?x=${lon}&y=${lat}`;
        const kr = await fetch(kurl, { headers: { Authorization: "KakaoAK " + KAKAO_KEY } });
        const kj = await kr.json();
        const docs = kj.documents || [];
        const doc = docs.find((d) => d.region_type === "H") || docs[0];
        if (doc) region = `${doc.region_1depth_name} ${doc.region_2depth_name}`.trim();
      } catch (e) {
        console.error("[날씨] 카카오 호출 실패:", e);
      }
    }

    return res.json({ pty, temp, rain, region, nx, ny, baseDate, baseTime });
  } catch (error) {
    console.error("[날씨] 서버 에러:", error);
    return res.json({ pty: 0, temp: null, region: "", error: "server" });
  }
});

// (임시 진단 함수 paymentDiag 는 결제 검증 완료 후 제거됨 — 2026-08-23)
// (임시 지급 함수 grantSkinTemp 는 미르페스카·아레투사 하수스킨 지급 후 제거됨 — 2026-08-23)
// (임시 config 함수 cfgAdmin 은 오픈베타→정식서비스 문구 교체 후 제거됨 — 2026-08-23)
// (임시 config 함수 cfgEvent 은 광복절 이벤트 종료 후 제거됨 — 2026-08-24)
// (임시 정리 함수 cleanupEventBadge 는 태극기 배지 34개 제거 후 제거됨 — 2026-08-24)

// (임시 함수 grantGuildFlagTemp 는 트로피 깃발 위치 테스트 후 제거됨 — 2026-08-24)
// (임시 함수 grantBadgeTemp 는 미르페스카·아레투사에 캠피싱 뱃지 지급 후 제거됨 — 2026-08-24)
// (임시 함수 diagUserTemp·fixTicketsTemp 는 달빛둠벙 1시간권 4개 복구 + 수량(qty) 필드 확인 후 제거됨 — 2026-08-24)

// (임시 함수 refundRodTemp 는 달빛둠벙 실수구매 CF-30T 제거+20,000P 환불 후 제거됨 — 2026-08-24)
