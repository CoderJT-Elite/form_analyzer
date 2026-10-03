"""Print the peaks and valleys of a metric in a fixture, to choose rep thresholds from data.

    python tools/peaks.py <fixture-stem-or-pose_sequences-name> <metric> [min_swing] [fps]
metric: hipAng | knee | elbow | torsoElev | spread | arm
"""
import json, math, os, sys
sys.path.insert(0, os.path.dirname(__file__))
from dump_rep_metrics import metrics, side, lvl

GRAV = {'live2_plank': (-1, 0), 'live2_pushup': (-1, 0), 'live2_situp': (-1, 0), 'live2_gluteBridge': (-1, 0),
        'live3_plank': (-1, 0), 'live3_pushupSide': (-1, 0), 'live3_pushupFloor': (-1, 0), 'live3_situp': (-1, 0),
        'live3_gluteBridge': (-1, 0)}

def load(name, fps):
    root = os.path.join(os.path.dirname(__file__), '..', 'app', 'test', 'fixtures')
    rec = os.path.join(root, 'recordings', name + '_poses.json')
    if os.path.exists(rec):
        P = json.load(open(rec)); M = json.load(open(os.path.join(root, 'recordings', name + '_meta.json')))['frames']
        return [(m['t'] / 1000, lvl(p, m.get('gravity') or [0, 1])) for p, m in zip(P, M)]
    P = json.load(open(os.path.join(root, 'pose_sequences', name + '.json')))
    g = GRAV.get(name, (0, 1))
    return [(i / fps, lvl(p, g)) for i, p in enumerate(P)]

def val(p, metric):
    mm = metrics(p)
    if metric == 'spread':
        l, r = p.get('leftAnkle'), p.get('rightAnkle'); ls, rs = p.get('leftShoulder'), p.get('rightShoulder')
        if l and r and ls and rs and min(l['likelihood'], r['likelihood']) > .5:
            sw = abs(ls['x'] - rs['x']); return abs(l['x'] - r['x']) / sw if sw > 1 else None
        return None
    if metric == 'spreadT':
        l, r = p.get('leftAnkle'), p.get('rightAnkle'); ls, rs = p.get('leftShoulder'), p.get('rightShoulder')
        lh, rh = p.get('leftHip'), p.get('rightHip')
        if all((l, r, ls, rs, lh, rh)) and min(l['likelihood'], r['likelihood']) > .5:
            torso = math.hypot((ls['x']+rs['x'])/2-(lh['x']+rh['x'])/2, (ls['y']+rs['y'])/2-(lh['y']+rh['y'])/2)
            return abs(l['x'] - r['x']) / torso if torso > 1 else None
        return None
    if metric == 'arm':
        best = None
        for s in ('left', 'right'):
            hp, sh, el = p.get(s + 'Hip'), p.get(s + 'Shoulder'), p.get(s + 'Elbow')
            if hp and sh and el:
                from dump_rep_metrics import ang
                c = el['likelihood']
                if best is None or c > best[0]: best = (c, ang(hp, sh, el))
        return best[1] if best else None
    return mm.get(metric)

if __name__ == '__main__':
    name, metric = sys.argv[1], sys.argv[2]
    swing = float(sys.argv[3]) if len(sys.argv) > 3 else 15
    fps = float(sys.argv[4]) if len(sys.argv) > 4 else 15
    pts = [(t, val(p, metric)) for t, p in load(name, fps)]
    pts = [(t, v) for t, v in pts if v is not None]
    # median-3 smooth
    sm = [(pts[i][0], sorted([pts[max(0,i-1)][1], pts[i][1], pts[min(len(pts)-1,i+1)][1]])[1]) for i in range(len(pts))]
    ext = []; dirn = 0; best = sm[0]
    for t, v in sm[1:]:
        if dirn >= 0:
            if v > best[1]: best = (t, v)
            if best[1] - v >= swing and dirn >= 0:
                ext.append(('max', *best)); dirn = -1; best = (t, v)
        if dirn <= 0:
            if v < best[1]: best = (t, v)
            if v - best[1] >= swing and dirn <= 0:
                ext.append(('min', *best)); dirn = 1; best = (t, v)
    print(name, metric, 'n=', len(sm))
    print('  '.join(f"{k}@{t:.1f}={v:.0f}" if metric not in ('spread','spreadT') else f"{k}@{t:.1f}={v:.2f}" for k, t, v in ext))
