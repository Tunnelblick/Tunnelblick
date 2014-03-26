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

#if defined(ENABLE_PKCS11H_ENGINE_GNUTLS)
#include <gnutls/x509.h>

static
int
__pkcs11h_crypto_gnutls_initialize (
	IN void * const global_data
) {
	(void)global_data;

	/*_PKCS11H_ASSERT (global_data!=NULL); NOT NEEDED*/
	if (gnutls_global_init () != GNUTLS_E_SUCCESS) {
		return FALSE;
	}
	else {
		return TRUE;
	}
}

static
int
__pkcs11h_crypto_gnutls_uninitialize (
	IN void * const global_data
) {
	(void)global_data;

	/*_PKCS11H_ASSERT (global_data!=NULL); NOT NEEDED*/
	gnutls_global_deinit ();

	return TRUE;
}

static
int
__pkcs11h_crypto_gnutls_certificate_get_expiration (
	IN void * const global_data,
	IN const unsigned char * const blob,
	IN const size_t blob_size,
	OUT time_t * const expiration
) {
	gnutls_x509_crt_t cert = NULL;
	gnutls_datum_t datum;
	time_t now = time (NULL);
	time_t notBefore;
	time_t notAfter;

	(void)global_data;

	/*_PKCS11H_ASSERT (global_data!=NULL); NOT NEEDED*/
	_PKCS11H_ASSERT (blob!=NULL);
	_PKCS11H_ASSERT (expiration!=NULL);

	*expiration = (time_t)0;

	if (gnutls_x509_crt_init (&cert) != GNUTLS_E_SUCCESS) {
		/* gnutls sets output */
		cert = NULL;
		goto cleanup;
	}

	datum.data = (unsigned char *)blob;
	datum.size = blob_size;

	if (gnutls_x509_crt_import (cert, &datum, GNUTLS_X509_FMT_DER) != GNUTLS_E_SUCCESS) {
		goto cleanup;
	}

	notBefore = gnutls_x509_crt_get_activation_time (cert);
	notAfter = gnutls_x509_crt_get_expiration_time (cert);

	if (
		now >= notBefore &&
		now <= notAfter
	) {
		*expiration = notAfter;
	}

cleanup:

	if (cert != NULL) {
		gnutls_x509_crt_deinit (cert);
		cert = NULL;
	}

	return *expiration != (time_t)0;
}

static
int
__pkcs11h_crypto_gnutls_certificate_get_dn (
	IN void * const global_data,
	IN const unsigned char * const blob,
	IN const size_t blob_size,
	OUT char * const dn,
	IN const size_t dn_max
) {
	gnutls_x509_crt_t cert = NULL;
	gnutls_datum_t datum;
	size_t s;

	(void)global_data;

	/*_PKCS11H_ASSERT (global_data!=NULL); NOT NEEDED*/
	_PKCS11H_ASSERT (blob!=NULL);
	_PKCS11H_ASSERT (dn!=NULL);
	_PKCS11H_ASSERT (dn_max>0);

	dn[0] = '\x0';

	if (gnutls_x509_crt_init (&cert) != GNUTLS_E_SUCCESS) {
		/* gnutls sets output */
		cert = NULL;
		goto cleanup;
	}

	datum.data = (unsigned char *)blob;
	datum.size = blob_size;

	if (gnutls_x509_crt_import (cert, &datum, GNUTLS_X509_FMT_DER) != GNUTLS_E_SUCCESS) {
		goto cleanup;
	}

	s = dn_max;
	if (
		gnutls_x509_crt_get_dn (
			cert,
			dn,
			&s
		) != GNUTLS_E_SUCCESS
	) {
		/* gnutls sets output */
		dn[0] = '\x0';
		goto cleanup;
	}

cleanup:

	if (cert != NULL) {
		gnutls_x509_crt_deinit (cert);
		cert = NULL;
	}

	return dn[0] != '\x0';
}

static
int
__pkcs11h_crypto_gnutls_certificate_is_issuer (
	IN void * const global_data,
	IN const unsigned char * const issuer_blob,
	IN const size_t issuer_blob_size,
	IN const unsigned char * const cert_blob,
	IN const size_t cert_blob_size
) {
	gnutls_x509_crt_t cert_issuer = NULL;
	gnutls_x509_crt_t cert_cert = NULL;
	gnutls_datum_t datum;
	PKCS11H_BOOL is_issuer = FALSE;
	unsigned int result = 0;

	(void)global_data;

	/*_PKCS11H_ASSERT (global_data!=NULL); NOT NEEDED*/
	_PKCS11H_ASSERT (issuer_blob!=NULL);
	_PKCS11H_ASSERT (cert_blob!=NULL);

	if (gnutls_x509_crt_init (&cert_issuer) != GNUTLS_E_SUCCESS) {
		/* gnutls sets output */
		cert_issuer = NULL;
		goto cleanup;
	}
	if (gnutls_x509_crt_init (&cert_cert) != GNUTLS_E_SUCCESS) {
		/* gnutls sets output */
		cert_cert = NULL;
		goto cleanup;
	}

	datum.data = (unsigned char *)issuer_blob;
	datum.size = issuer_blob_size;

	if (
		gnutls_x509_crt_import (
			cert_issuer,
			&datum,
			GNUTLS_X509_FMT_DER
		) != GNUTLS_E_SUCCESS
	) {
		goto cleanup;
	}

	datum.data = (unsigned char *)cert_blob;
	datum.size = cert_blob_size;

	if (
		gnutls_x509_crt_import (
			cert_cert,
			&datum,
			GNUTLS_X509_FMT_DER
		) != GNUTLS_E_SUCCESS
	) {
		goto cleanup;
	}

	if (
		gnutls_x509_crt_verify (
			cert_cert,
			&cert_issuer,
			1,
			0,
			&result
		) &&
		(result & GNUTLS_CERT_INVALID) == 0
	) {
		is_issuer = TRUE;
	}

cleanup:

	if (cert_cert != NULL) {
		gnutls_x509_crt_deinit (cert_cert);
		cert_cert = NULL;
	}

	if (cert_issuer != NULL) {
		gnutls_x509_crt_deinit (cert_issuer);
		cert_issuer = NULL;
	}

	return is_issuer;
}

const pkcs11h_engine_crypto_t _g_pkcs11h_crypto_engine_gnutls = {
	NULL,
	__pkcs11h_crypto_gnutls_initialize,
	__pkcs11h_crypto_gnutls_uninitialize,
	__pkcs11h_crypto_gnutls_certificate_get_expiration,
	__pkcs11h_crypto_gnutls_certificate_get_dn,
	__pkcs11h_crypto_gnutls_certificate_is_issuer
};

#endif				/* ENABLE_PKCS11H_ENGINE_GNUTLS */
