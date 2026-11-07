
// 제목에 '쿠로' 또는 '밤밤' → 포도색 (cc, 2026-10-05)
function 쿠로밤밤색칠() {
  const cal = CalendarApp.getCalendarsByName('*일정*')[0];
  const events = cal.getEvents(new Date('2024-01-01'), new Date('2028-12-31'));
  let n = 0;
  for (const e of events) {
    const t = e.getTitle();
    if (t.includes('쿠로') || t.includes('밤밤')) { e.setColor(CalendarApp.EventColor.MAUVE); n++; }
  }
  Logger.log('포도(쿠로·밤밤) ' + n + '개');
}
