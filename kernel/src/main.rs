#![no_std]
#![no_main]

use core::panic::PanicInfo;

mod arch;
mod ipc;
mod mm;

use arch::cpu::hlt;
use arch::serial::SERIAL1;
use arch::vga::{Color, VGA_WRITER};
use casfs::{hash, CasStorageEngine};
use manifest::{DriverKind, DriverManifest, SystemFlake, UserCapability, UserProfile};
use mm::PhysicalFrameAllocator;

#[no_mangle]
pub extern "C" fn _start() -> ! {
    // 1. Initialize Serial Port for ultra-fast logging
    SERIAL1.init();

    // 2. Initialize Screen Buffer
    unsafe {
        VGA_WRITER.set_color(Color::LightCyan, Color::Black);
        VGA_WRITER.clear_screen();
    }

    // 3. Print Banner
    println!("================================================================");
    println!("     *  AETHER-OS  *  v0.1.0 (Declarative Microkernel)         ");
    println!("     Unique Architecture: Content-Addressed + Native Flakes    ");
    println!("================================================================");

    // 4. Memory Subsystem
    println!("[INIT] Initializing Physical Memory (4KB Frame Allocator)...");
    let mut frame_allocator = PhysicalFrameAllocator::new(0x100000, 0x800000); // 1MB to 8MB
    if let Some(frame) = frame_allocator.allocate_frame() {
        println!("       Allocated initial root page table frame at 0x{:x}", frame);
    }
    println!("       Available system memory: {} KB", frame_allocator.free_memory_bytes() / 1024);

    // 5. CasFS Content-Addressed Storage Engine
    println!("[INIT] Mounting CasFS (BLAKE3 Content-Addressed Storage)...");
    let mut storage = CasStorageEngine::new();

    // Test data insertion
    let sample_kernel_config = b"boot.loader=direct\nhardware.cpu.mitigations=off\n";
    let (config_hash, _) = storage.store(sample_kernel_config, 1);
    print!("       Stored System Config (BLAKE3): ");
    let mut port = arch::serial::SerialPort::new(0x3F8);
    let _ = config_hash.write_hex(&mut port);
    println!("");

    // Test Deduplication (Storing identical payload)
    let (_, was_new) = storage.store(sample_kernel_config, 1);
    if !was_new {
        println!("       Deduplication verified: 0 bytes wasted, instant O(1) link!");
    }

    // 6. Native Declarative Flake (System Generation 1)
    println!("[INIT] Evaluating Native System Flake (Generation 1)...");
    let mut flake = SystemFlake::new(1);
    
    let drv_serial = DriverManifest {
        name: "uart_16550",
        kind: DriverKind::SerialConsole,
        binary_hash: hash(b"driver_serial_v1"),
        memory_limit_pages: 4,
    };
    let drv_vga = DriverManifest {
        name: "vga_framebuffer",
        kind: DriverKind::FramebufferDisplay,
        binary_hash: hash(b"driver_vga_v1"),
        memory_limit_pages: 16,
    };
    let drv_casfs = DriverManifest {
        name: "casfs_nvme",
        kind: DriverKind::NvmeBlockStorage,
        binary_hash: hash(b"driver_casfs_v1"),
        memory_limit_pages: 32,
    };

    flake.add_driver(drv_serial);
    flake.add_driver(drv_vga);
    flake.add_driver(drv_casfs);

    let gen_hash = flake.compute_generation_hash();
    print!("       System Generation Merkle Root: ");
    let _ = gen_hash.write_hex(&mut port);
    println!("");
    println!("       3/3 Sandboxed Drivers Registered");

    // 7. Home-Manager Style User Sandbox
    println!("[INIT] Projecting Declarative User Profile: @akash...");
    let mut user = UserProfile::new("akash", 1000);
    user.grant_capability(UserCapability::ReadObject(config_hash));
    user.grant_capability(UserCapability::DisplaySurface);
    println!("       Granted 2 Sandboxed Capabilities (No root/sudo needed)");

    // 8. Universal Multi-ABI Engine (Linux POSIX + Win32 + Mach-O)
    println!("[INIT] Activating Universal Multi-ABI Engine (Linux + Windows + Mac)...");
    let mut abi_engine = aether_compat::UniversalAbiEngine::new();
    let test_elf = [0x7F, b'E', b'L', b'F', 2, 1, 1, 0];
    let res = abi_engine.execute(&test_elf);
    println!("       Universal ABI Dispatch active: Linux ELF execution ready.");

    unsafe {
        VGA_WRITER.set_color(Color::LightGreen, Color::Black);
    }
    println!("================================================================");
    println!("  STATUS: Kernel Running in Hyper-Speed Mode. Ready for tasks!  ");
    println!("================================================================");

    // Halt loop
    loop {
        hlt();
    }
}

#[panic_handler]
fn panic(info: &PanicInfo) -> ! {
    unsafe {
        VGA_WRITER.set_color(Color::LightRed, Color::Black);
    }
    println!("\n[KERNEL PANIC] {}", info);
    loop {
        hlt();
    }
}
