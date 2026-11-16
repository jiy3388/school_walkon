/**
 * 체육관 무대 / 무용실 예약 시스템 (Google Apps Script + Google Sheets)
 *
 * 규칙
 *  - 매주 수요일 12:30 에 '다음 주(월~금)' 전체가 열린다. (이미 열린 이번 주도 계속 예약 가능)
 *  - 한 칸 = 30분, 한 사람(학번)이 하루 최대 2칸 (두 장소 합산).
 *  - 사용 당일 12:30 이후에는 하루 2칸 제한이 풀려, 남은 빈 칸을 추가로 예약할 수 있다.
 *  - 이미 지난 시간은 예약할 수 없다.
 */

// ===== 설정 (여기만 고치면 됩니다) =====
var CONFIG = {
  rooms: ['체육관 무대', '무용실'],
  blockMinutes: 60,           // 한 칸 길이(분)
  // 요일별 칸 시작 시각 (0=일 ... 6=토). 점심 12~13시는 매일, 15·16시는 월/목/금만.
  slotsByDow: {
    1: ['12:00', '15:00', '16:00'],
    2: ['12:00'],
    3: ['12:00'],
    4: ['12:00', '15:00', '16:00'],
    5: ['12:00', '15:00', '16:00']
  },
  maxPerDay: 2,               // 하루 최대 칸 수
  openWeekday: 3,             // 오픈 요일 (0=일, 1=월, 2=화, 3=수 ...)
  openTime: '12:30',          // 오픈 시각
  releaseTime: '12:30',       // 사용 당일 이 시각부터 제한 해제
  sheetName: '예약'
};

// ===== 웹앱 진입 =====
function doGet() {
  return HtmlService.createHtmlOutputFromFile('Index')
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
function sheet_() {
  var ss = SpreadsheetApp.getActiveSpreadsheet();
  var sh = ss.getSheetByName(CONFIG.sheetName);
  if (!sh) {
    sh = ss.insertSheet(CONFIG.sheetName);
    sh.appendRow(['날짜', '시작', '장소', '학번', '이름', '신청시각']);
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
    maxPerDay: CONFIG.maxPerDay,
    releaseTime: CONFIG.releaseTime,
    dates: dates,
    bookings: bookings
  };
}

function clean_(s) { return String(s || '').replace(/\s+/g, ' ').trim(); }

function book(room, date, time, sid, name) {
  sid = clean_(sid); name = clean_(name);
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

    var all = rows_();
    if (all.some(function (b) { return b.date === date && b.time === time && b.room === room; }))
      return { ok: false, msg: '방금 다른 사람이 예약했습니다.' };

    // 하루 2칸 제한 (당일 releaseTime 이후에는 제한 없음)
    var released = nowS >= date + 'T' + CONFIG.releaseTime;
    if (!released) {
      var mine = all.filter(function (b) { return b.date === date && b.sid === sid; }).length;
      if (mine >= CONFIG.maxPerDay)
        return { ok: false, msg: '하루 최대 ' + CONFIG.maxPerDay + '칸까지 예약할 수 있습니다. (당일 ' + CONFIG.releaseTime + ' 이후 추가 예약 가능)' };
    }
    sheet_().appendRow([date, time, room, sid, name, nowS.replace('T', ' ')]);
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
