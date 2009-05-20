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
 * @addtogroup pkcs11h_core pkcs11-helper core interface
 *
 * Core functionality.
 *
 * @{
 */

/**
 * @file pkcs11h-core.h
 * @brief pkcs11-helper core.
 * @author Alon Bar-Lev <alon.barlev@gmail.com>
 * @see pkcs11h_core.
 */

#ifndef __PKCS11H_BASE_H
#define __PKCS11H_BASE_H

#include <stdarg.h>
#include <time.h>

#include <pkcs11-helper-1.0/pkcs11h-version.h>
#include <pkcs11-helper-1.0/pkcs11h-def.h>
#include <pkcs11-helper-1.0/pkcs11h-engines.h>

#if defined(__cplusplus)
extern "C" {
#endif

/**
 * @brief pkcs11-helper features mask.
 * @addtogroup PKCS11H_FEATURE_MASK
 * @see pkcs11h_getFeatures().
 * @{
 */
/** Engine OpenSSL is enabled. */
#define PKCS11H_FEATURE_MASK_ENGINE_CRYPTO_OPENSSL	(1<< 0)
/** Engine GNUTLS is enabled. */
#define PKCS11H_FEATURE_MASK_ENGINE_CRYPTO_GNUTLS	(1<< 1)
/** Engine GNUTLS is enabled. */
#define PKCS11H_FEATURE_MASK_ENGINE_CRYPTO_WIN32	(1<< 2)
/** Debugging (logging) is enabled. */
#define PKCS11H_FEATURE_MASK_DEBUG			(1<< 3)
/** Threading support is enabled. */
#define PKCS11H_FEATURE_MASK_THREADING			(1<< 4)
/** Token interface is enabled. */
#define PKCS11H_FEATURE_MASK_TOKEN			(1<< 5)
/** Data interface is enabled. */
#define PKCS11H_FEATURE_MASK_DATA			(1<< 6)
/** Certificate interface is enabled, */
#define PKCS11H_FEATURE_MASK_CERTIFICATE		(1<< 7)
/** Slotevent interface is enabled. */
#define PKCS11H_FEATURE_MASK_SLOTEVENT			(1<< 8)
/** OpenSSL interface is enabled. */
#define PKCS11H_FEATURE_MASK_OPENSSL			(1<< 9)
/** @} */

/**
 * @brief pkcs11-helper log level.
 * @addtogroup PKCS11H_LOG
 * @see pkcs11h_getLogLevel().
 * @see pkcs11h_setLogLevel().
 * @{
 */
/** Most verbose log (entry/return). */
#define PKCS11H_LOG_DEBUG2	5
/** Important logic log. */
#define PKCS11H_LOG_DEBUG1	4
/** Information messages. */
#define PKCS11H_LOG_INFO	3
/** Warning messages, */
#define PKCS11H_LOG_WARN	2
/** Error messages. */
#define PKCS11H_LOG_ERROR	1
/** Used in order to turn off logging. */
#define PKCS11H_LOG_QUIET	0
/** @} */

/** Inifite session limit */
#define PKCS11H_PIN_CACHE_INFINITE	-1

/**
 * @brief Signature mask selection.
 * @addtogroup PKCS11H_PRIVATEMODE_MASK
 * @{
 */
/** Auto select by private key attributes. */
#define PKCS11H_PRIVATEMODE_MASK_AUTO		(0)
/** Force signature. */
#define PKCS11H_PRIVATEMODE_MASK_SIGN		(1<<0)
/** Force recover. */
#define PKCS11H_PRIVATEMODE_MASK_RECOVER	(1<<1)
/** Force decrypt. */
#define PKCS11H_PRIVATEMODE_MASK_DECRYPT	(1<<2)
/** Force unwrap. */
#define PKCS11H_PRIVATEMODE_MASK_UNWRAP		(1<<3)
/** @} */

/**
 * @brief Slotevent mode selection.
 * @addtogroup PKCS11H_SLOTEVENT_METHOD
 * @{
 */
/* Auto select by provider information. */
#define PKCS11H_SLOTEVENT_METHOD_AUTO		0
/** Force trigger. */
#define PKCS11H_SLOTEVENT_METHOD_TRIGGER	1
/** Force poll. */
#define PKCS11H_SLOTEVENT_METHOD_POLL		2
/** Force fetch. */
#define PKCS11H_SLOTEVENT_METHOD_FETCH		3
/** @} */

/**
 * @brief Prompt mask selection.
 * @addtogroup PKCS11H_PROMPT_MASK
 * @{
 */
/** Allow PIN prompt. */
#define PKCS11H_PROMPT_MASK_ALLOW_PIN_PROMPT	(1<<0)
/** Allow token prompt. */
#define PKCS11H_PROMPT_MASK_ALLOW_TOKEN_PROMPT	(1<<1)
/** Allow all prompt. */
#define PKCS11H_PROMPT_MASK_ALLOW_ALL ( \
		PKCS11H_PROMPT_MASK_ALLOW_PIN_PROMPT | \
		PKCS11H_PROMPT_MASK_ALLOW_TOKEN_PROMPT \
	)
/** @} */

/**
 * @brief Enumeration mode selection.
 * @addtogroup PKCS11H_ENUM_METHOD
 * @{
 */
/** Get from cache, if available. */
#define PKCS11H_ENUM_METHOD_CACHE               0
/** Get from cache, but only available objects. */
#define PKCS11H_ENUM_METHOD_CACHE_EXIST         1
/** Reload objects. */
#define PKCS11H_ENUM_METHOD_RELOAD              2
/** @} */

struct pkcs11h_token_id_s;

/**
 * @brief Token identifier.
 */
typedef struct pkcs11h_token_id_s *pkcs11h_token_id_t;

/**
 * @brief Log hook.
 * @param global_data	Hook data.
 * @param flags		Log flags.
 * @param format	printf style format.
 * @param args		stdargs
 */
typedef void (*pkcs11h_hook_log_t)(
	IN void * const global_data,
	IN const unsigned flags,
	IN const char * const format,
	IN va_list args
);

/**
 * @brief Slotevent hook.
 * @param global_data	Hook data.
 */
typedef void (*pkcs11h_hook_slotevent_t)(
	IN void * const global_data
);

/**
 * @brief Token prompt hook.
 * @param global_data	Hook data.
 * @param user_data	Local data.
 * @param token		Token.
 * @param retry		Retry counter.
 * @return TRUE success.
 */
typedef PKCS11H_BOOL (*pkcs11h_hook_token_prompt_t)(
	IN void * const global_data,
	IN void * const user_data,
	IN const pkcs11h_token_id_t token,
	IN const unsigned retry
);

/**
 * @brief PIN prompt hook.
 * @param global_data	Hook data.
 * @param user_data	Local data.
 * @param token		Token.
 * @param retry		Retry counter.
 * @param pin		PIN buffer.
 * @param pin_max	PIN buffer size.
 * @return TRUE success.
 */
typedef PKCS11H_BOOL (*pkcs11h_hook_pin_prompt_t)(
	IN void * const global_data,
	IN void * const user_data,
	IN const pkcs11h_token_id_t token,
	IN const unsigned retry,
	OUT char * const pin,
	IN const size_t pin_max
);

/**
 * @brief Token identifier.
 */
struct pkcs11h_token_id_s {
	/** Display for user. */
	char display[1024];
	/** NULL terminated manufacturerID */
	char manufacturerID[sizeof (((CK_TOKEN_INFO *)NULL)->manufacturerID)+1];
	/** NULL terminated model */
	char model[sizeof (((CK_TOKEN_INFO *)NULL)->model)+1];
	/** NULL terminated serialNumber */
	char serialNumber[sizeof (((CK_TOKEN_INFO *)NULL)->serialNumber)+1];
	/** NULL terminated label */
	char label[sizeof (((CK_TOKEN_INFO *)NULL)->label)+1];
};

/**
 * @brief Get message by return value.
 * @param rv	Return value.
 * @return CK_RV.
 */
const char *
pkcs11h_getMessage (
	IN const CK_RV rv
);

/**
 * @brief Get version of library.
 * @return version identifier.
 */
unsigned int
pkcs11h_getVersion (void);

/**
 * @brief Get features of library.
 * @return feature mask @ref PKCS11H_FEATURE_MASK.
 */
unsigned int
pkcs11h_getFeatures (void);

/**
 * @brief Inititalize helper interface.
 * @return CK_RV.
 * @see pkcs11h_terminate().
 * @attention This function must be called from the main thread.
 */
CK_RV
pkcs11h_initialize (void);

/**
 * @brief Terminate helper interface.
 * @return CK_RV.
 * @attention This function must be called from the main thread.
 */
CK_RV
pkcs11h_terminate (void);

/**
 * @brief Set current log level of the helper.
 * @param flags	Current log level @ref PKCS11H_LOG.
 */
void
pkcs11h_setLogLevel (
	IN const unsigned flags
);

/**
 * @brief Get current log level.
 * @return Log level @ref PKCS11H_LOG.
 */
unsigned
pkcs11h_getLogLevel (void);

/**
 * @brief How does the foked process bahaves after POSIX fork()
 * @param safe		Safe mode, default is false.
 * @return CK_RV.
 * @attention
 * This function should be called after @ref pkcs11h_initialize()
 * @note 
 * This funciton is releavant if @ref PKCS11H_FEATURE_MASK_THREADING is set.
 * If safe mode is on, the child process can use the loaded PKCS#11 providers
 * but it cannot use fork(), while it is in one of the hooks functions, since
 * locked mutexes cannot be released.
 */
CK_RV
pkcs11h_setForkMode (
	IN const PKCS11H_BOOL safe
);

/**
 * @brief Set a log callback.
 * @param hook		Callback.
 * @param global_data	Data to send to callback.
 * @return CK_RV.
 */
CK_RV
pkcs11h_setLogHook (
	IN const pkcs11h_hook_log_t hook,
	IN void * const global_data
);

/**
 * @brief Set a slot event callback.
 * @param hook		Callback.
 * @param global_data	Data to send to callback.
 * @return CK_RV.
 * @see pkcs11h_terminate().
 * @attention
 * Calling this function initialize slot event notifications, these
 * notifications can be started, but never terminate due to PKCS#11 limitation.
 * @note In order to use slot events you must have threading @ref PKCS11H_FEATURE_MASK_THREADING enabled.
 */
CK_RV
pkcs11h_setSlotEventHook (
	IN const pkcs11h_hook_slotevent_t hook,
	IN void * const global_data
);

/**
 * @brief Set a token prompt callback.
 * @param hook		Callback.
 * @param global_data	Data to send to callback.
 * @return CK_RV.
 * @attention
 * If @ref pkcs11h_setForkMode() is true, you cannot fork while in hook.
 */
CK_RV
pkcs11h_setTokenPromptHook (
	IN const pkcs11h_hook_token_prompt_t hook,
	IN void * const global_data
);

/**
 * @brief Set a pin prompt callback.
 * @param hook	Callback.
 * @param global_data	Data to send to callback.
 * @return CK_RV.
 * @attention
 * If @ref pkcs11h_setForkMode() is true, you cannot fork while in hook.
 */
CK_RV
pkcs11h_setPINPromptHook (
	IN const pkcs11h_hook_pin_prompt_t hook,
	IN void * const global_data
);

/**
 * @brief Set global protected authentication mode.
 * @param allow_protected_auth	Allow protected authentication if enabled by token.
 * @return CK_RV.
 * @note Default is on.
 */
CK_RV
pkcs11h_setProtectedAuthentication (
	IN const PKCS11H_BOOL allow_protected_auth
);

/**
 * @brief Set global PIN cache timeout.
 * @param pin_cache_period	Cache period in seconds, or @ref PKCS11H_PIN_CACHE_INFINITE.
 * @return CK_RV.
 * @note Default is infinite.
 */
CK_RV
pkcs11h_setPINCachePeriod (
	IN const int pin_cache_period
);

/**
 * @brief Set global login retries attempts.
 * @param max_retries	Login retries handled by the helper.
 * @return CK_RV.
 * @note Default is 3.
 */
CK_RV
pkcs11h_setMaxLoginRetries (
	IN const unsigned max_retries
);

/**
 * @brief Add a PKCS#11 provider.
 * @param reference		Reference name for this provider.
 * @param provider_location	Provider library location.
 * @param allow_protected_auth	Allow this provider to use protected authentication.
 * @param mask_private_mode	Provider private mode @ref PKCS11H_PRIVATEMODE_MASK override.
 * @param slot_event_method	Provider slot event @ref PKCS11H_SLOTEVENT_METHOD method.
 * @param slot_poll_interval	Slot event poll interval (If in polling mode), specify 0 for default.
 * @param cert_is_private	Provider's certificate access should be done after login.
 * @return CK_RV.
 * @attention This function must be called from the main thread.
 * @note The global allow_protected_auth must be enabled in order to allow provider specific.
 */
CK_RV
pkcs11h_addProvider (
	IN const char * const reference,
	IN const char * const provider_location,
	IN const PKCS11H_BOOL allow_protected_auth,
	IN const unsigned mask_private_mode,
	IN const unsigned slot_event_method,
	IN const unsigned slot_poll_interval,
	IN const PKCS11H_BOOL cert_is_private
);

/**
 * @brief Delete a PKCS#11 provider.
 * @param reference	Reference name for this provider.
 * @return CK_RV.
 * @attention This function must be called from the main thread.
 */
CK_RV
pkcs11h_removeProvider (
	IN const char * const reference
);

/**
 * @brief Handle special case of POSIX fork()
 * @return CK_RV.
 * @attention This function must be called from the main thread.
 * @attention
 * This function should be called after fork is called. This is required
 * due to a limitation of the PKCS#11 standard.
 * @note The helper library handles fork automatically if @ref PKCS11H_FEATURE_MASK_THREADING
 * is set by use of pthread_atfork.
 * When @ref PKCS11H_FEATURE_MASK_THREADING is enabled this function does nothing.
 */
CK_RV
pkcs11h_forkFixup (void);

/**
 * @brief Handle slot rescan.
 * @return CK_RV.
 * @attention This function must be called from the main thread.
 * @remarks
 * PKCS#11 providers do not allow plug&play, plug&play can be established by
 * finalizing all providers and initializing them again.
 * @remarks
 * The cost of this process is invalidating all sessions, and require user
 * login at the next access.
 */
CK_RV
pkcs11h_plugAndPlay (void);

/** 
 * @brief Logout from all sessions.
 * @return CK_RV.
 */
CK_RV
pkcs11h_logout (void);

#ifdef __cplusplus
}
#endif

/** @} */

#endif				/* __PKCS11H_BASE_H */
