#import <Foundation/Foundation.h>
#import <restage/restage-Swift.h>

// Runs when the binary loads, before main(): earlier than any Dart or plugin code.
@interface RestageEarlyLoader : NSObject
@end

@implementation RestageEarlyLoader
+ (void)load {
  [RestageEarlyRequest start];
}
@end
