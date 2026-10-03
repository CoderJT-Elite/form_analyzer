"""Print per-frame / per-attempt metrics for a recorded fixture (SessionRecorder or video-extracted).

    python tools/dump_rep_metrics.py app/test/fixtures/recordings/live5_pushupSide [signal]

Poses are levelled with the recorded gravity exactly as normalizePose does, then a few
analyzer-style signals are printed so thresholds can be chosen from real data instead of guessed.
"""
import json, math, sys

def lvl(p, g):
    gx, gy = g
    return {k: {**v, 'x': gy * v['x'] - gx * v['y'], 'y': gx * v['x'] + gy * v['y']} for k, v in p.items()}

def load(stem):
    P = json.load(open(stem + '_poses.json')); M = json.load(open(stem + '_meta.json'))
    out = []
    for p, m in zip(P, M['frames']):
        g = m.get('gravity') or [0, 1]
        out.append((m['t'] / 1000, lvl(p, g), m))
    return out, M

def ang(a, b, c):
    v1 = (a['x'] - b['x'], a['y'] - b['y']); v2 = (c['x'] - b['x'], c['y'] - b['y'])
    d = math.hypot(*v1) * math.hypot(*v2)
    return math.degrees(math.acos(max(-1, min(1, (v1[0]*v2[0] + v1[1]*v2[1]) / d)))) if d else float('nan')

def side(p, j):
    l, r = p.get('left' + j), p.get('right' + j)
    if l and r: return l if l['likelihood'] >= r['likelihood'] else r
    return l or r

def metrics(p):
    sh, hp, kn, an, el, wr = (side(p, j) for j in ('Shoulder', 'Hip', 'Knee', 'Ankle', 'Elbow', 'Wrist'))
    m = {}
    if sh and hp and kn: m['hipAng'] = ang(sh, hp, kn)
    if hp and kn and an: m['knee'] = ang(hp, kn, an)
    if sh and el and wr: m['elbow'] = ang(sh, el, wr)
    if sh and hp:
        m['torsoFromVert'] = math.degrees(math.atan2(abs(sh['x'] - hp['x']), hp['y'] - sh['y']))
        m['torsoElev'] = math.degrees(math.atan2(hp['y'] - sh['y'], abs(sh['x'] - hp['x'])))
    if sh and an:
        dx, dy = an['x'] - sh['x'], an['y'] - sh['y']; L = math.hypot(dx, dy)
        if hp and L:
            cross = dx * (hp['y'] - sh['y']) - dy * (hp['x'] - sh['x'])
            m['hipOffset'] = (1 if dx >= 0 else -1) * cross / (L * L)   # + = toward gravity (sag)
        m['tilt'] = math.degrees(math.atan2(abs(dy), abs(dx)))
    if hp and an: m['hipH'] = an['y'] - hp['y']
    return m

if __name__ == '__main__':
    frames, M = load(sys.argv[1])
    keys = sys.argv[2:] or ['knee', 'hipAng', 'elbow', 'torsoElev', 'hipOffset', 'tilt', 'hipH']
    ev = {round(e['t'] / 1000, 1): e for e in M.get('events', []) if e['type'] in ('rep',)}
    for t, p, m in frames:
        mm = metrics(p)
        mark = ' <<REP' if round(t, 1) in ev else ''
        print(f"{t:7.2f} " + ' '.join(f"{k}={mm[k]:7.2f}" if k in mm else f"{k}=   --  " for k in keys) + mark)
