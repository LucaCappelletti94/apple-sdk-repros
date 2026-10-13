// clang -O2 -fobjc-arc -framework Foundation -framework AppKit repro.m -o repro
// ./repro cold  8 threads race this process's very first +[NSColorPanel sharedColorPanel]
// ./repro warm  same race after one uncontested pre-call populated the slot
//
// The slot's slow path runs once per process, so each process is one trial.
#import <AppKit/AppKit.h>
#import <Foundation/Foundation.h>
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
    while (!atomic_load(&go)) {}
    // bridge_retained keeps each thread's returned panel alive for the compare
    results[i] = (__bridge_retained void *)[NSColorPanel sharedColorPanel];
    atomic_fetch_add(&done, 1);
    return NULL;
}

int main(int argc, char **argv) {
    int warm = 0;
    if (argc != 2 || (strcmp(argv[1], "cold") != 0 && strcmp(argv[1], "warm") != 0)) {
        fprintf(stderr, "usage: repro cold|warm\n");
        return 2;
    }
    warm = strcmp(argv[1], "warm") == 0;
    if (warm) {
        // uncontested first call takes the slow path alone and populates the slot
        (void)[NSColorPanel sharedColorPanel];
    }
    pthread_t t[THREADS];
    for (long i = 0; i < THREADS; i++) pthread_create(&t[i], NULL, worker, (void *)i);
    while (atomic_load(&ready) < THREADS) {}
    atomic_store(&go, 1);
    while (atomic_load(&done) < THREADS) {}
    for (int i = 0; i < THREADS; i++) pthread_join(t[i], NULL);
    for (int i = 1; i < THREADS; i++) {
        if (results[i] != results[0]) {
            printf("diverged at thread %d\n", i);
            return 1;
        }
    }
    printf("no divergence\n");
    return 0;
}
