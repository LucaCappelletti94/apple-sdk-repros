// clang -O2 -fobjc-arc -framework Foundation repro.m -o repro
// ./repro cold    8 threads race the process's first sharedCoercionHandler call
// ./repro warm    control, the getter is pre-called once alone first
// The slot is process-wide and fills once per process, so one invocation
// is exactly one trial. Divergent pointers violate the single-instance
// contract, so the process exits 1 on seeing one.
#import <Foundation/Foundation.h>
#import <pthread.h>
#import <stdatomic.h>

#define THREADS 8
static atomic_int go;
static void *results[THREADS];

static void *worker(void *arg) {
    int idx = (int)(intptr_t)arg;
    while (atomic_load(&go) == 0) {}
    results[idx] = (__bridge_retained void *)[NSScriptCoercionHandler sharedCoercionHandler];
    return NULL;
}

int main(int argc, char **argv) {
    if (argc != 2 || (strcmp(argv[1], "cold") && strcmp(argv[1], "warm"))) {
        fprintf(stderr, "usage: repro cold|warm\n");
        return 2;
    }
    if (strcmp(argv[1], "warm") == 0) (void)[NSScriptCoercionHandler sharedCoercionHandler];
    pthread_t t[THREADS];
    for (int i = 0; i < THREADS; i++) pthread_create(&t[i], NULL, worker, (void *)(intptr_t)i);
    atomic_store(&go, 1);
    for (int i = 0; i < THREADS; i++) pthread_join(t[i], NULL);
    int diff = 0;
    for (int i = 1; i < THREADS; i++)
        if (results[i] != results[0]) diff++;
    if (diff) printf("diverged: %d of %d threads got a different pointer than thread 0\n", diff, THREADS);
    else printf("all %d threads agree on %p\n", THREADS, results[0]);
    for (int i = 0; i < THREADS; i++) CFRelease(results[i]);
    return diff != 0;
}
