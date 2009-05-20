# pkcs11-helper-1.m4 - Macros to locate and utilise pkcs11-helper.     -*- Autoconf -*-
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

# PKCS11_HELPER_CHECK_FEATURES([features])
#
# Check whether features exists in pkcs11-helper.
#
# debug threading token data certificate locate slotevent openssl standalone engine_crypto
#
AC_DEFUN([PKCS11_HELPER_1_CHECK_FEATURES], [
	AC_REQUIRE([PKG_PROG_PKG_CONFIG])
	AC_ARG_VAR([PKCS11_HELPER_FEATURES], [pkcs11-helperer feartures overriding pkg-config])
	AC_MSG_CHECKING([pkcs11-helper features])
	_PKG_CONFIG([PKCS11_HELPER_FEATURES], [variable features], [libpkcs11-helper-1])
	for pkcs11h_feature in $1; do
		echo " ${pkg_cv_PKCS11_HELPER_FEATURES} " | grep " ${pkcs11h_feature} " > /dev/null 2>&1 || \
			AC_MSG_ERROR([pkcs11-helper ${pkcs11h_feature} feature must be enabled.])
	done
	AC_MSG_RESULT([ok])
])
