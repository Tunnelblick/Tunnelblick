#
# ip tunnel/ethertap driver for MacOSX
#
# Makefile
#
# (c) 2004 Mattias Nissler
#

OBJS = ../tuntap.o ../tuntap_mgr.o ../lock.o kmod.o tun_inet_proto.o tun_inet6_proto.o tun.o
KMOD_BIN = tun
BUNDLE_DIR = ../..
BUNDLE_NAME = tun.kext

TUN_KEXT_VERSION = 1.0

BUNDLE_REGION = English
BUNDLE_IDENTIFIER = foo.tun
BUNDLE_SIGNATURE = ????
BUNDLE_PACKAGETYPE = KEXT
BUNDLE_VERSION = $(TUN_KEXT_VERSION)

INCLUDE = -I.. \
	-I/System/Library/Frameworks/Kernel.framework/Headers \
	-I/System/Library/Frameworks/Kernel.framework/Headers/bsd
CFLAGS = -static -nostdinc -Wall -msoft-float -mlong-branch -force_cpusubtype_ALL -fno-builtin \
	-arch ppc -arch i386 -isysroot /Developer/SDKs/MacOSX10.4u.sdk/ \
	-DKERNEL -D__APPLE__ -DKERNEL_PRIVATE -DTUNTAP_VERSION=\"$(TUNTAP_VERSION)\" \
	-DTAP_KEXT_VERSION=\"$(TUN_KEXT_VERSION)\"
CCFLAGS = $(CFLAGS) -nostdinc++ -fapple-kext -fno-exceptions -fno-rtti
LDFLAGS = -static -Wall -nostdlib -r -lkmod -lkmodc++ -lcc_kext \
	-arch ppc -arch i386 -isysroot /Developer/SDKs/MacOSX10.4u.sdk/

CCP = g++
CC = gcc

all: $(KMOD_BIN) bundle

.c.o:
	$(CC) $(CFLAGS) $(INCLUDE) -c $< -o $@
.cc.o:
	$(CCP) $(CCFLAGS) $(INCLUDE) -c $< -o $@

$(KMOD_BIN):	$(OBJS)
	$(CCP) $(LDFLAGS) -o $(KMOD_BIN) $(OBJS)

bundle:	$(KMOD_BIN)
	rm -rf $(BUNDLE_DIR)/$(BUNDLE_NAME)
	mkdir -p $(BUNDLE_DIR)/$(BUNDLE_NAME)/Contents/MacOS
	cp $(KMOD_BIN) $(BUNDLE_DIR)/$(BUNDLE_NAME)/Contents/MacOS
	sed -e "s/@@CFBUNDLEEXECUTABLE@@/$(KMOD_BIN)/" \
	 -e "s/@@CFBUNDLEDEVELOPMENTREGION@@/$(BUNDLE_REGION)/" \
	 -e "s/@@CFBUNDLEIDENTIFIER@@/$(BUNDLE_IDENTIFIER)/" \
	 -e "s/@@CFBUNDLESIGNATURE@@/$(BUNDLE_SIGNATURE)/" \
	 -e "s/@@CFBUNDLEPACKAGETYPE@@/$(BUNDLE_PACKAGETYPE)/" \
	 -e "s/@@CFBUNDLEVERSION@@/$(BUNDLE_VERSION)/" \
	Info.plist > $(BUNDLE_DIR)/$(BUNDLE_NAME)/Contents/Info.plist

clean:
	-rm -f $(OBJS) $(KMOD_BIN)
	-rm -rf $(BUNDLE_DIR)/$(BUNDLE_NAME)

