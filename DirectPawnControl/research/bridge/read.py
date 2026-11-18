import json
r = json.load(open("/mnt/user-data/uploads/Dragons Dogma 2/reframework/data/agent_bridge/response.json"))
want = open("/home/claude/br/last_id").read().strip()
print("ID MATCH" if r.get("id") == want else f"STALE id={r.get('id')} want={want}", r.get("status"), r.get("execution_time_ms"), "ms")
if r.get("error"): print("ERROR:", r["error"])
res = r.get("result") or {}
print(json.dumps(res.get("return_value"), indent=1)[:12000])
if res.get("stdout"): print("\n".join(map(str, res["stdout"]))[:12000])
