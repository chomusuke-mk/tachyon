#include "my_application.h"

#ifdef GDK_WINDOWING_X11
#include <X11/Xlib.h>
#endif

int main(int argc, char** argv) {
  // Feature 19: Linux Thread Synchronization
  // Initialize X11 thread synchronization before any GTK, GL, or Flutter calls.
  // This ensures thread-safety across libmpv audio/video worker threads, Mesa GL/EGL
  // driver threads, and Flutter rasterizer threads under X11/XWayland sessions.
#ifdef GDK_WINDOWING_X11
  XInitThreads();
#endif

  g_autoptr(MyApplication) app = my_application_new();
  return g_application_run(G_APPLICATION(app), argc, argv);
}
