#include <Elementary.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/*
 * AuziX Installer — native EFL first slice
 *
 * This UI intentionally produces only an unconfirmed JSON plan.  The trusted
 * Lua plan validator/executor stays the sole component that can erase a disk.
 */
typedef struct {
  Evas_Object *window;
  Evas_Object *disk;
  Evas_Object *hostname;
  Evas_Object *boot;
  Evas_Object *status;
  Evas_Object *run_button;
  Evas_Object *progress_popup;
  Evas_Object *progress;
  Ecore_Exe *runner;
  Ecore_Event_Handler *runner_handler;
  Eina_Bool plan_ready;
} Installer;

static const char *plan_path = "/System/State/installer/efl-pending-plan.json";

static void status_set(Installer *ui, const char *text) {
  elm_object_text_set(ui->status, text);
}

static void progress_open(Installer *ui, const char *title, const char *detail, Eina_Bool pulse) {
  if (ui->progress_popup) evas_object_del(ui->progress_popup);
  ui->progress_popup = elm_popup_add(ui->window);
  elm_object_part_text_set(ui->progress_popup, "title,text", title);
  Evas_Object *box = elm_box_add(ui->progress_popup);
  elm_box_padding_set(box, 8, 8);
  Evas_Object *message = elm_label_add(box);
  elm_object_text_set(message, detail);
  elm_box_pack_end(box, message);
  evas_object_show(message);
  ui->progress = elm_progressbar_add(box);
  elm_progressbar_unit_format_set(ui->progress, pulse ? "Working…" : "100 %");
  if (pulse) {
    elm_progressbar_pulse_set(ui->progress, EINA_TRUE);
    elm_progressbar_pulse(ui->progress, EINA_TRUE);
  } else {
    elm_progressbar_value_set(ui->progress, 1.0);
  }
  elm_box_pack_end(box, ui->progress);
  evas_object_show(ui->progress);
  elm_object_content_set(ui->progress_popup, box);
  evas_object_show(box);
  evas_object_show(ui->progress_popup);
}

static void progress_close(Installer *ui) {
  if (ui->progress_popup) {
    evas_object_del(ui->progress_popup);
    ui->progress_popup = NULL;
    ui->progress = NULL;
  }
}

static void cancel_install_cb(void *data, Evas_Object *obj, void *event_info) {
  (void)obj;
  (void)event_info;
  progress_close(data);
}

static Eina_Bool install_done_cb(void *data, int type, void *event_info) {
  (void)type;
  Installer *ui = data;
  Ecore_Exe_Event_Del *event = event_info;
  if (!ui->runner || event->exe != ui->runner) return ECORE_CALLBACK_RENEW;
  progress_close(ui);
  ui->runner = NULL;
  if (event->exit_code == 0) {
    status_set(ui, "<color=#82d4bb>Install finished. Review the receipt, then reboot from the installed disk.</color>");
  } else {
    status_set(ui, "<color=#ff6b6b>Install failed or was interrupted. The live session remains available for recovery.</color>");
  }
  return ECORE_CALLBACK_RENEW;
}

static void write_plan_cb(void *data, Evas_Object *obj, void *event_info) {
  (void)obj; (void)event_info;
  Installer *ui = data;
  const char *disk = elm_entry_entry_get(ui->disk);
  const char *hostname = elm_entry_entry_get(ui->hostname);
  int boot_index = elm_radio_value_get(ui->boot);
  const char *boot = boot_index == 1 ? "iso" : "grub";
  char command[1024];

  if (!disk || strncmp(disk, "/dev/", 5) != 0 || !hostname || !hostname[0]) {
    status_set(ui, "<color=#ffb86c>Choose a /dev target and hostname before creating a plan.</color>");
    return;
  }
  if (strpbrk(disk, "'\";`$\\") || strpbrk(hostname, "'\";`$\\")) {
    status_set(ui, "<color=#ff6b6b>Unsafe characters are not accepted in installer values.</color>");
    return;
  }
  snprintf(command, sizeof(command),
           "/System/Tools/auzix-installer plan '%s' '%s' '%s' '%s' graphical",
           plan_path, disk, boot, hostname);
  if (system(command) == 0) {
    ui->plan_ready = EINA_TRUE;
    elm_object_disabled_set(ui->run_button, EINA_FALSE);
    progress_open(ui, "Plan validated", "The selected disk has not changed.\nA guarded install plan is ready for final review.", EINA_FALSE);
    status_set(ui, "<color=#82d4bb>Plan validated and saved. Nothing has been written to disk.</color>");
  } else {
    status_set(ui, "<color=#ff6b6b>Plan validation failed. Review the selected values.</color>");
  }
}

static void install_confirm_cb(void *data, Evas_Object *obj, void *event_info) {
  (void)obj; (void)event_info;
  Installer *ui = data;
  progress_close(ui);
  progress_open(ui, "Installing AuziX", "Writing the confirmed plan. Do not power off this machine.\nThe live recovery environment stays available if the install reports a failure.", EINA_TRUE);
  ui->runner = ecore_exe_run("/System/Tools/auzix-installer run /System/State/installer/efl-pending-plan.json", ui);
  if (!ui->runner) {
    progress_close(ui);
    status_set(ui, "<color=#ff6b6b>Could not start the guarded installer command.</color>");
  }
}

static void begin_install_cb(void *data, Evas_Object *obj, void *event_info) {
  (void)obj; (void)event_info;
  Installer *ui = data;
  if (!ui->plan_ready) {
    status_set(ui, "<color=#ffb86c>Validate a plan before requesting installation.</color>");
    return;
  }
  progress_open(ui, "Final destructive confirmation",
                "This runs the previously validated plan and erases its selected disk.\nChoose Install only after reviewing the plan.", EINA_FALSE);
  Evas_Object *cancel = elm_button_add(ui->progress_popup);
  elm_object_text_set(cancel, "Cancel");
  evas_object_smart_callback_add(cancel, "clicked", cancel_install_cb, ui);
  elm_object_part_content_set(ui->progress_popup, "button1", cancel);
  evas_object_show(cancel);
  Evas_Object *confirm = elm_button_add(ui->progress_popup);
  elm_object_text_set(confirm, "Erase disk and install");
  evas_object_smart_callback_add(confirm, "clicked", install_confirm_cb, ui);
  elm_object_part_content_set(ui->progress_popup, "button2", confirm);
  evas_object_show(confirm);
}

static Evas_Object *label(Evas_Object *parent, const char *text, int size) {
  Evas_Object *item = elm_label_add(parent);
  char markup[2048];
  snprintf(markup, sizeof(markup), "<font_size=%d><color=#dceaf3>%s</color></font_size>", size, text);
  elm_object_text_set(item, markup);
  evas_object_size_hint_weight_set(item, EVAS_HINT_EXPAND, 0.0);
  evas_object_size_hint_align_set(item, EVAS_HINT_FILL, 0.5);
  evas_object_show(item);
  return item;
}

EAPI_MAIN int elm_main(int argc, char **argv) {
  (void)argc; (void)argv;
  elm_policy_set(ELM_POLICY_QUIT, ELM_POLICY_QUIT_LAST_WINDOW_CLOSED);
  Installer ui = {0};
  ui.window = elm_win_util_standard_add("auzix-installer", "Install AuziX");
  elm_win_autodel_set(ui.window, EINA_TRUE);
  elm_win_title_set(ui.window, "Install AuziX — guided live installer");
  evas_object_resize(ui.window, 860, 600);

  Evas_Object *box = elm_box_add(ui.window);
  evas_object_size_hint_weight_set(box, EVAS_HINT_EXPAND, EVAS_HINT_EXPAND);
  evas_object_size_hint_align_set(box, EVAS_HINT_FILL, EVAS_HINT_FILL);
  elm_box_padding_set(box, 14, 10);
  elm_win_resize_object_add(ui.window, box);
  evas_object_show(box);

  elm_box_pack_end(box, label(box, "<b>AUZIX // FIRSTBOOT INSTALLER</b>", 28));
  elm_box_pack_end(box, label(box, "Plan first. Validate. Confirm separately.  The disk is never touched from this screen.", 15));
  elm_box_pack_end(box, label(box, "01  Target disk", 18));
  ui.disk = elm_entry_add(box);
  elm_entry_single_line_set(ui.disk, EINA_TRUE);
  elm_object_part_text_set(ui.disk, "guide", "/dev/sda");
  elm_entry_entry_set(ui.disk, "/dev/sda");
  evas_object_size_hint_weight_set(ui.disk, EVAS_HINT_EXPAND, 0.0);
  evas_object_size_hint_align_set(ui.disk, EVAS_HINT_FILL, 0.5);
  elm_box_pack_end(box, ui.disk); evas_object_show(ui.disk);

  elm_box_pack_end(box, label(box, "02  Machine identity", 18));
  ui.hostname = elm_entry_add(box);
  elm_entry_single_line_set(ui.hostname, EINA_TRUE);
  elm_entry_entry_set(ui.hostname, "auzix");
  evas_object_size_hint_weight_set(ui.hostname, EVAS_HINT_EXPAND, 0.0);
  evas_object_size_hint_align_set(ui.hostname, EVAS_HINT_FILL, 0.5);
  elm_box_pack_end(box, ui.hostname); evas_object_show(ui.hostname);

  elm_box_pack_end(box, label(box, "03  Boot handoff", 18));
  Evas_Object *boot_box = elm_box_add(box);
  elm_box_horizontal_set(boot_box, EINA_TRUE);
  Evas_Object *grub = elm_radio_add(boot_box);
  elm_object_text_set(grub, "Install GRUB"); elm_radio_state_value_set(grub, 0);
  Evas_Object *iso = elm_radio_add(boot_box);
  elm_object_text_set(iso, "Live-ISO test handoff"); elm_radio_state_value_set(iso, 1);
  elm_radio_group_add(iso, grub); elm_radio_value_set(grub, 0);
  ui.boot = grub;
  elm_box_pack_end(boot_box, grub); elm_box_pack_end(boot_box, iso);
  elm_box_pack_end(box, boot_box); evas_object_show(grub); evas_object_show(iso); evas_object_show(boot_box);

  Evas_Object *button = elm_button_add(box);
  elm_object_text_set(button, "Validate and save unconfirmed plan");
  evas_object_smart_callback_add(button, "clicked", write_plan_cb, &ui);
  evas_object_size_hint_weight_set(button, EVAS_HINT_EXPAND, 0.0);
  evas_object_size_hint_align_set(button, EVAS_HINT_FILL, 0.5);
  elm_box_pack_end(box, button); evas_object_show(button);

  ui.run_button = elm_button_add(box);
  elm_object_text_set(ui.run_button, "Review and begin guarded install");
  elm_object_disabled_set(ui.run_button, EINA_TRUE);
  evas_object_smart_callback_add(ui.run_button, "clicked", begin_install_cb, &ui);
  evas_object_size_hint_weight_set(ui.run_button, EVAS_HINT_EXPAND, 0.0);
  evas_object_size_hint_align_set(ui.run_button, EVAS_HINT_FILL, 0.5);
  elm_box_pack_end(box, ui.run_button); evas_object_show(ui.run_button);

  ui.status = elm_label_add(box);
  elm_object_text_set(ui.status, "<color=#84a7b8>Next: review the saved plan, then use the explicit confirmation path.</color>");
  evas_object_size_hint_weight_set(ui.status, EVAS_HINT_EXPAND, EVAS_HINT_EXPAND);
  evas_object_size_hint_align_set(ui.status, EVAS_HINT_FILL, 0.0);
  elm_box_pack_end(box, ui.status); evas_object_show(ui.status);

  evas_object_show(ui.window);
  ui.runner_handler = ecore_event_handler_add(ECORE_EXE_EVENT_DEL, install_done_cb, &ui);
  elm_run();
  if (ui.runner_handler) ecore_event_handler_del(ui.runner_handler);
  elm_shutdown();
  return 0;
}
ELM_MAIN()
