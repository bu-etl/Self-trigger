"""
Author: Naomi Gonzalez

Descrition: Testbench to verify flashing bit module works as expected
"""

import os
from pathlib import Path

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge
from cocotb_test.simulator import run


@cocotb.test()
async def flashbitclear_tb(dut):

    # Capture declared generics
    DATA_WIDTH   = dut.DATA_WIDTH.value.integer
    FLASH_PERIOD = dut.FLASH_PERIOD.value.integer
    THRESHOLD    = dut.THRESHOLD.value.integer

    # Start the clock
    cocotb.start_soon(Clock(dut.clk_i, 10, units="ns").start())

    # reset funciton
    async def reset(cycles=5):
        dut.reset_i.value = 1
        for _ in range(cycles):
            await RisingEdge(dut.clk_i)
        dut.reset_i.value = 0
        await RisingEdge(dut.clk_i)

    failures = []


    # test every index as the flashing bit position
    for idx in range(1):

        await reset()

        bit_state      = 0  # toggles every period
        active_period  = None           
        confirm_done   = False           

        # Enough periods for search of flashing bit index + confirmation
        max_periods = THRESHOLD + (DATA_WIDTH * FLASH_PERIOD)

        for period in range(max_periods):

            bit_state ^= 1  # next toggle (0→1 / 1→0)

            # Send flashing bit in first cyle of this period
            pattern = (1 << idx) if bit_state else 0
            dut.data_i.value = pattern
            await RisingEdge(dut.clk_i)

            # If already found flashing bit send check if clearing works 
            if active_period is not None and period == active_period + 1 and not confirm_done:
                cocotb.log.info(
                    f"[i={idx}] confirm pulse  input=0x{pattern:0{DATA_WIDTH//4}X} "
                    f"output=0x{int(dut.data_o.value):0{DATA_WIDTH//4}X}"
                )
                if int(dut.data_o.value[idx]) != 0:
                    failures.append(
                        f"[i={idx}] flashing bit not cleared during confirmation period"
                    )
                confirm_done = True
                break

            # Send all 0's for rest of period
            dut.data_i.value = 0
            for _ in range(FLASH_PERIOD - 1):
                await RisingEdge(dut.clk_i)

            # Check if flashing bit found
            if active_period is None and dut.active_o.value == 1:
                active_period = period

            # Check if flashing bit previously found but now lost
            if active_period is not None and dut.active_o.value != 1:
                failures.append(f"[i={idx}] active_o de‑asserted at period {period}")

        # Should have found flashing bit and confirmed clearing works
        if active_period is None:
            failures.append(f"[i={idx}] never entered ACTIVE")
        elif not confirm_done:
            failures.append(f"[i={idx}] confirmation pulse not executed")

    # Check if any failures occurred
    if failures:
        raise cocotb.result.TestFailure(f"{len(failures)} failure(s):\n" + "\n".join(failures))
    else:
        cocotb.log.info("FlashBitClear – all indices passed ✔")


def test_flashbitclear():
    """Sets up cocotb runs flashbitclear module test"""
    os.environ.setdefault("SIM", "ghdl")
    os.environ.setdefault("GHDL_FLAGS", "--std=08")

    here = os.path.abspath(os.path.dirname(__file__))
    rtl  = os.path.join(here, "..", "hdl")

    run(
        vhdl_sources=[os.path.join(rtl, "flash.vhd")],
        toplevel="flashbitclear",
        toplevel_lang="vhdl",
        module=os.path.splitext(os.path.basename(__file__))[0],
        waves=True,
        gui=0,
        extra_env={         
            "COCOTB_LOG_FILE":  "stdout",         
        },
    )



if __name__ == "__main__":
    import pytest, sys
    sys.exit(pytest.main(sys.argv[1:] + [__file__]))
