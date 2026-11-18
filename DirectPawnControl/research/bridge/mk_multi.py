import sys
parts=[]
for f in sys.argv[2:]:
    src=open(f).read()
    parts.append('do local f,e=load(%s,"%s"); if not f then res[#res+1]="%s LOADERR "..tostring(e) else local ok,r=pcall(f); res[#res+1]="%s: "..(ok and (type(r)=="table" and table.concat(r," | ") or tostring(r)) or ("ERR "..tostring(r))) end end' % ("[==[\n"+src+"\n]==]", f, f, f))
open(sys.argv[1],'w').write("local res={}\n"+"\n".join(parts)+"\nreturn res\n")
