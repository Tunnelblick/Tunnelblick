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
# ******************************************************************************

do_log_rollover() {

	# Copy the log to DownLog.previous.txt and clear the log

	cp -p -f "/Library/Application Support/Tunnelblick/DownLog.txt" \
			 "/Library/Application Support/Tunnelblick/DownLog.previous.txt"
	rm -f "/Library/Application Support/Tunnelblick/DownLog.txt"
}

log_message_no_header() {

# @param String message - The message to log

	echo "${@}" | tee -a "/Library/Application Support/Tunnelblick/DownLog.txt"
}

log_message() {

# @param String message - The message to log

	log_message_no_header "$( date -j +'%H:%M:%S' ) *Tunnelblick: " "${@}"
}

log_message_if_nonzero() {

# @param Number - The number to test
# @param String message - The message to log

	if [ "$1" -ne 0 ] ; then
		shift
		log_message "${@}"
	fi
}

log_debug_message() {

# @param String message - The message to log

	if $ARG_EXTRA_LOGGING ; then
		if [ -z "$1" ] ; then
			log_message ''
		else
			log_message "_________ " "${@}"
		fi
	fi
}

profile_or_execute() {

	# If debugging, profiles a command by running it and printing the elapsed, user CPU, and system CPU times
	# Otherwise, executes the command and prints a status message if the returned status was not zero.
	#
	# Used to profile the outermost subroutines

	if $ARG_EXTRA_LOGGING ; then
		{ time "${@}" > "/Library/Application Support/Tunnelblick/tunnelblick_profile_or_execute_1.txt" 2>&1 ; } 2> "/Library/Application Support/Tunnelblick/tunnelblick_profile_or_execute_2.txt"
		local status=$?

		local main ; main="$( cat "/Library/Application Support/Tunnelblick/tunnelblick_profile_or_execute_1.txt"  )"

		local real ; real="$( grep 'real' < "/Library/Application Support/Tunnelblick/tunnelblick_profile_or_execute_2.txt" )"
		real="${real/real	/}"
		real="${real/0m/}"
		real="${real/s/}"

		local user ; user="$( grep 'user' < "/Library/Application Support/Tunnelblick/tunnelblick_profile_or_execute_2.txt" )"
		user="${user/user	/}"
		user="${user/0m/}"
		user="${user/s/}"

		local sys ; sys="$(   grep 'sys' < "/Library/Application Support/Tunnelblick/tunnelblick_profile_or_execute_2.txt" )"
		sys="${sys/sys	/}"
		sys="${sys/0m/}"
		sys="${sys/s/}"

		rm -f "/Library/Application Support/Tunnelblick/tunnelblick_profile_or_execute_1.txt" \
              "/Library/Application Support/Tunnelblick/tunnelblick_profile_or_execute_2.txt"

		if [ -n "$main" ] ; then
			log_message_no_header "$main"
		fi

		log_debug_message "$real elapsed  $user user  $sys system for " "${@}"

	else
		"${@}"
		local status=$?
	fi

	if [ $status -ne 0 ] ; then
		log_message "ERROR: status = $status from " "${@}"
	fi

	return $status
}

execute_command() {

	# Executes a command with its arguments, printing an optional success or failure message.
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

	"${@}"
	local status=$?

	if [ $status -eq 0 ] ; then
		if [ -n "$success_msg" ] ; then
			log_message "$success_msg"
		fi
	else
		log_message "ERROR: status = $status from " "${@}"
		if [ -n "$failure_msg" ] ; then
			log_message "$failure_msg"
		fi
	fi

	return $status
}

run_prefix_or_suffix() {

# @param String 'down-prefix.sh' or 'down-suffix.sh'
#
# Execute the specified script (if it exists) in a subshell with the arguments with which this script was called.
#
# Tunnelblick starts OpenVPN with --set-env TUNNELBLICK_CONFIG_FOLDER <PATH>
# where <PATH> is the path to the folder containing the OpenVPN configuration file.
# That folder is where the script will be (if it exists).

	if [  -z "$TUNNELBLICK_CONFIG_FOLDER" ] ; then
		log_message "ERROR: 'TUNNELBLICK_CONFIG_FOLDER' is missing or empty"
		return
	fi

	if [ "$1" != "down-prefix.sh" ] && [ "$1" != "down-suffix.sh" ] ; then
		log_message "ERROR: run_prefix_or_suffix not called with 'down-prefix.sh' or 'down-suffix.sh'"
		return
	fi

	if [ -e "$TUNNELBLICK_CONFIG_FOLDER/$1" ] ; then
		log_message "---------- Start of output from $1"

		# shellcheck disable=SC2086
		(  "$TUNNELBLICK_CONFIG_FOLDER/$1" ${ARGS_FROM_OPENVPN[*]}  )
		local status=$?

		log_message "---------- End of output from $1"

		if [ $status -ne 0 ] ; then
			log_message "ERROR: status = $status from $1"
			return
		fi
	fi
}

get_info_saved_by_up_script() {

	# Sets GLOBALS from info saved by the 'up' script in State:/Network/OpenVPN

	# The info will not be available if we are not monitoring for network changes or are
	# shutting down or restarting the computer.
	#
	# THIS ROUTINE MAY EXIT THE SCRIPT IF NO INFO WAS FOUND.

	if ! scutil -w State:/Network/OpenVPN &>/dev/null -t 1 ; then
		log_message "WARNING: Not restoring network settings because no saved Tunnelblick DNS information was found."

		if [ -e "/Library/Application Support/Tunnelblick/shutting-down-computer.txt" ] ; then
			log_message "WARNING: Not flushing DNS or resetting the primary interface because the computer is shutting down."
		else
			flushDNSCache
			resetPrimaryInterface
		fi

		log_message "End of output from ${OUR_NAME}"
		log_message "**********************************************"

		run_prefix_or_suffix 'down-suffix.sh'

		exit 0
	fi

	# Get info saved by the up script
	local saved_info; saved_info="$( scutil <<-EOF
		open
		show State:/Network/OpenVPN
		quit
EOF
		)"

	readonly MADE_DNS_CHANGES="$(             get_item "$saved_info" '^[[:space:]]*madeDnsChanges :'          )"
	readonly INHIBIT_NETWORK_MONITORING="$(   get_item "$saved_info" '^[[:space:]]*inhibitNetworkMonitoring :')"

	readonly LEASEWATCHER_PLIST_PATH="$(      get_item "$saved_info" '^[[:space:]]*LeaseWatcherPlistPath :'   )"
	readonly REMOVE_LEASEWATCHER_PLIST="$(    get_item "$saved_info" '^[[:space:]]*RemoveLeaseWatcherPlist :' )"
	readonly PSID="$(                         get_item "$saved_info" '^[[:space:]]*Service :'                 )"
	readonly ROUTE_GATEWAY_IS_DHCP="$(        get_item "$saved_info" '^[[:space:]]*RouteGatewayIsDhcp :'      )"
	readonly TAP_DEVICE_HAS_BEEN_SET_NONE="$( get_item "$saved_info" '^[[:space:]]*TapDeviceHasBeenSetNone :' )"
	readonly ALSO_USING_SETUP_KEYS="$(        get_item "$saved_info" '^[[:space:]]*bAlsoUsingSetupKeys :'     )"
	readonly TUNNEL_DEVICE="$(                get_item "$saved_info" '^[[:space:]]*TunnelDevice :'            )"

	# Note: '\n' was translated into '\t' by the 'up' script before storing 'RestoreIpv6Services' and 'RestoreSecondaryServices', so we translate it back
	local tmp ; tmp="$(                       get_item "$saved_info" '^[[:space:]]*RestoreIpv6Services :'     )"
	readonly IPV6_SERVICES_TO_RESTORE="$( echo "${tmp#*: /}" | tr '\t' '\n' )"
	tmp="$(                                   get_item "$saved_info" '^[[:space:]]*RestoreSecondaryServices :'     )"
	readonly SECONDARY_SERVICES_TO_RESTORE="$( echo "${tmp#*: /}" | tr '\t' '\n' )"

    message=">>>>>>>>>>Set by get_info_saved_by_up_script():$LF"
    message="${message}MADE_DNS_CHANGES              = '$MADE_DNS_CHANGES'$LF"
    message="${message}INHIBIT_NETWORK_MONITORING    = '$INHIBIT_NETWORK_MONITORING'$LF"
    message="${message}LEASEWATCHER_PLIST_PATH       = '$LEASEWATCHER_PLIST_PATH'$LF"
    message="${message}REMOVE_LEASEWATCHER_PLIST     = '$REMOVE_LEASEWATCHER_PLIST'$LF"
    message="${message}PSID                          = '$PSID'$LF"
    message="${message}ROUTE_GATEWAY_IS_DHCP         = '$ROUTE_GATEWAY_IS_DHCP'$LF"
    message="${message}TAP_DEVICE_HAS_BEEN_SET_NONE  = '$TAP_DEVICE_HAS_BEEN_SET_NONE'$LF"
    message="${message}ALSO_USING_SETUP_KEYS         = '$ALSO_USING_SETUP_KEYS'$LF"
    message="${message}TUNNEL_DEVICE                 = '$TUNNEL_DEVICE'$LF"
    message="${message}SECONDARY_SERVICES_TO_RESTORE = '$SECONDARY_SERVICES_TO_RESTORE'"
    message="${message}IPV6_SERVICES_TO_RESTORE      = '$IPV6_SERVICES_TO_RESTORE'$LF"

    log_debug_message "$message"
}

get_item() {

	# Extracts one item from
	#
	#	$1 = info from State:/Network/OpenVPN
	#	$2 = pattern for grep to extract line with the desired item from the info

	local tmp
	tmp="$( echo "$1" | grep -i "$2" )"
	echo "${tmp#* : }"
}

get_primary_service_id_and_warn_if_it_changed() {

	local ipv4 ; ipv4="$( scutil <<-EOF |
		open
		show State:/Network/Global/IPv4
		quit
EOF
		grep 'Service : ' )"
	local current_psid="${ipv4##* : }"
	if [ "${PSID}" != "${current_psid}" ] ; then
		log_message "Ignoring change of Network Primary Service from ${PSID} to ${current_psid}"
	fi
}

remove_leasewatcher() {

    if [ "$INHIBIT_NETWORK_MONITORING" = "true" ] ; then
        log_message "INHIBIT_NETWORK_MONITORING is true, so not removing leasewatcher"
        return 0
    fi

    log_debug_message "Removing network monitoring because INHIBIT_NETWORK_MONITORING = '$INHIBIT_NETWORK_MONITORING'"

	if $ARG_MONITOR_NETWORK_CONFIGURATION ; then

		execute_command "Cancelled monitoring system configuration changes"       \
						"Error happened while trying to cancel monitoring system configuration changes" \
						launchctl unload "${LEASEWATCHER_PLIST_PATH}"

		if $REMOVE_LEASEWATCHER_PLIST ; then
			execute_command ""       \
							"Error happened while trying to remove $LEASEWATCHER_PLIST_PATH" \
							rm -f "$LEASEWATCHER_PLIST_PATH"
		fi
	fi
}

release_dhcp() {

	if ${ARG_TAP} ; then
		if [ "$ROUTE_GATEWAY_IS_DHCP" == true ] \
		&& [ "$TAP_DEVICE_HAS_BEEN_SET_NONE" == "false" ]; then

			# If $dev is not defined, use $TUNNEL_DEVICE, which was set from $dev by client.up.tunnelblick.sh.
			# $dev is defined by OpenVPN prior to it invoking this script, but it is not defined when this script
			# is invoked from MenuController to clean up when exiting Tunnelblick or when OpenVPN crashed.
			# shellcheck disable=SC2154
			local tap_dhcp_device="$dev"
			if [ -z "$tap_dhcp_device" ]; then
				tap_dhcp_device="$TUNNEL_DEVICE"
				if [ -n "$tap_dhcp_device" ]; then
					log_debug_message "WARNING: \$dev not defined; using TunnelDevice: $TUNNEL_DEVICE"
				fi
			fi
			if [ -n "$tap_dhcp_device" ] ; then
				execute_command "Released the DHCP lease" \
								"Error happened trying to release the DHCP lease" \
								/usr/sbin/ipconfig set "$tap_dhcp_device" NONE
			else
				log_message "WARNING: Cannot release the TAP DHCP lease without \$dev or \$TUNNEL_DEVICE being defined."
			fi
		fi
	fi
}

restore_network_settings() {

    if [ "$MADE_DNS_CHANGES" = "false" ] ; then
        log_message "MADE_DNS_CHANGES is false, so not restoring network_settings"
        return 0
    fi

    log_debug_message "Restoring network settings because MADE_DNS_CHANGES = '$MADE_DNS_CHANGES'"

	local no_such_key="<dictionary> {
  TunnelblickNoSuchKey : true
}"

	local dns_old ; dns_old="$( scutil <<-EOF
		open
		show State:/Network/OpenVPN/OldDNS
		quit
EOF
	)"
	local status=$?
	log_message_if_nonzero $status "ERROR: status = $status trying to read State:/Network/OpenVPN/OldDNS"

	local smb_old ; smb_old="$( scutil <<-EOF
		open
		show State:/Network/OpenVPN/OldSMB
		quit
EOF
	)"
	local status=$?
	log_message_if_nonzero $status "ERROR: status = $status trying to read State:/Network/OpenVPN/OldSMB"

	if [ "${dns_old}" = "${no_such_key}" ] ; then
		execute_command "Removed State:DNS" \
						"Error happened while trying to remove State:DNS" \
						scutil <<-EOF
							open
							remove State:/Network/Service/${PSID}/DNS
							quit
EOF
	else
		execute_command "Restored State:DNS" \
						"Error happened while trying to restore State:DNS" \
						scutil <<-EOF
							open
							get State:/Network/OpenVPN/OldDNS
							set State:/Network/Service/${PSID}/DNS
							quit
EOF
	fi

	if ${ALSO_USING_SETUP_KEYS} ; then
		local dns_old_setup ; dns_old_setup="$( scutil <<-EOF
			open
			show State:/Network/OpenVPN/OldDNSSetup
			quit
EOF
		)"
		local status=$?
		log_message_if_nonzero $status "ERROR: status = $status trying to read State:/Network/OpenVPN/OldDNSSetup"

		if [ "${dns_old_setup}" = "${no_such_key}" ] ; then
			execute_command "Removed Setup:DNS" \
							"Error happened while trying to remove Setup:DNS" \
							scutil <<-EOF
								open
								remove Setup:/Network/Service/${PSID}/DNS
								quit
EOF
		else
			execute_command "Restored Setup:DNS" \
							"Error happened while trying to restore Setup:DNS" \
							scutil <<-EOF
								open
								get State:/Network/OpenVPN/OldDNSSetup
								set Setup:/Network/Service/${PSID}/DNS
								quit
	EOF
		fi
	else
		log_debug_message "Not restoring Setup:DNS"
	fi

	if [ "${smb_old}" = "${no_such_key}" ] ; then
		execute_command "Removed State:SMB" \
						"Error happened while trying to remove State:SMB" \
						scutil > /dev/null <<-EOF
							open
							remove State:/Network/Service/${PSID}/SMB
							quit
EOF
	else
		execute_command "Restored State:SMB" \
						"Error happened while trying to restore State:SMB" \
						scutil > /dev/null <<-EOF
							open
							get State:/Network/OpenVPN/OldSMB
							set State:/Network/Service/${PSID}/SMB
							quit
EOF
	fi

	log_message "Restored DNS and SMB settings"
}

restore_ipv6() {

    # Undoes the actions performed by the disable_ipv6() routine in client.up.tunnelblick.sh by restoring
    # the IPv6 'automatic' setting for each network service for which that routine disabled IPv6.
    #
    # $IPV6_SERVICES_TO_RESTORE must contain the output from disable_ipv6() -- the list of network
	# services for whom IPv6 was disabled.

    if [ -z "$IPV6_SERVICES_TO_RESTORE" ] ; then
		log_debug_message "No IPv6 settings to be restored"
        return
    fi

	local ripv6_service

	printf %s "$IPV6_SERVICES_TO_RESTORE$LF" | \
	while IFS= read -r ripv6_service ; do
		if [ -n "$ripv6_service" ] ; then
			execute_command "Re-enabled IPv6 (automatic) for \"$ripv6_service\""       \
							"Error happened while trying to re-enable IPv6 (automatic)" \
							/usr/sbin/networksetup -setv6automatic "$ripv6_service"
		fi
    done
}

restore_disabled_network_services() {

    # Undoes the actions performed by the disable_secondary_network_services() routine in client.up.tunnelblick.sh by enabling
    # each network service which that routine disabled.
    #
    # $SECONDARY_SERVICES_TO_RESTORE must contain the output from disable_secondary_network_services() -- the list of network
	# services which were disabled.

    if [ -z "$SECONDARY_SERVICES_TO_RESTORE" ] ; then
		log_debug_message "No secondary services to be restored"
        return
    fi

	local service

	printf %s "$SECONDARY_SERVICES_TO_RESTORE$LF" | \
	while IFS= read -r service ; do
		if [ -n "$service" ] ; then
			execute_command "Re-enabled \"$service\""       \
							"Error happened while trying to re-enable network service \"$service\"" \
							/usr/sbin/networksetup -setnetworkserviceenabled "$service" on
		fi
    done
}

debug_log_current_network_settings() {

	if $ARG_EXTRA_LOGGING ; then
		local new_resolver_contents
		if [ -e /etc/resolv.conf ] ; then
			new_resolver_contents="$( grep -v '#' < /etc/resolv.conf )"
		else
			new_resolver_contents="(unavailable)"
		fi

		log_debug_message ''
		log_debug_message "/etc/resolve AFTER CHANGES:$LF${new_resolver_contents}"

		scutil_dns="$( scutil --dns )"
		log_debug_message ''
		log_debug_message "scutil --dns AFTER CHANGES$LF${scutil_dns}"
		log_debug_message ''
	fi
}

flushDNSCache() {

    if ${ARG_FLUSH_DNS_CACHE} ; then
		if [ -f /usr/bin/dscacheutil ] ; then
			execute_command "Flushed the DNS cache with dscacheutil -flushcache" \
							"Error happened while trying to flush the DNS cache" \
							/usr/bin/dscacheutil -flushcache
		else
			log_message "WARNING: /usr/bin/dscacheutil not present. Not flushing the DNS cache via dscacheutil"
		fi

		if [ -f /usr/sbin/discoveryutil ] ; then
			execute_command "Flushed the DNS cache with discoveryutil udnsflushcaches" \
							"Error happened while trying to flush the DNS cache" \
							/usr/sbin/discoveryutil udnsflushcaches
			execute_command "Flushed the DNS cache with discoveryutil mdnsflushcache" \
							"Error happened while trying to flush the DNS cache" \
							/usr/sbin/discoveryutil mdnsflushcache
		else
			log_debug_message "/usr/sbin/discoveryutil not present. Not flushing the DNS cache via discoveryutil"
		fi

		if [ -z "$( pgrep HandsOffDaemon )" ] ; then
			if [ -f /usr/bin/killall ] ; then
				if /usr/bin/killall -HUP mDNSResponder > /dev/null 2>&1 ; then
					log_message "Notified mDNSResponder that the DNS cache was flushed"
				else
					log_debug_message "Not notifying mDNSResponder that the DNS cache was flushed because it is not running"
				fi
				if /usr/bin/killall -HUP mDNSResponderHelper > /dev/null 2>&1 ; then
					log_message "Notified mDNSResponderHelper that the DNS cache was flushed"
				else
					log_debug_message "Not notifying mDNSResponderHelper that the DNS cache was flushed because it is not running"
				fi
			else
				log_message "WARNING: /usr/bin/killall not present. Not notifying mDNSResponder or mDNSResponderHelper that the DNS cache was flushed"
			fi
		else
			log_message "WARNING: Hands Off is running.  Not notifying mDNSResponder or mDNSResponderHelper that the DNS cache was flushed"
		fi
    fi
}

resetPrimaryInterface() {

	local should_reset="$ARG_RESET_PRIMARY_INTERFACE_ON_DISCONNECT_UNEXPECTED"
	local expected_folder_path="/Library/Application Support/Tunnelblick/expect-disconnect"
	if [ -e "$expected_folder_path/ALL" ] ; then
		should_reset="$ARG_RESET_PRIMARY_INTERFACE_ON_DISCONNECT"
	else
		# "Encode" config path so it can be used as a filename by replacing - with --, . with -D, and / with -S
		local filename="${TUNNELBLICK_CONFIG_FOLDER//-/--}"
		filename="${filename//./-D}"
		filename="${filename//\//-S}"
		if [ -e "$expected_folder_path/$filename" ]; then
			rm -f "$expected_folder_path/$filename"
			should_reset="$ARG_RESET_PRIMARY_INTERFACE_ON_DISCONNECT"
		fi
	fi

	if [ "$should_reset" != true ] ; then
		return
	fi

	local wifi_interface
	wifi_interface="$(/usr/sbin/networksetup -listallhardwareports | awk '$3=="Wi-Fi" {getline; print $2}')"
	if [ -z "${wifi_interface}" ] ; then
		wifi_interface="$(/usr/sbin/networksetup -listallhardwareports | awk '$3=="AirPort" {getline; print $2}')"
	fi
	local ipv4; ipv4="$( scutil <<-EOF |
		open
		show State:/Network/Global/IPv4
		quit
EOF
		grep PrimaryInterface )"
	local primary_interface="${ipv4##* : }"

    if [ -n "${primary_interface}" ] ; then
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

				execute_command "Turned on primary interface with ifconfig \"${primary_interface}\" up" \
								"Error happened while trying to turn on primary interface" \
								/sbin/ifconfig "${primary_interface}" up
			else
				log_message "WARNING: Not resetting primary interface via ifconfig because /sbin/ifconfig does not exist."
			fi

			if [ -f /usr/sbin/networksetup ] ; then
				local primary_interface_service_info; primary_interface_service_info="$( /usr/sbin/networksetup -listnetworkserviceorder | grep "Device: ${primary_interface}" )"
				local service="${primary_interface_service_info#*Hardware Port: }"
				service="${service%%, Device: *}"

				local status=$?
				log_message_if_nonzero $status "ERROR: status $status trying to get name of primary service for \"Device: ${primary_interface}\""
				if [ $status = 0 ] \
				&& [ -n "$service" ] ; then
					execute_command "Turned off primary interface '${primary_interface}' with networksetup" \
									"Error happened while trying to turn off primary interface" \
									/usr/sbin/networksetup -setnetworkserviceenabled "$service" off

					sleep 2

					execute_command "Turned on primary interface '${primary_interface}' with networksetup" \
									"Error happened while trying to turn on primary interface" \
									/usr/sbin/networksetup -setnetworkserviceenabled "$service" on
				else
					log_message "ERROR: Not resetting primary service via networksetup because could not find primary service."
				fi
			else
				log_message "ERROR: Not resetting primary service '$service' via networksetup because /usr/sbin/networksetup does not exist."
			fi
		fi
    else
        log_message "ERROR: Not resetting primary interface because it cannot be found."
    fi
}

remove_system_configuration_items() {

	# Ignore errors trying to delete items in the system configuration database.
	# They won't exist if the computer shut down or restarted while the VPN was connected.

   log_message "Up to six 'No such key' messages may appear next and may be ignored."

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
}

################################################################################
#
# START OF SCRIPT
#
################################################################################

trap "" TSTP
trap "" HUP
trap "" INT
export PATH="/bin:/sbin:/usr/sbin:/usr/bin"

################################################################################
#
# PROCESS ARGUMENTS

# Get options from our command line. We would get these values from State:/Network/OpenVPN, but that key
# may not exist (for example, because there were no DNS changes, or because the system is shutting down).
ARG_TAP=false
ARG_FLUSH_DNS_CACHE=false
ARG_EXTRA_LOGGING=false
ARG_MONITOR_NETWORK_CONFIGURATION=false
ARG_RESET_PRIMARY_INTERFACE_ON_DISCONNECT=false
ARG_RESET_PRIMARY_INTERFACE_ON_DISCONNECT_UNEXPECTED=false

while [ $# -ne 0 ] ; do

	if [ "${1:0:1}" != "-" ] ; then				# Tunnelblick arguments start with "-" and come first
        break                                   # so if this one doesn't start with "-" we are done processing Tunnelblick arguments
    fi

	if   [ "$1" = "-a" ] ; then		ARG_TAP=true

	elif [ "$1" = "-f" ] ; then		ARG_FLUSH_DNS_CACHE=true

	elif [ "$1" = "-l" ] ; then		ARG_EXTRA_LOGGING=true

	elif [ "$1" = "-m" ] ; then		ARG_MONITOR_NETWORK_CONFIGURATION=true

	elif [ "$1" = "-r" ] ; then     ARG_RESET_PRIMARY_INTERFACE_ON_DISCONNECT=true

	elif [ "$1" = "-ru" ] ; then	ARG_RESET_PRIMARY_INTERFACE_ON_DISCONNECT_UNEXPECTED=true

	fi

	if [ "${1:0:1}" = "-" ] ; then				# Shift out Tunnelblick arguments that we don't understand (they start with "-")
		shift									# so only the OpenVPN arguments are left
	fi
done

# Remember the OpenVPN arguments this script was started with so that run_prefix_or_suffix can pass them on to 'down-prefix.sh' and 'down-suffix.sh'
declare -a ARGS_FROM_OPENVPN
SCRIPT_ARGS_COUNT=$#
for ((SCRIPT_ARGS_INDEX=0; SCRIPT_ARGS_INDEX<SCRIPT_ARGS_COUNT; ++SCRIPT_ARGS_INDEX)) ; do
	SCRIPT_ARG="$(printf "%q" "$1")"
	ARGS_FROM_OPENVPN[$SCRIPT_ARGS_INDEX]="$(printf "%q" "$SCRIPT_ARG")"
	shift
done

readonly ARG_TAP
readonly ARG_FLUSH_DNS_CACHE
readonly ARG_EXTRA_LOGGING
readonly ARG_MONITOR_NETWORK_CONFIGURATION
readonly ARG_RESET_PRIMARY_INTERFACE_ON_DISCONNECT
readonly ARG_RESET_PRIMARY_INTERFACE_ON_DISCONNECT_UNEXPECTED
readonly ARGS_FROM_OPENVPN

################################################################################
#
# DO THE WORK OF THIS SCRIPT

readonly LF="
"

do_log_rollover

readonly OUR_NAME=$(basename "${0}")

log_message "**********************************************"
log_message "Start of output from ${OUR_NAME}"

rm -f "/Library/Application Support/Tunnelblick/downscript-needs-to-be-run.txt"

if [ -e "/Library/Application Support/Tunnelblick/shutting-down-computer.txt" ] ; then

	log_message "WARNING: Skipping further processing because the computer is shutting down."
	log_message "         No down-prefix.sh, down-suffix.sh, or post-disconnect.sh scripts were run."

else

	profile_or_execute run_prefix_or_suffix 'down-prefix.sh'

	# Note: The following command will exit this script if the info cannot be accessed
	profile_or_execute get_info_saved_by_up_script

	profile_or_execute get_primary_service_id_and_warn_if_it_changed

	profile_or_execute remove_leasewatcher

	profile_or_execute release_dhcp

	profile_or_execute restore_disabled_network_services

	profile_or_execute restore_network_settings

	profile_or_execute restore_ipv6

	profile_or_execute debug_log_current_network_settings

	profile_or_execute flushDNSCache

	profile_or_execute resetPrimaryInterface

	profile_or_execute remove_system_configuration_items

	profile_or_execute run_prefix_or_suffix 'down-suffix.sh'

	# Remove the files containing info needed to undo network changes if this script is not run to completion (because it was)
	rm -f "/Library/Application Support/Tunnelblick/restore-ipv6.txt" \
          "/Library/Application Support/Tunnelblick/restore-secondary.txt"
fi

log_message "End of output from ${OUR_NAME}"
log_message "**********************************************"
