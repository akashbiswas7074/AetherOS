; =============================================================================
; AnantaOS MBR Stage 1 Bootloader
; Switches to Graphics Mode 13h, loads kernel from disk, enters Protected Mode
; =============================================================================

[BITS 16]
[ORG 0x7C00]

start:
    cli
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7C00
    sti

    mov [BOOT_DRIVE], dl        ; Save boot drive number

    ; 1. Switch to 80x25 16-color VGA Text Mode (Mode 03h)
    mov ax, 0x0003
    int 0x10

    ; 2. Load Kernel sectors from disk into 0x1000:0000 (0x10000 physical)
    ; Part A: Cylinder 0, Head 0, Sectors 2..18 (17 sectors = 8,704 bytes)
    mov ax, 0x1000
    mov es, ax
    xor bx, bx                  ; ES:BX = 0x1000:0000
    mov ah, 0x02
    mov al, 17
    mov ch, 0                   ; Cylinder 0
    mov cl, 2                   ; Sector 2
    mov dh, 0                   ; Head 0
    mov dl, [BOOT_DRIVE]
    int 0x13
    jc .disk_err

    ; Part B: Cylinder 0, Head 1, Sectors 1..18 (18 sectors = 9,216 bytes)
    mov ax, 0x1220              ; ES:BX = 0x1220:0000 (0x12200 physical)
    mov es, ax
    xor bx, bx
    mov ah, 0x02
    mov al, 18
    mov ch, 0                   ; Cylinder 0
    mov cl, 1                   ; Sector 1
    mov dh, 1                   ; Head 1
    mov dl, [BOOT_DRIVE]
    int 0x13
    jc .disk_err

    ; Part C: Cylinder 1, Head 0, Sectors 1..18 (18 sectors = 9,216 bytes)
    mov ax, 0x1460              ; ES:BX = 0x1460:0000 (0x14600 physical)
    mov es, ax
    xor bx, bx
    mov ah, 0x02
    mov al, 18
    mov ch, 1                   ; Cylinder 1
    mov cl, 1                   ; Sector 1
    mov dh, 0                   ; Head 0
    mov dl, [BOOT_DRIVE]
    int 0x13
    jc .disk_err

    ; Part D: Cylinder 1, Head 1, Sectors 1..18 (18 sectors = 9,216 bytes)
    mov ax, 0x16A0              ; ES:BX = 0x16A0:0000 (0x16A00 physical)
    mov es, ax
    xor bx, bx
    mov ah, 0x02
    mov al, 18
    mov ch, 1                   ; Cylinder 1
    mov cl, 1                   ; Sector 1
    mov dh, 1                   ; Head 1
    mov dl, [BOOT_DRIVE]
    int 0x13
    jc .disk_err

    ; Part E: Cylinder 2, Head 0, Sectors 1..18 (18 sectors = 9,216 bytes)
    mov ax, 0x18E0              ; ES:BX = 0x18E0:0000 (0x18E00 physical)
    mov es, ax
    xor bx, bx
    mov ah, 0x02
    mov al, 18
    mov ch, 2                   ; Cylinder 2
    mov cl, 1                   ; Sector 1
    mov dh, 0                   ; Head 0
    mov dl, [BOOT_DRIVE]
    int 0x13
    jc .disk_err

    ; Part F: Cylinder 2, Head 1, Sectors 1..18 (18 sectors = 9,216 bytes)
    mov ax, 0x1B20              ; ES:BX = 0x1B20:0000 (0x1B200 physical)
    mov es, ax
    xor bx, bx
    mov ah, 0x02
    mov al, 18
    mov ch, 2                   ; Cylinder 2
    mov cl, 1                   ; Sector 1
    mov dh, 1                   ; Head 1
    mov dl, [BOOT_DRIVE]
    int 0x13
    jc .disk_err

    ; Part G: Cylinder 3, Head 0, Sectors 1..18 (18 sectors = 9,216 bytes)
    mov ax, 0x1D60              ; ES:BX = 0x1D60:0000 (0x1D600 physical)
    mov es, ax
    xor bx, bx
    mov ah, 0x02
    mov al, 18
    mov ch, 3                   ; Cylinder 3
    mov cl, 1                   ; Sector 1
    mov dh, 0                   ; Head 0
    mov dl, [BOOT_DRIVE]
    int 0x13
    jc .disk_err

    ; Part H: Cylinder 3, Head 1, Sectors 1..18 (18 sectors = 9,216 bytes)
    mov ax, 0x1FA0              ; ES:BX = 0x1FA0:0000 (0x1FA00 physical)
    mov es, ax
    xor bx, bx
    mov ah, 0x02
    mov al, 18
    mov ch, 3                   ; Cylinder 3
    mov cl, 1                   ; Sector 1
    mov dh, 1                   ; Head 1
    mov dl, [BOOT_DRIVE]
    int 0x13
    jnc .load_ok

.disk_err:
    ; Reset disk drive and continue
    xor ax, ax
    mov dl, [BOOT_DRIVE]
    int 0x13

.load_ok:
    ; 3. Enable A20 Line (Fast A20 Gate)
    in al, 0x92
    or al, 2
    out 0x92, al

    ; 4. Disable interrupts and load GDT
    cli
    lgdt [gdt_descriptor]

    ; 5. Switch to 32-bit Protected Mode (Set PE bit in CR0)
    mov eax, cr0
    or eax, 1
    mov cr0, eax

    ; 6. Far jump to 32-bit code segment (Flushes CPU prefetch queue)
    jmp dword CODE_SEG:0x10000

; =============================================================================
; GDT (Global Descriptor Table)
; =============================================================================
gdt_start:
    ; Null Descriptor
    dd 0x0
    dd 0x0

gdt_code:
    ; Code Segment Descriptor: Base=0, Limit=4GB, Present, Ring 0, Exec/Read
    dw 0xFFFF                   ; Limit (bits 0-15)
    dw 0x0000                   ; Base (bits 0-15)
    db 0x00                     ; Base (bits 16-23)
    db 10011010b                ; Access byte (Present, Ring 0, Code, Readable)
    db 11001111b                ; Granularity (4KB blocks, 32-bit)
    db 0x00                     ; Base (bits 24-31)

gdt_data:
    ; Data Segment Descriptor: Base=0, Limit=4GB, Present, Ring 0, Read/Write
    dw 0xFFFF
    dw 0x0000
    db 0x00
    db 10010010b                ; Access byte (Present, Ring 0, Data, Writable)
    db 11001111b
    db 0x00

gdt_end:

gdt_descriptor:
    dw gdt_end - gdt_start - 1  ; GDT size
    dd gdt_start                ; GDT address

CODE_SEG equ gdt_code - gdt_start
DATA_SEG equ gdt_data - gdt_start

BOOT_DRIVE db 0

times 510 - ($ - $$) db 0
dw 0xAA55                       ; MBR Boot Signature
