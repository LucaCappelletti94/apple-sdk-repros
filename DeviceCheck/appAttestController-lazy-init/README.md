# `-[DCAppAttestService appAttestController]` lazy-init race

Apple Feedback: FB25187723 (filed, open as of 2026-10-14, Apple has not replied).

## What this tests

`+[DCAppAttestService sharedService]` (and `new`, used here to get a fresh instance each round) returns an object whose `-appAttestController` getter creates its controller lazily: a plain load, an `alloc`+`init` and store, and a release of the old value, no lock and no `dispatch_once`. Every `DCAppAttestService` instance method (`isSupported`, the key-generation and attestation methods) calls this getter first. Two threads making the first call on the same instance at once can both create a controller, with one thread's store releasing the controller the other thread is about to use.

This is the same shape as 10 methods a broader objc2 safety-audit session found and did not yet build harnesses for (see `madsmtm/objc2`'s audit plan, `MASTER-ACTIONS.md`, direction 1): an unguarded double-checked lazy singleton or cache slot, no lock, no `dispatch_once`. This repro is the first one of that shape to run in this repository, ported from a working crash reproduction rather than built fresh.

## Running it

```sh
clang -O2 -fobjc-arc -framework Foundation -framework DeviceCheck repro.m -o repro
./repro 1000        # 8 threads call -isSupported on a fresh DCAppAttestService each round
./repro 5000 warm    # control: each round's controller is created before the threads start
```

## Reading a result

The cold run is expected to crash: either `objc_release` faults inside `-[DCAppAttestService appAttestController]` (`SIGSEGV`), or an `NSInvalidArgumentException` is raised because the freed controller's memory was reused (`SIGABRT`). Either way `./repro` exits abnormally rather than printing `completed N rounds`. The warm control creates each round's controller before the racing calls, so it always completes cleanly; a crash there would mean the harness itself is broken, not the framework.

## Platforms

Crashed consistently in every run tried so far, both directly on the host and inside a tart VM, both Apple silicon macOS 26.6.2. Not tried on iOS, though the original report's configuration notes the iOS 26 DeviceCheck build appears to have the same lazy getter while iOS 18 does not.

## Results

See `results/`. One file per platform and exact OS build, at `fault` strength.
