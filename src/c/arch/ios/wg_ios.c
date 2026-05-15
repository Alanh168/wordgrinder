#include "wg_ios.h"
#include "globals.h"
#include "lua-bitop.h"
#include <stdio.h>
#include <locale.h>

/* Lua bitop, registered by wordgrinder's main.c on Lua 5.1 */
extern int luaopen_bit(lua_State *L);
/* LPeg parser */
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

/* Replicates main.c's init sequence up to (but NOT including) script_run().
 * On success returns a status string with the Lua _VERSION + script count. */
const char* wg_ios_boot_test(void)
{
    if (boot_completed) {
        snprintf(boot_buf, sizeof(boot_buf), "already booted");
        return boot_buf;
    }

    static const char* fake_argv[] = { "wordgrinder", NULL };

    /* findlocale() — try common UTF-8 locales */
    static const char* locales[] = { "C.UTF-8", "en_US.UTF-8", "en_GB.UTF-8", "", NULL };
    const char** p = locales;
    while (*p && !setlocale(LC_ALL, *p)) p++;

    script_init();
    screen_init(fake_argv);
    word_init();
    utils_init();
    filesystem_init();
    zip_init();

    /* Lua 5.1 — direct openers, not luaL_requiref */
    luaopen_bit(L);
    luaopen_lpeg(L);

    /* Count scripts in the table */
    int script_count = 0;
    const FileDescriptor* fd = script_table;
    while (fd->data) { script_count++; fd++; }

    script_load_from_table(script_table);

    boot_completed = 1;
    snprintf(boot_buf, sizeof(boot_buf),
             "wordgrinder boot OK | %s | %d scripts loaded",
             LUA_VERSION, script_count);
    return boot_buf;
}
