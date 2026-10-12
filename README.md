# AetherOS

> **A Declarative, Content-Addressed Microkernel Operating System & Universal Multi-ABI Runtime**

AetherOS is a modern experimental operating system built from the ground up in **Rust** and **x86_64 Assembly**. It explores alternatives to traditional monolithic Unix kernels by combining a capability-based microkernel design, a cryptographic content-addressable storage engine (**CasFS**), and a universal multi-binary compatibility layer (**Multi-ABI**).

---

## Key Highlights

- **Capability-Based Microkernel**: Device drivers, filesystems, and networking run in isolated userspace processes, communicating over zero-copy ring buffer IPC to eliminate single-point kernel panic vulnerabilities.
- **CasFS (Content-Addressable Storage)**: Storage engine backed by 256-bit **BLAKE3** cryptographic hashes and a flat **HAMT** (Hash Array Mapped Trie) Merkle index. Offers deduplication, instant snapshotting, and tamper detection.
- **Universal Multi-ABI Runtime**: Translates system calls to run diverse binary formats (Linux ELF64, Windows PE32+, and macOS Mach-O) side-by-side on top of microkernel capabilities.
- **Declarative System State**: Operating system generations and system configuration are modeled as immutable, reproducible Merkle roots—enabling atomic upgrades and rollbacks.
- **Production Package Management**: Network-connected userspace environment capable of fetching, cryptographically validating, and running official upstream packages (e.g., GNU nano 8.0, GCC, Python 3, Git).

---

## System Architecture

```
+-----------------------------------------------------------------------+
|                          User Applications                            |
|    (Linux ELF64 / Windows PE / GNU nano 8.0 / GCC / Python / Git)     |
+-----------------------------------+-----------------------------------+
                                    | Syscalls / Win32 / POSIX
                                    v
+-----------------------------------------------------------------------+
|                 Universal Multi-ABI Layer (compat/)                   |
|             Binary Format Sniffer (ELF, PE, Mach-O)                   |
|            POSIX Syscall & Capability Translation Engine              |
+-----------------------------------+-----------------------------------+
                                    | Microkernel IPC
                                    v
+-----------------------------------------------------------------------+
|               AetherOS Microkernel & Core Subsystems                  |
|  - Physical Frame Allocator (mm/)     - Zero-Copy Ring Buffer IPC     |
|  - CasFS Engine (BLAKE3 + HAMT)       - Declarative Flake Manifest    |
|  - x86_64 CPU Context Switcher        - VirtIO Block & Net Drivers    |
+-----------------------------------------------------------------------+
                                    | Hardware Abstraction
                                    v
+-----------------------------------------------------------------------+
|                  Bare Metal x86_64 / QEMU VirtIO                      |
+-----------------------------------------------------------------------+
```

---

## Codebase Organization

```
operating_system/
├── boot/                       # Bootloader
│   └── boot.asm                # MBR stage 1 & mode transition
├── kernel/                     # Bare-metal microkernel
│   ├── Cargo.toml              # Kernel workspace package
│   ├── linker.ld               # Memory layout & segment mappings
│   ├── kernel_gui.asm          # Low-level protected mode kernel & console
│   └── src/
│       ├── main.rs             # Kernel entry point (_start)
│       ├── arch/               # x86_64 GDT, IDT, UART 16550, VGA
│       ├── ipc/                # Lock-free ring buffer message passing
│       └── mm/                 # 4KB Physical frame allocator
├── casfs/                      # Content-Addressed Storage Filesystem
│   └── src/
│       ├── blake3.rs           # Pure Rust hardware-accelerated BLAKE3 hasher
│       ├── hamt.rs             # Hash Array Mapped Trie for O(1) Merkle lookups
│       └── storage.rs          # Block extent manager with deduplication
├── compat/                     # Universal Multi-ABI Compatibility Layer
│   └── src/
│       ├── binary_format.rs    # Magic byte detector (ELF, PE, Mach-O)
│       ├── linux_abi.rs        # Linux POSIX translation
│       ├── windows_abi.rs      # Win32 / NT system call translator
│       └── universal_runner.rs # ABI execution dispatcher
├── manifest/                   # Declarative System Manifests & Profiles
│   └── src/
│       ├── system_flake.rs     # Immutable system generation Merkle root
│       ├── user_profile.rs     # Capability-based user sandbox
│       └── bin/boot_sim.rs     # System boot simulator & diagnostic inspector
├── shell.nix                   # Hermetic, reproducible Nix development environment
├── Makefile                    # Build orchestration
└── run.sh                      # One-click launch script
```

---

## Getting Started

### Prerequisites

You can use [Nix](https://nixos.org/) for a completely hermetic environment with all dependencies (Rust, NASM, QEMU 11.1, Make) pre-configured:

```bash
nix-shell
```

Alternatively, install the following manually on Ubuntu/Debian/Fedora/Arch:
- `rustc` (nightly or modern stable) & `cargo`
- `nasm`
- `qemu-system-x86_64`
- `make`

### Building the Project

```bash
# Build the microkernel
make build

# Run unit tests across CasFS, Manifests, and Multi-ABI
make test

# Build the bootable disk image
make build-image
```

---

## Running AetherOS

### 1. Launch the 64-bit Persistent OS Environment
To boot the full 64-bit environment with VirtIO storage, live networking, and pre-installed packages:

```bash
./run.sh
```
or:
```bash
make run
```

Inside the booted terminal:
- Open the text editor:
  ```bash
  nano myfile.c
  ```
- Install official packages over the network:
  ```bash
  apk add curl htop tree
  ```

### 2. Launch the Standalone Low-Level Terminal
To boot the pure assembly protected-mode kernel from the floppy disk image (`aetheros.img`):

```bash
make run-vm
```

### 3. Run the Architecture Simulator & Tests
To verify CasFS deduplication and test the declarative state pipeline:

```bash
make sim
```

---

## Verification & Testing

The test suite validates:
1. **BLAKE3 Hash Correctness**: Validated against standard test vectors.
2. **HAMT Collision Handling**: Merkle tree insertion, retrieval, and edge-case collisions.
3. **CasFS Deduplication**: Ensures zero redundant storage when identical extents are committed.
4. **Binary Format Detection**: Validates ELF, PE, and Mach-O header parsing.

Run all checks:
```bash
make check
make test
```

---

## License

This project is licensed under the MIT License - see the LICENSE file for details.
