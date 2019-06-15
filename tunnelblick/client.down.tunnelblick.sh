#!/bin/bash
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
	echo "$( date -j +'%Y-%m-%d %H:%M:%S' ) *Tunnelblick: " "${@}" | tee -a "/Library/Application Support/Tunnelblick/DownLog.txt"
}

# @param String message - The message to log
logDebugMessage()
{
	logMessage "${@}"
}

##########################################################################################
execute_command() {

	# Executes a command, printing an optional success or failure message.
	#
	# If an error occurs, a detailed error message is always printed before the optional failure message.
	#
	#	$1      = empty string or string to print if the command succeeded
	#	$2		= empty string or string to print if the command failed
	#	$3...$n = command to execute and its arguments
	#
	# The return status will be the status the command returned.

	local success_msg="$1"
	shift
	local failure_msg="$1"
	shift

	# Construct a string for eval, with the command and arguments enclosed in single quotes to avoid splitting and further expansion
	local command=''
	while [ $# -ne 0 ] ; do
		command="$command '$1'"
		shift
	done

	local status
	eval "$command" 2>&1
	status=$?
	if [ $status -eq 0 ] ; then
		if [ -n "$success_msg" ] ; then
			logMessage "$success_msg"
		fi
	else
		logMessage "ERROR: Failed with status $status: " "${@}"
		if [ -n "$failure_msg" ] ; then
			logMessage "$failure_msg"
		fi
	fi

	return $status
}

##########################################################################################
run_prefix_or_suffix()
{
# @param String 'down-prefix.sh' or 'down-suffix.sh'
#
# Execute the specified script (if it exists) in a subshell with the arguments with which this script was called.
#
# Tunnelblick starts OpenVPN with --set-env TUNNELBLICK_CONFIG_FOLDER <PATH>
# where <PATH> is the path to the folder containing the OpenVPN configuration file.
# That folder is where the script will be (if it exists).

	if [  -z "$TUNNELBLICK_CONFIG_FOLDER" ] ; then
		logMessage "ERROR: The 'TUNNELBLICK_CONFIG_FOLDER' environment variable is missing or empty"
		return
	fi

	if [ "$1" != "down-prefix.sh" ] && [ "$1" != "down-suffix.sh" ] ; then
		logMessage "ERROR: run_prefix_or_suffix not called with 'down-prefix.sh' or 'down-suffix.sh'"
		return
	fi

	if [ -e "$TUNNELBLICK_CONFIG_FOLDER/$1" ] ; then
		logMessage "---------- Start of output from $1"

		# shellcheck disable=SC2086
		(  "$TUNNELBLICK_CONFIG_FOLDER/$1" ${SCRIPT_ARGS[*]}  )
		local status=$?

		logMessage "---------- End of output from $1"

		if [ $status -ne 0 ] ; then
			logMessage "ERROR: $1 exited with error status $status"
			return
		fi
	fi
}

##########################################################################################
# @param String list - list of network service names, output from disable_ipv6()
restore_ipv6() {

    # Undoes the actions performed by the disable_ipv6() routine in client.up.tunnelblick.sh by restoring the IPv6
    # 'automatic' setting for each network service for which that routine disabled IPv6.
    #
    # $1 must contain the output from disable_ipv6() -- the list of network services.
    #
    # This routine outputs log messages describing its activities.

    if [ "$1" = "" ] ; then
        return
    fi

	local ripv6_service

	printf %s "$1$LF"  |   while IFS= read -r ripv6_service ; do
		if [ -n "$ripv6_service" ] ; then

			execute_command "Re-enabled IPv6 (automatic) for \"$ripv6_service\""       \
							"Error happened while trying to re-enable IPv6 (automatic)" \
							/usr/sbin/networksetup -setv6automatic "$ripv6_service"
		fi
    done
}

##########################################################################################
flushDNSCache()
{
    if ${ARG_FLUSH_DNS_CACHE} ; then
		if [ -f /usr/bin/dscacheutil ] ; then
			execute_command "Flushed the DNS cache with dscacheutil -flushcache" \
							"Error happened while trying to flush the DNS cache" \
							/usr/bin/dscacheutil -flushcache

		else
			logMessage "WARNING: /usr/bin/dscacheutil not present. Not flushing the DNS cache via dscacheutil"
		fi

		if [ -f /usr/sbin/discoveryutil ] ; then

			execute_command "Flushed the DNS cache with discoveryutil udnsflushcaches" \
							"Error happened while trying to flush the DNS cache" \
							/usr/sbin/discoveryutil udnsflushcaches

			execute_command "Flushed the DNS cache with discoveryutil mdnsflushcache" \
							"Error happened while trying to flush the DNS cache" \
							/usr/sbin/discoveryutil mdnsflushcache

		else
			logMessage "/usr/sbin/discoveryutil not present. Not flushing the DNS cache via discoveryutil"
		fi

		if [ "$( pgrep HandsOffDaemon )" = "" ] ; then
			if [ -f /usr/bin/killall ] ; then
				if /usr/bin/killall -HUP mDNSResponder > /dev/null 2>&1 ; then
					logMessage "Notified mDNSResponder that the DNS cache was flushed"
				else
					logMessage "Not notifying mDNSResponder that the DNS cache was flushed because it is not running"
				fi
				if /usr/bin/killall -HUP mDNSResponderHelper > /dev/null 2>&1 ; then
					logMessage "Notified mDNSResponderHelper that the DNS cache was flushed"
				else
					logMessage "Not notifying mDNSResponderHelper that the DNS cache was flushed because it is not running"
				fi
			else
				logMessage "WARNING: /usr/bin/killall not present. Not notifying mDNSResponder or mDNSResponderHelper that the DNS cache was flushed"
			fi
		else
			logMessage "WARNING: Hands Off is running.  Not notifying mDNSResponder or mDNSResponderHelper that the DNS cache was flushed"
		fi
    fi
}

##########################################################################################
# @param Bool true if should reset if disconnect was expected
# @param Bool true if should reset if disconnect was not expected

resetPrimaryInterface()
{

	local should_reset="$2"
	local expected_folder_path="/Library/Application Support/Tunnelblick/expect-disconnect"
	if [ -e "$expected_folder_path/ALL" ] ; then
		should_reset="$1"
	else
		logMessage "$expected_folder_path/ALL does not exist"
		local filename ; filename="$( echo "${TUNNELBLICK_CONFIG_FOLDER}" | sed -e 's/-/--/g' | sed -e 's/\./-D/g' | sed -e 's/\//-S/g' )"
		if [ -e "$expected_folder_path/$filename" ]; then
			rm -f "$expected_folder_path/$filename"
			should_reset="$1"
		fi
	fi

	if [ "$should_reset" != "true" ] ; then
		return
	fi

	local wifi_interface
	wifi_interface="$(/usr/sbin/networksetup -listallhardwareports | awk '$3=="Wi-Fi" {getline; print $2}')"
	if [ "${wifi_interface}" == "" ] ; then
		wifi_interface="$(/usr/sbin/networksetup -listallhardwareports | awk '$3=="AirPort" {getline; print $2}')"
	fi
	local primary_interface
	primary_interface="$( scutil <<-EOF |
		open
		show State:/Network/Global/IPv4
		quit
EOF
		grep PrimaryInterface | sed -e 's/.*PrimaryInterface : //' )"

    if [ "${primary_interface}" != "" ] ; then
	    if [ "${primary_interface}" == "${wifi_interface}" ] && [ -f /usr/sbin/networksetup ] ; then

			execute_command "Turned off primary interface with networksetup -setairportpower \"${primary_interface}\" off" \
							"Error happened while trying to turn off primary interface" \
							/usr/sbin/networksetup -setairportpower "${primary_interface}" off

			sleep 2

			execute_command "Turned on primary interface with networksetup -setairportpower \"${primary_interface}\" on" \
							"Error happened while trying to turn on primary interface" \
							/usr/sbin/networksetup -setairportpower "${primary_interface}" on

		else
		    if [ -f /sbin/ifconfig ] ; then
				execute_command "Turned off primary interface with ifconfig \"${primary_interface}\" down" \
								"Error happened while trying to turn off primary interface" \
								/sbin/ifconfig "${primary_interface}" down

                sleep 2

				execute_command "Turned on primary interface with ifconfig \"${primary_interface}\" down" \
								"Error happened while trying to turn on primary interface" \
								/sbin/ifconfig "${primary_interface}" up
			else
				logMessage "WARNING: Not resetting primary interface via ifconfig because /sbin/ifconfig does not exist."
			fi

			if [ -f /usr/sbin/networksetup ] ; then
				local service; service="$( /usr/sbin/networksetup -listnetworkserviceorder | grep "Device: ${primary_interface}" | sed -e 's/^(Hardware Port: //g' | sed -e 's/, Device.*//g' )"
				local status=$?
				if [ $status -ne 0 ] ; then
					logMessage "ERROR: status $status trying to get name of primary service for \"Device: ${primary_interface}\""
				fi
				if [ "$service" != "" ] ; then
					execute_command "Turned off primary interface '${primary_interface}' with networksetup" \
									"Error happened while trying to turn off primary interface" \
									/usr/sbin/networksetup -setnetworkserviceenabled "$service" off

					sleep 2

					execute_command "Turned on primary interface '${primary_interface}' with networksetup" \
									"Error happened while trying to turn on primary interface" \
									/usr/sbin/networksetup -setnetworkserviceenabled "$service" on
				else
					logMessage "ERROR: Not resetting primary service via networksetup because could not find primary service."
				fi
			else
				logMessage "ERROR: Not resetting primary service '$service' via networksetup because /usr/sbin/networksetup does not exist."
			fi
		fi
    else
        logMessage "WARNING: Not resetting primary interface because it cannot be found."
    fi
}

##########################################################################################
trap "" TSTP
trap "" HUP
trap "" INT
export PATH="/bin:/sbin:/usr/sbin:/usr/bin"

readonly LF="
"

readonly OUR_NAME=$(basename "${0}")

rm -f "/Library/Application Support/Tunnelblick/DownLog.txt"

logMessage "**********************************************"
logMessage "Start of output from ${OUR_NAME}"

rm -f "/Library/Application Support/Tunnelblick/downscript-needs-to-be-run.txt"

# Test for the "-r" Tunnelbick option (Reset primary interface after disconnecting) because we _always_ need its value.
# Usually we get the value for that option (and the other options) from State:/Network/OpenVPN,
# but that key may not exist (because, for example, there were no DNS changes).
# So we get the value from the Tunnelblick options passed to this script by OpenVPN.
#
# We do the same thing for the -f Tunnelblick option (Flush DNS cache after connecting or disconnecting)
ARG_RESET_PRIMARY_INTERFACE_ON_DISCONNECT="false"
ARG_RESET_PRIMARY_INTERFACE_ON_DISCONNECT_UNEXPECTED="false"
ARG_FLUSH_DNS_CACHE="false"
while [ $# -ne 0 ] ; do

	if [ "${1:0:1}" != "-" ] ; then				# Tunnelblick arguments start with "-" and come first
        break                                   # so if this one doesn't start with "-" we are done processing Tunnelblick arguments
    fi

	if [ "$1" = "-r" ] ; then
        ARG_RESET_PRIMARY_INTERFACE_ON_DISCONNECT="true"

	elif [ "$1" = "-ru" ] ; then
		ARG_RESET_PRIMARY_INTERFACE_ON_DISCONNECT_UNEXPECTED="true"

	elif [ "$1" = "-f" ] ; then
		ARG_FLUSH_DNS_CACHE="true"
    fi

	if [ "${1:0:1}" = "-" ] ; then				# Shift out Tunnelblick arguments (they start with "-") that we don't understand
		shift									# so the rest of the script sees only the OpenVPN arguments
	else
		break
	fi
done

# Remember the OpenVPN arguments this script was started with so that run_prefix_or_suffix can pass them on to 'up-prefix.sh' and 'up-suffix.sh'
declare -a SCRIPT_ARGS
SCRIPT_ARGS_COUNT=$#
for ((SCRIPT_ARGS_INDEX=0; SCRIPT_ARGS_INDEX<SCRIPT_ARGS_COUNT; ++SCRIPT_ARGS_INDEX)) ; do
	SCRIPT_ARG="$(printf "%q" "$1")"
	SCRIPT_ARGS[$SCRIPT_ARGS_INDEX]="$(printf "%q" "$SCRIPT_ARG")"
	shift
done

readonly ARG_DISABLE_INTERNET_ACCESS_AFTER_DISCONNECTING ARG_DISABLE_INTERNET_ACCESS_AFTER_DISCONNECTING_UNEXPECTED ARG_FLUSH_DNS_CACHE SCRIPT_ARGS

run_prefix_or_suffix 'down-prefix.sh'

# Quick check - is the configuration there?
if ! scutil -w State:/Network/OpenVPN &>/dev/null -t 1 ; then
	# Configuration isn't there
    logMessage "WARNING: Not restoring DNS settings because no saved Tunnelblick DNS information was found."

	flushDNSCache

	resetPrimaryInterface $ARG_RESET_PRIMARY_INTERFACE_ON_DISCONNECT $ARG_RESET_PRIMARY_INTERFACE_ON_DISCONNECT_UNEXPECTED

    logMessage "End of output from ${OUR_NAME}"
    logMessage "**********************************************"

	run_prefix_or_suffix 'down-suffix.sh'

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
ARG_TAP="$(echo "${TUNNELBLICK_CONFIG}" | grep -i '^[[:space:]]*IsTapInterface :' | sed -e 's/^.*: //g')"
ROUTE_GATEWAY_IS_DHCP="$(echo "${TUNNELBLICK_CONFIG}" | grep -i '^[[:space:]]*RouteGatewayIsDhcp :' | sed -e 's/^.*: //g')"
TAP_DEVICE_HAS_BEEN_SET_NONE="$(echo "${TUNNELBLICK_CONFIG}" | grep -i '^[[:space:]]*TapDeviceHasBeenSetNone :' | sed -e 's/^.*: //g')"
ALSO_USING_SETUP_KEYS="$(echo "${TUNNELBLICK_CONFIG}" | grep -i '^[[:space:]]*bAlsoUsingSetupKeys :' | sed -e 's/^.*: //g')"
TUNNEL_DEVICE="$(echo "${TUNNELBLICK_CONFIG}" | grep -i '^[[:space:]]*TunnelDevice :' | sed -e 's/^.*: //g')"

# Note: '\n' was translated into '\t', so we translate it back (it was done because grep and sed only work with single lines)
readonly sRestoreIpv6Services="$(echo "${TUNNELBLICK_CONFIG}" | grep -i '^[[:space:]]*RestoreIpv6Services :' | sed -e 's/^.*: //g' | tr '\t' '\n')"

# Remove leasewatcher
if ${ARG_MONITOR_NETWORK_CONFIGURATION} ; then
	launchctl unload "${LEASEWATCHER_PLIST_PATH}"
    if ${REMOVE_LEASEWATCHER_PLIST} ; then
        rm -f "${LEASEWATCHER_PLIST_PATH}"
    fi
	logMessage "Cancelled monitoring of system configuration changes"
fi

# Release the DHCP lease on a tap device
if ${ARG_TAP} ; then
	if [ "$ROUTE_GATEWAY_IS_DHCP" == "true" ]; then
        if [ "$TAP_DEVICE_HAS_BEEN_SET_NONE" == "false" ]; then

			# If $dev is not defined, then use $TUNNEL_DEVICE, which was set from $dev by client.up.tunnelblick.sh.
			# $dev is defined by OpenVPN prior to it invoking this script, but it is not defined when this script
			# is invoked from MenuController to clean up when exiting Tunnelblick or when OpenVPN crashed.
			# shellcheck disable=SC2154
			TAP_DHCP_DEVICE="$dev"
            if [ -z "$TAP_DHCP_DEVICE" ]; then
				TAP_DHCP_DEVICE="$TUNNEL_DEVICE"
                if [ -n "$TAP_DHCP_DEVICE" ]; then
                    logMessage "WARNING: \$dev not defined; using TunnelDevice: $TUNNEL_DEVICE"
				fi
			fi
			if [ -n "$TAP_DHCP_DEVICE" ] ; then
				execute_command "Released the DHCP lease" \
								"Error happened trying to release the DHCP lease" \
								/usr/sbin/ipconfig set "$TAP_DHCP_DEVICE" NONE
			else
				logMessage "WARNING: Cannot configure TAP interface to NONE without \$dev or TUNNEL_DEVICE being defined. Device may not have disconnected properly."
			fi
        fi
    fi
fi

# Issue warning if the primary service ID has changed
PSID_CURRENT="$( scutil <<-EOF |
	open
	show State:/Network/Global/IPv4
	quit
EOF
grep 'Service : ' | sed -e 's/.*Service : //' )"
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
	if ${ALSO_USING_SETUP_KEYS} ; then
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
	if ${ALSO_USING_SETUP_KEYS} ; then
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

if [ -e /etc/resolv.conf ] ; then
	new_resolver_contents="$( grep -v '#' < /etc/resolv.conf )"
else
	new_resolver_contents="(unavailable)"
fi
logDebugMessage "DEBUG:"
logDebugMessage "DEBUG: /etc/resolve = ${new_resolver_contents}"

scutil_dns="$( scutil --dns)"
logDebugMessage "DEBUG:"
logDebugMessage "DEBUG: scutil --dns = ${scutil_dns}"
logDebugMessage "DEBUG:"

restore_ipv6 "$IPV6_SERVICES_TO_RESTORE"

flushDNSCache

# Ignore errors trying to delete items in the system configuration database.
# They won't exist if the computer shut down or restarted while the VPN was connected.
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

resetPrimaryInterface "$ARG_RESET_PRIMARY_INTERFACE_ON_DISCONNECT" "$ARG_RESET_PRIMARY_INTERFACE_ON_DISCONNECT_UNEXPECTED"

run_prefix_or_suffix 'down-suffix.sh'

logMessage "End of output from ${OUR_NAME}"
logMessage "**********************************************"
