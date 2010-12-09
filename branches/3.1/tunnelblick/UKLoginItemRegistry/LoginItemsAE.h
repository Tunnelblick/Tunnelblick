// From http://developer.apple.com/mac/library/samplecode/LoginItemsAE/listing1.html
/*
 File:        LoginItemsAE.h
 
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
 
 $Log: LoginItemsAE.h,v $
 Revision 1.1  2005/09/27 12:29:29  eskimo1
 First checked in.
 
 
 */

#ifndef _LOGINITEMSAE_H
#define _LOGINITEMSAE_H

/////////////////////////////////////////////////////////////////

// System prototypes

#include <ApplicationServices/ApplicationServices.h>

/////////////////////////////////////////////////////////////////

#ifdef __cplusplus
extern "C" {
#endif
    
    /////////////////////////////////////////////////////////////////
    
    // Keys for the dictionary return by LIAECopyLoginItems.
    
#define kLIAEURL    CFSTR("URL")        // CFURL
#define kLIAEHidden CFSTR("Hidden")        // CFBoolean
    
    extern OSStatus LIAECopyLoginItems(CFArrayRef *itemsPtr);
    // Returns an array of CFDictionaries, each one describing a 
    // login item.  Each dictionary has two elements, 
    // kLIAEURL and kLIAEHidden, which are 
    // documented above.
    // 
    // On input,    itemsPtr must not be NULL.
    // On input,   *itemsPtr must be NULL.
    // On success, *itemsPtr will be a pointer to a CFArray.
    // Or error,   *itemsPtr will be NULL.
    
    extern OSStatus LIAEAddRefAtEnd(const FSRef *item, Boolean hideIt);
    extern OSStatus LIAEAddURLAtEnd(CFURLRef item,     Boolean hideIt);
    // Add a new login item at the end of the list, using either 
    // an FSRef or a CFURL.  The hideIt parameter controls whether 
    // the item is hidden when it's launched.
    
    extern OSStatus LIAERemove(CFIndex itemIndex);
    // Remove a login item.  itemIndex is an index into the array 
    // of login items as returned by LIAECopyLoginItems.
    
    /////////////////////////////////////////////////////////////////
    
#ifdef __cplusplus
}
#endif

#endif
