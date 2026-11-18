import re, lupa, runpy, io, contextlib
import os
src=open(os.path.join(os.path.dirname(os.path.abspath(__file__)),'..','..','..','reframework','autorun','DirectPawnControl.lua')).read()
a=src.index('quick.SITUATIONAL = {'); b=src.index('function quick.elems(x)')
c=src.index('function quick.situational(rel)'); d=src.index('-- v0.9.17: ask the pawn')
L=lupa.LuaRuntime()
names={int(x):y for x,y in re.findall(r'(\d+)=(\w+)', open(__import__('os').path.dirname(__file__)+'/hv11.out').read())}
L.execute('quick={defs={}} SKILL_NAMES={} rows={}')
for k,v in names.items(): L.execute(f'SKILL_NAMES[{k}]="{v}"')
for line in open(__import__('os').path.dirname(__file__)+'/hv9.out').read().splitlines()[1:]:
    m=re.match(r'(\d+) p\d+ d\d+ (.*)',line)
    if not m: continue
    L.execute(f'rows[{m[1]}]={{}}')
    for r in m[2].split(' ; '):
        r=r.strip()
        if not r: continue
        named='false' if r.startswith('~') else 'true'; r=r.lstrip('~'); p,fl=r.rsplit('>',1)
        L.execute(f'local rel=("{p}"):lower() table.insert(rows[{m[1]}],{{path="{p}",rel=rel,file=rel:match("([^/]+)$"),flag={fl},named={named}}})')
L.execute('function quick.game_rows() return rows end')
L.execute(src[a:b]); L.execute(src[c:d])
import os
here=os.path.dirname(os.path.abspath(__file__))
ns={'__file__':os.path.join(here,'cmp2.py')}
buf=io.StringIO()
exec(open(os.path.join(here,'cmp2.py')).read().split("same=diff=0")[0], ns)
bad=0
for i in sorted(ns['game']):
    g=ns['pick'](i); d=L.eval(f'quick.table_def({i})')
    lu=(d.path,d.flag,d.kind,d.alt) if d else None
    py=g[:4] if g else None
    if lu!=py: bad+=1; print('MISMATCH',i,lu,py)
print('skills',len(ns['game']),'mismatch',bad, 'unknown id ->', L.eval('quick.table_def(70)'))
