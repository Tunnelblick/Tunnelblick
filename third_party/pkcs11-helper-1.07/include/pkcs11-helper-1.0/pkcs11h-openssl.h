/*
 * Copyright (c) 2005-2008 Alon Bar-Lev <alon.barlev@gmail.com>
 * All rights reserved.
 *
 * This software is available to you under a choice of one of two
 * licenses.  You may choose to be licensed under the terms of the GNU
 * General Public License (GPL) Version 2, or the BSD license.
 *
 * GNU General Public License (GPL) Version 2
 * ===========================================
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License version 2
 * as published by the Free Software Foundation.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program (see the file COPYING.GPL included with this
 * distribution); if not, write to the Free Software Foundation, Inc.,
 * 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
 *
 * BSD License
 * ============
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *
 *     o Redistributions of source code must retain the above copyright notice,
 *       this list of conditions and the following disclaimer.
 *     o Redistributions in binary form must reproduce the above copyright
 *       notice, this list of conditions and the following disclaimer in the
 *       documentation and/or other materials provided with the distribution.
 *     o Neither the name of the <ORGANIZATION> nor the names of its
 *       contributors may be used to endorse or promote products derived from
 *       this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
 * AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
 * LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
 * CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 * SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 * INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
 * CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 * ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
 * POSSIBILITY OF SUCH DAMAGE.
 */

/**
 * @addtogroup pkcs11h_openssl OpenSSL interface
 *
 * OpenSSL engine to be used by OpenSSL enabled applications.
 *
 * @{
 */

/**
 * @file pkcs11h-openssl.h
 * @brief pkcs11-helper OpenSSL interface.
 * @author Alon Bar-Lev <alon.barlev@gmail.com>
 * @see pkcs11h_openssl.
 */

#ifndef __PKCS11H_HELPER_H
#define __PKCS11H_HELPER_H

#include <openssl/x509.h>
#include <pkcs11-helper-1.0/pkcs11h-core.h>
#include <pkcs11-helper-1.0/pkcs11h-certificate.h>

#if defined(__cplusplus)
extern "C" {
#endif

/**
 * @brief OpenSSL RSA cleanup hook.
 * @param certificate	Certificate attached to the RSA object.
 */
typedef void (*pkcs11h_hook_openssl_cleanup_t) (
	IN const pkcs11h_certificate_t certificate
);

struct pkcs11h_openssl_session_s;

/**
 * @brief OpenSSL session reference.
 */
typedef struct pkcs11h_openssl_session_s *pkcs11h_openssl_session_t;

/**
 * @brief Returns an X509 object out of the openssl_session object.
 * @param certificate	Certificate object.
 * @return X509.
 */
X509 *
pkcs11h_openssl_getX509 (
	IN const pkcs11h_certificate_t certificate
);

/**
 * @brief Create OpenSSL session based on a certificate object.
 * @param certificate	Certificate object.
 * @return OpenSSL session reference.
 * @note The certificate object will be freed by the OpenSSL interface on session end.
 * @see pkcs11h_openssl_freeSession().
 */
pkcs11h_openssl_session_t
pkcs11h_openssl_createSession (
	IN const pkcs11h_certificate_t certificate
);

/**
 * @brief Sets cleanup hook
 * @param openssl_session	OpenSSL session reference.
 * @return Current hook.
 */
pkcs11h_hook_openssl_cleanup_t
pkcs11h_openssl_getCleanupHook (
	IN const pkcs11h_openssl_session_t openssl_session
);

/**
 * @brief Sets cleanup hook
 * @param openssl_session	OpenSSL session reference.
 * @param cleanup		hook.
 */
void
pkcs11h_openssl_setCleanupHook (
	IN const pkcs11h_openssl_session_t openssl_session,
	IN const pkcs11h_hook_openssl_cleanup_t cleanup
);

/**
 * @brief Free OpenSSL session.
 * @param openssl_session	OpenSSL session reference.
 * @note The openssl_session object has a reference count just like other OpenSSL objects.
 */
void
pkcs11h_openssl_freeSession (
	IN const pkcs11h_openssl_session_t openssl_session
);

/**
 * @brief Returns an RSA object out of the openssl_session object.
 * @param openssl_session	OpenSSL session reference.
 * @return RSA.
 */
RSA *
pkcs11h_openssl_session_getRSA (
	IN const pkcs11h_openssl_session_t openssl_session
);

/**
 * @brief Returns an X509 object out of the openssl_session object.
 * @param openssl_session	OpenSSL session reference.
 * @return X509.
 */
X509 *
pkcs11h_openssl_session_getX509 (
	IN const pkcs11h_openssl_session_t openssl_session
);

#ifdef __cplusplus
}
#endif

/** @} */

#endif				/* __PKCS11H_OPENSSL_H */
