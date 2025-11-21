/*
 * Copyright 2025 Jonathan K. Bullard. All rights reserved.
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
 *  distribution); if not, see http://www.gnu.org/licenses/.
 */

// DEBUGGING USING THIS PROGRAM:
//
// This program has been written to be debuggable by a separate Xcode project, "Debug_update_signing_util".
//
// IT USES ARGUMENTS SPECIFIED IN the file ~/args.txt if the file exists:
//
// The file must consist of lines terminated by a LF. Each line contains a single argument.
//
// (This program creates and uses a new argc and new argv from the arguments, instead of the argc and argv
//  supplied normally.)
//
// If "arguments.txt" does not exist, or if built without DEBUG set, it behaves normally.
//
// NOTE: Because the only program allowed to access the Keychain item is the program that created it,
//       debugging is restricted to one build of the program, so:
//
//          1. Build the program
//          2. Execute "echo test     > ~/args.txt" to test everything from key generation to verifying a signture
//                  or "echo generate > ~/args.txt" to generate a new key pair for the new build
//                  or similar to test specific functions.
//          3. Run the program
//          4. Echo new commands to ~/args.txt
//          5. Run the program
//
//          Repeat steps 5 and 6 as needed.
//
//       Otherwise, it will be necessary to authorize the newly-built program to access the keychain item, which
//       must be done in Keychain Access.app


#import <Foundation/Foundation.h>
#import <Security/Security.h>

#import "UpdateSigning.h"

static const char * HelpMessage =
    "Utility for the asymmetric keys used to secure Tunnelblick updates.\n"
    "\n"
    "Usage: update_signing_util generate   <keychain-item-name>\n"
    "       update_signing_util delete_key <keychain-item-name>\n"
    "       update_signing_util public_key <keychain-item-name>\n"
    "       update_signing_util signature  <path> <keychain-item-name>\n"
    "       update_signing_util verify     <path> <signature> <keychain-item-name>\n"
    "       update_signing_util verify_with_public_key <path> <signature> <public_key>\n"
    "       update_signing_util test       <path>  <keychain-item-name>\n"
    "\n"
    "\n"
    "update_signing_util generate\" generates a new key pair,\n"
    "stores the private key in the login keychain with the name <keychain-item-name>,\n"
    "and prints the base-64 encoding of the public key.\n"
    "\n"
    "\"update_signing_util delete_key\" deletes the key with the name\n"
    "<keychain-item-name> if it exists.\n"
    "\n"
    "\"update_signing_util public_key\" prints the base-64 encoding of the\n"
    "public key stored in the login keychain item named <keychain-item-name>.\n"
    "\n"
    "\"update_signing_util signature\" prints the base-64 encoding of a\n"
    "signature of the file at <path> created using the public key\n"
    "stored in the login keychain item named <keychain-item-name>.\n"
    "\n"
    "\"update_signing_util verify\" verifies that <signature-base-64-encoded> is\n"
    "a valid signature for the file at <path> using the private key\n"
    "stored in the login keychain item named <keychain-item-name>.\n"
    "Nothing is printed if the verify succeeds. An error message is printed\n"
    "if the verify fails.\n"
    "\n"
    "\"update_signing_util verify_with_public_key\" verifies that\n"
    "<signature-base-64-encoded> is a valid signature for the file at <path>\n"
    "using the private key corresponding to the public key provided as a\n"
    "base 64 URL encoded string.\n"
    "Nothing is printed if the verify succeeds. An error message is printed\n"
    "if the verify fails.\n"
    "\n"
    "\"update_signing_util test\" tests generating a new key pair,\n"
    "using it to generate a signature for a file at <path>, and then\n"
    "verifying the signature using the public key of the key pair.\n";


#pragma mark - Helper Functions

static void DumpArgcAndArgv(int argc, const char * argv[]) {

    NSString * line = [NSString stringWithFormat: @" %d arguments:", argc - 1];
    for (  int i=1; i<argc; i++ ) {
        line = [line stringByAppendingFormat: @" '%s'", argv[i]];
    }
//    NSLog(@"%@", line);
}

static void ProcessArguments(int argc, const char * argv[],
                             BOOL * generate, BOOL * delete_key, BOOL * show_key, BOOL * sign, BOOL * verify, BOOL * verifyWithPublicKey, BOOL * test,
                             NSString ** itemLabel, NSString ** path, NSString ** signatureb64, NSString ** publicKeyb64) {

    //--------------------------------------------------------------
    // Parse arguments and set global variables
    //--------------------------------------------------------------

    // Note: no calls to ReleaseCFItems() are done even on failure exits, because no CFReleaseItems have
    //       been created when this function is called.

    //
    // Show command syntax if no arguments
    //
    if (  argc < 2  ) {
        fprintf(stderr, "%s\n", HelpMessage);
        exit(EXIT_FAILURE);
    }

    //
    // Check for a valid sub-command
    //

    NSArray * subcommands = @[
        @"generate",
        @"delete_key",
        @"public_key",
        @"signature",
        @"verify",
        @"verify_with_public_key",
        @"test",
    ];

    NSString * subcommand = [NSString stringWithUTF8String: argv[1]];

    if (  ! [subcommands containsObject: subcommand]  ) {
        fprintf(stderr, "Command '%s' not recognized\n%s", argv[1], HelpMessage);
        exit(EXIT_FAILURE);
    }

    if (  argc < 3  ) {
        fprintf(stderr, "Too few arguments\n%s\n", HelpMessage);
        exit(EXIT_FAILURE);
    }

    //
    // Parse the sub-command
    //

    if (  argc == 3  ) {
        if (  strcmp(argv[1], "generate") == 0  ) {
            *generate = TRUE;
            *itemLabel = [NSString stringWithUTF8String: argv[2]];

        } else if (  strcmp(argv[1], "delete_key") == 0  ) {
            *delete_key = TRUE;
            *itemLabel = [NSString stringWithUTF8String: argv[2]];

        } else if (  strcmp(argv[1], "public_key") == 0  ) {
            *show_key = TRUE;
            *itemLabel = [NSString stringWithUTF8String: argv[2]];

        } else {
            fprintf(stderr, "The '%s' command cannot have two arguments\n%s", argv[1], HelpMessage);
            exit(EXIT_FAILURE);
        }

    } else if (  argc == 4  ) {
        if (  strcmp(argv[1], "signature") == 0  ) {
            *sign = TRUE;
            *path = [NSString stringWithUTF8String: argv[2]];
            *itemLabel = [NSString stringWithUTF8String: argv[3]];

        } else if (  strcmp(argv[1], "test") == 0  ) {
            *test = TRUE;
            *path = [NSString stringWithUTF8String: argv[2]];
            *itemLabel = [NSString stringWithUTF8String: argv[3]];

        } else {
            fprintf(stderr, "The '%s' command cannot have three arguments\n%s", argv[1], HelpMessage);
            exit(EXIT_FAILURE);
        }

    } else if (  argc == 5  ) {
        if (  strcmp(argv[1], "verify") == 0  ) {
            *verify = TRUE;
            *path = [NSString stringWithUTF8String: argv[2]];
            *signatureb64 = [NSString stringWithUTF8String: argv[3]];
            *itemLabel = [NSString stringWithUTF8String: argv[4]];

        } else if (  strcmp(argv[1], "verify_with_public_key") == 0  ) {
            *verifyWithPublicKey = TRUE;
            *path = [NSString stringWithUTF8String: argv[2]];
            *signatureb64 = [NSString stringWithUTF8String: argv[3]];
            *publicKeyb64 = [NSString stringWithUTF8String: argv[4]];

        } else {
            fprintf(stderr, "The '%s' command cannot have four arguments\n%s", argv[1], HelpMessage);
            exit(EXIT_FAILURE);
        }

    } else {
        fprintf(stderr, "Too many arguments\n%s", HelpMessage);
        exit(EXIT_FAILURE);
    }

    // Make sure publicKeyb64 has been set if doing verify_with_public_key
    if (  *verifyWithPublicKey  ) {
        if (  ! *publicKeyb64  )  {
            fprintf(stderr, "The '%s' command requires a public key\n%s", argv[1], HelpMessage);
            *publicKeyb64 = @""; // Satisfy analyzer
            exit(EXIT_FAILURE);
        }
    }

    // Make sure signatureb64 has been set if doing verify or verify_with_public_key
    if (   *verify
        || *signatureb64  ) {
        if (  ! *path  )  {
            fprintf(stderr, "The '%s' command requires a signature\n%s", argv[1], HelpMessage);
            exit(EXIT_FAILURE);
        }
    }

    // Make sure path has been set if doing signature, test, verify, or verify_with_public_key
    if (   *sign
        || *test
        || *verify
        || *verifyWithPublicKey  ) {
        if (  ! *path  )  {
            fprintf(stderr, "The '%s' command requires a path\n%s", argv[1], HelpMessage);
            exit(EXIT_FAILURE);
        }

        if (  ! [NSFileManager.defaultManager isReadableFileAtPath: *path]  ) {
                fprintf(stderr, "No readable file at '%s'\n", (*path).fileSystemRepresentation);
                exit(EXIT_FAILURE);
        }
    }
}

static BOOL PrintBase64EncodedPublicKey(NSString * itemLabel, NSString ** errorMessagePtr) {

    NSString * base64PublicKey;

    if (  [UpdateSigning setBase64URLEncodedStringOfPublicKeyPtr: &base64PublicKey
                                               keychainItemLabel: itemLabel
                                                 errorMessagePtr: errorMessagePtr]  ) {
        printf("%s\n", base64PublicKey.UTF8String);
        return YES;
    }

    fprintf(stderr, "Could not get encoded string for public key (Internal error %s)\n", (*errorMessagePtr).UTF8String);
    return NO;
}

#if DEBUG

static const char * newArgVArray[10];    // New argv array. Allow up to 10 arguments.

static void ReplaceArgcAndArgvForDebugging(int * argc, const char * * argv[], NSString * argumentString) {

    //--------------------------------------------------------------
    // Set argc and argv using a new command line
    //
    // The new command line is constructed from argumentString. Each
    // line in argumentString is a separate argument.
    //--------------------------------------------------------------

    // Save the old argv to copy it to argv[0] in the new argv we create
    const char * * oldArgv = *argv;

    //
    // Create an NSArray with the new arguments
    //
    NSString * trimmedArgumentString = [argumentString stringByTrimmingCharactersInSet: NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSMutableArray * newArguments = [trimmedArgumentString componentsSeparatedByString: @"\n"].mutableCopy;

    //
    // Expand any arguments that start with "~"
    //
    for (  NSInteger i=0; i<newArguments.count; i++  ) {
        NSString * argument = [newArguments objectAtIndex: i];
        NSString * expandedArg = [argument stringByExpandingTildeInPath];
        [newArguments replaceObjectAtIndex: i withObject: expandedArg];
    }

    //
    // Replace argc
    //
    *argc = (int)newArguments.count + 1;   // Include the original argv[0]

    //
    // Replace argv with newArgVArray after populating it
    //
    newArgVArray[0] = oldArgv[0];

    for (  int i=0; i<newArguments.count; i++  ) {
        newArgVArray[i+1] = (  (NSString *)[newArguments objectAtIndex: i]  ).UTF8String;
    }
    *argv = (const char **)&newArgVArray;

    [newArguments release];
}

#endif

#pragma mark - Main

int main(int argc, const char * argv[]) {

    @autoreleasepool {

        //
        // Set the following variables from arguments
        //

        // BOOLs that indicate which operation will be performed. ONLY ONE MAY BE TRUE
        BOOL generate            = FALSE;
        BOOL delete_key          = FALSE;
        BOOL show_key            = FALSE; // (Shows the PUBLIC key)
        BOOL sign                = FALSE;
        BOOL verify              = FALSE;
        BOOL verifyWithPublicKey = FALSE;
        BOOL test                = FALSE;

        // Strings
        NSString * itemLabel     = nil;
        NSString * path          = nil;
        NSString * signatureb64  = nil;
        NSString * publicKeyb64  = nil;

#ifdef DEBUG

        // If ~/args.txt exists, it contains lines with arguments to replace
        // the arguments that this program was invoked with, and we replace argc and argv
        // with new values created from the line as described above in "DEBUGGING THIS PROGRAM".
        //
        // This is useful because ~/args.txt can be easily modified by shell scripts that use
        // this program to test the UpdateSigning class methods.
        //
        // If ~/args.txt does not exist, arguments come from the command line, as usual.

        NSString * argsTxtPath = [NSHomeDirectory()
                                  stringByAppendingPathComponent:@"args.txt"];
        if (  [NSFileManager.defaultManager fileExistsAtPath: argsTxtPath]  ) {
            NSError * err = nil;
            NSString * argsString = [NSString stringWithContentsOfFile: argsTxtPath
                                                              encoding: NSUTF8StringEncoding
                                                                 error: &err];
            if (  argsString.length == 0  ) {
                if (  err  ) {
                    fprintf(stderr, "Could not read ~/args.txt (error %s)\n\n", err.description.UTF8String);
                    return EXIT_FAILURE;
                } else
                    fprintf(stderr, "~/args.txt exists but is empty\n");
                return EXIT_FAILURE;
            } else {
                ReplaceArgcAndArgvForDebugging(&argc, &argv, argsString);
            }
        }
#endif

        DumpArgcAndArgv(argc, argv);

        ProcessArguments(argc, argv,
                         &generate, &delete_key, &show_key, &sign, &verify, &verifyWithPublicKey, &test,
                         &itemLabel, &path, &signatureb64, &publicKeyb64);

        NSString * errorMessage = nil;

        if (  test  ) {

            if (  [UpdateSigning testSigningFileAtPath: path
                                usingKeychainItemLabel: itemLabel
                                       errorMessagePtr: &errorMessage]  ) {
                printf("Test succceded\n");
            } else {
                fprintf(stderr, "Error during 'test': %s\n", errorMessage.UTF8String);
                return EXIT_FAILURE;
            }

        } else if (  generate  ) {

            if (  [UpdateSigning generateKeyPairWithKeychainItemLabel: itemLabel
                                                      errorMessagePtr: &errorMessage]  ) {
                if (  ! PrintBase64EncodedPublicKey(itemLabel, &errorMessage)  ) {
                    return EXIT_FAILURE;
                }
            } else {
                fprintf(stderr, "Error during 'generate': %s\n", errorMessage.UTF8String);
                return EXIT_FAILURE;
            }

        } else if (  delete_key  ) {

            if (  [UpdateSigning deletePrivateKeyFromKeychainWithLabel: itemLabel
                                                       errorMessagePtr: &errorMessage]  ) {
                printf("Key deleted\n");
            } else {
                fprintf(stderr, "Error during 'delete_key': %s\n", errorMessage.UTF8String);
                return EXIT_FAILURE;
           }

        } else if (  show_key  ) {

            if (  ! PrintBase64EncodedPublicKey(itemLabel, &errorMessage)  ) {
                return EXIT_FAILURE;
            }

        } else if (  sign  ) {

            NSString * signatureb64 = nil;
            if (  [UpdateSigning setBase64URLEncodedStringOfSignaturePtr: (NSString **) &signatureb64
                                                            ofFileAtPath: path
                                                       keychainItemLabel: itemLabel
                                                         errorMessagePtr: &errorMessage]  ) {
                printf("%s\n", signatureb64.UTF8String);
            } else {
                fprintf(stderr, "Error during 'signature': %s\n", errorMessage.UTF8String);
                return EXIT_FAILURE;
            }

        } else if (  verify  ) {

            if (  [UpdateSigning verifyFileAtPath: path
                                    signatureBase64: signatureb64
                                  keychainItemLabel: itemLabel
                                    errorMessagePtr: &errorMessage]  ) {
                printf("Verify succeeded\n");
            } else {
                fprintf(stderr, "Error during 'verify': %s\n", errorMessage.UTF8String);
                return EXIT_FAILURE;
            }

        } else if (  verifyWithPublicKey  ) {

            if (  [UpdateSigning verifyFileAtPath: path
                                  signatureBase64: signatureb64
                                  publicKeyBase64: publicKeyb64
                                  errorMessagePtr: &errorMessage]  ) {
                printf("Verify succeeded\n");
            } else {
                fprintf(stderr, "Error during 'verify_with_public_key': %s\n", errorMessage.UTF8String);
                return EXIT_FAILURE;
            }
        }
    }

    return EXIT_SUCCESS;
}
