#include <stdio.h>

static long steps(long n) {
    long c = 0;
    while (n > 1) {
        if (n % 2 == 0) { n = n / 2; } else { n = 3 * n + 1; }
        c++;
    }
    return c;
}

int main(void) {
    long total = 0;
    long i = 1;
    while (i <= 3000000) {
        total += steps(i);
        i++;
    }
    printf("%ld\n", total);
    return 0;
}
