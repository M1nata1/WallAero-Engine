"""The report of scripts/compare.sh: what differs from the baseline, as an HTML page.

    compare-report.py <run folder> <baseline folder> <exclusions file> [<least share>]

Reads <run>/results.tsv (engine, scene, picture, differing pixels, all pixels, largest channel
difference, mean difference — or `missing` / `size`), the shot.json each scene left (frame
times, watts, notes) in both folders, and the exclusions (`scene<TAB>engine or *<TAB>reason`).
A picture differs only when more than <least share> of its pixels do (0.0001: a hundredth of a
per cent, 92 pixels of 1280×720); fewer are listed as tiny — a few pixels of a 3D model's hair or
of a particle that run to run come out a shade apart. Writes <run>/report.html and prints a
summary; exits 1 when anything not excluded differs.
"""
import html
import json
import os
import sys

run, baseline, exclusions_file = sys.argv[1], sys.argv[2], sys.argv[3]
least_share = float(sys.argv[4]) if len(sys.argv) > 4 else 0.0001


def excluded_reasons():
    reasons = {}
    if not os.path.exists(exclusions_file):
        return reasons
    with open(exclusions_file, encoding="utf-8") as f:
        for line in f:
            line = line.rstrip("\n")
            if not line or line.startswith("#"):
                continue
            parts = line.split("\t")
            if len(parts) >= 3:
                reasons[(parts[0], parts[1])] = parts[2]
    return reasons


def reason_for(reasons, scene, engine):
    return reasons.get((scene, engine)) or reasons.get((scene, "*"))


def summary(folder, engine, scene):
    path = os.path.join(folder, engine, scene, "shot.json")
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return None


reasons = excluded_reasons()
rows = []
with open(os.path.join(run, "results.tsv"), encoding="utf-8") as f:
    for line in f:
        parts = line.rstrip("\n").split("\t")
        if len(parts) < 7:
            continue
        engine, scene, picture, differing, total, largest, mean = parts[:7]
        if differing in ("missing", "size"):
            kind, share = differing, None
        else:
            share = int(differing) / max(1, int(total))
            kind = "same" if int(differing) == 0 else ("tiny" if share <= least_share else "differs")
        rows.append({"engine": engine, "scene": scene, "picture": picture, "kind": kind, "share": share,
                     "largest": largest, "mean": mean, "excluded": reason_for(reasons, scene, engine)})


def rel(path):
    return html.escape(os.path.relpath(path, run))


bad = [r for r in rows if r["kind"] not in ("same", "tiny") and not r["excluded"]]
excused = [r for r in rows if r["kind"] not in ("same", "tiny") and r["excluded"]]
tiny = [r for r in rows if r["kind"] == "tiny"]
same = [r for r in rows if r["kind"] == "same"]

# Frame times and watts, scene by scene, beside the baseline's.
timings = []
for engine, scene in sorted({(r["engine"], r["scene"]) for r in rows}):
    now, before = summary(run, engine, scene), summary(baseline, engine, scene)
    if not now or not before or "timing" not in now or "timing" not in before:
        continue
    t, b = now["timing"], before["timing"]
    w, bw = (now.get("watts") or {}).get("total"), (before.get("watts") or {}).get("total")
    slower = b["p95"] > 0 and t["p95"] > b["p95"] * 1.25 and t["p95"] - b["p95"] > 1
    timings.append((engine, scene, b, t, bw, w, slower))


def figure(r):
    expected = os.path.join(baseline, r["engine"], r["scene"], r["picture"])
    actual = os.path.join(run, r["engine"], r["scene"], r["picture"])
    diff = os.path.join(run, r["engine"], r["scene"], "diff-" + r["picture"])
    what = {"missing": "no picture", "size": "another size"}.get(r["kind"])
    if what is None:
        what = "%.3f %% of pixels, up to %s, mean %s" % (r["share"] * 100, r["largest"], r["mean"])
    cells = ['<figure><img loading="lazy" src="%s"><figcaption>baseline</figcaption></figure>' % rel(expected)]
    if os.path.exists(actual):
        cells.append('<figure><img loading="lazy" src="%s"><figcaption>now</figcaption></figure>' % rel(actual))
    if os.path.exists(diff):
        cells.append('<figure><img loading="lazy" src="%s"><figcaption>difference</figcaption></figure>' % rel(diff))
    reason = '<p class="reason">%s</p>' % html.escape(r["excluded"]) if r["excluded"] else ""
    return ('<section class="case"><h3>%s <span>%s · %s</span></h3><p>%s</p>%s<div class="row">%s</div></section>'
            % (html.escape(r["scene"]), html.escape(r["engine"]), html.escape(r["picture"]), html.escape(what), reason, "".join(cells)))


def number(value, digits=2):
    return "—" if value is None else ("%." + str(digits) + "f") % value


timing_rows = "".join(
    '<tr class="%s"><td>%s</td><td>%s</td><td>%s → %s</td><td>%s → %s</td><td>%s → %s</td></tr>'
    % ("slower" if slower else "", html.escape(scene), engine, number(b["p50"]), number(t["p50"]), number(b["p95"]), number(t["p95"]),
       number(bw), number(w))
    for engine, scene, b, t, bw, w, slower in timings)

page = """<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Scene comparison</title>
<style>
:root { --bg: #fafafa; --fg: #1d1d1f; --muted: #6e6e73; --line: #d2d2d7; --bad: #c4314b; --ok: #1b7f3b; --card: #fff; }
@media (prefers-color-scheme: dark) { :root { --bg: #1c1c1e; --fg: #f2f2f7; --muted: #98989d; --line: #3a3a3c; --bad: #ff6b81; --ok: #4cd964; --card: #2c2c2e; } }
body { background: var(--bg); color: var(--fg); font: 14px/1.45 -apple-system, system-ui, sans-serif; margin: 0 auto; padding: 24px 16px; max-width: 1500px; }
h1 { font-size: 22px; margin: 0 0 4px; } h2 { font-size: 17px; margin: 32px 0 8px; } h3 { font-size: 15px; margin: 0 0 4px; }
h3 span { color: var(--muted); font-weight: normal; }
.meta { color: var(--muted); } .count { font-size: 15px; } .bad { color: var(--bad); } .ok { color: var(--ok); }
.case { background: var(--card); border: 1px solid var(--line); border-radius: 8px; padding: 12px; margin: 12px 0; }
.case p { margin: 0 0 8px; color: var(--muted); } .reason { font-style: italic; }
.row { display: grid; grid-template-columns: repeat(auto-fit, minmax(280px, 1fr)); gap: 8px; }
figure { margin: 0; } img { width: 100%%; display: block; border-radius: 4px; } figcaption { color: var(--muted); font-size: 12px; }
table { border-collapse: collapse; width: 100%%; } td, th { text-align: left; padding: 4px 8px; border-bottom: 1px solid var(--line); }
tr.slower td { color: var(--bad); } details { margin-top: 8px; }
</style></head><body>
<h1>Scene comparison</h1>
<p class="meta">%s · against %s</p>
<p class="count"><span class="%s">%d differ</span> · %d excused · %d tiny · %d same</p>
<h2>Differ</h2>%s
<h2>Tiny</h2><p class="meta">At most %s of the pixels differ.</p><details><summary>%d pictures</summary>%s</details>
<h2>Excused</h2><p class="meta">Scenes that cannot come out the same each run; see scripts/compare-exclusions.txt.</p>%s
<h2>Frame time and watts</h2>
<p class="meta">Milliseconds a frame (native: script and encoding; Chromium: gaps between frames), and the whole Mac's watts, baseline → now. Red: p95 a quarter slower or more.</p>
<details><summary>%d scenes</summary><table><tr><th>Scene</th><th>Engine</th><th>p50</th><th>p95</th><th>Watts</th></tr>%s</table></details>
</body></html>
""" % (html.escape(os.path.basename(run.rstrip("/"))), html.escape(baseline), "bad" if bad else "ok", len(bad), len(excused), len(tiny), len(same),
       "".join(figure(r) for r in bad) or "<p class=\"ok\">Nothing.</p>",
       "%g %%" % (least_share * 100), len(tiny), "".join(figure(r) for r in tiny),
       "".join(figure(r) for r in excused) or "<p class=\"meta\">Nothing.</p>",
       len(timings), timing_rows)

with open(os.path.join(run, "report.html"), "w", encoding="utf-8") as f:
    f.write(page)

slower = sum(1 for t in timings if t[6])
print("%d pictures differ, %d excused, %d tiny, %d same; %d scenes slower" % (len(bad), len(excused), len(tiny), len(same), slower))
print("report: " + os.path.join(run, "report.html"))
sys.exit(1 if bad else 0)
