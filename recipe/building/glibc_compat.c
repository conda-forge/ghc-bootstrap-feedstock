/* glibc compatibility shim for the aarch64 deb10 bindist.
 *
 * Provides fcntl64 for glibc < 2.28: on aarch64 fcntl64 and fcntl share the
 * same ABI, so forwarding is safe. Loaded only by libHSbase.so via DT_NEEDED.
 */
#include <fcntl.h>
#include <stdarg.h>
#include <unistd.h>

/* Also provides statx and memfd_create via raw aarch64 syscalls. */
long syscall(long number, ...);

/* statx: aarch64 syscall 291 */
int statx(int dirfd, const char *path, int flags, unsigned int mask, void *buf)
{
  return (int)syscall(291, dirfd, path, flags, mask, buf);
}

/* memfd_create: aarch64 syscall 279 */
int memfd_create(const char *name, unsigned int flags)
{
  return (int)syscall(279, name, flags);
}

int fcntl64(int fd, int cmd, ...)
{
  va_list ap;
  void *arg;

  va_start(ap, cmd);
  arg = va_arg(ap, void *);
  va_end(ap);
  return fcntl(fd, cmd, arg);
}
