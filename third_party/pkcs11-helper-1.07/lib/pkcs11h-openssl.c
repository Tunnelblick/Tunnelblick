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

#if defined(ENABLE_PKCS11H_OPENSSL)

#include <pkcs11-helper-1.0/pkcs11h-openssl.h>
#include "_pkcs11h-core.h"
#include "_pkcs11h-mem.h"

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

struct pkcs11h_openssl_session_s {
	int reference_count;
	PKCS11H_BOOL initialized;
	X509 *x509;
	RSA_METHOD smart_rsa;
	int (*orig_finish)(RSA *rsa);
	pkcs11h_certificate_t certificate;
	pkcs11h_hook_openssl_cleanup_t cleanup_hook;
};

static
int
__pkcs11h_openssl_finish (
	IN OUT RSA *rsa
);
#if OPENSSL_VERSION_NUMBER < 0x00907000L
static
int
__pkcs11h_openssl_dec (
	IN int flen,
	IN unsigned char *from,
	OUT unsigned char *to,
	IN OUT RSA *rsa,
	IN int padding
);
static
int
__pkcs11h_openssl_sign (
	IN int type,
	IN unsigned char *m,
	IN unsigned int m_len,
	OUT unsigned char *sigret,
	OUT unsigned int *siglen,
	IN OUT RSA *rsa
);
#else
static
int
__pkcs11h_openssl_dec (
	IN int flen,
	IN const unsigned char *from,
	OUT unsigned char *to,
	IN OUT RSA *rsa,
	IN int padding
);
static
int
__pkcs11h_openssl_sign (
	IN int type,
	IN const unsigned char *m,
	IN unsigned int m_len,
	OUT unsigned char *sigret,
	OUT unsigned int *siglen,
	IN OUT const RSA *rsa
);
#endif
static
pkcs11h_openssl_session_t
__pkcs11h_openssl_get_openssl_session (
	IN OUT const RSA *rsa
);  

static
pkcs11h_certificate_t
__pkcs11h_openssl_get_pkcs11h_certificate (
	IN OUT const RSA *rsa
);  

static
pkcs11h_openssl_session_t
__pkcs11h_openssl_get_openssl_session (
	IN OUT const RSA *rsa
) {
	pkcs11h_openssl_session_t session;
		
	_PKCS11H_ASSERT (rsa!=NULL);
#if OPENSSL_VERSION_NUMBER < 0x00907000L
	session = (pkcs11h_openssl_session_t)RSA_get_app_data ((RSA *)rsa);
#else
	session = (pkcs11h_openssl_session_t)RSA_get_app_data (rsa);
#endif
	_PKCS11H_ASSERT (session!=NULL);

	return session;
}

static
pkcs11h_certificate_t
__pkcs11h_openssl_get_pkcs11h_certificate (
	IN OUT const RSA *rsa
) {
	pkcs11h_openssl_session_t session = __pkcs11h_openssl_get_openssl_session (rsa);
	
	_PKCS11H_ASSERT (session!=NULL);
	_PKCS11H_ASSERT (session->certificate!=NULL);

	return session->certificate;
}

#if OPENSSL_VERSION_NUMBER < 0x00907000L
static
int
__pkcs11h_openssl_dec (
	IN int flen,
	IN unsigned char *from,
	OUT unsigned char *to,
	IN OUT RSA *rsa,
	IN int padding
) {
#else
static
int
__pkcs11h_openssl_dec (
	IN int flen,
	IN const unsigned char *from,
	OUT unsigned char *to,
	IN OUT RSA *rsa,
	IN int padding
) {
#endif
	pkcs11h_certificate_t certificate = __pkcs11h_openssl_get_pkcs11h_certificate (rsa);
	PKCS11H_BOOL session_locked = FALSE;
	CK_MECHANISM_TYPE mech = CKM_RSA_PKCS;
	CK_RV rv = CKR_FUNCTION_FAILED;
	size_t tlen = (size_t)flen;

	_PKCS11H_ASSERT (from!=NULL);
	_PKCS11H_ASSERT (to!=NULL);
	_PKCS11H_ASSERT (rsa!=NULL);

	_PKCS11H_DEBUG (
		PKCS11H_LOG_DEBUG2,
		"PKCS#11: __pkcs11h_openssl_dec entered - flen=%d, from=%p, to=%p, rsa=%p, padding=%d",
		flen,
		from,
		to,
		(void *)rsa,
		padding
	);

	switch (padding) {
		case RSA_PKCS1_PADDING:
			mech = CKM_RSA_PKCS;
		break;
		case RSA_PKCS1_OAEP_PADDING:
			mech = CKM_RSA_PKCS_OAEP;
		break;
		case RSA_SSLV23_PADDING:
			rv = CKR_MECHANISM_INVALID;
		break;
		case RSA_NO_PADDING:
			rv = CKR_MECHANISM_INVALID;
		break;
	}

	if ((rv = pkcs11h_certificate_lockSession (certificate)) != CKR_OK) {
		goto cleanup;
	}
	session_locked = TRUE;

	_PKCS11H_DEBUG (
		PKCS11H_LOG_DEBUG1,
		"PKCS#11: Performing decryption"
	);

	if (
		(rv = pkcs11h_certificate_decryptAny (
			certificate,
			mech,
			from,
			flen,
			to,
			&tlen
		)) != CKR_OK
	) {
		_PKCS11H_LOG (PKCS11H_LOG_WARN, "PKCS#11: Cannot perform decryption %ld:'%s'", rv, pkcs11h_getMessage (rv));
		goto cleanup;
	}

	rv = CKR_OK;

cleanup:

	if (session_locked) {
		pkcs11h_certificate_releaseSession (certificate);
		session_locked = FALSE;
	}

	_PKCS11H_DEBUG (
		PKCS11H_LOG_DEBUG2,
		"PKCS#11: __pkcs11h_openssl_dec - return rv=%lu-'%s'",
		rv,
		pkcs11h_getMessage (rv)
	);

	return rv == CKR_OK ? (int)tlen : -1; 
}

#if OPENSSL_VERSION_NUMBER < 0x00907000L
static
int
__pkcs11h_openssl_sign (
	IN int type,
	IN unsigned char *m,
	IN unsigned int m_len,
	OUT unsigned char *sigret,
	OUT unsigned int *siglen,
	IN OUT RSA *rsa
) {
#else
static
int
__pkcs11h_openssl_sign (
	IN int type,
	IN const unsigned char *m,
	IN unsigned int m_len,
	OUT unsigned char *sigret,
	OUT unsigned int *siglen,
	IN OUT const RSA *rsa
) {
#endif
	pkcs11h_certificate_t certificate = __pkcs11h_openssl_get_pkcs11h_certificate (rsa);
	PKCS11H_BOOL session_locked = FALSE;
	CK_RV rv = CKR_FUNCTION_FAILED;

	int myrsa_size = 0;
	size_t size_temp;
	
	unsigned char *enc_alloc = NULL;
	unsigned char *enc = NULL;
	int enc_len = 0;

	_PKCS11H_ASSERT (m!=NULL);
	_PKCS11H_ASSERT (sigret!=NULL);
	_PKCS11H_ASSERT (siglen!=NULL);

	_PKCS11H_DEBUG (
		PKCS11H_LOG_DEBUG2,
		"PKCS#11: __pkcs11h_openssl_sign entered - type=%d, m=%p, m_len=%u, signret=%p, *siglen=%u, rsa=%p",
		type,
		m,
		m_len,
		sigret,
		sigret != NULL ? *siglen : 0,
		(void *)rsa
	);

	myrsa_size = RSA_size (rsa);

	if (type == NID_md5_sha1) {
		enc = (unsigned char *)m;
		enc_len = m_len;
	}
	else {
		X509_SIG sig;
		ASN1_TYPE parameter;
		X509_ALGOR algor;
		ASN1_OCTET_STRING digest;
		unsigned char *p = NULL;

		if ((rv = _pkcs11h_mem_malloc ((void*)&enc, myrsa_size+1)) != CKR_OK) {
			goto cleanup;
		}

		enc_alloc = enc;
		sig.algor = &algor;

		if ((sig.algor->algorithm = OBJ_nid2obj (type)) == NULL) {
			rv = CKR_FUNCTION_FAILED;
			goto cleanup;
		}
	
		if (sig.algor->algorithm->length == 0) {
			rv = CKR_KEY_SIZE_RANGE;
			goto cleanup;
		}
	
		parameter.type = V_ASN1_NULL;
		parameter.value.ptr = NULL;

		sig.algor->parameter = &parameter;

		sig.digest = &digest;
		sig.digest->data = (unsigned char *)m;
		sig.digest->length = m_len;
	
		if ((enc_len=i2d_X509_SIG (&sig, NULL)) < 0) {
			rv = CKR_FUNCTION_FAILED;
			goto cleanup;
		}

		/*
		 * d_X509_SIG increments pointer!
		 */
		p = enc;
		if ((enc_len=i2d_X509_SIG (&sig, &p)) < 0) {
			rv = CKR_FUNCTION_FAILED;
			goto cleanup;
		}
	}

	if (enc_len > (myrsa_size - RSA_PKCS1_PADDING_SIZE)) {
		rv = CKR_KEY_SIZE_RANGE;
		goto cleanup;
	}

	if ((rv = pkcs11h_certificate_lockSession (certificate)) != CKR_OK) {
		goto cleanup;
	}
	session_locked = TRUE;

	_PKCS11H_DEBUG (
		PKCS11H_LOG_DEBUG1,
		"PKCS#11: Performing signature"
	);

	size_temp = myrsa_size;

	if (
		(rv = pkcs11h_certificate_signAny (
			certificate,
			CKM_RSA_PKCS,
			enc,
			enc_len,
			sigret,
			&size_temp
		)) != CKR_OK
	) {
		_PKCS11H_LOG (PKCS11H_LOG_WARN, "PKCS#11: Cannot perform signature %ld:'%s'", rv, pkcs11h_getMessage (rv));
		goto cleanup;
	}

	*siglen = (unsigned int)size_temp;
	rv = CKR_OK;

cleanup:

	if (session_locked) {
		pkcs11h_certificate_releaseSession (certificate);
		session_locked = FALSE;
	}

	if (enc_alloc != NULL) {
		_pkcs11h_mem_free ((void *)&enc_alloc);
	}
	
	_PKCS11H_DEBUG (
		PKCS11H_LOG_DEBUG2,
		"PKCS#11: __pkcs11h_openssl_sign - return rv=%lu-'%s'",
		rv,
		pkcs11h_getMessage (rv)
	);

	return rv == CKR_OK ? 1 : -1; 
}

static
int
__pkcs11h_openssl_finish (
	IN OUT RSA *rsa
) {
	pkcs11h_openssl_session_t openssl_session = __pkcs11h_openssl_get_openssl_session (rsa);

	_PKCS11H_DEBUG (
		PKCS11H_LOG_DEBUG2,
		"PKCS#11: __pkcs11h_openssl_finish - entered rsa=%p",
		(void *)rsa
	);

	RSA_set_app_data (rsa, NULL);
	
	if (openssl_session->orig_finish != NULL) {
		openssl_session->orig_finish (rsa);

#ifdef BROKEN_OPENSSL_ENGINE
		{
			/* We get called TWICE here, once for
			 * releasing the key and also for
			 * releasing the engine.
			 * To prevent endless recursion, FIRST
			 * clear rsa->engine, THEN call engine->finish
			 */
			ENGINE *e = rsa->engine;
			rsa->engine = NULL;
			if (e) {
				ENGINE_finish(e);
			}
		}
#endif
	}

	pkcs11h_openssl_freeSession (openssl_session);

	_PKCS11H_DEBUG (
		PKCS11H_LOG_DEBUG2,
		"PKCS#11: __pkcs11h_openssl_finish - return"
	);
	
	return 1;
}

X509 *
pkcs11h_openssl_getX509 (
	IN const pkcs11h_certificate_t certificate
) {
	unsigned char *certificate_blob = NULL;
	size_t certificate_blob_size = 0;
	X509 *x509 = NULL;
	CK_RV rv = CKR_FUNCTION_FAILED;
	__pkcs11_openssl_d2i_t d2i1 = NULL;

	_PKCS11H_ASSERT (certificate!=NULL);

	_PKCS11H_DEBUG (
		PKCS11H_LOG_DEBUG2,
		"PKCS#11: pkcs11h_openssl_getX509 - entry certificate=%p",
		(void *)certificate
	);

	if ((x509 = X509_new ()) == NULL) {
		_PKCS11H_LOG (PKCS11H_LOG_WARN, "PKCS#11: Unable to allocate certificate object");
		rv = CKR_HOST_MEMORY;
		goto cleanup;
	}

	if (
		(rv = pkcs11h_certificate_getCertificateBlob (
			certificate,
			NULL,
			&certificate_blob_size
		)) != CKR_OK
	) {
		goto cleanup;
	}

	if ((rv = _pkcs11h_mem_malloc ((void *)&certificate_blob, certificate_blob_size)) != CKR_OK) {
		goto cleanup;
	}

	if (
		(rv = pkcs11h_certificate_getCertificateBlob (
			certificate,
			certificate_blob,
			&certificate_blob_size
		)) != CKR_OK
	) {
		goto cleanup;
	}

	d2i1 = (__pkcs11_openssl_d2i_t)certificate_blob;
	if (!d2i_X509 (&x509, &d2i1, certificate_blob_size)) {
		_PKCS11H_LOG (PKCS11H_LOG_WARN, "PKCS#11: Unable to parse X.509 certificate");
		rv = CKR_FUNCTION_FAILED;
		goto cleanup;
	}

	rv = CKR_OK;

cleanup:

	if (rv != CKR_OK) {
		if (x509 != NULL) {
			X509_free (x509);
			x509 = NULL;
		}
	}
	
	_PKCS11H_DEBUG (
		PKCS11H_LOG_DEBUG2,
		"PKCS#11: pkcs11h_openssl_getX509 - return rv=%ld-'%s', x509=%p",
		rv,
		pkcs11h_getMessage (rv),
		(void *)x509
	);

	return x509;
}

pkcs11h_openssl_session_t
pkcs11h_openssl_createSession (
	IN const pkcs11h_certificate_t certificate
) {
	const RSA_METHOD *def;
	pkcs11h_openssl_session_t openssl_session = NULL;
	PKCS11H_BOOL ok = FALSE;

	_PKCS11H_DEBUG (
		PKCS11H_LOG_DEBUG2,
		"PKCS#11: pkcs11h_openssl_createSession - entry"
	);

	OpenSSL_add_all_digests ();

	if (
		_pkcs11h_mem_malloc (
			(void*)&openssl_session,
			sizeof (struct pkcs11h_openssl_session_s)) != CKR_OK
	) {
		_PKCS11H_LOG (PKCS11H_LOG_WARN, "PKCS#11: Cannot allocate memory");
		ok = FALSE;
		goto cleanup;
	}

	def = RSA_get_default_method ();

	memmove (&openssl_session->smart_rsa, def, sizeof(RSA_METHOD));

	openssl_session->orig_finish = def->finish;

	openssl_session->smart_rsa.name = "pkcs11";
	openssl_session->smart_rsa.rsa_priv_dec = __pkcs11h_openssl_dec;
	openssl_session->smart_rsa.rsa_sign = __pkcs11h_openssl_sign;
	openssl_session->smart_rsa.finish = __pkcs11h_openssl_finish;
	openssl_session->smart_rsa.flags  = RSA_METHOD_FLAG_NO_CHECK | RSA_FLAG_EXT_PKEY;
	openssl_session->certificate = certificate;
	openssl_session->reference_count = 1;

	ok = TRUE;

cleanup:

	if (!ok) {
		_pkcs11h_mem_free ((void *)&openssl_session);
	}
	
	_PKCS11H_DEBUG (
		PKCS11H_LOG_DEBUG2,
		"PKCS#11: pkcs11h_openssl_createSession - return openssl_session=%p",
		(void *)openssl_session
	);

	return openssl_session;
}

pkcs11h_hook_openssl_cleanup_t
pkcs11h_openssl_getCleanupHook (
	IN const pkcs11h_openssl_session_t openssl_session
) {
	_PKCS11H_ASSERT (openssl_session!=NULL);

	return openssl_session->cleanup_hook;
}

void
pkcs11h_openssl_setCleanupHook (
	IN const pkcs11h_openssl_session_t openssl_session,
	IN const pkcs11h_hook_openssl_cleanup_t cleanup
) {
	_PKCS11H_ASSERT (openssl_session!=NULL);

	openssl_session->cleanup_hook = cleanup;
}

void
pkcs11h_openssl_freeSession (
	IN const pkcs11h_openssl_session_t openssl_session
) {
	_PKCS11H_ASSERT (openssl_session!=NULL);
	_PKCS11H_ASSERT (openssl_session->reference_count>0);
	
	_PKCS11H_DEBUG (
		PKCS11H_LOG_DEBUG2,
		"PKCS#11: pkcs11h_openssl_freeSession - entry openssl_session=%p, count=%d",
		(void *)openssl_session,
		openssl_session->reference_count
	);

	openssl_session->reference_count--;
	
	if (openssl_session->reference_count == 0) {
		if (openssl_session->cleanup_hook != NULL) {
			openssl_session->cleanup_hook (openssl_session->certificate);
		}

		if (openssl_session->x509 != NULL) {
			X509_free (openssl_session->x509);
			openssl_session->x509 = NULL;
		}
		if (openssl_session->certificate != NULL) {
			pkcs11h_certificate_freeCertificate (openssl_session->certificate);
			openssl_session->certificate = NULL;
		}
		
		_pkcs11h_mem_free ((void *)&openssl_session);
	}

	_PKCS11H_DEBUG (
		PKCS11H_LOG_DEBUG2,
		"PKCS#11: pkcs11h_openssl_freeSession - return"
	);
}

RSA *
pkcs11h_openssl_session_getRSA (
	IN const pkcs11h_openssl_session_t openssl_session
) {
	X509 *x509 = NULL;
	RSA *rsa = NULL;
	EVP_PKEY *pubkey = NULL;
	PKCS11H_BOOL ok = FALSE;

	_PKCS11H_ASSERT (openssl_session!=NULL);
	_PKCS11H_ASSERT (!openssl_session->initialized);
	_PKCS11H_ASSERT (openssl_session!=NULL);

	_PKCS11H_DEBUG (
		PKCS11H_LOG_DEBUG2,
		"PKCS#11: pkcs11h_openssl_session_getRSA - entry openssl_session=%p",
		(void *)openssl_session
	);
	
	/*
	 * Dup x509 so RSA will not hold session x509
	 */
	if ((x509 = pkcs11h_openssl_session_getX509 (openssl_session)) == NULL) {
		_PKCS11H_LOG (PKCS11H_LOG_WARN, "PKCS#11: Cannot get certificate object");
		goto cleanup;
	}

	if ((pubkey = X509_get_pubkey (x509)) == NULL) {
		_PKCS11H_LOG (PKCS11H_LOG_WARN, "PKCS#11: Cannot get public key");
		goto cleanup;
	}
	
	if (pubkey->type != EVP_PKEY_RSA) {
		_PKCS11H_LOG (PKCS11H_LOG_WARN, "PKCS#11: Invalid public key algorithm");
		goto cleanup;
	}

	if (
		(rsa = EVP_PKEY_get1_RSA (pubkey)) == NULL
	) {
		_PKCS11H_LOG (PKCS11H_LOG_WARN, "PKCS#11: Cannot get RSA key");
		goto cleanup;
	}

	RSA_set_method (rsa, &openssl_session->smart_rsa);
	RSA_set_app_data (rsa, openssl_session);
	openssl_session->reference_count++;
	
#ifdef BROKEN_OPENSSL_ENGINE
	if (!rsa->engine) {
		rsa->engine = ENGINE_get_default_RSA ();
	}

	ENGINE_set_RSA(ENGINE_get_default_RSA (), &openssl_session->smart_rsa);
	_PKCS11H_LOG (PKCS11H_LOG_WARN, "PKCS#11: OpenSSL engine support is broken! Workaround enabled");
#endif
		
	rsa->flags |= RSA_FLAG_SIGN_VER;
	openssl_session->initialized = TRUE;

	ok = TRUE;

cleanup:

	if (!ok) {
		if (rsa != NULL) {
			RSA_free (rsa);
			rsa = NULL;
		}
	}

	/*
	 * openssl objects have reference
	 * count, so release them
	 */
	if (pubkey != NULL) {
		EVP_PKEY_free (pubkey);
		pubkey = NULL;
	}

	if (x509 != NULL) {
		X509_free (x509);
		x509 = NULL;
	}
	
	_PKCS11H_DEBUG (
		PKCS11H_LOG_DEBUG2,
		"PKCS#11: pkcs11h_openssl_session_getRSA - return rsa=%p",
		(void *)rsa
	);

	return rsa;
}

X509 *
pkcs11h_openssl_session_getX509 (
	IN const pkcs11h_openssl_session_t openssl_session
) {
	X509 *x509 = NULL;
	PKCS11H_BOOL ok = FALSE;
	
	_PKCS11H_ASSERT (openssl_session!=NULL);

	_PKCS11H_DEBUG (
		PKCS11H_LOG_DEBUG2,
		"PKCS#11: pkcs11h_openssl_session_getX509 - entry openssl_session=%p",
		(void *)openssl_session
	);

	if (
		openssl_session->x509 == NULL &&
		(openssl_session->x509 = pkcs11h_openssl_getX509 (openssl_session->certificate)) == NULL
	) {	
		_PKCS11H_LOG (PKCS11H_LOG_WARN, "PKCS#11: Cannot get certificate object");
		goto cleanup;
	}

	if ((x509 = X509_dup (openssl_session->x509)) == NULL) {
		_PKCS11H_LOG (PKCS11H_LOG_WARN, "PKCS#11: Cannot duplicate certificate object");
		goto cleanup;
	}

	ok = TRUE;

cleanup:

	if (!ok) {
		if (x509 != NULL) {
			X509_free (x509);
			x509 = NULL;
		}
	}
	
	_PKCS11H_DEBUG (
		PKCS11H_LOG_DEBUG2,
		"PKCS#11: pkcs11h_openssl_session_getX509 - return x509=%p",
		(void *)x509
	);

	return x509;
}

#endif				/* ENABLE_PKCS11H_OPENSSL */

