# Self-test inputs for the DS-2 S6 cloud checks of independent-rescore.py (review-pr53 i1; AC-M2-26, D-059).
# Builds a good DS-2 Part C-like results file (gemini) and mutated bad ones. Counts come from hand-written values and
# the Developer test's literal oracle list (data only), not from the script under test.
import json, re, copy, sys
repo = sys.argv[1]; out = sys.argv[2]
base = json.load(open(f'{repo}/Fixtures/M2/eval-selftest/results-selftest-1.canonical.json'))
allowed = sorted({k['path'] for k in json.load(open(f'{repo}/Fixtures/M2/payload/allowed-key-paths-gemini.json'))['keyPaths']},
                 key=lambda t: t.encode())
swift = open(f'{repo}/Packages/TendIngestion/Tests/TendIngestionTests/GoldenArrayCountsTests.swift').read()
gem = swift[swift.index('.gemini: ['):swift.index('],', swift.index('.gemini: ['))]
oracle = [{'count': int(c), 'path': p} for p, c in re.findall(r'\("(\$[^"]*)", (\d+)\)', gem)]
assert len(oracle) == 22, len(oracle)
uc = [{'count': 10, 'path': '$.existingTasks'}, {'count': 9, 'path': '$.rooms'}]
def req(n): return {'arrayCounts': copy.deepcopy(oracle), 'attempt': n, 'bytes': 9000, 'keyPaths': list(allowed),
                    'userContentArrayCounts': copy.deepcopy(uc)}
good = copy.deepcopy(base)
for a in good['inputs']:
    a['route'] = 'gemini'; a['cloudRequests'] = [req(1)]
good['inputs'][0]['cloudRequests'].append(req(2))   # a transport retry: two requests in one capture
json.dump(good, open(f'{out}/good-gemini.json', 'w'))
print('attempts (gemini good file)', [(a['inputID'], a['attempt'], len(a['cloudRequests'])) for a in good['inputs']])
def mut(name, f):
    m = copy.deepcopy(good); f(m); json.dump(m, open(f'{out}/bad-{name}.json', 'w'))
I = lambda m, iid, att: next(a for a in m['inputs'] if a['inputID'] == iid and a['attempt'] == att)
mut('keypath-not-allowed', lambda m: (m['inputs'][3]['cloudRequests'][0]['keyPaths'].append('$.zzz'), None))
mut('arraycounts-null', lambda m: m['inputs'][3]['cloudRequests'][0].__setitem__('arrayCounts', None))
mut('usercontent-null', lambda m: m['inputs'][3]['cloudRequests'][0].__setitem__('userContentArrayCounts', None))
def off(m): m['inputs'][3]['cloudRequests'][0]['arrayCounts'][6]['count'] += 1
mut('arraycount-off-by-one', off)
mut('arraycount-missing-entry', lambda m: m['inputs'][3]['cloudRequests'][0]['arrayCounts'].pop(5))
def extra(m):
    l = m['inputs'][3]['cloudRequests'][0]['arrayCounts']; l.append({'count': 1, 'path': '$.tools'})
    l.sort(key=lambda e: e['path'].encode())
mut('arraycount-extra-entry', extra)
mut('rooms-8', lambda m: m['inputs'][3]['cloudRequests'][0]['userContentArrayCounts'][1].__setitem__('count', 8))
mut('existingtasks-11', lambda m: m['inputs'][3]['cloudRequests'][0]['userContentArrayCounts'][0].__setitem__('count', 11))
mut('usercontent-extra-path', lambda m: m['inputs'][3]['cloudRequests'][0]['userContentArrayCounts'].append({'count': 1, 'path': '$.zpeople'}))
mut('usercontent-missing-rooms', lambda m: m['inputs'][3]['cloudRequests'][0]['userContentArrayCounts'].pop(1))
mut('not-sorted', lambda m: m['inputs'][3]['cloudRequests'][0]['arrayCounts'].reverse())
def dup(m): l = m['inputs'][3]['cloudRequests'][0]['arrayCounts']; l.insert(1, dict(l[0]))
mut('duplicate-entry', dup)
mut('bad-path-pattern', lambda m: m['inputs'][3]['cloudRequests'][0]['arrayCounts'][0].__setitem__('path', '$.contents[01]'))
mut('negative-count', lambda m: m['inputs'][3]['cloudRequests'][0]['arrayCounts'][0].__setitem__('count', -1))
mut('bool-count', lambda m: m['inputs'][3]['cloudRequests'][0]['arrayCounts'][0].__setitem__('count', True))
mut('entry-extra-member', lambda m: m['inputs'][3]['cloudRequests'][0]['arrayCounts'][0].__setitem__('value', 'x'))
mut('member-left-out', lambda m: m['inputs'][3]['cloudRequests'][0].pop('userContentArrayCounts'))
mut('bad-only-in-retake', lambda m: I(m, 'in02', 1)['cloudRequests'][0]['userContentArrayCounts'][1].__setitem__('count', 7))
mut('bad-only-in-2nd-request', lambda m: m['inputs'][0]['cloudRequests'][1]['keyPaths'].append('$.contents[].parts[].inlineData'))
mut('route-other-provider', lambda m: m['inputs'][5].__setitem__('route', 'openai'))
mut('no-request-recorded', lambda m: m['inputs'][5].__setitem__('cloudRequests', []))
mut('request-attempts-not-sequential', lambda m: m['inputs'][0]['cloudRequests'][1].__setitem__('attempt', 3))
def nocloud(m):
    for a in m['inputs']: a['cloudRequests'] = []; a['route'] = 'onDevice'
mut('no-cloud-at-all', nocloud)
# Good files for the other two providers, with that provider's allowed list and the oracle list as arrayCounts.
for prov, tag in (('openai', '.openAI'), ('anthropic', '.anthropic')):
    blk = swift[swift.index(tag + ': ['):swift.index('],', swift.index(tag + ': ['))]
    orc = [{'count': int(c), 'path': p} for p, c in re.findall(r'\("(\$[^"]*)", (\d+)\)', blk)]
    al = sorted({k['path'] for k in json.load(open(f'{repo}/Fixtures/M2/payload/allowed-key-paths-{prov}.json'))['keyPaths']},
                key=lambda t: t.encode())
    g = copy.deepcopy(base)
    for a in g['inputs']:
        a['route'] = prov
        a['cloudRequests'] = [{'arrayCounts': copy.deepcopy(orc), 'attempt': 1, 'bytes': 9000, 'keyPaths': list(al),
                               'userContentArrayCounts': copy.deepcopy(uc)}]
    json.dump(g, open(f'{out}/good-{prov}.json', 'w'))
