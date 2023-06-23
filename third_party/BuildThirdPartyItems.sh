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

cd ../third_party/

# The following line is needed so make openssl build without error
COMMAND_MODE=unix2003

# The following line is needed so up-to-date autotools are used
PATH="/usr/local/bin:$PATH"

# Test for version 2.69 of autoconf
autoconf_version="$(autoconf --version | grep autoconf | sed -e 's/autoconf (GNU Autoconf) //')"
if [ "${autoconf_version}" != "2.69" ] ; then
echo "warning: autoconf is version '${autoconf_version}'; expected version 2.69. Autotools may be out-of-date which can cause problems building some of the third_party programs"
fi

# Test for version 1.9 of automake
automake_version="$(automake --version | grep automake | sed -e 's/automake (GNU automake) //')"
if [ "${automake_version}" != "1.9" ] ; then
echo "warning: automake is version '${automake_version}'; expected version 1.9. Autotools may be out-of-date which can cause problems building some of the third_party programs"
fi

if [ ! -e do-not-clean ]; then
make clean
fi

make

touch do-not-clean
