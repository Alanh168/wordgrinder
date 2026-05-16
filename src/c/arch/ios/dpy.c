/* iOS display backend.
 *
 * Phase 2C: real cell buffer (double-buffered, mutex-swapped on dpy_sync).
 * Phase 2D: real input queue. wg_ios_push_key() (called from Swift on the
 *   main thread) appends to a ring buffer; dpy_getchar() (called from the
 *   wordgrinder pthread) pops with timeout via pthread_cond_timedwait.
 *
 * Encoding follows the same convention as the curses backend:
 *   - positive  = printable Unicode codepoint
 *   - negative  = special key, ncurses KEY_* constant negated
 *   - -KEY_TIMEOUT (-512) returned when the timeout expires
 * Swift is expected to push values already in this encoding.
 */

#include "globals.h"
#include <pthread.h>
#include <string.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <errno.h>

#include "wg_ios_internal.h"

#define WG_IOS_COLS 80
#define WG_IOS_ROWS 24
#define WG_IOS_CELL_COUNT (WG_IOS_COLS * WG_IOS_ROWS)

static int cols = WG_IOS_COLS;
static int rows = WG_IOS_ROWS;
static WgIOSCell front_buf[WG_IOS_CELL_COUNT];
static WgIOSCell back_buf[WG_IOS_CELL_COUNT];
static pthread_mutex_t swap_lock = PTHREAD_MUTEX_INITIALIZER;
static volatile uint32_t frame_counter = 0;

static uint16_t cur_fg = 2;
static uint16_t cur_bg = 0;
static uint16_t cur_attrs = 0;
static int cursor_col = 0, cursor_row = 0;
static int cursor_visible = 1;

/* ---- ncurses-compatible key constants (so dpy_getkeyname matches the curses port) ---- */
#define WG_KEY_DOWN       258
#define WG_KEY_UP         259
#define WG_KEY_LEFT       260
#define WG_KEY_RIGHT      261
#define WG_KEY_HOME       262
#define WG_KEY_BACKSPACE  263
#define WG_KEY_F0         264   /* KEY_F(n) = WG_KEY_F0 + n */
#define WG_KEY_DC         330   /* delete forward */
#define WG_KEY_IC         331   /* insert */
#define WG_KEY_NPAGE      338   /* page down */
#define WG_KEY_PPAGE      339   /* page up */
#define WG_KEY_STAB       353
#define WG_KEY_CTAB       354
#define WG_KEY_CATAB      355
#define WG_KEY_ENTER      343
#define WG_KEY_SIC        389
#define WG_KEY_SDC        383
#define WG_KEY_SHOME      391
#define WG_KEY_SEND       386
#define WG_KEY_SR         337   /* shift up */
#define WG_KEY_SF         336   /* shift down */
#define WG_KEY_SLEFT      393
#define WG_KEY_SRIGHT     402
#define WG_KEY_END        360
#define WG_KEY_MOUSE      409
#define WG_KEY_RESIZE     410
#define WG_KEY_MAX        511
#define WG_KEY_TIMEOUT    (WG_KEY_MAX + 1)

static void fill_cell(WgIOSCell* cell, int32_t cp) {
    cell->codepoint = cp;
    cell->fg_index  = cur_fg;
    cell->bg_index  = cur_bg;
    cell->attrs     = cur_attrs;
    cell->reserved  = 0;
}

void dpy_init(const char* argv[]) {
    (void)argv;
    for (int i = 0; i < WG_IOS_CELL_COUNT; i++) {
        back_buf[i].codepoint = 0x20;
        front_buf[i].codepoint = 0x20;
    }
}

void dpy_start(void)    {}
void dpy_shutdown(void) {}

void dpy_clearscreen(void) {
    for (int i = 0; i < WG_IOS_CELL_COUNT; i++) {
        fill_cell(&back_buf[i], 0x20);
    }
}

void dpy_cleararea(int x1, int y1, int x2, int y2) {
    if (x1 < 0) x1 = 0;
    if (y1 < 0) y1 = 0;
    if (x2 >= cols) x2 = cols - 1;
    if (y2 >= rows) y2 = rows - 1;
    for (int y = y1; y <= y2; y++) {
        for (int x = x1; x <= x2; x++) {
            fill_cell(&back_buf[y * cols + x], 0x20);
        }
    }
}

void dpy_setattr(int andmask, int ormask) {
    cur_attrs = (uint16_t)((cur_attrs & andmask) | ormask);
}

bool dpy_setcolorindex(int colorindex) {
    cur_fg = (uint16_t)colorindex;
    return true;
}

bool dpy_setcolorpair(int fg, int bg) {
    cur_fg = (uint16_t)fg;
    cur_bg = (uint16_t)bg;
    return true;
}

void dpy_writechar(int x, int y, uni_t c) {
    if (x < 0 || y < 0 || x >= cols || y >= rows) return;
    fill_cell(&back_buf[y * cols + x], c);
}

void dpy_setcursor(int x, int y, bool shown) {
    cursor_col = x;
    cursor_row = y;
    cursor_visible = shown ? 1 : 0;
}

void dpy_sync(void) {
    pthread_mutex_lock(&swap_lock);
    memcpy(front_buf, back_buf, sizeof(front_buf));
    frame_counter++;
    pthread_mutex_unlock(&swap_lock);
}

void dpy_getscreensize(int* x, int* y) {
    *x = cols;
    *y = rows;
}

/* ---- Input queue ---- */

#define WG_INPUT_QUEUE_SIZE 128
static int32_t input_queue[WG_INPUT_QUEUE_SIZE];
static int input_head = 0;
static int input_tail = 0;
static pthread_mutex_t input_lock = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t  input_cond = PTHREAD_COND_INITIALIZER;

void wg_ios_push_key(int32_t key) {
    pthread_mutex_lock(&input_lock);
    int next = (input_tail + 1) % WG_INPUT_QUEUE_SIZE;
    if (next != input_head) {
        input_queue[input_tail] = key;
        input_tail = next;
    }
    /* Drop on overflow (prevents head==tail ambiguity). Keystrokes are
       low-volume; overflow shouldn't happen in normal use. */
    pthread_cond_signal(&input_cond);
    pthread_mutex_unlock(&input_lock);
}

uni_t dpy_getchar(double timeout) {
    pthread_mutex_lock(&input_lock);

    if (input_head == input_tail) {
        if (timeout < 0) {
            while (input_head == input_tail) {
                pthread_cond_wait(&input_cond, &input_lock);
            }
        } else {
            struct timespec ts;
            clock_gettime(CLOCK_REALTIME, &ts);
            time_t whole = (time_t)timeout;
            long frac_ns = (long)((timeout - (double)whole) * 1e9);
            ts.tv_sec  += whole;
            ts.tv_nsec += frac_ns;
            if (ts.tv_nsec >= 1000000000L) {
                ts.tv_sec  += 1;
                ts.tv_nsec -= 1000000000L;
            }
            while (input_head == input_tail) {
                int r = pthread_cond_timedwait(&input_cond, &input_lock, &ts);
                if (r == ETIMEDOUT) {
                    pthread_mutex_unlock(&input_lock);
                    return -WG_KEY_TIMEOUT;
                }
            }
        }
    }

    int32_t key = input_queue[input_head];
    input_head = (input_head + 1) % WG_INPUT_QUEUE_SIZE;
    pthread_mutex_unlock(&input_lock);
    return key;
}

/* Mirrors the curses backend's dpy_getkeyname so Lua key-binding strings
   match across platforms. Caller-owned: returned pointer is valid until the
   next call from the same thread. */
const char* dpy_getkeyname(uni_t k) {
    k = -k;

    switch (k) {
        case WG_KEY_BACKSPACE: return "KEY_BACKSPACE";
        case WG_KEY_TIMEOUT:   return "KEY_TIMEOUT";
        case WG_KEY_DOWN:      return "KEY_DOWN";
        case WG_KEY_UP:        return "KEY_UP";
        case WG_KEY_LEFT:      return "KEY_LEFT";
        case WG_KEY_RIGHT:     return "KEY_RIGHT";
        case WG_KEY_HOME:      return "KEY_HOME";
        case WG_KEY_END:       return "KEY_END";
        case WG_KEY_DC:        return "KEY_DELETE";
        case WG_KEY_IC:        return "KEY_INSERT";
        case WG_KEY_NPAGE:     return "KEY_PGDN";
        case WG_KEY_PPAGE:     return "KEY_PGUP";
        case WG_KEY_STAB:      return "KEY_STAB";
        case WG_KEY_CTAB:      return "KEY_^TAB";
        case WG_KEY_CATAB:     return "KEY_^ATAB";
        case WG_KEY_ENTER:     return "KEY_RETURN";
        case WG_KEY_SIC:       return "KEY_SINSERT";
        case WG_KEY_SDC:       return "KEY_SDELETE";
        case WG_KEY_SHOME:     return "KEY_SHOME";
        case WG_KEY_SEND:      return "KEY_SEND";
        case WG_KEY_SR:        return "KEY_SUP";
        case WG_KEY_SF:        return "KEY_SDOWN";
        case WG_KEY_SLEFT:     return "KEY_SLEFT";
        case WG_KEY_SRIGHT:    return "KEY_SRIGHT";
        case WG_KEY_MOUSE:     return "KEY_MOUSE";
        case WG_KEY_RESIZE:    return "KEY_RESIZE";
        case 13:               return "KEY_RETURN";
        case 27:               return "KEY_ESCAPE";
    }

    static char buffer[32];
    if (k < 32) {
        snprintf(buffer, sizeof(buffer), "KEY_^%c", k + 'A' - 1);
        return buffer;
    }
    if (k >= WG_KEY_F0 && k < WG_KEY_F0 + 64) {
        snprintf(buffer, sizeof(buffer), "KEY_F%d", k - WG_KEY_F0);
        return buffer;
    }
    snprintf(buffer, sizeof(buffer), "KEY_UNKNOWN_%d", k);
    return buffer;
}

/* -------- Accessors for wg_ios.c -------- */

int      wg_ios_dpy_cols(void)             { return cols; }
int      wg_ios_dpy_rows(void)             { return rows; }
uint32_t wg_ios_dpy_frame_counter(void)    { return frame_counter; }
int      wg_ios_dpy_cursor_col(void)       { return cursor_col; }
int      wg_ios_dpy_cursor_row(void)       { return cursor_row; }
int      wg_ios_dpy_cursor_visible(void)   { return cursor_visible; }

void wg_ios_dpy_snapshot(WgIOSCell* out, int max_cells) {
    pthread_mutex_lock(&swap_lock);
    int n = WG_IOS_CELL_COUNT;
    if (n > max_cells) n = max_cells;
    memcpy(out, front_buf, n * sizeof(WgIOSCell));
    pthread_mutex_unlock(&swap_lock);
}
