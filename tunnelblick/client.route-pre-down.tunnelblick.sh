#!/bin/bash -e
# Note: must be bash; uses bash-specific tricks
#
# ******************************************************************************************************************
# This Tunnelblick script does everything! It handles TUN and TAP interfaces, 
# pushed configurations and DHCP leases. :)
# 
# This is the "route-pre-down" version of the script, executed before the connection is closed.
#
# It is a modified version of the "down" script written by Nick Williams
#
# It releases the DHCP lease for any TAP devices.
# It has no effect for TUN devices or TAP devices not using DHCP.
#
# ******************************************************************************************************************

# @param String message - The message to log
logMessage()
{
	echo "${@}"
}

##########################################################################################
disableInternetAccess()
{

# Disables Internet access by powering off Wi-Fi and disabling all other network services.
#
# Appends list of services that were disabled (including Wi-Fi) to a file which is used by
# re-enable-network-services.sh to re-enable network services that were disabled by this script.

	list_path="/Library/Application Support/Tunnelblick/disabled-network-services.txt"

	# Get list of services (remove the first line which contains a heading)
	dia_services="$( networksetup  -listallnetworkservices | sed -e '1,1d')"

	# Go through the list disabling the interface for enabled services
	printf %s "$dia_services
" | \
	while IFS= read -r dia_service ; do

		# If first character of a line is an asterisk, the service is disabled, so we skip it
		if [ "${dia_service:0:1}" != "*" ] ; then

			if [ "$dia_service" = "Wi-Fi" ] ; then
				dia_interface="$(networksetup -listallhardwareports | awk '$3=="Wi-Fi" {getline; print $2}')"
				dia_airport_power="$( networksetup -getairportpower $dia_interface | sed -e 's/^.*: //g' )"
				if [  "$dia_airport_power" = "On"  ] ; then
					networksetup -setairportpower "$dia_interface" off
					logMessage "Turned off $dia_service ($dia_interface)"
					echo -n "\"Wi-Fi\" " >> "$list_path"
				else
					logMessage "$dia_service ($dia_interface) was already off"
				fi
			else
				# (We already know it is enabled from the above)
				networksetup -setnetworkserviceenabled "$dia_service" off
				logMessage "Disabled $dia_service"
				echo -n "\"$dia_service\" " >> "$list_path"
			fi
		fi

	done
}

trap "" TSTP
trap "" HUP
trap "" INT
export PATH="/bin:/sbin:/usr/sbin:/usr/bin"

readonly OUR_NAME=$(basename "${0}")

logMessage "**********************************************"
logMessage "Start of output from ${OUR_NAME}"

# Test for the "-k" Tunnelbick option (Disable Internet access after disconnecting).
# Usually we get the value for that option (and the other options) from State:/Network/OpenVPN,
# but that key may not exist (because, for example, there were no DNS changes).
# So we get the value from the Tunnelblick options passed to this script by OpenVPN.
ARG_DISABLE_INTERNET_ACCESS_AFTER_DISCONNECTING="false"
while [ {$#} ] ; do

	if [ "${1:0:1}" != "-" ] ; then				# Tunnelblick arguments start with "-" and come first
		break                                   # so if this one doesn't start with "-" we are done processing Tunnelblick arguments
	fi

	if [ "$1" = "-k" ] ; then
		ARG_DISABLE_INTERNET_ACCESS_AFTER_DISCONNECTING="true"
	fi


	shift                                       # Shift arguments to examine the next option (if there is one)
done

readonly ARG_DISABLE_INTERNET_ACCESS_AFTER_DISCONNECTING

# Quick check - is the configuration there?
if ! scutil -w State:/Network/OpenVPN &>/dev/null -t 1 ; then

	# Configuration isn't there
	logMessage "WARNING: Not restoring DNS settings because no saved Tunnelblick DNS information was found."

	if ${ARG_DISABLE_INTERNET_ACCESS_AFTER_DISCONNECTING} ; then
		disableInternetAccess
	fi

    logMessage "End of output from ${OUR_NAME}"
    logMessage "**********************************************"
	exit 0
fi

# NOTE: This script does not use any arguments passed to it by OpenVPN, so it doesn't shift Tunnelblick options out of the argument list

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

bRouteGatewayIsDhcp="$(echo "${TUNNELBLICK_CONFIG}" | grep -i '^[[:space:]]*RouteGatewayIsDhcp :' | sed -e 's/^.*: //g')"
sTunnelDevice="$(echo "${TUNNELBLICK_CONFIG}" | grep -i '^[[:space:]]*TunnelDevice :' | sed -e 's/^.*: //g')"

if ${ARG_TAP} ; then
	if [ "$bRouteGatewayIsDhcp" == "true" ]; then
        # Issue warning if the primary service ID has changed
        PSID_CURRENT="$( scutil <<-EOF |
            open
            show State:/Network/OpenVPN
            quit
EOF
grep Service | sed -e 's/.*Service : //'
)"
        if [ "${PSID}" != "${PSID_CURRENT}" ] ; then
            logMessage "WARNING: Ignoring change of Network Primary Service from ${PSID} to ${PSID_CURRENT}"
        fi

        # Remove leasewatcher
        if ${ARG_MONITOR_NETWORK_CONFIGURATION} ; then
            launchctl unload "${LEASEWATCHER_PLIST_PATH}"
            if ${REMOVE_LEASEWATCHER_PLIST} ; then
                rm -f "${LEASEWATCHER_PLIST_PATH}"
            fi
            logMessage "Cancelled monitoring of system configuration changes"
            
            # Indicate leasewatcher has been removed
            scutil <<-EOF
            open
            get State:/Network/OpenVPN
            d.remove MonitorNetwork
            d.add MonitorNetwork        "false"
            set State:/Network/OpenVPN
            quit
EOF
        fi
            
        # Release the DHCP lease
        if [ -z "$dev" ]; then
            # If $dev is not defined, then use TunnelDevice, which was set from $dev by client.up.tunnelblick.sh
            # ($dev is not defined when this script is called from MenuController to clean up when OpenVPN has crashed)
            if [ -n "${sTunnelDevice}" ]; then
                logMessage "ERROR: \$dev not defined; using TunnelDevice: ${sTunnelDevice}"
                set +e
                ipconfig set "${sTunnelDevice}" NONE 2>/dev/null
                set -e
                logMessage "Released the DHCP lease via ipconfig set \"${sTunnelDevice}\" NONE."
            else
                logMessage "WARNING: Cannot release the DHCP lease without \$dev or State:/Network/OpenVPN/TunnelDevice being defined. Device may not have disconnected properly."
            fi
        else
            set +e
            ipconfig set "$dev" NONE 2>/dev/null
            set -e
            logMessage "Released the DHCP lease via ipconfig set \"$dev\" NONE."
        fi

        # Indicate the DHCP lease has been released
        scutil <<-EOF
        open
        get State:/Network/OpenVPN
        d.remove TapDeviceSetNone
        d.add TapDeviceHasBeenSetNone "true"
        set State:/Network/OpenVPN
        quit
EOF
    else
        logMessage "NOTE: No DHCP release by ${OUR_NAME} is needed because this TAP connection does not use DHCP via the TAP device."
	fi
else
    logMessage "No DHCP release by ${OUR_NAME} is needed because this is not a TAP connection."
fi

if ${ARG_DISABLE_INTERNET_ACCESS_AFTER_DISCONNECTING} ; then
	disableInternetAccess
fi

logMessage "End of output from ${OUR_NAME}"
logMessage "**********************************************"
exit 0
