// clang -O2 -fobjc-arc -framework Foundation -framework QuartzCore -framework CoreGraphics repro.m -o repro
// The "color" default is a one-shot process-wide lazy init, so one process is one trial and run.sh retries the cold trial in fresh processes.
#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>
#import <pthread.h>
#import <stdatomic.h>
#import <stdio.h>
#import <string.h>

#define THREADS 8

static id results[THREADS];
static atomic_int go;

static void *worker(void *arg) {
    long i = (long)arg;
    while (atomic_load(&go) == 0) {}
    @autoreleasepool {
        results[i] = [CAEmitterCell defaultValueForKey:@"color"];
    }
    return NULL;
}

int main(int argc, char **argv) {
    if (argc < 2) {
        fprintf(stderr, "usage: repro cold|warm\n");
        return 2;
    }
    @autoreleasepool {
        if (strcmp(argv[1], "warm") == 0) {
            (void)[CAEmitterCell defaultValueForKey:@"color"];
        }
        pthread_t t[THREADS];
        for (long i = 0; i < THREADS; i++) pthread_create(&t[i], NULL, worker, (void *)i);
        atomic_store(&go, 1);
        for (long i = 0; i < THREADS; i++) pthread_join(t[i], NULL);
        long distinct = 0;
        for (long i = 0; i < THREADS; i++) {
            int seen = 0;
            for (long j = 0; j < i; j++) {
                if (results[j] == results[i]) {
                    seen = 1;
                    break;
                }
            }
            if (!seen) distinct++;
        }
        if (distinct > 1) {
            printf("diverged: %ld distinct pointers among %d\n", distinct, THREADS);
            return 1;
        }
        printf("agreed: %d identical pointers (0x%lx)\n", THREADS, (unsigned long)results[0]);
        return 0;
    }
}
