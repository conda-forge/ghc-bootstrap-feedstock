/*
 * CRT Compatibility shim for GHC bootstrap
 * Provides legacy MSVCRT symbols for UCRT compatibility
 */

/* Prevent inclusion of secure CRT wrappers that define inline swprintf_s */
#define _INC_STDIO_S
#define _STDIO_S_DEFINED

#include <stdio.h>
#include <stdlib.h>

/* Forward declarations to avoid pulling in more headers */
typedef unsigned short wchar_t;
typedef unsigned long long size_t;

#ifdef __cplusplus
extern "C" {
#endif

/*
 * Legacy __imp__environ symbol
 * UCRT uses _get_environ() instead of direct access to _environ
 */
char **__imp__environ = NULL;

static void __attribute__((constructor)) init_environ(void) {
    __imp__environ = _environ;
}

/*
 * Legacy __iob_func for old code expecting FILE array
 * Returns pointer to array of stdin/stdout/stderr
 * Modern UCRT doesn't expose __iob directly
 */
static FILE iob_compat[3];
static int iob_initialized = 0;

FILE *__iob_func(void) {
    if (!iob_initialized) {
        /* Copy the FILE structures */
        if (stdin) iob_compat[0] = *stdin;
        if (stdout) iob_compat[1] = *stdout;
        if (stderr) iob_compat[2] = *stderr;
        iob_initialized = 1;
    }
    return iob_compat;  /* Returns pointer to first element of array */
}

/*
 * swprintf_s - provide as real symbol since UCRT only has inline version
 * Forward declare vswprintf to avoid pulling in headers
 */
extern int vswprintf(wchar_t *buffer, size_t count, const wchar_t *format, __builtin_va_list argptr);

int swprintf_s(wchar_t *buffer, size_t sizeOfBuffer, const wchar_t *format, ...) {
    __builtin_va_list args;
    int ret;

    if (!buffer || sizeOfBuffer == 0) {
        return -1;
    }

    __builtin_va_start(args, format);
    ret = vswprintf(buffer, sizeOfBuffer, format, args);
    __builtin_va_end(args);

    return ret;
}

#ifdef __cplusplus
}
#endif
