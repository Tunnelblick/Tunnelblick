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

#include "common.h"

#include <pkcs11-helper-1.0/pkcs11h-core.h>
#include "_pkcs11h-util.h"
#include "_pkcs11h-sys.h"
#include "_pkcs11h-crypto.h"

#if defined(ENABLE_PKCS11H_ENGINE_OPENSSL)
#include <openssl/x509.h>
#endif

#if defined(ENABLE_PKCS11H_ENGINE_GNUTLS)
#include <gnutls/x509.h>
#endif

#if defined(ENABLE_PKCS11H_ENGINE_NSS)
#define _PKCS11T_H_ /* required so no conflict with ours */
#include <nss.h>
#include <cert.h>
#endif

#if defined(ENABLE_PKCS11H_ENGINE_WIN32)
#include <wincrypt.h>
#if !defined(CRYPT_VERIFY_CERT_SIGN_SUBJECT_CERT)
#define CRYPT_VERIFY_CERT_SIGN_SUBJECT_CERT	0x02
#endif
#if !defined(CRYPT_VERIFY_CERT_SIGN_ISSUER_CERT)
#define CRYPT_VERIFY_CERT_SIGN_ISSUER_CERT	0x02
#endif
#if !defined(CERT_NAME_STR_REVERSE_FLAG)
#define CERT_NAME_STR_REVERSE_FLAG		0x02000000
#endif

#endif

/*===========================================
 * Constants
 */

#if defined(ENABLE_PKCS11H_ENGINE_OPENSSL)

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

#endif

#if defined(ENABLE_PKCS11H_ENGINE_OPENSSL)

#if OPENSSL_VERSION_NUMBER < 0x00908000L
typedef unsigned char *__pkcs11_openssl_d2i_t;
#else
typedef const unsigned char *__pkcs11_openssl_d2i_t;
#endif

#endif

#if defined(ENABLE_PKCS11H_ENGINE_WIN32)

typedef PCCERT_CONTEXT (WINAPI *__CertCreateCertificateContext_t) (
	DWORD dwCertEncodingType,
	const BYTE *pbCertEncoded,
	DWORD cbCertEncoded
);
typedef BOOL (WINAPI *__CertFreeCertificateContext_t) (
	PCCERT_CONTEXT pCertContext
);
typedef DWORD (WINAPI *CertNameToStrW_t) (
	DWORD dwCertEncodingType,
	PCERT_NAME_BLOB pName,
	DWORD dwStrType,
	LPWSTR psz,
	DWORD csz
);
typedef BOOL (WINAPI *__CryptVerifyCertificateSignatureEx_t) (
	void *hCryptProv,
	DWORD dwCertEncodingType,
	DWORD dwSubjectType,
	void* pvSubject,
	DWORD dwIssuerType,
	void* pvIssuer,
	DWORD dwFlags,
	void* pvReserved
);

typedef struct __crypto_win32_data_s {
	HMODULE handle;
	__CertCreateCertificateContext_t p_CertCreateCertificateContext;
	__CertFreeCertificateContext_t p_CertFreeCertificateContext;
	CertNameToStrW_t p_CertNameToStrW;
	__CryptVerifyCertificateSignatureEx_t p_CryptVerifyCertificateSignatureEx;
} *__crypto_win32_data_t;

#endif

#if defined(ENABLE_PKCS11H_ENGINE_OPENSSL)

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

static const pkcs11h_engine_crypto_t _g_pkcs11h_crypto_engine_openssl = {
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

#if defined(ENABLE_PKCS11H_ENGINE_GNUTLS)

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

static const pkcs11h_engine_crypto_t _g_pkcs11h_crypto_engine_gnutls = {
	NULL,
	__pkcs11h_crypto_gnutls_initialize,
	__pkcs11h_crypto_gnutls_uninitialize,
	__pkcs11h_crypto_gnutls_certificate_get_expiration,
	__pkcs11h_crypto_gnutls_certificate_get_dn,
	__pkcs11h_crypto_gnutls_certificate_is_issuer
};

#endif				/* ENABLE_PKCS11H_ENGINE_GNUTLS */

#if defined(ENABLE_PKCS11H_ENGINE_NSS)

static
int
__pkcs11h_crypto_nss_initialize (
	IN void * const global_data
) {
	int ret = FALSE;

	if (NSS_IsInitialized ()) {
		*(int *)global_data = FALSE;
	}
	else {
		if (NSS_NoDB_Init (NULL) != SECSuccess) {
			goto cleanup;
		}
		*(int *)global_data = TRUE;
	}

	ret = TRUE;

cleanup:

	return ret;
}

static
int
__pkcs11h_crypto_nss_uninitialize (
	IN void * const global_data
) {
	if (*(int *)global_data != FALSE) {
		NSS_Shutdown ();
	}

	return TRUE;
}

static
int
__pkcs11h_crypto_nss_certificate_get_expiration (
	IN void * const global_data,
	IN const unsigned char * const blob,
	IN const size_t blob_size,
	OUT time_t * const expiration
) {
	CERTCertificate *cert = NULL;
	PRTime pr_notBefore, pr_notAfter;
	time_t notBefore, notAfter;
	time_t now = time (NULL);

	(void)global_data;

	*expiration = (time_t)0;

	/*_PKCS11H_ASSERT (global_data!=NULL); NOT NEEDED*/
	_PKCS11H_ASSERT (blob!=NULL);
	_PKCS11H_ASSERT (expiration!=NULL);

	if ((cert = CERT_DecodeCertFromPackage ((char *)blob, blob_size)) == NULL) {
		goto cleanup;
	}

	if (CERT_GetCertTimes (cert, &pr_notBefore, &pr_notAfter) != SECSuccess) {
		goto cleanup;
	}

	notBefore = pr_notBefore/1000000;
	notAfter = pr_notAfter/1000000;

	notBefore = mktime (gmtime (&notBefore));
	notBefore += (int)(mktime (localtime (&notBefore)) - mktime (gmtime (&notBefore)));
	notAfter = mktime (gmtime (&notAfter));
	notAfter += (int)(mktime (localtime (&notAfter)) - mktime (gmtime (&notAfter)));

	if (
		now >= notBefore &&
		now <= notAfter
	) {
		*expiration = notAfter;
	}

cleanup:

	if (cert != NULL) {
		CERT_DestroyCertificate (cert);
	}

	return *expiration != (time_t)0;
}

static
int
__pkcs11h_crypto_nss_certificate_get_dn (
	IN void * const global_data,
	IN const unsigned char * const blob,
	IN const size_t blob_size,
	OUT char * const dn,
	IN const size_t dn_max
) {
	CERTCertificate *cert = NULL;

	(void)global_data;

	/*_PKCS11H_ASSERT (global_data!=NULL); NOT NEEDED*/
	_PKCS11H_ASSERT (blob!=NULL);
	_PKCS11H_ASSERT (dn!=NULL);
	_PKCS11H_ASSERT (dn_max>0);

	dn[0] = '\x0';

	if ((cert = CERT_DecodeCertFromPackage ((char *)blob, blob_size)) == NULL) {
		goto cleanup;
	}

	if (strlen (cert->subjectName) >= dn_max) {
		goto cleanup;
	}

	strcpy (dn, cert->subjectName);

cleanup:

	if (cert != NULL) {
		CERT_DestroyCertificate (cert);
	}

	return dn[0] != '\x0';
}

static
int
__pkcs11h_crypto_nss_certificate_is_issuer (
	IN void * const global_data,
	IN const unsigned char * const issuer_blob,
	IN const size_t issuer_blob_size,
	IN const unsigned char * const cert_blob,
	IN const size_t cert_blob_size
) {
	PKCS11H_BOOL is_issuer = FALSE;
	CERTCertificate *cert = NULL;
	CERTCertificate *issuer = NULL;

	(void)global_data;

	/*_PKCS11H_ASSERT (global_data!=NULL); NOT NEEDED*/
	_PKCS11H_ASSERT (issuer_blob!=NULL);
	_PKCS11H_ASSERT (cert_blob!=NULL);

	if ((issuer = CERT_DecodeCertFromPackage ((char *)issuer_blob, issuer_blob_size)) == NULL) {
		goto cleanup;
	}

	if ((cert = CERT_DecodeCertFromPackage ((char *)cert_blob, cert_blob_size)) == NULL) {
		goto cleanup;
	}

	is_issuer = CERT_VerifySignedDataWithPublicKeyInfo (
		&cert->signatureWrap,
		&issuer->subjectPublicKeyInfo,
		NULL
	) == SECSuccess;

cleanup:

	if (cert != NULL) {
		CERT_DestroyCertificate (cert);
	}

	if (issuer != NULL) {
		CERT_DestroyCertificate (issuer);
	}

	return is_issuer;
}

static int s_nss_data = 0;
static const pkcs11h_engine_crypto_t _g_pkcs11h_crypto_engine_nss = {
	&s_nss_data,
	__pkcs11h_crypto_nss_initialize,
	__pkcs11h_crypto_nss_uninitialize,
	__pkcs11h_crypto_nss_certificate_get_expiration,
	__pkcs11h_crypto_nss_certificate_get_dn,
	__pkcs11h_crypto_nss_certificate_is_issuer
};

#endif				/* ENABLE_PKCS11H_ENGINE_NSS */

#if defined(ENABLE_PKCS11H_ENGINE_WIN32)

static
int
__pkcs11h_crypto_win32_uninitialize (
	IN void * const global_data
) {
	__crypto_win32_data_t data = (__crypto_win32_data_t)global_data;

	_PKCS11H_ASSERT (global_data!=NULL);

	if (data->handle != NULL) {
		FreeLibrary (data->handle);
		data->handle = NULL;
	}

	memset (data, 0, sizeof (struct __crypto_win32_data_s));

	return 1;
}

static
int
__pkcs11h_crypto_win32_initialize (
	IN void * const global_data
) {
	__crypto_win32_data_t data = (__crypto_win32_data_t)global_data;

	_PKCS11H_ASSERT (global_data!=NULL);

	__pkcs11h_crypto_win32_uninitialize (data);

	data->handle = LoadLibraryA ("crypt32.dll");
	if (data->handle == NULL) {
		return 0;
	}

	data->p_CertCreateCertificateContext = (__CertCreateCertificateContext_t)GetProcAddress (
		data->handle,
		"CertCreateCertificateContext"
	);
	data->p_CertFreeCertificateContext = (__CertFreeCertificateContext_t)GetProcAddress (
		data->handle,
		"CertFreeCertificateContext"
	);
	data->p_CertNameToStrW = (CertNameToStrW_t)GetProcAddress (
		data->handle,
		"CertNameToStrW"
	);
	data->p_CryptVerifyCertificateSignatureEx = (__CryptVerifyCertificateSignatureEx_t)GetProcAddress (
		data->handle,
		"CryptVerifyCertificateSignatureEx"
	);

	if (
		data->p_CertCreateCertificateContext == NULL ||
		data->p_CertFreeCertificateContext == NULL ||
		data->p_CertNameToStrW == NULL ||
		data->p_CryptVerifyCertificateSignatureEx == NULL
	) {
		__pkcs11h_crypto_win32_uninitialize (data);
		return 0;
	}

	return 1;
}

static
int
__pkcs11h_crypto_win32_certificate_get_expiration (
	IN void * const global_data,
	IN const unsigned char * const blob,
	IN const size_t blob_size,
	OUT time_t * const expiration
) {
	__crypto_win32_data_t data = (__crypto_win32_data_t)global_data;
	PCCERT_CONTEXT cert = NULL;
	PKCS11H_BOOL ok = FALSE;
	SYSTEMTIME ust, st;
	struct tm tm1;

	_PKCS11H_ASSERT (global_data!=NULL);
	_PKCS11H_ASSERT (blob!=NULL);
	_PKCS11H_ASSERT (expiration!=NULL);

	*expiration = (time_t)0;

	if (
		(cert = data->p_CertCreateCertificateContext (
			PKCS_7_ASN_ENCODING | X509_ASN_ENCODING,
			blob,
			blob_size
		)) == NULL ||
		!FileTimeToSystemTime (
			&cert->pCertInfo->NotAfter,
			&ust
		)
	) {
		goto cleanup;
	}

	SystemTimeToTzSpecificLocalTime (NULL, &ust, &st);
	memset (&tm1, 0, sizeof (tm1));
	tm1.tm_year = st.wYear - 1900;
	tm1.tm_mon  = st.wMonth - 1;
	tm1.tm_mday = st.wDay;
	tm1.tm_hour = st.wHour;
	tm1.tm_min  = st.wMinute;
	tm1.tm_sec  = st.wSecond;

	*expiration = mktime (&tm1);

	ok = TRUE;

cleanup:

	if (cert != NULL) {
		data->p_CertFreeCertificateContext (cert);
		cert = NULL;
	}

	return ok != FALSE;
}

static
int
__pkcs11h_crypto_win32_certificate_get_dn (
	IN void * const global_data,
	IN const unsigned char * const blob,
	IN const size_t blob_size,
	OUT char * const dn,
	IN const size_t dn_max
) {
	__crypto_win32_data_t data = (__crypto_win32_data_t)global_data;
	PCCERT_CONTEXT cert = NULL;
	PKCS11H_BOOL ok = TRUE;
	DWORD wsize;
	WCHAR *wstr = NULL;

	_PKCS11H_ASSERT (global_data!=NULL);
	_PKCS11H_ASSERT (blob!=NULL);
	_PKCS11H_ASSERT (dn!=NULL);
	_PKCS11H_ASSERT (dn_max>0);

	dn[0] = '\x0';

	if (
		(cert = data->p_CertCreateCertificateContext (
			PKCS_7_ASN_ENCODING | X509_ASN_ENCODING,
			blob,
			blob_size
		)) == NULL ||
		(wsize = data->p_CertNameToStrW (
			X509_ASN_ENCODING,
			&cert->pCertInfo->Subject,
			CERT_X500_NAME_STR | CERT_NAME_STR_REVERSE_FLAG,
			NULL,
			0
		)) == 0
	) {
		goto cleanup;
	}
	
	if ((wstr = (WCHAR *)_g_pkcs11h_sys_engine.malloc (wsize * sizeof (WCHAR))) == NULL) {
		goto cleanup;
	}
			
	if (
		(wsize = data->p_CertNameToStrW (
			X509_ASN_ENCODING,
			&cert->pCertInfo->Subject,
			CERT_X500_NAME_STR | CERT_NAME_STR_REVERSE_FLAG,
			wstr,
			wsize
		)) == 0 ||
		WideCharToMultiByte (
			CP_UTF8,
			0,
			wstr,
			-1,
			dn,
			dn_max,
			NULL,
			NULL
		) == 0
	) {
		goto cleanup;
	}

	ok = TRUE;

cleanup:

	if (wstr != NULL) {
		_g_pkcs11h_sys_engine.free (wstr);
		wstr = NULL;
	}

	if (cert != NULL) {
		data->p_CertFreeCertificateContext (cert);
		cert = NULL;
	}

	return ok != FALSE;
}

static
int
__pkcs11h_crypto_win32_certificate_is_issuer (
	IN void * const global_data,
	IN const unsigned char * const issuer_blob,
	IN const size_t issuer_blob_size,
	IN const unsigned char * const cert_blob,
	IN const size_t cert_blob_size
) {
	__crypto_win32_data_t data = (__crypto_win32_data_t)global_data;
	PCCERT_CONTEXT cert_issuer = NULL;
	PCCERT_CONTEXT cert_cert = NULL;
	PKCS11H_BOOL issuer = FALSE;

	_PKCS11H_ASSERT (global_data!=NULL);
	_PKCS11H_ASSERT (issuer_blob!=NULL);
	_PKCS11H_ASSERT (cert_blob!=NULL);

	if (
		(cert_issuer = data->p_CertCreateCertificateContext (
			PKCS_7_ASN_ENCODING | X509_ASN_ENCODING,
			issuer_blob,
			issuer_blob_size
		)) == NULL ||
		(cert_cert = data->p_CertCreateCertificateContext (
			PKCS_7_ASN_ENCODING | X509_ASN_ENCODING,
			cert_blob,
			cert_blob_size
		)) == NULL
	) {
		goto cleanup;
	}

	if (
		data->p_CryptVerifyCertificateSignatureEx (
			NULL,
			X509_ASN_ENCODING,
			CRYPT_VERIFY_CERT_SIGN_SUBJECT_CERT,
			(void *)cert_cert,
			CRYPT_VERIFY_CERT_SIGN_ISSUER_CERT,
			(void *)cert_issuer,
			0,
			NULL
		)
	) {
		issuer = TRUE;
	}

cleanup:

	if (cert_issuer != NULL) {
		data->p_CertFreeCertificateContext (cert_issuer);
		cert_issuer = NULL;
	}

	if (cert_cert != NULL) {
		data->p_CertFreeCertificateContext (cert_cert);
		cert_cert = NULL;
	}

	return issuer != FALSE;
}

static struct __crypto_win32_data_s s_win32_data = { NULL };
static const pkcs11h_engine_crypto_t _g_pkcs11h_crypto_engine_win32 = {
	&s_win32_data,
	__pkcs11h_crypto_win32_initialize,
	__pkcs11h_crypto_win32_uninitialize,
	__pkcs11h_crypto_win32_certificate_get_expiration,
	__pkcs11h_crypto_win32_certificate_get_dn,
	__pkcs11h_crypto_win32_certificate_is_issuer
};

#endif				/* ENABLE_PKCS11H_ENGINE_WIN32 */

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
#if defined(ENABLE_PKCS11H_ENGINE_WIN32)
		_engine = &_g_pkcs11h_crypto_engine_win32;
#elif defined(ENABLE_PKCS11H_ENGINE_OPENSSL)
		_engine = &_g_pkcs11h_crypto_engine_openssl;
#elif defined(ENABLE_PKCS11H_ENGINE_NSS)
		_engine = &_g_pkcs11h_crypto_engine_nss;
#elif defined(ENABLE_PKCS11H_ENGINE_GNUTLS)
		_engine = &_g_pkcs11h_crypto_engine_gnutls;
#else
		rv = CKR_ATTRIBUTE_VALUE_INVALID;
		goto cleanup;
#endif
	}
	else if (engine ==  PKCS11H_ENGINE_CRYPTO_GPL) {
#if defined(_WIN32)
#if defined(ENABLE_PKCS11H_ENGINE_WIN32)
		_engine = &_g_pkcs11h_crypto_engine_win32;
#elif defined(ENABLE_PKCS11H_ENGINE_GNUTLS)
		_engine = &_g_pkcs11h_crypto_engine_gnutls;
#else
		rv = CKR_ATTRIBUTE_VALUE_INVALID;
		goto cleanup;
#endif
#else
#if defined(ENABLE_PKCS11H_ENGINE_GNUTLS)
		_engine = &_g_pkcs11h_crypto_engine_gnutls;
#else
		rv = CKR_ATTRIBUTE_VALUE_INVALID;
		goto cleanup;
#endif
#endif
	}
	else if (engine == PKCS11H_ENGINE_CRYPTO_WIN32) {
#if defined(ENABLE_PKCS11H_ENGINE_WIN32)
		_engine = &_g_pkcs11h_crypto_engine_win32;
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
	else {
		_engine = engine;
	}

	memmove (&_g_pkcs11h_crypto_engine, _engine, sizeof (pkcs11h_engine_crypto_t));

	rv = CKR_OK;

cleanup:

	return rv;
}

