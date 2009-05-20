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

#ifndef ___PKCS11H_THREADING_H
#define ___PKCS11H_THREADING_H

#include "common.h"

#if defined(ENABLE_PKCS11H_THREADING)

#include <pkcs11-helper-1.0/pkcs11h-def.h>

#if !defined(_WIN32)
#include <pthread.h>
#endif

#define PKCS11H_COND_INFINITE	0xffffffff

#if defined(_WIN32)
#define PKCS11H_THREAD_NULL	NULL
typedef HANDLE _pkcs11h_cond_t;
typedef HANDLE _pkcs11h_mutex_t;
typedef HANDLE _pkcs11h_thread_t;
#else
#define PKCS11H_THREAD_NULL	0l
typedef pthread_mutex_t _pkcs11h_mutex_t;
typedef pthread_t _pkcs11h_thread_t;

typedef struct {
	pthread_cond_t cond;
	pthread_mutex_t mut;
} _pkcs11h_cond_t;
#endif

typedef void * (*_pkcs11h_thread_start_t)(void *);

void
_pkcs11h_threading_sleep (
	IN const unsigned milli
);

CK_RV
_pkcs11h_threading_mutexInit (
	OUT _pkcs11h_mutex_t * const mutex
);

CK_RV
_pkcs11h_threading_mutexLock (
	IN OUT _pkcs11h_mutex_t *const mutex
);

CK_RV
_pkcs11h_threading_mutexRelease (
	IN OUT _pkcs11h_mutex_t *const mutex
);

CK_RV
_pkcs11h_threading_mutexFree (
	IN OUT _pkcs11h_mutex_t *const mutex
);

CK_RV
_pkcs11h_threading_condSignal (
	IN OUT _pkcs11h_cond_t *const cond
);

CK_RV
_pkcs11h_threading_condInit (
	OUT _pkcs11h_cond_t * const cond
);

CK_RV
_pkcs11h_threading_condWait (
	IN OUT _pkcs11h_cond_t *const cond,
	IN const unsigned milli
);

CK_RV
_pkcs11h_threading_condFree (
	IN OUT _pkcs11h_cond_t *const cond
);

CK_RV
_pkcs11h_threading_threadStart (
	OUT _pkcs11h_thread_t * const thread,
	IN _pkcs11h_thread_start_t const start,
	IN void * data
);

CK_RV
_pkcs11h_threading_threadJoin (
	IN _pkcs11h_thread_t * const thread
);

#if !defined(_WIN32)
void
_pkcs1h_threading_mutexLockAll (void);

void
_pkcs1h_threading_mutexReleaseAll (void);
#endif

#endif

#endif

