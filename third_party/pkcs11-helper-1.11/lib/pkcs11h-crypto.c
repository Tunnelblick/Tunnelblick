/*
 * Copyright (c) 2005-2011 Alon Bar-Lev <alon.barlev@gmail.com>
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
 *     o Neither the name of the Alon Bar-Lev nor the names of its
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

#include "common.h"

#include "_pkcs11h-crypto.h"

#if defined(ENABLE_PKCS11H_ENGINE_CRYPTOAPI)
extern const pkcs11h_engine_crypto_t _g_pkcs11h_crypto_engine_cryptoapi;
#endif
#if defined(ENABLE_PKCS11H_ENGINE_OPENSSL)
extern const pkcs11h_engine_crypto_t _g_pkcs11h_crypto_engine_openssl;
#endif
#if defined(ENABLE_PKCS11H_ENGINE_NSS)
extern const pkcs11h_engine_crypto_t _g_pkcs11h_crypto_engine_nss;
#endif
#if defined(ENABLE_PKCS11H_ENGINE_POLARSSL)
extern const pkcs11h_engine_crypto_t _g_pkcs11h_crypto_engine_polarssl;
#endif
#if defined(ENABLE_PKCS11H_ENGINE_GNUTLS)
extern const pkcs11h_engine_crypto_t _g_pkcs11h_crypto_engine_gnutls;
#endif

pkcs11h_engine_crypto_t _g_pkcs11h_crypto_engine = {
	NULL,
	NULL,
	NULL,
	NULL,
	NULL,
	NULL
};

CK_RV
pkcs11h_engine_setCrypto (
	IN const pkcs11h_engine_crypto_t * const engine
) {
	const pkcs11h_engine_crypto_t *_engine = NULL;
	CK_RV rv = CKR_FUNCTION_FAILED;

	/*_PKCS11H_ASSERT (engine!=NULL); Not required */

	if (engine == PKCS11H_ENGINE_CRYPTO_AUTO) {
#if defined(ENABLE_PKCS11H_ENGINE_CRYPTOAPI)
		_engine = &_g_pkcs11h_crypto_engine_cryptoapi;
#elif defined(ENABLE_PKCS11H_ENGINE_OPENSSL)
		_engine = &_g_pkcs11h_crypto_engine_openssl;
#elif defined(ENABLE_PKCS11H_ENGINE_NSS)
		_engine = &_g_pkcs11h_crypto_engine_nss;
#elif defined(ENABLE_PKCS11H_ENGINE_POLARSSL)
		_engine = &_g_pkcs11h_crypto_engine_polarssl;
#elif defined(ENABLE_PKCS11H_ENGINE_GNUTLS)
		_engine = &_g_pkcs11h_crypto_engine_gnutls;
#else
		rv = CKR_ATTRIBUTE_VALUE_INVALID;
		goto cleanup;
#endif
	}
	else if (engine ==  PKCS11H_ENGINE_CRYPTO_GPL) {
#if defined(ENABLE_PKCS11H_ENGINE_CRYPTOAPI)
		_engine = &_g_pkcs11h_crypto_engine_cryptoapi;
#elif defined(ENABLE_PKCS11H_ENGINE_POLARSSL)
		_engine = &_g_pkcs11h_crypto_engine_polarssl;
#elif defined(ENABLE_PKCS11H_ENGINE_GNUTLS)
		_engine = &_g_pkcs11h_crypto_engine_gnutls;
#else
		rv = CKR_ATTRIBUTE_VALUE_INVALID;
		goto cleanup;
#endif
	}
	else if (engine == PKCS11H_ENGINE_CRYPTO_CRYPTOAPI) {
#if defined(ENABLE_PKCS11H_ENGINE_CRYPTOAPI)
		_engine = &_g_pkcs11h_crypto_engine_cryptoapi;
#else
		rv = CKR_ATTRIBUTE_VALUE_INVALID;
		goto cleanup;
#endif
	}
	else if (engine == PKCS11H_ENGINE_CRYPTO_OPENSSL) {
#if defined(ENABLE_PKCS11H_ENGINE_OPENSSL)
		_engine = &_g_pkcs11h_crypto_engine_openssl;
#else
		rv = CKR_ATTRIBUTE_VALUE_INVALID;
		goto cleanup;
#endif
	}
	else if (engine == PKCS11H_ENGINE_CRYPTO_GNUTLS) {
#if defined(ENABLE_PKCS11H_ENGINE_GNUTLS)
		_engine = &_g_pkcs11h_crypto_engine_gnutls;
#else
		rv = CKR_ATTRIBUTE_VALUE_INVALID;
		goto cleanup;
#endif
	}
	else if (engine == PKCS11H_ENGINE_CRYPTO_NSS) {
#if defined(ENABLE_PKCS11H_ENGINE_NSS)
		_engine = &_g_pkcs11h_crypto_engine_nss;
#else
		rv = CKR_ATTRIBUTE_VALUE_INVALID;
		goto cleanup;
#endif
	}
	else if (engine == PKCS11H_ENGINE_CRYPTO_POLARSSL) {
#if defined(ENABLE_PKCS11H_ENGINE_POLARSSL)
		_engine = &_g_pkcs11h_crypto_engine_polarssl;
#else
		rv = CKR_ATTRIBUTE_VALUE_INVALID;
		goto cleanup;
#endif
	}
	else {
		_engine = engine;
	}

	memmove (&_g_pkcs11h_crypto_engine, _engine, sizeof (pkcs11h_engine_crypto_t));

	rv = CKR_OK;

cleanup:

	return rv;
}

