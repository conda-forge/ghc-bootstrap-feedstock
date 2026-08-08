/* CRT compatibility shim for the GHC 9.14.1 Windows bootstrap.
 *
 * The pre-built GHC RTS/ghc-internal objects reference these symbols
 * directly, but current mingw-w64/UCRT headers only provide them as
 * inline wrappers (stdio.h's swprintf.inl, sec_api's local-options
 * accessor) - so no real exported symbol exists for the linker to find.
 * This avoids including any mingw-w64/UCRT header at all (their inline
 * definitions collide with hand-written ones regardless of guard macros -
 * see git history) and declares only the exact types/externs needed.
 *
 * swprintf forwards to __stdio_common_vswprintf, the genuine non-inline
 * UCRT export that every working swprintf/vswprintf implementation
 * ultimately calls on Windows (documented Microsoft UCRT internal API,
 * exported from ucrtbase.dll / libucrt.a) - not to plain "vswprintf",
 * which turned out to be equally inline-only/unexported on this toolchain.
 */

typedef unsigned short wchar_t;
typedef __SIZE_TYPE__ size_t;

typedef struct {
    unsigned long _Fe_ctl;
    unsigned long _Fe_stat;
} __crt_fenv_t;

extern int __stdio_common_vswprintf(unsigned long long options, wchar_t *buffer,
                                     size_t buffer_count, const wchar_t *format,
                                     void *locale, __builtin_va_list arglist);

unsigned long long *__local_stdio_printf_options(void) {
    static unsigned long long options = 0;
    return &options;
}

int swprintf(wchar_t *buffer, size_t count, const wchar_t *format, ...) {
    __builtin_va_list args;
    int ret;

    if (!buffer || count == 0) {
        return -1;
    }

    __builtin_va_start(args, format);
    ret = __stdio_common_vswprintf(0, buffer, count, format, (void *)0, args);
    __builtin_va_end(args);

    return ret;
}

/* Fallback for mingw-w64's x87 "53-bit precision control" FP environment
 * constant, referenced by RTS/ghc-internal via a GNU ld "--enable-auto-import"
 * .refptr indirection (DLL-import-style access). A prior weak-symbol version
 * of this definition still left the .refptr unresolved - GNU ld's
 * auto-import refptr generation has known quirks with weak symbols, so this
 * is now a plain strong definition instead. libcrt_compat.a is
 * whole-archived ahead of "-lmingwex" in the link flags, so this always
 * resolves the reference before mingwex's lazy archive scan would even be
 * considered for it - no duplicate-definition risk. x87 precision control
 * is dead weight on x86_64 (SSE2 is the default FP unit for both GHC and
 * this toolchain), so an approximate value should not affect correctness -
 * it only needs to satisfy the linker. Value approximates mingw-w64's own
 * fenv.c: default x87 control word (0x027F: all exceptions masked,
 * round-to-nearest) with precision-control bits set to 53-bit (double)
 * mode.
 */
const __crt_fenv_t __mingw_fe_pc53_env = { 0x027Ful, 0x0ul };
