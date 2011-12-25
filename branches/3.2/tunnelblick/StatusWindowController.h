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


#import <Cocoa/Cocoa.h>

@interface StatusWindowController : NSWindowController <NSAnimationDelegate,NSWindowDelegate>
{
    IBOutlet NSButton        * cancelButton;
    IBOutlet NSTextFieldCell * configurationNameTFC;
    IBOutlet NSTextFieldCell * statusTFC;
    IBOutlet NSImageView     * animationIV;
    
    NSUInteger                 statusScreenPosition; // Position of status window (0, 1, 2...)
                                                     // Corresponds to bit in statusScreenPositionsInUse
    
    NSString                 * name;            // Name we are displaying - displayName of configuration
    NSString                 * status;          // Status (e.g., "EXITING") of the configuration
    
    NSAnimation              * theAnim;         // For animation in the window
    
    CGFloat                    originalWidth;   // Width of window frame with original title ("XXXX...")
    CGFloat                    currentWidth;    // Width of window frame currently
    
    BOOL                       isOpen;          // Flag for animating window fade-in and fade-out
    
    id                         delegate;
}

-(id)         initWithDelegate:       (id)         theDelegate;

-(IBAction)   cancelButtonWasClicked: (id)         sender;

-(id)         delegate;

-(void)       fadeIn;
-(void)       fadeOut;

-(void)       restore;

-(NSString *) name;
-(void)       setName:                (NSString *) newName;

-(void)       setStatus:              (NSString *) theStatus
                forName:              (NSString *) theName;

@end
