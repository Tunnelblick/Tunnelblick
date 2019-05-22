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

@interface PassphraseWindowController : NSWindowController <NSWindowDelegate>
{
    IBOutlet NSImageView        * iconIV;
    
    IBOutlet NSTextFieldCell    * mainText;
    
    IBOutlet NSButton           * cancelButton;
    IBOutlet NSButton           * OKButton;
    
    IBOutlet NSSecureTextField  * passphrase;
    IBOutlet NSTextField        * visiblePassphrase;

    IBOutlet NSButton           * saveInKeychainCheckbox;
    
    IBOutlet NSButton           * eyeButton;

    id                            delegate;

    NSImage                     * eyeNormal;
    NSImage                     * eyeRedSlash;
}

-(id)           initWithDelegate:       (id)            theDelegate;
-(void)         redisplay;

-(IBAction)     cancelButtonWasClicked: (id)            sender;
-(IBAction)     OKButtonWasClicked:     (id)            sender;
-(IBAction)     eyeButtonWasClicked:    (id)            sender;

-(NSTextField *)passphrase;
-(void)         setPassphrase:          (NSTextField *) newValue;

-(BOOL)         saveInKeychain;

-(id)           delegate;

TBPROPERTY_READONLY(NSTextField *, visiblePassphrase)

TBPROPERTY_READONLY(NSButton *,    eyeButton)

@end
