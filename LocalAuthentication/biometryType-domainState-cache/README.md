# `-[LAContext biometryType]` / `-[LAContext domainState]` cached-pointer race

Apple Feedback: FB25157119 (filed, open as of 2026-10-12, Apple has not replied).

## What this tests

`-[LAContext biometryType]` reads a process-wide cached `NSNumber` without retaining it first, while `-[LAContext domainState]` and the reply of `-evaluatePolicy:localizedReason:reply:` replace and release that same cache without a lock. All three run against separate `LAContext` instances, so threads that each own their own context still share this global. Disassembly of the macOS 26.6.2 binary (see the call-path gist linked from `madsmtm/objc2#864`) shows no lock or atomic instruction around any of these accesses.

## What this harness can and can't show

On every machine available here, the cached values are tagged pointers, so retain and release on them are no-ops and nothing crashes no matter how badly the accesses interleave. That hides the actual defect, it does not mean the defect is absent. See `EVIDENCE.md` for why `repro.m` is scored at `dynamic-window` strength rather than `fault`: it swizzles `-biometryType` and `-domainState` to record each call's time interval and reports whether a reader's interval overlapped a writer's (or a writer overlapped another writer), which is direct proof that calls into these methods run concurrently in a live process. It cannot show that an overlap corrupts anything here, since tagged pointers make retain and release no-ops either way.

The actual over-release and use-after-free need a build where the cached values are real heap objects, which needs 32-bit pointers. Current watchOS device builds target both `arm64_32` (32-bit pointers, where this would be a real use-after-free) and `arm64`/`arm64e` (64-bit pointers, same as macOS, where it's hidden the same way). Which current Apple Watch models fall on which side is not identified here, Apple does not publish an ABI-to-model table and nothing in Xcode's bundled metadata gives one either, only confirmation (Xcode 27's watchOS SDK settings) that both ABIs are real current device targets. The watchOS Simulator does not help: it was checked directly on a real Mac and runs as a 64-bit process regardless of which watchOS version it simulates, so it hits the same blind spot as macOS and the iOS Simulator, never the device's real pointer width.

## Running it

```sh
clang -O2 -fobjc-arc -framework Foundation -framework LocalAuthentication repro.m -o repro
./repro 8 4 5   # 8 reader threads, 4 writer threads, 5 seconds
```

## Reading a result

Each line reports `readers=R writers=W seconds=S calls=C overlaps=N`. `overlaps` greater than zero means a reader's call interval overlapped a writer's, or two writers' calls overlapped each other, confirmed dynamically rather than only inferred from the disassembly.

## Platforms

Runs on macOS and, for the same reason the counter race does, would run identically on iOS Simulator; a Simulator result would be redundant with the macOS one and isn't recorded. It does not run on watchOS Simulator for a different reason: Simulator processes are always 64-bit regardless of platform (confirmed with a probe program run in a real Apple Watch Series 12 simulator, which reported `sizeof(void*)=8` and a non-refcounted tagged `NSNumber`), so it adds no evidence beyond what macOS already shows.

## Results

See `results/`. One file per platform and exact OS build, at `dynamic-window` strength.
