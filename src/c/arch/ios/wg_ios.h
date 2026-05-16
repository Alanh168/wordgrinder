#ifndef WG_IOS_H
#define WG_IOS_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Public C-bridged structures for Swift. Keep layout-compatible with
   wg_ios_internal.h's WgIOSCell. */
typedef struct {
    int32_t  codepoint;
    uint16_t fg_index;
    uint16_t bg_index;
    uint16_t attrs;     /* DPY_ITALIC | DPY_UNDERLINE | DPY_REVERSE | DPY_BOLD | DPY_BRIGHT | DPY_DIM */
    uint16_t reserved;
} WgCell;

/* DPY attribute bits (mirrors globals.h enum) */
enum {
    WG_ATTR_ITALIC    = 1 << 0,
    WG_ATTR_UNDERLINE = 1 << 1,
    WG_ATTR_REVERSE   = 1 << 2,
    WG_ATTR_BOLD      = 1 << 3,
    WG_ATTR_BRIGHT    = 1 << 4,
    WG_ATTR_DIM       = 1 << 5,
};

/* -------- Diagnostics (Phase 0–2A) -------- */
const char* wg_ios_hello(void);
const char* wg_ios_lua_eval(const char* expression);
const char* wg_ios_boot_test(void);

/* -------- Phase 2C: run wordgrinder + read its display -------- */

/* Sets wordgrinder's $HOME *before* wg_ios_start() boots it. Wordgrinder's
   Lua code then reads HOME via os.getenv to derive CONFIGDIR, so this
   controls where projects, settings, and the .wordgrinder config directory
   live. Typical use: Swift resolves the iCloud container's Documents URL
   and passes its path here; on iCloud unavailability, the app falls back
   to the local sandbox Documents folder. Must be called before
   wg_ios_start(); ignored after boot. */
void wg_ios_set_home(const char* path);

/* Boots wordgrinder if needed, then starts its main event loop on a
   detached background thread. Safe to call multiple times — only acts once.
   Wordgrinder will block in dpy_getchar() until Phase 2D wires real input. */
void wg_ios_start(void);

/* Current screen dimensions wordgrinder is drawing into. */
void wg_ios_get_screen_size(int* cols, int* rows);

/* Monotonic counter incremented on every dpy_sync(). Use to skip
   snapshot/render when the frame hasn't changed. */
uint32_t wg_ios_get_frame_counter(void);

/* Copy the current displayed cells into `out` (under the dpy mutex).
   `max_cells` is the capacity of `out`; the implementation will not
   write more than that. */
void wg_ios_snapshot_cells(WgCell* out, int max_cells);

/* Cursor position + visibility. */
void wg_ios_get_cursor(int* col, int* row, int* visible);

/* -------- Phase 2D: keyboard input -------- */

/* Push a single key into wordgrinder's input queue. Encoding (matches the
   curses backend so the same Lua key bindings work):
     - positive value  = printable Unicode codepoint (e.g. 'a' = 97)
     - negative value  = special key, ncurses constant negated:
         -27   = ESC       -13  = Enter      -8/-263 = Backspace
         -258  = Down      -259 = Up         -260 = Left   -261 = Right
         -262  = Home      -360 = End        -338 = PgDn   -339 = PgUp
         -330  = Delete    -331 = Insert
         -1..-26 = Ctrl+A..Ctrl+Z
   Safe to call from any thread; wakes the wordgrinder pthread blocked in
   dpy_getchar(). */
void wg_ios_push_key(int32_t key);

#ifdef __cplusplus
}
#endif

#endif
