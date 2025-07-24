// Magic address for printing
#define PRINT_ADDR ((volatile char *)0xFFFF0000)

// Magic address for exit
#define EXIT_ADDR ((volatile char *)0xABCD0000)

int main() {
    *PRINT_ADDR = 'A';
    *PRINT_ADDR = 'b';

    int a = 5;
    int b = 7;
    int c = 6;
    int d = (a+b)*(c+1);

    *EXIT_ADDR = d;
}
