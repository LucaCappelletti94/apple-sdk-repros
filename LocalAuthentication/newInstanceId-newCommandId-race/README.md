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

`direct` calls `+newInstanceId` through a private selector, used only to measure how far the counter moved. Every `LAContext` construction calls the same counter, so `direct` exercises nothing that `new` does not reach through public API. `run.sh` records the `direct` runs only. Concurrent `new` runs slow the per-user `coreauthd` to about 150 ms per `LAContext` for minutes, for every process of that user (FB25189654), so a tracked run of them cannot finish.

## Reading a result

Each line reports `expected N increments, counter advanced M, lost N-M`. `lost` greater than zero on the repeated `direct` runs is the race. They lose most of their increments because nothing spaces the threads out. `new` loses far less often, because each construction waits on an XPC round trip to `coreauthd`. On macOS 26.6.2 it lost one increment in 1,600 and one in 4,000, which shows two `LAContext` objects created through public API alone can share an instance ID.

The single-threaded control (`direct 1 …`) should always show `lost 0`. If it doesn't, something about the run itself is suspect, not the framework.

## Platforms

Reproduces on macOS 26.6.2, on the host and in a tart VM, and on the iOS 27.0 Simulator through `scripts/run-in-ios-simulator.sh`.

## Results

See `results/`. One file per platform and exact OS build.
