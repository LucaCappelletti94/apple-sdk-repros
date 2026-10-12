// clang -O2 -fobjc-arc -framework Foundation -framework LocalAuthentication repro.m -o repro
// ./repro 8 4 3
//   <readers> threads call -biometryType in a loop
//   <writers> threads call -domainState in a loop (its reply writes the cache)
//   <seconds> how long to hammer before reporting
//
// -[LAContext biometryType] and -[LAContext domainState] were disassembled
// (see the gist linked from README.md) with no lock or atomic instruction
// around the shared `_cachedBiometryType` they both touch. This harness
// does not rely on that disassembly holding on every macOS build: it
// swizzles both selectors to record each call's [enter, exit) interval
// per thread, each on its own fresh LAContext, and reports whether any
// reader's interval overlapped any writer's (or a writer overlapped
// another writer), which is direct, dynamic evidence that calls into
// these methods actually run concurrently in this process, regardless of
// whatever locking (or absence of it) is inside them on this build.
//
// A reported overlap is `dynamic-window` strength (see EVIDENCE.md), not
// `fault`: it shows the race window is live, not that anything was
// corrupted. On this process's architecture the cached values are tagged
// pointers, so retain/release inside the race are no-ops either way.
#import <Foundation/Foundation.h>
#import <LocalAuthentication/LocalAuthentication.h>
#import <objc/runtime.h>
#import <pthread.h>
#import <stdatomic.h>

typedef struct {
    uint64_t start;
    uint64_t end;
    BOOL is_write;
} interval_t;

static interval_t *g_intervals;
static atomic_int g_count;
static int g_capacity;
static atomic_int g_go;
static atomic_int g_stop;

static uint64_t now_ns(void) {
    return clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW);
}

static void record(uint64_t start, uint64_t end, BOOL is_write) {
    int i = atomic_fetch_add(&g_count, 1);
    if (i < g_capacity) {
        g_intervals[i] = (interval_t){start, end, is_write};
    }
}

// Swizzled implementations. Each calls the original IMP (captured via the
// method's own selector before swizzling) and records the interval around
// that call, not around anything more than the method itself.
static LABiometryType (*orig_biometryType)(id, SEL);
static LABiometryType swizzled_biometryType(id self, SEL _cmd) {
    uint64_t start = now_ns();
    LABiometryType r = orig_biometryType(self, _cmd);
    record(start, now_ns(), NO);
    return r;
}

static id (*orig_domainState)(id, SEL);
static id swizzled_domainState(id self, SEL _cmd) {
    uint64_t start = now_ns();
    id r = orig_domainState(self, _cmd);
    record(start, now_ns(), YES);
    return r;
}

static void *reader_thread(void *arg) {
    (void)arg;
    while (!atomic_load(&g_go)) {}
    while (!atomic_load(&g_stop)) {
        @autoreleasepool {
            LAContext *ctx = [LAContext new];
            (void)ctx.biometryType;
        }
    }
    return NULL;
}

static void *writer_thread(void *arg) {
    (void)arg;
    while (!atomic_load(&g_go)) {}
    while (!atomic_load(&g_stop)) {
        @autoreleasepool {
            LAContext *ctx = [LAContext new];
            (void)ctx.domainState;
        }
    }
    return NULL;
}

// Sweep-line check for any reader/writer or writer/writer interval overlap.
static int count_overlaps(interval_t *v, int n) {
    // sort by start time, insertion sort is fine at this n
    for (int i = 1; i < n; i++) {
        interval_t key = v[i];
        int j = i - 1;
        while (j >= 0 && v[j].start > key.start) { v[j + 1] = v[j]; j--; }
        v[j + 1] = key;
    }
    int overlaps = 0;
    uint64_t max_write_end = 0;
    for (int i = 0; i < n; i++) {
        if (v[i].is_write && v[i].start < max_write_end) overlaps++;
        if (!v[i].is_write && v[i].start < max_write_end) overlaps++;
        if (v[i].is_write && v[i].end > max_write_end) max_write_end = v[i].end;
    }
    return overlaps;
}

int main(int argc, char **argv) {
    int readers = argc > 1 ? atoi(argv[1]) : 8;
    int writers = argc > 2 ? atoi(argv[2]) : 4;
    int seconds = argc > 3 ? atoi(argv[3]) : 3;

    g_capacity = 2000000;
    g_intervals = malloc(sizeof(interval_t) * (size_t)g_capacity);

    Method m1 = class_getInstanceMethod([LAContext class], @selector(biometryType));
    orig_biometryType = (LABiometryType(*)(id, SEL))method_getImplementation(m1);
    method_setImplementation(m1, (IMP)swizzled_biometryType);

    Method m2 = class_getInstanceMethod([LAContext class], @selector(domainState));
    orig_domainState = (id(*)(id, SEL))method_getImplementation(m2);
    method_setImplementation(m2, (IMP)swizzled_domainState);

    pthread_t t[256];
    int n = 0;
    for (int i = 0; i < readers; i++) pthread_create(&t[n++], NULL, reader_thread, NULL);
    for (int i = 0; i < writers; i++) pthread_create(&t[n++], NULL, writer_thread, NULL);

    atomic_store(&g_go, 1);
    sleep((unsigned)seconds);
    atomic_store(&g_stop, 1);
    for (int i = 0; i < n; i++) pthread_join(t[i], NULL);

    int total = atomic_load(&g_count);
    if (total > g_capacity) total = g_capacity;
    int overlaps = count_overlaps(g_intervals, total);

    printf("readers=%d writers=%d seconds=%d calls=%d overlaps=%d\n", readers, writers, seconds, total, overlaps);
    return 0;
}
