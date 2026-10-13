# `+[CAAnimation defaultValueForKey:]` lazy-cache race

Apple Feedback: not yet filed.

## What this tests

`+[CAAnimation defaultValueForKey:]` fills a process-wide static slot lazily for some keys. The slow path allocates an `NSNumber` via `initWithInt:` and stores it back unconditionally, with no lock and no `dispatch_once` (disassembly on macOS 26.6.2, build 25G83; source `plans/safety-audit/QuartzCore.md` lines 15–28 and the Direction 1 table of `plans/safety-audit/MASTER-ACTIONS.md`). Of the `CAAnimation` property names probed today, `"speed"` is the key that returns this lazily cached `NSNumber`, while `beginTime`, `duration`, `repeatCount` and the rest returned nil.

Two threads that both make the process's first call for that key concurrently can both observe the empty slot, both allocate their own `NSNumber`, and both store. All callers get value-identical results whichever allocation wins, so the externally visible consequence is a one-time leak of the losing thread's over-retained `NSNumber`, since the cached value is immutable and value-equal either way.

This is one of 10 singleton-shape findings from that audit being ported to runnable harnesses in this repository.

## Why the pointer-identity technique cannot observe this race

The 9 sibling harnesses in this batch race freshly-constructed callers and score a divergence of the returned pointers as a `fault`. That comparison is blind here. The cached value is a small integer `NSNumber`, which on this architecture is a tagged pointer, so both threads' allocations are bit-identical tagged pointers. Pointer-identity comparison therefore never diverges no matter how the alloc and store interleave. This is the same tagged-pointer blind spot the `LocalAuthentication/biometryType-domainState-cache` README documents.

## What this harness shows instead

`repro.m` swizzles `+[CAAnimation defaultValueForKey:]` itself and records each caller's `[enter, exit)` interval. 8 threads then make the process's very first `defaultValueForKey:@"speed"` calls at once, barrier-released, one shot per process because the lazy init runs only once per process. Two overlapping intervals are `dynamic-window` strength (see `EVIDENCE.md`), direct dynamic evidence that the unguarded window was entered by two threads concurrently in this process.

## Running it

```sh
clang -O2 -fobjc-arc -framework Foundation -framework QuartzCore repro.m -o repro
./repro
```

## Reading a result

Each fresh process is one trial and prints one line, `readers=8 writers=0 seconds=0 calls=8 overlaps=N`. The field names follow the shared `make-race-window-result.sh` format, all 8 threads are first callers, there is no separate writer role, and the barrier release has no time bound. `overlaps` greater than zero means two first-call intervals overlapped.

Measured today on the host, 50 of 50 fresh processes reported at least one overlap. `run.sh` records 10 fresh processes per result file.

## Platforms

Runs on macOS (26.6.2, build 25G83, Apple silicon, host). Every fresh process is one independent trial of the per-process window; no other platform changes that shape, so no other platform is recorded.

## Results

See `results/`. One file per platform and exact OS build, at `dynamic-window` strength.
