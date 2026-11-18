import json,sys,time,random
# usage: cmd.py '<json without id>'  -> writes /mnt/user-data/outputs/cmd/c_<id>.json, prints path
d=json.loads(sys.argv[1]); d['id']='t%d'%random.randint(10**5,10**6)
p='/mnt/user-data/outputs/cmd/c_%s.json'%d['id']; json.dump(d,open(p,'w')); print(p)
