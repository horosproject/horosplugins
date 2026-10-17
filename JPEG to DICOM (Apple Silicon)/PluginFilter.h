// Minimal declaration of Horos' PluginFilter base class.
// The real class lives in the Horos executable; we link with -bundle_loader.
// Non-fragile ivars mean we don't need its ivar layout as long as we don't touch them.

#import <Cocoa/Cocoa.h>

@interface PluginFilter : NSObject
- (void)initPlugin;
- (long)filterImage:(NSString *)menuName;
@end
