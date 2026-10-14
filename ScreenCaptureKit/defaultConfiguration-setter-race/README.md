# `-[SCContentSharingPicker setDefaultConfiguration:]` setter race

Apple Feedback: FB25187882 (filed, open as of 2026-10-14, Apple has not replied).

## What this tests

`-[SCContentSharingPicker setDefaultConfiguration:]` is a `copy` property implemented as the standard unlocked ARC strong store. It retains the new value, loads the old ivar, stores the new value, and releases the old one, with no lock anywhere, then forwards to the picker daemon via XPC (disassembly, safety-audit `ScreenCaptureKit.md` line 30). Two threads racing the setter each load the same old value and each release it. If the old configuration's reference count reaches zero it is deallocated while a concurrent reader may still hold it.

`+[SCContentSharingPicker sharedPicker]` is `dispatch_once`-guarded and safe. The harness resolves it once, single-threaded, outside the race. Each round constructs a fresh `SCContentSharingPickerConfiguration` instance, the correct probe value for a `copy` property since the setter calls `copyWithZone:` on the argument.

The getter's lazy-init race on the same property is already covered by `ScreenCaptureKit/defaultConfiguration-lazy-init` in this repository. This finding is the setter half, a distinct defect. Source: `MASTER-ACTIONS.md` direction 1 table row 29, `ScreenCaptureKit.md` lines 15-30.

## Running it

```sh
clang -O2 -fobjc-arc -framework Foundation -framework ScreenCaptureKit repro.m -o repro
./repro 30000       # 8 threads each call setDefaultConfiguration: 30000 times on the shared picker
./repro 30000 warm  # control: single-threaded, 30000 sequential sets
```

## Reading a result

The cold run is expected to crash with `SIGSEGV` (exit 139) inside `objc_release` on a double-released configuration, well before completing all rounds. On a 4-core VM, 3,000 rounds crashed in only 1 of 20 runs and 30,000 rounds in 20 of 20, so `run.sh` uses 30,000. The warm control calls the setter sequentially on a single thread, so it always completes cleanly. A crash there would mean the harness is broken, not the framework.

`run.sh` retries the cold run as a fresh child process up to 5 times, stopping at the first crash, then runs the warm control once. The result is recorded via `scripts/make-crash-result.sh` at `fault` strength (see `EVIDENCE.md`).

## Platforms

Plain macOS (not Catalyst), Apple silicon, macOS 26.6.2 (25G83), Xcode 27.0. No Catalyst dependency, so the tart VM can also run this, and it does. Both the host and the tart VM reproduced the crash, see results/.

## Results

See `results/`. One file per platform and exact OS build, at `fault` strength.
