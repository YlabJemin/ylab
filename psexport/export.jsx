// 포토샵 내보내기: SPEC(앞에 붙여 넣음) = {dest:"폴더", limit:바이트(0이면 제한 없음), jobs:[{i:문서번호, layers:[{k:레이어번호, suffix:"" | "_원본" | "_이름"}]}]}
// limit이 있으면(카톡용) 품질 12부터 저장해 보고 넘으면 한 단계씩 낮춰 다시 저장 (해상도는 그대로)
// 문서마다 복제본을 만들어 원하는 레이어 하나만 남기고 합쳐 JPG(품질 12, 색 프로필 포함)로 저장 → 복제본 닫음. 원래 문서는 바꾸지 않음
(function(){
var cur=app.activeDocument, n=0, errs=[];
function uniq(dir, base){ var f=new File(dir+"/"+base+".jpg"), i=2; while(f.exists){ f=new File(dir+"/"+base+" ("+i+").jpg"); i++; } return f; }
for(var j=0;j<SPEC.jobs.length;j++){
  var job=SPEC.jobs[j], d=app.documents[job.i];
  var base=d.name.replace(/\.[^.]+$/,'');
  for(var t=0;t<job.layers.length;t++){
    var L=job.layers[t];
    try{
      app.activeDocument=d;
      var dup=d.duplicate("cc_export_tmp", false);
      var keep=dup.layers[L.k];
      for(var k=dup.layers.length-1;k>=0;k--){ if(k!=L.k){ var x=dup.layers[k]; if(x.isBackgroundLayer) x.isBackgroundLayer=false; x.remove(); } }
      keep=dup.layers[0]; if(!keep.visible){ try{ keep.visible=true; }catch(e){} }
      try{ if(keep.typename=="ArtLayer" && !keep.isBackgroundLayer) keep.blendMode=BlendMode.NORMAL; }catch(e){}
      if(dup.layers.length>1 || !dup.layers[0].isBackgroundLayer) dup.flatten();
      if(dup.bitsPerChannel!=BitsPerChannelType.EIGHT) dup.bitsPerChannel=BitsPerChannelType.EIGHT;
      var o=new JPEGSaveOptions(); o.quality=12; o.embedColorProfile=true; o.formatOptions=FormatOptions.STANDARDBASELINE;
      var f=uniq(SPEC.dest, base+L.suffix);
      dup.saveAs(f, o, true, Extension.LOWERCASE);
      if(SPEC.limit>0){ f=new File(f.fsName); while(f.length>SPEC.limit && o.quality>0){ o.quality--; dup.saveAs(f, o, true, Extension.LOWERCASE); f=new File(f.fsName); } }
      dup.close(SaveOptions.DONOTSAVECHANGES); n++;
    }catch(e){ errs.push(d.name+" "+L.k+": "+e); try{ if(app.activeDocument.name.indexOf("cc_export_tmp")==0) app.activeDocument.close(SaveOptions.DONOTSAVECHANGES);}catch(e2){} }
  }
}
app.activeDocument=cur;
return n+"|"+errs.join(" / ");
})();
