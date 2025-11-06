/*
 * CRT Compatibility shim for GHC bootstrap
 * Provides legacy MSVCRT symbols for UCRT compatibility
 */

#include <stdio.h>
#include <stdlib.h>

#ifdef __cplusplus
extern "C" {
#endif

/*
 * Legacy __imp__environ symbol
 * UCRT uses _get_environ() instead of direct access to _environ
 */
__attribute__((dllexport))
char **__imp__environ = NULL;

static void __attribute__((constructor)) init_environ(void) {
    __imp__environ = _environ;
}

/*
 * Legacy __iob_func for old code expecting FILE* array
 * Modern UCRT doesn't expose __iob directly
 */
static FILE *iob_compat[3];
static int iob_initialized = 0;

__attribute__((dllexport))
FILE *__iob_func(void) {
    if (!iob_initialized) {
        iob_compat[0] = stdin;
        iob_compat[1] = stdout;
        iob_compat[2] = stderr;
        iob_initialized = 1;
    }
    return iob_compat;
}

#ifdef __cplusplus
}
#endif
