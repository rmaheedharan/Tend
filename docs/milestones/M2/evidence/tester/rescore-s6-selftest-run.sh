#!/bin/bash
# Self-test of the DS-2 S6 cloud checks in independent-rescore.py (review-pr53 i1; AC-M2-26, D-059).
# Run from the repo root: python3 -I docs/milestones/M2/evidence/tester/rescore-s6-selftest-build.py . <samples>; then
# bash docs/milestones/M2/evidence/tester/rescore-s6-selftest-run.sh <samples>  (<samples>: an empty scratch folder).
# Paths in the log are repo-relative or sample file names.
SAMPLES="$1"; SCRIPT=docs/milestones/M2/evidence/tester/independent-rescore.py
G=Fixtures/M2/payload; pass=0; fail=0
echo "== independent-rescore.py self-test (S6 cloud checks), $(date -u +%Y-%m-%dT%H:%MZ)"
echo "commit under test: $(git rev-parse HEAD) + working-tree changes to the script"
echo "script SHA-256: $(sha256sum $SCRIPT | cut -d' ' -f1)"
echo "python: $(python3 --version)"
run() { # name provider expected-exit [allowed golden]
  local name=$1 p=$2 want=$3 al=${4:-$G/allowed-key-paths-$2.json} gb=${5:-$G/golden/g1-outcome-empty-$2.body.json}
  out=$(python3 -I $SCRIPT Fixtures/M2/eval "$SAMPLES/$name.json" --provider $p --allowed-key-paths $al --golden-body $gb 2>&1)
  got=$?
  if [ $got -eq $want ]; then r=OK; pass=$((pass+1)); else r=WRONG; fail=$((fail+1)); fi
  echo; echo "-- case $name: expected exit $want, got $got: $r"
  echo "$out" | grep '^ *CLOUD' | sed "s#$SAMPLES/##g"
}
run good-gemini gemini 0
run good-openai openai 0
run good-anthropic anthropic 0
for f in "$SAMPLES"/bad-*.json; do run "$(basename $f .json)" gemini 1; done
run good-gemini openai 2 $G/allowed-key-paths-openai.json $G/golden/g1-outcome-empty-gemini.body.json
echo "   (above: provider arguments that do not match each other are refused)"
echo; echo "-- extra (not an exit-code case): a second, throw-away array walk over each G1/G2/G3 golden body vs the Developer test's literal oracle lists (data only)"
python3 -I - <<'PY'
import json, re
swift = open('Packages/TendIngestion/Tests/TendIngestionTests/GoldenArrayCountsTests.swift').read()
def walk(v, p='$', o=None):
    o = {} if o is None else o
    if isinstance(v, list):
        o[p] = len(v); [walk(x, f'{p}[{i}]', o) for i, x in enumerate(v)]
    elif isinstance(v, dict):
        [walk(x, f'{p}.{k}', o) for k, x in v.items()]
    return o
ok = True
for prov, tag in (('openai', '.openAI'), ('anthropic', '.anthropic'), ('gemini', '.gemini')):
    blk = swift[swift.index(tag + ': ['):swift.index('],', swift.index(tag + ': ['))]
    oracle = {p: int(c) for p, c in re.findall(r'\("(\$[^"]*)", (\d+)\)', blk)}
    for g in ('g1-outcome-empty', 'g2-typical', 'g3-edge'):
        mine = walk(json.load(open(f'Fixtures/M2/payload/golden/{g}-{prov}.body.json')))
        same = mine == oracle; ok &= same
        print(f'   {g}-{prov}: {len(mine)} arrays, equal to oracle: {same}')
print('   all nine equal:', 'yes' if ok else 'NO')
PY
echo; echo "-- case old-use-unchanged: no options, selftest-1 output equals the committed rescore-selftest-1.out"
if python3 -I $SCRIPT Fixtures/M2/eval-selftest Fixtures/M2/eval-selftest/results-selftest-1.canonical.json | diff -q - docs/milestones/M2/evidence/tester/rescore-selftest-1.out >/dev/null; then echo "   identical: OK"; pass=$((pass+1)); else echo "   differs: WRONG"; fail=$((fail+1)); fi
echo; echo "== exit-code cases: $pass as expected, $fail not as expected"
