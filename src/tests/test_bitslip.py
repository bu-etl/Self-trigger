'''
Author: Naomi Gonzalez
Descrition: Testbench to verify bitslip module works as expected
'''

import os
import random

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge
from cocotb_test.simulator import run


def calculate_expected_output(current_data_i, prev_data_i, slip_count, data_width, transmit_low_to_high):
    if slip_count == 0:
        # data_o <= prev_data_i
        return prev_data_i & ((1 << data_width) - 1)
    else:
        if transmit_low_to_high:
            # data_o <= data_i(i - 1 downto 0) & prev_data(g_DATA_WIDTH - 1 downto i);
            lower_bits = current_data_i & ((1 << slip_count) - 1)
            upper_bits = (prev_data_i >> slip_count) & ((1 << (data_width - slip_count)) - 1)
            shifted_data = (lower_bits << (data_width - slip_count)) | upper_bits
        else:
            # data_o <= prev_data(i - 1 downto 0) & data_i(g_DATA_WIDTH - 1 downto i);
            lower_bits = prev_data_i & ((1 << slip_count) - 1)
            upper_bits = (current_data_i >> slip_count) & ((1 << (data_width - slip_count)) - 1)
            shifted_data = (lower_bits << (data_width - slip_count)) | upper_bits
        return shifted_data & ((1 << data_width) - 1)


@cocotb.test()
async def bitslip_tb(dut):
    """Test the bitslip module with specfic inputs and randomized inputs"""

    # Start the clock
    cocotb.start_soon(Clock(dut.clk_i, 10, units="ns").start())

    # Initialize inputs to zeros
    dut.slip_cnt_i.value = 0
    dut.data_i.value     = 0
    prev_data            = 0

    # Wait for three clock cycles to ensure signals are stable
    for _ in range(3):
        await RisingEdge(dut.clk_i)

    DATA_WIDTH = dut.g_DATA_WIDTH.value.integer
    TRANSMIT_LOW_TO_HIGH   = dut.g_TRANSMIT_LOW_TO_HIGH.value

    failures = [] 

    async def run_case(slip_cnt, din):
        nonlocal prev_data

        dut.slip_cnt_i.value = slip_cnt
        dut.data_i.value     = din

        cur  = din
        prev = prev_data

        await RisingEdge(dut.clk_i)   # prev_data <= cur
        prev_data = cur

        await RisingEdge(dut.clk_i) 

        exp = calculate_expected_output(cur, prev, slip_cnt, DATA_WIDTH, TRANSMIT_LOW_TO_HIGH)
        got = dut.data_o.value.integer

        if got != exp:
            msg = (f"[FAIL] slip={slip_cnt}  prev={prev:#0{DATA_WIDTH//4+2}x} "
                   f"cur={cur:#0{DATA_WIDTH//4+2}x}  exp={exp:#0{DATA_WIDTH//4+2}x} "
                   f"got={got:#0{DATA_WIDTH//4+2}x}")
            cocotb.log.error(msg)
            failures.append(msg)
        else:
            cocotb.log.debug(f"[PASS] slip={slip_cnt}  prev={prev:#0{DATA_WIDTH//4+2}x} "
                   f"cur={cur:#0{DATA_WIDTH//4+2}x}  got={got:#0{DATA_WIDTH//4+2}x}")

    # Specific input with slip counts of 0, 1, and 2
    pattern = int("11010101010101010101010101010101", 2) & ((1 << DATA_WIDTH) - 1)
    for sc in (0, 1, 2):
        await run_case(sc, pattern)

    # Random input tests
    for _ in range(10):
        await run_case(random.randint(0, DATA_WIDTH - 1),
                       random.getrandbits(DATA_WIDTH))

    # Check if any failures occurred
    if failures:
        raise cocotb.result.TestFailure(
            f"{len(failures)} failure(s) detected:\n" + "\n".join(failures)
        )
    else:
        cocotb.log.info("All tests passed successfully 🎉")


def test_bitslip():
    """Sets up cocotb runs bitslip module test"""
    os.environ.setdefault("SIM", "ghdl")         
    os.environ.setdefault("GHDL_FLAGS", "--std=08")

    here = os.path.abspath(os.path.dirname(__file__))
    rtl  = os.path.join(here, "..", "hdl")

    run(
        vhdl_sources=[os.path.join(rtl, "bitslip.vhd")],
        toplevel="bitslip",
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
