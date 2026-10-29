// Swift has no constructor attribute, so this runs the Swift start function on dlopen.
extern void desknet_agent_start(void);
__attribute__((constructor)) static void desknet_agent_init(void) { desknet_agent_start(); }
