/*
 * Copyright 2011, 2012, 2013 Jonathan K. Bullard. All rights reserved.
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


#import "WelcomeController.h"

#import "defines.h"

#import "MenuController.h"
#import "TBUserDefaults.h"

extern TBUserDefaults  * gTbDefaults;

@interface WelcomeController() // Private methods

-(id)                delegate;
-(void)              setTitle: (NSString *) newTitle ofControl: (id) theControl;

@end

@implementation WelcomeController

-(NSString *) stringValue {
    
    // Implemented ONLY to work with "takeStringURLFrom:" in awakeFromNib
    
    return [[urlString copy] autorelease];
}

-(id)     initWithDelegate: (id) theDelegate
				 urlString: (NSString *) theUrlString
			   windowWidth: (float) windowWidth
			  windowHeight: (float) windowHeight
showDoNotShowAgainCheckbox: (BOOL) showTheCheckbox
{
    self = [super initWithWindowNibName:@"Welcome"];
    if (  ! self  ) {
        return nil;
    }
    
    delegate = [theDelegate retain];
	urlString = [theUrlString retain];
	urlWindowWidth  = windowWidth;
	urlWindowHeight = windowHeight;
	showCheckbox = showTheCheckbox;
	
	welcomeFrameStartCount = 0;
	
    return self;
}

-(void) awakeFromNib
{ 
	if (  urlWindowWidth   == 0.0f  ) {
		urlWindowWidth  = 500.00;
	}
	if (  urlWindowHeight  == 0.0f  ) {
		urlWindowHeight = 500.00;
	}

	float widthChange  = 500.0f - urlWindowWidth;
	float heightChange = 500.0f - urlWindowHeight;
	
	if (   (widthChange != 0.0f)
		|| (heightChange != 0.0f)  ) {
		NSRect wFrame = [[self window] frame];
		wFrame.size.width  = wFrame.size.width  - widthChange;
		wFrame.size.height = wFrame.size.height - heightChange;
		[[self window] setFrame: wFrame display: YES];
	}
	
    [[self window] setTitle: NSLocalizedString(@"Welcome", @"Window title")];
    
    [self setTitle: NSLocalizedString(@"OK" , @"Button") ofControl: okButton];
	
    [doNotShowAgainCheckbox setTitle: NSLocalizedString(@"Do not show this again", @"Checkbox")];
	
	[progressIndicator startAnimation: self];
    
    // respondsToSelector is used because OS X 10.4.11 and higher respond to setMainFrameURL:, so runningOnLeopardOrNewer() won't test what we want
    // But when we stop building for Tiger we can remove the test and the "else" clause and the "stingValue" definition (above)
    if (  [welcomeWV respondsToSelector:@selector(setMainFrameURL:)]  ) {
        [welcomeWV setMainFrameURL: urlString];
    } else {
        [welcomeWV takeStringURLFrom: self]; // Weird, but the only easy way to do it, since takeStringUrlFrom: invokes stringValue on its argument.
    }
    
    [welcomeWV setFrameLoadDelegate: self];
	
	if (  ! showCheckbox  ) {
		[doNotShowAgainCheckbox setHidden: YES];
	}
	
	
    [[self window] center];
    [NSApp activateIgnoringOtherApps:YES];
    [[self window] makeKeyAndOrderFront: self];
}

// Sets the title for a control, shifting the origin of the control itself to the left.
-(void) setTitle: (NSString *) newTitle ofControl: (id) theControl
{
    NSRect oldRect = [theControl frame];
    [theControl setTitle: newTitle];
    [theControl sizeToFit];
    
    NSRect newRect = [theControl frame];
    float widthChange = newRect.size.width - oldRect.size.width;
    NSRect oldPos;
    
    if (   [theControl isEqual: okButton]  ) {
        oldPos = [theControl frame];
        oldPos.origin.x = oldPos.origin.x - widthChange;
        [theControl setFrame:oldPos];
    }
}

-(void) webView: (WebView *) wv didStartProvisionalLoadForFrame: (WebFrame *) wf
{
    (void) wf;
    
    if (  wv == welcomeWV  ) {
        welcomeFrameStartCount++;
    }
}

-(void)webView: (WebView *) wv didFinishLoadForFrame: (WebFrame *) wf
{
    (void) wf;
    
    if (  wv == welcomeWV  ) {
        welcomeFrameStartCount--;
        if (  welcomeFrameStartCount <= 0  ) {
            [progressIndicator stopAnimation: self];
            [wv setPolicyDelegate: self];
        }
    }
}

-(void)webView: (WebView *) wv didFailProvisionalLoadWithError: (NSError *) error forFrame: (WebFrame *) wf
{
    (void) wf;
    
    if (  wv == welcomeWV  ) {
        NSLog(@"Failed to load welcome message; error = %@", [error description]);
        [progressIndicator stopAnimation: self];
        [NSApp activateIgnoringOtherApps:YES];
    }
}

-(void)                 webView: (WebView *)      wv
decidePolicyForNavigationAction: (NSDictionary *) actionInformation
                        request: (NSURLRequest *) request
                          frame: (WebFrame *)     frame
               decisionListener: (id < WebPolicyDecisionListener >)listener
{
    (void) actionInformation;
    (void) request;
    (void) frame;
    (void) listener;
    
    if (  wv == welcomeWV  ) {
        [[NSWorkspace sharedWorkspace] openURL:[request URL]];
    }
}

- (void) dealloc {
	
	[urlString release]; urlString = nil;
    [delegate  release]; delegate  = nil;
    
	[super dealloc];
}

-(NSString *) description
{
    return [NSString stringWithFormat:@"%@", [self class]];
}

-(IBAction) okButtonWasClicked: sender
{
	(void) sender;
	
	[[self delegate] welcomeOKButtonWasClicked];
}

-(IBAction)   doNotShowAgainCheckboxWasClicked: (NSButton *) sender
{
    [gTbDefaults setBool: [sender state] forKey: @"skipWelcomeScreen"];
}

-(NSButton *) doNotShowAgainCheckbox
{
	return doNotShowAgainCheckbox;
}

-(id) delegate
{
    return [[delegate retain] autorelease];
}

@end
