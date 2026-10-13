// UIKit links on the Mac only from the SDK's iOSSupport slice.
// clang -O2 -fobjc-arc -target arm64-apple-ios17.0-macabi -isysroot <MacOSX.sdk>
//   -iframework <MacOSX.sdk>/System/iOSSupport/System/Library/Frameworks
//   -framework Foundation -framework UIKit repro.m -o repro
// ./repro cold | ./repro warm
// Catalyst's pthread.h has no pthread_barrier, so the release point is an atomic spin.
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <pthread.h>
#import <stdatomic.h>

#define THREADS 8

static void *results[THREADS];
static int caught[THREADS];
static atomic_int arrived;
static char first_exception[256];

static void *worker(void *arg) {
    long i = (long)arg;
    Class c = NSClassFromString(@"UIMenuController");
    SEL s = NSSelectorFromString(@"sharedMenuController");
    atomic_fetch_add(&arrived, 1);
    while (atomic_load(&arrived) < THREADS) {}
    @autoreleasepool {
        @try {
            results[i] = (__bridge_retained void *)((id (*)(id, SEL))objc_msgSend)(c, s);
        } @catch (NSException *e) {
            // the losing thread's -init throws the singleton's own invariant
            caught[i] = 1;
            if (first_exception[0] == '\0') {
                const char *n = [(NSString *)e.name UTF8String];
                const char *r = [e.reason UTF8String];
                snprintf(first_exception, sizeof(first_exception), "%s: %s",
                         n ? n : "unknown", r ? r : "unknown");
            }
        }
    }
    return NULL;
}

int main(int argc, char **argv) {
    int warm = argc > 1 && strcmp(argv[1], "warm") == 0;
    Class c = NSClassFromString(@"UIMenuController");
    SEL s = NSSelectorFromString(@"sharedMenuController");
    if (c == NULL) {
        fprintf(stderr, "UIMenuController not found\n");
        return 2;
    }
    if (warm)
        (void)((id (*)(id, SEL))objc_msgSend)(c, s);
    pthread_t t[THREADS];
    for (long i = 0; i < THREADS; i++)
        pthread_create(&t[i], NULL, worker, (void *)i);
    for (long i = 0; i < THREADS; i++)
        pthread_join(t[i], NULL);

    long distinct = 0;
    for (long i = 0; i < THREADS; i++) {
        int seen = 0;
        for (long j = 0; j < i; j++)
            if (results[i] == results[j]) {
                seen = 1;
                break;
            }
        if (!seen)
            distinct++;
    }
    long ncaught = 0;
    for (long i = 0; i < THREADS; i++) {
        ncaught += caught[i];
        if (results[i] != NULL)
            CFRelease(results[i]);
    }
    printf("%s: distinct=%ld exceptions=%ld\n", warm ? "warm" : "cold", distinct, ncaught);
    if (first_exception[0] != '\0')
        printf("exception: %s\n", first_exception);
    return (distinct > 1 || ncaught > 0) ? 1 : 0;
}
