# `+[NSColorPanel sharedColorPanel]` lazy-init race

Apple Feedback: not yet filed.

## What this tests

`+[NSColorPanel sharedColorPanel]` creates its panel lazily. It loads the cached pointer, then `objc_alloc`s and stores if the slot is null, then inits and stores again, with no lock and no `dispatch_once` held at any point. The whole function is 17 instructions and the audit inspected all of them (disassembly window at `AppKit.md` lines 22-29). Two threads making the first call at once can both observe the null slot, both allocate and initialize their own panel, and both store, with the last store winning the slot and the two callers holding different objects despite the documented single-instance contract.

This is one of 10 singleton-shape findings from the objc2 safety-audit session being ported to runnable harnesses. Sources, both under `~/github/objc2.upstreams/safety-audit/plans/safety-audit/`, are `MASTER-ACTIONS.md`'s direction 1 table, row 3, and the method-level disassembly in `AppKit.md` lines 17-19. Unlike the DeviceCheck `appAttestController` finding, this slot takes its unguarded slow path only once per process, so each process is exactly one trial and the harness re-runs as fresh child processes rather than looping rounds inside one process.

One platform note on what the cold trial actually hits. `NSPanel`'s `init` runs `NSWindow`'s main-thread instantiation check, so a first caller on a worker thread aborts the process with an uncaught `NSInternalInconsistencyException` inside the unguarded slow path. The abort fires without concurrency at all, verified with a single background-thread first call, because the slow path cannot complete off the main thread. The audit's divergence outcome, both callers completing with different panels, needs the slow path to complete on a worker thread and does not happen on this platform. The abort is the observable fault here.

The audit's own probe (`AppKit.md` line 11) had not called this method, flagging it as untested on the assumption that creating an `NSPanel` needs a WindowServer session and the probe ran headless over SSH. That caveat is empirically disproven on this Mac. Today's verification ran the cold trial 100 times over SSH with no WindowServer session, and no WindowServer-related failure appeared. The only failure observed is the main-thread instantiation check above, which is unrelated to a WindowServer session.

## Running it

```sh
clang -O2 -fobjc-arc -framework Foundation -framework AppKit repro.m -o repro
./repro cold    # 8 threads race this process's very first sharedColorPanel call
./repro warm    # same race after one uncontested pre-call populated the slot
```

`run.sh` builds once, retries the `cold` trial as a fresh child process up to 50 times, stopping at the first nonzero exit, then runs `warm` once.

## Reading a result

A `cold` trial exits `1` when two racing first-callers got different panels, `0` when all 8 agree. On this platform it in fact exits `134` (`SIGABRT`) from the `NSWindow` main-thread check, with the full exception and stack preserved in the result's `raw_output`. The measured single-trial hit rate on this Mac today was 100/100, so the cold trial aborts on its first fresh-process attempt and `run.sh` stops at the first nonzero exit, well inside its 50-trial bound. `warm` pre-calls the getter single-threaded first, so the racing threads only hit the cached fast path and must always agree. A divergence there means the harness itself is broken, not the framework.

## Platforms

Verified headless over SSH on the macOS 26.6.2 (25G83) Apple silicon host with Xcode 27, and reproduced the same way inside a tart VM running the same build. Not yet tried on iOS.

## Results

See `results/`. One file per platform and exact OS build, at `fault` strength.
