# `+[NSScriptCoercionHandler sharedCoercionHandler]` lazy-init race

Apple Feedback: not yet filed.

## What this tests

`+[NSScriptCoercionHandler sharedCoercionHandler]` fills a process-wide static slot lazily with an unguarded load, branch-if-cached, `alloc`+`init` and unconditional store, no lock and no `dispatch_once`. The disassembly evidence is in the objc2 safety-audit plan, `MASTER-ACTIONS.md` direction 1 table row 2 and `Foundation.md` lines 29-30, both under `~/github/objc2.upstreams/safety-audit/plans/safety-audit/`. Two threads making the very first call at once can both allocate and both store, and the two callers then hold different objects from what is documented as one shared instance.

This is one of 10 singleton-shape findings from that audit being ported to runnable harnesses. The slot fills once per process rather than once per object, so each process gives exactly one trial. The race hit in 100/100 fresh-process trials on the host today.

## Running it

```sh
clang -O2 -fobjc-arc -framework Foundation repro.m -o repro
./repro cold    # 8 threads race the process's first sharedCoercionHandler call
./repro warm    # control, the getter is pre-called once alone first
sh run.sh macos-host-apple-silicon
```

## Reading a result

`./repro cold` exits 1 if any of the 8 threads got a pointer different from the first thread's. That divergence is the externally visible contract violation, two callers holding different objects from a documented single shared instance. `./repro warm` pre-calls the getter once alone and the 8 threads then only read the cached value, so a divergence there would mean the harness itself is broken.

## Platforms

macOS 26.6.2 build 25G83, Apple silicon, Xcode 27. Not yet run on other platforms.

## Results

See `results/`. One file per platform and exact OS build, at `fault` strength per `EVIDENCE.md`.
