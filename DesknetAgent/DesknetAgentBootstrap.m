#import <Foundation/Foundation.h>

extern void desknet_agent_start(void);

@interface DesknetAgentBootstrap : NSObject
@end

@implementation DesknetAgentBootstrap
+ (void)load {
    desknet_agent_start();
}
@end
