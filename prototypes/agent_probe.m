#import <Foundation/Foundation.h>
#import <notify.h>
#import <os/log.h>
#import <pwd.h>
#import <sys/socket.h>
#import <sys/un.h>
#import <netinet/in.h>
#import <TargetConditionals.h>
__attribute__((constructor)) static void desknet_agent_probe_init(void) {
    os_log_t log = os_log_create("DesknetAgentProbe", "load");
    NSString *path = NSBundle.mainBundle.bundlePath ?: @"-";
    BOOL userApp = [path containsString:@"/Containers/Bundle/Application/"];
    os_log(log, "loaded userApp=%{public}d bundle=%{public}@ process=%{public}s",
           userApp, NSBundle.mainBundle.bundleIdentifier ?: @"-", getprogname());
    NSDictionary *env = NSProcessInfo.processInfo.environment;
    os_log(log, "env SIMULATOR_UDID=%{public}@ SIMULATOR_DEVICE_NAME=%{public}@ SIMULATOR_HOST_HOME=%{public}@",
           env[@"SIMULATOR_UDID"] ?: @"-", env[@"SIMULATOR_DEVICE_NAME"] ?: @"-", env[@"SIMULATOR_HOST_HOME"] ?: @"-");
    // Spike 0.5: does `simctl spawn <udid> notifyutil -p desknet.viewer-started` reach the app?
    static int token;
    uint32_t status = notify_register_dispatch("desknet.viewer-started", &token, dispatch_get_main_queue(), ^(int t) {
        os_log(log, "notify desknet.viewer-started received");
    });
    os_log(log, "notify registered status=%u", status);
    // Spike 0.8: can this process reach the host socket? Sandboxed Mac apps may not.
    NSString *home = env[@"SIMULATOR_HOST_HOME"] ?: @(getpwuid(getuid())->pw_dir);
    NSString *sock = [home stringByAppendingPathComponent:@"Library/Caches/desknet.sock"];
    struct sockaddr_un addr = { .sun_family = AF_UNIX };
    strlcpy(addr.sun_path, sock.fileSystemRepresentation, sizeof(addr.sun_path));
    int fd = socket(AF_UNIX, SOCK_STREAM, 0);
    int rc = connect(fd, (struct sockaddr *)&addr, sizeof(addr));
    os_log(log, "socket path=%{public}@ connect=%d errno=%d sandboxed=%d", sock, rc, rc ? errno : 0,
           env[@"APP_SANDBOX_CONTAINER_ID"] != nil);
    close(fd);
#if !TARGET_OS_SIMULATOR
    // Spike 0.8 fallbacks for sandboxed Mac apps.
    // a) TCP to localhost (needs network.client in the app).
    struct sockaddr_in in = { .sin_len = sizeof(in), .sin_family = AF_INET, .sin_port = htons(39391),
                              .sin_addr.s_addr = htonl(INADDR_LOOPBACK) };
    fd = socket(AF_INET, SOCK_STREAM, 0);
    rc = connect(fd, (struct sockaddr *)&in, sizeof(in));
    os_log(log, "tcp connect=%d errno=%d", rc, rc ? errno : 0);
    close(fd);
    // b) Agent binds a Unix socket in its own home (the container when sandboxed); the host connects in.
    NSString *own = [NSHomeDirectory() stringByAppendingPathComponent:@"tmp/desknet-agent.sock"];
    struct sockaddr_un own_addr = { .sun_family = AF_UNIX };
    strlcpy(own_addr.sun_path, own.fileSystemRepresentation, sizeof(own_addr.sun_path));
    unlink(own_addr.sun_path);
    fd = socket(AF_UNIX, SOCK_STREAM, 0);
    rc = bind(fd, (struct sockaddr *)&own_addr, sizeof(own_addr));
    int lrc = rc ? -1 : listen(fd, 1);
    os_log(log, "own bind path=%{public}@ len=%lu bind=%d listen=%d errno=%d", own,
           (unsigned long)strlen(own_addr.sun_path), rc, lrc, (rc || lrc) ? errno : 0);
    // Left listening so the host side can be tested; spike only.
#endif
}
