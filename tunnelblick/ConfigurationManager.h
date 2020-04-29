/*
 * Copyright 2010, 2011, 2012, 2013, 2014, 2015, 2016, 2018, 2019, 2020 Jonathan K. Bullard. All rights reserved.
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


/*  ConfigurationManager
 *
 *  This class manipulates configurations (.ovpn and .conf files and .tblk packages)
 *
 *  It takes care of protecting and unprotecting configurations and making shadow copies of them,
 *  and installing .tblk packages
 */

#import "defines.h"

// Return values for +ConfigurationManager:commandOptionsInConfigurationsAtPaths: and some methods it invokes
typedef enum
{
    CommandOptionsError,     // Error occurred
    CommandOptionsNo,        // Configurations have only safe options and do not contain .sh files
	CommandOptionsUserScript,// Configurations have only safe options and contain only .sh files that are run as the user
    CommandOptionsYes,       // Configurations have unsafe options and/or contain .sh files
    CommandOptionsUnknown    // Configurations do not contain .sh files, but have options not known to be safe or unsafe
} CommandOptionsStatus;


//*************************************************************************************************
@class ListingWindowController;
@class VPNConnection;

@interface ConfigurationManager : NSObject {
	
	ListingWindowController * listingWindow;

    // The following variables are used by installConfigurations:skipConfirmationMessage:skipResultMessage:NotifyDelegate: and the methods it invokes:
   
    NSString * applyToAllSharedPrivate;
    NSString * applyToAllUninstall;
    NSString * applyToAllReplaceSkip;
    
    NSString * tempDirPath;
    
    NSMutableString * errorLog;
    
    NSMutableArray * installSources;	// Paths of .tblks to copy to install
    NSMutableArray * installTargets;
	NSMutableArray * replaceSources;	// Paths of .tblks to copy to replace
	NSMutableArray * replaceTargets;
    NSMutableArray * noAdminSources;	// Paths of .tblks in which keys and certs (only) are to be updated without admin credentials
    NSMutableArray * noAdminTargets;
	NSMutableArray * updateSources;		// Paths of .tblk stubs to copy to L_AS_T_TBLKS for updatable configurations
	NSMutableArray * updateTargets;
    NSMutableArray * deletions;			// Paths of .tblks to delete to uninstall
	
    BOOL inhibitCheckbox;
    BOOL installToSharedOK;
    BOOL installToPrivateOK;
	BOOL multipleConfigurations;
}

+(NSDictionary *)           plistInTblkAtPath:          (NSString *)         path;

+(void)                     editOrExamineConfigurationForConnection: (VPNConnection *) connection;

+(NSMutableDictionary *)    getConfigurations;

+(NSString *) parseString: (NSString *) cfgContents
				forOption: (NSString *) option;

+(NSString *) condensedConfigFileContentsFromString: (NSString *) fullString;

+(NSString *) parseConfigurationForConnection: (VPNConnection *) connection
							  hasAuthUserPass: (BOOL *)          hasAuthUserPass
						   authRetryParameter: (NSString **)	 authRetryParameter;

+(BOOL)                     userCanEditConfiguration:   (NSString *)        filePath;

+(void) makeConfigurationsPrivateInNewThreadWithDisplayNames: (NSArray *) displayNames;

+(void) makeConfigurationsSharedInNewThreadWithDisplayNames: (NSArray *) displayNames;

+(void) removeConfigurationsOrFoldersInNewThreadWithDisplayNames: (NSArray *) displayNames;

+(BOOL) revertOneConfigurationToShadowWithDisplayName: (NSString *) displayName;

+(void) revertToShadowInNewThreadWithDisplayNames: (NSArray *) displayNames;

+(void) removeCredentialsInNewThreadWithDisplayNames: (NSArray *) displayNames;

+(void) removeCredentialsGroupInNewThreadWithName: (NSString *) name;

+(BOOL) createShadowCopyWithDisplayName: (NSString *) displayName;

+(NSDictionary *) getUpdateInfoForDisplayName: (NSString *) displayName;

+(NSString *) updatePathForDisplayName: (NSString *)     displayName
							updateInfo: (NSDictionary *) updateInfo;

+(BOOL) makeShadowCopyMatchConfigurationWithDisplayName: (NSString *)	  displayName
											 updateInfo: (NSDictionary *) updateInfo
											thenConnect: (BOOL)			  thenConnect
											  userKnows: (BOOL)			  userKnows;

+(void) makeShadowCopyMatchConfigurationInNewThreadWithDisplayName: (NSString *)	 displayName
														updateInfo: (NSDictionary *) updateInfo
													   thenConnect: (BOOL)			 thenConnect
														 userKnows: (BOOL)			 userKnows;

+(void) copyConfigurationsIntoNewFolderInNewThread: (NSArray *) displayNames;

+(void) moveConfigurationsIntoNewFolderInNewThread: (NSArray *) displayNames;

+(void) renameConfigurationInNewThreadAtPath: (NSString *) sourcePath toPath: (NSString *) targetPath;

+(void) renameFolderInNewThreadWithDisplayName: (NSString *) sourceDisplayName toDisplayName: (NSString *) targetDisplayName;

+(void) moveConfigurationInNewThreadAtPath: (NSString *) sourcePath toPath: (NSString *) targetPath;

+(void) duplicateConfigurationInNewThreadPath: (NSString *) sourcePath toPath: (NSString *) targetPath;

+(void) copyConfigurationInNewThreadPath: (NSString *) sourcePath toPath: (NSString *) targetPath;

+(void) installConfigurationsUpdateInBundleInMainThreadAtPath: (NSString *) path;

+(void) installConfigurationsInNewThreadShowMessagesNotifyDelegateWithPaths: (NSArray *) filePaths;

+(void) installConfigurationsInNewThreadShowMessagesDoNotNotifyDelegateWithPaths: (NSArray *) filePaths;

+(void) putDiagnosticInfoOnClipboardInNewThreadForDisplayName: (NSString *) displayName log: (NSString *) log;

+(void) terminateAllOpenVPNInNewThread;

+(void) terminateOpenVPNWithProcessIdInNewThread: (NSNumber *) processIdAsNumber;

+(void) terminateOpenVPNWithManagmentSocketInNewThread: (VPNConnection *) connection;

+(void) putConsoleLogOnClipboardInNewThread;

+(void) exportTunnelblickSetupInNewThread;

+(void) addConfigurationGuideInNewThread;

+(void) haveNoConfigurationsGuideInNewThread;

+(void) installConfigurationsInCurrentMainThreadDoNotShowMessagesDoNotNotifyDelegateWithPaths: (NSArray *)  paths;

+(CommandOptionsStatus) commandOptionsInConfigurationsAtPaths: (NSArray *) paths;

@end
