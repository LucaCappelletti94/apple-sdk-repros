# `+[UIAccelerometer sharedAccelerometer]` lazy-init race

Apple Feedback: not yet filed.

## What this tests

`+[UIAccelerometer sharedAccelerometer]` lazily creates the process-wide singleton. It loads the cached pointer from a static slot, branches if non-null, else `objc_alloc_init`s, reloads the slot and does an unconditional store back, no lock and no `dispatch_once` — only a trailing `objc_release` of whatever the reload saw. The full disassembly of this build is in the source cited below. Two threads making the first call at once can each allocate an instance and each be handed a different one, breaking the documented single-instance contract for the rest of the process. There is no over-release and no leak because the store's extra reference is released exactly once.

This is one of 10 singleton-shape findings from the objc2 safety-audit session that are being ported to runnable harnesses in this repository. Source: `MASTER-ACTIONS.md`, Direction 1 table row 5 (`UIKit`, `+[UIAccelerometer sharedAccelerometer]`, "Same shape"), and `UIKit.md` Family A (lines 17–33, with the representative disassembly window) plus the method table entry at line 79, both under `objc2.upstreams/safety-audit/plans/safety-audit/`. Unlike the already-merged DeviceCheck finding, this getter is a one-shot per process, the static slot only takes its unguarded slow path on the very first call, so each fresh process gives exactly one trial.

The class is deprecated since iOS 5.0 and marked `API_OBSOLETED("...", ios(2.0, 5.0, 27.0))` in this SDK's header, so a header-based call would not compile at this deployment target. The underlying UIKitCore implementation is still present and answers the selector at runtime through the Catalyst slice on this macOS build, which is what was disassembled. The harness therefore resolves the class and selector dynamically, `NSClassFromString(@"UIAccelerometer")` + `NSSelectorFromString(@"sharedAccelerometer")` + `objc_msgSend`, guarded by `class_getClassMethod` because `+respondsToSelector:` reports `NO` for the obsoleted selector even though the method is present and dispatches normally.

## Running it

```sh
clang -O2 -fobjc-arc -target arm64-apple-ios17.0-macabi \
  -isysroot /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX27.0.sdk \
  -iframework /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX27.0.sdk/System/iOSSupport/System/Library/Frameworks \
  -framework Foundation -framework UIKit repro.m -o repro
./repro cold    # 8 threads released at once call the getter for the first time in this process
./repro warm    # control: one uncontested call warms the cache, then the same 8-thread release
```

`repro` does exactly one trial per process invocation and exits `1` when the threads disagree, `0` when all 8 agree. `run.sh` retries the cold trial as fresh child processes up to 50 times, since only a fresh process gets a new slow-path trial, then runs the warm control once and writes the record via `scripts/make-crash-result.sh`.

## Reading a result

The cold exit code is the claim, at `fault` strength per `EVIDENCE.md`. A nonzero cold exit means two callers of a documented single-instance getter were handed different objects, a direct, externally visible contract violation. The warm control pre-populates the cache before the threads race, so the threads can only hit the cached read. If it ever diverges, the harness itself is broken, not the framework.

## Platforms

UIKit does not link natively on macOS, so the harness builds for Mac Catalyst, whose slice is the Mac's UIKit. Measured on the host today, macOS 26.6.2 build 25G83, Apple silicon, 99 of 100 fresh cold processes diverge. The 50-retry bound in `run.sh` sits far above that rate, so the cold trial succeeds within the first attempts in practice. Not verified in the repository's tart VM: that image ships only Command Line Tools, which lack the Catalyst `iOSSupport` SDK slice a full Xcode install provides, so the build itself cannot run there. `track.yml`'s GitHub Actions runners carry full Xcode and will track this method once merged.

## Results

See `results/`. One file per platform and exact OS build, at `fault` strength.
