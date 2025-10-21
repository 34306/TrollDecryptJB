/*
Copykat from LowerInstall by Julioverne
*/

#import <objc/runtime.h>
#import <notify.h>
#import <dlfcn.h>
#import <substrate.h>
#import <sys/utsname.h>
#import <Foundation/Foundation.h>

extern const char *__progname;

#define NSLog(...)


static BOOL Enabled = TRUE;

typedef enum {
	kUserAgent=0,
	kUserAgentFormat=1,
	kCurrentDeviceType=2,
	kCurrentiOSVersion=3,
	kSpoofDeviceType=4,
	kSpoofiOSVersion=5,
} LowerInstall_var_Num;

#define MAX_STRING_LEN 30
#define STORED_STRING LowerInstall_var7956

char STORED_STRING[10][MAX_STRING_LEN];
#define StringVal(VALUE_ST) [NSString stringWithUTF8String:STORED_STRING[VALUE_ST]]


%group itunesstoredHooks

%hook NSMutableURLRequest

- (void)setValue:(NSString *)value forHTTPHeaderField:(NSString *)field
{
	if((Enabled && field && value) && [field isEqualToString:StringVal(kUserAgent)]) {
		if([value rangeOfString:StringVal(kCurrentiOSVersion)].location != NSNotFound) {
			value = [value stringByReplacingOccurrencesOfString:[NSString stringWithFormat:StringVal(kUserAgentFormat), StringVal(kCurrentiOSVersion)] withString:[NSString stringWithFormat:StringVal(kUserAgentFormat), StringVal(kSpoofiOSVersion)]];
			value = [value stringByReplacingOccurrencesOfString:[NSString stringWithFormat:StringVal(kUserAgentFormat), StringVal(kCurrentDeviceType)] withString:[NSString stringWithFormat:StringVal(kUserAgentFormat), StringVal(kSpoofDeviceType)]];
		}
	}
	%orig(value, field);
}

%end

%end

%group installdHooks

%hook MIDaemonConfiguration

- (BOOL)skipDeviceFamilyCheck
{
	if(Enabled) {
		return YES;
	}
	return %orig;
}

- (BOOL)skipThinningCheck
{
	if(Enabled) {
		return YES;
	}
	return %orig;
}

%end

%hook MIBundle

- (NSString*)minimumOSVersion
{
	NSString* ret = %orig;
	if(Enabled) {
		ret = @"2.0";
	}
	return ret;
}

- (NSArray *)supportedDevices
{
	NSArray* ret = %orig?:@[];
	if(Enabled && ![ret containsObject:StringVal(kCurrentDeviceType)]) {
		NSMutableArray* retMut = [ret mutableCopy];
		[retMut addObject:StringVal(kCurrentDeviceType)];
		ret = [retMut copy];
	}
	return ret;
}

- (BOOL)isCompatibleWithDeviceFamily:(int)device
{
	if(Enabled) {
		return YES;
	}
	return %orig;
}
- (BOOL)isApplicableToCurrentDeviceFamilyWithError:(id*)error
{
	if(Enabled) {
		return YES;
	}
	return %orig;
}
- (BOOL)isApplicableToCurrentOSVersionWithError:(id*)error
{
	if(Enabled) {
		return YES;
	}
	return %orig;
}
- (BOOL)isApplicableToOSVersion:(id)arg1 error:(id*)error
{
	if(Enabled) {
		return YES;
	}
	return %orig;
}
- (BOOL)isApplicableToCurrentDeviceCapabilitiesWithError:(id*)error
{
	if(Enabled) {
		return YES;
	}
	return %orig;
}
- (BOOL)thinningMatchesCurrentDeviceWithError:(id*)error
{
	if(Enabled) {
		return YES;
	}
	return %orig;
}

- (BOOL)validateAppMetadataWithError:(id*)error
{
	if(Enabled) {
		return YES;
	}
	return %orig;
}

- (BOOL)validatePluginMetadataWithError:(id*)error
{
	if(Enabled) {
		return YES;
	}
	return %orig;
}

%end

%hook MIInstallableBundle

-(BOOL)_validateApplicationIdentifierForNewBundleSigningInfo:(id)arg1 error:(id *)arg2
{
	if(Enabled) {
		return YES;
	}
	return %orig;
}

-(BOOL)_verifyBundleMetadataWithError:(id*)error
{
	if(Enabled) {
		return YES;
	}
	return %orig;
}

-(BOOL)_verifySubBundleMetadataWithError:(id*)error
{
	if(Enabled) {
		return YES;
	}
	return %orig;
}


// wa
-(BOOL)_isValidWatchKitApp:(id)arg1 withVersion:(id)arg2 installableSigningInfo:(id)arg3 error:(id *)arg4
{
	if(Enabled) {
		return YES;
	}
	return %orig;
}


%end


%hook MIExecutableBundle
//wa
- (BOOL)hasOnlyAllowedWatchKitAppInfoPlistKeysForWatchKitVersion:(id)arg1 error:(id*)arg2
{
	if(Enabled) {
		return YES;
	}
	return %orig;
}

%end


%hook MIPluginKitPluginBundle

- (BOOL)validateBundleMetadataWithError:(id*)error
{
	if(Enabled) {
		return YES;
	}
	return %orig;
}

%end


%end

%ctor
{
	bzero(STORED_STRING[kUserAgent], MAX_STRING_LEN);
	strcpy(STORED_STRING[kUserAgent], "User-Agent");
	
	bzero(STORED_STRING[kUserAgentFormat], MAX_STRING_LEN);
	strcpy(STORED_STRING[kUserAgentFormat], "/%@ ");
	
	// Fixed settings: device = iPhone18,2, iOS = 26.0
	bzero(STORED_STRING[kCurrentDeviceType], MAX_STRING_LEN);
	strcpy(STORED_STRING[kCurrentDeviceType], "iPhone18,2");
	
	bzero(STORED_STRING[kCurrentiOSVersion], MAX_STRING_LEN);
	strcpy(STORED_STRING[kCurrentiOSVersion], "26.0");
	
	// Set spoofed values to the same as current (no spoofing needed)
	bzero(STORED_STRING[kSpoofDeviceType], MAX_STRING_LEN);
	strcpy(STORED_STRING[kSpoofDeviceType], "iPhone18,2");
	
	bzero(STORED_STRING[kSpoofiOSVersion], MAX_STRING_LEN);
	strcpy(STORED_STRING[kSpoofiOSVersion], "26.0");

	if(strcmp(__progname, "itunesstored") == 0) {
		%init(itunesstoredHooks);
	} else {
		%init(installdHooks);
	}
}