"""Offline harness for TestGuide.lua: runs the real script against a fake REFramework and a fake clock.
Usage: python3 tests/harness.py   (needs lupa)"""
import json, sys, os
import lupa.lua54 as L

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = open(os.path.join(HERE, "..", "reframework", "autorun", "TestGuide.lua")).read()

def make(files):
    rt = L.LuaRuntime(unpack_returned_tuples=True)
    g = rt.globals()
    state = {"clock": 0.0, "keys": set(), "texts": [], "files": files, "pre": [], "frame": []}
    rt.execute("""
      function __mk(py)
        local t = {}
        re = { on_pre_application_entry = function(name, f) py.reg_pre(f) end, on_frame = function(f) py.reg_frame(f) end, on_draw_ui = function() end }
        imgui = setmetatable({ load_font = function() return 1 end, text_colored = function(s, c) py.text(s) end,
                               begin_window = function() return true end }, { __index = function() return function() end end })
        Vector2f = { new = function(x, y) return { x = x, y = y } end }
        sdk = setmetatable({}, { __index = function() return function() return nil end end })
        log = { info = function() end }
        reframework = { is_key_down = function(self, vk) return py.key(vk) end }
        local function to_lua(s) return load("return " .. s)() end
        json = { load_file = function(name) local s = py.load(name); if s == nil then return nil end return to_lua(s) end,
                 dump_file = function(name, v) py.dump(name, __ser(v)); return true end }
        fs = { glob = function(rx) return to_lua(py.glob(rx)) end }
        os.clock = function() return py.clock() end
      end
      function __ser(v, d)
        d = d or 0
        local tv = type(v)
        if tv == "table" then
          if d > 12 then return 'null' end
          local n = #v
          local is_arr = n > 0
          local parts = {}
          if is_arr then for i = 1, n do parts[#parts+1] = __ser(v[i], d+1) end return "[" .. table.concat(parts, ",") .. "]" end
          for k, x in pairs(v) do if type(x) ~= "function" and type(k) == "string" and k:sub(1,1) ~= "_" then parts[#parts+1] = string.format("%q:", k) .. __ser(x, d+1) end end
          return "{" .. table.concat(parts, ",") .. "}"
        elseif tv == "string" then return (string.format("%q", v):gsub("\\\\\\n", "\\\\n"))
        elseif tv == "number" then if v ~= v or v == math.huge or v == -math.huge then return "null" end return tostring(v)
        elseif tv == "boolean" then return tostring(v)
        else return "null" end
      end
    """)
    def py_to_lua_src(o):
        if isinstance(o, dict): return "{" + ",".join(f"[{json.dumps(k)}]={py_to_lua_src(v)}" for k, v in o.items()) + "}"
        if isinstance(o, list): return "{" + ",".join(py_to_lua_src(v) for v in o) + "}"
        if o is None: return "nil"
        if isinstance(o, bool): return "true" if o else "false"
        return json.dumps(o)
    class Py:
        def reg_pre(self, f): state["pre"].append(f)
        def reg_frame(self, f): state["frame"].append(f)
        def text(self, s): state["texts"].append(str(s))
        def key(self, vk): return int(vk) in state["keys"]
        def clock(self): return state["clock"]
        def load(self, name):
            v = state["files"].get(str(name).replace("\\", "/"))
            return None if v is None else py_to_lua_src(v)
        def dump(self, name, s):
            try: state["files"][str(name).replace("\\", "/")] = json.loads(s)
            except Exception as e: state["files"][str(name)] = {"__unparsed": s[:200], "err": str(e)}
        def glob(self, rx):
            rx = str(rx)
            pre = "dev_status/" if "dev_status" in rx else "test_guide/queue/"
            return py_to_lua_src(sorted(k for k in state["files"] if k.startswith(pre)))
    g.__mk(Py())
    rt.execute(SRC)
    def step(dt=0.05, n=1):
        for _ in range(n):
            state["clock"] += dt
            state["texts"].clear()
            for f in state["pre"]: f()
            for f in state["frame"]: f()
    def press(vk, shift=False):
        state["keys"] = {vk} | ({0x10} if shift else set()); step(); state["keys"] = set(); step()
    return state, step, press

def run():
    fails = []
    def check(name, cond, extra=""):
        print(("PASS " if cond else "FAIL ") + name + (("  " + str(extra)) if (extra and not cond) else ""))
        if not cond: fails.append(name)

    plan = {"id": "h1", "title": "harness", "requires": {"FakeMod": "1.2.0"},
            "steps": [{"text": "a", "secs": 1, "expect": [{"probe": "x", "op": ">", "value": 4, "label": "x above 4"},
                                                          {"probe": "flag", "agg": "all", "label": "flag always true"},
                                                          {"probe": "name", "op": "contains", "value": "Loco", "label": "in locomotion"}]},
                      {"text": "b", "wait": True, "expect": [{"probe": "x", "agg": "max", "op": "<", "value": 3, "label": "x below 3 (should fail)"}]}],
            "record": {"hz": 20, "out": "test_guide/result_h1.json",
                       "probes": {"x": "return 5", "flag": "return true", "name": "return 'Locomotion.Idle'", "bad": "error('boom')"}}}
    files = {"test_guide/plan.json": plan}
    state, step, press = make(files)
    step(n=30)
    st = files["test_guide/status.json"]
    check("plan loads and waits", st["state"] == "waiting", st)
    check("own dev status written", files.get("dev_status/TestGuide.json", {}).get("version") == "2.1")
    press(0x23); step(n=5)
    check("blocked while required mod is missing", files["test_guide/status.json"]["state"] == "waiting" and files["test_guide/status.json"].get("unmet"))
    files["dev_status/FakeMod.json"] = {"mod": "FakeMod", "version": "1.1.9", "t": state["clock"]}
    step(n=30); press(0x23); step(n=5)
    check("blocked on an older version", files["test_guide/status.json"]["state"] == "waiting")
    def beat(ver="1.2.0", **kw): files["dev_status/FakeMod.json"] = dict({"mod": "FakeMod", "version": ver, "t": state["clock"]}, **kw)
    beat(); step(n=30); beat(); press(0x23)
    check("starts once the version is met", files["test_guide/status.json"]["state"] == "countdown", files["test_guide/status.json"])
    for _ in range(90): beat(); step()          # 3 s countdown + 1 s step
    st = files["test_guide/status.json"]
    check("reaches the wait step", st["state"] == "running" and st["step"] == 2, st)
    check("3 verdicts after step 1, all pass", len(st.get("verdicts", [])) == 3 and all(v["pass"] for v in st["verdicts"]), st.get("verdicts"))
    for _ in range(40): beat(); step()
    check("wait step does not time out", files["test_guide/status.json"]["step"] == 2)
    press(0x23)
    st = files["test_guide/status.json"]
    check("finishes on End", st["state"] == "done", st)
    v = st["verdicts"]
    check("4th verdict fails as designed", len(v) == 4 and v[3]["pass"] is False, v)
    res = files["test_guide/result_h1.json"]
    check("result file has rows, verdicts, versions", len(res["rows"]) > 10 and len(res["verdicts"]) == 4 and res["versions"].get("FakeMod") == "1.2.0")
    check("probe errors are recorded, not fatal", str(res["rows"][0].get("bad", "")).startswith("ERR"))
    beat(); step()
    check("overlay shows the failed check", any("CHECKS FAILED" in t for t in state["texts"]), state["texts"][-6:])
    step(n=12); press(0x23); step(n=30)
    check("End closes the result screen", files["test_guide/status.json"]["state"] == "idle")

    # queue + HUD error line + flight recorder
    files["test_guide/queue/01.json"] = {"id": "q1", "steps": [{"text": "q", "secs": 1}]}
    step(n=40)
    check("queue plan picked up", files["test_guide/status.json"].get("id") == "q1", files["test_guide/status.json"])
    beat(last_error="kaboom", last_error_t=state["clock"], errors=3); step(n=30); beat(last_error="kaboom", last_error_t=state["clock"], errors=3); step()
    check("HUD shows a mod error", any("kaboom" in t for t in state["texts"]), state["texts"])
    beat(save_ok=False); step(n=25); beat(save_ok=False); step()
    check("HUD shows a failed save", any("SETTINGS NOT SAVED" in t for t in state["texts"]), state["texts"])
    step(n=120)
    check("HUD greys out a silent mod", any("not reporting" in t for t in state["texts"]), state["texts"])
    press(0x24)
    latest = files.get("test_guide/flight_latest.json")
    check("Home saves a flight recording", bool(latest) and len(files[latest["file"]]["rows"]) > 50, latest)
    press(0x24, shift=True); step(n=100)
    check("Shift+Home hides the HUD", not any("FakeMod" in t for t in state["texts"]) and files["test_guide/config.json"]["hud"] is False, state["texts"])
    print("\n%d failed" % len(fails))
    return 1 if fails else 0

if __name__ == "__main__":
    sys.exit(run())
