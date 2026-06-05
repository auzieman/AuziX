#include <math.h>
#include <stdio.h>

int main(void) {
    double value = sqrt(144.0);
    printf("Auzix dynamic probe\n");
    printf("native-prefix=/Programs/AuzixDynProbe/0.1\n");
    printf("runtime-libraries=/System/Libraries/Runtime/glibc\n");
    printf("sqrt-result=%.0f\n", value);
    return 0;
}

