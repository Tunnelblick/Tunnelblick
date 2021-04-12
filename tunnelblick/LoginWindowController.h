/*
 * Copyright 2011 Jonathan K. Bullard. All rights reserved.
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

#include "defines.h"
#import "TBButton.h"

@interface LoginWindowController : NSWindowController <NSWindowDelegate>
{
    IBOutlet NSImageView        * iconIV;
    
    IBOutlet NSTextFieldCell    * mainText;
    
    IBOutlet NSButton           * cancelButton;
    IBOutlet NSButton           * OKButton;
    
    IBOutlet NSTextField        * username;
    IBOutlet NSSecureTextField  * password;
    IBOutlet NSTextField        * visiblePassword;
    IBOutlet NSSecureTextField  * securityToken;
    IBOutlet NSTextField        * visibleSecurityToken;

    IBOutlet NSTextFieldCell    * usernameTFC;
    IBOutlet NSTextFieldCell    * passwordTFC;

    IBOutlet NSButton           * eyeButton;
    IBOutlet NSButton           * securityEyeButton;

    IBOutlet NSButton           * saveUsernameInKeychainCheckbox;
    IBOutlet NSButton           * savePasswordInKeychainCheckbox;
    IBOutlet TBButton           * useSecurityTokenCheckbox;
    IBOutlet NSButton           * alwaysShowLoginWindowCheckbox;

    id                            delegate;

    NSImage                     * eyeNormal;
    NSImage                     * eyeRedSlash;
}

-(id)       initWithDelegate:       (id)            theDelegate;
-(void)     redisplay;

-(IBAction) cancelButtonWasClicked: (id)            sender;
-(IBAction) OKButtonWasClicked:     (id)            sender;
-(IBAction) eyeButtonWasClicked:    (id)            sender;
-(IBAction) securityEyeButtonWasClicked:    (id)            sender;

-(IBAction) saveUsernameInKeychainCheckboxWasClicked: (id) sender;
-(IBAction) useSecurityTokenCheckboxWasClicked: (id) sender;

-(BOOL)     isSaveUsernameInKeychainChecked;
-(BOOL)     isSavePasswordInKeychainChecked;
-(BOOL)     useSecurityTokenChecked;

TBPROPERTY_READONLY(NSTextField *,       username)
TBPROPERTY_READONLY(NSSecureTextField *, password)
TBPROPERTY_READONLY(NSTextField *,       visiblePassword)
TBPROPERTY_READONLY(NSTextField *,       securityToken)

TBPROPERTY_READONLY(NSButton *,    eyeButton)

TBPROPERTY_READONLY(NSButton *,    saveUsernameInKeychainCheckbox)
TBPROPERTY_READONLY(NSButton *,    savePasswordInKeychainCheckbox)
TBPROPERTY_READONLY(NSButton *,    alwaysShowLoginWindowCheckbox)

TBPROPERTY_READONLY(id, delegate)

@end
