// clang -O2 -fobjc-arc -target arm64-apple-ios17.0-macabi -isysroot /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX27.0.sdk -iframework /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX27.0.sdk/System/iOSSupport/System/Library/Frameworks -framework Foundation -framework UIKit repro.m -o repro
// ./repro 1000        8 threads race the setter, 1000 rounds each, fresh probe value per set
// ./repro 5000 warm   single-threaded control, 5000*8 sets, the same total as the cold run
//
// The setter stores through an unlocked retain-new / load-old / store / release-old sequence,
// so two racing setters can each release the same old value.
// Resolved through the ObjC runtime, the implementation lives in the PrintKitUI binary, not in a header.
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <pthread.h>
#import <stdatomic.h>
#include <stdlib.h>
#include <string.h>

#define THREADS 8

static int rounds;
static id target;
static SEL sel;
static void (*setter)(id, SEL, id);
static atomic_int go;

static void *worker(void *arg) {
    long idx = (long)arg;
    while (!atomic_load(&go)) {}
    @autoreleasepool {
        for (long r = 1; r <= rounds; r++) {
            @autoreleasepool {
                setter(target, sel, [NSObject new]);
            }
            // Progress so a crash's raw output shows how far the race got.
            if (r % 50 == 0) printf("thread %ld set %ld\n", idx, r);
        }
    }
    return NULL;
}

int main(int argc, char **argv) {
    rounds = argc > 1 ? atoi(argv[1]) : 1000;
    BOOL warm = argc > 2;
    // Line-buffered so progress lines survive a crash into the recorded raw output.
    setvbuf(stdout, NULL, _IOLBF, 0);

    // Resolved once, uncontested, before any thread starts, so the shared instance's
    // own lazy getter is never in the path being raced, only the setter.
    Class c = NSClassFromString(@"UIPrintInteractionController");
    if (c == Nil) {
        fprintf(stderr, "UIPrintInteractionController not found in the loaded images\n");
        exit(2);
    }
    id (*cls)(id, SEL) = (id (*)(id, SEL))objc_msgSend;
    target = cls(c, NSSelectorFromString(@"sharedPrintController"));
    if (target == nil) {
        fprintf(stderr, "sharedPrintController returned nil\n");
        exit(2);
    }
    sel = NSSelectorFromString(@"setPrintInfo:");
    setter = (void (*)(id, SEL, id))objc_msgSend;

    if (warm) {
        long total = (long)rounds * THREADS;
        @autoreleasepool {
            for (long i = 0; i < total; i++) {
                @autoreleasepool {
                    setter(target, sel, [NSObject new]);
                }
            }
        }
        printf("completed %d rounds (%ld single-threaded sets)\n", rounds, total);
        return 0;
    }

    pthread_t t[THREADS];
    for (long i = 0; i < THREADS; i++) pthread_create(&t[i], NULL, worker, (void *)i);
    atomic_store(&go, 1);
    for (long i = 0; i < THREADS; i++) pthread_join(t[i], NULL);
    printf("completed %d rounds\n", rounds);
    return 0;
}