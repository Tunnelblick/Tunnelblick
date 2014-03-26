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

#if defined(ENABLE_PKCS11H_ENGINE_POLARSSL)
#include <polarssl/x509.h>
#include <polarssl/version.h>

static
int
__pkcs11h_crypto_polarssl_initialize (
	IN void * const global_data
) {
	(void)global_data;

	return TRUE;
}

static
int
__pkcs11h_crypto_polarssl_uninitialize (
	IN void * const global_data
) {
	(void)global_data;

	return TRUE;
}

static
int
__pkcs11h_crypto_polarssl_certificate_get_expiration (
	IN void * const global_data,
	IN const unsigned char * const blob,
	IN const size_t blob_size,
	OUT time_t * const expiration
) {
	x509_cert x509;

	(void)global_data;

	/*_PKCS11H_ASSERT (global_data!=NULL); NOT NEEDED*/
	_PKCS11H_ASSERT (blob!=NULL);
	_PKCS11H_ASSERT (expiration!=NULL);

	*expiration = (time_t)0;

	memset(&x509, 0, sizeof(x509));
	if (0 != x509parse_crt (&x509, blob, blob_size)) {
		goto cleanup;
	}

	if (0 == x509parse_time_expired(&x509.valid_to)) {
		struct tm tm1;

		memset (&tm1, 0, sizeof (tm1));
		tm1.tm_year = x509.valid_to.year - 1900;
		tm1.tm_mon  = x509.valid_to.mon  - 1;
		tm1.tm_mday = x509.valid_to.day;
		tm1.tm_hour = x509.valid_to.hour - 1;
		tm1.tm_min  = x509.valid_to.min  - 1;
		tm1.tm_sec  = x509.valid_to.sec  - 1;

		*expiration = mktime (&tm1);
		*expiration += (int)(mktime (localtime (expiration)) - mktime (gmtime (expiration)));
	}

cleanup:

	x509_free(&x509);

	return *expiration != (time_t)0;
}

static
int
__pkcs11h_crypto_polarssl_certificate_get_dn (
	IN void * const global_data,
	IN const unsigned char * const blob,
	IN const size_t blob_size,
	OUT char * const dn,
	IN const size_t dn_max
) {
	x509_cert x509;
	int ret = FALSE;

	(void)global_data;

	/*_PKCS11H_ASSERT (global_data!=NULL); NOT NEEDED*/
	_PKCS11H_ASSERT (blob!=NULL);
	_PKCS11H_ASSERT (dn!=NULL);
	_PKCS11H_ASSERT (dn_max>0);

	dn[0] = '\x0';

	memset(&x509, 0, sizeof(x509));
	if (0 != x509parse_crt (&x509, blob, blob_size)) {
		goto cleanup;
	}

	if (-1 == x509parse_dn_gets(dn, dn_max, &x509.subject)) {
		goto cleanup;
	}

	ret = TRUE;

cleanup:

	x509_free(&x509);

	return ret;
}

static
int
__pkcs11h_crypto_polarssl_certificate_is_issuer (
	IN void * const global_data,
	IN const unsigned char * const issuer_blob,
	IN const size_t issuer_blob_size,
	IN const unsigned char * const cert_blob,
	IN const size_t cert_blob_size
) {
	x509_cert x509_issuer;
	x509_cert x509_cert;
	int verify_flags = 0;

	PKCS11H_BOOL is_issuer = FALSE;

	(void)global_data;

	/*_PKCS11H_ASSERT (global_data!=NULL); NOT NEEDED*/
	_PKCS11H_ASSERT (issuer_blob!=NULL);
	_PKCS11H_ASSERT (cert_blob!=NULL);

	memset(&x509_issuer, 0, sizeof(x509_issuer));
	if (0 != x509parse_crt (&x509_issuer, issuer_blob, issuer_blob_size)) {
		goto cleanup;
	}

	memset(&x509_cert, 0, sizeof(x509_cert));
	if (0 != x509parse_crt (&x509_cert, cert_blob, cert_blob_size)) {
		goto cleanup;
	}

#if (POLARSSL_VERSION_MAJOR == 0)
	if ( 0 == x509parse_verify(&x509_cert, &x509_issuer, NULL, NULL,
		&verify_flags ))
#else
	if ( 0 == x509parse_verify(&x509_cert, &x509_issuer, NULL, NULL,
		&verify_flags, NULL, NULL ))
#endif

cleanup:
	x509_free(&x509_cert);
	x509_free(&x509_issuer);

	return is_issuer;
}

const pkcs11h_engine_crypto_t _g_pkcs11h_crypto_engine_polarssl = {
	NULL,
	__pkcs11h_crypto_polarssl_initialize,
	__pkcs11h_crypto_polarssl_uninitialize,
	__pkcs11h_crypto_polarssl_certificate_get_expiration,
	__pkcs11h_crypto_polarssl_certificate_get_dn,
	__pkcs11h_crypto_polarssl_certificate_is_issuer
};

#endif				/* ENABLE_PKCS11H_ENGINE_POLARSSL */
