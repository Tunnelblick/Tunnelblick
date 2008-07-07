##!/bin/sh
if [ -d /usr/local/sbin ]; then
    cp build/openvpnstart /usr/local/sbin/
    cp build/openvpnstop /usr/local/sbin/
    
    chmod u+s /usr/local/sbin/openvpnstart /usr/local/sbin/openvpnstop
    chown root:wheel /usr/local/sbin/openvpnstart /usr/local/sbin/openvpnstop
else
    mkdir -p /usr/local/sbin
    cp build/openvpnstart /usr/local/sbin/
    cp build/openvpnstop /usr/local/sbin/

    chmod u+s /usr/local/sbin/openvpnstart /usr/local/sbin/openvpnstop
    chown root:wheel /usr/local/sbin/openvpnstart /usr/local/sbin/openvpnstop
fi            
