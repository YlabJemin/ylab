// 포토샵 내보내기: 열린 문서·레이어 정보를 JSON 글자로 돌려줌 (문서를 바꾸지 않음)
(function(){
function q(s){return '"'+String(s).replace(/\\/g,'\\\\').replace(/"/g,'\\"').replace(/\n/g,' ')+'"';}
if(app.documents.length==0) return '{"docs":[]}';
var cur=app.activeDocument, out=[];
for(var i=0;i<app.documents.length;i++){
  var d=app.documents[i], ls=[], act=-1, al=null;
  try{ if(d==cur) al=d.activeLayer; }catch(e){}
  for(var k=0;k<d.layers.length;k++) ls.push(q(d.layers[k].name));
  if(d==cur){ var a=al; while(a && a.parent && a.parent.typename!="Document") a=a.parent;
    for(var k=0;k<d.layers.length;k++) if(a && d.layers[k]==a) act=k; }
  out.push('{"i":'+i+',"name":'+q(d.name)+',"current":'+(d==cur)+',"active":'+act+',"layers":['+ls.join(',')+']}');
}
// 지금 문서 말고는 선택 레이어를 알려면 문서를 바꿔야 해서, 각 문서를 잠깐 앞으로 가져와 읽고 되돌림
for(var i=0;i<app.documents.length;i++){
  var d=app.documents[i]; if(d==cur) continue;
  app.activeDocument=d; var a=d.activeLayer; while(a && a.parent && a.parent.typename!="Document") a=a.parent;
  var act=-1; for(var k=0;k<d.layers.length;k++) if(d.layers[k]==a) act=k;
  out[i]=out[i].replace('"active":-1','"active":'+act);
}
app.activeDocument=cur;
return '{"docs":['+out.join(',')+']}';
})();
