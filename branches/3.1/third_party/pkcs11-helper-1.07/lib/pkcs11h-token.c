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

#include <pkcs11-helper-1.0/pkcs11h-token.h>
#include "_pkcs11h-mem.h"
#include "_pkcs11h-session.h"
#include "_pkcs11h-util.h"
#include "_pkcs11h-token.h"

CK_RV
pkcs11h_token_freeTokenId (
	IN pkcs11h_token_id_t token_id
) {
	_PKCS11H_ASSERT (_g_pkcs11h_data!=NULL);
	_PKCS11H_ASSERT (_g_pkcs11h_data->initialized);
	_PKCS11H_ASSERT (token_id!=NULL);

	_PKCS11H_DEBUG (
		PKCS11H_LOG_DEBUG2,
		"PKCS#11: pkcs11h_token_freeTokenId entry certificate_id=%p",
		(void *)token_id
	);

	_pkcs11h_mem_free ((void *)&token_id);

	_PKCS11H_DEBUG (
		PKCS11H_LOG_DEBUG2,
		"PKCS#11: pkcs11h_token_freeTokenId return"
	);

	return CKR_OK;
}

CK_RV
pkcs11h_token_duplicateTokenId (
	OUT pkcs11h_token_id_t * const to,
	IN const pkcs11h_token_id_t from
) {
	CK_RV rv = CKR_FUNCTION_FAILED;

	_PKCS11H_ASSERT (_g_pkcs11h_data!=NULL);
	_PKCS11H_ASSERT (_g_pkcs11h_data->initialized);
	_PKCS11H_ASSERT (to!=NULL);
	_PKCS11H_ASSERT (from!=NULL);

	_PKCS11H_DEBUG (
		PKCS11H_LOG_DEBUG2,
		"PKCS#11: pkcs11h_token_duplicateTokenId entry to=%p form=%p",
		(void *)to,
		(void *)from
	);

	*to = NULL;

	if (
		(rv = _pkcs11h_mem_duplicate (
			(void*)to,
			NULL,
			from,
			sizeof (struct pkcs11h_token_id_s)
		)) != CKR_OK
	) {
		goto cleanup;
	}

	rv = CKR_OK;

cleanup:

	_PKCS11H_DEBUG (
		PKCS11H_LOG_DEBUG2,
		"PKCS#11: pkcs11h_token_duplicateTokenId return rv=%lu-'%s', *to=%p",
		rv,
		pkcs11h_getMessage (rv),
		(void *)*to
	);
	
	return rv;
}

PKCS11H_BOOL
pkcs11h_token_sameTokenId (
	IN const pkcs11h_token_id_t a,
	IN const pkcs11h_token_id_t b
) {
	_PKCS11H_ASSERT (a!=NULL);
	_PKCS11H_ASSERT (b!=NULL);

	return (
		!strcmp (a->manufacturerID, b->manufacturerID) &&
		!strcmp (a->model, b->model) &&
		!strcmp (a->serialNumber, b->serialNumber) &&
		!strcmp (a->label, b->label)
	);
}

CK_RV
_pkcs11h_token_getTokenId (
	IN const CK_TOKEN_INFO_PTR info,
	OUT pkcs11h_token_id_t * const p_token_id
) {
	pkcs11h_token_id_t token_id;
	CK_RV rv = CKR_FUNCTION_FAILED;
	
	_PKCS11H_ASSERT (info!=NULL);
	_PKCS11H_ASSERT (p_token_id!=NULL);
	
	_PKCS11H_DEBUG (
		PKCS11H_LOG_DEBUG2,
		"PKCS#11: _pkcs11h_token_getTokenId entry p_token_id=%p",
		(void *)p_token_id
	);

	*p_token_id = NULL;

	if ((rv = _pkcs11h_token_newTokenId (&token_id)) != CKR_OK) {
		goto cleanup;
	}

	_pkcs11h_util_fixupFixedString (
		token_id->label,
		(char *)info->label,
		sizeof (info->label)
	);
	_pkcs11h_util_fixupFixedString (
		token_id->manufacturerID,
		(char *)info->manufacturerID,
		sizeof (info->manufacturerID)
	);
	_pkcs11h_util_fixupFixedString (
		token_id->model,
		(char *)info->model,
		sizeof (info->model)
	);
	_pkcs11h_util_fixupFixedString (
		token_id->serialNumber,
		(char *)info->serialNumber,
		sizeof (info->serialNumber)
	);
	strncpy (
		token_id->display,
		token_id->label,
		sizeof (token_id->display)
	);

	*p_token_id = token_id;
	token_id = NULL;
	rv = CKR_OK;

cleanup:

	if (token_id != NULL) {
		_pkcs11h_mem_free ((void *)&token_id);
	}

	_PKCS11H_DEBUG (
		PKCS11H_LOG_DEBUG2,
		"PKCS#11: _pkcs11h_token_getTokenId return rv=%lu-'%s', *p_token_id=%p",
		rv,
		pkcs11h_getMessage (rv),
		(void *)*p_token_id
	);

	return rv;
}

CK_RV
_pkcs11h_token_newTokenId (
	OUT pkcs11h_token_id_t * const p_token_id
) {
	CK_RV rv = CKR_FUNCTION_FAILED;

	pkcs11h_token_id_t token_id = NULL;

	_PKCS11H_ASSERT (_g_pkcs11h_data!=NULL);
	_PKCS11H_ASSERT (_g_pkcs11h_data->initialized);
	_PKCS11H_ASSERT (p_token_id!=NULL);

	_PKCS11H_DEBUG (
		PKCS11H_LOG_DEBUG2,
		"PKCS#11: _pkcs11h_token_newTokenId entry p_token_id=%p",
		(void *)p_token_id
	);

	*p_token_id = NULL;

	if ((rv = _pkcs11h_mem_malloc ((void *)&token_id, sizeof (struct pkcs11h_token_id_s))) != CKR_OK) {
		goto cleanup;
	}

	*p_token_id = token_id;
	token_id = NULL;

	rv = CKR_OK;

cleanup:

	if (token_id != NULL) {
		_pkcs11h_mem_free ((void *)&token_id);
		token_id = NULL;
	}

	_PKCS11H_DEBUG (
		PKCS11H_LOG_DEBUG2,
		"PKCS#11: _pkcs11h_token_newTokenId return rv=%lu-'%s', *p_token_id=%p",
		rv,
		pkcs11h_getMessage (rv),
		(void *)*p_token_id
	);

	return rv;
}

CK_RV
pkcs11h_token_logout (
	IN const pkcs11h_token_id_t token_id
) {
#if defined(ENABLE_PKCS11H_THREADING)
	PKCS11H_BOOL mutex_locked = FALSE;
#endif
	CK_RV rv = CKR_FUNCTION_FAILED;

	_pkcs11h_session_t session = NULL;

	_PKCS11H_ASSERT (token_id!=NULL);

	_PKCS11H_DEBUG (
		PKCS11H_LOG_DEBUG2,
		"PKCS#11: pkcs11h_token_logout entry token_id=%p\n", 
		(void *)token_id
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

	if (
		(rv = _pkcs11h_session_logout (session)) != CKR_OK
	) {
		goto cleanup;
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
		"PKCS#11: pkcs11h_token_logout return rv=%lu-'%s'",
		rv,
		pkcs11h_getMessage (rv)
	);

	return rv;
}

CK_RV
pkcs11h_token_login (
	IN const pkcs11h_token_id_t token_id,
	IN const PKCS11H_BOOL readonly,
	IN const char * const pin
) {
#if defined(ENABLE_PKCS11H_THREADING)
	PKCS11H_BOOL mutex_locked = FALSE;
#endif
	CK_SLOT_ID slot = _PKCS11H_INVALID_SLOT_ID;
	CK_ULONG pin_size = 0;
	CK_RV rv = CKR_FUNCTION_FAILED;

	_pkcs11h_session_t session = NULL;

	_PKCS11H_ASSERT (token_id!=NULL);
	/*_PKCS11H_ASSERT (pin!=NULL); NOT NEEDED*/

	_PKCS11H_DEBUG (
		PKCS11H_LOG_DEBUG2,
		"PKCS#11: pkcs11h_token_login entry token_id=%p, readonly=%d\n", 
		(void *)token_id,
		readonly ? 1 : 0
	);

	if (pin != NULL) {
		pin_size = strlen (pin);
	}

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

	if (
		(rv = _pkcs11h_session_logout (session)) != CKR_OK ||
		(rv = _pkcs11h_session_reset (session, NULL, 0, &slot)) != CKR_OK ||
		(rv = __pkcs11h_session_touch (session)) != CKR_OK ||
		(rv = session->provider->f->C_OpenSession (
			slot,
			(
				CKF_SERIAL_SESSION |
				(readonly ? 0 : CKF_RW_SESSION)
			),
			NULL_PTR,
			NULL_PTR,
			&session->session_handle
		)) != CKR_OK
	) {
		goto cleanup;
	}
	if (
		(rv = session->provider->f->C_Login (
			session->session_handle,
			CKU_USER,
			(CK_UTF8CHAR_PTR)pin,
			pin_size
		)) != CKR_OK
	) {
		if (rv != CKR_USER_ALREADY_LOGGED_IN) {
			goto cleanup;
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
		"PKCS#11: pkcs11h_token_login return rv=%lu-'%s'",
		rv,
		pkcs11h_getMessage (rv)
	);

	return rv;
}

#if defined(ENABLE_PKCS11H_TOKEN)

CK_RV
pkcs11h_token_ensureAccess (
	IN const pkcs11h_token_id_t token_id,
	IN void * const user_data,
	IN const unsigned mask_prompt
) {
#if defined(ENABLE_PKCS11H_THREADING)
	PKCS11H_BOOL mutex_locked = FALSE;
#endif
	_pkcs11h_session_t session = NULL;

	CK_RV rv = CKR_FUNCTION_FAILED;
	CK_SLOT_ID slot;

	_PKCS11H_ASSERT (_g_pkcs11h_data!=NULL);
	_PKCS11H_ASSERT (_g_pkcs11h_data->initialized);
	_PKCS11H_ASSERT (token_id!=NULL);
	/*_PKCS11H_ASSERT (user_data) NOT NEEDED */

	_PKCS11H_DEBUG (
		PKCS11H_LOG_DEBUG2,
		"PKCS#11: pkcs11h_token_ensureAccess entry token_id=%p, user_data=%p, mask_prompt=%08x",
		(void *)token_id,
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


	if (
		(rv = _pkcs11h_session_reset (
			session,
			user_data,
			mask_prompt,
			&slot
		)) != CKR_OK
	) {
		goto cleanup;
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
		"PKCS#11: pkcs11h_token_ensureAccess return rv=%lu-'%s'",
		rv,
		pkcs11h_getMessage (rv)
	);

	return rv;
}

CK_RV
pkcs11h_token_freeTokenIdList (
	IN const pkcs11h_token_id_list_t token_id_list
) {
	pkcs11h_token_id_list_t _id = token_id_list;

	_PKCS11H_ASSERT (_g_pkcs11h_data!=NULL);
	_PKCS11H_ASSERT (_g_pkcs11h_data->initialized);
	/*_PKCS11H_ASSERT (token_id_list!=NULL); NOT NEEDED*/

	_PKCS11H_DEBUG (
		PKCS11H_LOG_DEBUG2,
		"PKCS#11: pkcs11h_token_freeTokenIdList entry token_id_list=%p",
		(void *)token_id_list
	);

	while (_id != NULL) {
		pkcs11h_token_id_list_t x = _id;
		_id = _id->next;
		if (x->token_id != NULL) {
			pkcs11h_token_freeTokenId (x->token_id);
		}
		x->next = NULL;
		_pkcs11h_mem_free ((void *)&x);
	}

	_PKCS11H_DEBUG (
		PKCS11H_LOG_DEBUG2,
		"PKCS#11: pkcs11h_token_freeTokenIdList return"
	);

	return CKR_OK;
}

CK_RV
pkcs11h_token_enumTokenIds (
	IN const unsigned method,
	OUT pkcs11h_token_id_list_t * const p_token_id_list
) {
#if defined(ENABLE_PKCS11H_THREADING)
	PKCS11H_BOOL mutex_locked = FALSE;
#endif

	pkcs11h_token_id_list_t token_id_list = NULL;
	_pkcs11h_provider_t current_provider;
	CK_RV rv = CKR_FUNCTION_FAILED;

	_PKCS11H_ASSERT (_g_pkcs11h_data!=NULL);
	_PKCS11H_ASSERT (_g_pkcs11h_data->initialized);
	_PKCS11H_ASSERT (p_token_id_list!=NULL);

	_PKCS11H_DEBUG (
		PKCS11H_LOG_DEBUG2,
		"PKCS#11: pkcs11h_token_enumTokenIds entry method=%u, p_token_id_list=%p",
		method,
		(void *)p_token_id_list
	);

	*p_token_id_list = NULL;

#if defined(ENABLE_PKCS11H_THREADING)
	if ((rv = _pkcs11h_threading_mutexLock (&_g_pkcs11h_data->mutexes.global)) != CKR_OK) {
		goto cleanup;
	}
	mutex_locked = TRUE;
#endif

	for (
		current_provider = _g_pkcs11h_data->providers;
		current_provider != NULL;
		current_provider = current_provider->next
	) {
		CK_SLOT_ID_PTR slots = NULL;
		CK_ULONG slotnum;
		CK_SLOT_ID slot_index;

		/*
		 * Skip disabled providers
		 */
		if (!current_provider->enabled) {
			continue;
		}

		if (
			(rv = _pkcs11h_session_getSlotList (
				current_provider,
				CK_TRUE,
				&slots,
				&slotnum
			)) != CKR_OK
		) {
			_PKCS11H_DEBUG (
				PKCS11H_LOG_DEBUG1,
				"PKCS#11: Cannot get slot list for provider '%s' rv=%lu-'%s'",
				current_provider->manufacturerID,
				rv,
				pkcs11h_getMessage (rv)
			);
			goto retry1;
		}

		for (
			slot_index=0;
			slot_index < slotnum;
			slot_index++
		) {
			pkcs11h_token_id_list_t entry = NULL;
			CK_TOKEN_INFO info;

			if (
				(rv = _pkcs11h_mem_malloc (
					(void *)&entry,
					sizeof (struct pkcs11h_token_id_list_s)
				)) != CKR_OK ||
				(rv = current_provider->f->C_GetTokenInfo (
					slots[slot_index],
					&info
				)) != CKR_OK ||
				(rv = _pkcs11h_token_getTokenId (
					&info,
					&entry->token_id
				))
			) {
				goto retry11;
			}

			entry->next = token_id_list;
			token_id_list = entry;
			entry = NULL;
			rv = CKR_OK;

		retry11:

			if (entry != NULL) {
				pkcs11h_token_freeTokenIdList (entry);
				entry = NULL;
			}
		}

	retry1:

		if (slots != NULL) {
			_pkcs11h_mem_free ((void *)&slots);
			slots = NULL;
		}
	}

	if (method == PKCS11H_ENUM_METHOD_CACHE) {
		_pkcs11h_session_t session = NULL;

		for (
			session = _g_pkcs11h_data->sessions;
			session != NULL;
			session = session->next
		) {
			pkcs11h_token_id_list_t entry = NULL;
			PKCS11H_BOOL found = FALSE;

			for (
				entry = token_id_list;
				entry != NULL && !found;
				entry = entry->next
			) {
				if (
					pkcs11h_token_sameTokenId (
						session->token_id,
						entry->token_id
					)
				) {
					found = TRUE;
				}
			}

			if (!found) {
				entry = NULL;

				if (
					(rv = _pkcs11h_mem_malloc (
						(void *)&entry,
						sizeof (struct pkcs11h_token_id_list_s)
					)) != CKR_OK ||
					(rv = pkcs11h_token_duplicateTokenId (
						&entry->token_id,
						session->token_id
					)) != CKR_OK 
				) {
					goto retry12;
				}

				entry->next = token_id_list;
				token_id_list = entry;
				entry = NULL;

			retry12:

				if (entry != NULL) {
					if (entry->token_id != NULL) {
						pkcs11h_token_freeTokenId (entry->token_id);
					}
					_pkcs11h_mem_free ((void *)&entry);
				}
			}
		}
	}

	*p_token_id_list = token_id_list;
	token_id_list = NULL;
	rv = CKR_OK;

cleanup:

	if (token_id_list != NULL) {
		pkcs11h_token_freeTokenIdList (token_id_list);
		token_id_list = NULL;
	}

#if defined(ENABLE_PKCS11H_THREADING)
	if (mutex_locked) {
		rv = _pkcs11h_threading_mutexRelease (&_g_pkcs11h_data->mutexes.global);
		mutex_locked = FALSE;
	}
#endif

	_PKCS11H_DEBUG (
		PKCS11H_LOG_DEBUG2,
		"PKCS#11: pkcs11h_token_enumTokenIds return rv=%lu-'%s', *p_token_id_list=%p",
		rv,
		pkcs11h_getMessage (rv),
		(void *)p_token_id_list
	);
	
	return rv;
}

#endif				/* ENABLE_PKCS11H_TOKEN */
