// clang -O2 -fobjc-arc -framework Foundation repro.m -o repro
// ./repro cold    first call of the process happens inside the 8 racing threads
// ./repro warm    control: getter pre-called once before the threads start
//
// The unguarded slow path of sharedAppleEventManager exists only until the first store,
// so each process gives exactly one trial.
#import <Foundation/Foundation.h>
#import <pthread.h>
#import <stdatomic.h>
#import <string.h>

#define THREADS 8

static atomic_int go;
static void *results[THREADS];

static void *worker(void *arg) {
    long i = (long)arg;
    while (!atomic_load_explicit(&go, memory_order_acquire)) {}
    NSAppleEventManager *manager = [NSAppleEventManager sharedAppleEventManager];
    results[i] = (__bridge_retained void *)manager;
    return NULL;
}

int main(int argc, char **argv) {
    int warm = argc > 1 && strcmp(argv[1], "warm") == 0;
    int cold = argc > 1 && strcmp(argv[1], "cold") == 0;
    if (!warm && !cold) {
        fprintf(stderr, "usage: repro cold|warm\n");
        return 2;
    }
    @autoreleasepool {
        if (warm) {
            (void)[NSAppleEventManager sharedAppleEventManager];
        }
        pthread_t t[THREADS];
        for (int i = 0; i < THREADS; i++) {
            if (pthread_create(&t[i], NULL, worker, (void *)(long)i) != 0) {
                fprintf(stderr, "pthread_create failed\n");
                return 2;
            }
        }
        atomic_store_explicit(&go, 1, memory_order_release);
        for (int i = 0; i < THREADS; i++) pthread_join(t[i], NULL);

        int diverged = 0;
        for (int i = 1; i < THREADS; i++) {
            if (results[i] != results[0]) {
                diverged++;
                printf("thread %d got %p, thread 0 got %p\n", i, results[i], results[0]);
            }
        }
        if (diverged > 0) {
            printf("DIVERGENCE: %d of %d threads got a different pointer than thread 0\n", diverged, THREADS);
            return 1;
        }
        printf("%s: all %d threads got the same pointer %p\n", warm ? "warm" : "cold", THREADS, results[0]);
    }
    return 0;
}
