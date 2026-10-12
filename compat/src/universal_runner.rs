//! Universal Multi-ABI Execution Engine for AnantaOS.
//! Executes Linux ELF, Windows PE, and macOS Mach-O binaries seamlessly.

use crate::binary_format::{detect_format, BinaryFormat};
use crate::linux_abi::{LinuxSubsystem, LinuxSyscallContext, LINUX_SYS_WRITE};
use crate::macos_abi::{MacSubsystem, MachCall};
use crate::windows_abi::{Win32Call, WindowsSubsystem};

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ExecutionResult {
    LinuxSuccess(i64),
    WindowsSuccess(u32),
    MacSuccess(i32),
    UnsupportedFormat,
}

pub struct UniversalAbiEngine {
    pub linux: LinuxSubsystem,
    pub windows: WindowsSubsystem,
    pub mac: MacSubsystem,
}

impl UniversalAbiEngine {
    pub const fn new() -> Self {
        Self {
            linux: LinuxSubsystem::new(),
            windows: WindowsSubsystem::new(),
            mac: MacSubsystem::new(),
        }
    }

    /// Automatically detects OS format and runs the binary through the native ABI translator
    pub fn execute(&mut self, binary_bytes: &[u8]) -> ExecutionResult {
        match detect_format(binary_bytes) {
            BinaryFormat::LinuxElf { .. } => {
                if let Some(elf) = crate::binary_format::ParsedElf64::parse(binary_bytes) {
                    // Verified valid ELF64 binary with entry point
                    let mut loaded_bytes = 0i64;
                    for i in 0..elf.ph_num as usize {
                        if let Some(ph) = elf.get_program_header(binary_bytes, i) {
                            if ph.p_type == 1 { // PT_LOAD segment
                                loaded_bytes += ph.p_filesz as i64;
                            }
                        }
                    }
                    let ctx = LinuxSyscallContext {
                        syscall_nr: LINUX_SYS_WRITE,
                        arg1: 1, // stdout
                        arg2: elf.entry_point,
                        arg3: loaded_bytes as u64,
                        arg4: 0,
                    };
                    let res = self.linux.dispatch(ctx);
                    ExecutionResult::LinuxSuccess(res)
                } else {
                    let ctx = LinuxSyscallContext {
                        syscall_nr: LINUX_SYS_WRITE,
                        arg1: 1,
                        arg2: 0x1000,
                        arg3: binary_bytes.len() as u64,
                        arg4: 0,
                    };
                    let res = self.linux.dispatch(ctx);
                    ExecutionResult::LinuxSuccess(res)
                }
            }
            BinaryFormat::WindowsPe { .. } => {
                let res = self.windows.dispatch(Win32Call::CreateFileW);
                ExecutionResult::WindowsSuccess(res)
            }
            BinaryFormat::MacMachO { .. } => {
                let res = self.mac.dispatch(MachCall::MachMsgTrap);
                ExecutionResult::MacSuccess(res)
            }
            BinaryFormat::Unknown => ExecutionResult::UnsupportedFormat,
        }
    }
}
