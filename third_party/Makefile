# Makefile to build all of the third-party software included in Tunnelblick
#
# Copyright 2004, 2005, 2006, 2007, 2008, 2009 Angelo Laub
# Contributions by Jonathan K. Bullard Copyright 2010, 2011, 2012, 2013, 2014, 2015, 2016. All rights reserved.
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

ifeq "$(XCODE_VERSION_MAJOR)" "0300"
		$(error error: Tunnelblick must be built with Xcode 4 or higher)
endif


TARGET_ARCHS = x86_64
OPENSSL_TARGET_ARCHS = darwin64-x86_64-cc
CC = gcc

TOPDIR = $(PWD)

#######################################################################################
# Define names of folders in third_party/sources that contain programs to build:
# Names of OpenVPN folders are determined by examining third_party/sources/openvpn

LZO_NAME         = lzo-2.09

LZ4_NAME         = lz4-r131
LZ4_TARGET_ARCHS = x86_64

OPENSSL_NAME     = openssl-1.0.2j

PKCS11_NAME      = pkcs11-helper-1.11

EASY_RSA_3_NAME  = easy-rsa-3.0.0-rc2

TUNTAP_20111101_NAME  = tuntap-20111101
TUNTAP_CURRENT_NAME   = tuntap-20141104
TUNTAP_20111101_TARGZ = tuntap_20111101_src.tar.gz
TUNTAP_CURRENT_TARGZ  = tuntap_20141104_src.tar.gz

#######################################################################################
# Define treatment of deprecated functions, methods, etc. for OpenVPN

OPENVPN_DEPRECATED_LLVN_OPTION = -Wno-deprecated-declarations
OPENVPN_DEPRECATED_GCC_MAKE_OPTION = GCC_WARN_ABOUT_DEPRECATED_FUNCTIONS=NO

#######################################################################################
# Define other make variables:

SDKROOT=$(SDK_DIR)

CFLAGS=-isysroot $(SDKROOT) -Os -mmacosx-version-min=$(MACOSX_DEPLOYMENT_TARGET)

STAGING_DIR = $(TOPDIR)/build/staging

OPENSSL_BUILD_DIR = $(TOPDIR)/build/$(OPENSSL_NAME)
OPENSSL_STAGING_DIR = $(STAGING_DIR)/$(OPENSSL_NAME)
OPENSSL_TARGET_FILES = $(foreach f, libcrypto.a libssl.a, $(OPENSSL_STAGING_DIR)/lib/$(f))

LZO_BUILD_DIR = $(TOPDIR)/build/$(LZO_NAME)
LZO_STAGING_DIR = $(STAGING_DIR)/$(LZO_NAME)

LZ4_BUILD_DIR = $(TOPDIR)/build/$(LZ4_NAME)/lib
LZ4_STAGING_DIR = $(STAGING_DIR)/$(LZ4_NAME)

PKCS11_BUILD_DIR = $(TOPDIR)/build/$(PKCS11_NAME)
PKCS11_STAGING_DIR=$(STAGING_DIR)/$(PKCS11_NAME)

EASY_RSA_SOURCE_DIR = $(TOPDIR)/sources/easy-rsa
EASY_RSA_PRODUCTS_DIR = $(TOPDIR)/products/easy-rsa-tunnelblick

TUNTAP_SOURCE_DIR = $(TOPDIR)/sources/tuntap
TUNTAP_BUILD_DIR = $(TOPDIR)/build/tuntap
TUNTAP_PRODUCTS_DIR = $(TOPDIR)/products/tuntap

OPENVPN_SOURCE_DIR = $(TOPDIR)/sources/openvpn
OPENVPN_BUILD_DIR = $(TOPDIR)/build/openvpn
OPENVPN_PRODUCTS_DIR = $(TOPDIR)/products/openvpn

PATCHES_DIR = $(TOPDIR)/sources/patches

DOWN_ROOT_ARCH_2_2=$(foreach f, $(TARGET_ARCHS), -arch $f)

#######################################################################################
# Define the make rules:

all: built-easy-rsa-tunnelblick \
	built-tuntap               \
	built-openvpn              \
	built-sparkle
	@echo "THIRD_PARTY: Made all third_party for Tunnelblick" ; \

clean:
	rm -f -R $(TOPDIR)/build
	rm -f -R $(TOPDIR)/products
	rm -f    built-*
	@echo "THIRD_PARTY: Cleaned all third_party for Tunnelblick"

include makefiles/Makefile-*
