#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "range.h"


int main(int argc, char **argv) {
	char **result;
	long int i;
    char * compressed;
	if (argc < 2) {
		printf("argc is %d, needs args\n", argc);
		exit(1);
	}
	range_startup();
	printf("hello world\n");
	result = range_expand(argv[1]);
	printf("string1: %s", result[0]);
	return 0;
}
