#include <Elementary.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

/*
 * AuziX Installer — native EFL first slice
 *
 * This UI intentionally produces only an unconfirmed JSON plan.  The trusted
 * Lua plan validator/executor stays the sole component that can erase a disk.
 */
typedef struct {
  Evas_Object *window;
  Evas_Object *disk;
  Evas_Object *repo_url;
  Evas_Object *profile;
  Evas_Object *hostname;
  Evas_Object *username;
  Evas_Object *password;
  Evas_Object *password_confirm;
  Evas_Object *root_policy;
  Evas_Object *storage_layout;
  Evas_Object *home_ratio;
  Evas_Object *work_ratio;
  Evas_Object *programs_ratio;
  Evas_Object *allocation_tally;
  Evas_Object *locale;
  Evas_Object *timezone;
  Evas_Object *keyboard;
  Evas_Object *theme_profile;
  Evas_Object *wallpaper_profile;
  Evas_Object *office;
  Evas_Object *dtp;
  Evas_Object *internet;
  Evas_Object *music_media;
  Evas_Object *graphics;
  Evas_Object *dev_ide;
  Evas_Object *containers;
  Evas_Object *retro;
  Evas_Object *boot;
  Evas_Object *status;
  Evas_Object *run_button;
  Evas_Object *progress_popup;
  Evas_Object *progress;
  Evas_Object *progress_detail;
  Ecore_Exe *runner;
  Ecore_Event_Handler *runner_handler;
  Ecore_Event_Handler *preflight_handler;
  Ecore_Timer *validate_timer;
  Ecore_Timer *install_timer;
  enum {
    RUNNER_NONE = 0,
    RUNNER_VALIDATE,
    RUNNER_PREFLIGHT,
    RUNNER_INSTALL
  } runner_kind;
  Eina_Bool plan_ready;
  char reviewed_disk[256];
  char pending_disk[256];
  int validate_ticks;
  int install_ticks;
} Installer;

static const char *plan_path = "/Users/auzix/.local/state/auzix/installer/efl-pending-plan.json";
static const char *install_log_path = "/System/Logs/installer/package-built-install.log";
static const char *install_pid_path = "/System/Logs/installer/package-built-install.pid";
static const char *brand_mark_path = "/System/Settings/installer/theme/mark-shield-swords.png";
static const char *vm135_theme_path = "/System/Compatibility/usr/share/elementary/themes/Transient-Color.edj";
static const char *fallback_theme_path = "/System/Compatibility/usr/share/elementary/themes/Dark.edj";

static void status_set(Installer *ui, const char *text) {
  elm_object_text_set(ui->status, text);
}

static int allocation_points(Installer *ui) {
  return (int)(elm_slider_value_get(ui->home_ratio) + 0.5) +
         (int)(elm_slider_value_get(ui->work_ratio) + 0.5) +
         (int)(elm_slider_value_get(ui->programs_ratio) + 0.5);
}

static void allocation_tally_update(Installer *ui) {
  if (!ui->allocation_tally) return;
  int total = allocation_points(ui);
  char markup[256];
  const char *color = total > 80 ? "#ffb86c" : "#82d4bb";
  snprintf(markup, sizeof(markup),
           "<color=%s><b>Data allocation tally:</b> %d / 80 points used. Root/system keeps the rest.</color>",
           color, total);
  elm_object_text_set(ui->allocation_tally, markup);
}

static void allocation_slider_changed_cb(void *data, Evas_Object *obj, void *event_info) {
  (void)obj;
  (void)event_info;
  allocation_tally_update(data);
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
  evas_object_size_hint_weight_set(message, EVAS_HINT_EXPAND, 0.0);
  evas_object_size_hint_align_set(message, EVAS_HINT_FILL, 0.5);
  elm_box_pack_end(box, message);
  evas_object_show(message);
  ui->progress_detail = elm_label_add(box);
  elm_label_line_wrap_set(ui->progress_detail, ELM_WRAP_WORD);
  elm_object_text_set(ui->progress_detail, "");
  evas_object_size_hint_weight_set(ui->progress_detail, EVAS_HINT_EXPAND, EVAS_HINT_EXPAND);
  evas_object_size_hint_align_set(ui->progress_detail, EVAS_HINT_FILL, EVAS_HINT_FILL);
  evas_object_size_hint_min_set(ui->progress_detail, 620, 180);
  elm_box_pack_end(box, ui->progress_detail);
  evas_object_show(ui->progress_detail);
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
    ui->progress_detail = NULL;
  }
  if (ui->install_timer) {
    ecore_timer_del(ui->install_timer);
    ui->install_timer = NULL;
  }
}

static void progress_close_cb(void *data, Evas_Object *obj, void *event_info) {
  (void)obj;
  (void)event_info;
  progress_close(data);
}

static void install_success_prompt(Installer *ui) {
  progress_close(ui);
  progress_open(ui,
                "Install complete",
                "AUZiX has been installed from repository packages and the target filesystems have been synced and unmounted.\n\n"
                "Next step: disconnect or remove the live ISO, then reboot this VM from the installed disk.",
                EINA_FALSE);
  Evas_Object *close = elm_button_add(ui->progress_popup);
  elm_object_text_set(close, "I will remove ISO and reboot");
  evas_object_smart_callback_add(close, "clicked", progress_close_cb, ui);
  elm_object_part_content_set(ui->progress_popup, "button1", close);
  evas_object_show(close);
  status_set(ui, "<color=#82d4bb>Install complete. Remove the live ISO and reboot from the installed disk.</color>");
}

static void safe_copy(char *dst, size_t dst_size, const char *src) {
  size_t i;
  if (!dst || dst_size == 0) return;
  if (!src) src = "";
  for (i = 0; i + 1 < dst_size && src[i]; i++) dst[i] = src[i];
  dst[i] = '\0';
}

static void install_progress_update(Installer *ui, Eina_Bool done) {
  if (!ui->progress_detail) return;
  FILE *f = fopen(install_log_path, "r");
  char line[1024];
  char tier[256] = "";
  char request[256] = "";
  char warn[512] = "";
  char final[512] = "";
  char stage[512] = "";
  int installs = 0;
  int missing = -1;
  int stage_step = 0;
  int stage_total = 0;
  if (f) {
    while (fgets(line, sizeof(line), f)) {
      size_t len = strlen(line);
      while (len && (line[len - 1] == '\n' || line[len - 1] == '\r')) line[--len] = 0;
      if (strncmp(line, "TIER ", 5) == 0) {
        safe_copy(tier, sizeof(tier), line + 5);
      } else if (strncmp(line, "REQUEST ", 8) == 0) {
        safe_copy(request, sizeof(request), line + 8);
      } else if (strncmp(line, "WARN missing ", 13) == 0) {
        safe_copy(warn, sizeof(warn), line);
      } else if (strncmp(line, "INSTALL package=", 16) == 0) {
        installs++;
      } else if (strncmp(line, "INSTALL_STAGE ", 14) == 0) {
        char *step = strstr(line, "step=");
        char *total = strstr(line, "total=");
        char *label = strstr(line, "label=");
        if (step) stage_step = atoi(step + 5);
        if (total) stage_total = atoi(total + 6);
        if (label) safe_copy(stage, sizeof(stage), label + 6);
      } else if (strncmp(line, "PACKAGE_PROFILE_INSTALL_DONE", 28) == 0) {
        safe_copy(final, sizeof(final), line);
        char *m = strstr(line, " missing=");
        if (m) missing = atoi(m + 9);
      } else if (strncmp(line, "INSTALL_DONE ", 13) == 0) {
        safe_copy(final, sizeof(final), line);
      } else if (strncmp(line, "FATAL ", 6) == 0) {
        safe_copy(final, sizeof(final), line);
      }
    }
    fclose(f);
  }
  char detail[1536];
  char stage_fraction[64] = "";
  if (stage_total > 0) {
    snprintf(stage_fraction, sizeof(stage_fraction), " (%d / %d)", stage_step, stage_total);
  }
  snprintf(detail, sizeof(detail),
           "<b>%s</b><br>"
           "Stage: %s%s<br>"
           "Tier: %s<br>"
           "Now: %s<br>"
           "Packages observed: %d<br>"
           "%s%s%s%s",
           done ? "Install finished" : "Installing package profile",
           stage[0] ? stage : "starting",
           stage_fraction,
           tier[0] ? tier : "starting",
           request[0] ? request : "waiting for installer log",
           installs,
           warn[0] ? "Latest warning: " : "",
           warn[0] ? warn : "",
           final[0] ? "<br>Final: " : "",
           final[0] ? final : "");
  elm_object_text_set(ui->progress_detail, detail);
  if (ui->progress && stage_step > 0 && stage_total > 0 && !done) {
    double value = (double)stage_step / (double)stage_total;
    if (value < 0.02) value = 0.02;
    if (value > 0.98) value = 0.98;
    elm_progressbar_pulse(ui->progress, EINA_FALSE);
    elm_progressbar_value_set(ui->progress, value);
    char unit[64];
    snprintf(unit, sizeof(unit), "%d / %d", stage_step, stage_total);
    elm_progressbar_unit_format_set(ui->progress, unit);
  } else if (ui->progress && installs > 0 && !done) {
    double pulse = (ui->install_ticks % 20) / 20.0;
    elm_progressbar_value_set(ui->progress, pulse);
  }
  if (done && ui->progress) elm_progressbar_value_set(ui->progress, 1.0);
  if (missing >= 0) {
    char status[512];
    snprintf(status, sizeof(status), "<color=#82d4bb>Install finished with %d missing package-contract entries. Remove ISO and reboot when ready.</color>", missing);
    status_set(ui, status);
  }
}

static Eina_Bool install_poll_cb(void *data) {
  Installer *ui = data;
  ui->install_ticks++;
  install_progress_update(ui, EINA_FALSE);
  return ECORE_CALLBACK_RENEW;
}

static void validate_success(Installer *ui) {
  progress_close(ui);
  ui->plan_ready = EINA_TRUE;
  snprintf(ui->reviewed_disk, sizeof(ui->reviewed_disk), "%s", ui->pending_disk);
  elm_object_disabled_set(ui->run_button, EINA_FALSE);
  progress_open(ui, "Plan validated", "The selected disk has not changed.\nPackage group intent is saved for first boot.\nA guarded install plan is ready for final review.", EINA_FALSE);
  Evas_Object *continue_button = elm_button_add(ui->progress_popup);
  elm_object_text_set(continue_button, "Continue to install options");
  evas_object_smart_callback_add(continue_button, "clicked", progress_close_cb, ui);
  elm_object_part_content_set(ui->progress_popup, "button1", continue_button);
  evas_object_show(continue_button);
  status_set(ui, "<color=#82d4bb>Plan validated and saved. Nothing has been written to disk.</color>");
}

static Eina_Bool validate_poll_cb(void *data) {
  Installer *ui = data;
  ui->validate_ticks++;
  if (access(plan_path, R_OK) == 0) {
    ui->validate_timer = NULL;
    ui->runner = NULL;
    ui->runner_kind = RUNNER_NONE;
    validate_success(ui);
    return ECORE_CALLBACK_CANCEL;
  }
  if (ui->validate_ticks >= 10) {
    ui->validate_timer = NULL;
    progress_close(ui);
    ui->plan_ready = EINA_FALSE;
    elm_object_disabled_set(ui->run_button, EINA_TRUE);
    status_set(ui, "<color=#ff6b6b>Plan validation did not return. Check /System/Logs/installer/installer-launch.log.</color>");
    return ECORE_CALLBACK_CANCEL;
  }
  return ECORE_CALLBACK_RENEW;
}

static void cancel_install_cb(void *data, Evas_Object *obj, void *event_info) {
  (void)obj;
  (void)event_info;
  progress_close(data);
}

static Eina_Bool runner_event_cb(void *data, int type, void *event_info);

static void write_plan_cb(void *data, Evas_Object *obj, void *event_info) {
  (void)obj; (void)event_info;
  Installer *ui = data;
  const char *disk = elm_entry_entry_get(ui->disk);
  const char *repo_url = elm_entry_entry_get(ui->repo_url);
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
  int layout_index = elm_radio_value_get(ui->storage_layout);
  const char *layout = layout_index == 2 ? "custom-percent" : (layout_index == 1 ? "user-work-programs" : "whole");
  int users_percent = (int)(elm_slider_value_get(ui->home_ratio) + 0.5);
  int work_percent = (int)(elm_slider_value_get(ui->work_ratio) + 0.5);
  int programs_percent = (int)(elm_slider_value_get(ui->programs_ratio) + 0.5);
  int data_percent_total = users_percent + work_percent + programs_percent;
  int theme_index = elm_radio_value_get(ui->theme_profile);
  int wallpaper_index = elm_radio_value_get(ui->wallpaper_profile);
  const char *theme_profile = theme_index == 2 ? "vm135-classic-dark" : (theme_index == 1 ? "vm135-retrowave" : "vm135-dark-scifi");
  const char *wallpaper_profile = wallpaper_index == 3 ? "solid-dark" : (wallpaper_index == 2 ? "amiga-retro" : (wallpaper_index == 1 ? "tron-fight-for-the-user" : "foggy-trees"));
  char packages[128] = "";
  char command[2048];

  if (!disk || strncmp(disk, "/dev/", 5) != 0 ||
      !repo_url || !repo_url[0] ||
      !hostname || !hostname[0] ||
      !username || !username[0]) {
    status_set(ui, "<color=#ffb86c>Choose a target, package repository, hostname, and primary username.</color>");
    return;
  }
  if (!password || strlen(password) < 8 || strcmp(password, password_confirm ? password_confirm : "") != 0) {
    status_set(ui, "<color=#ffb86c>Primary-account passwords must match and contain at least 8 characters.</color>");
    return;
  }
  if (layout_index != 0 && data_percent_total > 80) {
    status_set(ui, "<color=#ffb86c>Not enough points: /Home + /Work + /Programs must total 80 points or less.</color>");
    return;
  }
  if (strpbrk(disk, "'\";`$\\") || strpbrk(repo_url, "'\";`$\\") ||
      strpbrk(hostname, "'\";`$\\") ||
      strpbrk(username, "'\";`$\\") || strpbrk(locale, "'\";`$\\") ||
      strpbrk(timezone, "'\";`$\\") || strpbrk(keyboard, "'\";`$\\")) {
    status_set(ui, "<color=#ff6b6b>Unsafe characters are not accepted in installer values.</color>");
    return;
  }
  if (ui->runner) {
    status_set(ui, "<color=#ffb86c>An installer command is already running.</color>");
    return;
  }
  package_add(packages, sizeof(packages), ui->office, "group-office");
  package_add(packages, sizeof(packages), ui->dtp, "group-dtp");
  package_add(packages, sizeof(packages), ui->internet, "group-internet");
  package_add(packages, sizeof(packages), ui->music_media, "group-music-media");
  package_add(packages, sizeof(packages), ui->graphics, "group-graphics");
  package_add(packages, sizeof(packages), ui->dev_ide, "group-dev-ide");
  package_add(packages, sizeof(packages), ui->containers, "group-containers");
  package_add(packages, sizeof(packages), ui->retro, "group-retro");
  snprintf(command, sizeof(command),
           "/System/Tools/auzix-installer plan '%s' '%s' '%s' '%s' graphical '%s' '%s' '%s' '%d' '%s' '%s' '%s' '%s' '%d' '%d' '%s' '%s'",
           plan_path, disk, boot, hostname, username, root_policy, layout,
           users_percent, packages, locale, timezone, keyboard, work_percent, programs_percent, theme_profile, wallpaper_profile);
  snprintf(ui->pending_disk, sizeof(ui->pending_disk), "%s", disk);
  remove(plan_path);
  ui->validate_ticks = 0;
  progress_open(ui, "Validating install plan", "Writing and validating the plan JSON.\nNo disk changes are made by validation.", EINA_TRUE);
  ui->runner = ecore_exe_run(command, ui);
  if (!ui->runner) {
    progress_close(ui);
    ui->runner_kind = RUNNER_NONE;
    status_set(ui, "<color=#ff6b6b>Could not start plan validation.</color>");
  } else {
    ui->runner_kind = RUNNER_VALIDATE;
    if (ui->validate_timer) ecore_timer_del(ui->validate_timer);
    ui->validate_timer = ecore_timer_add(0.5, validate_poll_cb, ui);
  }
}

static void install_confirm_cb(void *data, Evas_Object *obj, void *event_info) {
  (void)obj; (void)event_info;
  Installer *ui = data;
  char command[1536];
  const char *repo_url = elm_entry_entry_get(ui->repo_url);
  int profile_index = elm_radio_value_get(ui->profile);
  const char *profile_path = profile_index == 0
    ? "/System/Settings/install/auzix-tiny-netinstall-remote.packages"
    : "/System/Settings/install/auzix-vmid135-clean-workstation.packages";
  progress_close(ui);
  progress_open(ui, "Installing AuziX", "Installing the selected profile from the AUZiX package repository.\nProgress streams to /System/Logs/installer/package-built-install.log.\nDo not power off this machine.", EINA_TRUE);
  snprintf(command, sizeof(command),
           "/System/Compatibility/bin/sudo -n sh -c \"echo $$ >'%s'; AUZIX_INSTALL_PLAN='%s' /System/Tools/auzix-install-disk --force --repo '%s' --profile '%s' '%s' >'%s' 2>&1\"",
           install_pid_path, plan_path, repo_url ? repo_url : "https://auzix-repo.test:8443", profile_path, ui->reviewed_disk, install_log_path);
  ui->runner = ecore_exe_run(command, ui);
  if (!ui->runner) {
    progress_close(ui);
    ui->runner_kind = RUNNER_NONE;
    status_set(ui, "<color=#ff6b6b>Could not start the guarded installer command.</color>");
  } else {
    ui->runner_kind = RUNNER_INSTALL;
    ui->install_ticks = 0;
    install_progress_update(ui, EINA_FALSE);
    if (ui->install_timer) ecore_timer_del(ui->install_timer);
    ui->install_timer = ecore_timer_add(1.0, install_poll_cb, ui);
  }
}

static void preflight_done_cb(void *data, int exit_code) {
  Installer *ui = data;
  progress_close(ui);
  if (exit_code == 0) {
    status_set(ui, "<color=#82d4bb>Preflight passed. Storage tooling, target visibility, and installer guard checks look ready.</color>");
  } else {
    status_set(ui, "<color=#ff6b6b>Preflight failed. Keep the live session open and review /System/Logs/installer/preflight.log.</color>");
  }
}

static Eina_Bool runner_event_cb(void *data, int type, void *event_info) {
  (void)type;
  Installer *ui = data;
  Ecore_Exe_Event_Del *event = event_info;
  if (!ui->runner || event->exe != ui->runner) return ECORE_CALLBACK_RENEW;
  int kind = ui->runner_kind;
  ui->runner = NULL;
  ui->runner_kind = RUNNER_NONE;
  if (kind == RUNNER_VALIDATE) {
    progress_close(ui);
    if (ui->validate_timer) {
      ecore_timer_del(ui->validate_timer);
      ui->validate_timer = NULL;
    }
    if (event->exit_code == 0) {
      validate_success(ui);
    } else {
      ui->plan_ready = EINA_FALSE;
      elm_object_disabled_set(ui->run_button, EINA_TRUE);
      status_set(ui, "<color=#ff6b6b>Plan validation failed. Review selected values and /System/Logs/installer.</color>");
    }
  } else if (kind == RUNNER_PREFLIGHT) {
    preflight_done_cb(ui, event->exit_code);
  } else if (kind == RUNNER_INSTALL) {
    if (ui->install_timer) {
      ecore_timer_del(ui->install_timer);
      ui->install_timer = NULL;
    }
    install_progress_update(ui, EINA_TRUE);
    if (event->exit_code == 0) {
      install_success_prompt(ui);
    } else {
      progress_close(ui);
      status_set(ui, "<color=#ff6b6b>Install failed or was interrupted. The live session remains available for recovery.</color>");
    }
  }
  return ECORE_CALLBACK_RENEW;
}

static void run_preflight_cb(void *data, Evas_Object *obj, void *event_info) {
  (void)obj; (void)event_info;
  Installer *ui = data;
  const char *disk = elm_entry_entry_get(ui->disk);
  const char *repo_url = elm_entry_entry_get(ui->repo_url);
  char command[1280];

  if (!disk || strncmp(disk, "/dev/", 5) != 0 || strpbrk(disk, "'\";`$\\")) {
    status_set(ui, "<color=#ffb86c>Select a valid /dev target before preflight.</color>");
    return;
  }
  if (ui->runner) {
    status_set(ui, "<color=#ffb86c>An installer/preflight command is already running.</color>");
    return;
  }

  progress_open(ui, "Running installer preflight", "Checking target disk visibility, ext4 tooling, repository path, and recovery surfaces.\nNo disk changes are made by this preflight.", EINA_TRUE);
  snprintf(command, sizeof(command),
           "/System/Compatibility/bin/sudo -n sh -c \"mkdir -p /System/Logs/installer && REPO_URL='%s' AUZIX_INSTALL_PLAN='%s' /System/Tools/auzix-existing-installer-preflight '%s' >/System/Logs/installer/preflight.log 2>&1 && /System/Tools/auzix-install-root-from-repo-profile --preflight --repo '%s' >>/System/Logs/installer/preflight.log 2>&1\"",
           repo_url ? repo_url : "https://auzix-repo.test:8443", plan_path, disk,
           repo_url ? repo_url : "https://auzix-repo.test:8443");
  ui->runner = ecore_exe_run(command, ui);
  if (!ui->runner) {
    progress_close(ui);
    ui->runner_kind = RUNNER_NONE;
    status_set(ui, "<color=#ff6b6b>Could not start installer preflight.</color>");
  } else {
    ui->runner_kind = RUNNER_PREFLIGHT;
  }
}

static void begin_install_cb(void *data, Evas_Object *obj, void *event_info) {
  (void)obj; (void)event_info;
  Installer *ui = data;
  if (!ui->plan_ready) {
    status_set(ui, "<color=#ffb86c>Validate a plan before requesting installation.</color>");
    return;
  }
  if (elm_radio_value_get(ui->storage_layout) == 2) {
    status_set(ui, "<color=#ffb86c>Custom split is recorded as install intent, but this installer slice executes Simple root or the default /Home /Work split.</color>");
    return;
  }
  char warning[1024];
  snprintf(warning, sizeof(warning),
           "ERASE %s and build an installed AUZiX root from the current package repository?\n\n"
           "The installer will partition, format, mount the target root, install the selected AUZiX package profile with dependency closure, write boot configuration and receipts, then sync and unmount the target.\n"
           "Default split creates real /Home and /Work partitions; /Programs remains package-owned inside the boot root until early-boot mount staging lands.",
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

static void storage_layout_changed_cb(void *data, Evas_Object *obj, void *event_info) {
  (void)obj;
  (void)event_info;
  Installer *ui = data;
  int layout_value = elm_radio_value_get(ui->storage_layout);
  Eina_Bool split_intent = layout_value != 0;
  elm_object_disabled_set(ui->home_ratio, !split_intent);
  elm_object_disabled_set(ui->work_ratio, !split_intent);
  elm_object_disabled_set(ui->programs_ratio, !split_intent);
  allocation_tally_update(ui);
  if (layout_value == 1) {
    status_set(ui, "<color=#62d9ef>STATUS // READY</color>  Default split creates /Home and /Work partitions; /Programs is recorded as package-space intent.");
  } else if (layout_value == 2) {
    status_set(ui, "<color=#ffb86c>Custom split is recorded as intent only in this installer slice.</color>");
  } else {
    status_set(ui, "<color=#62d9ef>STATUS // READY</color>  Default split install is executable after validation.");
  }
}

static Eina_Bool scroller_top_cb(void *data) {
  elm_scroller_region_show(data, 0, 0, 1, 1);
  return ECORE_CALLBACK_CANCEL;
}

EAPI_MAIN int elm_main(int argc, char **argv) {
  (void)argc; (void)argv;
  elm_policy_set(ELM_POLICY_QUIT, ELM_POLICY_QUIT_LAST_WINDOW_CLOSED);
  Installer ui = {0};
  ui.window = elm_win_util_standard_add("auzix-installer", "Install AuziX");
  elm_win_autodel_set(ui.window, EINA_TRUE);
  elm_win_title_set(ui.window, "BlackKnight // AuziX Deployment");
  evas_object_resize(ui.window, 1120, 760);

  if (access(vm135_theme_path, R_OK) == 0) {
    elm_theme_overlay_add(NULL, vm135_theme_path);
  } else if (access(fallback_theme_path, R_OK) == 0) {
    elm_theme_overlay_add(NULL, fallback_theme_path);
  }

  Evas_Object *bg = elm_bg_add(ui.window);
  elm_bg_color_set(bg, 7, 17, 31);
  evas_object_size_hint_weight_set(bg, EVAS_HINT_EXPAND, EVAS_HINT_EXPAND);
  elm_win_resize_object_add(ui.window, bg);
  evas_object_show(bg);

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

  if (access(brand_mark_path, R_OK) == 0) {
    Evas_Object *brand = elm_image_add(box);
    elm_image_file_set(brand, brand_mark_path, NULL);
    elm_image_resizable_set(brand, EINA_TRUE, EINA_TRUE);
    elm_image_aspect_fixed_set(brand, EINA_TRUE);
    evas_object_size_hint_min_set(brand, 48, 48);
    evas_object_size_hint_max_set(brand, 72, 72);
    evas_object_size_hint_align_set(brand, 0.5, 0.5);
    elm_box_pack_end(box, brand);
    evas_object_show(brand);
  }

  Evas_Object *intro = elm_label_add(box);
  elm_object_text_set(intro,
    "Build your AUZiX machine. Base first, extras after. VM135 dark sci-fi is the default desktop seed.");
  elm_label_line_wrap_set(intro, ELM_WRAP_WORD);
  evas_object_size_hint_weight_set(intro, EVAS_HINT_EXPAND, 0.0);
  evas_object_size_hint_align_set(intro, EVAS_HINT_FILL, 0.5);
  elm_box_pack_end(box, intro); evas_object_show(intro);

  Evas_Object *frame = elm_frame_add(box);
  elm_object_text_set(frame, "01 // TARGET, STORAGE, AND PACKAGE INTENT");
  evas_object_size_hint_weight_set(frame, EVAS_HINT_EXPAND, EVAS_HINT_EXPAND);
  evas_object_size_hint_align_set(frame, EVAS_HINT_FILL, EVAS_HINT_FILL);
  evas_object_size_hint_min_set(frame, 1040, 520);
  elm_box_pack_end(box, frame); evas_object_show(frame);

  Evas_Object *scroller = elm_scroller_add(frame);
  elm_scroller_policy_set(scroller, ELM_SCROLLER_POLICY_OFF, ELM_SCROLLER_POLICY_AUTO);
  elm_scroller_content_min_limit(scroller, EINA_TRUE, EINA_FALSE);
  evas_object_size_hint_weight_set(scroller, EVAS_HINT_EXPAND, EVAS_HINT_EXPAND);
  evas_object_size_hint_align_set(scroller, EVAS_HINT_FILL, EVAS_HINT_FILL);
  elm_object_content_set(frame, scroller); evas_object_show(scroller);

  Evas_Object *table = elm_table_add(scroller);
  elm_table_padding_set(table, 16, 14);
  evas_object_size_hint_weight_set(table, EVAS_HINT_EXPAND, EVAS_HINT_EXPAND);
  evas_object_size_hint_align_set(table, EVAS_HINT_FILL, EVAS_HINT_FILL);
  evas_object_size_hint_min_set(table, 1040, 560);
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
  elm_entry_entry_set(ui.password, "changeme123");
  evas_object_size_hint_weight_set(ui.password, EVAS_HINT_EXPAND, 0.0);
  evas_object_size_hint_align_set(ui.password, EVAS_HINT_FILL, 0.5);
  evas_object_size_hint_min_set(ui.password, 420, 48);
  elm_object_content_set(password_frame, ui.password); evas_object_show(ui.password);
  evas_object_size_hint_weight_set(password_frame, EVAS_HINT_EXPAND, 0.0);
  evas_object_size_hint_align_set(password_frame, EVAS_HINT_FILL, 0.5);
  evas_object_size_hint_min_set(password_frame, 420, 72);
  elm_table_pack(table, password_frame, 1, 3, 1, 1); evas_object_show(password_frame);

  Evas_Object *confirm_label = form_label(table, "Confirm password");
  elm_table_pack(table, confirm_label, 0, 4, 1, 1);
  Evas_Object *confirm_frame = elm_frame_add(table); elm_object_text_set(confirm_frame, "Repeat account password");
  ui.password_confirm = elm_entry_add(confirm_frame); elm_entry_single_line_set(ui.password_confirm, EINA_TRUE); elm_entry_password_set(ui.password_confirm, EINA_TRUE);
  elm_entry_entry_set(ui.password_confirm, "changeme123");
  evas_object_size_hint_weight_set(ui.password_confirm, EVAS_HINT_EXPAND, 0.0);
  evas_object_size_hint_align_set(ui.password_confirm, EVAS_HINT_FILL, 0.5);
  evas_object_size_hint_min_set(ui.password_confirm, 420, 48);
  elm_object_content_set(confirm_frame, ui.password_confirm); evas_object_show(ui.password_confirm);
  evas_object_size_hint_weight_set(confirm_frame, EVAS_HINT_EXPAND, 0.0);
  evas_object_size_hint_align_set(confirm_frame, EVAS_HINT_FILL, 0.5);
  evas_object_size_hint_min_set(confirm_frame, 420, 72);
  elm_table_pack(table, confirm_frame, 1, 4, 1, 1); evas_object_show(confirm_frame);

  Evas_Object *root_label = form_label(table, "Root login"); elm_table_pack(table, root_label, 0, 5, 1, 1);
  Evas_Object *root_box = elm_box_add(table); elm_box_horizontal_set(root_box, EINA_TRUE); elm_box_padding_set(root_box, 18, 0);
  Evas_Object *root_off = elm_radio_add(root_box); elm_object_text_set(root_off, "Disabled (sudo)"); elm_radio_state_value_set(root_off, 0);
  Evas_Object *root_same = elm_radio_add(root_box); elm_object_text_set(root_same, "Use account password"); elm_radio_state_value_set(root_same, 1); elm_radio_group_add(root_same, root_off);
  ui.root_policy = root_off; elm_box_pack_end(root_box, root_off); elm_box_pack_end(root_box, root_same);
  elm_radio_value_set(root_off, 1);
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
  Evas_Object *whole = elm_radio_add(layout_box); elm_object_text_set(whole, "Simple root"); elm_radio_state_value_set(whole, 0);
  Evas_Object *user_shape = elm_radio_add(layout_box); elm_object_text_set(user_shape, "/Home /Work split + /Programs package intent"); elm_radio_state_value_set(user_shape, 1); elm_radio_group_add(user_shape, whole);
  Evas_Object *custom_shape = elm_radio_add(layout_box); elm_object_text_set(custom_shape, "Custom split — record intent"); elm_radio_state_value_set(custom_shape, 2); elm_radio_group_add(custom_shape, whole);
  ui.storage_layout = whole; elm_box_pack_end(layout_box, whole); elm_box_pack_end(layout_box, user_shape); elm_box_pack_end(layout_box, custom_shape);
  elm_radio_value_set(whole, 1);
  evas_object_smart_callback_add(whole, "changed", storage_layout_changed_cb, &ui);
  evas_object_smart_callback_add(user_shape, "changed", storage_layout_changed_cb, &ui);
  evas_object_smart_callback_add(custom_shape, "changed", storage_layout_changed_cb, &ui);
  elm_table_pack(table, layout_box, 1, 7, 1, 1); evas_object_show(whole); evas_object_show(user_shape); evas_object_show(custom_shape); evas_object_show(layout_box);

  Evas_Object *ratio_label = form_label(table, "User-space allocation"); elm_table_pack(table, ratio_label, 0, 8, 1, 1);
  Evas_Object *ratio_box = elm_box_add(table);
  elm_box_padding_set(ratio_box, 4, 4);
  evas_object_size_hint_weight_set(ratio_box, EVAS_HINT_EXPAND, 0.0);
  evas_object_size_hint_align_set(ratio_box, EVAS_HINT_FILL, 0.5);
  ui.home_ratio = elm_slider_add(ratio_box); elm_slider_min_max_set(ui.home_ratio, 0, 80); elm_slider_value_set(ui.home_ratio, 20);
  elm_slider_unit_format_set(ui.home_ratio, "%1.0f pts /Home"); elm_box_pack_end(ratio_box, ui.home_ratio); evas_object_show(ui.home_ratio);
  ui.work_ratio = elm_slider_add(ratio_box); elm_slider_min_max_set(ui.work_ratio, 0, 80); elm_slider_value_set(ui.work_ratio, 20);
  elm_slider_unit_format_set(ui.work_ratio, "%1.0f pts /Work"); elm_box_pack_end(ratio_box, ui.work_ratio); evas_object_show(ui.work_ratio);
  ui.programs_ratio = elm_slider_add(ratio_box); elm_slider_min_max_set(ui.programs_ratio, 0, 80); elm_slider_value_set(ui.programs_ratio, 40);
  elm_slider_unit_format_set(ui.programs_ratio, "%1.0f pts /Programs"); elm_box_pack_end(ratio_box, ui.programs_ratio); evas_object_show(ui.programs_ratio);
  evas_object_smart_callback_add(ui.home_ratio, "changed", allocation_slider_changed_cb, &ui);
  evas_object_smart_callback_add(ui.work_ratio, "changed", allocation_slider_changed_cb, &ui);
  evas_object_smart_callback_add(ui.programs_ratio, "changed", allocation_slider_changed_cb, &ui);
  ui.allocation_tally = elm_label_add(ratio_box);
  elm_label_line_wrap_set(ui.allocation_tally, ELM_WRAP_WORD);
  evas_object_size_hint_weight_set(ui.allocation_tally, EVAS_HINT_EXPAND, 0.0);
  evas_object_size_hint_align_set(ui.allocation_tally, EVAS_HINT_FILL, 0.5);
  elm_box_pack_end(ratio_box, ui.allocation_tally); evas_object_show(ui.allocation_tally);
  allocation_tally_update(&ui);
  elm_object_disabled_set(ui.home_ratio, EINA_FALSE);
  elm_object_disabled_set(ui.work_ratio, EINA_FALSE);
  elm_object_disabled_set(ui.programs_ratio, EINA_FALSE);
  elm_table_pack(table, ratio_box, 1, 8, 1, 1); evas_object_show(ratio_box);

  Evas_Object *packages_label = form_label(table, "Package profile"); elm_table_pack(table, packages_label, 0, 9, 1, 1);
  Evas_Object *package_outer = elm_box_add(table);
  elm_box_padding_set(package_outer, 8, 8);
  evas_object_size_hint_weight_set(package_outer, EVAS_HINT_EXPAND, 0.0);
  evas_object_size_hint_align_set(package_outer, EVAS_HINT_FILL, 0.5);

  ui.repo_url = elm_entry_add(package_outer);
  elm_entry_single_line_set(ui.repo_url, EINA_TRUE);
  elm_object_part_text_set(ui.repo_url, "guide", "Package repository URL");
  elm_entry_entry_set(ui.repo_url, "https://auzix-repo.test:8443");
  evas_object_size_hint_weight_set(ui.repo_url, EVAS_HINT_EXPAND, 0.0);
  evas_object_size_hint_align_set(ui.repo_url, EVAS_HINT_FILL, 0.5);
  evas_object_size_hint_min_set(ui.repo_url, 620, 42);
  elm_box_pack_end(package_outer, ui.repo_url); evas_object_show(ui.repo_url);

  Evas_Object *profile_box = elm_box_add(package_outer);
  elm_box_horizontal_set(profile_box, EINA_TRUE);
  elm_box_padding_set(profile_box, 18, 0);
  Evas_Object *tiny_profile = elm_radio_add(profile_box);
  elm_object_text_set(tiny_profile, "Tiny remote shell");
  elm_radio_state_value_set(tiny_profile, 0);
  Evas_Object *workstation_profile = elm_radio_add(profile_box);
  elm_object_text_set(workstation_profile, "VM135 workstation");
  elm_radio_state_value_set(workstation_profile, 1);
  elm_radio_group_add(workstation_profile, tiny_profile);
  ui.profile = tiny_profile;
  elm_radio_value_set(tiny_profile, 1);
  elm_box_pack_end(profile_box, tiny_profile);
  elm_box_pack_end(profile_box, workstation_profile);
  elm_box_pack_end(package_outer, profile_box);
  evas_object_show(tiny_profile); evas_object_show(workstation_profile); evas_object_show(profile_box);

  Evas_Object *package_box = elm_box_add(package_outer); elm_box_horizontal_set(package_box, EINA_TRUE); elm_box_padding_set(package_box, 18, 0);
  evas_object_size_hint_weight_set(package_box, EVAS_HINT_EXPAND, 0.0);
  evas_object_size_hint_align_set(package_box, EVAS_HINT_FILL, 0.5);
  Evas_Object *package_col1 = elm_box_add(package_box); elm_box_padding_set(package_col1, 4, 4);
  Evas_Object *package_col2 = elm_box_add(package_box); elm_box_padding_set(package_col2, 4, 4);
  evas_object_size_hint_weight_set(package_col1, EVAS_HINT_EXPAND, 0.0);
  evas_object_size_hint_align_set(package_col1, EVAS_HINT_FILL, 0.5);
  evas_object_size_hint_weight_set(package_col2, EVAS_HINT_EXPAND, 0.0);
  evas_object_size_hint_align_set(package_col2, EVAS_HINT_FILL, 0.5);
#define ADD_PACKAGE_CHECK(field, label, selected) do { \
  ui.field = elm_check_add(package_col1); elm_object_text_set(ui.field, label); \
  elm_check_state_set(ui.field, selected); elm_box_pack_end(package_col1, ui.field); evas_object_show(ui.field); \
} while (0)
#define ADD_PACKAGE_CHECK2(field, label, selected) do { \
  ui.field = elm_check_add(package_col2); elm_object_text_set(ui.field, label); \
  elm_check_state_set(ui.field, selected); elm_box_pack_end(package_col2, ui.field); evas_object_show(ui.field); \
} while (0)
  ADD_PACKAGE_CHECK(office, "Office — Writer, Calc, notes", EINA_TRUE);
  ADD_PACKAGE_CHECK(dtp, "DTP / Publishing — layout, PDF, print", EINA_TRUE);
  ADD_PACKAGE_CHECK(internet, "Internet — browser, chat, mail", EINA_TRUE);
  ADD_PACKAGE_CHECK(music_media, "Music + Media — players, codecs", EINA_FALSE);
  ADD_PACKAGE_CHECK2(graphics, "Graphics — photo, paint, vector", EINA_TRUE);
  ADD_PACKAGE_CHECK2(dev_ide, "Dev / IDE — editors, Git, build tools", EINA_TRUE);
  ADD_PACKAGE_CHECK2(containers, "Containers — Podman, demo services", EINA_TRUE);
  ADD_PACKAGE_CHECK2(retro, "Retro / Amiga — emu-ready extras", EINA_TRUE);
#undef ADD_PACKAGE_CHECK
  elm_box_pack_end(package_box, package_col1); evas_object_show(package_col1);
  elm_box_pack_end(package_box, package_col2); evas_object_show(package_col2);
#undef ADD_PACKAGE_CHECK2
  elm_box_pack_end(package_outer, package_box); evas_object_show(package_box);
  elm_table_pack(table, package_outer, 1, 9, 1, 1); evas_object_show(package_outer);

  Evas_Object *look_label = form_label(table, "Desktop look"); elm_table_pack(table, look_label, 0, 10, 1, 1);
  Evas_Object *look_box = elm_box_add(table);
  elm_box_padding_set(look_box, 8, 8);
  evas_object_size_hint_weight_set(look_box, EVAS_HINT_EXPAND, 0.0);
  evas_object_size_hint_align_set(look_box, EVAS_HINT_FILL, 0.5);
  Evas_Object *theme_row = elm_box_add(look_box); elm_box_horizontal_set(theme_row, EINA_TRUE); elm_box_padding_set(theme_row, 12, 0);
  Evas_Object *theme_dark = elm_radio_add(theme_row); elm_object_text_set(theme_dark, "VM135 dark sci-fi"); elm_radio_state_value_set(theme_dark, 0);
  Evas_Object *theme_retro = elm_radio_add(theme_row); elm_object_text_set(theme_retro, "Retrowave"); elm_radio_state_value_set(theme_retro, 1); elm_radio_group_add(theme_retro, theme_dark);
  Evas_Object *theme_classic = elm_radio_add(theme_row); elm_object_text_set(theme_classic, "Classic dark"); elm_radio_state_value_set(theme_classic, 2); elm_radio_group_add(theme_classic, theme_dark);
  ui.theme_profile = theme_dark; elm_radio_value_set(theme_dark, 1);
  elm_box_pack_end(theme_row, theme_dark); elm_box_pack_end(theme_row, theme_retro); elm_box_pack_end(theme_row, theme_classic);
  elm_box_pack_end(look_box, theme_row);
  evas_object_show(theme_dark); evas_object_show(theme_retro); evas_object_show(theme_classic); evas_object_show(theme_row);
  Evas_Object *wall_row = elm_box_add(look_box); elm_box_horizontal_set(wall_row, EINA_TRUE); elm_box_padding_set(wall_row, 12, 0);
  Evas_Object *wall_blade = elm_radio_add(wall_row); elm_object_text_set(wall_blade, "Foggy Trees"); elm_radio_state_value_set(wall_blade, 0);
  Evas_Object *wall_tron = elm_radio_add(wall_row); elm_object_text_set(wall_tron, "Tron"); elm_radio_state_value_set(wall_tron, 1); elm_radio_group_add(wall_tron, wall_blade);
  Evas_Object *wall_amiga = elm_radio_add(wall_row); elm_object_text_set(wall_amiga, "Amiga retro"); elm_radio_state_value_set(wall_amiga, 2); elm_radio_group_add(wall_amiga, wall_blade);
  Evas_Object *wall_solid = elm_radio_add(wall_row); elm_object_text_set(wall_solid, "Solid dark"); elm_radio_state_value_set(wall_solid, 3); elm_radio_group_add(wall_solid, wall_blade);
  ui.wallpaper_profile = wall_blade; elm_radio_value_set(wall_blade, 2);
  elm_box_pack_end(wall_row, wall_blade); elm_box_pack_end(wall_row, wall_tron); elm_box_pack_end(wall_row, wall_amiga); elm_box_pack_end(wall_row, wall_solid);
  elm_box_pack_end(look_box, wall_row);
  evas_object_show(wall_blade); evas_object_show(wall_tron); evas_object_show(wall_amiga); evas_object_show(wall_solid); evas_object_show(wall_row);
  elm_table_pack(table, look_box, 1, 10, 1, 1); evas_object_show(look_box);

  Evas_Object *region_label = form_label(table, "Region defaults"); elm_table_pack(table, region_label, 0, 11, 1, 1);
  Evas_Object *region = elm_box_add(table); elm_box_horizontal_set(region, EINA_TRUE);
  ui.locale = elm_entry_add(region); elm_entry_single_line_set(ui.locale, EINA_TRUE); elm_entry_entry_set(ui.locale, "en_US.UTF-8"); elm_box_pack_end(region, ui.locale); evas_object_show(ui.locale);
  ui.timezone = elm_entry_add(region); elm_entry_single_line_set(ui.timezone, EINA_TRUE); elm_entry_entry_set(ui.timezone, "America/Los_Angeles"); elm_box_pack_end(region, ui.timezone); evas_object_show(ui.timezone);
  ui.keyboard = elm_entry_add(region); elm_entry_single_line_set(ui.keyboard, EINA_TRUE); elm_entry_entry_set(ui.keyboard, "us"); elm_box_pack_end(region, ui.keyboard); evas_object_show(ui.keyboard);
  elm_table_pack(table, region, 1, 11, 1, 1); evas_object_show(region);

  Evas_Object *safety = elm_label_add(table);
  elm_object_text_set(safety,
    "<color=#ffb86c><b>Safety:</b> validating saves a plan only. Package choices are intent, not proof of install. Disk changes require a second explicit confirmation.</color>");
  elm_label_line_wrap_set(safety, ELM_WRAP_WORD);
  evas_object_size_hint_weight_set(safety, EVAS_HINT_EXPAND, 0.0);
  evas_object_size_hint_align_set(safety, EVAS_HINT_FILL, 0.5);
  elm_table_pack(table, safety, 0, 12, 2, 1); evas_object_show(safety);

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

  Evas_Object *preflight = elm_button_add(actions);
  elm_object_text_set(preflight, "RUN PREFLIGHT");
  evas_object_smart_callback_add(preflight, "clicked", run_preflight_cb, &ui);
  evas_object_size_hint_weight_set(preflight, EVAS_HINT_EXPAND, 0.0);
  evas_object_size_hint_align_set(preflight, EVAS_HINT_FILL, 0.5);
  elm_box_pack_end(actions, preflight); evas_object_show(preflight);

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
  ecore_idler_add(scroller_top_cb, scroller);
  ui.runner_handler = ecore_event_handler_add(ECORE_EXE_EVENT_DEL, runner_event_cb, &ui);
  ui.preflight_handler = NULL;
  elm_run();
  if (ui.runner_handler) ecore_event_handler_del(ui.runner_handler);
  if (ui.preflight_handler) ecore_event_handler_del(ui.preflight_handler);
  elm_shutdown();
  return 0;
}
ELM_MAIN()
