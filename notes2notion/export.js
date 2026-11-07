// 메모 앱 → JSON (읽기 전용)
const Notes = Application('Notes');
const out = [];
Notes.accounts().forEach(acc => {
  acc.folders().forEach(f => {
    const fname = f.name();
    if (fname === '최근 삭제된 항목' || fname === 'Recently Deleted') return;
    f.notes().forEach(n => {
      const item = {id: n.id(), account: acc.name(), folder: fname, title: n.name(),
        created: n.creationDate().toISOString(), modified: n.modificationDate().toISOString(),
        locked: n.passwordProtected()};
      try { item.attachments = n.attachments().length; } catch (e) { item.attachments = -1; }
      if (!item.locked) item.body = n.body();
      out.push(item);
    });
  });
});
JSON.stringify(out);
