#!/bin/sh -e
trap "" TSTP
trap "" HUP
trap "" INT
export PATH="/bin:/sbin:/usr/sbin:/usr/bin"

# only do something when the server really is pushing something
if [ "$foreign_option_1" == "" ]; then
	exit 0
fi

nOptionIndex=1
nNameServerIndex=1
unset vForOptions
unset vDNS
unset vOptions

while vForOptions=foreign_option_$nOptionIndex; [ -n "${!vForOptions}" ]; do
	{
	vOptions[nOptionIndex-1]=${!vForOptions}
	case ${vOptions[nOptionIndex-1]} in
		*DOMAIN* )
			domain=${vOptions[nOptionIndex-1]//dhcp-option DOMAIN /}
			;;
		*DNS*    )
			vDNS[nNameServerIndex-1]=${vOptions[nOptionIndex-1]//dhcp-option DNS /}
			let nNameServerIndex++
			;;
	esac
	let nOptionIndex++
	}
done

# set domain to a default value when no domain is being transmitted
if [ "$domain" == "" ]; then
	domain="openvpn"
	NO_SEARCH="#"
fi

PSID=$( (scutil | grep PrimaryService | sed -e 's/.*PrimaryService : //')<<- EOF
	open
	show State:/Network/Global/IPv4
	quit
EOF
)

STATIC_DNS_CONFIG=$( (scutil | sed -e 's/^[[:space:]]*[[:digit:]]* : //g' | tr '\n' ' ')<<- EOF
	open
	show Setup:/Network/Service/${PSID}/DNS
	quit
EOF
)

if echo "${STATIC_DNS_CONFIG}" | grep -q "ServerAddresses" ; then
	STATIC_DNS="$( echo "${STATIC_DNS_CONFIG}" | sed -e 's/^.*ServerAddresses[^{]*{\([^}]*\)}.*$/\1/g' )"
fi
if echo "${STATIC_DNS_CONFIG}" | grep -q "SearchDomains" ; then
	STATIC_SEARCH="$( echo "${STATIC_DNS_CONFIG}" | sed -e 's/^.*SearchDomains[^{]*{\([^}]*\)}.*$/\1/g' )"
fi

if [ ${#vDNS[*]} -eq 0 ] ; then
	NO_DNS="#"
elif [ -n "${STATIC_DNS}" ] ; then
	# We need to remove duplicate DNS entries, so that our reference list matches MacOSX's
	SDNS="$(echo "${STATIC_DNS}" | tr ' ' '\n')"
	(( i=0 ))
	for n in "${vDNS[@]}" ; do
		if echo "${SDNS}" | grep -q "${n}" ; then
			unset vDNS[${i}]
		fi
		(( i++ ))
	done
	echo "$(date): Removal Status: [${STATIC_DNS}] vs. [${vDNS[*]}]" >> /tmp/dns.log
fi

# We double-check that our search domain isn't already on the list
SEARCH_DOMAIN="${domain}"
if [ "${NO_SEARCH}" != "#" ] ; then
	if echo "${STATIC_SEARCH}" | tr ' ' '\n' | grep -q "${domain}" ; then
		NO_SEARCH="#"
		SEARCH_DOMAIN=""
	fi
fi

if [ -z "${STATIC_DNS}" ] && [ ${#vDNS[*]} -eq 0 ] ; then
	AGG_DNS="#"
fi

if [ -z "${STATIC_SEARCH}" ] && [ "${NO_SEARCH}" == "#" ] ; then
	AGG_SEARCH="#"
fi

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

	# First, back up the device's current DNS configuration, for
	# restoration later
	get State:/Network/Service/${PSID}/DNS
	set State:/Network/OpenVPN/OldDNS

	# Second, initialize the new map
	d.init
	d.add DomainName ${domain}
	${NO_DNS}d.add ServerAddresses * ${vDNS[*]}
	${NO_SEARCH}d.add SearchDomains * ${SEARCH_DOMAIN}
	set State:/Network/Service/${PSID}/DNS

	# Now, initialize the map that will be compared against the system-generated map
	# which means that we will have to aggregate configurations of statically-configured
	# nameservers, and statically-configured search domains
	d.init
	d.add DomainName ${domain}
	${AGG_DNS}d.add ServerAddresses * ${STATIC_DNS} ${vDNS[*]}
	${AGG_SEARCH}d.add SearchDomains * ${STATIC_SEARCH} ${SEARCH_DOMAIN}
	set State:/Network/OpenVPN/DNS

	# We're done
	quit
EOF

# Generate an updated plist with the proper path
DIR="$(dirname "${0}")"
LEASE_WATCHER="${DIR}/LeaseWatch.plist"
sed -e "s|\${DIR}|${DIR}|g" "${LEASE_WATCHER}.template" > "${LEASE_WATCHER}"
launchctl load "${LEASE_WATCHER}"

exit 0
