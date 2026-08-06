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
  Evas_Object *username;
  Evas_Object *password;
  Evas_Object *password_confirm;
  Evas_Object *root_policy;
  Evas_Object *storage_layout;
  Evas_Object *home_ratio;
  Evas_Object *locale;
  Evas_Object *timezone;
  Evas_Object *keyboard;
  Evas_Object *abiword;
  Evas_Object *gnumeric;
  Evas_Object *geany;
  Evas_Object *gimp;
  Evas_Object *mpv;
  Evas_Object *claws;
  Evas_Object *firefox;
  Evas_Object *zathura;
  Evas_Object *boot;
  Evas_Object *status;
  Evas_Object *run_button;
  Evas_Object *progress_popup;
  Evas_Object *progress;
  Ecore_Exe *runner;
  Ecore_Event_Handler *runner_handler;
  Eina_Bool plan_ready;
  char reviewed_disk[256];
} Installer;

static const char *plan_path = "/Users/auzix/.local/state/auzix/installer/efl-pending-plan.json";

static void status_set(Installer *ui, const char *text) {
  elm_object_text_set(ui->status, text);
}

static void package_add(char *packages, size_t size, Evas_Object *check, const char *name) {
  if (!elm_check_state_get(check)) return;
  if (packages[0]) strncat(packages, ",", size - strlen(packages) - 1);
  strncat(packages, name, size - strlen(packages) - 1);
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
  const char *username = elm_entry_entry_get(ui->username);
  const char *password = elm_entry_entry_get(ui->password);
  const char *password_confirm = elm_entry_entry_get(ui->password_confirm);
  const char *locale = elm_entry_entry_get(ui->locale);
  const char *timezone = elm_entry_entry_get(ui->timezone);
  const char *keyboard = elm_entry_entry_get(ui->keyboard);
  int boot_index = elm_radio_value_get(ui->boot);
  const char *boot = boot_index == 1 ? "iso" : "grub";
  const char *root_policy = elm_radio_value_get(ui->root_policy) == 1 ? "same" : "disabled";
  const char *layout = elm_radio_value_get(ui->storage_layout) == 1 ? "split" : "whole";
  int home_percent = (int)(elm_slider_value_get(ui->home_ratio) + 0.5);
  char packages[128] = "";
  char command[2048];

  if (!disk || strncmp(disk, "/dev/", 5) != 0 || !hostname || !hostname[0] ||
      !username || !username[0]) {
    status_set(ui, "<color=#ffb86c>Choose a target, hostname, and primary username.</color>");
    return;
  }
  if (!password || strlen(password) < 8 || strcmp(password, password_confirm ? password_confirm : "") != 0) {
    status_set(ui, "<color=#ffb86c>Primary-account passwords must match and contain at least 8 characters.</color>");
    return;
  }
  if (strpbrk(disk, "'\";`$\\") || strpbrk(hostname, "'\";`$\\") ||
      strpbrk(username, "'\";`$\\") || strpbrk(locale, "'\";`$\\") ||
      strpbrk(timezone, "'\";`$\\") || strpbrk(keyboard, "'\";`$\\")) {
    status_set(ui, "<color=#ff6b6b>Unsafe characters are not accepted in installer values.</color>");
    return;
  }
  package_add(packages, sizeof(packages), ui->abiword, "Debian.abiword");
  package_add(packages, sizeof(packages), ui->gnumeric, "Gnumeric");
  package_add(packages, sizeof(packages), ui->geany, "Debian.geany");
  package_add(packages, sizeof(packages), ui->gimp, "Debian.gimp");
  package_add(packages, sizeof(packages), ui->mpv, "Debian.mpv");
  package_add(packages, sizeof(packages), ui->claws, "Debian.claws-mail");
  package_add(packages, sizeof(packages), ui->firefox, "Debian.firefox-esr");
  package_add(packages, sizeof(packages), ui->zathura, "Debian.zathura");
  snprintf(command, sizeof(command),
           "/System/Tools/auzix-installer plan '%s' '%s' '%s' '%s' graphical '%s' '%s' '%s' '%d' '%s' '%s' '%s' '%s'",
           plan_path, disk, boot, hostname, username, root_policy, layout,
           home_percent, packages, locale, timezone, keyboard);
  if (system(command) == 0) {
    ui->plan_ready = EINA_TRUE;
    snprintf(ui->reviewed_disk, sizeof(ui->reviewed_disk), "%s", disk);
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
  char command[1024];
  progress_close(ui);
  progress_open(ui, "Installing AuziX", "Writing the confirmed plan. Do not power off this machine.\nThe live recovery environment stays available if the install reports a failure.", EINA_TRUE);
  snprintf(command, sizeof(command),
           "sudo -n /System/Tools/auzix-installer execute '%s' '%s'",
           plan_path, ui->reviewed_disk);
  ui->runner = ecore_exe_run(command, ui);
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
  if (elm_radio_value_get(ui->storage_layout) != 0) {
    status_set(ui, "<color=#ffb86c>Split root/home execution is not ready. Select Whole disk for this installer slice.</color>");
    return;
  }
  if (elm_check_state_get(ui->abiword) || elm_check_state_get(ui->gnumeric) ||
      elm_check_state_get(ui->geany) || elm_check_state_get(ui->gimp) ||
      elm_check_state_get(ui->mpv) || elm_check_state_get(ui->claws) ||
      elm_check_state_get(ui->firefox) || elm_check_state_get(ui->zathura)) {
    status_set(ui, "<color=#ffb86c>First-boot package execution is not ready. Clear package selections to install the base system.</color>");
    return;
  }
  char warning[1024];
  snprintf(warning, sizeof(warning),
           "ERASE %s and install the validated AuziX live root?\n\n"
           "This first executable slice retains the live image account defaults; identity fields are not applied yet.",
           ui->reviewed_disk);
  progress_open(ui, "Final destructive confirmation", warning, EINA_FALSE);
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

static Evas_Object *form_label(Evas_Object *parent, const char *text) {
  Evas_Object *item = elm_label_add(parent);
  char markup[512];
  snprintf(markup, sizeof(markup), "<b>%s</b>", text);
  elm_object_text_set(item, markup);
  evas_object_size_hint_align_set(item, 0.0, 0.5);
  evas_object_show(item);
  return item;
}

EAPI_MAIN int elm_main(int argc, char **argv) {
  (void)argc; (void)argv;
  elm_policy_set(ELM_POLICY_QUIT, ELM_POLICY_QUIT_LAST_WINDOW_CLOSED);
  Installer ui = {0};
  ui.window = elm_win_util_standard_add("auzix-installer", "Install AuziX");
  elm_win_autodel_set(ui.window, EINA_TRUE);
  elm_win_title_set(ui.window, "BlackKnight // AuziX Deployment");
  evas_object_resize(ui.window, 920, 620);

  Evas_Object *box = elm_box_add(ui.window);
  evas_object_size_hint_weight_set(box, EVAS_HINT_EXPAND, EVAS_HINT_EXPAND);
  evas_object_size_hint_align_set(box, EVAS_HINT_FILL, EVAS_HINT_FILL);
  elm_box_padding_set(box, 12, 10);
  elm_win_resize_object_add(ui.window, box);
  evas_object_show(box);

  Evas_Object *header = elm_label_add(box);
  elm_object_text_set(header,
    "<color=#62d9ef><b>BLACKKNIGHT</b></color>  //  AUZIX DEPLOYMENT CONTROL");
  evas_object_size_hint_align_set(header, 0.0, 0.5);
  elm_box_pack_end(box, header); evas_object_show(header);

  Evas_Object *intro = elm_label_add(box);
  elm_object_text_set(intro,
    "Operator lane: define the target, validate a signed-off plan, then cross the destructive gate separately.");
  elm_label_line_wrap_set(intro, ELM_WRAP_WORD);
  evas_object_size_hint_weight_set(intro, EVAS_HINT_EXPAND, 0.0);
  evas_object_size_hint_align_set(intro, EVAS_HINT_FILL, 0.5);
  elm_box_pack_end(box, intro); evas_object_show(intro);

  Evas_Object *frame = elm_frame_add(box);
  elm_object_text_set(frame, "01 // TARGET AND HANDOFF");
  evas_object_size_hint_weight_set(frame, EVAS_HINT_EXPAND, EVAS_HINT_EXPAND);
  evas_object_size_hint_align_set(frame, EVAS_HINT_FILL, EVAS_HINT_FILL);
  elm_box_pack_end(box, frame); evas_object_show(frame);

  Evas_Object *scroller = elm_scroller_add(frame);
  elm_scroller_policy_set(scroller, ELM_SCROLLER_POLICY_OFF, ELM_SCROLLER_POLICY_AUTO);
  evas_object_size_hint_weight_set(scroller, EVAS_HINT_EXPAND, EVAS_HINT_EXPAND);
  evas_object_size_hint_align_set(scroller, EVAS_HINT_FILL, EVAS_HINT_FILL);
  elm_object_content_set(frame, scroller); evas_object_show(scroller);

  Evas_Object *table = elm_table_add(scroller);
  elm_table_padding_set(table, 16, 14);
  evas_object_size_hint_weight_set(table, EVAS_HINT_EXPAND, EVAS_HINT_EXPAND);
  evas_object_size_hint_align_set(table, EVAS_HINT_FILL, EVAS_HINT_FILL);
  elm_object_content_set(scroller, table); evas_object_show(table);

  Evas_Object *disk_label = form_label(table, "Target disk");
  elm_table_pack(table, disk_label, 0, 0, 1, 1);
  ui.disk = elm_entry_add(table);
  elm_entry_single_line_set(ui.disk, EINA_TRUE);
  elm_object_part_text_set(ui.disk, "guide", "/dev/sda");
  elm_entry_entry_set(ui.disk, "/dev/sda");
  evas_object_size_hint_weight_set(ui.disk, EVAS_HINT_EXPAND, 0.0);
  evas_object_size_hint_align_set(ui.disk, EVAS_HINT_FILL, 0.5);
  evas_object_size_hint_min_set(ui.disk, 420, 42);
  elm_table_pack(table, ui.disk, 1, 0, 1, 1); evas_object_show(ui.disk);

  Evas_Object *host_label = form_label(table, "Machine name");
  elm_table_pack(table, host_label, 0, 1, 1, 1);
  ui.hostname = elm_entry_add(table);
  elm_entry_single_line_set(ui.hostname, EINA_TRUE);
  elm_entry_entry_set(ui.hostname, "auzix");
  evas_object_size_hint_weight_set(ui.hostname, EVAS_HINT_EXPAND, 0.0);
  evas_object_size_hint_align_set(ui.hostname, EVAS_HINT_FILL, 0.5);
  evas_object_size_hint_min_set(ui.hostname, 420, 42);
  elm_table_pack(table, ui.hostname, 1, 1, 1, 1); evas_object_show(ui.hostname);

  Evas_Object *user_label = form_label(table, "Primary user");
  elm_table_pack(table, user_label, 0, 2, 1, 1);
  ui.username = elm_entry_add(table);
  elm_entry_single_line_set(ui.username, EINA_TRUE); elm_entry_entry_set(ui.username, "auzix");
  evas_object_size_hint_min_set(ui.username, 420, 42);
  elm_table_pack(table, ui.username, 1, 2, 1, 1); evas_object_show(ui.username);

  Evas_Object *password_label = form_label(table, "Password");
  elm_table_pack(table, password_label, 0, 3, 1, 1);
  Evas_Object *password_frame = elm_frame_add(table); elm_object_text_set(password_frame, "At least 8 characters");
  ui.password = elm_entry_add(password_frame); elm_entry_single_line_set(ui.password, EINA_TRUE); elm_entry_password_set(ui.password, EINA_TRUE);
  elm_object_content_set(password_frame, ui.password); evas_object_show(ui.password);
  elm_table_pack(table, password_frame, 1, 3, 1, 1); evas_object_show(password_frame);

  Evas_Object *confirm_label = form_label(table, "Confirm password");
  elm_table_pack(table, confirm_label, 0, 4, 1, 1);
  Evas_Object *confirm_frame = elm_frame_add(table); elm_object_text_set(confirm_frame, "Repeat account password");
  ui.password_confirm = elm_entry_add(confirm_frame); elm_entry_single_line_set(ui.password_confirm, EINA_TRUE); elm_entry_password_set(ui.password_confirm, EINA_TRUE);
  elm_object_content_set(confirm_frame, ui.password_confirm); evas_object_show(ui.password_confirm);
  elm_table_pack(table, confirm_frame, 1, 4, 1, 1); evas_object_show(confirm_frame);

  Evas_Object *root_label = form_label(table, "Root login"); elm_table_pack(table, root_label, 0, 5, 1, 1);
  Evas_Object *root_box = elm_box_add(table); elm_box_horizontal_set(root_box, EINA_TRUE); elm_box_padding_set(root_box, 18, 0);
  Evas_Object *root_off = elm_radio_add(root_box); elm_object_text_set(root_off, "Disabled (sudo)"); elm_radio_state_value_set(root_off, 0);
  Evas_Object *root_same = elm_radio_add(root_box); elm_object_text_set(root_same, "Use account password"); elm_radio_state_value_set(root_same, 1); elm_radio_group_add(root_same, root_off);
  ui.root_policy = root_off; elm_box_pack_end(root_box, root_off); elm_box_pack_end(root_box, root_same);
  elm_table_pack(table, root_box, 1, 5, 1, 1); evas_object_show(root_off); evas_object_show(root_same); evas_object_show(root_box);

  Evas_Object *boot_label = form_label(table, "Boot setup");
  elm_table_pack(table, boot_label, 0, 6, 1, 1);
  Evas_Object *boot_box = elm_box_add(table);
  elm_box_horizontal_set(boot_box, EINA_TRUE);
  elm_box_padding_set(boot_box, 18, 0);
  Evas_Object *grub = elm_radio_add(boot_box);
  elm_object_text_set(grub, "Install GRUB"); elm_radio_state_value_set(grub, 0);
  Evas_Object *iso = elm_radio_add(boot_box);
  elm_object_text_set(iso, "Test handoff only"); elm_radio_state_value_set(iso, 1);
  elm_radio_group_add(iso, grub); elm_radio_value_set(grub, 0);
  ui.boot = grub;
  elm_box_pack_end(boot_box, grub); elm_box_pack_end(boot_box, iso);
  elm_table_pack(table, boot_box, 1, 6, 1, 1);
  evas_object_show(grub); evas_object_show(iso); evas_object_show(boot_box);

  Evas_Object *layout_label = form_label(table, "Storage layout"); elm_table_pack(table, layout_label, 0, 7, 1, 1);
  Evas_Object *layout_box = elm_box_add(table); elm_box_horizontal_set(layout_box, EINA_TRUE); elm_box_padding_set(layout_box, 18, 0);
  Evas_Object *whole = elm_radio_add(layout_box); elm_object_text_set(whole, "Whole disk"); elm_radio_state_value_set(whole, 0);
  Evas_Object *split = elm_radio_add(layout_box); elm_object_text_set(split, "Split root/home"); elm_radio_state_value_set(split, 1); elm_radio_group_add(split, whole);
  ui.storage_layout = whole; elm_box_pack_end(layout_box, whole); elm_box_pack_end(layout_box, split);
  elm_table_pack(table, layout_box, 1, 7, 1, 1); evas_object_show(whole); evas_object_show(split); evas_object_show(layout_box);

  Evas_Object *ratio_label = form_label(table, "Home allocation"); elm_table_pack(table, ratio_label, 0, 8, 1, 1);
  ui.home_ratio = elm_slider_add(table); elm_slider_min_max_set(ui.home_ratio, 20, 80); elm_slider_value_set(ui.home_ratio, 60);
  elm_slider_unit_format_set(ui.home_ratio, "%1.0f%% to /home"); elm_table_pack(table, ui.home_ratio, 1, 8, 1, 1); evas_object_show(ui.home_ratio);

  Evas_Object *region_label = form_label(table, "Region defaults"); elm_table_pack(table, region_label, 0, 9, 1, 1);
  Evas_Object *region = elm_box_add(table); elm_box_horizontal_set(region, EINA_TRUE);
  ui.locale = elm_entry_add(region); elm_entry_single_line_set(ui.locale, EINA_TRUE); elm_entry_entry_set(ui.locale, "en_US.UTF-8"); elm_box_pack_end(region, ui.locale); evas_object_show(ui.locale);
  ui.timezone = elm_entry_add(region); elm_entry_single_line_set(ui.timezone, EINA_TRUE); elm_entry_entry_set(ui.timezone, "America/Los_Angeles"); elm_box_pack_end(region, ui.timezone); evas_object_show(ui.timezone);
  ui.keyboard = elm_entry_add(region); elm_entry_single_line_set(ui.keyboard, EINA_TRUE); elm_entry_entry_set(ui.keyboard, "us"); elm_box_pack_end(region, ui.keyboard); evas_object_show(ui.keyboard);
  elm_table_pack(table, region, 1, 9, 1, 1); evas_object_show(region);

  Evas_Object *packages_label = form_label(table, "First-boot packages"); elm_table_pack(table, packages_label, 0, 10, 1, 1);
  Evas_Object *package_scroll = elm_scroller_add(table); elm_scroller_policy_set(package_scroll, ELM_SCROLLER_POLICY_OFF, ELM_SCROLLER_POLICY_AUTO); evas_object_size_hint_min_set(package_scroll, 420, 150);
  Evas_Object *package_box = elm_box_add(package_scroll); elm_box_padding_set(package_box, 4, 4);
#define ADD_PACKAGE_CHECK(field, label, selected) do { \
  ui.field = elm_check_add(package_box); elm_object_text_set(ui.field, label); \
  elm_check_state_set(ui.field, selected); elm_box_pack_end(package_box, ui.field); evas_object_show(ui.field); \
} while (0)
  ADD_PACKAGE_CHECK(abiword, "AbiWord — documents (planned)", EINA_FALSE);
  ADD_PACKAGE_CHECK(gnumeric, "Gnumeric — spreadsheets (planned)", EINA_FALSE);
  ADD_PACKAGE_CHECK(geany, "Geany — editor and lightweight IDE", EINA_FALSE);
  ADD_PACKAGE_CHECK(gimp, "GIMP — image editing", EINA_FALSE);
  ADD_PACKAGE_CHECK(mpv, "MPV — media playback", EINA_FALSE);
  ADD_PACKAGE_CHECK(claws, "Claws Mail — email", EINA_FALSE);
  ADD_PACKAGE_CHECK(firefox, "Firefox ESR — full browser", EINA_FALSE);
  ADD_PACKAGE_CHECK(zathura, "Zathura — document viewer", EINA_FALSE);
#undef ADD_PACKAGE_CHECK
  elm_object_content_set(package_scroll, package_box); evas_object_show(package_box);
  elm_table_pack(table, package_scroll, 1, 10, 1, 1); evas_object_show(package_scroll);

  Evas_Object *safety = elm_label_add(table);
  elm_object_text_set(safety,
    "<color=#ffb86c><b>Safety:</b> validating saves a plan only. Disk changes require a second explicit confirmation.</color>");
  elm_label_line_wrap_set(safety, ELM_WRAP_WORD);
  evas_object_size_hint_weight_set(safety, EVAS_HINT_EXPAND, 0.0);
  evas_object_size_hint_align_set(safety, EVAS_HINT_FILL, 0.5);
  elm_table_pack(table, safety, 0, 11, 2, 1); evas_object_show(safety);

  Evas_Object *actions = elm_box_add(box);
  elm_box_horizontal_set(actions, EINA_TRUE);
  elm_box_padding_set(actions, 12, 0);
  evas_object_size_hint_weight_set(actions, EVAS_HINT_EXPAND, 0.0);
  evas_object_size_hint_align_set(actions, EVAS_HINT_FILL, 0.5);
  Evas_Object *button = elm_button_add(actions);
  elm_object_text_set(button, "VALIDATE PLAN");
  evas_object_smart_callback_add(button, "clicked", write_plan_cb, &ui);
  evas_object_size_hint_weight_set(button, EVAS_HINT_EXPAND, 0.0);
  evas_object_size_hint_align_set(button, EVAS_HINT_FILL, 0.5);
  elm_box_pack_end(actions, button); evas_object_show(button);

  ui.run_button = elm_button_add(actions);
  elm_object_text_set(ui.run_button, "AUTHORIZE INSTALL");
  elm_object_disabled_set(ui.run_button, EINA_TRUE);
  evas_object_smart_callback_add(ui.run_button, "clicked", begin_install_cb, &ui);
  evas_object_size_hint_weight_set(ui.run_button, EVAS_HINT_EXPAND, 0.0);
  evas_object_size_hint_align_set(ui.run_button, EVAS_HINT_FILL, 0.5);
  elm_box_pack_end(actions, ui.run_button); evas_object_show(ui.run_button);
  elm_box_pack_end(box, actions); evas_object_show(actions);

  ui.status = elm_label_add(box);
  elm_object_text_set(ui.status,
    "<color=#62d9ef>STATUS // READY</color>  No storage changes are armed.");
  elm_label_line_wrap_set(ui.status, ELM_WRAP_WORD);
  evas_object_size_hint_weight_set(ui.status, EVAS_HINT_EXPAND, 0.0);
  evas_object_size_hint_align_set(ui.status, EVAS_HINT_FILL, 0.5);
  elm_box_pack_end(box, ui.status); evas_object_show(ui.status);

  evas_object_show(ui.window);
  ui.runner_handler = ecore_event_handler_add(ECORE_EXE_EVENT_DEL, install_done_cb, &ui);
  elm_run();
  if (ui.runner_handler) ecore_event_handler_del(ui.runner_handler);
  elm_shutdown();
  return 0;
}
ELM_MAIN()
