"""
Author: Naomi Gonzalez

Descrition: Testbench to full self trigger works as expected
"""

import os
import random

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer
from cocotb_test.simulator import run


# reset function
async def reset_dut(dut):
    """Resets the DUT."""
    dut.reset_i.value = 1
    await Timer(50, units="ns")
    dut.reset_i.value = 0
    await RisingEdge(dut.clk_i)
    dut._log.info("DUT has been reset.")

async def run_no_trigger_test(dut, rate):
    """
    Test 1: Puts the flashing bit for every index at the correct flash period
    and all other data is 0 to verify that trigger_o will always be 0
    """

    # Capture declared generics
    UPLINK_WIDTH = dut.UPLINK_WIDTH.value.integer
    FLASH_PERIOD = dut.FLASH_PERIOD.value.integer
    THRESHOLD = dut.THRESHOLD.value.integer

    etroc_width = 8 * (2**rate)
    num_links = UPLINK_WIDTH // etroc_width

    dut._log.info(f"[Test 1, Rate {rate}] Starting no-trigger test with {num_links} flashing links.")
    await reset_dut(dut)

    # Configure initial DUT values
    dut.rate_i.value = rate
    dut.enable_i.value = (1 << UPLINK_WIDTH) - 1  # All bits enabled
    dut.slip_i.value = 0

    bit_state = 0
    failures = []

    # Simulation duration needs to be long enough to find flashing bits
    max_periods = THRESHOLD + 10 

    for period in range(max_periods):
        bit_state ^= 1  # toggles every flash period

        # Send flashing bit in first cyle of this period for each ETROC word
        pattern = 0
        if bit_state == 1:
            for i in range(num_links):
                pattern |= (1 << (i * etroc_width))

        dut.uplink_data_i.value = pattern
        await RisingEdge(dut.clk_i)

        # Send all 0's for rest of period
        dut.uplink_data_i.value = 0
        for _ in range(FLASH_PERIOD - 1):
            if dut.trigger_o.value == 1:
                msg = f"[Test 1, Rate {rate}] FAILED: trigger_o was asserted unexpectedly at clock cycle {cocotb.utils.get_sim_time('ns')} ns"
                dut._log.error(msg)
                failures.append(msg)
            await RisingEdge(dut.clk_i)

    # Final check
    if dut.trigger_o.value == 1:
        msg = f"[Test 1, Rate {rate}] FAILED: trigger_o was asserted at end of test."
        dut._log.error(msg)
        failures.append(msg)
    else:
        dut._log.info(f"[Test 1, Rate {rate}] PASSED: trigger_o correctly remained low.")

    return failures


async def run_trigger_test(dut, rate):
    """
    Test 2: Puts a continuous flashing bit at a random index and injects hits
    every 6000 cycles. Checks that trigger_o is 1 for hits and prints final counts.
    """
    UPLINK_WIDTH = dut.UPLINK_WIDTH.value.integer
    FLASH_PERIOD = dut.FLASH_PERIOD.value.integer
    NUM_ETROCS = dut.NUM_ETROCS.value.integer
    INTEGER_WIDTH = 8
    HIT_INTERVAL = 6000
    NUM_HITS = 40
    TOTAL_CYCLES = HIT_INTERVAL * (NUM_HITS + 1) 

    dut._log.info(f"[Test 2, Rate {rate}] Starting trigger generation test.")
    await reset_dut(dut)

    # Configure initial DUT values
    dut.rate_i.value = rate
    dut.enable_i.value = (1 << UPLINK_WIDTH) - 1
    dut.slip_i.value = 0
    
    failures = []
    trigger_count = 0
    
    # Define ETROC parameters based on the rate
    etroc_width = 8 * (2**rate)
    num_links = UPLINK_WIDTH // etroc_width

    # Choose one random bit for each ETROC word to be the flashing bit
    flashing_bit_positions = []
    for i in range(num_links):
        # random_offset is a position within the ETROC word (e.g., 0 to 7 for rate 0)
        # random_offset = random.randint(0, etroc_width - 1)
        random_offset = 0
        # Calculate the absolute position in the 224-bit uplink vector
        absolute_pos = (i * etroc_width) + random_offset
        flashing_bit_positions.append(absolute_pos)

    dut._log.info(f"[Test 2, Rate {rate}] Using the following bits as continuous flashing bits: {flashing_bit_positions}")


    for cycle in range(TOTAL_CYCLES):
        # Toggle the flashing bits at the start of a flash period
        flashing_pattern = 0
        if cycle % FLASH_PERIOD == 0:
            for pos in flashing_bit_positions:
                flashing_pattern |= (1 << pos)
        
        # Create the hit pattern based on hit interval
        hit_pattern = 0
        if cycle > 0 and cycle % HIT_INTERVAL == 0:
            hit_position = random.randint(0, UPLINK_WIDTH - 1)
            # Check hit is not a flashing bit 
            while hit_position in flashing_bit_positions:
                hit_position = random.randint(0, UPLINK_WIDTH - 1)
            hit_pattern = 1 << hit_position
            dut._log.info(f"[Test 2, Rate {rate}] Injecting hit at cycle {cycle}, position {hit_position}.")

            dut._log.info("--- DEBUG INFO ---")
            dut._log.info(f"active_o = 0x{dut.active_o.value.hexstring()}")
            dut._log.info("--------------------")

        # Combine patterns and drive the input
        dut.uplink_data_i.value = flashing_pattern | hit_pattern
        
        await RisingEdge(dut.clk_i)
        
        if dut.trigger_o.value == 1:
            trigger_count += 1
            dut._log.info(f"[Test 2, Rate {rate}] Trigger detected at clock cycle {cycle + 1}!")

    # Log the final counter values
    full_counts_vector = dut.cnts_o.value
    final_counts = []

    dut._log.info("--- DEBUG INFO ---")
    dut._log.info(f"Actual length of dut.cnts_o.value from simulator: {len(full_counts_vector)}")
    dut._log.info(f"Loop is configured to run {NUM_ETROCS} times.")
    dut._log.info("--------------------")

    for i in range(NUM_ETROCS):
        low_bit = i * INTEGER_WIDTH
        
        # Manually build the 8-bit string for the current counter
        current_count_str = ""
        for j in range(INTEGER_WIDTH):
            # Prepend the bit to get the correct order (MSB on the left)
            current_count_str = full_counts_vector[low_bit + j].binstr + current_count_str
        
        # Convert the manually built string to an integer
        final_counts.append(int(current_count_str, 2))

    dut._log.info(f"[Test 2, Rate {rate}] Final counter values (cnts_o): {final_counts}")

    # Verify a trigger output for each hit sent
    if trigger_count < NUM_HITS - 1 : # Allow for some margin of error
        msg = f"[Test 2, Rate {rate}] FAILED: Expected ~{NUM_HITS} triggers, but only got {trigger_count}."
        dut._log.error(msg)
        failures.append(msg)
    else:
        dut._log.info(f"[Test 2, Rate {rate}] PASSED: Trigger test completed with {trigger_count} triggers.")

    return failures


@cocotb.test()
async def self_trig_tb(dut):
    """Main test function for that runs both tests for all possible rates"""
    cocotb.start_soon(Clock(dut.clk_i, 10, units="ns").start())
    all_failures = []

    for rate in [0, 1, 2]:
        # --- Run Test 1 ---
        failures_t1 = await run_no_trigger_test(dut, rate)
        all_failures.extend(failures_t1)

        # --- Run Test 2 ---
        failures_t2 = await run_trigger_test(dut, rate)
        all_failures.extend(failures_t2)

    # Check if any failures occurred across all tests
    if all_failures:
        raise cocotb.result.TestFailure(
            f"{len(all_failures)} failure(s) detected:\n" + "\n".join(all_failures)
        )
    else:
        dut._log.info("All tests for all rates passed successfully! 🎉")


def test_self_trig():
    """Sets up cocotb to run the self_trig module test"""
    os.environ.setdefault("SIM", "ghdl")
    os.environ.setdefault("GHDL_FLAGS", "--std=08")

    here = os.path.abspath(os.path.dirname(__file__))
    rtl_dir = os.path.join(here, "..", "hdl")

    vhdl_sources = [
        os.path.join(rtl_dir, "def_pkg.vhd"),
        os.path.join(rtl_dir, "Top.vhd"),
        os.path.join(rtl_dir, "trigger_rx.vhd"),
        os.path.join(rtl_dir, "flash.vhd"),
        os.path.join(rtl_dir, "bitslip.vhd"),
        os.path.join(rtl_dir, "rate_counter.vhd") 
    ]
    
    # Override, especially for the rate_counter generic to update every 10,000 cycles instead of ~40 million
    generics = {
        "g_CLK_FREQUENCY" : 10000 
    }

    run(
        vhdl_sources=vhdl_sources,
        toplevel="self_trig",
        toplevel_lang="vhdl",
        module=os.path.splitext(os.path.basename(__file__))[0],
        generics=generics,
        waves=True,
        gui=0,
        extra_env={
            "COCOTB_LOG_FILE": "stdout",
        },
    )

if __name__ == "__main__":
    import pytest, sys
    sys.exit(pytest.main(sys.argv[1:] + [__file__]))
