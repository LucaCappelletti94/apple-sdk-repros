# `+[LAContext newInstanceId]` / `+[LAContext newCommandId]` counter race

Apple Feedback: FB25157108 (filed, open as of 2026-10-12, Apple has not replied).

## What this tests

`LAContext` construction and most of its methods take an ID from one of two process-wide counters (`+newInstanceId`, `+newCommandId`). On the macOS 26.6.2 binary, both counters are a plain load, add, and store, with no atomic instruction and no lock. `-[LARight init]` creates an `LAContext` internally, so it goes through the same counters.

Two threads that each create and use their own `LAContext` can race on these counters and end up with the same instance or command ID. Apple's own threading guidance says an object that is not documented thread-safe can still be used from several threads as long as each thread sticks to its own instance, so this race is reachable without doing anything unusual.

See `madsmtm/objc2#864` for where this was found and for the `objc2` Rust bindings this motivated.

## Running it

```sh
clang -O2 -fobjc-arc -framework Foundation -framework LocalAuthentication repro.m -o repro
./repro new 8 3000      # public API: 8 threads each create 3000 LAContext objects
./repro direct 16 1000000   # 16 threads call +newInstanceId directly, no XPC round trip in the way
./repro direct 1 16000000   # single-threaded control
```

`direct` calls `+newInstanceId` through a private selector, used only to measure how far the counter moved; it does not touch anything not already reachable through `new`. `new` only goes through public API.

## Reading a result

Each line reports `expected N increments, counter advanced M, lost N-M`. `lost` greater than zero on `new` means two or more `LAContext` objects, created through nothing but public API, ended up sharing an instance ID. `direct` isolates the counter from the XPC round trip each real construction makes, so it loses a much larger fraction, which is expected and not itself news; `new` losing anything is the result that matters.

The single-threaded control (`direct 1 …`) should always show `lost 0`. If it doesn't, something about the run itself is suspect, not the framework.

## Platforms

Reproduces on macOS. Not meaningfully testable on iOS/watchOS Simulator or in a way that differs from macOS, since this is pure Foundation/Objective-C runtime logic with no biometric-hardware dependency; a Simulator result would be redundant with the macOS one rather than additional evidence, so none is recorded here.

## Results

See `results/`. One file per platform and exact OS build.
