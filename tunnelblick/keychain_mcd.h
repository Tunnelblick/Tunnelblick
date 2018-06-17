/*
 *  Copyright 2017 Pavel Kondratiev <kaloprominat@yandex.ru>
 *  All rights reserved.
 *
 *  This file is part of Tunnelblick.
 *
 *  Tunnelblick is free software: you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License version 2
 *  as published by the Free Software Foundation.
 *
 *  Tunnelblick is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License
 *  along with this program (see the file COPYING included with this
 *  distribution); if not, write to the Free Software Foundation, Inc.,
 *  59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
 *  or see http://www.gnu.org/licenses/.
 */


#ifndef keychain_mcd_h
#define keychain_mcd_h

#include <stdio.h>

#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <sys/un.h>
#include <err.h>
#include <netdb.h>

#include <Security/Security.h>
#include <CoreServices/CoreServices.h>

#include "cert_data.h"
#include "crypto_osx.h"
#include "base64.h"

typedef enum
{
    templateSearchResultSuccess,
    templateSearchResultNotFound,
    templateSearchResultBadTemplate
} keychainMcdTemplateSearchResult;

typedef enum {
    getCertificateResultSuccess,
    getCertificateResultNull,
    getCertificateResultError
} keychainMcdGetCertificateResult;

typedef enum {
    rsasignResultSuccess,
    rsasignResultError,
    rsasignResultB64Error
} keychainMcdRsasignResult;


SecIdentityRef template_to_identity(const char *template, keychainMcdTemplateSearchResult *result);
char * get_certificate(SecIdentityRef identity, keychainMcdGetCertificateResult *result);
char * rsasign(SecIdentityRef identity, const char *input, keychainMcdRsasignResult *result);

#endif /* keychain_mcd_h */