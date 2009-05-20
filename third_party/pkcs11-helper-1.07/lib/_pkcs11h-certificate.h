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

#ifndef ___PKCS11H_CERTIFICATE_H
#define ___PKCS11H_CERTIFICATE_H

#include "common.h"

#if defined(ENABLE_PKCS11H_CERTIFICATE)

#include "_pkcs11h-core.h"
#include <pkcs11-helper-1.0/pkcs11h-certificate.h>

struct pkcs11h_certificate_s {

	pkcs11h_certificate_id_t id;
	int pin_cache_period;

	unsigned mask_private_mode;

	_pkcs11h_session_t session;
	CK_OBJECT_HANDLE key_handle;

	PKCS11H_BOOL operation_active;

#if defined(ENABLE_PKCS11H_THREADING)
	_pkcs11h_mutex_t mutex;
#endif

	unsigned mask_prompt;
	void * user_data;
};

PKCS11H_BOOL
_pkcs11h_certificate_isBetterCertificate (
	IN const unsigned char * const current,
	IN const size_t current_size,
	IN const unsigned char * const newone,
	IN const size_t newone_size
);

CK_RV
_pkcs11h_certificate_newCertificateId (
	OUT pkcs11h_certificate_id_t * const certificate_id
);

CK_RV
_pkcs11h_certificate_validateSession (
	IN const pkcs11h_certificate_t certificate
);

CK_RV
_pkcs11h_certificate_resetSession (
	IN const pkcs11h_certificate_t certificate,
	IN const PKCS11H_BOOL public_only,
	IN const PKCS11H_BOOL session_mutex_locked
);

CK_RV
_pkcs11h_certificate_enumSessionCertificates (
	IN const _pkcs11h_session_t session,
	IN void * const user_data,
	IN const unsigned mask_prompt
);

#endif				/* ENABLE_PKCS11H_CERTIFICATE */

#endif				/* ___PKCS11H_CERTIFICATE_H */

