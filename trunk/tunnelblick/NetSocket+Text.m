/*
 *  Created by Dirk Theisen on 17.05.05.
 *  Copyright 2005 Dirk Theisen. All rights reserved.
 *
 *  This program is free software; you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License version 2
 *  as published by the Free Software Foundation.
 *
 *  This program is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License
 *  along with this program (see the file COPYING included with this
 *  distribution); if not, write to the Free Software Foundation, Inc.,
 *  59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
 */


#import "NetSocket+Text.h"


@implementation NetSocket (TextHandling)

- (NSString*) readLine
/*" Returns nil if no complete line is available, a line of text otherwise. The line has to be terminated with the canonical line feed characters (\r\n). Currently only supports 8 bit char sets based on ASCII. "*/
{
    NSString*   result = nil;
    NSData*     data   = [self peekData];
    const char* peek   = [data bytes];
    unsigned    max    = [data length];
    unsigned    i      = 0;
    // search for CR:
    while (i<max) {
        BOOL foundCR = (peek[i]=='\r');
        BOOL foundLF = (i+1<max && peek[i+1]=='\n');
        if (foundCR || foundLF) {
            // We found a line feed:
            unsigned resultLength = i;
            result = [self readString: NSISOLatin1StringEncoding amount: resultLength];
            // skip LF, if neccessary:
            i++;
            if (foundCR && foundLF) {
                i++; // skip any LF after a CR
            }
            [self read: NULL amount: i-resultLength]; // skip 1 or two chars
            return result;
        }
        i++;
    }
    return result;
}

@end
