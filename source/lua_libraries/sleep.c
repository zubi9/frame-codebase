/*
 * This file is a part of: https://github.com/brilliantlabsAR/frame-codebase
 *
 * Authored by: Raj Nakarja / Brilliant Labs Ltd. (raj@brilliant.xyz)
 *              Rohit Rathnam / Silicon Witchery AB (rohit@siliconwitchery.com)
 *              Uma S. Gupta / Techno Exponent (umasankar@technoexponent.com)
 *
 * ISC Licence
 *
 * Copyright © 2023 Brilliant Labs Ltd.
 *
 * Permission to use, copy, modify, and/or distribute this software for any
 * purpose with or without fee is hereby granted, provided that the above
 * copyright notice and this permission notice appear in all copies.
 *
 * THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES WITH
 * REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF MERCHANTABILITY
 * AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY SPECIAL, DIRECT,
 * INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES WHATSOEVER RESULTING FROM
 * LOSS OF USE, DATA OR PROFITS, WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE OR
 * OTHER TORTIOUS ACTION, ARISING OUT OF OR IN CONNECTION WITH THE USE OR
 * PERFORMANCE OF THIS SOFTWARE.
 */

#include <stdbool.h>
#include "lua.h"
#include "lauxlib.h"
#include "error_logging.h"
#include "nrf_soc.h"
#include "nrf52840.h"

extern bool force_sleep;

static int frame_sleep(lua_State *L)
{
    if (lua_gettop(L) == 0)
    {
        // TODO wait 3 seconds before actually sleeping

        force_sleep = true;
        return 0;
    }

    // Get the current time
    if (luaL_dostring(L, "return frame.time.utc()") != LUA_OK)
    {
        error_with_message("lua error");
    }

    // Add the current time to the wait time
    lua_Number wait_until = lua_tonumber(L, 1) + lua_tonumber(L, 2);

    while (true)
    {
        // Keep getting the current time
        if (luaL_dostring(L, "return frame.time.utc()") != LUA_OK)
        {
            error_with_message("lua error");
        }

        lua_Number current_time = lua_tonumber(L, 3);
        lua_pop(L, 1);

        if (current_time >= wait_until)
        {
            break;
        }

        // Clear exceptions
        __set_FPSCR(__get_FPSCR() & ~(0x0000009F));
        (void)__get_FPSCR();

        NVIC_ClearPendingIRQ(FPU_IRQn);

        check_error(sd_app_evt_wait());
    }

    return 0;
}

void open_frame_sleep_library(lua_State *L)
{
    lua_getglobal(L, "frame");

    lua_pushcfunction(L, frame_sleep);
    lua_setfield(L, -2, "sleep");

    lua_pop(L, 1);
}