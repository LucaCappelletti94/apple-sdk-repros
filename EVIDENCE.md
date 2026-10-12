# Evidence strength

Every `results/*.json` record carries a `strength` field, so the sitemap and the method's own README never imply stronger evidence than what actually ran. Three levels, from weakest to strongest.

`static`: disassembly or decompilation only, nothing executed. No `results/` entry exists at this level; it belongs in the method's README as the reasoning for why a dynamic harness is expected to find something, not as a result on its own.

`dynamic-window`: instrumented code ran and directly observed the unsynchronized concurrent access itself, for example two threads' calls into methods known from disassembly to touch shared state without a lock overlapping in time. This proves the race condition is live in a running process. It does not prove the race corrupts anything, either because the consequence needs an architecture or build nothing available can run, or because the harness only measured the window rather than triggering the fault.

`fault`: the actual externally visible defect occurred while running, a wrong answer, a crash, or observed corruption. This is the strongest level and the only one that needs no further qualification.

A `strength` below `fault` is not a weaker version of the same claim, it is a different claim: that the hazard is real and live, not that it has been shown to break anything on the platform that produced the record. State the gap explicitly in the method's README rather than letting the `results/` table imply otherwise.
