const functions = require("firebase-functions");
const admin = require("firebase-admin");

admin.initializeApp();

// 📖 [아이템 사전 및 구매 조건 설정]
const itemDatabase = {
  "1시간 이용권": { 
    name: "낚시 1시간 이용권",
    category: "TICKET", type: "ETC", icon: "item_ticket_1h.png",
    limitType: "DAILY" // 👈 1일 1회 제한
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

// 📈 1~30레벨 경험치 표 (⚠️ 게임 클라이언트 ui_lobby.dart의 _calcLevelFromExp 와 반드시 동일하게 유지!)
const expTable = [
  0,        // 인덱스 0 (안 씀)
  0,        // Lv.1
  5000,     // Lv.2
  10000,    // Lv.3
  20000,    // Lv.4
  30000,    // Lv.5 (하수 스킨!)
  50000,    // Lv.6
  70000,    // Lv.7
  90000,    // Lv.8
  110000,   // Lv.9
  130000,   // Lv.10 (중수 스킨!)
  160000,   // Lv.11
  190000,   // Lv.12
  210000,   // Lv.13
  240000,   // Lv.14
  270000,   // Lv.15 (고수 스킨!)
  310000,   // Lv.16
  350000,   // Lv.17
  390000,   // Lv.18
  430000,   // Lv.19
  500000,   // Lv.20 (프로 스킨!)
  550000,   // Lv.21
  600000,   // Lv.22
  650000,   // Lv.23
  700000,   // Lv.24
  800000,   // Lv.25 (마스터 스킨!)
  900000,   // Lv.26
  1000000,  // Lv.27
  1100000,  // Lv.28
  1200000,  // Lv.29
  1300000   // Lv.30 (현재 만렙!)
];

// 🧠 경험치 기반 레벨 계산기 (30레벨 확장판)
function calcLevel(exp) {
  for (let i = 30; i >= 1; i--) {
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

    const data = req.body || {};
    const buyerEmail = data.buyer_email;
    const status = data.status;
    const purchasedItemName = data.order_name || "";
    // 🔁 [보안 2] 주문번호 (아임웹 실제 payload 필드명이 다르면 여기에 추가)
    const orderNo = data.order_no || data.order_number || data.orderno || data.order_id || "";

    if (status !== "PAY_COMPLETE") {
      return res.status(200).send("Ignored (not PAY_COMPLETE)");
    }

    // 🔁 [보안 2] 중복 처리 방지: 이미 처리한 주문번호면 건너뜀 (아임웹 webhook 재전송 대비)
    if (orderNo) {
      const dedupSnap = await admin.firestore().collection("processed_orders").doc(String(orderNo)).get();
      if (dedupSnap.exists) {
        console.log(`[중복 무시] 이미 처리된 주문: ${orderNo}`);
        return res.status(200).send("Already processed");
      }
    } else {
      console.warn("[경고] 주문번호 없음 → 중복방어 불가. 아임웹 payload의 주문번호 필드명을 확인하세요.");
    }

    const usersRef = admin.firestore().collection("users");
    const snapshot = await usersRef.where("email", "==", buyerEmail).get();

    // 🛑 [실패 로그] 결제 이메일과 일치하는 게임 계정 없음 (돈 냈는데 지급 불가 → 수동 확인)
    if (snapshot.empty) {
      await logPaymentIssue(buyerEmail, purchasedItemName, orderNo, "결제 이메일과 일치하는 게임 계정 없음");
      return res.status(200).send("User not found (logged)");
    }

    const userDoc = snapshot.docs[0];
    const userRef = userDoc.ref;
    const userData = userDoc.data();

    let inventory = userData.inventory || [];
    let currentExp = userData.exp || 0;
    let realLevel = calcLevel(currentExp); // 찐 레벨 판독
    const today = getTodayKST();

    let isInventoryUpdated = false;
    let needsRefund = false;
    let refundReason = "";
    let matchedKnownItem = false;
    let newTicketDate = null;

    for (const [key, itemTemplate] of Object.entries(itemDatabase)) {
      if (purchasedItemName.includes(key)) {
        matchedKnownItem = true;

        // 🚫 1. 스킨 검사 (계정당 1회 & 레벨 & 승급 자격)
        if (itemTemplate.limitType === "ONCE") {
          const alreadyOwns = inventory.some(i => i.name === itemTemplate.name);
          const meetsLevel = realLevel >= itemTemplate.reqLevel;
          // 🏅 승급 자격: 유저 rank가 요구 rank 이상이어야 함(승급 퀘스트 통과 필요)
          const userRank = userData.rank || "초보";
          const reqRankIdx = itemTemplate.reqRank ? RANK_ORDER.indexOf(itemTemplate.reqRank) : -1;
          const userRankIdx = RANK_ORDER.indexOf(userRank);
          const meetsRank = reqRankIdx < 0 || userRankIdx >= reqRankIdx;

          if (alreadyOwns) {
            needsRefund = true;
            refundReason = "이미 보유 중인 스킨을 중복 구매함";
          } else if (!meetsLevel) {
            needsRefund = true;
            refundReason = `레벨 미달 (요구: Lv.${itemTemplate.reqLevel}, 현재: Lv.${realLevel})`;
          } else if (!meetsRank) {
            needsRefund = true;
            refundReason = `승급 미달 (요구: ${itemTemplate.reqRank} 승급, 현재: ${userRank}) — 광장 아라 NPC의 승급 퀘스트를 먼저 완료하세요`;
          } else {
            inventory.push({ ...itemTemplate });
            isInventoryUpdated = true;
          }
        }

        // 🎟️ 2. 이용권 검사 (1일 1회 제한)
        else if (itemTemplate.limitType === "DAILY") {
          const lastTicketDate = userData.lastTicketDate || "";

          if (lastTicketDate === today) {
            needsRefund = true;
            refundReason = "1시간 이용권 1일 1회 구매 제한 초과";
          } else {
            let newItem = { ...itemTemplate };
            newItem.quantity = 1;
            inventory.push(newItem);
            newTicketDate = today; // 오늘 샀다고 도장 쾅!
            isInventoryUpdated = true;
          }
        }
      }
    }

    // 🛑 [실패 로그] 등록된 키워드와 맞는 상품이 없음 (아임웹 상품명 오타/누락 → 수동 확인)
    if (!matchedKnownItem) {
      await logPaymentIssue(buyerEmail, purchasedItemName, orderNo, "상품명이 등록된 키워드와 일치하지 않음");
      return res.status(200).send("Unknown product (logged)");
    }

    // 🚨 3. 규정 위반 결제 발생! -> 환불 장부에 기록
    if (needsRefund) {
      await admin.firestore().collection("refund_requests").add({
        email: buyerEmail,
        itemName: purchasedItemName,
        orderNo: orderNo || "(없음)",
        reason: refundReason,
        status: "환불 처리 대기중",
        requestedAt: admin.firestore.FieldValue.serverTimestamp()
      });
      console.log(`[환불 요망] ${buyerEmail}님이 규정을 어기고 결제함: ${refundReason}`);
    }

    // 🎁 4. 정상 결제 -> 인벤토리 저장
    if (isInventoryUpdated) {
      let updates = { inventory: inventory };
      if (newTicketDate) updates.lastTicketDate = newTicketDate;
      await userRef.update(updates);
      console.log(`[지급 완료] ${buyerEmail} 님에게 아이템이 정상 지급되었습니다.`);
    }

    // 🔁 [보안 2] 처리 완료한 주문번호 기록 (다음에 같은 주문 오면 위에서 걸러짐)
    if (orderNo) {
      await admin.firestore().collection("processed_orders").doc(String(orderNo)).set({
        email: buyerEmail,
        itemName: purchasedItemName,
        granted: isInventoryUpdated,
        refunded: needsRefund,
        processedAt: admin.firestore.FieldValue.serverTimestamp()
      });
    }

    return res.status(200).send("Webhook Success");

  } catch (error) {
    console.error("서버 처리 중 에러 발생:", error);
    return res.status(500).send("Server Error");
  }
});

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