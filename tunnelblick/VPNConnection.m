/*
 * Copyright 2004, 2005, 2006, 2007, 2008, 2009 by Angelo Laub
 * Contributions by Jonathan K. Bullard Copyright 2010, 2011, 2012, 2013, 2014, 2015, 2016, 2017, 2018, 2019. All rights reserved.
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

#import <CoreServices/CoreServices.h>
#import <libkern/OSAtomic.h>
#import <pthread.h>
#import <signal.h>

#import "helper.h"
#import "defines.h"
#import "sharedRoutines.h"

#import "AlertWindowController.h"
#import "AuthAgent.h"
#import "ConfigurationManager.h"
#import "KeyChain.h"
#import "LogDisplay.h"
#import "MenuController.h"
#import "MyPrefsWindowController.h"
#import "NetSocket.h"
#import "NetSocket+Text.h"
#import "NSApplication+LoginItem.h"
#import "NSDate+TB.h"
#import "NSFileManager+TB.h"
#import "NSString+TB.h"
#import "NSTimer+TB.h"
#import "StatusWindowController.h"
#import "SystemAuth.h"
#import "TBOperationQueue.h"
#import "TBUserDefaults.h"
#import "UIHelper.h"
#import "VPNConnection.h"

extern NSMutableArray       * gConfigDirs;
extern NSString             * gPrivatePath;
extern NSString             * gDeployPath;
extern NSFileManager        * gFileMgr;
extern TBUserDefaults       * gTbDefaults;
extern unsigned               gHookupTimeout;
extern BOOL                   gShuttingDownTunnelblick;
extern BOOL                   gShuttingDownOrRestartingComputer;
extern NSArray              * gRateUnits;
extern NSArray              * gTotalUnits;
extern volatile int32_t       gSleepWakeState;
extern volatile int32_t       gActiveInactiveState;

@interface VPNConnection()          // PRIVATE METHODS

-(void)             afterFailureHandler:            (NSTimer *)     timer;

-(NSArray *)        argumentsForOpenvpnstartForNow: (BOOL)          forNow
										 userKnows: (BOOL)          userKnows;

-(void)             clearStatisticsRatesDisplay;

-(void)             clearStatisticsIncludeTotals:   (BOOL)          includeTotals;

-(void)             connectToManagementSocket;

-(void)             credentialsHaveBeenAskedFor:    (NSDictionary *)dict;

-(void)             didHookup;

-(void)             disconnectFromManagmentSocket;

-(BOOL)             hasLaunchDaemon;

-(void)             killProcess;                                                // Kills the OpenVPN process associated with this connection, if any

-(NSString * )      leasewatchOptionsFromPreferences;

-(BOOL)             makeDictionary:             (NSDictionary * *)  dict
                         withLabel:             (NSString *)        daemonLabel
                  openvpnstartArgs:             (NSMutableArray * *)openvpnstartArgs;

-(void)             processLine:                (NSString *)        line;

-(void)             processState:               (NSString *)        newState
                           dated:               (NSString *)        dateTime;

-(void)             provideCredentials:         (NSString *)        parameterString
                                  line:         (NSString *)        line;

-(void)             runScriptNamed:             (NSString *)        scriptName
               openvpnstartCommand:             (NSString *)        command;

-(void)             setBit:                     (unsigned int)      bit
                    inMask:                     (unsigned int *)    bitMaskPtr
    ifConnectionPreference:                     (NSString *)        keySuffix
                  inverted:                     (BOOL)              invert
				 defaultTo:                     (BOOL)              defaultsTo;

-(void)             setManagementSocket:        (NetSocket *)       socket;

-(void)             setPort:                    (unsigned int)      inPort;

-(void)             setPreferencesFromOpenvnpstartArgString: (NSString *) openvpnstartArgString;

-(BOOL)             setPreference:              (BOOL)              value
                              key:              (NSString *)        key;

-(NSString *)       timeString;

TBPROPERTY(          NSMutableArray *,         messagesIfConnectionFails,        setMessagesIfConnectionFails)

@end

@implementation VPNConnection

-(void) initializeAuthAgent
{
	NSString * group = credentialsGroupFromDisplayName([self displayName]);
	[myAuthAgent release];
	myAuthAgent = [[AuthAgent alloc] initWithConfigName: [self displayName]
									   credentialsGroup: group];
}

-(void) reloadPreferencesFromTblk {
	
	// If a package, set preferences that haven't been defined yet or that should always be set
	if (  [[configPath pathExtension] isEqualToString: @"tblk"]  ) {
		NSString * infoPath = [configPath stringByAppendingPathComponent: @"Contents/Info.plist"];
		NSDictionary * infoDict = [NSDictionary dictionaryWithContentsOfFile: infoPath];
		NSString * key;
		NSEnumerator * e = [infoDict keyEnumerator];
		while (  (key = [e nextObject])  ) {
			if (  [key hasPrefix: @"TBPreference"]  ) {
				NSString * preferenceKey = [displayName stringByAppendingString: [key substringFromIndex: [@"TBPreference" length]]];
				if (  ! [gTbDefaults preferenceExistsForKey: preferenceKey]  ) {
					[gTbDefaults setObject: [infoDict objectForKey: key] forKey: preferenceKey];
				}
			} else if (  [key hasPrefix: @"TBAlwaysSetPreference"]  ) {
				NSString * preferenceKey = [displayName stringByAppendingString: [key substringFromIndex: [@"TBAlwaysSetPreference" length]]];
				[gTbDefaults setObject: [infoDict objectForKey: key] forKey: preferenceKey];
			}
		}
	}
}

-(id) initWithConfigPath: (NSString *) inPath withDisplayName: (NSString *) inDisplayName
{	
    if (  (self = [super init])  ) {
        configPath = [inPath copy];
        displayName = [inDisplayName copy];
        managementSocket = nil;
		connectedSinceDate = [[NSDate alloc] init];
        logDisplay = [[LogDisplay alloc] initWithConfigurationPath: inPath];
        if (  ! logDisplay  ) {
            return nil;
        }
        
		[self setLocalizedName: [((MenuController *)[NSApp delegate]) localizedNameforDisplayName: inDisplayName tblkPath: inPath]];
		
        [logDisplay setConnection: self];
		[logDisplay clear];
		
		[self setLastState:      @"EXITING"];
		[self setRequestedState: @"EXITING"];
		[self initializeAuthAgent];
		
        // Set preferences that haven't been defined yet or that should always be set
		[self reloadPreferencesFromTblk];
        
		messagesIfConnectionFails = [[NSMutableArray alloc] initWithCapacity: 8];
		
		speakWhenConnected    = FALSE;
		speakWhenDisconnected = FALSE;
        NSString * upSoundKey  = [displayName stringByAppendingString: @"-tunnelUpSoundName"];
        NSString * upSoundName = [gTbDefaults stringForKey: upSoundKey];
        if (  upSoundName  ) {
            if (  ! [upSoundName isEqualToString: @"None"]  ) {
                if (  [upSoundName isEqualToString: @"Speak"]  ) {
					speakWhenConnected = TRUE;
				} else {
                    tunnelUpSound   = [NSSound soundNamed: upSoundName];
                    if (  ! tunnelUpSound  ) {
                        NSLog(@"%@ '%@' not found; no sound will be played when connecting", upSoundKey, upSoundName);
                    }
                }
            }
        }
        NSString * downSoundKey  = [displayName stringByAppendingString: @"-tunnelDownSoundName"];
        NSString * downSoundName = [gTbDefaults stringForKey: downSoundKey];
        if (  downSoundName  ) {
            if (  ! [downSoundName isEqualToString: @"None"] ) {
                if (  [downSoundName isEqualToString: @"Speak"]  ) {
					speakWhenDisconnected = TRUE;
				} else {
                    tunnelDownSound = [NSSound soundNamed: downSoundName];
                    if (  ! tunnelDownSound  ) {
                        NSLog(@"%@ '%@' not found; no sound will be played when an unexpected disconnection occurs", downSoundKey, downSoundName);
                    }
                }
            }
        }
        portNumber = 0;
		pid = 0;
        avoidHasDisconnectedDeadlock = 0;
		timeLastWarnedAboutOpenVPNVersion = 0;
        
		waitingForNetworkAvailability = FALSE;
		wereWaitingForNetworkAvailability = FALSE;
		stopWaitForNetworkAvailabilityThread = FALSE;
        tryingToHookup = FALSE;
        initialHookupTry = TRUE;
        completelyDisconnected = TRUE;
        discardSocketInput = TRUE;
        isHookedup = FALSE;
        tunOrTap = nil;
        areDisconnecting = FALSE;
        haveConnectedSince = FALSE;
        areConnecting = FALSE;
		disconnectWhenStateChanges = FALSE;
        loadedOurTap = FALSE;
        loadedOurTun = FALSE;
        authFailed       = FALSE;
        credentialsAskedFor = FALSE;
        showingStatusWindow = FALSE;
        serverNotClient = FALSE;
        ipCheckLastHostWasIPAddress = FALSE;
		connectAfterDisconnect = FALSE;
		useManualChallengeResponseOnce = FALSE;
        logFilesMayExist = ([[gTbDefaults stringForKey: @"lastConnectedDisplayName"] isEqualToString: displayName]);

        userWantsState   = userWantsUndecided;
        
        bytecountMutexOK = FALSE;
        OSStatus status = pthread_mutex_init( &bytecountMutex, NULL);
        if (  status == EXIT_SUCCESS  ) {
            bytecountMutexOK = TRUE;
        } else {
            NSLog(@"VPNConnection:initWithConfigPath:withDisplayName: pthread_mutex_init( &bytecountMutex ) failed; status = %ld", (long) status);
        }
        statistics.lastSet = [[NSDate date] retain];
        
        [self clearStatisticsIncludeTotals: YES];        
    }
    
    return self;
}

-(void) clearStatisticsIncludeTotals: (BOOL) includeTotals
{
    OSStatus status = pthread_mutex_lock( &bytecountMutex );
    if (  status != EXIT_SUCCESS  ) {
        NSLog(@"VPNConnection:clearStatisticsIncludeTotals: pthread_mutex_lock( &bytecountMutex ) failed; status = %ld", (long) status);
        return;
    }
    
    if (  includeTotals  ) {
        statistics.totalInBytecount  = 0;
        statistics.totalOutBytecount = 0;
        statistics.totalInByteCountBeforeThisConnection  = 0;
        statistics.totalOutByteCountBeforeThisConnection = 0;
    }
    
    [statistics.lastSet release];
    statistics.lastSet = [[NSDate date] retain];
    
    statistics.rbIx = 0;
    unsigned i;
    for (  i=0; i<RB_SIZE; i++  ) {
        statistics.rb[i].lastInBytecount  = 0;
        statistics.rb[i].lastOutBytecount = 0;
        statistics.rb[i].lastTimeInterval = 0.0;
    }
    
    [self setBytecountsUpdated: [NSDate date]];    
    
    pthread_mutex_unlock( &bytecountMutex );
}

// Reinitializes a connection -- as if we quit Tunnelblick and then relaunched
-(void) reInitialize
{
    [self disconnectFromManagmentSocket];
    [connectedSinceDate release]; connectedSinceDate = [[NSDate alloc] init];
    [self clearStatisticsIncludeTotals: NO];
    [self initializeAuthAgent];
    // Don't change logDisplay -- we want to keep it
	[self setLastState:      @"EXITING"];
    [self setRequestedState: @"EXITING"];
	[self invalidateConfigurationParse];
	[messagesIfConnectionFails removeAllObjects];
    portNumber       = 0;
    pid              = 0;
    tryingToHookup   = FALSE;
    isHookedup       = FALSE;
    areDisconnecting = FALSE;
    haveConnectedSince = FALSE;
    areConnecting    = FALSE;
	disconnectWhenStateChanges = FALSE;
    loadedOurTap     = FALSE;
    loadedOurTun     = FALSE;
	useManualChallengeResponseOnce = FALSE;
    logFilesMayExist = FALSE;
    serverNotClient  = FALSE;
}

-(BOOL) makeShadowCopyMatchConfiguration {
	
	int result = TBRunAlertPanel(NSLocalizedString(@"Tunnelblick", @"Window title"),
								 [NSString stringWithFormat: NSLocalizedString(@"The OpenVPN configuration file for '%@' was modified after it was last secured.\n\n"
																			   @"Do you wish to secure the modified configuration or revert to the last secured configuration?\n\n",
																			   @"Window text; the %@ will be replaced by the name of a configuration."), [self displayName]],
								 NSLocalizedString(@"Secure the Configuration",		   @"Button"),  // Default
								 NSLocalizedString(@"Cancel",						   @"Button"),  // Alternate
								 NSLocalizedString(@"Revert to the Last Secured Copy", @"Button")); // Other
	switch (  result  ) {
			
		case NSAlertAlternateReturn:
			return NO;
			break;
			
		case NSAlertDefaultReturn:
			return [ConfigurationManager createShadowCopyWithDisplayName: [self displayName]];
			break;
			
		case NSAlertOtherReturn:
			return [ConfigurationManager revertOneConfigurationToShadowWithDisplayName: [self displayName]];
			break;
			
		default:
			NSLog(@"Unexpected result from TBRunAlertPanel: %d", result);
			return NO;
	}
}


-(BOOL) configurationIsSecureOrMatchesShadowCopy {

	NSString * path = [self configPath];
	return (   [path hasPrefix: L_AS_T_SHARED]
			|| [path hasPrefix: gDeployPath]
			|| [self shadowCopyIsIdentical]);
}

-(BOOL) userOrGroupOptionExistsInConfiguration {
	
	NSString * cfgContents = [self condensedSanitizedConfigurationFileContents];
	if (  cfgContents  ) {
		if (   [ConfigurationManager parseString: cfgContents forOption: @"user"]
			|| [ConfigurationManager parseString: cfgContents forOption: @"group"]  ) {
			return YES;
		}
	} else {
		NSLog(@"Unable to obtain configuration file for %@", [self displayName]);
	}
	
	return NO;
}

-(void) tryToHookup: (NSDictionary *) dict {
    
    // Call on main thread only
    
    unsigned   inPortNumber = [[dict objectForKey: @"port"] intValue];
    NSString * inStartArgs  =  [dict objectForKey: @"openvpnstartArgs"];
    
    TBLog(@"DB-HU", @"['%@'] entered tryToHookup: to port %lu with openvpnstart arguments: '%@'", displayName, (unsigned long)inPortNumber, inStartArgs)

    if (  portNumber != 0  ) {
        NSLog(@"Ignoring attempt to 'tryToHookup' for '%@' -- already using port number %d", displayName, portNumber);
        return;
    }
    
    if (  managementSocket  ) {
        NSLog(@"Ignoring attempt to 'tryToHookup' for '%@' -- already using managementSocket", displayName);
        return;
    }

    [self setPort: inPortNumber];
    
    NSArray * startArgs = [inStartArgs componentsSeparatedByString: @"_"];
    unsigned nArgs = [startArgs count];
    if (  nArgs != OPENVPNSTART_LOGNAME_ARG_COUNT  ) {
        NSLog(@"Program error: Expected %lu arguments but have %lu in '%@' (the 'startArgs' portion of log filename for %@)",
              (long unsigned)OPENVPNSTART_LOGNAME_ARG_COUNT, (long unsigned)nArgs, inStartArgs, [self displayName]);
		[((MenuController *)[NSApp delegate]) terminateBecause: terminatingBecauseOfError];
		return;
    }
	
	connectedUseScripts    = (unsigned)[[startArgs objectAtIndex: OPENVPNSTART_LOGNAME_ARG_USE_SCRIPTS_IX] intValue];
	[self setConnectedCfgLocCodeString: [startArgs objectAtIndex: OPENVPNSTART_LOGNAME_ARG_CFG_LOC_CODE_IX]];
    
    // We set preferences of any configuration that we try to hookup, because this might be a new user who hasn't run Tunnelblick,
    // and they may be hooking up to a configuration that started when the computer starts.
    TBLog(@"DB-HU", @"['%@'] tryToHookup: invoking setPreferencesFromOpenvnpstartArgString:", displayName)
    [self setPreferencesFromOpenvnpstartArgString: inStartArgs];

    tryingToHookup = TRUE;
	[self setRequestedState: @"CONNECTED"];
    [self connectToManagementSocket];
}

// Decodes arguments to openvpnstart and sets preferences from them
//
// We could do it by extracting arguments from the launchd .plist, but that won't work for a configuration that isn't set to
// connect when the computer starts. So we do it by decoding the arguments to openvpnstart that are part of the filename of the log file.
    
-(void) setPreferencesFromOpenvnpstartArgString: (NSString *) openvpnstartArgString
{
    NSArray * openvpnstartArgs = [openvpnstartArgString componentsSeparatedByString: @"_"];
    
    unsigned useScripts = [[openvpnstartArgs objectAtIndex: 0] unsignedIntValue];
    //  unsigned skipScrSec = [[openvpnstartArgs objectAtIndex: 1] unsignedIntValue];  // Skip - no preference for this
    unsigned cfgLocCode = [[openvpnstartArgs objectAtIndex: 2] unsignedIntValue];
    unsigned noMonitor  = [[openvpnstartArgs objectAtIndex: 3] unsignedIntValue];
    unsigned bitMask    = [[openvpnstartArgs objectAtIndex: 4] unsignedIntValue];
    
    BOOL configPathBad = FALSE;
    switch (  cfgLocCode & 0x3  ) {
            
        case CFG_LOC_PRIVATE:
        case CFG_LOC_ALTERNATE:
            if (! [configPath hasPrefix: [gPrivatePath stringByAppendingString: @"/"]] ) {
                configPathBad = TRUE;
            }
            break;
            
        case CFG_LOC_DEPLOY:
            if (! [configPath hasPrefix: [gDeployPath stringByAppendingString: @"/"]] ) {
                configPathBad = TRUE;
            }
            break;
            
        case CFG_LOC_SHARED:
            if (! [configPath hasPrefix: [L_AS_T_SHARED stringByAppendingString: @"/"]] ) {
                configPathBad = TRUE;
            }
            break;
            
        default:
            configPathBad = TRUE;
            break;
    }
    if (  configPathBad  ) {
        NSLog(@"cfgLocCode in log file for %@ doesn't match configuration path", [self displayName]);
        [((MenuController *)[NSApp delegate]) terminateBecause: terminatingBecauseOfError];
    }
    
    BOOL prefsChangedOK = TRUE;
    
    // Set preferences from the ones used when connection was made
    // They are extracted from the openvpnstart args in the log filename
    
    BOOL prefUseScripts  = (useScripts & OPENVPNSTART_USE_SCRIPTS_RUN_SCRIPTS) != 0;
    unsigned prefScriptNum = (useScripts & OPENVPNSTART_USE_SCRIPTS_SCRIPT_MASK) >> OPENVPNSTART_USE_SCRIPTS_SCRIPT_SHIFT_COUNT;
    if (  prefScriptNum > MAX_SET_DNS_WINS_INDEX - 1  ) { // Disallow invalid script numbers
        prefScriptNum = 0;
        prefsChangedOK = FALSE;
    }
    
    NSString * keyUseDNS = [displayName stringByAppendingString: @"useDNS"];
    unsigned useDnsFromArgs = (  prefUseScripts
                               ? prefScriptNum + 1
                               : 0);
    
    unsigned useDnsFromPrefs = [gTbDefaults unsignedIntForKey: keyUseDNS
                                                      default: 1
                                                          min: 0
                                                          max: MAX_SET_DNS_WINS_INDEX];
    if (  useDnsFromArgs != useDnsFromPrefs  ) {
        if (  [gTbDefaults canChangeValueForKey: keyUseDNS]  ) {
            NSNumber * useDnsFromArgsAsNumber = [NSNumber numberWithUnsignedInt: useDnsFromArgs];
            [gTbDefaults setObject: useDnsFromArgsAsNumber forKey: keyUseDNS];
            NSLog(@"The '%@' preference was changed to %u because that was encoded in the filename of the log file", keyUseDNS, useDnsFromArgs);
        } else {
            NSLog(@"The '%@' preference could not be changed to %u (which was encoded in the log filename) because it is a forced preference", keyUseDNS, useDnsFromArgs);
            prefsChangedOK = FALSE;
        }
    }
    
    //  BOOL prefUseDownRoot = (useScripts & 0x2) == 0x2;  // Skip - no preference for this
    
    BOOL prefNoMonitor = (noMonitor != 0);
    NSString * keyNoMonitor = [displayName stringByAppendingString: @"-notMonitoringConnection"];
    prefsChangedOK = prefsChangedOK && [self setPreference: prefNoMonitor key: keyNoMonitor];
    
    BOOL prefRestoreDNS  = ! ((bitMask & OPENVPNSTART_RESTORE_ON_DNS_RESET)  == OPENVPNSTART_RESTORE_ON_DNS_RESET);
    NSString * keyRestoreDNS = [displayName stringByAppendingString: @"-doNotRestoreOnDnsReset"];
    prefsChangedOK = prefsChangedOK && [self setPreference: prefRestoreDNS key: keyRestoreDNS];
    
    BOOL prefRestoreWINS = ! ((bitMask & OPENVPNSTART_RESTORE_ON_WINS_RESET) == OPENVPNSTART_RESTORE_ON_WINS_RESET);
    NSString * keyRestoreWINS = [displayName stringByAppendingString: @"-doNotRestoreOnWinsReset"];
    prefsChangedOK = prefsChangedOK && [self setPreference: prefRestoreWINS key: keyRestoreWINS];
    
    if ( (loadedOurTap = (bitMask & OPENVPNSTART_OUR_TAP_KEXT) == OPENVPNSTART_OUR_TAP_KEXT)  ) {
        NSString * keyLoadTun = [displayName stringByAppendingString: @"-loadTunKext"];
        prefsChangedOK = prefsChangedOK && [self setPreference: FALSE key: keyLoadTun];
    }

    if (  (loadedOurTun = (bitMask & OPENVPNSTART_OUR_TUN_KEXT) == OPENVPNSTART_OUR_TUN_KEXT) ) {
        NSString * keyLoadTap = [displayName stringByAppendingString: @"-loadTapKext"];
        prefsChangedOK = prefsChangedOK && [self setPreference: FALSE key: keyLoadTap];
    }
    
    NSString * keyAutoConnect = [displayName stringByAppendingString: @"autoConnect"];
    NSString * keyOnSystemStart = [displayName stringByAppendingString: @"-onSystemStart"];
    if (  [self hasLaunchDaemon]  ) {
        prefsChangedOK = prefsChangedOK && [self setPreference: TRUE key: keyAutoConnect];
        prefsChangedOK = prefsChangedOK && [self setPreference: TRUE key: keyOnSystemStart];
    } else {
        if (  [gTbDefaults boolForKey: keyOnSystemStart]  ) {
            NSLog(@"Warning: preference '%@' will be changed to FALSE because there is no launch daemon for the configuration", keyOnSystemStart);
            prefsChangedOK = prefsChangedOK && [self setPreference: FALSE key: keyOnSystemStart];
        }
    }
    
    if (  ! prefsChangedOK  ) {
        [((MenuController *)[NSApp delegate]) terminateBecause: terminatingBecauseOfError];
    }
    
    // Keep track of the number of tun and tap kexts that openvpnstart loaded
    if (  loadedOurTap  ) {
        [((MenuController *)[NSApp delegate]) incrementTapCount];
    }
    
    if (  loadedOurTun ) {
        [((MenuController *)[NSApp delegate]) incrementTunCount];
    }
}

// Returns TRUE if didn't need to change preference, or preference was changed, or FALSE if preference could not be set
-(BOOL) setPreference: (BOOL) value key: (NSString *) key
{
    if (  [gTbDefaults boolForKey: key] != value  ) {
        if (  [gTbDefaults canChangeValueForKey: key]  ) {
            [gTbDefaults setBool: value forKey: key];
            NSLog(@"The '%@' preference was changed to %@ because that was encoded in the filename of the log file", key, (value ? @"TRUE" : @"FALSE") );
        } else {
            NSLog(@"The '%@' preference could not be changed to %@ (which was encoded in the log filename) because it is a forced preference", key, (value ? @"TRUE" : @"FALSE") );
            return FALSE;
        }
    }
    
    return TRUE;
}

-(BOOL) hasLaunchDaemon
{
    NSString * daemonPath = [NSString stringWithFormat: @"/Library/LaunchDaemons/net.tunnelblick.tunnelblick.startup.%@.plist", encodeSlashesAndPeriods([self displayName])];
    return [gFileMgr fileExistsAtPath: daemonPath];
}

-(void) stopTryingToHookup
{
    if (   tryingToHookup
        && initialHookupTry  ) {
        tryingToHookup = FALSE;

        if ( ! isHookedup  ) {
            [self setPort: 0];
			[self setRequestedState: @"EXITING"];
            
            NSLog(@"Stopped trying to establish communications with an existing OpenVPN process for '%@' after %d seconds", [self localizedName], gHookupTimeout);
            NSString * msg = [NSString stringWithFormat:
                              NSLocalizedString(@"Tunnelblick was unable to establish communications with an existing OpenVPN process for '%@' within %d seconds. The attempt to establish communications has been abandoned.", @"Window text"),
                              [self localizedName],
                              gHookupTimeout];
            NSString * prefKey = [NSString stringWithFormat: @"%@-skipWarningUnableToToEstablishOpenVPNLink", [self displayName]];
            
            TBRunAlertPanelExtended(NSLocalizedString(@"Unable to Establish Communication", @"Window text"),
                                    msg,
                                    nil, nil, nil,
                                    prefKey,
                                    NSLocalizedString(@"Do not warn about this again", @"Checkbox name"),
                                    nil,
									NSAlertDefaultReturn);
        }
    }
}

-(void) didHookup
{
    MyPrefsWindowController * vpnDetails = [((MenuController *)[NSApp delegate]) logScreen];
    if (  vpnDetails  ) {
        TBLog(@"DB-HU", @"['%@'] didHookup invoked; informing VPN Details window", displayName)
		[vpnDetails hookedUpOrStartedConnection: self];
		[vpnDetails validateWhenConnectingForConnection: self];
    } else {
        TBLog(@"DB-HU", @"['%@'] didHookup invoked; VPN Details window does not exist", displayName)
    }
    [self addToLog: @"Established communication with OpenVPN"];
}

-(BOOL) shouldDisconnectWhenBecomeInactiveUser
{
    NSString * autoConnectkey      = [[self displayName] stringByAppendingString: @"autoConnect"];
    NSString * systemStartkey      = [[self displayName] stringByAppendingString: @"-onSystemStart"];
    NSString * doNotDisconnectKey  = [[self displayName] stringByAppendingString: @"-doNotDisconnectOnFastUserSwitch"];
    BOOL connectWhenComputerStarts = [gTbDefaults boolForKey: autoConnectkey] && [gTbDefaults boolForKey: systemStartkey];
    BOOL prefToNotDisconnect       = [gTbDefaults boolForKey: doNotDisconnectKey];
    
    return ! ( connectWhenComputerStarts || prefToNotDisconnect );
}

// Returns TRUE if this configuration will be connected when the system starts via a launchd .plist
-(BOOL) launchdPlistWillConnectOnSystemStart
{
    // Encode slashes and periods in the displayName so the result can act as a single component in a file name
    NSMutableString * daemonNameWithoutSlashes = encodeSlashesAndPeriods([self displayName]);
    
    NSString * daemonLabel = [NSString stringWithFormat: @"net.tunnelblick.tunnelblick.startup.%@", daemonNameWithoutSlashes];
    
    NSString * plistPath = [NSString stringWithFormat: @"/Library/LaunchDaemons/%@.plist", daemonLabel];
    
    return [gFileMgr fileExistsAtPath: plistPath];
}
    
// User wants to connect, or not connect, the configuration when the system starts.
// Returns TRUE if can and will connect, FALSE otherwise
//
// Needs and asks for computer administrator's authorization to make a change if a change is necessary and authRef is nil.
// (authRef is non-nil only when Tunnelblick is in the process of launching, and only when it was used for something else.)
//
// A change is necesary if changing connect/not connect status, or if preference changes would change
// the .plist file used to connect when the system starts

-(BOOL) checkConnectOnSystemStart: (BOOL)              startIt
{
    // Encode slashes and periods in the displayName so the result can act as a single component in a file name
    NSMutableString * daemonNameWithoutSlashes = encodeSlashesAndPeriods([self displayName]);
    
    NSString * daemonLabel = [NSString stringWithFormat: @"net.tunnelblick.tunnelblick.startup.%@", daemonNameWithoutSlashes];
    
    NSString * plistPath = [NSString stringWithFormat: @"/Library/LaunchDaemons/%@.plist", daemonLabel];

    NSDictionary * dict;
    NSMutableArray * openvpnstartArgs;
    
    if (  ! startIt  ) {
        if (  ! [gFileMgr fileExistsAtPath: plistPath]  ) {
            return NO; // Don't want to connect at system startup and no .plist in /Library/LaunchDaemons, so return that we ARE NOT connecting at system start
        }
        if (  ! [self makeDictionary: &dict withLabel: daemonLabel openvpnstartArgs: &openvpnstartArgs]  ) {
            // Don't want to connect at system startup, but .plist exists in /Library/LaunchDaemons
            // User cancelled when asked about openvpn-down-root.so, so return that we ARE connecting at system start
            return YES;
        }
    } else {
        if (  ! (   [configPath hasPrefix: [gDeployPath   stringByAppendingString: @"/"]]
                 || [configPath hasPrefix: [L_AS_T_SHARED stringByAppendingString: @"/"]]   )  ) {
            NSLog(@"Tunnelblick will NOT connect '%@' when the computer starts because it is a private configuration", [self displayName]);
            return NO;
        }
        
        if (  ! [self makeDictionary: &dict withLabel: daemonLabel openvpnstartArgs: &openvpnstartArgs]  ) {
            if (  [gFileMgr fileExistsAtPath: plistPath]  ) {
                // Want to connect at system start and a .plist exists, but user cancelled, so fall through to remove the .plist
                startIt = FALSE;
                // (Fall through to remove .plist)
            } else {
                // Want to connect at system start but no .plist exists and user cancelled, so return that we ARE NOT connecting at system start
                return NO;
            }

        } else if (  [gFileMgr fileExistsAtPath: plistPath]  ) {
            // Want to connect at system start and a .plist exists. If it is the same as the .plist we need, we're done
            if (  [dict isEqualToDictionary: [NSDictionary dictionaryWithContentsOfFile: plistPath]]  ) {
                return YES; // .plist contents are the same, so we needn't do anything, but indicate it will start at system start
            }
        }
    }
    
	NSBundle *thisBundle = [NSBundle mainBundle];
	NSString *launchPath = [thisBundle pathForResource:@"atsystemstart" ofType:nil];
    
    // Convert openvpnstart arguments to atsystemstart arguments by replacing the launch path with the atsystemstart parameter
    NSMutableArray * arguments = [[openvpnstartArgs mutableCopy] autorelease];
    [arguments replaceObjectAtIndex: 0 withObject: ( startIt ? @"1" : @"0" )];
    
    // Get a SystemAuth
    NSString * msg = (  startIt
                      ? [NSString stringWithFormat:
                         NSLocalizedString(@" Tunnelblick needs computer administrator authorization so it can automatically connect '%@' when the computer starts.", @"Window text; '%@' is the name of a configuration"),
                         [self localizedName]]
                      : [NSString stringWithFormat:
                         NSLocalizedString(@" Tunnelblick needs computer administrator authorization so it can stop automatically connecting '%@' when the computer starts.", @"Window text; '%@' is the name of a configuration"),
                         [self localizedName]]);
    SystemAuth * sysAuth = [SystemAuth newAuthWithPrompt: msg];
    if (  ! sysAuth  ) {
        if (  startIt  ) {
            NSLog(@"Connect '%@' when computer starts cancelled by user", [self displayName]);
            return NO;
        } else {
            NSLog(@"NOT connect '%@' when computer starts cancelled by user", [self displayName]);
            return YES;
        }
    }
    
    BOOL okNow = FALSE; // Assume failure
    unsigned i;
    for (i=0; i<5; i++) {
        if (  i != 0  ) {
            usleep( i * 500000 );
            NSLog(@"Retrying execution of atsystemstart");
        }
        
        if (  [NSApplication waitForExecuteAuthorized: launchPath withArguments: arguments withAuthorizationRef: [sysAuth authRef]]  ) {
            // Try for up to 6.35 seconds to verify that installer succeeded -- sleeping .05 seconds first, then .1, .2, .4, .8, 1.6,
            // and 3.2 seconds (totals 6.35 seconds) between tries as a cheap and easy throttling mechanism for a heavily loaded computer
            useconds_t sleepTime;
            for (sleepTime=50000; sleepTime < 7000000; sleepTime=sleepTime*2) {
                usleep(sleepTime);
                
                if (  startIt) {
                    if (  [dict isEqualToDictionary: [NSDictionary dictionaryWithContentsOfFile: plistPath]]  ) {
                        okNow = TRUE;
                        break;
                    }
                } else {
                    if (  ! [gFileMgr fileExistsAtPath: plistPath]  ) {
                        okNow = TRUE;
                        break;
                    }
                }
            }
            
            if (  okNow  ) {
                break;
            } else {
                NSLog(@"Timed out waiting for atsystemstart execution to finish");
            }
        } else {
            NSLog(@"Failed to execute %@: %@", launchPath, arguments);
        }
    }
    
    [sysAuth release];
    
    if (  startIt) {
        if (   okNow
            || [dict isEqualToDictionary: [NSDictionary dictionaryWithContentsOfFile: plistPath]]  ) {
            NSLog(@"%@ will be connected when the computer starts", [self displayName]);
            return YES;
        } else {
            NSLog(@"Failed to set up to connect '%@' when computer starts", [self displayName]);
            return NO;
        }
    } else {
        if (   okNow
            || ( ! [gFileMgr fileExistsAtPath: plistPath] )  ) {
            NSLog(@"%@ will NOT be connected when the computer starts", [self displayName]);
            return NO;
        } else {
            NSLog(@"Failed to set up to NOT connect '%@' when computer starts", [self displayName]);
            return YES;
        }
    }
}

// Returns YES on success, NO if user cancelled out of a dialog or there was an error 
-(BOOL) makeDictionary: (NSDictionary * *)  dict withLabel: (NSString *) daemonLabel openvpnstartArgs: (NSMutableArray * *) openvpnstartArgs
{
	NSString * openvpnstartPath = [[NSBundle mainBundle] pathForResource: @"openvpnstart" ofType: nil];
    *openvpnstartArgs = [[[self argumentsForOpenvpnstartForNow: NO userKnows: YES] mutableCopy] autorelease];
    if (  ! (*openvpnstartArgs)  ) {
        return NO;
    }
    
    [*openvpnstartArgs insertObject: openvpnstartPath atIndex: 0];
    
    NSString * daemonDescription = [NSString stringWithFormat: @"Processes Tunnelblick 'Connect when system starts' for VPN configuration '%@'",
                                    [self displayName]];
    
    NSString * workingDirectory;
    if (  [[configPath pathExtension] isEqualToString: @"tblk"]  ) {
        workingDirectory = [configPath stringByAppendingPathComponent: @"Contents/Resources"];
    } else {
        workingDirectory = firstPartOfPath(configPath);
		if (  ! workingDirectory  ) {
			NSLog(@"No firstPartOfPath for '%@'", configPath);
            [((MenuController *)[NSApp delegate]) terminateBecause: terminatingBecauseOfError];
		}
    }
    
    *dict = [NSDictionary dictionaryWithObjectsAndKeys:
             daemonLabel,       @"Label",
             *openvpnstartArgs, @"ProgramArguments",
             workingDirectory,  @"WorkingDirectory",
             daemonDescription, @"ServiceDescription",
             @YES,              @"RunAtLoad",
             nil];
    
    return YES;
}

-(NSString *) description
{
	return [NSString stringWithFormat:@"VPN Connection %@", displayName];
}

-(NSString *) condensedSanitizedConfigurationFileContents {
	
	if (  condensedSanitizedConfigurationFileContents  ) {
		return [[condensedSanitizedConfigurationFileContents retain] autorelease];
	}
	
	NSString * condensedContents = [ConfigurationManager condensedConfigFileContentsFromString: [self sanitizedConfigurationFileContents]];
	[self setCondensedSanitizedConfigurationFileContents: condensedContents];
	return condensedContents;
}

-(NSString *) sanitizedConfigurationFileContents {
    
	if (  sanitizedConfigurationFileContents  ) {
		return [[sanitizedConfigurationFileContents retain] autorelease];
	}
	
    NSString * configLocString = configLocCodeStringForPath([self configPath]);
    
    NSString * stdOutString = nil;
    NSString * stdErrString = nil;
    NSArray  * arguments = [NSArray arrayWithObjects: @"printSanitizedConfigurationFile", lastPartOfPath([self configPath]), configLocString, nil];
    OSStatus status = runOpenvpnstart(arguments, &stdOutString, &stdErrString);
    
    if (  status != EXIT_SUCCESS  ) {
        NSLog(@"Error status %d returned from 'openvpnstart printSanitizedConfigurationFile %@ %@'",
              (int) status, [self displayName], configLocString);
    }
    if (   stdErrString
        && ([stdErrString length] != 0)  ) {
        NSLog(@"stderr returned from 'openvpnstart printSanitizedConfigurationFile %@ %@':\n%@",
              [self displayName], configLocString, stdErrString);
    }
    
    NSString * configFileContents = nil;
    if (   stdOutString
        && ([stdOutString length] != 0)
		&& (status == EXIT_SUCCESS)  ) {
        configFileContents = [NSString stringWithString: stdOutString];
    }
    
	if ( ! configFileContents  ) {
		TBShowAlertWindow(NSLocalizedString(@"Warning", @"Window title"),
						  NSLocalizedString(@"Tunnelblick could not find the configuration file or the configuration file could not be sanitized. See the Console Log for details.", @"Window text"));
	}
	
	[self setSanitizedConfigurationFileContents: configFileContents];
	 
    return configFileContents;
}

-(void)setPort:(unsigned int)inPort 
{
	portNumber = inPort;
}

-(unsigned int)port 
{
    return portNumber;
}

-(NSString *) configPath
{
    return [[configPath retain] autorelease];
}

-(NSString *) secureDotTblkPath {
	
	// Returns the path of the secure .tblk for this configuration:
	//      * The path of a "Shared" configuration or a "Deployed" configuration; or
	//	    * The path of the shadow copy of a "Private" configuration.
	
	NSString * path = [self configPath];
	if (  [path hasPrefix: [gPrivatePath stringByAppendingString: @"/"]]  ) {
		path = [[L_AS_T_USERS stringByAppendingPathComponent: NSUserName()]
				stringByAppendingPathComponent: lastPartOfPath(path)];
	}

	return path;
}

// Also used as the prefix for preference and Keychain keys
-(NSString *) displayName
{
    return [[displayName retain] autorelease];
}

- (void) setManagementSocket: (NetSocket*) socket
{
    [socket retain];
    [managementSocket autorelease];
    managementSocket = socket;
    [managementSocket setDelegate: self];    
}

- (void) dealloc
{
    [self startDisconnectingUserKnows: @NO];
    [((MenuController *)[NSApp delegate]) cancelAllIPCheckThreadsForConnection: self];
    
    [configPath                       release]; configPath                       = nil;
    [displayName                      release]; displayName                      = nil;
    [connectedSinceDate               release]; connectedSinceDate               = nil;
    [lastState                        release]; lastState                        = nil;
    [tunOrTap                         release]; tunOrTap                         = nil;
    [requestedState                   release]; requestedState                   = nil;
    [logDisplay                       release]; logDisplay                       = nil;
    [managementSocket close];
    [managementSocket setDelegate: nil];
    [managementSocket                 release]; managementSocket                 = nil;
    [myAuthAgent                      release]; myAuthAgent                      = nil;
    [statusScreen                     release]; statusScreen                     = nil;
    [tunnelDownSound                  release]; tunnelDownSound                  = nil;
    [tunnelUpSound                    release]; tunnelUpSound                    = nil;
	[ipAddressBeforeConnect           release]; ipAddressBeforeConnect           = nil;
	[serverIPAddress                  release]; serverIPAddress                  = nil;
    [statistics.lastSet               release]; statistics.lastSet               = nil;
    [bytecountsUpdated                release]; bytecountsUpdated                = nil;
    [argumentsUsedToStartOpenvpnstart release]; argumentsUsedToStartOpenvpnstart = nil;
    [menuItem                         release]; menuItem                         = nil;
	[dynamicChallengeUsername         release]; dynamicChallengeUsername         = nil;
	[dynamicChallengeState            release]; dynamicChallengeState            = nil;
	[dynamicChallengePrompt           release]; dynamicChallengePrompt           = nil;
	[dynamicChallengeFlags            release]; dynamicChallengeFlags            = nil;
	[authRetryParameter				  release]; authRetryParameter               = nil;
	[statistics.lastSet               release]; statistics.lastSet               = nil;
	
    [super dealloc];
}

-(void) invalidateConfigurationParse
{
	[self setTunOrTap: nil];
	[self setSanitizedConfigurationFileContents: nil];
	[self setCondensedSanitizedConfigurationFileContents: nil];
}

-(void) showStatusWindowForce: (BOOL) force
{
    if (  force  ) {
        [statusScreen setClosedByRedDot: FALSE];
    }
    
    if (   (! gShuttingDownTunnelblick)
        && (  gSleepWakeState == noSleepState)
        && (  gActiveInactiveState == active)   ) {
        if (  ! showingStatusWindow  ) {
            NSString * statusPref = [gTbDefaults stringForKey: @"connectionWindowDisplayCriteria"];
            if (  ! [statusPref isEqualToString: @"neverShow"]  ) {
                if (  ! statusScreen) {
                    statusScreen = [[StatusWindowController alloc] initWithDelegate: self];
                    if (  force  ) {
                        [statusScreen setClosedByRedDot: FALSE];
                    }
                } else {
                    [statusScreen restore];
                }
                
                [statusScreen setStatus: [self lastState] forName: displayName connectedSince: [self timeString]];
                [statusScreen fadeIn];
                showingStatusWindow = TRUE;
            }
        }
    }
}

//******************************************************************************************************************
-(NSArray *) currentIPInfoWithIPAddress: (BOOL) useIPAddress
                        timeoutInterval: (NSTimeInterval) timeoutInterval
{
    // Returns information about the IP address and port used by the computer, and about the webserver from which the information was obtained
    //
    // If useIPAddress is FALSE, uses the URL in forced-preference IPCheckURL, or in Info.plist item IPCheckURL.
    // If useIPAddress is TRUE,  uses the URL with the host portion of the URL replaced by serverIPAddress
    //                                (https:// with an IP address will cause an SSL error, which means that the server
    //                                 was contacted successfully, which means routing works but DNS doesn't.)
    //
    // Normally returns an array with three strings: client IP address, client port, server IP address
    // If an SSL error occurs when using an IP address, returns an empty array
    // If any other error occurred, returns nil, having output a message to the Console log

    NSString * logHeader = [NSString stringWithFormat:@"currentIPInfo(%@)", (useIPAddress ? @"Address" : @"Name")];

    NSURL * url = [((MenuController *)[NSApp delegate]) getIPCheckURL];
    if (  ! url  ) {
        NSLog(@"%@: url == nil #1", logHeader);
        return nil;
    }
	
	NSString * hostName = [url host];
    
    if (  useIPAddress  ) {
        if (  serverIPAddress  ) {
            NSString * urlString = [url absoluteString];
			NSMutableString * tempMutableString = [[urlString mutableCopy] autorelease];
			NSRange rng = [tempMutableString rangeOfString: hostName];	// Just replace the first occurance of host
            [tempMutableString replaceOccurrencesOfString: hostName withString: serverIPAddress options: 0 range: rng];
            urlString = [NSString stringWithString: tempMutableString];
            url = [NSURL URLWithString: urlString];
            if (  ! url  ) {
                NSLog(@"%@:  url == nil #2", logHeader);
                return nil;
            }
        } else {
            NSLog(@"%@: serverIPAddress has not been set", logHeader);
            return nil;
        }
    }
	
    [self setIpCheckLastHostWasIPAddress: [[url host] containsOnlyCharactersInString: @"0123456789."]];

    // Create an NSURLRequest
    NSString * tbVersion = [[((MenuController *)[NSApp delegate]) tunnelblickInfoDictionary] objectForKey: @"CFBundleShortVersionString"];
    
    NSString * userAgent = [NSString stringWithFormat: @"Tunnelblick ipInfoChecker: %@", tbVersion];
    NSMutableURLRequest * req = [[[NSMutableURLRequest alloc] initWithURL: url] autorelease];
    if ( ! req  ) {
        NSLog(@"%@: req == nil", logHeader);
        return nil;
    }
    [req setValue: userAgent forHTTPHeaderField: @"User-Agent"];
	[req setValue: hostName  forHTTPHeaderField: @"Host"];
    [req setCachePolicy: NSURLRequestReloadIgnoringLocalAndRemoteCacheData];
	
	// Make the request synchronously. Make it asynchronous (in effect) by invoking this method from a separate thread.
    //
	// Implements the timeout and times the requests
    NSHTTPURLResponse * urlResponse = nil;
	NSError * requestError = nil;
	NSData * data = nil;
    uint64_t startTimeNanoseconds = nowAbsoluteNanoseconds();
    uint64_t timeoutNanoseconds = (uint64_t)((timeoutInterval + 2.0) * 1.0e9);	// (Add a couple of seconds for overhead)
    uint64_t endTimeNanoseconds = startTimeNanoseconds + timeoutNanoseconds;
	
	// On macOS 10.10 ("Yosemite"), the first request seems to always time out, so we retry several times, using a 1 second timeout for the first try
	NSTimeInterval internalTimeOut = 1.0;
	while (   (! data)
           && (nowAbsoluteNanoseconds() < endTimeNanoseconds)  ) {
		
		[req setTimeoutInterval: internalTimeOut];
		data = nil;
		requestError = nil;
		urlResponse  = nil;
		TBLog(@"DB-IC", @"%@: Set timeout to %f and made request to %@", logHeader, internalTimeOut, [url absoluteString]);
		data = [NSURLConnection sendSynchronousRequest: req
									 returningResponse: &urlResponse
												 error: &requestError];
		TBLog(@"DB-IC", @"%@: IP address check: error was '%@'; response was '%@'; data was %@", logHeader, requestError, urlResponse, data);
		
		/*
		 
		 Special handling for timeout errors, and for SSL errors when using the IP address instead of the domain name.

		 If there was a timeout error, allow more time for the next retry.
		 
		 If we're using the IP address instead of the domain name, the SSL negotiation will fail. But that means that the website was reached,
		 so routing works and the problem accessing the website was probably a DNS problem. Several different SSL-related errors have been seen
		 in experiments, so we check for any error that seems related to SSL.
		 
		 from /System/Library/Frameworks/Foundation.framework/Versions/C/Headers/NSURLError.h on macOS 10.11.6:
		 
				// SSL errors
				NSURLErrorSecureConnectionFailed = 		-1200,
				NSURLErrorServerCertificateHasBadDate = 	-1201,
				NSURLErrorServerCertificateUntrusted = 	-1202,
				NSURLErrorServerCertificateHasUnknownRoot = -1203,
				NSURLErrorServerCertificateNotYetValid = 	-1204,
				NSURLErrorClientCertificateRejected = 	-1205,
				NSURLErrorClientCertificateRequired =	-1206,
				NSURLErrorCannotLoadFromNetwork = 		-2000,
		 
		 */
		
		if (  requestError  ) {
			NSInteger errCode = [requestError code];
			
			if (  errCode == NSURLErrorTimedOut  ) {
				
				// Timeout -- try again allowing more time - the overall timeoutInterval still applies.
				internalTimeOut += 5.0;
				
			} else if (   useIPAddress
					   && (   (errCode == NSURLErrorSecureConnectionFailed)
						   || (errCode == NSURLErrorServerCertificateHasBadDate)
						   || (errCode == NSURLErrorServerCertificateUntrusted)
						   || (errCode == NSURLErrorServerCertificateHasUnknownRoot)
						   || (errCode == NSURLErrorServerCertificateNotYetValid)
						   || (errCode == NSURLErrorClientCertificateRejected)
						   || (errCode == NSURLErrorClientCertificateRequired)
						   || (errCode == NSURLErrorCannotLoadFromNetwork)
						   )
					   ) {
				NSLog(@"%@: Code = %ld, indicating an SSL error but that the server was reached by IP address; probably have a DNS problem", logHeader, errCode);
				return [NSArray array];
			}
		}
	}
    
    uint64_t elapsedTimeNanoseconds = nowAbsoluteNanoseconds() - startTimeNanoseconds;
    long elapsedTimeMilliseconds = (long) ((elapsedTimeNanoseconds + 500000) / 1000000);
	
	TBLog(@"DB-IC", "%@: error = %@", logHeader, requestError);
	
	if ( ! data  ) {
        NSLog(@"%@: IP address info could not be fetched within %.1f seconds; the error was '%@'; the response was '%@'", logHeader, ((double)elapsedTimeMilliseconds)/1000.0, requestError, urlResponse);
        return nil;
    } else {
        TBLog(@"DB-IC", @"%@: IP address info was fetched in %ld milliseconds", logHeader, elapsedTimeMilliseconds);
	}
    
    if (  [data length] > TUNNELBLICK_DOT_NET_IPINFO_RESPONSE_MAX_LENGTH  ) {
        NSLog(@"%@:  Response data was too long (%ld bytes)", logHeader, (long) [data length]);
        return nil;
    }
    
    NSString * response = [[[NSString alloc] initWithData: data encoding: NSUTF8StringEncoding] autorelease];
    if ( ! response  ) {
        NSLog(@"%@: Response as string == nil", logHeader);
        return nil;
    }
    
    if (  ! [response containsOnlyCharactersInString: @"0123456789ABCDEFabcdef:.,"]  ) {
        NSLog(@"%@: Response had invalid characters. response = %@", logHeader, response);
		return nil;
    }
    
    NSArray * items = [response componentsSeparatedByString: @","];
    if (  [items count] != 3  ) {
        NSLog(@"%@: Response does not have three items separated by commas. response = %@", logHeader, response);
		return nil;
    }
    
    TBLog(@"DB-IC", @"%@: [%@, %@, %@]", logHeader, [items objectAtIndex: 0], [items objectAtIndex: 1], [items objectAtIndex: 2] )
    return items;
}

- (void) ipInfoNotFetchedBeforeConnectedDialog
{
    NSString * msg = [NSString stringWithFormat:
                      NSLocalizedString(@"Tunnelblick could not fetch IP address information before the connection to %@ was made.\n\n", @"Window text"),
                      [self localizedName]];
    
    TBRunAlertPanelExtended(NSLocalizedString(@"Warning", @"Window text"),
                            msg,
                            nil, nil, nil,
                            @"skipWarningThatIPANotFetchedBeforeConnection",
                            NSLocalizedString(@"Do not warn about this again", @"Checkbox name"),
                            nil,
                            NSAlertDefaultReturn);
}

- (void) ipInfoTimeoutBeforeConnectingDialog: (NSTimeInterval) timeoutToUse
{
    NSString * msg = [NSString stringWithFormat:
                      NSLocalizedString(@"After %.1f seconds, gave up trying to fetch IP address information.\n\n"
                                        @"Tunnelblick will not check that this computer's apparent IP address changes when %@ is connected.\n\n",
                                        @"Window text"), (double) timeoutToUse, [self localizedName]];

    TBShowAlertWindow(NSLocalizedString(@"Warning", @"Window text"), msg);
}

- (void) ipInfoErrorDialog
{
    TBShowAlertWindow(NSLocalizedString(@"Warning", @"Window text"),
                      NSLocalizedString(@"A problem occurred while checking this computer's apparent public IP address.\n\nSee the Console log for details.\n\n", @"Window text"));
}

- (void) ipInfoInternetNotReachableDialog
{
    NSString * msg = [NSString stringWithFormat:
                      NSLocalizedString(@"After connecting to %@, the Internet does not appear to be reachable.\n\n"
                                        @"This may mean that your VPN is not configured correctly.\n\n", @"Window text"), [self localizedName]];
    
    TBRunAlertPanelExtended(NSLocalizedString(@"Warning", @"Window text"),
                            msg,
                            nil, nil, nil,
                            @"skipWarningThatInternetIsNotReachable",
                            NSLocalizedString(@"Do not warn about this again", @"Checkbox name"),
                            nil,
							NSAlertDefaultReturn);
}

- (void) ipInfoNoDNSDialog
{
    NSString * msg = [NSString stringWithFormat:
                      NSLocalizedString(@"After connecting to %@, DNS does not appear to be working.\n\n"
                                        @"This may mean that your VPN is not configured correctly.\n\n", @"Window text"), [self localizedName]];
    
    TBRunAlertPanelExtended(NSLocalizedString(@"Warning", @"Window text"),
                            msg,
                            nil, nil, nil,
                            @"skipWarningThatDNSIsNotWorking",
                            NSLocalizedString(@"Do not warn about this again", @"Checkbox name"),
                            nil,
							NSAlertDefaultReturn);
}

- (void) ipInfoNoChangeDialogBefore: (NSString *) beforeConnect
{
    NSString * msg = [NSString stringWithFormat:
                      NSLocalizedString(@"This computer's apparent public IP address was not different after connecting to %@. It is still %@.\n\n"
                                        @"This may mean that your VPN is not configured correctly.\n\n", @"Window text"), [self localizedName], beforeConnect];
	TBShowAlertWindowExtended(NSLocalizedString(@"Warning", @"Window text"),
							  msg,
							  @"skipWarningThatIPAddressDidNotChangeAfterConnection",
							  nil,
							  nil,
							  NSLocalizedString(@"Do not warn about this again for any configuration", @"Checkbox name"),
							  nil,
							  NO);
}

- (BOOL) okToCheckForIPAddressChange {
    
	if (  [gTbDefaults boolForKey: @"inhibitOutboundTunneblickTraffic"]  ) {
		return NO;
	}
	
	NSString * key = [displayName stringByAppendingString: @"-notOKToCheckThatIPAddressDidNotChangeAfterConnection"];
	return ! [gTbDefaults boolForKey: key];
}

-(void) startCheckingIPAddressBeforeConnected
{
    if (  ! [self okToCheckForIPAddressChange]  ) {
        return;
    }
    
    // Try to get ipAddressBeforeConnect and serverIPAddress
	[self setIpAddressBeforeConnect: nil];
	[self setServerIPAddress: nil];
    
    NSString * threadID = [NSString stringWithFormat: @"%lu-%llu", (long) self, (long long) nowAbsoluteNanoseconds()];
    [((MenuController *)[NSApp delegate]) addActiveIPCheckThread: threadID];
    [NSThread detachNewThreadSelector:@selector(checkIPAddressBeforeConnectedThread:) toTarget: self withObject: threadID];
}

-(void) startCheckingIPAddressAfterConnected
{
    if (  ! [self okToCheckForIPAddressChange] ) {
        return;
    }
    
    if (   [self ipAddressBeforeConnect]
        && [self serverIPAddress]  ) {
        NSString * threadID = [NSString stringWithFormat: @"%lu-%llu", (long) self, (long long) nowAbsoluteNanoseconds()];
        [((MenuController *)[NSApp delegate]) addActiveIPCheckThread: threadID];
        [NSThread detachNewThreadSelector:@selector(checkIPAddressAfterConnectedThread:) toTarget: self withObject: threadID];
    } else {
        [self addToLog: [NSString stringWithFormat: @"Could not determine this computer's apparent public IP address before the connection was completed"]];
        [self ipInfoNotFetchedBeforeConnectedDialog];
    }
}

-(BOOL) checkForChangedIPAddress: (NSString *) beforeConnect andIPAddress: (NSString *) afterConnect
{
	if (  [beforeConnect isEqualToString: afterConnect]  ) {
		[self addToLog: [NSString stringWithFormat: @"This computer's apparent public IP address (%@) was unchanged after the connection was made", beforeConnect]];
		[self ipInfoNoChangeDialogBefore: beforeConnect];
		return FALSE;
	} else {
		[self addToLog: [NSString stringWithFormat: @"This computer's apparent public IP address changed from %@ before connection to %@ after connection", beforeConnect, afterConnect]];
		return TRUE;
	}
}	

-(void) checkIPAddressErrorResultLogMessage: (NSString *) msg
{
    [self addToLog: msg];
    [self ipInfoErrorDialog];
}

-(void) checkIPAddressGoodResult: (NSDictionary *) dict
{
    NSString * before = [dict objectForKey: @"before"];
	NSString * after  = [dict objectForKey: @"after"];
	[((MenuController *)[NSApp delegate]) setPublicIPAddress: after];
    [self checkForChangedIPAddress: before
                      andIPAddress: after];
}

-(void) checkIPAddressBadResultLogMessage: (NSString *) msg
{
    [self addToLog: msg];      
    [self ipInfoInternetNotReachableDialog];
}

-(void) checkIPAddressNoDNSLogMessage: (NSString *) msg
{
    [self addToLog: msg];      
    [self ipInfoNoDNSDialog];
}

-(void) checkIPAddressBeforeConnectedThread: (NSString *) threadID
{
    // This method runs in a separate thread detached by startCheckingIPAddressBeforeConnected
    
    NSAutoreleasePool * threadPool = [NSAutoreleasePool new];
    
    NSTimeInterval timeoutToUse = [gTbDefaults timeIntervalForKey: @"timeoutForIPAddressCheckBeforeConnection"
                                                          default: 30.0
                                                              min: 1.0
                                                              max: 60.0 * 3.0];
	
    NSArray * ipInfo = [self currentIPInfoWithIPAddress: NO timeoutInterval: timeoutToUse];
    
    // Stop here if on cancelling list
    if (   [((MenuController *)[NSApp delegate]) isOnCancellingListIPCheckThread: threadID]
        || [lastState isEqualToString: @"CONNECTED" ]  ) {
        [((MenuController *)[NSApp delegate]) haveFinishedIPCheckThread: threadID];
        [threadPool drain];
        return;
    }
    
	if (  ipInfo  ) {
		if (  [ipInfo count] > 2  ) {
			[self setIpAddressBeforeConnect: [ipInfo objectAtIndex: 0]];
			[self setServerIPAddress:        [ipInfo objectAtIndex: 2]];
		} else {
            NSLog(@"After %.1f seconds, gave up trying to fetch IP address information before connecting", timeoutToUse);
			[self ipInfoTimeoutBeforeConnectingDialog: timeoutToUse];
		}
	} else {
        NSLog(@"An error occured fetching IP address information before connecting");
        [self ipInfoErrorDialog];
    }
    
	[((MenuController *)[NSApp delegate]) haveFinishedIPCheckThread: threadID];
    [threadPool drain];
}

-(void) checkIPAddressAfterConnectedThread: (NSString *) threadID
{
    // This method runs in a separate thread detached by startCheckingIPAddressAfterConnected

    NSAutoreleasePool * threadPool = [NSAutoreleasePool new];

    NSTimeInterval delay = [gTbDefaults timeIntervalForKey: @"delayBeforeIPAddressCheckAfterConnection"
                                                   default: 5.0
                                                       min: 0.001
                                                       max: 60.0 * 3.0];

    useconds_t delayMicroseconds = (unsigned)(delay * 1.0e6);
    if (  delayMicroseconds != 0  ) {
        TBLog(@"DB-IC", @"checkIPAddressAfterConnectedThread: Delaying %f seconds before checking connection", delay)
        usleep(delayMicroseconds);
    }
    
    NSTimeInterval timeoutToUse = [gTbDefaults timeIntervalForKey: @"timeoutForIPAddressCheckAfterConnection"
                                                          default: 30.0
                                                              min: 1.0
                                                              max: 60.0 * 3.0];
    
    NSArray * ipInfo = [self currentIPInfoWithIPAddress: NO timeoutInterval: timeoutToUse];
    if (   [((MenuController *)[NSApp delegate]) isOnCancellingListIPCheckThread: threadID]
        || ( ! [lastState isEqualToString: @"CONNECTED" ] )  ) {
        [((MenuController *)[NSApp delegate]) haveFinishedIPCheckThread: threadID];
        [threadPool drain];
        return;
    }
    
    if (  [ipInfo count] > 0  ) {
        TBLog(@"DB-IC", @"checkIPAddressAfterConnectedThread: fetched IP address %@", [ipInfo objectAtIndex:0])
        [self performSelectorOnMainThread: @selector(checkIPAddressGoodResult:)
                               withObject: [NSDictionary dictionaryWithObjectsAndKeys: [self ipAddressBeforeConnect], @"before", [ipInfo objectAtIndex: 0], @"after", nil]
                            waitUntilDone: NO];
        [((MenuController *)[NSApp delegate]) haveFinishedIPCheckThread: threadID];
        [threadPool drain];
        return;
    }
    
    // Couldn't get IP address by name, try by IP address
    TBLog(@"DB-IC", @"checkIPAddressAfterConnectedThread: Problem getting IP address using the ipInfo host's name; retrying by its IP address")

    [self addToLog:[NSString stringWithFormat: @"After %.1f seconds, gave up trying to fetch IP address information using the ipInfo host's name after connecting.", (double) timeoutToUse]];

    ipInfo = [self currentIPInfoWithIPAddress: YES timeoutInterval: timeoutToUse];
    if (   [((MenuController *)[NSApp delegate]) isOnCancellingListIPCheckThread: threadID]
        || ( ! [lastState isEqualToString: @"CONNECTED" ] )  ) {
        [((MenuController *)[NSApp delegate]) haveFinishedIPCheckThread: threadID];
        [threadPool drain];
        return;
    }
    
    if (  ! ipInfo  ) {
        NSLog(@"An error occured fetching IP address information after connecting");
        [self performSelectorOnMainThread: @selector(checkIPAddressErrorResultLogMessage:)
                               withObject: @"An error occured fetching IP address information using the ipInfo host's IP address after connecting"
                            waitUntilDone: NO];
        [((MenuController *)[NSApp delegate]) haveFinishedIPCheckThread: threadID];
        [threadPool drain];
        return;
    }
    
    if (  [ipInfo count] == 0  ) {
        TBLog(@"DB-IC", @"checkIPAddressAfterConnectedThread: SSL error getting IP address using the ipInfo host's IP address")
		[self performSelectorOnMainThread: @selector(checkIPAddressNoDNSLogMessage:)
							   withObject: [NSString stringWithFormat: @"fetched IP address information using the ipInfo host's IP address after connecting."]
							waitUntilDone: NO];
        [((MenuController *)[NSApp delegate]) haveFinishedIPCheckThread: threadID];
        [threadPool drain];
        return;
    }
    
    // Got IP address, even though DNS isn't working (!)
	NSString * address = [ipInfo objectAtIndex:0];
    TBLog(@"DB-IC", @"checkIPAddressAfterConnectedThread: fetched IP address %@ using the ipInfo host's IP address", address)
	[((MenuController *)[NSApp delegate]) performSelectorOnMainThread: @selector(setPublicIPAddress:)
                                                           withObject: address
                                                        waitUntilDone: NO];
    [self performSelectorOnMainThread: @selector(checkIPAddressNoDNSLogMessage:)
                           withObject: [NSString stringWithFormat: @"fetched IP address information using the ipInfo host's IP address after connecting."]
                        waitUntilDone: NO];
    [((MenuController *)[NSApp delegate]) haveFinishedIPCheckThread: threadID];
    [threadPool drain];
}

//******************************************************************************************************************

-(void) skipFinishMakingConnection: (NSDictionary *) dict {
	
	TBLog(@"DB-CD", @"skipFinishMakingConnection: %@", dict)
	
	pthread_mutex_lock( &areConnectingMutex );
	areConnecting = FALSE;
	pthread_mutex_unlock( &areConnectingMutex );
	
	[self setRequestedState: [dict objectForKey: @"requestedState"]];
	completelyDisconnected = TRUE;
	
	[self hasDisconnected];
}

-(void) finishMakingConnection: (NSDictionary *) dict {

	
	TBLog(@"DB-CD", @"finishMakingConnection: %@", dict)
	
	BOOL userKnows   = [[dict objectForKey: @"userKnows"]   boolValue];
	NSString * oldRequestedState = [dict objectForKey: @"requestedState"];
	
	[self startCheckingIPAddressBeforeConnected];
	
	// Process runOnConnect item
	NSString * path = [((MenuController *)[NSApp delegate]) customRunOnConnectPath];
	if (  path  ) {
		
		NSMutableArray * arguments = [NSMutableArray arrayWithCapacity: [argumentsUsedToStartOpenvpnstart count] + 1];
		
		// First argument to the runOnConnect program is the language code IFF there is a Localization.bundle in Deploy
		if (  [gFileMgr fileExistsAtPath: [gDeployPath stringByAppendingPathComponent: @"Localization.bundle"]]  ) {
			[arguments addObject: [((MenuController *)[NSApp delegate]) languageAtLaunch]];
		}
		
		[arguments addObjectsFromArray: argumentsUsedToStartOpenvpnstart];
		
		if (  [[[path stringByDeletingPathExtension] pathExtension] isEqualToString: @"wait"]  ) {
			OSStatus status = runTool(path, arguments, nil, nil);
			if (  status != 0  ) {
				NSLog(@"Tunnelblick runOnConnect item %@ returned %ld; The attempt to connect %@ has been cancelled", path, (long)status, [self displayName]);
				if (  userKnows  ) {
					TBShowAlertWindow(NSLocalizedString(@"Warning!", @"Window title"),
									  [NSString
									   stringWithFormat: NSLocalizedString(@"The attempt to connect %@ has been cancelled: the runOnConnect script returned status: %ld.", @"Window text"),
									   [self localizedName], (long)status]);
					[self setRequestedState: oldRequestedState];
				}
				areConnecting = FALSE;
				completelyDisconnected = TRUE;
				return;
			}
		} else {
			startTool(path, arguments);
		}
	}
	
	[gTbDefaults setBool: NO forKey: [displayName stringByAppendingString: @"-lastConnectionSucceeded"]];
	
	NSString * logText = [NSString stringWithFormat:@"Attempting connection with %@%@; Set nameserver = %@%@",
						  [self displayName],
						  (  [[argumentsUsedToStartOpenvpnstart objectAtIndex: 5] isEqualToString:@"1"]
						   ? @" using shadow copy"
						   : (  [[argumentsUsedToStartOpenvpnstart objectAtIndex: 5] isEqualToString:@"2"]
							  ? @" from Deploy"
							  : @""  )  ),
						  [argumentsUsedToStartOpenvpnstart objectAtIndex: 3],
						  (  [[argumentsUsedToStartOpenvpnstart objectAtIndex: 6] isEqualToString:@"1"]
						   ? @"; not monitoring connection"
						   : @"; monitoring connection" )
						  ];
	[self addToLog: logText];
	
	NSMutableArray * escapedArguments = [NSMutableArray arrayWithCapacity:[argumentsUsedToStartOpenvpnstart count]];
	unsigned i;
	for (i=0; i<[argumentsUsedToStartOpenvpnstart count]; i++) {
		[escapedArguments addObject: [[[argumentsUsedToStartOpenvpnstart objectAtIndex: i] componentsSeparatedByString: @" "] componentsJoinedByString: @"\\ "]];
	}
	
	[self addToLog: [NSString stringWithFormat: @"openvpnstart %@",
					 [escapedArguments componentsJoinedByString: @" "]]];
	
	unsigned bitMask = [[argumentsUsedToStartOpenvpnstart objectAtIndex: 7] unsignedIntValue];
	if (  (loadedOurTap = (bitMask & OPENVPNSTART_OUR_TAP_KEXT) == OPENVPNSTART_OUR_TAP_KEXT)  ) {
		[((MenuController *)[NSApp delegate]) incrementTapCount];
	}
	
	if (  (loadedOurTun = (bitMask & OPENVPNSTART_OUR_TUN_KEXT) == OPENVPNSTART_OUR_TUN_KEXT) ) {
		[((MenuController *)[NSApp delegate]) incrementTunCount];
	}
	
	[self setConnectedSinceDate: [NSDate date]];
	[self clearStatisticsIncludeTotals: NO];
	
	NSString * errOut;
	
	BOOL isDeployedConfiguration = [[argumentsUsedToStartOpenvpnstart objectAtIndex: 5] isEqualToString:@"2"];
	
	OSStatus status = runOpenvpnstart(argumentsUsedToStartOpenvpnstart, nil, &errOut);
	
	NSString * openvpnstartOutput;
	if (  status != EXIT_SUCCESS  ) {
		
		pthread_mutex_lock( &areConnectingMutex );
		areConnecting = FALSE;
		pthread_mutex_unlock( &areConnectingMutex );
		
		[self setRequestedState: oldRequestedState];
		completelyDisconnected = TRUE;
		
		if (  status == OPENVPNSTART_RETURN_SYNTAX_ERROR  ) {
			openvpnstartOutput = @"Internal Tunnelblick error: openvpnstart syntax error";
		} else {
			openvpnstartOutput = stringForLog(errOut, @"openvpnstart log:\n");
		}
		
		[self addToLog: [NSString stringWithFormat: @"\n\n"
						 "Could not start OpenVPN (openvpnstart returned with status #%ld)\n\n"
						 "Contents of the openvpnstart log:\n"
						 "%@",
						 (long)status, openvpnstartOutput]];
		
		if (  status == OPENVPNSTART_RETURN_CONFIG_NOT_SECURED_ERROR) {
			NSString * message = (  isDeployedConfiguration
								  ? [NSString stringWithFormat: NSLocalizedString(@"Configuration '%@' is not secure. Please reinstall Tunnelblick.", @"Window text"), [self localizedName]]
								  : [NSString stringWithFormat: NSLocalizedString(@"Configuration '%@' is not secure. It should be reinstalled.", @"Window text"), [self localizedName]]);
			TBShowAlertWindow(NSLocalizedString(@"Tunnelblick", @"Window title"),
							  message);
			areConnecting = FALSE;
			completelyDisconnected = TRUE;
			return;
		} else if (  status == OPENVPNSTART_COULD_NOT_LOAD_KEXT  ) {
			
			NSString * link = (  runningOnHighSierraOrNewer()
							   ? (  runningOnTen_Fourteen_FiveOrNewer()
								  ? @"https://tunnelblick.net/cKextNotarization.html"
								  : @"https://tunnelblick.net/cKextLoadErrorHighSierra.html")
							   : @"https://tunnelblick.net/cKextLoadError.html");
			NSString * linkMsg = [NSString stringWithFormat: NSLocalizedString(@"<a href=\"%@\">More information</a> [tunn" @"elblick.n" @"et]",
																			   @"Window text. The %@ is a URL such as https://tunnelblick.net/kextLoadError.html"),
								  link];
			
			NSString * htmlString = [NSString stringWithFormat:
									 NSLocalizedString(@"<p>Tunnelblick was not able to load a system extension that is needed to connect to %@.</p>"
													   @"<p>%@</p>",
													   
													   @"HTML error message. The first %@ is a configuration name. The second %@ is 'More info' link which has already been translated."),
									 [self displayName], linkMsg];
			NSAttributedString * msg = attributedLightDarkStringFromHTML(htmlString);
			if (  ! msg  ) {
				NSLog(@"connect:userKnows: msg = nil");
				msg = [[[NSAttributedString alloc] initWithString: NSLocalizedString(@"Tunnelblick could not load a kext", @"Window text") attributes: nil] autorelease];
			}
			
			TBShowAlertWindow(NSLocalizedString(@"Tunnelblick", @"Window title"), msg);
			areConnecting = FALSE;
			completelyDisconnected = TRUE;
			return;
		}
		
		if (  userKnows  ) {
			if (  [messagesIfConnectionFails count] != 0  ) {
				NSEnumerator * e = [messagesIfConnectionFails objectEnumerator];
				NSString * message;
				while (  (message = [e nextObject])  ) {
					TBShowAlertWindow(NSLocalizedString(@"Tunnelblick", @"Window title"), message);
				}
				[messagesIfConnectionFails removeAllObjects];
			} else {
				TBShowAlertWindow(NSLocalizedString(@"Warning!", @"Window title"),
								  [NSString stringWithFormat:
								   NSLocalizedString(@"Tunnelblick was unable to start OpenVPN to connect %@. For details, see the log in the VPN Details... window", @"Window text"),
								   [self localizedName]]);
			}
		}
		
	} else {
		openvpnstartOutput = stringForLog(errOut, @"openvpnstart log:\n");
		if (  [openvpnstartOutput length] != 0  ) {
			[self addToLog: openvpnstartOutput];
		}
		[self setState: @"SLEEP"];
		[((MenuController *)[NSApp delegate]) addNonconnection: self];
		[self connectToManagementSocket];
	}
}

-(void) waitForNetworkAvailabilityThread: (NSDictionary *) dict {
	
	// Secondary thread. Waits for the network to become available, then finishes connect sequence in the main thread
	
	NSAutoreleasePool * pool = [NSAutoreleasePool new];
	
	TBLog(@"DB-CD", @"waitForNetworkAvailabilityThread: %@", dict)
	
	while (  ! networkIsReachable()  ) {
		if (  stopWaitForNetworkAvailabilityThread  ) {
			break;
		}
		usleep(100000);
	}
	
	TBLog(@"DB-CD", @"waitForNetworkAvailabilityThread: broke out of loop; stopWaitForNetworkAvailabilityThread = %s", CSTRING_FROM_BOOL(stopWaitForNetworkAvailabilityThread))
	
	wereWaitingForNetworkAvailability = TRUE;
	waitingForNetworkAvailability = FALSE;
	
	if (  stopWaitForNetworkAvailabilityThread) {
		[self performSelectorOnMainThread: @selector(skipFinishMakingConnection:) withObject: dict waitUntilDone: NO];
	} else {
		// Although there is a network available, it isn't fully "up" for a while. This results in immedate error
		// returns from network access requests. So we wait for a few seconds.
		uint waitSeconds = [gTbDefaults unsignedIntForKey: @"delayBeforeConnectingAfterReenablingNetworkServices" default: 3 min: 0 max: 3600];
		sleep(waitSeconds);
		[self performSelectorOnMainThread: @selector(finishMakingConnection:) withObject: dict waitUntilDone: NO];
	}
	
	[pool drain];
}

-(void) connectOnMainThreadUserKnows: (NSNumber *) userKnowsNumber {
	
	[self performSelectorOnMainThread: @selector(connectUserKnows:) withObject: userKnowsNumber waitUntilDone: YES];
}

-(void) connectUserKnows: (NSNumber *) userKnowsNumber {
	
	[self connect: self userKnows: [userKnowsNumber boolValue]];
}
	 
static pthread_mutex_t areConnectingMutex = PTHREAD_MUTEX_INITIALIZER;

- (void) connect: (id) sender userKnows: (BOOL) userKnows
{
	(void) sender;
	
    [self invalidateConfigurationParse];
    
	[messagesIfConnectionFails removeAllObjects];
	
    if (   ( ! [[self configPath] hasPrefix: @"/Library/"] )
        && ( ! [[[self configPath] pathExtension] isEqualToString: @"tblk"] )  ) {
        TBShowAlertWindow(NSLocalizedString(@"Unavailable", @"Window title"),
                          NSLocalizedString(@"You may not connect this configuration.\n\n"
                                            @"If you convert it to a 'Tunnelblick VPN Connection' (.tblk), you"
                                            @" will be able to connect.", @"Window text"));
        return;
    }

	if (  [lastState isEqualToString: @"DISCONNECTING"] ) {
		// We are in the process of disconnecting, so set flags so that when the disconnect is complete we connect again
		connectAfterDisconnectUserKnows = userKnows;
		connectAfterDisconnect = TRUE;
		NSLog(@"connect: %@ but still disconnecting; setting up to reconnect when the disconnect is complete.", [self displayName]);
		return;
	}
	
    if (  ! [lastState isEqualToString: @"EXITING"]  ) {
        NSLog(@"connect: but %@ is not disconnected", [self displayName]);
        return;
    }
	
	if (  ! [(MenuController *)[NSApp delegate] askAndMaybeReenableNetworkAccessTryingToConnect]  ) {
		NSLog(@"connect: cancelled when asked to re-enabling network access");
		return;
	}
	
    pthread_mutex_lock( &areConnectingMutex );
    if (  areConnecting  ) {
        pthread_mutex_unlock( &areConnectingMutex );
        NSLog(@"connect: while connecting");
        return;
    }
    
	if (  doNotClearUseManualChallengeResponseOnceOnNextConnect  ) {
		doNotClearUseManualChallengeResponseOnceOnNextConnect = FALSE;
	} else {
		useManualChallengeResponseOnce = FALSE;
	}

    completelyDisconnected = FALSE;
    areConnecting = TRUE;
    pthread_mutex_unlock( &areConnectingMutex );
    
	[self setDynamicChallengeUsername: nil];
	[self setDynamicChallengeState:    nil];
	[self setDynamicChallengePrompt:   nil];
	[self setDynamicChallengeFlags:    nil];

	disconnectWhenStateChanges = FALSE;
    
    NSString * oldRequestedState = [self requestedState];
    if (  userKnows  ) {
		[self setRequestedState: @"CONNECTED"];
    }
    
    NSString * encodedPath = encodeSlashesAndPeriods([[self secureDotTblkPath] stringByAppendingPathComponent: @"Contents/Resources"]);
	if (  [gFileMgr fileExistsAtPath: [L_AS_T_EXPECT_DISCONNECT_FOLDER_PATH stringByAppendingPathComponent: encodedPath]]  ) {
		runOpenvpnstart([NSArray arrayWithObjects: @"expectDisconnect", @"0", encodedPath, nil], nil, nil);
		appendLog([NSString stringWithFormat: @"Cleared 'expect disconnect 0 %@'", encodedPath ]);
	}

    if (  ! [gTbDefaults boolForKey:@"skipWarningAboutSimultaneousConnections"]  ) {
        // Count the total number of connections and what their "Set nameserver" status was at the time of connection
        int numConnections = 1;
        int numConnectionsWithModifyNameserver = 0;
        if (  [self useDNSStatus] != 0  ) {
            numConnectionsWithModifyNameserver = 1;
        }
        VPNConnection * connection;
        NSEnumerator* e = [[((MenuController *)[NSApp delegate]) myVPNConnectionDictionary] objectEnumerator];
        while (  (connection = [e nextObject])  ) {
            if (  ! [[connection state] isEqualToString:@"EXITING"]  ) {
                numConnections++;
                if (  [connection usedModifyNameserver]  ) {
                    numConnectionsWithModifyNameserver++;
                }
            }
        }
        
        if (  numConnections != 1  ) {
            int button = TBRunAlertPanelExtended(NSLocalizedString(@"Do you wish to connect?", @"Window title"),
                                                 [NSString stringWithFormat:NSLocalizedString(@"Multiple simultaneous connections would be created (%d with 'Set nameserver', %d without 'Set nameserver').", @"Window text"), numConnectionsWithModifyNameserver, (numConnections-numConnectionsWithModifyNameserver) ],
                                                 NSLocalizedString(@"Connect", @"Button"),  // Default button
                                                 NSLocalizedString(@"Cancel", @"Button"),   // Alternate button
                                                 nil,
                                                 @"skipWarningAboutSimultaneousConnections",
                                                 NSLocalizedString(@"Do not warn about this again", @"Checkbox name"),
                                                 nil,
												 NSAlertDefaultReturn);
            if (  button != NSAlertDefaultReturn  ) {
                if (  userKnows  ) {
					[self setRequestedState: oldRequestedState];
                }
                areConnecting = FALSE;
                completelyDisconnected = TRUE;
                return;
            }
        }
    }
    
    logFilesMayExist = TRUE;
    authFailed = FALSE;
    credentialsAskedFor = FALSE;
    userWantsState = userWantsUndecided;
    
    areDisconnecting = FALSE;
    initialHookupTry = FALSE;
    tryingToHookup = TRUE;
    isHookedup = FALSE;
    
    [self disconnectFromManagmentSocket];

    [self clearLog];
    
    [self setArgumentsUsedToStartOpenvpnstart: [self argumentsForOpenvpnstartForNow: YES userKnows: userKnows]];
    
    connectedUseScripts    = (unsigned)[[argumentsUsedToStartOpenvpnstart objectAtIndex: OPENVPNSTART_ARG_USE_SCRIPTS_IX] intValue];
    [self setConnectedCfgLocCodeString: [argumentsUsedToStartOpenvpnstart objectAtIndex: OPENVPNSTART_ARG_CFG_LOC_CODE_IX]];
    
    if (  [argumentsUsedToStartOpenvpnstart count] == 0  ) {
        if (  userKnows  ) {
			[self setRequestedState: oldRequestedState]; // User cancelled
        }
        areConnecting = FALSE;
        completelyDisconnected = TRUE;
		
		if (  argumentsUsedToStartOpenvpnstart  ) {
			TBShowAlertWindow(NSLocalizedString(@"Tunnelblick", @"Window title"),
							  NSLocalizedString(@"There was a problem with the OpenVPN configuration. See the Console Log for details.", @"Window text"));
		}
        return;
    }
		
    [self showStatusWindowForce: YES]; // Force the VPN status window open (even if the user closed it earlier) because the user clicked "connect"

	wereWaitingForNetworkAvailability = FALSE;

	waitingForNetworkAvailability = (   ( ! [gTbDefaults boolForKey: @"doNotCheckForNetworkReachabilityWhenConnecting"])
									 && ( ! networkIsReachable() ));
	
	NSDictionary * dict = @{@"userKnows":      [NSNumber numberWithBool: userKnows],
							@"requestedState": [self requestedState]};
	
	if (  waitingForNetworkAvailability  ) {
		[self addToLog: @"Waiting for network to become available "];
		[self setConnectedSinceDate: [NSDate date]];
		[self clearStatisticsIncludeTotals: NO];
		[self setState: @"NETWORK_ACCESS"];
		stopWaitForNetworkAvailabilityThread = FALSE;
		[((MenuController *)[NSApp delegate]) addNonconnection: self];
		TBLog(@"DB-CD", @"connect:userKnows: Will wait for network availability in new thread")
		[NSThread detachNewThreadSelector: @selector(waitForNetworkAvailabilityThread:) toTarget: self withObject: dict];
		return;
	}
	
	[self finishMakingConnection: dict];
}

-(void) addMessageToDisplayIfConnectionFails: (NSString *) message {
	
	if (  ! [messagesIfConnectionFails containsObject: message]  ) {
		[messagesIfConnectionFails addObject: message];
		NSLog(@"%@", message);
	}
}

-(BOOL) shadowCopyIsIdentical
{
    NSString * cfgPath = [self configPath];
	NSString * name = lastPartOfPath(cfgPath);
	if (  ! [[name pathExtension] isEqualToString: @"tblk"]) {
		NSLog(@"Internal Tunnelblick error: '%@' is not a .tblk", name);
		return NO;
	}
	
	NSArray * arguments = [NSArray arrayWithObjects:@"compareShadowCopy", [self displayName], nil];
	OSStatus status =  runOpenvpnstart(arguments, nil, nil);
	
	switch (  status  ) {
			
		case OPENVPNSTART_COMPARE_CONFIG_SAME:
			return YES;
			break;
			
		case OPENVPNSTART_COMPARE_CONFIG_DIFFERENT:
			[self invalidateConfigurationParse];
			return NO;
			break;
			
		default:
			NSLog(@"Internal Tunnelblick error: unknown status %ld from compareShadowCopy(%@)", (long) status, [self displayName]);
            TBShowAlertWindow(NSLocalizedString(@"Warning", @"Window title"),
							  [NSString stringWithFormat: NSLocalizedString(@"An error (status %ld) occurred while trying to"
																			@" check the security of the %@ configuration.\n\n"
																			@"Please quit and relaunch Tunnelblick. If the problem persists, please"
																			@" reinstall Tunnelblick.", @"Window text"),
							   (long) status, [self localizedName]]);
			return NO;
	}
	
	return NO;	// Should never get here, but...
}

-(NSString *) setTunOrTapAndHasAuthUserPassAndAuthRetryParameter {
    
    if (  ! tunOrTap  ) {
		NSString * authRetryParameterTemp = nil;
		[self setTunOrTap: [ConfigurationManager parseConfigurationForConnection: self
																 hasAuthUserPass: &hasAuthUserPass
															  authRetryParameter: &authRetryParameterTemp]];

		[self setAuthRetryParameter: authRetryParameterTemp];
        
        // tunOrTap == 'Cancel' means we cancel whatever we're doing
        if (  [tunOrTap isEqualToString: @"Cancel"]  ) {
			[self invalidateConfigurationParse];
			return @"Cancel";
        }
    }
    
    return [self tunOrTap];
}

-(NSString *) tapOrTun {
	
	// This is the externally-referenced 'tunOrTap'
	return [self setTunOrTapAndHasAuthUserPassAndAuthRetryParameter];
}

-(BOOL) hasAuthUserPass {
    
    [self setTunOrTapAndHasAuthUserPassAndAuthRetryParameter];
    return hasAuthUserPass;
}

-(NSString *) authRetryParameter {
	
	[self setTunOrTapAndHasAuthUserPassAndAuthRetryParameter];
	return [[authRetryParameter retain] autorelease];
}

-(BOOL) hasAnySavedCredentials {
    
    NSString * name = [self displayName];
    return  (   keychainHasUsernameWithoutPasswordForDisplayName(name)
             || keychainHasUsernameAndPasswordForDisplayName(name)
             || keychainHasPrivateKeyForDisplayName(name)
             );
}

-(BOOL) mayConnectWhenComputerStarts {
    
    NSString * configurationPath = [self configPath];
    if (   [configurationPath hasPrefix: [gPrivatePath stringByAppendingString: @"/"]]  ) {
        return NO;  // Private paths may not start when computer starts
    }
    
    if (  ! [[configurationPath pathExtension] isEqualToString: @"tblk"]  ) {
        return NO;  // Only .tblks may start when computer starts
    }
    
    if (  [self hasAnySavedCredentials]  ) {
        return NO;  // Can't start when computer starts if have credentials
    }
    
    if (  [self hasAuthUserPass]  ) {
        return NO;  // Can't start when computer starts if have auth-user-pass unless it is from a file
    }
    
    return YES;
}

-(NSDictionary *) removedAndDeprecatedOptionsInfoForConfigurationFile: (NSString *) configString {
	
	// Returns a dictionary with:
	//		"removedInOpenvpnVersion"    the lowest OpenVPN version that removed any options that are contained in the configuration;
	//		"deprecatedInOpenvpnVersion" the lowest OpenVPN version that deprecated any options that are contained in the configuration; and
	//		"problematicOptions"         a localized string listing the problematic options and in which OpenVPN version each was deprecated and/or removed.
	//
	// If there are no deprecated options, "deprecatedInOpenvpnVersion" will not be present in the dictionary.
	// If there are no removed    options, "removedInOpenvpnVersion"    will not be present in the dictionary.
	//
	// If there are no deprecated or removed options in the configuration file, returns nil.

	// Dictionary with info about deprecated and removed options:
	//		OpenVPN version the option(s) were deprecated in,
	//		OpenVPN version the option(s) were removed in (if has a '?' suffix, the removal version has not been decided)
	//		Option name...
	//
	// These entries are based on the 2018-08-23 version of https://community.openvpn.net/openvpn/wiki/DeprecatedOptions
	
	NSArray * removedOptions = [NSArray arrayWithObjects:
								[NSArray arrayWithObjects: @"2.1", @"2.5",  @"ifconfig-pool-linear", nil],
								[NSArray arrayWithObjects: @"2.3", @"2.4",  @"remote-ip-hint", @"tls-remote", nil],
								[NSArray arrayWithObjects: @"2.3", @"2.5",  @"compat-names", @"no-name-remapping", nil],
								[NSArray arrayWithObjects: @"2.4", @"2.5",  @"client-cert-not-required", @"key-method", @"no-iv", @"no-replay", @"ns-cert-type", nil],
								[NSArray arrayWithObjects: @"2.4", @"2.5?", @"comp-lzo", @"max-routes", @"dhcp-release", nil],
								[NSArray arrayWithObjects: @"2.4", @"2.6",  @"keysize", nil],
								nil];
	
	NSString * lowestRemovedInOpenvpnVersion    = nil;
	NSString * lowestDeprecatedInOpenvpnVersion = nil;
	NSMutableString * optionsThatAreProblematic = [[[NSMutableString alloc] initWithCapacity: 1000] autorelease];
	
	NSString * deprecatedInOpenvpnVersion;
	NSString * removedInOpenvpnVersion;
	NSArray * removedList;
	for ( removedList in removedOptions  ) {
		deprecatedInOpenvpnVersion = [removedList firstObject];
		removedInOpenvpnVersion    = [removedList objectAtIndex: 1];
		NSUInteger ix;
		for (  ix=2; ix<[removedList count]; ix++  ) {
			NSString * option = [removedList objectAtIndex: ix];
			if (  [ConfigurationManager parseString: configString forOption: option]  ) {
				if (  [removedInOpenvpnVersion hasSuffix: @"?"]  ) {
					[optionsThatAreProblematic appendFormat: NSLocalizedString(@" • '%@' was deprecated in OpenVPN %@ and has been or will be removed in a later version\n\n",
																			   @"The first '%@' is the name of an OpenVPN option. The second '%@' is an OpenVPN version string such as '2.3' or '2.5'"),
					 option, deprecatedInOpenvpnVersion];
				} else {
					[optionsThatAreProblematic appendFormat: NSLocalizedString(@" • '%@' was deprecated in OpenVPN %@ and removed in OpenVPN %@\n\n",
																			   @"The first '%@' is the name of an OpenVPN option. The second '%@' and third '%@' are OpenVPN version strings such as '2.3' or '2.5'"),
					 option, deprecatedInOpenvpnVersion, removedInOpenvpnVersion];
					if (   ( ! lowestRemovedInOpenvpnVersion)
						|| [lowestRemovedInOpenvpnVersion compare: removedInOpenvpnVersion] == NSOrderedDescending  ) {
						lowestRemovedInOpenvpnVersion  = removedInOpenvpnVersion;
					}
				}
				
				if (   ( ! lowestDeprecatedInOpenvpnVersion)
					|| [lowestDeprecatedInOpenvpnVersion compare: deprecatedInOpenvpnVersion] == NSOrderedDescending  ) {
					lowestDeprecatedInOpenvpnVersion = deprecatedInOpenvpnVersion;
				}
			}
		}
	}
	
	if (   ( ! lowestRemovedInOpenvpnVersion )
		&& ( ! lowestDeprecatedInOpenvpnVersion)  ) {
		return nil;
	}
	
	NSMutableDictionary * dict = [[[NSMutableDictionary alloc] initWithCapacity: 3] autorelease];
	[dict setObject: optionsThatAreProblematic forKey: @"problematicOptions"];
	if (  lowestRemovedInOpenvpnVersion  ) {
		[dict setObject: lowestRemovedInOpenvpnVersion forKey:@"removedInOpenvpnVersion"];
	}
	if (  lowestDeprecatedInOpenvpnVersion  ) {
		[dict setObject: lowestDeprecatedInOpenvpnVersion forKey:@"deprecatedInOpenvpnVersion"];
	}
	
	return [NSDictionary dictionaryWithDictionary: dict];
}

-(NSDictionary *) addedOptionsInfoForConfigurationFile: (NSString *) configString {
	
	// Returns a dictionary with:
	//		"addedInOpenvpnVersion" the lowest OpenVPN version that added any options that are contained in the configuration;
	//		"problematicOptions"    a localized string listing the problematic options and in which OpenVPN version each was added.
	//
	// If all options in the configuration file are included in all versions of OpenVPN, returns nil.
	
	// Dictionary with info about added options:
	//		OpenVPN version the option(s) first appeared in,
	//		Option name...

	NSArray * addedOptions = @[
							   @[@"2.4",
								 @"auth-gen-token", @"compat-names", @"compress", @"ecdh-curve", @"http-proxy-user-pass", @"ip-remote-hint",
								 @"keying-material-exporter", @"machine-readable-output", @"management-external-cert", @"msg-channel",
								 @"ncp-ciphers", @"ncp-disable", @"preresolve", @"pull-filter", @"push-remove", @"show-curves", @"tls-crypt",
								 @"verify-client-cert",],
							   
							   @[@"2.5",
								 @"tls-cert-profile", @"tls-crypt-v2", @"tls-crypt-v2-verify"],
							   ];
	
	NSString * lowestAddedInOpenvpnVersion = nil;
	NSMutableString * optionsThatAreProblematic = [[[NSMutableString alloc] initWithCapacity: 1000] autorelease];
	
	NSString * addedInOpenvpnVersion;
	NSArray * addedList;
	for ( addedList in addedOptions  ) {
		addedInOpenvpnVersion = [addedList firstObject];
		NSUInteger ix;
		for (  ix=1; ix<[addedList count]; ix++  ) {
			NSString * option = [addedList objectAtIndex: ix];
			if (  [ConfigurationManager parseString: configString forOption: option]  ) {
				[optionsThatAreProblematic appendFormat: NSLocalizedString(@"'%@' was added in OpenVPN %@\n",
																		   @"The first '%@' is the name of an OpenVPN option. The second '%@' is an OpenVPN version string such as '2.3' or '2.5'"),
				 option, addedInOpenvpnVersion];
				if (   ( ! lowestAddedInOpenvpnVersion )
					|| [lowestAddedInOpenvpnVersion compare: addedInOpenvpnVersion] == NSOrderedDescending  ) {
					lowestAddedInOpenvpnVersion  = addedInOpenvpnVersion;
				}
			}
		}
	}
	
	if (  ! lowestAddedInOpenvpnVersion  ) {
		return nil;
	}
	
	return [NSDictionary dictionaryWithObjectsAndKeys:
			lowestAddedInOpenvpnVersion, @"addedInOpenvpnVersion",	 // One or more options is added in this version of OpenVPN
			optionsThatAreProblematic,	 @"problematicOptions",
			nil];
}

-(NSUInteger) defaultVersionIxFromVersionNames: (NSArray *) versionNames {
	
	// Use the default version of OpenVPN, from the "default" link
	NSUInteger useVersionIx;
	NSString * folderName = defaultOpenVpnFolderName();
	if (  [folderName hasPrefix: @"openvpn-"]  ) {
		NSString * versionName = [folderName substringFromIndex: [@"openvpn-" length]];
		useVersionIx = [versionNames indexOfObject: versionName];
		if (  useVersionIx == NSNotFound  ) {
			NSLog(@"Default OpenVPN '%@' not found. Using '%@'", versionName, [versionNames firstObject]);
			useVersionIx = 0;
		}
	} else {
		NSLog(@"Default OpenVPN '%@' not prefixed by '-openvpn'. Using '%@'", folderName, [versionNames firstObject]);
		useVersionIx = 0;
	}
	
	return useVersionIx;
}

-(NSString *) openvpnAndVersionLocalized: (NSString *) version {
	
	NSString * name = displayNameForOpenvpnName(version, nil);
	NSString * result = (  name
						 ? [NSString stringWithFormat:
							NSLocalizedString(@"OpenVPN %@",
											  @"Window text. The %@ is an OpenVPN version number, e.g. '2.3 - OpenSSL v1.0.2n'."),
							version]
						 : [NSString stringWithFormat:
							NSLocalizedString(@"OpenVPN %@, which is not available in this version of Tunnelblick",
											  @"Window text. The %@ is an OpenVPN version number, e.g. '2.3 - OpenSSL v1.0.2n'."),
							version]);
	return  result;
}

-(NSString *) openvpnVersionMayBeUnavailable: (NSString *) version {
	
	NSString * name = displayNameForOpenvpnName(version, nil);
	NSString * result = (  name
						 ? version
						 : [version stringByAppendingString: @"%@ (unavailable)"]);
	return  result;
}

-(NSUInteger) getOpenVPNVersionIxToUseConnecting: (BOOL) connecting {

	// Decides what version of OpenVPN to use with the configuration and returns its index in MenuController's "openvpnVersionNames" array.
	//
	// Returns NSNotFound if no version of OpenVPN in this copy of Tunnelblick can be used with the configuration (because the OpenVPN
	// configuration file contains options that are not included in any version of OpenVPN in this copy of Tunnelblick).
	//
	// Will pop up a window telling the user if:
	//
	//		The configuration cannot be used because it contains options that are not included in any version of OpenVPN in this copy of Tunnelblick,
	//			or
	//		the configuration contains options that have been deprecated,
	//			or
	//		the user specified a version of OpenVPN that is not available in this copy of Tunnelblick (a different version will be used).

	// We first decide what version the user would like, and then try to get as close a match to that version as possible, then adjust that if
	// the configuration requires a different version (because it contains options that are not included in that version).
	
	NSArray  * versionNames = [((MenuController *)[NSApp delegate]) openvpnVersionNames];

	// Get info about the version that the user has specified (or defaulted to)
    NSString * prefKey = [[self displayName] stringByAppendingString: @"-openvpnVersion"];
    NSString * prefVersionName = [gTbDefaults stringForKey: prefKey];
	BOOL isDefault = ([prefVersionName length] == 0);
	BOOL isLatest  = ([prefVersionName isEqualToString: @"-"]);
	
	NSUInteger versionIx = (  isDefault
							? [self defaultVersionIxFromVersionNames: versionNames]
							: (  isLatest
							   ? [versionNames count] - 1
							   : (  prefVersionName
								  ? [versionNames indexOfObject: prefVersionName]
								  : NSNotFound)));

	BOOL weHaveRequestedVersion = ( versionIx != NSNotFound );
	
	NSString * versionWanted = (  weHaveRequestedVersion
								? [versionNames objectAtIndex: versionIx]
								: [[prefVersionName copy] autorelease]);
	
	NSString * versionNameFromPreference = (  isDefault
											? [versionNames firstObject]
											: (  isLatest
											   ? [versionNames lastObject]
											   : prefVersionName
											   )
											);

	BOOL wantOpenSSL = ( [versionNameFromPreference rangeOfString: @"libressl"].length == 0 );
	
	NSString * sslString = (  wantOpenSSL
							? @"openssl"
							: @"libressl");
	
	NSString * versionToTry = (  weHaveRequestedVersion
							   ? [versionNames objectAtIndex: versionIx]
							   : nil);
	
	if (  ! versionToTry  ) {
		
		// We don't have the version of OpenVPN specified by the user. Try to find one with the same major.minor version and the same SSL type
		NSString * requestedMajorMinor = [prefVersionName substringToIndex: 3];
		NSString * version;
		NSUInteger ix;
		for (  ix=0; ix<[versionNames count]; ix++  ) {
			version = [versionNames objectAtIndex: ix];
			if (  [version hasPrefix: requestedMajorMinor]  ) {
				if (  [version rangeOfString: sslString].length != 0  ) {
					versionToTry = [[version copy] autorelease];
					break;
				}
			}
		}
		
		BOOL chooseSameOpenvpnOverSameSsl = [gTbDefaults boolForKey: @"chooseSameOpenvpnOverSameSsl"];
		
		if (   (! versionToTry)
			&& chooseSameOpenvpnOverSameSsl  ) {
			// Don't have the same major.minor with the same SSL that the user specified, try to get the same major.minor with any SSL type
			for (  ix=0; ix<[versionNames count]; ix++  ) {
				version = [versionNames objectAtIndex: ix];
				if (  [version hasPrefix: requestedMajorMinor]  ) {
					versionToTry = [[version copy] autorelease];
					break;
				}
			}
		}
		
		if (  ! versionToTry  ) {
			// Don't have the same major.minor, try to at least get SSL that the user specified
			for (  ix=0; ix<[versionNames count]; ix++  ) {
				version = [versionNames objectAtIndex: ix];
				if (  [version rangeOfString: sslString].length != 0  ) {
					versionToTry = [[version retain] autorelease];
					break;
				}
			}
		}
		
		if (   (! versionToTry)
			&& ( ! chooseSameOpenvpnOverSameSsl )  ) {
			// Don't have the same major.minor with the SSL that the user specified, try to get the same major.minor with any SSL type
			for (  ix=0; ix<[versionNames count]; ix++  ) {
				version = [versionNames objectAtIndex: ix];
				if (  [version hasPrefix: requestedMajorMinor]  ) {
					versionToTry = [[version copy] autorelease];
					break;
				}
			}
		}
		
		if (  ! versionToTry  ) {
			// Can't find a match to either major.minor or to SSL, so use default
			ix = [self defaultVersionIxFromVersionNames: versionNames];
			versionToTry = [versionNames objectAtIndex: ix];
		}
	}
	
	if (  [gTbDefaults boolForKey: @"doNotCheckThatOpenvpnVersionIsCompatibleWithConfiguration"]  ) {
		return [versionNames indexOfObject: versionToTry];
	}
	
	// We have a version to try. Make sure the configuration can be used with that version.

	NSString * configString = [self condensedSanitizedConfigurationFileContents];
	NSString * originalVersionToTry = [[versionToTry retain] autorelease];
	
	// Deal with removed options in this configuration file
	NSDictionary * removedAndDeprecatedOptionsInfo = [self removedAndDeprecatedOptionsInfoForConfigurationFile: configString];
	NSString * removedInMajorMinor = [removedAndDeprecatedOptionsInfo objectForKey: @"removedInOpenvpnVersion"];

	if (  removedInMajorMinor  ) {

		while (  [[versionToTry substringToIndex: 3] compare: removedInMajorMinor] != NSOrderedAscending  ) {
			
			// Config has option(s) that were removed. Try the next lower OpenVPN version with the requested SSL.
			
			NSInteger ixOfNextLowerVersion = [versionNames indexOfObject: versionToTry] - 1;
			if (  ixOfNextLowerVersion < 0  ) {
				break;
			}
			versionToTry = [versionNames objectAtIndex: ixOfNextLowerVersion];
			
			if (  [versionToTry rangeOfString: sslString].length != 0  ) {
				break;
			}
		}
		
		if (  [[versionToTry substringToIndex: 3] compare: removedInMajorMinor] != NSOrderedAscending) {
			
			versionToTry = [[originalVersionToTry retain] autorelease];
			while (  [[versionToTry substringToIndex: 3] compare: removedInMajorMinor] != NSOrderedAscending  ) {
				
				// Config has option(s) that were removed. Try the next lower OpenVPN version IGNORING the requested SSL.
				
				NSInteger ixOfNextLowerVersion = [versionNames indexOfObject: versionToTry] - 1;
				if (  ixOfNextLowerVersion < 0  ) {
					break;
				}
				versionToTry = [versionNames objectAtIndex: ixOfNextLowerVersion];
			}

			if (  [[versionToTry substringToIndex: 3] compare: removedInMajorMinor] != NSOrderedAscending) {

				// One or more options in the configuration file are not included in any version of OpenVPN in this copy of Tunnelblick
				if (  connecting  )  {
					TBLog(@"DB-CD", @"Cannot connect %@ because the configuration file includesone or more options that are not included in any OpenVPN version in this version of Tunnelblick",
						  [self displayName]);
				}
				NSString * problematicOptions =[removedAndDeprecatedOptionsInfo objectForKey: @"problematicOptions"];
				TBShowAlertWindow(NSLocalizedString(@"Tunnelblick", @"Window title"),
								  [NSString stringWithFormat:
								   NSLocalizedString(@"This VPN cannot be connected.\n\n"
													 @"The OpenVPN configuration file for '%@' contains these OpenVPN options:\n\n"
													 @"%@\n"
													 @"None of the versions of OpenVPN included in this version of Tunnelblick include the option(s).\n\n"
													 @"You should update the configuration so it can be used with modern versions of OpenVPN.",
													 
													 @"Window text."
													 @" The first '%@' will be replaced by the name of a configuration."
													 @" The second '%@' will be replaced by a list of names of OpenVPN options and when each was deprecated and removed."),
								   [self displayName], problematicOptions]);
				
				return NSNotFound;
			}
		}
	}

	// Deal with added options in this configuration file
	NSDictionary * addedOptionsInfo = [self addedOptionsInfoForConfigurationFile: configString];
	NSString * addedInMajorMinor = [addedOptionsInfo objectForKey: @"addedInOpenvpnVersion"];

	if (  addedInMajorMinor  ) {
		

		while (  [[versionToTry substringToIndex: 3] compare: addedInMajorMinor] == NSOrderedAscending  ) {
			
			// Config has option(s) that were added in a later. Try the next OpenVPN version with the requested SSL.

			NSUInteger ixOfNextHigherVersion = [versionNames indexOfObject: versionToTry] + 1;
			if (  ixOfNextHigherVersion > [versionNames count]  ) {
				break;
			}
			versionToTry = [versionNames objectAtIndex: ixOfNextHigherVersion];
			
			if (  [versionToTry rangeOfString: sslString].length != 0  ) {
				break;
			}
		}
		
		if (  [[versionToTry substringToIndex: 3] compare: addedInMajorMinor] == NSOrderedAscending) {
			
			versionToTry = [[originalVersionToTry retain] autorelease];
			while (  [[versionToTry substringToIndex: 3] compare: addedInMajorMinor] == NSOrderedAscending  ) {
				
				// Config has option(s) that were added. Try the next OpenVPN version IGNORING the requested SSL.
				
				NSUInteger ixOfNextHigherVersion = [versionNames indexOfObject: versionToTry] + 1;
				if (  ixOfNextHigherVersion > [versionNames count]  ) {
					break;
				}
				versionToTry = [versionNames objectAtIndex: ixOfNextHigherVersion];
			}
			
			if (  [[versionToTry substringToIndex: 3] compare: addedInMajorMinor] == NSOrderedAscending) {
				
				// One or more options in the configuration file are not included in any version of OpenVPN in this copy of Tunnelblick
				if (  connecting  )  {
					TBLog(@"DB-CD", @"Cannot connect %@ because the configuration file includesone or more options that are not included in any OpenVPN version in this version of Tunnelblick",
						  [self displayName]);
				}
				NSString * problematicOptions =[removedAndDeprecatedOptionsInfo objectForKey: @"problematicOptions"];
				TBShowAlertWindow(NSLocalizedString(@"Tunnelblick", @"Window title"),
								  [NSString stringWithFormat:
								   NSLocalizedString(@"This VPN cannot be connected.\n\n"
													 @"The OpenVPN configuration file for '%@' contains these OpenVPN options:\n\n"
													 @"%@\n"
													 @"None of the versions of OpenVPN included in this version of Tunnelblick include the option(s).\n\n"
													 @"You should update the configuration so it can be used with modern versions of OpenVPN.",
													 
													 @"Window text."
													 @" The first '%@' will be replaced by the name of a configuration."
													 @" The second '%@' will be replaced by a list of names of OpenVPN options and when each was deprecated and removed."),
								   [self displayName], problematicOptions]);
				
				return NSNotFound;
			}
		}
	}
	
	// We have a version of OpenVPN that can be used. Warn if the configuration includes any deprecated options
	
	NSString * key = [[self displayName] stringByAppendingString: @"-skipWarningThatNotUsingSpecifiedOpenVPN"];

	NSString * warningMessage1 = @"";

	NSString * deprecatedInMajorMinor = [removedAndDeprecatedOptionsInfo objectForKey: @"deprecatedInOpenvpnVersion"];

	if (  deprecatedInMajorMinor  ) {
		if (  [[versionToTry substringToIndex: 3] compare: deprecatedInMajorMinor] != NSOrderedAscending) {
			if (  connecting  )  {
				TBLog(@"DB-CD", @"Connecting %@ using OpenVPN %@ which has deprecated options",
					  [self displayName], displayNameForOpenvpnName(versionToTry, versionToTry));
			}
			NSString * problematicOptions =[removedAndDeprecatedOptionsInfo objectForKey: @"problematicOptions"];
			warningMessage1 = [NSString stringWithFormat:
							   NSLocalizedString(@"Warning: This VPN may not connect in the future.\n\n"
												 
												 @"The OpenVPN configuration file for '%@' contains these OpenVPN options:\n\n"
												 
												 @"%@\n"
												 
												 @"You should update the configuration so it can be used with modern versions of OpenVPN.\n\n"
												 
												 @"Tunnelblick will use OpenVPN %@ to connect this configuration.\n\n"
												 
												 @"However, you will not be able to connect to this VPN with future versions of"
												 @" Tunnelblick that do not include a version of OpenVPN that accepts the options.",
												 
												 @"Window text."
												 @" The first '%@' will be replaced by the name of a configuration."
												 @" The third '%@' will be replaced by a list of names of OpenVPN options, one on each line."
												 @" The forth '%@' will be replaced by the name of a version of OpenVPN, e.g. '2.3 - OpenSSL v1.0.2n'"),
							   [self displayName], problematicOptions, displayNameForOpenvpnName(versionToTry, versionToTry)];
		}
	}

	NSString * warningMessage2 = @"";
	
	if (  [versionWanted isNotEqualTo: versionToTry]  ) {
		NSLog(@"Configuration %@ will use OpenVPN %@ instead of %@",
			  [self displayName], displayNameForOpenvpnName(versionToTry, versionToTry), [self openvpnVersionMayBeUnavailable: versionWanted]);
		if (  connecting  )  {
			TBLog(@"DB-CD", @"Connecting %@ using OpenVPN %@ instead of %@",
				  [self displayName], displayNameForOpenvpnName(versionToTry, versionToTry), [self openvpnVersionMayBeUnavailable: versionWanted]);
		}
		warningMessage2 = [NSString stringWithFormat:
						   NSLocalizedString(@"'%@' will connect using OpenVPN %@ instead of the requested version (%@).",
											 @"Window text."
											 @" The first '%@' will be replaced by the name of a configuration."
											 @" The second and third '%@' will each be replaced by the name of a version of OpenVPN, e.g. '2.3 - OpenSSL v1.0.2n"),
						   [self displayName],
						   displayNameForOpenvpnName(versionToTry, versionToTry),
						   [self openvpnAndVersionLocalized: versionWanted]];
	}
	
	NSString * warningMessage = (  ([warningMessage2 length] != 0)
								 ? (  ([warningMessage1 length] != 0)
									? [NSString stringWithFormat: @"%@\n\n%@", warningMessage2, warningMessage1]
									: warningMessage2)
								 : (  ([warningMessage1 length] != 0)
									? warningMessage1
									: nil)
								 );
 
	if (  warningMessage  ) {
		// Warn about this at most once per minute for this configuration.
		// This avoids the problem that this method may be called several times before the user has a chance to respond to the warning.
		time_t now = time(NULL);
		if (  (now - timeLastWarnedAboutOpenVPNVersion) > 60  ) {
			timeLastWarnedAboutOpenVPNVersion = now;
			TBShowAlertWindowExtended(NSLocalizedString(@"Tunnelblick", @"Window title"),
									  warningMessage,
									  key,
									  nil,
									  nil,
									  nil,
									  nil,
									  NO);
		}
	}
	
	return [versionNames indexOfObject: versionToTry];
}

-(NSArray *) argumentsForOpenvpnstartForNow: (BOOL) forNow
								  userKnows: (BOOL) userKnows {
	
	// Returns nil if user cancelled or an error message has been shown to the user
	
    NSString * cfgPath = [self configPath];

    if (   [cfgPath hasPrefix: [gPrivatePath stringByAppendingString: @"/"]]  ) {
        if (  ! [self shadowCopyIsIdentical]  ) {
			
			[ConfigurationManager createShadowConfigurationInNewThreadWithDisplayName: [self displayName] thenConnectUserKnows: userKnows];
			return nil;
		}
    }

    BOOL useShadowCopy = [cfgPath hasPrefix: [gPrivatePath  stringByAppendingString: @"/"]];
    BOOL useDeploy     = [cfgPath hasPrefix: [gDeployPath   stringByAppendingString: @"/"]];
    BOOL useShared     = [cfgPath hasPrefix: [L_AS_T_SHARED stringByAppendingString: @"/"]];
    
    // "port" argument to openvpnstart is the port to use for the management interface:
	// If "forNow" (starting from the GUI) we find a free port now and remember it for immediate use
    // else we use 0 to flag that openvpnstart should find a free port
    unsigned int thePort;
    if (  forNow  ) {
        thePort = getFreePort();
        if (  thePort == 0  ) {
			TBShowAlertWindow(NSLocalizedString(@"Tunnelblick", @"Window title"),
							  NSLocalizedString(@"Tunnelblick could not find a free port to use for communication with OpenVPN", @"Window text"));
			return nil;
        }
        [self setPort: thePort]; // GUI active, so remember the port number
    } else {
        thePort = 0;
    }
    NSString *portString = [NSString stringWithFormat:@"%u", thePort];
    
    // Parse configuration file to catch "user" or "group" options and get tun/tap key
    [self setTunOrTapAndHasAuthUserPassAndAuthRetryParameter];
	if (  [tunOrTap isEqualToString: @"Cancel"]  ) {
		return nil;
	} else if (  ! tunOrTap  ) {
		TBShowAlertWindow(NSLocalizedString(@"Tunnelblick", @"Window title"),
						  NSLocalizedString(@"Tunnelblick could not find a 'tun' or 'tap' option in the OpenVPN configuration file", @"Window text"));
		return nil;
	}
    
    unsigned useDNSNum = 0;
    unsigned useDNSStat = (unsigned) [self useDNSStatus];
	if(  useDNSStat == 0) {
        if (  forNow  ) {
            usedModifyNameserver = FALSE;
        }
	} else {
        NSString * useDownRootPluginKey = [[self displayName] stringByAppendingString: @"-useDownRootPlugin"];
        BOOL useDownRoot = [gTbDefaults boolForKey: useDownRootPluginKey];
        useDNSNum = (  (useDNSStat-1) << 2) + (useDownRoot ? 2 : 0) + 1;   // (script #) + downroot-flag + set-nameserver-flag
        if (  forNow  ) {
            usedModifyNameserver = TRUE;
        }
    }
    NSString * key = [[self displayName] stringByAppendingString: @"-loggingLevel"];
    NSUInteger loggingLevelPreference = [gTbDefaults unsignedIntForKey: key
                                                               default: TUNNELBLICK_DEFAULT_LOGGING_LEVEL
                                                                   min: MIN_OPENVPN_LOGGING_LEVEL
                                                                   max: MAX_TUNNELBLICK_LOGGING_LEVEL];
    if (  loggingLevelPreference != TUNNELBLICK_NO_LOGGING_LEVEL  ) {
        useDNSNum = useDNSNum | (loggingLevelPreference << OPENVPNSTART_VERB_LEVEL_SHIFT_COUNT);
    }
    NSString * useDNSArg = [NSString stringWithFormat: @"%u", useDNSNum];
    
    NSString * skipScrSec = @"0";   // Clear skipScrSec so we use "--script-security 2" because we are now always use OpenVPN v. 2.1_rc9 or higher

    
    NSString *altCfgLoc = @"0";
    if ( useShadowCopy ) {
        altCfgLoc = @"1";
    } else if (  useDeploy  ) {
        altCfgLoc = @"2";
    } else if (  useShared  ) {
        altCfgLoc = @"3";
    }
    
    NSString * noMonitor = @"1";
    NSString * noMonitorKey = [[self displayName] stringByAppendingString: @"-notMonitoringConnection"];
    if (  ! [gTbDefaults boolForKey: noMonitorKey]  ) { // Monitor only if monitoring enabled
        unsigned onlyDNSFlags = useDNSNum & 0xFD;       //
        if (   (onlyDNSFlags == 0x01)                   //                 and "Set nameserver"
            || (onlyDNSFlags == 0x05)                   //                 or "Set nameserver (3.1)"
            ) {
            noMonitor = @"0";
        }
    }

    unsigned int bitMask = 0;
    if (  [tunOrTap isEqualToString: @"tap"]  ) {
        bitMask = OPENVPNSTART_USE_TAP;
    }

	NSString * preferenceKey = [displayName stringByAppendingString: @"-loadTap"];
	NSString * preference = [gTbDefaults stringForKey: preferenceKey];
	if (  [preference isEqualToString: @"always"]  ) {
		bitMask = bitMask | OPENVPNSTART_OUR_TAP_KEXT;
	} else if (   (! preference)
               || ( [preference length] == 0)  ) {
        if (   ( ! tunOrTap )
            || [tunOrTap isEqualToString: @"tap"]  ) {
            bitMask = bitMask | OPENVPNSTART_OUR_TAP_KEXT;
        }
    } else if (  ! [preference isEqualToString: @"never"]  ) {
        [self addToLog: [NSString stringWithFormat: @"Cannot recognize the %@ preference value of '%@', so Tunnelblick will load the tap kext", preferenceKey, preference]];
        bitMask = bitMask | OPENVPNSTART_OUR_TUN_KEXT;
    }
    
	preferenceKey = [displayName stringByAppendingString: @"-loadTun"];
	preference = [gTbDefaults stringForKey: preferenceKey];
	if (  [preference isEqualToString: @"always"]  ) {
		bitMask = bitMask | OPENVPNSTART_OUR_TUN_KEXT;
	} else if (   (! preference)
               || ( [preference length] == 0)  ) {
		// "automatic", so if an "dev-type tun" OpenVPN option was seen we must load our tun kext, otherwise we let OpenVPN use the utun device
        if (  [tunOrTap isEqualToString: @"tun"]  ) {
            bitMask = bitMask | OPENVPNSTART_OUR_TUN_KEXT;
        }
    } else if (  ! [preference isEqualToString: @"never"]  ) {
        [self addToLog: [NSString stringWithFormat: @"Cannot recognize the %@ preference value of '%@', so Tunnelblick will not load the tun kext", preferenceKey, preference]];
    }
    
    NSString * runMtuTestKey = [displayName stringByAppendingString: @"-runMtuTest"];
    if (  [gTbDefaults boolForKey: runMtuTestKey]  ) {
        bitMask = bitMask | OPENVPNSTART_TEST_MTU;
    }
    
    NSString * autoConnectKey   = [displayName stringByAppendingString: @"autoConnect"];
    NSString * onSystemStartKey = [displayName stringByAppendingString: @"-onSystemStart"];
    BOOL onsystemStart = (   [gTbDefaults boolForKey: autoConnectKey]
                          && [gTbDefaults boolForKey: onSystemStartKey]);
    if (   forNow
        && ( ! onsystemStart )  ) {
        bitMask = bitMask | OPENVPNSTART_NOT_WHEN_COMPUTER_STARTS;
    }
    
    [self setBit: OPENVPNSTART_RESTORE_ON_WINS_RESET				inMask: &bitMask ifConnectionPreference: @"-doNotRestoreOnWinsReset"						inverted: YES defaultTo: NO];
    [self setBit: OPENVPNSTART_RESTORE_ON_DNS_RESET					inMask: &bitMask ifConnectionPreference: @"-doNotRestoreOnDnsReset"							inverted: YES defaultTo: NO];
    [self setBit: OPENVPNSTART_PREPEND_DOMAIN_NAME					inMask: &bitMask ifConnectionPreference: @"-prependDomainNameToSearchDomains"				inverted: NO  defaultTo: NO];
    [self setBit: OPENVPNSTART_FLUSH_DNS_CACHE						inMask: &bitMask ifConnectionPreference: @"-doNotFlushCache"								inverted: YES defaultTo: NO];
    [self setBit: OPENVPNSTART_USE_ROUTE_UP_NOT_UP					inMask: &bitMask ifConnectionPreference: @"-useUpInsteadOfRouteUp"							inverted: YES defaultTo: NO];
    [self setBit: OPENVPNSTART_RESET_PRIMARY_INTERFACE				inMask: &bitMask ifConnectionPreference: @"-resetPrimaryInterfaceAfterDisconnect"			inverted: NO  defaultTo: NO];
	[self setBit: OPENVPNSTART_DISABLE_INTERNET_ACCESS				inMask: &bitMask ifConnectionPreference: @"-disableNetworkAccessAfterDisconnect"			inverted: NO  defaultTo: NO];
	[self setBit: OPENVPNSTART_RESET_PRIMARY_INTERFACE_UNEXPECTED	inMask: &bitMask ifConnectionPreference: @"-resetPrimaryInterfaceAfterUnexpectedDisconnect"	inverted: NO  defaultTo: NO];
	[self setBit: OPENVPNSTART_DISABLE_INTERNET_ACCESS_UNEXPECTED	inMask: &bitMask ifConnectionPreference: @"-disableNetworkAccessAfterUnexpectedDisconnect"	inverted: NO  defaultTo: NO];
    [self setBit: OPENVPNSTART_USE_REDIRECT_GATEWAY_DEF1			inMask: &bitMask ifConnectionPreference: @"-routeAllTrafficThroughVpn"						inverted: NO  defaultTo: NO];
    [self setBit: OPENVPNSTART_NO_DEFAULT_DOMAIN					inMask: &bitMask ifConnectionPreference: @"-doNotUseDefaultDomain"							inverted: NO  defaultTo: NO];
	[self setBit: OPENVPNSTART_OVERRIDE_MANUAL_NETWORK_SETTINGS		inMask: &bitMask ifConnectionPreference: @"-allowChangesToManuallySetNetworkSettings"		inverted: NO  defaultTo: NO];
    [self setBit: OPENVPNSTART_WAIT_FOR_DHCP_IF_TAP					inMask: &bitMask ifConnectionPreference: @"-waitForDHCPInfoIfTap"							inverted: NO  defaultTo: NO];
    [self setBit: OPENVPNSTART_DO_NOT_WAIT_FOR_INTERNET				inMask: &bitMask ifConnectionPreference: @"-doNotWaitForInternetAtBoot"						inverted: NO  defaultTo: NO];
    [self setBit: OPENVPNSTART_ENABLE_IPV6_ON_TAP					inMask: &bitMask ifConnectionPreference: @"-enableIpv6OnTap"								inverted: NO  defaultTo: NO];
    [self setBit: OPENVPNSTART_DISABLE_IPV6_ON_TUN					inMask: &bitMask ifConnectionPreference: @"-doNotDisableIpv6onTun"							inverted: YES defaultTo: NO];
    
    if (  loggingLevelPreference == TUNNELBLICK_NO_LOGGING_LEVEL  ) {
        bitMask = bitMask | OPENVPNSTART_DISABLE_LOGGING;
    }
    
    if (  [gTbDefaults boolForKey: @"DB-UP"] || [gTbDefaults boolForKey: @"DB-ALL"]  ) {
        bitMask = bitMask | OPENVPNSTART_EXTRA_LOGGING;
    }
    
    NSString * bitMaskString = [NSString stringWithFormat: @"%d", bitMask];
    
    NSString * leasewatchOptionsKey = [displayName stringByAppendingString: @"-leasewatchOptions"];
    NSString * leasewatchOptions = [gTbDefaults stringForKey: leasewatchOptionsKey];
    if (  leasewatchOptions  ) {
        if (  [leasewatchOptions hasPrefix: @"-i"]  ) {
            NSCharacterSet * optionCharacterSet = [NSCharacterSet characterSetWithCharactersInString: @"dasngw"];
            NSRange r = [[leasewatchOptions substringFromIndex: 2] rangeOfCharacterFromSet: [optionCharacterSet invertedSet]];
            if (  r.length != 0  ) {
                NSLog(@"Invalid '%@' preference (must start with '-i', then have only 'd', 'a', 's', 'n', 'g', 'w'). Ignoring the preference.", leasewatchOptionsKey);
                leasewatchOptions = @"";
            }
        } else {
            NSLog(@"Invalid '%@' preference (must start with '-i'). Ignoring the preference.", leasewatchOptionsKey);
            leasewatchOptions = @"";
        }
    } else {
        leasewatchOptions = [self leasewatchOptionsFromPreferences];
    }
    
	NSUInteger finalOpenvpnIx = [self getOpenVPNVersionIxToUseConnecting: YES];
	if (  finalOpenvpnIx == NSNotFound  ) {
		return nil;
	}
	
    NSString * ourOpenVPNVersion = [[((MenuController *)[NSApp delegate]) openvpnVersionNames] objectAtIndex: finalOpenvpnIx];

    NSArray * args = [NSArray arrayWithObjects:
                      @"start", [[lastPartOfPath(cfgPath) copy] autorelease], portString, useDNSArg, skipScrSec, altCfgLoc, noMonitor, bitMaskString, leasewatchOptions, ourOpenVPNVersion, nil];

    // IF THE NUMBER OF ARGUMENTS CHANGES:
    //    (1) Modify openvpnstart to use the new arguments
    //    (2) Change OPENVPNSTART_MAX_ARGC in defines.h to the maximum 'argc' for openvpnstart
    //        (That is, change it to one more than the number of entries in 'args' (because the path to openvpnstart is also an argument)
    //    (3) Change the constant integer in the next line to the same number
#if 11 != OPENVPNSTART_MAX_ARGC
    #error "OPENVPNSTART_MAX_ARGC is not correct. It must be 1 more than the count of the 'args' array"
#endif
    
    if (  [args count] + 1  != OPENVPNSTART_MAX_ARGC  ) {
        NSLog(@"Program error: [args count] = %ld, but OPENVPNSTART_MAX_ARGC = %d. It should be one more than [args count].", (long) [args count], OPENVPNSTART_MAX_ARGC);
    }

    return args;
}

-(void)         setBit: (unsigned int)   bit
				inMask: (unsigned int *) bitMaskPtr
ifConnectionPreference: (NSString *)     keySuffix
			  inverted: (BOOL)           invert
			 defaultTo: (BOOL)           defaultsTo
{
    NSString * prefKey = [[self displayName] stringByAppendingString: keySuffix];
    BOOL value = (  defaultsTo
				  ? [gTbDefaults boolWithDefaultYesForKey: prefKey]
				  : [gTbDefaults boolForKey: prefKey]);
	if (  value  ) {
        if (  ! invert  ) {
            *bitMaskPtr = *bitMaskPtr | bit;
        }
    } else {
        if (  invert  ) {
            *bitMaskPtr = *bitMaskPtr | bit;
        }
    }
}

-(NSString * ) leasewatchOptionsFromPreferences
{
    NSArray * chars = [NSArray arrayWithObjects: @"a", @"d", @"s", @"g", @"n", @"w", @"A", @"D", @"S", @"G", @"N", @"W", nil];
    NSArray * preferenceKeys = [NSArray arrayWithObjects:
                                @"-changeDNSServersAction",
                                @"-changeDomainAction",
                                @"-changeSearchDomainAction",
                                @"-changeWINSServersAction",
                                @"-changeNetBIOSNameAction",
                                @"-changeWorkgroupAction",
                                @"-changeOtherDNSServersAction",
                                @"-changeOtherDomainAction",
                                @"-changeOtherSearchDomainAction",
                                @"-changeOtherWINSServersAction",
                                @"-changeOtherNetBIOSNameAction",
                                @"-changeOtherWorkgroupAction",
                                nil];
    
    // Get the preference values. Use -1 for any preference that isn't present
    NSMutableArray * preferenceValues = [NSMutableArray arrayWithCapacity: 12];
    unsigned i;
    for (  i=0; i<[preferenceKeys count]; i++  ) {
        NSString * key = [[self displayName] stringByAppendingString: [preferenceKeys objectAtIndex: i]];
        NSString * value = [gTbDefaults stringForKey: key];
        int intValue;
        if (  value  ) {
			if (  [value isEqualToString:@"ignore"]  ) {
				intValue = 0;
			} else if (  [value isEqualToString:@"restore"]  ) {
				intValue = 1;
			} else if (  [value isEqualToString:@"restart"]  ) {
				intValue = 2;
			} else {
                NSLog(@"Preference '%@' is not 'ignore', 'restore', or 'restart'; it will be ignored", key);
                intValue = -1;
            }
        } else {
            intValue = -1;
        }
        
        // If no prefererence, changes to pre-VPN will be undone and other changes will cause a restart
        if (  intValue == -1  ) {
            if (  i < 6  ) {
                intValue = 1;			// pre-VPN default is restore
            } else if (  i == 8  ) {
				intValue = 0;			// Default for other SearchDomains is ignore
			} else {
                intValue = 2;			// Defai;t fpr others is restart
            }
        }

        [preferenceValues addObject: [NSNumber numberWithInt: intValue]];
    }
        
    // Go though preferences and pull out those that force RESTARTS
    NSMutableString * restartOptions = [NSMutableString stringWithCapacity: [preferenceKeys count] + 2];
    for (  i=0; i<[preferenceKeys count]; i++  ) {
        if (  [[preferenceValues objectAtIndex: i] intValue] == 2  ) {
            [restartOptions appendString: [chars objectAtIndex: i]];
        }
    }
    
    // Go though preferences and pull out those that force RESTORES
    NSMutableString * restoreOptions = [NSMutableString stringWithCapacity: [preferenceKeys count] + 2];
    for (  i=0; i<[preferenceKeys count]; i++  ) {
        if (  [[preferenceValues objectAtIndex: i] intValue] == 1  ) {
            [restoreOptions appendString: [chars objectAtIndex: i]];
        }
    }
    
    // Constuct the options string we return
    NSMutableString * options = [[@"-p" mutableCopy] autorelease];
    if (  [restartOptions length] != 0  ) {
        [options appendString: [NSString stringWithFormat: @"t%@", restartOptions]];
    }
    if (  [restoreOptions length] != 0  ) {
        [options appendString: [NSString stringWithFormat: @"r%@", restoreOptions]];
    }

    return options;
}

- (NSDate *)connectedSinceDate {
    return [[connectedSinceDate retain] autorelease];
}

-(NSString *) connectTimeString
{
    // Get connection duration if preferences say to 
    if (   [gTbDefaults boolWithDefaultYesForKey:@"showConnectedDurations"]
        && ( ! [[self state] isEqualToString: @"EXITING"] )    ) {
        NSString * cTimeS = @"";
        NSDate * csd = [self connectedSinceDate];
        NSTimeInterval ti = [csd timeIntervalSinceNow];
        long cTimeL = (long) round(-ti);
        if ( cTimeL >= 0 ) {
            if ( cTimeL < 3600 ) {
                cTimeS = [NSString stringWithFormat:@" %li:%02li", cTimeL/60, cTimeL%60];
            } else {
                cTimeS = [NSString stringWithFormat:@" %li:%02li:%02li", cTimeL/3600, (cTimeL/60) % 60, cTimeL%60];
            }
        }
        return cTimeS;
    } else {
        return @"";
    }
}

- (void)setConnectedSinceDate:(NSDate *)value {
    if (connectedSinceDate != value) {
        [connectedSinceDate release];
        connectedSinceDate = [value copy];
    }
}

- (BOOL) usedModifyNameserver {
    return usedModifyNameserver;
}

-(BOOL) tryingToHookup
{
    return tryingToHookup;
}

-(BOOL) isHookedup
{
    return isHookedup;
}

-(pid_t) pid
{
    return pid;
}

- (IBAction) toggle: (id) sender
{
	if (![self isDisconnected]) {
        [self addToLog: @"Disconnecting; 'Disconnect' (toggle) menu command invoked"];
		NSString * oldRequestedState = [self requestedState];
		[self startDisconnectingUserKnows: @YES];
		if (  [oldRequestedState isEqualToString: @"EXITING"]  ) {
			[self displaySlowDisconnectionDialogLater];
		}
	} else {
        [self addToLog: @"Connecting; 'Connect' (toggle) menu command invoked"];
		[self connect: sender userKnows: YES];
	}
}

-(BOOL) openvpnAllowsDynamicChallengeRegardlessOfAuthRetrySetting {
	
	// If and when OpenVPN starts to allow this, test the OpenVPN version and return YES only if the OpenVPN version being used supports it
 
	return [gTbDefaults boolForKey: @"openvpnAllowsDynamicChallengeRegardlessOfAuthRetrySetting"];
}

-(BOOL) forceAuthRetryInteract {
	
	// We force "auth-retry interact" via the management interface if there is no 'auth-retry' in the configuration file because dynamic
	// challenge/response does not work without "auth-retry interact" and we don't know ahead of time if a dynamic challenge will be presented.
	//
	// We do this because other OpenVPN GUIs (OpenVPN GUI for Windows, and iOS and Android apps) do the same thing (or do so in effect).
	//
	// At some point OpenVPN should be fixed so dynamic challenge/response works regardless of the "auth-retry" setting, but until that
	// is done we do it in Tunnelblick by forcing "auth-retry interact".
	//
	// By doing this, Tunnelblick affects not only dynamic challenge/response, but all authentication. (That's why it should be
	// fixed in OpenVPN: so it can be limited to only specific dynamic challenge/response interactions.)
	//
	// The "openvpnAllowsDynamicChallengeRegardlessOfAuthRetrySetting" preference will allow use of experimental versions of OpenVPN that
	// include a fix, before official releases of OpenVPN that Tunnelblick can check for.
	
	return (   ( ! [self authRetryParameter]  )
			&& ( ! [self openvpnAllowsDynamicChallengeRegardlessOfAuthRetrySetting]) );
}

- (void) connectToManagementSocket
{
    TBLog(@"DB-HU", @"['%@'] connectToManagementSocket: attempting to connect to 127.0.0.1:%lu", displayName, (unsigned long)portNumber)
    discardSocketInput = FALSE;
    [self setManagementSocket: [NetSocket netsocketConnectedToHost: @"127.0.0.1" port: (unsigned short)portNumber]];
}

-(void) disconnectFromManagmentSocket
{
    if (  managementSocket  ) {
		
		// Restore status of auth-retry (only if we changed it in the first place)
		if (  [self forceAuthRetryInteract]  ) {
			if (  [self authRetryParameter]  ) {
				
				// Restore status of retry-auth
				NSString * command = [NSString stringWithFormat: @"auth-retry %@\r\n", [self authRetryParameter]];
				[managementSocket writeString: command encoding: NSUTF8StringEncoding];
				
			} else {
				
				// No auth-retry parameter, set to the default, 'none'
				[managementSocket writeString: @"auth-retry none\r\n" encoding: NSUTF8StringEncoding];
			}
		}
		
        [managementSocket close];
        [managementSocket setDelegate: nil];
        [managementSocket release];
        managementSocket = nil;
    }
}

-(void) cancelDisplayOfSlowDisconnectionDialog {
	
    if (  ! [self slowDisconnectWindowController]  ) {
        TBLog(@"DB-CD", @"Do not need to close the slow disconnection dialog for %@ because it is not being displayed", [self displayName]);
        return;
    }
    
	[[slowDisconnectWindowController window] close];
	TBLog(@"DB-CD", @"Canceled the slow disconnection dialog");
    [self setSlowDisconnectWindowController: nil];
}

-(void) displaySlowDisconnectionDialog {
	
	AlertWindowController * sdwc = [self slowDisconnectWindowController];
	
	if (  [[self state] isEqualToString: @"EXITING"]  ) {
		if (  sdwc  ) {
			[self cancelDisplayOfSlowDisconnectionDialog];
			TBLog(@"DB-CD", @"Cancelled display of slow disconnection dialog for %@ because it is disconnected", [self displayName]);
		} else {
			TBLog(@"DB-CD", @"Not displaying slow disconnection dialog for %@ because it is disconnected", [self displayName]);
		}
        return;
	}
    
    if (  sdwc  ) {
        TBLog(@"DB-CD", @"Replacing the slow disconnection dialog for %@", [self displayName]);
		[self cancelDisplayOfSlowDisconnectionDialog];
        [self setSlowDisconnectWindowController: nil];
    } else {
		TBLog(@"DB-CD", @"Displaying slow disconnection dialog for %@", [self displayName]);
	}
	
    NSString * headline = NSLocalizedString(@"OpenVPN is Not Responding", @"Window title");
	
    NSString * message = [NSString stringWithFormat:
						  NSLocalizedString(@"OpenVPN is not responding to requests to disconnect %@.\n\n"
											"Tunnelblick will disconnect when OpenVPN starts responding to disconnection requests.\n\n"
											"THIS MAY TAKE UP TO TWO MINUTES in certain unusual circumstances.\n\n"
											"The connection will be unavailable until it is disconnected.", @"Window text"),
						  [self localizedName]];
    
	sdwc = TBShowAlertWindow(headline, message);
	[self setSlowDisconnectWindowController: sdwc];
}

-(void) displaySlowDisconnectionDialogHandler {
	[self performSelectorOnMainThread: @selector(displaySlowDisconnectionDialog) withObject: nil waitUntilDone: NO];
}

-(void) displaySlowDisconnectionDialogLater {
	
    NSTimeInterval delay = (NSTimeInterval) [gTbDefaults unsignedIntForKey: @"delayBeforeSlowDisconnectDialog" default: 1 min: 0 max: 300];
    
    if (  delay != 0.0  ) {
        TBLog(@"DB-CD", @"Setting up to display slow connection dialog in %f seconds", delay);
        [self performSelector: @selector(displaySlowDisconnectionDialogHandler) withObject: nil afterDelay: delay];
    } else {
        TBLog(@"DB-CD", @"Not displaying slow connection dialog because 'delayBeforeSlowDisconnectDialog' preference is 0");
    }
}

-(void) expectDisconnect: (NSNumber *) userKnows {
	NSString * encodedPath = encodeSlashesAndPeriods([[self secureDotTblkPath] stringByAppendingPathComponent: @"Contents/Resources"]);
	if (   [userKnows boolValue]
		&& ( ! [gFileMgr fileExistsAtPath: [L_AS_T_EXPECT_DISCONNECT_FOLDER_PATH stringByAppendingPathComponent: encodedPath]] )  ) {
		runOpenvpnstart([NSArray arrayWithObjects: @"expectDisconnect", @"1", encodedPath, nil], nil, nil);
		appendLog([NSString stringWithFormat: @"Set 'expect disconnect 1 %@'", encodedPath]);
	}
}

static pthread_mutex_t areDisconnectingMutex = PTHREAD_MUTEX_INITIALIZER;

- (BOOL) startDisconnectingUserKnows: (NSNumber *) userKnows {
	
    // Start disconnecting by killing the OpenVPN process or signaling through the management interface
	
    [((MenuController *)[NSApp delegate]) cancelAllIPCheckThreadsForConnection: self];
    
    if (  [self isDisconnected]  ) {
		NSLog(@"startDisconnectingUserKnows but %@ is already disconnected. Will attempt to rety disconnection.", [self displayName]);
    }
    
    pthread_mutex_lock( &areDisconnectingMutex );
    if (  areDisconnecting  ) {
        NSLog(@"startDisconnectingUserKnows: while already disconnecting '%@'; OpenVPN state = '%@'", [self displayName], [self state]);
		if (  ! disconnectWhenStateChanges  ) {
            if (  [[self state] isEqualToString: @"RECONNECTING"]  ) {
				[self performSelector: @selector(displaySlowDisconnectionDialog) withObject: nil afterDelay: 1.0];
			}
		}
	}
    
    if (  [userKnows boolValue]  ) {
		[self setRequestedState: @"EXITING"];
    }
	
	[self setState: @"DISCONNECTING"];
	[self setConnectedSinceDate: [NSDate date]];
	
    areDisconnecting = TRUE;
    pthread_mutex_unlock( &areDisconnectingMutex );
    
	// If we are waiting for a network to become available, all we do is indicate we should stop doing that
	if (  waitingForNetworkAvailability  ) {
		[self expectDisconnect: userKnows];
		stopWaitForNetworkAvailabilityThread = TRUE;
		return YES;
	}
	
	if (  [[self state] isEqualToString: @"RECONNECTING"]  ) {
		if (  ! disconnectWhenStateChanges  ) {
			disconnectWhenStateChanges = TRUE;
			TBLog(@"DB-CD", "setting disconnectWhenStateChanges to TRUE for '%@' because state = RECONNECTING", [self displayName]);
		}
	}
	
	[self runScriptNamed: @"pre-disconnect" openvpnstartCommand: @"preDisconnect"];

	pid_t thePid = pid; // Avoid pid changing between this if statement and the invokation of waitUntilNoProcessWithID (pid can change outside of main thread)
    NSArray * connectedList = nil;
    
	NSString * connectWhenComputerStartsKey = [[self displayName] stringByAppendingString: @"-onSystemStart"];
    NSString * autoConnectKey               = [[self displayName] stringByAppendingString: @"autoConnect"];
	BOOL notConnectWhenComputerStarts       = ! (   [gTbDefaults boolForKey: connectWhenComputerStartsKey]
                                                 && [gTbDefaults boolForKey: autoConnectKey              ]);
    if (   ALLOW_OPENVPNSTART_KILL
		&& (thePid > 0)  ) {
		[self addToLog: @"Disconnecting using 'kill'"];
        TBLog(@"DB-CD", @"Disconnecting '%@' using 'kill'", [self displayName]);
		[self expectDisconnect: userKnows];
        [self killProcess];
    } else if (   ALLOW_OPENVPNSTART_KILLALL
               && (  [(connectedList = [((MenuController *)[NSApp delegate]) connectionsNotDisconnected]) count] == 1  )
               && (  [connectedList objectAtIndex: 0] == self  )
               && notConnectWhenComputerStarts  ) {
		[self addToLog: @"Disconnecting using 'killall'"];
        TBLog(@"DB-CD", @"Disconnecting '%@' using 'killall'", [self displayName]);
		[self expectDisconnect: userKnows];
		[ConfigurationManager terminateAllOpenVPNInNewThread];
        TBLog(@"DB-CD", @"Using 'killall' to disconnect %@", [self displayName])
    } else if (  [managementSocket isConnected]  ) {
		[self addToLog: @"Disconnecting using management interface"];
        TBLog(@"DB-CD", @"Disconnecting '%@' using management interface", [self displayName]);
		[self expectDisconnect: userKnows];
		[ConfigurationManager terminateOpenVPNWithManagmentSocketInNewThread: self];
    } else {
        NSLog(@"No way to disconnect '%@': pid = %lu; connectedList = %@; notConnectWhenComputerStarts = %s; [managementSocket isConnected] = %s",
              [self displayName], (unsigned long) thePid, connectedList,
              CSTRING_FROM_BOOL(notConnectWhenComputerStarts),
              CSTRING_FROM_BOOL([managementSocket isConnected]));
        return NO;
    }
    
    return YES;
}

-(BOOL) waitUntilDisconnected {
    
    if (  [self isDisconnected]  ) {
        return YES;
    }
    
    BOOL disconnectionComplete = FALSE;
    if (  pid > 0  ) {
        disconnectionComplete = [NSApp waitUntilNoProcessWithID: pid];
    }
    
    if (  disconnectionComplete  ) {
        return YES;
    }
    
    if (  ! disconnectWhenStateChanges  ) {
        if (  [[self state] isEqualToString: @"RECONNECTING"]  ) {
            [self displaySlowDisconnectionDialog];
        }
    }
    
    while (  ! disconnectionComplete  ) {
        disconnectionComplete = FALSE;
        if (  pid > 0  ) {
            disconnectionComplete = [NSApp waitUntilNoProcessWithID: pid];
        }
        
        if (  disconnectionComplete  ) {
            return YES;
        }
        
        usleep(100000);
    }
	
    return YES;
}

// Tries to kill the OpenVPN process associated with this connection, if any
-(void)killProcess 
{
	if (   ALLOW_OPENVPNSTART_KILL
        && (pid > 0)  ) {
		[ConfigurationManager terminateOpenVPNWithProcessIdInNewThread: [NSNumber numberWithLong: (long) pid]];
	} else {
        NSLog(@"killProcess invoked but ALLOW_OPENVPNSTART_KILL = %@ and pid = %lu", (ALLOW_OPENVPNSTART_KILL ? @"TRUE" : @"FALSE"), (unsigned long) pid);
        [((MenuController *)[NSApp delegate]) terminateBecause: terminatingBecauseOfError];
    }
}

-(void) reconnectAfterUnexpectedDisconnection: (NSDictionary *) dict {
    
    BOOL satisfied = [[dict objectForKey: @"satisfied"] boolValue];
    if (  satisfied  ) {
        if (  gShuttingDownTunnelblick  ) {
            TBLog(@"DB-CD", @"reconnectAfterUnexpectedDisconnection invoked indicating OpenVPN process is gone; but shutting down Tunnelblick, so not reconnecting")
        } else {
            TBLog(@"DB-CD", @"reconnectAfterUnexpectedDisconnection invoked indicating OpenVPN process is gone; reconnecting...")
            [self connect: self userKnows: YES];
        }
    } else {
        TBLog(@"DB-CD", @"reconnectAfterUnexpectedDisconnection invoked indicating OpenVPN process is still running; doing nothing because it has apparently not finished disconnecting")
    }
}

-(BOOL) openvpnProcessIsGone: (NSNumber *) pidAsNumber unusedArgument: (id) unusedArgument {
    
    // 'unusedArgument' is included because this routine is invoked by performSelector:withObject:withObject:
    (void) unusedArgument;
	
    NSArray * openvpnPids = [NSApp pIdsForOpenVPNProcessesOnlyMain: NO];
	if (  [openvpnPids containsObject: pidAsNumber]  ) {
		TBLog(@"DB-CD", @"openvpnProcessIsGone: OpenVPN process #%@ still running", pidAsNumber)
        return FALSE;
	} else {
		TBLog(@"DB-CD", @"openvpnProcessIsGone: OpenVPN process #%@ has terminated", pidAsNumber)
        return TRUE;
	}
}

static pthread_mutex_t lastStateMutex = PTHREAD_MUTEX_INITIALIZER;

-(void) hasDisconnected {
    // The 'pre-connect.sh' and 'post-tun-tap-load.sh' scripts are run by openvpnstart
    // The 'connected.sh' and 'reconnecting.sh' scripts are by this class's setState: method
    // The 'disconnect.sh' script is run here
    //
    // Call on main thread only
    //
	// avoidHasDisconnectedDeadlock is used to avoid a deadlock in hasDisconnected:
	//
	// Under some circumstances, setState, invoked by hasConnected, can invoke hasDisconnected.
	// To avoid a deadlock or infinite recursion, we ignore such "multiple" calls by returning
	// immediately if that happens. (We stop doing this immediate return after setting lastState
	// to @"EXITING"), because we can then allow multiple invokations of hasDisconnected because
	// they will return without invoking setState.)
	
    if (  ! OSAtomicCompareAndSwap32Barrier(0, 1, &avoidHasDisconnectedDeadlock)  ) {
		TBLog(@"DB-CD", @"hasDisconnected: '%@' skipped to avoid deadlock", [self displayName]);
        return;
    }
    
	TBLog(@"DB-CD", @"hasDisconnected: '%@' invoked", [self displayName]);
	
	[self cancelDisplayOfSlowDisconnectionDialog];
    
    [((MenuController *)[NSApp delegate]) cancelAllIPCheckThreadsForConnection: self];

	[((MenuController *)[NSApp delegate]) setPublicIPAddress: nil];
	
    [self clearStatisticsRatesDisplay];
    
    pthread_mutex_lock( &lastStateMutex );
    if (  [lastState isEqualToString: @"EXITING"]  ) {
        pthread_mutex_unlock( &lastStateMutex );
        avoidHasDisconnectedDeadlock = 0;
		TBLog(@"DB-CD", @"hasDisconnected: '%@' skipped because state = EXITING", [self displayName]);
        return;
    }
    [self setState:@"EXITING"];
    pthread_mutex_unlock( &lastStateMutex );
    
    avoidHasDisconnectedDeadlock = 0;
    
	NSNumber * oldPidAsNumber = [NSNumber numberWithLong: (long) pid];
	
	if (  ! wereWaitingForNetworkAvailability  ) {
		[self disconnectFromManagmentSocket];
	}
    portNumber       = 0;
    pid              = 0;
    areDisconnecting = FALSE;
    areConnecting    = FALSE;
    isHookedup       = FALSE;
    tryingToHookup   = FALSE;
	disconnectWhenStateChanges = FALSE;
    
    [((MenuController *)[NSApp delegate]) removeConnection:self];
    
    // Unload tun/tap if not used by any other processes
    if (  loadedOurTap  ) {
        [((MenuController *)[NSApp delegate]) decrementTapCount];
        loadedOurTap = FALSE;
    }
    if (  loadedOurTun  ) {
        [((MenuController *)[NSApp delegate]) decrementTunCount];
        loadedOurTun = FALSE;
    }
    [((MenuController *)[NSApp delegate]) unloadKexts];
    
	if (  ! wereWaitingForNetworkAvailability  ) {
		// Run the post-disconnect script, if any
		[self runScriptNamed: @"post-disconnect" openvpnstartCommand: @"postDisconnect"];
	}
    
	if (  ! gShuttingDownTunnelblick  ) {
		[((MenuController *)[NSApp delegate]) updateUI];
		[((MenuController *)[NSApp delegate]) updateIconImage];
		[[((MenuController *)[NSApp delegate]) logScreen] validateDetailsWindowControls];
	}
	
    if (   ( ! [requestedState isEqualToString: @"EXITING"])
        && [self haveConnectedSince]
		&& ( ! gShuttingDownTunnelblick)
        && ( gSleepWakeState == noSleepState)
        && ( gActiveInactiveState == active)
		&& [gTbDefaults boolForKey: [[self displayName] stringByAppendingString: @"-keepConnected"]]
		&& ( ! wereWaitingForNetworkAvailability )
		) {
        NSTimeInterval interval = (NSTimeInterval)[gTbDefaults unsignedIntForKey: @"timeoutForOpenvpnToTerminateAfterDisconnectBeforeAssumingItIsReconnecting"
                                                                         default: 5
                                                                             min: 0
                                                                             max: 60];
        [self addToLog: [NSString stringWithFormat: @"Unexpected disconnection. requestedState = %@; waiting up to %.1f seconds for OpenVPN process %@ to terminate...",
                         requestedState, interval, oldPidAsNumber]];
		TBLog(@"DB-CD", @"Unexpected disconnection of %@. requestedState = %@; waiting up to %.1f seconds for OpenVPN process %@ to terminate...",
			  [self displayName], requestedState, interval, oldPidAsNumber)
        
        [self performSelectorOnMainThread: @selector(reconnectAfterUnexpectedDisconnection:)
                               withObject: @""
             whenTrueIsReturnedBySelector: @selector(openvpnProcessIsGone:unusedArgument:)
                               withObject: oldPidAsNumber
                               withObject: @""
                           orAfterTimeout: interval
                                testEvery: 0.2];
        return;  // DO NOT set "completelyDisconnected"
    } else if (  ! wereWaitingForNetworkAvailability  ) {
        [self addToLog: @"Expected disconnection occurred."];
	}
	
	if (  [messagesIfConnectionFails count] != 0  ) {
		NSEnumerator * e = [messagesIfConnectionFails objectEnumerator];
		NSString * message;
		while (  (message = [e nextObject])  ) {
			TBShowAlertWindow(NSLocalizedString(@"Tunnelblick", @"Window title"), message);
		}
		[messagesIfConnectionFails removeAllObjects];
	}
	
	wereWaitingForNetworkAvailability = FALSE;
	
	if (  connectAfterDisconnect  ) {
        BOOL userKnows = connectAfterDisconnectUserKnows;
		connectAfterDisconnect = FALSE;
		NSLog(@"Connecting %@ after disconnect completed", [self displayName]);
		[self connect: self userKnows: userKnows];
    } else {
        completelyDisconnected = TRUE;
    }
}

-(void) waitUntilCompletelyDisconnected {
    
    // Cannot be called on the main thread because it will never return
    if (  [NSThread isMainThread]  ) {
        NSLog(@"waitUntilCompletelyDisconnected: on main thread");
        [((MenuController *)[NSApp delegate]) terminateBecause: terminatingBecauseOfError];
    }
    
    while (  ! completelyDisconnected  ) {
        usleep(100000); // 0.1 seconds
    }
}

-(void) sendStringToManagementSocket: (NSString *) string encoding: (NSStringEncoding) encoding {
	
	if (  ! string  ) {
		NSLog(@"sendStringToManagementSocket: invoked with string = nil; stack trace = %@", callStack());
		return;
	}
	
	NS_DURING {
		[managementSocket writeString: string  encoding: encoding];
	} NS_HANDLER {
		NSLog(@"Exception caught while writing '%@' to socket: %@", string, localException);
	}
	NS_ENDHANDLER
}

-(void) sendSigtermToManagementSocket {
	
	[self sendStringToManagementSocket: @"signal SIGTERM\r\n" encoding: NSASCIIStringEncoding];
}

- (void) netsocketConnected: (NetSocket*) socket
{

    NSParameterAssert(socket == managementSocket);
    
	if (  tryingToHookup  ) TBLog(@"DB-HU", @"['%@'] netsocketConnected: invoked ; sending commands to port %lu", displayName, (unsigned long)[managementSocket remotePort])
	
    TBLog(@"DB-ALL", @"Tunnelblick connected to management interface on port %d.", [managementSocket remotePort]);
    
    NSString * theMipName = mipName();
	if (  theMipName  ) {
		NSString * mipString = [theMipName stringByAppendingString: @"\r\n"];
		NSString * authRetryCommand = (  [self forceAuthRetryInteract]
									   ? @"auth-retry interact\r\n"
									   : nil);
		
		NS_DURING {
			[managementSocket writeString: mipString					encoding: NSASCIIStringEncoding];
			[managementSocket writeString: @"pid\r\n"					encoding: NSASCIIStringEncoding];
			if (  authRetryCommand  ) {
				[managementSocket writeString: authRetryCommand			encoding: NSASCIIStringEncoding];
		    }
			[managementSocket writeString: @"state on\r\n"      		encoding: NSASCIIStringEncoding];
			[managementSocket writeString: @"state\r\n"         		encoding: NSASCIIStringEncoding];
			[managementSocket writeString: @"bytecount 1\r\n"   		encoding: NSASCIIStringEncoding];
		} NS_HANDLER {
			NSLog(@"Exception caught while writing to socket: %@\n", localException);
		}
		NS_ENDHANDLER
	} else {
		NSLog(@"Unable to find .mip file");
	}
}

-(NSArray *) dnsServers {
	
	// Returns the list of DNS servers currently in use (from scutil).
	//
	// Returns nil if there was an error (after logging the error).
	
	NSString * stdOut = @"";
	NSString * stdErr = @"";
	
	OSStatus status = runTool(TOOL_PATH_FOR_BASH, [NSArray arrayWithObjects:
												   @"-c",
												   @"scutil --dns | grep 'server' | sed -e 's/.* : //' | sort -u", nil], &stdOut, &stdErr);
	if (  status != 0  ) {
		NSLog(@"Error: dnsServers: status = %d; stdout = '%@'\nstderr = '%@'", status, stdOut, stdErr);
		return nil;
	}
	
	NSMutableArray * servers = [[[stdOut componentsSeparatedByString: @"\n"] mutableCopy] autorelease];
	
	// The last entry will be an empty string because:
	//     * If there are no servers, componentsSeparatedByString returns an array with one empty string
	//	   * If there are servers, the output from scutil ends in a LF, causing an empty string as the last entry in the array
	// So we remove it.
	if (   ([servers count] > 0)
		&& [[servers lastObject] isEqualToString: @""]  ) {
		[servers removeObjectAtIndex: [servers count] - 1];
	}
	
	return [[servers copy] autorelease];
}

-(BOOL) isRoutedThroughVpn: (NSString *) address type: (NSString *) type {
	
	// Returns TRUE if an IP address is routed through the VPN.
	//
	// Returns FALSE if there was an error (after logging the error).
	//
	// Uses the "route get" command to get the interface used to send to the address, then returns indicating if it was the correct
	// "tap", "tun", or "utun" interface, depending on the connection type.
	//
	// address is the string representation of an IP address (e.g. 1.2.3.4 or 4:44::27)
	// type    indicates the type of VPN connection; it must start with either "tap" or "tun".
	
	NSString * stdOut;
	NSString * stdErr;
	
	OSStatus status = runTool(TOOL_PATH_FOR_BASH,
							  [NSArray arrayWithObjects:
							   @"-c",
							   [NSString stringWithFormat: @"route -n get %@ | grep '  interface: ' | sed -e 's/  interface: //'", address],
							   nil],
							  &stdOut, &stdErr);
	if (  status != 0  ) {
		NSLog(@"isRoutedThroughVpn: Error status %d; stdout = '%@'\nstderr = '%@'", status, stdOut, stdErr);
		return FALSE;
	}
	
	if (  [type hasPrefix: @"tun"]  ) {
		return (   [stdOut hasPrefix: @"tun"]
				|| [stdOut hasPrefix: @"utun"] );
	}
	
	if (  [type hasPrefix: @"tap"]  ) {
		return [stdOut hasPrefix: @"tap"];
	}
	
	NSLog(@"isRoutedThroughVpn: Called with type = '%@'; type must start with 'tun' or 'tap'", type);
	return FALSE;
}

-(BOOL) isPrivateAddress: (NSString *) address {
	
	// Returns TRUE if an IP address is either localhost or a private IP address
	//
	// Returns FALSE if there was an error (after logging the error).
	//
	// Note: The address must be a valid IPv4 or IPv6 address.
	
	if (   [address hasPrefix: @"10."]				// 10.*.*.* are private
		|| [address hasPrefix: @"127."]				// 127.*.*.* are IPv4 localhost
		|| [address hasPrefix: @"192.168"]			// 192.168.*.* are private
		|| [address isEqualToString: @"::1"]  ) {	// IPv6 localhost
		return TRUE;
	}
	
	if (  [address hasPrefix: @"172."]  ) {
		NSArray * quads = [address componentsSeparatedByString: @"."];
		if (  [quads count] == 4) {
			NSString * quad2 = [quads objectAtIndex: 1];
			return (   ([@"15" compare: quad2] == NSOrderedAscending)		// 172.16.*.* - 172.31.*.* are private
					&& ([quad2 compare: @"32"] == NSOrderedAscending) );
		} else {
			NSLog(@"isPrivateAddress: Error: address %@ is not a dotted-quad address", address);
			return FALSE;
		}
	}
	
	NSString * addressLowCase = [address lowercaseString];
	
	if (   [addressLowCase hasPrefix: @"fc"]
		|| [addressLowCase hasPrefix: @"fd"]  ) {
		return TRUE;
	}
	
	return FALSE;
}

-(void) startCheckingDnsAddresses {
	
	NSAutoreleasePool * threadPool = [NSAutoreleasePool new];
	
	NSArray * addresses = [self dnsServers];
	if (  ! addresses  ) {
		[self addToLog: @"Warning: An error occurred while trying to get a list of the DNS servers"];
		TBShowAlertWindowExtended(NSLocalizedString(@"Tunnelblick", @"Window title"),
								  NSLocalizedString(@"There was a problem getting the list of the DNS servers.", @"Window text"),
								  @"skipWarningAboutErrorGettingDnsServers",
								  nil,
								  nil,
								  NSLocalizedString(@"Do not warn about this again for any configuration", @"Checkbox name"),
								  nil,
								  NO);
		[threadPool drain];
		return;
	}
	
	NSArray * knownPublicDnsServers = [(MenuController *)[NSApp delegate] knownPublicDnsServerAddresses];
	if (  ! knownPublicDnsServers  ) {
		[self addToLog: @"Warning: An error occurred while trying to get the list of known public DNS servers"];
		TBShowAlertWindowExtended(NSLocalizedString(@"Tunnelblick", @"Window title"),
								  NSLocalizedString(@"There was a problem getting the list of known public DNS servers.", @"Window text"),
								  @"skipWarningAboutErrorGettingKnownPublicDnsServers",
								  nil,
								  nil,
								  NSLocalizedString(@"Do not warn about this again for any configuration", @"Checkbox name"),
								  nil,
								  NO);
		[threadPool drain];
		return;
	}
	
	NSMutableString * message = [[NSMutableString alloc] initWithCapacity: 1000];
	
	if (  [addresses count] == 0  ) {
		[self addToLog: @"Warning: No DNS servers have been specified."];
		[message appendString: NSLocalizedString(@"     • No DNS servers have been specified.\n\n", @"Window text")];
	} else {
		
		NSString * type = [self tapOrTun];
		
		if (   ( ! [type isEqualToString: @"Cancel"])
			&& ( [message length] == 0)  ) {
			NSString * address;
			NSEnumerator * e = [addresses objectEnumerator];
			while (  (address = [e nextObject])  ) {
				
				if (  [self isRoutedThroughVpn: address type: type]  ) {
					[self addToLog: [NSString stringWithFormat: @"DNS address %@ is being routed through the VPN", address]];
				} else {
					if (  [self isPrivateAddress: address]  ) {
						[self addToLog: [NSString stringWithFormat: @"Warning: DNS server address %@ is a private address but is not being routed through the VPN.\n\n", address]];
						[message appendString: [NSString stringWithFormat:
												NSLocalizedString(@"     • DNS server address %@ is a private address but is not being routed through the VPN.\n\n", @"Window text"), address]];
					} else {
						if (  [knownPublicDnsServers containsObject: address]  ) {
							[self addToLog: [NSString stringWithFormat: @"Warning: DNS server Address %@ is a known public DNS server but is not being routed through the VPN", address]];
							[message appendString: [NSString stringWithFormat:
													NSLocalizedString(@"     • DNS server address %@ is a public DNS server known to Tunnelblick but is not being routed through the VPN.\n\n", @"Window text"), address]];
						} else {
							[self addToLog: [NSString stringWithFormat: @"Warning: DNS server address %@ is not a public DNS server known to Tunnelblick and is not being routed through the VPN", address]];
							[message appendString: [NSString stringWithFormat:
													NSLocalizedString(@"     • DNS server address %@ is not a public DNS server known to Tunnelblick and is not being routed through the VPN.\n\n", @"Window text"), address]];
						}
					}
				}
			}
		}
	}
	
	if (  [message length] != 0  ) {
		TBShowAlertWindowExtended(NSLocalizedString(@"Tunnelblick", @"Window title"),
								  [NSString stringWithFormat:
								   NSLocalizedString(@"One or more possible problems with DNS were found: \n\n%@", @"Window text"), message],
								  @"skipWarningAboutDnsProblems",
								  nil,
								  nil,
								  NSLocalizedString(@"Do not warn about DNS problems again for any configuration", @"Checkbox name"),
								  nil,
								  NO);
	}
	
	[message release];
	[threadPool drain];
}

-(void) setPIDFromLine:(NSString *)line
{
	if([line rangeOfString: @"SUCCESS: pid="].length) {
		@try {
			NSArray* parameters = [line componentsSeparatedByString: @"="];
			if (  [parameters count] == 0  ) {
				NSLog(@"setPIDFromLine: Error parsing parameters; ignoring line '%@'; stack trace = %@", line, callStack());
				pid = 0;
				return;
			}
			NSString *pidString = [parameters lastObject];
			pid = atoi([pidString UTF8String]);			
		} @catch(NSException *exception) {
			NSLog(@"setPIDFromLine: Exception %@ occurred; setting pid to 0; line '%@'; stack trace = %@", exception, line, callStack());
			pid = 0;
		}
	}
}

-(void) setStateFromLine: (NSString *) line 
{
    @try {
        NSArray* parameters = [line componentsSeparatedByString: @","];
        if (  [parameters count] > 1  ) {
            NSString *stateString = [parameters objectAtIndex:1];
            if (  [stateString length] > 3  ) {
                NSArray * validStates = [NSArray arrayWithObjects:
                                         @"ADD_ROUTES", @"ASSIGN_IP", @"AUTH", @"CONNECTED",  @"CONNECTING",
                                         @"EXITING", @"GET_CONFIG", @"RECONNECTING", @"RESOLVE", @"SLEEP", @"TCP_CONNECT", @"UDP_CONNECT", @"WAIT", nil];
                if (  [validStates containsObject: stateString]  ) {
                    [self processState: stateString dated: [parameters objectAtIndex: 0]];
                }
            }
        }
    } @catch(NSException *exception) {
		NSLog(@"setStateFromLine: Exception %@ occurred; ignoring line '%@'; stack trace = %@", exception, line, callStack());
    }
}

-(void) processState: (NSString *) newState dated: (NSString *) dateTime
{
	if (  ! newState  ) {
		NSLog(@"processState: newState = '%@'; dateTime = '%@'; stack trace = %@", newState, dateTime, callStack());
		return;
	}
	
    if ([newState isEqualToString: @"EXITING"]) {
        discardSocketInput = TRUE;
        [((MenuController *)[NSApp delegate]) cancelAllIPCheckThreadsForConnection: self];
        [self hasDisconnected];                     // Sets lastState and does processing only once
		if (  [gFileMgr fileExistsAtPath: L_AS_T_DISABLED_NETWORK_SERVICES_PATH]  ) {
			[UIHelper showSuccessNotificationTitle: NSLocalizedString(@"Tunnelblick", @"Window title") msg: NSLocalizedString(@"Network access was disabled when a VPN disconnected.", @"Window text")];
		}
    } else {
        
        if (  disconnectWhenStateChanges  ) {
            TBLog(@"DB-CD", @"Requesting disconnect of '%@' because disconnectWhenStateChanges is TRUE", [self displayName]);
            [self startDisconnectingUserKnows: @YES];
        }
		
        if ([newState isEqualToString: @"CONNECTED"]) {
			NSDate * date = (  dateTime
							 ? [NSDate dateWithOpenvpnMachineReadableLogRepresentation: dateTime]
							 : [NSDate date]);
            [self setConnectedSinceDate: date];
            [self clearStatisticsIncludeTotals: NO];
            [gTbDefaults setBool: YES forKey: [displayName stringByAppendingString: @"-lastConnectionSucceeded"]];
            haveConnectedSince = YES;
			[NSThread detachNewThreadSelector: @selector(startCheckingDnsAddresses) toTarget: self withObject: nil];
        }
        
        [self setState: newState];
        
        if ([newState isEqualToString: @"CONNECTED"]) {
            [((MenuController *)[NSApp delegate]) addConnection:self];
            [self startCheckingIPAddressAfterConnected];
            [gTbDefaults setBool: YES forKey: [displayName stringByAppendingString: @"-lastConnectionSucceeded"]];
        } else {
            [((MenuController *)[NSApp delegate]) addNonconnection: self];
            if([newState isEqualToString: @"RECONNECTING"]) {
                [self sendStringToManagementSocket: @"hold release\r\n" encoding: NSASCIIStringEncoding];
            }
        }
    }
}

-(void) indicateWeAreHookedUp {
	
    if (   tryingToHookup
        && ( ! isHookedup )  ) {
		TBLog(@"DB-HU", @"['%@'] indicateWeAreHookedUp: setting isHookedup to TRUE and tryingToHookup to FALSE", displayName)
		isHookedup = TRUE;
		tryingToHookup = FALSE;
		[self didHookup];
		if (  [((MenuController *)[NSApp delegate]) connectionsToRestoreOnUserActive]  ) {
			BOOL stillTrying = FALSE;
			NSEnumerator * e = [[((MenuController *)[NSApp delegate]) myVPNConnectionDictionary] objectEnumerator];
			VPNConnection * connection;
			while (  (connection = [e nextObject])  ) {
				if (  [connection tryingToHookup]  ) {
					stillTrying = TRUE;
					TBLog(@"DB-HU", @"['%@'] indicateWeAreHookedUp: the '%@' configuration is still trying to hook up", displayName, [connection displayName])
					break;
				}
			}
			
			if (  stillTrying  ) {
				TBLog(@"DB-HU", @"['%@'] indicateWeAreHookedUp: one or more configurations are still trying to hook up, so NOT yet invoking app delegate's reconnectAfterBecomeActiveUser", displayName)
            } else {
				TBLog(@"DB-HU", @"['%@'] indicateWeAreHookedUp: no configurations are still trying to hook up, so invoking app delegate's reconnectAfterBecomeActiveUser", displayName)
				[((MenuController *)[NSApp delegate]) reconnectAfterBecomeActiveUser];
			}
		} else {
			TBLog(@"DB-HU", @"['%@'] indicateWeAreHookedUp: '[((MenuController *)[NSApp delegate]) connectionsToRestoreOnUserActive]' is nil", displayName)
		}
		
		logFilesMayExist = TRUE;
		[messagesIfConnectionFails removeAllObjects];

	} else if (   isHookedup
			   && ( ! tryingToHookup )  ) {
		TBLog(@"DB-HU", @"['%@'] indicateWeAreHookedUp invoked but are already hooked up (OK to see this message a few times)", displayName)
	} else {
        TBLog(@"DB-HU", @"['%@'] indicateWeAreHookedUp invoked BUT tryingToHookup = %s and isHookedUp = %s", displayName, CSTRING_FROM_BOOL(tryingToHookup), CSTRING_FROM_BOOL(isHookedup))
	}
}

-(void) processChallengeResponseErrorWithMessage: (NSDictionary *) dict {
	
	NSAutoreleasePool * threadPool = [NSAutoreleasePool new];
	
	NSString * message                     = [dict objectForKey:  @"message"];
	BOOL       showRetryWithManualResponse = [[dict objectForKey: @"showRetryWithManualResponse"] boolValue];
	
	NSString * alternateButton = (  showRetryWithManualResponse
								  ? NSLocalizedString(@"Retry with manual response", @"Button text")
								  : nil);
	
	int button = TBRunAlertPanel(NSLocalizedString(@"Tunnelblick", @"Title text"),
								 message,
								 NSLocalizedString(@"Cancel", @"Button text"), // Default button
								 alternateButton,
								 NSLocalizedString(@"Retry",  @"Button text")); // Other button

	if (   (button == NSAlertAlternateReturn)
		|| (button == NSAlertOtherReturn)  ) {
		
		[self waitUntilDisconnected];
		
		if (  button == NSAlertAlternateReturn  ) {
			useManualChallengeResponseOnce = TRUE;
			doNotClearUseManualChallengeResponseOnceOnNextConnect = TRUE;
		}
		[self connectOnMainThreadUserKnows: @YES];
	}

	[threadPool drain];
}

-(NSString *) responseFromChallengeResponseScriptAtPath: (NSString *) scriptPath arguments: (NSArray *) arguments {
	
	NSString * myStdoutString = nil;
	NSString * myStderrString = nil;
	
	OSStatus status = runTool(scriptPath, arguments, &myStdoutString, &myStderrString);

	NSString * response = nil;
	
	if (  status == 0  ) {

		response = [[myStdoutString retain] autorelease];
		
	} else if (  status == 1  ) {
		
		[self startDisconnectingUserKnows: @NO];
		
		NSString * message = [NSString stringWithFormat: NSLocalizedString(@"     From the VPN server for %@:\n\n%@", @"Window text."
																		   @" The first %@ will be replaced by the name of a configuration."
																		   @" The second %@ will be replaced by a message from a VPN server,"
																		   @" such as 'Please insert your security token'."),
							  [self localizedName], myStderrString];
		TBShowAlertWindow(NSLocalizedString(@"Tunnelblick", @"Window title"), message);
		
	} else if (   (status == 2)
			   || (status == 3)  ) {
		
		[self startDisconnectingUserKnows: @NO];
		
		NSString * message = [NSString stringWithFormat: NSLocalizedString(@"     From the VPN server for %@:\n\n%@", @"Window text."
																		   @" The first %@ will be replaced by the name of a configuration."
																		   @" The second %@ will be replaced by a message from a VPN server,"
																		   @" such as 'Please insert your security token'."),
							  [self localizedName], myStderrString];
		NSDictionary * dict = [NSDictionary dictionaryWithObjectsAndKeys:
							   message, @"message",
							   [NSNumber numberWithBool: (status == 3)], @"showRetryWithManualResponse",
							   nil];
		[NSThread detachNewThreadSelector: @selector(processChallengeResponseErrorWithMessage:) toTarget: self withObject: dict];
	
	} else {
		NSLog(@"Challenge-response script at %@ returned a status of %d. Only 0, 1, 2, or 3 should be returned", scriptPath, status);
	}
	
	return response;
}

- (NSString *) getResponseToChallenge: (NSString *) challenge
						 echoResponse: (BOOL)       echoResponse
					 responseRequired: (BOOL)       responseRequired
							 isStatic: (BOOL)       isStatic {
	
	// Gets a response to a challenge.
	//
	// If a script is available and is not being temporarily overridden, invoke the script and return its output as the response
	//
	// Otherwise get the response from the user:
	//		If responseRequired is TRUE
	//			'challenge' is displayed with an OK button and a Cancel button in a modal window
	//			Control is returned when the user clicks OK or Cancel
	//			If the user clicks Cancel or an error occurs, nil is returned, otherwise the response is returned (it could be an empty string)
	//		Else
	//			if not nil and not an empty string, 'challenge' is displayed with an OK button in a non-modal window
	//			an empty string is returned immediately
	
	// Use a script to get the response if one is available
	if (  ! useManualChallengeResponseOnce ) {
		if (  [[configPath pathExtension] isEqualToString: @"tblk"]) {
			NSString * scriptFilename = (  isStatic
										 ? @"static-challenge-response.user.sh"
										 : @"dynamic-challenge-response.user.sh");
			NSString * scriptPath = [[[configPath stringByAppendingPathComponent: @"Contents"]
									  stringByAppendingPathComponent: @"Resources"]
									 stringByAppendingPathComponent: scriptFilename];
			if (  [gFileMgr fileExistsAtPath: scriptPath]  ) {
				
				NSArray * arguments = [NSArray arrayWithObjects: challenge,
									   [self displayName],
									   [self localizedName],
									   (echoResponse ? @"echo" : @"noecho"),
									   nil];
				NSString * response = [self responseFromChallengeResponseScriptAtPath: scriptPath arguments: arguments];
				if (  response  ) {
					[self addToLog: [NSString stringWithFormat: @"Received response to challenge from %@", scriptFilename]];
				} else {
					[self addToLog: [NSString stringWithFormat: @"User cancelled the response to challenge from %@", scriptFilename]];
				}
				
				return response;
			}
		}
	} else {
		useManualChallengeResponseOnce = FALSE;
	}
	
	// Otherwise, query the user
	if (  [challenge length] == 0  ) {
		if (  ! responseRequired  ) {
			[self addToLog: @"An empty challenge message is not being shown to the user because no response is required"];
			return @"";
		}
		
		challenge = NSLocalizedString(@"This VPN requires you to respond to a question but has not provided the question.", @"Window text");
	}

	// Prefix the challenge with a message containing the VPN name
	challenge = [NSString stringWithFormat: NSLocalizedString(@"     From the VPN server for %@:\n\n%@", @"Window text."
															  @" The first %@ will be replaced by the name of a configuration."
															  @" The second %@ will be replaced by a message from a VPN server,"
															  @" such as 'Please insert your security token'."),
						  [self localizedName], challenge];
	
	if (  ! responseRequired  ) {
		TBShowAlertWindow(NSLocalizedString(@"Tunnelblick", @"Window title"), challenge);
		return @"";
	}
	
	NSAlert * alert = [NSAlert alertWithMessageText: NSLocalizedString(@"Tunnelblick", @"Window title")
									  defaultButton: NSLocalizedString(@"OK",     @"Button")
									alternateButton: NSLocalizedString(@"Cancel", @"Button")
										otherButton: nil
						  informativeTextWithFormat: @"%@", challenge];
	id input = (  echoResponse
				? [[[NSTextField       alloc] initWithFrame:NSMakeRect(0, 0, 200, 24)] autorelease]
				: [[[NSSecureTextField alloc] initWithFrame:NSMakeRect(0, 0, 200, 24)] autorelease]);
	[alert setAccessoryView: input];
	[[alert window] setInitialFirstResponder: input];
	[NSApp activateIgnoringOtherApps: YES];
	
	NSModalResponse buttonValue = [alert runModal];
	
	if (  buttonValue == NSAlertDefaultReturn  ) {
		[input validateEditing];
		return [input stringValue];
	} else if (  buttonValue != NSAlertAlternateReturn  ) {
		NSLog(@"getResponseToChallenge: Invalid input dialog button return value %ld for %@", (long)buttonValue, [self displayName]);
	}
	
	return nil;
}

-(void) parseAndSaveDynamicChallengeResponseInfo: (NSString *) line {
	
	if (   (   [[self authRetryParameter] isEqualToString: @"none"]
			|| [[self authRetryParameter] isEqualToString: @"nointeract"] )
		&& ( ! [self openvpnAllowsDynamicChallengeRegardlessOfAuthRetrySetting])  ) {
		[self addToLog: @"Error: Disconnecting because the OpenVPN server requires a response to a dynamic challenge and the OpenVPN configuration file contains 'auth-retry none' or 'auth-retry nointeract'. The selected version of OpenVPN does not support that."];
		[self startDisconnectingUserKnows: @NO];
		return;
	}
	
	NSArray * parts = [line componentsSeparatedByString: @":"];
	if (  [parts count] > 6 ) {
		
		NSString * pwPart      = [parts objectAtIndex: 0]; // Must be ">PASSWORD"
		NSString * vfPart      = [parts objectAtIndex: 1]; // Must be "Verification Failed"
		NSString * acPart      = [parts objectAtIndex: 2]; // Must be " 'Auth' ['CRV1"
		NSString * flags       = [parts objectAtIndex: 3];
		NSString * state       = [parts objectAtIndex: 4];
		
		if (   ( ! [pwPart isEqualToString: @">PASSWORD"] )
			|| ( ! [vfPart isEqualToString: @"Verification Failed"] )
			|| ( ! [acPart isEqualToString: @" 'Auth' ['CRV1"] )  ) {
			[self addToLog: [NSString stringWithFormat: @"Disconnecting: dynamic challange request did not start with '>PASSWORD:Verification Failed: 'Auth' ['CRV1:': '%@'", line]];
			[self startDisconnectingUserKnows: @NO];
			return;
		}
		
		// The username is base-64-encoded. We need to decode it and treat it as UTF-8 text.
		NSString * usernameBase64 = [parts objectAtIndex: 5];
		NSData * usernameAsData = base64Decode(usernameBase64);
		if (  ! usernameAsData  ) {
			[self addToLog: [NSString stringWithFormat: @"Disconnecting: in dynamic challenge/response request, could not decode base 64 string with username '%@'", usernameBase64]];
			[self startDisconnectingUserKnows: @NO];
			return;
		}
		NSString * username  = [[[NSString alloc] initWithData: usernameAsData encoding: NSUTF8StringEncoding] autorelease];
		if (  ! username  ) {
			[self addToLog: [NSString stringWithFormat: @"Disconnecting: in dynamic challenge/response request, could not decode UTF-8 with username (Base 64 of username is '%@')", usernameBase64]];
			[self startDisconnectingUserKnows: @NO];
			return;
		}
		
		// Handle colons in the challenge properly. Create the prompt by concatenating the parts entries starting at the
		// seventh one, separating them by a ":".
		NSString * prompt = [parts objectAtIndex: 6];
		NSUInteger i;
		for (  i=7; i<[parts count]; i++) {
			prompt = [prompt stringByAppendingFormat: @":%@", [parts objectAtIndex: i]];
		}
		
		// Strip the trailing "']" from the challenge
		if (  ! [prompt hasSuffix: @"']"]  ) {
			[self addToLog: [NSString stringWithFormat: @"Disconnecting: dynamic challenge/response request does not end with \"']\": '%@'", line]];
			[self startDisconnectingUserKnows: @NO];
			return;
		}
		prompt = [prompt substringToIndex: [prompt length] - 2];
		
		// Save the info for later use
		[self setDynamicChallengeUsername: username];
		[self setDynamicChallengeState:    state];
		[self setDynamicChallengePrompt:   prompt];
		[self setDynamicChallengeFlags:    flags];
		
		[self addToLog: [NSString stringWithFormat: @"Saved dynamic challenge info for user %@ with flags '%@', state '%@', and prompt '%@'", username, flags, state, prompt]];
	} else {
		[self addToLog: [NSString stringWithFormat: @"Disconnecting: dynamic challange request did not have at least six colons: '%@'", line]];
		[self startDisconnectingUserKnows: @NO];
	}
	
	return;
}

- (void) processLine: (NSString*) line
{
    if (  discardSocketInput  ) {
        return;
    }
    
    if (  tryingToHookup  ) {
        TBLog(@"DB-HU", @"['%@'] invoked processLine:; isHookedUp = %s; line = '%@'", displayName, CSTRING_FROM_BOOL(isHookedup), line)
		[self indicateWeAreHookedUp];
    } else {
		TBLog(@"DB-AU", @"['%@'] invoked processLine:; line = '%@'", displayName, line)
	}

    
    if (  ! [line hasPrefix: @">"]  ) {
        // Output in response to command to OpenVPN
		[self setPIDFromLine:line];
        [self setStateFromLine:line];
		return;
	}

    // "Real time" output from OpenVPN.
	if (   [line isEqualToString: @">FATAL:Error: private key password verification failed"]
		|| [line rangeOfString: @"RECONNECTING,private-key-password-failure"].length) {
		// Private key verification failed. Rewrite the message to be similar to the regular password failed message so we can use the same code
		line = @">PASSPHRASE:Verification Failed";
		TBLog(@"DB-AU", @"Rewriting private key password verification failed message to be '>PASSPHRASE:Verification Failed' for '%@'", [self localizedName]);
	}
	
	if (  [line hasPrefix: @">HOLD:Waiting for hold release"]  ) {
		[self sendStringToManagementSocket: @"hold release\r\n" encoding: NSASCIIStringEncoding];
		return;
	}
	
     NSRange separatorRange = [line rangeOfString: @":"];
    if (separatorRange.length) {
        NSRange commandRange = NSMakeRange(1, separatorRange.location-1);
        NSString* command = [line substringWithRange: commandRange];
        NSString* parameterString = [line substringFromIndex: separatorRange.location+1];
        TBLog(@"DB-ALL", @"Found command '%@' with parameters: %@", command, parameterString);
        
        if ([command isEqualToString: @"STATE"]) {
            NSArray* parameters = [parameterString componentsSeparatedByString: @","];
			if (  [parameters count] < 2  ) {
				NSLog(@"processLine: Error parsing parameters; ignoring line '%@'; stack trace = %@", line, callStack());
				return;
			}
            NSString* state = [parameters objectAtIndex: 1];
            [self processState: state dated: nil];
            
        } else if (   [command isEqualToString: @"PASSWORD"]
				   || [command isEqualToString: @"PASSPHRASE"]  ) {
			TBLog(@"DB-AU", @"processLine: %@ command received; line = '%@'", command, line);
            if (   [line rangeOfString: @"Failed"].length
                || [line rangeOfString: @"failed"].length  ) {
                
				if (  [line hasPrefix: @">PASSWORD:Verification Failed: 'Auth' ['CRV1:"]  ) {

					// Do not process this as an actual auth failure. OpenVPN deals with the failure by restarting the connection and we
					// will use the info saved from this request in the reconnection.
					
					[self parseAndSaveDynamicChallengeResponseInfo: line];
					return;
				}
				
				TBLog(@"DB-AU", @"processLine: Failed: %@", line);
                
                // Set the "private message" sent by the server (if there is one)
                NSString * privateMessage = @"";
                NSRange rngQuote = [line rangeOfString: @"'"];
                if (  rngQuote.length != 0  ) {
                    NSString * afterQuoteMark = [line substringFromIndex: rngQuote.location + 1];
                    rngQuote = [afterQuoteMark rangeOfString: @"'"];
                    if (  rngQuote.length != 0) {
                        NSString * failedMessage = [afterQuoteMark substringToIndex: rngQuote.location];
                        if (   [failedMessage isNotEqualTo: @"Private Key"]
                            && [failedMessage isNotEqualTo: @"Auth"]  ) {
                            privateMessage = [NSString stringWithFormat: @"\n\n%@", failedMessage];
                        }
                    }
                }
                
                authFailed = TRUE;
                userWantsState = userWantsUndecided;
                credentialsAskedFor = FALSE;
                
                BOOL isPassphraseCommand = [command isEqualToString: @"PASSPHRASE"];
                
                NSString * message;
                if (  isPassphraseCommand  ) {
                    message = [NSString stringWithFormat:@"%@%@", NSLocalizedString(@"The passphrase was not accepted.", @"Window text"), privateMessage];
                } else {
                    message = [NSString stringWithFormat:@"%@%@", NSLocalizedString(@"The username and password were not accepted by the remote VPN server.", @"Window text"), privateMessage];
                }
                NSString * deleteAndTryAgainButton = nil;
                NSString * tryAgainButton = NSLocalizedString(@"Try again", @"Button");;
                if (  [myAuthAgent authMode]  ) {               // Handle "auto-login" --  we were never asked for credentials, so authMode was never set
                    if (  isPassphraseCommand  ) {
                        if (  [myAuthAgent keychainHasPassphrase]  ) {
                            deleteAndTryAgainButton = NSLocalizedString(@"Delete saved passphrase and try again", @"Button");
                            tryAgainButton = NSLocalizedString(@"Try again with saved passphrase", @"Button");
                        }
                    } else {
                        if (  [myAuthAgent keychainHasUsernameAndPassword]  ) {
                            deleteAndTryAgainButton = NSLocalizedString(@"Delete saved password and try again", @"Button");
                            tryAgainButton = NSLocalizedString(@"Try again with saved username and password", @"Button");
                        }
                    }
                }
                int alertVal = TBRunAlertPanel([NSString stringWithFormat:@"%@: %@", [self localizedName], NSLocalizedString(@"Authentication failed", @"Window title")],
                                               message,
                                               tryAgainButton,							 // Default
                                               deleteAndTryAgainButton,                  // Alternate
                                               NSLocalizedString(@"Cancel", @"Button")); // Other
                if (alertVal == NSAlertDefaultReturn) {
                    userWantsState = userWantsRetry;                // User wants to retry
                    
                } else if (alertVal == NSAlertAlternateReturn) {
                    if (  isPassphraseCommand  ) {
                        [myAuthAgent deletePassphrase];
                    } else {
                        [myAuthAgent deletePassword];
                    }
                    userWantsState = userWantsRetry;
                } else {
                    userWantsState = userWantsAbandon;              // User wants to cancel or an error happened, so disconnect
                    [self addToLog: @"Disconnecting; user cancelled authorization or there was an error obtaining authorization"];
                    [self startDisconnectingUserKnows: @YES];      // (User requested it by cancelling)
                }
                
				TBLog(@"DB-AU", @"processLine: queuing afterFailureHandler: for execution in 0.5 seconds");
                NSTimer * timer = [NSTimer scheduledTimerWithTimeInterval: (NSTimeInterval) 0.5   // Wait for time to process new credentials request or disconnect
                                                                   target: self
                                                                 selector: @selector(afterFailureHandler:)
                                                                 userInfo: [NSDictionary dictionaryWithObjectsAndKeys:
                                                                            parameterString, @"parameterString",
                                                                            line, @"line", nil]
                                                                  repeats: NO];
                [timer tbSetTolerance: -1.0];
            } else {
				TBLog(@"DB-AU", @"processLine: PASSWORD request from server");
                if ([parameterString hasPrefix:@"Auth-Token:"]) {
                    TBLog(@"DB-AU", @"processLine: Ignoring Auth-Token from server");
                } else if (  authFailed  ) {
                    if (  userWantsState == userWantsUndecided  ) {
                        // We don't know what to do yet: repeat this again later
						TBLog(@"DB-AU", @"processLine: authFailed and userWantsUndecided, queuing credentialsHaveBeenAskedForHandler for execution in 0.5 seconds");
                        credentialsAskedFor = TRUE;
                        NSTimer * timer = [NSTimer scheduledTimerWithTimeInterval: (NSTimeInterval) 0.5   // Wait for user to make decision
                                                                           target: self
                                                                         selector: @selector(credentialsHaveBeenAskedForHandler:)
                                                                         userInfo: [NSDictionary dictionaryWithObjectsAndKeys:
                                                                                    parameterString, @"parameterString",
                                                                                    line, @"line", nil]
                                                                          repeats: NO];
                        [timer tbSetTolerance: -1.0];
                    } else if (  userWantsState == userWantsRetry  ) {
                        // User wants to retry; send the credentials
						TBLog(@"DB-AU", @"processLine: authFailed and userWantsRetry, so requesting credentials again");
                        [self provideCredentials: parameterString line: line];
                    } // else user wants to abandon, so just ignore the request for credentials
					TBLog(@"DB-AU", @"processLine: authFailed and user wants to abandon, so ignoring the request");
                } else {
					TBLog(@"DB-AU", @"processLine: auth succeeded so requesting credentials");
                    [self provideCredentials: parameterString line: line];
                }
            }
            
        } else if ([command isEqualToString:@"NEED-OK"]) {
            // NEED-OK: MSG:Please insert TOKEN
            if ([line rangeOfString: @"Need 'token-insertion-request' confirmation"].length) {
               TBLog(@"DB-AU", @"Server wants token.");
                NSRange tokenNameRange = [parameterString rangeOfString: @"MSG:"];
                NSString* tokenName = [parameterString substringFromIndex: tokenNameRange.location+4];
                int needButtonReturn = TBRunAlertPanel([NSString stringWithFormat:@"%@: %@",
                                                        [self localizedName],
                                                        NSLocalizedString(@"Please insert token", @"Window title")],
                                                       [NSString stringWithFormat:NSLocalizedString(@"Please insert token \"%@\", then click \"OK\"", @"Window text"), tokenName],
                                                       nil,
                                                       NSLocalizedString(@"Cancel", @"Button"),
                                                       nil);
                if (needButtonReturn == NSAlertDefaultReturn) {
                    TBLog(@"DB-AU", @"Write need ok.");
                    [self sendStringToManagementSocket: @"needok token-insertion-request ok\r\n" encoding: NSASCIIStringEncoding];
                } else {
                    TBLog(@"DB-AU", @"Write need cancel.");
                    [self sendStringToManagementSocket: @"needok token-insertion-request cancel\r\n" encoding: NSASCIIStringEncoding];
                }
            }
		} else if ([command isEqualToString:@"INFO"]) {
			[self addToLog: line];
		} else {
			TBLog(@"DB-AU", @"Ignored unrecognized message from management interface for %@: %@", [self displayName], line);
        }
    }
}

-(void) afterFailureHandler: (NSTimer *) timer
{
	TBLog(@"DB-AU", @"processLine: afterFailureHandler: invoked");

    if (  gShuttingDownOrRestartingComputer  ) {
        return;
    }
    
	[self performSelectorOnMainThread: @selector(afterFailure:) withObject: [timer userInfo] waitUntilDone: NO];
}

-(void) afterFailure: (NSDictionary *) dict
{
	TBLog(@"DB-AU", @"processLine: afterFailure: invoked");

    if (   credentialsAskedFor  ) {
        [self credentialsHaveBeenAskedFor: dict];
    } else {
        if (  [self isDisconnected]  ) {
            if (  userWantsState == userWantsRetry  ) {
                [self connect: self userKnows: YES];
            } else if (  userWantsState == userWantsAbandon  ) {
                authFailed = FALSE;                 // (Don't retry)
                credentialsAskedFor = FALSE;
                userWantsState = userWantsUndecided;
            } else {
                // credentialsHaveBeenAskedFor has handled things
            }
        } else {
            // Wait until either credentials have been asked for or tunnel is disconnected
            NSTimer * timer = [NSTimer scheduledTimerWithTimeInterval: (NSTimeInterval) 0.5   // Wait for time to process new credentials request or disconnect
                                                               target: self
                                                             selector: @selector(afterFailureHandler:)
                                                             userInfo: dict
                                                              repeats: NO];
            [timer tbSetTolerance: -1.0];
        }
    }
}

-(void) credentialsHaveBeenAskedForHandler: (NSTimer *) timer
{
    if (  gShuttingDownOrRestartingComputer  ) {
        return;
    }
    
    [self performSelectorOnMainThread: @selector(credentialsHaveBeenAskedFor:) withObject: [timer userInfo] waitUntilDone: NO];
}

-(void) credentialsHaveBeenAskedFor: (NSDictionary *) dict
{
	TBLog(@"DB-AU", @"processLine: credentialsHaveBeenAskedFor: invoked");
	
    // Only do something if the credentials are still being asked for
    // Otherwise, afterFailure has already taken care of things and we can just forget about it
    if (  credentialsAskedFor  ) {
        if (  [self isDisconnected]  ) {
            if (  userWantsState == userWantsRetry) {
                NSLog(@"Warning: User asked to retry and OpenVPN asked for credentials but OpenVPN has already disconnected; reconnecting %@", displayName);
                [self connect: self userKnows: YES];
                
            } else if (  userWantsState == userWantsAbandon  ) {
                NSLog(@"Warning: User asked to abandon connection and OpenVPN has already disconnected; ignoring OpenVPN request for credentials for %@", displayName);
                authFailed = FALSE;
                credentialsAskedFor = FALSE;
                userWantsState = userWantsUndecided;
                
            } else {
                // OpenVPN asked for credentials, then disconnected, but user hasn't decided what to do -- wait for user to decide what to do
                NSTimer * timer = [NSTimer scheduledTimerWithTimeInterval: (NSTimeInterval) 0.5   // Wait for time to process new credentials request or disconnect
                                                                   target: self
                                                                 selector: @selector(afterFailureHandler:)
                                                                 userInfo: dict
                                                                  repeats: NO];
                [timer tbSetTolerance: -1.0];
            }
        } else {
            if (  userWantsState == userWantsRetry) {
                [self provideCredentials: [dict objectForKey: @"parameterString"] line: [dict objectForKey: @"line"]];
                
            } else if (  userWantsState == userWantsAbandon  ) {
                authFailed = FALSE;
                credentialsAskedFor = FALSE;
                userWantsState = userWantsUndecided;
                
            } else {
                // OpenVPN asked for credentials, but user hasn't decided what to do -- wait for user to decide what to do
                NSTimer * timer = [NSTimer scheduledTimerWithTimeInterval: (NSTimeInterval) 0.5   // Wait for time to process new credentials request or disconnect
                                                                   target: self
                                                                 selector: @selector(afterFailureHandler:)
                                                                 userInfo: dict
                                                                  repeats: NO];
                [timer tbSetTolerance: -1.0];
            }
        }
    }
}

-(void) processDynamicChallengeResponse {
	
	// Display dynamic challenge and send user's response to management interface
	
	BOOL echoResponse     = [dynamicChallengeFlags rangeOfString: @"E"].length != 0;
	BOOL responseRequired = [dynamicChallengeFlags rangeOfString: @"R"].length != 0;
	NSString * response   = [self getResponseToChallenge: dynamicChallengePrompt
											  echoResponse: echoResponse
										  responseRequired: responseRequired
												  isStatic: NO];
	
	if (  response  ) {
		[self addToLog: (  responseRequired
						 ? @"User responded to dynamic challenge"
						 : @"Displayed dynamic challenge to user; no response is required so an empty response is being returned")];
		NSString * msg = [NSString stringWithFormat:@"username \"Auth\" \"%@\"\r\n", escaped(dynamicChallengeUsername)];
		[self sendStringToManagementSocket: msg encoding: NSUTF8StringEncoding];
		msg = [NSString stringWithFormat:@"password \"Auth\" \"CRV1::%@::%@\"\r\n", escaped(dynamicChallengeState), escaped(response)];
		[self sendStringToManagementSocket: msg encoding: NSUTF8StringEncoding];
	} else {
		[self addToLog: @"Disconnecting: An error occurred or the user cancelled when presented with dynamic challenge"];
		[self startDisconnectingUserKnows: @YES];      // (User requested it by cancelling)
	}
	
	[self setDynamicChallengeUsername: nil];
	[self setDynamicChallengeState:    nil];
	[self setDynamicChallengePrompt:   nil];
	[self setDynamicChallengeFlags:    nil];
}

-(void) provideCredentials: (NSString *) parameterString line: (NSString *) line
{
	TBLog(@"DB-AU", @"processLine: provideCredentials: invoked");
	
	if (  areDisconnecting  ) {
		[self addToLog: @"Ignoring credentials request because the VPN is disconnecting"];
		return;
	}
	
	authFailed = FALSE;
    credentialsAskedFor = FALSE;
    userWantsState = userWantsUndecided;

    BOOL echoResponse = FALSE;
    NSString * staticChallengePrompt = nil;

    if (   [line rangeOfString: @" SC:0,"].length
        || [line rangeOfString: @" SC:1,"].length  ) {
        TBLog(@"DB-AU", @"processLine: Server asking for Static Challenge");

        NSRange rngStartChallenge = [line rangeOfString: @" SC:"];
 
        NSString * afterStartChallenge = [line substringFromIndex: rngStartChallenge.location + rngStartChallenge.length];
        NSString * echoResponseStr = [afterStartChallenge substringToIndex: 1]; // take "0" or "1"
        echoResponse = [echoResponseStr isEqualToString:@"1"];
		staticChallengePrompt = [afterStartChallenge substringFromIndex: 2]; // drop "0," or "1,"
     }

    // Find out whether the server wants a private key or user/auth:
    NSRange pwrange_need = [parameterString rangeOfString: @"Need \'"];
    NSRange pwrange_password = [parameterString rangeOfString: @"\' password"];
    if (pwrange_need.length && pwrange_password.length) {
        TBLog(@"DB-AU", @"Server wants user private key.");
		if (  ![self isConnected]  ) {
			[self setState: @"PRIVATE_KEY_WAIT"];
		}
        [myAuthAgent setAuthMode:@"privateKey"];
        [myAuthAgent performAuthentication];
        if (  [myAuthAgent authenticationWasFromKeychain]  ) {
            [self addToLog: @"Obtained passphrase from the Keychain"];
        }
        NSString *myPassphrase = [myAuthAgent passphrase];
        NSRange tokenNameRange = NSMakeRange(pwrange_need.length, pwrange_password.location - 6 );
        NSString* tokenName = [parameterString substringWithRange: tokenNameRange];
        TBLog(@"DB-AU", @"tokenName is '%@'", tokenName);
        if(  myPassphrase != nil  ){
            const char * tokenNameC  = [escaped(tokenName)    UTF8String];
            const char * passphraseC = [escaped(myPassphrase) UTF8String];
             if (  ( strlen(tokenNameC)  > MAX_LENGTH_OF_QUOTED_MANGEMENT_INTERFACE_PARAMETER )
                || ( strlen(passphraseC) > MAX_LENGTH_OF_QUOTED_MANGEMENT_INTERFACE_PARAMETER )  ) {
                [self addToLog: [NSString stringWithFormat: @"Disconnecting; token name is %ld bytes long; passphrase is %ld bytes long; each is limited to %ld bytes", (long)strlen(tokenNameC), (long)strlen(passphraseC), (long)MAX_LENGTH_OF_QUOTED_MANGEMENT_INTERFACE_PARAMETER]];
                [self startDisconnectingUserKnows: @NO];
            } else {
                [self sendStringToManagementSocket: [NSString stringWithFormat: @"password \"%@\" \"%@\"\r\n", escaped(tokenName), escaped(myPassphrase)] encoding:NSUTF8StringEncoding];
            }
        } else {
            [self addToLog: @"Disconnecting; user cancelled authorization"];
            [self startDisconnectingUserKnows: @YES];      // (User requested it by cancelling)
        }
        
    } else if ([line rangeOfString: @"Auth"].length) {
        TBLog(@"DB-AU", @"Server wants user auth/pass.");
		if (  ![self isConnected]  ) {
			[self setState: @"PASSWORD_WAIT"];
		}
		
		if (   [self dynamicChallengeUsername]
			&& ( ! staticChallengePrompt )  ) {
		
			[self processDynamicChallengeResponse];
			return;
		}
	
        [myAuthAgent setAuthMode:@"password"];
        [myAuthAgent performAuthentication];
        if (  [myAuthAgent authenticationWasFromKeychain]  ) {
            [self addToLog: @"Obtained VPN username and password from the Keychain"];
        }
        NSString *myPassword = [myAuthAgent password];
        NSString *myUsername = [myAuthAgent username];
        if(   (myUsername != nil)
           && (myPassword != nil)  ){
            const char * usernameC  = [escaped(myUsername) UTF8String];
            const char * passwordC  = [escaped(myPassword) UTF8String];
            if (   ( strlen(usernameC) > MAX_LENGTH_OF_QUOTED_MANGEMENT_INTERFACE_PARAMETER )
                || ( strlen(passwordC) > MAX_LENGTH_OF_QUOTED_MANGEMENT_INTERFACE_PARAMETER )  ) {
                [self addToLog: [NSString stringWithFormat: @"Disconnecting; username is %ld bytes long; password is %ld bytes long; each is limited to %ld bytes", (long)strlen(usernameC), (long)strlen(passwordC), (long)MAX_LENGTH_OF_QUOTED_MANGEMENT_INTERFACE_PARAMETER]];
                [self startDisconnectingUserKnows: @NO];
            } else {
                NSString * response = nil;
                if (  staticChallengePrompt  ) {
                    response = [self getResponseToChallenge: staticChallengePrompt
												 echoResponse: echoResponse
											 responseRequired: YES
													 isStatic: YES];
					if (  response  ) {
						[self addToLog: [NSString stringWithFormat: @"User responded to static challenge: '%@'", staticChallengePrompt]];
					} else {
						[self addToLog: [NSString stringWithFormat: @"Disconnecting: User cancelled when presented with static challenge: '%@'", staticChallengePrompt]];
						[self startDisconnectingUserKnows: @YES];      // (User requested it by cancelling)
					}
                }
                [self sendStringToManagementSocket:[NSString stringWithFormat:@"username \"Auth\" \"%@\"\r\n", escaped(myUsername)] encoding:NSUTF8StringEncoding];
                if (  response  ) {
					[self sendStringToManagementSocket: [NSString stringWithFormat:@"password \"Auth\" \"SCRV1:%@:%@\"\r\n",
														 base64Encode([myPassword dataUsingEncoding: NSUTF8StringEncoding]),
														 base64Encode([response   dataUsingEncoding: NSUTF8StringEncoding])]
											  encoding: NSASCIIStringEncoding];
                } else {
                    [self sendStringToManagementSocket:[NSString stringWithFormat:@"password \"Auth\" \"%@\"\r\n", escaped(myPassword)] encoding:NSUTF8StringEncoding];
                }
            }
        } else {
            [self addToLog: @"Disconnecting; user cancelled authorization"];
            [self startDisconnectingUserKnows: @YES];      // (User requested it by cancelling)
        }
        
    } else {
        NSLog(@"Unrecognized PASSWORD command from OpenVPN management interface has been ignored:\n%@", line);
    }
}

// Returns an empty string, " (Private)", " (Shared)", or " (Deployed)" if there are configurations in more than one location
-(NSString *) displayLocation
{
    NSString * locationMessage = @"";
    unsigned havePrivate  = 0;
    unsigned haveShared   = 0;
    unsigned haveDeployed = 0;
    NSString * path;
    NSEnumerator * configEnum = [[((MenuController *)[NSApp delegate]) myConfigDictionary] objectEnumerator];
    while (   ( path = [configEnum nextObject] )
           && ( (havePrivate + haveShared + haveDeployed) < 2) ) {
        if (  [path hasPrefix: [gPrivatePath stringByAppendingString: @"/"]]  ) {
            havePrivate = 1;
        } else if (  [path hasPrefix: [L_AS_T_SHARED stringByAppendingString: @"/"]]  ) {
            haveShared = 1;
        } else {
            haveDeployed =1;
        }
    }
    
    if (  (havePrivate + haveShared + haveDeployed) > 1  ) {
        path = [self configPath];
        if (  [path hasPrefix: [gDeployPath stringByAppendingString: @"/"]]) {
            locationMessage =  NSLocalizedString(@" (Deployed)", @"Window title");
        } else if (  [path hasPrefix: [L_AS_T_SHARED stringByAppendingString: @"/"]]) {
            locationMessage =  NSLocalizedString(@" (Shared)", @"Window title");
        } else {
            locationMessage =  NSLocalizedString(@" (Private)", @"Window title");
        }
    }
    
    return locationMessage;
}

// Adds a message to the log display with the current date/time
-(void)addToLog:(NSString *)text
{
	if (  [NSThread isMainThread]  ) {
		[logDisplay addToLog: [TB_LOG_PREFIX stringByAppendingString: text]];
	} else {
		[logDisplay performSelectorOnMainThread: @selector(addToLog:)
									 withObject: [TB_LOG_PREFIX stringByAppendingString: text]
								  waitUntilDone: NO];
	}
}

// Clears the log
-(void) clearLog
{
    [logDisplay clear];
}

- (void) netsocket: (NetSocket*) socket dataAvailable: (unsigned) inAmount
{
    (void) inAmount;
    
    NSParameterAssert(socket == managementSocket);
    NSString* line;
    
    if (  tryingToHookup  ) {
		TBLog(@"DB-HU", @"['%@'] entered netsocket:dataAvailable: %lu; queueing indicateWeAreHookedUp", displayName, (unsigned long)inAmount)
		[self performSelectorOnMainThread: @selector(indicateWeAreHookedUp) withObject: nil waitUntilDone: NO];
	}

    while ((line = [socket readLine])) {
        // Can we get blocked here?
        //NSLog(@">>> %@", line);
        if (  [line length]  ) {
            NSString * bcClientPrefix = @">BYTECOUNT:";
            NSString * bcServerPrefix = @">BYTECOUNT_CLI:";
            if (  [line hasPrefix: bcClientPrefix]  ) {
                if (   bytecountMutexOK  ) {
                    NSRange commaRange = [line rangeOfString: @","];
                    if (  commaRange.location != NSNotFound  ) {
                        if (  commaRange.location < [line length]  ) {
							NSRange inCountRange;
                            @try {
                                
                                NSDate * currentTime = [NSDate date];
                                unsigned long bcpl = [bcClientPrefix length];
                                inCountRange = NSMakeRange(bcpl, commaRange.location - bcpl);
                                
                                TBByteCount inCount  = (TBByteCount) [[line substringWithRange: inCountRange]            doubleValue];
                                TBByteCount outCount = (TBByteCount) [[line substringFromIndex: commaRange.location + 1] doubleValue];
                                OSStatus status = pthread_mutex_lock( &bytecountMutex );
                                if (  status != EXIT_SUCCESS  ) {
                                    NSLog(@"VPNConnection:netsocket:dataAvailable: pthread_mutex_lock( &bytecountMutex ) failed; status = %ld", (long) status);
                                    return;
                                }
                                
                                [statistics.lastSet release];
                                statistics.lastSet = [currentTime retain];
                                
                                if (  statistics.totalInBytecount > inCount  ) {
                                    statistics.totalInByteCountBeforeThisConnection += statistics.totalInBytecount;
                                    statistics.totalInBytecount = 0;
                                }
                                if (  statistics.totalOutBytecount > outCount  ) {
                                    statistics.totalOutByteCountBeforeThisConnection += statistics.totalOutBytecount;
                                    statistics.totalOutBytecount = 0;
                                }
                                
                                TBByteCount lastInBytecount    = inCount  - statistics.totalInBytecount;
                                TBByteCount lastOutBytecount   = outCount - statistics.totalOutBytecount;
                                statistics.totalInBytecount    = inCount;
                                statistics.totalOutBytecount   = outCount;
                                
                                // Add new data to the ring buffer
                                int ix = statistics.rbIx;
                                statistics.rb[ix].lastInBytecount  = lastInBytecount;
                                statistics.rb[ix].lastOutBytecount = lastOutBytecount;
                                statistics.rb[ix].lastTimeInterval = [currentTime timeIntervalSinceDate: bytecountsUpdated];
                                ix++;
                                // Point to the next ring buffer entry to write into  
                                if (  ix >= RB_SIZE) {
                                    ix = 0;
                                }
                                statistics.rbIx = ix;
                                
                                [self setBytecountsUpdated: currentTime];

                                pthread_mutex_unlock( &bytecountMutex );
                                
                                [self performSelectorOnMainThread: @selector(updateDisplayWithNewStatistics) 
                                                       withObject: nil 
                                                    waitUntilDone: NO];
                            }
                            @catch (NSException * e) {
                                ;
                            }
                        }
                    }
                }
            } else if (  [line hasPrefix: bcServerPrefix]  ) {
                OSStatus status = pthread_mutex_lock( &bytecountMutex );
                if (  status != EXIT_SUCCESS  ) {
                    NSLog(@"VPNConnection:netsocket:dataAvailable: pthread_mutex_lock( &bytecountMutex ) failed; status = %ld", (long) status);
                    return;
                }
                if (  ! serverNotClient  ) {
                    serverNotClient = TRUE;
                    [self performSelectorOnMainThread: @selector(updateDisplayWithNewStatistics) 
                                           withObject: nil 
                                        waitUntilDone: NO];                    
                }
                pthread_mutex_unlock( &bytecountMutex );
                
            } else {
                [self performSelectorOnMainThread: @selector(processLine:)
                                       withObject: line 
                                    waitUntilDone: NO];
            }
        }
    }
}

-(void) performHasDisconnectedOnMainThread {
	
	[self performSelectorOnMainThread: @selector(hasDisconnected) withObject: nil waitUntilDone: NO];
}

- (void) netsocketDisconnected: (NetSocket*) inSocket
{
    if (inSocket==managementSocket) {
		TBLog(@"DB-CD", @"netsocketDisconnected '%@'", [self displayName]);
        [self setManagementSocket: nil];
        [((MenuController *)[NSApp delegate]) cancelAllIPCheckThreadsForConnection: self];
		[self performSelector: @selector(performHasDisconnectedOnMainThread) withObject: nil afterDelay: 1.0];
    }
}

-(void) readStatisticsTo: (struct Statistics *) returnValue
{
    OSStatus status = pthread_mutex_lock( &bytecountMutex );
    
    // Get the statisticss even if the lock failed; so non-garbage values are filled in
    *returnValue = statistics;
    
    if (  status != EXIT_SUCCESS  ) {
        NSLog(@"VPNConnection:readStatisticsTo: pthread_mutex_lock( &bytecountMutex ) failed; status = %ld", (long) status);
        return;
    }
    
    pthread_mutex_unlock( &bytecountMutex );    
}

-(void) setNumber: (NSString * *) rate andUnits: (NSString * *) units from: (TBByteCount) value unitsArray: (NSArray *) unitsArray
{
    // Decide units
    unsigned i = 0;
	double valueD = (double) value;
    double n = valueD;
    while (  n > 999.0  ) {
        i++;
        double divisor = pow(10.0, (   (double) (i*3)   )  );
        n = valueD / divisor;
    }
    
    if (  i >= [unitsArray count]  ) {
        *units = @"***";
        *rate  = @"***";
        return;
    }
    
    *units = [unitsArray objectAtIndex: i];
    
    if (  i == 0  ) {
        *rate = [NSString stringWithFormat: @"%llu", value];
    } else {
		unsigned n100 = (unsigned) round(n * 100.0) ;
		unsigned displayInteger = n100/100u;
		unsigned displayFraction = n100 - (displayInteger * 100u);
        if (  n100 < 1000u  ) {
            *rate = [NSString stringWithFormat: @"%u.%02u", displayInteger, displayFraction];
			
        } else if (  n100 < 10000u  ) {
            *rate = [NSString stringWithFormat: @"%u.%01u", displayInteger,  (displayFraction + 5u) / 10u];
			
        } else if (  n100 < 100000 ) {
			if (   (displayFraction > 49u)
				&& (displayInteger < 999u)  ) {
				displayInteger++;
			}
            *rate = [NSString stringWithFormat: @"%u", displayInteger];
			
        } else {
            *units = @"***";
            *rate  = @"***";
        }
    }
}

-(void) updateDisplayWithNewStatistics {
    
    if (   serverNotClient  ) {
        [[statusScreen inTFC]            setTitle: @""];
        [[statusScreen inRateTFC]        setTitle: @""];
        [[statusScreen inRateUnitsTFC]   setTitle: @""];
        [[statusScreen outRateTFC]       setTitle: @""];
        [[statusScreen outRateUnitsTFC]  setTitle: @""];
        [[statusScreen outTFC]           setTitle: @""];
        [[statusScreen inTotalTFC]       setTitle: @""];
        [[statusScreen inTotalUnitsTFC]  setTitle: @""];
        [[statusScreen outTotalTFC]      setTitle: @""];
        [[statusScreen outTotalUnitsTFC] setTitle: @""];
        return;
    }

    struct Statistics stats;
    [self readStatisticsTo: &stats];
    
    NSString * inTotal       = nil;
    NSString * inTotalUnits  = nil;
    NSString * outTotal      = nil;
    NSString * outTotalUnits = nil;

    // The Xcode 4.6 analyzer gives spurious warnings about the stats.xxx variables having garbage values, because it does not realize that readStatisticsTo: sets them
    [self setNumber: &inTotal  andUnits: &inTotalUnits  from: (stats.totalInBytecount  + stats.totalInByteCountBeforeThisConnection ) unitsArray: gTotalUnits];
    [self setNumber: &outTotal andUnits: &outTotalUnits from: (stats.totalOutBytecount + stats.totalOutByteCountBeforeThisConnection) unitsArray: gTotalUnits];

    [[statusScreen inTotalTFC]       setTitle: LocalizationNotNeeded(inTotal)];
    [[statusScreen inTotalUnitsTFC]  setTitle: LocalizationNotNeeded(inTotalUnits)];
    [[statusScreen outTotalTFC]      setTitle: LocalizationNotNeeded(outTotal)];
    [[statusScreen outTotalUnitsTFC] setTitle: LocalizationNotNeeded(outTotalUnits)];
    
    // Set the time interval we look at (the last xxx seconds)
    NSTimeInterval rateTimeInterval = [gTbDefaults timeIntervalForKey: @"statisticsRateTimeInterval"
                                                              default: 3.0
                                                                  min: 1.0
                                                                  max: 60.0];
    
    NSTimeInterval timeSinceLastSet = [stats.lastSet timeIntervalSinceNow];
    if (  timeSinceLastSet < 0  ) {
        timeSinceLastSet = - timeSinceLastSet;
    }
    
    rateTimeInterval = rateTimeInterval - timeSinceLastSet;
    if (  rateTimeInterval < 0) {
        [self clearStatisticsRatesDisplay];
        return;
    }
    
    // Accumulate statistics for all samples taken during the last rateTimeInterval seconds
    TBByteCount    tInBytes  = 0;           // # bytes received and sent that we've pulled from the ring buffer
    TBByteCount    tOutBytes = 0;
    NSTimeInterval tTimeInt  = 0.0;         // Time interval the tInBytes and tOutBytes stats cover
    int            nPulled;
    int            ix        = stats.rbIx;  // Index to use to access rb[]
    for (  nPulled=0; nPulled<RB_SIZE; nPulled++  ) {
        // Pull the next data from the ring buffer and incorporate it into accumulated statistics
        if (  ix == 0  ) {
            ix = RB_SIZE;
        }
        ix--;
        
        tTimeInt  += stats.rb[ix].lastTimeInterval;
        tInBytes  += stats.rb[ix].lastInBytecount;
        tOutBytes += stats.rb[ix].lastOutBytecount;
        
        if (  tTimeInt > rateTimeInterval  ) {
            break;
        }
    }

    if ( tTimeInt == 0.0  ) {
        [self clearStatisticsRatesDisplay];
    } else {
        NSString * inRate       = nil;
        NSString * inRateUnits  = nil;
        NSString * outRate      = nil;
        NSString * outRateUnits = nil;
        
        [self setNumber: &inRate  andUnits: &inRateUnits  from: ((TBByteCount) ((double) tInBytes  / tTimeInt)) unitsArray: gRateUnits];
        [self setNumber: &outRate andUnits: &outRateUnits from: ((TBByteCount) ((double) tOutBytes / tTimeInt)) unitsArray: gRateUnits];
        
        [[statusScreen inRateTFC]       setTitle: LocalizationNotNeeded(inRate)];
        [[statusScreen inRateUnitsTFC]  setTitle: LocalizationNotNeeded(inRateUnits)];
        [[statusScreen outRateTFC]      setTitle: LocalizationNotNeeded(outRate)];
        [[statusScreen outRateUnitsTFC] setTitle: LocalizationNotNeeded(outRateUnits)];
    }
}

-(void) clearStatisticsRatesDisplay {
    [[statusScreen inRateTFC]       setTitle: @"0"];
    [[statusScreen outRateTFC]      setTitle: @"0"];
    NSString * units = [gRateUnits objectAtIndex: 0];
    [[statusScreen inRateUnitsTFC]  setTitle: units];
    [[statusScreen outRateUnitsTFC] setTitle: units];
}

-(void) updateStatisticsDisplay {
    
    // Update the connection time string
	if (  statusScreen) {
		[statusScreen setStatus: [self state] forName: [self displayName] connectedSince: [self timeString]];
		[self updateDisplayWithNewStatistics];
	}
}

-(NSString *) timeString
{
    if (  ! logFilesMayExist  ) {
        return @"";
    }
    
    NSDate * csd = [self connectedSinceDate];
    NSTimeInterval ti = [csd timeIntervalSinceNow];
    long timeL = (long) round(-ti);
    
    int days  = timeL / (24*60*60);
    long timeLessDays = timeL - ( days * (24*60*60) );
    
    int hours = timeLessDays / (60*60);
    int timeLessDaysHours = timeLessDays - ( hours * (60*60) );
    
    int mins = timeLessDaysHours / 60;
    int secs = timeLessDaysHours - ( mins * (60) );
    
    NSString * cTimeS;
    if (  days > 0  ) {
        cTimeS = [NSString stringWithFormat: NSLocalizedString(@"%d days %d:%02d:%02d", @"Tooltip"), days, hours, mins, secs];
    } else if (  hours > 0) {
        cTimeS = [NSString stringWithFormat: @"%d:%02d:%02d", hours, mins, secs];
    } else {
        cTimeS = [NSString stringWithFormat: @"%02d:%02d", mins, secs];
    }
    
    return cTimeS;
}

- (NSString*) state
{
    return [self lastState];
}

-(BOOL) isConnected
{
    return [[self state] isEqualToString:@"CONNECTED"];
}
-(BOOL) isDisconnected 
{
    return [[self state] isEqualToString:@"EXITING"];
}

-(BOOL) noOpenvpnProcess
{
    pid_t thePid = pid;
    
    if (  thePid > 0  ) {
        return ( ! [[NSApp pIdsForOpenVPNProcessesOnlyMain: YES] containsObject: [NSNumber numberWithInt: thePid]]);
    }
    
    return YES;
}

-(BOOL) authFailed
{
    return authFailed;
}

- (void) setState: (NSString*) newState
	// Be sure to call this in main thread only
{
    if (  [newState isEqualToString: @"EXITING"]  ) {
        [((MenuController *)[NSApp delegate]) cancelAllIPCheckThreadsForConnection: self];
        
        // If the up script created the flag file at DOWN_SCRIPT_NEEDS_TO_BE_RUN_PATH but the down script did not delete it,
        // it means the down script did not run, which probably means that OpenVPN crashed.
        // So OpenVPN did not, and will not, run the down script, so we run the down script here.
        
        if (  (connectedUseScripts & OPENVPNSTART_USE_SCRIPTS_RUN_SCRIPTS) != 0  ) {        //
			if (  [gFileMgr fileExistsAtPath: DOWN_SCRIPT_NEEDS_TO_BE_RUN_PATH]  ) {
                NSString * scriptNumberString = [NSString stringWithFormat: @"%d",
                                                 (connectedUseScripts & OPENVPNSTART_USE_SCRIPTS_SCRIPT_MASK) >> OPENVPNSTART_USE_SCRIPTS_SCRIPT_SHIFT_COUNT];
                [self addToLog: [NSString stringWithFormat: @"OpenVPN appears to have crashed -- the OpenVPN process has terminated without running a 'down' script, even though it ran an 'up' script. Tunnelblick will run the 'down' script #%@ to attempt to clean up network settings.", scriptNumberString]];
                if (  [scriptNumberString isEqualToString: @"0"]  ) {
					NSString * flagString = @"0";
					BOOL expected   = [gTbDefaults boolForKey: [[self displayName] stringByAppendingString: @"-disableNetworkAccessAfterDisconnect"]];
					BOOL unexpected = [gTbDefaults boolForKey: [[self displayName] stringByAppendingString: @"-disableNetworkAccessAfterUnexpectedDisconnect"]];
					if (  expected  ) {
						if (  unexpected  ) {
							flagString = @"3";
						} else {
							flagString = @"1";
						}
					} else if (  unexpected  ) {
						flagString = @"2";
					}
					[self addToLog: [NSString stringWithFormat: @"Running 'route-pre-down %@' script first.", flagString]];
					runOpenvpnstart([NSArray arrayWithObjects: @"route-pre-down", flagString, displayName, connectedCfgLocCodeString, nil], nil, nil);
                }
                runOpenvpnstart([NSArray arrayWithObjects: @"down", scriptNumberString, displayName, connectedCfgLocCodeString, nil], nil, nil);
            }
        }
        
		if (  ! wereWaitingForNetworkAvailability  ) {
			[logDisplay outputLogFiles];
		}
    }
    
    [self setLastState: newState];
	
    // The 'pre-connect.sh' and 'post-tun-tap-load.sh' scripts are run by openvpnstart
    // The 'connected.sh' and 'reconnecting.sh' scripts are run here
    // The 'disconnect.sh' script is run by this class's hasDisconnected method
    if (   [newState isEqualToString: @"EXITING"]
        && [requestedState isEqualToString: @"CONNECTED"]
		&& [self haveConnectedSince]
        && ( ! [((MenuController *)[NSApp delegate]) terminatingAtUserRequest] )  ) {
        if (  speakWhenDisconnected  ) {
            [self speakActivity: @"disconnected"];
        } else {
            [tunnelDownSound play];
        }
    } else if (  [newState isEqualToString: @"CONNECTED"]  ) {
        if (  speakWhenConnected  ) {
            [self speakActivity: @"connected"];
        } else {
            [tunnelUpSound play];
        }
        // Run the connected script, if any
        [self runScriptNamed: @"connected" openvpnstartCommand: @"connected"];
        [gTbDefaults setObject: displayName forKey: @"lastConnectedDisplayName"];
    } else if (   [newState isEqualToString: @"RECONNECTING"]
			   && [self haveConnectedSince]  ) {
        if (  speakWhenDisconnected  ) {
            [self speakActivity: @"disconnected"];
        } else {
            [tunnelDownSound play];
        }
        // Run the reconnecting script, if any
        [self runScriptNamed: @"reconnecting" openvpnstartCommand: @"reconnecting"];
    }
    
    NSString * statusPref = [gTbDefaults stringForKey: @"connectionWindowDisplayCriteria"];
    if (   [statusPref isEqualToString: @"showWhenChanges"]
        || [newState isEqualToString: @"RECONNECTING"]  ) {
        [self showStatusWindowForce: NO];
    }
    
    [statusScreen setStatus: newState forName: [self displayName] connectedSince: [self timeString]];
    
    if (  showingStatusWindow  ) {

		if (   [newState isEqualToString: @"EXITING"]
            || (   [newState isEqualToString: @"CONNECTED"]
                && (  ! [statusPref isEqualToString: @"showWhenConnectingAndConnected"] )
               )
            ) {
            // Wait one second, then fade away
            NSTimer * timer = [NSTimer scheduledTimerWithTimeInterval: 1.0
                                                               target: self
                                                             selector: @selector(fadeAway)
                                                             userInfo: nil
                                                              repeats: NO];
            [timer tbSetTolerance: -1.0];
        }
    }

    [((MenuController *)[NSApp delegate]) performSelectorOnMainThread:@selector(setState:) withObject:newState waitUntilDone:NO];
    [((MenuController *)[NSApp delegate]) performSelector: @selector(connectionStateDidChange:) withObject: self];
}

-(void) speakActivity: (NSString *) activityName
{
    NSString * speech;
    
    if (  [activityName isEqualToString: @"connected"]  ) {
        speech = [NSString stringWithFormat:
                  NSLocalizedString(@"Connected to %@", @"Speak string"),
                  [self localizedName]];
    } else if (  [activityName isEqualToString: @"disconnected"]  ) {
        speech = [NSString stringWithFormat:
                  NSLocalizedString(@"Disconnected from %@", @"Speak string"),
                  [self localizedName]];
    } else {
		NSLog(@"speakActivity: No activity '%@'", activityName);
		return;
	}
    
    if (  [speech length] != 0  ) {
        NSSpeechSynthesizer * speechSynth = [[[NSSpeechSynthesizer alloc] initWithVoice: nil] autorelease];
        [speechSynth startSpeakingString: speech];
    }
}

-(void) runScriptNamed: (NSString *) scriptName openvpnstartCommand: (NSString *) command
{
    if (  [[configPath pathExtension] isEqualToString: @"tblk"]  ) {
		NSString * configFile    = lastPartOfPath([self configPath]);
		NSString * configLocCode = [self connectedCfgLocCodeString];
        NSArray * arguments = [NSArray arrayWithObjects: command, configFile, configLocCode, nil];
        
        NSString * stdOutString = @"";
        NSString * stdErrString = @"";
        OSStatus status = runOpenvpnstart(arguments, &stdOutString, &stdErrString);
        
		if (   (status == EXIT_SUCCESS)
			&& [stdOutString hasPrefix: @"No such script exists: "]  ) {
			[self addToLog: [NSString stringWithFormat: @"No '%@.sh' script to execute", scriptName]];
			return;
		}
		
		if (  [stdOutString hasSuffix: @"\n"]  ) {
			stdOutString = [stdOutString substringToIndex: [stdOutString length] - 1];
		}
		if (  [stdErrString hasSuffix: @"\n"]  ) {
			stdErrString = [stdErrString substringToIndex: [stdErrString length] - 1];
		}
		
		NSMutableString * msg = [NSMutableString stringWithCapacity: 1000];
		if (  status == EXIT_SUCCESS  ) {
			[msg appendString: [NSString stringWithFormat: @"The '%@.sh' script succeeded\n", scriptName]];
		} else {
			[msg appendString: [NSString stringWithFormat: @"The '%@.sh' script failed; 'openvpnstart %@' returned error %ld\n",
								scriptName, command, (long) status]];
		}
		
		if (  [stdOutString length] != 0  ) {
			[msg appendString: [NSString stringWithFormat: @"%@\n", stdOutString]];
		}
		
		if (  [stdErrString length] != 0  ) {
			[msg appendString: [NSString stringWithFormat: @"%@\n", stdErrString]];
		}
		
		[self addToLog: msg];
		
        if (  status != EXIT_SUCCESS  ) {
            if (   ( ! [scriptName isEqualToString: @"post-disconnect"])
				&& ( ! [scriptName isEqualToString: @"pre-disconnect"])  ) {
                [self addToLog: [NSString stringWithFormat: @"Disconnecting because the '%@.sh' script failed", scriptName]];
				[self startDisconnectingUserKnows: @YES];
            }
        }
    }
}

-(void) fadeAway
{
    if (   (! gShuttingDownTunnelblick)
        && (  gSleepWakeState == noSleepState)
        && (  gActiveInactiveState == active)   ) {
        BOOL okToFade = TRUE;   // Assume OK to fade, but don't fade if any connection is being attempted or any auth failed
        VPNConnection * connection;
        NSEnumerator * connectionEnum = [[((MenuController *)[NSApp delegate]) connectionArray] objectEnumerator];
        while (  (connection = [connectionEnum nextObject])  ) {
            if (   ( ! [connection isConnected]    )            // Don't fade if any connection is being  attempted
                && ( ! [connection isDisconnected] )  ) {
                okToFade = FALSE;
                break;
            }
            if (  [connection authFailed]  ) {                  // or if any auth failed
                okToFade = FALSE;
                break;
            }
        }
        if (  [((MenuController *)[NSApp delegate]) mouseIsInsideAnyView]  ) {
            okToFade = FALSE;
        }
        
        if (  okToFade  ) {
            [statusScreen fadeOut];
            showingStatusWindow = FALSE;
        }
    }
}

- (BOOL)validateMenuItem:(NSMenuItem *)anItem 
{
    SEL action = [anItem action];
	
    if (action == @selector(toggle:)) 
    {
        VPNConnection *connection = [anItem target];
        
        // setting menu item's state:
        int state = NSMixedState;
        
        if ([connection isConnected]) 
        {
            state = NSOnState;
        } 
        else if ([connection isDisconnected]) 
        {
            state = NSOffState;
        }
        
        [anItem setState:state];
        
        // setting menu command title depending on current status:
        NSString *commandString; 
        if (  ! [[connection state] isEqualToString:@"EXITING"]  ) {
            commandString = NSLocalizedString(@"Disconnect %@%@", @"Menu item");
        } else {
            commandString = NSLocalizedString(@"Connect %@%@", @"Menu item");
        }
        
        // Remove submenu prefix if using submenus
        NSString * itemName = [connection localizedName];
        NSRange lastSlashRange = [itemName rangeOfString: @"/" options: NSBackwardsSearch range: NSMakeRange(0, [itemName length] - 1)];
        if (   (lastSlashRange.length != 0)
            && ( ! [gTbDefaults boolForKey: @"doNotShowConnectionSubmenus"])  ) {
            itemName = [itemName substringFromIndex: lastSlashRange.location + 1];
        }
        
        NSString *itemTitle = [NSString stringWithFormat:commandString,
                               itemName,
                               [self connectTimeString]];
        [anItem setTitle:itemTitle];
        if (  [gTbDefaults boolForKey: @"showTooltips"]  ) {
            [anItem setToolTip: [connection configPath]];
        }
    }
	
	if (  ! [TBOperationQueue shouldUIBeEnabledForDisplayName: [self displayName]]  ) {
		return NO; // Disable connect/disconnect menu commands if installing files
	}
	
	return YES;
}

-(int) useDNSStatus
{
	NSString * key = [[self displayName] stringByAppendingString:@"useDNS"];
	unsigned ix = [gTbDefaults unsignedIntForKey: key
                                         default: 1
                                             min: 0
                                             max: MAX_SET_DNS_WINS_INDEX];
    return (int)ix;
}

// Returns an array of NSDictionary objects with entries for the 'Set nameserver' popup button for this connection
// The "value" entry is the value of the xxxUseDNS preference for that entry
-(NSArray *) modifyNameserverOptionList
{
    // Figure out whether to use the standard scripts or 'custom' scripts
    // If Deployed, .tblk, or "old" scripts exist, they are considered "custom" scripts
    BOOL custom = FALSE;
    NSString * resourcePath          = [[NSBundle mainBundle] resourcePath];
    
    if (  [configPath hasPrefix: [gDeployPath stringByAppendingString: @"/"]]  ) {
        NSString * deployPath                  = [resourcePath stringByAppendingPathComponent: @"Deploy"];
        NSString * configFile                  = [configPath lastPathComponent];
        NSString * deployScriptPath            = [deployPath stringByAppendingPathComponent:[configFile stringByDeletingPathExtension]];
        NSString * deployUpscriptPath          = [deployScriptPath stringByAppendingPathExtension: @"up.sh"            ];
        NSString * deployUpscriptNoMonitorPath = [deployScriptPath stringByAppendingPathExtension: @"nomonitor.up.sh"  ];
        NSString * deployNewUpscriptPath       = [deployScriptPath stringByAppendingPathExtension: @"up.tunnelblick.sh"];
        if (   [gFileMgr fileExistsAtPath: deployUpscriptPath]
            || [gFileMgr fileExistsAtPath: deployUpscriptNoMonitorPath]
            || [gFileMgr fileExistsAtPath: deployNewUpscriptPath]  ) {
            custom = TRUE;
        }
    } else {
        NSString * upscriptPath          = [resourcePath stringByAppendingPathComponent: @"client.up.osx.sh"          ];
        NSString * upscriptNoMonitorPath = [resourcePath stringByAppendingPathComponent: @"client.nomonitor.up.osx.sh"];
        if (   [gFileMgr fileExistsAtPath: upscriptPath]
            || [gFileMgr fileExistsAtPath: upscriptNoMonitorPath]  ) {
            custom = TRUE;
        }
    }
    
    if (  ! custom  ) {
        if (  [[configPath pathExtension] isEqualToString: @"tblk"]) {
            NSString * scriptPath                   = [configPath stringByAppendingPathComponent: @"Contents/Resources"];
            NSString * tblkUpscriptPath             = [scriptPath stringByAppendingPathComponent: @"up.sh"            ];
            NSString * tblkUpscriptNoMonitorPath    = [scriptPath stringByAppendingPathComponent: @"nomonitor.up.sh"  ];
            NSString * tblkNewUpscriptPath          = [scriptPath stringByAppendingPathComponent: @"up.tunnelblick.sh"];
            if (   [gFileMgr fileExistsAtPath: tblkUpscriptPath]
                || [gFileMgr fileExistsAtPath: tblkUpscriptNoMonitorPath]
                || [gFileMgr fileExistsAtPath: tblkNewUpscriptPath]  ) {
                custom = TRUE;
            }
        }
    }
    
    if (   custom  ) {
        return [[[NSArray alloc] initWithObjects:
                 [NSDictionary dictionaryWithObjectsAndKeys: NSLocalizedString(@"Do not set nameserver",          @"PopUpButton"), @"name", @"0", @"value", nil],
                 [NSDictionary dictionaryWithObjectsAndKeys: NSLocalizedString(@"Set nameserver",                 @"PopUpButton"), @"name", @"1", @"value", nil],
                 nil] autorelease];
    } else {
        return [[[NSArray alloc] initWithObjects:
                 [NSDictionary dictionaryWithObjectsAndKeys: NSLocalizedString(@"Do not set nameserver",        @"PopUpButton"), @"name", @"0", @"value", nil],
                 [NSDictionary dictionaryWithObjectsAndKeys: NSLocalizedString(@"Set nameserver",               @"PopUpButton"), @"name", @"1", @"value", nil],
                 [NSDictionary dictionaryWithObjectsAndKeys: NSLocalizedString(@"Set nameserver (3.1)",         @"PopUpButton"), @"name", @"4", @"value", nil],
                 [NSDictionary dictionaryWithObjectsAndKeys: NSLocalizedString(@"Set nameserver (3.0b10)",      @"PopUpButton"), @"name", @"2", @"value", nil],
                 [NSDictionary dictionaryWithObjectsAndKeys: NSLocalizedString(@"Set nameserver (alternate 1)", @"PopUpButton"), @"name", @"3", @"value", nil],
				 [NSDictionary dictionaryWithObjectsAndKeys: NSLocalizedString(@"Set nameserver (alternate 2)",	@"PopUpButton"), @"name", @"4", @"value", nil],
                 nil] autorelease];
    }
}

-(void) startMonitoringLogFiles
{
    [logDisplay startMonitoringLogFiles];
}

-(void) stopMonitoringLogFiles
{
    [logDisplay stopMonitoringLogFiles];
}

-(NSString *) openvpnLogPath
{
    return [logDisplay openvpnLogPath];
}

-(void) setSpeakWhenConnected: (BOOL) newValue
{
	speakWhenConnected = newValue;
}

-(void) setSpeakWhenDisconnected: (BOOL) newValue
{
	speakWhenDisconnected = newValue;
}

TBSYNTHESIZE_OBJECT_GET(retain, StatusWindowController *, statusScreen)

TBSYNTHESIZE_OBJECT_SET(		NSString *,				  sanitizedConfigurationFileContents, setSanitizedConfigurationFileContents)
TBSYNTHESIZE_OBJECT_SET(        NSString *,               condensedSanitizedConfigurationFileContents,                         setCondensedSanitizedConfigurationFileContents)

TBSYNTHESIZE_OBJECT_SET(        NSSound *,                tunnelUpSound,                    setTunnelUpSound)

TBSYNTHESIZE_OBJECT_SET(        NSSound *,                tunnelDownSound,                  setTunnelDownSound)

TBSYNTHESIZE_OBJECT(retain,     NSDate *,                 bytecountsUpdated,                setBytecountsUpdated)

TBSYNTHESIZE_OBJECT(retain,     NSArray *,                argumentsUsedToStartOpenvpnstart, setArgumentsUsedToStartOpenvpnstart)

TBSYNTHESIZE_OBJECT(retain,     NSMutableArray *,         messagesIfConnectionFails,        setMessagesIfConnectionFails)

TBSYNTHESIZE_OBJECT(retain,     NSMenuItem *,             menuItem,                         setMenuItem)

TBSYNTHESIZE_OBJECT(retain,     AlertWindowController *,  slowDisconnectWindowController,   setSlowDisconnectWindowController)

TBSYNTHESIZE_OBJECT(retain,     NSString *,               ipAddressBeforeConnect,           setIpAddressBeforeConnect)
TBSYNTHESIZE_OBJECT(retain,     NSString *,               dynamicChallengeUsername,         setDynamicChallengeUsername)
TBSYNTHESIZE_OBJECT(retain,     NSString *,               dynamicChallengeState,            setDynamicChallengeState)
TBSYNTHESIZE_OBJECT(retain,     NSString *,               dynamicChallengePrompt,           setDynamicChallengePrompt)
TBSYNTHESIZE_OBJECT(retain,     NSString *,               dynamicChallengeFlags,            setDynamicChallengeFlags)
TBSYNTHESIZE_OBJECT_SET(	    NSString *,               authRetryParameter,               setAuthRetryParameter)
TBSYNTHESIZE_OBJECT(retain,     NSString *,               serverIPAddress,                  setServerIPAddress)
TBSYNTHESIZE_OBJECT(retain,     NSString *,               connectedCfgLocCodeString,        setConnectedCfgLocCodeString)
TBSYNTHESIZE_OBJECT(retain,     NSString *,               localizedName,                    setLocalizedName)
TBSYNTHESIZE_OBJECT(retain,     NSString *,               requestedState,                   setRequestedState)
TBSYNTHESIZE_OBJECT(retain,     NSString *,               lastState,                        setLastState)
TBSYNTHESIZE_OBJECT(retain,     NSString *,               tunOrTap,                         setTunOrTap)

TBSYNTHESIZE_NONOBJECT(         BOOL,                     ipCheckLastHostWasIPAddress,      setIpCheckLastHostWasIPAddress)
TBSYNTHESIZE_NONOBJECT(         BOOL,                     haveConnectedSince,               setHaveConnectedSince)
TBSYNTHESIZE_NONOBJECT(         BOOL,                     logFilesMayExist,                 setLogFilesMayExist)


//*********************************************************************************************************
//
// AppleScript support
//
//*********************************************************************************************************

- (NSScriptObjectSpecifier *)objectSpecifier
{
    NSScriptClassDescription* appDesc = (NSScriptClassDescription*)[NSApp classDescription]; 
    
    return [[[NSNameSpecifier alloc] 
             initWithContainerClassDescription:appDesc 
             containerSpecifier:nil 
             key:@"applescriptConfigurationList" 
             name:[self displayName]] autorelease]; 
} 

- (NSString *) autoConnect
{
    NSString* autoConnectkey = [[self displayName] stringByAppendingString: @"autoConnect"];
    NSString* systemStartkey = [[self displayName] stringByAppendingString: @"-onSystemStart"];
    
    if (  [gTbDefaults boolForKey: autoConnectkey]  ) {
        if (  [gTbDefaults boolForKey: systemStartkey]  ) {
            return @"START";
        }

        return @"LAUNCH";
    }
    
    return @"NO";
}

- (NSString *) bytesIn
{
    struct Statistics stats;
    stats.totalInBytecount = 0;  stats.totalInByteCountBeforeThisConnection = 0;   // Avoid Xcode 4.6 analyzer warnings
    [self readStatisticsTo: &stats];
    return [NSString stringWithFormat: @"%llu", (unsigned long long) (stats.totalInBytecount + stats.totalInByteCountBeforeThisConnection)];
}
- (NSString *) bytesOut
{
    struct Statistics stats;
    stats.totalOutBytecount = 0; stats.totalOutByteCountBeforeThisConnection = 0;    // Avoid Xcode 4.6 analyzer warnings
    [self readStatisticsTo: &stats];
    return [NSString stringWithFormat: @"%llu", (unsigned long long) (stats.totalOutBytecount + stats.totalOutByteCountBeforeThisConnection)];
}

@end
