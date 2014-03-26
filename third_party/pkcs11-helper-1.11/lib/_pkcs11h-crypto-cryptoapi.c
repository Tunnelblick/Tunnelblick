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

#include "_pkcs11h-sys.h"
#include "_pkcs11h-crypto.h"

#if defined(ENABLE_PKCS11H_ENGINE_CRYPTOAPI)
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

typedef struct __crypto_cryptoapi_data_s {
	HMODULE handle;
	__CertCreateCertificateContext_t p_CertCreateCertificateContext;
	__CertFreeCertificateContext_t p_CertFreeCertificateContext;
	CertNameToStrW_t p_CertNameToStrW;
	__CryptVerifyCertificateSignatureEx_t p_CryptVerifyCertificateSignatureEx;
} *__crypto_cryptoapi_data_t;

static
int
__pkcs11h_crypto_cryptoapi_uninitialize (
	IN void * const global_data
) {
	__crypto_cryptoapi_data_t data = (__crypto_cryptoapi_data_t)global_data;

	_PKCS11H_ASSERT (global_data!=NULL);

	if (data->handle != NULL) {
		FreeLibrary (data->handle);
		data->handle = NULL;
	}

	memset (data, 0, sizeof (struct __crypto_cryptoapi_data_s));

	return 1;
}

static
int
__pkcs11h_crypto_cryptoapi_initialize (
	IN void * const global_data
) {
	__crypto_cryptoapi_data_t data = (__crypto_cryptoapi_data_t)global_data;

	_PKCS11H_ASSERT (global_data!=NULL);

	__pkcs11h_crypto_cryptoapi_uninitialize (data);

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
		__pkcs11h_crypto_cryptoapi_uninitialize (data);
		return 0;
	}

	return 1;
}

static
int
__pkcs11h_crypto_cryptoapi_certificate_get_expiration (
	IN void * const global_data,
	IN const unsigned char * const blob,
	IN const size_t blob_size,
	OUT time_t * const expiration
) {
	__crypto_cryptoapi_data_t data = (__crypto_cryptoapi_data_t)global_data;
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
__pkcs11h_crypto_cryptoapi_certificate_get_dn (
	IN void * const global_data,
	IN const unsigned char * const blob,
	IN const size_t blob_size,
	OUT char * const dn,
	IN const size_t dn_max
) {
	__crypto_cryptoapi_data_t data = (__crypto_cryptoapi_data_t)global_data;
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
__pkcs11h_crypto_cryptoapi_certificate_is_issuer (
	IN void * const global_data,
	IN const unsigned char * const issuer_blob,
	IN const size_t issuer_blob_size,
	IN const unsigned char * const cert_blob,
	IN const size_t cert_blob_size
) {
	__crypto_cryptoapi_data_t data = (__crypto_cryptoapi_data_t)global_data;
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

static struct __crypto_cryptoapi_data_s s_cryptoapi_data;
const pkcs11h_engine_crypto_t _g_pkcs11h_crypto_engine_cryptoapi = {
	&s_cryptoapi_data,
	__pkcs11h_crypto_cryptoapi_initialize,
	__pkcs11h_crypto_cryptoapi_uninitialize,
	__pkcs11h_crypto_cryptoapi_certificate_get_expiration,
	__pkcs11h_crypto_cryptoapi_certificate_get_dn,
	__pkcs11h_crypto_cryptoapi_certificate_is_issuer
};

#endif				/* ENABLE_PKCS11H_ENGINE_CRYPTOAPI */
