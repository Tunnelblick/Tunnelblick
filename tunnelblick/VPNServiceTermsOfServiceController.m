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

#import "VPNServiceTermsOfServiceController.h"

#import "VPNServiceDefines.h"

#import "VPNService.h"

#import "MenuController.h"
extern MenuController * gMC;

@interface VPNServiceTermsOfServiceController() // Private methods

-(NSTextFieldCell *) termsOfServiceHeaderTFC;
-(WebView *)         termsOfServiceWV;

-(void)              setTitle: (NSString *) newTitle ofControl: (id) theControl;

-(id)                delegate;

@end

@implementation VPNServiceTermsOfServiceController

-(id) initWithDelegate: (id) theDelegate
{
    if (  ![super initWithWindowNibName:@"VPNServiceTermsOfService"]  ) {
        return nil;
    }
        
    delegate = [theDelegate retain];
    
    return self;
}

-(void) reloadTermsOfService
{
    [acceptButton setEnabled: NO];
    [progressIndicator startAnimation: self];
    [termsOfServiceWV setMainFrameURL: [delegate tosUrlString]];
    [termsOfServiceWV setFrameLoadDelegate: self];
}

-(void) awakeFromNib
{
    [[self window] setTitle: NSLocalizedString(@"Terms of Service", @"Window title  VPNService")];
    
    [self setTitle: NSLocalizedString(@"Accept" , @"Button VPNService") ofControl: acceptButton ];
    [self setTitle: NSLocalizedString(@"Reject", @"Button VPNService") ofControl: rejectButton ];
    
    [[self termsOfServiceHeaderTFC] setStringValue: NSLocalizedString(@"Please read our Terms of Service and indicate"
                                                                      " your acceptance or rejection of them.", @"Window text VPNService")];
    tosFrameStartCount = 1;
    [self reloadTermsOfService];
    
    [acceptButton setEnabled: NO];
    
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
    
    if (   [theControl isEqual: acceptButton ]
        || [theControl isEqual: rejectButton]  ) {  // Shift the control itself left/right if necessary
        oldPos = [theControl frame];
        oldPos.origin.x = oldPos.origin.x - widthChange;
        [theControl setFrame:oldPos];
    }
    
    if (  [theControl isEqual: acceptButton]  ) {   // Shift the reject button if the accept button changes
        oldPos = [rejectButton frame];
        oldPos.origin.x = oldPos.origin.x - widthChange;
        [rejectButton setFrame:oldPos];
    }
}

-(void) webView: (WebView *) wv didStartProvisionalLoadForFrame: (WebFrame *) wf
{
    tosFrameStartCount++;
}

-(void)webView: (WebView *) wv didFinishLoadForFrame: (WebFrame *) wf
{
    tosFrameStartCount--;
    if (  tosFrameStartCount == 0  ) {
        [progressIndicator stopAnimation: self];
        [acceptButton setEnabled: YES];
    }
}

-(void)webView: (WebView *) wv didFailProvisionalLoadWithError: (NSError *) error forFrame: (WebFrame *) wf
{
    TBRunAlertPanel(NSLocalizedString(@"Failed to load Terms of Service", @"Window title  VPNService"),
                    [NSString stringWithFormat: @"%@\n%@",
                     NSLocalizedString(@"The Terms of Service could not be loaded:", @"Window text VPNService"),
                     [[error userInfo] objectForKey: @"NSLocalizedDescription"]],
                    nil,nil,nil);
    [progressIndicator stopAnimation: self];
    [gMC activateIgnoringOtherApps];
}

- (void) dealloc {
    
    [delegate release]; delegate = nil;
    
	[super dealloc];
}

- (NSString *) description
{
    return [NSString stringWithFormat:@"%@", [self class]];
}

- (IBAction) acceptButtonWasClicked: sender
{
	[[self delegate] vpnServiceTermsOfService: self finishedWithChoice: VPNServiceTermsOfServiceAcceptChoice];
}

- (IBAction) rejectButtonWasClicked: sender
{
	[[self delegate] vpnServiceTermsOfService: self finishedWithChoice: VPNServiceTermsOfServiceRejectChoice];
}

-(WebView *) termsOfServiceWV
{
    return [[termsOfServiceWV retain] autorelease];
}

-(NSTextFieldCell *) termsOfServiceHeaderTFC
{
    return [[termsOfServiceHeaderTFC retain] autorelease];
}

-(id) delegate
{
    return [[delegate retain] autorelease];
}

@end

#endif
