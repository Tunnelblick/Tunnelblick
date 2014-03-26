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

#if defined(ENABLE_PKCS11H_ENGINE_OPENSSL)
#include <openssl/x509.h>

#if OPENSSL_VERSION_NUMBER < 0x00907000L && defined(CRYPTO_LOCK_ENGINE)
# define RSA_get_default_method RSA_get_default_openssl_method
#else
# ifdef HAVE_ENGINE_GET_DEFAULT_RSA
#  include <openssl/engine.h>
#  if OPENSSL_VERSION_NUMBER < 0x0090704fL
#   define BROKEN_OPENSSL_ENGINE
#  endif
# endif
#endif

#if OPENSSL_VERSION_NUMBER < 0x00907000L
#if !defined(RSA_PKCS1_PADDING_SIZE)
#define RSA_PKCS1_PADDING_SIZE 11
#endif
#endif

#if OPENSSL_VERSION_NUMBER < 0x00908000L
typedef unsigned char *__pkcs11_openssl_d2i_t;
#else
typedef const unsigned char *__pkcs11_openssl_d2i_t;
#endif

static
int
__pkcs11h_crypto_openssl_initialize (
	IN void * const global_data
) {
	(void)global_data;

	OpenSSL_add_all_digests ();

	return TRUE;
}

static
int
__pkcs11h_crypto_openssl_uninitialize (
	IN void * const global_data
) {
	(void)global_data;

	return TRUE;
}

static
int
__pkcs11h_crypto_openssl_certificate_get_expiration (
	IN void * const global_data,
	IN const unsigned char * const blob,
	IN const size_t blob_size,
	OUT time_t * const expiration
) {
	X509 *x509 = NULL;
	__pkcs11_openssl_d2i_t d2i;
	ASN1_TIME *notBefore;
	ASN1_TIME *notAfter;

	(void)global_data;

	/*_PKCS11H_ASSERT (global_data!=NULL); NOT NEEDED*/
	_PKCS11H_ASSERT (blob!=NULL);
	_PKCS11H_ASSERT (expiration!=NULL);

	*expiration = (time_t)0;

	if ((x509 = X509_new ()) == NULL) {
		goto cleanup;
	}

	d2i = (__pkcs11_openssl_d2i_t)blob;

	if (!d2i_X509 (&x509, &d2i, blob_size)) {
		goto cleanup;
	}

	notBefore = X509_get_notBefore (x509);
	notAfter = X509_get_notAfter (x509);

	if (
		notBefore != NULL &&
		notAfter != NULL &&
		X509_cmp_current_time (notBefore) <= 0 &&
		X509_cmp_current_time (notAfter) >= 0 &&
		notAfter->length >= 12
	) {
		struct tm tm1;

		memset (&tm1, 0, sizeof (tm1));
		tm1.tm_year = (notAfter->data[ 0] - '0') * 10 + (notAfter->data[ 1] - '0') + 100;
		tm1.tm_mon  = (notAfter->data[ 2] - '0') * 10 + (notAfter->data[ 3] - '0') - 1;
		tm1.tm_mday = (notAfter->data[ 4] - '0') * 10 + (notAfter->data[ 5] - '0');
		tm1.tm_hour = (notAfter->data[ 6] - '0') * 10 + (notAfter->data[ 7] - '0');
		tm1.tm_min  = (notAfter->data[ 8] - '0') * 10 + (notAfter->data[ 9] - '0');
		tm1.tm_sec  = (notAfter->data[10] - '0') * 10 + (notAfter->data[11] - '0');

		*expiration = mktime (&tm1);
		*expiration += (int)(mktime (localtime (expiration)) - mktime (gmtime (expiration)));
	}

cleanup:

	if (x509 != NULL) {
		X509_free (x509);
		x509 = NULL;
	}

	return *expiration != (time_t)0;
}

static
int
__pkcs11h_crypto_openssl_certificate_get_dn (
	IN void * const global_data,
	IN const unsigned char * const blob,
	IN const size_t blob_size,
	OUT char * const dn,
	IN const size_t dn_max
) {
	X509 *x509 = NULL;
	__pkcs11_openssl_d2i_t d2i;

	(void)global_data;

	/*_PKCS11H_ASSERT (global_data!=NULL); NOT NEEDED*/
	_PKCS11H_ASSERT (blob!=NULL);
	_PKCS11H_ASSERT (dn!=NULL);
	_PKCS11H_ASSERT (dn_max>0);

	dn[0] = '\x0';

	if ((x509 = X509_new ()) == NULL) {
		goto cleanup;
	}

	d2i = (__pkcs11_openssl_d2i_t)blob;

	if (!d2i_X509 (&x509, &d2i, blob_size)) {
		goto cleanup;
	}

	X509_NAME_oneline (
		X509_get_subject_name (x509),
		dn,
		dn_max
	);

cleanup:

	if (x509 != NULL) {
		X509_free (x509);
		x509 = NULL;
	}

	return dn[0] != '\x0';
}

static
int
__pkcs11h_crypto_openssl_certificate_is_issuer (
	IN void * const global_data,
	IN const unsigned char * const issuer_blob,
	IN const size_t issuer_blob_size,
	IN const unsigned char * const cert_blob,
	IN const size_t cert_blob_size
) {
	X509 *x509_issuer = NULL;
	X509 *x509_cert = NULL;
	EVP_PKEY *pub_issuer = NULL;
	__pkcs11_openssl_d2i_t d2i;
	PKCS11H_BOOL is_issuer = FALSE;

	(void)global_data;

	/*_PKCS11H_ASSERT (global_data!=NULL); NOT NEEDED*/
	_PKCS11H_ASSERT (issuer_blob!=NULL);
	_PKCS11H_ASSERT (cert_blob!=NULL);

	if (
		(x509_issuer = X509_new ()) == NULL ||
		(x509_cert = X509_new ()) == NULL
	) {
		goto cleanup;
	}

	d2i = (__pkcs11_openssl_d2i_t)issuer_blob;
	if (
		!d2i_X509 (
			&x509_issuer,
			&d2i,
			issuer_blob_size
		)
	) {
		goto cleanup;
	}

	d2i = (__pkcs11_openssl_d2i_t)cert_blob;
	if (
		!d2i_X509 (
			&x509_cert,
			&d2i,
			cert_blob_size
		)
	) {
		goto cleanup;
	}

	if (
		(pub_issuer = X509_get_pubkey (x509_issuer)) == NULL
	) {
		goto cleanup;
	}

	if (
		!X509_NAME_cmp (
			X509_get_subject_name (x509_issuer),
			X509_get_issuer_name (x509_cert)
		) &&
		X509_verify (x509_cert, pub_issuer) == 1
	) {
		is_issuer = TRUE;
	}

cleanup:

	if (pub_issuer != NULL) {
		EVP_PKEY_free (pub_issuer);
		pub_issuer = NULL;
	}
	if (x509_issuer != NULL) {
		X509_free (x509_issuer);
		x509_issuer = NULL;
	}
	if (x509_cert != NULL) {
		X509_free (x509_cert);
		x509_cert = NULL;
	}

	return is_issuer;
}

const pkcs11h_engine_crypto_t _g_pkcs11h_crypto_engine_openssl = {
	NULL,
	__pkcs11h_crypto_openssl_initialize,
	__pkcs11h_crypto_openssl_uninitialize,
	__pkcs11h_crypto_openssl_certificate_get_expiration,
	__pkcs11h_crypto_openssl_certificate_get_dn,
	__pkcs11h_crypto_openssl_certificate_is_issuer
};

/*======================================================================*
 * FIXUPS
 *======================================================================*/

#ifdef BROKEN_OPENSSL_ENGINE
static void broken_openssl_init(void) __attribute__ ((constructor));
static void  broken_openssl_init(void)
{
	SSL_library_init();
	ENGINE_load_openssl();
	ENGINE_register_all_RSA();
}
#endif

#endif				/* ENABLE_PKCS11H_ENGINE_OPENSSL */
