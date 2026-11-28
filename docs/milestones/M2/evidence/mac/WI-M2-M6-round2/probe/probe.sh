#!/bin/zsh
# R50-F2 and R50-F5 probe: the recording script in zsh and bash with a fake key against a local server only.
S=$1; REPO=$2; cd $REPO
FAKE='FAKE-TEST-KEY-not-a-real-key-0000'
SCRIPT=Tools/Recording/record-provider-stream.sh
python3 $S/server.py 18765 $S/requests.jsonl & SRV=$!
sleep 1
pass=0; fail=0
# Samples every process's arguments (ps -ax -o args=) about every 20 ms while a script runs (review R50-F5).
sample_start() { : > $S/ps-all.txt; touch $S/sampling; ( while [ -f $S/sampling ]; do ps -ax -o args= >> $S/ps-all.txt; sleep 0.02; done ) & SAMPLER=$!; }
sample_stop() { rm -f $S/sampling; wait $SAMPLER; }
samples() { grep -c '^ *PID\|^/sbin/launchd' $S/ps-all.txt; }
check() { if eval "$2"; then echo "PASS $1"; pass=$((pass+1)); else echo "FAIL $1"; fail=$((fail+1)); fi }
for sh in zsh bash; do
  for p in openai anthropic gemini; do
    rm -rf $S/out; : > $S/requests.jsonl
    ( sleep 0.7; ps -ax -o args= > $S/ps.txt ) & PS=$!
    sample_start
    printf '%s\n' "$FAKE" | TEND_REC_BASE=http://127.0.0.1:18765 $sh $SCRIPT $p $S/out > $S/run.txt 2>&1; rc=$?
    sample_stop
    wait $PS
    case $p in openai) hdr="Authorization: Bearer $FAKE";; anthropic) hdr="x-api-key: $FAKE";; gemini) hdr="x-goog-api-key: $FAKE";; esac
    want=$(shasum -a 256 Fixtures/M2/payload/golden/g1-outcome-empty-$p.body.json | cut -c1-64)
    check "$sh $p exit 0" "[ $rc -eq 0 ]"
    check "$sh $p status 200 printed" "grep -q 'HTTP status: 200' $S/run.txt"
    check "$sh $p one request" "[ \$(wc -l < $S/requests.jsonl) -eq 1 ]"
    check "$sh $p auth header exact" "python3 -c 'import json,sys; r=json.loads(open(\"$S/requests.jsonl\").readline()); h=[k+\": \"+v for k,v in r[\"headers\"]]; sys.exit(0 if \"$hdr\" in h else 1)'"
    check "$sh $p golden headers sent" "python3 -c 'import json,sys; r=json.loads(open(\"$S/requests.jsonl\").readline()); h=[k.lower()+\": \"+v for k,v in r[\"headers\"]]; want=[l.split(\": \",1)[0].lower()+\": \"+l.split(\": \",1)[1] for l in open(\"Fixtures/M2/payload/golden/g1-outcome-empty-$p.head.txt\").read().splitlines()[1:]]; sys.exit(0 if all(w in h for w in want) else 1)'"
    check "$sh $p body is the golden body" "grep -q $want $S/requests.jsonl"
    check "$sh $p path and query" "python3 -c 'import json,sys; r=json.loads(open(\"$S/requests.jsonl\").readline()); sys.exit(0 if r[\"path\"]==open(\"Fixtures/M2/payload/golden/g1-outcome-empty-$p.head.txt\").readline().split()[2] else 1)'"
    check "$sh $p curl was running when ps sampled" "grep -q '^curl ' $S/ps.txt"
    check "$sh $p key not in any process argv (curl sample)" "! grep -F -q -- $FAKE $S/ps.txt"
    check "$sh $p whole run sampled (>= 20 ps samples)" "[ \$(grep -c '^/sbin/launchd' $S/ps-all.txt) -ge 20 ]"
    check "$sh $p key in no process argv during the whole run" "! grep -F -q -- $FAKE $S/ps-all.txt"
    check "$sh $p key not on screen" "! grep -F -q -- $FAKE $S/run.txt"
    check "$sh $p only the stream saved" "[ \"\$(ls $S/out)\" = $p.sse ]"
    check "$sh $p key not in saved files" "! grep -r -F -q -- $FAKE $S/out"
  done
  # Empty key: nothing sent.
  rm -rf $S/out; : > $S/requests.jsonl
  printf '\n' | TEND_REC_BASE=http://127.0.0.1:18765 $sh $SCRIPT openai $S/out > $S/run.txt 2>&1; rc=$?
  check "$sh empty key exits 1" "[ $rc -eq 1 ]"
  check "$sh empty key says so" "grep -q 'no key read; nothing was sent' $S/run.txt"
  check "$sh empty key sends nothing" "[ ! -s $S/requests.jsonl ] && [ ! -e $S/out ]"
  # No input at all (EOF): nothing sent.
  : > $S/requests.jsonl
  TEND_REC_BASE=http://127.0.0.1:18765 $sh $SCRIPT anthropic $S/out < /dev/null > $S/run.txt 2>&1; rc=$?
  check "$sh no input exits 1, sends nothing" "[ $rc -eq 1 ] && [ ! -s $S/requests.jsonl ]"
  # Invalid endpoint (nothing listens on port 1).
  rm -rf $S/out
  printf '%s\n' "$FAKE" | TEND_REC_BASE=http://127.0.0.1:1 $sh $SCRIPT gemini $S/out > $S/run.txt 2>&1; rc=$?
  check "$sh invalid endpoint exits non-zero (curl 7)" "[ $rc -eq 7 ]"
  check "$sh invalid endpoint, key not on screen" "! grep -F -q -- $FAKE $S/run.txt"
  # Unknown provider.
  $sh $SCRIPT other > $S/run.txt 2>&1; rc=$?
  check "$sh unknown provider is a usage error" "[ $rc -eq 64 ]"
done
kill $SRV; wait $SRV 2>/dev/null
# A response that echoes the key: the stream is deleted.
ECHO_KEY=1 python3 $S/server.py 18766 $S/requests.jsonl & SRV=$!
sleep 1
for sh in zsh bash; do
  rm -rf $S/out
  sample_start
  printf '%s\n' "$FAKE" | TEND_REC_BASE=http://127.0.0.1:18766 $sh $SCRIPT anthropic $S/out > $S/run.txt 2>&1; rc=$?
  sample_stop
  check "$sh echoed key: key in no process argv during the run (leak check included)" "! grep -F -q -- $FAKE $S/ps-all.txt"
  check "$sh echoed key: exit 1 and stream deleted" "[ $rc -eq 1 ] && [ ! -e $S/out/anthropic.sse ]"
  check "$sh echoed key: not on screen" "! grep -F -q -- $FAKE $S/run.txt"
done
kill $SRV; wait $SRV 2>/dev/null
# Keys with glob characters (R50-F5): the leak check matches the key literally.
GLOBKEY='FAKE-*-KEY?[ab]'
ECHO_TEXT='FAKE-xyz-KEYa' python3 $S/server.py 18768 $S/requests.jsonl & SRV=$!
sleep 1
for sh in zsh bash; do
  rm -rf $S/out
  sample_start
  printf '%s\n' "$GLOBKEY" | TEND_REC_BASE=http://127.0.0.1:18768 $sh $SCRIPT anthropic $S/out > $S/run.txt 2>&1; rc=$?
  sample_stop
  check "$sh glob key, stream holds only a glob match: not a leak, kept" "[ $rc -eq 0 ] && [ -s $S/out/anthropic.sse ]"
  check "$sh glob key in no process argv during the run" "! grep -F -q -- '$GLOBKEY' $S/ps-all.txt"
done
kill $SRV; wait $SRV 2>/dev/null
ECHO_KEY=1 python3 $S/server.py 18769 $S/requests.jsonl & SRV=$!
sleep 1
for sh in zsh bash; do
  rm -rf $S/out
  sample_start
  printf '%s\n' "$GLOBKEY" | TEND_REC_BASE=http://127.0.0.1:18769 $sh $SCRIPT anthropic $S/out > $S/run.txt 2>&1; rc=$?
  sample_stop
  check "$sh glob key echoed literally: exit 1 and stream deleted" "[ $rc -eq 1 ] && [ ! -e $S/out/anthropic.sse ]"
  check "$sh glob key echoed: in no process argv" "! grep -F -q -- '$GLOBKEY' $S/ps-all.txt"
done
kill $SRV; wait $SRV 2>/dev/null
echo "probe: $pass passed, $fail not passed"
