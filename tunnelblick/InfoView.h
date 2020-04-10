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


#import "defines.h"

@interface InfoView : NSView {
    
    IBOutlet NSImageView        * infoLogoIV;
    
    IBOutlet NSTextFieldCell    * infoVersionTFC;
    
    IBOutlet NSTextView         * infoDescriptionTV;
    IBOutlet NSScrollView       * infoDescriptionSV;

    IBOutlet NSTextView         * infoCreditTV;
    IBOutlet NSScrollView       * infoCreditSV;

    IBOutlet NSTextFieldCell    * infoCopyrightTFC;
    
    NSImage                     * logo;
    
    NSTimer                     * scrollTimer;
    NSTimeInterval                startTime;
    CGFloat                       requestedPosition;
    CGFloat                       lastPosition;
    BOOL                          restartAtTop;
}

-(void) oldViewWillDisappear: (NSView *) view identifier: (NSString *) identifier;
-(void) newViewWillAppear:    (NSView *) view identifier: (NSString *) identifier;
-(void) newViewDidAppear:     (NSView *) view;

TBPROPERTY_READONLY(NSTextFieldCell *, infoVersionTFC)
TBPROPERTY(NSTimer *, scrollTimer, setScrollTimer)

@end
