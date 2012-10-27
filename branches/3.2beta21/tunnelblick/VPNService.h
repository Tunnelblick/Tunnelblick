/*
 * Copyright 2011 Jonathan Bullard
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

#import <Cocoa/Cocoa.h>
#import "VPNServiceIntroController.h"
#import "VPNServiceTermsOfServiceController.h"
#import "VPNServiceCreateAccountController.h"
#import "VPNServiceProveController.h"
#import "VPNServiceLoginController.h"
#import "VPNServiceWelcomeController.h"
#import "VPNServiceSorryController.h"

@class MenuController;

@interface VPNService : NSObject {
    
    VPNServiceIntroController          * introScreen;
    VPNServiceTermsOfServiceController * termsOfServiceScreen;
    VPNServiceCreateAccountController  * createAccountScreen;
    VPNServiceProveController          * proveScreen;
    VPNServiceLoginController          * loginScreen;
    VPNServiceWelcomeController        * welcomeScreen;
    VPNServiceSorryController          * sorryScreen;
    
    NSImage                            * captchaImage;
    NSString                           * sessionToken;
    NSString                           * reasonForRegistrationFailure;
    
    NSString                           * emailAddress;
    NSString                           * password;
    NSString                           * baseUrlString;
    NSString                           * tosUrlString;
    BOOL                                 acceptedTermsOfService;
    
    BOOL                                 createAccountScreenCancelNotBackButton;
}

// Used externally by MenuController:
-(void) showRegisterForTunneblickVPNScreen;
-(void) showOnLaunchScreen;

// Used internally by the VPNService classes:

-(void) vpnServiceIntro:         (NSWindowController *) ctl finishedWithChoice: (int) choice;
-(void) vpnServiceTermsOfService:(NSWindowController *) ctl finishedWithChoice: (int) choice;
-(void) vpnServiceCreateAccount: (NSWindowController *) ctl finishedWithChoice: (int) choice;
-(void) vpnServiceProve:         (NSWindowController *) ctl finishedWithChoice: (int) choice;
-(void) vpnServiceWelcome:       (NSWindowController *) ctl finishedWithChoice: (int) choice;
-(void) vpnServiceSorry:         (NSWindowController *) ctl finishedWithChoice: (int) choice;
-(void) vpnServiceLogin:         (NSWindowController *) ctl finishedWithChoice: (int) choice;

-(NSString *)   userExistsAndIsActive:(NSString *) address;
-(NSString *)   checkRegistation;
-(id)           getCaptchaImage;
-(NSString *)   getTermsOfService;
-(NSString *)   reasonForRegistrationFailure;
-(NSImage *)    captchaImage;
-(NSString *)   emailAddress;
-(NSString *)   password;
-(NSString *)   tosUrlString;
-(void)         setEmailAddress:                 (NSString *) s;
-(void)         setPassword:                     (NSString *) s;

@end

#endif