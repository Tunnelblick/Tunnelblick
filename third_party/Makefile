# Makefile to build all of the third-party software included in Tunnelblick
#
# Copyright 2004, 2005, 2006, 2007, 2008, 2009 Angelo Laub
# Contributions by Jonathan K. Bullard Copyright 2010, 2011, 2012, 2013, 2014, 2015, 2016, 2018, 2020, 2021, 2022. All rights reserved.
#
#  This file is part of Tunnelblick.
#
#  Tunnelblick is free software: you can redistribute it and/or modify
#  it under the terms of the GNU General Public License version 2
#  as published by the Free Software Foundation.
#
#  Tunnelblick is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  You should have received a copy of the GNU General Public License
#  along with this program (see the file COPYING included with this
#  distribution); if not, write to the Free Software Foundation, Inc.,

#######################################################################################
# Define names of folders in third_party/sources that contain programs to build:
# Names of OpenVPN folders are determined by examining third_party/sources/openvpn
#
# IMPORTANT: When an program version changes, change the name of any corresponding folder in patches

LZO_NAME         = lzo-2.10

LZ4_NAME         = lz4-1.9.3

SPARKLE_NAME     = Sparkle-077c64419f9460263bad99ab24dff962a103b1e2

OPENSSL_1_1_NAME = openssl-1.1.1w
OPENSSL_3_0_NAME = openssl-3.0.12

PKCS11_NAME      = pkcs11-helper-1.27.0

EASY_RSA_3_NAME  = easy-rsa-3.0.1

TUNTAP_CURRENT_NAME   = tuntap-20141104
TUNTAP_CURRENT_TARGZ  = tuntap_20141104_src.tar.gz



#######################################################################################
#######################################################################################
#######################################################################################
###                                                                                 ###
### THE REST OF THIS SCRIPT NEEDS TO BE CHANGED ONLY RARELY                         ###
###                                                                                 ###
### (For example, when a new major.minor version of OpenVPN or OpenSSL is added.)   ###
###                                                                                 ###
#######################################################################################
#######################################################################################
#######################################################################################

#######################################################################################
# Target architectures. Use a space-separated list of architectures.
#
#	For Intel,         use "x86_64" for all
#						   EXCEPT OpenSSL, which must use "darwin64-x86_64-cc"
#
#	For Apple Silicon, use "arm64" for all
#						   EXCEPT OpenSSL, which must use "darwin64-arm64-cc"
#						   and    Tuntap, which must use arm64e.

TB_COMMON_X86_ARCH  = x86_64
TB_COMMON_ARM_ARCH  = arm64

TB_OPENSSL_X86_ARCH = darwin64-x86_64-cc
TB_OPENSSL_ARM_ARCH = darwin64-arm64-cc

TB_TUNTAP_ARM_ARCH = arm64e

ifeq ($(TB_CAN_BUILD_ARM),0)

    # Build with an Xcode which cannot build for Apple Silicon (ARM architecture)

    LZ4_TARGET_ARCHS         = $(TB_COMMON_X86_ARCH)
    LZO_TARGET_ARCHS         = $(TB_COMMON_X86_ARCH)
    PKCS11_TARGET_ARCHS      = $(TB_COMMON_X86_ARCH)
    SPARKLE_TARGET_ARCHS     = $(TB_COMMON_X86_ARCH)
    TUNTAP_TARGET_ARCHS      = $(TB_COMMON_X86_ARCH)

    # Used to build OpenSSL:
    OPENSSL_1_1_TARGET_ARCHS = $(TB_COMMON_X86_ARCH)
    OPENSSL_3_0_TARGET_ARCHS = $(TB_COMMON_X86_ARCH)

    # Used to build OpenVPN
    OPENVPN_OPENSSL_1_1_TARGET_ARCHS = $(TB_COMMON_X86_ARCH)
    OPENVPN_OPENSSL_3_0_TARGET_ARCHS = $(TB_COMMON_X86_ARCH)

else

    # Build with an Xcode which can build for Apple Silicon (ARM architecture)

    LZ4_TARGET_ARCHS         = $(TB_COMMON_X86_ARCH) $(TB_COMMON_ARM_ARCH)
    LZO_TARGET_ARCHS         = $(TB_COMMON_X86_ARCH) $(TB_COMMON_ARM_ARCH)
    PKCS11_TARGET_ARCHS      = $(TB_COMMON_X86_ARCH) $(TB_COMMON_ARM_ARCH)
    SPARKLE_TARGET_ARCHS     = $(TB_COMMON_X86_ARCH) $(TB_COMMON_ARM_ARCH)
    TUNTAP_TARGET_ARCHS      = $(TB_COMMON_X86_ARCH) $(TB_TUNTAP_ARM_ARCH)
    OPENSSL_1_1_TARGET_ARCHS = $(TB_COMMON_X86_ARCH) $(TB_COMMON_ARM_ARCH)
    OPENSSL_3_0_TARGET_ARCHS = $(TB_COMMON_X86_ARCH) $(TB_COMMON_ARM_ARCH)

    # Used to build OpenVPN
    OPENVPN_OPENSSL_1_1_TARGET_ARCHS = $(TB_COMMON_X86_ARCH) $(TB_COMMON_ARM_ARCH)
    OPENVPN_OPENSSL_3_0_TARGET_ARCHS = $(TB_COMMON_X86_ARCH) $(TB_COMMON_ARM_ARCH)

endif

#######################################################################################
# For use in Makefile-openvpn
# Define tests (inside bash [ ]) which determine which SSL libraries to link to for each major.minor version of OpenVPN
# Each test compares a bash variable ($$ssl_name) with one or more make variables ( e.g., $(OPENSSL_1_1_NAME) )

OPENVPN_2_4_SSL_LIBRARIES_TEST = $$ssl_name = $(OPENSSL_1_1_NAME)
OPENVPN_2_5_SSL_LIBRARIES_TEST = $$ssl_name = $(OPENSSL_1_1_NAME)
OPENVPN_2_6_SSL_LIBRARIES_TEST = $$ssl_name = $(OPENSSL_1_1_NAME) -o $$ssl_name = $(OPENSSL_3_0_NAME)

#######################################################################################
# Define treatment of deprecated functions, methods, etc. for OpenVPN

OPENVPN_DEPRECATED_LLVN_OPTION = -Wno-deprecated-declarations
OPENVPN_DEPRECATED_GCC_MAKE_OPTION = GCC_WARN_ABOUT_DEPRECATED_FUNCTIONS=NO

#######################################################################################
# Define other make variables:

CC = gcc

TOPDIR = $(PWD)

SDKROOT=$(SDK_DIR)

CFLAGS=-isysroot $(SDKROOT) -Os -mmacosx-version-min=$(MACOSX_DEPLOYMENT_TARGET)

SOURCES_DIR = $(TOPDIR)/sources
BUILD_DIR = $(TOPDIR)/build
PRODUCTS_DIR = $(TOPDIR)/products

STAGING_DIR = $(BUILD_DIR)/staging

OPENSSL_1_1_STAGING_DIR = $(STAGING_DIR)/$(OPENSSL_1_1_NAME)

OPENSSL_3_0_STAGING_DIR = $(STAGING_DIR)/$(OPENSSL_3_0_NAME)

LZO_BUILD_DIR = $(BUILD_DIR)/$(LZO_NAME)
LZO_STAGING_DIR = $(STAGING_DIR)/$(LZO_NAME)

LZ4_BUILD_DIR = $(BUILD_DIR)/$(LZ4_NAME)/lib
LZ4_STAGING_DIR = $(STAGING_DIR)/$(LZ4_NAME)

PKCS11_BUILD_DIR = $(BUILD_DIR)/$(PKCS11_NAME)
PKCS11_STAGING_DIR=$(STAGING_DIR)/$(PKCS11_NAME)

EASY_RSA_SOURCE_DIR = $(SOURCES_DIR)/easy-rsa
EASY_RSA_PRODUCTS_DIR = $(PRODUCTS_DIR)/easy-rsa-tunnelblick

TUNTAP_SOURCE_DIR = $(SOURCES_DIR)/tuntap
TUNTAP_BUILD_DIR = $(BUILD_DIR)/tuntap
TUNTAP_PRODUCTS_DIR = $(PRODUCTS_DIR)/tuntap
TUNTAP_ARCH_ARGS = "$(foreach f, $(TUNTAP_TARGET_ARCHS), -arch $f)"

# If both of the following files exist
# then
#      We will NOT build tun or tap kexts.
#      Instead, makefile-tuntap will copy these two files into third_party/products/tuntap.
#      They will be copied from there into Tunnelblick.app/Contents/Resources by
#          the "BuildAppsAndDmgs.sh" script.
# else
#      makefile-tuntap will build tun and tap kexts and put them into third_party/products/tuntap.
#      They will be copied from there into Tunnelblick.app/Contents/Resources by
#          the "BuildAppsAndDmgs.sh" script.
TUNTAP_PREBUILT_TAP_NOTARIZED = $(TOPDIR)/tap-notarized.kext
TUNTAP_PREBUILT_TUN_NOTARIZED = $(TOPDIR)/tun-notarized.kext

OPENVPN_SOURCE_DIR = $(SOURCES_DIR)/openvpn
OPENVPN_BUILD_DIR = $(BUILD_DIR)/openvpn
OPENVPN_PRODUCTS_DIR = $(PRODUCTS_DIR)/openvpn

PATCHES_DIR = $(SOURCES_DIR)/patches

DOWN_ROOT_ARCH_2_2=$(foreach f, $(TARGET_ARCHS), -arch $f)

#######################################################################################
# Define the make rules:

all: 	built-sparkle \
	built-easy-rsa-tunnelblick \
	built-tuntap               \
	built-openvpn
	@echo "THIRD_PARTY: Made all third_party for Tunnelblick" ; \

clean:
	rm -f -R $(BUILD_DIR)
	rm -f -R $(PRODUCTS_DIR)
	rm -f    built-*
	rm -f    do-not-clean
	@echo "THIRD_PARTY: Cleaned all third_party for Tunnelblick"

include makefiles/Makefile-*
