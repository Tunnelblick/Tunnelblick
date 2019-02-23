#!/bin/bash
# - must be bash: uses bash-specific tricks
#
# ******************************************************************************************************************
# Alternative up script for Tunnelblick
#
# Created by:
#      Merging Ben Low's openvpn-tun-up-down.sh and openvpn-tap-up-down.sh scripts
#      Splitting the result into separate up and down scripts
#      Incorporating option processing from standard tunnelblick scripts
#
# ******************************************************************************************************************
#
# openvpn-tun-up-down.sh
#
# A script to be used as an OpenVPN routed (tun) up/down script on Mac OSX 10.4
# - OpenVPN will have assigned peer address as part of the tun establishment
# - the server may also have pushed routes, and "DHCP"-like information (DNS Domain and server)
#   - this script extracts any such options and merges them into the current DNS config
#
# Use in your OpenVPN config file as follows:
#
#    up  openvpn-tun-up-down.sh
#
# openvpn-tap-up-down.sh
#
# A script to be used as an OpenVPN bridged (tap) up/down script on Mac OSX 10.4
# - uses ipconfig to acquire a DHCP lease via the OpenVPN tap interface, and scutil to
#  incorporate the DHCP-supplied DNS configuration
#
# Use in your OpenVPN config file as follows:
#
#    up  openvpn-tap-up-down.sh
#
# - up: openvpn calls the 'up' script after the tun/tap interface is created, but before the link
#   to the server is available for use (ditto 'up-delay' at least for UDP)
#   - on testing w/ openvpn 2.0.5, and tcpdump on the tap interface as soon as it comes up,
#     packets are queued up on the interface (and not actually sent over the openvpn tunnel)
#     until *after* this script returns; this makes sense: this script could fail in which
#     case the connection is invalid
#     - this means the DHCP acquisition can't complete until after this script exits
#     - that's not directly a problem as the macOS DHCP client should do everything we need
#       to make the interface functional, all by itself - *except* for one small thing: as of
#       macOS 10.4.7 the DHCP-acquired DNS information is not "merged" into the System
#       Configuration (macOS bug?)
#       - thus we have a chicken-and-egg situation: we need to manually fixup the DNS config,
#         but can't until we get the DHCP lease; we won't get the lease until we this script exits
#       - the solution is to spawn a little "helper" that waits until the lease is acquired,
#         and then does the DNS fixup
#
# - down: the only sensible 'down' action is to release the DHCP lease (as a courtesy to the
#   DHCP server), alas it's too late to do this *after* the connection has been shutdown (as
#   of OpenVPN 2.0 there's no "pre-disconnect" script option; note that both 'down' and
#   'down-pre' are called only after the connection to the server is closed ('down-pre' before
#   closing the tun/tap device, 'down' after)
#   - macOS automatically cleans up the System Config keys created from ipconfig, but we need to
#     manually remove the DNS fixup
#
# 2006-09-21    Ben Low               original
#
# 2010-09-30    Jonathan K Bullard    Downloaded from http://openvpn.net/archive/openvpn-users/2006-10/msg00120.html
#                                     Modified as described above

# ******************************************************************************************************************
# BEGIN INSERTION FROM client.up.tunnelblick.sh:
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

while [ $# -ne 0 ] ; do
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
    else
        if [  "${1:0:1}" = "-" ] ; then                     # Shift out Tunnelblick arguments (they start with "-") that we don't understand
            shift                                           # so the rest of the script sees only the OpenVPN arguments                            
        else
            break
        fi
    fi
done

TBCONFIG="$config"
# Note: The script log path is constructed from the path of the regular config file, not the shadow copy
# if the config is shadow copy, e.g. /Library/Application Support/Tunnelblick/Users/Jonathan/Folder/Subfolder/config.ovpn
# then convert to regular config     /Users/Jonathan/Library/Application Support/Tunnelblick/Configurations/Folder/Subfolder/config.ovpn
#      to get the script log path
# Note: "/Users/..." works even if the home directory has a different path; it is used in the name of the script log file, and is not used as a path to get to anything.
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

trim() {
	echo ${@}
}

# ******************************************************************************************************************
# END INSERTION FROM client.up.tunnelblick.sh
#
# BEGIN code from openvpn-tun-up-down.sh and openvpn-tap-up-down.sh (first line modified to echo to Tunnelblick log file)
# ******************************************************************************************************************

if [ -z "$dev" ]; then echo "$0: \$dev not defined, exiting" >> "${SCRIPT_LOG_FILE}"; exit 1; fi

if ${ARG_TAP} ; then

     # bring the interface up and set it to DHCP
     # - System Configuration dynamic store will be automatically updated, with the
     #       State:/Network/Service/DHCP-tap0
     #   data store created.
     # - the ipconfig man page notes that it should only be used for "test and debug" purposes,
     #   and that you're supposed to use the SystemConfiguration APIs to manipulate the network
     #   configuration
     #   - alas, there appears to be no CLI utility other than ipconfig

     /usr/sbin/ipconfig set "$dev" DHCP

     # spawn our little DNS-fixerupper
     {
         # whilst ipconfig will have created the neccessary Network Service keys, the DNS
         # settings won't actually be used by macOS unless the SupplementalMatchDomains key
         # is added
         # ref. <http://lists.apple.com/archives/Macnetworkprog/2005/Jun/msg00011.html>
         # - is there a way to extract the domains from the SC dictionary and re-insert
         #   as SupplementalMatchDomains? i.e. not requiring the ipconfig domain_name call?

         # - wait until we get a lease before extracting the DNS domain name and merging into SC
         # - despite it's name, ipconfig waitall doesn't (but maybe one day it will :-)
         /usr/sbin/ipconfig waitall

         # usually takes at least a few seconds to get a DHCP lease
         sleep 3
         n=0
         while [ -z "$domain_name" -a $n -lt 5 ]
         do
             sleep $n
             n=`expr $n + 1`
             domain_name=`/usr/sbin/ipconfig getoption $dev domain_name 2>/dev/null`
         done

         if [ "$domain_name" ]; then
         /usr/sbin/scutil <<EOF
d.init
get State:/Network/Service/DHCP-$dev/DNS
d.add SupplementalMatchDomains * $domain_name
set State:/Network/Service/DHCP-$dev/DNS
EOF
         fi

     } &

else

     # need to create two Network Service keys:
     # 1. State:/Network/Service/<serviceID>/IPv4 key containing information about the tunnel
     # 2. State:/Network/Service/<serviceID>/DNS key including the SupplementalMatchDomains key
     # ref. thread: http://lists.apple.com/archives/Macnetworkprog/2005/Jun/msg00011.html
     # and http://lists.apple.com/archives/Macnetworkprog/2005/Sep/msg00047.html
     # - the first thread mentions 'OverridePrimary', but that sets "Both the default route
     #   and the default resolver configuration ..." which is NOT what we want here.

     # "parse" foreign_options into separate DNS and DOMAIN records
     # - based on Tunnelblick's client.up.osx.sh
     # e.g. (could be any number, in any order; assume consecutive):
     #   foreign_option_1=dhcp-option DOMAIN example.net
     #   foreign_option_2=dhcp-option DNS 10.1.0.1
     unset dns
     unset domain
     n=1; i=0; j=0;
     while o=foreign_option_${n}; o=${!o}; [ "$o" ]
     do
         #echo "$n - $o ($i, $j)"
         case $o in
             'dhcp-option DNS '*)        dns[i++]=${o/dhcp-option DNS /};;
             'dhcp-option DOMAIN '*)     domain[j++]=${o/dhcp-option DOMAIN /} ;;
         esac;
         let n++
     done

     #echo "dns [${dns[0]}] [${dns[1]}] [${dns[2]}]"
     #echo "dom [${domain[0]}] [${domain[1]}] [${domain[2]}]"

     if [ ${#dns[@]} ]; then
         /usr/sbin/scutil <<EOF
d.init
d.add Addresses * ${ifconfig_local}
d.add DestAddresses * ${ifconfig_remote}
d.add InterfaceName ${dev}
set State:/Network/Service/openvpn-${dev}/IPv4
d.init
d.add ServerAddresses * ${dns[*]}
d.add SupplementalMatchDomains * ${domain[*]}
set State:/Network/Service/openvpn-${dev}/DNS
EOF
     fi

fi

##### FIN
