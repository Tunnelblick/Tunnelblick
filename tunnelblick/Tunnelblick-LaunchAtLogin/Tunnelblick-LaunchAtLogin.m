/*
 * Copyright 2023 by Jonathan K. Bullard. All rights reserved.

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

// Launch Tunnelblick if:
//    A. Tunnelblick has disabled network access; or
//    B. The 'launchAtNextLogin' preference is "1"; or
//    C. OpenVPN is running or is about to be run.
//
// The 'launchAtNextLogin' preference is set to "1" when you launch Tunnelblick if the 'doNotLaunchOnLogin' preference is not "1".
// The 'launchAtNextLogin' preference is set to "0" when you quit Tunnelblick and you are not logging out.


#import <Foundation/Foundation.h>

#import "../defines.h"
#import "../NSFileManager+TB.h"
#import "../sharedRoutines.h"

int main(int argc, const char * argv[]) {

    (void) argc;
    (void) argv;
    
    return 0;
}

// The following routine is referenced in SharedRoutines.m, but in a routine not used by this program
void appendLog(NSString * msg)
{
    NSLog(@"%@", msg);
}

// The following variable is referenced in SharedRoutines.m, but in a routine not used by this program

NSString       * gDeployPath = nil;
