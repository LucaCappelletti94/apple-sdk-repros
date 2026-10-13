// clang -O2 -fobjc-arc -target arm64-apple-ios17.0-macabi \
//   -isysroot /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX27.0.sdk \
//   -iframework /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX27.0.sdk/System/iOSSupport/System/Library/Frameworks \
//   -framework Foundation -framework UIKit repro.m -o repro
// ./repro cold   first +sharedAccelerometer call in this process, 8 threads released together
// ./repro warm   control, one uncontested call first, then the same 8-thread release
//
// +[UIAccelerometer sharedAccelerometer] lazily creates the process-wide
// singleton with an unlocked load/cbnz/alloc_init/reload/unconditional-store,
// no lock and no dispatch_once (UIKit.md Family A, this build). Two first
// callers can each be handed a different instance for the rest of the
// process, breaking the documented single-instance contract.
//
// The header marks the class API_OBSOLETED as of ios 27.0, so the class
// and selector are resolved at runtime instead of a header-based call.
#import <Foundation/Foundation.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <pthread.h>
#import <stdatomic.h>

#define THREADS 8
static Class cls;
static SEL sel;
static atomic_int ready;
static void *results[THREADS];

static void *worker(void *arg) {
    size_t i = (size_t)(uintptr_t)arg;
    // the last thread to arrive releases all, no pthread_barrier_t in this SDK
    atomic_fetch_add(&ready, 1);
    while (atomic_load(&ready) < THREADS) {}
    // the bridge keeps our own +1 so the comparison cannot read freed memory
    results[i] = (__bridge_retained void *)((id (*)(id, SEL))objc_msgSend)(cls, sel);
    return NULL;
}

int main(int argc, char **argv) {
    int warm = argc > 1 && strcmp(argv[1], "warm") == 0;
    if (argc < 2 || strcmp(argv[1], warm ? "warm" : "cold") != 0) {
        fprintf(stderr, "usage: repro cold|warm\n");
        return 2;
    }
    cls = NSClassFromString(@"UIAccelerometer");
    sel = NSSelectorFromString(@"sharedAccelerometer");
    // +respondsToSelector: reports NO for the obsoleted selector on this build, so guard by IMP
    if (!class_getClassMethod(cls, sel)) {
        fprintf(stderr, "UIAccelerometer sharedAccelerometer unavailable\n");
        return 2;
    }
    if (warm) (void)((id (*)(id, SEL))objc_msgSend)(cls, sel);
    pthread_t t[THREADS];
    for (long i = 0; i < THREADS; i++) pthread_create(&t[i], NULL, worker, (void *)(uintptr_t)i);
    for (long i = 0; i < THREADS; i++) pthread_join(t[i], NULL);
    int diverged = 0;
    for (long i = 1; i < THREADS; i++) diverged |= results[i] != results[0];
    if (diverged) {
        for (long i = 1; i < THREADS; i++) {
            if (results[i] != results[0]) {
                printf("diverged: thread 0 got %p, thread %ld got %p\n", results[0], i, results[i]);
                break;
            }
        }
    }
    return diverged;
}
