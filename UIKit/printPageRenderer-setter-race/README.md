# `-[UIPrintInteractionController setPrintPageRenderer:]` setter race

Apple Feedback: not worth filing. Apple declares `UIPrintInteractionController` main-thread-only, see [why](../../README.md#findings-not-filed-with-apple).

## What this tests

`+[UIPrintInteractionController sharedPrintController]` is a process-wide shared singleton, and `-[UIPrintInteractionController setPrintPageRenderer:]` stores through the classic unlocked ARC strong-pointer store: `retain` the new value, `load` the old value without a lock, `store` the new value, then `release` the old one, no lock and no `dispatch_once` anywhere in the function. The audit's representative disassembly window is `-[UIMenuController setMenuItems:]`, and the same shape is confirmed at `setPrintPageRenderer:` in the source note cited below. Two threads racing through the setter can each load the same old value and each release it, a double-release; if that value's reference count reaches zero it is deallocated while a concurrent reader may still hold it, a plausible use-after-free. Unlike the `sharedPrintController` getter finding from the same audit (a one-shot per process), this setter race can be hammered repeatedly within a single process, exactly the shape of `DeviceCheck/appAttestController-lazy-init`, so no external process-spawn loop is needed.

This is one of the `Family B` findings from the objc2 safety-audit session being ported to runnable harnesses. Sources: `plans/safety-audit/MASTER-ACTIONS.md` direction 1 table row 22 (`UIKit`, `UIPrintInteractionController.printPageRenderer` (setter), "Same shape"), and `plans/safety-audit/UIKit.md` `Family B` (lines 35–49, with the representative `setMenuItems:` disassembly window and the line 47 naming `setPrintPageRenderer:` among the same-shape setters), both in the `objc2.upstreams/safety-audit` session's worktree.

The class is resolved through the ObjC runtime, `NSClassFromString(@"UIPrintInteractionController")` + `NSSelectorFromString` for `sharedPrintController` and `setPrintPageRenderer:` + `objc_msgSend`, so the harness does not depend on any header's availability annotations.

## Running it

```sh
clang -O2 -fobjc-arc -target arm64-apple-ios17.0-macabi -isysroot /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX27.0.sdk -iframework /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX27.0.sdk/System/iOSSupport/System/Library/Frameworks -framework Foundation -framework UIKit repro.m -o repro
./repro 10000      # 8 threads race the setter on the shared instance, a fresh NSObject each round
./repro 50000 warm # control: the same 50000 sets run single-threaded
```

Built for Mac Catalyst because UIKit does not link natively on macOS; the Catalyst slice is the Mac's UIKit. The probe value is a plain fresh `[[NSObject alloc] init]` each round: `printPageRenderer` is a strong property, not a `copy` property, so a plain `NSObject` works directly.

## Reading a result

The cold run is expected to crash: a `SIGSEGV` (exit 139) as the double-release over-frees a value, or the freed value's memory is reused and a later touch faults. Either way `./repro` exits abnormally rather than printing `completed N rounds`. The warm control runs the same 5000 sets single-threaded, so it always completes cleanly; a crash there would mean the harness itself is broken, not the framework.

Measured on the host today: the cold run crashed with `SIGSEGV` (exit 139) in every trial tried, including a trial of only 50 rounds, so it dies well inside the 1000-round bound. The single-threaded 5000-set warm control completed cleanly. One 1,000-round run on a GitHub-hosted runner completed without crashing, so `run.sh` uses 10,000 rounds and a 50,000-set warm control.

## Platforms

UIKit does not link natively on macOS, so the harness builds for Mac Catalyst, whose slice is the Mac's UIKit. Measured on the host today, macOS 26.6.2 build 25G83, Apple silicon, Xcode 27. Not verified in the repository's tart VM: that image ships only Command Line Tools, which lack the Catalyst `iOSSupport` SDK slice a full Xcode install provides, so the build itself cannot run there. `track.yml`'s GitHub Actions runners carry full Xcode and will track this method once merged. Not yet tried on iOS.

## Results

See `results/`. One file per platform and exact OS build, at `fault` strength.
