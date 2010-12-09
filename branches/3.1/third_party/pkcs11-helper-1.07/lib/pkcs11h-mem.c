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

#include "_pkcs11h-sys.h"
#include "_pkcs11h-mem.h"

CK_RV
_pkcs11h_mem_malloc (
	OUT const void * * const p,
	IN const size_t s
) {
	CK_RV rv = CKR_OK;

	_PKCS11H_ASSERT (p!=NULL);
	_PKCS11H_ASSERT (s!=0);

	*p = NULL;

	if (s > 0) {
		if (
			(*p = (void *)_g_pkcs11h_sys_engine.malloc (s)) == NULL
		) {
			rv = CKR_HOST_MEMORY;
		}
		else {
			memset ((void *)*p, 0, s);
		}
	}

	return rv;
}

CK_RV
_pkcs11h_mem_free (
	IN const void * * const  p
) {
	_PKCS11H_ASSERT (p!=NULL);

	_g_pkcs11h_sys_engine.free ((void *)*p);
	*p = NULL;

	return CKR_OK;
}

CK_RV
_pkcs11h_mem_strdup (
	OUT const char * * const dest,
	IN const char * const src
) {
	return _pkcs11h_mem_duplicate (
		(void *)dest,
		NULL,
		src,
		strlen (src)+1
	);
}

CK_RV
_pkcs11h_mem_duplicate (
	OUT const void * * const dest,
	OUT size_t * const p_dest_size,
	IN const void * const src,
	IN const size_t mem_size
) {
	CK_RV rv = CKR_FUNCTION_FAILED;

	_PKCS11H_ASSERT (dest!=NULL);
	/*_PKCS11H_ASSERT (dest_size!=NULL); NOT NEEDED*/
	_PKCS11H_ASSERT (!(mem_size!=0&&src==NULL));

	*dest = NULL;
	if (p_dest_size != NULL) {
		*p_dest_size = 0;
	}

	if (src != NULL) {
		if ((rv = _pkcs11h_mem_malloc (dest, mem_size)) != CKR_OK) {
			goto cleanup;
		}

		if (p_dest_size != NULL) {
			*p_dest_size = mem_size;
		}
		memmove ((void*)*dest, src, mem_size);
	}

	rv = CKR_OK;

cleanup:

	return rv;
}

