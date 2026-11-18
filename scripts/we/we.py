#!/usr/bin/env python3
"""Helpers for comparing the app's scenes with Wallpaper Engine's own drawing of them.

  we.py screen <shot.png>                       how the test machine's screen stands: "magenta <n>"
                                                (of 16 points, the plain desktop's 255,0,255) and
                                                "dialog" when WE's Safe Start dialog is up
  we.py distance <we> <ours> <out> [--previous <distances.tsv>]
                                                how far each scene of ours is from WE's: writes
                                                <out>/distances.tsv and <out>/report.html

WE's shots are taken at a moment of the scene's time nobody knows (it loads slowly in the
machine), so two pictures of the same scene are never the same pixel for pixel. The distance is
taken of both made small and blurred: what it shows is whether a scene looks like WE's — its
layout, colours, what is there — not every particle. A change of a stage that moves a scene away
from WE shows as its distance growing against the run before.
"""
import html
import os
import sys

from PIL import Image, ImageFilter

# Where the test machine's screen is sampled for the plain magenta desktop: a 4 x 4 grid.
POINTS = [(int(1280 * (i + 0.5) / 4), int(800 * (j + 0.5) / 4)) for i in range(4) for j in range(4)]
# WE's Safe Start dialog: its blue OK button.
DIALOG_BUTTON = [(740, 276), (790, 276)]
# WE's own window, which it opens after it fell over and started again: its blue "Installed" tab
# and OK button; and where its Cancel button is.
WINDOW_MARKS = [(160, 135), (976, 717)]
WINDOW_CANCEL = (1082, 717)
# What is left out of both: Windows' "not activated" note in the bottom right corner.
MASK = (920, 690, 1280, 800)
SMALL = (320, 200)


def screen(path):
    image = Image.open(path).convert('RGB')
    if image.size != (1280, 800):
        image = image.resize((1280, 800))
    px = image.load()
    magenta = sum(1 for x, y in POINTS if px[x, y][0] > 200 and px[x, y][1] < 60 and px[x, y][2] > 200)
    print('magenta', magenta)
    if all(px[x, y][2] > 180 and px[x, y][0] < 80 for x, y in DIALOG_BUTTON):
        print('dialog')
    if all(px[x, y][2] > 200 and px[x, y][0] < 130 for x, y in WINDOW_MARKS):
        print('window')


def small(path):
    import numpy as np
    image = Image.open(path).convert('RGB').resize((1280, 800), Image.LANCZOS)
    image.paste((0, 0, 0), MASK)
    return np.asarray(image.resize(SMALL, Image.LANCZOS).filter(ImageFilter.GaussianBlur(2)), dtype=np.float32)


def distance(we_dir, ours_dir, out, previous=None):
    import numpy as np
    os.makedirs(out, exist_ok=True)
    before = {}
    if previous and os.path.exists(previous):
        for line in open(previous):
            parts = line.rstrip('\n').split('\t')
            if len(parts) >= 2 and parts[0] != 'scene':
                before[parts[0]] = float(parts[1])
    rows = []
    for name in sorted(os.listdir(we_dir)):
        if not name.endswith('.png'):
            continue
        scene = name[:-4]
        ours = os.path.join(ours_dir, name)
        if not os.path.exists(ours):
            rows.append((scene, None, before.get(scene)))
            continue
        a, b = small(os.path.join(we_dir, name)), small(ours)
        rows.append((scene, float(np.abs(a - b).mean()), before.get(scene)))
    with open(os.path.join(out, 'distances.tsv'), 'w') as tsv:
        tsv.write('scene\tdistance\tbefore\n')
        for scene, d, b in rows:
            tsv.write(f"{scene}\t{'' if d is None else f'{d:.2f}'}\t{'' if b is None else f'{b:.2f}'}\n")
    measured = [d for _, d, _ in rows if d is not None]
    worse = [(s, d, b) for s, d, b in rows if d is not None and b is not None and d > b + 1.5]
    better = [(s, d, b) for s, d, b in rows if d is not None and b is not None and d < b - 1.5]
    summary = (f"{len(measured)} scenes, mean distance {np.mean(measured):.2f}" if measured else "no scenes") + \
              (f"; {len(worse)} farther from WE than before, {len(better)} nearer" if before else "")
    print(summary)
    for s, d, b in worse:
        print(f"  farther: {s} {b:.2f} -> {d:.2f}")
    cells = []
    for scene, d, b in sorted(rows, key=lambda r: -(r[1] or 0)):
        delta = '' if d is None or b is None else f" ({d - b:+.2f})"
        mark = ' class="worse"' if d is not None and b is not None and d > b + 1.5 else ''
        we = os.path.relpath(os.path.join(we_dir, scene + '.png'), out)
        ours = os.path.relpath(os.path.join(ours_dir, scene + '.png'), out)
        cells.append(f'<tr{mark}><td>{html.escape(scene)}<br>{"—" if d is None else f"{d:.2f}"}{delta}</td>'
                     f'<td><img src="{html.escape(we)}"></td><td><img src="{html.escape(ours)}"></td></tr>')
    with open(os.path.join(out, 'report.html'), 'w') as page:
        page.write('<!doctype html><meta charset="utf-8"><title>WE comparison</title><style>'
                   ':root{color-scheme:light dark}body{font:13px -apple-system,sans-serif;margin:16px}'
                   'img{width:420px}td{vertical-align:top;padding:4px}tr.worse td:first-child{color:#d33;font-weight:600}'
                   '</style><h1>Our scenes against Wallpaper Engine</h1>'
                   f'<p>{html.escape(summary)}. Distance: mean channel difference (0–255) of both made 320×200 and '
                   'blurred; WE is shot at an unknown moment, so only a change between runs means something.</p>'
                   '<table><tr><th>scene</th><th>Wallpaper Engine</th><th>ours</th></tr>' + ''.join(cells) + '</table>')


if __name__ == '__main__':
    command = sys.argv[1] if len(sys.argv) > 1 else ''
    if command == 'screen':
        screen(sys.argv[2])
    elif command == 'distance':
        args = sys.argv[2:]
        previous = None
        if '--previous' in args:
            at = args.index('--previous')
            previous = args[at + 1]
            del args[at:at + 2]
        distance(*args[:3], previous=previous)
    else:
        print(__doc__)
        sys.exit(2)
