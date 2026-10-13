// clang -O2 -fobjc-arc -target arm64-apple-ios17.0-macabi -isysroot /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX27.0.sdk -iframework /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX27.0.sdk/System/iOSSupport/System/Library/Frameworks -framework Foundation -framework UIKit repro.m -o repro
// ./repro 1000        8 threads x 1000 rounds of -[UIPrintInteractionController setPrintingItems:] on the shared controller, fresh value each round
// ./repro 5000 warm    control: single-threaded, 5000 sequential sets
// probe is a real NSArray: the property is copy and the setter calls -copyWithZone:, which a plain NSObject does not implement
// the shared instance is resolved once before the threads start, its lazy init being a separate finding; only the setter races here
#import <Foundation/Foundation.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <pthread.h>

#define THREADS 8

static id target;
static SEL set_items_sel;

static void set_items(id items) {
    ((void (*)(id, SEL, id))objc_msgSend)(target, set_items_sel, items);
}

static void *worker(void *arg) {
    long rounds = (long)arg;
    for (long r = 0; r < rounds; r++) {
        @autoreleasepool {
            set_items(@[ [[NSObject alloc] init] ]);
        }
    }
    return NULL;
}

int main(int argc, char **argv) {
    long rounds = argc > 1 ? atol(argv[1]) : 1000;
    BOOL warm = argc > 2;
    @autoreleasepool {
        Class c = NSClassFromString(@"UIPrintInteractionController");
        if (c == Nil) {
            fprintf(stderr, "UIPrintInteractionController not found in the loaded images\n");
            exit(2);
        }
        target = ((id (*)(id, SEL))objc_msgSend)(c, NSSelectorFromString(@"sharedPrintController"));
        if (target == Nil) {
            fprintf(stderr, "+[UIPrintInteractionController sharedPrintController] returned nil\n");
            exit(2);
        }
        set_items_sel = NSSelectorFromString(@"setPrintingItems:");
        if (class_getInstanceMethod(c, set_items_sel) == NULL) {
            fprintf(stderr, "-[UIPrintInteractionController setPrintingItems:] not found\n");
            exit(2);
        }
        if (warm) {
            for (long r = 0; r < rounds; r++) {
                @autoreleasepool {
                    set_items(@[ [[NSObject alloc] init] ]);
                }
            }
        } else {
            pthread_t t[THREADS];
            for (long i = 0; i < THREADS; i++) pthread_create(&t[i], NULL, worker, (void *)rounds);
            for (long i = 0; i < THREADS; i++) pthread_join(t[i], NULL);
        }
        printf("completed %ld rounds\n", rounds);
    }
    return 0;
}
