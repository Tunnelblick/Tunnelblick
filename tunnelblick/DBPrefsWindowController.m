//
//  DBPrefsWindowController.m
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
//  Modifications copyright 2016, 2021 by Jonathan K. Bullard.

#import "DBPrefsWindowController.h"

#import "helper.h"
#import "TBUserDefaults.h"
#import "UIHelper.h"


extern TBUserDefaults * gTbDefaults;


static DBPrefsWindowController *_sharedPrefsWindowController = nil;


// Data source and delegate of the sidebar's section list. It is a separate object because subclasses of
// DBPrefsWindowController may be table view delegates themselves.

@interface DBPrefsWindowController (SidebarSectionList)
- (NSInteger)sidebarSectionCount;
- (NSView *)sidebarCellForTableView:(NSTableView *)tableView row:(NSInteger)row;
- (void)sidebarSectionSelectionDidChange;
@end

@interface DBPrefsSidebarSectionList : NSObject <NSTableViewDataSource, NSTableViewDelegate> {
	DBPrefsWindowController * controller; // Not retained: the controller owns this object
}
- (id)initWithController:(DBPrefsWindowController *)theController;
@end

@implementation DBPrefsSidebarSectionList

- (id)initWithController:(DBPrefsWindowController *)theController
{
	self = [super init];
	if (  self  ) {
		controller = theController;
	}
	return self;
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
	(void) tableView;
	
	return [controller sidebarSectionCount];
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
	(void) tableColumn;
	
	return [controller sidebarCellForTableView: tableView row: row];
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification
{
	(void) notification;
	
	[controller sidebarSectionSelectionDidChange];
}

@end


@implementation DBPrefsWindowController




#pragma mark -
#pragma mark Class Methods


+ (DBPrefsWindowController *)sharedPrefsWindowController
{
	if (!_sharedPrefsWindowController) {
		_sharedPrefsWindowController = [[self alloc] initWithWindowNibName:[self nibName]];
	}
	return _sharedPrefsWindowController;
}




+ (NSString *)nibName
// Subclasses can override this to use a nib with a different name.
{
    return @"Preferences";
}




#pragma mark -
#pragma mark Setup & Teardown


- (id)initWithWindow:(NSWindow *)window
// -initWithWindow: is the designated initializer for NSWindowController.
{
    (void)window;
    
	self = [super initWithWindow:nil];
	if (self != nil) {
        // Set up an array and some dictionaries to keep track
        // of the views we'll be displaying.
		toolbarIdentifiers = [[NSMutableArray alloc] init];
		toolbarViews = [[NSMutableDictionary alloc] init];
		toolbarItems = [[NSMutableDictionary alloc] init];
        
        // Set up an NSViewAnimation to animate the transitions.
		viewAnimation = [[NSViewAnimation alloc] init];
		[viewAnimation setAnimationBlockingMode:NSAnimationNonblocking];
		[viewAnimation setAnimationCurve:NSAnimationEaseInOut];
		[viewAnimation setDelegate:self];
		
		[self setCrossFade:YES]; 
		[self setShiftSlowsAnimation:YES];
		
		windowHasLoaded = FALSE;
	}
	return self;
}




- (void)windowDidLoad
{
    // Create a new window to display the preference views.
    // If the developer attached a window to this controller
    // in Interface Builder, it gets replaced with this one.
    
	if (  [self window]  ) {
		return;
	}
	
    NSWindow *window = [[[NSWindow alloc] initWithContentRect:NSMakeRect(0.0, 0.0, 920.0, 560.0)
												    styleMask:(NSWindowStyleMaskTitled |
															   NSWindowStyleMaskClosable |
                                                               NSWindowStyleMaskResizable |
															   NSWindowStyleMaskMiniaturizable |
                                                               NSWindowStyleMaskFullSizeContentView)
													  backing:NSBackingStoreBuffered
													    defer:YES] autorelease];
	[window setToolbarStyle: NSWindowToolbarStyleUnified];
	[self setWindow:window];

    [self setShouldCascadeWindows: NO];

	// The sidebar extends under the title bar (it gets the sidebar material from NSSplitViewItem);
	// the views are shown in contentSubview, which starts below the toolbar.
	sidebarView = [[NSView alloc] initWithFrame: NSMakeRect(0.0, 0.0, 200.0, 560.0)];
	NSViewController * sidebarViewController = [[[NSViewController alloc] init] autorelease];
	[sidebarViewController setView: sidebarView];

	NSView * contentHolder = [[[NSView alloc] initWithFrame: NSMakeRect(0.0, 0.0, 680.0, 560.0)] autorelease];
	contentSubview = [[NSView alloc] initWithFrame: [contentHolder bounds]];
	[contentSubview setTranslatesAutoresizingMaskIntoConstraints: NO];
	[contentHolder addSubview: contentSubview];
	NSLayoutGuide * safeArea = [contentHolder safeAreaLayoutGuide];
	[NSLayoutConstraint activateConstraints: @[[[contentSubview topAnchor]      constraintEqualToAnchor: [safeArea topAnchor]],
											   [[contentSubview bottomAnchor]   constraintEqualToAnchor: [contentHolder bottomAnchor]],
											   [[contentSubview leadingAnchor]  constraintEqualToAnchor: [contentHolder leadingAnchor]],
											   [[contentSubview trailingAnchor] constraintEqualToAnchor: [contentHolder trailingAnchor]]]];
	NSViewController * contentViewController = [[[NSViewController alloc] init] autorelease];
	[contentViewController setView: contentHolder];

	NSSplitViewItem * sidebarItem = [NSSplitViewItem sidebarWithViewController: sidebarViewController];
	[sidebarItem setMinimumThickness: 190.0];
	[sidebarItem setMaximumThickness: 360.0];
	[sidebarItem setCanCollapse: NO];
	NSSplitViewItem * contentItem = [NSSplitViewItem splitViewItemWithViewController: contentViewController];
	[contentItem setMinimumThickness: 560.0];

	splitViewController = [[NSSplitViewController alloc] init];
	[splitViewController addSplitViewItem: sidebarItem];
	[splitViewController addSplitViewItem: contentItem];

	[window setContentViewController: splitViewController];
	[window setContentSize: NSMakeSize(920.0, 560.0)];
	[[self window] setShowsToolbarButton:NO];
    [[self window] setContentMinSize: NSMakeSize(760.0, 430.0)];

	windowHasLoaded = TRUE;
}




- (void) dealloc {
	
	[toolbarIdentifiers release]; toolbarIdentifiers = nil;
	[toolbarViews release];       toolbarViews       = nil;
	[toolbarItems release];       toolbarItems       = nil;
	[contentSubview release];     contentSubview     = nil;
	[viewAnimation release];      viewAnimation      = nil;
	[splitViewController release];       splitViewController       = nil;
	[sidebarView release];               sidebarView               = nil;
	[sidebarSectionTable release];       sidebarSectionTable       = nil;
	[sidebarSectionIdentifiers release]; sidebarSectionIdentifiers = nil;
	[sidebarSectionList release];        sidebarSectionList        = nil;
	[originalViewSizes release];         originalViewSizes         = nil;
	[[NSNotificationCenter defaultCenter] removeObserver: self];

	
	[super dealloc];
}




#pragma mark -
#pragma mark Configuration


- (void)setupToolbar
{
	// Subclasses must override this method to add items to the
	// toolbar by calling -addView:label: or -addView:label:image:.
}




- (void)addView:(NSView *)view label:(NSString *)label
{
	[self addView:view
			label:label
			image:[NSImage imageNamed:label]];
}




- (void)addView:(NSView *) view label:(NSString *)label image:(NSImage *)image
{	
	NSString *identifier = [[label copy] autorelease];
	
	[toolbarIdentifiers addObject:identifier];
	[toolbarViews setObject:view forKey:identifier];
	if (  ! [view isKindOfClass: [NSNull class]]  ) {
		if (  ! originalViewSizes  ) {
			originalViewSizes = [[NSMutableDictionary alloc] init];
		}
		[originalViewSizes setObject: [NSValue valueWithSize: [view frame].size] forKey: identifier];
	}
	
	NSToolbarItem *item = [[[NSToolbarItem alloc] initWithItemIdentifier:identifier] autorelease];
	[item setLabel:label];
	if (  image  ) {
		[item setImage:image];
	}
	[item setTarget:self];
	[item setAction:@selector(toggleActivePreferenceView:)];
	
	[toolbarItems setObject:item forKey:identifier];
}




#pragma mark -
#pragma mark Accessor Methods


- (BOOL)crossFade
{
    return _crossFade;
}




- (void)setCrossFade:(BOOL)fade
{
    _crossFade = fade;
}




- (BOOL)shiftSlowsAnimation
{
    return _shiftSlowsAnimation;
}




- (void)setShiftSlowsAnimation:(BOOL)slows
{
    _shiftSlowsAnimation = slows;
}




#pragma mark -
#pragma mark Overriding Methods


// Override in subclass if desired
-(void) windowWillAppear
{
    
}


- (IBAction)showWindow:(id)sender
{
    // This forces the resources in the nib to load.
	(void)[self window];
    
	if ([[self window] toolbar] == nil) {
        [self setupToolbar];
        NSAssert (([toolbarIdentifiers count] > 0),
                  @"No items were added to the toolbar in -setupToolbar.");
		NSToolbar *toolbar = [[NSToolbar alloc] initWithIdentifier:@"DBPreferencesToolbar"];
		[toolbar setAllowsUserCustomization:NO];
		[toolbar setAutosavesConfiguration:NO];
		[toolbar setSizeMode:NSToolbarSizeModeDefault];
		[toolbar setDisplayMode:NSToolbarDisplayModeIconOnly];
		[toolbar setDelegate:self];
		[[self window] setToolbar:toolbar];
		[toolbar release];

		[self setupSidebar];
	}

	unsigned int ix = [UIHelper detailsWindowsViewIndexFromPreferencesWithCount: [toolbarIdentifiers count]];
	NSString * firstIdentifier = [toolbarIdentifiers objectAtIndex:ix];
	if (  [[toolbarViews objectForKey: firstIdentifier] isKindOfClass: [NSNull class]]  ) {
		firstIdentifier = [self primaryIdentifier];
	}
	[self displayViewForIdentifier:firstIdentifier animate:NO];

    [self windowWillAppear];
    
	[super showWindow:sender];
}




#pragma mark -
#pragma mark Toolbar


- (NSArray *)toolbarDefaultItemIdentifiers:(NSToolbar*)toolbar
{
    // Views are chosen from the sidebar, so the toolbar only holds the items without a view (e.g. the lock icon),
    // pushed to the trailing edge
    (void)toolbar;

	NSMutableArray * identifiers = [NSMutableArray arrayWithObject: NSToolbarFlexibleSpaceItemIdentifier];
	NSString * identifier;
	NSEnumerator * e = [toolbarIdentifiers objectEnumerator];
	while (  (identifier = [e nextObject])  ) {
		if (   [[toolbarViews objectForKey: identifier] isKindOfClass: [NSNull class]]
			&& [identifier isNotEqualTo: NSToolbarFlexibleSpaceItemIdentifier]  ) {
			[identifiers addObject: identifier];
		}
	}
	return identifiers;
}




- (NSArray *)toolbarAllowedItemIdentifiers:(NSToolbar*)toolbar
{
	return [self toolbarDefaultItemIdentifiers: toolbar];
}




- (NSArray *)toolbarSelectableItemIdentifiers:(NSToolbar *)toolbar
{
    (void)toolbar;

    return [NSArray array];
}




- (NSToolbarItem *)toolbar:(NSToolbar *)toolbar itemForItemIdentifier:(NSString *)identifier willBeInsertedIntoToolbar:(BOOL)willBeInserted 
{
    (void)toolbar;
    (void)willBeInserted;
    
    
	return [toolbarItems objectForKey:identifier];
}




- (void)toggleActivePreferenceView:(NSToolbarItem *)toolbarItem
{
	[self displayViewForIdentifier:[toolbarItem itemIdentifier] animate:YES];
}




// Override in subclass if desired
-(void) oldViewWillDisappear: (NSView *) view identifier: (NSString *) identifier
{
	(void) view;
	(void) identifier;
}


// Override in subclass if desired
-(void) newViewWillAppear: (NSView *) view identifier: (NSString *) identifier
{
	(void) view;
	(void) identifier;
}


// Override in subclass if desired
-(void) newViewDidAppear: (NSView *) view
{
	(void) view;
}


- (void)displayViewForIdentifier:(NSString *)identifier animate:(BOOL)animate
{	
	if (   [identifier isEqualToString: NSToolbarFlexibleSpaceItemIdentifier]
        || [identifier isEqualToString: @"LockIcon"]) {
		return;
	}
	
    // Find the view we want to display.
	NSView *newView = [toolbarViews objectForKey:identifier];
    
    // See if there are any visible views.
	NSView *oldView = nil;
	if ([[contentSubview subviews] count] > 0) {
        // Get a list of all of the views in the window. Usually at this
        // point there is just one visible view. But if the last fade
        // hasn't finished, we need to get rid of it now before we move on.
		NSEnumerator *subviewsEnum = [[contentSubview subviews] reverseObjectEnumerator];
		
        // The first one (last one added) is our visible view.
		oldView = [subviewsEnum nextObject];
		
        // Remove any others.
		NSView *reallyOldView = nil;
		while (  (reallyOldView = [subviewsEnum nextObject])  ) {
			[reallyOldView removeFromSuperviewWithoutNeedingDisplay];
		}
	}
	
	if (![newView isEqualTo:oldView]) {
		// The window does not resize itself for different views; layOutViewInContentArea: sizes and places each view
		[contentSubview addSubview:newView];
		[self layOutViewInContentArea: newView];
		[[self window] setInitialFirstResponder:newView];

		if (animate && [self crossFade])
			[self crossFadeView:oldView withView:newView];
		else {
			[oldView removeFromSuperviewWithoutNeedingDisplay];
			[newView setHidden:NO];
            [self newViewDidAppear: newView];
		}

        [[self window] setTitle:[self windowTitle: [[toolbarItems objectForKey:identifier] label]]];

    }

	[self updateSidebarSelectionForIdentifier: identifier];
}


- (BOOL)isHelpButton:(NSView *)view
{
	return (   [view isKindOfClass: [NSButton class]]
			&& ([(NSButton *)view bezelStyle] == NSBezelStyleHelpButton));
}


- (BOOL)viewResizesItsContent:(NSView *)view
{
	// A view with a visible subview that resizes with its width (such as Info's credits) can fill the content area.
	// (Empty text fields, such as Utilities' status messages, do not count.)
	NSView * subview;
	NSEnumerator * e = [[view subviews] objectEnumerator];
	while (  (subview = [e nextObject])  ) {
		if (   ([subview autoresizingMask] & NSViewWidthSizable) != 0
			&& ( ! [subview isHidden] )
			&& ( ! NSIsEmptyRect([self visibleRectOfControl: subview]) )  ) {
			return YES;
		}
	}
	return NO;
}


- (NSRect)visibleRectOfControl:(NSView *)view
{
	// The part of a control's frame that shows something: labels and buttons are often much wider than their text
	NSRect frame = [view frame];
	if (  [view isKindOfClass: [NSTextField class]]  ) {
		NSTextField * textField = (NSTextField *) view;
		if (  [[textField stringValue] length] == 0  ) {
			return NSZeroRect;
		}
		if (  ! [[textField cell] wraps]  ) {
			CGFloat width = MIN(NSWidth(frame), ceil([[textField cell] cellSize].width));
			switch (  [textField alignment]  ) {
				case NSTextAlignmentRight:
					frame.origin.x = NSMaxX(frame) - width;
					break;
				case NSTextAlignmentCenter:
					frame.origin.x = NSMidX(frame) - width / 2.0;
					break;
				default:
					break;
			}
			frame.size.width = width;
		}
	} else if (   [view isKindOfClass: [NSButton class]]
			   && ( ! [view isKindOfClass: [NSPopUpButton class]] )  ) {
		// A checkbox's title can be wider than its frame (it is drawn anyway), so this can be wider than the frame,
		// unless the title wraps
		if (  ! [[(NSButton *) view cell] wraps]  ) {
			frame.size.width = ceil([view fittingSize].width);
		}
	}
	return frame;
}


- (NSRect)usedRectOfViewWithIdentifier:(NSString *)identifier
{
	// The part of a view (at the size it was designed for) that shows its controls, ignoring help buttons, which
	// layOutViewInContentArea: moves to the left edge of this rectangle. Controls (or parts of them) to the left of the view
	// are not shown, but text can extend past its right edge.
	NSView * view = [toolbarViews objectForKey: identifier];
	NSSize size = [[originalViewSizes objectForKey: identifier] sizeValue];
	NSRect bounds = NSMakeRect(0.0, 0.0, CGFLOAT_MAX / 4.0, size.height);
	NSRect used = NSZeroRect;
	NSView * subview;
	NSEnumerator * e = [[view subviews] objectEnumerator];
	while (  (subview = [e nextObject])  ) {
		if (   ( ! [subview isHidden] )
			&& ( ! [self isHelpButton: subview] )  ) {
			NSRect frame = NSIntersectionRect([self visibleRectOfControl: subview], bounds);
			if (  ! NSIsEmptyRect(frame)  ) {
				used = (  NSIsEmptyRect(used)
						? frame
						: NSUnionRect(used, frame));
			}
		}
	}
	return (  NSIsEmptyRect(used)
			? NSMakeRect(0.0, 0.0, size.width, size.height)
			: used);
}


- (void)wrapLongControlsInViewWithIdentifier:(NSString *)identifier maximumWidth:(CGFloat)maximumWidth
{
	// Checkboxes whose titles would make the view's controls wider than maximumWidth get titles that wrap onto more lines.
	// Each keeps its top edge, and the controls below it move down by the height it gained. (The views have room for that.)
	// This keeps the window narrow for long translations.
	NSView * view = [toolbarViews objectForKey: identifier];
	NSRect used = [self usedRectOfViewWithIdentifier: identifier];
	CGFloat rightEdge = NSMinX(used) + maximumWidth;
	if (  NSMaxX(used) <= rightEdge  ) {
		return;
	}
	
	// From top to bottom, so moving controls down does not change which ones are still to be looked at
	NSArray * subviews = [[view subviews] sortedArrayUsingComparator: ^NSComparisonResult(NSView * a, NSView * b) {
		CGFloat aTop = NSMaxY([a frame]);
		CGFloat bTop = NSMaxY([b frame]);
		return (  (aTop > bTop)
				? NSOrderedAscending
				: (  (aTop < bTop)
				   ? NSOrderedDescending
				   : NSOrderedSame));
	}];
	
	NSView * subview;
	NSEnumerator * e = [subviews objectEnumerator];
	while (  (subview = [e nextObject])  ) {
		if (   [subview isHidden]
			|| ( ! [subview isKindOfClass: [NSButton class]] )
			|| [subview isKindOfClass: [NSPopUpButton class]]
			|| (NSMaxX([self visibleRectOfControl: subview]) <= rightEdge)  ) {
			continue;
		}
		
		NSButton * button = (NSButton *) subview;
		NSRect frame = [button frame];
		CGFloat width = rightEdge - NSMinX(frame);
		if (  width < 100.0  ) {
			continue;
		}
		NSButtonCell * cell = [button cell];
		[cell setWraps: YES];
		[cell setLineBreakMode: NSLineBreakByWordWrapping];
		CGFloat height = MAX(NSHeight(frame), ceil([cell cellSizeForBounds: NSMakeRect(0.0, 0.0, width, 10000.0)].height));
		CGFloat gained = height - NSHeight(frame);
		[button setFrame: NSMakeRect(NSMinX(frame), NSMaxY(frame) - height, width, height)];
		
		if (  gained > 0.0  ) {
			NSView * other;
			NSEnumerator * e2 = [[view subviews] objectEnumerator];
			while (  (other = [e2 nextObject])  ) {
				if (   (other != button)
					&& ( ! [self isHelpButton: other] )
					&& (NSMaxY([other frame]) <= NSMinY(frame) + 1.0)  ) {
					NSRect otherFrame = [other frame];
					otherFrame.origin.y -= gained;
					[other setFrame: otherFrame];
				}
			}
		}
	}
}


- (void)setMinimumContentWidthForViews
{
	NSString * wrapIdentifier;
	NSEnumerator * wrapEnum = [sidebarSectionIdentifiers objectEnumerator];
	while (  (wrapIdentifier = [wrapEnum nextObject])  ) {
		if (  ! [self viewResizesItsContent: [toolbarViews objectForKey: wrapIdentifier]]  ) {
			[self wrapLongControlsInViewWithIdentifier: wrapIdentifier maximumWidth: 640.0];
		}
	}
	
	// The content area must be wide enough for the controls of the widest view that does not resize them (see
	// layOutViewInContentArea:)
	CGFloat minimumWidth = 560.0;
	NSString * identifier;
	NSEnumerator * e = [sidebarSectionIdentifiers objectEnumerator];
	while (  (identifier = [e nextObject])  ) {
		if (  ! [self viewResizesItsContent: [toolbarViews objectForKey: identifier]]  ) {
			minimumWidth = MAX(minimumWidth, ceil(NSWidth([self usedRectOfViewWithIdentifier: identifier])) + 32.0);
		}
	}
	
	NSSplitViewItem * contentItem = [[splitViewController splitViewItems] lastObject];
	[contentItem setMinimumThickness: minimumWidth];
	
	NSSplitViewItem * sidebarItem = [[splitViewController splitViewItems] firstObject];
	CGFloat minimumWindowContentWidth = [sidebarItem minimumThickness] + minimumWidth;
	NSSize minSize = [[self window] contentMinSize];
	minSize.width = minimumWindowContentWidth;
	[[self window] setContentMinSize: minSize];
	
	NSRect contentRect = [[self window] contentRectForFrameRect: [[self window] frame]];
	CGFloat wantedWidth = NSWidth([sidebarView frame]) + minimumWidth;
	if (  NSWidth(contentRect) < wantedWidth  ) {
		contentRect.size.width = wantedWidth;
		[[self window] setFrame: [[self window] frameRectForContentRect: contentRect] display: NO];
	}
}


- (void)layOutViewInContentArea:(NSView *)view
{
	// The primary view fills the content area. The other views were designed for a wider window without a sidebar, and
	// their controls do not move to stay centered when they are resized. So they keep the size they were designed for, and
	// are placed so their controls are centered horizontally in the content area. They clip to their bounds, so controls
	// their layout keeps to the left of them (such as an unused "Last checked..." label) stay hidden.
	NSRect content = [contentSubview bounds];
	NSString * identifier = [[toolbarViews allKeysForObject: view] firstObject];
	NSSize size = [[originalViewSizes objectForKey: identifier] sizeValue];
	if (   [identifier isEqualToString: [self primaryIdentifier]]
		|| (size.width <= 0.0)
		|| [self viewResizesItsContent: view]  ) {
		[view setAutoresizingMask: (NSViewWidthSizable | NSViewHeightSizable)];
		[view setFrame: content];
		return;
	}
	
	// Not resized with the content area (resizing its controls back and forth does not keep their frames exactly);
	// contentSubviewFrameDidChange: places it again instead
	[view setAutoresizingMask: NSViewNotSizable];
	
	if (  [view respondsToSelector: @selector(setClipsToBounds:)]  ) {
		[view setClipsToBounds: YES];
	}
	NSRect used = [self usedRectOfViewWithIdentifier: identifier];
	CGFloat width = MAX(size.width, ceil(NSMaxX(used))); // Wide enough to show text that extends past its right edge
	[view setFrame: NSMakeRect(floor(NSMidX(content) - NSMidX(used)), 0.0, width, NSHeight(content))];
	
	// Help buttons go to the left edge of the controls, so they are not cut off
	NSView * subview;
	NSEnumerator * e = [[view subviews] objectEnumerator];
	while (  (subview = [e nextObject])  ) {
		if (  [self isHelpButton: subview]  ) {
			NSRect frame = [subview frame];
			frame.origin.x = NSMinX(used);
			[subview setFrame: frame];
		}
	}
}


- (void)contentSubviewFrameDidChange:(NSNotification *)notification
{
	(void) notification;
	
	NSView * view = [[contentSubview subviews] lastObject];
	if (  view  ) {
		[self layOutViewInContentArea: view];
	}
}


#pragma mark -
#pragma mark Sidebar


// Override in subclass if desired
- (NSView *)sidebarTopView
{
	return nil;
}


// Override in subclass if desired
- (NSView *)sidebarBottomView
{
	return nil;
}


// Override in subclass if desired
- (NSString *)sidebarSectionTitle
{
	return nil;
}


// Override in subclass if desired
- (void)sidebarDidSelectPrimaryView:(BOOL)isPrimary
{
	(void) isPrimary;
}


- (NSString *)primaryIdentifier
{
	NSString * identifier;
	NSEnumerator * e = [toolbarIdentifiers objectEnumerator];
	while (  (identifier = [e nextObject])  ) {
		if (  ! [[toolbarViews objectForKey: identifier] isKindOfClass: [NSNull class]]  ) {
			return identifier;
		}
	}
	return nil;
}


- (void)showPrimaryView
{
	[self displayViewForIdentifier: [self primaryIdentifier] animate: YES];
}


- (void)setupSidebar
{
	// The primary view (the first one added) is reached through -sidebarTopView; every other view gets a row
	NSString * primaryIdentifier = [self primaryIdentifier];
	[sidebarSectionIdentifiers release];
	sidebarSectionIdentifiers = [[NSMutableArray alloc] init];
	NSString * identifier;
	NSEnumerator * e = [toolbarIdentifiers objectEnumerator];
	while (  (identifier = [e nextObject])  ) {
		if (   ( ! [[toolbarViews objectForKey: identifier] isKindOfClass: [NSNull class]] )
			&& [identifier isNotEqualTo: primaryIdentifier]  ) {
			[sidebarSectionIdentifiers addObject: identifier];
		}
	}

	NSLayoutGuide * safeArea = [sidebarView safeAreaLayoutGuide];
	NSMutableArray * constraints = [NSMutableArray array];

	NSView * topView = [self sidebarTopView];
	NSLayoutYAxisAnchor * nextTop = [safeArea topAnchor];
	if (  topView  ) {
		[topView removeFromSuperview];
		[topView setTranslatesAutoresizingMaskIntoConstraints: NO];
		[sidebarView addSubview: topView];
		[constraints addObjectsFromArray: @[[[topView topAnchor]      constraintEqualToAnchor: nextTop],
											[[topView leadingAnchor]  constraintEqualToAnchor: [sidebarView leadingAnchor]],
											[[topView trailingAnchor] constraintEqualToAnchor: [sidebarView trailingAnchor]]]];
		nextTop = [topView bottomAnchor];
	}

	NSString * title = [self sidebarSectionTitle];
	if (  title  ) {
		NSTextField * heading = [NSTextField labelWithString: title];
		[heading setFont: [NSFont systemFontOfSize: [NSFont smallSystemFontSize] weight: NSFontWeightSemibold]];
		[heading setTextColor: [NSColor secondaryLabelColor]];
		[heading setTranslatesAutoresizingMaskIntoConstraints: NO];
		[sidebarView addSubview: heading];
		[constraints addObjectsFromArray: @[[[heading topAnchor]      constraintEqualToAnchor: nextTop constant: 18.0],
											[[heading leadingAnchor]  constraintEqualToAnchor: [sidebarView leadingAnchor] constant: 13.0],
											[[heading trailingAnchor] constraintLessThanOrEqualToAnchor: [sidebarView trailingAnchor] constant: -10.0]]];
		nextTop = [heading bottomAnchor];
	}

	[sidebarSectionTable release];
	sidebarSectionTable = [[NSTableView alloc] initWithFrame: NSMakeRect(0.0, 0.0, 240.0, 120.0)];
	NSTableColumn * column = [[[NSTableColumn alloc] initWithIdentifier: @"section"] autorelease];
	[column setResizingMask: NSTableColumnAutoresizingMask];
	[sidebarSectionTable addTableColumn: column];
	[sidebarSectionTable setHeaderView: nil];
	[sidebarSectionTable setStyle: NSTableViewStyleSourceList];
	[sidebarSectionTable setSelectionHighlightStyle: NSTableViewSelectionHighlightStyleSourceList];
	[sidebarSectionTable setBackgroundColor: [NSColor clearColor]];
	[sidebarSectionTable setColumnAutoresizingStyle: NSTableViewFirstColumnOnlyAutoresizingStyle];
	[sidebarSectionTable setRowSizeStyle: NSTableViewRowSizeStyleCustom];
	[sidebarSectionTable setRowHeight: 28.0];
	[sidebarSectionTable setIntercellSpacing: NSMakeSize(0.0, 0.0)];
	[sidebarSectionList release];
	sidebarSectionList = [[DBPrefsSidebarSectionList alloc] initWithController: self];
	[sidebarSectionTable setDataSource: sidebarSectionList];
	[sidebarSectionTable setDelegate: sidebarSectionList];
	
	// In a scroll view (which never scrolls) so the column is sized to the sidebar's width
	NSScrollView * sectionScrollView = [[[NSScrollView alloc] initWithFrame: [sidebarSectionTable frame]] autorelease];
	[sectionScrollView setDocumentView: sidebarSectionTable];
	[sectionScrollView setDrawsBackground: NO];
	[sectionScrollView setBorderType: NSNoBorder];
	[sectionScrollView setHasVerticalScroller: NO];
	[sectionScrollView setHasHorizontalScroller: NO];
	[sectionScrollView setVerticalScrollElasticity: NSScrollElasticityNone];
	[sectionScrollView setAutomaticallyAdjustsContentInsets: NO];
	[sectionScrollView setTranslatesAutoresizingMaskIntoConstraints: NO];
	[sidebarView addSubview: sectionScrollView];
	[sidebarSectionTable reloadData];
	// The table's height includes the padding its (source list) style adds above and below the rows, so it is
	// measured after the rows are laid out; the scroll view is exactly that high, so it does not scroll
	[sidebarSectionTable tile];
	CGFloat tableHeight = NSHeight([sidebarSectionTable frame]);
	[constraints addObjectsFromArray: @[[[sectionScrollView topAnchor]      constraintEqualToAnchor: nextTop constant: 4.0],
										[[sectionScrollView leadingAnchor]  constraintEqualToAnchor: [sidebarView leadingAnchor]],
										[[sectionScrollView trailingAnchor] constraintEqualToAnchor: [sidebarView trailingAnchor]],
										[[sectionScrollView heightAnchor]   constraintEqualToConstant: tableHeight]]];
	
	NSView * bottomView = [self sidebarBottomView];
	if (  bottomView  ) {
		// A separator, then the bar at the very bottom
		NSBox * separator = [[[NSBox alloc] init] autorelease];
		[separator setBoxType: NSBoxSeparator];
		[separator setTranslatesAutoresizingMaskIntoConstraints: NO];
		[bottomView setTranslatesAutoresizingMaskIntoConstraints: NO];
		[sidebarView addSubview: separator];
		[sidebarView addSubview: bottomView];
		[constraints addObjectsFromArray: @[[[separator topAnchor]       constraintEqualToAnchor: [sectionScrollView bottomAnchor] constant: 10.0],
											[[separator leadingAnchor]   constraintEqualToAnchor: [sidebarView leadingAnchor]  constant: 10.0],
											[[separator trailingAnchor]  constraintEqualToAnchor: [sidebarView trailingAnchor] constant: -10.0],
											[[bottomView topAnchor]      constraintEqualToAnchor: [separator bottomAnchor] constant: 6.0],
											[[bottomView leadingAnchor]  constraintEqualToAnchor: [sidebarView leadingAnchor]  constant: 10.0],
											[[bottomView trailingAnchor] constraintLessThanOrEqualToAnchor: [sidebarView trailingAnchor] constant: -10.0],
											[[bottomView bottomAnchor]   constraintEqualToAnchor: [sidebarView bottomAnchor] constant: -10.0]]];
	} else {
		[constraints addObject: [[sectionScrollView bottomAnchor] constraintEqualToAnchor: [sidebarView bottomAnchor] constant: -12.0]];
	}
	[NSLayoutConstraint activateConstraints: constraints];
	
	[self setMinimumContentWidthForViews];
	
	// Keep the shown view's content centered when the content area changes size
	[contentSubview setPostsFrameChangedNotifications: YES];
	[[NSNotificationCenter defaultCenter] addObserver: self
											 selector: @selector(contentSubviewFrameDidChange:)
												 name: NSViewFrameDidChangeNotification
											   object: contentSubview];
}


- (void)updateSidebarSelectionForIdentifier:(NSString *)identifier
{
	if (  ! sidebarSectionTable  ) {
		return;
	}

	updatingSidebarSelection = TRUE;
	NSUInteger row = [sidebarSectionIdentifiers indexOfObject: identifier];
	if (  row == NSNotFound  ) {
		[sidebarSectionTable deselectAll: self];
	} else {
		[sidebarSectionTable selectRowIndexes: [NSIndexSet indexSetWithIndex: row] byExtendingSelection: NO];
	}
	updatingSidebarSelection = FALSE;

	[self sidebarDidSelectPrimaryView: [identifier isEqualToString: [self primaryIdentifier]]];
}


- (NSInteger)sidebarSectionCount
{
	return (NSInteger)[sidebarSectionIdentifiers count];
}


- (NSView *)sidebarCellForTableView:(NSTableView *)tableView row:(NSInteger)row
{
	NSTableCellView * cell = [tableView makeViewWithIdentifier: @"sidebarSectionCell" owner: self];
	if (  ! cell  ) {
		cell = [[[NSTableCellView alloc] initWithFrame: NSMakeRect(0.0, 0.0, 200.0, 24.0)] autorelease];
		[cell setIdentifier: @"sidebarSectionCell"];

		NSImageView * imageView = [[[NSImageView alloc] init] autorelease];
		[imageView setTranslatesAutoresizingMaskIntoConstraints: NO];
		[imageView setSymbolConfiguration: [NSImageSymbolConfiguration configurationWithScale: NSImageSymbolScaleMedium]];
		[cell addSubview: imageView];
		[cell setImageView: imageView];

		NSTextField * textField = [NSTextField labelWithString: @""];
		[textField setTranslatesAutoresizingMaskIntoConstraints: NO];
		[textField setLineBreakMode: NSLineBreakByTruncatingTail];
		[cell addSubview: textField];
		[cell setTextField: textField];

		[NSLayoutConstraint activateConstraints: @[[[imageView leadingAnchor]  constraintEqualToAnchor: [cell leadingAnchor] constant: 2.0],
												   [[imageView centerYAnchor]  constraintEqualToAnchor: [cell centerYAnchor]],
												   [[imageView widthAnchor]    constraintEqualToConstant: 18.0],
												   [[textField leadingAnchor]  constraintEqualToAnchor: [imageView trailingAnchor] constant: 6.0],
												   [[textField trailingAnchor] constraintEqualToAnchor: [cell trailingAnchor] constant: -4.0],
												   [[textField centerYAnchor]  constraintEqualToAnchor: [cell centerYAnchor]]]];
	}

	NSToolbarItem * item = [toolbarItems objectForKey: [sidebarSectionIdentifiers objectAtIndex: (NSUInteger)row]];
	[[cell imageView] setImage: [item image]];
	[[cell textField] setStringValue: [item label]];
	return cell;
}


- (void)sidebarSectionSelectionDidChange
{
	if (  updatingSidebarSelection  ) {
		return;
	}

	NSInteger row = [sidebarSectionTable selectedRow];
	if (  row >= 0  ) {
		[self displayViewForIdentifier: [sidebarSectionIdentifiers objectAtIndex: (NSUInteger)row] animate: YES];
	}
}


- (NSString *)windowTitle: (NSString *) currentItemLabel
// Subclasses can override this.
{
    return [[currentItemLabel retain] autorelease];
}


#pragma mark -
#pragma mark Cross-Fading Methods


- (void)crossFadeView:(NSView *)oldView withView:(NSView *)newView
{
	[viewAnimation stopAnimation];
	
    NSString * identifier = nil;
    NSArray * keyArray = [toolbarViews allKeysForObject: oldView];
    if (  [keyArray count] == 1  ) {
        identifier = [keyArray objectAtIndex: 0];
    }
    [self oldViewWillDisappear: oldView identifier: identifier];
    
    identifier = nil;
    keyArray = [toolbarViews allKeysForObject: newView];
    if (  [keyArray count] == 1  ) {
        identifier = [keyArray objectAtIndex: 0];
    }
    [self newViewWillAppear: newView identifier: identifier];
    
	[viewAnimation setDuration: 0.0];

    NSDictionary * fadeOutDictionary = @{NSViewAnimationTargetKey: NSNullIfNil(oldView),
                                        NSViewAnimationEffectKey: NSViewAnimationFadeOutEffect};

    NSDictionary * fadeInDictionary = @{NSViewAnimationTargetKey: newView,
                                       NSViewAnimationEffectKey: NSViewAnimationFadeInEffect};

    NSArray * animationArray = @[fadeOutDictionary, fadeInDictionary];

    [viewAnimation setViewAnimations:animationArray];
	[viewAnimation startAnimation];
}


- (void)animationDidEnd:(NSAnimation *)animation
{
	NSView *subview;
	
    // Get a list of all of the views in the window. Hopefully
    // at this point there are two. One is visible and one is hidden.
	NSEnumerator *subviewsEnum = [[contentSubview subviews] reverseObjectEnumerator];
	
    // This is our visible view. Get past it.
	NSView * visibleView = [subviewsEnum nextObject];
    [self newViewDidAppear: visibleView]; 
    
    // Remove everything else. There should be just one, but
    // if the user does a lot of fast clicking, we might have
    // more than one to remove.
	while (  (subview = [subviewsEnum nextObject])  ) {
		[subview removeFromSuperviewWithoutNeedingDisplay];
	}
    
	(void)animation;
}




- (NSRect)frameForView:(NSView *)view
// Calculate the window size for the new view.
{
	NSRect windowFrame = [[self window] frame];
	NSRect contentRect = [[self window] contentRectForFrameRect:windowFrame];
	float windowTitleAndToolbarHeight = NSHeight(windowFrame) - NSHeight(contentRect);
    
	windowFrame.size.height = NSHeight([view frame]) + windowTitleAndToolbarHeight;
	windowFrame.size.width = NSWidth([view frame]);
	windowFrame.origin.y = NSMaxY([[self window] frame]) - NSHeight(windowFrame);
	
	return windowFrame;
}

-(BOOL)windowHasLoaded {
	return windowHasLoaded;
}

@end
