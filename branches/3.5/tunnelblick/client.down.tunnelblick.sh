#!/bin/bash -e
# Note: must be bash; uses bash-specific tricks
#
# ******************************************************************************************************************
# This Tunnelblick script does everything! It handles TUN and TAP interfaces, 
# pushed configurations and DHCP leases. :)
# 
# This is the "Down" version of the script, executed after the connection is 
# closed.
#
# Created by: Nick Williams (using original code and parts of old Tblk scripts)
# 
# ******************************************************************************************************************

# @param String message - The message to log
logMessage()
{
	echo "${@}"
}

# @param String message - The message to log
logDebugMessage()
{
	echo "${@}" > /dev/null
}

trim()
{
echo ${@}
}

##########################################################################################
flushDNSCache()
{
    if ${ARG_FLUSH_DNS_CACHE} ; then
        set +e # "grep" will return error status (1) if no matches are found, so don't fail on individual errors
        readonly OSVER="$(sw_vers | grep 'ProductVersion:' | grep -o '10\.[0-9]*')"
        set -e # We instruct bash that it CAN again fail on errors
	    if [ "${OSVER}" = "10.4" ] ; then

			if [ -f /usr/sbin/lookupd ] ; then
				set +e # we will catch errors from lookupd
				/usr/sbin/lookupd -flushcache
				if [ $? != 0 ] ; then
					logMessage "Unable to flush the DNS cache via lookupd"
				else
					logMessage "Flushed the DNS cache via lookupd"
				fi
				set -e # bash should again fail on errors
			else
				logMessage "/usr/sbin/lookupd not present. Not flushing the DNS cache"
			fi

		else

			if [ -f /usr/bin/dscacheutil ] ; then
				set +e # we will catch errors from dscacheutil
				/usr/bin/dscacheutil -flushcache
				if [ $? != 0 ] ; then
					logMessage "Unable to flush the DNS cache via dscacheutil"
				else
					logMessage "Flushed the DNS cache via dscacheutil"
				fi
				set -e # bash should again fail on errors
			else
				logMessage "/usr/bin/dscacheutil not present. Not flushing the DNS cache via dscacheutil"
			fi
		
			if [ -f /usr/sbin/discoveryutil ] ; then
				set +e # we will catch errors from discoveryutil
				/usr/sbin/discoveryutil udnsflushcaches
				if [ $? != 0 ] ; then
					logMessage "Unable to flush the DNS cache via discoveryutil udnsflushcaches"
				else
					logMessage "Flushed the DNS cache via discoveryutil udnsflushcaches"
				fi
				/usr/sbin/discoveryutil mdnsflushcache
				if [ $? != 0 ] ; then
					logMessage "Unable to flush the DNS cache via discoveryutil mdnsflushcache"
				else
					logMessage "Flushed the DNS cache via discoveryutil mdnsflushcache"
				fi
				set -e # bash should again fail on errors
			else
				logMessage "/usr/sbin/discoveryutil not present. Not flushing the DNS cache via discoveryutil"
			fi
			
			set +e # "grep" will return error status (1) if no matches are found, so don't fail on individual errors
			hands_off_ps="$( ps -ax | grep HandsOffDaemon | grep -v grep.HandsOffDaemon )"
			set -e # We instruct bash that it CAN again fail on errors
			if [ "${hands_off_ps}" = "" ] ; then
				if [ -f /usr/bin/killall ] ; then
					set +e # ignore errors if mDNSResponder isn't currently running
					/usr/bin/killall -HUP mDNSResponder
					if [ $? != 0 ] ; then
						logMessage "mDNSResponder not running. Not notifying it that the DNS cache was flushed"
					else
						logMessage "Notified mDNSResponder that the DNS cache was flushed"
					fi
					set -e # bash should again fail on errors
				else
					logMessage "/usr/bin/killall not present. Not notifying mDNSResponder that the DNS cache was flushed"
				fi
			else
				logMessage "Hands Off is running.  Not notifying mDNSResponder that the DNS cache was flushed"
			fi
		
		fi
    fi
}

##########################################################################################
resetPrimaryInterface()
{
	set +e # "grep" will return error status (1) if no matches are found, so don't fail on individual errors
	WIFI_INTERFACE="$(networksetup -listallhardwareports | awk '$3=="Wi-Fi" {getline; print $2}')"
	if [ "${WIFI_INTERFACE}" == "" ] ; then
		WIFI_INTERFACE="$(networksetup -listallhardwareports | awk '$3=="AirPort" {getline; print $2}')"
    fi
	PINTERFACE="$( scutil <<-EOF |
        open
        show State:/Network/Global/IPv4
        quit
EOF
    grep PrimaryInterface | sed -e 's/.*PrimaryInterface : //'
    )"
    set -e # resume abort on error

    if [ "${PINTERFACE}" != "" ] ; then
	    if [ "${PINTERFACE}" == "${WIFI_INTERFACE}" -a "${OSVER}" != "10.4" -a -f /usr/sbin/networksetup ] ; then
		    if [ "${OSVER}" == "10.5" ] ; then
			    logMessage "Resetting primary interface '${PINTERFACE}' via networksetup -setairportpower off/on..."
				/usr/sbin/networksetup -setairportpower off
				sleep 2
				/usr/sbin/networksetup -setairportpower on
			else
				logMessage "Resetting primary interface '${PINTERFACE}' via networksetup -setairportpower ${PINTERFACE} off/on..."
				/usr/sbin/networksetup -setairportpower "${PINTERFACE}" off
				sleep 2
				/usr/sbin/networksetup -setairportpower "${PINTERFACE}" on
			fi
		else
		    if [ -f /sbin/ifconfig ] ; then
			    logMessage "Resetting primary interface '${PINTERFACE}' via ifconfig ${PINTERFACE} down/up..."
                /sbin/ifconfig "${PINTERFACE}" down
                sleep 2
			    /sbin/ifconfig "${PINTERFACE}" up
			else
				logMessage "Not resetting primary interface because /sbin/ifconfig does not exist."
			fi
		fi
    else
        logMessage "Not resetting primary interface because it cannot be found."
    fi
}

##########################################################################################
trap "" TSTP
trap "" HUP
trap "" INT
export PATH="/bin:/sbin:/usr/sbin:/usr/bin"

readonly OUR_NAME=$(basename "${0}")

logMessage "**********************************************"
logMessage "Start of output from ${OUR_NAME}"

# Remove the flag file that indicates we need to run the down script

if [ -e   "/tmp/tunnelblick-downscript-needs-to-be-run.txt" ] ; then
    rm -f "/tmp/tunnelblick-downscript-needs-to-be-run.txt"
fi

# Test for the "-r" Tunnelbick option (Reset primary interface after disconnecting) because we _always_ need its value.
# Usually we get the value for that option (and the other options) from State:/Network/OpenVPN,
# but that key may not exist (because, for example, there were no DNS changes).
# So we get the value from the Tunnelblick options passed to this script by OpenVPN.
#
# We do the same thing for the -f Tunnelblick option (Flush DNS cache after connecting or disconnecting)
ARG_RESET_PRIMARY_INTERFACE_ON_DISCONNECT="false"
ARG_FLUSH_DNS_CACHE="false"
while [ {$#} ] ; do
    if [ "${1:0:1}" != "-" ] ; then				# Tunnelblick arguments start with "-" and come first
        break                                   # so if this one doesn't start with "-" we are done processing Tunnelblick arguments
    fi
    if [ "$1" = "-r" ] ; then
        ARG_RESET_PRIMARY_INTERFACE_ON_DISCONNECT="true"
    else
	    if [ "$1" = "-f" ] ; then
            ARG_FLUSH_DNS_CACHE="true"
        fi
    fi
    shift                                       # Shift arguments to examine the next option (if there is one)
done

# Quick check - is the configuration there?
if ! scutil -w State:/Network/OpenVPN &>/dev/null -t 1 ; then
	# Configuration isn't there
    logMessage "WARNING: Not restoring DNS settings because no saved Tunnelblick DNS information was found."
	
	flushDNSCache
    
	if ${ARG_RESET_PRIMARY_INTERFACE_ON_DISCONNECT} ; then
        resetPrimaryInterface
    fi
    logMessage "End of output from ${OUR_NAME}"
    logMessage "**********************************************"
	exit 0
fi

# Get info saved by the up script
TUNNELBLICK_CONFIG="$( scutil <<-EOF
	open
	show State:/Network/OpenVPN
	quit
EOF
)"

ARG_MONITOR_NETWORK_CONFIGURATION="$(echo "${TUNNELBLICK_CONFIG}" | grep -i '^[[:space:]]*MonitorNetwork :' | sed -e 's/^.*: //g')"
LEASEWATCHER_PLIST_PATH="$(echo "${TUNNELBLICK_CONFIG}" | grep -i '^[[:space:]]*LeaseWatcherPlistPath :' | sed -e 's/^.*: //g')"
REMOVE_LEASEWATCHER_PLIST="$(echo "${TUNNELBLICK_CONFIG}" | grep -i '^[[:space:]]*RemoveLeaseWatcherPlist :' | sed -e 's/^.*: //g')"
PSID="$(echo "${TUNNELBLICK_CONFIG}" | grep -i '^[[:space:]]*Service :' | sed -e 's/^.*: //g')"
# Don't need: SCRIPT_LOG_FILE="$(echo "${TUNNELBLICK_CONFIG}" | grep -i '^[[:space:]]*ScriptLogFile :' | sed -e 's/^.*: //g')"
# Don't need: ARG_RESTORE_ON_DNS_RESET="$(echo "${TUNNELBLICK_CONFIG}" | grep -i '^[[:space:]]*RestoreOnDNSReset :' | sed -e 's/^.*: //g')"
# Don't need: ARG_RESTORE_ON_WINS_RESET="$(echo "${TUNNELBLICK_CONFIG}" | grep -i '^[[:space:]]*RestoreOnWINSReset :' | sed -e 's/^.*: //g')"
# Don't need: PROCESS="$(echo "${TUNNELBLICK_CONFIG}" | grep -i '^[[:space:]]*PID :' | sed -e 's/^.*: //g')"
# Don't need: ARG_IGNORE_OPTION_FLAGS="$(echo "${TUNNELBLICK_CONFIG}" | grep -i '^[[:space:]]*IgnoreOptionFlags :' | sed -e 's/^.*: //g')"
ARG_TAP="$(echo "${TUNNELBLICK_CONFIG}" | grep -i '^[[:space:]]*IsTapInterface :' | sed -e 's/^.*: //g')"
ARG_FLUSH_DNS_CACHE="$(echo "${TUNNELBLICK_CONFIG}" | grep -i '^[[:space:]]*FlushDNSCache :' | sed -e 's/^.*: //g')"
ARG_RESET_PRIMARY_INTERFACE_ON_DISCONNECT="$(echo "${TUNNELBLICK_CONFIG}" | grep -i '^[[:space:]]*ResetPrimaryInterface :' | sed -e 's/^.*: //g')"
bRouteGatewayIsDhcp="$(echo "${TUNNELBLICK_CONFIG}" | grep -i '^[[:space:]]*RouteGatewayIsDhcp :' | sed -e 's/^.*: //g')"
bTapDeviceHasBeenSetNone="$(echo "${TUNNELBLICK_CONFIG}" | grep -i '^[[:space:]]*TapDeviceHasBeenSetNone :' | sed -e 's/^.*: //g')"
bAlsoUsingSetupKeys="$(echo "${TUNNELBLICK_CONFIG}" | grep -i '^[[:space:]]*bAlsoUsingSetupKeys :' | sed -e 's/^.*: //g')"
sTunnelDevice="$(echo "${TUNNELBLICK_CONFIG}" | grep -i '^[[:space:]]*TunnelDevice :' | sed -e 's/^.*: //g')"

# Remove leasewatcher
if ${ARG_MONITOR_NETWORK_CONFIGURATION} ; then
	launchctl unload "${LEASEWATCHER_PLIST_PATH}"
    if ${REMOVE_LEASEWATCHER_PLIST} ; then
        rm -f "${LEASEWATCHER_PLIST_PATH}"
    fi
	logMessage "Cancelled monitoring of system configuration changes"
fi

if ${ARG_TAP} ; then
	if [ "$bRouteGatewayIsDhcp" == "true" ]; then
        if [ "$bTapDeviceHasBeenSetNone" == "false" ]; then
            if [ -z "$dev" ]; then
                # If $dev is not defined, then use TunnelDevice, which was set from $dev by client.up.tunnelblick.sh
                # ($def is not defined when this script is called from MenuController to clean up when exiting Tunnelblick)
                if [ -n "${sTunnelDevice}" ]; then
                    logMessage "\$dev not defined; using TunnelDevice: ${sTunnelDevice}"
                    set +e
                    ipconfig set "${sTunnelDevice}" NONE 2>/dev/null
                    set -e
                    logMessage "Released the DHCP lease via ipconfig set ${sTunnelDevice} NONE."
                else
                    logMessage "Cannot configure TAP interface to NONE without \$dev or State:/Network/OpenVPN/TunnelDevice being defined. Device may not have disconnected properly."
                fi
            else
                set +e
                ipconfig set "$dev" NONE 2>/dev/null
                set -e
                logMessage "Released the DHCP lease via ipconfig set $dev NONE."
            fi
        fi
    fi
fi

# Issue warning if the primary service ID has changed
set +e # "grep" will return error status (1) if no matches are found, so don't fail if not found
PSID_CURRENT="$( scutil <<-EOF |
	open
	show State:/Network/OpenVPN
	quit
EOF
grep Service | sed -e 's/.*Service : //'
)"
set -e # resume abort on error
if [ "${PSID}" != "${PSID_CURRENT}" ] ; then
	logMessage "Ignoring change of Network Primary Service from ${PSID} to ${PSID_CURRENT}"
fi

# Restore configurations
DNS_OLD="$( scutil <<-EOF
	open
	show State:/Network/OpenVPN/OldDNS
	quit
EOF
)"
SMB_OLD="$( scutil <<-EOF
	open
	show State:/Network/OpenVPN/OldSMB
	quit
EOF
)"
DNS_OLD_SETUP="$( scutil <<-EOF
	open
	show State:/Network/OpenVPN/OldDNSSetup
	quit
EOF
)"
TB_NO_SUCH_KEY="<dictionary> {
  TunnelblickNoSuchKey : true
}"

if [ "${DNS_OLD}" = "${TB_NO_SUCH_KEY}" ] ; then
	scutil <<-EOF
		open
		remove State:/Network/Service/${PSID}/DNS
		quit
EOF
else
	scutil <<-EOF
		open
		get State:/Network/OpenVPN/OldDNS
		set State:/Network/Service/${PSID}/DNS
		quit
EOF
fi

if [ "${DNS_OLD_SETUP}" = "${TB_NO_SUCH_KEY}" ] ; then
	if ${bAlsoUsingSetupKeys} ; then
		logDebugMessage "DEBUG: Removing 'Setup:' DNS key"
		scutil <<-EOF
			open
			remove Setup:/Network/Service/${PSID}/DNS
			quit
EOF
	else
		logDebugMessage "DEBUG: Not removing 'Setup:' DNS key"
	fi
else
	if ${bAlsoUsingSetupKeys} ; then
		logDebugMessage "DEBUG: Restoring 'Setup:' DNS key"
		scutil <<-EOF
			open
			get State:/Network/OpenVPN/OldDNSSetup
			set Setup:/Network/Service/${PSID}/DNS
			quit
EOF
	else
		logDebugMessage "DEBUG: Not restoring 'Setup:' DNS key"
	fi
fi

if [ "${SMB_OLD}" = "${TB_NO_SUCH_KEY}" ] ; then
	scutil > /dev/null <<-EOF
		open
		remove State:/Network/Service/${PSID}/SMB
		quit
EOF
else
	scutil > /dev/null <<-EOF
		open
		get State:/Network/OpenVPN/OldSMB
		set State:/Network/Service/${PSID}/SMB
		quit
EOF
fi

logMessage "Restored the DNS and SMB configurations"

set +e # "grep" will return error status (1) if no matches are found, so don't fail if not found
new_resolver_contents="$( grep -v '#' < /etc/resolv.conf )"
set -e # resume abort on error
logDebugMessage "DEBUG:"
logDebugMessage "DEBUG: /etc/resolve = ${new_resolver_contents}"

set +e # scutil --dns will return error status in case dns is already down, so don't fail if no dns found
scutil_dns="$( scutil --dns)"
set -e # resume abort on error
logDebugMessage "DEBUG:"
logDebugMessage "DEBUG: scutil --dns = ${scutil_dns}"
logDebugMessage "DEBUG:"

flushDNSCache

# Remove our system configuration data
scutil <<-EOF
	open
	remove State:/Network/OpenVPN/OldDNS
	remove State:/Network/OpenVPN/OldSMB
	remove State:/Network/OpenVPN/OldDNSSetup
	remove State:/Network/OpenVPN/DNS
	remove State:/Network/OpenVPN/SMB
	remove State:/Network/OpenVPN
	quit
EOF

if ${ARG_RESET_PRIMARY_INTERFACE_ON_DISCONNECT} ; then
    resetPrimaryInterface
fi

logMessage "End of output from ${OUR_NAME}"
logMessage "**********************************************"

exit 0
