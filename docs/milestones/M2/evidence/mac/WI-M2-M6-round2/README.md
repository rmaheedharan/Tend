# Probe record — WI-M2-M6 round 2 (PR #50 review round 2, R50-F5)

A script and docs change only: `Tools/Recording/record-provider-stream.sh`'s leak check no longer runs `grep` with
the key as an argument. No Swift code changed, so no new B0–B6 run was made; the last one is
[`../WI-M2-M6-round1/`](../WI-M2-M6-round1/README.md) at `990fffc`.

Run by the Developer agent (Claude) on the owner's Mac (zsh 5.9 and macOS bash), with a fake key
(`FAKE-TEST-KEY-not-a-real-key-0000`, and the glob-character key `FAKE-*-KEY?[ab]`) against local test servers
(`server.py`, 127.0.0.1) and an invalid endpoint. No real key and no network call.

- [`probe/probe.sh`](probe/probe.sh): the round-1 probe plus a sampler that records every process's arguments
  (`ps -ax -o args=`, about every 20 ms) for the whole of each script run, and checks the key is in none of them
  (including the run where the response echoes the key, so the leak check itself runs). New glob-key cases: a stream
  holding only a glob match of the key is kept (not a leak); a stream holding the key literally is deleted. Result:
  [`probe/probe.log`](probe/probe.log), 112 passed, 0 not passed.
- [`probe/control-sampler.sh`](probe/control-sampler.sh): sampler sensitivity control. A planted copy of the script
  puts the key in one process's arguments for 0.3 s, and the same sampler sees it
  ([`probe/control-sampler.log`](probe/control-sampler.log): 5 samples). A sampler cannot prove a shorter exposure is
  absent; the guarantee is by construction (the key is passed only to shell builtins: `read`, `printf`, `[`, `case`),
  and the probe checks it.

```text
    978071db529119862deb65a17de85278a7cee585f285dbd7458b8486d7fe2d67  probe/control-sampler.log
    66b9b74353f3fdfa138bae7bf01f14c18837bb230593d94108886d2a18308a5c  probe/control-sampler.sh
    474d0120d439fed51fd84868ea009050aec567c9c1baba0f8f036457f6fe4cc1  probe/probe.log
    4be1f3471ca1ac39f64116ed8f45a52e715244cba4e5ad6e2e9cb13479280a8c  probe/probe.sh
    015b623d61eecc617ea287d025a13bb0a40de1057b242949001e17b20d72ba61  probe/server.py
```
