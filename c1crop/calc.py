import sys
ref=(0.50449,0.32195,0.11768)
T={"엄브렐라 증명":(0.47434,0.28411,0.08466),"소박 디퓨저 증명":(0.49207,0.28758,0.09303),"소박 증명2":(0.48022,0.31179,0.08454)}
dims={"엄브렐라 증명":(5307,7956),"소박 디퓨저 증명":(5307,7956),"소박 증명2":(5303,7951)}
flip = len(sys.argv)>1 and sys.argv[1]=="flip"
for n,(cx,cy,d) in T.items():
    c=d/ref[2]; left=cx-ref[0]*c; top=cy-ref[1]*c
    W,H=dims[n]; ccx=(left+c/2)*W; ccy=(top+c/2)*H
    if flip: ccy=H-ccy
    print(f"{n}|{ccx:.1f}|{ccy:.1f}|{c*W:.1f}|{c*H:.1f}")
