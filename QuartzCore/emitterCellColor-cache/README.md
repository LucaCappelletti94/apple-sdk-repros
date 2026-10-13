# `+[CAEmitterCell defaultValueForKey:]` lazy-init race

Apple Feedback: not yet filed.

## What this tests

`+[CAEmitterCell defaultValueForKey:]` caches each key's default value in a process-wide static slot with a plain load, a branch if already initialized, and an unconditional store, no lock and no `dispatch_once`. For the `color` key the slow path builds a `CGColor` via `CAGetColorSpace` and `CGColorCreate`, and two threads making the very first call for the key at the same moment can both observe the null slot, both build a `CGColor`, and each return the color it built rather than one shared instance. The losing thread's `CGColor` is never released either, a one-time leak on top of the divergence. The audit's prose names the slot after the `defaultColor` property, but the KVC key the getter accepts is `color`; `defaultColor` returns `nil`.

Because the slot is process-wide and one-shot, each process gives exactly one trial. The `cold` run barrier-releases 8 threads on the first-ever call and reports a fault if any two of the 8 returned pointers differ, the `warm` run pre-calls the getter once alone so the racers only hit the cached path, and `run.sh` retries the `cold` trial in fresh processes.

The finding comes from the objc2 safety-audit session's disassembly review, the `QuartzCore` `+[CAEmitterCell defaultValueForKey:]` row of the direction 1 table in `MASTER-ACTIONS.md` plus lines 30-42 of `QuartzCore.md`, both under that session's `plans/safety-audit/`. This is one of 10 singleton-shape findings from that audit being ported to runnable harnesses. Measured on the host, the `cold` trial diverged in 89 of 100 single-trial runs.

## Running it

```sh
clang -O2 -fobjc-arc -framework Foundation -framework QuartzCore -framework CoreGraphics repro.m -o repro
./repro cold    # 8 threads make the first "color" call at the same moment
./repro warm    # control: the getter runs once alone before the threads start
```

## Reading a result

`cold` exits 1 when any two of the 8 racing first-calls returned different pointers, which is a direct contract violation for what is documented and implemented as a single shared instance. `run.sh` therefore retries `cold` in fresh processes up to 50 times and stops at the first divergence, then runs `warm` once, which must always agree since every racer hits the already-populated cache. A `warm` divergence would mean the harness is broken, not the framework. `make-crash-result.sh` records the runs at `fault` strength, `reproduced` when the `cold` trial diverged.

## Platforms

The disassembly is from the macOS 26.6.2 binary. The harness has been run on macOS Apple silicon so far and not yet on iOS, where the same one-shot shape applies.

## Results

See `results/`. One file per platform and exact OS build, at `fault` strength.
