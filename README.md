# Self-Trigger

This project is a self contained repo meant to design and test a self-trigger feature for the following larger FPGA project: [module_test_fw](https://gitlab.cern.ch/cms-etl-electronics/module_test_fw) which firmware is used to develop and test front-end electronics for the endcap regions of the new MIP Timing Detector for the CMS Experiment at CERN.

**Self-Trigger** is a VHDL design with _cocotb_ test-bench simulations that monitors the trigger uplink data of multiple ETROCs. It masks repeatedly occuring “flashing” bits coming from ETROC words and issues a Level-1 Accept (L1A) trigger whenever a real hit is observed.

It is meant as a compact, simulation-ready solution with:

| Area | Information |
|------|-------------------|
| **FPGA design** | per ETROC hit rate counters and configurable bit-slipping, Multi-rate data path (320 / 640 / 1280 Mbit s⁻¹)|
| **Verification** | Python-driven _cocotb_ tests, self-checking scoreboards, parameter scan, randomised stimulus input|
| **Continuous Integration** | One-command `pytest` launches GHDL + _cocotb_ simulations for every HDL unit |

---

## Table of Contents
1. [Folder Structure](#folder-structure)  
2. [Quick Start](#quick-start)  
3. [Design Overview](#design-overview)  
4. [Simulation & Tests](#simulation--tests)  
7. [Acknowledgements](#acknowledgements)  

---

## Folder Structure

```

self-trigger/
├── README.md              
├── pytest.ini             ← pytest settings
├── requirements.txt       ← Python dependencies 
└── src
    ├── hdl                    ← VHDL RTL
    │   ├── Top.vhd            ← Top-level wrapper (instantiates `self_trig`)
    │   ├── bitslip.vhd        ← bit-slipper
    │   ├── def_pkg.vhd        ← Types & constants for simulation
    │   ├── flash.vhd          ← Flashing-bit detector / clearer
    │   ├── rate_counter.vhd
    │   └── trigger_rx.vhd     ← L1A generator w/ Hit rate counter + bitsliping and multi-rates
    └── tests                  ← Python simulation test-benches
        ├── test_Top.py
        ├── test_bitslip.py
        └── test_flashbit.py

````

> **Note:** All HDL files follow VHDL-2008 syntax; simmulation tests rely on **GHDL** to run.

---

## Quick Start

**Prerequisites**

| Tool    | Tested version(s)            |
| ------- | ---------------------------- |
| Python  | ≥ 3.9                        |
| GHDL    | 4.0-dev (LLVM or mcode)      |
| GTKWave | 3.3.x (for waveform viewing) |

> **Note:** GTKWave is optional

```bash
# 1. Clone the repo
git clone https://github.com/your-org/self-trigger.git
cd self-trigger

# 2. Set up a Python virtualenv (recommended but optional)
python -m venv .venv             # or use conda/mamba
source .venv/bin/activate
pip install -r requirements.txt  # installs cocotb, cocotb-test, pytest …

# 3. Run the complete simulation suite
pytest                           # will compile RTL with GHDL and run all cocotb tests

# 4. Inspect waveforms (optional)
#    Each test dumps a .ghw (GHDL wave) in the local directory
gtkwave *.ghw &
````

---

## Design Overview

### 1. Flash-bit Cleaner (`flash_bit.vhd`)

Detects the flashing bit which is a periodic **1 → 0 → 1 → 0** toggle every **`FLASH_PERIOD` = 3546** clock cycles, over any bit position within an ETROC word. After observing `THRESHOLD` successive toggles, the module:

* Sets `active_o = '1'`
* Forces the flashing bit to **0** on the output `data_o`

### 2. Trigger Receiver (`trigger_rx.vhd`)

* **Bitslip stage** – aligns data words by `slip_i` bits (one instance per ETROC & data-rate).
* **Enable mask** – only allows triggers from enabled ETROCs.
* **Reduction tree** – OR-reduces 8 / 16 / 32-bit chunks to detect any hit bit based on ETROC operaiton rate.
* **Rate counters** – per-ETROC hit rate (free-running up-counters).
* **Trigger output** – per single clock, synchronous L1A.

### 3. Top Level (`self_trig.vhd`)

Wire-up of:

1. Three-rate flash-bit detector array
2. An adaptive mask generator which only allows triggers from ETROCs while their flash-cleaner is active
3. The trigger receiver

Generics:

| Name           | Default | Meaning                              |
| -------------- | ------- | ------------------------------------ |
| `NUM_ETROCS`   | `28`    | Number of ETROC board                |
| `UPLINK_WIDTH` | `224`   | Total uplink bits (8 × NUM\_ETROCS)  |
| `FLASH_PERIOD` | `3546`  | Clock cycles for one flash toggle    |
| `THRESHOLD`    | `10`    | Toggles until cleaner becomes active |

---

## Simulation & Tests

### Description

| Test file                            | DUT             | Purpose                                                                          |
| ------------------------------------ | --------------- | -------------------------------------------------------------------------------- |
| `test_bitslip.py`                    | `bitslip.vhd`   | bit slip/edge cases + random input patterns                                     |
| `test_flashbit.py`                   | `flash_bit.vhd` | Searches every bit position, confirms clearing                                   |
| `test_Top.py` *(aka `self_trig_tb`)* | `self_trig.vhd` | System-level: • **Test1** zero-hit sanity • **Test2** periodic hits & trigger counting |

All tests share a 10 ns clock (`100 MHz`) in simulation.

### Customising the Simulation and RTL Design

1. **Change generics** – open `src/hdl/Top.vhdl`. Most widths & thresholds are top-level generics.
2. **Simulation‐only knobs** – environment variables in `tests/*.py` (`SIM`, `GHDL_FLAGS`, …).

---

## Acknowledgements

* **Naomi Gonzalez** – main testbench author and RTL design engineer
* **Evaldas Juska** – RTL design engineer for `rate_counter.vhd` and `bitslip.vhd`



