// clang -O2 -fobjc-arc -framework Foundation -framework AppKit repro.m -o repro
// ./repro cold    8 threads make the first call in this process at once; divergent pointers -> exit 1
// ./repro warm    main thread pre-calls alone, then the same 8 race; must always agree
#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <pthread.h>
#import <stdatomic.h>
#import <stdio.h>
#import <string.h>

#define THREADS 8

static void *results[THREADS];
static atomic_int ready, go, done;

static void *worker(void *arg) {
    long i = (long)arg;
    atomic_fetch_add(&ready, 1);
    while (atomic_load(&go) == 0) {}
    @autoreleasepool {
        id obj = [NSDocumentController sharedDocumentController];
        results[i] = (__bridge_retained void *)obj;
    }
    atomic_fetch_add(&done, 1);
    return NULL;
}

int main(int argc, char **argv) {
    if (argc != 2 || (strcmp(argv[1], "cold") != 0 && strcmp(argv[1], "warm") != 0)) {
        fprintf(stderr, "usage: %s cold|warm\n", argv[0]);
        return 2;
    }

    pthread_t t[THREADS];
    for (long i = 0; i < THREADS; i++)
        pthread_create(&t[i], NULL, worker, (void *)i);

    if (strcmp(argv[1], "warm") == 0)
        (void)[NSDocumentController sharedDocumentController];

    while (atomic_load(&ready) < THREADS) {}
    atomic_store(&go, 1);
    while (atomic_load(&done) < THREADS) {}
    for (long i = 0; i < THREADS; i++)
        pthread_join(t[i], NULL);

    int divergent = 0;
    for (long i = 1; i < THREADS; i++)
        if (results[i] != results[0])
            divergent++;

    if (divergent == 0) {
        printf("%s: all %d first-callers returned the same pointer\n", argv[1], THREADS);
        return 0;
    }
    printf("%s: %d of %d first-callers returned a different pointer than the first caller\n",
           argv[1], divergent, THREADS);
    return 1;
}
