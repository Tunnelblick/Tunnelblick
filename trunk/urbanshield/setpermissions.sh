#!/bin/sh

sudo chown root:wheel build/Development/Tunnelblick.app/Contents/Resources/openvpnstart
sudo chmod +s build/Development/Tunnelblick.app/Contents/Resources/openvpnstart

sudo chown -R root:wheel build/Development/Tunnelblick.app/Contents/Resources/*.kext

sudo chown -R root:wheel ./*.kext