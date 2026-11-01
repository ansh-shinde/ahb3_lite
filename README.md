# AHB3 Lite Master

A Verilog-based implementation of an **AHB-Lite Master** featuring address generation, burst management, transfer-size validation, and read/write data handling.

## Project Overview

The design is organized into two main blocks:

- **Control Path:** Implements the FSM responsible for controlling AHB transactions and coordinating address and data phases.
- **Data Path:** Handles address generation, burst calculations, transfer-size validation, alignment checks, and read/write data operations.

## Features

- AHB-Lite master implementation
- Single and burst transfer support
- Incrementing and wrapping burst address generation
- Byte, halfword, and word transfer support
- Address alignment and transfer-size validation
- Read and write data handling
- FSM-based transaction control
- AHB-to-APB bridge integration

## Project Structure

```text
ahb3_lite/
│
├── rtl/
│   ├── ahb/
│   │   ├── top_ahb.v
│   │   ├── control_ahb.v
│   │   └── data_ahb.v
│   │
│   ├── bridge/
│   │
│   └── uart_interface/
│       ├── apb/
│       ├── rx/
│       └── tx/
│
├── tb/
│   ├── ahb_tb/
│   │   ├── single_trans/
│   │   ├── wrap/
│   │   └── incr/
│   │
│   └── ahb_uart/
│
└── README.md
```

## Verification Status

### 1. AHB Master
- Independently verified using simulation.
- Complete burst-transfer verification performed.
- Verified supported incrementing and wrapping burst types.
- Tested address generation, transfer sequencing, and data-phase handling.

### 2. AHB-to-APB Bridge
- Independently verified using simulation.

### 3. Integrated AHB-to-APB-to-UART System
- Verified the complete transaction path connecting the AHB master, AHB-to-APB bridge, and UART peripheral.
- Integrated verification performed using single transfers.
- Full-system burst-transfer verification is pending.

## Tools Used

- **HDL:** Verilog
- **Simulation:** Icarus Verilog
- **Waveform Analysis:** GTKWave

## Future Work

- Extend integrated verification to burst transfers.
- Validate incrementing and wrapping bursts across the complete system.
- Further test read/write transactions and peripheral integration.
