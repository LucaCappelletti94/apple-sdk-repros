// clang -O2 -fobjc-arc -framework Foundation -framework QuartzCore repro.m -o repro
// ./repro
//
// +[CAAnimation defaultValueForKey:@"speed"] fills a process-wide static slot
// lazily, with no lock (audit disassembly, QuartzCore.md lines 15-28). The
// cached NSNumber is a small integer, so racing first callers return
// bit-identical tagged pointers and pointer-identity comparison can never
// diverge. The swizzle below records each first caller's [enter, exit)
// interval instead and reports overlaps.
//
// Line format is parsed by scripts/make-race-window-result.sh. writers=0,
// all 8 threads are first callers with no separate writer role. seconds=0,
// the barrier release has no time bound.
#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <pthread.h>
#import <stdatomic.h>

typedef struct {
    uint64_t start;
    uint64_t end;
} interval_t;

static interval_t g_intervals[8];
static atomic_int g_count;
static atomic_int g_go;

static uint64_t now_ns(void) {
    return clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW);
}

static void record(uint64_t start, uint64_t end) {
    int i = atomic_fetch_add(&g_count, 1);
    if (i < 8) {
        g_intervals[i] = (interval_t){start, end};
    }
}

// the interval must bound the original call only, so the recording cost
// never lands inside a measured window
static id (*orig_defaultValueForKey)(id, SEL, id);
static id swizzled_defaultValueForKey(id self, SEL _cmd, id key) {
    uint64_t start = now_ns();
    id r = orig_defaultValueForKey(self, _cmd, key);
    record(start, now_ns());
    return r;
}

static void *first_caller_thread(void *arg) {
    (void)arg;
    while (!atomic_load(&g_go)) {}
    @autoreleasepool {
        (void)[CAAnimation defaultValueForKey:@"speed"];
    }
    return NULL;
}

// insertion sort is fine at n=8
static int count_overlaps(interval_t *v, int n) {
    for (int i = 1; i < n; i++) {
        interval_t key = v[i];
        int j = i - 1;
        while (j >= 0 && v[j].start > key.start) {
            v[j + 1] = v[j];
            j--;
        }
        v[j + 1] = key;
    }
    int overlaps = 0;
    uint64_t max_end = 0;
    for (int i = 0; i < n; i++) {
        if (v[i].start < max_end) overlaps++;
        if (v[i].end > max_end) max_end = v[i].end;
    }
    return overlaps;
}

int main(void) {
    Method m = class_getClassMethod([CAAnimation class], @selector(defaultValueForKey:));
    orig_defaultValueForKey = (id (*)(id, SEL, id))method_getImplementation(m);
    method_setImplementation(m, (IMP)swizzled_defaultValueForKey);

    pthread_t t[8];
    for (int i = 0; i < 8; i++) pthread_create(&t[i], NULL, first_caller_thread, NULL);
    atomic_store(&g_go, 1);
    for (int i = 0; i < 8; i++) pthread_join(t[i], NULL);

    int total = atomic_load(&g_count);
    if (total > 8) total = 8;
    printf("readers=8 writers=0 seconds=0 calls=%d overlaps=%d\n", total, count_overlaps(g_intervals, total));
    return 0;
}
