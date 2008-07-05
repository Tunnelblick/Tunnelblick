#!/bin/sh
#
# calls PackageMaker to build the package
#
pwd=`pwd`
pkgmkr=/Developer/Applications/Utilities/PackageMaker.app/Contents/MacOS/PackageMaker

# make copies of the resource and root directories, remove CVS data from them, make the files to be
# installed owned by root
root=$2
res=$3
roottmp="${root}_tmp"
restmp="${res}_tmp"

mkdir $roottmp
mkdir $restmp

tar cv -C $root . --exclude '*CVS*' | tar xv -C $roottmp
sudo chown -R root:wheel $roottmp || echo -E '\n\nInvalid password!\n\n'
tar cv -C $res . --exclude '*CVS*' | tar xv -C $restmp

# create the package
$pkgmkr -build -p $pwd/$1 -f $pwd/$roottmp -r $pwd/$restmp -i $pwd/$4/Info.plist -d $pwd/$4/Description.plist

sudo rm -rf $roottmp
rm -rf $restmp

exit 0

