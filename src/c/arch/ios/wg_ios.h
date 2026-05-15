#ifndef WG_IOS_H
#define WG_IOS_H

#ifdef __cplusplus
extern "C" {
#endif

const char* wg_ios_hello(void);

/* Evaluates a Lua expression string and returns its tostring()'d result.
   Returned pointer is owned by the library (static buffer, single-call use). */
const char* wg_ios_lua_eval(const char* expression);

#ifdef __cplusplus
}
#endif

#endif
