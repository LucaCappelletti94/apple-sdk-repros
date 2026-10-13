// UIKit links on the Mac only from the SDK's iOSSupport slice.
// clang -O2 -fobjc-arc -target arm64-apple-ios17.0-macabi -isysroot /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX27.0.sdk -iframework /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX27.0.sdk/System/iOSSupport/System/Library/Frameworks -framework Foundation -framework UIKit repro.m -o repro
//
// ./repro 1000        8 threads hammer -setPrintFormatter: with a fresh NSObject each round
// ./repro 5000 warm    control: the same 5000 sets single-threaded
//
// The setter stores through the unlocked ARC retain-new / load-old / store / release-old
// sequence, so two racing writers each release the same old value. The shared getter is
// already-safe and is resolved once, before the threads start. The class and selectors
// go through the ObjC runtime, matching UIKit/sharedPrintController-lazy-init.
#import <Foundation/Foundation.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <pthread.h>
#import <string.h>

#define THREADS 8

static id target;
static SEL set_selector;
static long rounds;

static void set_formatter(id value) {
    ((void (*)(id, SEL, id))objc_msgSend)(target, set_selector, value);
}

static void *worker(void *arg) {
    (void)arg;
    for (long r = 0; r < rounds; r++) {
        @autoreleasepool {
            set_formatter([[NSObject alloc] init]);
        }
    }
    return NULL;
}

int main(int argc, char **argv) {
    if (argc < 2) {
        fprintf(stderr, "usage: %s rounds [warm]\n", argv[0]);
        return 2;
    }
    rounds = atol(argv[1]);
    int warm = argc > 2 && strcmp(argv[2], "warm") == 0;

    Class c = NSClassFromString(@"UIPrintInteractionController");
    if (c == Nil) {
        fprintf(stderr, "UIPrintInteractionController not found in the loaded images\n");
        return 2;
    }
    target = ((id (*)(id, SEL))objc_msgSend)(c, NSSelectorFromString(@"sharedPrintController"));
    if (target == nil) {
        fprintf(stderr, "+[UIPrintInteractionController sharedPrintController] returned nil\n");
        return 2;
    }
    set_selector = NSSelectorFromString(@"setPrintFormatter:");

    if (warm) {
        for (long r = 0; r < rounds; r++)
            @autoreleasepool {
                set_formatter([[NSObject alloc] init]);
            }
        printf("completed %ld rounds\n", rounds);
        return 0;
    }

    pthread_t t[THREADS];
    for (long i = 0; i < THREADS; i++) pthread_create(&t[i], NULL, worker, (void *)i);
    for (long i = 0; i < THREADS; i++) pthread_join(t[i], NULL);
    printf("completed %ld rounds\n", rounds);
    return 0;
}
