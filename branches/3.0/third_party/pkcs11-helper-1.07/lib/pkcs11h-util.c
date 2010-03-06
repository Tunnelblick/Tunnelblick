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
#include "_pkcs11h-util.h"

void
_pkcs11h_util_fixupFixedString (
	OUT char * const target,			/* MUST BE >= length+1 */
	IN const char * const source,
	IN const size_t length				/* FIXED STRING LENGTH */
) {
	char *p;

	_PKCS11H_ASSERT (source!=NULL);
	_PKCS11H_ASSERT (target!=NULL);
	
	p = target+length;
	memmove (target, source, length);
	*p = '\0';
	p--;
	while (p >= target && *p == ' ') {
		*p = '\0';
		p--;
	}
}

CK_RV
_pkcs11h_util_hexToBinary (
	OUT unsigned char * const target,
	IN const char * const source,
	IN OUT size_t * const p_target_size
) {
	size_t target_max_size;
	const char *p;
	char buf[3] = {'\0', '\0', '\0'};
	int i = 0;

	_PKCS11H_ASSERT (source!=NULL);
	_PKCS11H_ASSERT (target!=NULL);
	_PKCS11H_ASSERT (p_target_size!=NULL);

	target_max_size = *p_target_size;
	p = source;
	*p_target_size = 0;

	while (*p != '\x0' && *p_target_size < target_max_size) {
		if (isxdigit ((unsigned char)*p)) {
			buf[i%2] = *p;

			if ((i%2) == 1) {
				unsigned v;
				if (sscanf (buf, "%x", &v) != 1) {
					v = 0;
				}
				target[*p_target_size] = (char)(v & 0xff);
				(*p_target_size)++;
			}

			i++;
		}
		p++;
	}

	if (*p != '\x0') {
		return CKR_ATTRIBUTE_VALUE_INVALID;
	}
	else {
		return CKR_OK;
	}
}

CK_RV
_pkcs11h_util_binaryToHex (
	OUT char * const target,
	IN const size_t target_size,
	IN const unsigned char * const source,
	IN const size_t source_size
) {
	static const char *x = "0123456789ABCDEF";
	size_t i;

	_PKCS11H_ASSERT (target!=NULL);
	_PKCS11H_ASSERT (source!=NULL);

	if (target_size < source_size * 2 + 1) {
		return CKR_ATTRIBUTE_VALUE_INVALID;
	}

	for (i=0;i<source_size;i++) {
		target[i*2] =   x[(source[i]&0xf0)>>4];
		target[i*2+1] = x[(source[i]&0x0f)>>0];
	}
	target[source_size*2] = '\x0';

	return CKR_OK;
}

CK_RV
_pkcs11h_util_escapeString (
	IN OUT char * const target,
	IN const char * const source,
	IN size_t * const max,
	IN const char * const invalid_chars
) {
	static const char *x = "0123456789ABCDEF";
	CK_RV rv = CKR_FUNCTION_FAILED;
	const char *s = source;
	char *t = target;
	size_t n = 0;

	/*_PKCS11H_ASSERT (target!=NULL); Not required*/
	_PKCS11H_ASSERT (source!=NULL);
	_PKCS11H_ASSERT (max!=NULL);

	while (*s != '\x0') {

		if (*s == '\\' || strchr (invalid_chars, *s) || !isgraph (*s)) {
			if (t != NULL) {
				if (n+4 > *max) {
					rv = CKR_ATTRIBUTE_VALUE_INVALID;
					goto cleanup;
				}
				else {
					t[0] = '\\';
					t[1] = 'x';
					t[2] = x[(*s&0xf0)>>4];
					t[3] = x[(*s&0x0f)>>0];
					t+=4;
				}
			}
			n+=4;
		}
		else {
			if (t != NULL) {
				if (n+1 > *max) {
					rv = CKR_ATTRIBUTE_VALUE_INVALID;
					goto cleanup;
				}
				else {
					*t = *s;
					t++;
				}
			}
			n+=1;
		}

		s++;
	}

	if (t != NULL) {
		if (n+1 > *max) {
			rv = CKR_ATTRIBUTE_VALUE_INVALID;
			goto cleanup;
		}
		else {
			*t = '\x0';
			t++;
		}
	}
	n++;

	*max = n;
	rv = CKR_OK;

cleanup:

	return rv;
}

CK_RV
_pkcs11h_util_unescapeString (
	IN OUT char * const target,
	IN const char * const source,
	IN size_t * const max
) {
	CK_RV rv = CKR_FUNCTION_FAILED;
	const char *s = source;
	char *t = target;
	size_t n = 0;

	/*_PKCS11H_ASSERT (target!=NULL); Not required*/
	_PKCS11H_ASSERT (source!=NULL);
	_PKCS11H_ASSERT (max!=NULL);

	while (*s != '\x0') {
		if (*s == '\\') {
			if (t != NULL) {
				if (n+1 > *max) {
					rv = CKR_ATTRIBUTE_VALUE_INVALID;
					goto cleanup;
				}
				else {
					char b[3];
					unsigned u;
					b[0] = s[2];
					b[1] = s[3];
					b[2] = '\x0';
					sscanf (b, "%08x", &u);
					*t = (char)(u & 0xff);
					t++;
				}
			}
			s+=4;
		}
		else {
			if (t != NULL) {
				if (n+1 > *max) {
					rv = CKR_ATTRIBUTE_VALUE_INVALID;
					goto cleanup;
				}
				else {
					*t = *s;
					t++;
				}
			}
			s++;
		}

		n+=1;
	}

	if (t != NULL) {
		if (n+1 > *max) {
			rv = CKR_ATTRIBUTE_VALUE_INVALID;
			goto cleanup;
		}
		else {
			*t = '\x0';
			t++;
		}
	}
	n++;

	*max = n;
	rv = CKR_OK;

cleanup:

	return rv;
}

