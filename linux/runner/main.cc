#include <malloc.h>
#include "my_application.h"

int main(int argc, char** argv) {
  mallopt(M_ARENA_MAX, 2);
  mallopt(M_TRIM_THRESHOLD, 128 * 1024);
  mallopt(M_MMAP_THRESHOLD, 128 * 1024);
  g_autoptr(MyApplication) app = my_application_new();
  return g_application_run(G_APPLICATION(app), argc, argv);
}
