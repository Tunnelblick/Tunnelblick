#!/bin/bash -e
trap "" TSTP
trap "" HUP
trap "" INT
export PATH="/bin:/sbin:/usr/sbin:/usr/bin"

# only do something when the server really is pushing something
if [ "$foreign_option_1" == "" ]; then
	exit 0
fi

trim() {
	echo ${@}
}

OSVER="$(sw_vers | grep 'ProductVersion:' | grep -o '10\.[0-9]*')"

case "${OSVER}" in
	10.4 | 10.5 )
		HIDE_SNOW_LEOPARD=""
		HIDE_LEOPARD="#"
		;;
	10.6 )
		HIDE_SNOW_LEOPARD="#"
		HIDE_LEOPARD=""
		;;
esac

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

if [ ${#vDNS[*]} -eq 0 ] ; then
	DYN_DNS="false"
	ALL_DNS="${STATIC_DNS}"
elif [ -n "${STATIC_DNS}" ] ; then
	case "${OSVER}" in
		10.6 )
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
		10.6 )
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
	10.6 )
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
# save the openvpn PID, the Old DNS settings, and the old service ID
#
# This is more robust than the previous file-based exchange mechanism because
# it leaves no garbage behind in case of a crash (configs aren't persisted), and
# also because it makes an EXACT copy of the DNS configs that were there before
# so they can be restored in the end.  EXACT copy means that if there were 20 DNS's
# configured, then they will be appropriately restored unlike the previous script
# which only saved two DNS's.
scutil <<- EOF
	open
	d.init
	d.add PID # ${PPID}
	d.add Service ${PSID}
	set State:/Network/OpenVPN

	# First, back up the device's current DNS and WINS configuration, for
	# restoration later
	get State:/Network/Service/${PSID}/DNS
	set State:/Network/OpenVPN/OldDNS

	# Second, initialize the new map
	d.init
	${HIDE_SNOW_LEOPARD}d.add DomainName ${domain}
	${NO_DNS}d.add ServerAddresses * ${vDNS[*]}
	${NO_SEARCH}d.add SearchDomains * ${SEARCH_DOMAIN}
	${HIDE_LEOPARD}d.add DomainName ${domain}
	set State:/Network/Service/${PSID}/DNS

	# Third, initialize the WINS map
	d.init
	${HIDE_SNOW_LEOPARD}${NO_WG}d.add Workgroup ${STATIC_WORKGROUP}
	${NO_WINS}d.add WINSAddresses * ${vWINS[*]}
	${HIDE_LEOPARD}${NO_WG}d.add Workgroup ${STATIC_WORKGROUP}
	set State:/Network/Service/${PSID}/SMB

	# Now, initialize the map that will be compared against the system-generated map
	# which means that we will have to aggregate configurations of statically-configured
	# nameservers, and statically-configured search domains
	d.init
	${HIDE_SNOW_LEOPARD}d.add DomainName ${domain}
	${AGG_DNS}d.add ServerAddresses * ${ALL_DNS}
	${AGG_SEARCH}d.add SearchDomains * ${ALL_SEARCH}
	${HIDE_LEOPARD}d.add DomainName ${domain}
	set State:/Network/OpenVPN/DNS

	d.init
	${HIDE_SNOW_LEOPARD}${NO_WG}d.add Workgroup ${STATIC_WORKGROUP}
	${AGG_WINS}d.add WINSAddresses * ${ALL_WINS}
	${HIDE_LEOPARD}${NO_WG}d.add Workgroup ${STATIC_WORKGROUP}
	set State:/Network/OpenVPN/SMB

	# We're done
	quit
EOF

exit 0
