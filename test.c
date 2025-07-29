// Magic address for printing
#define PRINT_ADDR ((volatile char*)0xFFFFFF00)

#include <stdio.h>
#include <stdlib.h>
#include <reent.h>

int _swbuf_r(struct _reent *r, int c, FILE *stream) {
    exit(1);
    *PRINT_ADDR = c;
    return c;  // Return the written character on success
}

void print_text(char *text) {
    while (*text) {
        *PRINT_ADDR = *text;
        text++;
    }
}

int factorial(int n) {
    if (n <= 1) return 1;
    return n * factorial(n-1);
}
int fibonacci(int n) {
    int fib[20] = {0, 1};
    for (int i = 2; i < n; i++) {
        fib[i] = fib[i-1] + fib[i-2];
    }
    return fib[n-1];
}
struct Point {
    int x, y;
};

void move_point(struct Point *p, int dx, int dy) {
    p->x += dx;
    p->y += dy;
}
int main() {
    // print_text("Hello world!");

    // int a = 5;
    // int b = 7;
    // int c = 6;
    // int d = (a+b)*(c+1);

    // *EXIT_ADDR = d;

    // *EXIT_ADDR = factorial(5);

    // *EXIT_ADDR = fibonacci(10);

    // struct Point p = {61, 34};
    // move_point(&p, 5, 3);

    // print_int(p.x);
    // print_text(", ");
    // print_int(p.y);
    // print_text("\n");

    // exit(0);

    // print_text("Hello world!\n");
    // fclose(stdout);
    // stdout = fdopen(1, "w");
    // setvbuf(stdout, NULL, _IONBF, 0); // disable buffering
    // putchar('c');
    printf("%d test\n", 5);
    // fflush(stdout);

    // write(1, "test", 18);
    return 0;
}
