#include "../../config.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#if defined(_WIN32)
#include <conio.h>
#else
#include <unistd.h>
#endif

#if !(defined(ENABLE_PKCS11H_CERTIFICATE) && (defined(ENABLE_PKCS11H_ENGINE_OPENSSL) || defined (ENABLE_PKCS11H_ENGINE_GNUTLS) || defined(ENABLE_PKCS11H_ENGINE_WIN32)))
int main () {
	printf ("!win32, certificate, enum and crypto engine interfaces should be enabled for this test");
	exit (0);
	return 0;
}
#else

#include <pkcs11-helper-1.0/pkcs11h-certificate.h>
#include <unistd.h>

static
void
fatal (const char * const m, CK_RV rv) {
	fprintf (stderr, "%s - %lu - %s\n", m, rv, pkcs11h_getMessage (rv));
	exit (1);
}

static
void
mypause (const char * const m) {
	char temp[10];

	fprintf (stdout, "%s", m);
	fflush (stdout);
	fgets (temp, sizeof (temp), stdin);
}

static
void
_pkcs11h_hooks_log (
	IN void * const global_data,
	IN unsigned flags,
	IN const char * const format,
	IN va_list args
) {
	vfprintf (stdout, format, args);
	fprintf (stdout, "\n");
	fflush (stdout);
}

static
PKCS11H_BOOL
_pkcs11h_hooks_token_prompt (
	IN void * const global_data,
	IN void * const user_data,
	IN const pkcs11h_token_id_t token,
	IN const unsigned retry
) {
	char buf[1024];
	PKCS11H_BOOL fValidInput = FALSE;
	PKCS11H_BOOL fRet = FALSE;

	while (!fValidInput) {
		fprintf (stderr, "Please insert token '%s' 'ok' or 'cancel': ", token->display);
		fgets (buf, sizeof (buf), stdin);
		buf[sizeof (buf)-1] = '\0';
		fflush (stdin);

		if (buf[strlen (buf)-1] == '\n') {
			buf[strlen (buf)-1] = '\0';
		}
		if (buf[strlen (buf)-1] == '\r') {
			buf[strlen (buf)-1] = '\0';
		}

		if (!strcmp (buf, "ok")) {
			fValidInput = TRUE;
			fRet = TRUE;
		}
		else if (!strcmp (buf, "cancel")) {
			fValidInput = TRUE;
		}
	}

	return fRet; 
}

static
PKCS11H_BOOL
_pkcs11h_hooks_pin_prompt (
	IN void * const global_data,
	IN void * const user_data,
	IN const pkcs11h_token_id_t token,
	IN const unsigned retry,
	OUT char * const pin,
	IN const size_t pin_max
) {
	char prompt[1024];
	char *p = NULL;

	snprintf (prompt, sizeof (prompt), "Please enter '%s' PIN or 'cancel': ", token->display);

#if defined(_WIN32)
	{
		size_t i = 0;
		char c;
		while (i < pin_max && (c = getch ()) != '\r') {
			pin[i++] = c;
		}
	}

	fprintf (stderr, "\n");
#else
	p = getpass (prompt);
#endif

	strncpy (pin, p, pin_max);
	pin[pin_max-1] = '\0';

	return strcmp (pin, "cancel") != 0;
}

void
sign_test (const pkcs11h_certificate_t cert) {

	static unsigned const char sha1_data[] = {
		0x30, 0x21, 0x30, 0x09, 0x06, 0x05, 0x2b, 0x0e, 0x03, /* 1.3.14.3.2.26 */
		0x02, 0x1a, 0x05, 0x00, 0x04, 0x14,
		0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07,	/* dummy data */
		0x08, 0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e, 0x0f,
		0x10, 0x11, 0x12, 0x13, 0x14
	};

	CK_RV rv;
					 
	unsigned char *blob;
	size_t blob_size;

	if (
		(rv = pkcs11h_certificate_signAny (
			cert,
			CKM_RSA_PKCS,
			sha1_data,
			sizeof (sha1_data),
			NULL,
			&blob_size
		)) != CKR_OK
	) {
		fatal ("pkcs11h_certificate_sign(1) failed", rv);
	}

	blob = (unsigned char *)malloc (blob_size);

	if (
		(rv = pkcs11h_certificate_signAny (
			cert,
			CKM_RSA_PKCS,
			sha1_data,
			sizeof (sha1_data),
			blob,
			&blob_size
		)) != CKR_OK
	) {
		fatal ("pkcs11h_certificate_sign(1) failed", rv);
	}

	free (blob);
}

int main () {
	pkcs11h_certificate_id_list_t issuers, certs, temp;
	pkcs11h_certificate_t cert;
	CK_RV rv;

	printf ("Initializing pkcs11-helper\n");

	if ((rv = pkcs11h_initialize ()) != CKR_OK) {
		fatal ("pkcs11h_initialize failed", rv);
	}

	printf ("Registering pkcs11-helper hooks\n");

	if ((rv = pkcs11h_setLogHook (_pkcs11h_hooks_log, NULL)) != CKR_OK) {
		fatal ("pkcs11h_setLogHook failed", rv);
	}

	pkcs11h_setLogLevel (TEST_LOG_LEVEL);

	if ((rv = pkcs11h_setTokenPromptHook (_pkcs11h_hooks_token_prompt, NULL)) != CKR_OK) {
		fatal ("pkcs11h_setTokenPromptHook failed", rv);
	}

	if ((rv = pkcs11h_setPINPromptHook (_pkcs11h_hooks_pin_prompt, NULL)) != CKR_OK) {
		fatal ("pkcs11h_setPINPromptHook failed", rv);
	}

	printf ("Adding provider '%s'\n", TEST_PROVIDER);

	if (
		(rv = pkcs11h_addProvider (
			TEST_PROVIDER,
			TEST_PROVIDER,
			FALSE,
			PKCS11H_PRIVATEMODE_MASK_AUTO,
			PKCS11H_SLOTEVENT_METHOD_AUTO,
			0,
			FALSE
		)) != CKR_OK
	) {
		fatal ("pkcs11h_addProvider failed", rv);
	}

	mypause ("Please remove all tokens, press <Enter>: ");

	printf ("Enumerating token certificate (list should be empty, no prompt)\n");

	if (
		(rv = pkcs11h_certificate_enumCertificateIds (
			PKCS11H_ENUM_METHOD_CACHE,
			NULL,
			PKCS11H_PROMPT_MASK_ALLOW_ALL,
			&issuers,
			&certs
		)) != CKR_OK
	) {
		fatal ("pkcs11h_certificate_enumCertificateIds failed", rv);
	}

	if (issuers != NULL || certs != NULL) {
		fatal ("No certificates should be found", rv);
	}

	mypause ("Please insert token, press <Enter>: ");

	printf ("Getting certificate cache, should be available certificates\n");

	if (
		(rv = pkcs11h_certificate_enumCertificateIds (
			PKCS11H_ENUM_METHOD_CACHE,
			NULL,
			PKCS11H_PROMPT_MASK_ALLOW_ALL,
			&issuers,
			&certs
		)) != CKR_OK
	) {
		fatal ("pkcs11h_certificate_enumCertificateIds failed", rv);
	}

	for (temp = issuers;temp != NULL;temp = temp->next) {
		printf ("Issuer: %s\n", temp->certificate_id->displayName);
	}
	for (temp = certs;temp != NULL;temp = temp->next) {
		printf ("Certificate: %s\n", temp->certificate_id->displayName);
	}

	if (certs == NULL) {
		fatal ("No certificates found", rv);
	}

	pkcs11h_certificate_freeCertificateIdList (issuers);
	pkcs11h_certificate_freeCertificateIdList (certs);

	mypause ("Please remove token, press <Enter>: ");

	printf ("Getting certificate cache, should be similar to last\n");

	if (
		(rv = pkcs11h_certificate_enumCertificateIds (
			PKCS11H_ENUM_METHOD_CACHE,
			NULL,
			PKCS11H_PROMPT_MASK_ALLOW_ALL,
			&issuers,
			&certs
		)) != CKR_OK
	) {
		fatal ("pkcs11h_certificate_enumCertificateIds failed", rv);
	}

	for (temp = issuers;temp != NULL;temp = temp->next) {
		printf ("Issuer: %s\n", temp->certificate_id->displayName);
	}
	for (temp = certs;temp != NULL;temp = temp->next) {
		printf ("Certificate: %s\n", temp->certificate_id->displayName);
	}

	if (certs == NULL) {
		fatal ("No certificates found", rv);
	}

	printf ("Creating certificate context\n");

	if (
		(rv = pkcs11h_certificate_create (
			certs->certificate_id,
			NULL,
			PKCS11H_PROMPT_MASK_ALLOW_ALL,
			PKCS11H_PIN_CACHE_INFINITE,
			&cert
		)) != CKR_OK
	) {
		fatal ("pkcs11h_certificate_create failed", rv);
	}

	printf ("Perforing signature #1 (you should be prompt for token and PIN)\n");

	sign_test (cert);

	printf ("Perforing signature #2 (you should NOT be prompt for anything)\n");

	sign_test (cert);

	mypause ("Please remove and insert token, press <Enter>: ");

	printf ("Perforing signature #3 (you should be prompt only for PIN)\n");

	sign_test (cert);

	printf ("Perforing signature #4 (you should NOT be prompt for anything)\n");

	if ((rv = pkcs11h_certificate_freeCertificate (cert)) != CKR_OK) {
		fatal ("pkcs11h_certificate_free failed", rv);
	}

	if (
		(rv = pkcs11h_certificate_create (
			certs->certificate_id,
			NULL,
			PKCS11H_PROMPT_MASK_ALLOW_ALL,
			PKCS11H_PIN_CACHE_INFINITE,
			&cert
		)) != CKR_OK
	) {
		fatal ("pkcs11h_certificate_create failed", rv);
	}

	sign_test (cert);

	printf ("Terminating pkcs11-helper\n");

	if ((rv = pkcs11h_certificate_freeCertificate (cert)) != CKR_OK) {
		fatal ("pkcs11h_certificate_free failed", rv);
	}

	pkcs11h_certificate_freeCertificateIdList (issuers);
	pkcs11h_certificate_freeCertificateIdList (certs);

	if ((rv = pkcs11h_terminate ()) != CKR_OK) {
		fatal ("pkcs11h_terminate failed", rv);
	}

	exit (0);
	return 0;
}

#endif
