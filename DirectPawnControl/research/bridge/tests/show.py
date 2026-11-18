import json,sys
r=json.load(open('/mnt/user-data/uploads/Dragons Dogma 2/reframework/data/agent_bridge/rr.json'))
keys=sys.argv[1:] or ['mode','tgt','hp','nodes','shells','err','poss','cam']
prev=None
for x in r:
  k=tuple(x.get(a) for a in keys)
  if k!=prev: print(x); prev=k
print('rows',len(r))
