#!/bin/bash -e
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
    if [  "$1" = "-m" ] ; then                              # Handle the arguments we know about
        ARG_MONITOR_NETWORK_CONFIGURATION="true"            # by setting ARG_ script variables to their values
        shift                                               # Then shift them out
    elif [  "$1" = "-d" ] ; then
        ARG_RESTORE_ON_DNS_RESET="true"
        shift
    elif [  "$1" = "-w" ] ; then
        ARG_RESTORE_ON_WINS_RESET="true"
        shift
    elif [  "$1" = "-a" ] ; then
        ARG_TAP="true"
        shift
    elif [  "${1:0:2}" = "-i" ] ; then
        ARG_IGNORE_OPTION_FLAGS="${1}"
        shift
    else
        if [  "${1:0:1}" = "-" ] ; then                     # Shift out Tunnelblick arguments (they start with "-") that we don't understand
            shift                                           # so the rest of the script sees only the OpenVPN arguments                            
        else
            break
        fi
    fi
done

TBCONFIG="$config"
# Note: The script log path name is constructed from the path of the regular config file, not the shadow copy
# if the config is shadow copy, e.g. /Library/Application Support/Tunnelblick/Users/Jonathan/Folder/Subfolder/config.ovpn
# then convert to regular config     /Users/Jonathan/Library/Application Support/Tunnelblick/Configurations/Folder/Subfolder/config.ovpn
#      to get the script log path
# "/Users/..." works even if the home directory has a different path; it is used in the name of the log file, and is not used as a path to get to anything.
TBALTPREFIX="/Library/Application Support/Tunnelblick/Users/"
TBALTPREFIXLEN="${#TBALTPREFIX}"
TBCONFIGSTART="${TBCONFIG:0:$TBALTPREFIXLEN}"
if [ "$TBCONFIGSTART" = "$TBALTPREFIX" ] ; then
    TBBASE="${TBCONFIG:$TBALTPREFIXLEN}"
    TBSUFFIX="${TBBASE#*/}"
    TBUSERNAME="${TBBASE%%/*}"
    TBCONFIG="/Users/$TBUSERNAME/Library/Application Support/Tunnelblick/Configurations/$TBSUFFIX"
fi

CONFIG_PATH_DASHES_SLASHES="$(echo "${TBCONFIG}" | sed -e 's/-/--/g' | sed -e 's/\//-S/g')"
SCRIPT_LOG_FILE="/Library/Application Support/Tunnelblick/Logs/${CONFIG_PATH_DASHES_SLASHES}.script.log"

# Do something only if the server pushed something
if [ "$foreign_option_1" == "" ]; then
    echo "$(date '+%a %b %e %T %Y') *Tunnelblick client.up.tunnelblick.sh: No network configuration changes need to be made" >> "${SCRIPT_LOG_FILE}"
    if ${ARG_MONITOR_NETWORK_CONFIGURATION} ; then
        echo "$(date '+%a %b %e %T %Y') *Tunnelblick client.up.tunnelblick.sh: Will NOT monitor for other network configuration changes" >> "${SCRIPT_LOG_FILE}"
    fi
	exit 0
fi

trim() {
	echo ${@}
}

LEASEWATCHER_PLIST_PATH="/Library/Application Support/Tunnelblick/LeaseWatch.plist"

OSVER="$(sw_vers | grep 'ProductVersion:' | grep -o '10\.[0-9]*')"

nOptionIndex=1
nNameServerIndex=1
nWINSServerIndex=1
unset vForOptions
unset vDNS
unset vWINS
unset vOptions

while vForOptions=foreign_option_$nOptionIndex; [ -n "${!vForOptions}" ]; do
	{
	vOptions[nOptionIndex-1]=${!vForOptions}
	case ${vOptions[nOptionIndex-1]} in
		*DOMAIN* )
			domain="$(trim "${vOptions[nOptionIndex-1]//dhcp-option DOMAIN /}")"
			;;
		*DNS*    )
			vDNS[nNameServerIndex-1]="$(trim "${vOptions[nOptionIndex-1]//dhcp-option DNS /}")"
			let nNameServerIndex++
			;;
		*WINS*    )
			vWINS[nWINSServerIndex-1]="$(trim "${vOptions[nOptionIndex-1]//dhcp-option WINS /}")"
			let nWINSServerIndex++
			;;
	esac
	let nOptionIndex++
	}
done

# set domain to a default value when no domain is being transmitted
if [ "$domain" == "" ]; then
	domain="openvpn"
fi

PSID=$( (scutil | grep PrimaryService | sed -e 's/.*PrimaryService : //')<<- EOF
	open
	show State:/Network/Global/IPv4
	quit
EOF
)

STATIC_DNS_CONFIG="$( (scutil | sed -e 's/^[[:space:]]*[[:digit:]]* : //g' | tr '\n' ' ')<<- EOF
	open
	show Setup:/Network/Service/${PSID}/DNS
	quit
EOF
)"
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
EOF
)"
if echo "${STATIC_WINS_CONFIG}" | grep -q "WINSAddresses" ; then
	readonly STATIC_WINS="$(trim "$( echo "${STATIC_WINS_CONFIG}" | sed -e 's/^.*WINSAddresses[^{]*{[[:space:]]*\([^}]*\)[[:space:]]*}.*$/\1/g' )")"
fi
if [ -n "${STATIC_WINS_CONFIG}" ] ; then
	readonly STATIC_WORKGROUP="$(trim "$( echo "${STATIC_WINS_CONFIG}" | sed -e 's/^.*Workgroup : \([^[:space:]]*\).*$/\1/g' )")"
fi
if echo "${STATIC_WINS_CONFIG}" | grep -q "NetBIOSName" ; then
	readonly STATIC_NETBIOSNAME="$(trim "$( echo "${STATIC_WINS_CONFIG}" | sed -e 's/^.*NetBIOSName : \([^[:space:]]*\).*$/\1/g' )")"
fi

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
	ALL_WINS="${STATIC_WINS}"
elif [ -n "${STATIC_WINS}" ] ; then
	case "${OSVER}" in
		10.6 | 10.7 )
			# Do nothing - in 10.6 we don't aggregate our configurations, apparently
			DYN_WINS="false"
			ALL_WINS="${STATIC_WINS}"
			;;
		10.4 | 10.5 )
			DYN_WINS="true"
			# We need to remove duplicate WINS entries, so that our reference list matches MacOSX's
			SWINS="$(echo "${STATIC_WINS}" | tr ' ' '\n')"
			(( i=0 ))
			for n in "${vWINS[@]}" ; do
				if echo "${SWINS}" | grep -q "${n}" ; then
					unset vWINS[${i}]
				fi
				(( i++ ))
			done
			if [ ${#vWINS[*]} -gt 0 ] ; then
				ALL_WINS="$(trim "${STATIC_WINS}" "${vWINS[*]}")"
			else
				DYN_WINS="false"
				ALL_WINS="${STATIC_WINS}"
			fi
			;;
	esac
else
	DYN_WINS="true"
	ALL_WINS="$(trim "${vWINS[*]}")"
fi
readonly DYN_WINS ALL_WINS

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
	NO_WINS="#"
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
if [ -z "${ALL_WINS}" ] ; then
	AGG_WINS="#"
fi

# Now, do the aggregation
# Save the openvpn process ID and the Network Primary Service ID, leasewather.plist path, logfile path, and optional arguments from Tunnelblick,
# then save old and new DNS and WINS settings
# PPID is a bash-script variable that contains the process ID of the parent of the process running the script (i.e., OpenVPN's process ID)
# config is an environmental variable set to the configuration path by OpenVPN prior to running this up script
echo "$(date '+%a %b %e %T %Y') *Tunnelblick client.up.tunnelblick.sh: Up to two 'No such key' warnings are normal and may be ignored" >> "${SCRIPT_LOG_FILE}"

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
	${NO_WINS}d.add WINSAddresses * ${vWINS[*]}
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
	${AGG_WINS}d.add WINSAddresses * ${ALL_WINS}
	${NO_WG}d.add Workgroup ${STATIC_WORKGROUP}
	set State:/Network/OpenVPN/SMB

	# We're done
	quit
EOF

echo "$(date '+%a %b %e %T %Y') *Tunnelblick client.up.tunnelblick.sh: Saved the DNS and WINS configurations for later use" >> "${SCRIPT_LOG_FILE}"

if ${ARG_MONITOR_NETWORK_CONFIGURATION} ; then
    # Generate an updated plist with a per-configuration path
    LEASEWATCHER_TEMPLATE_PATH="$(dirname "${0}")/LeaseWatch.plist.template"
    sed -e "s|\${DIR}|$(dirname "${0}")|g" "${LEASEWATCHER_TEMPLATE_PATH}" > "${LEASEWATCHER_PLIST_PATH}"
    launchctl load "${LEASEWATCHER_PLIST_PATH}"
    echo "$(date '+%a %b %e %T %Y') *Tunnelblick client.up.tunnelblick.sh: Set up to monitor system configuration with leasewatch" >> "${SCRIPT_LOG_FILE}"
fi

exit 0
