#![no_std]

pub mod binary_format;
pub mod linux_abi;
pub mod macos_abi;
pub mod universal_runner;
pub mod windows_abi;

pub use binary_format::{detect_format, BinaryFormat};
pub use linux_abi::LinuxSubsystem;
pub use macos_abi::MacSubsystem;
pub use universal_runner::{ExecutionResult, UniversalAbiEngine};
pub use windows_abi::WindowsSubsystem;

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_detect_linux_elf() {
        // Minimal ELF header
        let elf_header = [0x7F, b'E', b'L', b'F', 2, 1, 1, 0];
        let format = detect_format(&elf_header);
        assert_eq!(format, BinaryFormat::LinuxElf { is_64_bit: true });
    }

    #[test]
    fn test_parse_real_elf64_headers() {
        let mut elf_bytes = [0u8; 120];
        elf_bytes[0..4].copy_from_slice(&[0x7F, b'E', b'L', b'F']);
        elf_bytes[4] = 2; // 64-bit
        elf_bytes[5] = 1; // Little endian
        // e_entry = 0x401000
        elf_bytes[24..32].copy_from_slice(&0x401000u64.to_le_bytes());
        // e_phoff = 64
        elf_bytes[32..40].copy_from_slice(&64u64.to_le_bytes());
        // e_phentsize = 56
        elf_bytes[54..56].copy_from_slice(&56u16.to_le_bytes());
        // e_phnum = 1
        elf_bytes[56..58].copy_from_slice(&1u16.to_le_bytes());

        // Program Header at offset 64
        // p_type = 1 (PT_LOAD)
        elf_bytes[64..68].copy_from_slice(&1u32.to_le_bytes());
        // p_flags = 5 (RX)
        elf_bytes[68..72].copy_from_slice(&5u32.to_le_bytes());
        // p_offset = 0
        elf_bytes[72..80].copy_from_slice(&0u64.to_le_bytes());
        // p_vaddr = 0x400000
        elf_bytes[80..88].copy_from_slice(&0x400000u64.to_le_bytes());
        // p_filesz = 4096
        elf_bytes[96..104].copy_from_slice(&4096u64.to_le_bytes());

        let parsed = binary_format::ParsedElf64::parse(&elf_bytes).expect("Should parse ELF");
        assert_eq!(parsed.entry_point, 0x401000);
        assert_eq!(parsed.ph_num, 1);

        let ph = parsed.get_program_header(&elf_bytes, 0).expect("Should extract program header");
        assert_eq!(ph.p_type, 1);
        assert_eq!(ph.p_vaddr, 0x400000);
        assert_eq!(ph.p_filesz, 4096);
    }

    #[test]
    fn test_detect_windows_pe() {
        // Minimal PE header: 'MZ' stub + PE pointer
        let mut pe_bytes = [0u8; 128];
        pe_bytes[0] = b'M';
        pe_bytes[1] = b'Z';
        pe_bytes[0x3C] = 0x40; // PE header offset at 0x40
        pe_bytes[0x40] = b'P';
        pe_bytes[0x41] = b'E';
        pe_bytes[0x44] = 0x64; // x86_64 machine code
        pe_bytes[0x45] = 0x86;

        let format = detect_format(&pe_bytes);
        assert_eq!(format, BinaryFormat::WindowsPe { is_64_bit: true });
    }

    #[test]
    fn test_detect_mac_macho() {
        // 64-bit Mach-O magic: 0xfeedfacf
        let macho_header = [0xFE, 0xED, 0xFA, 0xCF, 0x01, 0x00, 0x00, 0x07];
        let format = detect_format(&macho_header);
        assert_eq!(format, BinaryFormat::MacMachO { is_64_bit: true, is_fat: false });
    }

    #[test]
    fn test_universal_execution_across_all_three_os() {
        let mut engine = UniversalAbiEngine::new();

        // 1. Run Linux binary
        let elf = [0x7F, b'E', b'L', b'F', 2, 1, 1, 0, 0x90, 0x90];
        let res_linux = engine.execute(&elf);
        assert_eq!(res_linux, ExecutionResult::LinuxSuccess(elf.len() as i64));

        // 2. Run Windows binary
        let pe = [b'M', b'Z', 0x90, 0x00];
        let res_windows = engine.execute(&pe);
        assert_eq!(res_windows, ExecutionResult::WindowsSuccess(0));

        // 3. Run macOS binary
        let macho = [0xFE, 0xED, 0xFA, 0xCF];
        let res_mac = engine.execute(&macho);
        assert_eq!(res_mac, ExecutionResult::MacSuccess(0));
    }
}
