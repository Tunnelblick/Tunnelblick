#!/bin/bash
#
# Copyright (c) 2016 by Jonathan K. Bullard. All rights reserved.
#
# This file is part of Tunnelblick.
#
# Tunnelblick is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 2
# as published by the Free Software Foundation.
#
# Tunnelblick is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program (see the file COPYING included with this
# distribution); if not, write to the Free Software Foundation, Inc.,
# 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
# or see http://www.gnu.org/licenses/.
#
#
# This build phase builds the third party items used by Tunnelblick.
#
# Because these items rarely change but take a lot of time to build, they are not
# "cleaned" when the Tunnelblick project is cleaned using Xcode.
#
# However, there are times when it is convenient to clean them. This can be accomplished
# by removing the third_party/do-not-clean file which was created when the third party
# items were last built.
#
# So, to do a clean build of the third party items, make sure that the
# third_party/do-not-clean file does not exist, and then build Tunnelblick normally.

# Make sure we have a recent version of Xcode
if [ ${XCODE_VERSION_ACTUAL} -lt 0731 ] ; then
  outer_dir="${PWD%/*}"
  echo "error: Tunnelblick must be built with Xcode 6.3 or higher. This version of Tunnelblick.xcodeproj is for Xcode 7.3.1 or higher on macOS 10.10.3 or higher. See ${outer_dir}/README.txt"
  exit 1
fi

# Make sure there are no spaces in the path to this folder
path_to_build_folder="$( pwd )"
if [ "$path_to_build_folder" != "${path_to_build_folder/ /}" ] ; then
	echo "error: There should not be any spaces in the path to the 'tunnelblick' and 'third_party' folders"
	exit -1
fi

cd ../third_party/

# The following line is needed so make openssl build without error
COMMAND_MODE=unix2003

# The following line is needed so up-to-date autotools are used
PATH="/usr/local/bin:$PATH"

if [ ! -e do-not-clean ]; then
  make clean
fi

make

touch do-not-clean
