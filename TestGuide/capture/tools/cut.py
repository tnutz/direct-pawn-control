"""Cut the kept takes out of the recordings and, if asked, join them into one video with captions.

  python tools/capture/cut.py --shots shots.json --log log.json --marks marks.json --out out_folder [--final]

shots.json  the shot list CaptureGuide ran (order of the final video, captions)
log.json    CaptureGuide's log (which take of which shot was kept, and its serial number)
marks.json  from find_marks.py (where each serial number starts and ends in which file)

Writes out_folder/clips/<nn>_<shot id>_take<k>.mp4 for every kept take, out_folder/edit.json (what was used and
what is missing), and with --final out_folder/final.mp4: the clips in shot-list order, each with its caption in the
lower third for the first --caption-secs seconds, scaled to --height.

Clips are re-encoded so that the cut is frame-accurate. Needs ffmpeg on the PATH. Standard library only.
"""
import argparse, json, os, subprocess, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from spans import take_spans

FONTS = [r"C:\Windows\Fonts\arialbd.ttf", r"C:\Windows\Fonts\segoeuib.ttf", r"C:\Windows\Fonts\arial.ttf",
         "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", "/System/Library/Fonts/Helvetica.ttc"]


def local_font(wanted, out):
    """ffmpeg's text filter has no default font on Windows and trips over the colon in C:\\ paths, so the font
    is copied next to the output and named by a relative path with forward slashes."""
    import shutil
    src = next((f for f in ([wanted] if wanted else []) + FONTS if f and os.path.isfile(f)), None)
    if not src:
        raise SystemExit("No font found for the captions. Pass one with --font path\\to\\font.ttf")
    dst = os.path.join(out, "_caption_font" + os.path.splitext(src)[1])
    shutil.copyfile(src, dst)
    try:
        rel = os.path.relpath(dst).replace("\\", "/")
    except ValueError:  # output on another drive than the current folder
        rel = dst.replace("\\", "/")
    return rel.replace(":", "\\:")


def run(cmd):
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        sys.stderr.write(r.stderr[-2000:] + "\n")
        raise SystemExit(f"ffmpeg failed: {' '.join(cmd[:6])} ...")


def esc(text):
    return text.replace("\\", "\\\\").replace(":", "\\:").replace("'", "’").replace("%", "\\%").replace(",", "\\,")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--shots", required=True); ap.add_argument("--log", required=True); ap.add_argument("--marks", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--choices", help="edit_choices.json saved from the review page: take, trims and caption per shot")
    ap.add_argument("--final", action="store_true")
    ap.add_argument("--proxy", action="store_true", help="with --final: also out/proxy.mp4, a small 360p copy to send for review")
    ap.add_argument("--height", type=int, default=1080)
    ap.add_argument("--fps", type=int, default=60)
    ap.add_argument("--caption-secs", type=float, default=3.0)
    ap.add_argument("--lead", type=float, default=0.05, help="seconds dropped after the start mark has gone")
    ap.add_argument("--font", default=None)
    a = ap.parse_args()

    shots = json.load(open(a.shots, encoding="utf-8"))["shots"]
    log = json.load(open(a.log, encoding="utf-8"))
    marks = json.load(open(a.marks, encoding="utf-8"))
    os.makedirs(os.path.join(a.out, "clips"), exist_ok=True)
    a.font = local_font(a.font, a.out)

    # where each take is: the start mark with its serial, and the first end mark with the same serial after it
    spans = take_spans(log, marks, a.lead)
    chosen = json.load(open(a.choices, encoding="utf-8")) if a.choices else {}
    choices = chosen.get("shots", {})
    if chosen.get("order"):  # the order set in the review page; shots it does not name keep their place at the end
        pos = {sid: n for n, sid in enumerate(chosen["order"])}
        shots = sorted(shots, key=lambda x: pos.get(x["id"], len(pos)))

    # which take each shot uses: the one picked in the review page (edit_choices.json), else the last kept one
    edit, clips = [], []
    kept = {}
    # the newest kept take; one that is in the recordings wins over one that is not
    found = {}
    for idx, t in enumerate(log.get("takes", [])):
        if t.get("verdict") == "keep":
            kept[t["shot"]] = idx
            if spans[idx]:
                found[t["shot"]] = idx
    kept.update(found)
    for sid, c in choices.items():
        if c.get("auto"):  # the desk's "newest kept take": follows new takes without the page being opened again
            continue
        if isinstance(c.get("take_index"), int) and 0 <= c["take_index"] < len(log.get("takes", [])):
            kept[sid] = c["take_index"]
    for i, s in enumerate(shots, 1):
        row = {"n": i, "shot": s["id"], "caption": s.get("caption")}
        if choices.get(s["id"], {}).get("skip"):
            row["status"] = "left out in the review page"
        elif s["id"] not in kept:
            row["status"] = "no kept take in the log"
        else:
            t, sp = log["takes"][kept[s["id"]]], spans[kept[s["id"]]]
            c = choices.get(s["id"], {})
            if "caption" in c:
                s = dict(s, caption=c["caption"]); row["caption"] = c["caption"]
            if isinstance(c.get("trims"), dict):  # the desk keeps trims per take
                tr = c["trims"].get(str(kept[s["id"]])) or {}
                tin, tout = float(tr.get("in") or 0), float(tr.get("out") or 0)
            else:
                tin, tout = float(c.get("trim_in") or 0), float(c.get("trim_out") or 0)
            if sp and (tin or tout):
                sp = [list(p) for p in sp]
                sp[0][1] += max(0.0, tin); sp[-1][2] -= max(0.0, tout)
                if any(p[2] - p[1] <= 0.05 for p in sp):
                    sp = None
            sp = {"parts": sp} if sp else None
            row.update(take=t["take"], serial=t["serial"])
            if not sp:
                row["status"] = "chosen, but its marks were not found in the recordings (or the trims leave nothing)"
            else:
                dst = os.path.join(a.out, "clips", f"{i:02d}_{s['id']}_take{t['take']}.mp4")
                s_id = s["id"]
                dur = round(sum(p[2] - p[1] for p in sp["parts"]), 3)
                vf = f"scale=-2:{a.height},fps={a.fps}"
                if s.get("caption") and a.final:
                    vf += (f",drawtext=fontfile={a.font}:text='{esc(s['caption'])}':fontcolor=white:fontsize=h/22:"
                           f"shadowcolor=black@0.7:shadowx=2:shadowy=2:x=(w-text_w)/2:y=h*0.80:"
                           f"enable='lt(t,{min(a.caption_secs, dur)})'")
                # -ss before -i: accurate when re-encoding, and the clip's own clock starts at 0 (the caption timing needs that)
                enc = ["-c:v", "libx264", "-preset", "medium", "-crf", "18", "-pix_fmt", "yuv420p",
                       "-c:a", "aac", "-b:a", "192k", "-ar", "48000", "-ac", "2"]
                if len(sp["parts"]) == 1:
                    f0, t0, t1 = sp["parts"][0]
                    run(["ffmpeg", "-y", "-v", "error", "-ss", f"{t0:.3f}", "-i", f0, "-t", f"{t1 - t0:.3f}", "-vf", vf] + enc + [dst])
                else:  # two files: join them first, then the same filter (so the caption clock runs over the join)
                    ins, n = [], len(sp["parts"])
                    for f0, t0, t1 in sp["parts"]:
                        ins += ["-ss", f"{t0:.3f}", "-t", f"{t1 - t0:.3f}", "-i", f0]
                    fc = "".join(f"[{k}:v:0][{k}:a:0]" for k in range(n)) + f"concat=n={n}:v=1:a=1[v0][a0];[v0]{vf}[v]"
                    run(["ffmpeg", "-y", "-v", "error"] + ins + ["-filter_complex", fc, "-map", "[v]", "-map", "[a0]"] + enc + [dst])
                row.update(status="cut", files=[p[0] for p in sp["parts"]], t0=round(sp["parts"][0][1], 3), secs=dur, clip=dst)
                clips.append(dst)
        edit.append(row)
        print(f"{i:02d} {s['id']:28} {row['status']}" + (f"  {row.get('secs')} s" if row.get("secs") else ""))
    json.dump(edit, open(os.path.join(a.out, "edit.json"), "w"), indent=1)

    if a.final and clips:
        lst = os.path.join(a.out, "clips", "list.txt")
        with open(lst, "w") as fh:
            for c in clips:
                fh.write(f"file '{os.path.abspath(c)}'\n")
        final = os.path.join(a.out, "final.mp4")
        run(["ffmpeg", "-y", "-v", "error", "-f", "concat", "-safe", "0", "-i", lst, "-c", "copy", final])
        print("final:", final)
        if a.proxy:
            proxy = os.path.join(a.out, "proxy.mp4")
            run(["ffmpeg", "-y", "-v", "error", "-i", final, "-vf", "scale=-2:360,fps=30", "-c:v", "libx264", "-preset", "veryfast",
                 "-crf", "34", "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "64k", proxy])
            print("proxy:", proxy)
    missing = [r for r in edit if r["status"] != "cut"]
    if missing:
        print(f"{len(missing)} shot(s) not in the cut; see edit.json")
    return 0


if __name__ == "__main__":
    sys.exit(main())
