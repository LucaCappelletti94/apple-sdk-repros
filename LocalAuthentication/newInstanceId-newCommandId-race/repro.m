// clang -O2 -fobjc-arc -framework Foundation -framework LocalAuthentication counters.m -o counters
// ./counters new 8 3000       threads create LAContext objects through public API
// ./counters direct 16 1000000 threads call +newInstanceId directly
#import <Foundation/Foundation.h>
#import <LocalAuthentication/LocalAuthentication.h>
#import <objc/message.h>
#import <pthread.h>
#import <stdatomic.h>

static BOOL direct;
static int per_thread;
static atomic_int go;

// Private selector, used only to measure how far the counter moved.
static unsigned instance_id(void) {
    return ((unsigned (*)(id, SEL))objc_msgSend)([LAContext class], NSSelectorFromString(@"newInstanceId"));
}

static void *worker(void *arg) {
    (void)arg;
    while (!atomic_load(&go)) {}
    for (int i = 0; i < per_thread; i++) {
        if (direct) {
            (void)instance_id();
        } else {
            @autoreleasepool { (void)[LAContext new]; }
        }
    }
    return NULL;
}

int main(int argc, char **argv) {
    if (argc < 4) {
        fprintf(stderr, "usage: %s new|direct threads iterations\n", argv[0]);
        return 2;
    }
    direct = strcmp(argv[1], "direct") == 0;
    int threads = atoi(argv[2]);
    per_thread = atoi(argv[3]);
    pthread_t t[64];
    unsigned before = instance_id();
    for (int i = 0; i < threads; i++) pthread_create(&t[i], NULL, worker, NULL);
    atomic_store(&go, 1);
    for (int i = 0; i < threads; i++) pthread_join(t[i], NULL);
    unsigned advanced = instance_id() - before - 1;
    unsigned expected = (unsigned)(threads * per_thread);
    printf("%s: expected %u increments, counter advanced %u, lost %u\n", argv[1], expected, advanced, expected - advanced);
    return 0;
}
