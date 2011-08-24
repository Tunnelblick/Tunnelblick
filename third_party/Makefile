# This Makefile builds all the third_party code
# It shouldn't be called by anything other than automated scripts

CC=gcc-4.0
MACOSX_DEPLOYMENT_TARGET=10.4
SDKROOT=/Developer/SDKs/MacOSX10.4u.sdk

CFLAGS=-isysroot $(SDKROOT) -Os -mmacosx-version-min=$(MACOSX_DEPLOYMENT_TARGET)

TOPDIR = $(PWD)
BUILD_DIR = build
THIRD_PARTY_PROJS = OPENSSL

OPENSSL_SRC_DIR = openssl-1.0.0d
OPENSSL_BUILD_DIR = $(TOPDIR)/$(BUILD_DIR)/$(OPENSSL_SRC_DIR)
OPENSSL_DEST_DIR = $(TOPDIR)/$(BUILD_DIR)/staging/$(OPENSSL_SRC_DIR)
OPENSSL_TARGET_FILES = $(foreach f, libcrypto.a libssl.a, $(OPENSSL_DEST_DIR)/lib/$(f))

PROJ_BUILD_DIRS = $(foreach proj, $(THIRD_PARTY_PROJS), $($(proj)_BUILD_DIR))

# Both lzo and openvpn should be built universally

LZO_DIR=lzo-2.05
PKCS11_DIR=pkcs11-helper-1.09
TUNTAP_DIR=tuntaposx-6e54e43

all: tuntap openvpn
	rm -rf $(BUILD_DIR)

buildenv: $(PROJ_BUILD_DIRS)
$(PROJ_BUILD_DIRS):
	mkdir -p $@;
	cd $@ && /usr/X11/bin/lndir $(TOPDIR)/$$(basename $@);

openssl-patch: $(OPENSSL_BUILD_DIR)
	@cd $(OPENSSL_BUILD_DIR); \
	if [ -d "$(TOPDIR)/patches/openssl" ]; then \
		for patchfile in $(TOPDIR)/patches/openssl/*.diff; do \
			patch -p0 -N --dry-run -i $$patchfile > /dev/null; \
			if [ $$? == 0 ]; then \
				patch -p0 -N -i $$patchfile; \
			fi \
		done \
	fi

openssl: openssl-patch
	@for a in darwin-i386-cc darwin-ppc-cc; do\
		echo Configure OpenSSL for $$a; \
		cd $(OPENSSL_BUILD_DIR); \
		echo Forcefully be clean; \
		$(MAKE) clean; \
		CC=$(CC) CFLAGS="$(CFLAGS)" ./Configure no-shared zlib no-krb5 --prefix="$(OPENSSL_DEST_DIR)/$$a" $$a; \
		echo Build OpenSSL for $$a; \
		$(MAKE) build_libs build_apps openssl.pc libssl.pc libcrypto.pc; \
		echo Install to $(OPENSSL_DEST_DIR)/$$a; \
		$(MAKE) install_sw; \
		cd -; \
	done
	ditto -v $(BUILD_DIR)/staging/$(OPENSSL_SRC_DIR)/darwin-i386-cc/include $(OPENSSL_DEST_DIR)/include/i386
	ditto -v $(BUILD_DIR)/staging/$(OPENSSL_SRC_DIR)/darwin-ppc-cc/include $(OPENSSL_DEST_DIR)/include/ppc
	mkdir -p $(OPENSSL_DEST_DIR)/lib; \
	for t in $(OPENSSL_TARGET_FILES); do \
		lipo $(BUILD_DIR)/staging/$(OPENSSL_SRC_DIR)/darwin*/lib/$$(basename $$t) -create -output $$t; \
	done
	rm -rf $(BUILD_DIR)/staging/$(OPENSSL_SRC_DIR)/darwin*
	
pkcs11-helper::
	@for a in ppc i386; do \
		echo Configure PKCS11-Helper for $$a; \
		cd $(PKCS11_DIR); \
		echo Forcefully be clean; \
		$(MAKE) clean; \
		OPENSSL_CFLAGS="-I$(OPENSSL_DEST_DIR)/include/$$a" OPENSSL_LIBS="-L$(OPENSSL_DEST_DIR)/lib -lssl -lcrypto -lz" CC=$(CC) CFLAGS="$(CFLAGS) -arch $$a" ./configure --enable-static --enable-shared=no --disable-dependency-tracking --prefix=$$(pwd)/staging_$$a --includedir=$$(pwd)/staging/include; \
		echo Build PKCS11-Helper; \
		$(MAKE); \
		echo Install to third_party/$(PKCS11_DIR)/staging_$$a; \
		$(MAKE) install; \
		cd ../; \
	done
	mkdir -p $(PKCS11_DIR)/staging/lib
	lipo $(PKCS11_DIR)/staging_*/lib/libpkcs11-helper.a -create -output $(PKCS11_DIR)/staging/lib/libpkcs11-helper.a
	cp  $(PKCS11_DIR)/staging_i386/lib/libpkcs11-helper.la  $(PKCS11_DIR)/staging/lib/ 

pkcs11-helper-clean:
	$(MAKE) -C $(PKCS11_DIR) clean
	rm -rf $(PKCS11_DIR)/staging*

lzo::
	@for a in ppc i386; do \
		echo Configure LZO for $$a; \
		cd $(LZO_DIR); \
		echo Forcefully be clean; \
		$(MAKE) clean; \
		CC=$(CC) CFLAGS="$(CFLAGS) -arch $$a" ./configure --disable-dependency-tracking --disable-asm --prefix=$$(pwd)/staging_$$a/ --includedir=$$(pwd)/staging/include/; \
		echo Build LZO; \
		$(MAKE); \
		echo Install to third_party/$(LZO_DIR)/staging_$$a; \
		$(MAKE) install; \
		cd ../; \
	done
	
	# Use lipo to create a universal library
	mkdir -p $(LZO_DIR)/staging/lib
	lipo $(LZO_DIR)/staging_*/lib/liblzo2.a -create -output $(LZO_DIR)/staging/lib/liblzo2.a
	cp  $(LZO_DIR)/staging_i386/lib/liblzo2.la  $(LZO_DIR)/staging/lib/ 

lzo-clean:
	$(MAKE) -C $(LZO_DIR) clean
	rm -rf $(LZO_DIR)/staging*

openvpn-patch:
	for openvpndir in `ls openvpn`; do \
		cd openvpn/$$openvpndir/openvpn; \
		for patchfile in ../patches/*.diff; do \
			patch -p0 -N --dry-run -i $$patchfile > /dev/null; \
			if [ $$? == 0 ]; then \
				patch -p0 -N -i $$patchfile; \
			fi \
		done; \
		cd ../../../; \
	done
	
openvpn: lzo openssl pkcs11-helper openvpn-patch
	for openvpndir in `ls openvpn`; do \
		for a in ppc i386; do \
			cd openvpn/$$openvpndir/openvpn; \
			$(MAKE) clean; \
			autoreconf -i -v; \
			CC=$(CC) CFLAGS="$(CFLAGS) -arch $$a" ./configure --with-lzo-headers=../../../$(LZO_DIR)/staging/include --with-lzo-lib=../../../$(LZO_DIR)/staging/lib --with-pkcs11-helper-headers=../../../$(PKCS11_DIR)/staging/include --with-pkcs11-helper-lib=../../../$(PKCS11_DIR)/staging/lib --with-ssl-headers=$(OPENSSL_DEST_DIR)/include/$$a --with-ssl-lib=$(OPENSSL_DEST_DIR)/lib --disable-dependency-tracking; \
			$(MAKE) LIBS="$(OPENSSL_TARGET_FILES) -lpkcs11-helper -llzo2 -lz"; \
			mv openvpn openvpn_tblk_$$a; \
			cd ../../../; \
		done; \
		$(MAKE) -C openvpn/$$openvpndir/openvpn/plugin/down-root; \
		lipo openvpn/$$openvpndir/openvpn/openvpn_tblk_* -create -output openvpn/$$openvpndir/openvpn/openvpn; \
	done
	
openvpn-clean:
	for openvpndir in `ls openvpn`; do \
		$(MAKE) -C openvpn/$$openvpndir/openvpn/ clean; \
		$(MAKE) -C openvpn/$$openvpndir/openvpn/plugin/down-root clean; \
		rm -f openvpn/$$openvpndir/openvpn/openvpn_tblk_*; \
		rm -f openvpn/$$openvpndir/openvpn/openvpn; \
		rm -f openvpn/$$openvpndir/openvpn/plugin/down-root/openvpn-down-root.so; \
	done

.PHONY : tuntap

tuntap-patch:
	cd $(TUNTAP_DIR); \
	for patchfile in ../patches/tuntap/*.diff; do \
		patch -p0 -N --dry-run -i $$patchfile > /dev/null; \
		if [ $$? == 0 ]; then \
			patch -p0 -N -i $$patchfile; \
		fi \
	done; \
	cd ../

tuntap: tuntap-patch
	# Now we'll build the tun/tap driver
	$(MAKE) -C $(TUNTAP_DIR)/; \
	mv $(TUNTAP_DIR)/tap.kext tap.kext; \
	mv $(TUNTAP_DIR)/tun.kext tun.kext

tuntap-clean:
	$(MAKE) -C $(TUNTAP_DIR)/ clean
	rm -f -R tap.kext
	rm -f -R tun.kext

clean: tuntap-clean lzo-clean pkcs11-helper-clean openvpn-clean
	rm -rf $(BUILD_DIR)
