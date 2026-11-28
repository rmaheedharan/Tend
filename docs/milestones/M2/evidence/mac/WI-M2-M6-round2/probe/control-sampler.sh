#!/bin/zsh
# Sampler sensitivity control (R50-F5): a planted copy of the script that puts the key in one process's arguments
# for 0.3 s; the same whole-run sampler must see it. Fake key, local server only.
S=$1; REPO=$2; cd $REPO
FAKE='FAKE-TEST-KEY-not-a-real-key-0000'
sed 's|^leak=no$|leak=no; sh -c "sleep 0.3; :" planted-"$key"|' Tools/Recording/record-provider-stream.sh > $S/planted.sh
grep -c 'planted-' $S/planted.sh
python3 $S/server.py 18770 $S/requests.jsonl & SRV=$!
sleep 1
: > $S/ps-ctl.txt; touch $S/sampling; ( while [ -f $S/sampling ]; do ps -ax -o args= >> $S/ps-ctl.txt; sleep 0.02; done ) & SAMPLER=$!
printf '%s\n' "$FAKE" | TEND_REC_BASE=http://127.0.0.1:18770 zsh $S/planted.sh openai $S/out-ctl > /dev/null 2>&1
rm -f $S/sampling; wait $SAMPLER; kill $SRV; wait $SRV 2>/dev/null
echo "control: planted argv exposure seen by the sampler in $(grep -F -c -- "planted-$FAKE" $S/ps-ctl.txt) sample(s) (must be > 0)"
