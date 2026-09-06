// 📦 게임스토어 상품 정보 (공용)
//
//   상품 상세(product.html)와 주문서(order.html)가 같은 값을 본다.
//   두 벌로 두면 가격·구성품이 어긋나고, 어긋나면 그게 곧 분쟁이 된다.
//   ⚠️ 실제 결제 금액은 서버(functions/payment.js PRODUCTS)에서만 정한다.
//      여기 값은 '보여주기용'이다. 둘이 다르면 서버 값이 이긴다.
//
//   2026-09-06 checkout.html 에서 떼어냄.

// 💳 포트원 채널키. PG 승인이 순차로 나므로, 승인된 것만 on:true 로 바꾸고
//    그 PG 의 채널키를 channel 에 넣으면 열린다.
//    ⚠️ 지금은 '테스트 채널' — 실연동 승인 뒤 실제 키로 바꿔야 한다.
const CHANNEL_KEY = 'channel-key-bda1f518-2031-435c-98bc-e2f2d66f189f';

const PAY_METHODS = [
  {key:'CARD',  label:'신용·체크카드', ic:'💳', on:true,  channel:CHANNEL_KEY, pay:'CARD'},
  {key:'KAKAO', label:'카카오페이',   ic:'🟡', on:false, channel:'', pay:'EASY_PAY', ep:'EASY_PAY_PROVIDER_KAKAOPAY'},
  {key:'NAVER', label:'네이버페이',   ic:'🟢', on:false, channel:'', pay:'EASY_PAY', ep:'EASY_PAY_PROVIDER_NAVERPAY'},
  {key:'TOSS',  label:'토스페이',     ic:'🔵', on:false, channel:'', pay:'EASY_PAY', ep:'EASY_PAY_PROVIDER_TOSSPAY'},
];
let payM = PAY_METHODS.find(m => m.on) || null;   // 지금 고른 결제수단

// 🛒 상품 표시 정보(가격은 서버가 정한다 — 여기 값은 화면용일 뿐)
const CATALOG = {
  ticket_1h:    {n:'낚시 1시간 이용권', p:1100,  img:'assets/st-ticket1h.jpg', d:'낚시 시간을 1시간 늘려줍니다', stack:true},
  ticket_arena: {n:'아레나 입장권',     p:1100,  img:'assets/st-arena.jpg',    d:'아레나에 하루 1회 더 참가', stack:true},
  skin_novice:  {n:'하수 조사',   p:2200,  img:'assets/st-skin1.jpg', d:'Lv.10 · 하수 이상'},
  skin_mid:     {n:'중수 조사',   p:5500,  img:'assets/st-skin2.jpg',    d:'Lv.30 · 중수 이상'},
  skin_expert:  {n:'고수 조사',   p:11000, img:'assets/st-skin3.jpg', d:'Lv.50 · 고수 이상'},
  skin_pro:     {n:'프로 조사',   p:22000, img:'assets/st-skin4.jpg',    d:'Lv.70 · 프로 이상'},
  skin_master:  {n:'마스터 조사', p:55000, img:'assets/st-skin5.jpg', d:'Lv.100 · 마스터 이상'},
  badge_1:      {n:'캠피싱 뱃지',      p:2200,  img:'assets/st-badge1.jpg', d:'Lv.10 이상'},
  badge_2:      {n:'캠피싱 휘장',      p:5500,  img:'assets/st-badge2.jpg', d:'Lv.30 이상'},
  badge_3:      {n:'KREFT 정예 휘장', p:11000, img:'assets/st-badge3.jpg', d:'Lv.50 이상'},
  growth_pack:  {n:'KREFT 성장패키지', p:5500, img:'assets/st-package.jpg', stack:true, max:1, box:true,
                 d:'시작이 반! 성장에 필요한 것을 한 번에 담았습니다. 5종 구성품이 상자에 담겨 지급됩니다.'},
};

// 📄 상세 표시용 — 게임 안 값(game_config.dart)과 같아야 한다.
//    stat: 장착 시 오르는 능력치 · use: 쓰는 법 · cond: 이용 조건
const DETAIL = {
  ticket_1h:    {use:'가방에서 눌러 사용하면 그 자리에서 낚시 시간이 60분 늘어납니다.',
                 cond:'레벨 제한 없음 · 계정당 하루 1회 사용',   give:'수량 누적(여러 장 보유 가능)'},
  ticket_arena: {use:'무료 입장을 다 쓴 뒤 아레나에 하루 한 번 더 참가할 수 있습니다. 낚시 시간 20분도 함께 채워집니다.',
                 cond:'레벨 제한 없음 · 계정당 하루 1회 사용',   give:'수량 누적(여러 장 보유 가능)'},
  skin_novice:  {stat:20,  cond:'Lv.10 이상 · 「하수」 승급 완료',   give:'계정당 1개'},
  skin_mid:     {stat:50,  cond:'Lv.30 이상 · 「중수」 승급 완료',   give:'계정당 1개'},
  skin_expert:  {stat:100, cond:'Lv.50 이상 · 「고수」 승급 완료',   give:'계정당 1개'},
  skin_pro:     {stat:200, cond:'Lv.70 이상 · 「프로」 승급 완료',   give:'계정당 1개'},
  skin_master:  {stat:300, cond:'Lv.100 이상 · 「마스터」 승급 완료', give:'계정당 1개'},
  badge_1:      {stat:10,  cond:'Lv.10 이상',  give:'계정당 1개'},
  badge_2:      {stat:30,  cond:'Lv.30 이상',  give:'계정당 1개'},
  badge_3:      {stat:50,  cond:'Lv.50 이상',  give:'계정당 1개'},
};
const IS_SKIN = (k) => k.indexOf('skin_') === 0;

// 📄 [긴 상세] html 이 있는 상품은 이 내용을 그대로 보여준다(아임웹 상세와 같은 구성).
const LONG = {
  growth_pack:
    '<h4>구성품 5종</h4>'
    + '<div class="bundle">'
    +   '<div class="b"><img src="assets/item_emblem_boost.jpg" alt="">'
    +     '<b>능력치 엠블럼 1개</b><span>켜면 1시간 동안 힘·컨트롤·감도 각 +10</span></div>'
    +   '<div class="b"><img src="assets/item_potion_exp.jpg" alt="">'
    +     '<b>경험치 물약 10병</b><span>마시면 10분 동안 경험치 2배</span></div>'
    +   '<div class="b"><img src="assets/item_card_kreft.jpg" alt="">'
    +     '<b>KREFT 2배 카드 10장</b><span>쓰면 10분 동안 KREFT 2배</span></div>'
    +   '<div class="b"><img src="assets/st-ticket1h.jpg" alt="">'
    +     '<b>낚시 1시간 이용권 1장</b><span>낚시 시간 1시간 충전</span></div>'
    +   '<div class="b"><img src="assets/st-arena.jpg" alt="">'
    +     '<b>아레나 입장권 1장</b><span>아레나 하루 1회 추가 참가</span></div>'
    + '</div>'
    + '<h4>사용 방법</h4><ul>'
    +   '<li>물약과 카드는 가방에서 눌러 사용합니다. 누른 순간부터 10분간 적용됩니다.</li>'
    +   '<li>엠블럼은 원할 때 켜고 끌 수 있습니다. 잠깐 자리를 비우실 땐 꺼두세요.</li>'
    +   '<li>세 아이템 모두 <b>낚시터에 있는 동안에만</b> 시간이 줄어듭니다. 광장이나 상점에 계실 때는 멈춰 있습니다.</li>'
    +   '<li>엠블럼은 뱃지·휘장과 함께 적용됩니다. 능력치가 더해집니다.</li>'
    +   '<li>물약·카드·엠블럼은 <b>아레나와 보스레이드에서는 적용되지 않습니다.</b></li>'
    + '</ul>'
    + '<h4>이용 방법</h4><ul>'
    +   '<li>이 페이지에서 결제합니다.</li>'
    +   '<li>결제 즉시 게임 계정 가방으로 <b>「성장패키지 상자」</b>가 지급됩니다.</li>'
    +   '<li>가방에서 상자를 <b>눌러 열면</b> 구성품 5종이 가방에 풀립니다.</li>'
    +   '<li>원하실 때 하나씩 눌러 사용하시면 됩니다.</li>'
    + '</ul>'
    + '<h4>유효기간</h4><ul>'
    +   '<li>구매일로부터 <b>1년</b>입니다. 기간 내에 사용하지 않으면 소멸됩니다. (게임 이용약관 제15조)</li>'
    +   '<li>물약·카드·엠블럼은 사용(활성화)한 뒤 정해진 시간이 지나면 사라집니다.</li>'
    + '</ul>'
    + '<h4>구매 전 꼭 읽어주세요</h4><ul>'
    +   '<li><b>디지털 상품</b>입니다. 택배 배송이 없는 게임 내 전용 아이템입니다.</li>'
    +   '<li><b>계정 확인</b> — 결제 계정과 게임 로그인 계정이 같아야 지급됩니다. 다른 계정으로 접속하시면 아이템이 보이지 않습니다.</li>'
    +   '<li><b>보관</b> — 지급된 상자는 가방에 보관되며, 유효기간 안에 원하시는 날 여시면 됩니다.</li>'
    +   '<li>이 상품은 <b>여러 번 구매</b>하실 수 있습니다. (주문 1건당 1개)</li>'
    + '</ul>'
    + '<h4>환불 규정</h4><ul>'
    +   '<li>결제 후 <b>7일 이내, 상자를 열지 않으셨다면</b> 전액 환불(청약철회)됩니다.</li>'
    +   '<li><b>상자를 여신 경우 환불이 제한됩니다.</b> 여는 순간 구성품이 가방으로 지급되어 사용이 시작된 것으로 봅니다.</li>'
    +   '<li>패키지는 묶음으로 구성된 하나의 상품입니다. 구성품을 나누어 환불하지 않습니다. '
    +       '낱개 판매 상품과 금액이 동일하지 않으며(묶음 할인), 구성품에는 개별 금액이 정해져 있지 않습니다.</li>'
    +   '<li>※ 상품 하자 · 오지급 · 중복 결제 시에는 전액 환불 또는 재지급해 드립니다.</li>'
    + '</ul>'
    + '<h4>교환 및 반품 가능 기간</h4><ul>'
    +   '<li>계약내용에 관한 서면을 받은 날부터 7일. 다만 그 서면을 받은 때보다 재화등의 공급이 늦게 이루어진 경우에는 '
    +       '재화등을 공급받거나 공급이 시작된 날부터 7일.</li>'
    +   '<li>공급받은 상품 및 용역의 내용이 표시·광고의 내용과 다르거나 계약내용과 다르게 이행된 경우에는 '
    +       '그 재화등을 공급받은 날부터 3개월 이내, 그 사실을 안 날 또는 알 수 있었던 날부터 30일 이내.</li>'
    +   '<li>디지털 상품 특성상 교환은 제공하지 않습니다.</li>'
    + '</ul>'
    + '<h4>문의</h4>'
    + '<p>intoas@naver.com · 02-487-2581 (평일 09:00~18:00)<br>'
    +   'kreft.co.kr → 고객지원 → 1:1 문의</p>'
    + '<h4>판매자</h4>'
    + '<p>주식회사 안테모사 · 대표 이명선 · 사업자등록번호 499-87-02378<br>'
    +   '통신판매업신고 제2026-충북청주-1745호 · 게임물제작업등록번호 제2026-000020호<br>'
    +   '충북 청주시 흥덕구 · 원산지 대한민국</p>',
};

// 상자로 지급되는 상품 — '열어야' 쓰이기 시작하므로 환불 기준이 다르다.
const IS_BOX = (k) => !!(CATALOG[k] && CATALOG[k].box);
