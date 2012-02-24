#!/bin/bash -e
# Note: must be bash; uses bash-specific tricks
#
# ******************************************************************************************************************
# This Tunnelblick script does everything! It handles TUN and TAP interfaces, 
# pushed configurations, DHCP with DNS and WINS, and renewed DHCP leases. :)
# 
# This is the "Up" version of the script, executed after the interface is 
# initialized.
#
# Created by: Nick Williams (using original code and parts of old Tblk scripts)
# 
# ******************************************************************************************************************

trap "" TSTP
trap "" HUP
trap "" INT
export PATH="/bin:/sbin:/usr/sbin:/usr/bin"

# Process optional arguments (if any) for the script
# Each one begins with a "-"
# They come from Tunnelblick, and come first, before the OpenVPN arguments
# So we set ARG_ script variables to their values and shift them out of the argument list
# When we're done, only the OpenVPN arguments remain for the rest of the script to use
ARG_MONITOR_NETWORK_CONFIGURATION="false"
ARG_RESTORE_ON_DNS_RESET="false"
ARG_RESTORE_ON_WINS_RESET="false"
ARG_TAP="false"
ARG_IGNORE_OPTION_FLAGS=""

while [ {$#} ] ; do
	if [ "$1" = "-m" ] ; then						# Handle the arguments we know about
		ARG_MONITOR_NETWORK_CONFIGURATION="true"	# by setting ARG_ script variables to their values
		shift										# Then shift them out
	elif [ "$1" = "-d" ] ; then
		ARG_RESTORE_ON_DNS_RESET="true"
		shift
	elif [ "$1" = "-w" ] ; then
		ARG_RESTORE_ON_WINS_RESET="true"
		shift
	elif [ "$1" = "-a" ] ; then
		ARG_TAP="true"
		shift
	elif [ "${1:0:2}" = "-i" ] ; then
		ARG_IGNORE_OPTION_FLAGS="${1}"
		shift
	elif [ "${1:0:2}" = "-a" ] ; then
		ARG_IGNORE_OPTION_FLAGS="${1}"
		shift
	else
		if [ "${1:0:1}" = "-" ] ; then				# Shift out Tunnelblick arguments (they start with "-") that we don't understand
			shift									# so the rest of the script sees only the OpenVPN arguments
		else
			break
		fi
	fi
done

readonly ARG_MONITOR_NETWORK_CONFIGURATION ARG_RESTORE_ON_DNS_RESET ARG_RESTORE_ON_WINS_RESET ARG_TAP ARG_IGNORE_OPTION_FLAGS

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

readonly CONFIG_PATH_DASHES_SLASHES="$(echo "${TBCONFIG}" | sed -e 's/-/--/g' | sed -e 's/\//-S/g')"
readonly SCRIPT_LOG_FILE="/Library/Application Support/Tunnelblick/Logs/${CONFIG_PATH_DASHES_SLASHES}.script.log"

readonly TB_RESOURCE_PATH=$(dirname "${0}")

LEASEWATCHER_PLIST_PATH="/Library/Application Support/Tunnelblick/LeaseWatch.plist"

readonly OSVER="$(sw_vers | grep 'ProductVersion:' | grep -o '10\.[0-9]*')"

readonly DEFAULT_DOMAIN_NAME="openvpn"

bRouteGatewayIsDhcp="false"

# @param String message - The message to log
readonly LOG_MESSAGE_COMMAND=$(basename "${0}")
logMessage()
{
	echo "$(date '+%a %b %e %T %Y') *Tunnelblick $LOG_MESSAGE_COMMAND: "${@} >> "${SCRIPT_LOG_FILE}"
}

# @param String string - Content to trim
trim()
{
	echo ${@}
}

# @param String[] dnsServers - The name servers to use
# @param String domainName - The domain name to use
# @param \optional String[] winsServers - The WINS servers to use
setDnsServersAndDomainName()
{
	declare -a vDNS=("${!1}")
	domain=$2
	declare -a vWINS=("${!3}")
	
	set +e # "grep" will return error status (1) if no matches are found, so don't fail on individual errors
	
	PSID=$( (scutil | grep PrimaryService | sed -e 's/.*PrimaryService : //')<<- EOF
		open
		show State:/Network/Global/IPv4
		quit
EOF )
	
	STATIC_DNS_CONFIG="$( (scutil | sed -e 's/^[[:space:]]*[[:digit:]]* : //g' | tr '\n' ' ')<<- EOF
		open
		show Setup:/Network/Service/${PSID}/DNS
		quit
EOF )"
	if echo "${STATIC_DNS_CONFIG}" | grep -q "ServerAddresses" ; then
		readonly STATIC_DNS="$(trim "$( echo "${STATIC_DNS_CONFIG}" | sed -e 's/^.*ServerAddresses[^{]*{[[:space:]]*\([^}]*\)[[:space:]]*}.*$/\1/g' )")"
	fi
	if echo "${STATIC_DNS_CONFIG}" | grep -q "SearchDomains" ; then
		readonly STATIC_SEARCH="$(trim "$( echo "${STATIC_DNS_CONFIG}" | sed -e 's/^.*SearchDomains[^{]*{[[:space:]]*\([^}]*\)[[:space:]]*}.*$/\1/g' )")"
	fi
	
	STATIC_WINS_CONFIG="$( (scutil | sed -e 's/^[[:space:]]*[[:digit:]]* : //g' | tr '\n' ' ')<<- EOF
		open
		show Setup:/Network/Service/${PSID}/SMB
		quit
EOF )"
    STATIC_WINS_SERVERS=""
    STATIC_WORKGROUP=""
    STATIC_NETBIOSNAME=""
    if echo "${STATIC_WINS_CONFIG}" | grep -q "WINSAddresses" ; then
        STATIC_WINS_SERVERS="$(trim "$( echo "${STATIC_WINS_CONFIG}" | sed -e 's/^.*WINSAddresses[^{]*{[[:space:]]*\([^}]*\)[[:space:]]*}.*$/\1/g' )")"
    fi
    if echo "${STATIC_WINS_CONFIG}" | grep -q "Workgroup" ; then
        STATIC_WORKGROUP="$(trim "$( echo "${STATIC_WINS_CONFIG}" | sed -e 's/^.*Workgroup : \([^[:space:]]*\).*$/\1/g' )")"
    fi
    if echo "${STATIC_WINS_CONFIG}" | grep -q "NetBIOSName" ; then
        STATIC_NETBIOSNAME="$(trim "$( echo "${STATIC_WINS_CONFIG}" | sed -e 's/^.*NetBIOSName : \([^[:space:]]*\).*$/\1/g' )")"
    fi
    readonly STATIC_WINS_SERVERS STATIC_WORKGROUP STATIC_NETBIOSNAME
    
	if [ ${#vDNS[*]} -eq 0 ] ; then
		DYN_DNS="false"
		ALL_DNS="${STATIC_DNS}"
	elif [ -n "${STATIC_DNS}" ] ; then
		case "${OSVER}" in
			10.6 | 10.7 )
				# Do nothing - in 10.6 we don't aggregate our configurations, apparently
				DYN_DNS="false"
				ALL_DNS="${STATIC_DNS}"
				;;
			10.4 | 10.5 )
				DYN_DNS="true"
				# We need to remove duplicate DNS entries, so that our reference list matches MacOSX's
				SDNS="$(echo "${STATIC_DNS}" | tr ' ' '\n')"
				(( i=0 ))
				for n in "${vDNS[@]}" ; do
					if echo "${SDNS}" | grep -q "${n}" ; then
						unset vDNS[${i}]
					fi
					(( i++ ))
				done
				if [ ${#vDNS[*]} -gt 0 ] ; then
					ALL_DNS="$(trim "${STATIC_DNS}" "${vDNS[*]}")"
				else
					DYN_DNS="false"
					ALL_DNS="${STATIC_DNS}"
				fi
				;;
		esac
	else
		DYN_DNS="true"
		ALL_DNS="$(trim "${vDNS[*]}")"
	fi
	readonly DYN_DNS ALL_DNS

	if [ ${#vWINS[*]} -eq 0 ] ; then
		DYN_WINS="false"
		ALL_WINS_SERVERS="${STATIC_WINS_SERVERS}"
	elif [ -n "${STATIC_WINS_SERVERS}" ] ; then
		case "${OSVER}" in
			10.6 | 10.7 )
				# Do nothing - in 10.6 we don't aggregate our configurations, apparently
				DYN_WINS="false"
				ALL_WINS_SERVERS="${STATIC_WINS_SERVERS}"
				;;
			10.4 | 10.5 )
				DYN_WINS="true"
				# We need to remove duplicate WINS entries, so that our reference list matches MacOSX's
				SWINS="$(echo "${STATIC_WINS_SERVERS}" | tr ' ' '\n')"
				(( i=0 ))
				for n in "${vWINS[@]}" ; do
					if echo "${SWINS}" | grep -q "${n}" ; then
						unset vWINS[${i}]
					fi
					(( i++ ))
				done
				if [ ${#vWINS[*]} -gt 0 ] ; then
					ALL_WINS_SERVERS="$(trim "${STATIC_WINS_SERVERS}" "${vWINS[*]}")"
				else
					DYN_WINS="false"
					ALL_WINS_SERVERS="${STATIC_WINS_SERVERS}"
				fi
				;;
		esac
	else
		DYN_WINS="true"
		ALL_WINS_SERVERS="$(trim "${vWINS[*]}")"
	fi
	readonly DYN_WINS ALL_WINS_SERVERS

	# We double-check that our search domain isn't already on the list
	SEARCH_DOMAIN="${domain}"
	case "${OSVER}" in
		10.6 | 10.7 )
			# Do nothing - in 10.6 we don't aggregate our configurations, apparently
			if [ -n "${STATIC_SEARCH}" ] ; then
				ALL_SEARCH="${STATIC_SEARCH}"
				SEARCH_DOMAIN=""
			else
				ALL_SEARCH="${SEARCH_DOMAIN}"
			fi
			;;
		10.4 | 10.5 )
			if echo "${STATIC_SEARCH}" | tr ' ' '\n' | grep -q "${SEARCH_DOMAIN}" ; then
				SEARCH_DOMAIN=""
			fi
			if [ -z "${SEARCH_DOMAIN}" ] ; then
				ALL_SEARCH="${STATIC_SEARCH}"
			else
				ALL_SEARCH="$(trim "${STATIC_SEARCH}" "${SEARCH_DOMAIN}")"
			fi
			;;
	esac
	readonly SEARCH_DOMAIN ALL_SEARCH

	if ! ${DYN_DNS} ; then
		NO_DNS="#"
	fi
	if ! ${DYN_WINS} ; then
		NO_WS="#"
	fi
	if [ -z "${SEARCH_DOMAIN}" ] ; then
		NO_SEARCH="#"
	fi
	if [ -z "${STATIC_WORKGROUP}" ] ; then
		NO_WG="#"
	fi
	if [ -z "${STATIC_NETBIOSNAME}" ] ; then
		NO_NB="#"
	fi
	if [ -z "${ALL_DNS}" ] ; then
		AGG_DNS="#"
	fi
	if [ -z "${ALL_SEARCH}" ] ; then
		AGG_SEARCH="#"
	fi
	if [ -z "${ALL_WINS_SERVERS}" ] ; then
		AGG_WINS="#"
	fi
	
	# Now, do the aggregation
	# Save the openvpn process ID and the Network Primary Service ID, leasewather.plist path, logfile path, and optional arguments from Tunnelblick,
	# then save old and new DNS and WINS settings
	# PPID is a bash-script variable that contains the process ID of the parent of the process running the script (i.e., OpenVPN's process ID)
	# config is an environmental variable set to the configuration path by OpenVPN prior to running this up script
	logMessage "Up to two 'No such key' warnings are normal and may be ignored"
	
	# If DNS is manually set, it overrides the DHCP setting, which isn't reflected in 'State:/Network/Service/${PSID}/DNS'
	if echo "${STATIC_DNS_CONFIG}" | grep -q "ServerAddresses" ; then
		CORRECT_OLD_DNS_KEY="Setup:"
	else
		CORRECT_OLD_DNS_KEY="State:"
	fi
	
	# If WINS is manually set, it overrides the DHCP setting, which isn't reflected in 'State:/Network/Service/${PSID}/DNS'
	if echo "${STATIC_WINS_CONFIG}" | grep -q "WINSAddresses" ; then
		CORRECT_OLD_WINS_KEY="Setup:"
	else
		CORRECT_OLD_WINS_KEY="State:"
	fi
	
    # If we are not expecting any WINS value, add <TunnelblickNoSuchKey : true> to the expected WINS setup
    NO_NOSUCH_KEY_WINS="#"
    if [ "${NO_NB}" = "#" -a "${AGG_WINS}" = "#" -a "${NO_WG}" = "#" ] ; then
        NO_NOSUCH_KEY_WINS=""
    fi
    readonly NO_NOSUCH_KEY_WINS
    
	set -e # We instruct bash that it CAN again fail on errors

	scutil <<- EOF
		open
		d.init
		d.add PID # ${PPID}
		d.add Service ${PSID}
		d.add LeaseWatcherPlistPath "${LEASEWATCHER_PLIST_PATH}"
		d.add ScriptLogFile         "${SCRIPT_LOG_FILE}"
		d.add MonitorNetwork        "${ARG_MONITOR_NETWORK_CONFIGURATION}"
		d.add RestoreOnDNSReset     "${ARG_RESTORE_ON_DNS_RESET}"
		d.add RestoreOnWINSReset    "${ARG_RESTORE_ON_WINS_RESET}"
		d.add IgnoreOptionFlags     "${ARG_IGNORE_OPTION_FLAGS}"
		d.add IsTapInterface        "${ARG_TAP}"
		d.add RouteGatewayIsDhcp    "${bRouteGatewayIsDhcp}"
		set State:/Network/OpenVPN
		
		# First, back up the device's current DNS and WINS configurations
		# Indicate 'no such key' by a dictionary with a single entry: "TunnelblickNoSuchKey : true"
		d.init
		d.add TunnelblickNoSuchKey true
		get ${CORRECT_OLD_DNS_KEY}/Network/Service/${PSID}/DNS
		set State:/Network/OpenVPN/OldDNS
		
		d.init
		d.add TunnelblickNoSuchKey true
		get ${CORRECT_OLD_WINS_KEY}/Network/Service/${PSID}/SMB
		set State:/Network/OpenVPN/OldSMB
		
		# Second, initialize the new DNS map
		d.init
		${NO_DNS}d.add ServerAddresses * ${vDNS[*]}
		${NO_SEARCH}d.add SearchDomains * ${SEARCH_DOMAIN}
		d.add DomainName ${domain}
		set State:/Network/Service/${PSID}/DNS
		
		# Third, initialize the WINS map
		d.init
		${NO_NB}d.add NetBIOSName ${STATIC_NETBIOSNAME}
		${NO_WS}d.add WINSAddresses * ${vWINS[*]}
		${NO_WG}d.add Workgroup ${STATIC_WORKGROUP}
		set State:/Network/Service/${PSID}/SMB
		
		# Now, initialize the maps that will be compared against the system-generated map
		# which means that we will have to aggregate configurations of statically-configured
		# nameservers, and statically-configured search domains
		d.init
		${AGG_DNS}d.add ServerAddresses * ${ALL_DNS}
		${AGG_SEARCH}d.add SearchDomains * ${ALL_SEARCH}
		d.add DomainName ${domain}
		set State:/Network/OpenVPN/DNS
		
		d.init
		${NO_NB}d.add NetBIOSName ${STATIC_NETBIOSNAME}
		${AGG_WINS}d.add WINSAddresses * ${ALL_WINS_SERVERS}
		${NO_WG}d.add Workgroup ${STATIC_WORKGROUP}
        ${NO_NOSUCH_KEY_WINS}d.add TunnelblickNoSuchKey true
		set State:/Network/OpenVPN/SMB
		
		# We are done
		quit
EOF
	
	logMessage "Saved the DNS and WINS configurations for later use"
	
	if ${ARG_MONITOR_NETWORK_CONFIGURATION} ; then
        if [ "${ARG_IGNORE_OPTION_FLAGS:0:2}" = "-a" ] ; then
            # Generate an updated plist with the path for process-network-changes
            readonly LEASEWATCHER_TEMPLATE_PATH="$(dirname "${0}")/ProcessNetworkChanges.plist.template"
            sed -e "s|\${DIR}|$(dirname "${0}")|g" "${LEASEWATCHER_TEMPLATE_PATH}" > "${LEASEWATCHER_PLIST_PATH}"
            launchctl load "${LEASEWATCHER_PLIST_PATH}"
            logMessage "Set up to monitor system configuration with process-network-changes"
        else
            # Generate an updated plist with the path for leasewatch
            readonly LEASEWATCHER_TEMPLATE_PATH="$(dirname "${0}")/LeaseWatch.plist.template"
            sed -e "s|\${DIR}|$(dirname "${0}")|g" "${LEASEWATCHER_TEMPLATE_PATH}" > "${LEASEWATCHER_PLIST_PATH}"
            launchctl load "${LEASEWATCHER_PLIST_PATH}"
            logMessage "Set up to monitor system configuration with leasewatch"
        fi
	fi
}

configureDhcpDns()
{
	# whilst ipconfig will have created the neccessary Network Service keys, the DNS
	# settings won't actually be used by OS X unless the SupplementalMatchDomains key
	# is added
	# ref. <http://lists.apple.com/archives/Macnetworkprog/2005/Jun/msg00011.html>
	# - is there a way to extract the domains from the SC dictionary and re-insert
	#   as SupplementalMatchDomains? i.e. not requiring the ipconfig domain_name call?
	
	# - wait until we get a lease before extracting the DNS domain name and merging into SC
	# - despite it's name, ipconfig waitall doesn't (but maybe one day it will :-)
	ipconfig waitall
	
	unset test_domain_name
	unset test_name_server
	
	set +e # We instruct bash NOT to exit on individual command errors, because if we need to wait longer these commands will fail
	
	# usually takes at least a few seconds to get a DHCP lease
	sleep 3
	n=0
	while [ -z "$test_domain_name" -a -z "$test_name_server" -a $n -lt 5 ]
	do
		logMessage "Sleeping for $n seconds to wait for DHCP to finish setup."
		sleep $n
		n=`expr $n + 1`
		
		if [ -z "$test_domain_name" ]; then
			test_domain_name=`ipconfig getoption $dev domain_name 2>/dev/null`
		fi
		
		if [ -z "$test_name_server" ]; then
			test_name_server=`ipconfig getoption $dev domain_name_server 2>/dev/null`
		fi
	done
	
	sGetPacketOutput=`ipconfig getpacket $dev`
	
	set -e # We instruct bash that it CAN again fail on individual errors
	
	#echo "`date` test_domain_name = $test_domain_name, test_name_server = $test_name_server, sGetPacketOutput = $sGetPacketOutput"
	
	unset aNameServers
	unset aWinsServers
	
	nNameServerIndex=1
	nWinsServerIndex=1
	
	if [ "$sGetPacketOutput" ]; then
		sGetPacketOutput_FirstLine=`echo "$sGetPacketOutput"|head -n 1`
		#echo $sGetPacketOutput_FirstLine
		
		if [ "$sGetPacketOutput_FirstLine" == "op = BOOTREPLY" ]; then
			set +e # "grep" will return error status (1) if no matches are found, so don't fail on individual errors
			
			for tNameServer in `echo "$sGetPacketOutput"|grep "domain_name_server"|grep -Eo "\{([0-9\.]+)(, [0-9\.]+)*\}"|grep -Eo "([0-9\.]+)"`; do
				aNameServers[nNameServerIndex-1]="$(trim "$tNameServer")"
				let nNameServerIndex++
			done
			
			for tWINSServer in `echo "$sGetPacketOutput"|grep "nb_over_tcpip_name_server"|grep -Eo "\{([0-9\.]+)(, [0-9\.]+)*\}"|grep -Eo "([0-9\.]+)"`; do
				aWinsServers[nWinsServerIndex-1]="$(trim "$tWINSServer")"
				let nWinsServerIndex++
			done
			
			sDomainName=`echo "$sGetPacketOutput"|grep "domain_name "|grep -Eo ": [-A-Za-z0-9\-\.]+"|grep -Eo "[-A-Za-z0-9\-\.]+"`
			sDomainName="$(trim "$sDomainName")"
			
			if [ ${#aNameServers[*]} -gt 0 -a "$sDomainName" ]; then
				logMessage "Retrieved name server(s) [ ${aNameServers[@]} ], domain name [ $sDomainName ], and WINS server(s) [ ${aWinsServers[@]} ]"
				setDnsServersAndDomainName aNameServers[@] "$sDomainName" aWinsServers[@]
				return 0
			elif [ ${#aNameServers[*]} -gt 0 ]; then
				logMessage "Retrieved name server(s) [ ${aNameServers[@]} ] and WINS server(s) [ ${aWinsServers[@]} ] and using default domain name [ $DEFAULT_DOMAIN_NAME ]"
				setDnsServersAndDomainName aNameServers[@] "$DEFAULT_DOMAIN_NAME" aWinsServers[@]
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
	fi
	
	unset sDomainName
	unset sNameServer
	unset aNameServers
	
	sDomainName=`ipconfig getoption $dev domain_name 2>/dev/null`
	sNameServer=`ipconfig getoption $dev domain_name_server 2>/dev/null`
	
	sDomainName="$(trim "$sDomainName")"
	sNameServer="$(trim "$sNameServer")"
	
	declare -a aWinsServers=( ) # Declare empty WINS array to avoid any useless error messages
	
	if [ "$sDomainName" -a "$sNameServer" ]; then
		aNameServers[0]=$sNameServer
		logMessage "Retrieved name server [ $sNameServer ], domain name [ $sDomainName ], and no WINS servers"
		setDnsServersAndDomainName aNameServers[@] "$sDomainName" aWinsServers[@]
	elif [ "$sNameServer" ]; then
		aNameServers[0]=$sNameServer
		logMessage "Retrieved name server [ $sNameServer ] and no WINS servers, and using default domain name [ $DEFAULT_DOMAIN_NAME ]"
		setDnsServersAndDomainName aNameServers[@] "$DEFAULT_DOMAIN_NAME" aWinsServers[@]
	elif [ "$sDomainName" ]; then
		logMessage "WARNING: Retrieved domain name [ $sDomainName ] but no name servers from OpenVPN (DHCP), which is not sufficient to make network/DNS configuration changes."
		if ${ARG_MONITOR_NETWORK_CONFIGURATION} ; then
			logMessage "Will NOT monitor for other network configuration changes."
		fi
	else
		logMessage "WARNING: No DNS information received from OpenVPN (DHCP), so no network/DNS configuration changes need to be made."
		if ${ARG_MONITOR_NETWORK_CONFIGURATION} ; then
			logMessage "Will NOT monitor for other network configuration changes."
		fi
	fi
	
	return 0
}

configureOpenVpnDns()
{
	unset vForOptions
	unset vOptions
	unset aNameServers
	unset aWinsServers
	
	nOptionIndex=1
	nNameServerIndex=1
	nWinsServerIndex=1

	while vForOptions=foreign_option_$nOptionIndex; [ -n "${!vForOptions}" ]; do
		vOptions[nOptionIndex-1]=${!vForOptions}
		case ${vOptions[nOptionIndex-1]} in
			*DOMAIN* )
				sDomainName="$(trim "${vOptions[nOptionIndex-1]//dhcp-option DOMAIN /}")"
				;;
			*DNS*    )
				aNameServers[nNameServerIndex-1]="$(trim "${vOptions[nOptionIndex-1]//dhcp-option DNS /}")"
				let nNameServerIndex++
				;;
			*WINS*   )
				aWinsServers[nWinsServerIndex-1]="$(trim "${vOptions[nOptionIndex-1]//dhcp-option WINS /}")"
				let nWinsServerIndex++
				;;
            *   )
                logMessage "Unknown: 'foreign_option_${nOptionIndex}' = '${vOptions[nOptionIndex-1]}'"
                ;;
		esac
		let nOptionIndex++
	done
	
	if [ ${#aNameServers[*]} -gt 0 -a "$sDomainName" ]; then
		logMessage "Retrieved name server(s) [ ${aNameServers[@]} ], domain name [ $sDomainName ], and WINS server(s) [ ${aWinsServers[@]} ]"
		setDnsServersAndDomainName aNameServers[@] "$sDomainName" aWinsServers[@]
	elif [ ${#aNameServers[*]} -gt 0 ]; then
		logMessage "Retrieved name server(s) [ ${aNameServers[@]} ] and WINS server(s) [ ${aWinsServers[@]} ] and using default domain name [ $DEFAULT_DOMAIN_NAME ]"
		setDnsServersAndDomainName aNameServers[@] "$DEFAULT_DOMAIN_NAME" aWinsServers[@]
	else
		# Should we maybe just return 1 here to indicate an error? Does this mean that something bad has happened?
		logMessage "No DNS information recieved from OpenVPN, so no network configuration changes need to be made."
		if ${ARG_MONITOR_NETWORK_CONFIGURATION} ; then
			logMessage "Will NOT monitor for other network configuration changes."
		fi
	fi
	
	return 0
}

# We sleep here to allow time for OS X to process network settings
sleep 2

EXIT_CODE=0

if ${ARG_TAP} ; then
	# Still need to do: Look for route-gateway dhcp (TAP isn't always DHCP)
	bRouteGatewayIsDhcp="false"
	if [ -z "${route_vpn_gateway}" -o "$route_vpn_gateway" == "dhcp" -o "$route_vpn_gateway" == "DHCP" ]; then
		bRouteGatewayIsDhcp="true"
	fi
	
	if [ "$bRouteGatewayIsDhcp" == "true" ]; then
		if [ -z "$dev" ]; then
			logMessage "Cannot configure TAP interface for DHCP without \$dev being defined. Exiting."
			exit 1
		fi
		
		ipconfig set "$dev" DHCP
		
		configureDhcpDns &
	elif [ "$foreign_option_1" == "" ]; then
		logMessage "No network configuration changes need to be made."
		if ${ARG_MONITOR_NETWORK_CONFIGURATION} ; then
			logMessage "Will NOT monitor for other network configuration changes."
		fi
	else
		configureOpenVpnDns
		EXIT_CODE=$?
	fi
else
	if [ "$foreign_option_1" == "" ]; then
		logMessage "No network configuration changes need to be made."
		if ${ARG_MONITOR_NETWORK_CONFIGURATION} ; then
			logMessage "Will NOT monitor for other network configuration changes."
		fi
	else
		configureOpenVpnDns
		EXIT_CODE=$?
	fi
fi

exit $EXIT_CODE
