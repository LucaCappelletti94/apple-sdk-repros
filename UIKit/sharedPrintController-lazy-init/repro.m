// clang -O2 -fobjc-arc -target arm64-apple-ios17.0-macabi -isysroot /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX27.0.sdk -iframework /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX27.0.sdk/System/iOSSupport/System/Library/Frameworks -framework Foundation -framework UIKit repro.m -o repro
//
// ./repro cold    8 threads race the very first +[UIPrintInteractionController sharedPrintController] call in this process
// ./repro warm    control: the getter is pre-called once before the threads start
//
// The getter's unguarded slow path runs exactly once per process, so each invocation is one trial.
// Resolved through the ObjC runtime: the implementation lives in the PrintKitUI binary, not in a header this harness may rely on.
#import <Foundation/Foundation.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <pthread.h>
#import <stdatomic.h>
#import <string.h>

#define THREADS 8

static atomic_int go;
static void *results[THREADS];

static id shared_print_controller(void) {
    Class c = NSClassFromString(@"UIPrintInteractionController");
    if (c == Nil) {
        fprintf(stderr, "UIPrintInteractionController not found in the loaded images\n");
        exit(2);
    }
    id (*fn)(id, SEL) = (id (*)(id, SEL))objc_msgSend;
    return fn(c, NSSelectorFromString(@"sharedPrintController"));
}

static void *worker(void *arg) {
    long idx = (long)arg;
    while (!atomic_load(&go)) {}
    @autoreleasepool {
        results[idx] = (__bridge_retained void *)shared_print_controller();
    }
    return NULL;
}

int main(int argc, char **argv) {
    if (argc != 2 || (strcmp(argv[1], "cold") != 0 && strcmp(argv[1], "warm") != 0)) {
        fprintf(stderr, "usage: %s cold|warm\n", argv[0]);
        return 2;
    }
    @autoreleasepool {
        if (strcmp(argv[1], "warm") == 0) (void)shared_print_controller();
        pthread_t t[THREADS];
        for (long i = 0; i < THREADS; i++) pthread_create(&t[i], NULL, worker, (void *)i);
        atomic_store(&go, 1);
        for (long i = 0; i < THREADS; i++) pthread_join(t[i], NULL);
        for (long i = 1; i < THREADS; i++) {
            if (results[i] != results[0]) {
                printf("diverged: first callers of +[UIPrintInteractionController sharedPrintController] returned different objects\n");
                return 1;
            }
        }
        printf("%s: all 8 threads agree\n", argv[1]);
        return 0;
    }
}
