# This Makefile builds all the third_party code
# It shouldn't be called by anything other than automated scripts

# Both lzo and openvpn should be built universally
# These are required but break lzo building:
CFLAGS=-Os -g -arch i686 -arch ppc -isysroot /Developer/SDKs/MacOSX10.4u.sdk
LDFLAGS=-arch i686 -arch ppc

all: tuntap lzo openvpn

lzo:
	# First we configure lzo
	cd lzo-2.02/ && LDFLAGS="$(LDFLAGS)" CFLAGS="$(CFLAGS)" ./configure --disable-dependency-tracking --disable-asm --prefix=`pwd`/staging/

	# Then we build lzo
	$(MAKE) -C lzo-2.02/
	# Now lzo libs are inside of: third_party/lzo-2.02/src
	$(MAKE) -C lzo-2.02/ install

lzo-clean:
	$(MAKE) -C lzo-2.02/

openvpn: lzo
	# Now we'll configure openvpn
	cd openvpn/ && autoreconf -i -v
	# For building with our local lzo
	cd openvpn/ && ./configure --with-lzo-headers=../lzo-2.02/staging/include/ --with-lzo-lib=../lzo-2.02/staging/lib/ --disable-dependency-tracking
	# For building without lzo
	# cd openvpn/ && ./configure --disable-lzo
	# Now we'll build openvpn
	$(MAKE) -C  openvpn/

openvpn-clean:
	$(MAKE) -C openvpn/

.PHONY : tuntap

tuntap: 
	# Now we'll build the tun/tap driver
	$(MAKE) -C tuntap/

tuntap-clean:
	$(MAKE) -C tuntap/ clean



clean: lzo-clean tuntap-clean openvpn-clean
