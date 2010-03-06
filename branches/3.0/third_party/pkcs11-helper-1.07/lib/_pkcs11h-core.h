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

#ifndef ___PKCS11H_BASE_H
#define ___PKCS11H_BASE_H

#include "common.h"

#include <pkcs11-helper-1.0/pkcs11h-core.h>
#include <pkcs11-helper-1.0/pkcs11h-certificate.h>
#include "_pkcs11h-threading.h"

#if !defined(_WIN32)
#include <unistd.h>
#endif

#define _PKCS11H_INVALID_SLOT_ID		((CK_SLOT_ID)-1)
#define _PKCS11H_INVALID_SESSION_HANDLE		((CK_SESSION_HANDLE)-1)
#define _PKCS11H_INVALID_OBJECT_HANDLE		((CK_OBJECT_HANDLE)-1)

#define _PKCS11H_DEFAULT_SLOTEVENT_POLL		5000
#define _PKCS11H_DEFAULT_MAX_LOGIN_RETRY	3
#define _PKCS11H_DEFAULT_PIN_CACHE_PERIOD	PKCS11H_PIN_CACHE_INFINITE

/*===========================================
 * Macros
 */

#define __PKCS11H_MSG_LEVEL_TEST(flags) (((unsigned int)flags) <= _g_pkcs11h_loglevel)

#if defined(HAVE_CPP_VARARG_MACRO_ISO) && !defined(__LCLINT__)
# define _PKCS11H_LOG(flags, ...) do { if (__PKCS11H_MSG_LEVEL_TEST(flags)) _pkcs11h_log((flags), __VA_ARGS__); } while (FALSE)
# ifdef ENABLE_PKCS11H_DEBUG
#  define _PKCS11H_DEBUG(flags, ...) do { if (__PKCS11H_MSG_LEVEL_TEST(flags)) _pkcs11h_log((flags), __VA_ARGS__); } while (FALSE)
# else
#  define _PKCS11H_DEBUG(flags, ...)
# endif
#elif defined(HAVE_CPP_VARARG_MACRO_GCC) && !defined(__LCLINT__)
# define _PKCS11H_LOG(flags, args...) do { if (__PKCS11H_MSG_LEVEL_TEST(flags)) _pkcs11h_log((flags), args); } while (FALSE)
# ifdef ENABLE_PKCS11H_DEBUG
#  define _PKCS11H_DEBUG(flags, args...) do { if (__PKCS11H_MSG_LEVEL_TEST(flags)) _pkcs11h_log((flags), args); } while (FALSE)
# else
#  define _PKCS11H_DEBUG(flags, args...)
# endif
#else
# define _PKCS11H_LOG _pkcs11h_log
# define _PKCS11H_DEBUG _pkcs11h_log
#endif

/*===========================================
 * Types
 */

struct _pkcs11h_provider_s;
struct _pkcs11h_session_s;
struct _pkcs11h_data_s;
typedef struct _pkcs11h_provider_s *_pkcs11h_provider_t;
typedef struct _pkcs11h_session_s *_pkcs11h_session_t;
typedef struct _pkcs11h_data_s *_pkcs11h_data_t;

struct _pkcs11h_provider_s {
	_pkcs11h_provider_t next;

	PKCS11H_BOOL enabled;
	char reference[1024];
	char manufacturerID[sizeof (((CK_TOKEN_INFO *)NULL)->manufacturerID)+1];
	
#if defined(_WIN32)
	HANDLE handle;
#else
	void *handle;
#endif

	CK_FUNCTION_LIST_PTR f;
	PKCS11H_BOOL should_finalize;
	PKCS11H_BOOL allow_protected_auth;
	PKCS11H_BOOL cert_is_private;
	unsigned mask_private_mode;
	unsigned mask_decrypt_mode;
	unsigned slot_event_method;
	unsigned slot_poll_interval;

#if defined(ENABLE_PKCS11H_SLOTEVENT)
	_pkcs11h_thread_t slotevent_thread;
#endif
};

struct _pkcs11h_session_s {
	_pkcs11h_session_t next;

	int reference_count;
	PKCS11H_BOOL valid;

	_pkcs11h_provider_t provider;

	pkcs11h_token_id_t token_id;

	CK_SESSION_HANDLE session_handle;

	PKCS11H_BOOL allow_protected_auth_supported;
	int pin_cache_period;
	time_t pin_expire_time;

#if defined(ENABLE_PKCS11H_CERTIFICATE)
	pkcs11h_certificate_id_list_t cached_certs;
	PKCS11H_BOOL touch;
#endif

#if defined(ENABLE_PKCS11H_THREADING)
	_pkcs11h_mutex_t mutex;
#endif
};

struct _pkcs11h_data_s {
	PKCS11H_BOOL initialized;
	int pin_cache_period;

	_pkcs11h_provider_t providers;
	_pkcs11h_session_t sessions;

	struct {
		void * log_data;
		void * slotevent_data;
		void * token_prompt_data;
		void * pin_prompt_data;
		pkcs11h_hook_log_t log;
		pkcs11h_hook_slotevent_t slotevent;
		pkcs11h_hook_token_prompt_t token_prompt;
		pkcs11h_hook_pin_prompt_t pin_prompt;
	} hooks;

	PKCS11H_BOOL allow_protected_auth;
	unsigned max_retries;

#if defined(ENABLE_PKCS11H_THREADING)
	struct {
		_pkcs11h_mutex_t global;
		_pkcs11h_mutex_t session;
		_pkcs11h_mutex_t cache;
	} mutexes;
#if !defined(_WIN32)
	PKCS11H_BOOL safefork;
#endif
#endif

#if defined(ENABLE_PKCS11H_SLOTEVENT)
	struct {
		PKCS11H_BOOL initialized;
		PKCS11H_BOOL should_terminate;
		PKCS11H_BOOL skip_event;
		_pkcs11h_cond_t cond_event;
		_pkcs11h_thread_t thread;
	} slotevent;
#endif
};

void
_pkcs11h_log (
	IN const unsigned flags,
	IN const char * const format,
	IN ...
)
#ifdef __GNUC__
	__attribute__ ((format (printf, 2, 3)))
#endif
	;

extern _pkcs11h_data_t _g_pkcs11h_data;
extern unsigned int _g_pkcs11h_loglevel;

#endif
