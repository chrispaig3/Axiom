/* Object-code block coverage for Axiom programs (scripts/measure-coverage.sh, scripts/lib/coverage.py).
 * The counters SanitizerCoverage places in the binary are moved onto a
 * file-backed MAP_SHARED mapping at start-up, so every increment lands in
 * the file however the process ends - a trap's raw exit syscall included,
 * which no destructor would see. */
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>
extern int main(int, char **);
static uint8_t *cb, *ce;
void __sanitizer_cov_8bit_counters_init(uint8_t *s, uint8_t *e) { cb = s; ce = e; }
void __sanitizer_cov_pcs_init(const uintptr_t *pb, const uintptr_t *pe) {
  const char *dir = getenv("AXIOM_COV_DIR");
  if (!dir || !cb || ce <= cb) return;
  size_t n = (size_t)(ce - cb);
  if ((size_t)(pe - pb) != 2 * n) return;
  long pg = sysconf(_SC_PAGESIZE);
  uintptr_t lo = (uintptr_t)cb & ~(uintptr_t)(pg - 1);
  uintptr_t hi = ((uintptr_t)ce + pg - 1) & ~(uintptr_t)(pg - 1);
  size_t span = hi - lo;
  char path[4096];
  snprintf(path, sizeof path, "%s/pcs", dir);
  if (access(path, F_OK) != 0) {
    char tmp[4096];
    snprintf(tmp, sizeof tmp, "%s/pcs.%d", dir, (int)getpid());
    FILE *f = fopen(tmp, "w");
    if (f) {
      uintptr_t base = (uintptr_t)&main;
      for (size_t i = 0; i < n; i++)
        fprintf(f, "%ld %lu\n", (long)(pb[2 * i] - base), (unsigned long)pb[2 * i + 1]);
      fclose(f);
      rename(tmp, path);
    }
  }
  snprintf(path, sizeof path, "%s/run.%d.cnt", dir, (int)getpid());
  int fd = open(path, O_RDWR | O_CREAT | O_TRUNC, 0644);
  if (fd < 0) return;
  if (write(fd, (void *)lo, span) != (ssize_t)span) { close(fd); return; }
  void *m = mmap((void *)lo, span, PROT_READ | PROT_WRITE, MAP_SHARED | MAP_FIXED, fd, 0);
  close(fd);
  if (m == MAP_FAILED) { unlink(path); return; }
  snprintf(path, sizeof path, "%s/run.%d.meta", dir, (int)getpid());
  FILE *f = fopen(path, "w");
  if (f) { fprintf(f, "%lu %lu\n", (unsigned long)((uintptr_t)cb - lo), (unsigned long)n); fclose(f); }
}
