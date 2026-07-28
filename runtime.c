#include <stdio.h>

long long println(const char *s) {
    fputs(s, stdout);
    fputc('\n', stdout);
    return 0;
}