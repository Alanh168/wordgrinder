/* © 2008 David Given.
 * WordGrinder is licensed under the MIT open source license. See the COPYING
 * file in this distribution for the full text.
 */

#include "globals.h"
#include <string.h>
#include <curses.h>
#include <wctype.h>
#include <sys/time.h>
#include <time.h>

#define KEY_TIMEOUT (KEY_MAX + 1)
#define INDEXED_PAIR_BASE 1
#define INDEXED_COLOUR_COUNT 256
#define DPY_COLOUR_MASK (DPY_COLOR_RED | DPY_COLOR_YELLOW | DPY_COLOR_CYAN | \
	DPY_COLOR_BLUE | DPY_COLOR_MAGENTA | DPY_COLOR_WHITE | \
	DPY_COLOR_ORANGE | DPY_COLOR_DARKORANGE | DPY_COLOR_BEIGE)

#if defined A_ITALIC
/* True when the terminal advertises italics via terminfo. */
static bool has_italics = false;
#endif

static int attr = 0; /* Current DPY_* attribute bitmask. */
static int indexed_pair = 0; /* Active runtime pair id for wg.setcolorindex(). */
static int indexed_pair_capacity = 0; /* Available pair slots from INDEXED_PAIR_BASE upward. */
static int indexed_pairs_used = 0; /* Number of runtime pairs allocated in this cache. */
static int indexed_colour_to_pair[INDEXED_COLOUR_COUNT]; /* xterm index -> pair id cache; 0=unseen, -1=unsupported. */
static bool indexed_pairs_initialised = false; /* Guards one-time runtime pair setup. */

/* Clamp caller-supplied indexed colours to the supported 0..255 range. */
static int clamp_colour_index(int colour)
{
	if (colour < 0)
		return 0;
	if (colour > (INDEXED_COLOUR_COUNT - 1))
		colour = INDEXED_COLOUR_COUNT - 1;
	return colour;
}

/* Clear runtime indexed-colour allocations so they can be rebuilt lazily. */
static void reset_indexed_pair_cache(void)
{
	indexed_pair = 0;
	indexed_pairs_used = 0;
	memset(indexed_colour_to_pair, 0, sizeof(indexed_colour_to_pair));
}

/* Initialize runtime indexed-colour support once per curses session. */
static void init_indexed_pairs(void)
{
	if (indexed_pairs_initialised)
		return;

	indexed_pairs_initialised = true;
	indexed_pair_capacity = 0;

	if (!has_colors())
		return;

	if (COLOR_PAIRS <= INDEXED_PAIR_BASE)
		return;

	indexed_pair_capacity = COLOR_PAIRS - INDEXED_PAIR_BASE;
	reset_indexed_pair_cache();
}

/* Resolve (or allocate) a curses pair id for a 0..255 foreground colour index. */
static int resolve_indexed_pair(int colour)
{
	init_indexed_pairs();

	if (!has_colors() || (indexed_pair_capacity <= 0))
		return 0;

	colour = clamp_colour_index(colour);
	int pair = indexed_colour_to_pair[colour]; /* Cached mapping for this colour index. */
	if (pair > 0)
		return pair;
	if (pair < 0)
		return 0;

	if (colour >= COLORS)
	{
		indexed_colour_to_pair[colour] = -1;
		return 0;
	}

	if (indexed_pairs_used >= indexed_pair_capacity)
	{
		indexed_colour_to_pair[colour] = -1;
		return 0;
	}

	pair = INDEXED_PAIR_BASE + indexed_pairs_used;
	indexed_pairs_used++;

	if (init_pair(pair, colour, -1) == ERR)
	{
		indexed_colour_to_pair[colour] = -1;
		return 0;
	}

	indexed_colour_to_pair[colour] = pair;
	return pair;
}

/* Convert legacy DPY named-colour bits into concrete terminal colour indexes. */
static int resolve_named_colour_index(void)
{
	if (attr & DPY_COLOR_RED)
		return COLOR_RED;
	if (attr & DPY_COLOR_YELLOW)
		return COLOR_YELLOW;
	if (attr & DPY_COLOR_CYAN)
		return COLOR_CYAN;
	if (attr & DPY_COLOR_BLUE)
		return COLOR_BLUE;
	if (attr & DPY_COLOR_MAGENTA)
		return COLOR_MAGENTA;
	if (attr & DPY_COLOR_WHITE)
		return COLOR_WHITE;
	if (attr & DPY_COLOR_ORANGE)
		return (COLORS >= INDEXED_COLOUR_COUNT) ? 208 : COLOR_YELLOW;
	if (attr & DPY_COLOR_DARKORANGE)
		return (COLORS >= INDEXED_COLOUR_COUNT) ? 130 : COLOR_RED;
	if (attr & DPY_COLOR_BEIGE)
		return (COLORS >= INDEXED_COLOUR_COUNT) ? 223 : COLOR_WHITE;
	return -1;
}

/* Map logical DPY colour flags (or indexed colour) to a curses COLOR_PAIR(). */
static int resolve_colour_pair(void)
{
	if (!has_colors())
		return 0;

	if (indexed_pair > 0)
		return COLOR_PAIR(indexed_pair);

	int colour = resolve_named_colour_index();
	if (colour >= 0)
	{
		int pair = resolve_indexed_pair(colour);
		if (pair > 0)
			return COLOR_PAIR(pair);
	}

	return 0;
}

/* Translate the DPY_* bitmask into curses attributes and apply with attrset(). */
static void apply_attr(void)
{
	int cattr = 0; /* Combined curses attributes for the next draw operations. */
	if (attr & DPY_ITALIC)
	{
		#if defined A_ITALIC
			if (has_italics)
				cattr |= A_ITALIC;
			else
				cattr |= A_BOLD;
		#else
			cattr |= A_BOLD;
		#endif
	}
	if (attr & (DPY_BOLD|DPY_BRIGHT))
		cattr |= A_BOLD;
	if (attr & DPY_DIM)
		cattr |= A_DIM;
	if (attr & DPY_UNDERLINE)
		cattr |= A_UNDERLINE;
	if (attr & DPY_REVERSE)
		cattr |= A_REVERSE;

	cattr |= resolve_colour_pair();
	attrset(cattr);
}

/* Pre-curses startup tuning. */
void dpy_init(const char* argv[])
{
	// ESCDELAY defaults to 1000 (ms) in ncurses. This is why the menu requires a 1 second delay to appear after hitting escape.
	// Setting it too low might interfere with other control key inputs. 30ms keeps menu response snappy.
	ESCDELAY = 30;
}

/* Start curses mode, configure terminal behavior, and initialise color support. */
void dpy_start(void)
{
	attr = 0;
	indexed_pair = 0;
	indexed_pair_capacity = 0;
	indexed_pairs_used = 0;
	memset(indexed_colour_to_pair, 0, sizeof(indexed_colour_to_pair));
	indexed_pairs_initialised = false;

	initscr();
	raw();
	noecho();
	meta(NULL, TRUE);
	nonl();
	idlok(stdscr, TRUE);
	idcok(stdscr, TRUE);
	scrollok(stdscr, FALSE);
	intrflush(stdscr, FALSE);
	//notimeout(stdscr, TRUE);
	keypad(stdscr, TRUE);

	#if defined A_ITALIC
		has_italics = !!tigetstr("sitm");
	#endif

	if (has_colors())
	{
		start_color();
		use_default_colors();
	}
}

/* Leave curses mode and restore terminal settings. */
void dpy_shutdown(void)
{
	endwin();
}

/* Clear all drawn content and reset dynamic indexed-colour caches. */
void dpy_clearscreen(void)
{
	erase();
	reset_indexed_pair_cache();
}

/* Return current screen dimensions in character cells. */
void dpy_getscreensize(int* x, int* y)
{
	getmaxyx(stdscr, *y, *x);
}

/* Flush pending terminal updates. */
void dpy_sync(void)
{
	refresh();
}

/* Move the cursor to a cell; curses backend ignores the 'shown' hint. */
void dpy_setcursor(int x, int y, bool shown)
{
	move(y, x);
}

/* Update logical attributes and clear indexed colours when named colours are set. */
void dpy_setattr(int andmask, int ormask)
{
	attr &= andmask;
	attr |= ormask;

	if ((andmask == 0) && (ormask == 0))
		indexed_pair = 0;
	else if (ormask & DPY_COLOUR_MASK)
		indexed_pair = 0;

	apply_attr();
}

/* Set a foreground by 0..255 index, allocating a runtime pair if possible. */
bool dpy_setcolorindex(int colorindex)
{
	if (colorindex < 0)
		indexed_pair = 0;
	else
		indexed_pair = resolve_indexed_pair(colorindex);
	attr &= ~DPY_COLOUR_MASK;
	apply_attr();
	return indexed_pair > 0;
}

/* Encode one Unicode codepoint as UTF-8 and render it at (x, y). */
void dpy_writechar(int x, int y, uni_t c)
{
	char buffer[8]; /* UTF-8 bytes for one codepoint plus '\0'. */
	char* p = buffer; /* Running output pointer consumed by writeu8(). */
	writeu8(&p, c);
	*p = '\0';

	mvaddstr(y, x, buffer);
}

/* Fill a rectangular region with spaces using the current attributes. */
void dpy_cleararea(int x1, int y1, int x2, int y2)
{
	char cc = ' '; /* Single blank glyph reused for each cell write. */

	for (int y = y1; y <= y2; y++)
		for (int x = x1; x <= x2; x++)
			mvaddnstr(y, x, &cc, 1);
}

/* Read one character or key token, returning KEY_TIMEOUT on timeout expiry. */
uni_t dpy_getchar(double timeout)
{
	struct timeval then; /* Start timestamp for timeout accounting. */
	gettimeofday(&then, NULL);
	u_int64_t thenms = (then.tv_usec/1000) + ((u_int64_t) then.tv_sec*1000); /* Start time in ms. */

	for (;;)
	{

		if (timeout != -1)
		{
			struct timeval now;
			gettimeofday(&now, NULL);
			u_int64_t nowms = (now.tv_usec/1000) + ((u_int64_t) now.tv_sec*1000); /* Current time in ms. */

			int delay = ((u_int64_t) (timeout*1000)) + nowms - thenms; /* Remaining timeout window (ms). */
			if (delay <= 0)
				return -KEY_TIMEOUT;

			timeout(delay);
		}
		else
			timeout(-1);

		wint_t c;
		int r = get_wch(&c);

		if (r == ERR) /* timeout */
			return -KEY_TIMEOUT;

		if ((r == KEY_CODE_YES) || !iswprint(c)) /* function key */
			return -c;

		if (emu_wcwidth(c) > 0)
			return c;
	}
}

/* Translate ncurses keyname() prefixes into WordGrinder token names. */
static const char* ncurses_prefix_to_name(const char* s)
{
	if (strcmp(s, "KDC") == 0)  return "DELETE";
	if (strcmp(s, "kDN") == 0)  return "DOWN";
	if (strcmp(s, "kEND") == 0) return "END";
	if (strcmp(s, "kHOM") == 0) return "HOME";
	if (strcmp(s, "kIC") == 0)  return "INSERT";
	if (strcmp(s, "kLFT") == 0) return "LEFT";
	if (strcmp(s, "kNXT") == 0) return "PGDN";
	if (strcmp(s, "kPRV") == 0) return "PGUP";
	if (strcmp(s, "kRIT") == 0) return "RIGHT";
	if (strcmp(s, "kUP") == 0)  return "UP";

	return s;
}

/* Translate ncurses numeric suffixes into modifier strings. */
static const char* ncurses_suffix_to_name(int suffix)
{
	switch (suffix)
	{
		case 3: return "A";
		case 4: return "SA";
		case 5: return "^";
		case 6: return "S^";
		case 7: return "A^";
	}

	return NULL;
}

/* Convert backend key codes to stable KEY_* names consumed by Lua/UI code. */
const char* dpy_getkeyname(uni_t k)
{
	k = -k;

	switch (k)
	{
		case 127: /* Some misconfigured terminals produce this */
		case KEY_BACKSPACE:
			return "KEY_BACKSPACE";

		case KEY_TIMEOUT: return "KEY_TIMEOUT";
		case KEY_DOWN: return "KEY_DOWN";
		case KEY_UP: return "KEY_UP";
		case KEY_LEFT: return "KEY_LEFT";
		case KEY_RIGHT: return "KEY_RIGHT";
		case KEY_HOME: return "KEY_HOME";
		case KEY_END: return "KEY_END";
		case KEY_DC: return "KEY_DELETE";
		case KEY_IC: return "KEY_INSERT";
		case KEY_NPAGE: return "KEY_PGDN";
		case KEY_PPAGE: return "KEY_PGUP";
		case KEY_STAB: return "KEY_STAB";
		case KEY_CTAB: return "KEY_^TAB";
		case KEY_CATAB: return "KEY_^ATAB";
		case KEY_ENTER: return "KEY_RETURN";
		case KEY_SIC: return "KEY_SINSERT";
		case KEY_SDC: return "KEY_SDELETE";
		case KEY_SHOME: return "KEY_SHOME";
		case KEY_SEND: return "KEY_SEND";
		case KEY_SR: return "KEY_SUP";
		case KEY_SF: return "KEY_SDOWN";
		case KEY_SLEFT: return "KEY_SLEFT";
		case KEY_SRIGHT: return "KEY_SRIGHT";
		case KEY_MOUSE: return "KEY_MOUSE";
		case KEY_RESIZE: return "KEY_RESIZE";
		case 13: return "KEY_RETURN";
		case 27: return "KEY_ESCAPE";
	}

	static char buffer[32]; /* Persistent storage for synthesized key names. */
	if (k < 32)
	{
		sprintf(buffer, "KEY_^%c", k+'A'-1);
		return buffer;
	}

	if ((k >= KEY_F0) && (k < (KEY_F0+64)))
	{
		sprintf(buffer, "KEY_F%d", k - KEY_F0);
		return buffer;
	}

	const char* name = keyname(k);
	if (name)
	{
		char buf[strlen(name)+1];
		strcpy(buf, name);

		int prefix = strcspn(buf, "0123456789"); /* Start of ncurses numeric suffix. */
		int suffix = buf[prefix] - '0'; /* Encoded modifier selector. */
		buf[prefix] = '\0';

		if ((suffix >= 0) && (suffix <= 9))
		{
			const char* ps = ncurses_prefix_to_name(buf);
			const char* ss = ncurses_suffix_to_name(suffix);
			if (ss)
			{
				sprintf(buffer, "KEY_%s%s", ss, ps);
				return buffer;
			}
		}
	}

	sprintf(buffer, "KEY_UNKNOWN_%d (%s)", k, name ? name : "???");
	return buffer;
}
