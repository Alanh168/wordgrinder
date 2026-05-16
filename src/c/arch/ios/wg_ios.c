#include "wg_ios.h"
#include "wg_ios_internal.h"
#include "globals.h"
#include "lua-bitop.h"
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <locale.h>
#include <pthread.h>
#include <sys/stat.h>
#include <unistd.h>

extern int luaopen_bit(lua_State *L);
extern int luaopen_lpeg(lua_State *L);

const char* wg_ios_hello(void)
{
    return "wordgrinder linked OK";
}

static char eval_buf[512];

const char* wg_ios_lua_eval(const char* expression)
{
    lua_State* L_local = luaL_newstate();
    if (!L_local) return "lua: luaL_newstate failed";
    luaL_openlibs(L_local);

    char wrapped[1024];
    snprintf(wrapped, sizeof(wrapped), "return tostring((%s))", expression);

    if (luaL_dostring(L_local, wrapped) != 0) {
        const char* err = lua_tostring(L_local, -1);
        snprintf(eval_buf, sizeof(eval_buf), "lua error: %s", err ? err : "(no message)");
        lua_close(L_local);
        return eval_buf;
    }
    const char* result = lua_tostring(L_local, -1);
    snprintf(eval_buf, sizeof(eval_buf), "%s", result ? result : "(nil)");
    lua_close(L_local);
    return eval_buf;
}

static char boot_buf[512];
static int boot_completed = 0;

/* Explicit HOME provided by Swift (e.g. the iCloud container's Documents
   URL). When non-NULL, used in place of the fallback redirect. */
static char explicit_home[1024];
static int  explicit_home_set = 0;

void wg_ios_set_home(const char* path)
{
    if (!path || !*path) return;
    snprintf(explicit_home, sizeof(explicit_home), "%s", path);
    explicit_home_set = 1;
}

/* iOS apps cannot write to the container-root HOME, only to its Documents/,
   Library/, and tmp/ subdirectories. If Swift didn't set an explicit HOME,
   fall back to the local sandbox's Documents folder. */
static void resolve_home(void)
{
    if (explicit_home_set) {
        mkdir(explicit_home, 0755);
        setenv("HOME", explicit_home, 1);
        chdir(explicit_home);
        return;
    }
    const char* base = getenv("HOME");
    if (!base) return;
    static char wg_home[1024];
    snprintf(wg_home, sizeof(wg_home), "%s/Documents", base);
    mkdir(wg_home, 0755);
    setenv("HOME", wg_home, 1);
    chdir(wg_home);
}

static void do_boot(void)
{
    if (boot_completed) return;

    static const char* fake_argv[] = { "wordgrinder", NULL };

    resolve_home();

    static const char* locales[] = { "C.UTF-8", "en_US.UTF-8", "en_GB.UTF-8", "", NULL };
    const char** p = locales;
    while (*p && !setlocale(LC_ALL, *p)) p++;

    script_init();
    screen_init(fake_argv);
    word_init();
    utils_init();
    filesystem_init();
    zip_init();

    luaopen_bit(L);
    luaopen_lpeg(L);

    script_load_from_table(script_table);
    boot_completed = 1;
}

const char* wg_ios_boot_test(void)
{
    if (boot_completed) {
        snprintf(boot_buf, sizeof(boot_buf), "already booted");
        return boot_buf;
    }
    do_boot();
    int script_count = 0;
    const FileDescriptor* fd = script_table;
    while (fd->data) { script_count++; fd++; }
    snprintf(boot_buf, sizeof(boot_buf),
             "wordgrinder boot OK | %s | %d scripts loaded",
             LUA_VERSION, script_count);
    return boot_buf;
}

/* -------- Phase 2C: background thread + snapshot bridge -------- */

static pthread_t wg_main_thread;
static int wg_started = 0;

static void* wg_thread_main(void* arg)
{
    (void)arg;
    static const char* fake_argv[] = { "wordgrinder", NULL };
    script_run(fake_argv);
    return NULL;
}

void wg_ios_start(void)
{
    if (wg_started) return;
    wg_started = 1;
    do_boot();
    pthread_create(&wg_main_thread, NULL, wg_thread_main, NULL);
    pthread_detach(wg_main_thread);
}

void wg_ios_get_screen_size(int* cols_out, int* rows_out)
{
    *cols_out = wg_ios_dpy_cols();
    *rows_out = wg_ios_dpy_rows();
}

uint32_t wg_ios_get_frame_counter(void)
{
    return wg_ios_dpy_frame_counter();
}

void wg_ios_snapshot_cells(WgCell* out, int max_cells)
{
    /* WgCell and WgIOSCell share layout — safe reinterpret. */
    wg_ios_dpy_snapshot((WgIOSCell*)out, max_cells);
}

void wg_ios_get_cursor(int* col, int* row, int* visible)
{
    *col     = wg_ios_dpy_cursor_col();
    *row     = wg_ios_dpy_cursor_row();
    *visible = wg_ios_dpy_cursor_visible();
}
