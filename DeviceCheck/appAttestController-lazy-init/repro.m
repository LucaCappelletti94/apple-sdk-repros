// clang -O2 -fobjc-arc -framework Foundation -framework DeviceCheck repro.m -o repro
// ./repro 1000        8 threads call -isSupported at the same moment on a fresh DCAppAttestService each round
// ./repro 5000 warm    control: the same harness, but each round's controller is created before the threads start
//
// +[DCAppAttestService sharedService] (and `new`, used here to get a fresh
// instance each round) returns an object whose -appAttestController getter
// creates its controller lazily with a plain load, store and release of
// the old value, no lock, no dispatch_once. Two threads making the first
// call on the same instance at once can both create a controller, with
// one store releasing the controller the other thread is about to use.
//
// Ported unchanged from the objc2.upstreams/safe-device-check session's
// upstream/fb-device-check/race.m.
#import <Foundation/Foundation.h>
#import <DeviceCheck/DeviceCheck.h>
#import <pthread.h>
#import <stdatomic.h>

#define THREADS 8
static DCAppAttestService *target;
static atomic_int ready, go, done;

static void *worker(void *arg) {
    (void)arg;
    for (;;) {
        int gen = atomic_load(&go);
        atomic_fetch_add(&ready, 1);
        while (atomic_load(&go) == gen) {}
        if (atomic_load(&go) < 0) return NULL;
        @autoreleasepool {
            (void)[target isSupported];
        }
        atomic_fetch_add(&done, 1);
    }
}

int main(int argc, char **argv) {
    int rounds = argc > 1 ? atoi(argv[1]) : 1000;
    BOOL warm = argc > 2;
    pthread_t t[THREADS];
    for (long i = 0; i < THREADS; i++) pthread_create(&t[i], NULL, worker, NULL);
    for (int r = 1; r <= rounds; r++) {
        @autoreleasepool {
            while (atomic_load(&ready) < THREADS) {}
            atomic_store(&ready, 0);
            atomic_store(&done, 0);
            target = [DCAppAttestService new];
            if (warm) (void)[target isSupported];
            atomic_store(&go, r);
            while (atomic_load(&done) < THREADS) {}
            target = nil;
        }
    }
    while (atomic_load(&ready) < THREADS) {}
    atomic_store(&go, -1);
    for (int i = 0; i < THREADS; i++) pthread_join(t[i], NULL);
    printf("completed %d rounds\n", rounds);
    return 0;
}
