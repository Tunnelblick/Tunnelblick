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


#import "GeneralView.h"
#import "TBUserDefaults.h"


extern TBUserDefaults * gTbDefaults;


@implementation GeneralView

- (id)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        // Initialization code here.
    }
    return self;
}

- (void)drawRect:(NSRect)dirtyRect {
    // Drawing code here.
}

-(void) awakeFromNib
{
    [configurationFilesTFC              setTitle: NSLocalizedString(@"Configurations:",                                                   @"Window text")];
    [useShadowCopiesCheckbox            setTitle: NSLocalizedString(@"Use shadow copies of configuration files",                          @"Checkbox name")];
    [monitorConfigurationFolderCheckbox setTitle: NSLocalizedString(@"Monitor the configuration folders for changes",                     @"Checkbox name")];
    
    [updatesUpdatesTFC                  setTitle: NSLocalizedString(@"Updates:",                        @"Window text")];
    [updatesCheckAutomaticallyCheckbox  setTitle: NSLocalizedString(@"Check for updates automatically", @"Checkbox name")];
    [updatesCheckNowButton              setTitle: NSLocalizedString(@"Check Now",                       @"Button")];
    [updatesCheckNowButton sizeToFit];
    
    // Keyboard Shortcuts popup
    // We allow F1...F12 as keyboard shortcuts (or no shortcut) so the menu isn't too long (and MacBook keyboards only go that high, anyway)
    [keyboardShortcutTFC setTitle: NSLocalizedString(@"Keyboard shortcut:", @"Window text")];
    const unichar cmdOptionChars[] = {0x2318,' ',0x2325};
    NSString * cmdOptionString = [NSString stringWithCharacters: cmdOptionChars
                                                         length: sizeof cmdOptionChars / sizeof * cmdOptionChars];
    NSMutableArray * kbsContent = [NSMutableArray arrayWithCapacity: 12];
    [kbsContent addObject: [NSDictionary dictionaryWithObjectsAndKeys: NSLocalizedString(@"None", @"Button"), @"name", [NSNumber numberWithUnsignedInt: 0], @"value", nil]];
    int i;
    for (  i=0; i<12; i++  ) {
        [kbsContent addObject: [NSDictionary dictionaryWithObjectsAndKeys:
                                // Display <cmd><option>F1 (Command-Option-F1)...; Value is 0...11
                                [NSString stringWithFormat: 
                                 NSLocalizedString(@"%@ F%d (Command-Option-F%d)", @"Button"), cmdOptionString, i+1, i+1], @"name",
                                [NSNumber numberWithUnsignedInt: i], @"value",
                                nil]];
    }
    [keyboardShortcutArrayController setContent: kbsContent];
    [keyboardShortcutButton sizeToFit];
    
    // Log display size popup
    // We allow specific log display sizes
    [maxLogDisplaySizeTFC               setTitle: NSLocalizedString(@"Maximum log display size:", @"Window text")];
    NSArray * mlsContent = [NSArray arrayWithObjects:
                            [NSDictionary dictionaryWithObjectsAndKeys: NSLocalizedString( @"10 KB", @"Button"), @"name", [NSNumber numberWithUnsignedInt:       10*1024], @"value", nil],
                            [NSDictionary dictionaryWithObjectsAndKeys: NSLocalizedString(@"100 KB", @"Button"), @"name", [NSNumber numberWithUnsignedInt:      100*1024], @"value", nil],
                            [NSDictionary dictionaryWithObjectsAndKeys: NSLocalizedString(  @"1 MB", @"Button"), @"name", [NSNumber numberWithUnsignedInt:     1024*1024], @"value", nil],
                            [NSDictionary dictionaryWithObjectsAndKeys: NSLocalizedString( @"10 MB", @"Button"), @"name", [NSNumber numberWithUnsignedInt:  10*1024*1024], @"value", nil],
                            nil];
    [maximumLogSizeArrayController setContent: mlsContent];
    [maximumLogSizeButton sizeToFit];
    
    [warningsTFC                        setTitle: NSLocalizedString(@"Warnings:",                 @"Window text")];
    [resetDisabledWarningsButton        setTitle: NSLocalizedString(@"Reset Disabled Warnings",   @"Button")];
    [resetDisabledWarningsButton sizeToFit];
}


//***************************************************************************************************************
// Getters

TBSYNTHESIZE_OBJECT_GET(retain, NSButton *,          useShadowCopiesCheckbox)
TBSYNTHESIZE_OBJECT_GET(retain, NSButton *,          monitorConfigurationFolderCheckbox)

TBSYNTHESIZE_OBJECT_GET(retain, NSButton *,          updatesCheckAutomaticallyCheckbox)
TBSYNTHESIZE_OBJECT_GET(retain, NSTextFieldCell *,   updatesLastCheckedTFC)

TBSYNTHESIZE_OBJECT_GET(retain, NSArrayController *, keyboardShortcutArrayController)
TBSYNTHESIZE_OBJECT_GET(retain, NSButton *,          keyboardShortcutButton)

TBSYNTHESIZE_OBJECT_GET(retain, NSArrayController *, maximumLogSizeArrayController)
TBSYNTHESIZE_OBJECT_GET(retain, NSButton *,          maximumLogSizeButton)

@end
