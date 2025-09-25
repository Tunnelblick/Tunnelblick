#!/bin/sh -e
trap "" TSTP
trap "" HUP
trap "" INT
export PATH="/bin:/sbin:/usr/sbin:/usr/bin"

configuration_display_name() {

    local display_name

    display_name="${TUNNELBLICK_CONFIG_FOLDER/.tblk\/Contents\/Resources/}"                                                 # Strip suffix from configuration path
    if [ "${display_name/\/Library\/Application Support\/Tunnelblick\/Users\//}" != "$display_name" ] ; then
        display_name="${display_name/\/Library\/Application Support\/Tunnelblick\/Users\//}"                                # Strip prefix up to username/ from private configuration path
        display_name="${display_name#*\/}"                                                                                  # Strip username/ from private config"
    elif [ "${display_name/\/Library\/Application Support\/Tunnelblick\/Shared\//}" != "$display_name" ] ; then
        display_name="${display_name/\/Library\/Application Support\/Tunnelblick\/Shared\//}"                               # Strip prefix from shared configuration path
    elif [ "${display_name/\/Applications\/Tunnelblick.app\/Contents\/Resources\/Deploy\//}" != "$display_name" ] ; then
        display_name="${display_name/\/Applications\/Tunnelblick.app\/Contents\/Resources\/Deploy\//}"                      # Strip prefix from Deployed configuration path
    else
        echo "Error: Unable to determine configuration's display name from configuration path '$TUNNELBLICK_CONFIG_FOLDER'"
        exit 1
    fi

    echo "$display_name"
}

disconnect_and_exit() {

    local display_name
    display_name="$( configuration_display_name )"

    echo "Disconnecting '$display_name'"

    osascript -e "tell application \"/Applications/Tunnelblick.app\"" -e "disconnect \"$display_name\"" -e "end tell"

    exit 1
}

exit_if_suspicious_domain_name() {

    # @param String string - Content to test
    #
    # Prevent script injection attacks from a domain name supplied by the OpenVPN server.
    #
    # This is a very loose test, it exits after outputting an error message if a domain name
    # contains characters that don't belong in a domain name.
    #
    # Allows empty string or any sequence of characters 0-9, A-F, a-f, "." and "-", and any Unicode characters.
    #
    # Will allow (for example) "", "-", "9", all of which are invalid domain names, as well as domain
    # names that are longer than 63 characters.
    #
    # Allows Unicode characters, and allows punycode, which consists of the same characters as a pure ASCII domain name.

    local str
    local i
    local val

    str="$1"

    for (( i=0; i<${#str}; i++ )); do
        ch="${str:$i:1}"
        val=$(printf '%d' "'$ch")

        if [ "$val" -ge  65 ] \
        && [ "$val" -le  90 ] ; then
            continue; # A-Z
        fi

        if [ "$val" -ge  97 ] \
        && [ "$val" -le 122 ] ; then
            continue; # a-z
        fi

        if [ "$val" -ge 48 ] \
        && [ "$val" -le 57 ] ; then
            continue; # 0-9
        fi

        if [ "$val" -ge 127 ] \
        || [ "$val" -le 0 ] ; then
            continue; # > 0x80
        fi

        if [ "$ch" = "." ] \
        || [ "$ch" = "-" ] ; then # . or -
            continue;
        fi

        echo "Error: Disconnecting because of a suspicious domain name: '$str'"
        disconnect_and_exit
    done
}

exit_if_suspicious_ip_address() {

    # @param String string - Content to test
    #
    # Prevent script injection attacks from an IP address supplied by the OpenVPN server.
    #
    # This is a very loose test, it exits after outputting an error message if an IP address
    # contains characters that don't belong in an IP address).
    #
    # Allows empty string or any sequence of the characters 0-9, A-F, a-f, "." and ":".
    #
    # Will allow invalid IP addresses, for example, abc.123.456:...:::::::::::::::: and a.b.c.d.e.f.

    local str
    local i
    local val

    str="$1"

    for (( i=0; i<${#str}; i++ )); do
        ch="${str:$i:1}"
        val=$(printf '%d' "'$ch")

        # Allow 0-9
        if [ "$val" -ge 48 ] \
        && [ "$val" -le 57 ] ; then
            continue; # 0-9
        fi

        # Allow A-F
        if [ "$val" -ge 65 ] \
        && [ "$val" -le 70 ] ; then
            continue; # A-F
        fi

        # Allow a-f
        if [ "$val" -ge 97 ] \
        && [ "$val" -le 102 ] ; then
            continue; # a-f
        fi

        if [ "$ch" = "." ] \
        || [ "$ch" = ":" ] ; then
            continue;
        fi

        echo "Error: Disconnecting because of a suspicious IP address: '$str'"
        disconnect_and_exit
    done
}

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
            exit_if_suspicious_domain_name "$domain"
            ;;
        *DNS*    )
            sTempVal=${vOptions[nOptionIndex-1]//dhcp-option DNS /}
            exit_if_suspicious_ip_address "$sTempVal"
            vDNS[nNameServerIndex-1]="$sTempVal"
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
if [ ! -e "/Library/Application Support/Tunnelblick/openvpn_dns_${PSID}" ]; then
	echo "$OLDDNS1 $OLDDNS2" > "/Library/Application Support/Tunnelblick/openvpn_dns_${PSID}"
fi
if [ ! -e "/Library/Application Support/Tunnelblick/openvpn_domain_${PSID}" ]; then
	echo "$OLDDOMAIN" > "/Library/Application Support/Tunnelblick/openvpn_domain_${PSID}"
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
