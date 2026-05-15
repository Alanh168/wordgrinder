/* iOS display backend.
 *
 * Phase 2B: all no-ops so wordgrinder's init sequence can run without
 * crashing. Phase 2C will replace this with a real cell buffer that
 * Swift reads to drive the Metal renderer.
 */

#include "globals.h"
#include <string.h>

static int screen_cols = 80;
static int screen_rows = 24;

void dpy_init(const char* argv[])      { (void)argv; }
void dpy_start(void)                    {}
void dpy_shutdown(void)                 {}
void dpy_clearscreen(void)              {}
void dpy_sync(void)                     {}
void dpy_setattr(int andmask, int ormask)     { (void)andmask; (void)ormask; }
bool dpy_setcolorindex(int colorindex)        { (void)colorindex; return true; }
bool dpy_setcolorpair(int fg, int bg)         { (void)fg; (void)bg; return true; }
void dpy_writechar(int x, int y, uni_t c)     { (void)x; (void)y; (void)c; }
void dpy_setcursor(int x, int y, bool shown)  { (void)x; (void)y; (void)shown; }
void dpy_cleararea(int x1, int y1, int x2, int y2)
    { (void)x1; (void)y1; (void)x2; (void)y2; }

void dpy_getscreensize(int* x, int* y)
{
    *x = screen_cols;
    *y = screen_rows;
}

/* Returns 'Q' immediately to make the wordgrinder event loop exit on its
   first poll. Replaced in Phase 2D with a real keystroke queue. */
uni_t dpy_getchar(double timeout)
{
    (void)timeout;
    return 'Q';
}

const char* dpy_getkeyname(uni_t key)
{
    (void)key;
    return NULL;
}
