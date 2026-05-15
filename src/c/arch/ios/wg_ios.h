#ifndef WG_IOS_H
#define WG_IOS_H

#ifdef __cplusplus
extern "C" {
#endif

const char* wg_ios_hello(void);

/* Evaluates a Lua expression string and returns its tostring()'d result.
   Returned pointer is owned by the library (static buffer, single-call use). */
const char* wg_ios_lua_eval(const char* expression);

/* Runs wordgrinder's full init sequence (script_init, screen_init,
   word_init, utils_init, filesystem_init, zip_init, luaopen_bit/lpeg,
   script_load_from_table) but stops short of the main event loop.
   Returns a single-line status string. */
const char* wg_ios_boot_test(void);

#ifdef __cplusplus
}
#endif

#endif
