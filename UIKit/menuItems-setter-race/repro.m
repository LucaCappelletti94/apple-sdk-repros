// UIKit links on the Mac only from the SDK's iOSSupport slice.
// clang -O2 -fobjc-arc -target arm64-apple-ios17.0-macabi -isysroot /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX27.0.sdk -iframework /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX27.0.sdk/System/iOSSupport/System/Library/Frameworks -framework Foundation -framework UIKit repro.m -o repro
// ./repro 1000        8 threads each call setMenuItems: 1000 times with a fresh value
// ./repro 5000 warm   control: 5000 sequential single-threaded sets
#import <Foundation/Foundation.h>
#import <objc/message.h>
#import <pthread.h>

#define THREADS 8

static void *target;
static SEL setter;

static void *worker(void *arg) {
    int rounds = *(int *)arg;
    for (int i = 0; i < rounds; i++) {
        id value = [NSObject new];
        ((void (*)(id, SEL, id))objc_msgSend)((__bridge id)target, setter, value);
    }
    return NULL;
}

int main(int argc, char **argv) {
    int rounds = argc > 1 ? atoi(argv[1]) : 1000;
    BOOL warm = argc > 2 && strcmp(argv[2], "warm") == 0;

    Class c = NSClassFromString(@"UIMenuController");
    if (c == NULL) {
        fprintf(stderr, "UIMenuController not found\n");
        return 2;
    }
    setter = NSSelectorFromString(@"setMenuItems:");
    // the singleton's own lazy init is not part of this race, so the shared instance is resolved before the threads start
    target = (__bridge_retained void *)((id (*)(id, SEL))objc_msgSend)(c,
                                                                       NSSelectorFromString(@"sharedMenuController"));

    if (warm) {
        for (int i = 0; i < rounds; i++) {
            id value = [NSObject new];
            ((void (*)(id, SEL, id))objc_msgSend)((__bridge id)target, setter, value);
        }
    } else {
        pthread_t t[THREADS];
        for (long i = 0; i < THREADS; i++)
            pthread_create(&t[i], NULL, worker, &rounds);
        for (long i = 0; i < THREADS; i++)
            pthread_join(t[i], NULL);
    }

    CFRelease(target);
    printf("completed %d rounds\n", rounds);
    return 0;
}
