# `nw_browser_browse_results_changed_handler_t` nonnull results passed `NULL`

Apple Feedback: FB25452730 (filed, open as of 2026-11-05, Apple has not replied).

## What this tests

`browser.h` declares `nw_browser_browse_results_changed_handler_t` inside `NW_ASSUME_NONNULL_BEGIN`, so its `old_result` and `new_result` are nonnull. Network passes `NULL` as `old_result` for every added service and as `new_result` for every removed one. `nw_browse_result_get_changes`, which the handler's documentation says to call with those two values, already declares both `_Nullable`.

Swift imports both parameters as non-optional `nw_browse_result_t`, so code written to the header's types compiles without a warning and crashes. This handler dies with `EXC_BAD_ACCESS` at address 0 in `swift_getObjectType` on the removal, after Network logs `nw_browse_result_copy_endpoint called with null result`.

```swift
nw_browser_set_browse_results_changed_handler(browser) { old, new, done in
    print(nw_browse_result_copy_endpoint(new))
}
```

Bindings generated from the header inherit the same promise, which is how `objc2` handed Rust closures an invalid `NonNull` (`madsmtm/objc2#889`).

## Running it

```sh
clang -O2 -fobjc-arc -framework Foundation -framework Network repro.m -o repro
./repro    # advertises one Bonjour service, browses for it, withdraws it, exits 1 if a NULL reached the handler
```

`run.sh` also compiles `repro.m` with `-DPROBE_OLD_RESULT` and `-DPROBE_NEW_RESULT` under `-Werror=nonnull`, which passes `NULL` to one handler parameter. Clang rejects it exactly when the SDK header declares that parameter nonnull.

## Reading a result

Each record holds the header annotation from the probe (`nonnull` or `not-nonnull` per parameter) and the runtime counts separately. `reproduced` means a `NULL` reached a parameter the header declares nonnull. A header that drops the nonnull promise gives `not-reproduced` even while the `NULL`s keep arriving, and a run that saw no added and removed service is `inconclusive`. The probe reads the SDK used for the build, so iOS Simulator records pair the installed Xcode's simulator header with the runtime under test.

## Platforms

Reproduces on macOS 26.7.1 on the host, macOS 26.6.2 in a tart VM, and the iOS 17.5, 26.5 and 27.0 Simulators. Not yet run on macOS 15 or earlier.

## Results

See `results/`. One file per platform and exact OS build, at `fault` strength.
