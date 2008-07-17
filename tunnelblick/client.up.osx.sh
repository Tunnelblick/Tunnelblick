#!/bin/sh -e
trap "" TSTP
trap "" HUP
trap "" INT
export PATH="/bin:/sbin:/usr/sbin:/usr/bin"

INTERFACE=$1
IDENTIFYER="org.openvpn.${INTERFACE}"

# only do something when the server really is pushing something
# What do we actually expect from foreign_option?
if [ "$foreign_option_1" == "" ]; then
	exit 0;
fi

nOptionIndex=1
nNameServerIndex=1
unset vForOptions
unset vDNS
unset vOptions

# This starts as 1 and enters the loop
while vForOptions = foreign_option_${nOptionIndex};	[ -n "${!vForOptions}" ]; 
do
	{
	
	# Examples documented for first run
	# vOptions[0] = foreign_option_1
	vOptions[nOptionIndex-1]=${!vForOptions}

	# Here we take the value from vOptions[0]
	# We figure out what it is
	case ${vOptions[nOptionIndex-1]} in
		# If it's a search domain
		*DOMAIN* )
			# Stuff the contents of the array into $domain
			# $domain = {CONTENTS OF array} . //dhcp-option DOMAIN /
			domain=${vOptions[nOptionIndex-1]//dhcp-option DOMAIN /}
		;;
		# If it's a DNS server the client will use
		*DNS*    )
			# Stuff the contents of the array into $vDNS
			# vDNS[0] = {CONTENTS OF array} . //dhcp-option DNS /
			vDNS[nNameServerIndex-1]=${vOptions[nOptionIndex-1]//dhcp-option DNS /}
			# Increment the name server index to allow for adding more dns servers
			let nNameServerIndex++
		;;
	esac

	let nOptionIndex++

	}
done

# Set domain to a default value when no domain is being transmitted
if [ "$domain" -eq "" ]; then
	# The remote server didn't set a search domain
	domain="openvpn.automatically.set.the.search.domain.to.something.invalid"
fi

# Oh my lord. Please remove the forks from my subshelled bleeding eyes.
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

# Perhaps this should go in /var/tmp?
# Save old dns settings to temporary file
if [ ! -e /tmp/openvpn_dns_${PSID} ]; then
	echo "$OLDDNS1 $OLDDNS2" > /tmp/openvpn_dns_${PSID}
fi
if [ ! -e /tmp/openvpn_domain_${PSID} ]; then
	echo "$OLDDOMAIN" > /tmp/openvpn_domain_${PSID}
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
