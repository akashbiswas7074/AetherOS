# AnantaOS (आकाश)

> **A Declarative, Content-Addressed Microkernel Operating System & Universal Multi-ABI Runtime**
> 
> 📄 **Academic Research Paper Available:** [Read Full Research Paper (RESEARCH_PAPER.md)](RESEARCH_PAPER.md)

**AnantaOS** (named after *Akash* / आकाश — the Sanskrit concept for *Cosmic Space / Aether*, the primordial fifth element of the Indian *Pancha Mahabhuta*) is an experimental operating system built from the ground up in **Rust** and **x86_64 Assembly**. It explores alternatives to traditional monolithic Unix kernels by combining a capability-based microkernel design, a cryptographic content-addressable storage engine (**CasFS**), an append-only **Blockchain Audit Ledger**, and a universal multi-binary compatibility layer (**Multi-ABI**).


---

## 1. Languages Used Across the System

AnantaOS utilizes specific languages tailored to the requirements of each system layer:

| Layer | Language | Purpose & Codebase Location |
| :--- | :--- | :--- |
| **Microkernel & Core Modules** | **Rust (`no_std`)** | High memory safety, zero-cost abstractions, lock-free concurrency in [`kernel/`](kernel/) |
| **Storage Engine (CasFS)** | **Rust** | BLAKE3 cryptographic hashing, HAMT (Hash Array Mapped Trie) Merkle trees in [`casfs/`](casfs/) |
| **System State & Profiles** | **Rust** | Pure declarative system flakes and configuration tracking in [`manifest/`](manifest/) |
| **Compatibility Layer (Multi-ABI)** | **Rust** | Syscall translation and ELF/PE execution runtimes in [`compat/`](compat/) |
| **Bootloader & Real Mode** | **x86 / x86_64 Assembly (NASM)** | MBR 512-byte boot sector, switching from 16-bit Real Mode to Protected Mode in [`boot/boot.asm`](boot/boot.asm) and [`kernel/kernel_gui.asm`](kernel/kernel_gui.asm) |
| **User Applications** | **C / C++** | Upstream applications such as GNU nano 8.0, GCC, and NCURSES running on the ABI |
| **Toolchain & Environment** | **Nix** | Deterministic and reproducible build tooling in [`shell.nix`](shell.nix) |
| **Build Automation & Scripts** | **Make / Bash** | Build scripts and QEMU execution targets in [`Makefile`](Makefile) and [`run.sh`](run.sh) |

---

## 2. How AnantaOS Differs from Traditional OSes

| Feature | Traditional Linux (Ubuntu / Debian) | Alpine Linux | AnantaOS |
| :--- | :--- | :--- | :--- |
| **Kernel Architecture** | Monolithic (drivers, storage, network all inside kernel space) | Monolithic | **Declarative Microkernel Design** (isolated core with user-space services) |
| **Filesystem Model** | Inode-based block filesystems (ext4, XFS, Btrfs) | Inode-based (ext4) | **CasFS (Content-Addressable Storage Engine)** indexed by cryptographic **BLAKE3 hashes** |
| **Deduplication & Integrity** | Optional filesystem extensions or none | None by default | **Automatic BLAKE3 HAMT Merkle verification** on every block extent |
| **Binary Compatibility** | Strictly native Linux ELF | Strictly musl ELF | **Universal Multi-ABI** (executes Linux ELF64, Windows PE32+, and Mach-O) |
| **System Configuration** | Mutable `/etc/` files modified imperatively | Mutable OpenRC runlevels | **Declarative Manifests & Flakes** (pure, reproducible state with cryptographic rollback) |
| **Safety Guarantees** | Written in C (susceptible to memory leaks and buffer overflows) | Written in C | Built in **Rust** for compile-time memory and concurrency safety |

---

## 3. Key Architectural Innovations

### 1. CasFS (Content-Addressable Storage)
Traditional operating systems locate data by path and inode numbers (e.g., `/home/user/file.txt` points to inode `142051`). 
In **CasFS**:
- All blocks are named by their cryptographic **BLAKE3 hash** (256-bit digest).
- If two files share identical content, they automatically share the exact same physical block.
- Filesystem snapshots are immutable Merkle roots, allowing instant time-travel rollbacks without data duplication.

### 2. Universal Multi-ABI Runtime
Rather than locking the OS to a single operating system standard:
- The [`compat/`](compat/) engine parses file headers (`ELF`, `PE`, `Mach-O`).
- Syscalls are translated into microkernel capability IPC messages, allowing diverse binary formats to run side-by-side.

### 3. Memory Safety via Rust
By building the core kernel and storage engine in **Rust**:
- Null pointer dereferences, data races across threads, and buffer overflows are eliminated at compile time.
- Assembly is restricted only to hardware bootstrapping where direct CPU register control is strictly mandatory.

### 4. Blockchain-Grade Security Subsystem
AnantaOS brings blockchain cryptography directly into kernel and userspace security:
- **Immutable Audit Ledger**: Critical security events (file creations, folder Merkle updates, privilege delegations, logins) are committed into an append-only Merkle-linked blockchain hash-chain, defeating anti-forensics attacks.
- **Anti-Supply-Chain Attestation**: Downloaded packages are cryptographically verified against a decentralized consensus hash registry before execution, preventing malicious backdoor injection.
- **Zero-Trust Capability Tokens**: Eliminates monolithic `root` and `sudo` vulnerabilities. Permissions are granted via cryptographically signed capability tokens with microsecond granularity and automatic expiration.
- **Measured Boot PCR Chain**: Cumulative cryptographic measurement across BIOS, MBR, bare-metal kernel, and driver manifests to detect bootkits and unauthorized disk tampering.

---

## 4. Blockchain-Secured Filesystem (CasFS)

Every file and directory created or modified in AnantaOS is **automatically sealed into an append-only cryptographic Merkle blockchain ledger**.

### File & Folder Blockchain Protection Flow Chart

| Step # | Stage | Trigger / Action | Technical Mechanism | Blockchain Security Result |
|:---:|:---|:---|:---|:---|
| **1** | **Creation Event** | User or app executes `mkdir <folder>` or `touch <file>` | Captured via shell hook or background `casfs-daemon` watcher | Triggers cryptographic processing before disk write finishes |
| **2** | **Fingerprinting** | Read payload bytes of the file | Computes **BLAKE3 (256-bit)** content hash: `H = BLAKE3(Data)` | Unique cryptographic fingerprint; even a 1-bit change creates a completely different hash |
| **3** | **Deduplication** | Check if hash exists in HAMT trie | $\mathcal{O}(1)$ Content-Address lookup in memory trie | If file exists, reference is reused (zero extra disk blocks allocated) |
| **4** | **Folder Merkle Tree** | For directories: gather all children hashes | Aggregates child hashes into a Merkle node: `Root = BLAKE3(H1 \|\| H2 \|\| ...)` | Protects entire folder structure; adding/deleting any file alters the folder root |
| **5** | **Event Packaging** | Format audit transaction | `FileCommitted:<path>:<hash>` or `FolderCommitted:<dir>:<root>` | Bundles timestamp, path, actor, and content hash into an immutable payload |
| **6** | **Block Sealing** | Chain into the blockchain | `New_Hash = BLAKE3(Prev_Block_Hash \|\| Payload \|\| Height)` | Cryptographically links the new block to the genesis chain |
| **7** | **Tamper Verification** | User or security tool runs `casfs verify <path>` | Compares current disk hash against sealed blockchain block | **PASS**: File/folder matches.<br>**ALERT**: Flagged if altered by malware/tampering |

### Visual Block Architecture Chart

```
[ Your Files & Folders ]
       │
       ▼
 ┌─────────────────────────────────────────────────────────┐
 │                   STEP 1: HASHING                       │
 │  file1.txt   ──►  BLAKE3 Hash: 40a729a29...             │
 │  file2.c     ──►  BLAKE3 Hash: e3b0c4429...             │
 └────────────────────────────┬────────────────────────────┘
                              │
                              ▼
 ┌─────────────────────────────────────────────────────────┐
 │               STEP 2: FOLDER MERKLE TREE                │
 │  my_folder/  ──►  BLAKE3( 40a729... + e3b0c4... )       │
 │                   Merkle Root: bda10362f...             │
 └────────────────────────────┬────────────────────────────┘
                              │
                              ▼
 ┌─────────────────────────────────────────────────────────┐
 │              STEP 3: BLOCKCHAIN AUDIT LEDGER            │
 │                                                         │
 │  ┌─────────────────┐       ┌─────────────────┐          │
 │  │    BLOCK #1     │       │    BLOCK #2     │          │
 │  ├─────────────────┤       ├─────────────────┤          │
 │  │ Prev: Genesis   │       │ Prev: Block #1  │          │
 │  │ File: flake.nix │──────►│ Folder: my_proj │──► ...   │
 │  │ Hash: 98558f... │       │ Hash: bda103... │          │
 │  └─────────────────┘       └─────────────────┘          │
 │                                                         │
 │   Chain File: /var/lib/ananta/casfs/ledger/chain        │
 └─────────────────────────────────────────────────────────┘
```

### CasFS CLI Commands

| Command | Action |
|:---|:---|
| `casfs commit <file_or_dir>` | Computes BLAKE3 hash, registers extent deduplication, and seals into the next blockchain audit block |
| `casfs verify <file_or_dir>` | Cryptographic tamper check against sealed blockchain block (returns PASS or TAMPER ALERT) |
| `casfs audit` | Inspects full blockchain audit ledger, block heights, and block hashes |
| `casfs status` | Displays HAMT Merkle-trie indexing status, stored object count, and blockchain height |
| `casfs auto-secure start` | Starts background watcher daemon (`casfs-daemon`) to auto-secure all newly created files & folders |

---

## 5. Protection from Hackers & Threats

AnantaOS incorporates **Zero-Trust Microkernel Architecture** and **Cryptographic Defense-in-Depth** to neutralize modern hacker tactics.

### Hacker Threat vs. AnantaOS Defense Matrix

| Hacker Attack Type | How Hackers Attack Normal OS (Linux/Windows) | How AnantaOS Stops the Hacker | Built-in Ananta Defense |
|:---|:---|:---|:---|
| **Ransomware / File Encryption** | Silently encrypts files and overwrites blocks on disk | Encrypted files trigger an immediate hash mismatch; previous versions are preserved in immutable CasFS blocks | **CasFS + Merkle Tree Verification** |
| **Rootkits & Kernel Tampering** | Injects malicious code into bootloader or kernel drivers | Cryptographic PCR measured boot chain validates stage fingerprints before execution | **Measured Boot Chain (TPM/PCR)** |
| **Privilege Escalation** | Exploit bugs to gain ambient `root` (UID 0) and take over everything | AnantaOS eliminates ambient root; processes require explicit unforgeable capability tokens | **Zero-Trust Capability Tokens** |
| **Anti-Forensics / Deleting Logs** | Hackers delete `/var/log` to erase evidence of intrusion | Logs are chained into an append-only cryptographic blockchain ledger; altering or deleting a line invalidates the whole chain | **Immutable Audit Blockchain** |
| **Supply Chain Malware** | Inject malicious dependencies or corrupted packages | Every package requires multi-signature cryptographic provenance before loading | **Anti-Supply Chain Verification** |
| **Zero-Day System Corruption** | System files or configurations corrupted by an exploit | Instant $\mathcal{O}(1)$ rollback reverts kernel, drivers, and user space to a clean generation | **Declarative Flake Rollback** |

### The 5 Security Defense Layers

```
   [ LAYER 5: ATOMIC RECOVERY ]
   └── Instant O(1) Rollback (ananta-rebuild rollback) reverts any infected state
             ▲
   [ LAYER 4: TAMPER DETECTION ]
   └── CasFS Blockchain continuously seals & verifies file & directory Merkle trees
             ▲
   [ LAYER 3: ANTI-FORENSIC AUDIT ]
   └── Append-only cryptographic ledger permanently logs all hacker activity
             ▲
   [ LAYER 2: ZERO-TRUST CAPABILITY ]
   └── No root superpowers; fine-grained cryptographic tokens for each action
             ▲
   [ LAYER 1: MEASURED BOOT CHAIN ]
   └── Hardware-level PCR hashes ensure the microkernel hasn't been modified
```

---

## 6. Linux-like Declarative System Generations

AnantaOS includes native generation management inspired by NixOS, backed by microkernel Merkle-tree state attestations:

| Command | Action |
|:---|:---|
| `ananta-rebuild list` (or `flake list`) | Displays all system generations, timestamps, Merkle root hashes, and the current active generation |
| `ananta-rebuild switch` (or `flake switch`) | Evaluates `/etc/flake.nix`, registers kernel drivers, seals a new generation attestation block, and switches live |
| `ananta-rebuild rollback` (or `flake rollback`) | Instant **$\mathcal{O}(1)$ rollback** reverting the active pointer to the previous known good generation |



---

---

## 7. System Architecture

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
|               AnantaOS Microkernel & Core Subsystems                  |
|  - Physical Frame Allocator (mm/)     - Zero-Copy Ring Buffer IPC     |
|  - CasFS Engine (BLAKE3 + HAMT)       - Declarative Flake Manifest    |
|  - x86_64 CPU Context Switcher        - VirtIO Block & Net Drivers    |
+-----------------------------------+-----------------------------------+
                                    | Hardware Abstraction
                                    v
+-----------------------------------------------------------------------+
|                  Bare Metal x86_64 / QEMU VirtIO                      |
+-----------------------------------------------------------------------+
```

---

## 8. How AnantaOS is Built ("How to Make It")

Building AnantaOS consists of a 4-phase compilation and disk generation pipeline:

```mermaid
flowchart TD
    subgraph Phase1 ["1. Toolchain & Sandboxing"]
        A["shell.nix"] -->|"nix-shell"| B["Hermetic Toolchain (rustc, nasm, qemu, make)"]
    end

    subgraph Phase2 ["2. Source Compilation"]
        B --> C["nasm -f bin boot/boot.asm"]
        B --> D["cargo build --package ananta-kernel"]
        B --> E["cargo test --package casfs --package ananta-compat"]
        C --> F["boot.bin (512-byte MBR)"]
        D --> G["ananta-kernel (ELF64 / Kernel Binary)"]
    end

    subgraph Phase3 ["3. Virtual Disk Assembly"]
        F & G --> H["Partitioning & Formatting (qemu-img, ext4)"]
        H --> I["Deploying Kernel & EXTLINUX to /dev/vda1"]
        H --> J["Deploying Root Filesystem to /dev/vda3"]
        I & J --> K["build/ananta-linux.qcow2 (4 GB Persistent Disk)"]
    end

    subgraph Phase4 ["4. Execution & Verification"]
        K --> L["./run.sh -> QEMU VirtIO Hardware Virtualization"]
    end
```

### Build Steps:
1. **Bootloader Generation**:
   ```bash
   nasm -f bin boot/boot.asm -o boot/boot.bin
   ```
   Generates the master boot record that initializes CPU segments, clears interrupts, and loads the kernel payload into memory.

2. **Microkernel & Storage Engine Build**:
   ```bash
   cargo build --package ananta-kernel --target x86_64-unknown-none
   cargo test --package casfs --package ananta-manifest --package ananta-compat --package ananta-security
   ```
   Builds the Rust kernel without the standard library (`no_std`), targeting bare-metal x86_64.

3. **Disk Image Packaging**:
   - Creates a 4 GB grow-on-demand virtual disk (`qcow2`).
   - Formats boot and root partitions (`ext4`).
   - Configures the bootloader (`extlinux.conf`) with AnantaOS kernel parameters.

4. **Booting**:
   ```bash
   ./run.sh
   ```
   Launches QEMU with VirtIO storage, NAT networking, and standard VGA display.

---

## 9. Codebase Organization

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
├── security/                   # Blockchain-Grade Security Subsystem
│   └── src/
│       ├── ledger.rs           # Immutable audit blockchain & Merkle blocks
│       ├── attestation.rs      # Measured boot PCRs & anti-supply-chain checks
│       └── token.rs            # Zero-trust cryptographic capability tokens
├── shell.nix                   # Hermetic, reproducible Nix development environment
├── Makefile                    # Build orchestration
└── run.sh                      # One-click launch script
```

---

## 10. Getting Started

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

# Run unit tests across CasFS, Manifests, Security, and Multi-ABI
make test

# Build the bootable disk image
make build-image
```

---

## 11. Running AnantaOS

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
To boot the pure assembly protected-mode kernel from the floppy disk image (`ananta.img`):

```bash
make run-vm
```

### 3. Installing & Running Windows Applications (.exe / .msi)

AnantaOS features a **Universal Multi-ABI Subsystem** (`compat/src/windows_abi.rs`), enabling execution of Windows PE binaries directly.

#### Step 1: Pre-installed Windows Runtime & Apps
Wine 9.0 and pre-installed Windows applications are pre-configured inside `build/ananta-linux.qcow2`:
- **PuTTY (`putty.exe`)**: Located at `/opt/windows_apps/putty.exe` and `C:\Program Files\PuTTY\`
- **Windows Built-in Tools**: `winapp notepad`, `winapp cmd`, `winapp explorer`, `winapp regedit`

#### Step 2: Running Any Windows Application (.exe / .msi)
```bash
# Launch pre-installed Windows application:
winapp /opt/windows_apps/putty.exe

# Or run any custom Windows installer:
winapp setup.exe
```

All files created by Windows apps are automatically fingerprinted by **BLAKE3** and sealed into the **Blockchain Audit Ledger** via `casfs-daemon`.

---

### 4. Running Apple macOS Applications (Mach-O / .app Bundles)

AnantaOS features native **macOS Darwin Mach-O Subsystem** (`compat/src/macos_abi.rs`), allowing execution of 64-bit Mach-O binaries and `.app` bundles directly.

#### Step 1: Pre-installed macOS Apps
- **Mach-O 64-bit Binary**: `/opt/mac_apps/hello_darwin.macho` (Header `0xFEEDFACF`)
- **macOS App Bundle**: `/opt/mac_apps/Calculator.app` (`Contents/MacOS/Calculator` + `Info.plist`)

#### Step 2: Running macOS Applications
Use the native `macapp` (or `ananta-macapp`) launcher:

```bash
# Run 64-bit Mach-O binary:
macapp /opt/mac_apps/hello_darwin.macho

# Run complete macOS .app bundle:
macapp /opt/mac_apps/Calculator.app
```

Whenever a macOS binary or bundle is executed, `macapp` automatically commits its cryptographic Merkle tree into the **Blockchain Audit Ledger** and verifies its integrity before execution.

---

### 5. Run the Architecture Simulator & Tests
To verify CasFS deduplication, blockchain audit integrity, and test the declarative state pipeline:

```bash
make sim
```


---

## 12. Verification & Testing

The test suite validates:
1. **BLAKE3 Hash Correctness**: Validated against standard test vectors.
2. **HAMT Collision Handling**: Merkle tree insertion, retrieval, and edge-case collisions.
3. **CasFS Deduplication**: Ensures zero redundant storage when identical extents are committed.
4. **Folder Merkle Trees**: Computes hierarchical directory hashes and detects tampering.
5. **Blockchain Audit Ledger**: Verifies chain continuity and tamper-evident blocks.
6. **Binary Format Detection**: Validates ELF, PE, and Mach-O header parsing.
7. **System Flake Generations**: Validates atomic $O(1)$ rollback and generation switching.

Run all checks:
```bash
make check
make test
```

---

## 13. License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

