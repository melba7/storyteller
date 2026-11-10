"""Write one spectrogram sheet per mood for a picks.csv.

Usage: python -I sheets_for_picks.py PICKS.csv FEATURES.csv OUT_DIR [IDS_ONLY_FILE]
Runs the sheets two at a time.
"""
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor

import pandas as pd

picks_path, feat_path, out_dir = sys.argv[1:4]
only = set(open(sys.argv[4]).read().split()) if len(sys.argv) > 4 else None
picks = pd.read_csv(picks_path)
feat = pd.read_csv(feat_path)
feat["id"] = feat.path.str.extract(r"/(c\d{4})\.m4a")[0]
path = dict(zip(feat.id, feat.path))
here = sys.argv[0].rsplit("/", 1)[0]
cmds = []
for mood, g in picks.groupby("mood", sort=False):
    if only is not None:
        g = g[g.id.isin(only)]
        if g.empty:
            continue
    items = []
    for r in g.itertuples():
        label = f"{r.id} {str(r.title_clean)[:28]}\n{str(r.artist)[:22]} lra {r.lra:.0f}"
        items.append(f"{label}|{path[r.id]}")
    cmd = [sys.executable, "-I", f"{here}/sheet.py", f"{out_dir}/{mood}.png",
           f"{feat_path.rsplit('/', 1)[0]}/yamnet", f"{mood}: {len(items)} picks"] + items
    cmds.append(cmd)
with ThreadPoolExecutor(max_workers=2) as pool:
    for cmd, res in zip(cmds, pool.map(lambda c: subprocess.run(c, capture_output=True, text=True), cmds)):
        print(cmd[3], "ok" if res.returncode == 0 else "FAILED " + res.stderr[-300:], flush=True)
