# Generates greedify-icon.svg (RAM-stick equalizer). Render to PNG with headless Chrome, then resize into App/Assets.xcassets/AppIcon.appiconset (16-1024).
import sys
S=1024
# Background: top, bottom, trace colour, halo colour. Picked for contrast with the green PCB.
BGS={
 'violet':('#5b2bd6','#22105e','#ffffff','#c77dff'),
 'coral':('#ff7a59','#c2304f','#ffffff','#ffd166'),
 'navy':('#2b4fd8','#0f1a5c','#ffffff','#7ab8ff'),
}
bg_top,bg_bot,trace,halo=BGS[sys.argv[1] if len(sys.argv)>1 else 'coral']
X,Y,W,H,R=100,100,824,824,185
heights=[300,470,590,410,250]
bw,gx=106,24
total=len(heights)*bw+(len(heights)-1)*gx
x0=(S-total)/2; base=790
d=[]; body=[]
d.append(f'''<linearGradient id="bg" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="{bg_top}"/><stop offset="1" stop-color="{bg_bot}"/></linearGradient>
<radialGradient id="halo" cx="0.5" cy="0.42" r="0.55"><stop offset="0" stop-color="{halo}" stop-opacity="0.35"/><stop offset="1" stop-color="{halo}" stop-opacity="0"/></radialGradient>
<linearGradient id="pcb" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="#2cc46a"/><stop offset="0.5" stop-color="#1da756"/><stop offset="1" stop-color="#14833f"/></linearGradient>
<linearGradient id="chip" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#2b2f35"/><stop offset="1" stop-color="#121417"/></linearGradient>
<linearGradient id="gold" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#ffe08a"/><stop offset="0.5" stop-color="#e9b949"/><stop offset="1" stop-color="#b8862a"/></linearGradient>
<linearGradient id="slot" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#2a2e34"/><stop offset="1" stop-color="#0c0d10"/></linearGradient>
<filter id="sh" x="-20%" y="-20%" width="140%" height="140%"><feDropShadow dx="0" dy="14" stdDeviation="14" flood-opacity="0.35"/></filter>
<filter id="ssh" x="-30%" y="-10%" width="160%" height="130%"><feDropShadow dx="0" dy="6" stdDeviation="6" flood-opacity="0.55"/></filter>
<clipPath id="clip"><rect x="{X}" y="{Y}" width="{W}" height="{H}" rx="{R}"/></clipPath>
<pattern id="traces" width="64" height="64" patternUnits="userSpaceOnUse"><path d="M0 16 H24 L36 28 H64 M16 0 V10 L28 22 M48 64 V44 L40 36" stroke="{trace}" stroke-opacity="0.08" stroke-width="2" fill="none"/><circle cx="24" cy="16" r="3" fill="{trace}" fill-opacity="0.10"/><circle cx="48" cy="44" r="3" fill="{trace}" fill-opacity="0.10"/></pattern>''')
for i,h in enumerate(heights):
    x=x0+i*(bw+gx); top=base-h
    # mask: side clip notches
    ny=base-110
    d.append(f'<mask id="m{i}"><rect x="{x-5}" y="{top-5}" width="{bw+10}" height="{h+10}" fill="#fff"/><circle cx="{x}" cy="{ny}" r="9" fill="#000"/><circle cx="{x+bw}" cy="{ny}" r="9" fill="#000"/></mask>')
    g=[]
    # pcb
    g.append(f'<rect x="{x}" y="{top}" width="{bw}" height="{h}" rx="6" fill="url(#pcb)"/>')
    g.append(f'<rect x="{x+4}" y="{top+8}" width="2" height="{h-56}" fill="#ffffff" opacity="0.12"/>')
    # chips with pins
    cw,ch,gap=70,60,16
    cy=top+24
    while cy+ch < base-140:
        cx=x+(bw-cw)/2
        for p in range(6):
            py=cy+7+p*(ch-14)/5
            g.append(f'<rect x="{cx-6}" y="{py-1.5:.1f}" width="6" height="3" fill="#c9cdd2"/><rect x="{cx+cw}" y="{py-1.5:.1f}" width="6" height="3" fill="#c9cdd2"/>')
        g.append(f'<rect x="{cx}" y="{cy}" width="{cw}" height="{ch}" rx="3" fill="url(#chip)"/>')
        g.append(f'<circle cx="{cx+9}" cy="{cy+9}" r="3" fill="#3a3f46"/>')
        g.append(f'<rect x="{cx+18}" y="{cy+ch/2-3}" width="{cw-36}" height="4" rx="2" fill="#4a5058" opacity="0.8"/>')
        cy+=ch+gap
    # smd components row
    for k in range(5):
        g.append(f'<rect x="{x+14+k*17}" y="{base-128}" width="10" height="6" rx="1" fill="#d8b46a" opacity="0.85"/>')
    # gold fingers with key notch
    fy=base-72; fh=46
    n=10; fw=(bw-14)/n
    nk=x+bw*0.4
    for k in range(n):
        fx=x+7+k*fw
        if abs(fx+fw*0.3-nk)<fw*0.6: continue
        g.append(f'<rect x="{fx:.1f}" y="{fy}" width="{fw*0.62:.1f}" height="{fh}" rx="2" fill="url(#gold)"/>')
    g.append(f'<rect x="{nk-5:.1f}" y="{fy+fh-24}" width="10" height="40" rx="3" fill="#0b0d10"/>')
    body.append(f'<g mask="url(#m{i})" filter="url(#ssh)">'+''.join(g)+'</g>')
# slot with latches
sx=x0-34; sw=total+68
body.append(f'<rect x="{sx}" y="{base-34}" width="{sw}" height="50" rx="10" fill="url(#slot)"/>')
body.append(f'<rect x="{sx+8}" y="{base-34}" width="{sw-16}" height="3" fill="#ffffff" opacity="0.08"/>')
for lx in (sx-6, sx+sw-18):
    body.append(f'<rect x="{lx}" y="{base-70}" width="24" height="86" rx="7" fill="#d9dde3"/><rect x="{lx+4}" y="{base-66}" width="6" height="74" rx="3" fill="#ffffff" opacity="0.6"/>')
svg=f'''<svg xmlns="http://www.w3.org/2000/svg" width="{S}" height="{S}"><defs>{''.join(d)}</defs>
<rect x="{X}" y="{Y}" width="{W}" height="{H}" rx="{R}" fill="url(#bg)" filter="url(#sh)"/>
<g clip-path="url(#clip)"><rect x="{X}" y="{Y}" width="{W}" height="{H}" fill="url(#traces)"/><rect x="{X}" y="{Y}" width="{W}" height="{H}" fill="url(#halo)"/>{''.join(body)}</g>
<rect x="{X+1.5}" y="{Y+1.5}" width="{W-3}" height="{H-3}" rx="{R-1.5}" fill="none" stroke="#ffffff" stroke-opacity="0.08" stroke-width="3"/></svg>'''
open('greedify-icon.svg','w').write(svg)
