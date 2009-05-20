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

#include <pkcs11-helper-1.0/pkcs11h-data.h>
#include "_pkcs11h-mem.h"
#include "_pkcs11h-session.h"

#if defined(ENABLE_PKCS11H_DATA)

static
CK_RV
_pkcs11h_data_getObject (
	IN const _pkcs11h_session_t session,
	IN const char * const application,
	IN const char * const label,
	OUT CK_OBJECT_HANDLE * const p_handle
) {
	CK_OBJECT_CLASS class = CKO_DATA;
	CK_ATTRIBUTE filter[] = {
		{CKA_CLASS, (void *)&class, sizeof (class)},
		{CKA_APPLICATION, (void *)application, application == NULL ? 0 : strlen (application)},
		{CKA_LABEL, (void *)label, label == NULL ? 0 : strlen (label)}
	};
	CK_OBJECT_HANDLE *objects = NULL;
	CK_ULONG objects_found = 0;
	CK_RV rv = CKR_FUNCTION_FAILED;
	
	_PKCS11H_ASSERT (session!=NULL);
	_PKCS11H_ASSERT (application!=NULL);
	_PKCS11H_ASSERT (label!=NULL);

	_PKCS11H_DEBUG (
		PKCS11H_LOG_DEBUG2,
		"PKCS#11: _pkcs11h_data_getObject entry session=%p, application='%s', label='%s', p_handle=%p",
		(void *)session,
		application,
		label,
		(void *)p_handle
	);

	*p_handle = _PKCS11H_INVALID_OBJECT_HANDLE;

	if ((rv = _pkcs11h_session_validate (session)) != CKR_OK) {
		goto cleanup;
	}

	if (
		(rv = _pkcs11h_session_findObjects (
			session,
			filter,
			sizeof (filter) / sizeof (CK_ATTRIBUTE),
			&objects,
			&objects_found
		)) != CKR_OK
	) {
		goto cleanup;
	}

	if (objects_found == 0) {
		rv = CKR_FUNCTION_REJECTED;
		goto cleanup;
	}

	*p_handle = objects[0];
	rv = CKR_OK;

cleanup:

	if (objects != NULL) {
		_pkcs11h_mem_free ((void *)&objects);
	}

	_PKCS11H_DEBUG (
		PKCS11H_LOG_DEBUG2,
		"PKCS#11: _pkcs11h_data_getObject return rv=%lu-'%s', *p_handle=%08lx",
		rv,
		pkcs11h_getMessage (rv),
		(unsigned long)*p_handle
	);

	return rv;
}

CK_RV
pkcs11h_data_get (
	IN const pkcs11h_token_id_t token_id,
	IN const PKCS11H_BOOL is_public,
	IN const char * const application,
	IN const char * const label,
	IN void * const user_data,
	IN const unsigned mask_prompt,
	OUT unsigned char * const blob,
	IN OUT size_t * const p_blob_size
) {
	CK_ATTRIBUTE attrs[] = {
		{CKA_VALUE, NULL, 0}
	};
	CK_OBJECT_HANDLE handle = _PKCS11H_INVALID_OBJECT_HANDLE;
	CK_RV rv = CKR_FUNCTION_FAILED;

#if defined(ENABLE_PKCS11H_THREADING)
	PKCS11H_BOOL mutex_locked = FALSE;
#endif
	_pkcs11h_session_t session = NULL;
	PKCS11H_BOOL op_succeed = FALSE;
	PKCS11H_BOOL login_retry = FALSE;
	size_t blob_size_max = 0;

	_PKCS11H_ASSERT (_g_pkcs11h_data!=NULL);
	_PKCS11H_ASSERT (_g_pkcs11h_data->initialized);
	_PKCS11H_ASSERT (token_id!=NULL);
	_PKCS11H_ASSERT (application!=NULL);
	_PKCS11H_ASSERT (label!=NULL);
	/*_PKCS11H_ASSERT (user_data) NOT NEEDED */
	/*_PKCS11H_ASSERT (blob!=NULL); NOT NEEDED*/
	_PKCS11H_ASSERT (p_blob_size!=NULL);

	_PKCS11H_DEBUG (
		PKCS11H_LOG_DEBUG2,
		"PKCS#11: pkcs11h_data_get entry token_id=%p, application='%s', label='%s', user_data=%p, mask_prompt=%08x, blob=%p, *p_blob_size="P_Z"",
		(void *)token_id,
		application,
		label,
		user_data,
		mask_prompt,
		blob,
		blob != NULL ? *p_blob_size : 0
	);

	if (blob != NULL) {
		blob_size_max = *p_blob_size;
	}
	*p_blob_size = 0;

	if (
		(rv = _pkcs11h_session_getSessionByTokenId (
			token_id,
			&session
		)) != CKR_OK
	) {
		goto cleanup;
	}

#if defined(ENABLE_PKCS11H_THREADING)
	if ((rv = _pkcs11h_threading_mutexLock (&session->mutex)) != CKR_OK) {
		goto cleanup;
	}
	mutex_locked = TRUE;
#endif

	while (!op_succeed) {
		if (
			(rv = _pkcs11h_session_validate (session)) != CKR_OK ||
			(rv = _pkcs11h_data_getObject (
				session,
				application,
				label,
				&handle
			)) != CKR_OK ||
			(rv = _pkcs11h_session_getObjectAttributes (
				session,
				handle,
				attrs,
				sizeof (attrs)/sizeof (CK_ATTRIBUTE)
			)) != CKR_OK
		) {
			goto retry;
		}

		op_succeed = TRUE;
		rv = CKR_OK;
	
	retry:

		if (!op_succeed) {
			if (!login_retry) {
				_PKCS11H_DEBUG (
					PKCS11H_LOG_DEBUG1,
					"PKCS#11: Read data object failed rv=%lu-'%s'",
					rv,
					pkcs11h_getMessage (rv)
				);
				login_retry = TRUE;
				rv = _pkcs11h_session_login (
					session,
					is_public,
					TRUE,
					user_data,
					mask_prompt
				);
			}

			if (rv != CKR_OK) {
				goto cleanup;
			}
		}
	}

	*p_blob_size = attrs[0].ulValueLen;

	if (blob != NULL) {
		if (*p_blob_size > blob_size_max) {
			rv = CKR_BUFFER_TOO_SMALL;
		}
		else {
			memmove (blob, attrs[0].pValue, *p_blob_size);
		}
	}

	rv = CKR_OK;

cleanup:

#if defined(ENABLE_PKCS11H_THREADING)
	if (mutex_locked) {
		_pkcs11h_threading_mutexRelease (&session->mutex);
		mutex_locked = FALSE;
	}
#endif

	_pkcs11h_session_freeObjectAttributes (
		attrs,
		sizeof (attrs)/sizeof (CK_ATTRIBUTE)
	);

	if (session != NULL) {
		_pkcs11h_session_release (session);
		session = NULL;
	}

	_PKCS11H_DEBUG (
		PKCS11H_LOG_DEBUG2,
		"PKCS#11: pkcs11h_data_get return rv=%lu-'%s', *p_blob_size="P_Z"",
		rv,
		pkcs11h_getMessage (rv),
		*p_blob_size
	);

	return rv;
}

CK_RV
pkcs11h_data_put (
	IN const pkcs11h_token_id_t token_id,
	IN const PKCS11H_BOOL is_public,
	IN const char * const application,
	IN const char * const label,
	IN void * const user_data,
	IN const unsigned mask_prompt,
	OUT unsigned char * const blob,
	IN const size_t blob_size
) {
	CK_OBJECT_CLASS class = CKO_DATA;
	CK_BBOOL ck_true = CK_TRUE;
	CK_BBOOL ck_false = CK_FALSE;

	CK_ATTRIBUTE attrs[] = {
		{CKA_CLASS, &class, sizeof (class)},
		{CKA_TOKEN, &ck_true, sizeof (ck_true)},
		{CKA_PRIVATE, is_public ? &ck_false : &ck_true, sizeof (CK_BBOOL)},
		{CKA_APPLICATION, (void *)application, strlen (application)},
		{CKA_LABEL, (void *)label, strlen (label)},
		{CKA_VALUE, blob, blob_size}
	};

	CK_OBJECT_HANDLE handle = _PKCS11H_INVALID_OBJECT_HANDLE;
	CK_RV rv = CKR_FUNCTION_FAILED;

#if defined(ENABLE_PKCS11H_THREADING)
	PKCS11H_BOOL mutex_locked = FALSE;
#endif
	_pkcs11h_session_t session = NULL;
	PKCS11H_BOOL op_succeed = FALSE;
	PKCS11H_BOOL login_retry = FALSE;

	_PKCS11H_ASSERT (_g_pkcs11h_data!=NULL);
	_PKCS11H_ASSERT (_g_pkcs11h_data->initialized);
	_PKCS11H_ASSERT (token_id!=NULL);
	_PKCS11H_ASSERT (application!=NULL);
	_PKCS11H_ASSERT (label!=NULL);
	/*_PKCS11H_ASSERT (user_data) NOT NEEDED */
	_PKCS11H_ASSERT (blob!=NULL);

	_PKCS11H_DEBUG (
		PKCS11H_LOG_DEBUG2,
		"PKCS#11: pkcs11h_data_put entry token_id=%p, application='%s', label='%s', user_data=%p, mask_prompt=%08x, blob=%p, blob_size="P_Z"",
		(void *)token_id,
		application,
		label,
		user_data,
		mask_prompt,
		blob,
		blob != NULL ? blob_size : 0
	);

	if (
		(rv = _pkcs11h_session_getSessionByTokenId (
			token_id,
			&session
		)) != CKR_OK
	) {
		goto cleanup;
	}

#if defined(ENABLE_PKCS11H_THREADING)
	if ((rv = _pkcs11h_threading_mutexLock (&session->mutex)) != CKR_OK) {
		goto cleanup;
	}
	mutex_locked = TRUE;
#endif

	while (!op_succeed) {

		if (
			(rv = _pkcs11h_session_validate (session)) != CKR_OK ||
			(rv = session->provider->f->C_CreateObject (
				session->session_handle,
				attrs,
				sizeof (attrs)/sizeof (CK_ATTRIBUTE),
				&handle
			)) != CKR_OK
		) {
			goto retry;
		}
	
		op_succeed = TRUE;
		rv = CKR_OK;

	retry:

		if (!op_succeed) {
			if (!login_retry) {
				_PKCS11H_DEBUG (
					PKCS11H_LOG_DEBUG1,
					"PKCS#11: Write data object failed rv=%lu-'%s'",
					rv,
					pkcs11h_getMessage (rv)
				);
				login_retry = TRUE;
				rv = _pkcs11h_session_login (
					session,
					is_public,
					FALSE,
					user_data,
					mask_prompt
				);
			}

			if (rv != CKR_OK) {
				goto cleanup;
			}
		}
	}

	rv = CKR_OK;

cleanup:

#if defined(ENABLE_PKCS11H_THREADING)
	if (mutex_locked) {
		_pkcs11h_threading_mutexRelease (&session->mutex);
		mutex_locked = FALSE;
	}
#endif

	if (session != NULL) {
		_pkcs11h_session_release (session);
		session = NULL;
	}

	_PKCS11H_DEBUG (
		PKCS11H_LOG_DEBUG2,
		"PKCS#11: pkcs11h_data_put return rv=%lu-'%s'",
		rv,
		pkcs11h_getMessage (rv)
	);

	return rv;
}

CK_RV
pkcs11h_data_del (
	IN const pkcs11h_token_id_t token_id,
	IN const PKCS11H_BOOL is_public,
	IN const char * const application,
	IN const char * const label,
	IN void * const user_data,
	IN const unsigned mask_prompt
) {
#if defined(ENABLE_PKCS11H_THREADING)
	PKCS11H_BOOL mutex_locked = FALSE;
#endif
	_pkcs11h_session_t session = NULL;
	PKCS11H_BOOL op_succeed = FALSE;
	PKCS11H_BOOL login_retry = FALSE;
	CK_OBJECT_HANDLE handle = _PKCS11H_INVALID_OBJECT_HANDLE;
	CK_RV rv = CKR_FUNCTION_FAILED;

	_PKCS11H_ASSERT (_g_pkcs11h_data!=NULL);
	_PKCS11H_ASSERT (_g_pkcs11h_data->initialized);
	_PKCS11H_ASSERT (token_id!=NULL);
	_PKCS11H_ASSERT (application!=NULL);
	_PKCS11H_ASSERT (label!=NULL);
	/*_PKCS11H_ASSERT (user_data) NOT NEEDED */

	_PKCS11H_DEBUG (
		PKCS11H_LOG_DEBUG2,
		"PKCS#11: pkcs11h_data_del entry token_id=%p, application='%s', label='%s', user_data=%p, mask_prompt=%08x",
		(void *)token_id,
		application,
		label,
		user_data,
		mask_prompt
	);

	if (
		(rv = _pkcs11h_session_getSessionByTokenId (
			token_id,
			&session
		)) != CKR_OK
	) {
		goto cleanup;
	}

#if defined(ENABLE_PKCS11H_THREADING)
	if ((rv = _pkcs11h_threading_mutexLock (&session->mutex)) != CKR_OK) {
		goto cleanup;
	}
	mutex_locked = TRUE;
#endif

	while (!op_succeed) {

		if (
			(rv = _pkcs11h_session_validate (session)) != CKR_OK ||
			(rv = _pkcs11h_data_getObject (
				session,
				application,
				label,
				&handle
			)) != CKR_OK ||
			(rv = session->provider->f->C_DestroyObject (
				session->session_handle,
				handle
			)) != CKR_OK
		) {
			goto retry;
		}

		op_succeed = TRUE;
		rv = CKR_OK;

	retry:

		if (!op_succeed) {
			if (!login_retry) {
				_PKCS11H_DEBUG (
					PKCS11H_LOG_DEBUG1,
					"PKCS#11: Remove data object failed rv=%lu-'%s'",
					rv,
					pkcs11h_getMessage (rv)
				);
				login_retry = TRUE;
				rv = _pkcs11h_session_login (
					session,
					is_public,
					FALSE,
					user_data,
					mask_prompt
				);
			}

			if (rv != CKR_OK) {
				goto cleanup;
			}
		}
	}

cleanup:

#if defined(ENABLE_PKCS11H_THREADING)
	if (mutex_locked) {
		_pkcs11h_threading_mutexRelease (&session->mutex);
		mutex_locked = FALSE;
	}
#endif

	if (session != NULL) {
		_pkcs11h_session_release (session);
		session = NULL;
	}

	_PKCS11H_DEBUG (
		PKCS11H_LOG_DEBUG2,
		"PKCS#11: pkcs11h_data_del return rv=%lu-'%s'",
		rv,
		pkcs11h_getMessage (rv)
	);

	return rv;
}

CK_RV
pkcs11h_data_freeDataIdList (
	IN const pkcs11h_data_id_list_t data_id_list
) {
	pkcs11h_data_id_list_t _id = data_id_list;

	_PKCS11H_ASSERT (_g_pkcs11h_data!=NULL);
	_PKCS11H_ASSERT (_g_pkcs11h_data->initialized);
	/*_PKCS11H_ASSERT (data_id_list!=NULL); NOT NEEDED*/

	_PKCS11H_DEBUG (
		PKCS11H_LOG_DEBUG2,
		"PKCS#11: pkcs11h_freeDataIdList entry token_id_list=%p",
		(void *)data_id_list
	);

	while (_id != NULL) {
		pkcs11h_data_id_list_t x = _id;
		_id = _id->next;

		if (x->application != NULL) {
			_pkcs11h_mem_free ((void *)&x->application);
		}
		if (x->label != NULL) {
			_pkcs11h_mem_free ((void *)&x->label);
		}
		_pkcs11h_mem_free ((void *)&x);
	}

	_PKCS11H_DEBUG (
		PKCS11H_LOG_DEBUG2,
		"PKCS#11: pkcs11h_token_freeDataIdList return"
	);

	return CKR_OK;
}

CK_RV
pkcs11h_data_enumDataObjects (
	IN const pkcs11h_token_id_t token_id,
	IN const PKCS11H_BOOL is_public,
	IN void * const user_data,
	IN const unsigned mask_prompt,
	OUT pkcs11h_data_id_list_t * const p_data_id_list
) {
#if defined(ENABLE_PKCS11H_THREADING)
	PKCS11H_BOOL mutex_locked = FALSE;
#endif
	_pkcs11h_session_t session = NULL;
	pkcs11h_data_id_list_t data_id_list = NULL;
	CK_RV rv = CKR_FUNCTION_FAILED;

	PKCS11H_BOOL op_succeed = FALSE;
	PKCS11H_BOOL login_retry = FALSE;

	_PKCS11H_ASSERT (_g_pkcs11h_data!=NULL);
	_PKCS11H_ASSERT (_g_pkcs11h_data->initialized);
	_PKCS11H_ASSERT (p_data_id_list!=NULL);

	_PKCS11H_DEBUG (
		PKCS11H_LOG_DEBUG2,
		"PKCS#11: pkcs11h_data_enumDataObjects entry token_id=%p, is_public=%d, user_data=%p, mask_prompt=%08x, p_data_id_list=%p",
		(void *)token_id,
		is_public ? 1 : 0,
		user_data,
		mask_prompt,
		(void *)p_data_id_list
	);

	*p_data_id_list = NULL;

	if (
		(rv = _pkcs11h_session_getSessionByTokenId (
			token_id,
			&session
		)) != CKR_OK
	) {
		goto cleanup;
	}

#if defined(ENABLE_PKCS11H_THREADING)
	if ((rv = _pkcs11h_threading_mutexLock (&session->mutex)) != CKR_OK) {
		goto cleanup;
	}
	mutex_locked = TRUE;
#endif

	while (!op_succeed) {

		CK_OBJECT_CLASS class = CKO_DATA;
		CK_ATTRIBUTE filter[] = {
			{CKA_CLASS, (void *)&class, sizeof (class)}
		};
		CK_OBJECT_HANDLE *objects = NULL;
		CK_ULONG objects_found = 0;

		CK_ULONG i;

		if (
			(rv = _pkcs11h_session_validate (session)) != CKR_OK ||
			(rv = _pkcs11h_session_findObjects (
				session,
				filter,
				sizeof (filter) / sizeof (CK_ATTRIBUTE),
				&objects,
				&objects_found
			)) != CKR_OK
		) {
			goto retry1;
		}

		for (i = 0;i < objects_found;i++) {
			pkcs11h_data_id_list_t entry = NULL;

			CK_ATTRIBUTE attrs[] = {
				{CKA_APPLICATION, NULL, 0},
				{CKA_LABEL, NULL, 0}
			};

			if (
				(rv = _pkcs11h_session_getObjectAttributes (
					session,
					objects[i],
					attrs,
					sizeof (attrs) / sizeof (CK_ATTRIBUTE)
				)) != CKR_OK ||
				(rv = _pkcs11h_mem_malloc (
					(void *)&entry,
					sizeof (struct pkcs11h_data_id_list_s)
				)) != CKR_OK ||
				(rv = _pkcs11h_mem_malloc (
					(void *)&entry->application,
					attrs[0].ulValueLen+1
				)) != CKR_OK ||
				(rv = _pkcs11h_mem_malloc (
					(void *)&entry->label,
					attrs[1].ulValueLen+1
				)) != CKR_OK
			) {
				goto retry11;
			}

			memmove (entry->application, attrs[0].pValue, attrs[0].ulValueLen);
			entry->application[attrs[0].ulValueLen] = '\0';

			memmove (entry->label, attrs[1].pValue, attrs[1].ulValueLen);
			entry->label[attrs[1].ulValueLen] = '\0';

			entry->next = data_id_list;
			data_id_list = entry;
			entry = NULL;

			rv = CKR_OK;

		retry11:

			_pkcs11h_session_freeObjectAttributes (
				attrs,
				sizeof (attrs) / sizeof (CK_ATTRIBUTE)
			);

			if (entry != NULL) {
				if (entry->application != NULL) {
					_pkcs11h_mem_free ((void *)&entry->application);
				}
				if (entry->label != NULL) {
					_pkcs11h_mem_free ((void *)&entry->label);
				}
				_pkcs11h_mem_free ((void *)&entry);
			}
		}

		op_succeed = TRUE;
		rv = CKR_OK;

	retry1:

		if (objects != NULL) {
			_pkcs11h_mem_free ((void *)&objects);
		}

		if (!op_succeed) {
			if (!login_retry) {
				_PKCS11H_DEBUG (
					PKCS11H_LOG_DEBUG1,
					"PKCS#11: Enumerate data objects failed rv=%lu-'%s'",
					rv,
					pkcs11h_getMessage (rv)
				);
				login_retry = TRUE;
				rv = _pkcs11h_session_login (
					session,
					is_public,
					TRUE,
					user_data,
					mask_prompt
				);
			}

			if (rv != CKR_OK) {
				goto cleanup;
			}
		}
	}

	*p_data_id_list = data_id_list;
	data_id_list = NULL;
	rv = CKR_OK;

cleanup:

#if defined(ENABLE_PKCS11H_THREADING)
	if (mutex_locked) {
		_pkcs11h_threading_mutexRelease (&session->mutex);
		mutex_locked = FALSE;
	}
#endif

	if (session != NULL) {
		_pkcs11h_session_release (session);
		session = NULL;
	}

	if (data_id_list != NULL) {
		pkcs11h_data_freeDataIdList (data_id_list);
		data_id_list = NULL;
	}

	_PKCS11H_DEBUG (
		PKCS11H_LOG_DEBUG2,
		"PKCS#11: pkcs11h_data_enumDataObjects return rv=%lu-'%s', *p_data_id_list=%p",
		rv,
		pkcs11h_getMessage (rv),
		(void *)*p_data_id_list
	);
	
	return rv;
}

#endif				/* ENABLE_PKCS11H_DATA */
