import json, sys, uuid
# usage: send.py <luafile> [action]
code = open(sys.argv[1]).read()
rid = "c-" + uuid.uuid4().hex[:6]
p = "/mnt/user-data/outputs/bridge/req_" + rid + ".json"
json.dump({"id": rid, "action": "eval", "args": {"code": code}}, open(p, "w"))
print(p)
open("/home/claude/br/last_id", "w").write(rid)
print(rid)
