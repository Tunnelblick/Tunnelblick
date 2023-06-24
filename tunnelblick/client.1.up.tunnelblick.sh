#!/bin/sh -e
trap "" TSTP
trap "" HUP
trap "" INT
export PATH="/bin:/sbin:/usr/sbin:/usr/bin"

INTERFACE=$1
IDENTIFYER="org.openvpn.${INTERFACE}"

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

PSID=$( (scutil | grep PrimaryService | sed -e 's/.*PrimaryService : //')<< EOF
open
get State:/Network/Global/IPv4
d.show
quit
EOF
)

OLDDOMAIN=$( (scutil | grep "DomainName : " | sed -e 's/.*DomainName : //')<< EOF
open
get State:/Network/Service/${PSID}/DNS
d.show
quit
EOF
)

OLDDNS1=$( (scutil | grep '0 : ' | sed -e 's/\ *0 : //')<< EOF
open
get State:/Network/Service/${PSID}/DNS
d.show
quit
EOF
)

OLDDNS2=$( (scutil | grep '1 : ' | sed -e 's/\ *1 : //')<< EOF
open
get State:/Network/Service/${PSID}/DNS
d.show
quit
EOF
)


# save old dns settings to temporary file
if [ ! -e /Library/Application Support/Tunnelblick/openvpn_dns_${PSID} ]; then
	echo "$OLDDNS1 $OLDDNS2" > /Library/Application Support/Tunnelblick/openvpn_dns_${PSID}
fi
if [ ! -e /Library/Application Support/Tunnelblick/openvpn_domain_${PSID} ]; then
	echo "$OLDDOMAIN" > /Library/Application Support/Tunnelblick/openvpn_domain_${PSID}
fi

# set pushed nameserver
scutil << EOF
open
d.init
d.add ServerAddresses * $vDNS
d.add DomainName $domain
set State:/Network/Service/${PSID}/DNS
quit
EOF


exit 0
