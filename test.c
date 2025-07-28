// Magic address for printing
#define PRINT_ADDR ((volatile char *)0xFFFF0000)

// Magic address for exit
#define EXIT_ADDR ((volatile char *)0xABCD0000)

// Standard library memset function is needed for arrays
void* memset(void* ptr, int value, int num) {
    unsigned char* p = (unsigned char*)ptr;
    for (int i = 0; i < num; i++) {
        p[i] = (unsigned char)value;
    }
    return ptr;
}
/////////////////////////////////////////////////////


void print_text(char *text) {
    while (*text != '\0') {
        *PRINT_ADDR = *text;
        text++;
    }
}

void print_int(int n) {
    char buffer[10];
    int i = 0;
    do {
        buffer[i++] = '0' + (n % 10);
        n /= 10;
    } while (n > 0);
    for (int j = i-1; j >= 0; j--) {
        *PRINT_ADDR = buffer[j];
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

    struct Point p = {61, 34};
    move_point(&p, 5, 3);

    print_int(p.x);
    print_text(", ");
    print_int(p.y);
    print_text("\n");

    *EXIT_ADDR = 0;
}
