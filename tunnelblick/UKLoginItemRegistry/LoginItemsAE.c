// From http://developer.apple.com/mac/library/samplecode/LoginItemsAE/listing1.html
/*
    File:        LoginItemsAE.c

    Contains:    Login items manipulation via Apple events.

    Copyright:    Copyright (c) 2005 by Apple Computer, Inc., All Rights Reserved.

    Disclaimer:    IMPORTANT:  This Apple software is supplied to you by Apple Computer, Inc.
                ("Apple") in consideration of your agreement to the following terms, and your
                use, installation, modification or redistribution of this Apple software
                constitutes acceptance of these terms.  If you do not agree with these terms,
                please do not use, install, modify or redistribute this Apple software.

                In consideration of your agreement to abide by the following terms, and subject
                to these terms, Apple grants you a personal, non-exclusive license, under Apple's
                copyrights in this original Apple software (the "Apple Software"), to use,
                reproduce, modify and redistribute the Apple Software, with or without
                modifications, in source and/or binary forms; provided that if you redistribute
                the Apple Software in its entirety and without modifications, you must retain
                this notice and the following text and disclaimers in all such redistributions of
                the Apple Software.  Neither the name, trademarks, service marks or logos of
                Apple Computer, Inc. may be used to endorse or promote products derived from the
                Apple Software without specific prior written permission from Apple.  Except as
                expressly stated in this notice, no other rights or licenses, express or implied,
                are granted by Apple herein, including but not limited to any patent rights that
                may be infringed by your derivative works or by other works in which the Apple
                Software may be incorporated.

                The Apple Software is provided by Apple on an "AS IS" basis.  APPLE MAKES NO
                WARRANTIES, EXPRESS OR IMPLIED, INCLUDING WITHOUT LIMITATION THE IMPLIED
                WARRANTIES OF NON-INFRINGEMENT, MERCHANTABILITY AND FITNESS FOR A PARTICULAR
                PURPOSE, REGARDING THE APPLE SOFTWARE OR ITS USE AND OPERATION ALONE OR IN
                COMBINATION WITH YOUR PRODUCTS.

                IN NO EVENT SHALL APPLE BE LIABLE FOR ANY SPECIAL, INDIRECT, INCIDENTAL OR
                CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE
                GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
                ARISING IN ANY WAY OUT OF THE USE, REPRODUCTION, MODIFICATION AND/OR DISTRIBUTION
                OF THE APPLE SOFTWARE, HOWEVER CAUSED AND WHETHER UNDER THEORY OF CONTRACT, TORT
                (INCLUDING NEGLIGENCE), STRICT LIABILITY OR OTHERWISE, EVEN IF APPLE HAS BEEN
                ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

    Change History (most recent first):

$Log: LoginItemsAE.c,v $
Revision 1.1  2005/09/27 12:29:26  eskimo1
First checked in.


*/

/////////////////////////////////////////////////////////////////

// Our prototypes

#include "LoginItemsAE.h"

#if MAC_OS_X_VERSION_MIN_REQUIRED < MAC_OS_X_VERSION_10_5

// System interfaces

// We need to pull in all of Carbon just to get the definition of 
// pProperties.  *sigh*  This is purely a compile-time dependency, 
// which is why we include it in the implementation and not the 
// header.

#include <Carbon/Carbon.h>

#include <string.h>

/////////////////////////////////////////////////////////////////
#pragma mark ***** Apple event utilities

enum {
    kSystemEventsCreator = 'sevs'
};

static OSStatus LaunchSystemEvents(ProcessSerialNumber *psnPtr)
    // Launches the "System Events" process.
{
    OSStatus             err;
    FSRef                appRef;
    
    assert(psnPtr != NULL);

    // Ask Launch Services to find System Events by creator.
    
    err = LSFindApplicationForInfo(
        kSystemEventsCreator,
        NULL,
        NULL,
        &appRef,
        NULL
    );

    // Launch it!
    
    if (err == noErr) {
        if ( LSOpenApplication != NULL ) {
            LSApplicationParameters     appParams;
            
            // Do it the easy way on 10.4 and later.
            
            memset(&appParams, 0, sizeof(appParams));
            appParams.version = 0;
            appParams.flags = kLSLaunchDefaults;
            appParams.application = &appRef;
            
            err = LSOpenApplication(&appParams, psnPtr);
        } else {
            FSSpec                appSpec;
            LaunchParamBlockRec lpb;
            
            // Do it the compatible way on earlier systems.
            
            // I launch System Events using LaunchApplication, rather than 
            // Launch Services, because LaunchApplication gives me back 
            // the ProcessSerialNumber.  Unfortunately this requires me to 
            // get an FSSpec for the application because there's no 
            // FSRef version of Launch Application.
            
            if (err == noErr) {
                err = FSGetCatalogInfo(&appRef, kFSCatInfoNone, NULL, NULL, &appSpec, NULL);
            }
            if (err == noErr) {
                memset(&lpb, 0, sizeof(lpb));
                lpb.launchBlockID      = extendedBlock;
                lpb.launchEPBLength    = extendedBlockLen;
                lpb.launchControlFlags = launchContinue | launchNoFileFlags;
                lpb.launchAppSpec      = &appSpec;
                
                err = LaunchApplication(&lpb);
            }
            if (err == noErr) {
                *psnPtr = lpb.launchProcessSN;
            }
        }
    }

    return err;
}

static OSStatus FindSystemEvents(ProcessSerialNumber *psnPtr)
    // Finds the "System Events" process or, if it's not 
    // running, launches it.
{
    OSStatus        err;
    Boolean            found;
    ProcessInfoRec    info;
    
    assert(psnPtr != NULL);

    psnPtr->lowLongOfPSN    = kNoProcess;
    psnPtr->highLongOfPSN    = kNoProcess;

    do {
        err = GetNextProcess(psnPtr);
        if (err == noErr) {    
            memset(&info, 0, sizeof(info));
            err = GetProcessInformation(psnPtr, &info);
        }
        if (err == noErr) {
            found = (info.processSignature == kSystemEventsCreator);
        }
    } while ( (err == noErr) && ! found );

    if (err == procNotFound) {
        err = LaunchSystemEvents(psnPtr);
    }
    return err;
}

#if ! defined(LOGIN_ITEMS_AE_PRINT_DESC)
    #if defined(NDEBUG)
        #define LOGIN_ITEMS_AE_PRINT_DESC 0
    #else
        #define LOGIN_ITEMS_AE_PRINT_DESC 0         // change this to 1 to get output in debug build
    #endif
#endif

static OSStatus SendAppleEvent(const AEDesc *event, AEDesc *reply)
    // This is the bottleneck routine we use for sending Apple events.
    // It has a number of neato features.
    // 
    // o It use the "AEMach.h" routine AESendMessage because that allows 
    //   us to do an RPC without having to field UI events while waiting 
    //   for the reply.  Yay for Mac macOS!
    //
    // o It automatically extracts the error from the reply.
    //
    // o It allows you to enable printing of events and their replies 
    //   for debugging purposes.
{
    static const long kAETimeoutTicks = 5 * 60;
    OSStatus     err;
    OSErr        replyErr;
    DescType    junkType;
    Size        junkSize;

    // Normally I don't declare function prototypes in local scope, 
    // but I made this exception because I don't want anyone except 
    // for this routine calling GDBPrintAEDesc.  This routine takes 
    // care to only link with the routine when debugging is enabled; 
    // everyone else might not be so careful.
    
    #if LOGIN_ITEMS_AE_PRINT_DESC

        extern void GDBPrintAEDesc(const AEDesc *desc);
            // This is private system function used to print a 
            // textual representation of an AEDesc to stderr.  
            // It's very handy when debugging, and is meant only 
            // for that purpose.  It's only available to Mach-O 
            // clients.  We use it when debugging *only*.

    #endif

    assert(event != NULL);
    assert(reply != NULL);

    #if LOGIN_ITEMS_AE_PRINT_DESC
        GDBPrintAEDesc(event);
    #endif

    err = AESendMessage(event, reply, kAEWaitReply, kAETimeoutTicks);

    #if LOGIN_ITEMS_AE_PRINT_DESC
        GDBPrintAEDesc(reply);
    #endif

    // Extract any error from the Apple event handler via the 
    // keyErrorNumber parameter of the reply.
    
    if ( (err == noErr) && (reply->descriptorType != typeNull) ) {
        err = AEGetParamPtr(
            reply, 
            keyErrorNumber, 
            typeShortInteger, 
            &junkType,
            &replyErr, 
            sizeof(replyErr), 
            &junkSize
        );
        
        if (err == errAEDescNotFound ) {
            err = noErr;
        } else {
            err = replyErr;
        }
    }
    
    return err;
}

/////////////////////////////////////////////////////////////////
#pragma mark ***** Constants from Login Items AppleScript Dictionary

enum {
    cLoginItem = 'logi',
    
    propPath   = 'ppth',
    propHidden = 'hidn'
};

/////////////////////////////////////////////////////////////////
#pragma mark ***** Public routines (and helpers)

static const AEDesc kAENull = { typeNull, NULL };

static void AEDisposeDescQ(AEDesc *descPtr)
{
    OSStatus    junk;
    
    junk = AEDisposeDesc(descPtr);
    assert(junk == noErr);
    *descPtr = kAENull;
}

static void CFQRelease(CFTypeRef cf)
{
    if (cf != NULL) {
        CFRelease(cf);
    }
}

static OSStatus CreateCFArrayFromAEDescList(
    const AEDescList *    descList, 
    CFArrayRef *        itemsPtr
)
    // This routine's input is an AEDescList that contains replies 
    // from the "properties of every login item" event.  Each element 
    // of the list is an AERecord with two important properties, 
    // "path" and "hidden".  This routine creates a CFArray that 
    // corresponds to this list.  Each element of the CFArray 
    // contains two properties, kLIAEURL and 
    // kLIAEHidden, that are derived from the corresponding 
    // AERecord properties.
    //
    // On entry, descList must not be NULL
    // On entry,  itemsPtr must not be NULL
    // On entry, *itemsPtr must be NULL
    // On success, *itemsPtr will be a valid CFArray
    // On error, *itemsPtr will be NULL
{
    OSStatus            err;
    CFMutableArrayRef    result;
    long                itemCount;
    long                itemIndex;
    AEKeyword            junkKeyword;
    DescType            junkType;
    Size                junkSize;
    
    assert( itemsPtr != NULL);
    assert(*itemsPtr == NULL);

    result = NULL;
    
    // Create a place for the result.
    
    err = noErr;
    result = CFArrayCreateMutable(NULL, 0, &kCFTypeArrayCallBacks);
    if (result == NULL) {
        err = coreFoundationUnknownErr;
    }
    
    // For each element in the descriptor list...
    
    if (err == noErr) {
        err = AECountItems(descList, &itemCount);
    }
    if (err == noErr) {
        for (itemIndex = 1; itemIndex <= itemCount; itemIndex++) {
            AERecord             thisItem;
            UInt8                 thisPath[1024];
            Size                thisPathSize;
            FSRef                thisItemRef;
            CFURLRef            thisItemURL;
            Boolean                thisItemHidden;
            CFDictionaryRef        thisItemDict;
            
            thisItem = kAENull;
            thisItemURL = NULL;
            thisItemDict = NULL;
            
            // Get this element's AERecord.
            
            err = AEGetNthDesc(descList, itemIndex, typeAERecord, &junkKeyword, &thisItem);

            // Extract the path and create a CFURL.

            if (err == noErr) {
                err = AEGetKeyPtr(
                    &thisItem, 
                    propPath, 
                    typeUTF8Text, 
                    &junkType, 
                    thisPath, 
                    sizeof(thisPath) - 1,         // to ensure that we can always add null terminator
                    &thisPathSize
                );
            }
            if (err == noErr) {
                thisPath[thisPathSize] = 0;
                
                err = FSPathMakeRef(thisPath, &thisItemRef, NULL);
                
                if (err == noErr) {
                    thisItemURL = CFURLCreateFromFSRef(NULL, &thisItemRef);
                } else {
                    err = noErr;            // swallow error and create an imprecise URL
                    
                    thisItemURL = CFURLCreateFromFileSystemRepresentation(
                        NULL,
                        thisPath,
                        thisPathSize,
                        false
                    );
                }
                if (thisItemURL == NULL) {
                    err = coreFoundationUnknownErr;
                }
            }
            
            // Extract the hidden flag.
            
            if (err == noErr) {
                err = AEGetKeyPtr(
                    &thisItem, 
                    propHidden, 
                    typeBoolean, 
                    &junkType, 
                    &thisItemHidden, 
                    sizeof(thisItemHidden),
                    &junkSize
                );
                
                // Work around <rdar://problem/4052117> by assuming that hidden 
                // is false if we can't get its value.
                
                if (err != noErr) {
                    thisItemHidden = false;
                    err = noErr;
                }
            }

            // Create the CFDictionary for this item.
            
            if (err == noErr) {
                CFStringRef keys[2];
                CFTypeRef    values[2];
                
                keys[0] = kLIAEURL;
                keys[1] = kLIAEHidden;
                
                values[0] = thisItemURL;
                values[1] = (thisItemHidden ? kCFBooleanTrue : kCFBooleanFalse);

                thisItemDict = CFDictionaryCreate(
                    NULL,
                    (const void **) keys,
                    values,
                    2,
                    &kCFTypeDictionaryKeyCallBacks,
                    &kCFTypeDictionaryValueCallBacks
                );
                if (thisItemDict == NULL) {
                    err = coreFoundationUnknownErr;
                }
            }
            
            // Add it to the results array.
            
            if (err == noErr) {
                CFArrayAppendValue(result, thisItemDict);
            }
                        
            AEDisposeDescQ(&thisItem);
            CFQRelease(thisItemURL);
            CFQRelease(thisItemDict);
                        
            if (err != noErr) {
                break;
            }
        }
    }

    // Clean up.
    
    if (err != noErr) {
        CFQRelease(result);
        result = NULL;
    }
    *itemsPtr = result;
    assert( (err == noErr) == (*itemsPtr != NULL) );

    return err;
}

static OSStatus SendEventToSystemEventsWithParameters(
    AEEventClass     theClass,
    AEEventID        theEvent,
    AppleEvent *    reply,
    ...
)
    // Creates an Apple event and sends it to the System Events 
    // process.  theClass and theEvent are the event class and ID, 
    // respectively.  If reply is not NULL, the caller gets a copy 
    // of the reply.  Following reply is a variable number of Apple event 
    // parameters.  Each AE parameter is made up of two C parameters, 
    // the first being the AEKeyword, the second being a pointer to 
    // the AEDesc for that parameter.  This list is terminated by an 
    // AEKeyword of value 0.
    //
    // You typically call this as:
    //
    // err = SendEventToSystemEventsWithParameters(
    //     kClass,
    //     kEvent,
    //     NULL,
    //     param1_keyword, param1_desc_ptr, 
    //     param2_keyword, param2_desc_ptr, 
    //     0
    // );
    //
    // On entry, reply must be NULL or *reply must be the null AEDesc.
    // On success, if reply is not NULL, *reply will be the AE reply 
    // (that is, not a null desc).
    // On error, if reply is not NULL, *reply will be the null AEDesc.
{
    OSStatus            err;
    ProcessSerialNumber    psn;
    AppleEvent            target;
    AppleEvent            event;
    AppleEvent            localReply;
//  AEDescList            results;

    assert( (reply == NULL) || (reply->descriptorType == typeNull) );
        
    target = kAENull;
    event = kAENull;
    localReply = kAENull;
//  results = kAENull;
    
    // Create Apple event.
    
    err = FindSystemEvents(&psn);
    if (err == noErr) {
        err = AECreateDesc(typeProcessSerialNumber, &psn, sizeof(psn), &target);
    }
    if (err == noErr) {
        err = AECreateAppleEvent(
            theClass, 
            theEvent, 
            &target, 
            kAutoGenerateReturnID, 
            kAnyTransactionID, 
            &event
        );
    }

    // Handle varargs parameters.
    
    if (err == noErr) {
        va_list         ap;
        AEKeyword        thisKeyword;
        const AEDesc *    thisDesc;

        va_start(ap, reply);

        do {
            thisKeyword = va_arg(ap, AEKeyword);
            if (thisKeyword != 0) {
                thisDesc = va_arg(ap, const AEDesc *);
                assert(thisDesc != NULL);
                
                err = AEPutParamDesc(&event, thisKeyword, thisDesc);
            }
        } while ( (err == noErr) && (thisKeyword != 0) );

        va_end(ap);
    }    
    
    // Send event and get reply.
    
    if (err == noErr) {
        err = SendAppleEvent(&event, &localReply);
    }
    
    // Clean up.
    
    if ( (reply == NULL) || (err != noErr)) {
        // *reply is already null because of our precondition
        AEDisposeDescQ(&localReply);
    } else {
        *reply = localReply;
    }
    AEDisposeDescQ(&event);
    AEDisposeDescQ(&target);
    assert( (reply == NULL) || ((err == noErr) == (reply->descriptorType != typeNull)) );
    
    return err;
}

extern OSStatus LIAECopyLoginItems(CFArrayRef *itemsPtr)
    // See comment in header.
    //
    // This routine creates an Apple event that corresponds to the 
    // AppleScript:
    //
    //     get properties of every login item
    //
    // and sends it to System Events.  It then processes the reply 
    // into a CFArray in the format that's documented in the header 
    // comments.
{
    OSStatus            err;
    AppleEvent            reply;
    AEDescList            results;
    AEDesc                propertiesOfEveryLoginItem;
    
    assert( itemsPtr != NULL);
    assert(*itemsPtr == NULL);
    
    reply = kAENull;
    results = kAENull;
    propertiesOfEveryLoginItem = kAENull;
    
    // Build object specifier for "properties of every login item".

    {
        static const DescType keyAEPropertiesLocal = pProperties;
        static const DescType kAEAllLocal = kAEAll;
        AEDesc    every;
        AEDesc    everyLoginItem;
        AEDesc    properties;
        
        every = kAENull;
        everyLoginItem = kAENull;
        properties = kAENull;

        err = AECreateDesc(typeAbsoluteOrdinal, &kAEAllLocal, sizeof(kAEAllLocal), &every);
        if (err == noErr) {
            err = CreateObjSpecifier(cLoginItem, (AEDesc *) &kAENull, formAbsolutePosition, &every, false, &everyLoginItem);
        }
        if (err == noErr) {
            err = AECreateDesc(typeType, &keyAEPropertiesLocal, sizeof(keyAEPropertiesLocal), &properties);
        }
        if (err == noErr) {
            err = CreateObjSpecifier(
                typeProperty, 
                &everyLoginItem, 
                formPropertyID,
                &properties, 
                false, 
                &propertiesOfEveryLoginItem);
        }

        AEDisposeDescQ(&every);
        AEDisposeDescQ(&everyLoginItem);
        AEDisposeDescQ(&properties);
    }
    
    // Send event and get reply.
    
    if (err == noErr) {
        err = SendEventToSystemEventsWithParameters(
            kAECoreSuite,
            kAEGetData,
            &reply,
            keyDirectObject, &propertiesOfEveryLoginItem,
            0
        );
    }
    
    // Process reply.
    
    if (err == noErr) {
        err = AEGetParamDesc(&reply, keyDirectObject, typeAEList, &results);
    }
    if (err == noErr) {
        err = CreateCFArrayFromAEDescList(&results, itemsPtr);
    }

    // Clean up.
    
    AEDisposeDescQ(&reply);
    AEDisposeDescQ(&results);
    AEDisposeDescQ(&propertiesOfEveryLoginItem);
    assert( (err == noErr) == (*itemsPtr != NULL) );
    
    return err;
}

extern OSStatus LIAEAddRefAtEnd(const FSRef *item, Boolean hideIt)
    // See comment in header.
    //
    // This routine creates an Apple event that corresponds to the 
    // AppleScript:
    //
    //     make new login item 
    //            with properties {
    //               path:<path of item>,
    //               hidden:hideIt
    //           }
    //         at end
    //    
    // and sends it to System Events.
{
    OSStatus             err;
    AEDesc                newLoginItem;
    AERecord            properties;
    AERecord            endLoc;
    static const DescType cLoginItemLocal = cLoginItem;
    
    assert(item != NULL);
    
    newLoginItem = kAENull;
    endLoc = kAENull;
    properties = kAENull;

    // Create "new login item" parameter.
    
    err = AECreateDesc(typeType, &cLoginItemLocal, sizeof(cLoginItemLocal), &newLoginItem);
    
    // Create "with properties" parameter.
    
    if (err == noErr) {
        char        path[1024];
        AEDesc        pathDesc;
        
        pathDesc = kAENull;
        
        err = AECreateList(NULL, 0, true, &properties);
        if (err == noErr) {
            err = FSRefMakePath(item, (UInt8 *) path, sizeof(path));
        }
        
        // System Events complains if you pass it typeUTF8Text directly, so 
        // we do the conversion from typeUTF8Text to typeUnicodeText on our 
        // side of the world.
        
        if (err == noErr) {
            err = AECoercePtr(typeUTF8Text, path, (Size) strlen(path), typeUnicodeText, &pathDesc);
        }
        if (err == noErr) {
            err = AEPutKeyDesc(&properties, propPath, &pathDesc);
        }
        if (err == noErr) {
            err = AEPutKeyPtr(&properties, propHidden, typeBoolean, &hideIt, sizeof(hideIt));
        }
        
        AEDisposeDescQ(&pathDesc);
    }
    
    // Create "at end" parameter.
    
    if (err == noErr) {
        AERecord    end;
        static const DescType kAEEndLocal = kAEEnd;

        end = kAENull;
        
        err = AECreateList(NULL, 0, true, &end);
        if (err == noErr) {
            err = AEPutKeyPtr(&end, keyAEObject, typeNull, NULL, 0);
        }
        if (err == noErr) {
            err = AEPutKeyPtr(&end, keyAEPosition, typeEnumerated, &kAEEndLocal, (Size) sizeof(kAEEndLocal));
        }
        if (err == noErr) {
            err = AECoerceDesc(&end, cInsertionLoc, &endLoc);
        }
        
        AEDisposeDescQ(&end);
    }
    
    // Send the event.
        
    if (err == noErr) {
        err = SendEventToSystemEventsWithParameters(
            kAECoreSuite,
            kAECreateElement,
            NULL,
            keyAEObjectClass,     &newLoginItem,
            keyAEPropData,         &properties,
            keyAEInsertHere,     &endLoc,
            0
        );
    }

    // Clean up.
    
    AEDisposeDescQ(&newLoginItem);
    AEDisposeDescQ(&endLoc);
    AEDisposeDescQ(&properties);
    
    return err;
}

extern OSStatus LIAEAddURLAtEnd(CFURLRef item,     Boolean hideIt)
    // See comment in header.
    //
    // This is implemented as a wrapper around LIAEAddRef.  
    // I chose to do it this way because an URL can reference a 
    // file that doesn't except, whereas an FSRef can't, so by 
    // having the URL routine call the FSRef routine, I naturally 
    // ensure that the item exists on disk.
{
    OSStatus     err;
    Boolean        success;
    FSRef        ref;

    assert(item != NULL);
        
    err = noErr;
    success = CFURLGetFSRef(item, &ref);
    if ( ! success ) {
        // I have no idea what went wrong (thanks CF!).  Normally I'd 
        // return coreFoundationUnknownErr here, but in this case I'm 
        // going to go out on a limb and say that we have a file not found.
        err = fnfErr;
    }

    if (err == noErr) {
        err = LIAEAddRefAtEnd(&ref, hideIt);
    }
    
    return err;
}

extern OSStatus LIAERemove(CFIndex itemIndex)
    // See comment in header.
    //
    // This routine creates an Apple event that corresponds to the 
    // AppleScript:
    //
    //     delete login item itemIndex
    //    
    // and sends it to System Events.
{
    OSStatus    err;
    long        itemIndexPlusOne;
    AEDesc        indexDesc;
    AEDesc        loginItemAtIndex;
    
    assert(itemIndex >= 0);
    
    indexDesc = kAENull;
    loginItemAtIndex = kAENull;

    // Build object specifier for "login item X".

    itemIndexPlusOne = itemIndex + 1;    // AppleScript is one-based, CF is zero-based
    err = AECreateDesc(typeLongInteger, &itemIndexPlusOne, sizeof(itemIndexPlusOne), &indexDesc);
    if (err == noErr) {
        err = CreateObjSpecifier(cLoginItem, (AEDesc *) &kAENull, formAbsolutePosition, &indexDesc, false, &loginItemAtIndex);
    }

    // Send the event.

    if (err == noErr) {
        err = SendEventToSystemEventsWithParameters(
            kAECoreSuite,
            kAEDelete,
            NULL,
            keyDirectObject, &loginItemAtIndex,
            0
        );
    }

    // Clean up.

    AEDisposeDescQ(&indexDesc);
    AEDisposeDescQ(&loginItemAtIndex);
    
    return err;
}

#endif
