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

#include "_pkcs11h-sys.h"
#include "_pkcs11h-mem.h"
#include "_pkcs11h-token.h"
#include "_pkcs11h-session.h"

CK_RV
_pkcs11h_session_getSlotList (
	IN const _pkcs11h_provider_t provider,
	IN const CK_BBOOL token_present,
	OUT CK_SLOT_ID_PTR * const pSlotList,
	OUT CK_ULONG_PTR pulCount
) {
	CK_SLOT_ID_PTR _slots = NULL;
	CK_ULONG _slotnum = 0;
	CK_RV rv = CKR_FUNCTION_FAILED;

	_PKCS11H_ASSERT (provider!=NULL);
	_PKCS11H_ASSERT (pSlotList!=NULL);
	_PKCS11H_ASSERT (pulCount!=NULL);

	_PKCS11H_DEBUG (
		PKCS11H_LOG_DEBUG2,
		"PKCS#11: _pkcs11h_session_getSlotList entry provider=%p, token_present=%d, pSlotList=%p, pulCount=%p",
		(void *)provider,
		token_present ? 1 : 0,
		(void *)pSlotList,
		(void *)pulCount
	);

	*pSlotList = NULL;
	*pulCount = 0;

	if (!provider->enabled) {
		rv = CKR_CRYPTOKI_NOT_INITIALIZED;
		goto cleanup;
	}

	if (
		(rv = provider->f->C_GetSlotList (
			token_present,
			NULL_PTR,
			&_slotnum
		)) != CKR_OK
	) {
		goto cleanup;
	}

	if (_slotnum > 0) {
		if ((rv = _pkcs11h_mem_malloc ((void *)&_slots, _slotnum * sizeof (CK_SLOT_ID))) != CKR_OK) {
			goto cleanup;
		}
	}

	if (_slotnum > 0) {
		if (
			(rv = provider->f->C_GetSlotList (
				token_present,
				_slots,
				&_slotnum
			)) != CKR_OK
		) {
			goto cleanup;
		}
	}

	*pSlotList = _slots;
	_slots = NULL;
	*pulCount = _slotnum;
	rv = CKR_OK;

cleanup:

	if (_slots != NULL) {
		_pkcs11h_mem_free ((void *)&_slots);
	}

	_PKCS11H_DEBUG (
		PKCS11H_LOG_DEBUG2,
		"PKCS#11: _pkcs11h_session_getSlotList return rv=%lu-'%s' *pulCount=%ld",
		rv,
		pkcs11h_getMessage (rv),
		*pulCount
	);

	return rv;
}

CK_RV
_pkcs11h_session_getObjectAttributes (
	IN const _pkcs11h_session_t session,
	IN const CK_OBJECT_HANDLE object,
	IN OUT const CK_ATTRIBUTE_PTR attrs,
	IN const unsigned count
) {
	/*
	 * THREADING:
	 * session->mutex must be locked
	 */
	CK_RV rv = CKR_FUNCTION_FAILED;
	unsigned i;

	_PKCS11H_ASSERT (session!=NULL);
	_PKCS11H_ASSERT (attrs!=NULL);

	_PKCS11H_DEBUG (
		PKCS11H_LOG_DEBUG2,
		"PKCS#11: _pkcs11h_session_getObjectAttributes entry session=%p, object=%ld, attrs=%p, count=%u",
		(void *)session,
		object,
		(void *)attrs,
		count
	);

	if (
		(rv = session->provider->f->C_GetAttributeValue (
			session->session_handle,
			object,
			attrs,
			count
		)) != CKR_OK
	) {
		goto cleanup;
	}

	for (i=0;i<count;i++) {
		if (attrs[i].ulValueLen == (CK_ULONG)-1) {
			rv = CKR_ATTRIBUTE_VALUE_INVALID;
			goto cleanup;
		}
		else if (attrs[i].ulValueLen == 0) {
			attrs[i].pValue = NULL;
		}
		else {
			if (
				(rv = _pkcs11h_mem_malloc (
					(void *)&attrs[i].pValue,
					attrs[i].ulValueLen
				)) != CKR_OK
			) {
				goto cleanup;
			}
		}
	}

	if (
		(rv = session->provider->f->C_GetAttributeValue (
			session->session_handle,
			object,
			attrs,
			count
		)) != CKR_OK
	) {
		goto cleanup;
	}

cleanup:

	_PKCS11H_DEBUG (
		PKCS11H_LOG_DEBUG2,
		"PKCS#11: _pkcs11h_session_getObjectAttributes return rv=%lu-'%s'",
		rv,
		pkcs11h_getMessage (rv)
	);

	return rv;
}

CK_RV
_pkcs11h_session_freeObjectAttributes (
	IN OUT const CK_ATTRIBUTE_PTR attrs,
	IN const unsigned count
) {
	unsigned i;

	_PKCS11H_ASSERT (attrs!=NULL);

	_PKCS11H_DEBUG (
		PKCS11H_LOG_DEBUG2,
		"PKCS#11: _pkcs11h_session_freeObjectAttributes entry attrs=%p, count=%u",
		(void *)attrs,
		count
	);

	for (i=0;i<count;i++) {
		if (attrs[i].pValue != NULL) {
			_pkcs11h_mem_free ((void *)&attrs[i].pValue);
			attrs[i].pValue = NULL;
		}
	}

	_PKCS11H_DEBUG (
		PKCS11H_LOG_DEBUG2,
		"PKCS#11: _pkcs11h_session_freeObjectAttributes return"
	);

	return CKR_OK;
}

CK_RV
_pkcs11h_session_findObjects (
	IN const _pkcs11h_session_t session,
	IN const CK_ATTRIBUTE * const filter,
	IN const CK_ULONG filter_attrs,
	OUT CK_OBJECT_HANDLE **const p_objects,
	OUT CK_ULONG *p_objects_found
) {
	/*
	 * THREADING:
	 * session->mutex must be locked
	 */
	PKCS11H_BOOL should_FindObjectsFinal = FALSE;

	CK_OBJECT_HANDLE *objects = NULL;
	CK_ULONG objects_size = 0;
	CK_OBJECT_HANDLE objects_buffer[100];
	CK_ULONG objects_found;
	CK_OBJECT_HANDLE oLast = _PKCS11H_INVALID_OBJECT_HANDLE;
	CK_RV rv = CKR_FUNCTION_FAILED;

	_PKCS11H_ASSERT (session!=NULL);
	_PKCS11H_ASSERT (!(filter==NULL && filter_attrs!=0) || filter!=NULL);
	_PKCS11H_ASSERT (p_objects!=NULL);
	_PKCS11H_ASSERT (p_objects_found!=NULL);
	
	_PKCS11H_DEBUG (
		PKCS11H_LOG_DEBUG2,
		"PKCS#11: _pkcs11h_session_findObjects entry session=%p, filter=%p, filter_attrs=%ld, p_objects=%p, p_objects_found=%p",
		(void *)session,
		(void *)filter,
		filter_attrs,
		(void *)p_objects,
		(void *)p_objects_found
	);

	*p_objects = NULL;
	*p_objects_found = 0;

	if (
		(rv = session->provider->f->C_FindObjectsInit (
			session->session_handle,
			(CK_ATTRIBUTE *)filter,
			filter_attrs
		)) != CKR_OK
	) {
		goto cleanup;
	}
	should_FindObjectsFinal = TRUE;

	while (
		(rv = session->provider->f->C_FindObjects (
			session->session_handle,
			objects_buffer,
			sizeof (objects_buffer) / sizeof (CK_OBJECT_HANDLE),
			&objects_found
		)) == CKR_OK &&
		objects_found > 0
	) { 
		CK_OBJECT_HANDLE *temp = NULL;
		
		/*
		 * Begin workaround
		 *
		 * Workaround iKey bug
		 * It returns the same objects over and over
		 */
		if (oLast == objects_buffer[0]) {
			_PKCS11H_LOG (
				PKCS11H_LOG_WARN,
				"PKCS#11: Bad PKCS#11 C_FindObjects implementation detected, workaround applied"
			);
			break;
		}
		oLast = objects_buffer[0];
		/* End workaround */
		
		if (
			(rv = _pkcs11h_mem_malloc (
				(void *)&temp,
				(objects_size+objects_found) * sizeof (CK_OBJECT_HANDLE)
			)) != CKR_OK
		) {
			goto cleanup;
		}

		if (objects != NULL) {
			memmove (
				temp,
				objects,
				objects_size * sizeof (CK_OBJECT_HANDLE)
			);
		}
		memmove (
			temp + objects_size,
			objects_buffer,
			objects_found * sizeof (CK_OBJECT_HANDLE)
		);

		if (objects != NULL) {
			_pkcs11h_mem_free ((void *)&objects);
			objects = NULL;
		}

		objects = temp;
		objects_size += objects_found;
		temp = NULL;
	}

	if (should_FindObjectsFinal) {
		session->provider->f->C_FindObjectsFinal (
			session->session_handle
		);
		should_FindObjectsFinal = FALSE;
	}
	
	*p_objects = objects;
	*p_objects_found = objects_size;
	objects = NULL;
	objects_size = 0;
	rv = CKR_OK;

cleanup:

	if (objects != NULL) {
		_pkcs11h_mem_free ((void *)&objects);
		objects = NULL;
		objects_size = 0;
	}

	_PKCS11H_DEBUG (
		PKCS11H_LOG_DEBUG2,
		"PKCS#11: _pkcs11h_session_findObjects return rv=%lu-'%s', *p_objects_found=%ld",
		rv,
		pkcs11h_getMessage (rv),
		*p_objects_found
	);

	return rv;
}

CK_RV
_pkcs11h_session_getSessionByTokenId (
	IN const pkcs11h_token_id_t token_id,
	OUT _pkcs11h_session_t * const p_session
) {
#if defined(ENABLE_PKCS11H_THREADING)
	PKCS11H_BOOL mutex_locked = FALSE;
	PKCS11H_BOOL have_session_mutex = FALSE;
#endif
	_pkcs11h_session_t session = NULL;
	_pkcs11h_session_t current_session;

	CK_RV rv = CKR_FUNCTION_FAILED;

	_PKCS11H_ASSERT (token_id!=NULL);
	_PKCS11H_ASSERT (p_session!=NULL);

	_PKCS11H_DEBUG (
		PKCS11H_LOG_DEBUG2,
		"PKCS#11: _pkcs11h_session_getSessionByTokenId entry token_id=%p, p_session=%p",
		(void *)token_id,
		(void *)p_session
	);

	*p_session = NULL;

#if defined(ENABLE_PKCS11H_THREADING)
	if ((rv = _pkcs11h_threading_mutexLock (&_g_pkcs11h_data->mutexes.session)) != CKR_OK) {
		goto cleanup;
	}
	mutex_locked = TRUE;
#endif

	for (
		current_session = _g_pkcs11h_data->sessions;
		current_session != NULL && session == NULL;
		current_session = current_session->next
	) {
		if (
			pkcs11h_token_sameTokenId (
				current_session->token_id,
				token_id
			)
		) {
			_PKCS11H_DEBUG (
				PKCS11H_LOG_DEBUG1,
				"PKCS#11: Using cached session"
			);
			session = current_session;
			session->reference_count++;
		}
	}

	if (session == NULL) {
		_PKCS11H_DEBUG (
			PKCS11H_LOG_DEBUG1,
			"PKCS#11: Creating a new session"
		);

		if (
			(rv = _pkcs11h_mem_malloc (
				(void *)&session,
				sizeof (struct _pkcs11h_session_s))
			) != CKR_OK
		) {
			goto cleanup;
		}

		session->reference_count = 1;
		session->session_handle = _PKCS11H_INVALID_SESSION_HANDLE;
		
		session->pin_cache_period = _g_pkcs11h_data->pin_cache_period;

		if (
			(rv = pkcs11h_token_duplicateTokenId (
				&session->token_id,
				token_id
			)) != CKR_OK
		) {
			goto cleanup;
		}

#if defined(ENABLE_PKCS11H_THREADING)
		if ((rv = _pkcs11h_threading_mutexInit (&session->mutex)) != CKR_OK) {
			goto cleanup;
		}
		have_session_mutex = TRUE;
#endif

		session->valid = TRUE;
		session->next = _g_pkcs11h_data->sessions;
		_g_pkcs11h_data->sessions = session;
	}

	*p_session = session;
	session = NULL;
	rv = CKR_OK;

cleanup:
	if (session != NULL) {
#if defined(ENABLE_PKCS11H_THREADING)
		if (have_session_mutex) {
			_pkcs11h_threading_mutexFree (&session->mutex);
		}
#endif
		_pkcs11h_mem_free ((void *)&session);
	}

#if defined(ENABLE_PKCS11H_THREADING)
	if (mutex_locked) {
		_pkcs11h_threading_mutexRelease (&_g_pkcs11h_data->mutexes.session);
		mutex_locked = FALSE;
	}
#endif

	_PKCS11H_DEBUG (
		PKCS11H_LOG_DEBUG2,
		"PKCS#11: _pkcs11h_session_getSessionByTokenId return rv=%lu-'%s', *p_session=%p",
		rv,
		pkcs11h_getMessage (rv),
		(void *)*p_session
	);

	return rv;
}

CK_RV
_pkcs11h_session_release (
	IN const _pkcs11h_session_t session
) {
#if defined(ENABLE_PKCS11H_THREADING)
	PKCS11H_BOOL mutex_locked = TRUE;
#endif
	CK_RV rv = CKR_FUNCTION_FAILED;

	_PKCS11H_ASSERT (session!=NULL);
	_PKCS11H_ASSERT (session->reference_count>=0);

	_PKCS11H_DEBUG (
		PKCS11H_LOG_DEBUG2,
		"PKCS#11: _pkcs11h_session_release entry session=%p",
		(void *)session
	);

#if defined(ENABLE_PKCS11H_THREADING)
	if ((rv = _pkcs11h_threading_mutexLock (&session->mutex)) != CKR_OK) {
		goto cleanup;
	}
	mutex_locked = TRUE;
#endif

	/*
	 * Never logout for now
	 */
	if (session->reference_count > 0) {
		session->reference_count--;
	}

	rv = CKR_OK;

#if defined(ENABLE_PKCS11H_THREADING)
cleanup:

	if (mutex_locked) {
		_pkcs11h_threading_mutexRelease (&session->mutex);
		mutex_locked = FALSE;
	}
#endif

	_PKCS11H_DEBUG (
		PKCS11H_LOG_DEBUG2,
		"PKCS#11: _pkcs11h_session_release return rv=%lu-'%s'",
		rv,
		pkcs11h_getMessage (rv)
	);

	return rv;
}

CK_RV
_pkcs11h_session_reset (
	IN const _pkcs11h_session_t session,
	IN void * const user_data,
	IN const unsigned mask_prompt,
	OUT CK_SLOT_ID * const p_slot
) {
	PKCS11H_BOOL found = FALSE;

	CK_RV rv = CKR_FUNCTION_FAILED;

	unsigned nRetry = 0;

	_PKCS11H_ASSERT (session!=NULL);
	/*_PKCS11H_ASSERT (user_data) NOT NEEDED */
	_PKCS11H_ASSERT (p_slot!=NULL);

	_PKCS11H_DEBUG (
		PKCS11H_LOG_DEBUG2,
		"PKCS#11: _pkcs11h_session_reset entry session=%p, user_data=%p, mask_prompt=%08x, p_slot=%p",
		(void *)session,
		user_data,
		mask_prompt,
		(void *)p_slot
	);

	*p_slot = _PKCS11H_INVALID_SLOT_ID;

	_PKCS11H_DEBUG (
		PKCS11H_LOG_DEBUG2,
		"PKCS#11: _pkcs11h_session_reset Expected token manufacturerID='%s' model='%s', serialNumber='%s', label='%s'",
		session->token_id->manufacturerID,
		session->token_id->model,
		session->token_id->serialNumber,
		session->token_id->label
	);

	while (!found) {
		_pkcs11h_provider_t current_provider = NULL;

		for (
			current_provider = _g_pkcs11h_data->providers;
			(
				current_provider != NULL &&
				!found
			);
			current_provider = current_provider->next
		) {
			CK_SLOT_ID_PTR slots = NULL;
			CK_ULONG slotnum;
			CK_SLOT_ID slot_index;

			/*
			 * Skip all other providers,
			 * if one was set in the past
			 */
			if (
				session->provider != NULL &&
				session->provider != current_provider
			) {
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
				(
					slot_index < slotnum &&
					!found
				);
				slot_index++
			) {
				pkcs11h_token_id_t token_id = NULL;
				CK_TOKEN_INFO info;

				if (
					(rv = current_provider->f->C_GetTokenInfo (
						slots[slot_index],
						&info
					)) != CKR_OK ||
					(rv = _pkcs11h_token_getTokenId (
						&info,
						&token_id
					)) != CKR_OK
				) {
					goto retry11;
				}

				_PKCS11H_DEBUG (
					PKCS11H_LOG_DEBUG2,
					"PKCS#11: _pkcs11h_session_reset Found token manufacturerID='%s' model='%s', serialNumber='%s', label='%s'",
					token_id->manufacturerID,
					token_id->model,
					token_id->serialNumber,
					token_id->label
				);

				if (
					pkcs11h_token_sameTokenId (
						session->token_id,
						token_id
					)
				) {
					found = TRUE;
					*p_slot = slots[slot_index];
					if (session->provider == NULL) {
						session->provider = current_provider;
						session->allow_protected_auth_supported = (info.flags & CKF_PROTECTED_AUTHENTICATION_PATH) != 0;
					}
				}

				rv = CKR_OK;

			retry11:

				if (rv != CKR_OK) {
					_PKCS11H_DEBUG (
						PKCS11H_LOG_DEBUG1,
						"PKCS#11: Cannot get token information for provider '%s' slot %ld rv=%lu-'%s'",
						current_provider->manufacturerID,
						slots[slot_index],
						rv,
						pkcs11h_getMessage (rv)
					);
				}

				if (token_id != NULL) {
					pkcs11h_token_freeTokenId (token_id);
				}
			}

		retry1:
			if (slots != NULL) {
				_pkcs11h_mem_free ((void *)&slots);
				slots = NULL;
			}
		}

		if (!found && (mask_prompt & PKCS11H_PROMPT_MASK_ALLOW_TOKEN_PROMPT) == 0) {
			rv = CKR_TOKEN_NOT_PRESENT;
			goto cleanup;
		}

		if (!found) {
			PKCS11H_BOOL canceled;

			_PKCS11H_DEBUG (
				PKCS11H_LOG_DEBUG1,
				"PKCS#11: Calling token_prompt hook for '%s'",
				session->token_id->display
			);
	
			canceled = !_g_pkcs11h_data->hooks.token_prompt (
				_g_pkcs11h_data->hooks.token_prompt_data,
				user_data,
				session->token_id,
				nRetry++
			);

			_PKCS11H_DEBUG (
				PKCS11H_LOG_DEBUG1,
				"PKCS#11: token_prompt returned %d",
				canceled ? 0 : 1
			);

			if (canceled) {
				rv = CKR_CANCEL;
				goto cleanup;
			}
		}
	}

	rv = CKR_OK;

cleanup:

	_PKCS11H_DEBUG (
		PKCS11H_LOG_DEBUG2,
		"PKCS#11: _pkcs11h_session_reset return rv=%lu-'%s', *p_slot=%ld",
		rv,
		pkcs11h_getMessage (rv),
		*p_slot
	);

	return rv;
}

CK_RV
_pkcs11h_session_getObjectById (
	IN const _pkcs11h_session_t session,
	IN const CK_OBJECT_CLASS class,
	IN const CK_BYTE_PTR id,
	IN const size_t id_size,
	OUT CK_OBJECT_HANDLE * const p_handle
) {
	/*
	 * THREADING:
	 * session->mutex must be locked
	 */
	CK_ATTRIBUTE filter[] = {
		{CKA_CLASS, (void *)&class, sizeof (class)},
		{CKA_ID, (void *)id, id_size}
	};
	CK_OBJECT_HANDLE *objects = NULL;
	CK_ULONG objects_found = 0;
	CK_RV rv = CKR_FUNCTION_FAILED;
	
	/*_PKCS11H_ASSERT (session!=NULL); NOT NEEDED*/
	_PKCS11H_ASSERT (id!=NULL);
	_PKCS11H_ASSERT (p_handle!=NULL);

	_PKCS11H_DEBUG (
		PKCS11H_LOG_DEBUG2,
		"PKCS#11: _pkcs11h_session_getObjectById entry session=%p, class=%ld, id=%p, id_size="P_Z", p_handle=%p",
		(void *)session,
		class,
		id,
		id_size,
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
		"PKCS#11: _pkcs11h_session_getObjectById return rv=%lu-'%s', *p_handle=%08lx",
		rv,
		pkcs11h_getMessage (rv),
		(unsigned long)*p_handle
	);

	return rv;
}

CK_RV
_pkcs11h_session_validate (
	IN const _pkcs11h_session_t session
) {
	CK_RV rv = CKR_FUNCTION_FAILED;

	/*_PKCS11H_ASSERT (session!=NULL); NOT NEEDED*/

	_PKCS11H_DEBUG (
		PKCS11H_LOG_DEBUG2,
		"PKCS#11: _pkcs11h_session_validate entry session=%p",
		(void *)session
	);

	if (session == NULL) {
		rv = CKR_SESSION_HANDLE_INVALID;
		goto cleanup;
	}

	if (
		session->provider == NULL ||
		!session->provider->enabled ||
		session->session_handle == _PKCS11H_INVALID_SESSION_HANDLE
	) {
		rv = CKR_SESSION_HANDLE_INVALID;
		goto cleanup;
	}

	_PKCS11H_DEBUG (
		PKCS11H_LOG_DEBUG2,
		"PKCS#11: _pkcs11h_session_validate session->pin_expire_time=%u, time=%u",
		(unsigned int)session->pin_expire_time,
		(unsigned int)_g_pkcs11h_sys_engine.time ()
	);

	if (
		session->pin_expire_time != (time_t)0 &&
		session->pin_expire_time < _g_pkcs11h_sys_engine.time ()
	) {
		_PKCS11H_DEBUG (
			PKCS11H_LOG_DEBUG1,
			"PKCS#11: Forcing logout due to pin timeout"
		);
		_pkcs11h_session_logout (session);
		rv = CKR_SESSION_HANDLE_INVALID;
		goto cleanup;
	}

	rv = CKR_OK;

cleanup:

	_PKCS11H_DEBUG (
		PKCS11H_LOG_DEBUG2,
		"PKCS#11: _pkcs11h_session_validate return rv=%lu-'%s'",
		rv,
		pkcs11h_getMessage (rv)
	);

	return rv;
}

CK_RV
__pkcs11h_session_touch (
	IN const _pkcs11h_session_t session
) {
	/*
	 * THREADING:
	 * session->mutex must be locked
	 */
	_PKCS11H_ASSERT (session!=NULL);

	if (session->pin_cache_period == PKCS11H_PIN_CACHE_INFINITE) {
		session->pin_expire_time = 0;
	}
	else {
		session->pin_expire_time = (
			_g_pkcs11h_sys_engine.time () +
			(time_t)session->pin_cache_period
		);
	}

	return CKR_OK;
}

CK_RV
_pkcs11h_session_login (
	IN const _pkcs11h_session_t session,
	IN const PKCS11H_BOOL is_publicOnly,
	IN const PKCS11H_BOOL readonly,
	IN void * const user_data,
	IN const unsigned mask_prompt
) {
	/*
	 * THREADING:
	 * session->mutex must be locked
	 */
	CK_SLOT_ID slot = _PKCS11H_INVALID_SLOT_ID;
	CK_RV rv = CKR_FUNCTION_FAILED;

	_PKCS11H_ASSERT (session!=NULL);
	/*_PKCS11H_ASSERT (user_data) NOT NEEDED */

	_PKCS11H_DEBUG (
		PKCS11H_LOG_DEBUG2,
		"PKCS#11: _pkcs11h_session_login entry session=%p, is_publicOnly=%d, readonly=%d, user_data=%p, mask_prompt=%08x",
		(void *)session,
		is_publicOnly ? 1 : 0,
		readonly ? 1 : 0,
		user_data,
		mask_prompt
	);

	if (
		(rv = _pkcs11h_session_logout (session)) != CKR_OK ||
		(rv = _pkcs11h_session_reset (session, user_data, mask_prompt, &slot)) != CKR_OK ||
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
		!is_publicOnly ||
		session->provider->cert_is_private
	) {
		PKCS11H_BOOL login_succeeded = FALSE;
		unsigned retry_count = 0;

		if ((mask_prompt & PKCS11H_PROMPT_MASK_ALLOW_PIN_PROMPT) == 0) {
			rv = CKR_USER_NOT_LOGGED_IN;

			_PKCS11H_DEBUG (
				PKCS11H_LOG_DEBUG1,
				"PKCS#11: Calling pin_prompt hook denied because of prompt mask"
			);
		}

		while (
			!login_succeeded &&
			retry_count < _g_pkcs11h_data->max_retries 
		) {
			CK_UTF8CHAR_PTR utfPIN = NULL;
			CK_ULONG lPINLength = 0;
			char pin[1024];

			if (
				!(
					_g_pkcs11h_data->allow_protected_auth  &&
					session->provider->allow_protected_auth &&
					session->allow_protected_auth_supported
				)
			) {
				_PKCS11H_DEBUG (
					PKCS11H_LOG_DEBUG1,
					"PKCS#11: Calling pin_prompt hook for '%s'",
					session->token_id->display
				);

				if (
					_g_pkcs11h_data->hooks.pin_prompt (
						_g_pkcs11h_data->hooks.pin_prompt_data,
						user_data,
						session->token_id,
						retry_count,
						pin,
						sizeof (pin)
					)
				) {
					rv = CKR_OK;
				}
				else {
					rv = CKR_CANCEL;
				}

				_PKCS11H_DEBUG (
					PKCS11H_LOG_DEBUG1,
					"PKCS#11: pin_prompt hook return rv=%ld",
					rv
				);

				if (rv != CKR_OK ){
					goto retry;
				}

				utfPIN = (CK_UTF8CHAR_PTR)pin;
				lPINLength = strlen (pin);

			}

			if ((rv = __pkcs11h_session_touch (session)) != CKR_OK) {
				goto cleanup;
			}

			if (
				(rv = session->provider->f->C_Login (
					session->session_handle,
					CKU_USER,
					utfPIN,
					lPINLength
				)) != CKR_OK &&
				rv != CKR_USER_ALREADY_LOGGED_IN
			) {
				goto retry;
			}

			login_succeeded = TRUE;
			rv = CKR_OK;

		retry:
			_PKCS11H_DEBUG (
				PKCS11H_LOG_DEBUG2,
				"PKCS#11: _pkcs11h_session_login C_Login rv=%lu-'%s'",
				rv,
				pkcs11h_getMessage (rv)
			);

			/*
			 * Clean PIN buffer
			 */
			memset (pin, 0, sizeof (pin));

			if (
				rv != CKR_OK &&
				rv != CKR_PIN_INCORRECT &&
				rv != CKR_PIN_INVALID &&
				rv != CKR_PIN_LEN_RANGE
			) {
				goto cleanup;
			}

			retry_count++;
		}

		/*
		 * Retry limit
		 */
		if (!login_succeeded) {
			rv = CKR_PIN_INCORRECT;
			goto cleanup;
		}
	}

	rv = CKR_OK;

cleanup:

	_PKCS11H_DEBUG (
		PKCS11H_LOG_DEBUG2,
		"PKCS#11: _pkcs11h_session_login return rv=%lu-'%s'",
		rv,
		pkcs11h_getMessage (rv)
	);

	return rv;
}

CK_RV
_pkcs11h_session_logout (
	IN const _pkcs11h_session_t session
) {
	/*
	 * THREADING:
	 * session->mutex must be locked
	 */
	/*_PKCS11H_ASSERT (session!=NULL); NOT NEEDED*/

	_PKCS11H_DEBUG (
		PKCS11H_LOG_DEBUG2,
		"PKCS#11: _pkcs11h_session_logout entry session=%p",
		(void *)session
	);

	if (
		session != NULL &&
		session->session_handle != _PKCS11H_INVALID_SESSION_HANDLE
	) {
		if (session->provider != NULL) {
			session->provider->f->C_Logout (session->session_handle);
			session->provider->f->C_CloseSession (session->session_handle);
		}
		session->session_handle = _PKCS11H_INVALID_SESSION_HANDLE;
	}

	_PKCS11H_DEBUG (
		PKCS11H_LOG_DEBUG2,
		"PKCS#11: _pkcs11h_session_logout return"
	);

	return CKR_OK;
}

