#!/bin/sh -e
# Copyright © 2015 by Jonathan K. Bullard. All rights reserved.
#
# This script downloads and installs new versions of the GNU "autotools" -- a set of
# command line tools that are obsolete in Xcode 3 and are missing from Xcode 4 and higher.
#
# It installs the tools to /usr/local/bin. It uses sudo to install because /usr/local/bin
# is a protected folder. So it must be run from an OS X account with administrator
# privileges. (Sudo will ask for the user's password once.)



# Version of each tool to download and install:

readonly autoconf_version="autoconf-2.69"
readonly automake_version="automake-1.15"
readonly libtool_version="libtool-2.4.5"

# You can check for the latest version of each tool by examining the following:
#     http://ftpmirror.gnu.org/autoconf
#     http://ftpmirror.gnu.org/automake
#     http://ftpmirror.gnu.org/libtool
# If you wish to install different versions, modify the variables above.
# Note that it is possible (although unlikely) that later versions of the autotools may
# not work properly for the third party build process.



# Folder to which the tools are downloaded and in which the tools are built:

readonly downloads_folder_path=~/"Downloads"

# Note that if you modify this path, you should be sure to either have no spaces in the
# path or use double-quotes to enclose the path. If you use double-quotes with ~/, be sure
# the first double-quote follows the '~/'.



# URLs for downloading the tools:
readonly autoconf_url=http://ftpmirror.gnu.org/autoconf/${autoconf_version}.tar.gz
readonly automake_url=http://ftpmirror.gnu.org/automake/${automake_version}.tar.gz
readonly libtool_url=http://ftpmirror.gnu.org/libtool/${libtool_version}.tar.gz

if [ ! -d "${downloads_folder_path}" ] ; then
    echo "Downloads folder '${downloads_folder_path}' does not exist or is not a folder"
    exit 1
fi

echo "INSTALLING AUTOCONF:"
cd "${downloads_folder_path}"
curl -OL "${autoconf_url}"
tar xzf "${autoconf_version}.tar.gz"
cd "${autoconf_version}"
./configure
make
sudo make install

# Building and installing automake requires the (just downloaded and installed) latest
# version of autoconf, so we change the path to find that version first.

export "PATH=/usr/local/bin:$PATH"

echo "INSTALLING AUTOMAKE:"
cd "${downloads_folder_path}"
curl -OL "${automake_url}"
tar xzf "${automake_version}.tar.gz"
cd "${automake_version}"
./configure
make
sudo make install

echo "INSTALLING LIBTOOL:"
cd "${downloads_folder_path}"
curl -OL "${libtool_url}"
tar xzf "${libtool_version}.tar.gz"
cd "${libtool_version}"
./configure
make
sudo make install

echo "Installation of autotools completed successfully"
