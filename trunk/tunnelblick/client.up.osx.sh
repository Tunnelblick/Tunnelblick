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
fi

PSID=$( (scutil | grep PrimaryService | sed -e 's/.*PrimaryService : //')<<- EOF
	open
	show State:/Network/Global/IPv4
	quit
EOF
)

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

	get State:/Network/Service/${PSID}/DNS
	set State:/Network/OpenVPN/OldDNS

	d.init
	d.add ServerAddresses * ${vDNS[*]}
	d.add DomainName ${domain}
	set State:/Network/OpenVPN/DNS
	set State:/Network/Service/${PSID}/DNS
	quit
EOF

# Generate an updated plist with the proper path
DIR="$(dirname "${0}")"
LEASE_WATCHER="${DIR}/LeaseWatch.plist"
sed -e "s|\${DIR}|${DIR}|g" "${LEASE_WATCHER}.template" > "${LEASE_WATCHER}"
launchctl load "${LEASE_WATCHER}"

exit 0
