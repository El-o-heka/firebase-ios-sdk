/*
 * Copyright 2019 Google
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#import "Firebase/InstanceID/FIRInstanceIDUtilities.h"

#if TARGET_OS_IOS || TARGET_OS_TV
#import <UIKit/UIKit.h>
#endif
#import <sys/utsname.h>

#import <GoogleUtilities/GULUserDefaults.h>
#import "Firebase/InstanceID/FIRInstanceIDConstants.h"
#import "Firebase/InstanceID/FIRInstanceIDLogger.h"
#import "Firebase/InstanceID/Public/FIRInstanceID.h"
#import "FirebaseCore/Sources/Private/FirebaseCoreInternal.h"

// Convert the macro to a string
#define STR_EXPAND(x) #x
#define STR(x) STR_EXPAND(x)

static NSString *const kFIRInstanceIDAPNSSandboxPrefix = @"s_";
static NSString *const kFIRInstanceIDAPNSProdPrefix = @"p_";

/// FIRMessaging Class that responds to the FIRMessaging SDK version selector.
/// Verify at runtime if the class exists and implements the required method.
NSString *const kFIRInstanceIDFCMSDKClassString = @"FIRMessaging";

/// FIRMessaging selector that returns the current FIRMessaging library version.
static NSString *const kFIRInstanceIDFCMSDKVersionSelectorString = @"FIRMessagingSDKVersion";

/// FIRMessaging selector that returns the current device locale.
static NSString *const kFIRInstanceIDFCMSDKLocaleSelectorString = @"FIRMessagingSDKCurrentLocale";

NSString *const kFIRInstanceIDUserDefaultsKeyLocale =
    @"com.firebase.instanceid.user_defaults.locale";  // locale key stored in GULUserDefaults

/// Static values which will be populated once retrieved using
/// |FIRInstanceIDRetrieveEnvironmentInfoFromFirebaseCore|.
static NSString *operatingSystemVersion;
static NSString *hardwareDeviceModel;

#pragma mark - URL Helpers

NSString *FIRInstanceIDRegisterServer() {
  return @"https://fcmtoken.googleapis.com/register";
}

#pragma mark - Time

int64_t FIRInstanceIDCurrentTimestampInSeconds() {
  return (int64_t)[[NSDate date] timeIntervalSince1970];
}

int64_t FIRInstanceIDCurrentTimestampInMilliseconds() {
  return (int64_t)(FIRInstanceIDCurrentTimestampInSeconds() * 1000.0);
}

#pragma mark - App Info

NSString *FIRInstanceIDCurrentAppVersion() {
  NSString *version = [[NSBundle mainBundle] infoDictionary][@"CFBundleShortVersionString"];
  if (![version length]) {
    return @"";
  }
  return version;
}

NSString *FIRInstanceIDBundleIDByRemovingLastPartFrom(NSString *bundleID) {
  NSString *bundleIDComponentsSeparator = @".";

  NSMutableArray<NSString *> *bundleIDComponents =
      [[bundleID componentsSeparatedByString:bundleIDComponentsSeparator] mutableCopy];
  [bundleIDComponents removeLastObject];

  return [bundleIDComponents componentsJoinedByString:bundleIDComponentsSeparator];
}

NSString *FIRInstanceIDAppIdentifier() {
  NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
  if (!bundleID.length) {
    FIRInstanceIDLoggerError(kFIRInstanceIDMessageCodeUtilitiesMissingBundleIdentifier,
                             @"The mainBundle's bundleIdentifier returned '%@'. Bundle identifier "
                             @"expected to be non-empty.",
                             bundleID);
    return @"";
  }
#if TARGET_OS_WATCH
  return FIRInstanceIDBundleIDByRemovingLastPartFrom(bundleID);
#endif
  return bundleID;
}

NSString *FIRInstanceIDFirebaseAppID() {
  return [FIROptions defaultOptions].googleAppID;
}

#pragma mark - Device Info
// Get the device model from Firebase Core's App Environment Util
NSString *FIRInstanceIDDeviceModel() {
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    struct utsname systemInfo;
    if (uname(&systemInfo) == 0) {
      hardwareDeviceModel = [NSString stringWithUTF8String:systemInfo.machine];
    }
  });
  return hardwareDeviceModel;
}

// Get the system version from Firebase Core's App Environment Util
NSString *FIRInstanceIDOperatingSystemVersion() {
#if TARGET_OS_IOS || TARGET_OS_TV
  return [UIDevice currentDevice].systemVersion;
#elif TARGET_OS_OSX || TARGET_OS_WATCH
  return [NSProcessInfo processInfo].operatingSystemVersionString;
#endif
}

BOOL FIRInstanceIDHasLocaleChanged() {
  NSString *lastLocale =
      [[GULUserDefaults standardUserDefaults] stringForKey:kFIRInstanceIDUserDefaultsKeyLocale];
  NSString *currentLocale = FIRInstanceIDCurrentLocale();
  if (lastLocale) {
    if ([currentLocale isEqualToString:lastLocale]) {
      return NO;
    }
  }
  return YES;
}

#pragma mark - Helpers

BOOL FIRInstanceIDIsValidGCMScope(NSString *scope) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
  return [scope compare:kFIRInstanceIDScopeFirebaseMessaging
                options:NSCaseInsensitiveSearch] == NSOrderedSame;
#pragma clang diagnostic pop
}

NSString *FIRInstanceIDStringForAPNSDeviceToken(NSData *deviceToken) {
  NSMutableString *APNSToken = [NSMutableString string];
  unsigned char *bytes = (unsigned char *)[deviceToken bytes];
  for (int i = 0; i < (int)deviceToken.length; i++) {
    [APNSToken appendFormat:@"%02x", bytes[i]];
  }
  return APNSToken;
}

NSString *FIRInstanceIDAPNSTupleStringForTokenAndServerType(NSData *deviceToken, BOOL isSandbox) {
  if (deviceToken == nil) {
    // A nil deviceToken leads to an invalid tuple string, so return nil.
    return nil;
  }
  NSString *prefix = isSandbox ? kFIRInstanceIDAPNSSandboxPrefix : kFIRInstanceIDAPNSProdPrefix;
  NSString *APNSString = FIRInstanceIDStringForAPNSDeviceToken(deviceToken);
  NSString *APNSTupleString = [NSString stringWithFormat:@"%@%@", prefix, APNSString];

  return APNSTupleString;
}

#pragma mark - GCM Helpers

NSString *FIRInstanceIDCurrentGCMVersion() {
  Class versionClass = NSClassFromString(kFIRInstanceIDFCMSDKClassString);
  SEL versionSelector = NSSelectorFromString(kFIRInstanceIDFCMSDKVersionSelectorString);
  if ([versionClass respondsToSelector:versionSelector]) {
    IMP getVersionIMP = [versionClass methodForSelector:versionSelector];
    NSString *(*getVersion)(id, SEL) = (void *)getVersionIMP;
    return getVersion(versionClass, versionSelector);
  }
  return nil;
}

NSString *FIRInstanceIDCurrentLocale() {
  Class localeClass = NSClassFromString(kFIRInstanceIDFCMSDKClassString);
  SEL localeSelector = NSSelectorFromString(kFIRInstanceIDFCMSDKLocaleSelectorString);

  if ([localeClass respondsToSelector:localeSelector]) {
    IMP getLocaleIMP = [localeClass methodForSelector:localeSelector];
    NSString *(*getLocale)(id, SEL) = (void *)getLocaleIMP;
    NSString *fcmLocale = getLocale(localeClass, localeSelector);
    if (fcmLocale != nil) {
      return fcmLocale;
    }
  }

  NSString *systemLanguage = [[NSLocale preferredLanguages] firstObject];
  if (systemLanguage != nil) {
    return systemLanguage;
  }

  if (@available(macOS 10.12, iOS 10.0, *)) {
    return [NSLocale currentLocale].languageCode;
  } else {
    return nil;
  }
}
