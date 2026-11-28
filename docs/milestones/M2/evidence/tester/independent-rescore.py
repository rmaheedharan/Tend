# Independent re-score (Acceptance Tester, AC-M2-14). Written from the brief's "Eval scoring rules", "Keywords of a
# text", "Name folding", "Banned tokens" and the M1 invariants only. Does not read or call the TendIngestion scorer.
# Usage: independent-rescore.py <fixtures dir> <results file>
#          [--provider <openai|anthropic|gemini> --allowed-key-paths <file> --golden-body <file>]
# The three options (all or none) add the DS-2 S6 cloud checks (AC-M2-26, D-059), written from the brief's "Results
# file", plan WI-M2-15 "Per-array element counts", results-v1.schema.json and the golden bodies only. Exit 1 if a cloud
# check fails, 2 on bad arguments.
import json, sys, unicodedata, re, math
from datetime import datetime
ARGS = sys.argv[1:]; OPT = {}
while len(ARGS) > 2 and ARGS[-2].startswith('--'):
    OPT[ARGS[-2][2:]] = ARGS[-1]; ARGS = ARGS[:-2]
if len(ARGS) != 2 or (OPT and set(OPT) != {'provider', 'allowed-key-paths', 'golden-body'}):
    print('usage: independent-rescore.py DIR RESULTS [--provider P --allowed-key-paths F --golden-body F]'); sys.exit(2)
d = ARGS[0]; res = json.load(open(ARGS[1]))
inputs = {i['id']: i for i in json.load(open(d+'/inputs.json'))['inputs']}
order = [i['id'] for i in json.load(open(d+'/inputs.json'))['inputs']]
hh = json.load(open(d+'/household.json')); gold = json.load(open(d+'/golden.json'))['items']
STOP = set("""a an the and or but of to in on at for with from by about before after this that these those it its is are
be been was were we us our i me my you your re s t ll ve d m need needs let lets get got some any all more almost out up
again also just really please maybe should must can will would could do does did have has had if then so too very no
not wait um uh like okay ok""".split())
BANNED = {"overdue","late","lateness","missed","failed","behind","penalty","debt","streak"}
def fold(s):
    s = s.replace('’',"'").replace('‘',"'").replace('“','"').replace('”','"')
    s = unicodedata.normalize('NFKC', s)  # width
    s = ''.join(c for c in unicodedata.normalize('NFD', s) if not unicodedata.combining(c))
    s = ' '.join(s.split()).lower()
    return s
def namefold(s):
    s = fold(s)
    for a in ("the ","a ","an ","my ","our "):
        if s.startswith(a): return s[len(a):]
    return s
def keywords(s):
    if not s: return []
    toks = re.split(r'[^\w]|_', fold(s)); out=[]
    for t in toks:
        if t and t not in STOP and t not in out: out.append(t)
    return out
def letters_tokens(s):
    return [namefold(t) for t in re.split(r'[^A-Za-zÀ-ɏ]+', s) if t]
def dtext(dr):
    k = keywords(dr['title'])
    for t in keywords(dr.get('sourcePhrase')):
        if t not in k: k.append(t)
    return k
def satisfies(dt, groups): return all(any(t in g for t in dt) for g in groups)
def overlap(dt, groups):
    allg = set().union(*map(set, groups)); return sum(1 for t in dt if t in allg)
def valid(dr):
    if not dr['title'].strip(): return 'emptyTitle'
    if not dr['allowedDayparts']: return 'noAllowedDayparts'
    if not dr['allowedWeekdays']: return 'noAllowedWeekdays'
    p = lambda x: datetime.fromisoformat(x.replace('Z','+00:00'))
    if not p(dr['windowEnd']) > p(dr['windowStart']): return 'windowEndNotAfterStart'
    iv = dr['recurrenceIntervalDays']
    if dr['kind']=='recurring' and iv is None: return 'recurringWithoutInterval'
    if dr['kind']=='recurring' and iv < 1: return 'intervalBelowOneDay'
    if dr['kind']!='recurring' and iv is not None: return 'intervalOnNonRecurringTask'
    if dr['isCritical'] and dr['isDeepClean']: return 'criticalAndDeepClean'
    return None
def room_ok(dr, g):
    r, e = dr['room'], g['room']
    if e['type']=='none': return r['type']=='none'
    if e['type']=='existing': return r['type']=='existing' and r['roomKey']==e['roomKey']
    if e['type']=='new':
        return r['type']=='proposed' and namefold(r['name']) in {namefold(e['name'])}|{namefold(a) for a in e['alternates']}
fields = ['segmentation','kind','room','effort','isCritical','isDeepClean','isWeatherDependent']
T = {f:0 for f in fields}; N=0; extras=0; drafts=0; validn=0; intro=0; dups=0; fm=0
for iid in order:
    att = [x for x in res['inputs'] if x['inputID']==iid]
    if not att: print(iid,'ABSENT'); continue
    a = max(att, key=lambda x: x['attempt'])
    G = [g for g in gold if g['inputID']==iid]; N += len(G)
    D = a['drafts']; drafts += len(D)
    src = (a['transcript'] if a['mode']=='voice' and a['transcript'] else inputs[iid]['text'])
    srct = set(letters_tokens(src))
    for dr in D:
        v = valid(dr); validn += v is None
        for t in letters_tokens(dr['title']):
            if t in BANNED and t not in srct: intro += 1; print(f'  {iid} d{dr["draftID"]} introduced title {t}')
        if dr['room']['type']=='proposed':
            for t in letters_tokens(dr['room']['name']):
                if t in BANNED and t not in srct: intro += 1; print(f'  {iid} d{dr["draftID"]} introduced room {t}')
        if v: print(f'  {iid} d{dr["draftID"]} invalid {v}')
    DT = {dr['draftID']: dtext(dr) for dr in D}
    prim = [dr for dr in D if dr['duplicate']['type']!='ofDraft']
    pairs = sorted([(-overlap(DT[dr['draftID']], g['matchGroups']), gi, dr['draftID'])
                    for gi,g in enumerate(G) for dr in prim if satisfies(DT[dr['draftID']], g['matchGroups'])])
    tg, td, match = set(), set(), {}
    for o, gi, di in pairs:
        if gi in tg or di in td: continue
        tg.add(gi); td.add(di); match[gi]=di
    ex = [dr['draftID'] for dr in prim if dr['draftID'] not in td]; extras += len(ex)
    byid = {dr['draftID']: dr for dr in D}
    per = []
    for gi,g in enumerate(G):
        if gi not in match: per.append(f'{g["key"]}:notfound'); continue
        dr = byid[match[gi]]; T['segmentation']+=1; bad=[]
        for f in ['kind','effort','isCritical','isDeepClean','isWeatherDependent']:
            if dr[f]==g[f]: T[f]+=1
            else: bad.append(f)
        if room_ok(dr,g): T['room']+=1
        else: bad.append('room')
        per.append(f'{g["key"]}<-d{match[gi]}' + (' wrong:'+','.join(bad) if bad else ''))
    # best targets
    targets = [(0, g['key'], g['matchGroups']) for g in G if g['expect']['type']=='create'] + \
              [(1, t['key'], t['matchGroups']) for t in hh['tasks'] if t['state']!='completed']
    best = {}
    for dr in D:
        c = [(-overlap(DT[dr['draftID']], m), kind, key) for kind,key,m in targets if satisfies(DT[dr['draftID']], m)]
        best[dr['draftID']] = min(c)[1:] if c else None
    cnt = {}
    for di in a['committed']:
        b = best[di]
        if b: cnt[b] = cnt.get(b,0)+1
    du = sum(max(0,v-1) for (k,_),v in cnt.items() if k==0) + sum(v for (k,_),v in cnt.items() if k==1); dups += du
    f = 0
    for g in G:
        if g['expect']['type']!='create': continue
        marked = any(best[dr['draftID']]==(0,g['key']) and dr['duplicate']['type'] in ('ofExisting','ofDraft') for dr in D)
        if marked and cnt.get((0,g['key']),0)==0: f+=1; print(f'  {iid} false merge {g["key"]}')
    fm += f
    print(iid, f'att {a["attempt"]}', ' '.join(per), f'extras {ex}', 'best', {k:v for k,v in best.items()}, f'dup {du} fm {f}')
req = {'segmentation':.95,'kind':.95,'room':.90,'effort':.85,'isCritical':.95,'isDeepClean':.95,'isWeatherDependent':.95}
print(f'TOTAL N {N} extras {extras} drafts {drafts} valid {validn} introduced {intro} duplicates {dups} falseMerges {fm}')
for f in fields: print(f'  {f} {T[f]} of {N} (required {math.ceil(req[f]*N - 1e-9)})')

# ---- DS-2 S6 cloud checks (AC-M2-26, D-059): every request of every attempt, retakes included ----
if OPT:
    prov = OPT['provider']
    if prov not in ('openai', 'anthropic', 'gemini') or \
       not OPT['allowed-key-paths'].endswith(f'allowed-key-paths-{prov}.json') or \
       not OPT['golden-body'].endswith(f'g1-outcome-empty-{prov}.body.json'):
        print(f'CLOUD arguments do not all name provider {prov!r}'); sys.exit(2)
    def strict(b):
        def no_const(c): raise ValueError('non-JSON constant ' + c)
        def no_dup(pairs):
            keys = [k for k, _ in pairs]
            if len(keys) != len(set(keys)): raise ValueError('duplicate member')
            return dict(pairs)
        return json.loads(b, parse_constant=no_const, object_pairs_hook=no_dup)
    NAME = re.compile(r'[A-Za-z0-9_-]+\Z')
    COUNT_PATH = re.compile(r'\$(\.[A-Za-z0-9_-]+|\[(0|[1-9][0-9]*)\])*\Z')
    KEY_PATH = re.compile(r'\$(\.[A-Za-z0-9_-]+|\[\])*\Z')
    def my_counts(v, path='$', out=None):
        # Every array at any depth (empty ones and arrays in arrays too): path with concrete indices, element count.
        out = {} if out is None else out
        if isinstance(v, list):
            out[path] = len(v)
            for i, x in enumerate(v): my_counts(x, f'{path}[{i}]', out)
        elif isinstance(v, dict):
            for k, x in v.items():
                if not NAME.match(k): raise ValueError(f'member name {k!r} outside the path pattern')
                my_counts(x, f'{path}.{k}', out)
        return out
    golden = my_counts(strict(open(OPT['golden-body'], 'rb').read().decode('utf-8')))
    allowed = {k['path'] for k in json.load(open(OPT['allowed-key-paths']))['keyPaths']}
    rooms_expected = len(hh['rooms'])
    print(f'CLOUD provider {prov}: golden arrays {len(golden)}, allowed key paths {len(allowed)}, '
          f'seeded rooms {rooms_expected}')
    u8 = lambda t: t.encode('utf-8')
    fails_kp, fails_ct, fails_other = [], [], []
    def shape(lst, where, tag):
        # null, or a list of {count, path} with exactly those members, path pattern, sorted by UTF-8 bytes, unique.
        if lst is None: return None
        if not isinstance(lst, list): fails_ct.append(f'{where} {tag} not a list'); return None
        ok = True
        for e in lst:
            if not (isinstance(e, dict) and set(e) == {'count', 'path'} and isinstance(e['path'], str)
                    and type(e['count']) is int and e['count'] >= 0 and COUNT_PATH.match(e['path'])):
                fails_ct.append(f'{where} {tag} bad entry {e!r}'); ok = False
        if not ok: return None
        paths = [e['path'] for e in lst]
        if paths != sorted(paths, key=u8) or len(paths) != len(set(paths)):
            fails_ct.append(f'{where} {tag} not sorted by path or not unique'); return None
        return {e['path']: e['count'] for e in lst}
    def compare(where, tag, seen, want):
        for path in sorted(set(seen) | set(want), key=u8):
            if seen.get(path) != want.get(path):
                fails_ct.append(f'{where} {tag} {path}: expected {want.get(path, "absent")}, seen {seen.get(path, "absent")}')
    nreq = 0
    for a in res['inputs']:
        reqs = a['cloudRequests']
        if a['route'] != prov: fails_other.append(f"{a['inputID']} att {a['attempt']} route {a['route']}, not {prov}")
        if a['route'] == prov and not reqs: fails_other.append(f"{a['inputID']} att {a['attempt']} route {prov} but no request recorded")
        if [r.get('attempt') for r in reqs] != list(range(1, len(reqs) + 1)):
            fails_other.append(f"{a['inputID']} att {a['attempt']} request attempts not 1..{len(reqs)}")
        for r in reqs:
            nreq += 1; where = f"{a['inputID']} att {a['attempt']} req {r.get('attempt')}"
            if set(r) != {'arrayCounts', 'attempt', 'bytes', 'keyPaths', 'userContentArrayCounts'}:
                fails_other.append(f'{where} members {sorted(r)}'); continue
            kp = r['keyPaths']
            if not all(isinstance(k, str) and KEY_PATH.match(k) for k in kp) or len(kp) != len(set(kp)) or kp != sorted(kp, key=u8):
                fails_kp.append(f'{where} keyPaths not valid, sorted and unique')
            for k in kp:
                if k not in allowed: fails_kp.append(f'{where} key path {k} not in the allowed list')
            if not kp: fails_kp.append(f'{where} no key paths')
            if r['arrayCounts'] is None: fails_ct.append(f'{where} arrayCounts null')
            if r['userContentArrayCounts'] is None: fails_ct.append(f'{where} userContentArrayCounts null')
            ac = shape(r['arrayCounts'], where, 'arrayCounts')
            uc = shape(r['userContentArrayCounts'], where, 'userContentArrayCounts')
            if ac is not None: compare(where, 'arrayCounts', ac, golden)
            if uc is not None:
                if set(uc) != {'$.existingTasks', '$.rooms'}:
                    fails_ct.append(f'{where} userContentArrayCounts paths {sorted(uc, key=u8)}, expected exactly $.existingTasks and $.rooms')
                if '$.rooms' in uc and uc['$.rooms'] != rooms_expected:
                    fails_ct.append(f"{where} userContentArrayCounts $.rooms: expected {rooms_expected}, seen {uc['$.rooms']}")
                if '$.existingTasks' in uc and uc['$.existingTasks'] > 10:
                    fails_ct.append(f"{where} userContentArrayCounts $.existingTasks: expected <= 10, seen {uc['$.existingTasks']}")
    if nreq == 0: fails_other.append('no cloud request in the file')
    for f in fails_other + fails_kp + fails_ct: print('  CLOUD FAIL', f)
    v = lambda l: 'PASS' if not l else f'FAIL ({len(l)})'
    print(f'CLOUD requests checked {nreq} in {len(res["inputs"])} attempts')
    print(f'CLOUD route and request records: {v(fails_other)}')
    print(f'CLOUD key paths subset of the allowed list: {v(fails_kp)}')
    print(f'CLOUD element counts match the golden body and the seeded household: {v(fails_ct)}')
    sys.exit(1 if fails_other or fails_kp or fails_ct else 0)
