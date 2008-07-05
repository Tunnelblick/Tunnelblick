#!/bin/sh -e
trap "" TSTP
trap "" HUP
trap "" INT
export PATH="/bin:/sbin:/usr/sbin:/usr/bin"

INTERFACE=$1
IDENTIFYER="org.openvpn.${INTERFACE}"

# if [ "$foreign_option_1" == "" ]; then
# 	exit 0
# fi

PSID=$( (scutil | grep PrimaryService | sed -e 's/.*PrimaryService : //')<< EOF
open
get State:/Network/Global/IPv4
d.show
quit
EOF
)

if [ ! -e /tmp/openvpn_dns_${PSID} ]; then
	exit 0
fi
if [ ! -e /tmp/openvpn_domain_${PSID} ]; then
	exit 0
fi


scutil << EOF
open
d.init
d.add ServerAddresses * `cat /tmp/openvpn_dns_${PSID}`
d.add DomainName `cat /tmp/openvpn_domain_${PSID}`
set State:/Network/Service/${PSID}/DNS
quit
EOF


rm /tmp/openvpn_dns_${PSID} /tmp/openvpn_domain_${PSID}

