#include <dlfcn.h>
#include <stdio.h>

int main(int argc, char **argv) {
    for (int i = 1; i < argc; i++) {
        dlopen(argv[i], RTLD_LAZY);
    }
    return 0;
}
