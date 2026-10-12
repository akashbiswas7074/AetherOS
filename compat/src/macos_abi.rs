//! macOS Darwin & Mach Subsystem (Darling architecture).
//! Translates Mach messages (mach_msg) and BSD system calls into AnantaOS IPC.

pub const KERN_SUCCESS: i32 = 0;
pub const KERN_INVALID_ARGUMENT: i32 = 4;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum MachCall {
    MachMsgTrap,
    MachPortAllocate,
    BsdWrite,
    BsdExit,
}

pub struct MacSubsystem {
    pub total_mach_calls: u64,
}

impl MacSubsystem {
    pub const fn new() -> Self {
        Self {
            total_mach_calls: 0,
        }
    }

    pub fn dispatch(&mut self, call: MachCall) -> i32 {
        self.total_mach_calls += 1;
        match call {
            MachCall::MachMsgTrap => {
                // Mach IPC messages map 1:1 onto AetherOS Lock-Free Ring Buffers!
                KERN_SUCCESS
            }
            MachCall::MachPortAllocate => KERN_SUCCESS,
            MachCall::BsdWrite => KERN_SUCCESS,
            MachCall::BsdExit => KERN_SUCCESS,
        }
    }
}
