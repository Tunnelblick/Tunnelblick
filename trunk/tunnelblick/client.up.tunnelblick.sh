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
# Modifed by: Jonathan Bullard for Mountain Lion
# 
# ******************************************************************************************************************


##########################################################################################
# @param String message - The message to log
readonly LOG_MESSAGE_COMMAND=$(basename "${0}")
logMessage()
{
	echo "$(date '+%a %b %e %T %Y') *Tunnelblick $LOG_MESSAGE_COMMAND: "${@} >> "${SCRIPT_LOG_FILE}"
}

##########################################################################################
# @param String string - Content to trim
trim()
{
	echo ${@}
}

##########################################################################################
# @param String[] dnsServers - The name servers to use
# @param String domainName - The domain name to use
# @param \optional String[] winsServers - The SMB servers to use
# @param \optional String[] searchDomains - The search domains to use
#
# Throughout this routine:
#            MAN_ is a prefix for manually set parameters
#            DYN_ is a prefix for dynamically set parameters (by a "push", config file, or command line option)
#            CUR_ is a prefix for the current parameters (as arbitrated by OS X between manual and DHCP data)
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

setDnsServersAndDomainName()
{
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
	
	logMessage "DEBUG:"
	logMessage "DEBUG: MAN_DNS_CONFIG = ${MAN_DNS_CONFIG}"
	logMessage "DEBUG: MAN_SMB_CONFIG = ${MAN_SMB_CONFIG}"
	logMessage "DEBUG:"
	logMessage "DEBUG: CUR_DNS_CONFIG = ${CUR_DNS_CONFIG}"
	logMessage "DEBUG: CUR_SMB_CONFIG = ${CUR_SMB_CONFIG}"
	logMessage "DEBUG:"
	logMessage "DEBUG:"
	logMessage "DEBUG: DYN_DNS_DN = ${DYN_DNS_DN}; DYN_DNS_SA = ${DYN_DNS_SA}; DYN_DNS_SD = ${DYN_DNS_SD}"
	logMessage "DEBUG: DYN_SMB_NN = ${DYN_SMB_NN}; DYN_SMB_WG = ${DYN_SMB_WG}; DYN_SMB_WA = ${DYN_SMB_WA}"
	
# Set up the MAN_... variables to contain manual network settings

	set +e # "grep" will return error status (1) if no matches are found, so don't fail on individual errors
	
	if echo "${MAN_DNS_CONFIG}" | grep -q "DomainName" ; then
		readonly MAN_DNS_DN="$(trim "$( echo "${MAN_DNS_CONFIG}" | sed -e 's/^.*DomainName[^{]*{[[:space:]]*\([^}]*\)[[:space:]]*}.*$/\1/g' )")"
	else
		readonly MAN_DNS_DN="";
	fi
	if echo "${MAN_DNS_CONFIG}" | grep -q "ServerAddresses" ; then
		readonly MAN_DNS_SA="$(trim "$( echo "${MAN_DNS_CONFIG}" | sed -e 's/^.*ServerAddresses[^{]*{[[:space:]]*\([^}]*\)[[:space:]]*}.*$/\1/g' )")"
	else
		readonly MAN_DNS_SA="";
	fi
	if echo "${MAN_DNS_CONFIG}" | grep -q "SearchDomains" ; then
		readonly MAN_DNS_SD="$(trim "$( echo "${MAN_DNS_CONFIG}" | sed -e 's/^.*SearchDomains[^{]*{[[:space:]]*\([^}]*\)[[:space:]]*}.*$/\1/g' )")"
	else
		readonly MAN_DNS_SD="";
	fi
    if echo "${MAN_SMB_CONFIG}" | grep -q "NetBIOSName" ; then
        readonly MAN_SMB_NN="$(trim "$( echo "${MAN_SMB_CONFIG}" | sed -e 's/^.*NetBIOSName : \([^[:space:]]*\).*$/\1/g' )")"
	else
		readonly MAN_SMB_NN="";
    fi
    if echo "${MAN_SMB_CONFIG}" | grep -q "Workgroup" ; then
        readonly MAN_SMB_WG="$(trim "$( echo "${MAN_SMB_CONFIG}" | sed -e 's/^.*Workgroup : \([^[:space:]]*\).*$/\1/g' )")"
	else
		readonly MAN_SMB_WG="";
    fi
    if echo "${MAN_SMB_CONFIG}" | grep -q "WINSAddresses" ; then
        readonly MAN_SMB_WA="$(trim "$( echo "${MAN_SMB_CONFIG}" | sed -e 's/^.*WINSAddresses[^{]*{[[:space:]]*\([^}]*\)[[:space:]]*}.*$/\1/g' )")"
	else
		readonly MAN_SMB_WA="";
    fi

	set -e # resume abort on error

	logMessage "DEBUG:"
	logMessage "DEBUG: MAN_DNS_DN = ${MAN_DNS_DN}; MAN_DNS_SA = ${MAN_DNS_SA}; MAN_DNS_SD = ${MAN_DNS_SD}"
	logMessage "DEBUG: MAN_SMB_NN = ${MAN_SMB_NN}; MAN_SMB_WG = ${MAN_SMB_WG}; MAN_SMB_WA = ${MAN_SMB_WA}"
	
# Set up the CUR_... variables to contain the current network settings (from manual or DHCP, as arbitrated by OS X

	set +e # "grep" will return error status (1) if no matches are found, so don't fail on individual errors
	
	if echo "${CUR_DNS_CONFIG}" | grep -q "DomainName" ; then
		readonly CUR_DNS_DN="$(trim "$( echo "${CUR_DNS_CONFIG}" | sed -e 's/^.*DomainName[^{]*{[[:space:]]*\([^}]*\)[[:space:]]*}.*$/\1/g' )")"
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

	logMessage "DEBUG:"
	logMessage "DEBUG: CUR_DNS_DN = ${CUR_DNS_DN}; CUR_DNS_SA = ${CUR_DNS_SA}; CUR_DNS_SD = ${CUR_DNS_SD}"
	logMessage "DEBUG: CUR_SMB_NN = ${CUR_SMB_NN}; CUR_SMB_WG = ${CUR_SMB_WG}; CUR_SMB_WA = ${CUR_SMB_WA}"

# set up the FIN_... variables with what we want to set things to

	# Three FIN_... variables are simple -- no aggregation is done for them

	if [ "${DYN_DNS_DN}" != "" ] ; then
		if [ "${MAN_DNS_DN}" != "" ] ; then
			logMessage "DomainName '$DYN_DNS_DN' ignored because DomainName was set manually"
			readonly FIN_DNS_DN="${MAN_DNS_DN}"
		else
			readonly FIN_DNS_DN="${DYN_DNS_DN}"
		fi
	else
		readonly FIN_DNS_DN="${CUR_DNS_DN}"
	fi
	
	if [ "${DYN_SMB_NN}" != "" ] ; then
		if [ "${MAN_SMB_NN}" != "" ] ; then
			logMessage "NetBIOSName '$DYN_SMB_NN' ignored because NetBIOSName was set manually"
			readonly FIN_SMB_NN="${MAN_SMB_NN}"
		else
			readonly FIN_SMB_NN="${DYN_SMB_NN}"
		fi
	else
		readonly FIN_SMB_NN="${CUR_SMB_NN}"
	fi
	
	if [ "${DYN_SMB_WG}" != "" ] ; then
		if [ "${MAN_SMB_WG}" != "" ] ; then
			logMessage "Workgroup '$DYN_SMB_WG' ignored because Workgroup was set manually"
			readonly FIN_SMB_WG="${MAN_SMB_WG}"
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
			logMessage "ServerAddresses '$DYN_DNS_SA' ignored because ServerAddresses was set manually"
			readonly FIN_DNS_SA="${CUR_DNS_SA}"
		else
			case "${OSVER}" in
				10.4 | 10.5 )
					# We need to remove duplicate DNS entries, so that our reference list matches MacOSX's
					SDNS="$(echo "${DYN_DNS_SA}" | tr ' ' '\n')"
					(( i=0 ))
					for n in "${vDNS[@]}" ; do
						if echo "${SDNS}" | grep -q "${n}" ; then
							unset vDNS[${i}]
						fi
						(( i++ ))
					done
					if [ ${#vDNS[*]} -gt 0 ] ; then
						readonly FIN_DNS_SA="$(trim "${DYN_DNS_SA}" "${vDNS[*]}")"
					else
						readonly FIN_DNS_SA="${DYN_DNS_SA}"
					fi
					logMessage "ServerAddresses were aggregated because running on OS X 10.4 or 10.5"
					;;
				* )
					# Do nothing - in 10.6 and higher -- we don't aggregate our configurations, apparently
					readonly FIN_DNS_SA="${DYN_DNS_SA}"
					logMessage "ServerAddresses were not aggregated because running on OS X 10.6 or higher"
					;;
			esac
		fi
	fi

	# SMB WINSAddresses (FIN_SMB_WA) are aggregated for 10.4 and 10.5
	if [ ${#vSMB[*]} -eq 0 ] ; then
		readonly FIN_SMB_WA="${CUR_SMB_WA}"
	else
		if [ "${MAN_SMB_WA}" != "" ] ; then
			logMessage "WINSAddresses '$DYN_SMB_WA' ignored because WINSAddresses was set manually"
			readonly FIN_SMB_WA="${MAN_SMB_WA}"
		else
		case "${OSVER}" in
			10.4 | 10.5 )
				# We need to remove duplicate SMB entries, so that our reference list matches MacOSX's
				SSMB="$(echo "${DYN_SMB_WA}" | tr ' ' '\n')"
				(( i=0 ))
				for n in "${vSMB[@]}" ; do
					if echo "${SSMB}" | grep -q "${n}" ; then
						unset vSMB[${i}]
					fi
					(( i++ ))
				done
				if [ ${#vSMB[*]} -gt 0 ] ; then
					readonly FIN_SMB_WA="$(trim "${DYN_SMB_WA}" "${vSMB[*]}")"
				else
					readonly FIN_SMB_WA="${DYN_SMB_WA}"
				fi
				logMessage "WINSAddresses were aggregated because running on OS X 10.4 or 10.5"
				;;
			* )
				# Do nothing - in 10.6 and higher -- we don't aggregate our configurations, apparently
				readonly FIN_SMB_WA="${DYN_SMB_WA}"
				logMessage "WINSAddresses were not aggregated because running on OS X 10.6 or higher"
				;;
		esac
		fi
	fi

	# DNS SearchDomains (FIN_DNS_SD) is treated specially
	#
	# OLD BEHAVIOR:
	#     if SearchDomains was not set manually, we set SearchDomains to the DomainName
	#     else
	#          In OS X 10.4-10.5, we add the DomainName to the end of any manual SearchDomains (unless it is already there)
	#          In OS X 10.6+, if SearchDomains was entered manually, we ignore the DomainName 
	#                         else we set SearchDomains to the DomainName
	#
	# NEW BEHAVIOR (done if ARG_PREPEND_DOMAIN_NAME is "true"):
	#
	#     if SearchDomains was entered manually, we do nothing
	#     else we  PREpend new SearchDomains (if any) to the existing SearchDomains (NOT replacing them)
	#          and PREpend DomainName to that
	#
	#              (done if ARG_PREPEND_DOMAIN_NAME is "false" and there are new SearchDomains from DOMAIN-SEARCH):
	#
	#     if SearchDomains was entered manually, we do nothing
	#     else we  PREpend any new SearchDomains to the existing SearchDomains (NOT replacing them)
	#
	#     This behavior is meant to behave like Linux with Network Manager and Windows
	
	if "${ARG_PREPEND_DOMAIN_NAME}" ; then
		if [ "${MAN_DNS_SD}" = "" ] ; then
			if [ "${DYN_DNS_SD}" != "" ] ; then
				readonly TMP_DNS_SD="$(trim "${DYN_DNS_SD}" "${CUR_DNS_SD}")"
				logMessage "Prepended '${DYN_DNS_SD}' to search domains '${CUR_DNS_SD}' because the search domains were not set manually and 'Prepend domain name to search domains' was selected"
			else
				readonly TMP_DNS_SD="${CUR_DNS_SD}"
			fi
			logMessage "Prepended '${FIN_DNS_DN}' to search domains '${CUR_DNS_SD}' because the search domains were not set manually and 'Prepend domain name to search domains' was selected"
			readonly FIN_DNS_SD="$(trim "${FIN_DNS_DN}" "${TMP_DNS_SD}")"
		else
			if [ "${DYN_DNS_SD}" != "" ] ; then
				logMessage "Did not prepend '${DYN_DNS_SD}' to search domains '${CUR_DNS_SD}' because the search domains were set manually and 'Prepend domain name to search domains' was selected"
			fi
			logMessage "Did not prepend '${FIN_DNS_DN}' to search domains '${CUR_DNS_SD}' because the search domains were set manually and 'Prepend domain name to search domains' was selected"
			readonly FIN_DNS_SD="${CUR_DNS_SD}"
		fi
	else
		if [ "${DYN_DNS_SD}" != "" ] ; then
			if [ "${MAN_DNS_SD}" = "" ] ; then
				readonly FIN_DNS_SD="$(trim "${DYN_DNS_SD}" "${CUR_DNS_SD}")"
				logMessage "Prepended '${DYN_DNS_SD}' to search domains '${CUR_DNS_SD}' because the search domains were not set manually but were set via OpenVPN and 'Prepend domain name to search domains' was not selected"
			fi
		else
			case "${OSVER}" in
				10.4 | 10.5 )
					if echo "${MAN_DNS_SD}" | tr ' ' '\n' | grep -q "${FIN_DNS_DN}" ; then
						logMessage "Did not append '${FIN_DNS_DN}' to search domains '${CUR_DNS_SD}' because it is already in the search domains that were set manually and 'Prepend domain name to search domains' was not selected"
						readonly FIN_DNS_SD="${CUR_DNS_SD}"
					else
						logMessage "Appended '${FIN_DNS_DN}' to search domains '${CUR_DNS_SD}' that were set manually because running under OS X 10.4 or 10.5 and 'Prepend domain name to search domains' was not selected"
						readonly FIN_DNS_SD="$(trim "${MAN_DNS_SD}" "${FIN_DNS_DN}")"
					fi
					;;
				* )
					if [ "${MAN_DNS_SD}" = "" ] ; then
						logMessage "Setting search domains to '${FIN_DNS_DN}' because running under OS X 10.6 or higher and the search domains were not set manually and 'Prepend domain name to search domains' was not selected"
						readonly FIN_DNS_SD="${FIN_DNS_DN}"
					else
						logMessage "Did not replace search domains '${CUR_DNS_SD}' with '${FIN_DNS_DN}' because running under OS X 10.6 or higher and the search domains were set manually and 'Prepend domain name to search domains' was not selected"
						readonly FIN_DNS_SD="${CUR_DNS_SD}"
					fi
					;;
			esac
		fi
	fi
		
	logMessage "DEBUG:"
	logMessage "DEBUG: FIN_DNS_DN = ${FIN_DNS_DN}; FIN_DNS_SA = ${FIN_DNS_SA}; FIN_DNS_SD = ${FIN_DNS_SD}"
	logMessage "DEBUG: FIN_SMB_NN = ${FIN_SMB_NN}; FIN_SMB_WG = ${FIN_SMB_WG}; FIN_SMB_WA = ${FIN_SMB_WA}"

# Set up SKP_... variables to inhibit scutil from making some changes
	
	# SKP_DNS_... and SKP_SMB_... are used to comment out individual items that are not being set
	if [ "${FIN_DNS_DN}" = "" -o "${FIN_DNS_DN}" = "${CUR_DNS_DN}" ] ; then
		SKP_DNS_DN="#"
	else
		SKP_DNS_DN=""
	fi
	if [ "${FIN_DNS_SA}" = "" -o "${FIN_DNS_SA}" = "${CUR_DNS_SA}" ] ; then
		SKP_DNS_SA="#"
	else
		SKP_DNS_SA=""
	fi
	if [ "${FIN_DNS_SD}" = "" -o "${FIN_DNS_SD}" = "${CUR_DNS_SD}" ] ; then
		SKP_DNS_SD="#"
	else
		SKP_DNS_SD=""
	fi
	if [ "${FIN_SMB_NN}" = "" -o "${FIN_SMB_NN}" = "${CUR_SMB_NN}" ] ; then
		SKP_SMB_NN="#"
	else
		SKP_SMBNN=""
	fi
	if [ "${FIN_SMB_WG}" = "" -o "${FIN_SMB_WG}" = "${CUR_SMB_WG}" ] ; then
		SKP_SMB_WG="#"
	else
		SKP_SMB_WG=""
	fi
	if [ "${FIN_SMB_WA}" = "" -o "${FIN_SMB_WA}" = "${CUR_SMB_WA}" ] ; then
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
	# we pass a flag indicating whether we've done that to the other scripts in 'bAlsoUsingSetupKeys'

	case "${OSVER}" in
		10.4 | 10.5 | 10.6 )
			logMessage "DEBUG: OS X 10.4-10.6, so will modify settings using only State:"
			readonly SKP_SETUP_DNS="#"
			readonly bAlsoUsingSetupKeys="false"
			;;
		10.7 )
			if [ "${MAN_DNS_SA}" = "" -a  "${MAN_DNS_SD}" = "" ] ; then
				logMessage "DEBUG: OS X 10.7 and neither ServerAddresses nor SearchDomains were set manually, so will modify DNS settings using only State:"
				readonly SKP_SETUP_DNS="#"
				readonly bAlsoUsingSetupKeys="false"
			else
				logMessage "DEBUG: OS X 10.7 and ServerAddresses or SearchDomains were set manually, so will modify DNS settings using Setup: in addition to State:"
				readonly SKP_SETUP_DNS=""
				readonly bAlsoUsingSetupKeys="true"
			fi
			;;
		* )
			logMessage "DEBUG: OS X 10.8 or higher, so will modify DNS settings using Setup: in addition to State:"
			readonly SKP_SETUP_DNS=""
			readonly bAlsoUsingSetupKeys="true"
			;;
	esac
	
	logMessage "DEBUG:"
	logMessage "DEBUG: SKP_DNS = ${SKP_DNS}; SKP_DNS_SA = ${SKP_DNS_SA}; SKP_DNS_SD = ${SKP_DNS_SD}; SKP_DNS_DN = ${SKP_DNS_DN}"
	logMessage "DEBUG: SKP_SETUP_DNS = ${SKP_SETUP_DNS}"
	logMessage "DEBUG: SKP_SMB = ${SKP_SMB}; SKP_SMB_NN = ${SKP_SMB_NN}; SKP_SMB_WG = ${SKP_SMB_WG}; SKP_SMB_WA = ${SKP_SMB_WA}"

    set +e # "grep" will return error status (1) if no matches are found, so don't fail if not found
    original_resolver_contents="`cat /etc/resolv.conf | grep -v '#'`"
    set -e # resume abort on error
    logMessage "DEBUG:"
    logMessage "DEBUG: /etc/resolve = ${original_resolver_contents}"
    logMessage "DEBUG:"

	scutil_dns="$( scutil --dns)"
	logMessage "DEBUG:"
	logMessage "DEBUG: scutil --dns BEFORE CHANGES = ${scutil_dns}"
	logMessage "DEBUG:"

	logMessage "DEBUG:"
	logMessage "DEBUG: Configuration changes:"
	logMessage "DEBUG: ${SKP_DNS}${SKP_DNS_SA}ADD State: ServerAddresses  ${FIN_DNS_SA}"
	logMessage "DEBUG: ${SKP_DNS}${SKP_DNS_SD}ADD State: SearchDomains    ${FIN_DNS_SD}"
	logMessage "DEBUG: ${SKP_DNS}${SKP_DNS_DN}ADD State: DomainName       ${FIN_DNS_DN}"
	logMessage "DEBUG:"
	logMessage "DEBUG: ${SKP_SETUP_DNS}${SKP_DNS}${SKP_DNS_SA}ADD Setup: ServerAddresses  ${FIN_DNS_SA}"
	logMessage "DEBUG: ${SKP_SETUP_DNS}${SKP_DNS}${SKP_DNS_SD}ADD Setup: SearchDomains    ${FIN_DNS_SD}"
	logMessage "DEBUG: ${SKP_SETUP_DNS}${SKP_DNS}${SKP_DNS_DN}ADD Setup: DomainName       ${FIN_DNS_DN}"
	logMessage "DEBUG:"
	logMessage "DEBUG: ${SKP_SMB}${SKP_SMB_NN}ADD State: NetBIOSName    ${FIN_SMB_NN}"
	logMessage "DEBUG: ${SKP_SMB}${SKP_SMB_WG}ADD State: Workgroup      ${FIN_SMB_WG}"
	logMessage "DEBUG: ${SKP_SMB}${SKP_SMB_WA}ADD State: WINSAddresses  ${FIN_SMB_WA}"

	# Save the openvpn process ID and the Network Primary Service ID, leasewather.plist path, logfile path, and optional arguments from Tunnelblick,
	# then save old and new DNS and SMB settings
	# PPID is a script variable (defined by bash itself) that contains the process ID of the parent of the process running the script (i.e., OpenVPN's process ID)
	# config is an environmental variable set to the configuration path by OpenVPN prior to running this up script

	scutil <<-EOF > /dev/null
		open

		# Store our variables for the other scripts (leasewatch, down, etc.) to use
		d.init
		# The '#' in the next line does NOT start a comment; it indicates to scutil that a number follows it (as opposed to a string or an array)
		d.add PID # ${PPID}
		d.add Service ${PSID}
		d.add LeaseWatcherPlistPath "${LEASEWATCHER_PLIST_PATH}"
		d.add ScriptLogFile         "${SCRIPT_LOG_FILE}"
		d.add MonitorNetwork        "${ARG_MONITOR_NETWORK_CONFIGURATION}"
		d.add RestoreOnDNSReset     "${ARG_RESTORE_ON_DNS_RESET}"
		d.add RestoreOnWINSReset    "${ARG_RESTORE_ON_WINS_RESET}"
		d.add IgnoreOptionFlags     "${ARG_IGNORE_OPTION_FLAGS}"
        d.add IsTapInterface        "${ARG_TAP}"
        d.add FlushDNSCache         "${ARG_FLUSH_DNS_CACHE}"
        d.add ResetPrimaryInterface "${ARG_RESET_PRIMARY_INTERFACE_ON_DISCONNECT}"
        d.add RouteGatewayIsDhcp    "${bRouteGatewayIsDhcp}"
		d.add bAlsoUsingSetupKeys   "${bAlsoUsingSetupKeys}"
        d.add TapDeviceHasBeenSetNone "false"
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

	logMessage "DEBUG:"
	logMessage "DEBUG: Pause for configuration changes to be propagated to State:/Network/Global/DNS and .../SMB"
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


	logMessage "DEBUG:"
	logMessage "DEBUG: Configurations as read back after changes:"
	logMessage "DEBUG: State:/.../DNS = ${NEW_DNS_STATE_CONFIG}"
	logMessage "DEBUG: State:/.../SMB = ${NEW_SMB_STATE_CONFIG}"
	logMessage "DEBUG:"
	logMessage "DEBUG: Setup:/.../DNS = ${NEW_DNS_SETUP_CONFIG}"
	logMessage "DEBUG: Setup:/.../SMB = ${NEW_SMB_SETUP_CONFIG}"
	logMessage "DEBUG:"
    logMessage "DEBUG: State:/Network/Global/DNS = ${NEW_DNS_GLOBAL_CONFIG}"
    logMessage "DEBUG: State:/Network/Global/SMB = ${NEW_SMB_GLOBAL_CONFIG}"
	logMessage "DEBUG:"
	logMessage "DEBUG: Expected by process-network-changes:"
    logMessage "DEBUG: State:/Network/OpenVPN/DNS = ${EXPECTED_NEW_DNS_GLOBAL_CONFIG}"
    logMessage "DEBUG: State:/Network/OpenVPN/SMB = ${EXPECTED_NEW_SMB_GLOBAL_CONFIG}"

    set +e # "grep" will return error status (1) if no matches are found, so don't fail if not found
    new_resolver_contents="`cat /etc/resolv.conf | grep -v '#'`"
    set -e # resume abort on error
    logMessage "DEBUG:"
    logMessage "DEBUG: /etc/resolve = ${new_resolver_contents}"
    logMessage "DEBUG:"

	scutil_dns="$( scutil --dns)"
	logMessage "DEBUG:"
	logMessage "DEBUG: scutil --dns AFTER CHANGES = ${scutil_dns}"
	logMessage "DEBUG:"
	
	logMessage "Saved the DNS and SMB configurations for later use"
	
	flushDNSCache

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

##########################################################################################
# Used for TAP device which does DHCP
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
	logMessage "DEBUG_TAP: About to 'ipconfig waitall'"
	ipconfig waitall
	logMessage "DEBUG_TAP: Completed 'ipconfig waitall'"
	
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

    logMessage "DEBUG_TAP: Finished waiting for DHCP lease: test_domain_name = '$test_domain_name', test_name_server = '$test_name_server'"
    
    logMessage "DEBUG_TAP: About to 'ipconfig getpacket $dev'"
	sGetPacketOutput=`ipconfig getpacket $dev`
    logMessage "DEBUG_TAP: Completed 'ipconfig getpacket $dev'; sGetPacketOutput = $sGetPacketOutput"

	set -e # We instruct bash that it CAN again fail on individual errors
	
	unset aNameServers
	unset aWinsServers
	unset aSearchDomains
	
	nNameServerIndex=1
	nWinsServerIndex=1
	nSearchDomainIndex=1
	
	if [ "$sGetPacketOutput" ]; then
		sGetPacketOutput_FirstLine=`echo "$sGetPacketOutput"|head -n 1`
		logMessage "DEBUG_TAP: sGetPacketOutput_FirstLine = $sGetPacketOutput_FirstLine"
		
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
			
			for tSearchDomain in `echo "$sGetPacketOutput"|grep "search_domain"|grep -Eo "\{([-A-Za-z0-9\-\.]+)(, [-A-Za-z0-9\-\.]+)*\}"|grep -Eo "([-A-Za-z0-9\-\.]+)"`; do
				aSearchDomains[nSearchDomainIndex-1]="$(trim "$tSearchDomain")"
				let nSearchDomainIndex++
			done
			
			sDomainName=`echo "$sGetPacketOutput"|grep "domain_name "|grep -Eo ": [-A-Za-z0-9\-\.]+"|grep -Eo "[-A-Za-z0-9\-\.]+"`
			sDomainName="$(trim "$sDomainName")"
			
			if [ ${#aNameServers[*]} -gt 0 -a "$sDomainName" ]; then
				logMessage "Retrieved from DHCP/BOOTP packet: name server(s) [ ${aNameServers[@]} ], domain name [ $sDomainName ], search domain(s) [ ${aSearchDomains[@]} ] and SMB server(s) [ ${aWinsServers[@]} ]"
				setDnsServersAndDomainName aNameServers[@] "$sDomainName" aWinsServers[@] aSearchDomains[@]
				return 0
			elif [ ${#aNameServers[*]} -gt 0 ]; then
				logMessage "Retrieved from DHCP/BOOTP packet: name server(s) [ ${aNameServers[@]} ], search domain(s) [ ${aSearchDomains[@]} ] and SMB server(s) [ ${aWinsServers[@]} ] and using default domain name [ $DEFAULT_DOMAIN_NAME ]"
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
	fi
	
	unset sDomainName
	unset sNameServer
	unset aNameServers
	
    set +e # We instruct bash NOT to exit on individual command errors, because if we need to wait longer these commands will fail
	
	logMessage "DEBUG_TAP: About to 'ipconfig getoption $dev domain_name'"
	sDomainName=`ipconfig getoption $dev domain_name 2>/dev/null`
	logMessage "DEBUG_TAP: Completed 'ipconfig getoption $dev domain_name'"
	logMessage "DEBUG_TAP: About to 'ipconfig getoption $dev domain_name_server'"
	sNameServer=`ipconfig getoption $dev domain_name_server 2>/dev/null`
	logMessage "DEBUG_TAP: Completed 'ipconfig getoption $dev domain_name_server'"
    
	set -e # We instruct bash that it CAN again fail on individual errors

	sDomainName="$(trim "$sDomainName")"
	sNameServer="$(trim "$sNameServer")"
	
	declare -a aWinsServers=( )   # Declare empty WINSServers   array to avoid any useless error messages
	declare -a aSearchDomains=( ) # Declare empty SearchDomains array to avoid any useless error messages
	
	if [ "$sDomainName" -a "$sNameServer" ]; then
		aNameServers[0]=$sNameServer
		logMessage "Retrieved OpenVPN (DHCP): name server [ $sNameServer ], domain name [ $sDomainName ], and no SMB servers or search domains"
		setDnsServersAndDomainName aNameServers[@] "$sDomainName" aWinsServers[@] aSearchDomains[@]
	elif [ "$sNameServer" ]; then
		aNameServers[0]=$sNameServer
		logMessage "Retrieved OpenVPN (DHCP): name server [ $sNameServer ] and no SMB servers or search domains, and using default domain name [ $DEFAULT_DOMAIN_NAME ]"
		setDnsServersAndDomainName aNameServers[@] "$DEFAULT_DOMAIN_NAME" aWinsServers[@] aSearchDomains[@]
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

##########################################################################################
# Configures using OpenVPN foreign_option_* instead of DHCP

configureOpenVpnDns()
{
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
			*DOMAIN-SEARCH*    )
				aSearchDomains[nSearchDomainIndex-1]="$(trim "${vOptions[nOptionIndex-1]//dhcp-option DOMAIN-SEARCH /}")"
				let nSearchDomainIndex++
				;;
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
                logMessage "UNKNOWN: 'foreign_option_${nOptionIndex}' = '${vOptions[nOptionIndex-1]}' ignored"
                ;;
		esac
		let nOptionIndex++
	done
	
	if [ ${#aNameServers[*]} -gt 0 -a "$sDomainName" ]; then
		logMessage "Retrieved from OpenVPN: name server(s) [ ${aNameServers[@]} ], domain name [ $sDomainName ], search domain(s) [ ${aSearchDomains[@]} ], and SMB server(s) [ ${aWinsServers[@]} ]"
		setDnsServersAndDomainName aNameServers[@] "$sDomainName" aWinsServers[@] aSearchDomains[@]
	elif [ ${#aNameServers[*]} -gt 0 ]; then
		logMessage "Retrieved from OpenVPN: name server(s) [ ${aNameServers[@]} ], search domain(s) [ ${aSearchDomains[@]} ] and SMB server(s) [ ${aWinsServers[@]} ] and using default domain name [ $DEFAULT_DOMAIN_NAME ]"
		setDnsServersAndDomainName aNameServers[@] "$DEFAULT_DOMAIN_NAME" aWinsServers[@] aSearchDomains[@]
	else
		logMessage "No DNS information received from OpenVPN, so no network configuration changes need to be made."
		if ${ARG_MONITOR_NETWORK_CONFIGURATION} ; then
			logMessage "Will NOT monitor for other network configuration changes."
		fi
	fi
	
	return 0
}

##########################################################################################
flushDNSCache()
{
    if ${ARG_FLUSH_DNS_CACHE} ; then
        case "${OSVER}" in
            10.4 )
                if [ -f /usr/sbin/lookupd ] ; then
                    /usr/sbin/lookupd -flushcache
                    logMessage "Flushed the DNS Cache"
                else
                    logMessage "/usr/sbin/lookupd not present. Not flushing the DNS cache"
                fi
                ;;
            10.5 | 10.6 )
                if [ -f /usr/bin/dscacheutil ] ; then
                    /usr/bin/dscacheutil -flushcache
                    logMessage "Flushed the DNS Cache"
                else
                    logMessage "/usr/bin/dscacheutil not present. Not flushing the DNS cache"
                fi
                ;;
            * )
				set +e # "grep" will return error status (1) if no matches are found, so don't fail on individual errors
				hands_off_ps="$( ps -ax | grep HandsOffDaemon | grep -v grep.HandsOffDaemon )"
				set -e # We instruct bash that it CAN again fail on errors
				if [ "${hands_off_ps}" = "" ] ; then
					if [ -f /usr/bin/killall ] ; then
						/usr/bin/killall -HUP mDNSResponder
						logMessage "Flushed the DNS Cache"
					else
						logMessage "/usr/bin/killall not present. Not flushing the DNS cache"
					fi
				else
					logMessage "Hands Off is running. Not flushing the DNS cache"
				fi
                ;;
        esac
    fi
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

# Process optional arguments (if any) for the script
# Each one begins with a "-"
# They come from Tunnelblick, and come first, before the OpenVPN arguments
# So we set ARG_ script variables to their values and shift them out of the argument list
# When we're done, only the OpenVPN arguments remain for the rest of the script to use
ARG_MONITOR_NETWORK_CONFIGURATION="false"
ARG_RESTORE_ON_DNS_RESET="false"
ARG_RESTORE_ON_WINS_RESET="false"
ARG_TAP="false"
ARG_PREPEND_DOMAIN_NAME="false"
ARG_FLUSH_DNS_CACHE="false"
ARG_RESET_PRIMARY_INTERFACE_ON_DISCONNECT="false"
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
	elif [ "$1" = "-p" ] ; then
		ARG_PREPEND_DOMAIN_NAME="true"
		shift
    elif [ "$1" = "-f" ] ; then
        ARG_FLUSH_DNS_CACHE="true"
        shift
    elif [ "$1" = "-r" ] ; then
        ARG_RESET_PRIMARY_INTERFACE_ON_DISCONNECT="true"
        shift
	elif [ "${1:0:2}" = "-i" ] ; then
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

readonly ARG_MONITOR_NETWORK_CONFIGURATION ARG_RESTORE_ON_DNS_RESET ARG_RESTORE_ON_WINS_RESET ARG_TAP ARG_PREPEND_DOMAIN_NAME ARG_FLUSH_DNS_CACHE ARG_RESET_PRIMARY_INTERFACE_ON_DISCONNECT ARG_IGNORE_OPTION_FLAGS

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

set +e # "grep" will return error status (1) if no matches are found, so don't fail on individual errors
readonly OSVER="$(sw_vers | grep 'ProductVersion:' | grep -o '10\.[0-9]*')"
set -e # We instruct bash that it CAN again fail on errors

readonly DEFAULT_DOMAIN_NAME="openvpn"

bRouteGatewayIsDhcp="false"

# We sleep to allow time for OS X to process network settings
sleep 2

EXIT_CODE=0

if ${ARG_TAP} ; then
	# Still need to do: Look for route-gateway dhcp (TAP isn't always DHCP)
	bRouteGatewayIsDhcp="false"
	if [ -z "${route_vpn_gateway}" -o "$route_vpn_gateway" == "dhcp" -o "$route_vpn_gateway" == "DHCP" ]; then
		bRouteGatewayIsDhcp="true"
	fi
	
	if [ "$bRouteGatewayIsDhcp" == "true" ]; then
		logMessage "DEBUG_TAP: bRouteGatewayIsDhcp is TRUE"
		if [ -z "$dev" ]; then
			logMessage "Cannot configure TAP interface for DHCP without \$dev being defined. Exiting."
            # We don't create the "/tmp/tunnelblick-downscript-needs-to-be-run.txt" file, because the down script does NOT need to be run since we didn't do anything
			exit 1
		fi
		
		logMessage "DEBUG: About to 'ipconfig set \"$dev\" DHCP"
		ipconfig set "$dev" DHCP
		logMessage "DEBUG: Did 'ipconfig set \"$dev\" DHCP"
		
		logMessage "Configuring tap DNS via DHCP asynchronously"
		configureDhcpDns & # This must be run asynchronously; the DHCP lease will not complete until this script exits
		EXIT_CODE=0
	elif [ "$foreign_option_1" == "" ]; then
		logMessage "No network configuration changes need to be made."
		if ${ARG_MONITOR_NETWORK_CONFIGURATION} ; then
			logMessage "Will NOT monitor for other network configuration changes."
		fi
	else
		logMessage "Configuring tap DNS via OpenVPN"
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

touch "/tmp/tunnelblick-downscript-needs-to-be-run.txt"

exit $EXIT_CODE
