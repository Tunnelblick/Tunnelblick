/*
 * Copyright (c) 2010 Jonathan K. Bullard
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License version 2
 * as published by the Free Software Foundation.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program (see the file COPYING included with this
 * distribution); if not, write to the Free Software Foundation, Inc.,
 * 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
 */

/* This program must be run as root via executeAuthorized.
 *
 * It sets up to either run, or not run, openvpnstart with specified arguments at system startup.
 *
 * A launchd plist for running openvpnstart must be located in /tmp/tunnelblick/atsystemstart.SESSION.plist, where SESSION is the 
 * session ID (to work with fast user switching). The "Label" entry from the plist is used to identify the specific connection
 * openvpnstart is making.
 *
 * This program accepts a single command line argument.
 *
 * If the command line argument is "1", the plist is copied to /Library/LaunchDaemons/LABEL.plist
 * so it will be used to run openvpnstart at system startup.
 *
 * Otherwise, the file /Library/LaunchDaemons/LABEL.plist will be deleted, so it will not be used
 * to run openvpnstart at system startup.
 *
 * LABEL is the "Label" entry from the plist. It must be "net.tunnelblick.startup.NAME", where NAME is the configuration's display name
 * with hypens, slashes, and dots encoded as --, -S, -D, respectively.
 *
 * When finished, this program creates a file, /tmp/tunnelblick/atsystemstart.SESSION.done, where SESSION is the 
 * session ID (to work with fast user switching) to indicate that it has finished. The file is owned by the user
 * so the Tunnelblick GUI can delete it. (We do this because executeAuthorized does not wait for the task to complete before returning.)
 */

#import <Foundation/Foundation.h>
#import <Security/AuthSession.h>

NSAutoreleasePool   * pool;
NSString            * flagFilePath;

void setStart(NSString * libPath, NSString * plistPath);
void setNoStart(NSString * libPath);
void createFlagFile(void);


//**************************************************************************************************************************
int main(int argc, char* argv[])
{
    pool = [[NSAutoreleasePool alloc] init];

    // Use a session ID in temporary files to support fast user switching
    SecuritySessionId securitySessionId;
    OSStatus error;
    SessionAttributeBits sessionInfo;
    error = SessionGetInfo(callerSecuritySession, &securitySessionId, &sessionInfo);
    if (  error != 0  ) {
        securitySessionId = 0;
    }
    
	BOOL syntaxError = TRUE;
    
    if (  argc == 2  ) {
        NSString * plistPath = [NSString stringWithFormat: @"/tmp/tunnelblick/atsystemstart.%d.plist", (int) securitySessionId];
        flagFilePath         = [NSString stringWithFormat: @"/tmp/tunnelblick/atsystemstart.%d.done", (int) securitySessionId];

        NSDictionary * plistDict = [NSDictionary dictionaryWithContentsOfFile: plistPath];
        
        if (  ! plistDict  ) {
            NSLog(@"File not found or error loading it: %@", plistPath);
            syntaxError = FALSE;
        } else {
        
            NSString * label = [plistDict objectForKey: @"Label"];
            
            if (  ! label  ) {
                NSLog(@"No 'Label' in %@", plistPath);
                syntaxError = FALSE;
            } else if (  ! [label hasPrefix: @"net.tunnelblick.startup."]  ) {
                NSLog(@"Invalid 'Label' (must start with 'net.tunnelblick.startup.') in %@", plistPath);
                syntaxError = FALSE;
            } else {
            
                NSString * libPath = [NSString stringWithFormat: @"/Library/LaunchDaemons/%@.plist", label];
                
                if (  atoi(argv[1]) == 1   ) {
                    setStart(libPath, plistPath);
                    syntaxError = FALSE;
                } else {
                    setNoStart(libPath);
                    syntaxError = FALSE;
                }
            }
        }
    }
    
    if (  syntaxError  ) {
        fprintf(stderr, "Syntax error");
        createFlagFile();
        [pool drain];
        exit(EXIT_FAILURE);
    }
    
    createFlagFile();
    [pool drain];
    exit(EXIT_SUCCESS);
}

void setStart(NSString * libPath, NSString * plistPath)
{
    if (  [[NSFileManager defaultManager] fileExistsAtPath: libPath]  ) {
        if ( ! [[NSFileManager defaultManager] removeFileAtPath: libPath handler: nil]  ) {
            NSLog(@"Unable to delete %@", libPath);
            createFlagFile();
            [pool drain];
            exit(EXIT_FAILURE);
        }
    }
    
    // File must be owned by root:wheel to be copied into /Library/LaunchDaemons/
    if (  chown([plistPath UTF8String], 0, 0) != 0  ) {
        NSLog(@"Unable to change ownership of %@ to root:wheel", plistPath);
        createFlagFile();
        [pool drain];
        exit(EXIT_FAILURE);
    }

    if (  ! [[NSFileManager defaultManager] copyPath: plistPath toPath: libPath handler: nil]  ) {
        NSLog(@"Unable to copy %@ to %@", plistPath, libPath);
        if (  chown([plistPath UTF8String], getuid(), getgid()) != 0  ) {
            NSLog(@"Unable to restore ownership of %@", plistPath);
        }
        createFlagFile();
        [pool drain];
        exit(EXIT_FAILURE);
    }

    if (  chown([plistPath UTF8String], getuid(), getgid()) != 0  ) {
        NSLog(@"Unable to restore ownership of %@", plistPath);
        createFlagFile();
        [pool drain];
        exit(EXIT_FAILURE);
    }
    
}

void setNoStart(NSString * libPath)
{
    if (  [[NSFileManager defaultManager] fileExistsAtPath: libPath]  ) {
        if ( ! [[NSFileManager defaultManager] removeFileAtPath: libPath handler: nil]  ) {
            NSLog(@"Unable to delete %@", libPath);
            createFlagFile();
            [pool drain];
            exit(EXIT_FAILURE);
        }
    } else {
        NSLog(@"Does not exist, so do not need to delete %@", libPath);
    }

}

void createFlagFile(void)
{
    if (  [[NSFileManager defaultManager] createFileAtPath: flagFilePath contents: [NSData data] attributes: nil]  ) {
        if (  chown([flagFilePath UTF8String], getuid(), getgid()) != 0  ) {
            NSLog(@"Unable to make %d:%d owner of %@", getuid(), getgid(), flagFilePath);
        }
    } else {
        NSLog(@"Unable to create temporary file %@", flagFilePath);
    }
}
