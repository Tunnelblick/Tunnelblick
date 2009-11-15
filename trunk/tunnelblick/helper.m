/*
 *  Copyright (c) 2005, 2006, 2007, 2008, 2009 Angelo Laub
 *  Contributions by Jonathan K. Bullard
 *
 *  This program is free software; you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License version 2
 *  as published by the Free Software Foundation.
 *
 *  This program is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License
 *  along with this program (see the file COPYING included with this
 *  distribution); if not, write to the Free Software Foundation, Inc.,
 *  59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
 */

#include "TBUserDefaults.h"
#include "helper.h"

// This file contains global variables and common routines

TBUserDefaults * gTbDefaults;

// Returns an escaped version of a string so it can be sent over the management interface
NSString *escaped(NSString *string) {
	NSMutableString * stringOut = [[string mutableCopy] autorelease];
	[stringOut replaceOccurrencesOfString:@"\\" withString:@"\\\\" options:NSLiteralSearch range:NSMakeRange(0, [string length])];
	[stringOut replaceOccurrencesOfString:@"\"" withString:@"\\\"" options:NSLiteralSearch range:NSMakeRange(0, [string length])];
	return stringOut;
}

BOOL useDNSStatus(id connection)
{
	static BOOL useDNS = FALSE;
	NSString *key = [[connection configName] stringByAppendingString:@"useDNS"];
	id status = [gTbDefaults objectForKey:key];
	
	if(status == nil) { // nothing is set, use default value
		useDNS = TRUE;
	} else {
		useDNS = [gTbDefaults boolForKey:key];
	}

	return useDNS;
}

// Returns a string with the version # for Tunnelblick, e.g., "Tunnelbick 3 (3.0b12 build 157)"
NSString * tunnelblickVersion(void)
{
    NSString * TBFullV = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"];
    NSDictionary * TunnelblickV = parseVersion(TBFullV);
    NSString * version      = [NSString stringWithFormat:@"Tunnelblick %@ (%@ build %@)",
                               [TunnelblickV objectForKey:@"major"],
                               TBFullV,
                               [[NSBundle mainBundle] objectForInfoDictionaryKey:@"Build"]
                              ];
    return (version);
}

// Returns a string with the version # for OpenVPN, e.g., "OpenVPN 2 (2.1_rc15)"
NSString * openVPNVersion(void)
{
    NSDictionary * OpenVPNV = getOpenVPNVersion();
    NSString * version      = [NSString stringWithFormat:@"OpenVPN %@ (%@)",
                               [OpenVPNV objectForKey:@"major"],
                               [OpenVPNV objectForKey:@"full"]
                              ];
    return (version);
}

// Returns a dictionary from parseVersion with version info about OpenVPN
NSDictionary * getOpenVPNVersion(void)
{
    //Launch "openvpnstart OpenVPNInfo", which launches openvpn (as root) with no arguments to get info, and put the result into an NSString:
    
    NSTask * task = [[NSTask alloc] init];
    
    NSString * exePath = [[[NSBundle mainBundle] bundlePath] stringByAppendingPathComponent:@"/Contents/Resources/openvpnstart"];
    [task setLaunchPath: exePath];
    
    NSArray  *arguments = [NSArray arrayWithObjects: @"OpenVPNInfo", nil];
    [task setArguments: arguments];
    
    NSPipe * pipe = [NSPipe pipe];
    [task setStandardOutput: pipe];
    
    NSFileHandle * file = [pipe fileHandleForReading];
    
    [task launch];
    
    NSData * data = [file readDataToEndOfFile];
    
    [task release];
    
    NSString * string = [[NSString alloc] initWithData: data encoding: NSUTF8StringEncoding];
    
    // Now extract the version. String should look like "OpenVPN <version> <more-stuff>" with a spaces on the left and right of the version
    
    NSArray * arr = [string componentsSeparatedByString:@" "];
    [string release];
    string = @"Unknown";
    if (  [arr count] > 1  ) {
        if (  [[arr objectAtIndex:0] isEqual:@"OpenVPN"]  ) {
            if (  [[arr objectAtIndex:1] length] < 100  ) {     // No version # should be as long as this arbitrary number!
                string = [arr objectAtIndex:1];
            }
        }
    }

    return (  parseVersion(string)  );
}

// Given a string with a version number, parses it and returns an NSDictionary with full, preMajor, major, preMinor, minor, preSuffix, suffix, and postSuffix fields
//              full is the full version string as displayed by openvpn when no arguments are given.
//              major, minor, and suffix are strings of digits (may be empty strings)
//              The first string of digits goes in major, the second string of digits goes in minor, the third string of digits goes in suffix
//              preMajor, preMinor, preSuffix and postSuffix are strings that come before major, minor, and suffix, and after suffix (may be empty strings)
//              if no digits, everything goes into preMajor
NSDictionary * parseVersion( NSString * string)
{
    NSRange r;
    NSString * s = string;
    
    NSString * preMajor     = @"";
    NSString * major        = @"";
    NSString * preMinor     = @"";
    NSString * minor        = @"";
    NSString * preSuffix    = @"";
    NSString * suffix       = @"";
    NSString * postSuffix   = @"";
    
    r = rangeOfDigits(s);
    if (r.length == 0) {
        preMajor = s;
    } else {
        preMajor = [s substringToIndex:r.location];
        major = [s substringWithRange:r];
        s = [s substringFromIndex:r.location+r.length];
        
        r = rangeOfDigits(s);
        if (r.length == 0) {
            preMinor = s;
        } else {
            preMinor = [s substringToIndex:r.location];
            minor = [s substringWithRange:r];
            s = [s substringFromIndex:r.location+r.length];
            
            r = rangeOfDigits(s);
            if (r.length == 0) {
                preSuffix = s;
             } else {
                 preSuffix = [s substringToIndex:r.location];
                 suffix = [s substringWithRange:r];
                 postSuffix = [s substringFromIndex:r.location+r.length];
            }
        }
    }
    
//NSLog(@"full = '%@'; preMajor = '%@'; major = '%@'; preMinor = '%@'; minor = '%@'; preSuffix = '%@'; suffix = '%@'; postSuffix = '%@'    ",
//      string, preMajor, major, preMinor, minor, preSuffix, suffix, postSuffix);
    return (  [NSDictionary dictionaryWithObjectsAndKeys:   string, @"full",
                                                            preMajor, @"preMajor", major, @"major", preMinor, @"preMinor", minor, @"minor",
                                                            preSuffix, @"preSuffix", suffix, @"suffix", postSuffix, @"postSuffix", nil]  );
}


// Examines an NSString for the first decimal digit or the first series of decimal digits
// Returns an NSRange that includes all of the digits
NSRange rangeOfDigits(NSString * s)
{
    NSRange r1, r2;
    // Look for a digit
    r1 = [s rangeOfCharacterFromSet:[NSCharacterSet decimalDigitCharacterSet] ];
    if ( r1.length == 0 ) {
        
        // No digits, return that they were not found
        return (r1);
    } else {
        
        // r1 has range of the first digit. Look for a non-digit after it
        r2 = [[s substringFromIndex:r1.location] rangeOfCharacterFromSet:[[NSCharacterSet decimalDigitCharacterSet] invertedSet]];
        if ( r2.length == 0) {
           
            // No non-digits after the digits, so return the range from the first digit to the end of the string
            r1.length = [s length] - r1.location;
            return (r1);
        } else {
            
            // Have some non-digits, so the digits are between r1 and r2
            r1.length = r1.location + r2.location - r1.location;
            return (r1);
        }
    }
}

// Takes the same arguments as, and is similar to, NSRunAlertPanel
// DOES NOT BEHAVE IDENTICALLY to NSRunAlertPanel:
//   * Stays on top of other windows
//   * Blocks the runloop
//   * Displays the Tunnelblick icon
//   * If title is nil, "Alert" will be used.
//   * If defaultButtonLabel is nil, "OK" will be used.

int TBRunAlertPanel(NSString * title, NSString * msg, NSString * defaultButtonLabel, NSString * alternateButtonLabel, NSString * otherButtonLabel)
{
    NSMutableDictionary * dict = [[NSMutableDictionary alloc] initWithObjectsAndKeys:
                                  msg,  kCFUserNotificationAlertMessageKey,
                                  [NSURL fileURLWithPath:[[NSBundle mainBundle] pathForResource:@"tunnelblick" ofType: @"icns"]],
                                        kCFUserNotificationIconURLKey,
                                  nil];
    if ( title ) {
        [dict setObject: title
                 forKey: (NSString *)kCFUserNotificationAlertHeaderKey];
    } else {
        [dict setObject: NSLocalizedString(@"Alert", @"Window title")
                 forKey: (NSString *)kCFUserNotificationAlertHeaderKey];
    }
    
    if ( defaultButtonLabel ) {
        [dict setObject: defaultButtonLabel
                 forKey: (NSString *)kCFUserNotificationDefaultButtonTitleKey];
    } else {
        [dict setObject: NSLocalizedString(@"OK", @"Button")
                 forKey: (NSString *)kCFUserNotificationDefaultButtonTitleKey];
    }
    
    if ( alternateButtonLabel ) {
        [dict setObject: alternateButtonLabel
                 forKey: (NSString *)kCFUserNotificationAlternateButtonTitleKey];
    }
    
    if ( otherButtonLabel ) {
        [dict setObject: otherButtonLabel
                 forKey: (NSString *)kCFUserNotificationOtherButtonTitleKey];
    }
    
    SInt32 error;
    CFUserNotificationRef notification;
    CFOptionFlags response;
    
    [NSApp activateIgnoringOtherApps:YES];
    notification = CFUserNotificationCreate(NULL, 0, 0, &error, (CFDictionaryRef) dict);
    
    if(  error || CFUserNotificationReceiveResponse(notification, 0, &response)  ) {
        CFRelease(notification);
        [dict release];
        return NSAlertErrorReturn;     // Couldn't receive a response
    }
    
    CFRelease(notification);
    [dict release];
    
    switch (response & 0x3) {
        case kCFUserNotificationDefaultResponse:
            return NSAlertDefaultReturn;
            
        case kCFUserNotificationAlternateResponse:
            return NSAlertAlternateReturn;
            
        case kCFUserNotificationOtherResponse:
            return NSAlertOtherReturn;
            
        default:
            return NSAlertErrorReturn;
    }
}

// This method is never invoked. It is a place to put strings which are used in the .nib or come from OpenVPN
// They are here so that automated tools that deal with strings (such as the "getstrings" command) will include them.
void localizableStrings(void)
{
    // These strings come from the .nib
    NSLocalizedString(@"OpenVPN Log Output - Tunnelblick",  @"Window title");
    NSLocalizedString(@"Clear log",                         @"Button");
    NSLocalizedString(@"Edit configuration",                @"Button");
    NSLocalizedString(@"Connect",                           @"Button");
    NSLocalizedString(@"Disconnect",                        @"Button");
    NSLocalizedString(@"Automatically connect on launch",   @"Checkbox name");
    NSLocalizedString(@"Set nameserver",                    @"Checkbox name");
    NSLocalizedString(@"Monitor connection",                @"Checkbox name");
    
    // These strings come from OpenVPN and indicate the status of a connection
    NSLocalizedString(@"ADD_ROUTES",    @"Connection status");
    NSLocalizedString(@"ASSIGN_IP",     @"Connection status");
    NSLocalizedString(@"AUTH",          @"Connection status");
    NSLocalizedString(@"CONNECTED",     @"Connection status");
    NSLocalizedString(@"CONNECTING",    @"Connection status");
    NSLocalizedString(@"EXITING",       @"Connection status");
    NSLocalizedString(@"GET_CONFIG",    @"Connection status");
    NSLocalizedString(@"RECONNECTING",  @"Connection status");
    NSLocalizedString(@"SLEEP",         @"Connection status");
    NSLocalizedString(@"WAIT",          @"Connection status");
}
