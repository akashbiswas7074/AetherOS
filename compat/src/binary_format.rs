//! Binary format detector for Linux ELF, Windows PE, and macOS Mach-O.

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum BinaryFormat {
    LinuxElf { is_64_bit: bool },
    WindowsPe { is_64_bit: bool },
    MacMachO { is_64_bit: bool, is_fat: bool },
    Unknown,
}

pub fn detect_format(bytes: &[u8]) -> BinaryFormat {
    if bytes.len() < 4 {
        return BinaryFormat::Unknown;
    }

    // 1. Linux ELF: \x7F 'E' 'L' 'F'
    if bytes[0] == 0x7F && bytes[1] == b'E' && bytes[2] == b'L' && bytes[3] == b'F' {
        let is_64 = if bytes.len() > 4 { bytes[4] == 2 } else { true };
        return BinaryFormat::LinuxElf { is_64_bit: is_64 };
    }

    // 2. Windows PE: 'M' 'Z' (DOS Stub)
    if bytes[0] == b'M' && bytes[1] == b'Z' {
        // Look up e_lfanew at offset 0x3C if available
        let mut is_64 = true;
        if bytes.len() >= 0x40 {
            let pe_offset = u32::from_le_bytes([bytes[0x3C], bytes[0x3D], bytes[0x3E], bytes[0x3F]]) as usize;
            if bytes.len() >= pe_offset + 6 {
                // Check 'PE\0\0'
                if bytes[pe_offset] == b'P' && bytes[pe_offset + 1] == b'E' {
                    let machine = u16::from_le_bytes([bytes[pe_offset + 4], bytes[pe_offset + 5]]);
                    is_64 = machine == 0x8664; // IMAGE_FILE_MACHINE_AMD64
                }
            }
        }
        return BinaryFormat::WindowsPe { is_64_bit: is_64 };
    }

    // 3. macOS Mach-O: 0xfeedface (32-bit), 0xfeedfacf (64-bit), 0xcafebabe (Fat Universal)
    let magic = u32::from_be_bytes([bytes[0], bytes[1], bytes[2], bytes[3]]);
    let magic_le = u32::from_le_bytes([bytes[0], bytes[1], bytes[2], bytes[3]]);

    if magic == 0xFEEDFACF || magic_le == 0xFEEDFACF {
        return BinaryFormat::MacMachO { is_64_bit: true, is_fat: false };
    }
    if magic == 0xFEEDFACE || magic_le == 0xFEEDFACE {
        return BinaryFormat::MacMachO { is_64_bit: false, is_fat: false };
    }
    if magic == 0xCAFEBABE || magic_le == 0xCAFEBABE {
        return BinaryFormat::MacMachO { is_64_bit: true, is_fat: true };
    }

    BinaryFormat::Unknown
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Elf64ProgramHeader {
    pub p_type: u32,
    pub p_flags: u32,
    pub p_offset: u64,
    pub p_vaddr: u64,
    pub p_paddr: u64,
    pub p_filesz: u64,
    pub p_memsz: u64,
    pub p_align: u64,
}

#[derive(Clone, Copy, Debug)]
pub struct ParsedElf64 {
    pub entry_point: u64,
    pub ph_offset: u64,
    pub ph_num: u16,
    pub ph_entsize: u16,
}

impl ParsedElf64 {
    pub fn parse(bytes: &[u8]) -> Option<Self> {
        if bytes.len() < 64 {
            return None;
        }
        if bytes[0..4] != [0x7F, b'E', b'L', b'F'] {
            return None;
        }
        if bytes[4] != 2 {
            // Must be 64-bit ELF
            return None;
        }

        let entry_point = u64::from_le_bytes(bytes[24..32].try_into().ok()?);
        let ph_offset = u64::from_le_bytes(bytes[32..40].try_into().ok()?);
        let ph_entsize = u16::from_le_bytes(bytes[54..56].try_into().ok()?);
        let ph_num = u16::from_le_bytes(bytes[56..58].try_into().ok()?);

        Some(Self {
            entry_point,
            ph_offset,
            ph_num,
            ph_entsize,
        })
    }

    pub fn get_program_header(&self, bytes: &[u8], index: usize) -> Option<Elf64ProgramHeader> {
        if index >= self.ph_num as usize {
            return None;
        }
        let offset = (self.ph_offset as usize) + index * (self.ph_entsize as usize);
        if bytes.len() < offset + 56 {
            return None;
        }

        let p_type = u32::from_le_bytes(bytes[offset..offset + 4].try_into().ok()?);
        let p_flags = u32::from_le_bytes(bytes[offset + 4..offset + 8].try_into().ok()?);
        let p_offset = u64::from_le_bytes(bytes[offset + 8..offset + 16].try_into().ok()?);
        let p_vaddr = u64::from_le_bytes(bytes[offset + 16..offset + 24].try_into().ok()?);
        let p_paddr = u64::from_le_bytes(bytes[offset + 24..offset + 32].try_into().ok()?);
        let p_filesz = u64::from_le_bytes(bytes[offset + 32..offset + 40].try_into().ok()?);
        let p_memsz = u64::from_le_bytes(bytes[offset + 40..offset + 48].try_into().ok()?);
        let p_align = u64::from_le_bytes(bytes[offset + 48..offset + 56].try_into().ok()?);

        Some(Elf64ProgramHeader {
            p_type,
            p_flags,
            p_offset,
            p_vaddr,
            p_paddr,
            p_filesz,
            p_memsz,
            p_align,
        })
    }
}
