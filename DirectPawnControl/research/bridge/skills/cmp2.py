import re
import os
import sys; sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', '..', '..', 'tools'))
from dpc_source import joined  # 0.9.178: the script is DirectPawnControl.lua + its parts
ptw={}
for m in re.finditer(r'^\s*\[(\d+)\] = \{ "([^"]+)", "(\w+)" \}, -- (\w+)', joined(), re.M):
    ptw[int(m[1])]=(m[2].replace('\\\\','/').lower(), m[3], m[4])
names={int(a):b for a,b in re.findall(r'(\d+)=(\w+)', open(__import__('os').path.dirname(__file__)+'/hv11.out').read())}
game={}
for line in open(__import__('os').path.dirname(__file__)+'/hv9.out').read().splitlines()[1:]:
    m=re.match(r'(\d+) p\d+ d\d+ (.*)',line)
    if not m: continue
    rows=[]
    for r in m[2].split(' ; '):
        r=r.strip()
        if not r: continue
        named=not r.startswith('~'); r=r.lstrip('~'); p,fl=r.rsplit('>',1)
        rows.append((p,int(fl),named))
    game[int(m[1])]=rows
allrows=[r for v in game.values() for r in v]
SIT=["_npc","_ch%d","_gm%d","cnt%d","quest","climb","_spot","_air","_break","_tired","combo","_multiple","_concentrate","_charged","keepdistance","_release","_ground","_around","jumpatt","gimmick","_ex$","_ex_","_lv2","_lvex","_nrd","neutral","^common/","^grimoire/","^npc/","^ch%d"]
SITRE=[re.compile(s.replace('%d',r'\d')) for s in SIT]
def sit(p): 
    p=p.lower(); return any(r.search(p) for r in SITRE)
def pick(i):
    rows=game.get(i,[]); nm=names.get(i,'').lower()
    fn=lambda p:p.split('/')[-1].lower()
    c=[r for r in rows if nm and nm in fn(r[0])]; how='name'
    if not c: c=[r for r in rows if r[2]]; how='named'
    if not c: c=[r for r in allrows if nm and nm in fn(r[0])]; how='global'
    if not c:
        if len(set(r[0] for r in rows))<=6: c=rows; how='few'
    if not c: return None
    plain=[r for r in c if not sit(r[0])]
    if plain: c=plain
    p=sorted(set(r[0] for r in c), key=lambda p:(len(p),p.lower()))[0]
    fl=0
    for r in c:
        if r[0]==p: fl|=r[1]
    kind='enemy' if fl&4 else ('player' if fl&66 else ('self' if fl&1 else 'enemy'))
    alt=None
    if kind=='enemy': alt='self' if fl&1 else ('player' if fl&66 else None)
    return p,fl,kind,alt,how
same=diff=0
for i in sorted(game):
    g=pick(i); p=ptw.get(i); tag=''
    if g and p:
        if g[0].lower()==p[0] and g[2]==p[1]: same+=1; tag='='
        elif g[0].lower()==p[0]: tag='kind'
        else: tag='PACK'
    print(i,names.get(i),'|',g,'|',p[:2] if p else None,tag)
print('same',same)
