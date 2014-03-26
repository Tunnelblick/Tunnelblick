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

#if defined(ENABLE_PKCS11H_ENGINE_NSS)
#define _PKCS11T_H_ /* required so no conflict with ours */
#include <nss.h>
#include <cert.h>

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
const pkcs11h_engine_crypto_t _g_pkcs11h_crypto_engine_nss = {
	&s_nss_data,
	__pkcs11h_crypto_nss_initialize,
	__pkcs11h_crypto_nss_uninitialize,
	__pkcs11h_crypto_nss_certificate_get_expiration,
	__pkcs11h_crypto_nss_certificate_get_dn,
	__pkcs11h_crypto_nss_certificate_is_issuer
};

#endif				/* ENABLE_PKCS11H_ENGINE_NSS */
