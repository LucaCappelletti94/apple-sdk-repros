# `-[UIPrintInteractionController setPrintInfo:]` unlocked-store race

Apple Feedback: not worth filing. Apple declares `UIPrintInteractionController` main-thread-only, see [why](../../README.md#findings-not-filed-with-apple).

## What this tests

`+[UIPrintInteractionController sharedPrintController]` hands out the process-wide shared controller, and its settable `printInfo` property is stored through the classic unlocked ARC strong-pointer sequence. Retain the new value, load the old value without a lock, store the new value without a lock, release the old value, with no lock anywhere in the function. The audit's representative disassembly window is `-[UIMenuController setMenuItems:]` and the same shape is confirmed at `setPrintInfo:` in the source note cited below. Two threads racing the setter can each load the same old value and each release it, a double-release, and if the object's reference count reaches zero from this it is deallocated while a concurrent reader may still hold it, a plausible use-after-free.

Unlike the lazy-init getter findings already merged in this repository, this is the setter half of the audit's Family B shape. The unlocked store runs on every call, so the race can be hammered repeatedly within one process, and the harness races 8 threads through a loop of fresh probe values instead of retrying across fresh processes. Each set constructs a fresh `[[NSObject alloc] init]`, since `printInfo` is a plain strong property, not a `copy` one, so a plain `NSObject` probe works directly.

The shared instance is resolved once on the main thread before any worker starts, so the getter, which carries its own separate unlocked lazy-init finding, is only ever called uncontested here, and only the setter call is in the raced path. The implementation lives in the `PrintKitUI` binary, not in a header this harness may rely on, so the class and selector are resolved through the ObjC runtime, `NSClassFromString` + `NSSelectorFromString` + `objc_msgSend`, matching the already-merged `UIKit/sharedPrintController-lazy-init` harness.

This is one of the Family B setter-shape findings from the objc2 safety-audit session being ported to runnable harnesses. Sources: `plans/safety-audit/MASTER-ACTIONS.md` Direction 1 table row 21, and `plans/safety-audit/UIKit.md` Family B (lines 35–49, the shared-singleton unlocked-store family with the disassembly window), both in the `objc2.upstreams/safety-audit` session's worktree.

## Running it

```sh
clang -O2 -fobjc-arc -target arm64-apple-ios17.0-macabi \
  -isysroot /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX27.0.sdk \
  -iframework /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX27.0.sdk/System/iOSSupport/System/Library/Frameworks \
  -framework Foundation -framework UIKit repro.m -o repro
./repro 1000        # 8 threads race the setter for 1000 rounds each, fresh NSObject probe per set
./repro 5000 warm   # control: single-threaded, 5000*8 = 40000 sets, five times the cold run's 8000
```

Built for Mac Catalyst because UIKit does not link natively on macOS. The Catalyst slice is the Mac's UIKit, and the disassembled function lives in the same dyld shared-cache images the host runs.

## Reading a result

The cold run is expected to crash, a `SIGSEGV` (exit 139) inside the setter's release or store, well before its 8000 total sets complete. Each thread prints a progress line every 50 sets, and the last lines in the raw output mark how far the race got before the crash, at most 50 sets behind it. A clean `completed 1000 rounds` would mean the double-release window was not hit in that trial. The warm control runs 40000 sets single-threaded, five times the cold run's total, so no two threads ever race the store, and it always completes cleanly with exit 0. A crash there would mean the harness itself is broken, not the framework.

## Platforms

HOST-ONLY. Measured on the host today, macOS 26.6.2 build 25G83, Apple silicon, Xcode 27. Every cold trial so far has crashed, 10 of 10, with exit 139 within the first ~50–100 sets of each thread, and the single-threaded 40000-set control completed cleanly in every run. Not verified in the repository's tart VM, that image ships only Command Line Tools, which lack the Catalyst `iOSSupport` SDK slice a full Xcode install provides, so the build itself cannot run there. `track.yml`'s GitHub Actions runners carry full Xcode and will track this method once merged.

## Results

See `results/`. One file per platform and exact OS build, at `fault` strength.
