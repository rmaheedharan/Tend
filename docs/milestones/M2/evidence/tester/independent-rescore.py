# Independent re-score (Acceptance Tester, AC-M2-14). Written from the brief's "Eval scoring rules", "Keywords of a
# text", "Name folding", "Banned tokens" and the M1 invariants only. Does not read or call the TendIngestion scorer.
import json, sys, unicodedata, re, math
from datetime import datetime
d = sys.argv[1]; res = json.load(open(sys.argv[2]))
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
