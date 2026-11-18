"""Shared by cut.py and review_page.py: where each logged take is in the recordings."""


def take_spans(log, marks, lead=0.05):
    """Returns a list parallel to log["takes"]: for each take a list of parts (file, t0, t1), or None when its
    marks were not found. A take that starts in one file and ends in the next gets two parts."""
    found = {}
    for fi, f in enumerate(marks):
        ms = f["marks"]
        for i, m in enumerate(ms):
            if m["kind"] != "start":
                continue
            parts, closed = None, False
            for e in ms[i + 1:]:
                if e["kind"] == "end" and e["serial"] == m["serial"]:
                    parts = [(f["file"], m["t_last"] + lead, e["t_first"])]
                    closed = True
                    break
                if e["kind"] == "start":
                    closed = True  # never closed by its own end mark in this file
                    break
            if not closed and fi + 1 < len(marks):
                nxt = marks[fi + 1]
                e = nxt["marks"][0] if nxt["marks"] else None
                if e and e["kind"] == "end" and e["serial"] == m["serial"]:
                    parts = [(f["file"], m["t_last"] + lead, f["frames"] / f["fps"]), (nxt["file"], 0.0, e["t_first"])]
            if parts:
                found.setdefault(m["serial"], []).append(parts)
    # serial numbers wrap at 255: the n-th use of a serial in the log is the n-th span found for it
    used, out = {}, []
    for t in log.get("takes", []):
        n = used.get(t["serial"], 0)
        used[t["serial"]] = n + 1
        sp = found.get(t["serial"], [])
        out.append(sp[n] if n < len(sp) else None)
    return out
