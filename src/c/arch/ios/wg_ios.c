#include "wg_ios.h"
#include "lua.h"
#include "lauxlib.h"
#include "lualib.h"
#include <stdio.h>

const char* wg_ios_hello(void)
{
    return "wordgrinder linked OK";
}

static char eval_buf[512];

const char* wg_ios_lua_eval(const char* expression)
{
    lua_State* L = luaL_newstate();
    if (!L) return "lua: luaL_newstate failed";
    luaL_openlibs(L);

    char wrapped[1024];
    snprintf(wrapped, sizeof(wrapped), "return tostring((%s))", expression);

    if (luaL_dostring(L, wrapped) != 0) {
        const char* err = lua_tostring(L, -1);
        snprintf(eval_buf, sizeof(eval_buf), "lua error: %s", err ? err : "(no message)");
        lua_close(L);
        return eval_buf;
    }

    const char* result = lua_tostring(L, -1);
    snprintf(eval_buf, sizeof(eval_buf), "%s", result ? result : "(nil)");
    lua_close(L);
    return eval_buf;
}
