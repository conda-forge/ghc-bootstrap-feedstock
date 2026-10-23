/* glibc compatibility shim for the aarch64 deb10 bindist.
 *
 * Provides fcntl64 (glibc 2.28), statx (2.28) and memfd_create (2.27) for the
 * glibc 2.17 sysroot. On aarch64 fcntl64 and fcntl share the same ABI, and
 * statx/memfd_create are plain syscalls (291 and 279 on aarch64). Loaded via
 * DT_NEEDED by every object whose versioned references were cleared.
 */
#include <fcntl.h>
#include <stdarg.h>
#include <unistd.h>

int fcntl64(int fd, int cmd, ...)
{
  va_list ap;
  void *arg;

  va_start(ap, cmd);
  arg = va_arg(ap, void *);
  va_end(ap);
  return fcntl(fd, cmd, arg);
}

int statx(int dirfd, const char *path, int flags, unsigned int mask, void *buf)
{
  return (int)syscall(291, dirfd, path, flags, mask, buf);
}

int memfd_create(const char *name, unsigned int flags)
{
  return (int)syscall(279, name, flags);
}
