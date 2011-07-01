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


#import "AppearanceView.h"
#import "NSFileManager+TB.h"


extern NSString       * gDeployPath;
extern NSString       * gSharedPath;
extern NSFileManager  * gFileMgr;


@interface AppearanceView()  // Private methods

-(NSArray *) getIconSets;

@end


@implementation AppearanceView

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
    // Icon set popup
    
    [appearanceIconTFC setTitle: NSLocalizedString(@"Icon:", @"Window text")];
    
    NSArray * paths = [self getIconSets];
    
    NSString * defaultIconSetName    = @"TunnelBlick.TBMenuIcons";
    NSString * blackWhiteIconSetName = @"TunnelBlick-black-white.TBMenuIcons";
    
    NSMutableArray * iconSetContent = [NSMutableArray arrayWithCapacity: [paths count]];
    int i;
    for (  i=0; i< [paths count]; i++  ) {
        NSString * path = [paths objectAtIndex: i];
        NSString * fileName = [path lastPathComponent];
        NSString * name = [fileName stringByDeletingPathExtension];
        if (  [fileName isEqualToString: defaultIconSetName]  ) {
            name = NSLocalizedString(@"Standard icon", @"Button");
        } else if (  [fileName isEqualToString: blackWhiteIconSetName]  ) {
            name = NSLocalizedString(@"Monochrome icon", @"Button");
        }
        
        [iconSetContent addObject: [NSDictionary dictionaryWithObjectsAndKeys: name, @"name", fileName, @"value", nil]];
    }
    
    if (  [iconSetContent count] > 0  ) {
        [appearanceIconSetArrayController setContent: iconSetContent];
    } else {
        [appearanceIconSetArrayController setContent:
         [NSDictionary dictionaryWithObjectsAndKeys: NSLocalizedString(@"(None available)", @"Button"), "name", @"", "value", nil]];
    }
    [appearanceIconSetButton sizeToFit];
    
    
    // Icon placement checkbox
    [appearancePlaceIconNearSpotlightCheckbox setTitle: NSLocalizedString(@"Place next to Spotlight icon", @"Checkbox name")];
    
    
    // Menu checkboxes
    
    [appearanceMenuTFC setTitle: NSLocalizedString(@"Menu:", @"Window text")];
    [appearanceDisplayConnectionSubmenusCheckbox setTitle: NSLocalizedString(@"Display connection submenus",       @"Checkbox name")];
    [appearanceDisplayConnectionTimersCheckbox   setTitle: NSLocalizedString(@"Display connection timers",         @"Checkbox name")];
    
    
    // Connection window display criteria
    [appearanceConnectionWindowDisplayCriteriaTFC setTitle: NSLocalizedString(@"Notification window:", @"Window text")];
    NSArray * cwContent = [NSArray arrayWithObjects:
                            [NSDictionary dictionaryWithObjectsAndKeys: NSLocalizedString(@"Never show",                          @"Button"), @"name", @"neverShow", @"value", nil],
                            [NSDictionary dictionaryWithObjectsAndKeys: NSLocalizedString(@"Show while connecting",               @"Button"), @"name", @"showWhenConnecting", @"value", nil],
                            [NSDictionary dictionaryWithObjectsAndKeys: NSLocalizedString(@"Show when connection status changes", @"Button"), @"name", @"showWhenChanges", @"value", nil],
                            nil];
    [appearanceConnectionWindowDisplayCriteriaArrayController setContent: cwContent];
    [appearanceConnectionWindowDisplayCriteriaButton sizeToFit];
}

-(NSArray *) getIconSets
{
    // Get all the icon sets in (1) Deploy, (2) Shared, and (3) the app's Resources
    
    NSMutableArray * paths = [[[NSMutableArray alloc] initWithCapacity: 30] autorelease];
    NSMutableArray * iconNames = [[[NSMutableArray alloc] initWithCapacity: 30] autorelease];
    NSArray * iconDirs = [NSArray arrayWithObjects:
                          [gDeployPath stringByAppendingPathComponent: @"IconSets"],
                          [gSharedPath stringByAppendingPathComponent: @"IconSets"],
                          [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent: @"IconSets"],
                          nil];
    NSEnumerator * iconDirEnum = [iconDirs objectEnumerator];
    NSString * folder;
    NSString * file;
    while (  folder = [iconDirEnum nextObject]  ) {
        NSDirectoryEnumerator * dirEnum = [gFileMgr enumeratorAtPath: folder];
        while (  file = [dirEnum nextObject]  ) {
            [dirEnum skipDescendents];
            if (  [[file pathExtension] isEqualToString: @"TBMenuIcons"]  ) {
                NSString * iconName = [file stringByDeletingPathExtension];
                if (  ! [iconName hasPrefix: @"large-"]  ) {
                    if (  ! [iconNames containsObject: iconName]  ) {
                        [paths addObject: [folder stringByAppendingPathComponent: file]];
                    }
                }
            }
        }
    }
    
    return paths;
}


//***************************************************************************************************************
// Getters

TBSYNTHESIZE_OBJECT_GET(retain, NSArrayController *, appearanceIconSetArrayController)
TBSYNTHESIZE_OBJECT_GET(retain, NSButton *,        appearanceIconSetButton)
TBSYNTHESIZE_OBJECT_GET(retain, NSButton *,        appearancePlaceIconNearSpotlightCheckbox)

TBSYNTHESIZE_OBJECT_GET(retain, NSButton *,        appearanceDisplayConnectionSubmenusCheckbox)
TBSYNTHESIZE_OBJECT_GET(retain, NSButton *,        appearanceDisplayConnectionTimersCheckbox)

TBSYNTHESIZE_OBJECT_GET(retain, NSArrayController *, appearanceConnectionWindowDisplayCriteriaArrayController)
TBSYNTHESIZE_OBJECT_GET(retain, NSButton *,        appearanceConnectionWindowDisplayCriteriaButton)

@end
