#include <Elementary.h>
#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef enum { ACTION_NONE, ACTION_REFRESH, ACTION_LIST, ACTION_INSTALL } Action;

typedef struct Package_Row Package_Row;

typedef struct {
  Evas_Object *window;
  Evas_Object *list;
  Evas_Object *status;
  Evas_Object *install_button;
  Ecore_Exe *runner;
  Ecore_Event_Handler *data_handler;
  Ecore_Event_Handler *error_handler;
  Ecore_Event_Handler *done_handler;
  char *output;
  size_t output_size;
  Eina_List *rows;
  Action action;
} Package_Manager;

struct Package_Row {
  Package_Manager *manager;
  Evas_Object *check;
  char *name;
};

static void status_set(Package_Manager *ui, const char *text) {
  elm_object_text_set(ui->status, text);
}

static void output_reset(Package_Manager *ui) {
  free(ui->output);
  ui->output = NULL;
  ui->output_size = 0;
}

static void output_append(Package_Manager *ui, const void *data, size_t size) {
  char *next = realloc(ui->output, ui->output_size + size + 1);
  if (!next) return;
  ui->output = next;
  memcpy(ui->output + ui->output_size, data, size);
  ui->output_size += size;
  ui->output[ui->output_size] = '\0';
}

static Eina_Bool package_name_safe(const char *name) {
  if (!name || !name[0]) return EINA_FALSE;
  for (const unsigned char *p = (const unsigned char *)name; *p; p++) {
    if (!isalnum(*p) && *p != '-' && *p != '_' && *p != '.' && *p != '+') return EINA_FALSE;
  }
  return EINA_TRUE;
}

static Eina_Bool run_action(Package_Manager *ui, Action action, const char *command) {
  if (ui->runner) return EINA_FALSE;
  output_reset(ui);
  ui->action = action;
  ui->runner = ecore_exe_pipe_run(command,
    ECORE_EXE_PIPE_READ | ECORE_EXE_PIPE_ERROR, ui);
  return ui->runner != NULL;
}

static void list_start(Package_Manager *ui) {
  status_set(ui, "<color=#84a7b8>Reading available packages…</color>");
  if (!run_action(ui, ACTION_LIST, "/System/Tools/auzix-pkg list available"))
    status_set(ui, "<color=#ff6b6b>Could not start auzix-pkg.</color>");
}

static unsigned int selected_count(Package_Manager *ui) {
  unsigned int count = 0;
  Eina_List *node;
  Package_Row *row;
  EINA_LIST_FOREACH(ui->rows, node, row) {
    if (elm_check_state_get(row->check)) count++;
  }
  return count;
}

static void checked_cb(void *data, Evas_Object *obj, void *event_info) {
  (void)obj; (void)event_info;
  Package_Row *row = data;
  Package_Manager *ui = row->manager;
  unsigned int count = selected_count(ui);
  elm_object_disabled_set(ui->install_button, count == 0);
  char message[512];
  snprintf(message, sizeof(message), "<color=#dceaf3>%u package%s selected.</color>",
           count, count == 1 ? "" : "s");
  status_set(ui, message);
}

static void row_toggle_cb(void *data, Evas_Object *obj, void *event_info) {
  (void)obj; (void)event_info;
  Package_Row *row = data;
  elm_check_state_set(row->check, !elm_check_state_get(row->check));
  checked_cb(row, row->check, NULL);
}

static void rows_clear(Package_Manager *ui) {
  Package_Row *row;
  EINA_LIST_FREE(ui->rows, row) {
    free(row->name);
    free(row);
  }
}

static void list_populate(Package_Manager *ui) {
  rows_clear(ui);
  elm_list_clear(ui->list);
  elm_object_disabled_set(ui->install_button, EINA_TRUE);
  unsigned int count = 0;
  if (!ui->output || !ui->output[0]) {
    status_set(ui, "<color=#ffb86c>No packages were returned by auzix-pkg.</color>");
    return;
  }
  char *save = NULL;
  for (char *line = strtok_r(ui->output, "\n", &save);
       line; line = strtok_r(NULL, "\n", &save)) {
    char *tab = strchr(line, '\t');
    if (!tab) continue;
    *tab = '\0';
    if (!package_name_safe(line)) continue;
    Package_Row *row = calloc(1, sizeof(*row));
    if (!row) continue;
    row->manager = ui;
    row->name = strdup(line);
    if (!row->name) { free(row); continue; }
    char display[1024];
    snprintf(display, sizeof(display), "%s  //  %s", line, tab + 1);
    row->check = elm_check_add(ui->list);
    evas_object_smart_callback_add(row->check, "changed", checked_cb, row);
    evas_object_show(row->check);
    elm_list_item_append(ui->list, display, row->check, NULL, row_toggle_cb, row);
    ui->rows = eina_list_append(ui->rows, row);
    count++;
  }
  elm_list_go(ui->list);
  char message[256];
  snprintf(message, sizeof(message), "<color=#82d4bb>%u packages available.</color>", count);
  status_set(ui, message);
}

static Eina_Bool output_cb(void *data, int type, void *event_info) {
  Package_Manager *ui = data;
  Ecore_Exe_Event_Data *event = event_info;
  (void)type;
  if (event->exe == ui->runner) output_append(ui, event->data, (size_t)event->size);
  return ECORE_CALLBACK_RENEW;
}

static Eina_Bool done_cb(void *data, int type, void *event_info) {
  Package_Manager *ui = data;
  Ecore_Exe_Event_Del *event = event_info;
  (void)type;
  if (event->exe != ui->runner) return ECORE_CALLBACK_RENEW;
  Action finished = ui->action;
  ui->runner = NULL;
  ui->action = ACTION_NONE;
  if (event->exit_code != 0) {
    status_set(ui, "<color=#ff6b6b>auzix-pkg failed. Review the package log.</color>");
    return ECORE_CALLBACK_RENEW;
  }
  if (finished == ACTION_REFRESH) list_start(ui);
  else if (finished == ACTION_LIST) list_populate(ui);
  else if (finished == ACTION_INSTALL) {
    status_set(ui, "<color=#82d4bb>Package installed successfully.</color>");
    list_start(ui);
  }
  return ECORE_CALLBACK_RENEW;
}

static void refresh_cb(void *data, Evas_Object *obj, void *event_info) {
  (void)obj; (void)event_info;
  Package_Manager *ui = data;
  status_set(ui, "<color=#84a7b8>Refreshing repository metadata…</color>");
  if (!run_action(ui, ACTION_REFRESH, "/System/Tools/auzix-pkg refresh"))
    status_set(ui, "<color=#ffb86c>A package operation is already running.</color>");
}

static void install_cb(void *data, Evas_Object *obj, void *event_info) {
  (void)obj; (void)event_info;
  Package_Manager *ui = data;
  unsigned int count = selected_count(ui);
  if (count == 0) return;
  size_t capacity = 256 + ((size_t)count * 384);
  char *command = calloc(1, capacity);
  if (!command) return;
  snprintf(command, capacity, "/System/Compatibility/bin/sh -c \"");
  Eina_List *node;
  Package_Row *row;
  EINA_LIST_FOREACH(ui->rows, node, row) {
    if (!elm_check_state_get(row->check) || !package_name_safe(row->name)) continue;
    if (strlen(command) > strlen("/System/Compatibility/bin/sh -c \""))
      strncat(command, " && ", capacity - strlen(command) - 1);
    strncat(command, "/System/Compatibility/bin/sudo -n /System/Tools/auzix-pkg install '", capacity - strlen(command) - 1);
    strncat(command, row->name, capacity - strlen(command) - 1);
    strncat(command, "'", capacity - strlen(command) - 1);
  }
  strncat(command, "\"", capacity - strlen(command) - 1);
  status_set(ui, "<color=#84a7b8>Installing selected packages…</color>");
  if (!run_action(ui, ACTION_INSTALL, command))
    status_set(ui, "<color=#ffb86c>A package operation is already running.</color>");
  free(command);
}

EAPI_MAIN int elm_main(int argc, char **argv) {
  (void)argc; (void)argv;
  elm_policy_set(ELM_POLICY_QUIT, ELM_POLICY_QUIT_LAST_WINDOW_CLOSED);
  Package_Manager ui = {0};
  ui.window = elm_win_util_standard_add("auzix-package-manager", "BlackKnight // AuziX Packages");
  elm_win_autodel_set(ui.window, EINA_TRUE);
  evas_object_resize(ui.window, 960, 680);

  Evas_Object *box = elm_box_add(ui.window);
  evas_object_size_hint_weight_set(box, EVAS_HINT_EXPAND, EVAS_HINT_EXPAND);
  evas_object_size_hint_align_set(box, EVAS_HINT_FILL, EVAS_HINT_FILL);
  elm_box_padding_set(box, 12, 10);
  elm_win_resize_object_add(ui.window, box);
  evas_object_show(box);

  Evas_Object *title = elm_label_add(box);
  elm_object_text_set(title,
    "<color=#62d9ef><b>BLACKKNIGHT</b></color>  //  AUZIX PACKAGE CONTROL");
  evas_object_size_hint_align_set(title, 0.0, 0.5);
  elm_box_pack_end(box, title); evas_object_show(title);

  Evas_Object *intro = elm_label_add(box);
  elm_object_text_set(intro,
    "Repository-backed software catalog. Package discovery and transactions remain owned by auzix-pkg.");
  elm_label_line_wrap_set(intro, ELM_WRAP_WORD);
  evas_object_size_hint_weight_set(intro, EVAS_HINT_EXPAND, 0.0);
  evas_object_size_hint_align_set(intro, EVAS_HINT_FILL, 0.5);
  elm_box_pack_end(box, intro); evas_object_show(intro);

  Evas_Object *frame = elm_frame_add(box);
  elm_object_text_set(frame, "01 // AVAILABLE PACKAGES");
  evas_object_size_hint_weight_set(frame, EVAS_HINT_EXPAND, EVAS_HINT_EXPAND);
  evas_object_size_hint_align_set(frame, EVAS_HINT_FILL, EVAS_HINT_FILL);
  elm_box_pack_end(box, frame); evas_object_show(frame);

  ui.list = elm_list_add(frame);
  evas_object_size_hint_weight_set(ui.list, EVAS_HINT_EXPAND, EVAS_HINT_EXPAND);
  evas_object_size_hint_align_set(ui.list, EVAS_HINT_FILL, EVAS_HINT_FILL);
  elm_object_content_set(frame, ui.list); evas_object_show(ui.list);

  Evas_Object *buttons = elm_box_add(box);
  elm_box_horizontal_set(buttons, EINA_TRUE);
  Evas_Object *refresh = elm_button_add(buttons);
  elm_object_text_set(refresh, "REFRESH CATALOG");
  evas_object_smart_callback_add(refresh, "clicked", refresh_cb, &ui);
  elm_box_pack_end(buttons, refresh); evas_object_show(refresh);
  ui.install_button = elm_button_add(buttons);
  elm_object_text_set(ui.install_button, "INSTALL SELECTED");
  elm_object_disabled_set(ui.install_button, EINA_TRUE);
  evas_object_smart_callback_add(ui.install_button, "clicked", install_cb, &ui);
  elm_box_pack_end(buttons, ui.install_button); evas_object_show(ui.install_button);
  elm_box_pack_end(box, buttons); evas_object_show(buttons);

  ui.status = elm_label_add(box);
  elm_object_text_set(ui.status,
    "<color=#62d9ef>STATUS // READY</color>  Select a package to inspect or install.");
  elm_label_line_wrap_set(ui.status, ELM_WRAP_WORD);
  evas_object_size_hint_weight_set(ui.status, EVAS_HINT_EXPAND, 0.0);
  evas_object_size_hint_align_set(ui.status, EVAS_HINT_FILL, 0.5);
  elm_box_pack_end(box, ui.status); evas_object_show(ui.status);

  ui.data_handler = ecore_event_handler_add(ECORE_EXE_EVENT_DATA, output_cb, &ui);
  ui.error_handler = ecore_event_handler_add(ECORE_EXE_EVENT_ERROR, output_cb, &ui);
  ui.done_handler = ecore_event_handler_add(ECORE_EXE_EVENT_DEL, done_cb, &ui);
  evas_object_show(ui.window);
  list_start(&ui);
  elm_run();
  if (ui.data_handler) ecore_event_handler_del(ui.data_handler);
  if (ui.error_handler) ecore_event_handler_del(ui.error_handler);
  if (ui.done_handler) ecore_event_handler_del(ui.done_handler);
  rows_clear(&ui);
  output_reset(&ui);
  elm_shutdown();
  return 0;
}
ELM_MAIN()
