#include "my_application.h"

#include <flutter_linux/flutter_linux.h>
#include <malloc.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

#include "flutter/generated_plugin_registrant.h"

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
  FlMethodChannel* window_state_channel;
  GtkWindow* window;
  GtkHeaderBar* header_bar;
  GtkWidget* background_button;
  gboolean use_header_bar;
  gboolean is_minimized;
  gboolean is_focused;
  gboolean is_maximized;
  gboolean is_hidden_to_tray;
  gboolean app_held;
  gint64 minimize_timestamp_us;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

static FlValue* build_window_state_value(MyApplication* self) {
  FlValue* map = fl_value_new_map();
  fl_value_set_string_take(map, "hasNativeHeaderBar",
                           fl_value_new_bool(self->use_header_bar));
  fl_value_set_string_take(map, "hasSystemDecorations",
                           fl_value_new_bool(TRUE));
  fl_value_set_string_take(map, "isMinimized",
                           fl_value_new_bool(self->is_minimized));
  fl_value_set_string_take(map, "isFocused",
                           fl_value_new_bool(self->is_focused));
  fl_value_set_string_take(map, "isMaximized",
                           fl_value_new_bool(self->is_maximized));
  fl_value_set_string_take(map, "isHiddenToTray",
                           fl_value_new_bool(self->is_hidden_to_tray));
  return map;
}

static void emit_window_state_changed(MyApplication* self) {
  if (self->window_state_channel == nullptr) {
    return;
  }
  g_autoptr(FlValue) state_map = build_window_state_value(self);
  fl_method_channel_invoke_method(self->window_state_channel,
                                  "onWindowStateChanged", state_map, nullptr,
                                  nullptr, nullptr);
}

static void set_minimized_state(MyApplication* self, gboolean minimized) {
  if (minimized) {
    self->minimize_timestamp_us = g_get_monotonic_time();
  }
  if (self->is_minimized == minimized) {
    return;
  }
  self->is_minimized = minimized;

  if (minimized) {
    malloc_trim(0);
  }

  emit_window_state_changed(self);
}

static void release_app_hold_if_needed(MyApplication* self) {
  if (self->app_held) {
    self->app_held = FALSE;
    g_application_release(G_APPLICATION(self));
  }
}

static void on_background_button_clicked(GtkButton* button,
                                         gpointer user_data) {
  (void)button;
  MyApplication* self = MY_APPLICATION(user_data);
  if (self->window_state_channel != nullptr) {
    fl_method_channel_invoke_method(self->window_state_channel,
                                    "onBackgroundRequested", nullptr, nullptr,
                                    nullptr, nullptr);
  }
}

static void on_minimize_button_clicked(GtkButton* button, gpointer user_data) {
  (void)button;
  MyApplication* self = MY_APPLICATION(user_data);
  set_minimized_state(self, TRUE);
}

static gboolean widget_has_minimize_icon(GtkWidget* widget) {
  if (GTK_IS_IMAGE(widget)) {
    const gchar* icon_name = nullptr;
    gtk_image_get_icon_name(GTK_IMAGE(widget), &icon_name, nullptr);
    if (icon_name != nullptr &&
        g_strstr_len(icon_name, -1, "minimize") != nullptr) {
      return TRUE;
    }
  }
  if (GTK_IS_CONTAINER(widget)) {
    GList* children = gtk_container_get_children(GTK_CONTAINER(widget));
    for (GList* l = children; l != nullptr; l = l->next) {
      if (widget_has_minimize_icon(GTK_WIDGET(l->data))) {
        g_list_free(children);
        return TRUE;
      }
    }
    g_list_free(children);
  }
  return FALSE;
}

static void hook_minimize_buttons_forall_cb(GtkWidget* widget, gpointer data) {
  MyApplication* self = MY_APPLICATION(data);
  if (GTK_IS_BUTTON(widget) && widget != self->background_button) {
    GtkStyleContext* style = gtk_widget_get_style_context(widget);
    gboolean is_min_btn =
        (style != nullptr && gtk_style_context_has_class(style, "minimize")) ||
        widget_has_minimize_icon(widget);
    if (is_min_btn &&
        g_object_get_data(G_OBJECT(widget), "tachyon-min-hooked") == nullptr) {
      g_object_set_data(G_OBJECT(widget), "tachyon-min-hooked",
                        GINT_TO_POINTER(1));
      g_signal_connect_object(widget, "clicked",
                              G_CALLBACK(on_minimize_button_clicked), self,
                              static_cast<GConnectFlags>(0));
    }
  }
  if (GTK_IS_CONTAINER(widget)) {
    gtk_container_forall(GTK_CONTAINER(widget), hook_minimize_buttons_forall_cb,
                         self);
  }
}

static void hook_header_bar_minimize_button(MyApplication* self) {
  if (self->header_bar != nullptr) {
    gtk_container_forall(GTK_CONTAINER(self->header_bar),
                         hook_minimize_buttons_forall_cb, self);
  }
}

static void on_header_bar_hierarchy_updated(GtkWidget* widget,
                                            gpointer user_data) {
  (void)widget;
  MyApplication* self = MY_APPLICATION(user_data);
  hook_header_bar_minimize_button(self);
}

static gboolean on_window_state_event(GtkWidget* widget,
                                      GdkEventWindowState* event,
                                      gpointer user_data) {
  (void)widget;
  MyApplication* self = MY_APPLICATION(user_data);
  gboolean changed = FALSE;

  const GdkWindowState min_mask = static_cast<GdkWindowState>(
      GDK_WINDOW_STATE_ICONIFIED | GDK_WINDOW_STATE_WITHDRAWN);
  if ((event->changed_mask & min_mask) != 0 && !self->is_hidden_to_tray) {
    gboolean minimized = (event->new_window_state & min_mask) != 0;
    if (minimized) {
      self->minimize_timestamp_us = g_get_monotonic_time();
    }
    if (self->is_minimized != minimized) {
      self->is_minimized = minimized;
      changed = TRUE;
      if (minimized) {
        malloc_trim(0);
      }
    }
  }

  if ((event->changed_mask & GDK_WINDOW_STATE_MAXIMIZED) != 0) {
    gboolean maximized =
        (event->new_window_state & GDK_WINDOW_STATE_MAXIMIZED) != 0;
    if (self->is_maximized != maximized) {
      self->is_maximized = maximized;
      changed = TRUE;
    }
  }

  if ((event->changed_mask & GDK_WINDOW_STATE_FOCUSED) != 0 &&
      !self->is_hidden_to_tray) {
    gboolean focused =
        (event->new_window_state & GDK_WINDOW_STATE_FOCUSED) != 0;
    if (focused && self->is_minimized) {
      gint64 elapsed_us = g_get_monotonic_time() - self->minimize_timestamp_us;
      if (elapsed_us > 250000) {
        self->is_minimized = FALSE;
        changed = TRUE;
      }
    }
    if (self->is_focused != focused) {
      self->is_focused = focused;
      changed = TRUE;
    }
  }

  if (changed) {
    emit_window_state_changed(self);
  }
  return FALSE;
}

static void on_window_is_active_notify(GObject* object,
                                       GParamSpec* pspec,
                                       gpointer user_data) {
  (void)object;
  (void)pspec;
  MyApplication* self = MY_APPLICATION(user_data);
  if (self->window == nullptr || self->is_hidden_to_tray) {
    return;
  }

  gboolean active = gtk_window_is_active(self->window);
  gboolean changed = FALSE;

  if (active && self->is_minimized) {
    gint64 elapsed_us = g_get_monotonic_time() - self->minimize_timestamp_us;
    if (elapsed_us > 250000) {
      self->is_minimized = FALSE;
      changed = TRUE;
    }
  }

  if (self->is_focused != active) {
    self->is_focused = active;
    changed = TRUE;
  }

  if (changed) {
    emit_window_state_changed(self);
  }
}

static void window_state_method_call_cb(FlMethodChannel* channel,
                                        FlMethodCall* method_call,
                                        gpointer user_data) {
  (void)channel;
  MyApplication* self = MY_APPLICATION(user_data);
  const gchar* method = fl_method_call_get_name(method_call);

  if (g_strcmp0(method, "getWindowState") == 0) {
    g_autoptr(FlValue) result = build_window_state_value(self);
    fl_method_call_respond_success(method_call, result, nullptr);
  } else if (g_strcmp0(method, "isMinimized") == 0) {
    g_autoptr(FlValue) result = fl_value_new_bool(self->is_minimized);
    fl_method_call_respond_success(method_call, result, nullptr);
  } else if (g_strcmp0(method, "minimize") == 0) {
    if (self->window != nullptr) {
      set_minimized_state(self, TRUE);
      gtk_window_iconify(self->window);
    }
    fl_method_call_respond_success(method_call, nullptr, nullptr);
  } else if (g_strcmp0(method, "toggleMaximize") == 0) {
    if (self->window != nullptr) {
      if (gtk_window_is_maximized(self->window)) {
        gtk_window_unmaximize(self->window);
      } else {
        gtk_window_maximize(self->window);
      }
    }
    fl_method_call_respond_success(method_call, nullptr, nullptr);
  } else if (g_strcmp0(method, "closeWindow") == 0) {
    release_app_hold_if_needed(self);
    if (self->window != nullptr) {
      gtk_window_close(self->window);
    }
    fl_method_call_respond_success(method_call, nullptr, nullptr);
  } else if (g_strcmp0(method, "startWindowDrag") == 0) {
    if (self->window != nullptr) {
      GdkWindow* gdk_win = gtk_widget_get_window(GTK_WIDGET(self->window));
      if (gdk_win != nullptr) {
        GdkDisplay* display = gdk_window_get_display(gdk_win);
        GdkSeat* seat = gdk_display_get_default_seat(display);
        GdkDevice* pointer =
            seat != nullptr ? gdk_seat_get_pointer(seat) : nullptr;
        if (pointer != nullptr) {
          gint root_x = 0;
          gint root_y = 0;
          gdk_device_get_position(pointer, nullptr, &root_x, &root_y);
          gtk_window_begin_move_drag(self->window, 1, root_x, root_y,
                                     GDK_CURRENT_TIME);
        }
      }
    }
    fl_method_call_respond_success(method_call, nullptr, nullptr);
  } else if (g_strcmp0(method, "enterBackgroundMode") == 0) {
    if (self->window != nullptr) {
      if (!self->app_held) {
        self->app_held = TRUE;
        g_application_hold(G_APPLICATION(self));
      }
      self->is_hidden_to_tray = TRUE;
      gtk_widget_hide(GTK_WIDGET(self->window));
      malloc_trim(0);
      emit_window_state_changed(self);
    }
    fl_method_call_respond_success(method_call, nullptr, nullptr);
  } else if (g_strcmp0(method, "restoreFromBackground") == 0) {
    if (self->window != nullptr) {
      self->is_hidden_to_tray = FALSE;
      self->is_minimized = FALSE;
      self->is_focused = TRUE;
      gtk_widget_show(GTK_WIDGET(self->window));
      gtk_window_deiconify(self->window);
      gtk_window_present(self->window);
      release_app_hold_if_needed(self);
      emit_window_state_changed(self);
    }
    fl_method_call_respond_success(method_call, nullptr, nullptr);
  } else if (g_strcmp0(method, "setBackgroundButtonTooltip") == 0) {
    FlValue* args = fl_method_call_get_args(method_call);
    if (self->background_button != nullptr && args != nullptr &&
        fl_value_get_type(args) == FL_VALUE_TYPE_STRING) {
      gtk_widget_set_tooltip_text(self->background_button,
                                  fl_value_get_string(args));
    }
    fl_method_call_respond_success(method_call, nullptr, nullptr);
  } else if (g_strcmp0(method, "updateTrayState") == 0) {
    fl_method_call_respond_success(method_call, nullptr, nullptr);
  } else {
    fl_method_call_respond_not_implemented(method_call, nullptr);
  }
}

// Called when first Flutter frame received.
static void first_frame_cb(MyApplication* self, FlView* view) {
  if (!self->is_hidden_to_tray) {
    gtk_widget_show(gtk_widget_get_toplevel(GTK_WIDGET(view)));
  }
  hook_header_bar_minimize_button(self);
  malloc_trim(0);
}

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  if (self->window != nullptr) {
    gboolean was_hidden_to_tray = self->is_hidden_to_tray;
    self->is_hidden_to_tray = FALSE;
    self->is_minimized = FALSE;
    gtk_widget_show(GTK_WIDGET(self->window));
    gtk_window_deiconify(self->window);
    gtk_window_present(self->window);
    release_app_hold_if_needed(self);
    emit_window_state_changed(self);
    if (was_hidden_to_tray && self->window_state_channel != nullptr) {
      g_autoptr(FlValue) action = fl_value_new_string("restore");
      fl_method_channel_invoke_method(self->window_state_channel,
                                      "onTrayAction", action, nullptr,
                                      nullptr, nullptr);
    }
    return;
  }

  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));
  self->window = window;
  self->is_minimized = FALSE;
  self->is_focused = TRUE;
  self->is_maximized = FALSE;
  self->is_hidden_to_tray = FALSE;
  self->app_held = FALSE;
  self->minimize_timestamp_us = 0;

  gtk_window_set_default_icon_name("tachyon");

  // Use a header bar when running in GNOME as this is the common style used
  // by applications and is the setup most users will be using (e.g. Ubuntu
  // desktop).
  // If running on X and not using GNOME then just use a traditional title bar
  // in case the window manager does more exotic layout, e.g. tiling.
  // If running on Wayland assume the header bar will work (may need changing
  // if future cases occur).
  gboolean use_header_bar = TRUE;
#ifdef GDK_WINDOWING_X11
  GdkScreen* screen = gtk_window_get_screen(window);
  if (GDK_IS_X11_SCREEN(screen)) {
    const gchar* wm_name = gdk_x11_screen_get_window_manager_name(screen);
    if (g_strcmp0(wm_name, "GNOME Shell") != 0) {
      use_header_bar = FALSE;
    }
  }
#endif
  self->use_header_bar = use_header_bar;

  if (use_header_bar) {
    GtkHeaderBar* header_bar = GTK_HEADER_BAR(gtk_header_bar_new());
    self->header_bar = header_bar;
    gtk_widget_show(GTK_WIDGET(header_bar));
    gtk_header_bar_set_title(header_bar, "tachyon");
    gtk_header_bar_set_show_close_button(header_bar, TRUE);

    GtkWidget* bg_btn = gtk_button_new_from_icon_name("go-bottom-symbolic",
                                                     GTK_ICON_SIZE_MENU);
    self->background_button = bg_btn;
    gtk_style_context_add_class(gtk_widget_get_style_context(bg_btn),
                                "titlebutton");
    gtk_widget_set_valign(bg_btn, GTK_ALIGN_CENTER);
    gtk_widget_set_tooltip_text(bg_btn, "Send to background");
    gtk_widget_show(bg_btn);
    gtk_header_bar_pack_end(header_bar, bg_btn);
    g_signal_connect_object(bg_btn, "clicked",
                            G_CALLBACK(on_background_button_clicked), self,
                            static_cast<GConnectFlags>(0));

    gtk_window_set_titlebar(window, GTK_WIDGET(header_bar));
    g_signal_connect_object(header_bar, "map",
                            G_CALLBACK(on_header_bar_hierarchy_updated), self,
                            G_CONNECT_AFTER);
    g_signal_connect_object(header_bar, "style-updated",
                            G_CALLBACK(on_header_bar_hierarchy_updated), self,
                            G_CONNECT_AFTER);
  } else {
    self->header_bar = nullptr;
    self->background_button = nullptr;
    gtk_window_set_title(window, "tachyon");
  }

  g_signal_connect_object(window, "window-state-event",
                          G_CALLBACK(on_window_state_event), self,
                          static_cast<GConnectFlags>(0));
  g_signal_connect_object(window, "notify::is-active",
                          G_CALLBACK(on_window_is_active_notify), self,
                          static_cast<GConnectFlags>(0));

  gtk_window_set_default_size(window, 1280, 720);

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(project,
                                                self->dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);
  GdkRGBA background_color;
  gdk_rgba_parse(&background_color, "#000000");
  fl_view_set_background_color(view, &background_color);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  g_signal_connect_swapped(view, "first-frame", G_CALLBACK(first_frame_cb),
                           self);
  gtk_widget_realize(GTK_WIDGET(view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));

  FlEngine* engine = fl_view_get_engine(view);
  FlBinaryMessenger* messenger = fl_engine_get_binary_messenger(engine);
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  self->window_state_channel = fl_method_channel_new(
      messenger, "dev.chomusuke.tachyon/window_state", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(
      self->window_state_channel, window_state_method_call_cb, self, nullptr);

  hook_header_bar_minimize_button(self);

  gtk_widget_grab_focus(GTK_WIDGET(view));
}

// Implements GApplication::local_command_line.
static gboolean my_application_local_command_line(GApplication* application,
                                                  gchar*** arguments,
                                                  int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);
  self->dart_entrypoint_arguments = g_strdupv(*arguments + 1);

  g_autoptr(GError) error = nullptr;
  if (!g_application_register(application, nullptr, &error)) {
    g_warning("Failed to register: %s", error->message);
    *exit_status = 1;
    return TRUE;
  }

  g_application_activate(application);
  *exit_status = 0;

  return TRUE;
}

// Implements GApplication::startup.
static void my_application_startup(GApplication* application) {
  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);
}

// Implements GApplication::shutdown.
static void my_application_shutdown(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  release_app_hold_if_needed(self);
  G_APPLICATION_CLASS(my_application_parent_class)->shutdown(application);
}

// Implements GObject::dispose.
static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  release_app_hold_if_needed(self);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  g_clear_object(&self->window_state_channel);
  self->window = nullptr;
  self->header_bar = nullptr;
  self->background_button = nullptr;
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->local_command_line =
      my_application_local_command_line;
  G_APPLICATION_CLASS(klass)->startup = my_application_startup;
  G_APPLICATION_CLASS(klass)->shutdown = my_application_shutdown;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {}

MyApplication* my_application_new() {
  g_set_prgname(APPLICATION_ID);

  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID, "flags",
                                     G_APPLICATION_NON_UNIQUE, nullptr));
}
