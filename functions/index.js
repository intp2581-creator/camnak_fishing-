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
  "하수 스킨": { 
    name: "하수 조사", 
    reqLevel: 6, // 👈 레벨 제한 (6레벨 이상만)
    category: "SKIN", type: "SKIN", icon: "../images/skin_novice.jpg", stats: { P: 20, C: 20, S: 20 },
    limitType: "ONCE"  // 👈 계정당 1회 한정
  },
  "중수 스킨": { 
    name: "중수 조사", 
    reqLevel: 11,
    category: "SKIN", type: "SKIN", icon: "../images/skin_intermediate.jpg", stats: { P: 50, C: 50, S: 50 },
    limitType: "ONCE"
  },
  "고수 스킨": { 
    name: "고수 조사", 
    reqLevel: 16,
    category: "SKIN", type: "SKIN", icon: "../images/skin_expert.jpg", stats: { P: 100, C: 100, S: 100 },
    limitType: "ONCE"
  }
  ,
  "프로 스킨": { 
    name: "프로 조사", 
    reqLevel: 21,
    category: "SKIN", type: "SKIN", icon: "../images/skin_pro.jpg", stats: { P: 200, C: 200, S: 200 },
    limitType: "ONCE"
  },
  "마스터 스킨": { 
    name: "마스터 조사", 
    reqLevel: 26,
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

exports.imwebWebhook = functions.https.onRequest(async (req, res) => {
  try {
    const data = req.body;
    const buyerEmail = data.buyer_email; 
    const status = data.status; 
    const purchasedItemName = data.order_name || ""; 

    if (status === "PAY_COMPLETE") {
      const usersRef = admin.firestore().collection("users");
      const snapshot = await usersRef.where("email", "==", buyerEmail).get();

      if (snapshot.empty) return res.status(200).send("User not found");

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

      for (const [key, itemTemplate] of Object.entries(itemDatabase)) {
        if (purchasedItemName.includes(key)) {
          
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
              userData.lastTicketDate = today; // 오늘 샀다고 도장 쾅!
              isInventoryUpdated = true;
            }
          }
        }
      }

      // 🚨 3. 규정 위반 결제 발생! -> 환불 장부에 기록
      if (needsRefund) {
        await admin.firestore().collection("refund_requests").add({
          email: buyerEmail,
          itemName: purchasedItemName,
          reason: refundReason,
          status: "환불 처리 대기중",
          requestedAt: admin.firestore.FieldValue.serverTimestamp()
        });
        console.log(`[환불 요망] ${buyerEmail}님이 규정을 어기고 결제함: ${refundReason}`);
      }

      // 🎁 4. 정상 결제 -> 인벤토리 저장
      if (isInventoryUpdated) {
        let updates = { inventory: inventory };
        if (userData.lastTicketDate === today) updates.lastTicketDate = today;
        await userRef.update(updates);
        console.log(`[지급 완료] ${buyerEmail} 님에게 아이템이 정상 지급되었습니다.`);
      }
    }

    res.status(200).send("Webhook Success");

  } catch (error) {
    console.error("서버 처리 중 에러 발생:", error);
    res.status(500).send("Server Error");
  }
});