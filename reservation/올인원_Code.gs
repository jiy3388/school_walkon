/**
 * 체육관 무대 / 무용실 예약 시스템 (Google Apps Script + Google Sheets)
 *
 * 규칙
 *  - 매주 수요일 08:00 에 '다음 주(월~금)' 전체가 열린다. (이미 열린 이번 주도 계속 예약 가능)
 *  - 한 칸 = 1시간.
 *  - 한 사람(학번)이 한 주(월~금)에 최대 2칸.
 *  - 사용 당일 08:00 이후에는 한 주 제한이 풀려, 남은 빈 칸을 추가로 예약할 수 있다.
 *  - 이미 지난 시간은 예약할 수 없다.
 */

// ===== 설정 (여기만 고치면 됩니다) =====
var CONFIG = {
  rooms: ['체육관 무대', '무용실'],
  blockMinutes: 60,           // 한 칸 길이(분)
  // 요일별 칸 시작 시각 (0=일 ... 6=토). 점심 12~13시는 매일, 15·16시는 월/목/금만.
  slotsByDow: {
    1: ['12:00', '15:00'],
    2: ['12:00'],
    3: ['12:00'],
    4: ['12:00', '15:00'],
    5: ['12:00', '15:00']
  },
  maxPerWeek: 2,              // 한 주(월~금) 최대 칸 수
  openWeekday: 3,             // 오픈 요일 (0=일, 1=월, 2=화, 3=수 ...)
  openTime: '08:00',          // 오픈 시각
  releaseTime: '08:00',       // 사용 당일 이 시각부터 제한 해제
  sheetName: '예약',
  blockSheetName: '차단',
  // 예약할 때 보여주고 체크하게 할 사용 주의사항 (학교 상황에 맞게 고치세요)
  notices: {
    // 모든 예약자에게 보이는 공통 사항
    common: [
      '본 시설은 축제 공연 연습 용도로만 사용할 수 있습니다.',
      '예약은 한 팀당 1명만 신청해 주세요. 다른 팀원의 이름이나 학번으로 여러 건을 예약하는 것은 허용되지 않습니다.',
      '학교 일정에 따라 예약이 취소될 수 있으며, 이 경우 다른 시간으로의 예약은 보장되지 않습니다.',
      '예약한 시간을 지켜 사용하고, 사용 후에는 정리정돈하여 사용 전 상태로 되돌려 주세요.',
      '사용 후에는 소등해 주세요.',
      '시설·기구가 파손되면 즉시 담당 선생님께 알려 주세요.',
      '사용하지 않게 되면 미리 예약을 취소해 주세요.'
    ],
    // 해당 장소를 예약한 사람에게만 보이는 사항 (공통 사항 위에 표시)
    rooms: {
      '체육관 무대': [
        '체육관 무대는 무대 위 공간만 사용할 수 있습니다. 무대 아래(체육관 바닥)에서는 다른 학생들이 배드민턴 등 운동을 하고 있을 수 있으니 안전에 유의해 주세요.'
      ],
      '무용실': [
        '무용실 바깥문은 열어 두고 사용해 주세요. 퇴실할 때는 문을 닫고 도어락의 # 버튼을 눌러 잠가 주세요.'
      ]
    }
  }
};

// ===== 웹앱 진입 =====
function doGet() {
  return HtmlService.createHtmlOutput(INDEX_HTML)
    .setTitle('체육관·무용실 예약')
    .addMetaTag('viewport', 'width=device-width, initial-scale=1');
}

// ===== 시간 유틸 (한국시간 기준, 문자열 비교) =====
function kstNow_() {
  return new Date(Date.now() + 9 * 3600 * 1000);
}
function pad_(n) { return (n < 10 ? '0' : '') + n; }
function ymd_(d) { return d.getUTCFullYear() + '-' + pad_(d.getUTCMonth() + 1) + '-' + pad_(d.getUTCDate()); }
function stamp_(d) { return ymd_(d) + 'T' + pad_(d.getUTCHours()) + ':' + pad_(d.getUTCMinutes()); }
function addDays_(d, n) { return new Date(d.getTime() + n * 86400000); }
function dayStart_(d) { return new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate())); }

// 해당 날짜가 열리는 시각: 그 주 월요일 기준 전 주의 오픈 요일 오픈 시각
function openStamp_(date) {
  var dow = date.getUTCDay();
  var monday = addDays_(dayStart_(date), -((dow + 6) % 7));
  var openDay = addDays_(monday, -7 + ((CONFIG.openWeekday + 6) % 7));
  return ymd_(openDay) + 'T' + CONFIG.openTime;
}

// 그 주 월요일 날짜 문자열 (주 단위 묶음 키)
function weekKey_(d) {
  return ymd_(addDays_(dayStart_(d), -((d.getUTCDay() + 6) % 7)));
}

// 예약 대상 날짜: 오늘 ~ 다음 주 금요일 중 평일
function bookableDates_(now) {
  var today = dayStart_(now);
  var dow = today.getUTCDay();
  var thisMonday = addDays_(today, -((dow + 6) % 7));
  var out = [];
  for (var i = 0; i < 14; i++) {
    var d = addDays_(thisMonday, i);
    var wd = d.getUTCDay();
    if (wd === 0 || wd === 6) continue;
    if (ymd_(d) < ymd_(today)) continue;
    out.push(d);
  }
  return out;
}

// ===== 시트 =====
// 시트에 연결된 스크립트면 그 시트를, 독립 스크립트면 처음 실행 시 '시설 예약' 시트를 만들어 계속 사용
function spreadsheet_() {
  var ss = SpreadsheetApp.getActiveSpreadsheet();
  if (ss) return ss;
  var props = PropertiesService.getScriptProperties();
  var id = props.getProperty('SHEET_ID');
  if (id) return SpreadsheetApp.openById(id);
  ss = SpreadsheetApp.create('시설 예약 (체육관 무대·무용실)');
  props.setProperty('SHEET_ID', ss.getId());
  return ss;
}
function sheet_() {
  var ss = spreadsheet_();
  var sh = ss.getSheetByName(CONFIG.sheetName);
  if (!sh) {
    sh = ss.insertSheet(CONFIG.sheetName);
    sh.appendRow(['날짜', '시작', '장소', '학번', '이름', '신청시각', '주의사항 동의']);
    sh.getRange('A:B').setNumberFormat('@');
    sh.getRange('D:D').setNumberFormat('@');
    sh.setFrozenRows(1);
  }
  return sh;
}
function rows_() {
  var sh = sheet_();
  var n = sh.getLastRow();
  if (n < 2) return [];
  return sh.getRange(2, 1, n - 1, 6).getDisplayValues().map(function (r, i) {
    return { row: i + 2, date: r[0], time: r[1], room: r[2], sid: r[3], name: r[4] };
  });
}

// 차단 시트: 시작날짜 | 종료날짜(선택) | 시간(선택) | 장소(선택) | 사유(선택)
function blockSheet_() {
  var ss = spreadsheet_();
  var sh = ss.getSheetByName(CONFIG.blockSheetName);
  if (!sh) {
    sh = ss.insertSheet(CONFIG.blockSheetName);
    sh.appendRow(['시작날짜', '종료날짜(선택)', '시간(선택)', '장소(선택)', '사유(선택)']);
    sh.getRange('A:C').setNumberFormat('@');
    sh.getRange('A1').setNote('예) 2026-12-01 / 하루만 막으면 종료날짜 비움 / 시간을 비우면 그날 전체 / 장소를 비우면 두 곳 모두 / 날짜는 yyyy-mm-dd, 시간은 12:00 형식');
    sh.setFrozenRows(1);
  }
  return sh;
}
function blocks_() {
  var sh = blockSheet_();
  var n = sh.getLastRow();
  if (n < 2) return [];
  return sh.getRange(2, 1, n - 1, 5).getDisplayValues().map(function (r) {
    var from = clean_(r[0]).replace(/\./g, '-').replace(/\s/g, '');
    var to = clean_(r[1]).replace(/\./g, '-').replace(/\s/g, '') || from;
    return { from: from, to: to, time: clean_(r[2]), room: clean_(r[3]), reason: clean_(r[4]) };
  }).filter(function (b) { return /^\d{4}-\d{2}-\d{2}$/.test(b.from); });
}
function blockFor_(blocks, room, date, time) {
  for (var i = 0; i < blocks.length; i++) {
    var b = blocks[i];
    if (date >= b.from && date <= b.to && (!b.time || b.time === time) && (!b.room || b.room === room)) return b;
  }
  return null;
}

// ===== 클라이언트 API =====
function getSchedule() {
  var now = kstNow_();
  var nowS = stamp_(now);
  var dates = bookableDates_(now).map(function (d) {
    var o = openStamp_(d);
    return { date: ymd_(d), dow: d.getUTCDay(), open: nowS >= o, openAt: o, slots: CONFIG.slotsByDow[d.getUTCDay()] || [] };
  });
  var first = dates.length ? dates[0].date : '';
  var bookings = rows_().filter(function (b) { return b.date >= first; })
    .map(function (b) { return { date: b.date, time: b.time, room: b.room, name: b.name, sid: b.sid.slice(-2) }; });
  return {
    now: nowS,
    rooms: CONFIG.rooms,
    blockMinutes: CONFIG.blockMinutes,
    notices: CONFIG.notices,
    blocks: blocks_().filter(function (b) { return b.to >= first; }),
    maxPerWeek: CONFIG.maxPerWeek,
    releaseTime: CONFIG.releaseTime,
    dates: dates,
    bookings: bookings
  };
}

function clean_(s) { return String(s || '').replace(/\s+/g, ' ').trim(); }

function book(room, date, time, sid, name, agreed) {
  sid = clean_(sid); name = clean_(name);
  if (agreed !== true) return { ok: false, msg: '사용 주의사항에 동의(체크)해야 예약할 수 있습니다.' };
  if (!/^\d{4,8}$/.test(sid)) return { ok: false, msg: '학번은 숫자 4~8자리로 입력해 주세요.' };
  if (!name || name.length > 20) return { ok: false, msg: '이름을 입력해 주세요.' };
  if (CONFIG.rooms.indexOf(room) < 0 || (CONFIG.slotsByDow[new Date(date + 'T00:00:00Z').getUTCDay()] || []).indexOf(time) < 0) return { ok: false, msg: '잘못된 요청입니다.' };

  var lock = LockService.getScriptLock();
  lock.waitLock(20000);
  try {
    var now = kstNow_();
    var nowS = stamp_(now);
    var d = new Date(date + 'T00:00:00Z');
    if (isNaN(d.getTime())) return { ok: false, msg: '잘못된 날짜입니다.' };
    var wd = d.getUTCDay();
    if (wd === 0 || wd === 6) return { ok: false, msg: '평일만 예약할 수 있습니다.' };
    if (nowS < openStamp_(d)) return { ok: false, msg: '아직 예약이 열리지 않았습니다. (' + openStamp_(d).replace('T', ' ') + ' 오픈)' };
    if (date + 'T' + time <= nowS) return { ok: false, msg: '이미 지난 시간입니다.' };
    if (date > ymd_(bookableDates_(now).slice(-1)[0])) return { ok: false, msg: '예약 가능한 기간이 아닙니다.' };

    var blk = blockFor_(blocks_(), room, date, time);
    if (blk) return { ok: false, msg: '사용할 수 없는 시간입니다.' + (blk.reason ? ' (' + blk.reason + ')' : '') };

    var all = rows_();
    if (all.some(function (b) { return b.date === date && b.time === time && b.room === room; }))
      return { ok: false, msg: '방금 다른 사람이 예약했습니다.' };

    // 한 주 제한 (당일 releaseTime 이후에는 제한 없음)
    var released = nowS >= date + 'T' + CONFIG.releaseTime;
    if (!released) {
      var mineAll = all.filter(function (b) { return b.sid === sid; });
      var wk = weekKey_(d);
      var thisWeek = mineAll.filter(function (b) { return weekKey_(new Date(b.date + 'T00:00:00Z')) === wk; }).length;
      if (thisWeek >= CONFIG.maxPerWeek)
        return { ok: false, msg: '한 주에 최대 ' + (CONFIG.maxPerWeek * CONFIG.blockMinutes / 60) + '시간까지 예약할 수 있습니다. (사용 당일 ' + CONFIG.releaseTime + ' 이후 추가 예약 가능)' };
    }
    sheet_().appendRow([date, time, room, sid, name, nowS.replace('T', ' '), '동의']);
    return { ok: true, msg: '예약되었습니다.' };
  } finally {
    lock.releaseLock();
  }
}

function cancel(room, date, time, sid, name) {
  sid = clean_(sid); name = clean_(name);
  var lock = LockService.getScriptLock();
  lock.waitLock(20000);
  try {
    var hit = rows_().filter(function (b) {
      return b.date === date && b.time === time && b.room === room;
    })[0];
    if (!hit) return { ok: false, msg: '예약을 찾을 수 없습니다.' };
    if (hit.sid !== sid || hit.name !== name) return { ok: false, msg: '학번/이름이 예약자와 다릅니다.' };
    sheet_().deleteRow(hit.row);
    return { ok: true, msg: '취소되었습니다.' };
  } finally {
    lock.releaseLock();
  }
}


// ===== 화면(HTML) — 아래는 고치지 마세요 =====
var INDEX_HTML = "<!DOCTYPE html>\n<html lang=\"ko\">\n<head>\n<base target=\"_top\">\n<meta charset=\"utf-8\">\n<style>\n  :root { --bg:#f6f7fb; --fg:#1d2433; --card:#fff; --line:#dde1ea; --pri:#2f6fed; --ok:#e8f0ff; --busy:#eceef3; --mine:#d9f5e3; }\n  @media (prefers-color-scheme: dark) { :root { --bg:#14171f; --fg:#e8ebf2; --card:#1d2230; --line:#303749; --pri:#6c9bff; --ok:#223256; --busy:#262c3b; --mine:#1f4331; } }\n  * { box-sizing:border-box; }\n  body { margin:0; padding:16px; background:var(--bg); color:var(--fg); font:16px/1.5 -apple-system,\"Apple SD Gothic Neo\",\"Malgun Gothic\",sans-serif; }\n  .wrap { max-width:560px; margin:0 auto; }\n  h1 { font-size:20px; margin:0 0 4px; }\n  .sub { color:#7a8296; font-size:13px; margin-bottom:12px; }\n  .card { background:var(--card); border:1px solid var(--line); border-radius:12px; padding:12px; margin-bottom:12px; }\n  .row { display:flex; gap:8px; }\n  input { flex:1; min-width:0; padding:10px; border:1px solid var(--line); border-radius:8px; background:var(--bg); color:var(--fg); font-size:16px; }\n  .tabs { display:flex; gap:6px; flex-wrap:wrap; margin-bottom:10px; }\n  .tab { padding:8px 12px; border:1px solid var(--line); border-radius:999px; background:var(--card); color:var(--fg); font-size:14px; cursor:pointer; }\n  .tab.on { background:var(--pri); border-color:var(--pri); color:#fff; }\n  .tab.lock { opacity:.55; }\n  .slot { width:100%; text-align:left; display:flex; justify-content:space-between; padding:12px; margin-bottom:6px; border-radius:10px; border:1px solid var(--line); background:var(--ok); color:var(--fg); font-size:16px; cursor:pointer; }\n  .slot.busy { background:var(--busy); cursor:default; }\n  .slot.mine { background:var(--mine); }\n  .slot:disabled { opacity:.6; cursor:default; }\n  .note { font-size:13px; color:#7a8296; }\n  .modal { position:fixed; inset:0; background:rgba(0,0,0,.5); display:none; align-items:center; justify-content:center; padding:16px; z-index:10; }\n  .modal.on { display:flex; }\n  .sheet { background:var(--card); border-radius:14px; padding:18px; width:100%; max-width:460px; max-height:90vh; overflow:auto; }\n  .sheet h2 { font-size:18px; margin:0 0 4px; }\n  .sheet ul { padding-left:20px; margin:10px 0; }\n  .sheet li { margin-bottom:4px; }\n  .chk { display:flex; gap:10px; align-items:flex-start; padding:12px; border:1px solid var(--line); border-radius:10px; margin:12px 0; cursor:pointer; }\n  .chk input { flex:none; width:22px; height:22px; margin-top:2px; }\n  .btns { display:flex; gap:8px; }\n  .btns button { flex:1; padding:12px; border-radius:10px; border:1px solid var(--line); background:var(--card); color:var(--fg); font-size:16px; cursor:pointer; }\n  .btns button.go { background:var(--pri); border-color:var(--pri); color:#fff; }\n  .btns button:disabled { opacity:.4; cursor:default; }\n  #msg { position:fixed; left:16px; right:16px; bottom:16px; max-width:528px; margin:0 auto; padding:12px 14px; border-radius:10px; background:#1d2433; color:#fff; display:none; }\n  #msg.err { background:#c0392b; }\n</style>\n</head>\n<body>\n<div class=\"wrap\">\n  <h1>체육관 무대 · 무용실 예약</h1>\n  <div class=\"note\" style=\"margin-bottom:12px\">매주 수요일 오전 8시에 다음 주 전체가 열립니다.</div>\n\n  <div class=\"card\">\n    <div class=\"row\">\n      <input id=\"sid\" inputmode=\"numeric\" placeholder=\"학번\" autocomplete=\"off\">\n      <input id=\"name\" placeholder=\"이름\" autocomplete=\"off\">\n    </div>\n    <div class=\"note\" style=\"margin-top:6px\">예약은 팀당 한 주에 최대 2시간까지 신청할 수 있습니다. 사용 당일 오전 8시 이후에 비어 있는 시간이 있으면 추가로 신청할 수 있습니다.</div>\n  </div>\n\n  <div class=\"tabs\" id=\"rooms\"></div>\n  <div class=\"tabs\" id=\"dates\"></div>\n  <div class=\"card\" id=\"slots\"></div>\n</div>\n<div class=\"modal\" id=\"modal\"><div class=\"sheet\">\n  <h2>사용 주의사항</h2>\n  <div class=\"note\" id=\"mWhat\"></div>\n  <ul id=\"mList\"></ul>\n  <label class=\"chk\"><input type=\"checkbox\" id=\"mChk\"><span>위 주의사항을 모두 읽었으며 지키겠습니다.</span></label>\n  <div class=\"btns\"><button id=\"mNo\">취소</button><button class=\"go\" id=\"mYes\" disabled>예약하기</button></div>\n</div></div>\n<div id=\"msg\"></div>\n\n<script>\nvar S = null, room = null, date = null;\nvar DOW = ['일','월','화','수','목','금','토'];\nfunction $(id){ return document.getElementById(id); }\nfunction store(k,v){ try{ if(v===undefined) return localStorage.getItem(k)||''; localStorage.setItem(k,v);}catch(e){return '';} }\nfunction toast(t, err){ var m=$('msg'); m.textContent=t; m.className=err?'err':''; m.style.display='block'; clearTimeout(toast.t); toast.t=setTimeout(function(){m.style.display='none';},3500); }\nfunction md(d){ var p=d.split('-'); return (+p[1])+'/'+(+p[2]); }\n\nfunction load(){\n  google.script.run.withSuccessHandler(function(s){\n    S = s;\n    if(!room) room = s.rooms[0];\n    if(!date || !s.dates.some(function(d){return d.date===date;})) {\n      var firstOpen = s.dates.filter(function(d){return d.open;})[0];\n      date = (firstOpen||s.dates[0]).date;\n    }\n    render();\n  }).withFailureHandler(function(e){ toast('불러오기 실패: '+e.message, true); }).getSchedule();\n}\n\nfunction render(){\n  $('rooms').innerHTML = '';\n  S.rooms.forEach(function(r){\n    var b=document.createElement('button'); b.className='tab'+(r===room?' on':''); b.textContent=r;\n    b.onclick=function(){room=r;render();}; $('rooms').appendChild(b);\n  });\n  $('dates').innerHTML = '';\n  S.dates.forEach(function(d){\n    var b=document.createElement('button'); b.className='tab'+(d.date===date?' on':'')+(d.open?'':' lock');\n    b.textContent=md(d.date)+'('+DOW[d.dow]+')'+(d.open?'':' 🔒');\n    b.onclick=function(){date=d.date;render();}; $('dates').appendChild(b);\n  });\n  var di = S.dates.filter(function(d){return d.date===date;})[0];\n  var box = $('slots'); box.innerHTML='';\n  if(!di.open){\n    box.innerHTML='<div class=\"note\">'+di.openAt.replace('T',' ')+' 에 열립니다.</div>';\n  } else if(!di.slots.length){\n    box.innerHTML='<div class=\"note\">이 날은 예약 가능한 시간이 없습니다.</div>';\n  } else {\n    var sid=$('sid').value.trim(), nm=$('name').value.trim();\n    di.slots.forEach(function(t){\n      var hit = S.bookings.filter(function(b){return b.date===date&&b.time===t&&b.room===room;})[0];\n      var past = (date+'T'+t) <= S.now;\n      var blk = blockOf(room,date,t);\n      var b=document.createElement('button'); b.className='slot';\n      var label = t+' ~ '+endOf(t);\n      if(blk){\n        b.className+=' busy'; b.disabled=true;\n        b.innerHTML='<span>'+label+'</span><span>🚫 사용 불가'+(blk.reason?' · '+esc(blk.reason):'')+'</span>';\n      } else if(hit){\n        var mine = sid && hit.sid===sid.slice(-2) && hit.name===nm;\n        b.className+=' busy'+(mine?' mine':'');\n        b.innerHTML='<span>'+label+'</span><span>'+esc(hit.name)+(mine?' · 내 예약 (눌러서 취소)':'')+'</span>';\n        if(mine) b.onclick=function(){doCancel(t);}; else b.disabled=true;\n      } else if(past){\n        b.className+=' busy'; b.disabled=true; b.innerHTML='<span>'+label+'</span><span>지남</span>';\n      } else {\n        b.innerHTML='<span>'+label+'</span><span>예약 가능</span>';\n        b.onclick=function(){doBook(t);};\n      }\n      box.appendChild(b);\n    });\n  }\n}\nfunction blockOf(r,d,t){\n  return (S.blocks||[]).filter(function(b){\n    return d>=b.from && d<=b.to && (!b.time||b.time===t) && (!b.room||b.room===r);\n  })[0];\n}\nfunction endOf(t){ var p=t.split(':'); var m=+p[0]*60+ +p[1]+S.blockMinutes; return ('0'+Math.floor(m/60)).slice(-2)+':'+('0'+m%60).slice(-2); }\nfunction esc(s){ return s.replace(/[&<>\"]/g,function(c){return {'&':'&amp;','<':'&lt;','>':'&gt;','\"':'&quot;'}[c];}); }\n\nfunction ident(){\n  var sid=$('sid').value.trim(), nm=$('name').value.trim();\n  if(!sid||!nm){ toast('학번과 이름을 먼저 입력해 주세요.', true); return null; }\n  store('sid',sid); store('name',nm); return {sid:sid,name:nm};\n}\nfunction doBook(t){\n  var id=ident(); if(!id) return;\n  var d=date, r=room;\n  $('mWhat').textContent=md(d)+' '+r+' '+t+' ~ '+endOf(t);\n  $('mList').innerHTML=((S.notices.rooms[r]||[]).concat(S.notices.common)).map(function(n){return '<li>'+esc(n)+'</li>';}).join('');\n  $('mChk').checked=false; $('mYes').disabled=true; $('modal').className='modal on';\n  $('mChk').onchange=function(){ $('mYes').disabled=!this.checked; };\n  $('mNo').onclick=function(){ $('modal').className='modal'; };\n  $('mYes').onclick=function(){\n    if(!$('mChk').checked) return;\n    $('mYes').disabled=true;\n    google.script.run.withSuccessHandler(function(res){ $('modal').className='modal'; toast(res.msg,!res.ok); load(); })\n      .withFailureHandler(function(e){ $('modal').className='modal'; toast(e.message,true); })\n      .book(r,d,t,id.sid,id.name,true);\n  };\n}\nfunction doCancel(t){\n  var id=ident(); if(!id) return;\n  if(!confirm('이 예약을 취소할까요?')) return;\n  google.script.run.withSuccessHandler(function(r){ toast(r.msg,!r.ok); load(); })\n    .withFailureHandler(function(e){toast(e.message,true);}).cancel(room,date,t,id.sid,id.name);\n}\n\n$('sid').value=store('sid'); $('name').value=store('name');\n$('sid').oninput=$('name').oninput=function(){ if(S) render(); };\nload(); setInterval(load, 30000);\n</script>\n</body>\n</html>\n";
