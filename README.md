# apple-sdk-repros

[![Track](https://github.com/LucaCappelletti94/apple-sdk-repros/actions/workflows/track.yml/badge.svg)](https://github.com/LucaCappelletti94/apple-sdk-repros/actions/workflows/track.yml)

Runnable reproductions of soundness defects in Apple SDK frameworks, rerun on each new macOS release to track Apple's fixes.

One directory per method or bug, each with a standalone `repro.m`, a `README.md` naming the Apple Feedback ID and what the repro proves, and `results/` holding one dated record per platform and exact OS build. `.github/workflows/track.yml` reruns every tracked repro monthly on the macOS majors still receiving Apple security patches and commits a fresh result when one changes. `scripts/run-in-tart.sh` runs the same repros against macOS majors GitHub's hosted runners don't offer, using [tart](https://tart.run/).

<!-- sitemap:start -->
| Framework | Method | Status | Feedback |
|---|---|---|---|
| DeviceCheck | [`-[DCAppAttestService appAttestController]` lazy-init race](DeviceCheck/appAttestController-lazy-init/) | fault: reproduced | none filed |
| LocalAuthentication | [`-[LAContext biometryType]` / `-[LAContext domainState]` cached-pointer race](LocalAuthentication/biometryType-domainState-cache/) | dynamic-window: window-detected | FB25157119 |
| LocalAuthentication | [`+[LAContext newInstanceId]` / `+[LAContext newCommandId]` counter race](LocalAuthentication/newInstanceId-newCommandId-race/) | fault: reproduced | FB25157108 |
| UIKit | [`+[UIMenuController sharedMenuController]` lazy-init race](UIKit/sharedMenuController-lazy-init/) | fault: reproduced | none filed |
<!-- sitemap:end -->

