const functions = require("firebase-functions");
const admin = require("firebase-admin");

admin.initializeApp();

// 📖 [아이템 사전 및 구매 조건 설정]
const itemDatabase = {
  "1시간 이용권": { 
    name: "대회 1시간 이용권", 
    category: "TICKET", type: "ETC", icon: "item_ticket_1h.png",
    limitType: "DAILY" // 👈 1일 1회 제한
  },
  "스킨(하수)": {
    name: "하수 조사",
    reqLevel: 5, // 👈 레벨 제한 (5레벨 이상만) - 상점 표시와 일치
    category: "SKIN", type: "SKIN", icon: "../images/skin_novice.jpg", stats: { P: 20, C: 20, S: 20 },
    limitType: "ONCE"  // 👈 계정당 1회 한정
  },
  "스킨(중수)": {
    name: "중수 조사",
    reqLevel: 10,
    category: "SKIN", type: "SKIN", icon: "../images/skin_intermediate.jpg", stats: { P: 50, C: 50, S: 50 },
    limitType: "ONCE"
  },
  "스킨(고수)": {
    name: "고수 조사",
    reqLevel: 15,
    category: "SKIN", type: "SKIN", icon: "../images/skin_expert.jpg", stats: { P: 100, C: 100, S: 100 },
    limitType: "ONCE"
  }
  ,
  "스킨(프로)": {
    name: "프로 조사",
    reqLevel: 20,
    category: "SKIN", type: "SKIN", icon: "../images/skin_pro.jpg", stats: { P: 200, C: 200, S: 200 },
    limitType: "ONCE"
  },
  "스킨(마스터)": {
    name: "마스터 조사",
    reqLevel: 25,
    category: "SKIN", type: "SKIN", icon: "../images/skin_master.jpg", stats: { P: 300, C: 300, S: 300 },
    limitType: "ONCE"
  }
};

// 🕒 한국 시간(KST) 기준으로 오늘 날짜(YYYY-MM-DD) 구하는 함수
function getTodayKST() {
  const curr = new Date();
  const utc = curr.getTime() + (curr.getTimezoneOffset() * 60 * 1000);
  const kstTime = new Date(utc + (9 * 60 * 60 * 1000));
  return kstTime.toISOString().substring(0, 10);
}

// 📈 1~30레벨 경험치 표 (사장님 마음대로 수정 가능!)
const expTable = [
  0,        // 인덱스 0 (안 씀)
  0,        // Lv.1
  5000,     // Lv.2
  10000,    // Lv.3
  42000,    // Lv.4
  102000,   // Lv.5
  150000,   // Lv.6 (하수 스킨!)
  200000,   // Lv.7
  250000,   // Lv.8
  300000,   // Lv.9
  350000,   // Lv.10
  420000,   // Lv.11 (중수 스킨!)
  500000,   // Lv.12
  580000,   // Lv.13
  660000,   // Lv.14
  750000,   // Lv.15
  850000,   // Lv.16 (고수 스킨!)
  950000,   // Lv.17
  1050000,  // Lv.18
  1150000,  // Lv.19
  1250000,  // Lv.20
  1400000,  // Lv.21 (프로 스킨!)
  1550000,  // Lv.22
  1700000,  // Lv.23
  1850000,  // Lv.24
  2000000,  // Lv.25
  2200000,  // Lv.26 (마스터 스킨!)
  2400000,  // Lv.27
  2600000,  // Lv.28
  2800000,  // Lv.29
  3000000   // Lv.30 (현재 만렙!)
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

        // 🚫 1. 스킨 검사 (계정당 1회 & 레벨 제한)
        if (itemTemplate.limitType === "ONCE") {
          const alreadyOwns = inventory.some(i => i.name === itemTemplate.name);
          const meetsLevel = realLevel >= itemTemplate.reqLevel;

          if (alreadyOwns) {
            needsRefund = true;
            refundReason = "이미 보유 중인 스킨을 중복 구매함";
          } else if (!meetsLevel) {
            needsRefund = true;
            refundReason = `레벨 미달 (요구: Lv.${itemTemplate.reqLevel}, 현재: Lv.${realLevel})`;
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