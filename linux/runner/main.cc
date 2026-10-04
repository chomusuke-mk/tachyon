#include <malloc.h>
#include "my_application.h"

int main(int argc, char** argv) {
  mallopt(M_ARENA_MAX, 2);
  g_autoptr(MyApplication) app = my_application_new();
  return g_application_run(G_APPLICATION(app), argc, argv);
}
