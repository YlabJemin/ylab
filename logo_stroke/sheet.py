import sys
from PIL import Image, ImageDraw, ImageFont
d=sys.argv[1]; out=sys.argv[2]
items=[("원본",f"{d}/../botong_원본.jpg","")]+[(f"{i}",f"{d}/v{i}.png",t) for i,t in enumerate(["획만 약간 얇게","얇게 + 끝 날렵","얇게 + 끝 날렵 + 꼬리 조금 짧게","더 얇게 + 끝 날렵 + 꼬리 조금 짧게","더 얇게 + 더 날렵 + 꼬리 더 짧게"],1)]
T=620; G=24; M=40
f1=ImageFont.truetype("/System/Library/Fonts/AppleSDGothicNeo.ttc",26,index=6)
f2=ImageFont.truetype("/System/Library/Fonts/AppleSDGothicNeo.ttc",20,index=2)
sheet=Image.new("RGB",(M*2+T*3+G*2,M*2+90+T*2+G),(236,234,228))
dr=ImageDraw.Draw(sheet)
dr.text((M,M),"Botong Studio — 원본 글씨 그대로 가공 5안",font=ImageFont.truetype("/System/Library/Fonts/AppleSDGothicNeo.ttc",34,index=6),fill=(30,30,30))
dr.text((M,M+48),"폰트 교체 없음 · 원본 이미지의 획 두께 / 끝 / 꼬리만 조절",font=f2,fill=(120,120,120))
for k,(lab,p,t) in enumerate(items):
    im=Image.open(p).convert("RGB")
    w,h=im.size; c=int(w*0.66); im=im.crop(((w-c)//2,(h-c)//2,(w+c)//2,(h+c)//2)).resize((T,T),Image.LANCZOS)
    x=M+(k%3)*(T+G); y=M+90+(k//3)*(T+G)
    tile=Image.new("RGB",(T,T),(255,255,255)); tile.paste(im)
    m=Image.new("L",(T,T),0); ImageDraw.Draw(m).rounded_rectangle((0,0,T-1,T-1),22,fill=255)
    sheet.paste(tile,(x,y),m)
    dr.text((x+22,y+18),lab if lab=="원본" else lab+"안",font=f1,fill=(110,44,14))
    if t: dr.text((x+22,y+T-44),t,font=f2,fill=(150,120,100))
sheet.save(out)
