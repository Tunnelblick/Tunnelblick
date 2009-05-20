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
 * @addtogroup pkcs11h_engines Engines interface
 *
 * External dependencies.
 *
 * @{
 */

/**
 * @file pkcs11h-engines.h
 * @brief pkcs11-helper engines definitions.
 * @author Alon Bar-Lev <alon.barlev@gmail.com>
 * @see pkcs11h_engines.
 */

#ifndef __PKCS11H_ENGINES_H
#define __PKCS11H_ENGINES_H

#include <time.h>
#if !defined(_WIN32)
#include <sys/time.h>
#endif
#include <pkcs11-helper-1.0/pkcs11h-def.h>

#if defined(__cplusplus)
extern "C" {
#endif

/**
 * @brief System engine.
 */
typedef struct pkcs11h_sys_engine_s {

	/**
	 * @brief malloc provider.
	 * @param size	Block size.
	 * @return Pointer.
	 */
	void *(*malloc) (size_t size);

	/**
	 * @brief free provider.
	 * @param ptr	Pointer.
	 */
	void (*free) (void *ptr);

	/**
	 * @brief time provider.
	 * @return time_t.
	 */
	time_t (*time) (void);

	/**
	 * @brief usleep provider.
	 * @param usec	Microseconds.
	 */
	void (*usleep) (unsigned long usec);

	/**
	 * @brief gettimeofday provider (unix).
	 * @param rv	timeval.
	 */
#if defined(_WIN32)
	void *gettimeofday;
#else
	int (*gettimeofday) (struct timeval *tv);
#endif
} pkcs11h_engine_system_t;

/**
 * @brief Crypto engine.
 */
typedef struct pkcs11h_crypto_engine_s {
	void *global_data;

	/**
	 * @brief Initialize engine.
	 * @param global_data	Engine data.
	 * @return None zero - Sucess.
	 */
	int (*initialize) (
		IN void * const global_data
	);

	/**
	 * @brief Uninitialize engine.
	 * @param global_data	Engine data.
	 * @return None zero - Sucess.
	 */
	int (*uninitialize) (
		IN void * const global_data
	);

	/**
	 * @brief Get exportation date out of certificate.
	 * @param global_data	Engine data.
	 * @param blob		Certificate blob.
	 * @param blob_size	Certificate blob size.
	 * @param expiration	Certificate expiration time.
	 * @return None zero - Sucess.
	 */
	int (*certificate_get_expiration) (
		IN void * const global_data,
		IN const unsigned char * const blob,
		IN const size_t blob_size,
		OUT time_t * const expiration
	);

	/**
	 * @brief Get certificate distinguished name.
	 * @param global_data	Engine data.
	 * @param blob		Certificate blob.
	 * @param blob_size	Certificate blob size.
	 * @param dn		dn buffer.
	 * @param dn_max	dn buffer size.
	 * @return None zero - Sucess.
	 */
	int (*certificate_get_dn) (
		IN void * const global_data,
		IN const unsigned char * const blob,
		IN const size_t blob_size,
		OUT char * const dn,
		IN const size_t dn_max
	);

	/**
	 * @brief Determine if one certificate is an issuer of another.
	 * @param global_data		Engine data.
	 * @param issuer_blob		Issuer's certificate blob.
	 * @param issuer_blob_size	Issuer's certificate blob size.
	 * @param cert_blob		Certificate blob.
	 * @param cert_blob_size	Certificate blob size.
	 * @return None zero - Sucess.
	 */
	int (*certificate_is_issuer) (
		IN void * const global_data,
		IN const unsigned char * const issuer_blob,
		IN const size_t issuer_blob_size,
		IN const unsigned char * const cert_blob,
		IN const size_t cert_blob_size
	);
} pkcs11h_engine_crypto_t;

/**
 * @brief pkcs11-helper built-in engines.
 * @addtogroup PKCS11H_ENGINE_CRYPTO
 * @see pkcs11h_engine_setCrypto().
 * @{
 */
/** Auto select. */
#define PKCS11H_ENGINE_CRYPTO_AUTO	((pkcs11h_engine_crypto_t *)0)
/** Select OpenSSL. */
#define PKCS11H_ENGINE_CRYPTO_OPENSSL	((pkcs11h_engine_crypto_t *)1)
/** Select GnuTLS. */
#define PKCS11H_ENGINE_CRYPTO_GNUTLS	((pkcs11h_engine_crypto_t *)2)
/** Select Win32. */
#define PKCS11H_ENGINE_CRYPTO_WIN32	((pkcs11h_engine_crypto_t *)3)
/** Select NSS. */
#define PKCS11H_ENGINE_CRYPTO_NSS	((pkcs11h_engine_crypto_t *)4)
/** Auto select GPL enigne. */
#define PKCS11H_ENGINE_CRYPTO_GPL	((pkcs11h_engine_crypto_t *)10)
/** @} */

/**
 * @brief Set system engine to be used.
 * @param engine	Engine to use.
 * @return CK_RV.
 * @note Must be called before pkcs11h_initialize.
 * @note Default engine is libc functions.
 */
CK_RV
pkcs11h_engine_setSystem (
	IN const pkcs11h_engine_system_t * const engine
);

/**
 * @brief Set crypto engine to be used.
 * @param engine	Engine to use.
 * @return CK_RV.
 * @note Must be called before pkcs11h_initialize.
 * @note Default is provided at configuration time.
 * @see PKCS11H_ENGINE_CRYPTO
 */
CK_RV
pkcs11h_engine_setCrypto (
	IN const pkcs11h_engine_crypto_t * const engine
);

#ifdef __cplusplus
}
#endif

/** @} */

#endif				/* __PKCS11H_ENGINES_H */
