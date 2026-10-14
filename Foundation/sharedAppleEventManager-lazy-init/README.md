# `+[NSAppleEventManager sharedAppleEventManager]` lazy-init race

Apple Feedback: FB25188007 (filed, open as of 2026-10-14, Apple has not replied).

## What this tests

`+[NSAppleEventManager sharedAppleEventManager]` is a process-wide one-shot lazy singleton: it loads a static slot, branches if non-null, and otherwise does `objc_allocWithZone` + `init` and an unconditional store back to the slot, with no `os_unfair_lock`, no `dispatch_once`, and no lock message anywhere in the function. Two threads making the very first call of a process at once can both observe the null slot, both allocate and initialize their own instance, and both store, with the loser's instance leaked and the two callers holding different objects despite the documented single-instance contract. `NSScriptCommand.currentCommand` goes through this getter first and inherits this race, not an independent finding.

This is one of 10 singleton-shape findings from the objc2 safety-audit session being ported to runnable harnesses. Source: `MASTER-ACTIONS.md`'s Direction 1 table (row 1), plus `Foundation.md` lines 15–27 for the disassembly of this method, both under `~/github/objc2.upstreams/safety-audit/plans/safety-audit/`.

The race window lives only until the first store, so each process gives exactly one trial: `repro.m` takes one `cold` or `warm` argument and races once, and `run.sh` retries `cold` as fresh child processes up to 50 times. Measured hit rate on this build today: effectively 100% (3000/3000 fresh-process trials diverged).

## Running it

```sh
clang -O2 -fobjc-arc -framework Foundation repro.m -o repro
./repro cold    # 8 threads make the process's first call simultaneously; exit 1 if any got a different pointer
./repro warm    # control: getter pre-called once single-threaded before the race
sh run.sh macos-host-apple-silicon 27.0    # assembles output.txt and writes results/
```

## Reading a result

The cold run is expected to exit 1: two (or more) of the 8 racing first-callers got different pointers out of a getter documented and implemented as one shared instance. A wrong object is the actual externally visible defect, so the record is `fault` strength per `EVIDENCE.md`. The harness prints which threads diverged and the pointers. The `output.txt` line is `race cold rounds=<attempts-used> exit=<E>`; at the measured hit rate the first fresh process diverges in practice.

The warm control pre-calls the getter single-threaded, so all 8 racing threads take only the cached fast path and must always agree; a divergence there (which would exit 1) means the harness itself is broken, not the framework.

The verdict in the JSON is `reproduced` when the cold run exits nonzero, `not-reproduced` if all 50 fresh processes agreed.

## Platforms

Measured on macOS 26.6.2, build 25G83, Apple silicon, both directly on the host and inside a tart VM. The disassembly in the audit is from the same build. Not tried on iOS or other OS builds.

## Results

See `results/`. One file per platform and exact OS build, at `fault` strength.
