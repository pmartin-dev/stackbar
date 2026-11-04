#include <errno.h>
#include <stdio.h>
#include <unistd.h>

int main(int argc, char **argv) {
  if (argc < 4) {
    return 64;
  }
  if (setpgid(0, 0) != 0) {
    perror("setpgid");
    return 126;
  }
  if (chdir(argv[1]) != 0) {
    perror("chdir");
    return 126;
  }

  execv(argv[2], &argv[2]);
  perror("execv");
  return errno == ENOENT ? 127 : 126;
}
