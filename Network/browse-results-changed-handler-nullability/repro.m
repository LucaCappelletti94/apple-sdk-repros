// clang -O2 -fobjc-arc -framework Foundation -framework Network repro.m -o repro
#import <Foundation/Foundation.h>
#import <Network/Network.h>

#if defined(PROBE_OLD_RESULT) || defined(PROBE_NEW_RESULT)
// With -Werror=nonnull clang rejects this NULL exactly when the header declares the parameter nonnull.
void probe(nw_browser_browse_results_changed_handler_t handler, nw_browse_result_t result) {
#ifdef PROBE_OLD_RESULT
    handler(NULL, result, true);
#else
    handler(result, NULL, true);
#endif
}
#endif

int main(void) {
    @autoreleasepool {
        dispatch_queue_t queue = dispatch_queue_create("repro", DISPATCH_QUEUE_SERIAL);
        __block int added = 0, added_with_null_old = 0, removed = 0, removed_with_null_new = 0, other = 0;

        nw_parameters_t parameters = nw_parameters_create_secure_tcp(NW_PARAMETERS_DISABLE_PROTOCOL, NW_PARAMETERS_DEFAULT_CONFIGURATION);
        nw_listener_t listener = nw_listener_create(parameters);
        nw_listener_set_advertise_descriptor(listener, nw_advertise_descriptor_create_bonjour_service("nonnull-repro", "_nwnullrepro._tcp", NULL));
        nw_listener_set_new_connection_handler(listener, ^(nw_connection_t connection) {
          nw_connection_cancel(connection);
        });
        nw_listener_set_queue(listener, queue);
        nw_listener_start(listener);

        nw_browser_t browser = nw_browser_create(nw_browse_descriptor_create_bonjour_service("_nwnullrepro._tcp", NULL), NULL);
        nw_browser_set_browse_results_changed_handler(browser, ^(nw_browse_result_t old_result, nw_browse_result_t new_result, bool batch_complete) {
          nw_browse_result_change_t changes = nw_browse_result_get_changes(old_result, new_result);
          printf("changes=0x%llx old=%s new=%s batch_complete=%d\n", changes, old_result ? "set" : "NULL", new_result ? "set" : "NULL", batch_complete);
          if (changes & nw_browse_result_change_result_added) {
              added++;
              if (!old_result) added_with_null_old++;
          } else if (changes & nw_browse_result_change_result_removed) {
              removed++;
              if (!new_result) removed_with_null_new++;
          } else {
              other++;
          }
        });
        nw_browser_set_queue(browser, queue);
        nw_browser_start(browser);

        [NSThread sleepForTimeInterval:3.0];
        nw_listener_cancel(listener);
        [NSThread sleepForTimeInterval:3.0];
        nw_browser_cancel(browser);

        __block int a, an, r, rn, o;
        dispatch_sync(queue, ^{
          a = added;
          an = added_with_null_old;
          r = removed;
          rn = removed_with_null_new;
          o = other;
        });
        printf("added=%d added_with_null_old=%d removed=%d removed_with_null_new=%d other=%d\n", a, an, r, rn, o);
        return (an > 0 || rn > 0) ? 1 : 0;
    }
}
