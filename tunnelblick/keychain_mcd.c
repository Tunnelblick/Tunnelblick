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

/*
 *  This file contains modified functions from openvpn keychain-mcd main.c module
 *  https://github.com/OpenVPN/openvpn/blob/master/contrib/keychain-mcd/main.c
 */

#include "keychain_mcd.h"

SecIdentityRef template_to_identity(const char *template, keychainMcdTemplateSearchResult *result) {
    SecIdentityRef identity;
    CertDataRef pCertDataTemplate = createCertDataFromString(template);
    if (pCertDataTemplate == NULL)
    {
        *result = templateSearchResultBadTemplate;
        return NULL;
    }
    identity = findIdentity(pCertDataTemplate);
    if (identity == NULL)
    {
        *result = templateSearchResultNotFound;
        return NULL;
    }
    destroyCertData(pCertDataTemplate);
    result = templateSearchResultSuccess;
    return identity;
}

char * get_certificate(SecIdentityRef identity, keychainMcdGetCertificateResult *result) {

    OSStatus status;
    SecCertificateRef certificate = NULL;
    CFDataRef data;
    const unsigned char *cert;
    size_t cert_len;
    char *result_b64;

    status = SecIdentityCopyCertificate(identity, &certificate);
    if (status != noErr)
    {
        *result = getCertificateResultError;
        return strdup(GetMacOSStatusErrorString(status));
    }

    data = SecCertificateCopyData(certificate);
    if (data == NULL)
    {
        *result = getCertificateResultNull;
        return NULL;
    }

    cert = CFDataGetBytePtr(data);
    cert_len = CFDataGetLength(data);

    base64_encode(cert, cert_len, &result_b64);
#if 0
    fprintf(stderr, "certificate %s\n", result_b64);
#endif

    CFRelease(data);
    CFRelease(certificate);

    *result = getCertificateResultSuccess;
    return result_b64;
}

char * rsasign(SecIdentityRef identity, const char *input, keychainMcdRsasignResult *result) {

    const char *input_b64 = strchr(input, ':') + 1;
    char *input_binary;
    int input_len;
    char *output_binary;
    size_t output_len;
    char *output_b64;

    input_len = strlen(input_b64)*8/6 + 4;
    input_binary = malloc(input_len);
    input_len = base64_decode(input_b64, input_binary, input_len);

    if (input_len < 0)
    {
        *result = rsasignResultB64Error;
        return NULL;
    }

    output_len = 1024;
    output_binary = malloc(output_len);
    signData(identity, (const uint8_t *)input_binary, input_len, (uint8_t *)output_binary, &output_len);
    if (output_len == 0)
    {
        *result = rsasignResultError;
        return NULL;
    }

    base64_encode(output_binary, output_len, &output_b64);

    free(input_binary);
    free(output_binary);

    *result = rsasignResultSuccess;
    return output_b64;

}