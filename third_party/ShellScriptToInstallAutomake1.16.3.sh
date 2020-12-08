#!/bin/sh -e
# Copyright © 2020 by Jonathan K. Bullard. All rights reserved.
#
# This script downloads and installs version 1.16.3 of automake.
#
# It should be used when an older version of automake has been installed by
# ShellScriptToInstallAutotools.sh.
#
# It installs or replaces /usr/local/bin/automake. It uses sudo to install because
# /usr/local/bin is a protected folder. So it must be run from an macOS account
# with administrator privileges. (Sudo will ask for the user's password once.)

# Version of automake to download and install:

readonly automake_version="automake-1.16.3"

# Folder to which the tools are downloaded and in which the tools are built:

readonly downloads_folder_path=~/"Downloads"


# URL for downloading automake:

readonly automake_url=https://ftpmirror.gnu.org/automake/${automake_version}.tar.gz

# Download automake:

if [ -L /usr/local/bin/automake ]; then
  echo "/usr/local/bin/automake exists & appears to be a symlink."
  echo "Presuming automake is from a package manager & refusing to overwrite."
  exit 1
fi

echo "INSTALLING AUTOMAKE:"
cd "${downloads_folder_path}"
curl -OL "${automake_url}"
tar xzf "${automake_version}.tar.gz"
cd "${automake_version}"
./configure
make
sudo make install

echo "Installation of $automake_version completed successfully"
