#!/bin/bash -e
# Note: must be bash; uses bash-specific tricks
#
# ******************************************************************************************************************
# This Tunnelblick script does everything! It handles TUN and TAP interfaces,
# pushed configurations, DHCP with DNS and SMB, and renewed DHCP leases. :)
#
# This is the "Up" version of the script, executed after the interface is
# initialized.
#
# Created by: Nick Williams (using original code and parts of old Tblk scripts)
# Modifed by: Jonathan K. Bullard for Mountain Lion
#
# ******************************************************************************************************************


logMessage() {

    # @param String message - The message to log

	echo "$( date -j +'%H:%M:%S' ) *Tunnelblick: " "${@}"
}

logDebugMessage() {

    # @param String message - The message to log
    #
    # If Tunnelblick's "DB-UP" preference is set, extra logging will be done for all configurations.
    #
    # (If the "DB-UP" preference is set, VPNConnection sets the OPENVPNSTART_EXTRA_LOGGING bit;
    #  if tunnelblick-helper sees that bit set, it adds " -l" to OpenVPN's "--up" or "--route-up" commands; and
    #  if this script sees the "-l", it sets ARG_EXTRA_LOGGING to "true")

    if ${ARG_EXTRA_LOGGING} ; then
		if [ -z "$1" ] ; then
			logMessage ''
		else
			logMessage "_________ " "${@}"
		fi
    fi
}

logChange() {

    # log a change to a setting
    # @param String filters - empty, or one or two '#' if not performing the change
    # @param String name of setting that is being changed
    # @param String new value
    # @param String old value

 	if [ "$1" = "" ] ; then
		if [ "$3" = "$4" ] ; then
			logMessage "Did not change $2 setting of '$3' (but re-set it)"
		else
			logMessage "Changed $2 setting from '$4' to '$3'"
		fi
	else
		logMessage "Did not change $2 setting of '$4'"
	fi
}

trim() {

    # @param String string - Content to trim
    #
    # We DO NOT want to double-quote {%@}
    # This should create a set of trimmed strings.
    # shellcheck disable=SC2068

    echo ${@}
}

setGlobal() {

    # @param name of a global variable
    # @param value to set the global variable to

    # When called in a subroutine, sets a global variable to a value.
    # (Normally setting a variable does not affect the global variable's value.)

    export -n "$1=$2"
}

get_networksetup_setting() {

	# Outputs a string with the networksetup setting named $1 for each active network service.
	#
	# This routine is designed to have its output captured by the bash $() construct, but it
	# outputs error and warning messages to stderr.
	#
	# $1 must be either "dnsservers" or "searchdomains". (Those are the only two settings
	#    that can be modified by "networksetup".)
	#
	# The output from this function consists of a line for each active network service.
	# Each entry consists of the following:
	#
	#       <setting> <service name>
	#
	# where <setting> is a comma-separated list of either namserver IP addresses or
	# search domains, with NO SPACES. An empty setting is specified or shown as 'empty'.
	#
	# Note: We do not allow tab characters (HT, ASCII 0x09) in service names or settings
	#		because we replace line-feed characters (LF, ASCII 0x0D) with tabs when
	#		storing the output of this routine in the System Configuration Database.
	#
	#		We also do not allow spaces in settings because we parse the output of
	#		this routine very simply: the first space in a line separates the setting
	#		from the service name.
	#
	# Examples:
	#       get_networksetup_setting   dnsservers
	#       get_networksetup_setting   searchdomains

	if [ "$1" != "dnsservers" ] && [ "$1" != "searchdomains" ] ; then
		echo "ERROR: restore_networksetup_setting: Unknown setting name '$1'" 1>&2
		return;
	fi

	if [ ! -f "/usr/sbin/networksetup" ] ; then
		echo "get_networksetup_setting: networksetup is not in /usr/sbin" 1>&2
		return;
	fi

	# Get list of services and remove the first line which contains a heading
	local services ; services="$( /usr/sbin/networksetup  -listallnetworkservices | sed -e '1,1d' ; true )"

	# Go through the list for enabled services

	local saved_IFS="$IFS"

	printf %s "$services$LF" | \
	while IFS= read -r service ; do

		if [ -n "$service" ] ; then

			# If first character of a line is a *, the service is disabled, so we skip it
			if [ "${service:0:1}" != "*" ] ; then

				# Make sure there are no tabs in the service name
				if [ "$service" != "${service/$HT/}" ] ; then
					echo "get_networksetup_setting: service name '$service' contains one or more tab characters" 1>&2
					exit 1
				fi

				# Get the setting for the service
				local setting ; setting="$(  /usr/sbin/networksetup -get"$1" "$service" ; true )"


				if [ "${setting/There aren/}" = "$setting" ] ; then

					# The setting is returned by networksetup as separate lines, each with one setting (IP address or domain name).

					# Change newlines into commas to get a comma-separated list of settings.
					setting="${setting//$LF/,}"

					# Make sure there are no tabs or spaces in the setting
					# shellcheck disable=SC2252
					if [ "$setting" != "${setting/$HT/}" ] || [ "$setting" != "${setting/ /}" ] ; then
						echo "get_networksetup_setting: setting '$setting' for service '$service' contains spaces or tabs" 1>&2
						exit 1
					fi
				else

					# The output contains "There aren't any..." (settings), so set it to 'empty'
					setting='empty'
				fi

				# Output a line containing the setting and service separated by a single space.
				echo "$setting $service"
			fi
		fi

	done

	IFS="$saved_IFS"
}

run_prefix_or_suffix() {

    # @param String 'up-prefix.sh' or 'up-suffix.sh'
    #
    # Execute the specified script (if it exists) in a subshell with the arguments with which this script was called.
    #
    # Tunnelblick starts OpenVPN with --set-env TUNNELBLICK_CONFIG_FOLDER <PATH>
    # where <PATH> is the path to the folder containing the OpenVPN configuration file.
    # That folder is where the script will be (if it exists).

	if [  -z "$TUNNELBLICK_CONFIG_FOLDER" ] ; then
		logMessage "The 'TUNNELBLICK_CONFIG_FOLDER' environment variable is missing or empty"
		exit 1
	fi

	if [ "$1" != "up-prefix.sh" ] && [ "$1" != "up-suffix.sh" ] ; then
		logMessage "run_prefix_or_suffix not called with 'up-prefix.sh' or 'up-suffix.sh'"
		exit 1
	fi

	if [ -e "$TUNNELBLICK_CONFIG_FOLDER/$1" ] ; then
		logMessage "---------- Start of output from $1"

		set +e
		# We DO NOT want to double-quote SCRIPT_ARGS
		# They should be separate arguments to the script, as they are separate arguments to this script
		# shellcheck disable=SC2086
			(  "$TUNNELBLICK_CONFIG_FOLDER/$1" ${SCRIPT_ARGS[*]}  )
			local status=$?
		set -e

		logMessage "---------- End of output from $1"

		if [ $status -ne 0 ] ; then
			logMessage "ERROR: $1 exited with error status $status"
			exit $status
		fi
	fi
}

disable_ipv6() {

    # Disables IPv6 on each enabled (active) network service on which it is set to the macOS default "IPv6 Automatic".
    #
    # For each such service, outputs a line with the name of the service.
    # (A separate line is output for each name because a name may include spaces.)
    #
    # The 'restore_ipv6' routine in client.down.tunnelblick.sh undoes the actions performed by this routine.
    #
    # NOTE: Done only for enabled services because some versions of macOS enable the service if this IPv6 setting is changed.

    # Get list of services and remove the first line which contains a heading
    local dipv6_services ; dipv6_services="$( /usr/sbin/networksetup  -listallnetworkservices | sed -e '1,1d' ; true)"

    # Go through the list disabling IPv6 for enabled services, and outputting lines with the names of the services
    local dipv6_service
    printf %s "$dipv6_services$LF"  |   while IFS= read -r dipv6_service ; do
		if [ -n "$dipv6_service" ] ; then

			# If first character of a line is an asterisk, the service is disabled, so we skip it
			if [ "${dipv6_service:0:1}" != "*" ] ; then
				dipv6_ipv6_status="$( /usr/sbin/networksetup -getinfo "$dipv6_service" | grep 'IPv6: ' | sed -e 's/IPv6: //')"
				if [ "$dipv6_ipv6_status" = "Automatic" ] ; then
					/usr/sbin/networksetup -setv6off "$dipv6_service"
					echo "$dipv6_service"
				fi
			fi
		fi

    done
}

disable_secondary_network_services() {

    # Disables each enabled (active) network service except the primary service.
    #
    # For each such service, outputs a line with the name of the service.
    # (A separate line is output for each name because a name may include spaces.)
    #
    # The 'restore_disabled_network_services' routine in client.down.tunnelblick.sh undoes the actions performed by this routine.

    # Get list of services and remove the first four lines, which contain a heading and the primary service
    local services ; services="$( /usr/sbin/networksetup  -listnetworkserviceorder | sed -e '1,4d' ; true)"

    # Go through the list disabling each service and outputting a line with the name of the service
    # If first character of a line is an asterisk, the service is disabled, so we skip it

    local service
    printf %s "$services$LF"  |   while IFS= read -r service ; do
		if [ -n "$service" ] \
        && [ "${service:0:9}" != "(Hardware" ] \
		&& [ "${service:0:1}" != "*" ] ; then
            # Remove '(nnn) ' from start of line to get the service name
            service="${service#* }"
            /usr/sbin/networksetup -setnetworkserviceenabled "$service" off
            echo "$service"
		fi
    done
}

get_ServicePorts_and_ServiceNames_from_listnetworkservices() {

    # Sets up two arrays:
    #
    #   $ServiceNames
    #   $ServicePorts
    #
    # with the service name and hardware port of all active network services.
    #
    # The arrays are in the same order as the output from
    #     'networksetup -listnetworkserviceorder'.
    #
    # Sample output from 'networksetup  -listnetworkserviceorder'.
    #    The output consists of a header line followed by a three-line entry for
    #    each network service (the third line is empty).
    #    If the service is disabled, an asterisk will replace the service order number.
    #
    #    =========================================================
    #        An asterisk (*) denotes that a network service is disabled.
    #        (1) USB 10/100/1000 LAN
    #        (Hardware Port: USB 10/100/1000 LAN, Device: en7)
    #
    #        (*) Wi-Fi
    #        (Hardware Port: Wi-Fi, Device: en0)
    #
    #        (3) Thunderbolt Bridge
    #        (Hardware Port: Thunderbolt Bridge, Device: bridge0)
    #
    #        (4) iPhone USB
    #        (Hardware Port: iPhone USB, Device: en12)
    #
    #    =========================================================
    # Get list of network services and remove the first line, which contains the heading
    local services ; services="$( /usr/sbin/networksetup  -listnetworkserviceorder | sed -e '1d' ; true)"

    # Go through the list disabling each service other than the primary service and echoing a line
    # with the name of the service that was disabled.
    # Skip already disabled services.

    local isActive
    local line
    local name
    local port

    while IFS= read -r line ; do

        if [ -n "$line" ] \
        && [ "${line:0:9}" != "(Hardware" ] ; then
            if [ "${line:1:1}" != "*" ] ; then

                # Have the first line of an active service listing, e.g. "(1) USB 10/100/1000 LAN"
                # Assume it is active and extract the service name into
                isActive=true
            else
                isActive=false
            fi

        elif [ -n "$line" ] \
        &&   [ "${line:0:9}" = "(Hardware" ] ; then

            if [ "$isActive" = "true" ] ; then \

                # Have the second line of an active service listing, e.g. "(Hardware Port: USB 10/100/1000 LAN, Device: en7)"

                # Get the service name
                # Remove '(Hardware Port: ' from the start of the line to get the interface name followed by ", Device:..."
                line="${line#*: }"
                # Remove the comma and everything after it
                name="${line%,*}"

                # Get the port
                # Remove everything up to the last ", Device: "
                port="${line##*, Device: }"
                # Remove the ")"
                port="${port%?}"

                ServiceNames+=("$name")
                ServicePorts+=("$port")
            fi

        else
            # Have the third line of a service listing. Must be empty
            if [ -n "$line" ] ; then
                echo "ERROR: output of 'networksetup  -listnetworkserviceorder' not as expected:"
                echo "'$services'"
                exit 1
            fi
        fi

    done <<-EOT
"$services$LF$LF"
EOT
}

get_ServiceStatuses_from_ifconfig() {

    # Sets up the "ServiceStatuses" array, with each element corresponding to the status
    # of an element in the "ServicesPorts" array, with a value of "active" or "inactive".

    # The output of ifconfig should look like the following:
    #       port:...
    #       <tab>info
    #       ...
    #       <tab>info
    #       port:...
    #       <tab>info
    #       ...
    #       <tab>info

    # Go through the output, creating an entry in the "active_interfaces" array for each active interface.
    # The value of the array entry is the name of the port/interface.

    local active_interfaces
    local ifconfig_output
    local line_number
    local line
    local name
    local port
    local status
    local ix

    declare -a active_interfaces

    # Get ifconfig output
    ifconfig_output="$( /sbin/ifconfig ; true)"

    line_number=0
    while IFS= read -r line ; do

        line_number=$((line_number+1))

        if [ -n "$line" ] ; then
            if [ "${line:0:1}" != "$HT" ] ; then
                name="${line%%:*}"
            elif [ "${line:0:15}" = "	status: active" ] ; then
                active_interfaces+=("$name")
            fi
        else
            echo "ERROR: output of 'ifconfig' not as expected (at line $line_number):"
            echo "'$ifconfig_output'"
            exit 1
        fi

    done <<-EOT
"$ifconfig_output$LF"
EOT

    # For each port, set it's status
    for port in "${ServicePorts[@]}" ; do

        status="inactive"
        ix=0
        while [ $ix -lt ${#active_interfaces[@]} ] ; do
            if [ "${active_interfaces[$ix]}" = "$port" ] ; then
                status="active"
                ix=99999
            else
                ix=$((ix+1))
            fi
        done

        ServiceStatuses+=("$status")

    done
}

echo_primary_network_service_name() {

    declare -a ServicePorts
    declare -a ServiceNames
    declare -a ServiceStatuses

    get_ServicePorts_and_ServiceNames_from_listnetworkservices
    get_ServiceStatuses_from_ifconfig

    local ix

    ix=0

    while [ $ix -lt ${#ServicePorts[@]} ] ; do

        if [ "${ServiceStatuses[$ix]}" = "active" ] ; then
            echo "${ServiceNames[$ix]}"
            return
        fi

        ix=$((ix+1))

    done
}

disableIPv6AndSecondaryServices() {

    # Disables IPv6 and secondary services if appropriate.
    # Sets global variables withs encoded lists of the services that were disabled
    #      so they can be restored by the down script.
    # Saves non-encoded lists of the services that were disabled in a file
    #       so they can be restored on shutdown or restart of the computer.

    # Disable IPv6 services if requested and the VPN server address is not an IPv6 address,
    # and create a list of those that were disabled.

    ipv6_disabled_services=""
    if ${ARG_DISABLE_IPV6_ON_TUN} ; then
        trusted_ip_line="$( env | grep 'trusted_ip' ; true )"
        if [ "${trusted_ip_line/:/}" = "$trusted_ip_line" ] ; then
            readonly ipv6_disabled_services="$( disable_ipv6 )"
            if [ "$ipv6_disabled_services" != "" ] ; then
                printf '%s\n' "$ipv6_disabled_services" \
                | while IFS= read -r dipv6_service ; do
                    logMessage "Disabled IPv6 for '$dipv6_service'"
                done
            fi
        else
            trusted_ip="${trusted_ip_line#trusted_ip=}"
            logMessage "WARNING: NOT disabling IPv6 because the OpenVPN server address is an IPv6 address ($trusted_ip)"
        fi
    fi

    # Save an encoded copy of the list in global IPV6_DISABLED_SERVICES_ENCODED so it can be used later
    # Note '\n' is translated into '\t' so it is all on one line, because grep and sed only work with single lines
    setGlobal IPV6_DISABLED_SERVICES_ENCODED "$( echo "$ipv6_disabled_services" | tr '\n' '\t' )"
    readonly  IPV6_DISABLED_SERVICES_ENCODED

    # Save non-encoded list in file for use on shutdown or restart of the computer
    if [ -n  "$ipv6_disabled_services" ] ; then
        echo "$ipv6_disabled_services" > "/Library/Application Support/Tunnelblick/restore-ipv6.txt"
    else
        rm -f "/Library/Application Support/Tunnelblick/restore-ipv6.txt"
    fi

    # Disable secondary services if requested and create a list of those that were disabled
    secondary_disabled_services=""
    if ${ARG_DISABLE_SECONDARY_SERVICES_ON_TUN} ; then
        readonly secondary_disabled_services="$( disable_secondary_network_services )"
        if [ "$secondary_disabled_services" != "" ] ; then
            printf '%s\n' "$secondary_disabled_services" \
            | while IFS= read -r service ; do
                logMessage "Disabled '$service'"
              done
        fi
    fi

    # Save an encoded copy of the list in global SECONDARY_DISABLED_SERVICES_ENCODED so it can be used later
    # Note '\n' is translated into '\t' so it is all on one line, because grep and sed only work with single lines
    setGlobal SECONDARY_DISABLED_SERVICES_ENCODED "$( echo "$secondary_disabled_services" | tr '\n' '\t' )"
    readonly  SECONDARY_DISABLED_SERVICES_ENCODED

    # Save non-encoded list in file for use on shutdown or restart of the computer
	if [ -n "$secondary_disabled_services" ] ; then
		echo "$secondary_disabled_services" > "/Library/Application Support/Tunnelblick/restore-secondary.txt"
    else
        rm -f "/Library/Application Support/Tunnelblick/restore-secondary.txt"
	fi
}

willNotMonitorNetworkConfiguration() {

        logMessage "Will not monitor for network configuration changes."
}

setupToMonitorNetworkConfiguration() {

    if ${ARG_MONITOR_NETWORK_CONFIGURATION} ; then
        if [ "${ARG_IGNORE_OPTION_FLAGS:0:2}" = "-p" ] ; then
            logMessage "Setting up to monitor system configuration with process-network-changes"
        else
            logMessage "Setting up to monitor system configuration with leasewatch"
        fi
        if [ "${LEASEWATCHER_TEMPLATE_PATH}" != "" ] ; then
            sed -e "s|/Applications/Tunnelblick\.app/Contents/Resources|${TB_RESOURCES_PATH}|g" "${LEASEWATCHER_TEMPLATE_PATH}" > "${LEASEWATCHER_PLIST_PATH}"
        fi
        launchctl load "${LEASEWATCHER_PLIST_PATH}"
    else
        willNotMonitorNetworkConfiguration
    fi
}

setDnsServersAndDomainName() {

    # @param String[] dnsServers - The name servers to use
    # @param String domainName - The domain name to use
    # @param \optional String[] winsServers - The SMB servers to use
    # @param \optional String[] searchDomains - The search domains to use
    #
    # Throughout this routine:
    #            MAN_ is a prefix for manually set parameters
    #            DYN_ is a prefix for dynamically set parameters (by a "push", config file, or command line option)
    #            CUR_ is a prefix for the current parameters (as arbitrated by macOS between manual and DHCP data)
    #            FIN_ is a prefix for the parameters we want to end up with
    #            SKP_ is a prefix for an empty string or a "#" used to control execution of statements that set parameters in scutil
    #
    #            DNS_SA is a suffix for the ServerAddresses value in a System Configuration DNS key
    #            DNS_SD is a suffix for the SearchDomains   value in a System Configuration DNS key
    #            DNS_DN is a suffix for the DomainName      value in a System Configuration DNS key
    #
    #            SMB_NN is a suffix for the NetBIOSName   value in a System Configuration SMB key
    #            SMB_WG is a suffix for the Workgroup     value in a System Configuration SMB key
    #            SMB_WA is a suffix for the WINSAddresses value in a System Configuration SMB key
    #
    # So, for example, MAN_SMB_NN is the manually set NetBIOSName value (or the empty string if not set manually)

	set +e # "grep" will return error status (1) if no matches are found, so don't fail on individual errors
		PSID="$( scutil <<-EOF |
			open
			show State:/Network/Global/IPv4
			quit
EOF
grep PrimaryService | sed -e 's/.*PrimaryService : //'
)"

	set -e # resume abort on error

	MAN_DNS_CONFIG="$( scutil <<-EOF |
		open
		show Setup:/Network/Service/${PSID}/DNS
		quit
EOF
sed -e 's/^[[:space:]]*[[:digit:]]* : //g' | tr '\n' ' '
)"

	MAN_SMB_CONFIG="$( scutil <<-EOF |
		open
		show Setup:/Network/Service/${PSID}/SMB
		quit
EOF
sed -e 's/^[[:space:]]*[[:digit:]]* : //g' | tr '\n' ' '
)"
	CUR_DNS_CONFIG="$( scutil <<-EOF |
		open
		show State:/Network/Global/DNS
		quit
EOF
sed -e 's/^[[:space:]]*[[:digit:]]* : //g' | tr '\n' ' '
)"

	CUR_SMB_CONFIG="$( scutil <<-EOF |
		open
		show State:/Network/Global/SMB
		quit
EOF
sed -e 's/^[[:space:]]*[[:digit:]]* : //g' | tr '\n' ' '
)"

# Set up the DYN_... variables to contain what is asked for (dynamically, by a 'push' directive, for example)

	declare -a vDNS=("${!1}")
	declare -a vSMB=("${!3}")
	declare -a vSD=("${!4}")

	if [ ${#vDNS[*]} -eq 0 ] ; then
		readonly DYN_DNS_SA=""
	else
		readonly DYN_DNS_SA="${!1}"
	fi

	if [ ${#vSMB[*]} -eq 0 ] ; then
		readonly DYN_SMB_WA=""
	else
		readonly DYN_SMB_WA="${!3}"
	fi

	if [ ${#vSD[*]} -eq 0 ] ; then
		readonly DYN_DNS_SD=""
	else
		readonly DYN_DNS_SD="${!4}"
	fi

	DYN_DNS_DN="$2"

	# The variables
	#     DYN_SMB_WG
	#     DYN_SMB_NN
	# are left empty. There isn't a way for OpenVPN to set them.
	DYN_SMB_WG=''
	DYN_SMB_NN=''

	logDebugMessage ''
	logDebugMessage "MAN_DNS_CONFIG = ${MAN_DNS_CONFIG}"
	logDebugMessage "MAN_SMB_CONFIG = ${MAN_SMB_CONFIG}"
	logDebugMessage ''
	logDebugMessage "CUR_DNS_CONFIG = ${CUR_DNS_CONFIG}"
	logDebugMessage "CUR_SMB_CONFIG = ${CUR_SMB_CONFIG}"
	logDebugMessage ''
	logDebugMessage ''
	logDebugMessage "DYN_DNS_DN = ${DYN_DNS_DN}; DYN_DNS_SA = ${DYN_DNS_SA}; DYN_DNS_SD = ${DYN_DNS_SD}"
	logDebugMessage "DYN_SMB_NN = ${DYN_SMB_NN}; DYN_SMB_WG = ${DYN_SMB_WG}; DYN_SMB_WA = ${DYN_SMB_WA}"

# Set up the MAN_... variables to contain manual network settings

	set +e # "grep" will return error status (1) if no matches are found, so don't fail on individual errors

		if echo "${MAN_DNS_CONFIG}" | grep -q "DomainName" ; then
			readonly MAN_DNS_DN="$( trim "$( echo "${MAN_DNS_CONFIG}" | sed -e 's/^.*DomainName[^{]*{[[:space:]]*\([^}]*\)[[:space:]]*}.*$/\1/g' )" )"
		else
			readonly MAN_DNS_DN="";
		fi
		if echo "${MAN_DNS_CONFIG}" | grep -q "ServerAddresses" ; then
			readonly MAN_DNS_SA="$( trim "$( echo "${MAN_DNS_CONFIG}" | sed -e 's/^.*ServerAddresses[^{]*{[[:space:]]*\([^}]*\)[[:space:]]*}.*$/\1/g' )" )"
		else
			readonly MAN_DNS_SA="";
		fi
		if echo "${MAN_DNS_CONFIG}" | grep -q "SearchDomains" ; then
			readonly MAN_DNS_SD="$( trim "$( echo "${MAN_DNS_CONFIG}" | sed -e 's/^.*SearchDomains[^{]*{[[:space:]]*\([^}]*\)[[:space:]]*}.*$/\1/g' )" )"
		else
			readonly MAN_DNS_SD="";
		fi
		if echo "${MAN_SMB_CONFIG}" | grep -q "NetBIOSName" ; then
			readonly MAN_SMB_NN="$( trim "$( echo "${MAN_SMB_CONFIG}" | sed -e 's/^.*NetBIOSName : \([^[:space:]]*\).*$/\1/g' )" )"
		else
			readonly MAN_SMB_NN="";
		fi
		if echo "${MAN_SMB_CONFIG}" | grep -q "Workgroup" ; then
			readonly MAN_SMB_WG="$( trim "$( echo "${MAN_SMB_CONFIG}" | sed -e 's/^.*Workgroup : \([^[:space:]]*\).*$/\1/g' )" )"
		else
			readonly MAN_SMB_WG="";
		fi
		if echo "${MAN_SMB_CONFIG}" | grep -q "WINSAddresses" ; then
			readonly MAN_SMB_WA="$( trim "$( echo "${MAN_SMB_CONFIG}" | sed -e 's/^.*WINSAddresses[^{]*{[[:space:]]*\([^}]*\)[[:space:]]*}.*$/\1/g' )" )"
		else
			readonly MAN_SMB_WA="";
		fi

	set -e # resume abort on error

	logDebugMessage ''
	logDebugMessage "MAN_DNS_DN = ${MAN_DNS_DN}; MAN_DNS_SA = ${MAN_DNS_SA}; MAN_DNS_SD = ${MAN_DNS_SD}"
	logDebugMessage "MAN_SMB_NN = ${MAN_SMB_NN}; MAN_SMB_WG = ${MAN_SMB_WG}; MAN_SMB_WA = ${MAN_SMB_WA}"

# Set up the CUR_... variables to contain the current network settings (from manual or DHCP, as arbitrated by macOS

	set +e # "grep" will return error status (1) if no matches are found, so don't fail on individual errors

		if echo "${CUR_DNS_CONFIG}" | grep -q "DomainName" ; then
			readonly CUR_DNS_DN="$(trim "$( echo "${CUR_DNS_CONFIG}" | sed -e 's/^.*DomainName : \([^[:space:]]*\).*$/\1/g' )")"
		else
			readonly CUR_DNS_DN="";
		fi
		if echo "${CUR_DNS_CONFIG}" | grep -q "ServerAddresses" ; then
			readonly CUR_DNS_SA="$(trim "$( echo "${CUR_DNS_CONFIG}" | sed -e 's/^.*ServerAddresses[^{]*{[[:space:]]*\([^}]*\)[[:space:]]*}.*$/\1/g' )")"
		else
			readonly CUR_DNS_SA="";
		fi
		if echo "${CUR_DNS_CONFIG}" | grep -q "SearchDomains" ; then
			readonly CUR_DNS_SD="$(trim "$( echo "${CUR_DNS_CONFIG}" | sed -e 's/^.*SearchDomains[^{]*{[[:space:]]*\([^}]*\)[[:space:]]*}.*$/\1/g' )")"
		else
			readonly CUR_DNS_SD="";
		fi
		if echo "${CUR_SMB_CONFIG}" | grep -q "NetBIOSName" ; then
			readonly CUR_SMB_NN="$(trim "$( echo "${CUR_SMB_CONFIG}" | sed -e 's/^.*NetBIOSName : \([^[:space:]]*\).*$/\1/g' )")"
		else
			readonly CUR_SMB_NN="";
		fi
		if echo "${CUR_SMB_CONFIG}" | grep -q "Workgroup" ; then
			readonly CUR_SMB_WG="$(trim "$( echo "${CUR_SMB_CONFIG}" | sed -e 's/^.*Workgroup : \([^[:space:]]*\).*$/\1/g' )")"
		else
			readonly CUR_SMB_WG="";
		fi
		if echo "${CUR_SMB_CONFIG}" | grep -q "WINSAddresses" ; then
			readonly CUR_SMB_WA="$(trim "$( echo "${CUR_SMB_CONFIG}" | sed -e 's/^.*WINSAddresses[^{]*{[[:space:]]*\([^}]*\)[[:space:]]*}.*$/\1/g' )")"
		else
			readonly CUR_SMB_WA="";
		fi

	set -e # resume abort on error

	logDebugMessage ''
	logDebugMessage "CUR_DNS_DN = ${CUR_DNS_DN}; CUR_DNS_SA = ${CUR_DNS_SA}; CUR_DNS_SD = ${CUR_DNS_SD}"
	logDebugMessage "CUR_SMB_NN = ${CUR_SMB_NN}; CUR_SMB_WG = ${CUR_SMB_WG}; CUR_SMB_WA = ${CUR_SMB_WA}"

# set up the FIN_... variables with what we want to set things to

	# Three FIN_... variables are simple -- no aggregation is done for them

	if [ "${DYN_DNS_DN}" != "" ] ; then
		if [ "${MAN_DNS_DN}" != "" ] ; then
			if ${ARG_OVERRIDE_MANUAL_NETWORK_SETTINGS} ; then
				logMessage "Will allow changes to manually-set DomainName '${MAN_DNS_DN}'"
				readonly FIN_DNS_DN="${DYN_DNS_DN}"
			else
				logMessage "WARNING: Ignoring DomainName '$DYN_DNS_DN' because DomainName was set manually and '-allowChangesToManuallySetNetworkSettings' was not specified"
				readonly FIN_DNS_DN="${MAN_DNS_DN}"
			fi
		else
			readonly FIN_DNS_DN="${DYN_DNS_DN}"
		fi
	else
		readonly FIN_DNS_DN="${CUR_DNS_DN}"
	fi

	if [ "${DYN_SMB_NN}" != "" ] ; then
		if [ "${MAN_SMB_NN}" != "" ] ; then
			if ${ARG_OVERRIDE_MANUAL_NETWORK_SETTINGS} ; then
				logMessage "Will allow changes to manually-set NetBIOSName '${MAN_SMB_NN}'"
				readonly FIN_SMB_NN="${DYN_SMB_NN}"
			else
				logMessage "WARNING: Ignoring NetBIOSName '$DYN_SMB_NN' because NetBIOSName was set manually and '-allowChangesToManuallySetNetworkSettings' was not specified"
				readonly FIN_SMB_NN="${MAN_SMB_NN}"
			fi
		else
			readonly FIN_SMB_NN="${DYN_SMB_NN}"
		fi
	else
		readonly FIN_SMB_NN="${CUR_SMB_NN}"
	fi

	if [ "${DYN_SMB_WG}" != "" ] ; then
		if [ "${MAN_SMB_WG}" != "" ] ; then
			if ${ARG_OVERRIDE_MANUAL_NETWORK_SETTINGS} ; then
				logMessage "Will allow changes to manually-set Workgroup '${MAN_SMB_WG}'"
				readonly FIN_SMB_WG="${DYN_SMB_WG}"
			else
				logMessage "WARNING: Ignoring Workgroup '$DYN_SMB_WG' because Workgroup was set manually and '-allowChangesToManuallySetNetworkSettings' was not specified"
				readonly FIN_SMB_WG="${MAN_SMB_WG}"
			fi
		else
			readonly FIN_SMB_WG="${DYN_SMB_WG}"
		fi
	else
		readonly FIN_SMB_WG="${CUR_SMB_WG}"
	fi

	# DNS ServerAddresses (FIN_DNS_SA) are aggregated for 10.4 and 10.5
	if [ ${#vDNS[*]} -eq 0 ] ; then
		readonly FIN_DNS_SA="${CUR_DNS_SA}"
	else
		if [ "${MAN_DNS_SA}" != "" ] ; then
			if ${ARG_OVERRIDE_MANUAL_NETWORK_SETTINGS} ; then
				logMessage "Will allow changes to manually-set ServerAddresses '${MAN_DNS_SA}'"
				# (Don't include 10.4 or 10.5 code since we now support only 10.7 and higher)
				readonly FIN_DNS_SA="${DYN_DNS_SA}"
			else
				logMessage "WARNING: Ignoring ServerAddresses '$DYN_DNS_SA' because ServerAddresses was set manually and '-allowChangesToManuallySetNetworkSettings' was not specified"
				readonly FIN_DNS_SA="${CUR_DNS_SA}"
			fi
		else
			# Do nothing - in 10.6 and higher -- we don't aggregate our configurations, apparently
			readonly FIN_DNS_SA="${DYN_DNS_SA}"
			logMessage "Not aggregating ServerAddresses because running on macOS 10.6 or higher"
		fi
	fi

	# SMB WINSAddresses (FIN_SMB_WA) are aggregated for 10.4 and 10.5
	if [ ${#vSMB[*]} -eq 0 ] ; then
		readonly FIN_SMB_WA="${CUR_SMB_WA}"
	else
		if [ "${MAN_SMB_WA}" != "" ] ; then
			if ${ARG_OVERRIDE_MANUAL_NETWORK_SETTINGS} ; then
				logMessage "Will allow changes to manually-set WINSAddresses '${MAN_SMB_WA}'"
				# (Don't include 10.4 or 10.5 code since we now support only 10.7 and higher)
				readonly FIN_SMB_WA="${DYN_SMB_WA}"
			else
				logMessage "WARNING: Ignoring WINSAddresses '$DYN_SMB_WA' because WINSAddresses was set manually and '-allowChangesToManuallySetNetworkSettings' was not specified"
				readonly FIN_SMB_WA="${MAN_SMB_WA}"
			fi
		else
			# Do nothing - in 10.6 and higher -- we don't aggregate our configurations, apparently
			readonly FIN_SMB_WA="${DYN_SMB_WA}"
			logMessage "Not aggregating WINSAddresses because running on macOS 10.6 or higher"
		fi
	fi

	# DNS SearchDomains (FIN_DNS_SD) is treated specially
	#
	# OLD BEHAVIOR:
	#     if SearchDomains was not set manually, we set SearchDomains to the DomainName
	#     else
	#          In macOS 10.4-10.5, we add the DomainName to the end of any manual SearchDomains (unless it is already there)
	#          In macOS 10.6+, if SearchDomains was entered manually, we ignore the DomainName
	#                         else we set SearchDomains to the DomainName
	#
	# NEW BEHAVIOR (done if ARG_PREPEND_DOMAIN_NAME is "true"):
	#
	#     if SearchDomains was entered manually and ARG_OVERRIDE_MANUAL_NETWORK_SETTINGS is false, we do nothing
	#     else we  PREpend new SearchDomains (if any) to the existing SearchDomains (NOT replacing them)
	#          and PREpend DomainName to that
	#
	#              (done if ARG_PREPEND_DOMAIN_NAME is "false" and there are new SearchDomains from DOMAIN-SEARCH):
	#
	#     if SearchDomains was entered manually and ARG_OVERRIDE_MANUAL_NETWORK_SETTINGS is false, we do nothing
	#     else we  PREpend any new SearchDomains to the existing SearchDomains (NOT replacing them)
	#
	#     This behavior is meant to behave like Linux with Network Manager and Windows

	if "${ARG_PREPEND_DOMAIN_NAME}" ; then
		if [ "${MAN_DNS_SD}" = "" ] || [ "${ARG_OVERRIDE_MANUAL_NETWORK_SETTINGS}" = "true" ] ; then
			if [ "${MAN_DNS_SD}" != "" ] ; then
				logMessage "Will allow changes to manually-set search domains '${MAN_DNS_SD}'"
			fi
			if [ "${DYN_DNS_SD}" != "" ] ; then
                if ! echo "${CUR_DNS_SD}" | tr ' ' '\n' | grep -q "${DYN_DNS_SD}" ; then
                    logMessage "Prepending '${DYN_DNS_SD}' to search domains '${CUR_DNS_SD}' because the search domains were not set manually (or are allowed to be changed) and 'Prepend domain name to search domains' was selected"
                    readonly TMP_DNS_SD="$( trim "${DYN_DNS_SD}" "${CUR_DNS_SD}" )"
                else
                    logMessage "Not prepending '${DYN_DNS_SD}' to search domains '${CUR_DNS_SD}' because it is already there"
                    readonly TMP_DNS_SD="${CUR_DNS_SD}"
                fi
            else
				readonly TMP_DNS_SD="${CUR_DNS_SD}"
			fi
			if [ "${FIN_DNS_DN}" != "" ] && [ "${FIN_DNS_DN}" != "localdomain" ] ; then
                if ! echo "${TMP_DNS_SD}" | tr ' ' '\n' | grep -q "${FIN_DNS_DN}" ; then
                    logMessage "Prepending '${FIN_DNS_DN}' to search domains '${TMP_DNS_SD}' because the search domains were not set manually (or are allowed to be changed) and 'Prepend domain name to search domains' was selected"
                    readonly FIN_DNS_SD="$( trim "${FIN_DNS_DN}" "${TMP_DNS_SD}" )"
                else
                    logMessage "Not prepending '${FIN_DNS_DN}' to search domains '${TMP_DNS_SD}' because it is already there"
                    readonly FIN_DNS_SD="${TMP_DNS_SD}"
                fi
            else
				readonly FIN_DNS_SD="${TMP_DNS_SD}"
			fi
		else
			if [ "${DYN_DNS_SD}" != "" ] ; then
				logMessage "WARNING: Not prepending '${DYN_DNS_SD}' to search domains '${CUR_DNS_SD}' because the search domains were set manually and '-allowChangesToManuallySetNetworkSettings' was not specified"
			fi
            if [ "${FIN_DNS_DN}" != "" ] ; then
                logMessage "WARNING: Not prepending domain '${FIN_DNS_DN}' to search domains '${CUR_DNS_SD}' because the search domains were set manually and '-allowChangesToManuallySetNetworkSettings' was not specified"
            fi
			readonly FIN_DNS_SD="${CUR_DNS_SD}"
		fi
	else
		if [ "${DYN_DNS_SD}" != "" ] ; then
			if [ "${MAN_DNS_SD}" = "" ] || [ "${ARG_OVERRIDE_MANUAL_NETWORK_SETTINGS}" = "true" ] ; then
				if [ "${MAN_DNS_SD}" != "" ] ; then
					logMessage "Will allow changes to manually-set search domains '${MAN_DNS_SD}'"
				fi
				logMessage "Prepending '${DYN_DNS_SD}' to search domains '${CUR_DNS_SD}' because the search domains were not set manually (or are allowed to be changed) but were set via OpenVPN and 'Prepend domain name to search domains' was not selected"
				readonly FIN_DNS_SD="$( trim "${DYN_DNS_SD}" "${CUR_DNS_SD}" )"
            else
                logMessage "WARNING: Not prepending '${DYN_DNS_SD}' to search domains '${CUR_DNS_SD}' because the search domains were set manually"
                readonly FIN_DNS_SD="${CUR_DNS_SD}"
			fi
		else
            if [ "${FIN_DNS_DN}" != "" ] && [ "${FIN_DNS_DN}" != "localdomain" ] ; then
				if [ "${MAN_DNS_SD}" = "" ] || [ "${ARG_OVERRIDE_MANUAL_NETWORK_SETTINGS}" = "true" ] ; then
					logMessage "Setting search domains to '${FIN_DNS_DN}' because the search domains were not set manually (or are allowed to be changed) and 'Prepend domain name to search domains' was not selected"
					readonly FIN_DNS_SD="${FIN_DNS_DN}"
				else
					logMessage "Not replacing search domains '${CUR_DNS_SD}' with '${FIN_DNS_DN}' because the search domains were set manually, '-allowChangesToManuallySetNetworkSettings' was not selected, and 'Prepend domain name to search domains' was not selected"
					readonly FIN_DNS_SD="${CUR_DNS_SD}"
				fi
            else
                readonly FIN_DNS_SD="${CUR_DNS_SD}"
            fi
		fi
	fi

	logDebugMessage ''
	logDebugMessage "FIN_DNS_DN = ${FIN_DNS_DN}; FIN_DNS_SA = ${FIN_DNS_SA}; FIN_DNS_SD = ${FIN_DNS_SD}"
	logDebugMessage "FIN_SMB_NN = ${FIN_SMB_NN}; FIN_SMB_WG = ${FIN_SMB_WG}; FIN_SMB_WA = ${FIN_SMB_WA}"

# Set up SKP_... variables to inhibit scutil from making some changes

	# SKP_DNS_... and SKP_SMB_... are used to comment out individual items that are not being set
	if [ "${FIN_DNS_DN}" = "" ] || [ "${FIN_DNS_DN}" = "${CUR_DNS_DN}" ] ; then
		SKP_DNS_DN="#"
	else
		SKP_DNS_DN=""
	fi
	if [ "${FIN_DNS_SA}" = "" ] || [ "${FIN_DNS_SA}" = "${CUR_DNS_SA}" ] ; then
		SKP_DNS_SA="#"
	else
		SKP_DNS_SA=""
	fi
	if [ "${FIN_DNS_SD}" = "" ] || [ "${FIN_DNS_SD}" = "${CUR_DNS_SD}" ] ; then
		SKP_DNS_SD="#"
	else
		SKP_DNS_SD=""
	fi
	if [ "${FIN_SMB_NN}" = "" ] || [ "${FIN_SMB_NN}" = "${CUR_SMB_NN}" ] ; then
		SKP_SMB_NN="#"
	else
		SKP_SMB_NN=""
	fi
	if [ "${FIN_SMB_WG}" = "" ] || [ "${FIN_SMB_WG}" = "${CUR_SMB_WG}" ] ; then
		SKP_SMB_WG="#"
	else
		SKP_SMB_WG=""
	fi
	if [ "${FIN_SMB_WA}" = "" ] || [ "${FIN_SMB_WA}" = "${CUR_SMB_WA}" ] ; then
		SKP_SMB_WA="#"
	else
		SKP_SMB_WA=""
	fi

	# if any DNS items should be set, set all that have values
	if [ "${SKP_DNS_DN}${SKP_DNS_SA}${SKP_DNS_SD}" = "###" ] ; then
		readonly SKP_DNS="#"
	else
		readonly SKP_DNS=""
		if [ "${FIN_DNS_DN}" != "" ] ; then
			SKP_DNS_DN=""
		fi
		if [ "${FIN_DNS_SA}" != "" ] ; then
			SKP_DNS_SA=""
		fi
		if [ "${FIN_DNS_SD}" != "" ] ; then
			SKP_DNS_SD=""
		fi
	fi

	# if any SMB items should be set, set all that have values
	if [ "${SKP_SMB_NN}${SKP_SMB_WG}${SKP_SMB_WA}" = "###" ] ; then
		readonly SKP_SMB="#"
	else
		readonly SKP_SMB=""
		if [ "${FIN_SMB_NN}" != "" ] ; then
			SKP_SMB_NN=""
		fi
		if [ "${FIN_SMB_WG}" != "" ] ; then
			SKP_SMB_WG=""
		fi
		if [ "${FIN_SMB_WA}" != "" ] ; then
			SKP_SMB_WA=""
		fi
	fi

	readonly SKP_DNS_SA SKP_DNS_SD SKP_DNS_DN
	readonly SKP_SMB_NN SKP_SMB_WG SKP_SMB_WA

# special-case fiddling:

	# in 10.8 and higher, ServerAddresses and SearchDomains must be set via the Setup: key in addition to the State: key
	# in 10.7 if ServerAddresses or SearchDomains are manually set, ServerAddresses and SearchDomains must be similarly set with the Setup: key in addition to the State: key
	#
	# we pass a flag indicating whether we've done that to the other scripts in 'ALSO_USING_SETUP_KEYS'

	case "${OSVER}" in
		10.7 )
			if [ "${MAN_DNS_SA}" = "" ] && [  "${MAN_DNS_SD}" = "" ] ; then
				logDebugMessage "macOS 10.7 and neither ServerAddresses nor SearchDomains were set manually, so will modify DNS settings using only State:"
				readonly SKP_SETUP_DNS="#"
				readonly ALSO_USING_SETUP_KEYS="false"
			else
				logDebugMessage "macOS 10.7 and ServerAddresses or SearchDomains were set manually, so will modify DNS settings using Setup: in addition to State:"
				readonly SKP_SETUP_DNS=""
				readonly ALSO_USING_SETUP_KEYS="true"
			fi
			;;
		* )
			logDebugMessage "macOS 10.8 or higher, so will modify DNS settings using Setup: in addition to State:"
			readonly SKP_SETUP_DNS=""
			readonly ALSO_USING_SETUP_KEYS="true"
			;;
	esac

	logDebugMessage ''
	logDebugMessage "SKP_DNS = ${SKP_DNS}; SKP_DNS_SA = ${SKP_DNS_SA}; SKP_DNS_SD = ${SKP_DNS_SD}; SKP_DNS_DN = ${SKP_DNS_DN}"
	logDebugMessage "SKP_SETUP_DNS = ${SKP_SETUP_DNS}"
	logDebugMessage "SKP_SMB = ${SKP_SMB}; SKP_SMB_NN = ${SKP_SMB_NN}; SKP_SMB_WG = ${SKP_SMB_WG}; SKP_SMB_WA = ${SKP_SMB_WA}"

	if [ -e /etc/resolv.conf ] ; then
		set +e # "grep" will return error status (1) if no matches are found, so don't fail if not found
			original_resolver_contents="$( grep -v '#' < /etc/resolv.conf )"
		set -e # resume abort on error
	else
		original_resolver_contents="(unavailable)"
	fi
    logDebugMessage ''
    logDebugMessage "/etc/resolv.conf = ${original_resolver_contents}"
    logDebugMessage ''

	set +e # scutil --dns will return error status in case dns is already down, so don't fail if no dns found
		scutil_dns="$( scutil --dns)"
	set -e # resume abort on error
	logDebugMessage ''
	logDebugMessage "scutil --dns BEFORE CHANGES = ${scutil_dns}"
	logDebugMessage ''

	logDebugMessage ''
	logDebugMessage "Configuration changes:"
	logDebugMessage "${SKP_DNS}${SKP_DNS_SA}ADD State: ServerAddresses  ${FIN_DNS_SA}"
	logDebugMessage "${SKP_DNS}${SKP_DNS_SD}ADD State: SearchDomains    ${FIN_DNS_SD}"
	logDebugMessage "${SKP_DNS}${SKP_DNS_DN}ADD State: DomainName       ${FIN_DNS_DN}"
	logDebugMessage ''
	logDebugMessage "${SKP_SETUP_DNS}${SKP_DNS}${SKP_DNS_SA}ADD Setup: ServerAddresses  ${FIN_DNS_SA}"
	logDebugMessage "${SKP_SETUP_DNS}${SKP_DNS}${SKP_DNS_SD}ADD Setup: SearchDomains    ${FIN_DNS_SD}"
	logDebugMessage "${SKP_SETUP_DNS}${SKP_DNS}${SKP_DNS_DN}ADD Setup: DomainName       ${FIN_DNS_DN}"
	logDebugMessage ''
	logDebugMessage "${SKP_SMB}${SKP_SMB_NN}ADD State: NetBIOSName    ${FIN_SMB_NN}"
	logDebugMessage "${SKP_SMB}${SKP_SMB_WG}ADD State: Workgroup      ${FIN_SMB_WG}"
	logDebugMessage "${SKP_SMB}${SKP_SMB_WA}ADD State: WINSAddresses  ${FIN_SMB_WA}"

	# Save the openvpn process ID and the Network Primary Service ID, leasewather.plist path, logfile path, and optional arguments from Tunnelblick,
	# then save old and new DNS and SMB settings
	# PPID is a script variable (defined by bash itself) that contains the process ID of the parent of the process running the script (i.e., OpenVPN's process ID)
	# config is an environmental variable set to the configuration path by OpenVPN prior to running this up script

	scutil <<-EOF > /dev/null
		open

		# Store our variables for Tunnelblick and other scripts (process-network-changes, leasewatch, down, etc.) to use
		d.init
		# The '#' in the next line does NOT start a comment; it indicates to scutil that a number follows it (as opposed to a string or an array)
		d.add PID # ${PPID}
        d.add madeDnsChanges        "true"
        d.add inhibitNetworkMonitoring "false"
		d.add Service ${PSID}
		d.add LeaseWatcherPlistPath "${LEASEWATCHER_PLIST_PATH}"
		d.add RemoveLeaseWatcherPlist "${REMOVE_LEASEWATCHER_PLIST}"
		d.add ScriptLogFile         "${SCRIPT_LOG_FILE}"
		d.add MonitorNetwork        "${ARG_MONITOR_NETWORK_CONFIGURATION}"
		d.add RestoreOnDNSReset     "${ARG_RESTORE_ON_DNS_RESET}"
		d.add RestoreOnWINSReset    "${ARG_RESTORE_ON_WINS_RESET}"
		d.add IgnoreOptionFlags     "${ARG_IGNORE_OPTION_FLAGS}"
        d.add IsTapInterface        "${ARG_TAP}"
        d.add FlushDNSCache         "${ARG_FLUSH_DNS_CACHE}"
        d.add ResetPrimaryInterface "${ARG_RESET_PRIMARY_INTERFACE_ON_DISCONNECT}"
		d.add ResetPrimaryInterfaceOnUnexpected "${ARG_RESET_PRIMARY_INTERFACE_ON_DISCONNECT_UNEXPECTED}"
        d.add RouteGatewayIsDhcp    "${ROUTE_GATEWAY_IS_DHCP}"
		d.add bAlsoUsingSetupKeys   "${ALSO_USING_SETUP_KEYS}"
        d.add TapDeviceHasBeenSetNone "false"
        d.add TunnelDevice          "$dev"
        d.add RestoreIpv6Services   "$IPV6_DISABLED_SERVICES_ENCODED"
        d.add RestoreSecondaryServices "$SECONDARY_DISABLED_SERVICES_ENCODED"
        d.add ExpectedDnsAddresses  "$FIN_DNS_SA"
		set State:/Network/OpenVPN

		# Back up the device's current DNS and SMB configurations,
		# Indicate 'no such key' by a dictionary with a single entry: "TunnelblickNoSuchKey : true"
		# If there isn't a key, "TunnelblickNoSuchKey : true" won't be removed.
		# If there is a key, "TunnelblickNoSuchKey : true" will be removed and the key's contents will be used

		d.init
		d.add TunnelblickNoSuchKey true
		get State:/Network/Service/${PSID}/DNS
		set State:/Network/OpenVPN/OldDNS

		d.init
		d.add TunnelblickNoSuchKey true
		get Setup:/Network/Service/${PSID}/DNS
		set State:/Network/OpenVPN/OldDNSSetup

		d.init
		d.add TunnelblickNoSuchKey true
		get State:/Network/Service/${PSID}/SMB
		set State:/Network/OpenVPN/OldSMB

		# Initialize the new DNS map via State:
		${SKP_DNS}d.init
		${SKP_DNS}${SKP_DNS_SA}d.add ServerAddresses * ${FIN_DNS_SA}
		${SKP_DNS}${SKP_DNS_SD}d.add SearchDomains   * ${FIN_DNS_SD}
		${SKP_DNS}${SKP_DNS_DN}d.add DomainName        ${FIN_DNS_DN}
		${SKP_DNS}set State:/Network/Service/${PSID}/DNS

		# If necessary, initialize the new DNS map via Setup: also
		${SKP_SETUP_DNS}${SKP_DNS}d.init
		${SKP_SETUP_DNS}${SKP_DNS}${SKP_DNS_SA}d.add ServerAddresses * ${FIN_DNS_SA}
		${SKP_SETUP_DNS}${SKP_DNS}${SKP_DNS_SD}d.add SearchDomains   * ${FIN_DNS_SD}
		${SKP_SETUP_DNS}${SKP_DNS}${SKP_DNS_DN}d.add DomainName        ${FIN_DNS_DN}
		${SKP_SETUP_DNS}${SKP_DNS}set Setup:/Network/Service/${PSID}/DNS

		# Initialize the SMB map
		${SKP_SMB}d.init
		${SKP_SMB}${SKP_SMB_NN}d.add NetBIOSName     ${FIN_SMB_NN}
		${SKP_SMB}${SKP_SMB_WG}d.add Workgroup       ${FIN_SMB_WG}
		${SKP_SMB}${SKP_SMB_WA}d.add WINSAddresses * ${FIN_SMB_WA}
		${SKP_SMB}set State:/Network/Service/${PSID}/SMB

		quit
EOF

	logDebugMessage ''
	logDebugMessage "Pause for configuration changes to be propagated to State:/Network/Global/DNS and .../SMB"
	sleep 1

	scutil <<-EOF > /dev/null
		open

		# Initialize the maps that will be compared when a configuration change occurs
		d.init
		d.add TunnelblickNoSuchKey true
		get State:/Network/Global/DNS
		set State:/Network/OpenVPN/DNS

		d.init
		d.add TunnelblickNoSuchKey true
		get State:/Network/Global/SMB
		set State:/Network/OpenVPN/SMB

		quit
EOF

	readonly NEW_DNS_SETUP_CONFIG="$( scutil <<-EOF |
		open
		show Setup:/Network/Service/${PSID}/DNS
		quit
EOF
sed -e 's/^[[:space:]]*[[:digit:]]* : //g' | tr '\n' ' '
)"
	readonly NEW_SMB_SETUP_CONFIG="$( scutil <<-EOF |
		open
		show Setup:/Network/Service/${PSID}/SMB
		quit
EOF
sed -e 's/^[[:space:]]*[[:digit:]]* : //g' | tr '\n' ' '
)"
	readonly NEW_DNS_STATE_CONFIG="$( scutil <<-EOF |
		open
		show State:/Network/Service/${PSID}/DNS
		quit
EOF
sed -e 's/^[[:space:]]*[[:digit:]]* : //g' | tr '\n' ' '
)"
	readonly NEW_SMB_STATE_CONFIG="$( scutil <<-EOF |
		open
		show State:/Network/Service/${PSID}/SMB
		quit
EOF
sed -e 's/^[[:space:]]*[[:digit:]]* : //g' | tr '\n' ' '
)"
	readonly NEW_DNS_GLOBAL_CONFIG="$( scutil <<-EOF |
		open
		show State:/Network/Global/DNS
		quit
EOF
sed -e 's/^[[:space:]]*[[:digit:]]* : //g' | tr '\n' ' '
)"
	readonly NEW_SMB_GLOBAL_CONFIG="$( scutil <<-EOF |
		open
		show State:/Network/Global/SMB
		quit
EOF
sed -e 's/^[[:space:]]*[[:digit:]]* : //g' | tr '\n' ' '
)"
	readonly EXPECTED_NEW_DNS_GLOBAL_CONFIG="$( scutil <<-EOF |
		open
		show State:/Network/OpenVPN/DNS
		quit
EOF
sed -e 's/^[[:space:]]*[[:digit:]]* : //g' | tr '\n' ' '
)"
	readonly EXPECTED_NEW_SMB_GLOBAL_CONFIG="$( scutil <<-EOF |
		open
		show State:/Network/OpenVPN/SMB
		quit
EOF
sed -e 's/^[[:space:]]*[[:digit:]]* : //g' | tr '\n' ' '
)"

	networksetup_dnsservers="$(    get_networksetup_setting dnsservers )"
	networksetup_searchdomains="$( get_networksetup_setting searchdomains )"

	logDebugMessage ''
	logDebugMessage "Configurations as read back after changes:$LF"
	logDebugMessage "State:/.../DNS = ${NEW_DNS_STATE_CONFIG}"
	logDebugMessage "State:/.../SMB = ${NEW_SMB_STATE_CONFIG}"
	logDebugMessage ''
	logDebugMessage "Setup:/.../DNS = ${NEW_DNS_SETUP_CONFIG}"
	logDebugMessage "Setup:/.../SMB = ${NEW_SMB_SETUP_CONFIG}"
	logDebugMessage ''
    logDebugMessage "State:/Network/Global/DNS = ${NEW_DNS_GLOBAL_CONFIG}"
    logDebugMessage "State:/Network/Global/SMB = ${NEW_SMB_GLOBAL_CONFIG}"
	logDebugMessage ''
	logDebugMessage "Expected by process-network-changes:"
    logDebugMessage "State:/Network/OpenVPN/DNS = ${EXPECTED_NEW_DNS_GLOBAL_CONFIG}"
    logDebugMessage "State:/Network/OpenVPN/SMB = ${EXPECTED_NEW_SMB_GLOBAL_CONFIG}"
	logDebugMessage ''
	logDebugMessage "networksetup dnsservers = $LF$networksetup_dnsservers"
	logDebugMessage ''
	logDebugMessage "networksetup searchdomains = $LF$networksetup_searchdomains"
	logDebugMessage ''

	if [ -e /etc/resolv.conf ] ; then
		set +e # "grep" will return error status (1) if no matches are found, so don't fail if not found
			new_resolver_contents="$( grep -v '#' < /etc/resolv.conf )"
		set -e # resume abort on error
	else
		new_resolver_contents="(unavailable)"
	fi
    logDebugMessage ''
    logDebugMessage "/etc/resolv.conf = ${new_resolver_contents}"
    logDebugMessage ''

	set +e # scutil --dns will return error status in case dns is already down, so don't fail if no dns found
		scutil_dns="$( scutil --dns )"
	set -e # resume abort on error
	logDebugMessage ''
	logDebugMessage "scutil --dns AFTER CHANGES = ${scutil_dns}"
	logDebugMessage ''

	logMessage "Saved the DNS and SMB configurations so they can be restored"

    logChange "${SKP_DNS}${SKP_DNS_SA}" "DNS ServerAddresses"   "${FIN_DNS_SA}"   "${CUR_DNS_SA}"
    logChange "${SKP_DNS}${SKP_DNS_SD}" "DNS SearchDomains"     "${FIN_DNS_SD}"   "${CUR_DNS_SD}"
    logChange "${SKP_DNS}${SKP_DNS_DN}" "DNS DomainName"        "${FIN_DNS_DN}"   "${CUR_DNS_DN}"
    logChange "${SKP_SMB}${SKP_SMB_NN}" "SMB NetBIOSName"       "${FIN_SMB_NN}"   "${CUR_SMB_NN}"
    logChange "${SKP_SMB}${SKP_SMB_WG}" "SMB Workgroup"         "${FIN_SMB_WG}"   "${CUR_SMB_WG}"
    logChange "${SKP_SMB}${SKP_SMB_WA}" "SMB WINSAddresses"     "${FIN_SMB_WA}"   "${CUR_SMB_WA}"

	logDnsInfo "${MAN_DNS_SA}" "${FIN_DNS_SA}"

	flushDNSCache

	setupToMonitorNetworkConfiguration
}

configureDhcpDns() {

    # Used for TAP device which does DHCP
	# whilst ipconfig will have created the neccessary Network Service keys, the DNS
	# settings won't actually be used by macOS unless the SupplementalMatchDomains key
	# is added
	# ref. <http://lists.apple.com/archives/Macnetworkprog/2005/Jun/msg00011.html>
	# - is there a way to extract the domains from the SC dictionary and re-insert
	#   as SupplementalMatchDomains? i.e. not requiring the ipconfig domain_name call?

	# - wait until we get a lease before extracting the DNS domain name and merging into SC
	# - despite it's name, ipconfig waitall doesn't (but maybe one day it will :-)

	logDebugMessage "About to 'ipconfig waitall'"
	ipconfig waitall
	logDebugMessage "Completed 'ipconfig waitall'"

	unset test_domain_name
	unset test_name_server

	# Maximum time to wait for DHCP (seconds)
	local time_limit=15

	local time_waited=0

	# It usually takes at least a few seconds to get a DHCP lease, so we loop, checking once per second
	local sleep_time=1

	while [ -z "$test_domain_name" ] && [ -z "$test_name_server" ] && [ $time_waited -lt $time_limit ] ; do

		if [ $sleep_time -ne 0 ] ; then
			logMessage "Sleeping for $sleep_time seconds to wait for DHCP to finish setup."
			sleep $sleep_time
			(( time_waited += sleep_time ))
		fi

		if [ -z "$test_domain_name" ]; then
			test_domain_name="$( ipconfig getoption "$dev" domain_name 2>/dev/null ; true )"
		fi

		if [ -z "$test_name_server" ]; then
			test_name_server="$( ipconfig getoption "$dev" domain_name_server 2>/dev/null ; true )"
		fi
	done

	if [ $time_waited -ge $time_limit ] ; then
		logMessage "WARNING: Gave up waiting to get DHCP lease after $time_waited seconds"
	fi

	if [ -z "$test_domain_name" ] && [ -z "$test_name_server" ] ; then
		logMessage "WARNING: domain_name and domain_name_server from 'ipconfig getoption \"$dev\"' were both empty indicating DHCP info has not been received"
	fi

	logDebugMessage "Finished waiting for DHCP lease: test_domain_name = '$test_domain_name', test_name_server = '$test_name_server'"

	logDebugMessage "About to 'ipconfig getpacket $dev'"
	sGetPacketOutput="$( ipconfig getpacket "$dev" ; true )"
	logDebugMessage "Completed 'ipconfig getpacket $dev'; sGetPacketOutput = $sGetPacketOutput"

	unset aNameServers
	unset aWinsServers
	unset aSearchDomains

	nNameServerIndex=1
	nWinsServerIndex=1
	nSearchDomainIndex=1

	if [ "$sGetPacketOutput" ]; then
		sGetPacketOutput_FirstLine="$( echo "$sGetPacketOutput" | head -n 1 )"
		logDebugMessage "sGetPacketOutput_FirstLine = $sGetPacketOutput_FirstLine"

		if [ "$sGetPacketOutput_FirstLine" == "op = BOOTREPLY" ]; then
			set +e # "grep" will return error status (1) if no matches are found, so don't fail on individual errors

				for tNameServer in $( echo "$sGetPacketOutput" | grep "domain_name_server" | grep -Eo "\{([0-9\.]+)(, [0-9\.]+)*\}" | grep -Eo "([0-9\.]+)" ); do
					aNameServers[nNameServerIndex-1]="$( trim "$tNameServer" )"
					(( nNameServerIndex++ ))
				done

				for tWINSServer in $( echo "$sGetPacketOutput" | grep "nb_over_tcpip_name_server" | grep -Eo "\{([0-9\.]+)(, [0-9\.]+)*\}" | grep -Eo "([0-9\.]+)" ); do
					aWinsServers[nWinsServerIndex-1]="$( trim "$tWINSServer" )"
					(( nWinsServerIndex++ ))
				done

				for tSearchDomain in $( echo "$sGetPacketOutput" | grep "search_domain" | grep -Eo "\{([-A-Za-z0-9\-\.]+)(, [-A-Za-z0-9\-\.]+)*\}" | grep -Eo "([-A-Za-z0-9\-\.]+)" ); do
					aSearchDomains[nSearchDomainIndex-1]="$( trim "$tSearchDomain" )"
					(( nSearchDomainIndex++ ))
				done

				sDomainName="$( echo "$sGetPacketOutput" | grep "domain_name " | grep -Eo ": [-A-Za-z0-9\-\.]+" | grep -Eo "[-A-Za-z0-9\-\.]+" )"
				sDomainName="$( trim "$sDomainName" )"

				if [ ${#aNameServers[*]} -gt 0 ] && [ "$sDomainName" ]; then
					logMessage "Retrieved from DHCP/BOOTP packet: name server(s) [" "${aNameServers[@]}" "], domain name [ $sDomainName ], search domain(s) [" "${aSearchDomains[@]}" "] and SMB server(s) [" "${aWinsServers[@]}" "]"
					setDnsServersAndDomainName aNameServers[@] "$sDomainName" aWinsServers[@] aSearchDomains[@]
					return 0
				elif [ ${#aNameServers[*]} -gt 0 ]; then
					logMessage "Retrieved from DHCP/BOOTP packet: name server(s) [" "${aNameServers[@]}" "], search domain(s) [" "${aSearchDomains[@]}" "] and SMB server(s) [" "${aWinsServers[@]}" "] and using default domain name [ $DEFAULT_DOMAIN_NAME ]"
					setDnsServersAndDomainName aNameServers[@] "$DEFAULT_DOMAIN_NAME" aWinsServers[@] aSearchDomains[@]
					return 0
				else
					# Should we return 1 here and indicate an error, or attempt the old method?
					logMessage "No useful information extracted from DHCP/BOOTP packet. Attempting legacy configuration."
				fi

			set -e # We instruct bash that it CAN again fail on errors
		else
			# Should we return 1 here and indicate an error, or attempt the old method?
			logMessage "No DHCP/BOOTP packet found on interface. Attempting legacy configuration."
		fi
	else
		logMessage "WARNING: Failed or had no output: 'ipconfig getpacket \"$dev\"'"
	fi

	unset sDomainName
	unset sNameServer
	unset aNameServers

    set +e # We instruct bash NOT to exit on individual command errors, because if we need to wait longer these commands will fail

		logDebugMessage "About to 'ipconfig getoption $dev domain_name'"
		sDomainName="$( ipconfig getoption "$dev" domain_name 2>/dev/null )"
		logDebugMessage "Completed 'ipconfig getoption $dev domain_name'"
		logDebugMessage "About to 'ipconfig getoption $dev domain_name_server'"
		sNameServer="$( ipconfig getoption "$dev" domain_name_server 2>/dev/null )"
		logDebugMessage "Completed 'ipconfig getoption $dev domain_name_server'"

	set -e # We instruct bash that it CAN again fail on individual errors

	sDomainName="$( trim "$sDomainName" )"
	sNameServer="$( trim "$sNameServer" )"

	declare -a aWinsServers=( )   # Declare empty WINSServers   array to avoid any useless error messages
	declare -a aSearchDomains=( ) # Declare empty SearchDomains array to avoid any useless error messages

	if [ "$sDomainName" ] && [ "$sNameServer" ]; then
		aNameServers[0]=$sNameServer
		logMessage "Retrieved OpenVPN (DHCP): name server [ $sNameServer ], domain name [ $sDomainName ], and no SMB servers or search domains"
		setDnsServersAndDomainName aNameServers[@] "$sDomainName" aWinsServers[@] aSearchDomains[@]
	elif [ "$sNameServer" ]; then
		aNameServers[0]=$sNameServer
		logMessage "Retrieved OpenVPN (DHCP): name server [ $sNameServer ] and no SMB servers or search domains, and using default domain name [ $DEFAULT_DOMAIN_NAME ]"
		setDnsServersAndDomainName aNameServers[@] "$DEFAULT_DOMAIN_NAME" aWinsServers[@] aSearchDomains[@]
	elif [ "$sDomainName" ]; then
		logMessage "WARNING: Retrieved domain name [ $sDomainName ] but no name servers from OpenVPN via DHCP, which is not sufficient to make network/DNS configuration changes."
		if ${ARG_MONITOR_NETWORK_CONFIGURATION} ; then
			logMessage "WARNING: Will NOT monitor for other network configuration changes."
		fi
        notMakingDnsChanges
        flushDNSCache
	else
		logMessage "WARNING: No DNS information received from OpenVPN via DHCP, so no network/DNS configuration changes need to be made."
		if ${ARG_MONITOR_NETWORK_CONFIGURATION} ; then
			logMessage "WARNING: Will NOT monitor for other network configuration changes."
		fi
        notMakingDnsChanges
        flushDNSCache
	fi

	return 0
}

configureOpenVpnDns() {

    # Configures using OpenVPN foreign_option_* instead of DHCP

    # Description of foreign_option_ parameters (from OpenVPN 2.3-alpha_2 man page):
    #
    # DOMAIN name -- Set Connection-specific DNS Suffix.
    #
    # DOMAIN-SEARCH name -- Set Connection-specific DNS Search Address. Repeat this option to
    #               set additional search domains. (Tunnelblick-specific addition.)
    #
    # DNS addr -- Set primary domain name server address.  Repeat  this  option  to  set
    #              secondary DNS server addresses.
    #
    # WINS  addr  --  Set primary WINS server address (NetBIOS over TCP/IP Name Server).
    #              Repeat this option to set secondary WINS server addresses.
    #
    # NBDD addr -- Set primary NBDD server address (NetBIOS over TCP/IP Datagram Distribution Server)
    #              Repeat this option to set secondary NBDD server addresses.
    #
    # NTP  addr  -- Set primary NTP server address (Network Time Protocol).  Repeat this option
    #              to set secondary NTP server addresses.
    #
    # NBT type -- Set NetBIOS over TCP/IP Node  type.   Possible  options:  1  =  b-node
    #              (broadcasts),  2  =  p-node (point-to-point name queries to a WINS server), 4 = m-
    #              node (broadcast then query name server), and 8 = h-node (query name  server,  then
    #              broadcast).
    #
    # NBS  scope-id  --  Set  NetBIOS  over TCP/IP Scope. A NetBIOS Scope ID provides an
    #              extended naming service for the NetBIOS over TCP/IP (Known  as  NBT)  module.  The
    #              primary  purpose  of  a NetBIOS scope ID is to isolate NetBIOS traffic on a single
    #              network to only those nodes with the same NetBIOS scope ID.  The NetBIOS scope  ID
    #              is  a  character string that is appended to the NetBIOS name. The NetBIOS scope ID
    #              on two hosts must match, or the two hosts will not be  able  to  communicate.  The
    #              NetBIOS Scope ID also allows computers to use the same computer name, as they have
    #              different scope IDs. The Scope ID becomes a part of the NetBIOS name,  making  the
    #              name unique.  (This description of NetBIOS scopes courtesy of NeonSurge@abyss.com)
    #
    #DISABLE-NBT -- Disable Netbios-over-TCP/IP.

	unset vForOptions
	unset vOptions
	unset aNameServers
	unset aWinsServers
	unset aSearchDomains

	nOptionIndex=1
	nNameServerIndex=1
	nWinsServerIndex=1
	nSearchDomainIndex=1

	while vForOptions=foreign_option_$nOptionIndex; [ -n "${!vForOptions}" ]; do
		vOptions[nOptionIndex-1]=${!vForOptions}
		case ${vOptions[nOptionIndex-1]} in
			"dhcp-option DOMAIN-SEARCH "*   )
				aSearchDomains[nSearchDomainIndex-1]="$( trim "${vOptions[nOptionIndex-1]//dhcp-option DOMAIN-SEARCH /}" )"
				(( nSearchDomainIndex++ ))
				;;
			"dhcp-option SEARCH-DOMAIN "*   )
				aSearchDomains[nSearchDomainIndex-1]="$( trim "${vOptions[nOptionIndex-1]//dhcp-option SEARCH-DOMAIN /}" )"
				(( nSearchDomainIndex++ ))
				;;
			"dhcp-option DOMAIN "* )
				sDomainName="$( trim "${vOptions[nOptionIndex-1]//dhcp-option DOMAIN /}" )"
				;;
			"dhcp-option ADAPTER_DOMAIN_SUFFIX "* )
				sDomainName="$( trim "${vOptions[nOptionIndex-1]//dhcp-option ADAPTER_DOMAIN_SUFFIX /}" )"
				;;
			"dhcp-option DNS "*    )
				aNameServers[nNameServerIndex-1]="$( trim "${vOptions[nOptionIndex-1]//dhcp-option DNS /}" )"
				(( nNameServerIndex++ ))
				;;
			"dhcp-option DNS6 "*    )
				aNameServers[nNameServerIndex-1]="$( trim "${vOptions[nOptionIndex-1]//dhcp-option DNS6 /}" )"
				(( nNameServerIndex++ ))
				;;
			"dhcp-option WINS "*   )
				aWinsServers[nWinsServerIndex-1]="$( trim "${vOptions[nOptionIndex-1]//dhcp-option WINS /}" )"
				(( nWinsServerIndex++ ))
				;;
            *   )
                logMessage "WARNING: 'foreign_option_${nOptionIndex}' = '${vOptions[nOptionIndex-1]}' ignored"
                ;;
		esac
		(( nOptionIndex++ ))
	done

	if [ ${#aNameServers[*]} -gt 0 ] && [ "$sDomainName" ]; then
		logMessage "Retrieved from OpenVPN: name server(s) [" "${aNameServers[@]}" "], domain name [ $sDomainName ], search domain(s) [" "${aSearchDomains[@]}" "], and SMB server(s) [" "${aWinsServers[@]}" "]"
		setDnsServersAndDomainName aNameServers[@] "$sDomainName" aWinsServers[@] aSearchDomains[@]
	elif [ ${#aNameServers[*]} -gt 0 ]; then
		logMessage "Retrieved from OpenVPN: name server(s) [" "${aNameServers[@]}" "], search domain(s) [" "${aSearchDomains[@]}" "] and SMB server(s) [" "${aWinsServers[@]}" "] and using default domain name [ $DEFAULT_DOMAIN_NAME ]"
		setDnsServersAndDomainName aNameServers[@] "$DEFAULT_DOMAIN_NAME" aWinsServers[@] aSearchDomains[@]
	else
		logMessage "WARNING: No DNS information received from OpenVPN, so no network configuration changes need to be made."
		if ${ARG_MONITOR_NETWORK_CONFIGURATION} ; then
			logMessage "WARNING: Will NOT monitor for other network configuration changes."
		fi
        notMakingDnsChanges
        flushDNSCache
	fi

	return 0
}

flushDNSCache() {

    if ${ARG_FLUSH_DNS_CACHE} ; then
		if [ -f /usr/bin/dscacheutil ] ; then
			set +e # we will catch errors from dscacheutil
				if /usr/bin/dscacheutil -flushcache ; then
					logMessage "Flushed the DNS cache via dscacheutil"
				else
					logMessage "WARNING: Unable to flush the DNS cache via dscacheutil"
				fi
			set -e # bash should again fail on errors
		else
			logMessage "WARNING: /usr/bin/dscacheutil not present. Not flushing the DNS cache via dscacheutil"
		fi

		if [ -f /usr/sbin/discoveryutil ] ; then
			set +e # we will catch errors from discoveryutil
				if /usr/sbin/discoveryutil udnsflushcaches ; then
					logMessage "Flushed the DNS cache via discoveryutil udnsflushcaches"
				else
					logMessage "WARNING: Unable to flush the DNS cache via discoveryutil udnsflushcaches"
				fi
				if /usr/sbin/discoveryutil mdnsflushcache ; then
					logMessage "Flushed the DNS cache via discoveryutil mdnsflushcache"
				else
					logMessage "WARNING: Unable to flush the DNS cache via discoveryutil mdnsflushcache"
				fi
			set -e # bash should again fail on errors
		else
			logMessage "/usr/sbin/discoveryutil not present. Not flushing the DNS cache via discoveryutil"
		fi

		if [ "$( pgrep HandsOffDaemon )" = "" ] ; then
			if [ -f /usr/bin/killall ] ; then
				set +e # ignore errors if mDNSResponder isn't currently running
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
				set -e # bash should again fail on errors
			else
				logMessage "WARNING: /usr/bin/killall not present. Not notifying mDNSResponder or mDNSResponderHelper that the DNS cache was flushed"
			fi
		else
			logMessage "WARNING: Hands Off is running.  Not notifying mDNSResponder or mDNSResponderHelper that the DNS cache was flushed"
		fi
    fi
}

logDnsInfo() {

    # log information about the DNS settings
    # @param String Manual DNS_SA
    # @param String New DNS_SA

	log_dns_info_manual_dns_sa="$1"
	log_dns_info_new_dns_sa="$2"

	if [ "${log_dns_info_manual_dns_sa}" != "" ] && [ "${ARG_OVERRIDE_MANUAL_NETWORK_SETTINGS}" = "false"  ] ; then
        logMessage "DNS servers '${log_dns_info_manual_dns_sa}' were set manually"
        if [ "${log_dns_info_manual_dns_sa}" != "${log_dns_info_new_dns_sa}" ] ; then
            logMessage "WARNING: that setting is being ignored; '${log_dns_info_new_dns_sa}' is being used."
        fi
    fi

    if [ "${log_dns_info_new_dns_sa}" != "" ] ; then
        logMessage "DNS servers '${log_dns_info_new_dns_sa}' will be used for DNS queries when the VPN is active"
		if [ "${log_dns_info_new_dns_sa}" == "127.0.0.1" ] ; then
			logMessage "NOTE: DNS server 127.0.0.1 often is used inside virtual machines (e.g., 'VirtualBox', 'Parallels', or 'VMWare'). The actual VPN server may be specified by the host machine. This DNS server setting may cause DNS queries to fail or be intercepted or falsified. Specify only known public DNS servers or DNS servers located on the VPN network to avoid such problems."
		else
			set +e # "grep" will return error status (1) if no matches are found, so don't fail on individual errors
				serversContainLoopback="$( echo "${log_dns_info_new_dns_sa}" | grep "127.0.0.1" )"
			set -e # We instruct bash that it CAN again fail on errors
			if [ "${serversContainLoopback}" != "" ] ; then
				logMessage "NOTE: DNS server 127.0.0.1 often is used inside virtual machines (e.g., 'VirtualBox', 'Parallels', or 'VMWare'). The actual VPN server may be specified by the host machine. If used, 127.0.0.1 may cause DNS queries to fail or be intercepted or falsified. Specify only known public DNS servers or DNS servers located on the VPN network to avoid such problems."
			else
				readonly knownPublicDnsServers="$( cat "${FREE_PUBLIC_DNS_SERVERS_LIST_PATH}" )"
				knownDnsServerNotFound="true"
				unknownDnsServerFound="false"
				for server in ${log_dns_info_new_dns_sa} ; do
					set +e # "grep" will return error status (1) if no matches are found, so don't fail on individual errors
						serverIsKnown="$( echo "${knownPublicDnsServers}" | grep "${server}" )"
					set -e # We instruct bash that it CAN again fail on errors
					if [ "${serverIsKnown}" != "" ] ; then
						knownDnsServerNotFound="false"
					else
						unknownDnsServerFound="true"
					fi
				done
				if ${knownDnsServerNotFound} ; then
					logMessage "NOTE: The DNS servers do not include any free public DNS servers known to Tunnelblick. This may cause DNS queries to fail or be intercepted or falsified even if they are directed through the VPN. Specify only known public DNS servers or DNS servers located on the VPN network to avoid such problems."
				else
					if ${unknownDnsServerFound} ; then
						logMessage "NOTE: The DNS servers include one or more free public DNS servers known to Tunnelblick and one or more DNS servers not known to Tunnelblick. If used, the DNS servers not known to Tunnelblick may cause DNS queries to fail or be intercepted or falsified even if they are directed through the VPN. Specify only known public DNS servers or DNS servers located on the VPN network to avoid such problems."
					else
						logMessage "The DNS servers include only free public DNS servers known to Tunnelblick."
					fi
				fi
			fi
		fi
    else
        logMessage "WARNING: There are no DNS servers in this computer's new network configuration. This computer or a DHCP server that this computer uses may be configured incorrectly."
    fi
}

logDnsInfoNoChanges() {

    # log information about DNS settings if they are not changing

    set +e # "grep" will return error status (1) if no matches are found, so don't fail on individual errors

		PSID="$( scutil <<-EOF |
			open
			show State:/Network/Global/IPv4
			quit
EOF
grep PrimaryService | sed -e 's/.*PrimaryService : //'
)"

		readonly LOGDNSINFO_MAN_DNS_CONFIG="$( scutil <<-EOF |
			open
			show Setup:/Network/Service/${PSID}/DNS
			quit
EOF
sed -e 's/^[[:space:]]*[[:digit:]]* : //g' | tr '\n' ' '
)"

		readonly LOGDNSINFO_CUR_DNS_CONFIG="$( scutil <<-EOF |
			open
			show State:/Network/Global/DNS
			quit
EOF
sed -e 's/^[[:space:]]*[[:digit:]]* : //g' | tr '\n' ' '
)"

		if echo "${LOGDNSINFO_MAN_DNS_CONFIG}" | grep -q "ServerAddresses" ; then
			readonly LOGDNSINFO_MAN_DNS_SA="$( trim "$( echo "${LOGDNSINFO_MAN_DNS_CONFIG}" | sed -e 's/^.*ServerAddresses[^{]*{[[:space:]]*\([^}]*\)[[:space:]]*}.*$/\1/g' )" )"
		else
			readonly LOGDNSINFO_MAN_DNS_SA="";
		fi

		if echo "${LOGDNSINFO_CUR_DNS_CONFIG}" | grep -q "ServerAddresses" ; then
			readonly LOGDNSINFO_CUR_DNS_SA="$( trim "$( echo "${LOGDNSINFO_CUR_DNS_CONFIG}" | sed -e 's/^.*ServerAddresses[^{]*{[[:space:]]*\([^}]*\)[[:space:]]*}.*$/\1/g' )" )"
		else
			readonly LOGDNSINFO_CUR_DNS_SA="";
		fi

    set -e # resume abort on error

	logDnsInfo "${LOGDNSINFO_MAN_DNS_SA}" "${LOGDNSINFO_CUR_DNS_SA}"
}

notMakingDnsChanges() {

        logMessage "No changes to DNS servers have been requested"

        logDnsInfoNoChanges

        willNotMonitorNetworkConfiguration

        scutil <<-EOF > /dev/null
            open

            d.init

            # Store variables needed by the down script

            d.add madeDnsChanges           "false"
            d.add inhibitNetworkMonitoring "true"

            d.add LeaseWatcherPlistPath    "${LEASEWATCHER_PLIST_PATH}"
            d.add RemoveLeaseWatcherPlist  "${REMOVE_LEASEWATCHER_PLIST}"
            d.add Service ${PSID}
            d.add RouteGatewayIsDhcp       "${ROUTE_GATEWAY_IS_DHCP}"
            d.add TapDeviceHasBeenSetNone  "false"
            d.add bAlsoUsingSetupKeys      "${ALSO_USING_SETUP_KEYS}"
            d.add TunnelDevice             "$dev"
            d.add RestoreIpv6Services      "$IPV6_DISABLED_SERVICES_ENCODED"
            d.add RestoreSecondaryServices "$SECONDARY_DISABLED_SERVICES_ENCODED"

            # Store variables needed by Tunnelblick

            d.add ScriptLogFile                     "${SCRIPT_LOG_FILE}"
            d.add MonitorNetwork                    "${ARG_MONITOR_NETWORK_CONFIGURATION}"
            d.add RestoreOnDNSReset                 "${ARG_RESTORE_ON_DNS_RESET}"
            d.add RestoreOnWINSReset                "${ARG_RESTORE_ON_WINS_RESET}"
            d.add IgnoreOptionFlags                 "${ARG_IGNORE_OPTION_FLAGS}"
            d.add IsTapInterface                    "${ARG_TAP}"
            d.add FlushDNSCache                     "${ARG_FLUSH_DNS_CACHE}"
            d.add ResetPrimaryInterface             "${ARG_RESET_PRIMARY_INTERFACE_ON_DISCONNECT}"
            d.add ResetPrimaryInterfaceOnUnexpected "${ARG_RESET_PRIMARY_INTERFACE_ON_DISCONNECT_UNEXPECTED}"
            d.add ExpectedDnsAddresses              "$FIN_DNS_SA"

            set State:/Network/OpenVPN

EOF

        logMessage "Have written State:/Network/OpenVPN for no DNS changes and to inhibit network monitoring"

 		noChangesState="$( scutil <<-EOF
			open
			show State:/Network/OpenVPN
			quit
EOF
)"

        logDebugMessage "State:/Network/OpenVPN = $noChangesState"
}

##########################################################################################
#
# START OF SCRIPT
#
##########################################################################################

trap "" TSTP
trap "" HUP
trap "" INT
export PATH="/bin:/sbin:/usr/sbin:/usr/bin"

readonly LF="
"
readonly HT="$( printf '\t' )"

readonly OUR_NAME="$( basename "${0}" )"

logMessage "**********************************************"
logMessage "Start of output from ${OUR_NAME}"

logMessage "Primary network service: $( echo_primary_network_service_name )"

# Check variables should have been set up by OpenVPN
# shellcheck disable=SC2154
if [ -z "$dev" ] ; then
	dev=''
	echo "WARNING: \$dev is empty"
fi
# shellcheck disable=SC2154
if [ -z "$config" ] ; then
	config=''
	echo "WARNING: \$config is empty"
fi
# shellcheck disable=SC2154
if [ -z "$route_vpn_gateway" ] ; then
	route_vpn_gateway=''
	echo "WARNING: \$route_vpn_gateway is empty"
fi
# shellcheck disable=SC2154
if [ -z "$script_type" ] ; then
	script_type=''
	echo "WARNING: \$script_type is empty"
fi

# Process optional arguments (if any) for the script
# Each one begins with a "-"
# They come from Tunnelblick, and come first, before the OpenVPN arguments
# So we set ARG_ script variables to their values and shift them out of the argument list
# When we're done, only the OpenVPN arguments remain for the rest of the script to use
ARG_ENABLE_IPV6_ON_TAP="false"
ARG_DISABLE_IPV6_ON_TUN="false"
ARG_DISABLE_SECONDARY_SERVICES_ON_TUN="false"
ARG_TAP="false"
ARG_WAIT_FOR_DHCP_IF_TAP="false"
ARG_RESTORE_ON_DNS_RESET="false"
ARG_FLUSH_DNS_CACHE="false"
ARG_IGNORE_OPTION_FLAGS=""
ARG_EXTRA_LOGGING="false"
ARG_MONITOR_NETWORK_CONFIGURATION="false"
ARG_DO_NO_USE_DEFAULT_DOMAIN="false"
ARG_OVERRIDE_MANUAL_NETWORK_SETTINGS="false"
ARG_PREPEND_DOMAIN_NAME="false"
ARG_RESET_PRIMARY_INTERFACE_ON_DISCONNECT="false"
ARG_RESET_PRIMARY_INTERFACE_ON_DISCONNECT_UNEXPECTED="false"
ARG_TB_PATH="/Applications/Tunnelblick.app"
ARG_RESTORE_ON_WINS_RESET="false"

logDebugMessage "        **********************************************"
logDebugMessage "        ENVIRONMENT VARIABLES:"
logDebugMessage "$( env | sed -e 's/^/        /g' )"
logDebugMessage "        **********************************************"

# Handle the arguments we know about by setting ARG_ script variables to their values, then shift them out
while [ $# -ne 0 ] ; do
    if [ "$1" = "-6" ] ; then                       # -6 = ARG_ENABLE_IPV6_ON_TAP (for TAP connections only)
        ARG_ENABLE_IPV6_ON_TAP="true"
        shift
    elif [ "$1" = "-9" ] ; then                     # -9 = ARG_DISABLE_IPV6_ON_TUN (for TUN connections only)
        ARG_DISABLE_IPV6_ON_TUN="true"
        shift
	elif [ "$1" = "-a" ] ; then						# -a = ARG_TAP
		ARG_TAP="true"
		shift
    elif [ "$1" = "-b" ] ; then                     # -b = ARG_WAIT_FOR_DHCP_IF_TAP
        ARG_WAIT_FOR_DHCP_IF_TAP="true"
        shift
    elif [ "$1" = "-d" ] ; then                     # -d = ARG_RESTORE_ON_DNS_RESET
        ARG_RESTORE_ON_DNS_RESET="true"
        shift
    elif [ "$1" = "-f" ] ; then                     # -f = ARG_FLUSH_DNS_CACHE
        ARG_FLUSH_DNS_CACHE="true"
        shift
	elif [ "${1:0:2}" = "-i" ] ; then				# -i arguments are for leasewatcher
		ARG_IGNORE_OPTION_FLAGS="${1}"
		shift
   elif [ "$1" = "-l" ] ; then                      # -l = ARG_EXTRA_LOGGING
        ARG_EXTRA_LOGGING="true"
        shift
    elif [ "$1" = "-m" ] ; then                     # -m = ARG_MONITOR_NETWORK_CONFIGURATION
		ARG_MONITOR_NETWORK_CONFIGURATION="true"
		shift
    elif [ "$1" = "-n" ] ; then                     # -n = ARG_DO_NO_USE_DEFAULT_DOMAIN
        ARG_DO_NO_USE_DEFAULT_DOMAIN="true"
        shift
    elif [ "$1" = "-o" ] ; then                     # -o = ARG_OVERRIDE_MANUAL_NETWORK_SETTINGS
        ARG_OVERRIDE_MANUAL_NETWORK_SETTINGS="true"
        shift
    elif [ "$1" = "-p" ] ; then                     # -p = ARG_PREPEND_DOMAIN_NAME
		ARG_PREPEND_DOMAIN_NAME="true"
		shift
    elif [ "${1:0:2}" = "-p" ] ; then				# -p arguments are for process-network-changes
		ARG_IGNORE_OPTION_FLAGS="${1}"
		shift
    elif [ "$1" = "-r" ] ; then                     # -r = ARG_RESET_PRIMARY_INTERFACE_ON_DISCONNECT
        ARG_RESET_PRIMARY_INTERFACE_ON_DISCONNECT="true"
        shift
	elif [ "$1" = "-ru" ] ; then                    # -ru = ARG_RESET_PRIMARY_INTERFACE_ON_DISCONNECT_UNEXPECTED
		ARG_RESET_PRIMARY_INTERFACE_ON_DISCONNECT_UNEXPECTED="true"
		shift
    elif [ "${1:0:2}" = "-t" ] ; then
        ARG_TB_PATH="${1:2}"				        # -t path of Tunnelblick.app
        shift
    elif [ "$1" = "-w" ] ; then                     # -w = ARG_RESTORE_ON_WINS_RESET
		ARG_RESTORE_ON_WINS_RESET="true"
		shift
    elif [ "$1" = "-x" ] ; then                     # -x = ARG_DISABLE_SECONDARY_SERVICES_ON_TUN
		ARG_DISABLE_SECONDARY_SERVICES_ON_TUN="true"
		shift
	else
		if [ "${1:0:1}" = "-" ] ; then				# Shift out Tunnelblick arguments (they start with "-") that we don't understand
			shift									# so the rest of the script sees only the OpenVPN arguments
		else
			break
		fi
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

readonly ARG_MONITOR_NETWORK_CONFIGURATION ARG_RESTORE_ON_DNS_RESET ARG_RESTORE_ON_WINS_RESET ARG_TAP ARG_PREPEND_DOMAIN_NAME ARG_FLUSH_DNS_CACHE ARG_RESET_PRIMARY_INTERFACE_ON_DISCONNECT ARG_RESET_PRIMARY_INTERFACE_ON_DISCONNECT_UNEXPECTED ARG_IGNORE_OPTION_FLAGS SCRIPT_ARGS

run_prefix_or_suffix 'up-prefix.sh'


# Note: The script log path name is constructed from the path of the regular config file, not the shadow copy
# if the config is shadow copy, e.g. /Library/Application Support/Tunnelblick/Users/Jonathan/Folder/Subfolder/config.ovpn
# then convert to regular config     /Users/Jonathan/Library/Application Support/Tunnelblick/Configurations/Folder/Subfolder/config.ovpn
#      to get the script log path
# Note: "/Users/..." works even if the home directory has a different path; it is used in the name of the log file, and is not used as a path to get to anything.
readonly TBALTPREFIX="/Library/Application Support/Tunnelblick/Users/"
readonly TBALTPREFIXLEN="${#TBALTPREFIX}"
readonly TBCONFIGSTART="${config:0:$TBALTPREFIXLEN}"
if [ "$TBCONFIGSTART" = "$TBALTPREFIX" ] ; then
	readonly TBBASE="${config:$TBALTPREFIXLEN}"
	readonly TBSUFFIX="${TBBASE#*/}"
	readonly TBUSERNAME="${TBBASE%%/*}"
	readonly TBCONFIG="/Users/$TBUSERNAME/Library/Application Support/Tunnelblick/Configurations/$TBSUFFIX"
else
    readonly TBCONFIG="${config}"
fi

readonly CONFIG_PATH_DASHES_SLASHES="$( echo "${TBCONFIG}" | sed -e 's/-/--/g' | sed -e 's/\//-S/g' )"
readonly SCRIPT_LOG_FILE="/Library/Application Support/Tunnelblick/Logs/${CONFIG_PATH_DASHES_SLASHES}.script.log"

readonly TB_RESOURCES_PATH="${ARG_TB_PATH}/Contents/Resources"
readonly FREE_PUBLIC_DNS_SERVERS_LIST_PATH="${TB_RESOURCES_PATH}/FreePublicDnsServersList.txt"

# These scripts use a launchd .plist to set up to monitor the network configuration.
#
# If Tunnelblick.app is located in /Applications, we load the launchd .plist directly from within the .app.
#
# If Tunnelblick.app is not located in /Applications (i.e., we are debugging), we create a modified version of the launchd .plist and use
# that modified copy in the 'launchctl load' command. (The modification is that the path to process-network-changes or leasewatch program
# in the .plist is changed to point to the copy of the program that is inside the running Tunnelblick.)
#
# The variables involved in this are set up here:
#
#     LEASEWATCHER_PLIST_PATH    is the path of the .plist to use in the 'launchctl load' command
#     LEASEWATCHER_TEMPLATE_PATH is an empty string if we load the .plist directly from within the .app,
#                                or it is the path to the original .plist inside the .app which we copy and modify
#     REMOVE_LEASEWATCHER_PLIST  is "true" if a modified .plist was used and should be deleted after it is unloaded
#                                or "false' if the plist was loaded directly from the .app
#
#     LEASEWATCHER_PLIST_PATH and REMOVE_LEASEWATCHER_PLIST are passed to the other scripts via the scutil State:/Network/OpenVPN mechanism

if [ "${ARG_IGNORE_OPTION_FLAGS:0:2}" = "-p" ] ; then
    readonly LEASEWATCHER_PLIST="ProcessNetworkChanges.plist"
else
    readonly LEASEWATCHER_PLIST="LeaseWatch.plist"
fi
if [ "${ARG_TB_PATH}" = "/Applications/Tunnelblick.app" ] ; then
    readonly LEASEWATCHER_PLIST_PATH="${TB_RESOURCES_PATH}/${LEASEWATCHER_PLIST}"
    readonly LEASEWATCHER_TEMPLATE_PATH=""
    readonly REMOVE_LEASEWATCHER_PLIST="false"
else
    readonly LEASEWATCHER_PLIST_PATH="/Library/Application Support/Tunnelblick/${LEASEWATCHER_PLIST}"
    readonly LEASEWATCHER_TEMPLATE_PATH="${TB_RESOURCES_PATH}/${LEASEWATCHER_PLIST}"
    readonly REMOVE_LEASEWATCHER_PLIST="true"
fi

set +e # "grep" will return error status (1) if no matches are found, so don't fail on individual errors
	readonly OSVER="$( sw_vers | grep 'ProductVersion:' | grep -o '10\.[0-9]*' )"
set -e # We instruct bash that it CAN again fail on errors

if ${ARG_DO_NO_USE_DEFAULT_DOMAIN} ; then
    readonly DEFAULT_DOMAIN_NAME=""
else
    readonly DEFAULT_DOMAIN_NAME="openvpn"
fi

ROUTE_GATEWAY_IS_DHCP="false"

# We sleep to allow time for macOS to process network settings
sleep 2

EXIT_CODE=0

if ${ARG_TAP} ; then

    # IPv6 should be re-enabled only for TUN, not TAP; the same for secondary network services
    readonly IPV6_DISABLED_SERVICES_ENCODED=""
    readonly SECONDARY_DISABLED_SERVICES_ENCODED=""

    if ${ARG_DISABLE_SECONDARY_SERVICES_ON_TUN} ; then
        logMessage "WARNING: Will NOT disable secondary services because this is a TAP configuration."
    fi

	# If _any_ DHCP info (such as DNS) is provided by the OpenVPN server or the client configuration file (via "dhcp-option"), use it
	# Otherwise, use DHCP to get DNS if possible, or do nothing about DNS

	# "foreign_option_n" variables __may or may not__ set up by OpenVPN
	# shellcheck disable=SC2154
	if [ -n "$foreign_option_1" ]; then
		if ${ARG_ENABLE_IPV6_ON_TAP} ; then
			logMessage "WARNING: Will NOT set up IPv6 on TAP device because it does not use DHCP."
		fi
		logMessage "Configuring tap DNS via OpenVPN"
		configureOpenVpnDns
		EXIT_CODE=$?
	else
		if [ -z "${route_vpn_gateway}" ] || [ "$route_vpn_gateway" == "dhcp" ] || [ "$route_vpn_gateway" == "DHCP" ]; then
			# Check if $dev already has an ip configuration
			hasIp="$(ifconfig "$dev" | grep inet | cut -d ' ' -f 2)"
			if [ "${hasIp}" ]; then
				logMessage "Not using DHCP because $dev already has an IP configuration ($hasIp). route_vpn_gateway = '$route_vpn_gateway'"
			else
				ROUTE_GATEWAY_IS_DHCP="true"
				logMessage "Using DHCP because route_vpn_gateway = '$route_vpn_gateway' and there $dev has no IP configuration"
			fi
		fi
		if [ "$ROUTE_GATEWAY_IS_DHCP" == "true" ]; then
			logDebugMessage "ROUTE_GATEWAY_IS_DHCP is TRUE"
			if [ -z "$dev" ]; then
				logMessage "ERROR: Cannot configure TAP interface for DHCP without \$dev being defined. Exiting."
				# We don't create the "/Library/Application Support/Tunnelblick/downscript-needs-to-be-run.txt" file, because the down script does NOT need to be run since we didn't do anything
				run_prefix_or_suffix 'up-suffix.sh'
				logMessage "End of output from ${OUR_NAME}"
				logMessage "**********************************************"
				exit 1
			fi

			if [ "$script_type" != "route-up" ] ; then
				logMessage "WARNING: Tap connection using DHCP but 'Set DNS after routes are set' is not set in Tunnelblick's Advanced settings window (script_type = '$script_type')"
			fi

			logDebugMessage "About to 'ipconfig set \"$dev\" DHCP"
			ipconfig set "$dev" DHCP
			logMessage "Did 'ipconfig set \"$dev\" DHCP'"

			if ${ARG_ENABLE_IPV6_ON_TAP} ; then
				ipconfig set "$dev" AUTOMATIC-V6
				logMessage "Did 'ipconfig set \"$dev\" AUTOMATIC-V6'"
			fi

			if ${ARG_WAIT_FOR_DHCP_IF_TAP} ; then
				logMessage "Configuring tap DNS via DHCP synchronously"
				configureDhcpDns
			else
				logMessage "Configuring tap DNS via DHCP asynchronously"
				configureDhcpDns & # This must be run asynchronously; the DHCP lease will not complete until this script exits
				EXIT_CODE=0
			fi
		else
			logMessage "NOTE: No network configuration changes need to be made."
			if ${ARG_MONITOR_NETWORK_CONFIGURATION} ; then
				logMessage "WARNING: Will NOT monitor for other network configuration changes."
			fi
			if ${ARG_ENABLE_IPV6_ON_TAP} ; then
				logMessage "WARNING: Will NOT set up IPv6 on TAP device because it does not use DHCP."
			fi
			notMakingDnsChanges
			flushDNSCache
		fi
	fi
else

    # TUN

	disableIPv6AndSecondaryServices

	if [ "$foreign_option_1" == "" ]; then

        notMakingDnsChanges
        flushDNSCache

        EXIT_CODE=0
	else

		configureOpenVpnDns

		EXIT_CODE=$?
	fi
fi

touch "/Library/Application Support/Tunnelblick/downscript-needs-to-be-run.txt"

run_prefix_or_suffix 'up-suffix.sh'

logMessage "End of output from ${OUR_NAME}"
logMessage "**********************************************"

exit $EXIT_CODE
