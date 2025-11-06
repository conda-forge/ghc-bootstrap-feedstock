/*
 * CRT Compatibility shim for GHC bootstrap
 * Provides legacy MSVCRT symbols for UCRT compatibility
 */

#include <stdio.h>
#include <stdlib.h>
#include <wchar.h>
#include <stdarg.h>

/* Provide __imp__environ for legacy code */
#if defined(_WIN64) || defined(_WIN32)
#ifdef __cplusplus
extern "C" {
#endif

/* Export _environ pointer */
extern char ***__p__environ(void);

__attribute__((dllexport))
char **__imp__environ;

__attribute__((constructor))
static void init_environ(void) {
    __imp__environ = *__p__environ();
}

/* Provide __iob_func for legacy stdio */
__attribute__((dllexport))
FILE *__iob_func(void) {
    static FILE _iob[3] = {0};
    static int initialized = 0;

    if (!initialized) {
        _iob[0] = *stdin;
        _iob[1] = *stdout;
        _iob[2] = *stderr;
        initialized = 1;
    }

    return _iob;
}

/* Provide swprintf_s for legacy code that expects it */
__attribute__((dllexport))
int swprintf_s(wchar_t *buffer, size_t sizeOfBuffer, const wchar_t *format, ...) {
    va_list args;
    int ret;

    va_start(args, format);
    ret = vswprintf(buffer, sizeOfBuffer, format, args);
    va_end(args);

    return ret;
}

#ifdef __cplusplus
}
#endif
#endif
