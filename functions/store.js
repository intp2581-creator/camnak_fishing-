// 🛒 [게임스토어 상품 관리] 상품을 코드가 아니라 Firestore로 관리한다.
//   지금까지 상품이 hub/store.html 안에 배열로 박혀 있어, 하나 추가하려면
//   코드를 고치고 배포해야 했다. 상품은 계속 늘어나므로 운영자가 직접
//   추가·수정할 수 있어야 한다(2026-09-02 신설).
//
//   GET  ?list=1            노출 상품 목록 (누구나 — 스토어 화면용)
//   GET  ?all=1             전체 목록 (GM만 — 숨김 포함)
//   GET  ?keys=1            지급 키 목록 (GM만 — 코드 지급표 + 관리 화면에서 만든 것)
//   GET  ?bundleItems=1     상자에 담을 수 있는 아이템 목록 (GM만)
//   POST {action:"save"}    추가·수정 (GM만)
//   POST {action:"delete"}  삭제 (GM만)
//   POST {action:"sort"}    순서 일괄 저장 (GM만)
//   POST {action:"upload"}  상품 이미지 업로드 (GM만) → 주소를 돌려준다
//
//   ⚠️ 게임 안 KREFT 상점(낚싯대·릴·미끼)은 여기서 다루지 않는다.
//      파워·레벨게이트는 밸런스 수치라 코드에 두는 편이 안전하다.

const {onRequest} = require("firebase-functions/v2/https");
const admin = require("firebase-admin");

// 지급표 — 결제가 끝나면 이 표를 보고 물건을 넣어준다.
// 상품의 '지급 키'는 반드시 이 표에 있는 키여야 한다.
const {PRODUCTS} = require("./payment");

const COL = "store_products";
const CATS = ["ticket", "skin", "badge", "package", "etc"];
const BADGES = ["NEW", "BEST", "HOT", "EVENT"];

/// 'YYYY-MM-DDTHH:mm' 만 통과시킨다(한국시간으로 읽는다). 아니면 빈 값.
function dtStr(v) {
  const s = String(v || "").trim();
  return /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}$/.test(s) ? s : "";
}

// 🖼️ 상품 이미지 저장. 화면에서 미리 줄여 보내므로 여기선 용량만 본다.
//   파일 이름에 시각을 붙인다 — 같은 이름으로 덮어쓰면 브라우저가 옛 그림을
//   캐시에서 꺼내와 '바꿨는데 안 바뀐다'가 된다.
async function saveImage(dataUri, name) {
  const m = String(dataUri || "").match(/^data:(image\/(?:jpeg|png|webp));base64,(.+)$/);
  if (!m) throw new Error("이미지 파일만 올릴 수 있습니다 (jpg · png · webp)");
  const buf = Buffer.from(m[2], "base64");
  if (buf.length > 2 * 1024 * 1024) throw new Error("이미지가 2MB를 넘습니다. 조금 줄여서 올려 주세요");
  const ext = m[1] === "image/png" ? "png" : (m[1] === "image/webp" ? "webp" : "jpg");
  const safe = String(name || "item").toLowerCase()
      .replace(/[^a-z0-9._-]+/g, "-").replace(/\.[a-z0-9]+$/, "").slice(0, 40) || "item";
  const path = "store/" + safe + "-" + Date.now() + "." + ext;
  const bucket = admin.storage().bucket();
  const file = bucket.file(path);
  await file.save(buf, {
    metadata: {contentType: m[1], cacheControl: "public,max-age=31536000,immutable"},
  });
  await file.makePublic();
  return "https://storage.googleapis.com/" + bucket.name + "/" + path;
}

async function gm(req) {
  const m = String(req.get("Authorization") || "").match(/^Bearer\s+(.+)$/i);
  if (!m) throw new Error("로그인이 필요합니다");
  const dec = await admin.auth().verifyIdToken(m[1]);
  const d = await admin.firestore().collection("users").doc(dec.uid).get();
  if (!d.exists || d.data().isGm !== true) throw new Error("운영자만 가능합니다");
  return {uid: dec.uid, nick: d.data().nickname || ""};
}

// 📦 지급 구성표를 다듬는다. 여기 없는 필드는 버린다 — 화면에서 뭘 보내든
//    서버가 아는 모양으로만 저장해야 나중에 지급이 안전하다.
function cleanGrant(g) {
  if (!g || typeof g !== "object") return null;
  const bundle = (Array.isArray(g.bundle) ? g.bundle : []).slice(0, 20).map((it) => {
    const o = {
      name: String(it.name || "").trim().slice(0, 40),
      qty: Math.max(1, Math.min(999, parseInt(it.qty, 10) || 1)),
      category: String(it.category || "COMMON").trim().slice(0, 20),
      type: String(it.type || "ETC").trim().slice(0, 20),
      icon: String(it.icon || "").trim().slice(0, 120),
    };
    if (String(it.desc || "").trim()) o.desc = String(it.desc).trim().slice(0, 300);
    // 능력치는 세 값만. 0 이면 넣지 않는다(빈 stats 가 남으면 화면이 지저분해진다).
    const st = {};
    ["P", "C", "S"].forEach((k) => {
      const v = parseInt((it.stats || {})[k], 10) || 0;
      if (v) st[k] = v;
    });
    if (Object.keys(st).length) o.stats = st;
    // 기간제(엠블럼류) — 초 단위. 있으면 '아직 안 켠' 상태로 넣는다.
    const sec = parseInt(it.secLeft, 10) || 0;
    if (sec > 0) { o.secLeft = sec; o.active = false; }
    if (it.boost) o.boost = String(it.boost).trim().slice(0, 20);
    if (it.cash === true) o.cash = true;
    return o;
  }).filter((it) => it.name);
  const out = {
    price: Math.max(0, parseInt(g.price, 10) || 0),
    limitType: g.limitType === "ONCE" ? "ONCE" : "STACK",
    bundle,
  };
  const mq = parseInt(g.maxQty, 10) || 0;
  if (mq > 0) out.maxQty = Math.min(10, mq);
  const rl = parseInt(g.reqLevel, 10) || 0;
  if (rl > 0) out.reqLevel = rl;
  if (String(g.boxName || "").trim()) {
    out.boxName = String(g.boxName).trim().slice(0, 40);
    out.boxIcon = String(g.boxIcon || "item_box_cash.png").trim().slice(0, 120);
    out.boxMsg = String(g.boxMsg || "눌러서 열면 아이템을 받습니다.").trim().slice(0, 300);
  }
  return out;
}

function clean(b) {
  const cat = CATS.indexOf(String(b.c)) > -1 ? String(b.c) : "etc";
  return {
    c: cat,
    key: String(b.key || "").trim().slice(0, 40),
    n: String(b.n || "").trim().slice(0, 60),
    p: Math.max(0, parseInt(b.p, 10) || 0),
    lv: Math.max(0, parseInt(b.lv, 10) || 0),
    idx: Math.max(0, parseInt(b.idx, 10) || 0),   // 아임웹 상품번호(임시 결제 경로)
    img: String(b.img || "").trim().slice(0, 120),
    d: String(b.d || "").trim().slice(0, 500),
    detail: String(b.detail || "").trim().slice(0, 4000),
    hidden: b.hidden === true,
    soon: b.soon === true,      // 🕒 진열은 하되 아직 판매 전(구매 버튼 잠금)
    soonText: String(b.soonText || "").trim().slice(0, 40),  // 예: "9월 5일 판매 시작"
    order: Math.max(0, parseInt(b.order, 10) || 0),
    // 🏷️ 카드에 붙는 강조 배지. 빈 값이면 안 붙는다.
    badge: BADGES.indexOf(String(b.badge)) > -1 ? String(b.badge) : "",
    // 🗓️ 판매기간 — 'YYYY-MM-DDTHH:mm' 문자열(한국시간). 비우면 제한 없음.
    //    자리를 비워도 정해둔 때에 열리고 닫히게 하려는 것이다.
    soldFrom: dtStr(b.soldFrom),
    soldTo: dtStr(b.soldTo),
    // 🛒 구매 제한. 0 이면 제한 없음.
    //    perAccount 1 = 계정당 1개(스킨·뱃지) · perOrder = 한 번에 살 수 있는 수량
    perAccount: Math.max(0, Math.min(99, parseInt(b.perAccount, 10) || 0)),
    perOrder: Math.max(0, Math.min(99, parseInt(b.perOrder, 10) || 0)),
  };
}

/// 지금 파는 중인가 — 판매기간을 반영한 상태.
///   'on'(판매중) · 'soon'(아직 시작 전이거나 준비중) · 'off'(숨김·종료)
function saleState(v) {
  if (v.hidden === true) return "off";
  const now = Date.now();
  const from = v.soldFrom ? Date.parse(v.soldFrom + "+09:00") : 0;
  const to = v.soldTo ? Date.parse(v.soldTo + "+09:00") : 0;
  if (to && now > to) return "off";        // 기간이 끝나면 내린다
  if (from && now < from) return "soon";   // 아직 시작 전이면 진열만
  return v.soon === true ? "soon" : "on";
}

exports.storeApi = onRequest({region: "us-central1", cors: true}, async (req, res) => {
  res.set("Access-Control-Allow-Origin", "*");
  res.set("Access-Control-Allow-Headers", "Content-Type, Authorization");
  res.set("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
  if (req.method === "OPTIONS") return res.status(204).send("");

  const db = admin.firestore();
  const col = db.collection(COL);

  try {
    // ── 목록(공개) ─────────────────────────────
    if (req.method === "GET" && req.query.list) {
      const s = await col.limit(200).get();
      const rows = [];
      s.forEach((doc) => {
        const v = doc.data();
        // 🗓️ 숨김이거나 판매기간이 끝났으면 목록에서 뺀다.
        //    시작 전(soon)은 진열하되 구매 버튼이 잠긴다.
        const st = saleState(v);
        if (st === "off") return;
        // 수량을 여러 개 살 수 있는지, 상자로 지급되는지는 지급표가 정한다.
        // 화면이 제 나름대로 짐작하면 '주문서와 다른 안내'가 되어 분쟁이 된다.
        // 코드 지급표가 먼저, 없으면 관리 화면에서 저장한 지급 구성을 본다.
        // ⚠️ 예전엔 PRODUCTS 만 봐서, 관리 화면으로 만든 상품은 상자로 지급하도록
        //    저장해도 box:false 로 나갔다. 상세페이지의 청약철회 안내가 box 로
        //    갈리므로(product.html), 상자인데 '낱개' 문구가 나가 분쟁이 될 자리였다.
        //    수량 제한(stack·max)도 마찬가지로 무시되고 있었다.
        const g = PRODUCTS[v.key] || v.grant || null;
        rows.push({id: doc.id, ...v,
          soon: st === "soon",                 // 기간 전이면 코드가 잠근다
          stack: !!(g && g.limitType === "STACK"),
          max: (g && g.maxQty) || (g && g.limitType === "STACK" ? 10 : 1),
          box: !!(g && g.boxName)});
      });
      rows.sort((a, b) => (a.order || 0) - (b.order || 0));
      return res.json({ok: true, items: rows});
    }

    // ── 지급 키 목록(운영자) ──────────────────
    //   관리 화면이 이 목록으로 드롭다운을 만든다. 손으로 치면 오타가 나고,
    //   오타는 '결제는 됐는데 물건이 안 들어온' 문의가 되어 돌아온다.
    if (req.method === "GET" && req.query.keys) {
      await gm(req);
      const used = {};
      const s = await col.limit(200).get();
      s.forEach((doc) => {
        const k = doc.data().key;
        if (k) used[k] = (used[k] || 0) + 1;
      });
      const keys = Object.keys(PRODUCTS).map((k) => ({
        key: k,
        name: PRODUCTS[k].name,
        price: PRODUCTS[k].price,
        limitType: PRODUCTS[k].limitType || "",
        reqLevel: PRODUCTS[k].reqLevel || 0,
        box: !!PRODUCTS[k].boxName,          // 상자로 지급되는 상품인가
        used: used[k] || 0,                  // 이미 이 키를 쓰는 상품 수
        code: true,                          // 코드 지급표에 있는 키(고칠 수 없다)
      }));
      // 관리 화면에서 만든 키도 함께 — 고를 수 있어야 다시 편집할 수 있다.
      s.forEach((doc) => {
        const v = doc.data();
        if (!v.key || PRODUCTS[v.key]) return;
        if (keys.some((x) => x.key === v.key)) return;
        const g = v.grant || {};
        keys.push({key: v.key, name: v.n || v.key, price: g.price || 0,
          limitType: g.limitType || "STACK", reqLevel: g.reqLevel || 0,
          box: !!g.boxName, used: used[v.key] || 0, code: false});
      });
      return res.json({ok: true, keys});
    }

    // ── 상자에 담을 수 있는 아이템(운영자) ──────
    //   지금 실제로 지급되고 있는 것들에서 뽑는다. 손으로 목록을 따로 적어 두면
    //   아이콘 이름이나 분류가 어긋나 '가방에서 그림이 깨지는' 아이템이 생긴다.
    if (req.method === "GET" && req.query.bundleItems) {
      await gm(req);
      const seen = {};
      Object.keys(PRODUCTS).forEach((k) => {
        (PRODUCTS[k].bundle || []).forEach((it) => {
          if (!it || !it.name || seen[it.name]) return;
          seen[it.name] = {name: it.name, category: it.category || "COMMON",
            type: it.type || "ETC", icon: it.icon || "",
            stats: it.stats || null, desc: it.desc || "",
            boost: it.boost || "", secLeft: it.secLeft || 0,
            cash: it.cash === true};
        });
      });
      // 상자 없이 낱개로 지급되는 상품(이용권 등)도 담을 수 있어야 한다.
      Object.keys(PRODUCTS).forEach((k) => {
        const p = PRODUCTS[k];
        if (p.bundle || !p.name || seen[p.name]) return;
        seen[p.name] = {name: p.name, category: "TICKET", type: "ETC",
          icon: "", stats: null, desc: "", boost: "", secLeft: 0, cash: true};
      });
      return res.json({ok: true, items: Object.values(seen)});
    }

    // ── 목록(운영자 — 숨김 포함) ────────────────
    if (req.method === "GET" && req.query.all) {
      await gm(req);
      const s = await col.limit(200).get();
      const rows = [];
      s.forEach((doc) => {
        const v = doc.data();
        // 화면이 판매기간까지 계산하지 않도록 서버가 지금 상태를 알려준다.
        rows.push({id: doc.id, ...v, state: saleState(v)});
      });
      rows.sort((a, b) => (a.order || 0) - (b.order || 0));
      return res.json({ok: true, items: rows});
    }

    if (req.method !== "POST") return res.status(405).json({ok: false, err: "method"});
    const u = await gm(req);
    const b = req.body || {};
    const action = String(b.action || "");

    if (action === "save") {
      const data = clean(b);
      if (!data.n) return res.status(400).json({ok: false, err: "상품명을 입력해 주세요"});
      if (!data.key) return res.status(400).json({ok: false, err: "지급 키를 골라 주세요"});
      // 📦 지급 구성표. 코드 지급표에 있는 키는 코드가 이기므로 저장하지 않는다
      //    (저장해 두면 '여기서 고쳤는데 왜 안 바뀌지'가 된다).
      if (PRODUCTS[data.key]) {
        data.grant = admin.firestore.FieldValue.delete();
      } else {
        const g = cleanGrant(b.grant);
        // 지급표에도 없고 구성표도 없으면 결제만 되고 물건이 안 들어간다.
        // 아직 정하지 못했으면 '판매 준비중'으로 두고 진열만 할 수 있다.
        if ((!g || !g.bundle.length) && !data.soon) {
          return res.status(400).json({ok: false,
            err: "이 지급 키는 코드 지급표에 없습니다. 무엇을 줄지(지급 구성)를 " +
                 "정해 주세요. 아직 못 정하셨으면 '판매 준비중'으로 두시면 됩니다."});
        }
        if (g && g.bundle.length) {
          // 🛒 구매 제한은 화면에서 따로 받지만, 결제 서버가 보는 곳은 grant 다.
          if (data.perAccount === 1) g.limitType = "ONCE";
          if (data.perOrder > 0) g.maxQty = data.perOrder;
          if (data.lv > 0) g.reqLevel = data.lv;
          if (!(g.price > 0)) {
            return res.status(400).json({ok: false,
              err: "실제 결제 금액을 입력해 주세요. 이 금액으로 결제됩니다."});
          }
          data.grant = g;
        } else if (b.grant) {
          data.grant = cleanGrant(b.grant) || {};
        }
      }
      // 지급 키 모양 검사 — 영문 소문자·숫자·밑줄. 나중에 코드로 옮길 때도 쓴다.
      if (!/^[a-z][a-z0-9_]{2,39}$/.test(data.key)) {
        return res.status(400).json({ok: false,
          err: "지급 키는 영문 소문자로 시작하고 소문자·숫자·밑줄만 쓸 수 있습니다 " +
               "(3~40자). 예: pet_husky"});
      }
      // 같은 지급 키를 쓰는 상품이 이미 있으면 알려준다(막지는 않는다 —
      // 노출용·숨김용으로 일부러 둘 수 있다).
      let dup = 0;
      const ds = await col.where("key", "==", data.key).limit(5).get();
      ds.forEach((doc) => { if (doc.id !== String(b.id || "")) dup++; });
      data.updatedAt = admin.firestore.FieldValue.serverTimestamp();
      data.updatedBy = u.nick;
      // 화면에 띄울 주의사항 — 막을 정도는 아니지만 그냥 넘기면 나중에 문제가 된다.
      const notes = [];
      const gp = PRODUCTS[data.key];
      if (gp && gp.price !== data.p) {
        notes.push("표시 가격(" + data.p.toLocaleString() + "원)이 실제 결제 금액(" +
          gp.price.toLocaleString() + "원)과 다릅니다. 결제는 서버 금액으로 됩니다.");
      }
      if (dup) notes.push("같은 지급 키를 쓰는 상품이 " + dup + "개 더 있습니다.");
      if (!data.idx && !data.soon) notes.push("아임웹 상품번호가 없어 구매하기가 연결되지 않습니다.");

      if (b.id) {
        await col.doc(String(b.id)).set(data, {merge: true});
        return res.json({ok: true, id: String(b.id), notes});
      }
      data.createdAt = admin.firestore.FieldValue.serverTimestamp();
      const doc = await col.add(data);
      return res.json({ok: true, id: doc.id, notes});
    }

    if (action === "delete") {
      const id = String(b.id || "");
      if (!id) return res.status(400).json({ok: false, err: "id 없음"});
      await col.doc(id).delete();
      console.log("[상품 삭제] " + id + " (by " + u.nick + ")");
      return res.json({ok: true});
    }

    // 🖼️ 이미지 업로드 — 주소만 돌려준다. 상품에 넣는 것은 저장할 때.
    if (action === "upload") {
      const url = await saveImage(b.data, b.name);
      console.log("[상품 이미지] " + url + " (by " + u.nick + ")");
      return res.json({ok: true, url});
    }

    // 순서 일괄 저장 — [{id, order}, ...]
    if (action === "sort") {
      const rows = Array.isArray(b.rows) ? b.rows.slice(0, 200) : [];
      const batch = db.batch();
      rows.forEach((r) => {
        if (!r || !r.id) return;
        batch.update(col.doc(String(r.id)), {order: parseInt(r.order, 10) || 0});
      });
      await batch.commit();
      return res.json({ok: true, n: rows.length});
    }

    return res.status(400).json({ok: false, err: "알 수 없는 요청"});
  } catch (e) {
    // 로그인·권한 문제만 401. 나머지는 400 으로 — 전부 401 로 내려보내면
    // 화면에 '로그인이 필요합니다'로 보여 진짜 원인이 가려진다.
    const msg = String(e.message || e);
    const authErr = msg.indexOf("로그인") > -1 || msg.indexOf("운영자") > -1;
    return res.status(authErr ? 401 : 400).json({ok: false, err: msg});
  }
});
