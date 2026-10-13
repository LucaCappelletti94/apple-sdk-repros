# `-[UIPrintInteractionController setPrintingItems:]` setter race

Apple Feedback: not yet filed.

## What this tests

`-[UIPrintInteractionController setPrintingItems:]` is the `copy` property of the process-wide shared singleton returned by `+[UIPrintInteractionController sharedPrintController]`. The setter stores through the classic unlocked ARC sequence of retain-new, load-old, store-new, release-old with no lock anywhere in the function, which the disassembly shows as a thunk into a shared generic store helper at ivar offset `0x98`. Two threads racing the setter can each load the same old value and each release it, a double-release. If the old value's reference count reaches zero from this, it is deallocated while a concurrent reader may still hold it, a plausible use-after-free.

Unlike the singleton-getter findings from the previous batch, which each needed a fresh process per trial, this race is re-triggered within one process. Every setter call runs the unguarded store sequence, so 8 threads each looping rounds of fresh values and setter calls in a single process reach the race window over and over, and no fresh-process retry loop is needed. The shared instance is resolved once before the threads start, since its own lazy init is a separate finding. Only the setter call inside the loop races.

This is one of the audit's Family B findings, the five unlocked ARC strong-pointer stores on the `UIMenuController` and `UIPrintInteractionController` shared singletons. Source: `MASTER-ACTIONS.md` Direction 1 table row 24 (`UIKit`, `UIPrintInteractionController.printingItems` setter) and row 25 for the inherited `printingItem` note, and `UIKit.md` Family B, lines 35–49, with the representative disassembly window, both under `objc2.upstreams/safety-audit/plans/safety-audit/`.

`-[UIPrintInteractionController setPrintingItem:]` (singular) is not a separate finding. It copies/wraps its argument and then calls `setPrintingItems:`, so it inherits this exact race via forwarding, per the audit's own characterization at `UIKit.md` line 47. No separate harness is built for it.

## Running it

```sh
clang -O2 -fobjc-arc -target arm64-apple-ios17.0-macabi -isysroot /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX27.0.sdk -iframework /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX27.0.sdk/System/iOSSupport/System/Library/Frameworks -framework Foundation -framework UIKit repro.m -o repro
./repro 1000        # 8 threads x 1000 rounds of setPrintingItems: with a fresh value each round
./repro 5000 warm    # control: single-threaded, 5000 sequential sets
```

Built for Mac Catalyst because UIKit does not link natively on macOS, and the Catalyst slice is the Mac's UIKit with the disassembled function living in the same dyld shared-cache images the host runs. The class and selectors are resolved through the ObjC runtime so the harness does not depend on any header's availability annotations.

The probe value is a real `NSArray`, `@[[[NSObject alloc] init]]`, fresh each round. The property is `copy`, so the setter calls `-copyWithZone:` on its argument. The probe uses the property's declared `NSArray` type for fidelity to the real `printingItems` type, rather than an unrelated `NSObject`. `NSArray` implements `copyWithZone:` and is not tagged-pointer-eligible, so every round's retain-new and release-old are real operations on the shared slot.

## Reading a result

The cold run is expected to crash with `SIGSEGV`, `exit 139`, when the double-release of the old value faults inside or just after the store sequence. A scratch variant of this harness with a `SIGSEGV` handler that reports the total completed set count measured the fault landing after 46 to 143 sets out of the 8000 in 1000-round trials, and the crash still lands at 50 rounds per thread. The fault therefore arrives within the first few dozen rounds per thread in practice, well inside the 1000-round bound. The warm control runs the same setter single-threaded for 5000 sequential sets and completes cleanly, printing `completed 5000 rounds`. A crash there would mean the harness itself is broken, not the framework. `run.sh` builds once, runs the cold trial (expected nonzero exit) and the warm control (expected zero exit), and writes the record via `scripts/make-crash-result.sh`.

## Platforms

UIKit does not link natively on macOS, so the harness builds for Mac Catalyst, whose slice is the Mac's UIKit. Measured on the host today, macOS 26.6.2 build 25G83, Apple silicon, Xcode 27, the cold trial crashed with `SIGSEGV` and `exit 139` within the first few dozen rounds per thread, and the 5000-set single-threaded control completed cleanly. Not verified in the repository's tart VM: that image ships only Command Line Tools, which lack the Catalyst `iOSSupport` SDK slice a full Xcode install provides, so the build itself cannot run there. `track.yml`'s GitHub Actions runners carry full Xcode and will track this method once merged. Not yet tried on iOS.

## Results

See `results/`. One file per platform and exact OS build, at `fault` strength.
