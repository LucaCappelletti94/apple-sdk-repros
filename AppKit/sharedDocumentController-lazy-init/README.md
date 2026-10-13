# `+[NSDocumentController sharedDocumentController]` lazy-init race

Apple Feedback: not yet filed.

## What this tests

`+[NSDocumentController sharedDocumentController]` populates a process-wide static slot lazily. It loads the slot, branches on the null value, calls `objc_opt_new`, stores unconditionally, and re-reads the old value only to `objc_release` it, with no lock and no `dispatch_once`. Two threads making the first call at once can both pass the null check, both allocate, and each return its own instance, violating the documented contract that the first instance allocated and initialized during application launch is the shared document controller.

This is one of 10 singleton-shape findings from the objc2 safety audit being ported to runnable harnesses. Source: `MASTER-ACTIONS.md`, Direction 1 table, row 4, and `AppKit.md` lines 32-45, both under `plans/safety-audit/` in the `objc2.upstreams/safety-audit` worktree.

## Running it

```sh
clang -O2 -fobjc-arc -framework Foundation -framework AppKit repro.m -o repro
./repro cold   # 8 threads make the first call in this process at the same moment
./repro warm   # control: the main thread calls the getter alone first, then the 8 race
```

One trial per process invocation. `run.sh` retries the cold trial as fresh child processes up to 50 times, stopping at the first divergence.

## Reading a result

A diverged cold run is the externally visible defect at `fault` strength (see `EVIDENCE.md`). Two callers got different objects from what is documented as a single shared instance, and `./repro cold` prints how many of the 8 first-callers disagreed and exits 1. Each process gives the getter exactly one first call, so the retry is across fresh processes, not rounds inside one harness.

The warm control pre-calls the getter on the main thread, so the 8 racers only hit the cached read and must always agree. A divergence there means the harness itself is broken.

## Measured hit rate

Measured on this host: 83 of 100 single-trial cold runs diverged. The verification run that produced `results/` diverged on its first attempt, and 11 of a further 20 fresh trials diverged, lower than 83 of 100 with the 9 sibling audit harnesses running concurrently on the same machine. The 50-attempt bound in `run.sh` covers both rates with a large margin.

## Platforms

Reproduced on the host, Apple silicon macOS 26.6.2 (build 25G83), Xcode 27. Not yet tried in the tart VM. Not tried on iOS.

## Results

See `results/`. One file per platform and exact OS build, at `fault` strength.
