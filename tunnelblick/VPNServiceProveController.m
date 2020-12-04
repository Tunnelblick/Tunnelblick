/*
 * Copyright 2011, 2012, 2013, 2014 Jonathan K. Bullard. All rights reserved.
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

#import "VPNServiceProveController.h"

#import "VPNServiceDefines.h"

#import "VPNService.h"

#import "MenuController.h"
extern MenuController * gMC;

@interface VPNServiceProveController() // Private methods

-(void)      setTitle:        (NSString *) newTitle ofControl: (id) theControl;
-(NSImage *) captchaImage;
-(void)      setCaptchaImage: (NSImage *)  img;
-(NSTextFieldCell *) captchaTF;

-(NSTextFieldCell *) proveTFC;
-(NSTextFieldCell *) captchaTFC;
-(NSImageView     *) captchaImageView;

-(id)                delegate;

@end

@implementation VPNServiceProveController

-(id) initWithDelegate: (id) theDelegate
{
    if (  ![super initWithWindowNibName:@"VPNServiceProve"]  ) {
        return nil;
    }
    
    delegate = [theDelegate retain];
    id obj = [theDelegate getCaptchaImage];
    if (  ( ! [[obj class] isSubclassOfClass: [NSImage class]] )  ) {
        TBRunAlertPanel(NSLocalizedString(@"Cannot obtain image", @"Window title  VPNService"),
                        obj,
                        nil,nil,nil);
        [self autorelease];
        [gMC activateIgnoringOtherApps];
        return nil;
    }
    
    [self setCaptchaImage: obj];
    
    return self;
}

-(id) restore
{
    if (  captchaImageView  ) {
        id obj = [[self delegate] getCaptchaImage];
        if (  ( ! [[obj class] isSubclassOfClass: [NSImage class]] )  ) {
            TBRunAlertPanel(NSLocalizedString(@"Cannot obtain image", @"Window title  VPNService"),
                            obj,
                            nil,nil,nil);
            [gMC activateIgnoringOtherApps];
            return nil;
        }
        
        [self setCaptchaImage: obj];
        
        [[self captchaImageView] setImage: obj];
        [captchaTF setStringValue: @""];
        return self;
    } else {
        NSLog(@"VPNServiceProveController reload invoked but window is not loaded yet.");
        return nil;
    }
}

-(void) changeCaptchaImage: (NSImage *) theCaptchaImage
{
    if (  captchaImageView  ) {
        [captchaImageView setImage: theCaptchaImage];
        [captchaTF setStringValue: @""];
    } else {
        NSLog(@"VPNServiceProveController changeCaptchaImage invoked but window is not loaded yet.");
    }
}

-(void) awakeFromNib
{
    [[self window] setTitle: NSLocalizedString(@"Prove You are Human", @"Window title  VPNService")];
    
    
    [self setTitle: NSLocalizedString(@"Back"                , @"Button VPNService") ofControl: backButton   ];
    [self setTitle: NSLocalizedString(@"Get Different Image" , @"Button VPNService") ofControl: refreshButton];
    [self setTitle: NSLocalizedString(@"Next"                , @"Button VPNService") ofControl: nextButton   ];
    
    // Move the Refresh button to the middle of the space between the Back and Next buttons
    NSRect backRect = [backButton frame];
    NSRect nextRect = [nextButton frame];
    NSRect refreshRect = [refreshButton frame];
    refreshRect.origin.x = (nextRect.origin.x + backRect.origin.x + backRect.size.width - refreshRect.size.width) / 2;
    [refreshButton setFrame: refreshRect];
    
    [[self proveTFC]         setStringValue: NSLocalizedString(@"Please type the characters in the image and click next.", @"Window text VPNService")];
    [[self captchaTFC]       setStringValue: NSLocalizedString(@"Type the characters above:", @"Window text VPNService")];
    
    [[self captchaImageView] setImage: [self captchaImage]];
    
    [[self window] center];
    [gMC activateIgnoringOtherApps];
    [[self window] makeKeyAndOrderFront: self];
}

// Sets the title for a control, shifting the origin of the control itself to the left, and the origin of other controls to the left or right to accomodate any change in width.
-(void) setTitle: (NSString *) newTitle ofControl: (id) theControl
{
    NSRect oldRect = [theControl frame];
    [theControl setTitle: newTitle];
    [theControl sizeToFit];
    
    NSRect newRect = [theControl frame];
    float widthChange = newRect.size.width - oldRect.size.width;
    NSRect oldPos;
    
    if (   [theControl isEqual: refreshButton]
        || [theControl isEqual: nextButton]  ) {  // Shift the control itself left/right if necessary
        oldPos = [theControl frame];
        oldPos.origin.x = oldPos.origin.x - widthChange;
        [theControl setFrame:oldPos];
    }
}

- (void) dealloc {
    
    [captchaImage release]; captcaImage = nil;
    [delegate release];     delegate = nil;
    
	[super dealloc];
}

- (NSString *) description
{
    return [NSString stringWithFormat:@"%@", [self class]];
}

- (IBAction) nextButtonWasClicked: sender
{
    NSLog(@"value='%@'", [[self captchaTF] stringValue]);
    if (  [[[self captchaTF] stringValue] length] == 0  ) {
        TBRunAlertPanel(NSLocalizedString(@"You Must Type the Characters", @"Window title  VPNService"),
                        NSLocalizedString(@"You must type the characters in the image to proceed.", @"Window text VPNService"),
                        nil,nil,nil);
        [gMC activateIgnoringOtherApps];
       return;
    }
	[[self delegate] vpnServiceProve: self finishedWithChoice: VPNServiceCreateAccountNextChoice];
}

- (IBAction) backButtonWasClicked: sender
{
	[[self delegate] vpnServiceProve: self finishedWithChoice: VPNServiceCreateAccountBackChoice];
}

- (IBAction) refreshButtonWasClicked: sender
{
    id obj = [[self delegate] getCaptchaImage];
    if (  [[obj class] isSubclassOfClass: [NSImage class]]  ) {
        [self changeCaptchaImage: obj]; 
        return;
    }
    TBRunAlertPanel(NSLocalizedString(@"Cannot obtain image", @"Window title  VPNService"),
                    obj,
                    nil,nil,nil);
    [gMC activateIgnoringOtherApps];
}

-(NSString *) captcha
{
    return [captchaTF stringValue];
}

-(NSImage *) captchaImage
{
    return [delegate captchaImage];
}

-(void) setCaptchaImage: (NSImage *) img
{
    if (  captchaImage != img  ) {
        [captchaImage release];
        captchaImage = [img retain];
    }
}

-(NSTextFieldCell *) proveTFC
{
    return [[proveTFC retain] autorelease];
}

-(NSTextFieldCell *) captchaTFC
{
    return [[captchaTFC retain] autorelease];
}

-(NSTextFieldCell *) captchaTF
{
    return [[captchaTF retain] autorelease];
}

-(NSImageView     *) captchaImageView
{
    return [[captchaImageView retain] autorelease];
}

-(id) delegate
{
    return [[delegate retain] autorelease];
}

@end

#endif
