# `-[SCContentSharingPicker defaultConfiguration]` lazy-init race

Apple Feedback: not yet filed.

## What this tests

`-[SCContentSharingPicker defaultConfiguration]` creates its configuration lazily. The getter loads the ivar and returns a copy of it if it is already set, and on the first call it creates the configuration, reloads the ivar, stores it, and releases the old value, with no lock and no `dispatch_once` (disassembly, safety-audit `ScreenCaptureKit.md` lines 15-19). `+[SCContentSharingPicker sharedPicker]` is `dispatch_once`-guarded and confirmed safe by the audit (`ScreenCaptureKit.md` line 54).

The harness calls `sharedPicker` once, single-threaded, outside the race, and races 8 threads' first `defaultConfiguration` calls on that one process-wide picker instance. Two threads making the first call at once each create a configuration, and each returns its own object, so two callers of a getter implemented as a single shared instance get different objects. That divergence is the visible defect the harness exits 1 on.

This is one of 10 singleton-shape findings from the objc2 safety-audit session (`MASTER-ACTIONS.md` direction 1 table, row 16, both documents under `~/github/objc2.upstreams/safety-audit/plans/safety-audit/`) being ported to runnable harnesses.

The setter races on `defaultConfiguration` and `maximumStreamCount` (unlocked ARC strong-store, racing writers can double-release the old value) found in the same audit are explicitly out of scope for this task. Only the getter's lazy-init race is covered here. The setters are later, separate work.

## The cached generation invalidates under concurrent use

On this build the cached value is not stable for the whole process. The cached generation is invalidated whenever the cached object still has an external reference at the next call. Measured single-threaded, back-to-back and 10-second-spaced calls return the same pointer while each result is not kept across the next call, and keeping the result alive makes the very next call return a fresh object (18/18 runs, 10-800 ms gaps).

Concurrent calls diverge even when no thread keeps its result, 8 threads against an already-cached value 18/20 and 2 threads 20/20. The same 8 threads calling in strict turn without keeping results always agree. The cold trial therefore keeps its results, as real callers do, and the warm control captures the pointers without keeping the objects and calls in strict turn through an atomic turn counter.

## Running it

```sh
clang -O2 -fobjc-arc -framework Foundation -framework ScreenCaptureKit repro.m -o repro
./repro cold   # one trial per process; 8 threads race the first call, each keeping its result
./repro warm    # control; the getter is pre-called once, then the 8 threads call in strict turn
```

## Reading a result

The target's slow path runs once per process, so one invocation of `repro` is one trial. `cold` exits 1 if any of the 8 threads got a different pointer than the first, and 0 if all agree. `warm` exercises the same threads, barrier, capture, and comparison against a stable cached value, so it must always agree, and a nonzero exit there means the harness is broken, not the framework.

`run.sh` retries `cold` as a fresh child process up to 50 times, stopping at the first fault, then runs `warm` once. The result is recorded via `scripts/make-crash-result.sh` at `fault` strength (see `EVIDENCE.md`).

## Platforms

Plain macOS (not Catalyst), Apple silicon, macOS 26.6.2 (25G83), Xcode 27.0. Verified on the real Mac host, where the cold trial diverged 100/100 on 2026-10-13. This harness reproduced it 10/10 with the warm control agreeing 30/30.

## Results

See `results/`. One file per platform and exact OS build, at `fault` strength.
