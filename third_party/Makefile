# This Makefile builds all the third_party code
# It shouldn't be called by anything other than automated scripts

# Both lzo and openvpn should be built universally

# Cross compiling for 10.4u seems to be broken on Leopard (9A581), so we need this symlink:
# sudo ln -s /Developer/SDKs/MacOSX10.4u.sdk/usr/lib/crt1.o /Developer/SDKs/MacOSX10.4u.sdk/usr/lib/crt1.10.5.o

LZO_DIR=lzo-2.02

all: tuntap lzo openvpn

lzo::
	@for a in powerpc i686; do \
		echo Configure LZO for $$a; \
		cd $(LZO_DIR); \
		echo Forcefully be clean; \
		$(MAKE) clean; \
		CC=$$(ls /usr/bin/$$a-apple-darwin*-gcc-*) CFLAGS="-isysroot /Developer/SDKs/MacOSX10.4u.sdk -Os" ./configure --disable-dependency-tracking --disable-asm --prefix=$$(pwd)/staging_$$a/ --includedir=$$(pwd)/staging/include/; \
		echo Build LZO; \
		$(MAKE); \
		echo Install to third_party/$(LZO_DIR)/staging_$$a; \
		$(MAKE) install; \
		cd ../; \
	done
	
	# Use lipo to create a universal library
	mkdir -p $(LZO_DIR)/staging/lib
	lipo $(LZO_DIR)/staging_*/lib/liblzo2.a -create -output $(LZO_DIR)/staging/lib/liblzo2.a
	cp  $(LZO_DIR)/staging_i686/lib/liblzo2.la  $(LZO_DIR)/staging/lib/ 

	# wtf? library was renamed??? move it back so openvpn will build correctly
	cd $(LZO_DIR)/staging/lib/; mv liblzo2.a liblzo.a; mv liblzo2.la liblzo.la
	
lzo-clean:
	$(MAKE) -C $(LZO_DIR) clean
	rm -rf $(LZO_DIR)/staging*

openvpn::
	@for a in powerpc i686; do \
		echo Configure OpenVPN for $$a; \
		cd openvpn/; \
		echo Forcefully be clean; \
		$(MAKE) clean; \
		autoreconf -i -v; \
		CC=$$(ls /usr/bin/$$a-apple-darwin*-gcc-*) CFLAGS="-isysroot /Developer/SDKs/MacOSX10.4u.sdk -Os" ./configure --with-lzo-headers=../$(LZO_DIR)/staging/include/ --with-lzo-lib=../$(LZO_DIR)/staging/lib/ --disable-dependency-tracking; \
		echo Build OpenVPN; \
		$(MAKE); \
		mv openvpn openvpn_tblk_$$a; \
		cd ../; \
	done
		
		# Use lipo to create a universal library
		lipo openvpn/openvpn_tblk_* -create -output openvpn/openvpn

openvpn-clean:
	$(MAKE) -C openvpn/ clean
	rm openvpn/openvpn_tblk_*

.PHONY : tuntap

tuntap: 
	# Now we'll build the tun/tap driver
	$(MAKE) -C tuntap/

tuntap-clean:
	$(MAKE) -C tuntap/ clean



clean: lzo-clean tuntap-clean openvpn-clean
