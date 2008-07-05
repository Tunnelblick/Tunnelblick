# This is the Makefile that will eventually output a signed .dmg
# 

CFLAGS=-Os -g -arch i686 -arch ppc -isysroot /Developer/SDKs/MacOSX10.4u.sdk
LDFLAGS=-arch i686 -arch ppc
TMPDMG=/tmp/tunnelblick/
TARGET=Universal
VERSION=3.0b5

# Default to everything
all: third_party tunnelblick dmg
clean: third_party-clean tunnelblick-clean dmg-clean

# First we'll compile the third party modules
third_party:
	# Here's where we'll call the top level third_party/Makefile
	$(MAKE) -C ../third_party
third_party-clean:
	$(MAKE)	-C ../third_party clean

# Now we'll build tunnelblick
tunnelblick: tunnelblick-clean third_party
	# Here's where we'll build tunnelblick
	xcodebuild -configuration Deployment -alltargets

tunnelblick-clean:
	# Here's where we'll clean up the mess left from building tunnelblick
	xcodebuild clean -alltargets

dmg: tunnelblick
	# Prep our disk image source directory
	mkdir -p $(TMPDMG)
	cp -rv build/Deployment/Tunnelblick.app $(TMPDMG)
	ln -s /Applications/ $(TMPDMG)/Applications
	# Here's where we'll make the dmg
	hdiutil create -srcfolder $(TMPDMG) Tunnelblick-$(TARGET)-$(VERSION).dmg
	@echo "The sha1 of the freshly built dmg is: "
	openssl sha1 Tunnelblick-$(TARGET)-$(VERSION).dmg

dmg-clean:
	rm -r $(TMPDMG)
	rm -r Tunnelblick-$(TARGET)-$(VERSION).dmg

dmg-sig:
	# Here's where we sign the dmg
	gpg -a --clearsign -b Tunnelblick-$TARGET-$VERSION.dmg
