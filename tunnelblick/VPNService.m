/*
 * Copyright 2011, 2012, 2013, 2014, 2016 Jonathan K. Bullard. All rights reserved.
 *
 *  This file is part of Tunnelblick.
 *
 *  Tunnelblick is free software: you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License version 2
 *  as published by the Free Software Foundation.
 *
 *  Tunnelblick is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License
 *  along with this program (see the file COPYING included with this
 *  distribution); if not, write to the Free Software Foundation, Inc.,
 *  59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
 *  or see http://www.gnu.org/licenses/.
 */


#import "defines.h"

#ifdef INCLUDE_VPNSERVICE

#import "VPNService.h"

#import "VPNServiceDefines.h"

#import "KeyChain.h"
#import "MenuController.h"
#import "NSApplication+LoginItem.h"
#import "TBUserDefaults.h"
#import "VPNServiceCreateAccountController.h"
#import "VPNServiceIntroController.h"
#import "VPNServiceLoginController.h"

extern TBUserDefaults * gTbDefaults;

@interface VPNService()   // Private methods

-(void)       quit;
-(NSString *) encode: (NSString *) s;
-(void)       closeAllScreens;

-(id)         getImageFrom:         (NSString *) url;
-(NSString *) registerWithService;
-(NSString *) getResponseFrom:      (NSString *) url;

-(void)       setCaptchaImage:                 (NSImage *) img;
-(void)       setReasonForRegistrationFailure: (NSString *) reason;
-(void)       setSessionToken:                 (NSString *) token;
-(void)       storeCredentialsInKeychain;

@end


@implementation VPNService

-(id) init
{
	if (  self = [super init]  ) {
        NSDictionary * infoDict = [((MenuController *)[NSApp delegate]) tunnelblickInfoDictionary];
        
        baseUrlString = [[infoDict objectForKey: @"VPNServiceBaseURL"] retain];
        if (  ! baseUrlString  ) {
            NSLog(@"VPNService init invoked, but 'VPNServiceBaseURL'is not set in Info.plist");
            return nil;
        }
        
        tosUrlString = [[infoDict objectForKey: @"VPNServiceTOSURL"] retain];
        acceptedTermsOfService = FALSE;
        
        if (   [gTbDefaults boolForKey: @"Tunnelblick-keychainHasUsernameAndPassword"]  ) {
            //Get emailAddress and password from Keychain
            KeyChain * usernameKeychain = [[KeyChain alloc] initWithService: @"Tunnelblick-Auth-Tunnelblick" withAccountName: @"username"];
            KeyChain * passwordKeychain = [[KeyChain alloc] initWithService: @"Tunnelblick-Auth-Tunnelblick" withAccountName: @"password"];
            [self setEmailAddress: [usernameKeychain password]];
            [self setPassword:     [passwordKeychain password] ];
            [usernameKeychain release];
            [passwordKeychain release];
        } else {
            [self setEmailAddress: @""];
            [self setPassword:     @""];
        }

        [self closeAllScreens];
    }
    
    return self;
}

-(void) showRegisterForTunneblickVPNScreen
{
    [self closeAllScreens];
    
    createAccountScreenCancelNotBackButton = YES;
    
    if (  ! createAccountScreen  ) {
        createAccountScreen = [[VPNServiceCreateAccountController alloc] initWithDelegate: self cancelButton: createAccountScreenCancelNotBackButton];
    } else {
        [createAccountScreen showCancelButton: createAccountScreenCancelNotBackButton];
    }
    [createAccountScreen showWindow: self];
}

-(void) showOnLaunchScreen
{
    createAccountScreenCancelNotBackButton = NO;
    
    if (   [gTbDefaults boolForKey: @"Tunnelblick-keychainHasUsernameAndPassword"]  ) {
        if (   emailAddress  
            && password
            && ( ! [emailAddress isEqualToString: @""] )
            && ( ! [password     isEqualToString: @""] )  ) {
            if (  [gTbDefaults boolForKey: @"Tunnelblick-lastConnectionSucceeded"]  ) {
                if (  [((MenuController *)[NSApp delegate]) tryToConnect: NSLocalizedString(@"Tunnelblick", @"Window title")]  ) {
                    return;
                }
            }
        } else {
            NSLog(@"Missing email address and/or password from KeyChain. Assuming credentials are not present.");
            [gTbDefaults removeObjectForKey: @"Tunnelblick-keychainHasUsernameAndPassword"];
            [gTbDefaults removeObjectForKey: @"Tunnelblick-lastConnectionSucceeded"];
            [self setEmailAddress: @""];
            [self setPassword:     @""];
        }
    }
    
    if (  [gTbDefaults boolForKey: @"Tunnelblick-keychainHasUsernameAndPassword"]  ) {
        if (  ! loginScreen  ) {
            loginScreen = [[VPNServiceLoginController alloc] initWithDelegate: self quitButton: YES];
        } else {
            [loginScreen showQuitButton: YES];
        }
        [loginScreen showWindow: self];
        return;
    }
    
    if (  ! introScreen  ) {
        introScreen = [[VPNServiceIntroController alloc] initWithDelegate: self];
    }
    [introScreen showWindow: self];
}

-(void) vpnServiceIntro: (NSWindowController *) ctl finishedWithChoice: (int) choice
{
    switch (  choice  ) {
        case VPNServiceIntroCreateAccountChoice:
            if (  ! createAccountScreen  ) {
                createAccountScreen = [[VPNServiceCreateAccountController alloc] initWithDelegate: self cancelButton: createAccountScreenCancelNotBackButton];
            } else {
                [createAccountScreen showCancelButton: createAccountScreenCancelNotBackButton];
            }

            [createAccountScreen showWindow: self];
            [[introScreen window] close];
            break;
            
        case VPNServiceIntroLoginChoice:
            if (  ! loginScreen  ) {
                loginScreen = [[VPNServiceLoginController alloc] initWithDelegate: self quitButton: NO];
            } else {
                [loginScreen showQuitButton: NO];
            }
            [loginScreen showWindow: self];
            [[introScreen window] close];
            break;
            
        case VPNServiceIntroQuitChoice:
            [[introScreen window] close];
            [self quit];
            break;
            
        default:
            NSLog(@"vpnServiceIntro:finishedWithChoice: Invalid choice: %d", (int) choice);
    }
}

-(void) vpnServiceCreateAccount: (NSWindowController *) ctl finishedWithChoice: (int) choice
{
    [self setEmailAddress: [createAccountScreen emailAddress]];
    [self setPassword:     [createAccountScreen password    ]];
    
    switch (  choice  ) {
        case VPNServiceCreateAccountNextChoice:
            if (   acceptedTermsOfService
                || ( ! tosUrlString )  ) {
                id obj;
                if (  ! proveScreen  ) {
                    proveScreen = [[VPNServiceProveController alloc] initWithDelegate: self];
                    obj = proveScreen;
                } else {
                    obj = [proveScreen restore];
                }
                if (  obj != nil  ) {
                    [proveScreen showWindow: self];
                    [[createAccountScreen window] close];
                }
                
            } else {
                if (  ! termsOfServiceScreen  ) {
                    termsOfServiceScreen = [[VPNServiceTermsOfServiceController alloc] initWithDelegate: self];
                } else {
                    [termsOfServiceScreen reloadTermsOfService];
                }
                
                [termsOfServiceScreen showWindow: self];
                [[createAccountScreen window] close];
            }
            
            break;
            
        case VPNServiceCreateAccountBackChoice:
            if (  ! introScreen  ) {
                introScreen = [[VPNServiceIntroController alloc] initWithDelegate: self];
            }
            [introScreen showWindow: self];
            [[createAccountScreen window] close];
            break;
            
        case VPNServiceCreateAccountCancelChoice:
            [[createAccountScreen window] close];
            break;
            
        default:
            NSLog(@"vpnServiceCreateAccount:finishedWithChoice: Invalid choice: %d", (int) choice);
    }
}

-(void) vpnServiceTermsOfService:(NSWindowController *) ctl finishedWithChoice: (int) choice
{
    switch (  choice  ) {
        case VPNServiceTermsOfServiceAcceptChoice:
            acceptedTermsOfService = TRUE;
            id obj;
            if (  ! proveScreen  ) {
                proveScreen = [[VPNServiceProveController alloc] initWithDelegate: self];
                obj = proveScreen;
            } else {
                obj = [proveScreen restore];
            }
            if (  obj != nil  ) {
                [proveScreen showWindow: self];
                [[termsOfServiceScreen window] close];
            }
            break;
            
        case VPNServiceTermsOfServiceRejectChoice:
            acceptedTermsOfService = FALSE;
            if (  ! createAccountScreen  ) {
                createAccountScreen = [[VPNServiceCreateAccountController alloc] initWithDelegate: self cancelButton: createAccountScreenCancelNotBackButton];
            } else {
                [createAccountScreen showCancelButton: createAccountScreenCancelNotBackButton];
            }
            [createAccountScreen showWindow: self];
            [[termsOfServiceScreen window] close];
            break;
            
        default:
            NSLog(@"vpnServiceTermsOfService:finishedWithChoice: Invalid choice: %d", (int) choice);
    }
}


-(void) vpnServiceProve: (NSWindowController *) ctl finishedWithChoice: (int) choice
{
    NSString * result;
    switch (  choice  ) {
        case VPNServiceProveNextChoice:
            result = [self registerWithService];
            if (  result  ) { // Registration failed
                [self setReasonForRegistrationFailure: result];
                if (  ! sorryScreen  ) {
                    sorryScreen = [[VPNServiceSorryController alloc] initWithDelegate: self];
                }
                [sorryScreen showWindow: self];
                [[proveScreen window] close];
            } else { // Registration was OK
                [self storeCredentialsInKeychain];
                if (  ! welcomeScreen  ) {
                    welcomeScreen = [[VPNServiceWelcomeController alloc] initWithDelegate: self];
                }
                [welcomeScreen showWindow: self];
                [[proveScreen window] close];
            }
            break;
            
        case VPNServiceProveBackChoice:
            if (  ! createAccountScreen  ) {
                createAccountScreen = [[VPNServiceCreateAccountController alloc] initWithDelegate: self cancelButton: createAccountScreenCancelNotBackButton];
            } else {
                [createAccountScreen showCancelButton: createAccountScreenCancelNotBackButton];
            }
            [createAccountScreen showWindow: self];
            [[proveScreen window] close];
            break;
            
        default:
            NSLog(@"vpnServiceProve:finishedWithChoice: Invalid choice: %d", (int) choice);
    }
}

-(void) vpnServiceWelcome: (NSWindowController *) ctl finishedWithChoice: (int) choice
{
    switch (  choice  ) {
        case VPNServiceWelcomeNextChoice:
            if (  ! loginScreen  ) {
                loginScreen = [[VPNServiceLoginController alloc] initWithDelegate: self quitButton: YES];
            } else {
                [loginScreen showQuitButton: YES];
            }
            [loginScreen showWindow: self];
            [[welcomeScreen window] close];
            break;
            
        default:
            NSLog(@"vpnServiceWelcome:finishedWithChoice: Invalid choice: %d", (int) choice);
    }
}

-(void) vpnServiceSorry: (NSWindowController *) ctl finishedWithChoice: (int) choice
{
    switch (  choice  ) {
        case VPNServiceSorryBackChoice:
            if (  ! createAccountScreen  ) {
                createAccountScreen = [[VPNServiceCreateAccountController alloc] initWithDelegate: self cancelButton: createAccountScreenCancelNotBackButton];
            } else {
                [createAccountScreen showCancelButton: createAccountScreenCancelNotBackButton];
            }
            [createAccountScreen showWindow: self];
            [[sorryScreen window] close];
            break;
            
        case VPNServiceSorryQuitChoice:
            [[sorryScreen window] close];
            [self quit];
            break;
            
        default:
            NSLog(@"vpnServiceSorry:finishedWithChoice: Invalid choice: %d", (int) choice);
    }
}

-(void) vpnServiceLogin: (NSWindowController *) ctl finishedWithChoice: (int) choice
{
    switch (  choice  ) {
        case VPNServiceLoginLoginChoice:
            [self setEmailAddress: [loginScreen emailAddress]];
            [self setPassword:     [loginScreen password    ]];
            [self storeCredentialsInKeychain];
            if (  [((MenuController *)[NSApp delegate]) tryToConnect: NSLocalizedString(@"Tunnelblick", @"Window title")]  ) {
                [[loginScreen window] close];
            }
            break;
            
        case VPNServiceLoginQuitChoice:
            [[loginScreen window] close];
            [self quit];
            break;
            
        case VPNServiceLoginBackChoice:
            if (  ! introScreen  ) {
                introScreen = [[VPNServiceIntroController alloc] initWithDelegate: self];
            }
            [introScreen showWindow: self];
            [[loginScreen window] close];
            break;
            
        default:
            NSLog(@"vpnServiceLogin:finishedWithChoice: Invalid choice: %d", (int) choice);
    }
}

-(void) storeCredentialsInKeychain
{
    // Store emailAddress and password in Keychain
    KeyChain * usernameKeychain = [[KeyChain alloc] initWithService: @"Tunnelblick-Auth-Tunnelblick" withAccountName: @"username"];
    KeyChain * passwordKeychain = [[KeyChain alloc] initWithService: @"Tunnelblick-Auth-Tunnelblick" withAccountName: @"password"];
    [usernameKeychain deletePassword];
    [usernameKeychain setPassword: emailAddress];
    [passwordKeychain deletePassword];
    [passwordKeychain setPassword: password];
    [usernameKeychain release];
    [passwordKeychain release];
    [gTbDefaults setBool: TRUE forKey: @"Tunnelblick-keychainHasUsernameAndPassword"];
}

// Returns an NSString with the terms of service or an error message explaining why the image could not be obtained
-(NSString *) getTermsOfService
{
    NSString * tos = [self getResponseFrom: tosUrlString];
    if (  ! tos  ) {
        return NSLocalizedString(@"Terms of service are unavailable.", @"Window text VPNService");
    }
    return tos;
}

// Returns an NSImage or an NSString with an error message explaining why the image could not be obtained
-(id) getCaptchaImage
{
    // Check if already registered
    if (  [self checkRegistation]  ) {
        return reasonForRegistrationFailure;
    }

    // Get session token
    NSString * getSessionToken = [NSString stringWithFormat: @"%@/api/s.php", baseUrlString];
    [self setSessionToken: [[self getResponseFrom: getSessionToken] retain]];
    if (  ! sessionToken  ) {
        return NSLocalizedString(@"Could not get a session token", @"Window text VPNService");
    }
    if (  [sessionToken length] > 100  ) {
        return NSLocalizedString(@"Session token too long", @"Window text VPNService");
    }
    if (  ! [[self encode: sessionToken] isEqualToString: sessionToken] ) {
        return NSLocalizedString(@"Session token requires encoding", @"Window text VPNService");
    }
    
    // Get captcha image
    NSString * getCaptchaURL = [NSString stringWithFormat: @"%@/api/c.php?sid=%@", baseUrlString, sessionToken];
    [self setCaptchaImage: [self getImageFrom: getCaptchaURL]];
    if (  ! captchaImage  ) {
        return NSLocalizedString(@"Could not get a captcha image", @"Window text VPNService");
    }
    
    return [[captchaImage retain] autorelease];
}

// Returns nil if registration is OK, otherwise returns an error message
-(NSString *) checkRegistation
{
    NSString * encodedEmailAddress = [self encode: [self emailAddress]];
    
    NSString * checkRegistrationURL = [NSString stringWithFormat: @"%@/api/q.php?u=%@", baseUrlString, encodedEmailAddress];
    NSString * registrationResponse = [self getResponseFrom: checkRegistrationURL];
    
    if (  [registrationResponse hasPrefix: @"OK"]  ) {
        [self setReasonForRegistrationFailure: nil];
    } else if (  [registrationResponse hasPrefix: @"USER_EXISTS"]  ) {
        [self setReasonForRegistrationFailure: [NSString stringWithFormat: NSLocalizedString(@"Email address %@ is already registered for an account", @"Window text VPNService"), [self emailAddress]]];
    } else {
        [self setReasonForRegistrationFailure: [NSString stringWithFormat: NSLocalizedString(@"Unable to check account status:\n     %@", @"Window text VPNService"), registrationResponse]];
    }
    
    return [[reasonForRegistrationFailure retain] autorelease];
}    

// Returns nil if registered OK, otherwise a localized string with the reason registration failed
-(NSString *) registerWithService
{
    NSString * captcha = [proveScreen captcha];
    
    NSString * encodedEmailAddress = [self encode: emailAddress];
    NSString * encodedPassword     = [self encode: password];
    NSString * encodedCaptcha      = [self encode: captcha];
    
    NSString * encodedVersion = [self encode: tunnelblickVersion([NSBundle mainBundle])];
    
    NSString * getRegisteredURL = [NSString stringWithFormat: @"%@/api/register.php?code=%@&sid=%@&email=%@&password=%@&tos=%@&client=mac&version=%@",
                                   baseUrlString,
                                   encodedCaptcha,
                                   sessionToken,
                                   encodedEmailAddress,
                                   encodedPassword,
                                   (tosUrlString ? @"yes" : @"no"),
                                   encodedVersion];
    
    NSString * registration = [self getResponseFrom: getRegisteredURL];
    if (  ! registration  ) {
        return NSLocalizedString(@"Could not check registration", @"Window text VPNService");
    }
    if (  [registration hasPrefix: @"OK"]  ) {
        return nil;
    }
    if (  [registration hasPrefix: @"error:captcha"]  ) {
        return NSLocalizedString(@"The text you entered did not match the text in the Captcha image.", @"Window text VPNService");
    }
    if (  [registration hasPrefix: @"error:invalid_email"]  ) {
        return NSLocalizedString(@"The email address you entered was not a valid email address.", @"Window text VPNService");
    }
    if (  [registration hasPrefix: @"error:no_sid_provided"]  ) {
        return NSLocalizedString(@"No valid session token.", @"Window text VPNService");
    }
    if (  [registration hasPrefix: @"error:user_exists_pending"]  ) {
        return NSLocalizedString(@"You have already registered but not yet confirmed your email address.", @"Window text VPNService");
    }
    if (  [registration hasPrefix: @"error:user_exists"]  ) {
        return NSLocalizedString(@"You have already registered.", @"Window text VPNService");
    }
    return registration;
}

-(NSString *) userExistsAndIsActive:(NSString *) address
{
    // Check registration of email address
    if (  ! emailAddress) {
        return NSLocalizedString(@"Unable to check registration for empty email address", @"Window text VPNService");
    }
    NSString * encodedEmailAddress = [self encode: address];
    NSString * checkRegistrationURL = [NSString stringWithFormat: @"%@/api/q.php?u=%@", baseUrlString, encodedEmailAddress];
    NSString * checkRegistration = [self getResponseFrom: checkRegistrationURL];
    if (  ! checkRegistration  ) {
        return NSLocalizedString(@"Could not check registration", @"Window text VPNService");
    }
    if (  [checkRegistration hasPrefix: @"USER_EXISTS"]  ) {
        return @"YES"; // DO NOT localize!
    }
    if (  [checkRegistration hasPrefix: @"OK"]  ) {
        return @"NO"; // DO NOT localize!
    }
    return checkRegistration;
}

-(NSString *) getResponseFrom: (NSString *) url
{
    NSData        * urlData;
    NSURLResponse * urlResponse;
    NSError       * urlError = [NSError errorWithDomain: NSURLErrorDomain code: 0 userInfo: nil];
    
    NSURL * realURL = [NSURL URLWithString: url];
    if (  ! realURL  ) {
        return [NSString stringWithFormat: NSLocalizedString(@"Invalid URL: %@", @"Window text VPNService"), url];
    }
    
    NSURLRequest * urlRequest = [NSURLRequest requestWithURL: realURL
                                                 cachePolicy: NSURLRequestReloadIgnoringLocalAndRemoteCacheData
                                             timeoutInterval: 30.0];
    
    urlData = [NSURLConnection sendSynchronousRequest: urlRequest
                                    returningResponse: &urlResponse
                                                error: &urlError];
    if (  [urlData length] == 0  ) {
        return NSLocalizedString(@"Unable to connect to server", @"Window text VPNService");
    }
    
    const char * bytes = [urlData bytes];
    NSString * responseString = [[[NSString alloc] initWithBytes: bytes
                                                          length: strlen(bytes) encoding: NSUTF8StringEncoding]
                                 autorelease];
    return responseString;
}

-(id) getImageFrom: (NSString *) url
{
    NSData        * urlData;
    NSURLResponse * urlResponse;
    NSError       * urlError;
    
    NSURL * realURL = [NSURL URLWithString: url];
    if (  ! realURL  ) {
        return [NSString stringWithFormat: NSLocalizedString(@"Invalid URL: %@", @"Window text VPNService"), url];
    }
    NSURLRequest * urlRequest = [NSURLRequest requestWithURL: realURL
                                                 cachePolicy: NSURLRequestReloadIgnoringLocalAndRemoteCacheData
                                             timeoutInterval: 30.0];
    
    urlData = [NSURLConnection sendSynchronousRequest: urlRequest
                                    returningResponse: &urlResponse
                                                error: &urlError];
    if (  ! urlData  ) {
        return NSLocalizedString(@"Unable to connect to server", @"Window text VPNService");
    }
    
    NSImage * responseImage = [[[NSImage alloc] initWithData: urlData] autorelease];
    return responseImage;
}

-(NSString *) encode:(NSString *)s
{
    NSString *result = (NSString *) CFURLCreateStringByAddingPercentEscapes(kCFAllocatorDefault,
                                                                            (CFStringRef) s,
                                                                            NULL,
                                                                            CFSTR("?=&+"),
                                                                            kCFStringEncodingUTF8);
    return [result autorelease];
}

-(void) quit
{
    [((MenuController *)[NSApp delegate]) terminateBecause: terminatingBecauseOfQuit];
}

-(void) closeAllScreens
{
    if (  introScreen           ) [introScreen          close];
    if (  termsOfServiceScreen  ) [termsOfServiceScreen close];
    if (  createAccountScreen   ) [createAccountScreen  close];
    if (  proveScreen           ) [proveScreen          close];
    if (  loginScreen           ) [loginScreen          close];
    if (  welcomeScreen         ) [welcomeScreen        close];
    if (  sorryScreen           ) [sorryScreen          close];
}

-(void) dealloc
{
    [introScreen                    release]; introScreen                  = nil;
    [termsOfServiceScreen           release]; termsOfServiceScreen         = nil;
    [createAccountScreen            release]; createAccountScreen          = nil;
    [loginScreen                    release]; loginScreen                  = nil;
    [proveScreen                    release]; proveScreen                  = nil;
    [welcomeScreen                  release]; welcomeScreen                = nil;
    [sorryScreen                    release]; sorryScreen                  = nil;
    
    [captchaImage                   release]; captchaImage                 = nil;
    [sessionToken                   release]; sessionToken                 = nil;
    [reasonForRegistrationFailure   release]; reasonForRegistrationFailure = nil;

    [emailAddress                   release]; emailAddress                 = nil;
    [password                       release]; password                     = nil;
    [baseUrlString                  release]; baseUrlString                = nil;
    [tosUrlString                   release]; tosUrlString                 = nil;
    
    [super dealloc];
}

-(void) setSessionToken: (NSString *) token
{
    if (  sessionToken != token  ) {
        [sessionToken release];
        sessionToken = [token retain];
    }
}

-(NSString *) reasonForRegistrationFailure
{
    return [[reasonForRegistrationFailure retain] autorelease];
}

-(void) setReasonForRegistrationFailure: (NSString *) reason
{
    if (  reasonForRegistrationFailure != reason  ) {
        [reasonForRegistrationFailure release];
        reasonForRegistrationFailure = [reason retain];
    }
}

-(NSImage *) captchaImage
{
    return [[captchaImage retain] autorelease];
}

-(void) setCaptchaImage: (NSImage *) img
{
    if (  captchaImage != img  ) {
        [captchaImage release];
        captchaImage = [img retain];
    }
}

-(NSString *) emailAddress
{
    return [[emailAddress retain] autorelease];
}

-(void) setEmailAddress: (NSString *) s
{
    if (  emailAddress != s  ) {
        [emailAddress release];
        emailAddress = [s retain];
    }
}

-(NSString *) password
{
    return [[password retain] autorelease];
}

-(void) setPassword: (NSString *) s
{
    if (  password != s  ) {
        [password release];
        password = [s retain];
    }
}

-(NSString *)   tosUrlString
{
    return [[tosUrlString retain] autorelease];
}

-(id) delegate
{
    return nil;
}

@end

#endif
