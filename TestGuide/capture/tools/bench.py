"""Test bench: runs TestGuide plans in Dragon's Dogma 2 with nobody at the PC, and survives crashes.

  python tools\\bench.py                 watch for jobs and run them (leave the window open; Ctrl+C stops)
  python tools\\bench.py --job FILE      run one job file now, then exit
  python tools\\bench.py --dump FILE     read a crash dump: exception, fault address, game code on the stack
  python tools\\bench.py --status        print the bench's state and the last runs

Also built into the capture desk (capture_desk.bat): the "Test bench" panel starts and stops it and shows the runs.

Where things live (all under the game's reframework\\data\\bench\\, so Claude can drop jobs and read results):
  jobs\\*.json          jobs waiting (a job is moved to jobs\\done\\ once it has run)
  runs\\<run id>\\       one folder per job run: summary.json, summary.md, each plan's results, logs, crash reports
  state.json           what the bench is doing now (the desk and Claude read it)
  heartbeat.json       written by DevBench.lua in the game once a second (wall clock): alive, title or world
  autoload.json        tells DevBench.lua which save slot to load from the title menu, and how
  stop.json            {"stop": true} makes the bench stop after the current plan

A job (JSON):
  { "id": "evening-1", "title": "...",
    "plans": ["queue/62_hitstop-as-player-1.json", {"id": "inline-plan", "steps": [...]}],   paths are relative to
                                                                                         reframework\\data\\test_guide\\
    "slot": null,                   a save slot to check (and for "call"); null = whichever save is loaded
    "autoload": "observe",          observe: wait for someone (or the keys below) to load the save; call: DevBench asks
                                    the game to load the slot (untested guess); keys: the bench presses keys
    "keys": [{"wait": 8}, {"key": "ENTER"}, ...],   for "keys": pressed on the title menu, in order
    "use_running_game": false,      true: use a game that is already running (never killed by the bench)
    "max_crashes": 3, "retry_after_crash": true, "plan_timeout_s": 900, "boot_timeout_s": 300, "hang_s": 90,
    "video": false,                 true: record each plan with ffmpeg (desktop capture; untested)
    "quit_at_end": false,           true: close the game when the job is done (only a game the bench started)
    "scene": true,                  a known start for each plan: DPC's "scene" command (pawn released, test enemies
                                    gone, party healed, experimental switches off, back to where the job started)
    "save_block": "flag",           the game does not save while the job runs: "flag" (the game's own switch),
                                    "skip" (save requests dropped), or false. The bench checks the save files after
                                    every plan and reports any that changed.
    "revert": false,
    "title_between": false,         true: after each plan, quit to the title menu and load again, for crashes that
                                    happen when the world unloads. DevBench sets the pause menu's own "return to title"
                                    flag (app.ui060101.returnTitle), then the bench presses "title_keys" (default Esc,
                                    which opens that menu; the game then quits to title without saving). Verified by
                                    hand on Thirteen 2026-11-19.
    "title_keys": [{"key": "ESC"}] }               "job_end" or "each_plan": restart the game afterwards so it is back at the save
                                    (only a game the bench started, and only while the save block held)

Safety: the bench only ever closes a game it started itself, never one that was already running. It backs up the
saves folder before each job (bench\\save_backups\\, last 10 kept). Python standard library only; Windows.
"""
import argparse, ctypes, glob, json, os, shutil, struct, subprocess, sys, threading, time, zipfile

STEAM_APP = "2054970"
GAME_CANDIDATES = [r"C:\Games\Steam\steamapps\common\Dragons Dogma 2", r"<game folder>",
                   r"C:\Program Files (x86)\Steam\steamapps\common\Dragons Dogma 2"]
EXE = "DD2.exe"
DEFAULTS = {"slot": None, "autoload": "observe", "keys": [], "use_running_game": False, "max_crashes": 3,
            "retry_after_crash": True, "plan_timeout_s": 900, "boot_timeout_s": 300, "world_timeout_s": 240,
            "hang_s": 90, "video": False, "quit_at_end": False, "scene": True, "save_block": "flag", "revert": False,
            "title_between": False, "title_keys": [{"key": "ESC"}]}


def find_game(arg=None):
    for c in [arg, os.environ.get("DD2_GAME_DIR")] + GAME_CANDIDATES:
        if c and os.path.isfile(os.path.join(c, EXE)):
            return c
    return None


def steam_save_roots(game):
    """Every userdata/<id>/2054970 folder. Steam's own folder is often not the library the game is in
    (game on E:\\Games\\Steam, Steam itself in Program Files), so look in both, plus the registry."""
    roots = [os.path.abspath(os.path.join(game, "..", "..", ".."))] if game else []
    try:
        import winreg
        for hive, key, val in ((winreg.HKEY_CURRENT_USER, r"Software\Valve\Steam", "SteamPath"),
                               (winreg.HKEY_LOCAL_MACHINE, r"SOFTWARE\WOW6432Node\Valve\Steam", "InstallPath")):
            try:
                with winreg.OpenKey(hive, key) as k:
                    roots.append(os.path.normpath(winreg.QueryValueEx(k, val)[0]))
            except OSError:
                pass
    except ImportError:
        pass
    roots += [r"C:\Program Files (x86)\Steam", r"C:\Program Files\Steam"]
    out, seen = [], set()
    for r in roots:
        for f in glob.glob(os.path.join(r, "userdata", "*", STEAM_APP)):
            key = os.path.normcase(os.path.abspath(f))
            if key not in seen:
                seen.add(key)
                out.append(f)
    return out


def read_json(path, default=None):
    try:
        with open(path, encoding="utf-8-sig") as fh:
            return json.load(fh)
    except (OSError, ValueError):
        return default


def write_json(path, obj):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump(obj, fh, indent=1, ensure_ascii=False)
    os.replace(tmp, path)


# ---- crash dumps (minidump format, read directly) -----------------------------------------------------------------
def read_minidump(path, stack_bytes=0x6000):
    """Exception code and address, the module it is in, and game-module addresses found on the faulting thread's
    stack (a rough call stack). Offsets are module-relative, ready for `dd2-modkit index addr DD2.exe+0x...`."""
    out = {"file": path}
    with open(path, "rb") as fh:
        hdr = fh.read(32)
        if hdr[:4] != b"MDMP":
            raise ValueError("not a minidump")
        nstreams, dir_rva = struct.unpack_from("<II", hdr, 8)
        fh.seek(dir_rva)
        streams = {}
        for _ in range(nstreams):
            stype, size, rva = struct.unpack("<III", fh.read(12))
            streams.setdefault(stype, (size, rva))

        mods = []
        if 4 in streams:  # ModuleListStream
            fh.seek(streams[4][1])
            (n,) = struct.unpack("<I", fh.read(4))
            raw = fh.read(108 * n)
            for i in range(n):
                base, size, _, _, name_rva = struct.unpack_from("<QIIII", raw, i * 108)
                mods.append([base, size, name_rva])
            for m in mods:
                fh.seek(m[2])
                (ln,) = struct.unpack("<I", fh.read(4))
                m[2] = fh.read(ln).decode("utf-16-le", "replace").split("\\")[-1]

        def where(a):
            for base, size, name in mods:
                if base <= a < base + size:
                    return name, a - base
            return None, None

        tid = None
        if 6 in streams:  # ExceptionStream
            fh.seek(streams[6][1])
            tid, _, code, flags, _, addr, nparams, _ = struct.unpack("<IIIIQQII", fh.read(40))
            params = struct.unpack("<15Q", fh.read(120))[:nparams]
            name, off = where(addr)
            out.update(code=hex(code), address=hex(addr), module=name, offset=hex(off) if off is not None else None,
                       params=[hex(p) for p in params], thread=tid)
            if name:
                out["where"] = f"{name}+{off:#x}"
        stack = []
        if 3 in streams and tid is not None:  # ThreadListStream
            fh.seek(streams[3][1])
            (n,) = struct.unpack("<I", fh.read(4))
            raw = fh.read(48 * n)
            for i in range(n):
                t_id, _, _, _, _, st_start, st_size, st_rva, _, _ = struct.unpack_from("<IIIIQQIIII", raw, i * 48)
                if t_id != tid:
                    continue
                fh.seek(st_rva)
                data = fh.read(min(st_size, stack_bytes))
                for j in range(0, len(data) - 7, 8):
                    (v,) = struct.unpack_from("<Q", data, j)
                    name, off = where(v)
                    if name and name.lower() in ("dd2.exe", "dinput8.dll"):
                        stack.append(f"{name}+{off:#x}")
                    if len(stack) >= 40:
                        break
        out["stack"] = stack
    return out


def resolve(addrs):
    """Names for DD2.exe addresses through dd2-modkit's index, if it is installed on this PC."""
    addrs = [a for a in addrs if a.lower().startswith("dd2.exe+")]
    if not addrs:
        return None
    try:
        r = subprocess.run([sys.executable, "-m", "dd2_modkit.cli", "index", "addr"] + addrs[:30],
                           capture_output=True, text=True, timeout=120)
        return r.stdout.strip() or r.stderr.strip()
    except (OSError, subprocess.SubprocessError) as e:
        return f"(dd2-modkit not available here: {e})"


# ---- Windows: the game process, its window, key presses ------------------------------------------------------------
def game_pids():
    try:
        r = subprocess.run(["tasklist", "/FI", f"IMAGENAME eq {EXE}", "/FO", "CSV", "/NH"], capture_output=True, text=True,
                           timeout=20)
    except (OSError, subprocess.SubprocessError):
        return []
    pids = []
    for line in r.stdout.splitlines():
        parts = [p.strip('"') for p in line.split('","')]
        if len(parts) > 1 and parts[0].strip('"').lower() == EXE.lower():
            try:
                pids.append(int(parts[1]))
            except ValueError:
                pass
    return pids


SCAN = {"ENTER": (0x1C, False), "ESC": (0x01, False), "SPACE": (0x39, False), "UP": (0x48, True),
        "DOWN": (0x50, True), "LEFT": (0x4B, True), "RIGHT": (0x4D, True), "E": (0x12, False), "F": (0x21, False),
        "Q": (0x10, False), "TAB": (0x0F, False), "BACKSPACE": (0x0E, False)}


def focus_game(pid):
    """Bring the game's window to the front (key presses go to the window in front)."""
    if os.name != "nt":
        return False
    user32 = ctypes.windll.user32
    found = []

    @ctypes.WINFUNCTYPE(ctypes.c_bool, ctypes.c_void_p, ctypes.c_void_p)
    def cb(hwnd, _):
        p = ctypes.c_ulong()
        user32.GetWindowThreadProcessId(hwnd, ctypes.byref(p))
        if p.value == pid and user32.IsWindowVisible(hwnd):
            found.append(hwnd)
        return True
    user32.EnumWindows(cb, 0)
    if not found:
        return False
    user32.ShowWindow(found[0], 9)
    return bool(user32.SetForegroundWindow(found[0]))


def press(name, hold=0.08):
    """One key press as hardware scan codes (games that read raw input see these; SendKeys text often is not)."""
    if os.name != "nt" or name.upper() not in SCAN:
        return False
    code, ext = SCAN[name.upper()]

    class KI(ctypes.Structure):
        _fields_ = [("wVk", ctypes.c_ushort), ("wScan", ctypes.c_ushort), ("dwFlags", ctypes.c_ulong),
                    ("time", ctypes.c_ulong), ("dwExtraInfo", ctypes.c_size_t)]

    class INP(ctypes.Structure):
        class _U(ctypes.Union):
            _fields_ = [("ki", KI), ("pad", ctypes.c_byte * 32)]
        _anonymous_ = ("u",)
        _fields_ = [("type", ctypes.c_ulong), ("u", _U)]

    def send(up):
        flags = 0x0008 | (0x0001 if ext else 0) | (0x0002 if up else 0)  # SCANCODE | EXTENDED | KEYUP
        i = INP(type=1)
        i.ki = KI(0, code, flags, 0, 0)
        ctypes.windll.user32.SendInput(1, ctypes.byref(i), ctypes.sizeof(INP))
    send(False)
    time.sleep(hold)
    send(True)
    return True


# ---- the bench ----------------------------------------------------------------------------------------------------
class Bench:
    def __init__(self, game=None, say=print):
        self.game = find_game(game)
        if not self.game:
            raise SystemExit("Dragon's Dogma 2 was not found. Pass --game or set DD2_GAME_DIR.")
        self.data = os.path.join(self.game, "reframework", "data")
        self.dir = os.path.join(self.data, "bench")
        self.tg = os.path.join(self.data, "test_guide")
        for d in ("jobs", "runs", "save_backups"):
            os.makedirs(os.path.join(self.dir, d), exist_ok=True)
        self.say_fn = say
        self.lines = []
        self.launched_pid = None  # only a game the bench started may be closed by it
        self.stop_flag = False
        self.thread = None
        self.state = {"running": False, "job": None, "plan": None, "phase": "idle", "since": time.time()}

    # -- reporting
    def say(self, text):
        line = time.strftime("%H:%M:%S ") + text
        self.lines.append(line)
        self.lines = self.lines[-300:]
        try:
            self.say_fn(line)
        except Exception:
            pass
        self.save_state()

    def set(self, **kw):
        self.state.update(kw)
        self.state["since"] = time.time()
        self.save_state()

    def save_state(self):
        st = dict(self.state, lines=self.lines[-40:], t=time.time(), game=self.game, launched_pid=self.launched_pid)
        try:
            write_json(os.path.join(self.dir, "state.json"), st)
        except OSError:
            pass

    def p(self, *parts):
        return os.path.join(self.dir, *parts)

    # -- the game's side
    def heartbeat(self):
        hb = read_json(self.p("heartbeat.json"))
        if not isinstance(hb, dict) or not isinstance(hb.get("wall"), (int, float)):
            return None
        hb["age"] = time.time() - hb["wall"]
        return hb

    def alive(self):
        pids = game_pids()
        return pids[0] if pids else None

    def stopped(self):
        if self.stop_flag:
            return True
        st = read_json(self.p("stop.json"))
        return isinstance(st, dict) and st.get("stop") is True

    def renew_auto(self, run_id, on=True, block=None):
        until = int(time.time()) + 120
        write_json(os.path.join(self.tg, "auto.json"), {"on": on, "until": until, "run": run_id})
        if block is not None:
            write_json(self.p("saveblock.json"), {"on": bool(on and block), "until": until, "mode": block or "flag", "run": run_id})

    def save_files(self):
        """Size and time of every save file, to tell whether a run wrote to the save."""
        out = {}
        for root in steam_save_roots(self.game):
            for dp, _, files in os.walk(root):
                for f in files:
                    full = os.path.join(dp, f)
                    try:
                        st = os.stat(full)
                        out[os.path.relpath(full, root)] = (st.st_size, int(st.st_mtime))
                    except OSError:
                        pass
        return out

    def to_title(self, job, tag):
        """Quit to the title menu (the world unloads, where some crashes happen). Returns 'title', 'crash' or 'failed'."""
        self.set(phase="quitting to title")
        write_json(self.p("title.json"), {"id": f"{tag}-{int(time.time())}", "mode": "call", "wall": int(time.time())})
        keys_done = False
        t0 = time.time()
        while time.time() - t0 < 90:
            time.sleep(1)
            if not self.alive():
                return "crash"
            hb = self.heartbeat() or {}
            if hb.get("title") and hb.get("age", 99) < 10:
                self.say(f"at the title menu ({hb.get('title_req')})")
                return "title"
            if not keys_done and time.time() - t0 > 2 and job["title_keys"]:
                keys_done = True
                self.say(f"title request: {hb.get('title_req')}; pressing the job's keys")
                focus_game(self.alive())
                for k in job["title_keys"]:
                    if "wait" in k:
                        time.sleep(float(k["wait"]))
                    elif "key" in k:
                        press(k["key"])
                        time.sleep(float(k.get("after", 0.6)))
        self.say("could not get to the title menu")
        return "failed"

    def restart_game(self, why):
        """Close a game the bench started and start it again (back at the save)."""
        pid = self.alive()
        if not pid or pid != self.launched_pid:
            self.say(f"revert skipped ({why}): the game was not started by the bench")
            return False
        self.say(f"revert ({why}): restarting the game")
        subprocess.run(["taskkill", "/PID", str(pid), "/F"], capture_output=True)
        for _ in range(30):
            if not self.alive():
                break
            time.sleep(1)
        self.launched_pid = None
        return True

    def clean_before_launch(self):
        """Leftovers that would run again at startup (a stale bridge request once did, right after a crash)."""
        # (an empty JSON object, not a removed file: the bridge reads request.json 20 times a second and logs an
        #  error for every read of a missing or empty one; first bench run, 2026-11-19)
        for rel, empty in (("agent_bridge/request.json", {}), ("DPC_cmd.json", {})):
            f = os.path.join(self.data, rel)
            if os.path.isfile(f):
                try:
                    if empty is None:
                        os.replace(f, f + ".bench-old")
                    else:
                        write_json(f, empty)
                except OSError as e:
                    self.say(f"could not clear {rel}: {e}")

    def backup_saves(self):
        found = steam_save_roots(self.game)
        if not found:
            self.say("save backup: the Steam saves folder was not found (skipped)")
            return None
        dst = self.p("save_backups", time.strftime("saves_%Y%m%d-%H%M%S.zip"))
        with zipfile.ZipFile(dst, "w", zipfile.ZIP_DEFLATED) as z:
            for root in found:
                for dp, _, files in os.walk(root):
                    for f in files:
                        full = os.path.join(dp, f)
                        z.write(full, os.path.relpath(full, os.path.dirname(root)))
        old = sorted(glob.glob(self.p("save_backups", "saves_*.zip")))
        for f in old[:-10]:
            try:
                os.remove(f)
            except OSError:
                pass
        self.say(f"saves backed up: {os.path.basename(dst)}")
        return dst

    def launch(self, job):
        self.clean_before_launch()
        try:  # the last game's heartbeat must not count for this one (it can be seconds old after a crash)
            os.replace(self.p("heartbeat.json"), self.p("heartbeat.prev.json"))
        except OSError:
            pass
        write_json(self.p("autoload.json"), {"mode": job["autoload"], "slot": job["slot"], "id": f"{job['id']}-{int(time.time())}"})
        self.set(phase="launching")
        self.say("starting the game through Steam")
        if os.name == "nt":
            os.startfile(f"steam://rungameid/{STEAM_APP}")
        t0 = time.time()
        while time.time() - t0 < 120:
            pid = self.alive()
            if pid:
                self.launched_pid = pid
                self.say(f"game process {pid}")
                return pid
            time.sleep(2)
        return None

    def ensure_world(self, job):
        """Game running and the Arisen in the world. Returns (ok, why)."""
        pid = self.alive()
        if pid and pid != self.launched_pid and not job["use_running_game"]:
            return False, "the game is running and the bench did not start it (set use_running_game to use it)"
        if not pid:
            self.launched_pid = None
            pid = self.launch(job)
            if not pid:
                return False, "the game did not start"
        t0, keys_done, title_t = time.time(), False, None
        self.set(phase="waiting for the world")
        while True:
            if self.stopped():
                return False, "stopped"
            if not self.alive():
                return False, "crash while starting"
            hb = self.heartbeat()
            fresh = hb and hb["age"] < 10
            if fresh and hb.get("in_game") and hb.get("player"):
                self.say(f"in the world (slot {hb.get('slot')})")
                if job["slot"] is not None and hb.get("slot") not in (None, job["slot"]):
                    self.say(f"NOTE: the loaded slot is {hb.get('slot')}, the job asked for {job['slot']}")
                return True, "ok"
            if fresh and hb.get("title"):
                title_t = title_t or time.time()
                if job["autoload"] == "keys" and not keys_done and time.time() - title_t > 3:
                    keys_done = True
                    self.say("title menu: pressing the job's keys")
                    focus_game(pid)
                    for k in job["keys"]:
                        if "wait" in k:
                            time.sleep(float(k["wait"]))
                        elif "key" in k:
                            press(k["key"])
                            time.sleep(float(k.get("after", 0.6)))
                if job["autoload"] == "observe" and time.time() - title_t < 3:
                    self.set(phase="title menu: waiting for someone to load the test save")
            limit = job["boot_timeout_s"] if not hb else job["world_timeout_s"] + job["boot_timeout_s"]
            if time.time() - t0 > limit:
                return False, "timed out before the world"
            time.sleep(2)

    # -- one plan
    def plan_obj(self, ref):
        if isinstance(ref, dict):
            return dict(ref)
        path = ref if os.path.isabs(ref) else os.path.join(self.tg, ref)
        p = read_json(path)
        if not isinstance(p, dict):
            raise ValueError(f"plan not found or not JSON: {ref}")
        return p

    def plan_secs(self, plan):
        return sum(float(s.get("secs") or s.get("auto_secs") or 3) for s in plan.get("steps", [])) + 20

    def collect(self, run_dir, plan, tag):
        """Results and logs of one plan into the run folder."""
        got = []
        rec = (plan.get("record") or {}).get("out")
        files = [("test_guide/status.json", f"{tag}_status.json")]
        if rec:
            files.append((rec, f"{tag}_{os.path.basename(rec)}"))
        for name in ("DPC_trace.json", "DPC_session.json", "DPC_cmd_ack.json", "DPC_arisen_brain.json",
                     "bench/flow_log.json", "bench/heartbeat.json"):
            files.append((name, f"{tag}_{os.path.basename(name)}"))
        for src, dst in files:
            f = os.path.join(self.data, src)
            if os.path.isfile(f):
                try:
                    shutil.copyfile(f, os.path.join(run_dir, dst))
                    got.append(dst)
                except OSError:
                    pass
        log = os.path.join(self.game, "re2_framework_log.txt")
        if os.path.isfile(log):  # the last 300 KB is plenty
            with open(log, "rb") as fh:
                fh.seek(max(0, os.path.getsize(log) - 300_000))
                open(os.path.join(run_dir, f"{tag}_re2_framework_log_tail.txt"), "wb").write(fh.read())
            got.append(f"{tag}_re2_framework_log_tail.txt")
        return got

    def crash_report(self, run_dir, tag, t_start):
        """Find the dump Windows wrote for this crash and read it."""
        dumps_dir = os.path.join(os.environ.get("LOCALAPPDATA", ""), "CrashDumps")
        rep = {"dump": None}
        for _ in range(30):  # Windows takes a while to write it (200 MB)
            dumps = [f for f in glob.glob(os.path.join(dumps_dir, "DD2.exe.*.dmp")) if os.path.getmtime(f) >= t_start - 5]
            if dumps:
                newest = max(dumps, key=os.path.getmtime)
                s1 = os.path.getsize(newest)
                time.sleep(3)
                if os.path.getsize(newest) == s1:
                    rep["dump"] = newest
                    break
            time.sleep(2)
        if rep["dump"]:
            try:
                rep.update(read_minidump(rep["dump"]))
                rep["names"] = resolve(([rep["where"]] if rep.get("where") else []) + rep.get("stack", []))
            except (OSError, ValueError, struct.error) as e:
                rep["error"] = str(e)
        else:
            rep["note"] = "no new dump in " + dumps_dir
        write_json(os.path.join(run_dir, f"{tag}_crash.json"), rep)
        return rep

    def start_video(self, run_dir, tag):
        if not shutil.which("ffmpeg"):
            self.say("video: ffmpeg not on the PATH (skipped)")
            return None
        out = os.path.join(run_dir, f"{tag}.mp4")
        cmd = ["ffmpeg", "-y", "-loglevel", "error", "-f", "lavfi", "-i",
               "ddagrab=output_idx=0:framerate=30,hwdownload,format=bgra,scale=1280:-2",
               "-c:v", "libx264", "-preset", "veryfast", "-crf", "30", "-pix_fmt", "yuv420p", out]
        try:
            return subprocess.Popen(cmd, stdin=subprocess.PIPE, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except OSError as e:
            self.say(f"video: could not start ffmpeg: {e}")
            return None

    @staticmethod
    def stop_video(proc):
        if not proc:
            return
        try:
            proc.communicate(b"q", timeout=20)
        except (subprocess.TimeoutExpired, OSError):
            proc.kill()

    def run_plan(self, job, run_id, run_dir, ref, attempt):
        plan = self.plan_obj(ref)
        base = str(plan.get("id") or "plan")
        tag = f"{base}" + (f"_try{attempt + 1}" if attempt else "")
        self.plan_n = getattr(self, "plan_n", 0) + 1  # (the same plan can be in a job more than once)
        plan["id"] = f"{base}@{run_id}.{self.plan_n}" + (f"#{attempt + 1}" if attempt else "")  # TestGuide runs each id once
        plan.pop("requires", None) if job.get("ignore_requires") else None
        res = {"plan": base, "id": plan["id"], "attempt": attempt + 1, "start": time.strftime("%H:%M:%S")}
        if job["scene"]:  # a known start (DPC's "scene" command runs when TestGuide loads the plan)
            plan["setup_cmds"] = [{"cmd": "scene", "anchor": "set" if job.get("_first_plan") else "go"}] + list(plan.get("setup_cmds") or [])
            job["_first_plan"] = False
        ok, why = self.ensure_world(job)
        if not ok:
            res.update(state="crash" if "crash" in why else "not run", why=why)
            return res
        self.set(phase="running", plan=base)
        self.renew_auto(run_id, block=job["save_block"])
        if job["save_block"]:  # wait (briefly) until the game reports the block is on
            for _ in range(10):
                hb = self.heartbeat()
                if hb and hb.get("save_block"):
                    break
                time.sleep(1)
            else:
                self.say("NOTE: the game did not confirm the save block (DevBench.lua 1.1 loaded?)")
        before = self.save_files()
        write_json(os.path.join(self.tg, "plan.json"), plan)
        self.say(f"plan {base}: started (attempt {attempt + 1})")
        video = self.start_video(run_dir, tag) if job["video"] else None
        t0, last_renew, limit = time.time(), time.time(), min(job["plan_timeout_s"], self.plan_secs(plan) + 180)
        state = None
        try:
            while True:
                time.sleep(2)
                if time.time() - last_renew > 30:
                    self.renew_auto(run_id, block=job["save_block"])
                    last_renew = time.time()
                st = read_json(os.path.join(self.tg, "status.json"), {})
                if st.get("id") == plan["id"] and st.get("state") in ("done", "aborted"):
                    state = st["state"]
                    res.update(verdicts=st.get("verdicts"), msg=st.get("msg"))
                    break
                if not self.alive():
                    state = "crash"
                    break
                hb = self.heartbeat()
                if hb and hb["age"] > job["hang_s"]:
                    state = "hang"
                    break
                if time.time() - t0 > limit:
                    state = "timeout"
                    res["status_seen"] = st
                    break
                if self.stopped():
                    state = "stopped"
                    break
        finally:
            self.stop_video(video)
        res.update(state=state, secs=round(time.time() - t0))
        after = self.save_files()
        changed = sorted(k for k in set(before) | set(after) if before.get(k) != after.get(k))
        res["save_written"] = changed
        if changed:
            self.say(f"plan {base}: the save files changed during the plan: {', '.join(changed[:4])}")
        hb = self.heartbeat() or {}
        res["saves_seen"], res["saves_blocked"] = hb.get("saves_seen"), hb.get("saves_blocked")
        if state in ("crash", "hang", "timeout"):
            step = read_json(os.path.join(self.tg, "status.json"), {})
            res["at_step"] = step.get("step") if step.get("id") == plan["id"] else None
        if state in ("hang", "timeout"):
            pid = self.alive()
            if pid and pid == self.launched_pid:
                self.say(f"plan {base}: {state}; closing the game (the bench started it)")
                subprocess.run(["taskkill", "/PID", str(pid), "/F"], capture_output=True)
                time.sleep(5)
            elif pid:
                self.say(f"plan {base}: {state}; the game was not started by the bench, so it is left running")
        res["files"] = self.collect(run_dir, plan, tag)
        if state in ("crash", "hang"):
            self.set(phase="reading the crash")
            rep = self.crash_report(run_dir, tag, t0) if state == "crash" else {}
            res["crash"] = {k: rep.get(k) for k in ("where", "code", "address", "names", "dump", "note") if rep.get(k)}
        self.say(f"plan {base}: {state}" + (f" at step {res.get('at_step')}" if res.get("at_step") else "")
                 + (f" ({res['crash'].get('where')})" if res.get("crash", {}).get("where") else ""))
        return res

    # -- a job
    def run_job(self, job_path):
        raw = read_json(job_path)
        if not isinstance(raw, dict) or not raw.get("plans"):
            self.say(f"job {os.path.basename(job_path)}: not a job (no plans)")
            return None
        job = dict(DEFAULTS, **raw)
        job["id"] = str(job.get("id") or os.path.splitext(os.path.basename(job_path))[0])
        run_id = time.strftime("%Y%m%d-%H%M%S") + "_" + job["id"]
        run_dir = self.p("runs", run_id)
        os.makedirs(run_dir, exist_ok=True)
        shutil.copyfile(job_path, os.path.join(run_dir, "job.json"))
        summary = {"run": run_id, "job": job["id"], "title": job.get("title"), "start": time.strftime("%Y-%m-%d %H:%M:%S"),
                   "plans": [], "crashes": 0, "state": "running"}
        job["_first_plan"] = True
        self.set(running=True, job=job["id"], run=run_id, phase="starting")
        self.say(f"job {job['id']}: {len(job['plans'])} plan(s)")
        try:
            self.backup_saves()
        except OSError as e:
            self.say(f"save backup failed: {e}")
        for ref in job["plans"]:
            attempt = 0
            while True:
                if self.stopped():
                    summary["state"] = "stopped"
                    break
                try:
                    res = self.run_plan(job, run_id, run_dir, ref, attempt)
                except (ValueError, OSError) as e:
                    res = {"plan": str(ref), "state": "error", "why": str(e)}
                summary["plans"].append(res)
                write_json(os.path.join(run_dir, "summary.json"), summary)
                if res.get("state") in ("crash", "hang"):
                    summary["crashes"] += 1
                    if summary["crashes"] >= job["max_crashes"]:
                        summary["state"] = "too many crashes"
                        break
                    if job["retry_after_crash"] and attempt == 0:
                        attempt += 1
                        continue
                if res.get("state") == "not run" and "did not start it" in str(res.get("why")):
                    summary["state"] = "waiting for the game to be free"
                    break
                if job["title_between"] and res.get("state") == "done":
                    t_state = self.to_title(job, str(res.get("plan")))
                    res["to_title"] = t_state
                    write_json(os.path.join(run_dir, "summary.json"), summary)
                    if t_state == "crash":
                        res["state"] = "crash on the way to title"
                        summary["crashes"] += 1
                        res["crash"] = {k: v for k, v in self.crash_report(run_dir, str(res.get("plan")) + "_title", time.time() - 120).items()
                                        if k in ("where", "code", "address", "names", "dump", "note") and v}
                        self.say(f"CRASH on the way to the title menu ({res['crash'].get('where')})")
                        if summary["crashes"] >= job["max_crashes"]:
                            summary["state"] = "too many crashes"
                            break
                    elif t_state == "failed":
                        summary["state"] = "could not reach the title menu"
                        break
                if job["revert"] == "each_plan" and res.get("state") == "done":
                    if res.get("save_written"):
                        self.say("revert skipped: the save changed during the plan (the restart would not undo it)")
                    else:
                        self.restart_game("after " + str(res.get("plan")))
                break
            if summary["state"] != "running":
                break
        if summary["state"] == "running":
            summary["state"] = "done"
        summary["end"] = time.strftime("%Y-%m-%d %H:%M:%S")
        summary["save_written"] = sorted({f for r in summary["plans"] for f in (r.get("save_written") or [])})
        self.renew_auto(run_id, on=False, block=job["save_block"])
        if job["revert"] == "job_end" and not summary["save_written"]:
            if self.restart_game("job end") and not job["quit_at_end"]:
                self.ensure_world(job)
        if job["quit_at_end"] and self.launched_pid and self.alive() == self.launched_pid:
            subprocess.run(["taskkill", "/PID", str(self.launched_pid), "/F"], capture_output=True)
            self.say("closed the game (job done)")
        write_json(os.path.join(run_dir, "summary.json"), summary)
        with open(os.path.join(run_dir, "summary.md"), "w", encoding="utf-8") as fh:
            fh.write(f"# {job['id']}: {summary['state']}\n\n{summary['start']} to {summary['end']}, crashes: {summary['crashes']}, "
                     f"save files written: {', '.join(summary['save_written']) or 'none'}\n\n")
            for r in summary["plans"]:
                fh.write(f"- {r.get('plan')} (try {r.get('attempt', 1)}): {r.get('state')}"
                         + (f", at step {r['at_step']}" if r.get("at_step") else "")
                         + (f", {r['crash'].get('where')}" if r.get("crash", {}).get("where") else "")
                         + (f", {r.get('why')}" if r.get("why") else "") + "\n")
        self.set(running=False, phase="idle", plan=None, last_run=run_id, last_state=summary["state"])
        self.say(f"job {job['id']}: {summary['state']}")
        return summary

    def take_jobs(self):
        jobs = sorted(glob.glob(self.p("jobs", "*.json")))
        for j in jobs:
            if self.stopped():
                return
            summary = self.run_job(j)
            if summary and summary["state"] == "waiting for the game to be free":
                continue  # left in jobs\ to try again later
            os.makedirs(self.p("jobs", "done"), exist_ok=True)
            try:
                os.replace(j, self.p("jobs", "done", time.strftime("%Y%m%d-%H%M%S_") + os.path.basename(j)))
            except OSError:
                pass

    def watch(self):
        self.say(f"test bench watching {self.p('jobs')}")
        self.set(running=False, phase="idle")
        while not self.stopped():
            self.take_jobs()
            time.sleep(5)
        self.set(running=False, phase="stopped")
        self.say("test bench stopped")

    # -- for the desk
    def start_thread(self):
        if self.thread and self.thread.is_alive():
            return False
        self.stop_flag = False
        try:
            os.remove(self.p("stop.json"))
        except OSError:
            pass
        self.thread = threading.Thread(target=self.watch, daemon=True)
        self.thread.start()
        return True

    def stop_thread(self):
        self.stop_flag = True
        return True

    def runs(self, n=20):
        out = []
        for d in sorted(glob.glob(self.p("runs", "*")), reverse=True)[:n]:
            s = read_json(os.path.join(d, "summary.json"), {})
            out.append({"run": os.path.basename(d), "state": s.get("state"), "crashes": s.get("crashes"),
                        "plans": [{k: r.get(k) for k in ("plan", "state", "attempt", "at_step", "crash", "why", "verdicts")}
                                  for r in s.get("plans", [])]})
        return out

    def info(self):
        return {"state": dict(self.state, lines=self.lines[-40:]), "heartbeat": self.heartbeat(),
                "thread": bool(self.thread and self.thread.is_alive()),
                "jobs": [os.path.basename(j) for j in sorted(glob.glob(self.p("jobs", "*.json")))], "runs": self.runs()}


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--game", help="the game folder (default: found automatically, or DD2_GAME_DIR)")
    ap.add_argument("--job", help="run this job file now, then exit")
    ap.add_argument("--dump", help="read a crash dump and print what it says")
    ap.add_argument("--status", action="store_true")
    a = ap.parse_args()
    if a.dump:
        rep = read_minidump(a.dump)
        rep["names"] = resolve(([rep["where"]] if rep.get("where") else []) + rep.get("stack", []))
        print(json.dumps(rep, indent=1))
        return 0
    b = Bench(a.game)
    if a.status:
        print(json.dumps(b.info(), indent=1))
        return 0
    try:
        if a.job:
            b.run_job(a.job)
        else:
            b.watch()
    except KeyboardInterrupt:
        b.say("stopped (Ctrl+C)")
        b.renew_auto("stopped", on=False, block="flag")
    return 0


if __name__ == "__main__":
    sys.exit(main())
