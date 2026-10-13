# `-[UIPrintInteractionController setPrintFormatter:]` setter race

Apple Feedback: not yet filed.

## What this tests

`-[UIPrintInteractionController setPrintFormatter:]` stores its value on the process-wide shared instance behind `+[UIPrintInteractionController sharedPrintController]` through the classic unlocked ARC strong-pointer sequence, `retain(new)`, `load(old)`, `store`, `release(old)`, with no lock anywhere in the function. Two threads racing the setter can each load the same old value and each release it, so the old value is released twice. If its reference count reaches zero from this it is deallocated while a concurrent caller may still hold it, a plausible use-after-free.

The setter's unlocked store runs on every call, so the race repeats every round within one process and one invocation hammers it for thousands of rounds. The singleton-getter harnesses of the previous batch needed one fresh process per trial. Source: row 23 of the Direction 1 table in `MASTER-ACTIONS.md` and `UIKit.md` Family B (lines 35–49, the representative disassembly window at lines 39–45, and line 47 naming this setter as the same shape), both under `objc2.upstreams/safety-audit/plans/safety-audit/` (read-only reference).

The class and selectors are resolved through the ObjC runtime (`NSClassFromString`, `NSSelectorFromString`, `objc_msgSend`), matching `UIKit/sharedPrintController-lazy-init`. The shared instance is resolved once, before the threads start, since the getter is already-safe and the setter is the only racing part. Each round's probe value is a fresh `[[NSObject alloc] init]`, which `setPrintFormatter:` accepts directly since it is a plain strong property.

## Running it

```sh
clang -O2 -fobjc-arc -target arm64-apple-ios17.0-macabi \
  -isysroot /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX27.0.sdk \
  -iframework /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX27.0.sdk/System/iOSSupport/System/Library/Frameworks \
  -framework Foundation -framework UIKit repro.m -o repro
./repro 1000        # 8 threads each call -setPrintFormatter: 1000 times with a fresh NSObject
./repro 5000 warm    # control: the same 5000 sets single-threaded
```

## Reading a result

The cold run is expected to crash with `SIGSEGV` (exit 139) well before completing all 8000 total sets (8 threads × 1000 rounds). In the verification run today, every 1000-round cold trial died within 34–44 ms of process start, and the same binary run at 50 rounds per thread still crashed 3 of 6 times. The warm control does the same sets single-threaded and must complete cleanly, exit 0, every time. A crash there would mean the harness itself is broken, not the framework.

## Platforms

UIKit does not link natively on macOS, so the repro builds for Mac Catalyst (`arm64-apple-ios17.0-macabi`) against the iOSSupport slice of the macOS SDK. That slice is the Mac's UIKit, and the disassembled functions live in the same dyld shared cache images the host runs, so the evidence applies to this OS build. Not verified in the repository's tart VM: that image ships only Command Line Tools, which lack the Catalyst `iOSSupport` SDK slice a full Xcode install provides, so the build itself cannot run there. `track.yml`'s GitHub Actions runners carry full Xcode and will track this method once merged. Not yet tried on iOS.

## Results

See `results/`. One file per platform and exact OS build, at `fault` strength.
