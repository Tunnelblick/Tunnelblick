#include "../../config.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#if !defined(ENABLE_PKCS11H_SLOTEVENT)
int main () {
	printf ("!win32, certificate, enum and crypto engine interfaces should be enabled for this test");
	exit (0);
	return 0;
}
#else

#if defined(_WIN32)
#include <windows.h>
#else
#include <unistd.h>
#endif

#include <pkcs11-helper-1.0/pkcs11h-core.h>

static
void
fatal (const char * const m, CK_RV rv) {
	fprintf (stderr, "%s - %08lu - %s\n", m, rv, pkcs11h_getMessage (rv));
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
void
_pkcs11h_hooks_slotevent (
	IN void * const global_data
) {
	printf ("slotevent\n");
}

int main () {
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

	if ((rv = pkcs11h_setSlotEventHook (_pkcs11h_hooks_slotevent, NULL)) != CKR_OK) {
		fatal ("pkcs11h_setSlotEventHook failed", rv);
	}

	printf ("Adding provider '%s' as auto\n", TEST_PROVIDER);

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

	printf ("Please remove and insert tokens (pause for 30 seconds)\n");

#if defined(_WIN32)
	Sleep (30*1024);
#else
	sleep (30);
#endif

	if ((rv = pkcs11h_removeProvider (TEST_PROVIDER)) != CKR_OK) {
		fatal ("pkcs11h_removeProvider failed", rv);
	}

	printf ("Adding provider '%s' as trigger\n", TEST_PROVIDER);

	if (
		(rv = pkcs11h_addProvider (
			TEST_PROVIDER,
			TEST_PROVIDER,
			FALSE,
			PKCS11H_PRIVATEMODE_MASK_AUTO,
			PKCS11H_SLOTEVENT_METHOD_TRIGGER,
			0,
			FALSE
		)) != CKR_OK
	) {
		fatal ("pkcs11h_addProvider failed", rv);
	}

	printf ("Please remove and insert tokens (pause for 30 seconds)\n");

#if defined(_WIN32)
	Sleep (30*1024);
#else
	sleep (30);
#endif

	if ((rv = pkcs11h_removeProvider (TEST_PROVIDER)) != CKR_OK) {
		fatal ("pkcs11h_removeProvider failed", rv);
	}

	printf ("Adding provider '%s' as poll\n", TEST_PROVIDER);

	if (
		(rv = pkcs11h_addProvider (
			TEST_PROVIDER,
			TEST_PROVIDER,
			FALSE,
			PKCS11H_PRIVATEMODE_MASK_AUTO,
			PKCS11H_SLOTEVENT_METHOD_POLL,
			0,
			FALSE
		)) != CKR_OK
	) {
		fatal ("pkcs11h_addProvider failed", rv);
	}

	printf ("Please remove and insert tokens (pause for 30 seconds)\n");

#if defined(_WIN32)
	Sleep (30*1024);
#else
	sleep (30);
#endif

	if ((rv = pkcs11h_removeProvider (TEST_PROVIDER)) != CKR_OK) {
		fatal ("pkcs11h_removeProvider failed", rv);
	}

	printf ("Adding provider '%s' as fetch\n", TEST_PROVIDER);

	if (
		(rv = pkcs11h_addProvider (
			TEST_PROVIDER,
			TEST_PROVIDER,
			FALSE,
			PKCS11H_PRIVATEMODE_MASK_AUTO,
			PKCS11H_SLOTEVENT_METHOD_FETCH,
			0,
			FALSE
		)) != CKR_OK
	) {
		fatal ("pkcs11h_addProvider failed", rv);
	}

	printf ("Please remove and insert tokens (pause for 30 seconds)\n");

#if defined(_WIN32)
	Sleep (30*1024);
#else
	sleep (30);
#endif

	printf ("Terminating pkcs11-helper\n");

	if ((rv = pkcs11h_terminate ()) != CKR_OK) {
		fatal ("pkcs11h_terminate failed", rv);
	}

	exit (0);
	return 0;
}

#endif
