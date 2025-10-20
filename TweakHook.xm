#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <rootless.h>

@interface MIBundle : NSObject
- (BOOL)isWatchApp;
@end

static NSString *iosVersion = nil;
static BOOL updatesEnabled = NO;

%group appstoredHooks

%hook NSMutableURLRequest

- (void)setValue:(NSString *)value forHTTPHeaderField:(NSString *)field
{
    if (iosVersion != nil) {
        if (updatesEnabled == YES) {
            if ([field isEqualToString:@"User-Agent"]) {
                // NSLog(@"[TrollDecrypt] Spoofing iOS version: iOS/%@", iosVersion);
                value = [value stringByReplacingOccurrencesOfString:@"iOS/.*? " withString:[NSString stringWithFormat:@"iOS/%@ ", iosVersion] options:NSRegularExpressionSearch range:NSMakeRange(0, [value length])];
            }
        } else {
            if ([[self.URL absoluteString] containsString:@"WebObjects/MZBuy.woa/wa/buyProduct"]) {
                if ([field isEqualToString:@"User-Agent"]) {
                    // NSLog(@"[TrollDecrypt] Spoofing iOS version for buyProduct: iOS/%@", iosVersion);
                    value = [value stringByReplacingOccurrencesOfString:@"iOS/.*? " withString:[NSString stringWithFormat:@"iOS/%@ ", iosVersion] options:NSRegularExpressionSearch range:NSMakeRange(0, [value length])];
                }
            }
        }
    }
    %orig(value, field);
}

%end

%end

%group installdHooks

%hook MIBundle

-(BOOL)_isMinimumOSVersion:(id)arg1 applicableToOSVersion:(id)arg2 requiredOS:(unsigned long long)arg3 error:(id*)arg4
{
    if ([self isWatchApp]) {
        return %orig(arg1, arg2, arg3, arg4);
    }
    // NSLog(@"[TrollDecrypt] installd: arg1: %@ arg2: %@ arg3: %llu", arg1, arg2, arg3);
    if (iosVersion != nil) {
	    return %orig(arg1, iosVersion, arg3, arg4);
    } else {
        return %orig(arg1, arg2, arg3, arg4);
    }
}

// iOS 15.x API
-(BOOL)isMinimumOSVersion:(id)arg1 applicableToOSVersion:(id)arg2 error:(id*)arg3
{
    if ([self isWatchApp]) {
        return %orig(arg1, arg2, arg3);
    }
    // NSLog(@"[TrollDecrypt] installd: arg1: %@ arg2: %@ arg3: %llu", arg1, arg2, arg3);
    if (iosVersion != nil) {
        return %orig(arg1, iosVersion, arg3);
    } else {
        return %orig(arg1, arg2, arg3);
    }
}

%end

%end

%ctor {

    // Use our preference file path
    [[NSFileManager defaultManager] setAttributes:@{NSFilePosixPermissions: @(0644)} ofItemAtPath:ROOT_PATH_NS(@"/var/mobile/Library/Preferences/com.trolldecrypt.hook.plist") error:nil];
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:ROOT_PATH_NS(@"/var/mobile/Library/Preferences/com.trolldecrypt.hook.plist")];
    
    // Check if hook is enabled (default: disabled)
    if (![prefs objectForKey:@"hookEnabled"] || ![[prefs objectForKey:@"hookEnabled"] boolValue]) {
        // NSLog(@"[TrollDecrypt] Hook not enabled");
        return;
    }
    
    // Get custom iOS version (default: 99.0.0 if not set)
    iosVersion = [prefs objectForKey:@"iOSVersion"];
    if (iosVersion == nil || [iosVersion length] == 0) {
        iosVersion = @"99.0.0";
    }
    
    // Get updates enabled flag (default: NO)
    updatesEnabled = [[prefs objectForKey:@"updatesEnabled"] boolValue];

    NSLog(@"[TrollDecrypt] Hook enabled - iOS version: %@, updatesEnabled: %d", iosVersion, updatesEnabled);

        %init(appstoredHooks);
        %init(installdHooks);
}

