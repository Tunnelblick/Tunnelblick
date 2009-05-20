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

#if !defined(_WIN32)
#include <sys/types.h>
#include <dlfcn.h>
#endif

#include <pkcs11-helper-1.0/pkcs11h-core.h>
#include <pkcs11-helper-1.0/pkcs11h-token.h>
#include "_pkcs11h-threading.h"
#include "_pkcs11h-mem.h"
#include "_pkcs11h-sys.h"
#include "_pkcs11h-crypto.h"
#include "_pkcs11h-util.h"
#include "_pkcs11h-core.h"
#include "_pkcs11h-session.h"
#include "_pkcs11h-slotevent.h"

/*======================================================================*
 * COMMON INTERNAL INTERFACE
 *======================================================================*/

static
void
__pkcs11h_hooks_default_log (
	IN void * const global_data,
	IN const unsigned flags,
	IN const char * const format,
	IN va_list args
);

static
PKCS11H_BOOL
__pkcs11h_hooks_default_token_prompt (
	IN void * const global_data,
	IN void * const user_data,
	IN const pkcs11h_token_id_t token,
	IN const unsigned retry
);

static
PKCS11H_BOOL
__pkcs11h_hooks_default_pin_prompt (
	IN void * const global_data,
	IN void * const user_data,
	IN const pkcs11h_token_id_t token,
	IN const unsigned retry,
	OUT char * const pin,
	IN const size_t pin_max
);

#if !defined(_WIN32)
#if defined(ENABLE_PKCS11H_THREADING)
static
void
__pkcs11h_threading_atfork_prepare  (void);
static
void
__pkcs11h_threading_atfork_parent (void);
static
void
__pkcs11h_threading_atfork_child (void);
#endif
static
CK_RV
__pkcs11h_forkFixup (
	IN const PKCS11H_BOOL activate_slotevent
);
#endif


/*==========================================
 * Data
 */

_pkcs11h_data_t _g_pkcs11h_data = NULL;
unsigned int _g_pkcs11h_loglevel = PKCS11H_LOG_INFO;

/*======================================================================*
 * PUBLIC INTERFACE
 *======================================================================*/

const char *
pkcs11h_getMessage (
	IN const CK_RV rv
) {
	switch (rv) {
		case CKR_OK: return "CKR_OK";
		case CKR_CANCEL: return "CKR_CANCEL";
		case CKR_HOST_MEMORY: return "CKR_HOST_MEMORY";
		case CKR_SLOT_ID_INVALID: return "CKR_SLOT_ID_INVALID";
		case CKR_GENERAL_ERROR: return "CKR_GENERAL_ERROR";
		case CKR_FUNCTION_FAILED: return "CKR_FUNCTION_FAILED";
		case CKR_ARGUMENTS_BAD: return "CKR_ARGUMENTS_BAD";
		case CKR_NO_EVENT: return "CKR_NO_EVENT";
		case CKR_NEED_TO_CREATE_THREADS: return "CKR_NEED_TO_CREATE_THREADS";
		case CKR_CANT_LOCK: return "CKR_CANT_LOCK";
		case CKR_ATTRIBUTE_READ_ONLY: return "CKR_ATTRIBUTE_READ_ONLY";
		case CKR_ATTRIBUTE_SENSITIVE: return "CKR_ATTRIBUTE_SENSITIVE";
		case CKR_ATTRIBUTE_TYPE_INVALID: return "CKR_ATTRIBUTE_TYPE_INVALID";
		case CKR_ATTRIBUTE_VALUE_INVALID: return "CKR_ATTRIBUTE_VALUE_INVALID";
		case CKR_DATA_INVALID: return "CKR_DATA_INVALID";
		case CKR_DATA_LEN_RANGE: return "CKR_DATA_LEN_RANGE";
		case CKR_DEVICE_ERROR: return "CKR_DEVICE_ERROR";
		case CKR_DEVICE_MEMORY: return "CKR_DEVICE_MEMORY";
		case CKR_DEVICE_REMOVED: return "CKR_DEVICE_REMOVED";
		case CKR_ENCRYPTED_DATA_INVALID: return "CKR_ENCRYPTED_DATA_INVALID";
		case CKR_ENCRYPTED_DATA_LEN_RANGE: return "CKR_ENCRYPTED_DATA_LEN_RANGE";
		case CKR_FUNCTION_CANCELED: return "CKR_FUNCTION_CANCELED";
		case CKR_FUNCTION_NOT_PARALLEL: return "CKR_FUNCTION_NOT_PARALLEL";
		case CKR_FUNCTION_NOT_SUPPORTED: return "CKR_FUNCTION_NOT_SUPPORTED";
		case CKR_KEY_HANDLE_INVALID: return "CKR_KEY_HANDLE_INVALID";
		case CKR_KEY_SIZE_RANGE: return "CKR_KEY_SIZE_RANGE";
		case CKR_KEY_TYPE_INCONSISTENT: return "CKR_KEY_TYPE_INCONSISTENT";
		case CKR_KEY_NOT_NEEDED: return "CKR_KEY_NOT_NEEDED";
		case CKR_KEY_CHANGED: return "CKR_KEY_CHANGED";
		case CKR_KEY_NEEDED: return "CKR_KEY_NEEDED";
		case CKR_KEY_INDIGESTIBLE: return "CKR_KEY_INDIGESTIBLE";
		case CKR_KEY_FUNCTION_NOT_PERMITTED: return "CKR_KEY_FUNCTION_NOT_PERMITTED";
		case CKR_KEY_NOT_WRAPPABLE: return "CKR_KEY_NOT_WRAPPABLE";
		case CKR_KEY_UNEXTRACTABLE: return "CKR_KEY_UNEXTRACTABLE";
		case CKR_MECHANISM_INVALID: return "CKR_MECHANISM_INVALID";
		case CKR_MECHANISM_PARAM_INVALID: return "CKR_MECHANISM_PARAM_INVALID";
		case CKR_OBJECT_HANDLE_INVALID: return "CKR_OBJECT_HANDLE_INVALID";
		case CKR_OPERATION_ACTIVE: return "CKR_OPERATION_ACTIVE";
		case CKR_OPERATION_NOT_INITIALIZED: return "CKR_OPERATION_NOT_INITIALIZED";
		case CKR_PIN_INCORRECT: return "CKR_PIN_INCORRECT";
		case CKR_PIN_INVALID: return "CKR_PIN_INVALID";
		case CKR_PIN_LEN_RANGE: return "CKR_PIN_LEN_RANGE";
		case CKR_PIN_EXPIRED: return "CKR_PIN_EXPIRED";
		case CKR_PIN_LOCKED: return "CKR_PIN_LOCKED";
		case CKR_SESSION_CLOSED: return "CKR_SESSION_CLOSED";
		case CKR_SESSION_COUNT: return "CKR_SESSION_COUNT";
		case CKR_SESSION_HANDLE_INVALID: return "CKR_SESSION_HANDLE_INVALID";
		case CKR_SESSION_PARALLEL_NOT_SUPPORTED: return "CKR_SESSION_PARALLEL_NOT_SUPPORTED";
		case CKR_SESSION_READ_ONLY: return "CKR_SESSION_READ_ONLY";
		case CKR_SESSION_EXISTS: return "CKR_SESSION_EXISTS";
		case CKR_SESSION_READ_ONLY_EXISTS: return "CKR_SESSION_READ_ONLY_EXISTS";
		case CKR_SESSION_READ_WRITE_SO_EXISTS: return "CKR_SESSION_READ_WRITE_SO_EXISTS";
		case CKR_SIGNATURE_INVALID: return "CKR_SIGNATURE_INVALID";
		case CKR_SIGNATURE_LEN_RANGE: return "CKR_SIGNATURE_LEN_RANGE";
		case CKR_TEMPLATE_INCOMPLETE: return "CKR_TEMPLATE_INCOMPLETE";
		case CKR_TEMPLATE_INCONSISTENT: return "CKR_TEMPLATE_INCONSISTENT";
		case CKR_TOKEN_NOT_PRESENT: return "CKR_TOKEN_NOT_PRESENT";
		case CKR_TOKEN_NOT_RECOGNIZED: return "CKR_TOKEN_NOT_RECOGNIZED";
		case CKR_TOKEN_WRITE_PROTECTED: return "CKR_TOKEN_WRITE_PROTECTED";
		case CKR_UNWRAPPING_KEY_HANDLE_INVALID: return "CKR_UNWRAPPING_KEY_HANDLE_INVALID";
		case CKR_UNWRAPPING_KEY_SIZE_RANGE: return "CKR_UNWRAPPING_KEY_SIZE_RANGE";
		case CKR_UNWRAPPING_KEY_TYPE_INCONSISTENT: return "CKR_UNWRAPPING_KEY_TYPE_INCONSISTENT";
		case CKR_USER_ALREADY_LOGGED_IN: return "CKR_USER_ALREADY_LOGGED_IN";
		case CKR_USER_NOT_LOGGED_IN: return "CKR_USER_NOT_LOGGED_IN";
		case CKR_USER_PIN_NOT_INITIALIZED: return "CKR_USER_PIN_NOT_INITIALIZED";
		case CKR_USER_TYPE_INVALID: return "CKR_USER_TYPE_INVALID";
		case CKR_USER_ANOTHER_ALREADY_LOGGED_IN: return "CKR_USER_ANOTHER_ALREADY_LOGGED_IN";
		case CKR_USER_TOO_MANY_TYPES: return "CKR_USER_TOO_MANY_TYPES";
		case CKR_WRAPPED_KEY_INVALID: return "CKR_WRAPPED_KEY_INVALID";
		case CKR_WRAPPED_KEY_LEN_RANGE: return "CKR_WRAPPED_KEY_LEN_RANGE";
		case CKR_WRAPPING_KEY_HANDLE_INVALID: return "CKR_WRAPPING_KEY_HANDLE_INVALID";
		case CKR_WRAPPING_KEY_SIZE_RANGE: return "CKR_WRAPPING_KEY_SIZE_RANGE";
		case CKR_WRAPPING_KEY_TYPE_INCONSISTENT: return "CKR_WRAPPING_KEY_TYPE_INCONSISTENT";
		case CKR_RANDOM_SEED_NOT_SUPPORTED: return "CKR_RANDOM_SEED_NOT_SUPPORTED";
		case CKR_RANDOM_NO_RNG: return "CKR_RANDOM_NO_RNG";
		case CKR_DOMAIN_PARAMS_INVALID: return "CKR_DOMAIN_PARAMS_INVALID";
		case CKR_BUFFER_TOO_SMALL: return "CKR_BUFFER_TOO_SMALL";
		case CKR_SAVED_STATE_INVALID: return "CKR_SAVED_STATE_INVALID";
		case CKR_INFORMATION_SENSITIVE: return "CKR_INFORMATION_SENSITIVE";
		case CKR_STATE_UNSAVEABLE: return "CKR_STATE_UNSAVEABLE";
		case CKR_CRYPTOKI_NOT_INITIALIZED: return "CKR_CRYPTOKI_NOT_INITIALIZED";
		case CKR_CRYPTOKI_ALREADY_INITIALIZED: return "CKR_CRYPTOKI_ALREADY_INITIALIZED";
		case CKR_MUTEX_BAD: return "CKR_MUTEX_BAD";
		case CKR_MUTEX_NOT_LOCKED: return "CKR_MUTEX_NOT_LOCKED";
		case CKR_FUNCTION_REJECTED: return "CKR_FUNCTION_REJECTED";
		case CKR_VENDOR_DEFINED: return "CKR_VENDOR_DEFINED";
		default: return "Unknown PKCS#11 error";
	}
}

unsigned int
pkcs11h_getVersion (void) {
	return PKCS11H_VERSION;
}

unsigned int
pkcs11h_getFeatures (void) {
	unsigned int features = (
#if defined(ENABLE_PKCS11H_ENGINE_OPENSSL)
		PKCS11H_FEATURE_MASK_ENGINE_CRYPTO_OPENSSL |
#endif
#if defined(ENABLE_PKCS11H_ENGINE_GNUTLS)
		PKCS11H_FEATURE_MASK_ENGINE_CRYPTO_GNUTLS |
#endif
#if defined(ENABLE_PKCS11H_ENGINE_WIN32)
		PKCS11H_FEATURE_MASK_ENGINE_CRYPTO_WIN32 |
#endif
#if defined(ENABLE_PKCS11H_DEBUG)
		PKCS11H_FEATURE_MASK_DEBUG |
#endif
#if defined(ENABLE_PKCS11H_THREADING)
		PKCS11H_FEATURE_MASK_THREADING |
#endif
#if defined(ENABLE_PKCS11H_TOKEN)
		PKCS11H_FEATURE_MASK_TOKEN |
#endif
#if defined(ENABLE_PKCS11H_DATA)
		PKCS11H_FEATURE_MASK_DATA |
#endif
#if defined(ENABLE_PKCS11H_CERTIFICATE)
		PKCS11H_FEATURE_MASK_CERTIFICATE |
#endif
#if defined(ENABLE_PKCS11H_SLOTEVENT)
		PKCS11H_FEATURE_MASK_SLOTEVENT |
#endif
#if defined(ENABLE_PKCS11H_OPENSSL)
		PKCS11H_FEATURE_MASK_OPENSSL |
#endif
		0
	);
	return features;
}

CK_RV
pkcs11h_initialize (void) {
#if defined(ENABLE_PKCS11H_THREADING)
	PKCS11H_BOOL has_mutex_global = FALSE;
	PKCS11H_BOOL has_mutex_cache = FALSE;
	PKCS11H_BOOL has_mutex_session = FALSE;
#endif

	CK_RV rv = CKR_FUNCTION_FAILED;

	_pkcs11h_data_t data = NULL;
	_PKCS11H_DEBUG (
		PKCS11H_LOG_DEBUG2,
		"PKCS#11: pkcs11h_initialize entry"
	);

	pkcs11h_terminate ();

	if ((rv = _pkcs11h_mem_malloc ((void*)&data, sizeof (struct _pkcs11h_data_s))) != CKR_OK) {
		goto cleanup;
	}

	if (_g_pkcs11h_crypto_engine.initialize == NULL) {
		if ((rv = pkcs11h_engine_setCrypto (PKCS11H_ENGINE_CRYPTO_AUTO)) != CKR_OK) {
			goto cleanup;
		}
	}

	if (!_g_pkcs11h_crypto_engine.initialize (_g_pkcs11h_crypto_engine.global_data)) {
		_PKCS11H_DEBUG (
			PKCS11H_LOG_ERROR,
			"PKCS#11: Cannot initialize crypto engine"
		);

		rv = CKR_FUNCTION_FAILED;
		goto cleanup;
	}

#if defined(ENABLE_PKCS11H_THREADING)
	if ((rv = _pkcs11h_threading_mutexInit (&data->mutexes.global)) != CKR_OK) {
		goto cleanup;
	}
	has_mutex_global = TRUE;
	if ((rv = _pkcs11h_threading_mutexInit (&data->mutexes.cache)) != CKR_OK) {
		goto cleanup;
	}
	has_mutex_cache = TRUE;
	if ((rv = _pkcs11h_threading_mutexInit (&data->mutexes.session)) != CKR_OK) {
		goto cleanup;
	}
	has_mutex_session = TRUE;
#if !defined(_WIN32)
	if (
		pthread_atfork (
			__pkcs11h_threading_atfork_prepare,
			__pkcs11h_threading_atfork_parent,
			__pkcs11h_threading_atfork_child
		)
	) {
		rv = CKR_FUNCTION_FAILED;
		goto cleanup;
	}
#endif
#endif

	data->max_retries = _PKCS11H_DEFAULT_MAX_LOGIN_RETRY;
	data->allow_protected_auth = TRUE;
	data->pin_cache_period = _PKCS11H_DEFAULT_PIN_CACHE_PERIOD;
	data->initialized = TRUE;

	_g_pkcs11h_data = data;
	data = NULL;

	pkcs11h_setLogHook (__pkcs11h_hooks_default_log, NULL);
	pkcs11h_setTokenPromptHook (__pkcs11h_hooks_default_token_prompt, NULL);
	pkcs11h_setPINPromptHook (__pkcs11h_hooks_default_pin_prompt, NULL);

	rv = CKR_OK;

cleanup:

	if (data != NULL) {
#if defined(ENABLE_PKCS11H_THREADING)
		if (has_mutex_global) {
			_pkcs11h_threading_mutexFree (&data->mutexes.global);
			has_mutex_global = FALSE;
		}
		if (has_mutex_cache) {
			_pkcs11h_threading_mutexFree (&data->mutexes.cache);
			has_mutex_cache = FALSE;
		}
		if (has_mutex_session) {
			_pkcs11h_threading_mutexFree (&data->mutexes.session); 
			has_mutex_session = FALSE;
		}
#endif
		_pkcs11h_mem_free ((void *)&data);
		data = NULL;
	}

	_PKCS11H_DEBUG (
		PKCS11H_LOG_DEBUG2,
		"PKCS#11: pkcs11h_initialize return rv=%lu-'%s'",
		rv,
		pkcs11h_getMessage (rv)
	);

	return rv;
}

CK_RV
pkcs11h_terminate (void) {

	_PKCS11H_DEBUG (
		PKCS11H_LOG_DEBUG2,
		"PKCS#11: pkcs11h_terminate entry"
	);

	if (_g_pkcs11h_data != NULL) {
		_pkcs11h_provider_t current_provider = NULL;

		_PKCS11H_DEBUG (
			PKCS11H_LOG_DEBUG1,
			"PKCS#11: Removing providers"
		);

		for (
			current_provider = _g_pkcs11h_data->providers;
			current_provider != NULL;
			current_provider = current_provider->next
		) {
			pkcs11h_removeProvider (current_provider->reference);
		}

#if defined(ENABLE_PKCS11H_THREADING)
		_pkcs11h_threading_mutexLock (&_g_pkcs11h_data->mutexes.cache);
		_pkcs11h_threading_mutexLock (&_g_pkcs11h_data->mutexes.session);
		_pkcs11h_threading_mutexLock (&_g_pkcs11h_data->mutexes.global);
#endif

		_PKCS11H_DEBUG (
			PKCS11H_LOG_DEBUG1,
			"PKCS#11: Releasing sessions"
		);

		while (_g_pkcs11h_data->sessions != NULL) {
			_pkcs11h_session_t current = _g_pkcs11h_data->sessions;
			_g_pkcs11h_data->sessions = _g_pkcs11h_data->sessions->next;

#if defined(ENABLE_PKCS11H_THREADING)
			_pkcs11h_threading_mutexLock (&current->mutex);
#endif

			current->valid = FALSE;

			if (current->reference_count != 0) {
				_PKCS11H_DEBUG (
					PKCS11H_LOG_DEBUG1,
					"PKCS#11: Warning: Found session with references"
				);
			}

			if (current->token_id != NULL) {
				pkcs11h_token_freeTokenId (current->token_id);
				current->token_id = NULL;
			}

#if defined(ENABLE_PKCS11H_CERTIFICATE)
			pkcs11h_certificate_freeCertificateIdList (current->cached_certs);
#endif

			current->provider = NULL;

#if defined(ENABLE_PKCS11H_THREADING)
			_pkcs11h_threading_mutexFree (&current->mutex);
#endif

			_pkcs11h_mem_free ((void *)&current);
		}

#if defined(ENABLE_PKCS11H_SLOTEVENT)
		_PKCS11H_DEBUG (
			PKCS11H_LOG_DEBUG1,
			"PKCS#11: Terminating slotevent"
		);

		_pkcs11h_slotevent_terminate ();
#endif
		_PKCS11H_DEBUG (
			PKCS11H_LOG_DEBUG1,
			"PKCS#11: Marking as uninitialized"
		);
		
		_g_pkcs11h_data->initialized = FALSE;

		while (_g_pkcs11h_data->providers != NULL) {
			_pkcs11h_provider_t current = _g_pkcs11h_data->providers;
			_g_pkcs11h_data->providers = _g_pkcs11h_data->providers->next;

			_pkcs11h_mem_free ((void *)&current);
		}

#if defined(ENABLE_PKCS11H_THREADING)
		_pkcs11h_threading_mutexFree (&_g_pkcs11h_data->mutexes.global); 
		_pkcs11h_threading_mutexFree (&_g_pkcs11h_data->mutexes.cache);
		_pkcs11h_threading_mutexFree (&_g_pkcs11h_data->mutexes.session); 
#endif

		_g_pkcs11h_crypto_engine.uninitialize (_g_pkcs11h_crypto_engine.global_data);

		_pkcs11h_mem_free ((void *)&_g_pkcs11h_data);
	}

	_PKCS11H_DEBUG (
		PKCS11H_LOG_DEBUG2,
		"PKCS#11: pkcs11h_terminate return"
	);

	return CKR_OK;
}

void
pkcs11h_setLogLevel (
	IN const unsigned flags
) {
	_g_pkcs11h_loglevel = flags;
}

CK_RV
pkcs11h_setForkMode (
	IN const PKCS11H_BOOL safe
) {
#if defined(ENABLE_PKCS11H_THREADING) && !defined(_WIN32)
	_PKCS11H_ASSERT (_g_pkcs11h_data!=NULL);
	_PKCS11H_ASSERT (_g_pkcs11h_data->initialized);

	_g_pkcs11h_data->safefork = safe;
#endif
	return CKR_OK;
}

unsigned
pkcs11h_getLogLevel (void) {
	_PKCS11H_ASSERT (_g_pkcs11h_data!=NULL);
	_PKCS11H_ASSERT (_g_pkcs11h_data->initialized);

	return _g_pkcs11h_loglevel;
}

CK_RV
pkcs11h_setLogHook (
	IN const pkcs11h_hook_log_t hook,
	IN void * const global_data
) {
	_PKCS11H_ASSERT (_g_pkcs11h_data!=NULL);
	_PKCS11H_ASSERT (_g_pkcs11h_data->initialized);
	_PKCS11H_ASSERT (hook!=NULL);

	_g_pkcs11h_data->hooks.log = hook;
	_g_pkcs11h_data->hooks.log_data = global_data;

	return CKR_OK;
}

CK_RV
pkcs11h_setSlotEventHook (
	IN const pkcs11h_hook_slotevent_t hook,
	IN void * const global_data
) {
	_PKCS11H_ASSERT (_g_pkcs11h_data!=NULL);
	_PKCS11H_ASSERT (_g_pkcs11h_data->initialized);
	_PKCS11H_ASSERT (hook!=NULL);

#if defined(ENABLE_PKCS11H_SLOTEVENT)
	_g_pkcs11h_data->hooks.slotevent = hook;
	_g_pkcs11h_data->hooks.slotevent_data = global_data;

	return _pkcs11h_slotevent_init ();
#else
	(void)global_data;

	return CKR_FUNCTION_NOT_SUPPORTED;
#endif
}

CK_RV
pkcs11h_setPINPromptHook (
	IN const pkcs11h_hook_pin_prompt_t hook,
	IN void * const global_data
) {
	_PKCS11H_ASSERT (_g_pkcs11h_data!=NULL);
	_PKCS11H_ASSERT (_g_pkcs11h_data->initialized);
	_PKCS11H_ASSERT (hook!=NULL);

	_g_pkcs11h_data->hooks.pin_prompt = hook;
	_g_pkcs11h_data->hooks.pin_prompt_data = global_data;

	return CKR_OK;
}

CK_RV
pkcs11h_setTokenPromptHook (
	IN const pkcs11h_hook_token_prompt_t hook,
	IN void * const global_data
) {
	_PKCS11H_ASSERT (_g_pkcs11h_data!=NULL);
	_PKCS11H_ASSERT (_g_pkcs11h_data->initialized);
	_PKCS11H_ASSERT (hook!=NULL);

	_g_pkcs11h_data->hooks.token_prompt = hook;
	_g_pkcs11h_data->hooks.token_prompt_data = global_data;

	return CKR_OK;
}

CK_RV
pkcs11h_setPINCachePeriod (
	IN const int pin_cache_period
) {
	_PKCS11H_ASSERT (_g_pkcs11h_data!=NULL);
	_PKCS11H_ASSERT (_g_pkcs11h_data->initialized);

	_g_pkcs11h_data->pin_cache_period = pin_cache_period;

	return CKR_OK;
}

CK_RV
pkcs11h_setMaxLoginRetries (
	IN const unsigned max_retries
) {
	_PKCS11H_ASSERT (_g_pkcs11h_data!=NULL);
	_PKCS11H_ASSERT (_g_pkcs11h_data->initialized);

	_g_pkcs11h_data->max_retries = max_retries;

	return CKR_OK;
}

CK_RV
pkcs11h_setProtectedAuthentication (
	IN const PKCS11H_BOOL allow_protected_auth
) {
	_PKCS11H_ASSERT (_g_pkcs11h_data!=NULL);
	_PKCS11H_ASSERT (_g_pkcs11h_data->initialized);

	_g_pkcs11h_data->allow_protected_auth = allow_protected_auth;

	return CKR_OK;
}

CK_RV
pkcs11h_addProvider (
	IN const char * const reference,
	IN const char * const provider_location,
	IN const PKCS11H_BOOL allow_protected_auth,
	IN const unsigned mask_private_mode,
	IN const unsigned slot_event_method,
	IN const unsigned slot_poll_interval,
	IN const PKCS11H_BOOL cert_is_private
) {
#if defined(ENABLE_PKCS11H_THREADING)
	PKCS11H_BOOL mutex_locked = FALSE;
#endif
#if defined(ENABLE_PKCS11H_DEBUG)
#if defined(_WIN32)
	int mypid = 0;
#else
	pid_t mypid = getpid ();
#endif
#endif
#if !defined(_WIN32)
	void *p;
#endif

	_pkcs11h_provider_t provider = NULL;
	CK_C_GetFunctionList gfl = NULL;
	CK_INFO info;
	CK_RV rv = CKR_FUNCTION_FAILED;

	_PKCS11H_ASSERT (_g_pkcs11h_data!=NULL);
	_PKCS11H_ASSERT (_g_pkcs11h_data->initialized);
	_PKCS11H_ASSERT (provider_location!=NULL);
	/*_PKCS11H_ASSERT (szSignMode!=NULL); NOT NEEDED*/

	_PKCS11H_DEBUG (
		PKCS11H_LOG_DEBUG2,
		"PKCS#11: pkcs11h_addProvider entry version='%s', pid=%d, reference='%s', provider_location='%s', allow_protected_auth=%d, mask_private_mode=%08x, cert_is_private=%d",
		PACKAGE_VERSION,
		mypid,
		reference,
		provider_location,
		allow_protected_auth ? 1 : 0,
		mask_private_mode,
		cert_is_private ? 1 : 0
	);

	_PKCS11H_DEBUG (
		PKCS11H_LOG_DEBUG1,
		"PKCS#11: Adding provider '%s'-'%s'",
		reference,
		provider_location
	);

#if defined(ENABLE_PKCS11H_THREADING)
	if ((rv = _pkcs11h_threading_mutexLock (&_g_pkcs11h_data->mutexes.global)) != CKR_OK) {
		goto cleanup;
	}
	mutex_locked = TRUE;
#endif

	if ((rv = _pkcs11h_mem_malloc ((void *)&provider, sizeof (struct _pkcs11h_provider_s))) != CKR_OK) {
		goto cleanup;
	}

	strncpy (
		provider->reference,
		reference,
		sizeof (provider->reference)-1
	);
	provider->reference[sizeof (provider->reference)-1] = '\x0';
	strncpy (
		provider->manufacturerID,
		(
			strlen (provider_location) < sizeof (provider->manufacturerID) ?
			provider_location :
			provider_location+strlen (provider_location)-sizeof (provider->manufacturerID)+1
		),
		sizeof (provider->manufacturerID)-1
	);
	provider->manufacturerID[sizeof (provider->manufacturerID)-1] = '\x0';
	provider->allow_protected_auth = allow_protected_auth;
	provider->mask_private_mode = mask_private_mode;
	provider->slot_event_method = slot_event_method;
	provider->slot_poll_interval = slot_poll_interval;
	provider->cert_is_private = cert_is_private;
		
#if defined(_WIN32)
	provider->handle = LoadLibraryA (provider_location);
#else
	provider->handle = dlopen (provider_location, RTLD_NOW);
#endif

	if (provider->handle == NULL) {
		rv = CKR_FUNCTION_FAILED;
		goto cleanup;
	}

#if defined(_WIN32)
	gfl = (CK_C_GetFunctionList)GetProcAddress (
		provider->handle,
		"C_GetFunctionList"
	);
#else
	/*
	 * Make compiler happy!
	 */
	p = dlsym (
		provider->handle,
		"C_GetFunctionList"
	);
	memmove (
		&gfl, 
		&p,
		sizeof (void *)
	);
#endif
	if (gfl == NULL) {
		rv = CKR_FUNCTION_FAILED;
		goto cleanup;
	}

	if ((rv = gfl (&provider->f)) != CKR_OK) {
		goto cleanup;
	}

	if ((rv = provider->f->C_Initialize (NULL)) != CKR_OK) {
		if (rv == CKR_CRYPTOKI_ALREADY_INITIALIZED) {
			rv = CKR_OK;
		}
		else {
			goto cleanup;
		}
	}
	else {
		provider->should_finalize = TRUE;
	}

	if ((rv = provider->f->C_GetInfo (&info)) != CKR_OK) {
		goto cleanup;
	}

	_pkcs11h_util_fixupFixedString (
		provider->manufacturerID,
		(char *)info.manufacturerID,
		sizeof (info.manufacturerID)
	);

	_PKCS11H_DEBUG (
		PKCS11H_LOG_DEBUG2,
		"PKCS#11: pkcs11h_addProvider Provider '%s' manufacturerID '%s'",
		reference,
		provider->manufacturerID
	);

	provider->enabled = TRUE;

	if (_g_pkcs11h_data->providers == NULL) {
		_g_pkcs11h_data->providers = provider;
	}
	else {
		_pkcs11h_provider_t last = NULL;

		for (
			last = _g_pkcs11h_data->providers;
			last->next != NULL;
			last = last->next
		);
		last->next = provider;
	}

	provider = NULL;
	rv = CKR_OK;

cleanup:

	if (provider != NULL) {
		if (provider->handle != NULL) {
#if defined(_WIN32)
			FreeLibrary (provider->handle);
#else
			dlclose (provider->handle);
#endif
			provider->handle = NULL;
		}

		_pkcs11h_mem_free ((void *)&provider);
		provider = NULL;
	}

#if defined(ENABLE_PKCS11H_THREADING)
	if (mutex_locked) {
		_pkcs11h_threading_mutexRelease (&_g_pkcs11h_data->mutexes.global);
		mutex_locked = FALSE;
	}
#endif

#if defined(ENABLE_PKCS11H_SLOTEVENT)
	_pkcs11h_slotevent_notify ();
#endif

	_PKCS11H_DEBUG (
		PKCS11H_LOG_DEBUG1,
		"PKCS#11: Provider '%s' added rv=%lu-'%s'",
		reference,
		rv,
		pkcs11h_getMessage (rv)
	);

	_PKCS11H_DEBUG (
		PKCS11H_LOG_DEBUG2,
		"PKCS#11: pkcs11h_addProvider return rv=%lu-'%s'",
		rv,
		pkcs11h_getMessage (rv)
	);

	return rv;
}

CK_RV
pkcs11h_removeProvider (
	IN const char * const reference
) {
#if defined(ENABLE_PKCS11H_THREADING)
	_pkcs11h_session_t current_session = NULL;
	PKCS11H_BOOL has_mutex_global = FALSE;
	PKCS11H_BOOL has_mutex_cache = FALSE;
	PKCS11H_BOOL has_mutex_session = FALSE;
#endif
	_pkcs11h_provider_t provider = NULL;
	CK_RV rv = CKR_FUNCTION_FAILED;

	_PKCS11H_ASSERT (reference!=NULL);

	_PKCS11H_DEBUG (
		PKCS11H_LOG_DEBUG2,
		"PKCS#11: pkcs11h_removeProvider entry reference='%s'",
		reference
	);

	_PKCS11H_DEBUG (
		PKCS11H_LOG_DEBUG1,
		"PKCS#11: Removing provider '%s'",
		reference
	);

#if defined(ENABLE_PKCS11H_THREADING)
	if ((rv = _pkcs11h_threading_mutexLock (&_g_pkcs11h_data->mutexes.cache)) != CKR_OK) {
		goto cleanup;
	}
	has_mutex_cache = TRUE;
	if ((rv = _pkcs11h_threading_mutexLock (&_g_pkcs11h_data->mutexes.session)) != CKR_OK) {
		goto cleanup;
	}
	has_mutex_session = TRUE;
	if ((rv = _pkcs11h_threading_mutexLock (&_g_pkcs11h_data->mutexes.global)) != CKR_OK) {
		goto cleanup;
	}
	has_mutex_global = TRUE;

	for (
		current_session = _g_pkcs11h_data->sessions;
		current_session != NULL;
		current_session = current_session->next
	) {
		_pkcs11h_threading_mutexLock (&current_session->mutex);
	}
#endif

	provider = _g_pkcs11h_data->providers;
	while (
		provider != NULL &&
		strcmp (reference, provider->reference)
	) {
		provider = provider->next;
	}

	if (provider == NULL) {
		rv = CKR_OBJECT_HANDLE_INVALID;
		goto cleanup;
	}

	provider->enabled = FALSE;
	provider->reference[0] = '\0';

	if (provider->should_finalize) {
		provider->f->C_Finalize (NULL);
		provider->should_finalize = FALSE;
	}

#if defined(ENABLE_PKCS11H_SLOTEVENT)
	_pkcs11h_slotevent_notify ();
	
	/*
	 * Wait until manager join this thread
	 * this happens saldom so I can poll
	 */
	while (provider->slotevent_thread != PKCS11H_THREAD_NULL) {
		_pkcs11h_threading_sleep (500);
	}
#endif

	if (provider->f != NULL) {
		provider->f = NULL;
	}

	if (provider->handle != NULL) {
#if defined(_WIN32)
		FreeLibrary (provider->handle);
#else
		dlclose (provider->handle);
#endif
		provider->handle = NULL;
	}

	rv = CKR_OK;

cleanup:
	
#if defined(ENABLE_PKCS11H_THREADING)
	for (
		current_session = _g_pkcs11h_data->sessions;
		current_session != NULL;
		current_session = current_session->next
	) {
		_pkcs11h_threading_mutexRelease (&current_session->mutex);
	}

	if (has_mutex_cache) {
		_pkcs11h_threading_mutexRelease (&_g_pkcs11h_data->mutexes.cache);
		has_mutex_cache = FALSE;
	}
	if (has_mutex_session) {
		_pkcs11h_threading_mutexRelease (&_g_pkcs11h_data->mutexes.session);
		has_mutex_session = FALSE;
	}
	if (has_mutex_global) {
		_pkcs11h_threading_mutexRelease (&_g_pkcs11h_data->mutexes.global);
		has_mutex_global = FALSE;
	}
#endif

	_PKCS11H_DEBUG (
		PKCS11H_LOG_DEBUG2,
		"PKCS#11: pkcs11h_removeProvider return rv=%lu-'%s'",
		rv,
		pkcs11h_getMessage (rv)
	);

	return rv;
}

CK_RV
pkcs11h_forkFixup (void) {
#if defined(_WIN32)
	return CKR_OK;
#else
#if defined(ENABLE_PKCS11H_THREADING)
	return CKR_OK;
#else
	return __pkcs11h_forkFixup (TRUE);
#endif
#endif
}

CK_RV
pkcs11h_plugAndPlay (void) {
#if defined(ENABLE_PKCS11H_DEBUG)
#if defined(_WIN32)
	int mypid = 0;
#else
	pid_t mypid = getpid ();
#endif
#endif

	_PKCS11H_DEBUG (
		PKCS11H_LOG_DEBUG2,
		"PKCS#11: pkcs11h_plugAndPlay entry pid=%d",
		mypid
	);

	if (_g_pkcs11h_data != NULL && _g_pkcs11h_data->initialized) {
		_pkcs11h_provider_t current;
#if defined(ENABLE_PKCS11H_SLOTEVENT)
		PKCS11H_BOOL slot_event_active = FALSE;
#endif

#if defined(ENABLE_PKCS11H_THREADING)
		_pkcs11h_threading_mutexLock (&_g_pkcs11h_data->mutexes.global);
#endif
		for (
			current = _g_pkcs11h_data->providers;
			current != NULL;
			current = current->next
		) {
			if (current->enabled) {
				current->f->C_Finalize (NULL);
			}
		}

#if defined(ENABLE_PKCS11H_SLOTEVENT)
		if (_g_pkcs11h_data->slotevent.initialized) {
			slot_event_active = TRUE;
			_pkcs11h_slotevent_terminate ();
		}
#endif

		for (
			current = _g_pkcs11h_data->providers;
			current != NULL;
			current = current->next
		) {
			if (current->enabled) {
				current->f->C_Initialize (NULL);
			}
		}

#if defined(ENABLE_PKCS11H_SLOTEVENT)
		if (slot_event_active) {
			_pkcs11h_slotevent_init ();
		}
#endif

#if defined(ENABLE_PKCS11H_THREADING)
		_pkcs11h_threading_mutexRelease (&_g_pkcs11h_data->mutexes.global);
#endif
	}

	_PKCS11H_DEBUG (
		PKCS11H_LOG_DEBUG2,
		"PKCS#11: pkcs11h_plugAndPlay return"
	);

	return CKR_OK;
}

CK_RV
pkcs11h_logout (void) {
	_pkcs11h_session_t current_session = NULL;
	CK_RV rv = CKR_OK;

	_PKCS11H_DEBUG (
		PKCS11H_LOG_DEBUG2,
		"PKCS#11: pkcs11h_logout entry"
	);

	for (
		current_session = _g_pkcs11h_data->sessions;
		current_session != NULL;
		current_session = current_session->next
	) {
		CK_RV _rv;

#if defined(ENABLE_PKCS11H_THREADING)
		if ((_rv = _pkcs11h_threading_mutexLock (&current_session->mutex)) == CKR_OK) {
#else
		{
#endif
			_rv = _pkcs11h_session_logout (current_session);
#if defined(ENABLE_PKCS11H_THREADING)
			_pkcs11h_threading_mutexRelease (&current_session->mutex);
#endif
		}

		if (_rv != CKR_OK) {
			rv = _rv;
		}
	}

	_PKCS11H_DEBUG (
		PKCS11H_LOG_DEBUG2,
		"PKCS#11: pkcs11h_logout return rv=%lu-'%s'",
		rv,
		pkcs11h_getMessage (rv)
	);

	return rv;
}

/*======================================================================*
 * COMMON INTERNAL INTERFACE
 *======================================================================*/

void
_pkcs11h_log (
	IN const unsigned flags,
	IN const char * const format,
	IN ...
) {
	va_list args;

	_PKCS11H_ASSERT (format!=NULL);

	va_start (args, format);

	if (
		_g_pkcs11h_data != NULL &&
		_g_pkcs11h_data->initialized
	) { 
		if (__PKCS11H_MSG_LEVEL_TEST (flags)) {
			if (_g_pkcs11h_data->hooks.log == NULL) {
				__pkcs11h_hooks_default_log (
					NULL,
					flags,
					format,
					args
				);
			}
			else {
				_g_pkcs11h_data->hooks.log (
					_g_pkcs11h_data->hooks.log_data,
					flags,
					format,
					args
				);
			}
		}
	}

	va_end (args);
}

static
void
__pkcs11h_hooks_default_log (
	IN void * const global_data,
	IN const unsigned flags,
	IN const char * const format,
	IN va_list args
) {
	(void)global_data;
	(void)flags;
	(void)format;
	(void)args;
}

static
PKCS11H_BOOL
__pkcs11h_hooks_default_token_prompt (
	IN void * const global_data,
	IN void * const user_data,
	IN const pkcs11h_token_id_t token,
	IN const unsigned retry
) {
	/*_PKCS11H_ASSERT (global_data) NOT NEEDED */
	/*_PKCS11H_ASSERT (user_data) NOT NEEDED */
	_PKCS11H_ASSERT (token!=NULL);

	(void)global_data;
	(void)user_data;
	(void)retry;

	_PKCS11H_DEBUG (
		PKCS11H_LOG_DEBUG2,
		"PKCS#11: __pkcs11h_hooks_default_token_prompt global_data=%p, user_data=%p, display='%s'",
		global_data,
		user_data,
		token->display
	);

	return FALSE;
}

static
PKCS11H_BOOL
__pkcs11h_hooks_default_pin_prompt (
	IN void * const global_data,
	IN void * const user_data,
	IN const pkcs11h_token_id_t token,
	IN const unsigned retry,
	OUT char * const pin,
	IN const size_t pin_max
) {
	/*_PKCS11H_ASSERT (global_data) NOT NEEDED */
	/*_PKCS11H_ASSERT (user_data) NOT NEEDED */
	_PKCS11H_ASSERT (token!=NULL);

	(void)global_data;
	(void)user_data;
	(void)retry;
	(void)pin;
	(void)pin_max;

	_PKCS11H_DEBUG (
		PKCS11H_LOG_DEBUG2,
		"PKCS#11: __pkcs11h_hooks_default_pin_prompt global_data=%p, user_data=%p, display='%s'",
		global_data,
		user_data,
		token->display
	);
	
	return FALSE;
}

#if !defined(_WIN32)
#if defined(ENABLE_PKCS11H_THREADING)

static
void
__pkcs11h_threading_atfork_prepare  (void) {
	if (_g_pkcs11h_data != NULL && _g_pkcs11h_data->initialized) {
		if (_g_pkcs11h_data->safefork) {
			_pkcs1h_threading_mutexLockAll ();
		}
	}
}
static
void
__pkcs11h_threading_atfork_parent (void) {
	if (_g_pkcs11h_data != NULL && _g_pkcs11h_data->initialized) {
		if (_g_pkcs11h_data->safefork) {
			_pkcs1h_threading_mutexReleaseAll ();
		}
	}
}
static
void
__pkcs11h_threading_atfork_child (void) {
	if (_g_pkcs11h_data != NULL && _g_pkcs11h_data->initialized) {
		_pkcs1h_threading_mutexReleaseAll ();
		if (_g_pkcs11h_data->safefork) {
			__pkcs11h_forkFixup (TRUE);
		}
		else {
			__pkcs11h_forkFixup (FALSE);
			pkcs11h_terminate ();
		}
	}
}

#endif				/* ENABLE_PKCS11H_THREADING */

static
CK_RV
__pkcs11h_forkFixup (
	IN const PKCS11H_BOOL activate_slotevent
) {
#if defined(ENABLE_PKCS11H_THREADING)
	PKCS11H_BOOL mutex_locked = FALSE;
#endif
#if defined(ENABLE_PKCS11H_DEBUG)
	pid_t mypid = getpid ();
#endif

	_PKCS11H_DEBUG (
		PKCS11H_LOG_DEBUG2,
		"PKCS#11: __pkcs11h_forkFixup entry pid=%d, activate_slotevent=%d",
		mypid,
		activate_slotevent ? 1 : 0
	);

#if !defined(ENABLE_PKCS11H_SLOTEVENT)
	(void)activate_slotevent;
#endif

	if (_g_pkcs11h_data != NULL && _g_pkcs11h_data->initialized) {
		_pkcs11h_provider_t current;

#if defined(ENABLE_PKCS11H_THREADING)
		if (_pkcs11h_threading_mutexLock (&_g_pkcs11h_data->mutexes.global) != CKR_OK) {
			goto cleanup;
		}
		mutex_locked = TRUE;
#endif

		for (
			current = _g_pkcs11h_data->providers;
			current != NULL;
			current = current->next
		) {
			if (current->enabled) {
				current->f->C_Initialize (NULL);
			}

#if defined(ENABLE_PKCS11H_SLOTEVENT)
			/*
			 * After fork we have no threads...
			 * So just initialized.
			 */
			if (_g_pkcs11h_data->slotevent.initialized) {
				_pkcs11h_slotevent_terminate_force ();

				if (activate_slotevent) {
					_pkcs11h_slotevent_init ();
				}
			}
#endif
		}

#if defined(ENABLE_PKCS11H_THREADING)
	cleanup:

		if (mutex_locked) {
			_pkcs11h_threading_mutexRelease (&_g_pkcs11h_data->mutexes.global);
			mutex_locked = FALSE;
		}
#endif
	}

	_PKCS11H_DEBUG (
		PKCS11H_LOG_DEBUG2,
		"PKCS#11: __pkcs11h_forkFixup return"
	);

	return CKR_OK;
}

#endif				/* !WIN32 */

