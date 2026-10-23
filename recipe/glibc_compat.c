/* glibc compatibility shim for the aarch64 deb10 bindist.
 *
 * Provides fcntl64 for glibc < 2.28: on aarch64 fcntl64 and fcntl share the
 * same ABI, so forwarding is safe. Loaded only by libHSbase.so via DT_NEEDED.
 */
#include <fcntl.h>
#include <stdarg.h>

int fcntl64(int fd, int cmd, ...)
{
  va_list ap;
  void *arg;

  va_start(ap, cmd);
  arg = va_arg(ap, void *);
  va_end(ap);
  return fcntl(fd, cmd, arg);
}
