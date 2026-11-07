// 구글 캘린더 '*일정*' 캘린더에서 휴무 일정 색 바꾸기 (cc, 2026-10-05)
//   제목에 '예진' + '휴무' → 분홍(홍학),  '제민' + '휴무' → 주황(귤)
//   먼저 dryRun = true 로 실행해서 개수만 확인 → 맞으면 false 로 바꿔 다시 실행
function 휴무색칠() {
  const dryRun = true;
  const cal = CalendarApp.getCalendarsByName('*일정*')[0];
  if (!cal) throw new Error("'*일정*' 캘린더를 못 찾았어요");
  const events = cal.getEvents(new Date('2024-01-01'), new Date('2028-12-31'));
  let pink = 0, orange = 0;
  for (const e of events) {
    const t = e.getTitle();
    if (!t.includes('휴무')) continue;
    if (t.includes('예진')) { if (!dryRun) e.setColor(CalendarApp.EventColor.PALE_RED); pink++; }
    else if (t.includes('제민')) { if (!dryRun) e.setColor(CalendarApp.EventColor.ORANGE); orange++; }
  }
  Logger.log((dryRun ? '[시험] ' : '') + '분홍(예진) ' + pink + '개 / 주황(제민) ' + orange + '개');
}
