# This Makefile builds all the third_party code
# It shouldn't be called by anything other than automated scripts
#
# Modified 2013-04-08 by Harold Molina-Bulla to support post-OpenVPN 2.3alpha1 versions of OpenVPN
# Modified 2013-04-17 by Harold Molina-Bulla to support separate architectures for OpenVPN versions higher
#                        than 2.3alpha1, and to build ppc, i386, and x86_64 architectures for them.
#                        2.3alpha1 and lower continue to be built only for ppc and i386 because
#                        64-bit 2.2.1 builds have problems with certain OpenVPN setups.
# Modified 2014-06-30 by Harold Molina-Bulla to identify correctly the machine hardware name in 
#                        openvpn --version option. Also modified LZO and pkcs-helper machine identifier.
#

CC=gcc-4.0
MACOSX_DEPLOYMENT_TARGET=10.4
SDKROOT=/Developer/SDKs/MacOSX10.6.sdk
TARGET_ARCHS=ppc i386 x86_64
TARGET_ARCHS_2_2=ppc i386

CFLAGS=-isysroot $(SDKROOT) -Os -mmacosx-version-min=$(MACOSX_DEPLOYMENT_TARGET)

TOPDIR = $(PWD)
BUILD_DIR = build
THIRD_PARTY_PROJS = OPENSSL

OPENSSL_SRC_DIR = openssl-1.0.1k
OPENSSL_BUILD_DIR = $(TOPDIR)/$(BUILD_DIR)/$(OPENSSL_SRC_DIR)
OPENSSL_DEST_DIR = $(TOPDIR)/$(BUILD_DIR)/staging/$(OPENSSL_SRC_DIR)
OPENSSL_TARGET_FILES = $(foreach f, libcrypto.a libssl.a, $(OPENSSL_DEST_DIR)/lib/$(f))
OPENSSL_TARGET_ARCHS=darwin-ppc-cc darwin-i386-cc darwin64-x86_64-cc

DOWN_ROOT_ARCH_2_2=$(foreach f, $(TARGET_ARCHS_2_2), -arch $f)

SPARKLE_DIR = sparkle-1.5b6

LZO_DIR=$(TOPDIR)/lzo-2.08
PKCS11_DIR=pkcs11-helper-1.11
PKCS11_TUNNELBLICK_STAGING_DIR=$(TOPDIR)/$(PKCS11_DIR)/staging
TUNTAP_20090913_DIR=tuntap-20090913
TUNTAP_CURRENT_DIR=tuntap-20111101

all: built-tuntap built-sparkle built-openvpn
	@echo "Made all third_party for Tunnelblick"

clean: built-tuntap-clean built-sparkle-clean built-lzo-clean built-pkcs11-helper-clean built-openvpn-clean
	rm -rf $(BUILD_DIR)

built-openssl-patch:
	mkdir -p $(OPENSSL_BUILD_DIR)
	cd $(OPENSSL_BUILD_DIR); \
	/usr/X11/bin/lndir $(TOPDIR)/$$(basename $(OPENSSL_BUILD_DIR)); \
	if [ -d "$(TOPDIR)/patches/openssl" ]; then \
		for patchfile in $(TOPDIR)/patches/openssl/*.diff; do \
			patch -p0 -N --dry-run -i $$patchfile > /dev/null; \
			if [ $$? == 0 ]; then \
				patch -p0 -N -i $$patchfile; \
			fi \
		done \
	fi; \
	cd $(TOPDIR);
	touch built-openssl-patch

built-openssl: built-openssl-patch
	for a in $(OPENSSL_TARGET_ARCHS); do\
		@echo Configure OpenSSL for $$a; \
		cd $(OPENSSL_BUILD_DIR); \
		@echo Forcefully be clean; \
		$(MAKE) clean; \
		CC=$(CC) CFLAGS="$(CFLAGS)" ./Configure no-shared zlib no-zlib-dynamic no-asm no-krb5 --prefix="$(OPENSSL_DEST_DIR)/$$a" $$a; \
		@echo Build OpenSSL for $$a; \
		$(MAKE) build_libs build_apps openssl.pc libssl.pc libcrypto.pc; \
		@echo Install to $(OPENSSL_DEST_DIR)/$$a; \
		$(MAKE) install_sw; \
		cd -; \
	done
	ditto -v $(BUILD_DIR)/staging/$(OPENSSL_SRC_DIR)/darwin64-x86_64-cc/include $(OPENSSL_DEST_DIR)/include/x86_64
	ditto -v $(BUILD_DIR)/staging/$(OPENSSL_SRC_DIR)/darwin-i386-cc/include $(OPENSSL_DEST_DIR)/include/i386
	ditto -v $(BUILD_DIR)/staging/$(OPENSSL_SRC_DIR)/darwin-ppc-cc/include $(OPENSSL_DEST_DIR)/include/ppc
	mkdir -p $(OPENSSL_DEST_DIR)/lib
	for t in $(OPENSSL_TARGET_FILES); do \
		lipo $(BUILD_DIR)/staging/$(OPENSSL_SRC_DIR)/darwin*/lib/$$(basename $$t) -create -output $$t; \
		ranlib $$t; \
	done
	rm -rf $(BUILD_DIR)/staging/$(OPENSSL_SRC_DIR)/darwin*
	touch built-openssl
	
built-pkcs11-helper: built-openssl
	for a in $(TARGET_ARCHS); do \
		@echo Configure PKCS11-Helper for $$a; \
		cd $(PKCS11_DIR); \
		@echo Forcefully be clean; \
		$(MAKE) clean; \
		OPENSSL_CFLAGS="-I$(OPENSSL_DEST_DIR)/include/$$a" OPENSSL_LIBS="-L$(OPENSSL_DEST_DIR)/lib -lssl -lcrypto -lz" CC=$(CC) CFLAGS="$(CFLAGS) -arch $$a" ./configure --build=$$a-apple-darwin --enable-static --enable-shared=no --disable-dependency-tracking --prefix=$$(pwd)/staging_$$a --includedir=$$(pwd)/staging/include; \
		@echo Build PKCS11-Helper; \
		$(MAKE); \
		@echo Install to $(PKCS11_TUNNELBLICK_STAGING_DIR)_$$a; \
		$(MAKE) install; \
		cd ../; \
	done
	rm -r -f $(PKCS11_TUNNELBLICK_STAGING_DIR)/lib
	mkdir -p $(PKCS11_TUNNELBLICK_STAGING_DIR)/lib
	lipo $(PKCS11_TUNNELBLICK_STAGING_DIR)_*/lib/libpkcs11-helper.a -create -output $(PKCS11_TUNNELBLICK_STAGING_DIR)/lib/libpkcs11-helper.a
	ranlib $(PKCS11_TUNNELBLICK_STAGING_DIR)/lib/libpkcs11-helper.a
	touch built-pkcs11-helper

built-pkcs11-helper-clean:
	$(MAKE) -C $(PKCS11_DIR) clean
	rm -rf $(PKCS11_TUNNELBLICK_STAGING_DIR)*
	rm -f built-pkcs11-helper

built-lzo:
	for a in $(TARGET_ARCHS); do \
		@echo Configure LZO for $$a; \
		cd $(LZO_DIR); \
		@echo Forcefully be clean; \
		$(MAKE) clean; \
		CC=$(CC) CFLAGS="$(CFLAGS) -arch $$a" ./configure --build=$$a-apple-darwin --disable-dependency-tracking --disable-asm --prefix=$$(pwd)/staging_$$a/ --includedir=$$(pwd)/staging/include/; \
		@echo Build LZO; \
		$(MAKE); \
		@echo Install to $(LZO_DIR)/staging_$$a; \
		$(MAKE) install; \
		cd ../; \
	done
	
	# Use lipo to create a universal library
	mkdir -p $(LZO_DIR)/staging/lib
	lipo $(LZO_DIR)/staging_*/lib/liblzo2.a -create -output $(LZO_DIR)/staging/lib/liblzo2.a
	ranlib $(LZO_DIR)/staging/lib/liblzo2.a
	touch built-lzo
	
built-lzo-clean:
	$(MAKE) -C $(LZO_DIR) clean
	rm -rf $(LZO_DIR)/staging*
	rm -f built-lzo
	
built-openvpn-patch:
	for openvpndir in `ls openvpn`; do \
		cd openvpn/$$openvpndir/openvpn; \
		if [ -d ../patches ]; then \
			for patchfile in `ls ../patches/*.diff`; do \
				patch -p1 -N --dry-run -i $$patchfile > /dev/null; \
				if [ $$? == 0 ]; then \
					patch -p1 -N -i $$patchfile; \
					if [ $$? == 0 ]; then \
					    touch "$${patchfile}.patch-applied" ; \
						echo "OpenVPN patch applied: $$openvpndir/openvpn/$${patchfile}" ; \
					else \
						echo "error: OpenVPN patch failed: $$openvpndir/openvpn/$${patchfile}" ; \
					fi \
				else \
					if [ -e "$${patchfile}.patch-applied" ] ; then \
						echo "warning: OpenVPN patch skipped; it has apparently already been applied: $$openvpndir/openvpn/$${patchfile}" ; \
					else \
						echo "error: OpenVPN patch has not been applied previously and could not be applied now: $$openvpndir/openvpn/$${patchfile}" ; \
					fi \
				fi \
			done; \
		else \
			echo "No OpenVPN patches for $$openvpndir" ; \
		fi; \
		cd ../../../; \
	done
	touch built-openvpn-patch
	
built-openvpn: built-openvpn-patch built-lzo built-pkcs11-helper built-openssl
	for openvpndir in `ls openvpn`; do \
		cd openvpn/$$openvpndir/openvpn; \
		if [ -d src ]; then \
			echo "Making $$openvpndir from post-2.3-alpha1 build system"; \
			for a in $(TARGET_ARCHS); do \
				$(MAKE) clean; \
				autoreconf -i -v; \
				CC="$(CC)" CFLAGS="$(CFLAGS) -arch $$a" LZO_CFLAGS="-I$(LZO_DIR)/staging/include" LZO_LIBS="-L$(LZO_DIR)/staging/lib -llzo2" OPENSSL_SSL_CFLAGS="-I$(OPENSSL_DEST_DIR)/include/$$a" OPENSSL_SSL_LIBS="$(OPENSSL_DEST_DIR)/lib/libssl.a" OPENSSL_CRYPTO_CFLAGS="-I$(OPENSSL_DEST_DIR)/include/$$a" OPENSSL_CRYPTO_LIBS="$(OPENSSL_DEST_DIR)/lib/libcrypto.a -lz" PKCS11_HELPER_CFLAGS="-I$(PKCS11_TUNNELBLICK_STAGING_DIR)/include/"  PKCS11_HELPER_LIBS="-L$(PKCS11_TUNNELBLICK_STAGING_DIR)/lib -lpkcs11-helper" OS_VERSION=`uname -r` ./configure --build=$$a-apple-darwin --enable-static=yes --enable-shared --enable-pkcs11 --disable-debug --disable-plugin-auth-pam --disable-dependency-tracking --enable-crypto --enable-ssl ; \
				echo "Compiling openvpn"; \
				$(MAKE) LIBS="$(OPENSSL_TARGET_FILES) -L$(PKCS11_TUNNELBLICK_STAGING_DIR)/lib -lpkcs11-helper -L$(LZO_DIR)/staging/lib -llzo2"; \
				echo "Fixing down-root plugin" ; \
				$(MAKE) -C src/plugins/down-root clean ; \
				$(MAKE) LDFLAGS="-bundle -Wl,-dylib_install_name,openvpn-down-root.so" -C src/plugins/down-root ; \
	 			mv src/openvpn/openvpn ../openvpn_tblk_$$a; \
                mv src/plugins/down-root/.libs/openvpn-plugin-down-root.so ../openvpn-plugin-down-root.so_tblk_$$a; \
	 		done; \
			lipo ../openvpn-plugin-down-root.so_tblk_* -create -output ../openvpn-down-root.so; \
			rm ../openvpn-plugin-down-root.so_tblk_* ; \
		else \
			echo "Making $$openvpndir from pre-2.3-alpha2 build system"; \
			for a in $(TARGET_ARCHS_2_2); do \
				$(MAKE) clean; \
				autoreconf -i -v; \
				CC=$(CC) CFLAGS="$(CFLAGS) -arch $$a" OS_VERSION=`uname -r` ./configure --build=$$a-apple-darwin --with-lzo-headers=$(LZO_DIR)/staging/include --with-lzo-lib=$(LZO_DIR)/staging/lib --with-pkcs11-helper-headers=$(PKCS11_TUNNELBLICK_STAGING_DIR)/include --with-pkcs11-helper-lib=$(PKCS11_TUNNELBLICK_STAGING_DIR)/lib --with-ssl-headers=$(OPENSSL_DEST_DIR)/include/$$a --with-ssl-lib=$(OPENSSL_DEST_DIR)/lib --disable-dependency-tracking; \
				$(MAKE) LIBS="$(OPENSSL_TARGET_FILES) -lpkcs11-helper -llzo2 -lz"; \
				mv openvpn ../openvpn_tblk_$$a; \
			done; \
			$(MAKE) CC_FLAGS="-Wall -isysroot $(SDKROOT) -Os -mmacosx-version-min=$(MACOSX_DEPLOYMENT_TARGET) $(DOWN_ROOT_ARCH_2_2)" -C plugin/down-root; \
			mv plugin/down-root/openvpn-down-root.so ../openvpn-down-root.so; \
		fi; \
		cd ../; \
		lipo openvpn_tblk_* -create -output openvpn-executable; \
		rm openvpn_tblk_* ; \
		cd ../../; \
	done
	touch built-openvpn

built-openvpn-clean:
	for openvpndir in `ls openvpn`; do \
		$(MAKE) -C openvpn/$$openvpndir/openvpn/ clean; \
		$(MAKE) -C openvpn/$$openvpndir/openvpn/plugin/down-root clean; \
		rm -f openvpn/$$openvpndir/openvpn_tblk_*; \
		rm -f openvpn/$$openvpndir/openvpn-executable; \
		rm -f openvpn/$$openvpndir/openvpn-down-root.so; \
	done
	rm -f built-openvpn

built-tuntap-patch:
	for tuntapdir in `ls tuntap`; do \
		cd tuntap/$$tuntapdir/tuntap; \
		for patchfile in ../patches/*.diff; do \
			patch -p0 -N --dry-run -i $$patchfile > /dev/null; \
			if [ $$? == 0 ]; then \
				patch -p0 -N -i $$patchfile; \
			fi \
		done; \
		cd ../../../; \
	done
	touch built-tuntap-patch

built-tuntap: built-tuntap-patch
	$(MAKE) -C tuntap/$(TUNTAP_20090913_DIR)/tuntap/; \
	mv tuntap/$(TUNTAP_20090913_DIR)/tuntap/tap.kext tap-20090913.kext; \
	mv tuntap/$(TUNTAP_20090913_DIR)/tuntap/tun.kext tun-20090913.kext; \
	$(MAKE) -C tuntap/$(TUNTAP_CURRENT_DIR)/tuntap/; \
	mv tuntap/$(TUNTAP_CURRENT_DIR)/tuntap/tap.kext tap.kext; \
	mv tuntap/$(TUNTAP_CURRENT_DIR)/tuntap/tun.kext tun.kext
	touch built-tuntap

built-tuntap-clean:
	$(MAKE) -C tuntap/$(TUNTAP_20090913_DIR)/tuntap/ clean; \
	rm -f -R tap-20090913.kext; \
	rm -f -R tun-20090913.kext; \
	$(MAKE) -C tuntap/$(TUNTAP_CURRENT_DIR)/tuntap/ clean; \
	rm -f -R tap.kext; \
	rm -f -R tun.kext
	rm -f built-tuntap

built-sparkle-patch:
	cd "$(SPARKLE_DIR)"; \
	if [ -d ../patches/sparkle ]; then \
		for patchfile in `ls ../patches/sparkle/*.diff`; do \
			patch -p1 -N --dry-run -i $$patchfile > /dev/null; \
			if [ $$? == 0 ]; then \
				patch -p1 -N -i $$patchfile; \
				if [ $$? == 0 ]; then \
				    touch "$${patchfile}.patch-applied" ; \
					echo "Sparkle patch applied: $(SPARKLE_DIR)/$${patchfile}" ; \
				else \
					echo "error: Sparkle patch failed: $(SPARKLE_DIR)/$${patchfile}" ; \
				fi \
			else \
				if [ -e "$${patchfile}.patch-applied" ] ; then \
					echo "warning: Sparkle patch skipped; it has apparently already been applied: $(SPARKLE_DIR)/$${patchfile}" ; \
				else \
					echo "error: Sparkle patch has not been applied previously and could not be applied now: $(SPARKLE_DIR)/$${patchfile}" ; \
				fi \
			fi \
		done; \
	else \
		echo "No Sparkle patches" ; \
	fi; \
	cd ../
	touch built-sparkle-patch

built-sparkle: built-sparkle-patch
	cd "$(SPARKLE_DIR)/Extras/Source Code"; \
	xcodebuild -project Sparkle.xcodeproj -target Sparkle -configuration Release clean; \
	xcodebuild -project Sparkle.xcodeproj -target Sparkle -configuration Release build; \
	cd ../../../
	rm -f -r "Sparkle.framework"
	cp -X -f -R "$(SPARKLE_DIR)/Extras/Source Code/build/Release/Sparkle.framework" "Sparkle.framework"
	touch built-sparkle
	
built-sparkle-clean:
	rm -f -r "Sparkle.framework"
	cd "$(SPARKLE_DIR)/Extras/Source Code"; \
	xcodebuild -project Sparkle.xcodeproj -target Sparkle -configuration Release clean; \
	cd ../../../
	rm -f built-sparkle
