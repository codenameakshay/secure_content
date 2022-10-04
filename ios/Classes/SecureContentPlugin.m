#import "SecureContentPlugin.h"
#if __has_include(<secure_content/secure_content-Swift.h>)
#import <secure_content/secure_content-Swift.h>
#else
// Support project import fallback if the generated compatibility header
// is not copied when this plugin is created as a library.
// https://forums.swift.org/t/swift-static-libraries-dont-copy-generated-objective-c-header/19816
#import "secure_content-Swift.h"
#endif

@implementation SecureContentPlugin
+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
  [SwiftSecureContentPlugin registerWithRegistrar:registrar];
}
@end
