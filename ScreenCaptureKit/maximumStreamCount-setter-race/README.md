# `-[SCContentSharingPicker setMaximumStreamCount:]` setter race

Apple Feedback: FB25187882 (filed, open as of 2026-10-14, Apple has not replied).

## What this tests

`-[SCContentSharingPicker setMaximumStreamCount:]` is the standard unlocked ARC strong store. It retains the new value, loads the old ivar, stores the new value and releases the old one, with no lock anywhere, then forwards to the picker daemon over XPC (disassembly, `ScreenCaptureKit.md` lines 32-46, and `MASTER-ACTIONS.md` Direction 1 table row 29, both under `~/github/objc2.upstreams/safety-audit/plans/safety-audit/`). The XPC forwarding is serialized by the daemon connection, which does not protect the ivar update itself. Two threads racing the setter can each load the same old value and each release it, a double release. If the reference count reaches zero, the old `NSNumber` is deallocated while a concurrent reader may still hold it, a plausible use-after-free.

`+[SCContentSharingPicker sharedPicker]` is `dispatch_once`-guarded and safe, so it is called once, single-threaded, before the race. Only the setter call inside the loop races.

This is one of the seven same-process setter races the audit found (`MASTER-ACTIONS.md` rows 20-25 and 29) being ported to runnable harnesses. Unlike the one-shot-per-process lazy-init getter findings, this race re-triggers on every setter call, so one process can hammer it in a loop, exactly like `DeviceCheck/appAttestController-lazy-init`.

## Why the probe value has to be a float `NSNumber`

Small-integer `NSNumber`s built with `numberWithInt:` are tagged pointers on this platform, and `objc_retain`/`objc_release` on a tagged pointer is a no-op. A `[NSNumber numberWithInt:i]` probe leaves the race invisible, measured today as 0 crashes in 3000 rounds x 8 threads. A float value built with `numberWithDouble:` is heap-allocated. Its retain and release actually move its reference count, and the crash appears immediately. This is the same tagged-pointer blind spot `QuartzCore/animationSpeed-cache/README.md` documents, but over there the evidence is capped at `dynamic-window` because that race truly cannot be observed any other way. Here a non-tagged probe value exposes the crash directly, so the record stays at `fault` strength (see `EVIDENCE.md`).

## Running it

```sh
clang -O2 -fobjc-arc -framework Foundation -framework ScreenCaptureKit repro.m -o repro
./repro 1000        # 8 threads x 1000 rounds, each building a fresh float NSNumber and setting it
./repro 5000 warm   # control, single-threaded, 5000 x 8 = 40000 sets, five times the cold run
```

## Reading a result

The cold run is expected to crash with `SIGSEGV` (exit 139) well before all rounds complete, and measured today it crashed within the first few rounds in every fresh process (round 1-4 across five runs, one of which exited `SIGTRAP` 133 instead). The warm control runs 40000 sets single-threaded, five times the cold run total, and always completes cleanly with exit 0. A crash there would mean the harness is broken, not the framework.

## Platforms

Plain macOS (not Catalyst), Apple silicon. Verified on the real Mac host (macOS 26.6.2, build 25G83, Xcode 27.0) on 2026-10-13, and reproduced again inside a tart VM running the same build, see results/.

## Results

See `results/`. One file per platform and exact OS build, at `fault` strength.
