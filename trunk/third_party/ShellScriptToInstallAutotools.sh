#!/bin/sh -e
# Copyright © 2015 by Jonathan K. Bullard. All rights reserved.
#
# This script downloads and installs new versions of the GNU "autotools" -- a set of
# command line tools that are obsolete in Xcode 3 and are missing from Xcode 4 and higher.
#
# It downloads the following version of each tool (change to download different versions):

readonly autoconf_version=autoconf-2.69
readonly automake_version=automake-1.9
readonly libtool_version=libtool-2.4.5

# It installs the tools to /usr/local/bin. It uses sudo to install because /usr/local/bin
# is a protected folder. So it must be run from an OS X account with administrator
# privileges, and will ask for the the user's password.

# Download and build the tools in the user's "Downloads" folder.
readonly downloads_folder_path=~/Downloads

readonly autoconf_url=http://ftpmirror.gnu.org/autoconf/${autoconf_version}.tar.gz
readonly automake_url=http://ftpmirror.gnu.org/automake/${automake_version}.tar.gz
readonly libtool_url=http://ftpmirror.gnu.org/libtool/${libtool_version}.tar.gz

if [ ! -d ${downloads_folder_path} ] ; then
    echo "Downloads folder '${downloads_folder_path}' does not exist"
    exit 1
fi

echo "INSTALLING AUTOCONF:"
cd "${downloads_folder_path}"
curl -OL ${autoconf_url}
tar xzf ${autoconf_version}.tar.gz
cd ${autoconf_version}
./configure
make
sudo make install

# Building and installing automake requires the (just downloaded and installed) latest
# version of autoconf, so we change the path to find that version first.

export "PATH=/usr/local/bin:$PATH"

echo "INSTALLING AUTOMAKE:"
cd "${downloads_folder_path}"
curl -OL ${automake_url}
tar xzf ${automake_version}.tar.gz
cd ${automake_version}
./configure
make
sudo make install

echo "INSTALLING LIBTOOL:"
cd "${downloads_folder_path}"
curl -OL ${libtool_url}
tar xzf ${libtool_version}.tar.gz
cd ${libtool_version}
./configure
make
sudo make install

echo "Installation of autotools completed successfully"