#
# Copyright (c) 2005-2008 Alon Bar-Lev <alon.barlev@gmail.com>
# All rights reserved.
#
# This software is available to you under a choice of one of two
# licenses.  You may choose to be licensed under the terms of the GNU
# General Public License (GPL) Version 2, or the BSD license.
#
# GNU General Public License (GPL) Version 2
# ===========================================
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 2
# as published by the Free Software Foundation.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program (see the file COPYING.GPL included with this
# distribution); if not, write to the Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
#
# BSD License
# ============
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#
#     o Redistributions of source code must retain the above copyright notice,
#       this list of conditions and the following disclaimer.
#     o Redistributions in binary form must reproduce the above copyright
#       notice, this list of conditions and the following disclaimer in the
#       documentation and/or other materials provided with the distribution.
#     o Neither the name of the <ORGANIZATION> nor the names of its
#       contributors may be used to endorse or promote products derived from
#       this software without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
# LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
# CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
# SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
# INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
# CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
# ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
# POSSIBILITY OF SUCH DAMAGE.
#

MAINTAINERCLEANFILES=\
	$(srcdir)/Makefile.in
	$(srcdir)/versioninfo.rc
CLEANFILES=pkcs11-helper.exports

dist_noinst_DATA= \
	Makefile.w32-vc \
	certificate.exports \
	core.exports \
	data.exports \
	openssl.exports \
	slotevent.exports \
	token.exports

BUILT_SOURCES=pkcs11-helper.exports
pkgconfig_DATA=libpkcs11-helper-1.pc
lib_LTLIBRARIES=libpkcs11-helper.la

INCLUDES= \
	-I$(top_srcdir)/include \
	-I$(top_builddir)/include

nodist_libpkcs11_helper_la_SOURCES= \
	pkcs11-helper.exports
libpkcs11_helper_la_SOURCES= \
	common.h \
	_pkcs11h-mem.h pkcs11h-mem.c \
	_pkcs11h-sys.h pkcs11h-sys.c \
	_pkcs11h-crypto.h pkcs11h-crypto.c \
	_pkcs11h-threading.h pkcs11h-threading.c \
	_pkcs11h-util.h pkcs11h-util.c \
	_pkcs11h-session.h pkcs11h-session.c \
	_pkcs11h-token.h pkcs11h-token.c \
	_pkcs11h-certificate.h pkcs11h-certificate.c \
	_pkcs11h-slotevent.h pkcs11h-slotevent.c \
	_pkcs11h-core.h pkcs11h-core.c \
	pkcs11h-data.c \
	pkcs11h-serialization.c \
	pkcs11h-openssl.c
libpkcs11_helper_la_LDFLAGS= \
	$(AM_LDFLAGS) \
	-version-info @LIBPKCS11_HELPER_LT_CURRENT@:@LIBPKCS11_HELPER_LT_REVISION@:@LIBPKCS11_HELPER_LT_AGE@ \
	-export-symbols "pkcs11-helper.exports" \
	-no-undefined
if WIN32
libpkcs11_helper_la_SOURCES+=versioninfo.rc
else
dist_noinst_DATA+=versioninfo.rc
endif

pkcs11-helper.exports: \
		$(top_builddir)/config.h \
		$(srcdir)/certificate.exports \
		$(srcdir)/core.exports \
		$(srcdir)/data.exports \
		$(srcdir)/openssl.exports \
		$(srcdir)/slotevent.exports \
		$(srcdir)/token.exports
	cat "$(srcdir)/core.exports" > pkcs11-helper.exports
if ENABLE_PKCS11H_CERTIFICATE
	cat "$(srcdir)/certificate.exports" >> pkcs11-helper.exports
endif
if ENABLE_PKCS11H_DATA
	cat "$(srcdir)/data.exports" >> pkcs11-helper.exports
endif
if ENABLE_PKCS11H_OPENSSL
	cat "$(srcdir)/openssl.exports" >> pkcs11-helper.exports
endif
if ENABLE_PKCS11H_SLOTEVENT
	cat "$(srcdir)/slotevent.exports" >> pkcs11-helper.exports
endif
if ENABLE_PKCS11H_TOKEN
	cat "$(srcdir)/token.exports" >> pkcs11-helper.exports
endif

if WIN32
mylibdir=$(libdir)
mylib_DATA=.libs/@WIN_LIBPREFIX@pkcs11-helper-@LIBPKCS11_HELPER_LT_OLDEST@.dll.def
.libs/@WIN_LIBPREFIX@pkcs11-helper-@LIBPKCS11_HELPER_LT_OLDEST@.dll.def:	libpkcs11-helper.la
endif

RCCOMPILE = $(RC) $(DEFS) $(DEFAULT_INCLUDES) $(INCLUDES) \
	$(AM_CPPFLAGS) $(CPPFLAGS)
LTRCCOMPILE = $(LIBTOOL) --mode=compile --tag=RC $(RCCOMPILE)

.rc.lo:
	$(LTRCCOMPILE) -i "$<" -o "$@"

.rc.o:
	$(RCCOMPILE) -i "$<" -o "$@"
