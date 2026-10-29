// Spike agent for build-phase mode: logs where it loaded and, on a real iOS device,
// serves one hello line on 127.0.0.1:39391 so the Mac can reach it through usbmuxd.
#import <Foundation/Foundation.h>
#import <TargetConditionals.h>
#import <netinet/in.h>
#import <os/log.h>
#import <sys/socket.h>

#if TARGET_OS_IPHONE && !TARGET_OS_SIMULATOR
static void desknet_serve(os_log_t log) {
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    int one = 1;
    setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &one, sizeof(one));
    // Loopback only: nothing on the LAN can connect, and no Local Network prompt is expected.
    struct sockaddr_in addr = { .sin_len = sizeof(addr), .sin_family = AF_INET, .sin_port = htons(39391),
                                .sin_addr.s_addr = htonl(INADDR_LOOPBACK) };
    if (bind(fd, (struct sockaddr *)&addr, sizeof(addr)) || listen(fd, 4)) {
        os_log(log, "listen failed errno=%d", errno);
        close(fd);
        return;
    }
    os_log(log, "listening 127.0.0.1:39391");
    fprintf(stderr, "DesknetAgent listening 127.0.0.1:39391\n");
    static dispatch_source_t source;
    source = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, fd, 0, dispatch_get_global_queue(QOS_CLASS_UTILITY, 0));
    dispatch_source_set_event_handler(source, ^{
        int client = accept(fd, NULL, NULL);
        if (client < 0) return;
        NSString *line = [NSString stringWithFormat:@"{\"type\":\"hello\",\"bundleID\":\"%@\",\"pid\":%d,\"bundle\":\"%@\"}\n",
                          NSBundle.mainBundle.bundleIdentifier ?: @"-", getpid(), NSBundle.mainBundle.bundlePath];
        const char *bytes = line.UTF8String;
        write(client, bytes, strlen(bytes));
        close(client);
    });
    dispatch_resume(source);
}
#endif

__attribute__((constructor)) static void desknet_agent_framework_init(void) {
    os_log_t log = os_log_create("DesknetAgent", "load");
    os_log(log, "loaded bundle=%{public}@ path=%{public}@", NSBundle.mainBundle.bundleIdentifier ?: @"-",
           NSBundle.mainBundle.bundlePath);
    // Device logs need root to collect; stderr shows up in `devicectl device process launch --console`.
    fprintf(stderr, "DesknetAgent loaded bundle=%s\n", NSBundle.mainBundle.bundleIdentifier.UTF8String ?: "-");
#if TARGET_OS_IPHONE && !TARGET_OS_SIMULATOR
    desknet_serve(log);
#endif
}
