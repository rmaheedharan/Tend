#!/bin/zsh
# R50-F2 probe on a real terminal (pty via script(1)): the typed key is hidden and never reaches shell history.
S=$1; REPO=$2; cd $REPO
FAKE='FAKE-TEST-KEY-not-a-real-key-0000'
python3 $S/server.py 18767 $S/requests.jsonl & SRV=$!
sleep 1
pass=0; fail=0
check() { if eval "$2"; then echo "PASS $1"; pass=$((pass+1)); else echo "FAIL $1"; fail=$((fail+1)); fi }
for sh in zsh bash; do
  rm -rf $S/out $S/hist; : > $S/requests.jsonl; : > $S/tty.txt
  if [ $sh = zsh ]; then start="zsh -f -i"; histset="HISTFILE=$S/hist; SAVEHIST=100; HISTSIZE=100; setopt INC_APPEND_HISTORY"
  else start="bash --norc -i"; histset="HISTFILE=$S/hist; HISTSIZE=100; HISTFILESIZE=100; set -o history"; fi
  ( print -r -- "$histset"; sleep 1
    print -r -- "TEND_REC_BASE=http://127.0.0.1:18767 $sh Tools/Recording/record-provider-stream.sh anthropic $S/out"; sleep 2
    print -r -- "$FAKE"; sleep 4
    print -r -- "history -w 2>/dev/null; exit"; sleep 1 ) | script -q $S/tty.txt ${=start} > /dev/null 2>&1
  check "$sh pty: prompt shown" "grep -q 'Anthropic key (hidden)' $S/tty.txt"
  check "$sh pty: request sent with the typed key" "grep -F -q -- \"$FAKE\" $S/requests.jsonl"
  check "$sh pty: stream saved" "[ -s $S/out/anthropic.sse ]"
  check "$sh pty: typed key not echoed on the terminal" "! grep -F -q -- $FAKE $S/tty.txt"
  check "$sh pty: history file written" "[ -s $S/hist ]"
  check "$sh pty: key not in shell history" "! grep -F -q -- $FAKE $S/hist"
  check "$sh pty: terminal echo restored after" "grep -q 'history -w' $S/tty.txt"
done
kill $SRV; wait $SRV 2>/dev/null
echo "tty probe: $pass passed, $fail not passed"
