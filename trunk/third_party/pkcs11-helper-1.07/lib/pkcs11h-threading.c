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

#if defined(ENABLE_PKCS11H_THREADING)

#if defined(_WIN32)
#include <process.h>
#else
#include <signal.h>
#endif

#include "_pkcs11h-sys.h"
#include "_pkcs11h-mem.h"
#include "_pkcs11h-threading.h"

typedef struct {
	_pkcs11h_thread_start_t start;
	void *data;
} ___pkcs11h_thread_data_t;

/*==========================================
 * Static data
 */

#if !defined(_WIN32)
typedef struct __pkcs11h_threading_mutex_entry_s {
	struct __pkcs11h_threading_mutex_entry_s *next;
	_pkcs11h_mutex_t *p_mutex;
	PKCS11H_BOOL locked;
} *__pkcs11h_threading_mutex_entry_t;

static struct {
	_pkcs11h_mutex_t mutex;
	__pkcs11h_threading_mutex_entry_t head;
} __s_pkcs11h_threading_mutex_list = {
	PTHREAD_MUTEX_INITIALIZER,
	NULL
};
#endif

void
_pkcs11h_threading_sleep (
	IN const unsigned milli
) {
	_g_pkcs11h_sys_engine.usleep (milli*1000);
}

CK_RV
_pkcs11h_threading_mutexInit (
	OUT _pkcs11h_mutex_t * const mutex
) {
	CK_RV rv = CKR_FUNCTION_FAILED;

#if defined(_WIN32)
	if ((*mutex = CreateMutex (NULL, FALSE, NULL)) == NULL) {
		rv = CKR_FUNCTION_FAILED;
		goto cleanup;
	}

	rv = CKR_OK;

cleanup:

#else
	{
		__pkcs11h_threading_mutex_entry_t entry = NULL;
		PKCS11H_BOOL mutex_locked = FALSE;

		if ((rv = _pkcs11h_threading_mutexLock (&__s_pkcs11h_threading_mutex_list.mutex)) != CKR_OK) {
			goto cleanup;
		}
		mutex_locked = TRUE;
		
		if (
			(rv = _pkcs11h_mem_malloc (
				(void *)&entry,
				sizeof (struct __pkcs11h_threading_mutex_entry_s)
			)) != CKR_OK
		) {
			goto cleanup;
		}

		if (pthread_mutex_init (mutex, NULL)) {
			rv = CKR_FUNCTION_FAILED;
			goto cleanup;
		}

		entry->p_mutex = mutex;
		entry->next = __s_pkcs11h_threading_mutex_list.head;
		__s_pkcs11h_threading_mutex_list.head = entry;
		entry = NULL;
		rv = CKR_OK;

	cleanup:
		if (entry != NULL) {
			_pkcs11h_mem_free ((void *)&entry);
		}

		if (mutex_locked) {
			_pkcs11h_threading_mutexRelease (&__s_pkcs11h_threading_mutex_list.mutex);
			mutex_locked = FALSE;
		}
	}
#endif
	return rv;
}

CK_RV
_pkcs11h_threading_mutexLock (
	IN OUT _pkcs11h_mutex_t *const mutex
) {
	CK_RV rv = CKR_FUNCTION_FAILED;
#if defined(_WIN32)
	if (WaitForSingleObject (*mutex, INFINITE) == WAIT_FAILED) {
		rv = CKR_FUNCTION_FAILED;
		goto cleanup;
	}
#else
	if (pthread_mutex_lock (mutex)) {
		goto cleanup;
	}
#endif
	rv = CKR_OK;
cleanup:
	return rv;
}

CK_RV
_pkcs11h_threading_mutexRelease (
	IN OUT _pkcs11h_mutex_t *const mutex
) {
	CK_RV rv = CKR_FUNCTION_FAILED;
#if defined(_WIN32)
	if (!ReleaseMutex (*mutex)) {
		rv = CKR_FUNCTION_FAILED;
		goto cleanup;
	}
#else
	if (pthread_mutex_unlock (mutex)) {
		rv = CKR_FUNCTION_FAILED;
		goto cleanup;
	}
#endif
	rv = CKR_OK;
cleanup:
	return rv;
}

CK_RV
_pkcs11h_threading_mutexFree (
	IN OUT _pkcs11h_mutex_t *const mutex
) {
#if defined(_WIN32)
	if (*mutex != NULL) {
		CloseHandle (*mutex);
		*mutex = NULL;
	}
#else
	{
		__pkcs11h_threading_mutex_entry_t last = NULL;
		__pkcs11h_threading_mutex_entry_t entry = NULL;
		PKCS11H_BOOL mutex_locked = FALSE;

		if (_pkcs11h_threading_mutexLock (&__s_pkcs11h_threading_mutex_list.mutex) != CKR_OK) {
			goto cleanup;
		}
		mutex_locked = TRUE;

		entry =  __s_pkcs11h_threading_mutex_list.head;
		while (
			entry != NULL &&
			entry->p_mutex != mutex
		) {
			last = entry;
			entry = entry->next;
		}

		if (entry != NULL) {
			if (last == NULL) {
				__s_pkcs11h_threading_mutex_list.head = entry->next;
			}
			else {
				last->next = entry->next;
			}
			_pkcs11h_mem_free ((void *)&entry);
		}

		pthread_mutex_destroy (mutex);

cleanup:
		if (mutex_locked) {
			_pkcs11h_threading_mutexRelease (&__s_pkcs11h_threading_mutex_list.mutex);
			mutex_locked = FALSE;
		}
	}
#endif
	return CKR_OK;
}

#if !defined(_WIN32)
/*
 * This function is required in order
 * to lock all mutexes before fork is called,
 * and to avoid dedlocks.
 * The loop is required because there is no
 * way to lock all mutex in one system call...
 */
void
_pkcs1h_threading_mutexLockAll (void) {
	__pkcs11h_threading_mutex_entry_t entry = NULL;
	PKCS11H_BOOL mutex_locked = FALSE;
	PKCS11H_BOOL all_mutexes_locked = FALSE;

	if (_pkcs11h_threading_mutexLock (&__s_pkcs11h_threading_mutex_list.mutex) != CKR_OK) {
		goto cleanup;
	}
	mutex_locked = TRUE;

	for (
		entry = __s_pkcs11h_threading_mutex_list.head;
		entry != NULL;
		entry = entry->next
	) {
		entry->locked = FALSE;
	}

	while (!all_mutexes_locked) {
		PKCS11H_BOOL ok = TRUE;
		
		for (
			entry = __s_pkcs11h_threading_mutex_list.head;
			entry != NULL && ok;
			entry = entry->next
		) {
			if (!pthread_mutex_trylock (entry->p_mutex)) {
				entry->locked = TRUE;
			}
			else {
				ok = FALSE;
			}
		}

		if (!ok) {
			for (
				entry = __s_pkcs11h_threading_mutex_list.head;
				entry != NULL;
				entry = entry->next
			) {
				if (entry->locked == TRUE) {
					pthread_mutex_unlock (entry->p_mutex);
					entry->locked = FALSE;
				}
			}

			_pkcs11h_threading_mutexRelease (&__s_pkcs11h_threading_mutex_list.mutex);
			_pkcs11h_threading_sleep (1000);
			_pkcs11h_threading_mutexLock (&__s_pkcs11h_threading_mutex_list.mutex);
		}
		else {
			all_mutexes_locked  = TRUE;
		}
	}

cleanup:

	if (mutex_locked) {
		_pkcs11h_threading_mutexRelease (&__s_pkcs11h_threading_mutex_list.mutex);
		mutex_locked = FALSE;
	}
}

void
_pkcs1h_threading_mutexReleaseAll (void) {
	__pkcs11h_threading_mutex_entry_t entry = NULL;
	PKCS11H_BOOL mutex_locked = FALSE;

	if (_pkcs11h_threading_mutexLock (&__s_pkcs11h_threading_mutex_list.mutex) != CKR_OK) {
		goto cleanup;
	}
	mutex_locked = TRUE;

	for (
		entry = __s_pkcs11h_threading_mutex_list.head;
		entry != NULL;
		entry = entry->next
	) {
		pthread_mutex_unlock (entry->p_mutex);
		entry->locked = FALSE;
	}

cleanup:

	if (mutex_locked) {
		_pkcs11h_threading_mutexRelease (&__s_pkcs11h_threading_mutex_list.mutex);
		mutex_locked = FALSE;
	}
}
#endif

CK_RV
_pkcs11h_threading_condSignal (
	IN OUT _pkcs11h_cond_t *const cond
) {
	CK_RV rv = CKR_FUNCTION_FAILED;

#if defined(_WIN32)
	if (!SetEvent (*cond)) {
		rv = CKR_FUNCTION_FAILED;
		goto cleanup;
	}
#else
	if (
		(
			pthread_mutex_lock (&cond->mut) ||
			pthread_cond_signal (&cond->cond) ||
			pthread_mutex_unlock (&cond->mut)
		)
	) {
		rv = CKR_FUNCTION_FAILED;
		goto cleanup;
	}
#endif
	rv = CKR_OK;
cleanup:
	return rv;
}

CK_RV
_pkcs11h_threading_condInit (
	OUT _pkcs11h_cond_t * const cond
) {
	CK_RV rv = CKR_FUNCTION_FAILED;
#if defined(_WIN32)
	if ((*cond = CreateEvent (NULL, FALSE, FALSE, NULL)) == NULL) {
		rv = CKR_FUNCTION_FAILED;
		goto cleanup;
	}
#else
	if (
		(
			pthread_mutex_init (&cond->mut, NULL) ||
			pthread_cond_init (&cond->cond, NULL) ||
			pthread_mutex_lock (&cond->mut)
		)
	) {
		rv = CKR_FUNCTION_FAILED;
		goto cleanup;
	}
#endif
	rv = CKR_OK;
cleanup:
	return rv;
}

CK_RV
_pkcs11h_threading_condWait (
	IN OUT _pkcs11h_cond_t *const cond,
	IN const unsigned milli
) {
	CK_RV rv = CKR_FUNCTION_FAILED;

#if defined(_WIN32)
	DWORD dwMilli;

	if (milli == PKCS11H_COND_INFINITE) {
		dwMilli = INFINITE;
	}
	else {
		dwMilli = milli;
	}

	if (WaitForSingleObject (*cond, dwMilli) == WAIT_FAILED) {
		rv = CKR_FUNCTION_FAILED;
		goto cleanup;
	}
#else
	if (milli == PKCS11H_COND_INFINITE) {
		if (pthread_cond_wait (&cond->cond, &cond->mut)	) {
			rv = CKR_FUNCTION_FAILED;
			goto cleanup;
		}
	}
	else {
		struct timeval now;
		struct timespec timeout;

		if (_g_pkcs11h_sys_engine.gettimeofday (&now)) {
			rv = CKR_FUNCTION_FAILED;
			goto cleanup;
		}
		
		timeout.tv_sec = now.tv_sec + milli/1000;
		timeout.tv_nsec = now.tv_usec*1000 + milli%1000;
		
		if (pthread_cond_timedwait (&cond->cond, &cond->mut, &timeout)) {
			rv = CKR_FUNCTION_FAILED;
			goto cleanup;
		}
	}
#endif
	rv = CKR_OK;
cleanup:
	return rv;
}

CK_RV
_pkcs11h_threading_condFree (
	IN OUT _pkcs11h_cond_t *const cond
) {
#if defined(_WIN32)
	CloseHandle (*cond);
	*cond = NULL;
#else
	pthread_mutex_unlock (&cond->mut);
#endif
	return CKR_OK;
}

#if defined(_WIN32)
static
unsigned
__stdcall
___pkcs11h_thread_start (void *p) {
	___pkcs11h_thread_data_t *_data = (___pkcs11h_thread_data_t *)p;
	unsigned ret;

	ret = (unsigned)(_data->start (_data->data) - (void*)0);

	_pkcs11h_mem_free ((void *)&_data);

	return ret;
}
#else
static
void *
___pkcs11h_thread_start (void *p) {
	___pkcs11h_thread_data_t *_data = (___pkcs11h_thread_data_t *)p;
	sigset_t signal_mask;
	void *ret;
	int i;

	/*
	 * Ignore any signal in
	 * this thread
	 */
	sigemptyset (&signal_mask);
	for (i=1;i<16;i++) {
		sigaddset (&signal_mask, i);
	}
	pthread_sigmask (SIG_SETMASK, &signal_mask, NULL);

	ret = _data->start (_data->data);

	_pkcs11h_mem_free ((void *)&_data);

	return ret;
}
#endif

CK_RV
_pkcs11h_threading_threadStart (
	OUT _pkcs11h_thread_t * const thread,
	IN _pkcs11h_thread_start_t const start,
	IN void * data
) {
	___pkcs11h_thread_data_t *_data = NULL;
	CK_RV rv = CKR_FUNCTION_FAILED;

	if (
		(rv = _pkcs11h_mem_malloc (
			(void *)&_data,
			sizeof (___pkcs11h_thread_data_t)
		)) != CKR_OK
	) {
		goto cleanup;
	}

	_data->start = start;
	_data->data = data;

#if defined(_WIN32)
	{
		unsigned tmp;

		if (
			(*thread = (HANDLE)_beginthreadex (
				NULL,
				0,
				___pkcs11h_thread_start,
				_data,
				0,
				&tmp
			)) == NULL
		) {
			rv = CKR_FUNCTION_FAILED;
			goto cleanup;
		}
	}
#else
	if (pthread_create (thread, NULL, ___pkcs11h_thread_start, _data)) {
		rv = CKR_FUNCTION_FAILED;
		goto cleanup;
	}
#endif
	rv = CKR_OK;
cleanup:
	return rv;
}

CK_RV
_pkcs11h_threading_threadJoin (
	IN _pkcs11h_thread_t * const thread
) {
#if defined(_WIN32)
	WaitForSingleObject (*thread, INFINITE);
	CloseHandle (*thread);
	*thread = NULL;
#else
	pthread_join (*thread, NULL);
	*thread = 0l;
#endif
	return CKR_OK;
}

#endif
