// clang -O2 -fobjc-arc -framework Foundation -framework ScreenCaptureKit repro.m -o repro
// ./repro 1000        8 threads x 1000 rounds of -setMaximumStreamCount: on the shared picker
// ./repro 5000 warm    control, single-threaded, 5000 x 8 = 40000 sets, five times the cold run
//
// Probe value is a float NSNumber; small-integer NSNumbers are tagged pointers whose no-op retain/release hides the race.
#import <Foundation/Foundation.h>
#import <ScreenCaptureKit/ScreenCaptureKit.h>
#include <objc/message.h>
#import <pthread.h>
#import <stdatomic.h>

#define THREADS 8

static SCContentSharingPicker *picker;
static SEL setSel;
static atomic_int ready, go, done;

static void *worker(void *arg) {
    long i = (long)arg;
    for (;;) {
        int gen = atomic_load(&go);
        atomic_fetch_add(&ready, 1);
        while (atomic_load(&go) == gen) {}
        int r = atomic_load(&go);
        if (r < 0) return NULL;
        @autoreleasepool {
            ((void(*)(id, SEL, id))objc_msgSend)(picker, setSel, [NSNumber numberWithDouble:(double)r * THREADS + i + 0.5]);
        }
        atomic_fetch_add(&done, 1);
    }
}

int main(int argc, char **argv) {
    int rounds = argc > 1 ? atoi(argv[1]) : 1000;
    BOOL warm = argc > 2;
    picker = [SCContentSharingPicker sharedPicker];
    setSel = NSSelectorFromString(@"setMaximumStreamCount:");
    if (warm) {
        for (int r = 0; r < rounds * THREADS; r++) {
            @autoreleasepool {
                ((void(*)(id, SEL, id))objc_msgSend)(picker, setSel, [NSNumber numberWithDouble:r + 0.5]);
            }
        }
        printf("completed %d rounds (%d sets)\n", rounds, rounds * THREADS);
        return 0;
    }
    pthread_t t[THREADS];
    for (long i = 0; i < THREADS; i++) pthread_create(&t[i], NULL, worker, (void *)i);
    for (int r = 1; r <= rounds; r++) {
        @autoreleasepool {
            while (atomic_load(&ready) < THREADS) {}
            atomic_store(&ready, 0);
            atomic_store(&done, 0);
            atomic_store(&go, r);
            while (atomic_load(&done) < THREADS) {}
        }
    }
    while (atomic_load(&ready) < THREADS) {}
    atomic_store(&go, -1);
    for (int i = 0; i < THREADS; i++) pthread_join(t[i], NULL);
    printf("completed %d rounds (%d sets)\n", rounds, rounds * THREADS);
    return 0;
}
