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

#import "TBDownloader.h"

@implementation TBDownloader

//********************************************************************************
//
// EXTERNAL METHODS

-(TBDownloader *) init {

    self = [super init];
    return self;
}

-(void) dealloc {

    [urlString  release];
    [contents   release];
    [delegate   release];

    [connection cancel];
    [connection release];

    [super dealloc];
}

-(void) startDownload {

    if (   ( ! self.urlString)
        || ( ! self.contents)
        || ( ! self.finishedSelector)
        || ( ! self.delegate)
        ) {
        [self indicateFinishedWithMessage: @"ERROR: startDownload: Not all required parameters have not been set"];
        return;
    }

    if (  self.currentlyDownloading  ) {
        [self indicateFinishedWithMessage: @"ERROR: startDownload: Ignoring because already downloading"];
        return;
    }

    NSURL * url = [NSURL URLWithString: self.urlString];
    if (  ! url  ) {
        [self indicateFinishedWithMessage: [NSString stringWithFormat:
                                            @"ERROR: startDownload: Cannot get NSURL from '%@'",
                                            self.urlString]];
        return;
    }

    NSURLRequest * request = [NSURLRequest requestWithURL: url];
    if (  ! request  ) {
        [self indicateFinishedWithMessage: [NSString stringWithFormat:
                                            @"ERROR: startDownload: Cannot get NSURLRequest from '%@'",
                                            self.urlString]];
        return;
    }

    [self indicateProgress];

    [self setCurrentlyDownloading: YES];

    connection = [[NSURLConnection alloc] initWithRequest: request  delegate: self startImmediately: YES];
    if (  ! connection  ) {
        [self indicateFinishedWithMessage: [NSString stringWithFormat:
                                            @"ERROR: startDownload: Cannot get NSURLConnection from '%@'",
                                            self.urlString]];
        return;
    }
}

-(void) stopDownload {

    if (  ! self.currentlyDownloading  ) {
        [self indicateFinishedWithMessage: @"ERROR: stopDownload: not currently downloading"];
        return;
    }

    [connection cancel];
    [self appendUpdaterLog: [NSString stringWithFormat:
                           @"Cancelled downloading %@",
                          self.urlString]];
    [self indicateFinishedWithMessage: @"Cancelled"];
}


//********************************************************************************
//
// INTERNAL METHODS

-(void) indicateFinishedWithMessage: (nullable NSString *) message {

    [self setCurrentlyDownloading: NO];
    [self.delegate performSelector: self.finishedSelector withObject: message];
}

-(void) indicateProgress {

    if (   (self.expectedLength != 0)
        && progressSelector) {

        double percentage = 100.0 * (double)self.contents.length / (double)self.expectedLength;
        [self.delegate performSelector: self.progressSelector withObject: [NSNumber numberWithDouble: percentage]];
    }
}

-(void) appendUpdaterLog: (NSString *) message {

    [self.delegate appendUpdaterLog: message];
}

-(BOOL) lengthIsTooLarge: (long long) length {

    BOOL tooLarge = FALSE;
    if (   (self.expectedLength != 0)
        && (length > self.expectedLength)  ) {
        tooLarge = TRUE;
    }

    if (   (self.maximumLength != 0)
        && (length > self.maximumLength)  ) {
        tooLarge = TRUE;
    }

    return tooLarge;
}


//********************************************************************************
//
// METHODS INVOKED BY NSURLConnection

-(void) connection: (NSURLConnection *)   connection
didReceiveResponse: (NSHTTPURLResponse *) response {

    if (connection != self.connection  ) {
        [self appendUpdaterLog: @"connection:didReceiveResponse: Ignored because not our connection"];
        return;
    }

    if (  ! self.currentlyDownloading  ) {
        [self appendUpdaterLog: @"connection:didReceiveResponse: Ignored because not downloading"];
        return;
    }

    if (  response.statusCode != 200  ) {
        [connection cancel];
        [self indicateFinishedWithMessage:
         [NSString stringWithFormat:
          @"ERROR: connection:didReceiveResponse: Download status code should be 200 but was %ld (%@) for '%@'",
          response.statusCode, [NSHTTPURLResponse localizedStringForStatusCode: response.statusCode], self.urlString]];
        return;
    }

    long long length = response.expectedContentLength;

    if (  length != NSURLResponseUnknownLength  ) {

        if (  [self lengthIsTooLarge: length]  ) {
            [connection cancel];
            [self indicateFinishedWithMessage:
             [NSString stringWithFormat:
              @"ERROR: connection:didReceiveResponse: Download is too large (%lld bytes); expected = %lld, maximum = %lld bytes",
              length, self.expectedLength, self.maximumLength]];
        }
    }
}

-(void) connection: (NSURLConnection *) connection
    didReceiveData: (NSData *)          data {

    if (connection != self.connection  ) {
        [self appendUpdaterLog: @"connection:didReceiveData: Ignored because not our connection"];
        return;
    }

    if (  ! self.currentlyDownloading  ) {
        [self appendUpdaterLog: @"connection:didReceiveResponse: Ignored because not downloading"];
        return;
    }

    long long lengthIncludingThisData = self.contents.length + data.length;

    if (  [self lengthIsTooLarge: lengthIncludingThisData]  ) {
        [connection cancel];
        [self indicateFinishedWithMessage:
         [NSString stringWithFormat:
          @"ERROR: connection:didReceiveResponse: Download is too large (%lld bytes); expected = %lld, maximum = %lld bytes",
          lengthIncludingThisData, self.expectedLength, self.maximumLength]];
    }

    [self.contents appendData: data];

    [self indicateProgress];
}

-(void) connectionDidFinishLoading: (NSURLConnection *) connection {

    if (connection != self.connection  ) {
        [self appendUpdaterLog: @"connectionDidFinishLoading: Ignored because not our connection"];
        return;
    }

    if (  ! self.currentlyDownloading  ) {
        [self appendUpdaterLog: @"connection:didReceiveResponse: Ignored because not downloading"];
        return;
    }

    [self indicateProgress];

    long long length = (long long)self.contents.length;

    NSString * message = (   (self.expectedLength == 0)
                          || (length == self.expectedLength)
                          ? nil
                          : [NSString stringWithFormat:
                             @"Received %lu bytes of update data, expected %lld",
                             (unsigned long)self.contents.length, self.expectedLength]);
    [self indicateFinishedWithMessage: message];
}

-(void) connection: (NSURLConnection *) connection
  didFailWithError: (NSError *)         err {

    if (connection != self.connection  ) {
        [self appendUpdaterLog: @"connection:didFailWithError: Ignored because not our connection"];
        return;
    }

    if (  ! self.currentlyDownloading  ) {
        [self appendUpdaterLog: @"connection:didFailWithError: Ignored because not downloading"];
        return;
    }

    [self indicateProgress];

    [self indicateFinishedWithMessage: [NSString stringWithFormat: @"connection:didFailWithError: %@", err]];
}


//********************************************************************************
//
// GETTERS & SETTERS

TBSYNTHESIZE_OBJECT(retain, NSString *,      urlString,        setUrlString)
TBSYNTHESIZE_NONOBJECT(long long,            expectedLength,   setExpectedLength)
TBSYNTHESIZE_NONOBJECT(long long,            maximumLength,    setMaximumLength)
TBSYNTHESIZE_OBJECT(retain, NSMutableData *, contents,         setContents)
TBSYNTHESIZE_NONOBJECT(SEL,                  progressSelector, setProgressSelector)
TBSYNTHESIZE_NONOBJECT(SEL,                  finishedSelector, setFinishedSelector)
TBSYNTHESIZE_OBJECT(retain, id,              delegate,         setDelegate)

TBSYNTHESIZE_NONOBJECT(     BOOL,              currentlyDownloading, setCurrentlyDownloading)
TBSYNTHESIZE_OBJECT(retain, NSURLConnection *, connection,           setConnection)

@end


