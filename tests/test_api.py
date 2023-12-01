"""
Tests the Frame specific Lua libraries over Bluetooth.
"""

import asyncio
import sys
from frameutils import Bluetooth


class TestBluetooth(Bluetooth):
    def __init__(self):
        self._passed_tests = 0
        self._failed_tests = 0

    def _log_passed(self, sent, responded):
        self._passed_tests += 1
        if responded == None:
            print(f"\033[92mPassed: {sent}")
        else:
            print(f"\033[92mPassed: {sent} => {responded}")

    def _log_failed(self, sent, responded, expected):
        self._failed_tests += 1
        if expected == None:
            print(f"\033[91mFAILED: {sent} => {responded}")
        else:
            print(f"\033[91mFAILED: {sent} => {responded} != {expected}")

    async def initialize(self):
        await self.connect()

    async def end(self):
        passed_tests = self._passed_tests
        total_tests = self._passed_tests + self._failed_tests
        print("\033[0m")
        print(f"Done! Passed {passed_tests} of {total_tests} tests")
        await self.disconnect()

    async def lua_equals(self, send: str, expect):
        response = await self.send_lua(f"print({send})", await_print=True)
        if response == str(expect):
            self._log_passed(send, response)
        else:
            self._log_failed(send, response, expect)

    async def lua_is_type(self, send: str, expect):
        response = await self.send_lua(f"print(type({send}))", await_print=True)
        if response == str(expect):
            self._log_passed(send, response)
        else:
            self._log_failed(send, response, expect)

    async def lua_has_length(self, send: str, length: int):
        response = await self.send_lua(f"print({send})", await_print=True)
        if len(response) == length:
            self._log_passed(send, response)
        else:
            self._log_failed(send, f"len({len(response)})", f"len({length})")

    async def lua_send(self, send: str):
        response = await self.send_lua(send + ";print(nil)", await_print=True)
        if response == "nil":
            self._log_passed(send, None)
        else:
            self._log_failed(send, response, None)

    async def lua_error(self, send: str):
        response = await self.send_lua(send + ";print(nil)", await_print=True)
        if response != "nil":
            self._log_passed(send, response.partition(":1: ")[2])
        else:
            self._log_failed(send, response, None)

    async def data_equal(self, send: bytearray, expect: bytearray):
        response = await self.send_data(send, await_data=True)
        if response == expect:
            self._log_passed(send, response)
        else:
            self._log_failed(send, response, expect)


async def main():
    test = TestBluetooth()
    await test.initialize()

    # Version
    await test.lua_has_length("frame.FIRMWARE_VERSION", 12)
    await test.lua_has_length("frame.GIT_TAG", 7)

    # Bluetooth
    await test.lua_has_length("frame.bluetooth.address()", 17)

    # Send and callback
    await test.lua_send(
        "frame.bluetooth.receive_callback((function(d)frame.bluetooth.send(d)end))"
    )
    await test.data_equal(b"test", b"test")
    await test.lua_send("frame.bluetooth.receive_callback(nil)")

    # MTU size
    max_length = test.max_data_payload()
    await test.lua_equals("frame.bluetooth.max_length()", max_length)
    await test.lua_send("frame.bluetooth.send('123')")
    await test.lua_send("frame.bluetooth.send('12\\0003')")
    await test.lua_send(f"frame.bluetooth.send(string.rep('a',{max_length}))")
    await test.lua_error(f"frame.bluetooth.send(string.rep('a',{max_length + 1}))")

    # Display
    # TODO frame.display.text("string", x, y, {color, alignment})
    # TODO frame.display.show()

    # Camera
    # TODO camera.output_format(xres, yres, colordepth)
    # TODO pan and zoom?
    # TODO camera.capture()
    # TODO camera.read(bytes)

    # Microphone

    # Expected sizes for different record options
    await test.lua_send("frame.microphone.record(0.0125, 16000, 16)")
    await asyncio.sleep(0.1)
    await test.lua_equals("#frame.microphone.read(512)", "400")

    await test.lua_send("frame.microphone.record(0.05, 8000, 8)")
    await asyncio.sleep(0.1)
    await test.lua_equals("#frame.microphone.read(512)", "400")

    await test.lua_send("frame.microphone.record(0.05, 4000, 4)")
    await asyncio.sleep(0.1)
    await test.lua_equals("#frame.microphone.read(512)", "100")

    # Unexpected parameters
    await test.lua_error("frame.microphone.record(0, 16000, 8)")
    await test.lua_error("frame.microphone.record(-3, 16000, 8)")
    await test.lua_error("frame.microphone.record(5, 12000, 8)")
    await test.lua_error("frame.microphone.record(5, 16000, 12)")

    # Restarted recording
    await test.lua_send("frame.microphone.record(0.0125, 16000, 16)")
    await asyncio.sleep(1)
    await test.lua_send("frame.microphone.record(0.0125, 16000, 16)")
    await asyncio.sleep(0.1)
    await test.lua_equals("#frame.microphone.read(512)", "400")

    # Continuous readout
    # TODO

    # FIFO overflow
    # TODO

    # IMU
    # imu.heading().exactly                 => ±180 degrees
    # imu.heading().roughly                 => N, NNE, NE, NEE, E, ...
    # imu.yaw().exactly                     => ±180 degrees
    # imu.yaw().roughly                     => LEFT, SLIGHTLY_LEFT, CENTER, ...
    # imu.pitch().exactly                   => ±180 degrees
    # imu.pitch().roughly                   => UP, SLIGHTLY_UP, CENTER
    # TODO Tap, double tap?

    # Time functions

    # Delays
    await test.lua_send("frame.time.utc(1698756584)")
    await test.lua_send("frame.sleep(2.0)")
    await test.lua_equals("math.floor(frame.time.utc()+0.5)", "1698756586")

    # Date now under different timezones
    await test.lua_send("frame.time.zone('0:00')")
    await test.lua_equals("frame.time.zone()", "+00:00")

    await test.lua_equals("frame.time.date()['second']", "46")
    await test.lua_equals("frame.time.date()['minute']", "49")
    await test.lua_equals("frame.time.date()['hour']", "12")
    await test.lua_equals("frame.time.date()['day']", "31")
    await test.lua_equals("frame.time.date()['month']", "10")
    await test.lua_equals("frame.time.date()['year']", "2023")
    await test.lua_equals("frame.time.date()['weekday']", "2")
    await test.lua_equals("frame.time.date()['day of year']", "303")
    await test.lua_equals("frame.time.date()['is daylight saving']", "false")

    await test.lua_send("frame.time.zone('2:30')")
    await test.lua_equals("frame.time.zone()", "+02:30")

    await test.lua_equals("frame.time.date()['minute']", "19")
    await test.lua_equals("frame.time.date()['hour']", "15")

    await test.lua_send("frame.time.zone('-3:45')")
    await test.lua_equals("frame.time.zone()", "-03:45")

    # Invalid timezones
    await test.lua_error("frame.time.zone('0:25')")
    await test.lua_error("frame.time.zone('15:00')")
    await test.lua_error("frame.time.zone('-13:00')")

    # Date table from UTC timestamp
    await test.lua_send("frame.time.zone('+01:00')")
    await test.lua_equals("frame.time.date(1698943733)['second']", "53")
    await test.lua_equals("frame.time.date(1698943733)['minute']", "48")
    await test.lua_equals("frame.time.date(1698943733)['hour']", "17")
    await test.lua_equals("frame.time.date(1698943733)['day']", "2")
    await test.lua_equals("frame.time.date(1698943733)['month']", "11")
    await test.lua_equals("frame.time.date(1698943733)['year']", "2023")
    await test.lua_equals("frame.time.date(1698943733)['weekday']", "4")
    await test.lua_equals("frame.time.date(1698943733)['day of year']", "305")
    await test.lua_equals("frame.time.date(1698943733)['is daylight saving']", "false")

    # System functions

    # Resets
    await test.send_reset_signal()
    await asyncio.sleep(1)
    await test.send_reset_signal()

    # Battery level
    await test.lua_equals("frame.battery_level()", "100.0")

    # Cancelling sleep
    await test.lua_is_type("frame.sleep", "function")
    await test.send_lua("frame.sleep()")
    await asyncio.sleep(1)
    await test.send_break_signal()

    # Preventing sleep
    await test.lua_equals("frame.stay_awake()", "false")
    await test.lua_send("frame.stay_awake(true)")
    await test.send_lua("frame.sleep()")
    await asyncio.sleep(4)
    await test.lua_equals("frame.stay_awake()", "true")
    await test.lua_send("frame.stay_awake(false)")

    # Cancelling update
    await test.lua_is_type("frame.update", "function")
    await test.send_lua("frame.update()")
    await asyncio.sleep(1)
    await test.send_break_signal()

    # FPGA io
    # frame.fpga.read()
    # frame.fpga.write()

    # File handling
    # TODO frame.file.open()
    # frame.file.read()
    # TODO frame.file.write()
    # TODO frame.file.close()
    # TODO frame.file.remove()
    # frame.file.rename()

    # Standard libraries
    await test.lua_equals("math.sqrt(25)", "5.0")

    await test.end()


asyncio.run(main())
