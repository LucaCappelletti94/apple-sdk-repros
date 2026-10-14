// clang -O2 -fobjc-arc -framework Foundation -framework ScreenCaptureKit repro.m -o repro
// ./repro 30000       8 threads each call setDefaultConfiguration: 30000 times on the shared picker
// ./repro 30000 warm  control: single-threaded, 30000 sequential sets
//
// setDefaultConfiguration: is the standard unlocked ARC strong store with no lock
// (safety-audit ScreenCaptureKit.md line 30). sharedPicker is dispatch_once, called once before the race.
#import <Foundation/Foundation.h>
#import <ScreenCaptureKit/ScreenCaptureKit.h>
#import <objc/message.h>
#import <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define THREADS 8
static SCContentSharingPicker *picker;
static SEL set_sel;

static void *worker(void *arg) {
    int rounds = (int)(long)arg;
    for (int r = 0; r < rounds; r++) {
        @autoreleasepool {
            ((void (*)(id, SEL, id))objc_msgSend)(picker, set_sel,
                                                  [[SCContentSharingPickerConfiguration alloc] init]);
        }
    }
    return NULL;
}

int main(int argc, char **argv) {
    int rounds = argc > 1 ? atoi(argv[1]) : 3000;
    int warm = argc > 2 && strcmp(argv[2], "warm") == 0;
    @autoreleasepool {
        picker = [SCContentSharingPicker sharedPicker];
        set_sel = NSSelectorFromString(@"setDefaultConfiguration:");
        if (warm) {
            for (int r = 0; r < rounds; r++)
                @autoreleasepool {
                    ((void (*)(id, SEL, id))objc_msgSend)(picker, set_sel,
                                                          [[SCContentSharingPickerConfiguration alloc] init]);
                }
        } else {
            pthread_t t[THREADS];
            for (int i = 0; i < THREADS; i++)
                pthread_create(&t[i], NULL, worker, (void *)(long)rounds);
            for (int i = 0; i < THREADS; i++)
                pthread_join(t[i], NULL);
        }
        printf("completed %d rounds\n", rounds);
        return 0;
    }
}
