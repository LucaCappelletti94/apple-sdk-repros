# `-[UIMenuController setMenuItems:]` setter race

Apple Feedback: not worth filing. Apple declares `UIMenuController` main-thread-only, see [why](../../README.md#findings-not-filed-with-apple).

## What this tests

`+[UIMenuController sharedMenuController]` returns a process-wide singleton, and its settable `menuItems` property is stored by the classic unlocked ARC strong-pointer sequence. The setter retains the new value, loads the old value without a lock, stores the new value, and releases the old value, with no lock anywhere in the function. Two threads racing the setter can both load the same old value and both release it, a double-release. If the old value's reference count reaches zero from that, it is deallocated while a concurrent reader may still hold it, a use-after-free.

The disassembly of this build shows exactly this window for `-[UIMenuController setMenuItems:]`:

```
mov    x19, x2                ; new value
bl     objc_retain_x19        ; retain(new)
ldr    x8, [x20, #0x10]       ; load old value, unlocked
str    x19, [x20, #0x10]      ; store new, no lock held
bl     objc_release_x8        ; release old
```

The disassembly evidence is in the objc2 safety-audit session's plan files (read-only reference, `~/github/objc2.upstreams/safety-audit/plans/safety-audit/`). Row 20 of the direction 1 table in `MASTER-ACTIONS.md` (`UIKit`, `UIMenuController.menuItems` setter, "unlocked ARC strong store on a shared singleton; two racing writers can double-release the old value") and the family B section of `UIKit.md` (lines 35-49), whose representative window is this method. This repro is one of the five UIKit setter-shape findings from that audit being ported to runnable harnesses in this batch, and it reaches `fault` strength by crashing directly and reproducibly.

## Running it

The class and selector are resolved through the Objective-C runtime (`NSClassFromString`, `NSSelectorFromString`, `objc_msgSend`), matching the other UIKit repros in this repository. The shared instance is resolved once before the threads are spawned, since the singleton's own lazy init is not part of this race. Each racing iteration constructs a fresh `NSObject` probe value and sets it, and `menuItems` is a plain strong property, so a fresh `NSObject` is the right probe. A `copy` property would call `copyWithZone:` on its argument and reject one.

```sh
clang -O2 -fobjc-arc -target arm64-apple-ios17.0-macabi \
  -isysroot /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX27.0.sdk \
  -iframework /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX27.0.sdk/System/iOSSupport/System/Library/Frameworks \
  -framework Foundation -framework UIKit repro.m -o repro
./repro 1000        # 8 threads each set menuItems 1000 times, 8000 racing sets in total
./repro 5000 warm   # control: 5000 sequential single-threaded sets
```

## Reading a result

The cold run is expected to crash before completing its 8000 sets. Measured today on this host, the process died with `SIGSEGV` (exit 139) well inside that bound, and the bracketing probes below pin the window: 50 per-thread rounds (400 total sets) never crashed in four trials, while 100 per-thread rounds (800 total sets) crashed in 2 of 2 trials. The `warm` run is the negative control, 5000 sequential single-threaded sets through the same setter, and it must always complete cleanly with `completed 5000 rounds`. A crash there would mean the harness itself is broken, not the framework.

## Platforms

UIKit does not link natively on macOS, so the harness builds for Mac Catalyst, whose slice is the Mac's UIKit. Measured on the host today, macOS 26.6.2 build 25G83, Apple silicon. Not verified in the repository's tart VM: that image ships only Command Line Tools, which lack the Catalyst `iOSSupport` SDK slice a full Xcode install provides, so the build itself cannot run there. `track.yml`'s GitHub Actions runners carry full Xcode and will track this method once merged.

## Results

See `results/`. One file per platform and exact OS build, at `fault` strength.
