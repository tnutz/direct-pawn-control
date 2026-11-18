"""Find CaptureGuide's sync marks in video files.

  python tools/capture/find_marks.py recording1.mkv [recording2.mkv ...] -o marks.json

CaptureGuide draws a strip of ten squares in the top-left corner of the game picture for a few frames at the
start of every take and again after its end: square 1 white, square 2 magenta (start) or cyan (end), squares 3-10
the take's serial number in binary (white = 1, black = 0). Each square is 1/45 of the picture height.

The recording must be the game picture edge to edge (OBS game capture or window capture of the client area, no
borders), at any resolution. Needs ffmpeg and ffprobe on the PATH. Standard library only.
"""
import argparse, json, subprocess, sys

W, H = 100, 10  # the strip, scaled so that every square is 10 x 10


def probe_fps(path):
    out = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries", "stream=r_frame_rate",
                          "-of", "csv=p=0", path], capture_output=True, text=True, check=True).stdout.strip()
    num, _, den = out.partition("/")
    return float(num) / float(den or 1)


def classify(px):
    r, g, b = px
    if r > 190 and g > 190 and b > 190:
        return "W"
    if r < 80 and g < 80 and b < 80:
        return "K"
    if r > 170 and b > 170 and g < 110:
        return "M"
    if g > 170 and b > 170 and r < 110:
        return "C"
    return "?"


def read_mark(frame):
    """frame: W*H*3 bytes -> (kind, serial) or None"""
    cells = []
    for i in range(10):
        # the middle 4 x 4 of the square, averaged (scaling and compression blur the edges)
        acc = [0, 0, 0]
        for y in range(3, 7):
            for x in range(i * 10 + 3, i * 10 + 7):
                o = (y * W + x) * 3
                acc[0] += frame[o]; acc[1] += frame[o + 1]; acc[2] += frame[o + 2]
        cells.append(classify([v / 16 for v in acc]))
    if cells[0] != "W" or cells[1] not in ("M", "C"):
        return None
    if any(c not in ("W", "K") for c in cells[2:]):
        return None
    serial = 0
    for c in cells[2:]:
        serial = (serial << 1) | (1 if c == "W" else 0)
    return ("start" if cells[1] == "M" else "end", serial)


def scan(path):
    fps = probe_fps(path)
    cmd = ["ffmpeg", "-v", "error", "-i", path, "-an", "-vf", f"crop=ih*10/45:ih/45:0:0,scale={W}:{H}:flags=area",
           "-f", "rawvideo", "-pix_fmt", "rgb24", "-"]
    p = subprocess.Popen(cmd, stdout=subprocess.PIPE)
    size, n, marks, cur = W * H * 3, 0, [], None
    while True:
        buf = p.stdout.read(size)
        if len(buf) < size:
            break
        m = read_mark(buf)
        if m and cur and (cur["kind"], cur["serial"]) == m and n - cur["last_frame"] <= 2:
            cur["last_frame"] = n
        elif m:
            cur = {"kind": m[0], "serial": m[1], "first_frame": n, "last_frame": n}
            marks.append(cur)
        n += 1
    p.wait()
    for m in marks:
        m["t_first"] = round(m["first_frame"] / fps, 4)
        m["t_last"] = round((m["last_frame"] + 1) / fps, 4)  # the time the mark is gone
    # a mark seen on a single frame is most likely a coincidence in the picture
    marks = [m for m in marks if m["last_frame"] - m["first_frame"] >= 1]
    return {"file": path, "fps": round(fps, 3), "frames": n, "marks": marks}


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("videos", nargs="+")
    ap.add_argument("-o", "--out", default="marks.json")
    a = ap.parse_args()
    res = [scan(v) for v in a.videos]
    json.dump(res, open(a.out, "w"), indent=1)
    for r in res:
        print(f"{r['file']}: {r['frames']} frames at {r['fps']} fps, {len(r['marks'])} marks")
        for m in r["marks"]:
            print(f"   {m['kind']:5} serial {m['serial']:3}  {m['t_first']:9.3f} s")
    return 0


if __name__ == "__main__":
    sys.exit(main())
