# `+[UIMenuController sharedMenuController]` lazy-init race

Apple Feedback: not worth filing. Apple declares `UIMenuController` main-thread-only, see [why](../../README.md#findings-not-filed-with-apple).

## What this tests

`+[UIMenuController sharedMenuController]` creates its process-wide singleton lazily. The getter loads a cached pointer from a static slot, branches if it is non-null, else `objc_alloc_init`, then reloads the slot and stores unconditionally. There is no lock and no `dispatch_once` anywhere in the function. The trailing `objc_release` of whatever the reload saw balances reference counts but does not close the window. Two threads taking the first call at once can each allocate an instance and each be handed a different one, breaking the documented single-instance contract for the rest of the process.

In this build the race has two externally visible signatures, and both were measured today on the host.

- Plain pointer divergence. Some of the racing first-callers are handed different instances (69 of 100 single-trial cold runs).
- An uncaught `NSInternalInconsistencyException` with the reason "There can only be one UIMenuController instance.", thrown from `-[UIMenuController init]`, which enforces the single-instance invariant itself and asserts on the losing thread of a race (27 of 100).

The two signatures are the two faces of the same unguarded slow path and are recorded as one finding. This harness counts either as a reproduction.

The disassembly evidence is in the objc2 safety-audit session's plan files (read-only reference, `~/github/objc2.upstreams/safety-audit/plans/safety-audit/`). Row 6 of the direction 1 table in `MASTER-ACTIONS.md`, the family A section of `UIKit.md` (lines 17-33, representative window for this same shape), and the `UIMenuController.sharedMenuController` row of its complete method table (line 89). This repro is one of 10 singleton-shape findings from that audit being ported to runnable harnesses.

## Running it

The class and selector are resolved through the Objective-C runtime (`NSClassFromString`, `NSSelectorFromString`, `objc_msgSend`), matching the other UIKit repros in this batch, so the harness does not depend on the header's availability annotations. Each invocation of the binary is exactly one trial, and the slot's slow path runs once per process.

```sh
clang -O2 -fobjc-arc -target arm64-apple-ios17.0-macabi \
    -isysroot <MacOSX.sdk> \
    -iframework <MacOSX.sdk>/System/iOSSupport/System/Library/Frameworks \
    -framework Foundation -framework UIKit repro.m -o repro
./repro cold    # 8 threads take this process's very first +[UIMenuController sharedMenuController] call at once
./repro warm    # control. one uncontested call fills the slot before the 8 threads race
```

## Reading a result

A `cold` run exits `1` when the 8 first-callers do not all come back with the same pointer, or when any of them caught the singleton's `NSInternalInconsistencyException` out of `-[UIMenuController init]`. Either signature is the unguarded slow path taken by two threads at once, so either is a reproduction. A `cold` run exits `0` when all 8 agree and nothing threw. That is a missed trial at the measured rate, which is why `run.sh` retries the cold trial as fresh child processes, up to 50, stopping at the first nonzero exit, then runs `warm` once. The `warm` run fills the slot single-threaded before the race, so its 8 threads hit only the cached-read fast path and must always agree. A nonzero exit there would mean the harness itself is broken, not the framework.

Measured today on this host (macOS 26.6.2, Apple silicon, Xcode 27) the hit rate is 96 of 100 fresh-process cold trials, so `run.sh` normally stops within the first 1-3 attempts.

## Platforms

UIKit does not link natively on macOS, so the repro builds for Mac Catalyst (`arm64-apple-ios17.0-macabi`) against the iOSSupport slice of the macOS SDK. That slice is the Mac's UIKit, and the disassembled functions live in the same dyld shared cache images the host runs, so the evidence applies to this OS build. Not verified in the repository's tart VM: that image ships only Command Line Tools, which lack the Catalyst `iOSSupport` SDK slice a full Xcode install provides, so the build itself cannot run there. `track.yml`'s GitHub Actions runners carry full Xcode and will track this method once merged. Not yet tried on iOS.

## Results

See `results/`. One file per platform and exact OS build, at `fault` strength.
