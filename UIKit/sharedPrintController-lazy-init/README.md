# `+[UIPrintInteractionController sharedPrintController]` lazy-init race

Apple Feedback: not worth filing. Apple declares `UIPrintInteractionController` main-thread-only, see [why](../../README.md#findings-not-filed-with-apple).

## What this tests

`+[UIPrintInteractionController sharedPrintController]` creates its singleton lazily with an unguarded double-checked pattern: load the cached pointer from a static slot, branch if non-null, else `alloc`+`init`, reload the slot, and store unconditionally, with no lock and no `dispatch_once` anywhere in the function — the only balancing act is a trailing release of whatever the reload saw, which does not close the window. The audit classifies the function as the exact shape of `+[UIAccelerometer sharedAccelerometer]`, whose representative disassembly window is reproduced in the source note below. The implementation lives in the `PrintKitUI` binary, reachable through the `UIKit` import.

The getter is documented and implemented as a single shared instance, so two first callers receiving different objects is a direct, externally visible contract violation, observable as pointer divergence. Unlike the instance-method shape in `DeviceCheck/appAttestController-lazy-init`, this is a process-wide one-shot lazy-init: the unguarded slow path runs exactly once per process, on the very first call ever, so a single process gives exactly one trial and no in-process loop can re-trigger it. The harness therefore races 8 threads on the first call of a fresh process and retries across fresh processes.

This is one of 10 singleton-shape findings from the objc2 safety-audit session being ported to runnable harnesses. Sources: `plans/safety-audit/MASTER-ACTIONS.md` direction 1 table, and `plans/safety-audit/UIKit.md` lines 17–19 (the Family A description) and line 90 (the verdict table row), both in the `objc2.upstreams/safety-audit` session's worktree.

## Running it

```sh
clang -O2 -fobjc-arc -target arm64-apple-ios17.0-macabi -isysroot /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX27.0.sdk -iframework /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX27.0.sdk/System/iOSSupport/System/Library/Frameworks -framework Foundation -framework UIKit repro.m -o repro
./repro cold    # 8 threads race the very first call in this process
./repro warm    # control: the getter is pre-called once before the threads start
```

Built for Mac Catalyst because UIKit does not link natively on macOS; the Catalyst slice is the Mac's UIKit, and the disassembled function lives in the same dyld shared-cache images the host runs. The class and selector are resolved through the ObjC runtime so the harness does not depend on any header's availability annotations.

## Reading a result

`cold` races the very first call in a fresh process: `exit 1` if the 8 first callers disagree on the returned pointer, `exit 0` if they all get the same object. `warm` pre-calls the getter once single-threaded, so the 8 racing threads only take the fast cached-read path and must always agree; a divergence there means the harness itself is broken, not the framework. `run.sh` builds once, retries `cold` as fresh child processes up to 50 times stopping at the first divergence, then runs `warm` once.

## Platforms

Pointer divergence only, no exception or crash signature observed, in contrast to the `UIMenuController` finding from the same audit. Measured hit rate on this host (macOS 26.6.2, build 25G83, Apple silicon, Xcode 27) as of 2026-10-13: 100/100 single trials diverged. Not verified in the repository's tart VM: that image ships only Command Line Tools, which lack the Catalyst `iOSSupport` SDK slice a full Xcode install provides, so the build itself cannot run there. `track.yml`'s GitHub Actions runners carry full Xcode and will track this method once merged. Not yet tried on iOS.

## Results

See `results/`. One file per platform and exact OS build, at `fault` strength.
