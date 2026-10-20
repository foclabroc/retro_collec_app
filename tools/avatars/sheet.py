import sys
from PIL import Image, ImageDraw
from px import render
from chars import CHARS
import os
OUT='../../assets/avatars'
S=128; cols=6; rows=5
sheet=Image.new('RGB',(cols*(S+16)+16, rows*(S+34)+16),(12,16,40))
d=ImageDraw.Draw(sheet)
mask=Image.new('L',(S,S),0); ImageDraw.Draw(mask).ellipse((0,0,S-1,S-1),fill=255)
for i,(fn,acc,name) in enumerate(CHARS):
    render(fn,acc,f'{OUT}/avatar_{i:02d}.webp')
    im=Image.open(f'{OUT}/avatar_{i:02d}.webp').convert('RGB')
    x=16+(i%cols)*(S+16); y=16+(i//cols)*(S+34)
    sheet.paste(im,(x,y),mask)
    d.ellipse((x-2,y-2,x+S+1,y+S+1),outline=acc,width=3)
    d.text((x+4,y+S+6),f'{i:02d} {name}',fill=(230,230,240))
sheet.save('sheet.png')
