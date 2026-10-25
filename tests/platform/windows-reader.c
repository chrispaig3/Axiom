/* Freestanding source for emitWinReaderRuntime's embedded LLVM, not a
 * separately linked runtime. Regenerate with windows-reader-generate.py;
 * --check verifies both the source and embedded-body digests without a C
 * toolchain. Windows uses 64-bit words for the existing extern ABI, and
 * masks DWORD/BOOL results. CreateThread's callback is exactly i32(ptr).
 *
 * Registry fields and buffer publication use the registry lock. No worker
 * retains an Axiom pointer. A helper reference keeps a state alive while
 * read/mode drops the lock. Closing stops new references and reads, waits
 * existing helpers out, then joins the worker before freeing its buffer.
 * A mode helper owns the paused interval and worker HANDLE; closing waits
 * its reference, so two lifecycle operations never join/close one HANDLE.
 */
typedef unsigned long long U;
typedef unsigned int D;
extern U VirtualAlloc(U, U, U, U), VirtualFree(U, U, U),
    CreateThread(U, U, U, U, U, U);
extern U WaitForSingleObject(U, U), CloseHandle(U), CancelSynchronousIo(U),
    Sleep(U);
extern U ReadFile(U, U, U, U, U), GetLastError(void), GetFileType(U),
    SetConsoleMode(U, U), GetConsoleMode(U, U);
extern U CreateFileW(U, U, U, U, U, U, U);
extern U GetNumberOfConsoleInputEvents(U, U);
struct Reader {
  struct Reader *next;
  U handle, refs, closing, paused, thread, status, count, offset, last_error,
      stop, console, input, cancelled;
  unsigned char buffer[4096];
};
static struct Reader *__axiom_reader_readers;
static D __axiom_reader_reader_lock;
static const unsigned short __axiom_reader_console_path[] = {
    'C', 'O', 'N', 'I', 'N', '$', 0};
static void __axiom_reader_lock(void) {
  while (__atomic_exchange_n(&__axiom_reader_reader_lock, 1, __ATOMIC_ACQUIRE))
    Sleep(0);
}
static void __axiom_reader_unlock(void) {
  __atomic_store_n(&__axiom_reader_reader_lock, 0, __ATOMIC_RELEASE);
}
static U __axiom_reader_error(void) {
  U e = GetLastError() & 4294967295ULL;
  return e ? e : 1;
}
static struct Reader *__axiom_reader_find(U h) {
  struct Reader *s = __axiom_reader_readers;
  while (s && s->handle != h)
    s = s->next;
  return s;
}
/* FILE_TYPE_CHAR also includes NUL and serial devices. Only a real
 * console has cooked-input zero-byte completions that should be retried. */
static U __axiom_reader_kind(U h) {
  U kind = GetFileType(h) & 4294967295ULL;
  if (kind == 2) {
    D mode = 0;
    if (!(GetConsoleMode(h, (U)&mode) & 4294967295ULL))
      return 0;
  }
  return kind;
}
static struct Reader *__axiom_reader_create(U h, U kind) {
  struct Reader *s =
      (struct Reader *)VirtualAlloc(0, sizeof(struct Reader), 12288, 4);
  if (!s)
    return 0;
  s->handle = h;
  s->console = (kind == 2);
  s->next = __axiom_reader_readers;
  __axiom_reader_readers = s;
  return s;
}
/* CancelSynchronousIo can finish the client read while conhost still owns
 * a server read which would consume the next key (terminal issues 12143,
 * 17791). Closing its independently opened CONIN$ handle retires that read.
 * A duplicate shares the original file object and cannot isolate teardown.
 * Completed reads keep their input handle, including conhost's line tail. */
static U __axiom_reader_input_close(struct Reader *s) {
  if (s->input) {
    if (!(CloseHandle(s->input) & 4294967295ULL))
      return __axiom_reader_error();
    s->input = 0;
  }
  s->cancelled = 0;
  return 0;
}
static U __axiom_reader_input_open(struct Reader *s) {
  if (!s->console)
    return 0;
  if (s->cancelled) {
    U e = __axiom_reader_input_close(s);
    if (e)
      return e;
  }
  if (!s->input) {
    /* GetConsoleMode accepts output handles too. Require a readable input
     * handle before opening its private read session. This consumes no key. */
    D events = 0;
    if (!(GetNumberOfConsoleInputEvents(s->handle, (U)&events) & 4294967295ULL))
      return __axiom_reader_error();
    U h = CreateFileW((U)__axiom_reader_console_path, 2147483648ULL, 3, 0, 3, 0, 0);
    if (h == ~(U)0)
      return __axiom_reader_error();
    s->input = h;
  }
  return 0;
}
static D __axiom_reader_worker(void *arg) {
  struct Reader *s = arg;
  for (;;) {
    __axiom_reader_lock();
    U stop = s->stop;
    __axiom_reader_unlock();
    if (stop) {
      __axiom_reader_lock();
      s->status = 0;
      __axiom_reader_unlock();
      return 0;
    }
    D got = 0;
    U ok = ReadFile(s->console ? s->input : s->handle,
                   (U)s->buffer, 4096, (U)&got, 0) & 4294967295ULL;
    U e = __axiom_reader_error();
    __axiom_reader_lock();
    if (s->console && !ok && e == 995)
      s->cancelled = 1;
    if (got) {
      s->count = got;
      s->offset = 0;
      s->status = 2;
      __axiom_reader_unlock();
      return 0;
    }
    if (s->stop || s->cancelled) {
      s->status = 0;
      __axiom_reader_unlock();
      return 0;
    }
    if ((ok && s->console) || (!ok && e == 995)) {
      __axiom_reader_unlock();
      Sleep(1);
      continue;
    }
    if (ok || (!s->console && (e == 109 || e == 232)))
      s->status = 3;
    else {
      s->last_error = e;
      s->status = 4;
    }
    __axiom_reader_unlock();
    return 0;
  }
}
static void __axiom_reader_start(struct Reader *s) {
  if (s->status || s->paused || s->closing)
    return;
  if (s->thread) {
    CloseHandle(s->thread);
    s->thread = 0;
  }
  U e = __axiom_reader_input_open(s);
  if (e) {
    s->last_error = e;
    s->status = 4;
    return;
  }
  s->stop = 0;
  s->status = 1;
  U t = CreateThread(0, 0, (U)__axiom_reader_worker, (U)s, 0, 0);
  if (t)
    s->thread = t;
  else {
    s->last_error = __axiom_reader_error();
    s->status = 4;
  }
}
static U __axiom_reader_join(struct Reader *s) {
  U t = s->thread;
  if (!t)
    return 0;
  for (;;) {
    U w = WaitForSingleObject(t, 0) & 4294967295ULL;
    if (!w)
      return 0;
    if (w == 4294967295ULL)
      return __axiom_reader_error();
    if (w != 258)
      return 1;
    U ok = CancelSynchronousIo(t) & 4294967295ULL;
    if (!ok) {
      U e = __axiom_reader_error();
      if (e != 1168) {
        w = WaitForSingleObject(t, 0) & 4294967295ULL;
        if (!w)
          return 0;
        return e;
      }
    }
    Sleep(1);
  }
}
U __axiom_win_reader_ready(U h) {
  __axiom_reader_lock();
  struct Reader *s = __axiom_reader_find(h);
  if (!s) {
    U k = __axiom_reader_kind(h);
    if (k != 2 && k != 3) {
      __axiom_reader_unlock();
      return -87;
    }
    s = __axiom_reader_create(h, k);
    if (!s) {
      U e = __axiom_reader_error();
      __axiom_reader_unlock();
      return -e;
    }
  }
  if (s->closing) {
    __axiom_reader_unlock();
    return -6;
  }
  __axiom_reader_start(s);
  U ready = s->status >= 2;
  __axiom_reader_unlock();
  return ready;
}
U __axiom_win_reader_read(U h, U dst, U count) {
  if (!count)
    return 0;
  if (count > 9223372036854775807ULL)
    return -87;
  __axiom_reader_lock();
  struct Reader *s = __axiom_reader_find(h);
  if (!s) {
    U k = __axiom_reader_kind(h);
    if (k != 2 && k != 3) {
      __axiom_reader_unlock();
      D got = 0;
      U ok = ReadFile(h, dst, count > 4294967295ULL ? 4294967295ULL : count,
                      (U)&got, 0) &
             4294967295ULL;
      return ok ? got : -__axiom_reader_error();
    }
    s = __axiom_reader_create(h, k);
    if (!s) {
      U e = __axiom_reader_error();
      __axiom_reader_unlock();
      return -e;
    }
  }
  if (s->closing) {
    __axiom_reader_unlock();
    return -6;
  }
  s->refs++;
  __axiom_reader_unlock();
  for (;;) {
    __axiom_reader_lock();
    if (s->closing) {
      s->refs--;
      __axiom_reader_unlock();
      return -995;
    }
    if (s->paused) {
      __axiom_reader_unlock();
      Sleep(1);
      continue;
    }
    __axiom_reader_start(s);
    U status = s->status;
    if (status == 2) {
      U n = s->count - s->offset;
      if (n > count)
        n = count;
      unsigned char *out = (unsigned char *)dst;
      for (U i = 0; i < n; i++)
        out[i] = s->buffer[s->offset + i];
      s->offset += n;
      if (s->offset == s->count)
        s->status = 0;
      s->refs--;
      __axiom_reader_unlock();
      return n;
    }
    if (status >= 3) {
      U result = status == 3 ? 0 : -s->last_error;
      s->refs--;
      __axiom_reader_unlock();
      return result;
    }
    __axiom_reader_unlock();
    Sleep(1);
  }
}
U __axiom_win_reader_mode(U h, U mode) {
  __axiom_reader_lock();
  struct Reader *s = __axiom_reader_find(h);
  if (!s) {
    U ok = SetConsoleMode(h, mode) & 4294967295ULL;
    U result = ok ? 0 : -__axiom_reader_error();
    __axiom_reader_unlock();
    return result;
  }
  if (s->closing) {
    __axiom_reader_unlock();
    return -6;
  }
  s->refs++;
  __axiom_reader_unlock();
  for (;;) {
    __axiom_reader_lock();
    if (s->closing) {
      s->refs--;
      __axiom_reader_unlock();
      return -6;
    }
    if (!s->paused)
      break;
    __axiom_reader_unlock();
    Sleep(1);
  }
  s->paused = 1;
  s->stop = 1;
  __axiom_reader_unlock();
  U joined = __axiom_reader_join(s);
  __axiom_reader_lock();
  if (!joined && s->cancelled)
    joined = __axiom_reader_input_close(s);
  if (joined) {
    s->paused = 0;
    s->refs--;
    __axiom_reader_unlock();
    return -joined;
  }
  U result;
  if (s->closing)
    result = -6;
  else {
    U ok = SetConsoleMode(h, mode) & 4294967295ULL;
    result = ok ? 0 : -__axiom_reader_error();
  }
  if (s->thread) {
    CloseHandle(s->thread);
    s->thread = 0;
  }
  s->paused = 0;
  s->refs--;
  __axiom_reader_unlock();
  return result;
}
U __axiom_win_reader_close(U h) {
  __axiom_reader_lock();
  struct Reader *s = __axiom_reader_find(h);
  if (!s) {
    U ok = CloseHandle(h) & 4294967295ULL;
    U result = ok ? 0 : -__axiom_reader_error();
    __axiom_reader_unlock();
    return result;
  }
  if (s->closing == 1) {
    __axiom_reader_unlock();
    return -6;
  }
  s->closing = 1;
  s->stop = 1;
  __axiom_reader_unlock();
  for (;;) {
    __axiom_reader_lock();
    U refs = s->refs;
    __axiom_reader_unlock();
    if (!refs)
      break;
    Sleep(1);
  }
  U joined = __axiom_reader_join(s);
  __axiom_reader_lock();
  if (joined) {
    s->closing = 2;
    __axiom_reader_unlock();
    return -joined;
  }
  if (s->thread) {
    CloseHandle(s->thread);
    s->thread = 0;
  }
  U retired = __axiom_reader_input_close(s);
  if (retired) {
    s->closing = 2;
    __axiom_reader_unlock();
    return -retired;
  }
  U ok = CloseHandle(h) & 4294967295ULL;
  if (!ok) {
    U e = __axiom_reader_error();
    /* A failed close can leave the handle live. Preserve prefetched bytes
     * and allow the owner to read or retry rather than losing its input. */
    s->closing = 0;
    s->stop = 0;
    __axiom_reader_unlock();
    return -e;
  }
  struct Reader **p = &__axiom_reader_readers;
  while (*p != s)
    p = &(*p)->next;
  *p = s->next;
  VirtualFree((U)s, 0, 32768);
  __axiom_reader_unlock();
  return 0;
}
