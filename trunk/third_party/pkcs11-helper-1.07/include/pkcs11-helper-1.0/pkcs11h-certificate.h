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
 * @addtogroup pkcs11h_certificate Certificate interface
 *
 * X.509 certificate interface, provides signature and decryption.
 *
 * @{
 */

/**
 * @file pkcs11h-certificate.h
 * @brief pkcs11-helper certificate functions.
 * @author Alon Bar-Lev <alon.barlev@gmail.com>
 * @see pkcs11h_certificate.
 */

/**
 * @example test-certificate.c
 * 
 * The following example shows some basic usage of the certificate interface.
 */

#ifndef __PKCS11H_CERTIFICATE_H
#define __PKCS11H_CERTIFICATE_H

#include <pkcs11-helper-1.0/pkcs11h-core.h>

#if defined(__cplusplus)
extern "C" {
#endif

struct pkcs11h_certificate_id_s;
struct pkcs11h_certificate_s;

/**
 * @brief Certificate id reference.
 */
typedef struct pkcs11h_certificate_id_s *pkcs11h_certificate_id_t;

/**
 * @brief Certificate object.
 */
typedef struct pkcs11h_certificate_s *pkcs11h_certificate_t;

struct pkcs11h_certificate_id_list_s;

/**
 * @brief Certificate id list.
 */
typedef struct pkcs11h_certificate_id_list_s *pkcs11h_certificate_id_list_t;

/**
 * @brief Certificate id reference
 */
struct pkcs11h_certificate_id_s {
	/** Token id */
	pkcs11h_token_id_t token_id;

	/** displayName for users */
	char displayName[1024];
	/** CKA_ID of object */
	CK_BYTE_PTR attrCKA_ID;
	/** CKA_ID size */
	size_t attrCKA_ID_size;

	/** Certificate blob (if available) */
	unsigned char *certificate_blob;
	/** Certificate blob size */
	size_t certificate_blob_size;
};

/**
 * @brief Certificate id list
 */
struct pkcs11h_certificate_id_list_s {
	/** Next element */
	pkcs11h_certificate_id_list_t next;
	/** Certificate id */
	pkcs11h_certificate_id_t certificate_id;
};

/**
 * @brief Free certificate_id object.
 * @param certificate_id	Certificate id.
 * @return CK_RV.
 */
CK_RV
pkcs11h_certificate_freeCertificateId (
	IN pkcs11h_certificate_id_t certificate_id
);

/**
 * @brief Duplicate certificate_id object.
 * @param to	Target.
 * @param from	Source.
 * @return CK_RV.
 * @note Caller must free result.
 * @see pkcs11h_certificate_freeCertificateId().
 */
CK_RV
pkcs11h_certificate_duplicateCertificateId (
	OUT pkcs11h_certificate_id_t * const to,
	IN const pkcs11h_certificate_id_t from
);

/**
 * @brief Sets internal certificate_id blob.
 * @param certificate_id	Certificate id object.
 * @param blob			Certificate blob.
 * @param blob_size		Certificate blob size.
 * @return CK_RV.
 * @remarks
 * Useful to set after deserialization so certificate is available and not read from token.
 */
CK_RV
pkcs11h_certificate_setCertificateIdCertificateBlob (
	IN const pkcs11h_certificate_id_t certificate_id,
	IN const unsigned char * const blob,
	IN const size_t blob_size
);

/**
 * @brief Free certificate object.
 * @param certificate	Certificate object.
 * @return CK_RV.
 */
CK_RV
pkcs11h_certificate_freeCertificate (
	IN pkcs11h_certificate_t certificate
);

/**
 * @brief Create a certificate object out of certificate_id.
 * @param certificate_id	Certificate id object to be based on.
 * @param user_data		Optional user data, to be passed to hooks.
 * @param mask_prompt		Allow prompt @ref PKCS11H_PROMPT_MASK.
 * @param pin_cache_period	Session specific cache period.
 * @param p_certificate		Receives certificate object.
 * @note Caller must free result.
 * @see pkcs11h_certificate_freeCertificate().
 * @remarks
 * The certificate id object may not specify the certificate blob.
 */	
CK_RV
pkcs11h_certificate_create (
	IN const pkcs11h_certificate_id_t certificate_id,
	IN void * const user_data,
	IN const unsigned mask_prompt,
	IN const int pin_cache_period,
	OUT pkcs11h_certificate_t * const p_certificate
);

/**
 * @brief Extract user data out of certificate.
 * @param certificate	Certificate object.
 * @return Mask prompt @ref PKCS11H_PROMPT_MASK.
 */
unsigned
pkcs11h_certificate_getPromptMask (
	IN const pkcs11h_certificate_t certificate
);

/**
 * @brief Extract user data out of certificate.
 * @param certificate	Certificate object.
 * @param mask_prompt	Allow prompt @ref PKCS11H_PROMPT_MASK.
 */
void
pkcs11h_certificate_setPromptMask (
	IN const pkcs11h_certificate_t certificate,
	IN const unsigned mask_prompt
);

/**
 * @brief Extract user data out of certificate.
 * @param certificate	Certificate object.
 * @return User data.
 */
void *
pkcs11h_certificate_getUserData (
	IN const pkcs11h_certificate_t certificate
);

/**
 * @brief Extract user data out of certificate.
 * @param certificate	Certificate object.
 * @param user_data	Optional user data, to be passed to hooks.
 */
void
pkcs11h_certificate_setUserData (
	IN const pkcs11h_certificate_t certificate,
	IN void * const user_data
);

/**
 * @brief Get certifiate id object out of a certifiate.
 * @param certificate		Certificate object.
 * @param p_certificate_id	Certificate id object pointer.
 * @return CK_RV.
 * @note Caller must free result.
 * @see pkcs11h_certificate_freeCertificateId().
 */
CK_RV
pkcs11h_certificate_getCertificateId (
	IN const pkcs11h_certificate_t certificate,
	OUT pkcs11h_certificate_id_t * const p_certificate_id
);

/**
 * @brief Get the certificate blob out of the certificate object.
 * @param certificate			Certificate object.
 * @param certificate_blob		Buffer.
 * @param p_certificate_blob_size	Buffer size.
 * @return CK_RV.
 * @note certificate_blob may be NULL in order to get size.
 */
CK_RV
pkcs11h_certificate_getCertificateBlob (
	IN const pkcs11h_certificate_t certificate,
	OUT unsigned char * const certificate_blob,
	IN OUT size_t * const p_certificate_blob_size
);

/**
 * @brief Serialize certificate_id into a string
 * @param sz			Output string.
 * @param max			Max buffer size.
 * @param certificate_id	id to serialize
 * @return CK_RV.
 * @note sz may be NULL in order to get size.
 */
CK_RV
pkcs11h_certificate_serializeCertificateId (
	OUT char * const sz,
	IN OUT size_t *max,
	IN const pkcs11h_certificate_id_t certificate_id
);

/**
 * @brief Deserialize certificate_id out of string.
 * @param p_certificate_id	id.
 * @param sz			Inut string
 * @return CK_RV.
 * @note Caller must free result.
 * @see pkcs11h_certificate_freeCertificateId().
 */
CK_RV
pkcs11h_certificate_deserializeCertificateId (
	OUT pkcs11h_certificate_id_t * const p_certificate_id,
	IN const char * const sz
);

/**
 * @brief Ensure certificate is accessible.
 * @param certificate		Certificate object.
 * @return CK_RV.
 */
CK_RV
pkcs11h_certificate_ensureCertificateAccess (
	IN const pkcs11h_certificate_t certificate
);

/**
 * @brief Ensure key is accessible.
 * @param certificate		Certificate object.
 * @return CK_RV.
 */
CK_RV
pkcs11h_certificate_ensureKeyAccess (
	IN const pkcs11h_certificate_t certificate
);

/**
 * @brief Lock session for threded environment.
 * @param certificate		Certificate object.
 * @return CK_RV.
 * @remarks
 * This must be called on threaded environment, so both calls to _sign and
 * _signRecover and _decrypt will be from the same source.
 * Failing to lock session, will result with CKR_OPERATION_ACTIVE if
 * provider is good, or unexpected behaviour for others.
 * @remarks
 * It is save to call this also in none threaded environment, it will do nothing.
 * Call this also if you are doing one stage operation, since locking is not
 * done by method.
 */
CK_RV
pkcs11h_certificate_lockSession (
	IN const pkcs11h_certificate_t certificate
);

/**
 * @brief Releases session lock.
 * @param certificate		Certificate object.
 * @return CK_RV.
 * @see pkcs11h_certificate_lockSession().
 */
CK_RV
pkcs11h_certificate_releaseSession (
	IN const pkcs11h_certificate_t certificate
);

/**
 * @brief Sign data.
 * @param certificate		Certificate object.
 * @param mech_type		PKCS#11 mechanism.
 * @param source		Buffer to sign.
 * @param source_size		Buffer size.
 * @param target		Target buffer.
 * @param p_target_size		Target buffer size.
 * @return CK_RV.
 * @note target may be NULL to get size.
 * @attention When using in threaded environment session must be locked.
 * @see pkcs11h_certificate_lockSession().
 * @see pkcs11h_certificate_signAny().
 */
CK_RV
pkcs11h_certificate_sign (
	IN const pkcs11h_certificate_t certificate,
	IN const CK_MECHANISM_TYPE mech_type,
	IN const unsigned char * const source,
	IN const size_t source_size,
	OUT unsigned char * const target,
	IN OUT size_t * const p_target_size
);

/**
 * @brief Sign data.
 * @param certificate		Certificate object.
 * @param mech_type		PKCS#11 mechanism.
 * @param source		Buffer to sign.
 * @param source_size		Buffer size.
 * @param target		Target buffer.
 * @param p_target_size		Target buffer size.
 * @return CK_RV.
 * @note target may be NULL to get size.
 * @attention When using in threaded environment session must be locked.
 * @see pkcs11h_certificate_lockSession().
 * @see pkcs11h_certificate_signAny().
 */
CK_RV
pkcs11h_certificate_signRecover (
	IN const pkcs11h_certificate_t certificate,
	IN const CK_MECHANISM_TYPE mech_type,
	IN const unsigned char * const source,
	IN const size_t source_size,
	OUT unsigned char * const target,
	IN OUT size_t * const p_target_size
);

/**
 * @brief Decrypt data.
 * @param certificate		Certificate object.
 * @param mech_type		PKCS#11 mechanism.
 * @param source		Buffer to sign.
 * @param source_size		Buffer size.
 * @param target		Target buffer.
 * @param p_target_size		Target buffer size.
 * @return CK_RV.
 * @note target may be NULL to get size.
 * @attention When using in threaded environment session must be locked.
 * @see pkcs11h_certificate_lockSession().
 */
CK_RV
pkcs11h_certificate_decrypt (
	IN const pkcs11h_certificate_t certificate,
	IN const CK_MECHANISM_TYPE mech_type,
	IN const unsigned char * const source,
	IN const size_t source_size,
	OUT unsigned char * const target,
	IN OUT size_t * const p_target_size
);

/**
 * @brief Decrypt data.
 * @param certificate		Certificate object.
 * @param mech_type		PKCS#11 mechanism.
 * @param source		Buffer to sign.
 * @param source_size		Buffer size.
 * @param target		Target buffer.
 * @param p_target_size		Target buffer size.
 * @return CK_RV.
 * @note target may be NULL to get size.
 * @attention When using in threaded environment session must be locked.
 * @see pkcs11h_certificate_lockSession().
 */
CK_RV
pkcs11h_certificate_unwrap (
	IN const pkcs11h_certificate_t certificate,
	IN const CK_MECHANISM_TYPE mech_type,
	IN const unsigned char * const source,
	IN const size_t source_size,
	OUT unsigned char * const target,
	IN OUT size_t * const p_target_size
);

/**
 * @brief Sign data mechanism determined by key attributes.
 * @param certificate		Certificate object.
 * @param mech_type		PKCS#11 mechanism.
 * @param source		Buffer to sign.
 * @param source_size		Buffer size.
 * @param target		Target buffer.
 * @param p_target_size		Target buffer size.
 * @return CK_RV.
 * @note target may be NULL to get size.
 * @attention When using in threaded environment session must be locked.
 * @see pkcs11h_certificate_lockSession().
 */
CK_RV
pkcs11h_certificate_signAny (
	IN const pkcs11h_certificate_t certificate,
	IN const CK_MECHANISM_TYPE mech_type,
	IN const unsigned char * const source,
	IN const size_t source_size,
	OUT unsigned char * const target,
	IN OUT size_t * const p_target_size
);

/**
 * @brief Decrypt data mechanism determined by key attributes.
 * @param certificate		Certificate object.
 * @param mech_type		PKCS#11 mechanism.
 * @param source		Buffer to sign.
 * @param source_size		Buffer size.
 * @param target		Target buffer.
 * @param p_target_size		Target buffer size.
 * @return CK_RV.
 * @note target may be NULL to get size.
 * @attention When using in threaded environment session must be locked.
 * @see pkcs11h_certificate_lockSession().
 */
CK_RV
pkcs11h_certificate_decryptAny (
	IN const pkcs11h_certificate_t certificate,
	IN const CK_MECHANISM_TYPE mech_type,
	IN const unsigned char * const source,
	IN const size_t source_size,
	OUT unsigned char * const target,
	IN OUT size_t * const p_target_size
);

/**
 * @brief Free certificate_id list.
 * @param cert_id_list		List.
 * @return CK_RV.
 */
CK_RV
pkcs11h_certificate_freeCertificateIdList (
	IN const pkcs11h_certificate_id_list_t cert_id_list
);

/**
 * @brief Enumerate available certificates on specific token
 * @param token_id			Token id to enum.
 * @param method			How to fetch certificates @ref PKCS11H_ENUM_METHOD.
 * @param user_data			Some user specific data.
 * @param mask_prompt			Allow prompt @ref PKCS11H_PROMPT_MASK.
 * @param p_cert_id_issuers_list	Receives issues list.
 * @param p_cert_id_end_list		Receives end certificates list.
 * @return CK_RV.
 * @note p_cert_id_issuers_list may be NULL.
 * @note Caller must free result.
 * @note This function will likely take long time.
 * @see pkcs11h_certificate_freeCertificateIdList().
 */
CK_RV
pkcs11h_certificate_enumTokenCertificateIds (
	IN const pkcs11h_token_id_t token_id,
	IN const unsigned method,
	IN void * const user_data,
	IN const unsigned mask_prompt,
	OUT pkcs11h_certificate_id_list_t * const p_cert_id_issuers_list,
	OUT pkcs11h_certificate_id_list_t * const p_cert_id_end_list
);

/**
 * @brief Enumerate available certificates.
 * @param method			How to fetch certificates @ref PKCS11H_ENUM_METHOD.
 * @param user_data			Some user specific data.
 * @param mask_prompt			Allow prompt @ref PKCS11H_PROMPT_MASK.
 * @param p_cert_id_issuers_list	Receives issues list.
 * @param p_cert_id_end_list		Receives end certificates list.
 * @note p_cert_id_issuers_list may be NULL.
 * @note Caller must free result.
 * @note This function will likely take long time.
 * @see pkcs11h_certificate_freeCertificateIdList().
 */
CK_RV
pkcs11h_certificate_enumCertificateIds (
	IN const unsigned method,
	IN void * const user_data,
	IN const unsigned mask_prompt,
	OUT pkcs11h_certificate_id_list_t * const p_cert_id_issuers_list,
	OUT pkcs11h_certificate_id_list_t * const p_cert_id_end_list
);

#ifdef __cplusplus
}
#endif

/** @} */

#endif				/* __PKCS11H_CERTIFICATE_H */
