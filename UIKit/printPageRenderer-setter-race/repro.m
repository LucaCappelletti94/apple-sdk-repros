// clang -O2 -fobjc-arc -target arm64-apple-ios17.0-macabi \
//   -isysroot /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX27.0.sdk -iframework /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX27.0.sdk/System/iOSSupport/System/Library/Frameworks \
//   -framework Foundation -framework UIKit repro.m -o repro
//
// ./repro 10000       8 threads race -[UIPrintInteractionController setPrintPageRenderer:] on the shared instance, fresh value per round
// ./repro 50000 warm  control: the same sets run single-threaded
//
// The shared instance is resolved once, before the threads start; only the setter call inside the loop is the race.
#import <Foundation/Foundation.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <pthread.h>
#import <stdatomic.h>

#define THREADS 8

static id target;
static SEL set_sel;
static atomic_int ready, go, done;

static id shared_print_controller(void) {
    Class c = NSClassFromString(@"UIPrintInteractionController");
    if (c == Nil) {
        fprintf(stderr, "UIPrintInteractionController not found in the loaded images\n");
        exit(2);
    }
    return ((id (*)(id, SEL))objc_msgSend)(c, NSSelectorFromString(@"sharedPrintController"));
}

static void set_renderer(id value) {
    ((void (*)(id, SEL, id))objc_msgSend)(target, set_sel, value);
}

static void *worker(void *arg) {
    (void)arg;
    for (;;) {
        int gen = atomic_load(&go);
        atomic_fetch_add(&ready, 1);
        while (atomic_load(&go) == gen) {}
        if (atomic_load(&go) < 0) return NULL;
        @autoreleasepool {
            set_renderer([[NSObject alloc] init]);
        }
        atomic_fetch_add(&done, 1);
    }
}

int main(int argc, char **argv) {
    int rounds = argc > 1 ? atoi(argv[1]) : 1000;
    BOOL warm = argc > 2;
    target = shared_print_controller();
    set_sel = NSSelectorFromString(@"setPrintPageRenderer:");
    if (warm) {
        for (int r = 0; r < rounds; r++)
            @autoreleasepool {
                set_renderer([[NSObject alloc] init]);
            }
        printf("completed %d rounds\n", rounds);
        return 0;
    }
    pthread_t t[THREADS];
    for (long i = 0; i < THREADS; i++) pthread_create(&t[i], NULL, worker, NULL);
    for (int r = 1; r <= rounds; r++) {
        while (atomic_load(&ready) < THREADS) {}
        atomic_store(&ready, 0);
        atomic_store(&done, 0);
        atomic_store(&go, r);
        while (atomic_load(&done) < THREADS) {}
    }
    while (atomic_load(&ready) < THREADS) {}
    atomic_store(&go, -1);
    for (int i = 0; i < THREADS; i++) pthread_join(t[i], NULL);
    printf("completed %d rounds\n", rounds);
    return 0;
}
