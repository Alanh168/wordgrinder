/* Internal accessors shared between dpy.c and wg_ios.c.
   NOT part of the public XCFramework header (those go in wg_ios.h). */

#ifndef WG_IOS_INTERNAL_H
#define WG_IOS_INTERNAL_H

#include <stdint.h>

typedef struct {
    int32_t  codepoint;
    uint16_t fg_index;
    uint16_t bg_index;
    uint16_t attrs;
    uint16_t reserved;
} WgIOSCell;

int      wg_ios_dpy_cols(void);
int      wg_ios_dpy_rows(void);
uint32_t wg_ios_dpy_frame_counter(void);
int      wg_ios_dpy_cursor_col(void);
int      wg_ios_dpy_cursor_row(void);
int      wg_ios_dpy_cursor_visible(void);
void     wg_ios_dpy_snapshot(WgIOSCell* out, int max_cells);

#endif
