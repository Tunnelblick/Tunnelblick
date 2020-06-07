/*
 * Copyright 2011, 2012, 2013, 2014, 2015, 2016, 2017 Jonathan K. Bullard. All rights reserved.
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

#import "helper.h"

#import "MenuController.h"
#import "NSFileManager+TB.h"
#import "TBButton.h"
#import "UIHelper.h"


extern NSString       * gDeployPath;
extern NSFileManager  * gFileMgr;
extern MenuController * gMC;


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

-(void) dealloc {
	
	[super dealloc];
}

TBSYNTHESIZE_OBJECT_GET(retain, NSArrayController *, appearanceIconSetArrayController)
TBSYNTHESIZE_OBJECT_GET(retain, TBPopUpButton *,     appearanceIconSetButton)
TBSYNTHESIZE_OBJECT_GET(retain, TBButton *,          appearancePlaceIconNearSpotlightCheckbox)

TBSYNTHESIZE_OBJECT_GET(retain, TBButton *,        appearanceDisplayConnectionSubmenusCheckbox)
TBSYNTHESIZE_OBJECT_GET(retain, TBButton *,        appearanceDisplayConnectionTimersCheckbox)

TBSYNTHESIZE_OBJECT_GET(retain, TBButton *,        appearanceDisplaySplashScreenCheckbox)

TBSYNTHESIZE_OBJECT_GET(retain, NSArrayController *, appearanceConnectionWindowDisplayCriteriaArrayController)
TBSYNTHESIZE_OBJECT_GET(retain, TBPopUpButton *,     appearanceConnectionWindowDisplayCriteriaButton)

TBSYNTHESIZE_OBJECT_GET(retain, NSArrayController *, appearanceConnectionWindowScreenArrayController)
TBSYNTHESIZE_OBJECT_GET(retain, TBPopUpButton *,     appearanceConnectionWindowScreenButton)

TBSYNTHESIZE_OBJECT_GET(retain, TBButton *,        appearanceDisplayStatisticsWindowsCheckbox)
TBSYNTHESIZE_OBJECT_GET(retain, TBButton *,        appearanceDisplayStatisticsWindowsWhenDisconnectedCheckbox)

- (void)drawRect:(NSRect)dirtyRect {
    // Drawing code here.
	
	(void) dirtyRect;
}

-(void) awakeFromNib
{
    // Icon set popup
    
    [appearanceIconTFC setTitle: NSLocalizedString(@"Icon:", @"Window text")];
    
    NSArray * paths = [self getIconSets];
    
    NSString * defaultIconSetName    = @"TunnelBlick.TBMenuIcons";
    NSString * blackWhiteIconSetName = @"TunnelBlick-black-white.TBMenuIcons";
    NSString * oldIconSetName        = @"3.3.TBMenuIcons";
    
    NSMutableArray * iconSetContent = [NSMutableArray arrayWithCapacity: [paths count]];
    unsigned i;
    for (  i=0; i< [paths count]; i++  ) {
        NSString * path = [paths objectAtIndex: i];
        NSString * fileName = [path lastPathComponent];
        NSString * name = [fileName stringByDeletingPathExtension];
        if (  [fileName isEqualToString: defaultIconSetName]  ) {
            name = NSLocalizedString(@"Standard icon", @"Button");
        } else if (  [fileName isEqualToString: blackWhiteIconSetName]  ) {
            name = NSLocalizedString(@"Monochrome icon", @"Button");
        } else if (  [fileName isEqualToString: oldIconSetName]  ) {
            name = NSLocalizedString(@"Tunnelblick 3.3 icon", @"Button");
        }
        
        [iconSetContent addObject: [NSDictionary dictionaryWithObjectsAndKeys: name, @"name", fileName, @"value", nil]];
    }
    
    if (  [iconSetContent count] > 0  ) {
        [appearanceIconSetArrayController setContent: iconSetContent];
    } else {
        [appearanceIconSetArrayController setContent:
         [NSDictionary dictionaryWithObjectsAndKeys: NSLocalizedString(@"(None available)", @"Button"), @"name", @"", @"value", nil]];
    }
	
	BOOL rtl = [UIHelper languageAtLaunchWasRTL];
	
	[appearanceIconSetButton
	 setTitle: nil	 infoTitle: attributedStringFromHTML(NSLocalizedString(@"<p>Specifies the icon which Tunnelblick should display in the menu bar.</p>",
														   @"HTML info for the 'Icon' button."))];
    [UIHelper setTitle: nil ofControl: appearanceIconSetButton shift: rtl narrow: YES enable: YES];
    
    // Icon placement checkbox
    NSString * onRightImageTag = [UIHelper imgTagForImageName: @"info-icon-on-right-360x40" width: 360 height: 40];
    NSString * onLeftImageTag  = [UIHelper imgTagForImageName: @"info-icon-on-left-360x40"  width: 360 height: 40];
    NSAttributedString * infoTitle = attributedStringFromHTML([NSString stringWithFormat:
                                                                          NSLocalizedString(@"<p><strong>When checked</strong>, the Tunnelblick icon is positioned near the Spotlight icon:</p>\n"
                                                                                            @"<p>%@</p>\n"
                                                                                            @"<p><strong>When not checked</strong>, the Tunnelblick icon is positioned normally:</p>\n"
                                                                                            @"<p>%@</p>\n"
                                                                                            @"<p><strong>This checkbox is disabled</strong> on macOS Sierra and higher because it is not needed, and on systems for which it is known to cause problems.</p>\n"
                                                                                            @"<p><a href=\"https://tunnelblick.net/cAppInfoPlaceNearSpotLightIconCheckbox.html\">More info</a></p>",
                                                                                            @"HTML info for the 'Place near Spotlight icon' checkbox. The two '%@' are replaced by images of the menu bar showing the position of the Tunnelblick icon."),
                                                               onRightImageTag, onLeftImageTag]);
	[appearancePlaceIconNearSpotlightCheckbox
	 setTitle: NSLocalizedString(@"Place near Spotlight icon", @"Checkbox name")
	 infoTitle: infoTitle];
	
	// Menu checkboxes
	[appearanceMenuTFC setTitle: NSLocalizedString(@"Menu:", @"Window text")];
	[appearanceDisplayConnectionSubmenusCheckbox
	 setTitle: NSLocalizedString(@"Display connection submenus", @"Checkbox name")
	 infoTitle: attributedStringFromHTML(NSLocalizedString(@"<p><strong>When checked</strong>, configurations that are inside folders are shown in submenus of the Tunnelblick menu.</p>\n"
														   @"<p><strong>When not checked</strong>, configurations that are inside folders are shown in the Tunnelblick menu.</p>",
														   @"HTML info for the 'Display connection submenus' checkbox."))];
	
	[appearanceDisplayConnectionTimersCheckbox
	  setTitle: NSLocalizedString(@"Display connection timers", @"Checkbox name")
	 infoTitle: attributedStringFromHTML(NSLocalizedString(@"<p><strong>When checked</strong>, the time since a connection was established is displayed in the Tunnelblick menu and in the title of the VPN Details window.</p>",
														   @"HTML info for the 'Display connection timers' checkbox."))];
	
	// Splash screen checkboxes
	[appearanceSplashTFC setTitle: NSLocalizedString(@"Startup window:", @"Window text")];
 
	[appearanceDisplaySplashScreenCheckbox
	  setTitle: NSLocalizedString(@"Display window while Tunnelblick is starting up", @"Checkbox name")
	 infoTitle: attributedStringFromHTML(NSLocalizedString(@"<p><strong>When checked</strong>, a window will display Tunnelblick's progress while starting up.</p>",
														   @"HTML info for the 'Display window while Tunnelblick is starting up' checkbox."))];

    // VPN status windows display criteria
    [appearanceConnectionWindowDisplayCriteriaTFC setTitle: NSLocalizedString(@"VPN status windows:", @"Window text")];
    NSArray * cwContent = [NSArray arrayWithObjects:
						   [NSDictionary dictionaryWithObjectsAndKeys: NSLocalizedString(@"Never show",                          @"Button"), @"name", @"neverShow",          @"value", nil],
						   [NSDictionary dictionaryWithObjectsAndKeys: NSLocalizedString(@"Show while connecting",               @"Button"), @"name", @"showWhenConnecting", @"value", nil],
						   [NSDictionary dictionaryWithObjectsAndKeys: NSLocalizedString(@"Show while connecting and connected", @"Button"), @"name", @"showWhenConnectingAndConnected" , @"value", nil],
						   [NSDictionary dictionaryWithObjectsAndKeys: NSLocalizedString(@"Show when connection status changes", @"Button"), @"name", @"showWhenChanges",    @"value", nil],
						   nil];
    [appearanceConnectionWindowDisplayCriteriaArrayController setContent: cwContent];
	[appearanceConnectionWindowDisplayCriteriaButton
	 setTitle: nil
	 infoTitle: attributedStringFromHTML(NSLocalizedString(@"<p>Specifies when Tunnelblick should display VPN status windows.</p>",
														   @"HTML info for the 'VPN status windows' button."))];
    [UIHelper setTitle: nil ofControl: appearanceConnectionWindowDisplayCriteriaButton shift: rtl narrow: YES enable: YES];

    // Connection window screen assignment popup
    NSMutableArray * cwsContent = [NSMutableArray arrayWithCapacity: [[NSScreen screens] count] + 1];
    
    NSArray * screens = [gMC screenList];
    
    NSDictionary * dict = [screens objectAtIndex: 0];
    unsigned width  = [[dict objectForKey: @"DisplayWidth"]  unsignedIntValue];
    unsigned height = [[dict objectForKey: @"DisplayHeight"] unsignedIntValue];
	dict = [NSDictionary dictionaryWithObjectsAndKeys:
						   [NSString stringWithFormat: NSLocalizedString(@"Show on default screen (%u x %u)", @"Button"), width, height], @"name",
						   [NSNumber numberWithUnsignedInt: 0], @"value", nil];
    [cwsContent addObject: dict];
    
    for (  i=0; i<[screens count]; i++  ) {
        dict = [screens objectAtIndex: i];
        unsigned displayNumber = [[dict objectForKey: @"DisplayNumber"] unsignedIntValue];
		width  = [[dict objectForKey: @"DisplayWidth"]  unsignedIntValue];
		height = [[dict objectForKey: @"DisplayHeight"] unsignedIntValue];
        [cwsContent addObject: [NSDictionary dictionaryWithObjectsAndKeys:
                                [NSString stringWithFormat: NSLocalizedString(@"Show on screen %u (%u x %u)", @"Button"), i, width, height], @"name",
                                [NSNumber numberWithUnsignedInt: displayNumber], @"value",
                                nil]];
    }
	
    [appearanceConnectionWindowScreenArrayController setContent: cwsContent];
	[appearanceConnectionWindowScreenButton
	 setTitle: nil
	 infoTitle: attributedStringFromHTML(NSLocalizedString(@"<p>Specifies the screen on which Tunnelblick should display VPN status windows.</p>",
														   @"HTML info for the button for selecting which screen to show status windows."))];
    [UIHelper setTitle: nil ofControl: appearanceConnectionWindowScreenButton shift: rtl narrow: YES enable: YES];
    
	[appearanceDisplayStatisticsWindowsCheckbox
	 setTitle: NSLocalizedString(@"Show when the pointer is over the Tunnelblick icon", @"Checkbox name")
	 infoTitle: attributedStringFromHTML(NSLocalizedString(@"<p><strong>When checked</strong>, VPN status windows for all 'active' configurations are displayed when the pointer is over the Tunnelblick icon.</p>"
														   @"<p>'Active' configurations are configurations that you have attempted to connect since Tunnelblick was launched.</p>"
														   @"<p><strong>This checkbox is disabled</strong> when 'Never Show' is selected above.</p>",
														   @"HTML info for the 'Show the VPN status window when the pointer is over the Tunnelblick icon' checkbox."))];
	
	
	[appearanceDisplayStatisticsWindowsWhenDisconnectedCheckbox
	 setTitle: NSLocalizedString(@"Show when disconnected", @"Checkbox name")
	 infoTitle: attributedStringFromHTML(NSLocalizedString(@"<p><strong>When checked</strong>, the VPN status window is displayed even when the configuration is disconnected.</p>"
														   @"<p><strong>This checkbox is disabled</strong> when 'Never Show' is selected above.</p>",
														   @"HTML info for the 'Show the VPN status window when disconnected' checkbox."))];
}

-(NSArray *) getIconSets
{
    // Get all the icon sets in (1) Deploy, (2) Shared, and (3) the app's Resources
    
    NSMutableArray * paths = [[[NSMutableArray alloc] initWithCapacity: 30] autorelease];
    NSMutableArray * iconNames = [[[NSMutableArray alloc] initWithCapacity: 30] autorelease];
    NSArray * iconDirs = [NSArray arrayWithObjects:
                          [gDeployPath                          stringByAppendingPathComponent: @"IconSets"],
                          [L_AS_T_SHARED                        stringByAppendingPathComponent: @"IconSets"],
                          [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent: @"IconSets"],
                          nil];
    NSEnumerator * iconDirEnum = [iconDirs objectEnumerator];
    NSString * folder;
    NSString * file;
    while (  (folder = [iconDirEnum nextObject])  ) {
        NSDirectoryEnumerator * dirEnum = [gFileMgr enumeratorAtPath: folder];
        while (  (file = [dirEnum nextObject])  ) {
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

@end
