// clang -O2 -fobjc-arc -framework Foundation -framework ScreenCaptureKit repro.m -o repro
// ./repro cold   8 threads race the first -defaultConfiguration call, each keeping its result
// ./repro warm    control: getter pre-called once, then the 8 threads call it in strict turn
//
// The getter is an unguarded lazy init of an ivar on the shared picker (safety-audit
// ScreenCaptureKit.md) and returns a copy of the cached value. On this build the cached
// generation is invalidated while the cached object still has an external reference, so
// the warm threads capture the pointer without keeping the object and take turns.
// +[SCContentSharingPicker sharedPicker] is dispatch_once-guarded and safe, so it is
// called once, single-threaded, before the race.
#import <Foundation/Foundation.h>
#import <ScreenCaptureKit/ScreenCaptureKit.h>
#import <pthread.h>
#import <stdatomic.h>
#include <stdio.h>
#include <string.h>

#define THREADS 8

static SCContentSharingPicker *picker;
static void *results[THREADS];
static atomic_int ready, go;
static atomic_long turn;
static int warm_mode;

static void *worker(void *arg) {
    long i = (long)arg;
    atomic_fetch_add(&ready, 1);
    while (atomic_load(&go) == 0) {}
    @autoreleasepool {
        if (warm_mode) {
            while (atomic_load(&turn) != i) {}
            results[i] = (__bridge void *)picker.defaultConfiguration;
            atomic_store(&turn, i + 1);
        } else {
            results[i] = (__bridge_retained void *)picker.defaultConfiguration;
        }
    }
    return NULL;
}

int main(int argc, char **argv) {
    if (argc != 2 || (strcmp(argv[1], "cold") != 0 && strcmp(argv[1], "warm") != 0)) {
        fprintf(stderr, "usage: repro cold|warm\n");
        return 2;
    }
    warm_mode = strcmp(argv[1], "warm") == 0;
    @autoreleasepool {
        picker = [SCContentSharingPicker sharedPicker];
        if (warm_mode)
            (void)(__bridge void *)picker.defaultConfiguration;
        pthread_t t[THREADS];
        for (long i = 0; i < THREADS; i++)
            pthread_create(&t[i], NULL, worker, (void *)i);
        while (atomic_load(&ready) < THREADS) {}
        atomic_store(&go, 1);
        for (long i = 0; i < THREADS; i++)
            pthread_join(t[i], NULL);
    }
    for (long i = 0; i < THREADS; i++)
        printf("results[%ld] = %p\n", i, results[i]);
    long diverged = 0;
    for (long i = 1; i < THREADS; i++)
        if (results[i] != results[0])
            diverged++;
    if (diverged > 0) {
        printf("fault: %ld of %ld threads got a different pointer than results[0]\n", diverged, (long)THREADS);
        return 1;
    }
    printf("all %d threads agree\n", THREADS);
    return 0;
}
