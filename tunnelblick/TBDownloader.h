/*
 * Copyright 2024 Jonathan K. Bullard. All rights reserved.
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

/*
 * This class simplifies downloading files via http/https.
 *
 * 1. alloc/init an instance
 *
 * 2. Set the required parameters:
 *
 *      urlString
 *      contents
 *      finishedSelector
 *      delegate
 *
 *    Set the optional parameters as desired:
 *
 *      expectedLength (defaults to not known)
 *      maximumLength (defaults to no maximum)
 *      progressSelector (defaults to not report progress)
 *
 * 2. Invoke startDownload
 *
 * 3. Each time data is received, if expectedLength and progressSelector
 *    are both set, then the progressSelector method of the delegate
 *    will be invoked with one argument: an [NSNumber numberWithDouble] containing
 *    the percentage of the expected download that has been received.
 *
 * 4. When the download is complete, has been stopped, or if an error occurs,
 *    the finishedSelector method of the delegate will be invoked with one
 *    argument: nil (if there was no error), or an NSString with an error message.
 *
 * At any point, the "stopDownload" method may be invoked to cancel the download.
 * If the cancellation occurred without error, the error message sent to the
 * finishedSelector method of the delegate will be "Cancelled".
 *
 * At any point, the "abortDownload" method may be invoked to cancel the download.
 * No user-visible notice of the abort will be done.
 *
 */


#import <Foundation/Foundation.h>

#import "defines.h"

NS_ASSUME_NONNULL_BEGIN

@interface TBDownloader : NSObject

{
    // Parameters that MUST be set

    NSString *      urlString;           // URL string (e.g., "https://tunnelblick.net/appcast-b.rss"
    NSMutableData * contents;            // Downloaded data
    SEL             finishedSelector;    // Method to invoke when download *: (void) finished: (nullable NSString *) errorMessage;
    id              delegate;            // What instance to invoke with selectors

    // Parameters that MAY be set

    SEL             progressSelector;    // Method to invoke as download progresses: (void) *: (double) progressPercentage;
    long long       expectedLength;      // Expected size of download in bytes, or 0 if unknown
    long long       maximumLength;       // Maximum size allowed for download in bytes, or 0 for no maximum

    // Private parameters

    BOOL              currentlyDownloading;   // TRUE iff downloading
    NSURLConnection * connection;             // Our connection
    NSTimer         * retryTimer;             // Timer to retry download later
}

-(TBDownloader *) init;

-(void) startDownload;

-(void) stopDownload;

-(void) abortDownload;

TBPROPERTY(NSString *,      urlString,        setUrlString)
TBPROPERTY(long long,       expectedLength,   setExpectedLength)
TBPROPERTY(long long,       maximumLength,    setMaximumLength)
TBPROPERTY(NSMutableData *, contents,         setContents)
TBPROPERTY(SEL,             progressSelector, setProgressSelector)
TBPROPERTY(SEL,             finishedSelector, setFinishedSelector)
TBPROPERTY(id,              delegate,         setDelegate)

@end

NS_ASSUME_NONNULL_END
