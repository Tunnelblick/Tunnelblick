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


#import "SplashWindowController.h"

#import "defines.h"
#import "helper.h"

#import "MenuController.h"
#import "NSTimer+TB.h"
#import "TunnelblickInfo.h"

extern MenuController * gMC;
extern BOOL             gShuttingDownWorkspace;
extern TunnelblickInfo * gTbInfo;

@implementation SplashWindowController


-(id) init
{
    self = [super initWithWindowNibName:@"SplashWindow"];
    if (  ! self  ) {
        return nil;
    }

    return self;
}

-(void) awakeFromNib
{
    [[self window] setTitle: NSLocalizedString(@"Tunnelblick", @"Window title")];
    
    [iconIV setImage: [NSImage imageNamed: @"tb-icon-64x64.v1"]];

    NSString * tunnelblickName = NSLocalizedString(@"Tunnelblick", @"Window title");
	[tbNameTFC setTitle: tunnelblickName];

    NSMutableString * versionString = [[gTbInfo.tunnelblickVersionString mutableCopy] autorelease];
    NSString * programNameAndSpace = [tunnelblickName stringByAppendingString: @""];
    [versionString replaceOccurrencesOfString: programNameAndSpace
                                   withString: @""
                                      options: 0
                                        range: NSMakeRange(0, [versionString length])];
    [versionTFC setTitle: versionString];

    [self setMessage: NSLocalizedString(@"Starting Tunnelblick...", @"Window text in the splash screen")];
    
    [copyrightTFC setStringValue: copyrightNotice()];
    
    [[self window] center];
    [[self window] display];
    [self showWindow: self];
    [[self window] makeKeyAndOrderFront: self];
}

- (void) dealloc {
    
    [message  release]; message = nil;
    
	[super dealloc];
}

-(void) fadeOutAndClose
{
    NSWindow * window = [self window];
    if (   [window respondsToSelector: @selector(animator)]
        && [[window animator] respondsToSelector: @selector(setAlphaValue:)]  ) {
        [[window animator] setAlphaValue: 0.0];
        NSTimer * timer = [NSTimer scheduledTimerWithTimeInterval: (NSTimeInterval) 1.0   // Wait for the window to become transparent
                                                           target: self
                                                         selector: @selector(closeAfterFadeOutHandler:)
                                                         userInfo: nil
                                                          repeats: NO];
        [timer tbSetTolerance: -1.0];
    } else {
        [window close];
    }
}

-(void) closeAfterFadeOutHandler: (NSTimer *) timer
{
	(void) timer;
	
    if (  gShuttingDownWorkspace  ) {
        return;
    }
    
	[self performSelectorOnMainThread: @selector(closeAfterFadeOut:) withObject: nil waitUntilDone: NO];
}

-(void) closeAfterFadeOut: (NSDictionary *) dict
{
	(void) dict;
	
    [self close];
}


- (NSString *) description
{
    return [NSString stringWithFormat:@"%@", [self class]];
}

-(void) setMessage: (NSString *) newValue
{
    [newValue retain];
    [message release];
    message = newValue;

    if (  mainText  ) {
        [mainText setTitle: newValue];
        [[self window] display];
    }
}

TBSYNTHESIZE_OBJECT_GET(retain, NSString *, message)

@end
