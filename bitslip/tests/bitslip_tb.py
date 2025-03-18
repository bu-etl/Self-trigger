'''
Author: Naomi Gonzalez
Descrition: Testbench to verify bitslip module works as expected
'''



import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge
import random

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
async def test_bitslip(dut):
    """Test the bitslip module."""

    # Start the clock
    cocotb.start_soon(Clock(dut.clk_i, 10, units="ns").start())

    # Initialize inputs to zeros
    dut.slip_cnt_i.value = 0
    dut.data_i.value = 0

    # Initialize prev_data
    prev_data = 0

    # Wait for three clock cycles to ensure signals are stable
    for _ in range(3):
        await RisingEdge(dut.clk_i)

    DATA_WIDTH = dut.g_DATA_WIDTH.value.integer
    TRANSMIT_LOW_TO_HIGH = dut.g_TRANSMIT_LOW_TO_HIGH.value

    # Prepare test data
    test_data = int('11010101010101010101010101010101', 2) & ((1 << DATA_WIDTH) - 1)

    failures = []

    # Function to perform a single test case
    async def run_test(slip_count, data_input):
        nonlocal prev_data

        dut.slip_cnt_i.value = slip_count
        dut.data_i.value = data_input

        # Capture current and previous data_i values
        current_data_i = data_input
        current_prev_data = prev_data  # prev_data before it's updated

        await RisingEdge(dut.clk_i)  # prev_data <= data_i
        prev_data = current_data_i  # Update prev_data after clock edge

        await RisingEdge(dut.clk_i)  # data_o is updated based on previous prev_data

        expected_output = calculate_expected_output(
            current_data_i, current_prev_data, slip_count, DATA_WIDTH, TRANSMIT_LOW_TO_HIGH
        )
        actual_output = dut.data_o.value.integer

        if actual_output != expected_output:
            error_message = (
                f"Test failed for slip count {slip_count}.\n"
                f"Data Input: {bin(current_data_i)}\n"
                f"Prev Data: {bin(current_prev_data)}\n"
                f"Expected: {bin(expected_output)}\n"
                f"Got: {bin(actual_output)}"
            )
            cocotb.log.error(error_message)
            failures.append(error_message)
        else:
            success_message = (
                f"Test passed for slip count {slip_count}.\n"
                f"Data Input: {bin(current_data_i)}\n"
                f"Prev Data: {bin(current_prev_data)}\n"
                f"Output: {bin(actual_output)}"
            )
            cocotb.log.info(success_message)

    # Test with slip counts of 0, 1, and 2
    for slip_count in [0, 1, 2]:
        await run_test(slip_count, test_data)

    # Perform random testing
    for _ in range(10):  # Adjust the number of random tests as needed
        random_slip_count = random.randint(0, DATA_WIDTH - 1)
        random_data = random.getrandbits(DATA_WIDTH)
        await run_test(random_slip_count, random_data)

    # Check if any failures occurred
    if failures:
        assert False, "Some tests failed. See error log for details."
    else:
        cocotb.log.info("All tests passed successfully.")

