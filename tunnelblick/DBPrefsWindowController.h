//
//  DBPrefsWindowController.h
//
//  Created by Dave Batton
//  http://www.Mere-Mortal-Software.com/blog/
//
//  Documentation for this class is available here:
//  http://www.mere-mortal-software.com/blog/details.php?d=2007-03-11
//
//  Copyright 2007. Some rights reserved.
//  This work is licensed under a Creative Commons license:
//  http://creativecommons.org/licenses/by/3.0/
//
//  11 March 2007 : Initial 1.0 release
//  15 March 2007 : Version 1.1
//                  Resizing is now handled along with the cross-fade by
//                  the NSViewAnimation routine.
//                  Cut the fade time in half to speed up the window resize.
//                  -setupToolbar is now called each time the window opens so
//                  you can configure it differently each time if you want.
//                  Holding down the shift key will now slow down the animation.
//                  This can be disabled by using the new -setShiftSlowsAnimation:
//                  method.
//  23 March 2007 : Version 1.1.1
//                  The initial first responder now gets set when the view is
//                  swapped so that the user can tab to the objects displayed
//                  in the window.
//                  Also added a work-around to Cocoa's insistance on drawing
//                  a focus ring around the first toolbar icon when going from
//                  a view with a focusable item to a view without a focusable item.
//
//  31 May 2007 :   Version 1.1.2
//                  The window's title bar and toolbar heights are now calculated at
//                  runtime, rather than being hard-coded.
//                  Fixed a redraw problem and a window placement problem associated
//                  with large preference windows.
//                  Added some code to supress compiler warnings from unused parameters.
//                  Fixed a couple of objects that weren't being properly released.
//
//
//  10 June 2011:   Modified for use in Tunnelblick
//
//  24 October 2026: The views are now chosen from a sidebar instead of from toolbar buttons.
//                   The first view added is the "primary" view. A subclass supplies the top
//                   part of the sidebar for it (-sidebarTopView) and calls -showPrimaryView when
//                   it is clicked. Every other view gets a row in the sidebar's section list.
//                   The toolbar only holds items that have no view (e.g. the lock icon).


@interface DBPrefsWindowController : NSWindowController <NSAnimationDelegate, NSToolbarDelegate> {
	NSMutableArray *toolbarIdentifiers;
	NSMutableDictionary *toolbarViews;
	NSMutableDictionary *toolbarItems;

	BOOL _crossFade;
	BOOL _shiftSlowsAnimation;

	NSView *contentSubview;
	NSViewAnimation *viewAnimation;

	NSSplitViewController * splitViewController;
	NSView                * sidebarView;
	NSTableView           * sidebarSectionTable;
	NSMutableArray        * sidebarSectionIdentifiers;
	NSMutableDictionary   * originalViewSizes;  // Size of each view when it was added (the size it was designed for)
	id                      sidebarSectionList;
	BOOL                    updatingSidebarSelection;

	BOOL windowHasLoaded;
}


+ (DBPrefsWindowController *)sharedPrefsWindowController;
+ (NSString *)nibName;

- (void)setupToolbar;
- (void)addView:(NSView *)view label:(NSString *)label;
- (void)addView:(NSView *)view label:(NSString *)label image:(NSImage *)image;
- (NSString *)windowTitle:(NSString *)currentItemLabel;

- (BOOL)crossFade;
- (void)setCrossFade:(BOOL)fade;
- (BOOL)shiftSlowsAnimation;
- (void)setShiftSlowsAnimation:(BOOL)slows;

- (void)displayViewForIdentifier:(NSString *)identifier animate:(BOOL)animate;

// Sidebar
- (NSView *)sidebarTopView;                           // Override: view shown above the section list (nil = none)
- (NSView *)sidebarBottomView;                        // Override: bar shown at the bottom of the sidebar (nil = none)
- (NSString *)sidebarSectionTitle;                    // Override: heading of the section list (nil = none)
- (void)sidebarDidSelectPrimaryView:(BOOL)isPrimary;  // Override: called when the primary view is shown or hidden
- (void)showPrimaryView;
- (void)crossFadeView:(NSView *)oldView withView:(NSView *)newView;
- (NSRect)frameForView:(NSView *)view;

-(BOOL)windowHasLoaded;

@end
