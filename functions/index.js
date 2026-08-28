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
        // 🎖️ [2026-08-24] 착용 레벨/승급 제한은 '지급'이 아니라 '게임 내 착용·능력치'에서 검사.
        //    → 홈페이지서 조건 미달로 사도 인벤엔 무조건 지급(계정당 1개라 exploit 없음, "안 들어왔다" 문의 방지).
        //    조건 충족 전엔 게임에서 착용·능력치 적용이 안 되고, 충족하면 자동 적용됨.
        const alreadyOwns = inventory.some(i => i.name === itemTemplate.name);
        if (alreadyOwns) { needsRefund = true; refundReason = "이미 보유 중(계정당 1개) 중복 구매"; }
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

// (임시 함수 diagTerryTemp 는 빨강테리 중수스킨 구매=승급미달 환불요청 확인 후 제거됨 — 2026-08-24)

// (임시 함수 resetOctopusRecordTemp 는 문어 1~50kg 개편에 맞춰 전 유저 문어 기록 39건 리셋 후 제거됨 — 2026-08-24)

// (임시 함수 setStarMultTemp 는 별점별 힘 배율 첫날값[★3 1.05·★4 1.08·★5 1.10] 설정 후 제거됨 — 2026-08-24)
//   다음 단계 상향 시: 이 함수 재추가(query s3/s4/s5) → 배포 → 호출 → 삭제. config/event.starMult에 저장됨.

// ⭐ [상시 스케줄] 별점별 물고기 힘 배율 자동 램프 — ★3·4·5를 매일 04:00 KST에 +0.02씩 동시에 상향.
//   목표 도달(★3 1.20·★4 1.30·★5 1.40) 시 no-op. config/event.starRampOff=true면 일시정지.
//   반발 시 정지: config/event.starRampOff=true / 되돌리기: setStarMultTemp로 값 하향 / 종료: 이 함수 삭제.
exports.rampStarMult = functions.scheduler.onSchedule(
  { schedule: "0 4 * * *", timeZone: "Asia/Seoul", region: "us-central1" },
  async (event) => {
    try {
      const db = admin.firestore();
      const ref = db.collection("config").doc("event");
      const snap = await ref.get();
      const d = snap.data() || {};
      if (d.starRampOff === true) { console.log("[별점램프] 일시정지(starRampOff)"); return; }
      const targets = { "3": 1.20, "4": 1.30, "5": 1.40 };
      const step = 0.02;
      const cur = (d.starMult && typeof d.starMult === "object") ? d.starMult : {};
      const out = { "1": 1.0, "2": 1.0 };
      let changed = false;
      for (const k of ["3", "4", "5"]) {
        let v = (typeof cur[k] === "number") ? cur[k] : 1.0;
        if (v < targets[k]) { v = Math.min(targets[k], Math.round((v + step) * 100) / 100); changed = true; }
        out[k] = v;
      }
      if (!changed) { console.log("[별점램프] 목표 도달 — 변화 없음", cur); return; }
      await ref.set({ starMult: out }, { merge: true });
      console.log("[별점램프] 상향", out);
    } catch (e) {
      console.error("[별점램프] 실패", e);
    }
  }
);

// (임시 함수 cfgTickerTemp 는 줄광고 betaNotice에 문어개편·이용권수량수정 공지 설정 후 제거됨 — 2026-08-24)
//   원복(공지 내려도 될 때): config/event.betaNotice를 정식서비스 문구만 남게 되돌리기.

// (임시 함수 diagTadagiTemp 는 따다기 1시간 이용권 2장 누락 복구[결제5·지급3] 후 제거됨 — 2026-08-24)

// (임시 함수 diagEmailTicketsTemp 는 달빛둠벙[pmhseo] 이용권 6장 결제=6장 지급 정산확인 후 제거됨 — 2026-08-24)

// (임시 함수 grantJungsuSkinTemp 는 빨강테리 중수승급 완료 후 중수스킨 지급+환불요청 취소 후 제거됨 — 2026-08-24)

// (임시 함수 grantTestItemsTemp 는 미르페스카·아레투사에 중수스킨+캠피싱휘장 지급 후 제거됨 — 2026-08-24)

// (임시 함수 diagBaekduTemp 는 백두무궁 제압력 하락원인[하수스킨+뱃지 보유·미착용] 확인 후 제거됨 — 2026-08-24)

// (임시 함수 cfgTicker2Temp 는 줄광고를 능력치(착용기반) 업데이트 공지로 갱신 후 제거됨 — 2026-08-24)
//   원복: config/event.betaNotice를 정식서비스 문구만 남게 되돌리기.

// (임시 함수 refundArenaTicketTemp 는 빨강테리 아레나 입장권 1장 복구[평준화 버그 허탕] 후 제거됨 — 2026-08-24)

// ═══════════════════════════════════════════════════════════════
// 📢 [게임 홈페이지 공지 API] camfishing.web.app 공지 목록/상세/작성
//   컬렉션: site_notices/{id}
//   GET  ?list=1[&limit=20]  → 공개 목록(발행된 것만)
//   GET  ?id=<문서id>        → 공개 상세(조회수 +1)
//   POST (Authorization: Bearer <FirebaseIdToken>) → 작성/수정/삭제 (users/{uid}.isGm === true 필요)
//   ⚠️ Firestore 보안규칙을 건드리지 않기 위해 전부 서버(admin SDK) 경유로 처리.
// ═══════════════════════════════════════════════════════════════
exports.noticesApi = functions.https.onRequest(async (req, res) => {
  res.set("Access-Control-Allow-Origin", "*");
  res.set("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
  res.set("Access-Control-Allow-Headers", "Content-Type, Authorization");
  if (req.method === "OPTIONS") return res.status(204).send("");

  const db = admin.firestore();
  const col = db.collection("site_notices");

  try {
    // ── 공개 조회 ────────────────────────────────
    if (req.method === "GET") {
      res.set("Cache-Control", "no-store");
      if (req.query.id) {
        const doc = await col.doc(String(req.query.id)).get();
        if (!doc.exists) return res.status(404).json({ ok: false, err: "not found" });
        const d = doc.data();
        if (d.published === false) return res.status(404).json({ ok: false, err: "not found" });
        col.doc(doc.id).update({ views: admin.firestore.FieldValue.increment(1) }).catch(() => {});
        return res.json({ ok: true, item: { id: doc.id, ...d, createdAt: d.createdAt ? d.createdAt.toMillis() : null } });
      }
      let limit = parseInt(req.query.limit, 10);
      if (!Number.isFinite(limit) || limit < 1 || limit > 100) limit = 30;
      const snap = await col.orderBy("createdAt", "desc").limit(limit).get();
      const items = [];
      snap.forEach((doc) => {
        const d = doc.data();
        if (d.published === false) return;
        items.push({
          id: doc.id, type: d.type || "notice", title: d.title || "",
          date: d.date || (d.createdAt ? d.createdAt.toDate().toISOString().substring(0, 10) : ""),
          pinned: d.pinned === true, views: d.views || 0,
          createdAt: d.createdAt ? d.createdAt.toMillis() : 0,
        });
      });
      items.sort((a, b) => (b.pinned - a.pinned) || (b.createdAt - a.createdAt));
      return res.json({ ok: true, items });
    }

    // ── 관리자 쓰기 ──────────────────────────────
    if (req.method !== "POST") return res.status(405).json({ ok: false, err: "method" });

    const authHeader = String(req.get("Authorization") || "");
    const m = authHeader.match(/^Bearer\s+(.+)$/i);
    if (!m) return res.status(401).json({ ok: false, err: "로그인이 필요합니다" });
    let decoded;
    try {
      decoded = await admin.auth().verifyIdToken(m[1]);
    } catch (e) {
      return res.status(401).json({ ok: false, err: "인증 실패(다시 로그인해 주세요)" });
    }
    const uref = await db.collection("users").doc(decoded.uid).get();
    if (!uref.exists || uref.data().isGm !== true) {
      return res.status(403).json({ ok: false, err: "관리자 계정만 사용할 수 있습니다" });
    }
    // 📝 공지 작성자는 항상 "운영자"로 고정 — 관리자의 개인 게임 닉네임(미르페스카 등) 노출 방지.
    //    (관리자 계정이 여러 개라도 공지엔 일관되게 "캠피싱"으로 표기 — 광장 GM 캐릭터명, 친근감)
    const nick = "캠피싱";

    const b = req.body || {};
    const action = String(b.action || "save");

    if (action === "delete") {
      if (!b.id) return res.status(400).json({ ok: false, err: "id 없음" });
      await col.doc(String(b.id)).delete();
      return res.json({ ok: true, deleted: String(b.id) });
    }

    // 목록(관리자용: 미발행 포함)
    if (action === "adminList") {
      const snap = await col.orderBy("createdAt", "desc").limit(100).get();
      const items = [];
      snap.forEach((doc) => {
        const d = doc.data();
        items.push({ id: doc.id, type: d.type || "notice", title: d.title || "",
          date: d.date || "", pinned: d.pinned === true, published: d.published !== false,
          views: d.views || 0, body: d.body || "" });
      });
      return res.json({ ok: true, items });
    }

    const title = String(b.title || "").trim();
    const body = String(b.body || "").trim();
    if (!title) return res.status(400).json({ ok: false, err: "제목을 입력해 주세요" });
    if (title.length > 200) return res.status(400).json({ ok: false, err: "제목이 너무 깁니다" });
    if (body.length > 30000) return res.status(400).json({ ok: false, err: "본문이 너무 깁니다" });
    const type = ["notice", "update", "event"].includes(String(b.type)) ? String(b.type) : "notice";

    const payload = {
      type, title, body,
      pinned: b.pinned === true,
      published: b.published !== false,
      date: String(b.date || "").match(/^\d{4}[.-]\d{2}[.-]\d{2}$/) ? String(b.date).replace(/-/g, ".") : getTodayKST().replace(/-/g, "."),
      author: nick,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    if (b.id) {
      await col.doc(String(b.id)).set(payload, { merge: true });
      return res.json({ ok: true, id: String(b.id), updated: true });
    }
    payload.createdAt = admin.firestore.FieldValue.serverTimestamp();
    payload.views = 0;
    const ref = await col.add(payload);
    return res.json({ ok: true, id: ref.id, created: true });
  } catch (e) {
    console.error("[noticesApi]", e);
    return res.status(500).json({ ok: false, err: String(e) });
  }
});

// 👤 [홈페이지 내정보 API] 로그인한 유저의 표시용 정보만 반환(닉네임·레벨·등급·GM여부)
//    Authorization: Bearer <FirebaseIdToken> 필요. 포인트/경험치 등 민감정보는 제외.
exports.meApi = functions.https.onRequest(async (req, res) => {
  res.set("Access-Control-Allow-Origin", "*");
  res.set("Access-Control-Allow-Methods", "GET, OPTIONS");
  res.set("Access-Control-Allow-Headers", "Content-Type, Authorization");
  res.set("Cache-Control", "no-store");
  if (req.method === "OPTIONS") return res.status(204).send("");
  try {
    const m = String(req.get("Authorization") || "").match(/^Bearer\s+(.+)$/i);
    if (!m) return res.status(401).json({ ok: false, err: "no token" });
    let decoded;
    try { decoded = await admin.auth().verifyIdToken(m[1]); }
    catch (e) { return res.status(401).json({ ok: false, err: "invalid token" }); }
    const doc = await admin.firestore().collection("users").doc(decoded.uid).get();
    if (!doc.exists) return res.json({ ok: true, registered: false, email: decoded.email || "" });
    const d = doc.data();
    return res.json({
      ok: true, registered: true,
      email: decoded.email || "",
      nickname: d.nickname || "",
      rank: d.rank || "초보",
      level: calcLevel(d.exp || 0),
      isGm: d.isGm === true,
    });
  } catch (e) {
    console.error("[meApi]", e);
    return res.status(500).json({ ok: false, err: String(e) });
  }
});






