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

/* -------- Phase 4: sprite overlay queue (OSC 99) ---------------------- */
/* Wordgrinder emits sprite commands via OSC 99 escape sequences on the
   desktop (redraw.lua:146 emitSpriteCommand -> io.write("\\27]99;…\\7")).
   On iPad there is no PTY for cool-retro-term to parse, so we intercept
   io.write at the Lua boundary, strip the OSC framing, and push the inner
   payload onto a mutex-protected ring buffer. Swift drains the queue each
   frame via wg_ios_pop_sprite_command(). Wordgrinder's emitter stays
   unchanged — it still emits real OSC 99 — so the desktop pipeline is
   completely unaffected by these additions. */

#define WG_SPRITE_QUEUE_SLOTS  32
#define WG_SPRITE_PAYLOAD_MAX  8192

typedef struct {
    char payload[WG_SPRITE_PAYLOAD_MAX];
} wg_sprite_slot_t;

static wg_sprite_slot_t wg_sprite_queue[WG_SPRITE_QUEUE_SLOTS];
static int wg_sprite_queue_head = 0;
static int wg_sprite_queue_tail = 0;
static pthread_mutex_t wg_sprite_queue_mutex = PTHREAD_MUTEX_INITIALIZER;

static void wg_sprite_queue_push(const char* payload)
{
    if (!payload) return;
    pthread_mutex_lock(&wg_sprite_queue_mutex);
    int next_tail = (wg_sprite_queue_tail + 1) % WG_SPRITE_QUEUE_SLOTS;
    if (next_tail == wg_sprite_queue_head) {
        /* Queue full — drop oldest. Latest frame supersedes anyway. */
        wg_sprite_queue_head = (wg_sprite_queue_head + 1) % WG_SPRITE_QUEUE_SLOTS;
    }
    strncpy(wg_sprite_queue[wg_sprite_queue_tail].payload,
            payload,
            WG_SPRITE_PAYLOAD_MAX - 1);
    wg_sprite_queue[wg_sprite_queue_tail].payload[WG_SPRITE_PAYLOAD_MAX - 1] = '\0';
    wg_sprite_queue_tail = next_tail;
    pthread_mutex_unlock(&wg_sprite_queue_mutex);
}

int wg_ios_pop_sprite_command(char* out, int out_size)
{
    if (!out || out_size <= 0) return 0;
    pthread_mutex_lock(&wg_sprite_queue_mutex);
    if (wg_sprite_queue_head == wg_sprite_queue_tail) {
        pthread_mutex_unlock(&wg_sprite_queue_mutex);
        out[0] = '\0';
        return 0;
    }
    strncpy(out, wg_sprite_queue[wg_sprite_queue_head].payload, out_size - 1);
    out[out_size - 1] = '\0';
    wg_sprite_queue_head = (wg_sprite_queue_head + 1) % WG_SPRITE_QUEUE_SLOTS;
    pthread_mutex_unlock(&wg_sprite_queue_mutex);
    return 1;
}

/* Lua-callable: takes the OSC 99 payload (the part between `\27]99;` and
   `\7`) and pushes it onto the queue. Registered as `__wg_ios_emit_sprite`
   in the Lua global table during boot. */
static int wg_lua_emit_sprite(lua_State* lua_state)
{
    const char* payload = luaL_checkstring(lua_state, 1);
    wg_sprite_queue_push(payload);
    return 0;
}

/* Installs the io.write wrapper that intercepts OSC 99 sequences. Non-OSC
   writes fall through to the original io.write untouched, so Lua code that
   uses io.write for unrelated purposes is unaffected. Wordgrinder's
   emitSpriteCommand (redraw.lua:146) continues to emit real OSC sequences,
   which keeps it identical to the desktop build. Runs once after scripts
   are loaded inside do_boot(). */
static void wg_install_sprite_bridge(void)
{
    lua_pushcfunction(L, wg_lua_emit_sprite);
    lua_setglobal(L, "__wg_ios_emit_sprite");

    static const char* override_src =
        "local original = io.write\n"
        "io.write = function(...)\n"
        "    local n = select('#', ...)\n"
        "    local s = ''\n"
        "    for i = 1, n do s = s .. tostring(select(i, ...)) end\n"
        "    local payload = s:match('^\\27%]99;(.-)\\7$')\n"
        "    if payload then\n"
        "        __wg_ios_emit_sprite(payload)\n"
        "        return io.stdout\n"
        "    end\n"
        "    return original(...)\n"
        "end\n";

    if (luaL_dostring(L, override_src) != 0) {
        const char* err = lua_tostring(L, -1);
        fprintf(stderr, "wg_ios: failed to install sprite bridge: %s\n",
                err ? err : "(no message)");
        lua_pop(L, 1);
    }
}

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

    /* Install the OSC 99 io.write wrapper after scripts are loaded so it
       overrides the freshly-resolved io.write that wordgrinder's emitter
       (redraw.lua) will call at runtime. */
    wg_install_sprite_bridge();

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
