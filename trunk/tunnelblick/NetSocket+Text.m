//
//  NetSocket+Text.m
//  openVPNGui
//
//  Created by Dirk Theisen on 17.05.05.
//  Copyright 2005 Dirk Theisen. All rights reserved.
/*
 * Permission to use, copy, modify, and distribute this software for any
 * purpose with or without fee is hereby granted, provided that the above
 * copyright notice and this permission notice appear in all copies.
 *
 * THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
 * WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
 * MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
 * ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
 * WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
 * ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
 * OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
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
