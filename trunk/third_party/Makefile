# This Makefile builds all the third_party code
# It shouldn't be called by anything other than automated scripts

# Both lzo and openvpn should be built universally

LZO_DIR=lzo-2.02
PKCS11_DIR=pkcs11-helper-1.07

all: tuntap lzo openvpn

pkcs11-helper::
	@for a in ppc i686; do \
		echo Configure PKCS11-Helper for $$a; \
		cd $(PKCS11_DIR); \
		echo Forcefully be clean; \
		$(MAKE) clean; \
		OPENSSL_LIBS="-lcrypto" CFLAGS="-isysroot /Developer/SDKs/MacOSX10.4u.sdk -Os -mmacosx-version-min=10.4 -arch $$a" ./configure --enable-static --disable-dependency-tracking --prefix=$$(pwd)/staging_$$a/ --includedir=$$(pwd)/staging/include/; \
		echo Build PKCS11-Helper; \
		$(MAKE); \
		echo Install to third_party/$(PKCS11_DIR)/staging_$$a; \
		$(MAKE) install; \
		cd ../; \
	done
	mkdir -p $(PKCS11_DIR)/staging/lib
	lipo $(PKCS11_DIR)/staging_*/lib/libpkcs11-helper.a -create -output $(PKCS11_DIR)/staging/lib/libpkcs11-helper.a
	cp  $(PKCS11_DIR)/staging_i686/lib/libpkcs11-helper.la  $(PKCS11_DIR)/staging/lib/ 

lzo::
	@for a in ppc i686; do \
		echo Configure LZO for $$a; \
		cd $(LZO_DIR); \
		echo Forcefully be clean; \
		$(MAKE) clean; \
		CFLAGS="-isysroot /Developer/SDKs/MacOSX10.4u.sdk -Os -mmacosx-version-min=10.4 -arch $$a" ./configure --disable-dependency-tracking --disable-asm --prefix=$$(pwd)/staging_$$a/ --includedir=$$(pwd)/staging/include/; \
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

openvpn: lzo pkcs11-helper
	@for a in ppc i686; do \
		echo Configure OpenVPN for $$a; \
		cd openvpn/; \
		echo Forcefully be clean; \
		$(MAKE) clean; \
		autoreconf -i -v; \
		LDFLAGS="-L../$(PKCS11_DIR)/staging/lib/" CFLAGS="-isysroot /Developer/SDKs/MacOSX10.4u.sdk -Os -mmacosx-version-min=10.4 -arch $$a" ./configure --with-lzo-headers=../$(LZO_DIR)/staging/include/ --with-lzo-lib=../$(LZO_DIR)/staging/lib/ --with-pkcs11-helper-headers=../$(PKCS11_DIR)/staging/include/ --with-pkcs11-helper-libs=../$(PKCS11_DIR)/staging/lib/ --disable-dependency-tracking; \
		echo Build OpenVPN; \
		$(MAKE); \
		mv openvpn openvpn_tblk_$$a; \
		cd ../; \
	done
		
		# Use lipo to create a universal library
		lipo openvpn/openvpn_tblk_* -create -output openvpn/openvpn

openvpn-clean:
	$(MAKE) -C openvpn/ clean
	rm -f openvpn/openvpn_tblk_*

.PHONY : tuntap

tuntap: 
	# Now we'll build the tun/tap driver
	$(MAKE) -C tuntap/

tuntap-clean:
	$(MAKE) -C tuntap/ clean



clean: lzo-clean tuntap-clean openvpn-clean
