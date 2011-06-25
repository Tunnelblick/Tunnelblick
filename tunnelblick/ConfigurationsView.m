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


#import "ConfigurationsView.h"
#import "TBUserDefaults.h"

extern NSFileManager  * gFileMgr;
extern TBUserDefaults * gTbDefaults;


@interface ConfigurationsView() // Private methods

-(void) setTitle: (NSString *) newTitle ofControl: (id) theControl;
-(void) initializeSoundPopUpButtons;

@end


@implementation ConfigurationsView

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

-(void) dealloc
{
    [sortedSounds release];
    
    [super dealloc];
}

-(void) awakeFromNib
{
    [self setTitle: NSLocalizedString(@"Connect"   , @"Button") ofControl: connectButton   ];
    [self setTitle: NSLocalizedString(@"Disconnect", @"Button") ofControl: disconnectButton];
    
    
    // Left split view -- list of configurations and configuration manipulation
    
    [[leftNavTableColumn headerCell] setTitle: NSLocalizedString(@"Configurations", @"Window text")];
    
    [renameConfigurationMenuItem          setTitle: NSLocalizedString(@"Rename Configuration..."                          , @"Menu Item")];
    [duplicateConfigurationMenuItem       setTitle: NSLocalizedString(@"Duplicate Configuration..."                       , @"Menu Item")];
    [editOpenVPNConfigurationFileMenuItem setTitle: NSLocalizedString(@"Edit OpenVPN Configuration File..."               , @"Menu Item")];
    [showOpenvpnLogMenuItem               setTitle: NSLocalizedString(@"Show OpenVPN Log in Finder"                       , @"Menu Item")];
    [removeCredentialsMenuItem            setTitle: NSLocalizedString(@"Delete Configuration's Credentials in Keychain...", @"Menu Item")];
    
    // editOpenVPNConfigurationFileMenuItem, makePrivateOrSharedMenuItem, and showOnTunnelblickMenuMenuItem are initialized in validateDetailsWindowControls
    
    
    // Right split view - Log tab
    
    [logTabViewItem setLabel: NSLocalizedString(@"Log", @"Window title")];
    
    [self setTitle: NSLocalizedString(@"Copy Log to Clipboard", @"Button") ofControl: logToClipboardButton   ];
    
    
    // Right split view - Settings tab
    
    [settingsTabViewItem setLabel: NSLocalizedString(@"Settings", @"Window title")];
    
    [whenToConnectTFC                       setTitle: NSLocalizedString(@"Connect:", @"Window text")];
    [whenToConnectManuallyMenuItem          setTitle: NSLocalizedString(@"Manually"                 , @"Button")];
    [whenToConnectTunnelblickLaunchMenuItem setTitle: NSLocalizedString(@"When Tunnelblick launches", @"Button")];
    [whenToConnectOnComputerStartMenuItem   setTitle: NSLocalizedString(@"When computer starts"     , @"Button")];
    [whenToConnectPopUpButton sizeToFit];
    
    [setNameserverTFC setTitle: NSLocalizedString(@"Set DNS/WINS:", @"Window text")];
    // setNameserverPopUpButton is initialized in setupSettingsFromPreferences
    
    [monitorNetworkForChangesCheckbox setTitle: NSLocalizedString(@"Monitor network settings", @"Checkbox name")];
    
    [alertSoundsBox setTitle: NSLocalizedString(@"Alert sounds", @"Window title")];
    
    [connectionAlertSoundTFC    setTitle: NSLocalizedString(@"Connection:", @"Window text")              ];
    [disconnectionAlertSoundTFC setTitle: NSLocalizedString(@"Unexpected disconnection:", @"Window text")];
    [self initializeSoundPopUpButtons];
    
    [self setTitle: NSLocalizedString(@"Advanced..." , @"Button") ofControl: advancedButton];
}


-(void) initializeSoundPopUpButtons
{
    // Get all the names of sounds
    NSMutableArray * sounds = [[[NSMutableArray alloc] initWithCapacity: 30] autorelease];
    NSArray * soundDirs = [NSArray arrayWithObjects:
                           [NSHomeDirectory() stringByAppendingString: @"/Library/Sounds"],
                           @"/Library/Sounds",
                           @"/Network/Library/Sounds",
                           @"/System/Library/Sounds",
                           nil];
    NSArray * soundTypes = [NSArray arrayWithObjects: @"aiff", @"wav", nil];
    NSEnumerator * soundDirEnum = [soundDirs objectEnumerator];
    NSString * folder;
    NSString * file;
    while (  folder = [soundDirEnum nextObject]  ) {
        NSDirectoryEnumerator * dirEnum = [gFileMgr enumeratorAtPath: folder];
        while (  file = [dirEnum nextObject]  ) {
            [dirEnum skipDescendents];
            if (  [soundTypes containsObject: [file pathExtension]]  ) {
                NSString * soundName = [file stringByDeletingPathExtension];
                if (  ! [sounds containsObject: soundName]  ) {
                    [sounds addObject: soundName];
                }
            }
        }
    }
    
    // Sort them
    sortedSounds = [[sounds sortedArrayUsingSelector: @selector(caseInsensitiveCompare:)] retain];
    
    // Create an array of dictionaries of them
    NSMutableArray * soundsDictionaryArray = [NSMutableArray arrayWithCapacity: [sortedSounds count]];
    
    [soundsDictionaryArray addObject: [NSDictionary dictionaryWithObjectsAndKeys: 
                                       NSLocalizedString(@"None", @"Button"), @"name", 
                                       @"None", @"value", nil]];
    
    int i;
    for (  i=0; i<[sortedSounds count]; i++  ) {
        [soundsDictionaryArray addObject: [NSDictionary dictionaryWithObjectsAndKeys: 
                                           [sortedSounds objectAtIndex: i], @"name", 
                                           [sortedSounds objectAtIndex: i], @"value", nil]];
    }
    
    [soundOnConnectArrayController    setContent: soundsDictionaryArray];
    [soundOnDisconnectArrayController setContent: soundsDictionaryArray];
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
    
    if (   [theControl isEqual: connectButton]              // Shift the control itself left/right if necessary
        || [theControl isEqual: disconnectButton]
        || [theControl isEqual: advancedButton]  ) {
        oldPos = [theControl frame];
        oldPos.origin.x = oldPos.origin.x - widthChange;
        [theControl setFrame:oldPos];
    }
    
    if (  [theControl isEqual: connectButton]  )  {          // If the Connect button changes, shift the Disconnect button left/right
        oldPos = [disconnectButton frame];
        oldPos.origin.x = oldPos.origin.x - widthChange;
        [disconnectButton setFrame:oldPos];
    }
}


//***************************************************************************************************************
// Getters

TBSYNTHESIZE_OBJECT_GET(retain, NSArray *,             sortedSounds)

TBSYNTHESIZE_OBJECT_GET(retain, NSView *,              leftSplitView)
TBSYNTHESIZE_OBJECT_GET(retain, NSTableView *,         leftNavTableView)
TBSYNTHESIZE_OBJECT_GET(retain, NSTableColumn *,       leftNavTableColumn)

TBSYNTHESIZE_OBJECT_GET(retain, NSButton *,            addConfigurationButton)
TBSYNTHESIZE_OBJECT_GET(retain, NSButton *,            removeConfigurationButton)
TBSYNTHESIZE_OBJECT_GET(retain, NSPopUpButton *,       workOnConfigurationPopUpButton)
TBSYNTHESIZE_OBJECT_GET(retain, NSArrayController *,   workOnConfigurationArrayController)

TBSYNTHESIZE_OBJECT_GET(retain, NSMenuItem *,          renameConfigurationMenuItem)
TBSYNTHESIZE_OBJECT_GET(retain, NSMenuItem *,          duplicateConfigurationMenuItem)
TBSYNTHESIZE_OBJECT_GET(retain, NSMenuItem *,          makePrivateOrSharedMenuItem)
TBSYNTHESIZE_OBJECT_GET(retain, NSMenuItem *,          showOnTunnelblickMenuMenuItem)
TBSYNTHESIZE_OBJECT_GET(retain, NSMenuItem *,          editOpenVPNConfigurationFileMenuItem)
TBSYNTHESIZE_OBJECT_GET(retain, NSMenuItem *,          showOpenvpnLogMenuItem)
TBSYNTHESIZE_OBJECT_GET(retain, NSMenuItem *,          removeCredentialsMenuItem)

TBSYNTHESIZE_OBJECT_GET(retain, NSTextFieldCell *,     configurationNameTFC)
TBSYNTHESIZE_OBJECT_GET(retain, NSTextFieldCell *,     configurationStatusTFC)

TBSYNTHESIZE_OBJECT_GET(retain, NSButton *,            configurationsHelpButton)
TBSYNTHESIZE_OBJECT_GET(retain, NSButton *,            disconnectButton)
TBSYNTHESIZE_OBJECT_GET(retain, NSButton *,            connectButton)

TBSYNTHESIZE_OBJECT_GET(retain, NSTabView *,           configurationsTabView)

TBSYNTHESIZE_OBJECT_GET(retain, NSTabViewItem *,       logTabViewItem)
TBSYNTHESIZE_OBJECT_GET(retain, NSTextView *,          logView)

TBSYNTHESIZE_OBJECT_GET(retain, NSProgressIndicator *, progressIndicator)
TBSYNTHESIZE_OBJECT_GET(retain, NSButton *,            logToClipboardButton)


TBSYNTHESIZE_OBJECT_GET(retain, NSTabViewItem *,       settingsTabViewItem)

TBSYNTHESIZE_OBJECT_GET(retain, NSTextFieldCell *,     whenToConnectTFC)
TBSYNTHESIZE_OBJECT_GET(retain, NSPopUpButton *,       whenToConnectPopUpButton)
TBSYNTHESIZE_OBJECT_GET(retain, NSMenuItem *,          whenToConnectManuallyMenuItem)
TBSYNTHESIZE_OBJECT_GET(retain, NSMenuItem *,          whenToConnectTunnelblickLaunchMenuItem)
TBSYNTHESIZE_OBJECT_GET(retain, NSMenuItem *,          whenToConnectOnComputerStartMenuItem)

TBSYNTHESIZE_OBJECT_GET(retain, NSMenuItem *,          setNameserverTF)
TBSYNTHESIZE_OBJECT_GET(retain, NSMenuItem *,          setNameserverTFC)
TBSYNTHESIZE_OBJECT_GET(retain, NSPopUpButton *,       setNameserverPopUpButton)
TBSYNTHESIZE_OBJECT_GET(retain, NSArrayController *,   setNameserverArrayController)

TBSYNTHESIZE_OBJECT_GET(retain, NSButton *,            monitorNetworkForChangesCheckbox)

TBSYNTHESIZE_OBJECT_GET(retain, NSBox *,               alertSoundsBox)

TBSYNTHESIZE_OBJECT_GET(retain, NSTextFieldCell *,     connectionAlertSoundTFC)
TBSYNTHESIZE_OBJECT_GET(retain, NSTextFieldCell *,     disconnectionAlertSoundTFC)
TBSYNTHESIZE_OBJECT_GET(retain, NSButton *,            soundOnConnectButton)
TBSYNTHESIZE_OBJECT_GET(retain, NSButton *,            soundOnDisconnectButton)
TBSYNTHESIZE_OBJECT_GET(retain, NSArrayController *,   soundOnConnectArrayController)
TBSYNTHESIZE_OBJECT_GET(retain, NSArrayController *,   soundOnDisconnectArrayController)

TBSYNTHESIZE_OBJECT_GET(retain, NSButton *,          advancedButton)

@end
