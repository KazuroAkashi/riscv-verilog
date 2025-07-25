// Magic address for printing
#define PRINT_ADDR ((volatile char *)0xFFFF0000)

// Magic address for exit
#define EXIT_ADDR ((volatile char *)0xABCD0000)

void print_text(char *text) {
    while (*text != '\0') {
        *PRINT_ADDR = *text;
        text++;
    }
}

int main() {
    print_text("Hello world!");

    int a = 5;
    int b = 7;
    int c = 6;
    int d = (a+b)*(c+1);

    *EXIT_ADDR = d;
}
