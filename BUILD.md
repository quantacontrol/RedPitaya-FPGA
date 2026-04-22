# Red Pitaya 125-14 Lock-in + PID

A minimal FPGA project for the Red Pitaya 125-14 board implementing a lock-in amplifier and PID controller.

## Repository Layout

```
RedPitaya-FPGA/
├── modeling/          # Algorithm RTL + cocotb simulations
│   ├── rtl/           # SystemVerilog modules (feedback controller, lock-in, PID)
│   └── cocotb/        # Algorithm-level simulation (Verilator)
├── rp_minimal/        # 125-14 hardware project (Vivado)
│   ├── src/           # Top-level RTL, constraints, block design TCL
│   ├── sim/           # Cocotb top-level simulation (Icarus)
│   ├── build.tcl      # Vivado batch build → bitstream
│   ├── build_fsbl_hsi.tcl
│   └── deploy.sh      # Deploy to board over SSH
├── rp_web/            # Web stack for board control
│   ├── backend/       # Rust HTTP server (cross-compiled for ARMv7)
│   └── frontend/      # React/TypeScript UI
├── xguo/              # Design docs and utility scripts
│   ├── architecture.md
│   ├── manual.md
│   └── scripts/       # detect_hw.tcl, inspect_xsa.tcl, recover_xsa.tcl
└── www/               # quantacontrol.com website (standalone Next.js project)
```

## Quick Start

```bash
# Simulate RTL (Icarus + cocotb, ~30s)
make sim

# Simulate algorithm only (Verilator + cocotb, ~1min)
make sim-algo

# Build bitstream (Vivado batch, ~5-10min)
make bitstream

# Build everything (bitstream + FSBL + dtbo + bit.bin)
make hw

# Build web stack
make web

# Deploy to board
make deploy IP=192.168.1.100
```

## Documentation

- [Architecture overview](xguo/architecture.md)
- [User manual](xguo/manual.md)

## Related Projects

Built and maintained by [Quanta Control](https://quantacontrol.com) — precision quantum measurement tools.
