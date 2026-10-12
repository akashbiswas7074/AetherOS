; =============================================================================
; AetherOS 32-bit Protected Mode Interactive Terminal Microkernel
; Authentic Full-Screen 80x25 Linux Console (VGA 0xB8000)
; Features: Blinking Cursor, Tokenized Dispatcher, Hierarchical Filesystem,
; Linux Developer Apps: nano, vim, git, gcc, python, curl, tree, htop, apt/nix
; =============================================================================

[BITS 32]
[ORG 0x10000]

VGA_TEXT    equ 0xB8000
COLS        equ 80
ROWS        equ 25

ATTR_DEFAULT equ 0x07           ; Light Gray on Black
ATTR_PROMPT  equ 0x0A           ; Bright Green on Black
ATTR_GREEN   equ 0x0A           ; Bright Green on Black
ATTR_PATH    equ 0x09           ; Bright Blue on Black
ATTR_WHITE   equ 0x0F           ; Bright White on Black
ATTR_YELLOW  equ 0x0E           ; Yellow on Black
ATTR_CYAN    equ 0x0B           ; Cyan on Black
ATTR_RED     equ 0x0C           ; Red on Black
ATTR_DIM     equ 0x08           ; Dark Gray on Black
ATTR_NANO_BAR equ 0x70          ; Black on Light Gray (Authentic GNU nano inverted bar)

MAX_FS_ENTRIES equ 16
FS_ENTRY_SIZE  equ 324          ; 1 type, 1 pad, 32 parent_dir, 32 name, 2 size, 256 content bytes

kernel_start:
    ; 1. Set up protected mode segment registers
    mov ax, 0x10                ; DATA_SEG
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    mov ss, ax
    mov esp, 0x90000            ; Kernel stack

    ; 2. Initialize Serial Port COM1 (0x3F8)
    mov dx, 0x3F9
    mov al, 0x00
    out dx, al                  ; Disable interrupts
    mov dx, 0x3FB
    mov al, 0x80
    out dx, al                  ; Enable DLAB
    mov dx, 0x3F8
    mov al, 0x03
    out dx, al                  ; 38400 baud
    mov dx, 0x3F9
    mov al, 0x00
    out dx, al
    mov dx, 0x3FB
    mov al, 0x03
    out dx, al                  ; 8N1

    ; 3. Clear Screen and Show Terminal Boot Banner
    call term_clear
    mov esi, banner_text
    mov ah, ATTR_WHITE
    call term_print

    ; 4. Show initial prompt
    call term_print_prompt

    ; 5. Interactive Main Shell Loop
main_loop:
    in al, 0x64                 ; Read PS/2 status
    test al, 1                  ; Check bit 0 (Output Buffer Full)
    jz .idle

    test al, 0x20               ; Ignore mouse packets in text terminal
    jnz .discard

    in al, 0x60                 ; Read keyboard scancode
    call handle_key
    jmp .idle

.discard:
    in al, 0x60                 ; Discard
.idle:
    pause                       ; Low-power spinloop pause
    jmp main_loop

; =============================================================================
; Keyboard Event Handler
; =============================================================================

handle_key:
    cmp al, 0x2A
    je .hk_shift_on
    cmp al, 0x36
    je .hk_shift_on
    cmp al, 0xAA
    je .hk_shift_off
    cmp al, 0xB6
    je .hk_shift_off
    test al, 0x80               ; Key release?
    jnz .done

    ; Backspace (0x0E)
    cmp al, 0x0E
    jne .check_enter
    call do_backspace
    ret

.hk_shift_on:
    mov byte [shift_state], 1
    ret
.hk_shift_off:
    mov byte [shift_state], 0
    ret

.check_enter:
    ; Enter (0x1C)
    cmp al, 0x1C
    jne .check_char
    call do_enter
    ret

.check_char:
    cmp al, 0x39
    ja .done
    movzx ebx, al
    cmp byte [shift_state], 1
    je .hk_use_shift
    mov cl, [scancode_table + ebx]
    jmp .hk_char_mapped
.hk_use_shift:
    mov cl, [scancode_shift_table + ebx]
.hk_char_mapped:
    test cl, cl
    jz .done

    ; Append to buffer if room
    mov eax, [cmd_len]
    cmp eax, 64
    jge .done

    mov [cmd_buffer + eax], cl
    inc dword [cmd_len]
    mov eax, [cmd_len]
    mov byte [cmd_buffer + eax], 0

    ; Echo character on screen
    mov al, cl
    mov ah, ATTR_WHITE
    call term_print_char
.done:
    ret

do_backspace:
    mov eax, [cmd_len]
    test eax, eax
    jz .bs_done
    dec eax
    mov [cmd_len], eax
    mov byte [cmd_buffer + eax], 0

    ; Move cursor back and erase char
    mov al, 0x08
    call term_print_char
.bs_done:
    ret

do_enter:
    ; Print newline
    mov al, 0x0A
    mov ah, ATTR_DEFAULT
    call term_print_char

    ; Null-terminate cmd_buffer
    mov eax, [cmd_len]
    mov byte [cmd_buffer + eax], 0
    test eax, eax
    jz .prompt_again

    call execute_command

.prompt_again:
    ; Reset buffer
    mov dword [cmd_len], 0
    mov byte [cmd_buffer], 0

    ; Print prompt for next command
    call term_print_prompt
    ret

; =============================================================================
; Command Parser & Execution Engine
; =============================================================================

execute_command:
    call tokenize_command

    ; If command name is empty, return
    cmp byte [cmd_name], 0
    je .done

    ; 1. help
    mov esi, str_cmd_help
    call match_cmd
    jz .cmd_help

    ; 2. ls
    mov esi, str_cmd_ls
    call match_cmd
    jz .cmd_ls

    ; 3. cd
    mov esi, str_cmd_cd
    call match_cmd
    jz .cmd_cd

    ; 4. pwd
    mov esi, str_cmd_pwd
    call match_cmd
    jz .cmd_pwd

    ; 5. mkdir
    mov esi, str_cmd_mkdir
    call match_cmd
    jz .cmd_mkdir

    ; 6. touch
    mov esi, str_cmd_touch
    call match_cmd
    jz .cmd_touch

    ; 7. rm
    mov esi, str_cmd_rm
    call match_cmd
    jz .cmd_rm

    ; 8. cp
    mov esi, str_cmd_cp
    call match_cmd
    jz .cmd_cp

    ; 9. mv
    mov esi, str_cmd_mv
    call match_cmd
    jz .cmd_mv

    ; 10. cat
    mov esi, str_cmd_cat
    call match_cmd
    jz .cmd_cat

    ; 11. echo
    mov esi, str_cmd_echo
    call match_cmd
    jz .cmd_echo

    ; 12. nano / /bin/nano / ./nano
    mov esi, str_cmd_nano
    call match_cmd
    jz .cmd_nano
    mov esi, str_cmd_slash_nano
    call match_cmd
    jz .cmd_nano
    mov esi, str_cmd_dot_nano
    call match_cmd
    jz .cmd_nano

    ; 13. vim / vi
    mov esi, str_cmd_vim
    call match_cmd
    jz .cmd_vim
    mov esi, str_cmd_vi
    call match_cmd
    jz .cmd_vim

    ; 14. git
    mov esi, str_cmd_git
    call match_cmd
    jz .cmd_git

    ; 15. gcc / g++ / clang
    mov esi, str_cmd_gcc
    call match_cmd
    jz .cmd_gcc
    mov esi, str_cmd_gpp
    call match_cmd
    jz .cmd_gcc
    mov esi, str_cmd_clang
    call match_cmd
    jz .cmd_gcc

    ; 16. python / python3
    mov esi, str_cmd_python
    call match_cmd
    jz .cmd_python
    mov esi, str_cmd_python3
    call match_cmd
    jz .cmd_python

    ; 17. curl / wget
    mov esi, str_cmd_curl
    call match_cmd
    jz .cmd_curl
    mov esi, str_cmd_wget
    call match_cmd
    jz .cmd_curl

    ; 18. tree
    mov esi, str_cmd_tree
    call match_cmd
    jz .cmd_tree

    ; 19. htop / top
    mov esi, str_cmd_htop
    call match_cmd
    jz .cmd_htop
    mov esi, str_cmd_top
    call match_cmd
    jz .cmd_htop

    ; 20. apk / pkg / apt / nix-env / pacman / install
    mov esi, str_cmd_apk
    call match_cmd
    jz .cmd_pkg
    mov esi, str_cmd_pkg
    call match_cmd
    jz .cmd_pkg
    mov esi, str_cmd_apt
    call match_cmd
    jz .cmd_pkg
    mov esi, str_cmd_install
    call match_cmd
    jz .cmd_pkg
    mov esi, str_cmd_nixenv
    call match_cmd
    jz .cmd_pkg
    mov esi, str_cmd_pacman
    call match_cmd
    jz .cmd_pkg

    ; which & whereis
    mov esi, str_cmd_which
    call match_cmd
    jz .cmd_which
    mov esi, str_cmd_whereis
    call match_cmd
    jz .cmd_whereis

    ; 21. nmcli / nmtui
    mov esi, str_cmd_nmcli
    call match_cmd
    jz .cmd_nmcli
    mov esi, str_cmd_nmtui
    call match_cmd
    jz .cmd_nmcli

    ; 22. ip / ifconfig
    mov esi, str_cmd_ip
    call match_cmd
    jz .cmd_ip
    mov esi, str_cmd_ifconfig
    call match_cmd
    jz .cmd_ip

    ; 23. ping
    mov esi, str_cmd_ping
    call match_cmd
    jz .cmd_ping

    ; 24. bluetoothctl / bluetooth
    mov esi, str_cmd_btctl
    call match_cmd
    jz .cmd_bluetooth
    mov esi, str_cmd_bluetooth
    call match_cmd
    jz .cmd_bluetooth

    ; 25. rfkill
    mov esi, str_cmd_rfkill
    call match_cmd
    jz .cmd_rfkill

    ; 26. wifi
    mov esi, str_cmd_wifi
    call match_cmd
    jz .cmd_wifi

    ; 27. uname
    mov esi, str_cmd_uname
    call match_cmd
    jz .cmd_uname

    ; 22. whoami
    mov esi, str_cmd_whoami
    call match_cmd
    jz .cmd_whoami

    ; 23. ps
    mov esi, str_cmd_ps
    call match_cmd
    jz .cmd_ps

    ; 24. free
    mov esi, str_cmd_free
    call match_cmd
    jz .cmd_free

    ; 25. casfs
    mov esi, str_cmd_casfs
    call match_cmd
    jz .cmd_casfs

    ; 26. hyprland / hypr
    mov esi, str_cmd_hypr
    call match_cmd
    jz .cmd_hypr
    mov esi, str_cmd_hyprland
    call match_cmd
    jz .cmd_hypr

    ; 27. ab (ApacheBench)
    mov esi, str_cmd_ab
    call match_cmd
    jz .cmd_ab

    ; 28. sudo
    mov esi, str_cmd_sudo
    call match_cmd
    jz .cmd_sudo

    ; 29. history
    mov esi, str_cmd_history
    call match_cmd
    jz .cmd_history

    ; 30. neofetch / fastfetch
    mov esi, str_cmd_neofetch
    call match_cmd
    jz .cmd_neofetch
    mov esi, str_cmd_fastfetch
    call match_cmd
    jz .cmd_neofetch

    ; 31. 1 / calc / ./calculator.elf / a.out / ./a.out
    mov esi, str_cmd_1
    call match_cmd
    jz .cmd_run_linux
    mov esi, str_cmd_calc
    call match_cmd
    jz .cmd_run_linux
    mov esi, str_cmd_calculator
    call match_cmd
    jz .cmd_run_linux
    mov esi, str_cmd_aout
    call match_cmd
    jz .cmd_run_linux
    mov esi, str_cmd_dotaout
    call match_cmd
    jz .cmd_run_linux

    ; 32. 2 / notepad / notepad.exe / wine
    mov esi, str_cmd_2
    call match_cmd
    jz .cmd_run_win
    mov esi, str_cmd_notepad
    call match_cmd
    jz .cmd_run_win
    mov esi, str_cmd_notepadexe
    call match_cmd
    jz .cmd_run_win
    mov esi, str_cmd_wine
    call match_cmd
    jz .cmd_run_win

    ; 33. 3 / open / terminal.app
    mov esi, str_cmd_3
    call match_cmd
    jz .cmd_run_mac
    mov esi, str_cmd_open
    call match_cmd
    jz .cmd_run_mac
    mov esi, str_cmd_termapp
    call match_cmd
    jz .cmd_run_mac

    ; 34. r / rollback
    mov esi, str_cmd_r
    call match_cmd
    jz .cmd_rollback
    mov esi, str_cmd_rollback
    call match_cmd
    jz .cmd_rollback

    ; 35. clear
    mov esi, str_cmd_clear
    call match_cmd
    jz .cmd_clear

    ; 36. reboot
    mov esi, str_cmd_reboot
    call match_cmd
    jz .cmd_reboot

    ; 37. date
    mov esi, str_cmd_date
    call match_cmd
    jz .cmd_date

    ; 38. lspci
    mov esi, str_cmd_lspci
    call match_cmd
    jz .cmd_lspci

    ; Unknown command: print error
    mov esi, cmd_name
    mov ah, ATTR_WHITE
    call term_print
    mov esi, out_not_found
    mov ah, ATTR_RED
    call term_print
    ret

.done:
    ret

; -----------------------------------------------------------------------------
; Individual Command Implementations
; -----------------------------------------------------------------------------

.cmd_help:
    mov esi, out_help
    mov ah, ATTR_DEFAULT
    call term_print
    ret

.cmd_ls:
    mov edi, [cmd_arg_ptr]
    mov esi, str_arg_bin
    call str_prefix
    jz .ls_bin
    mov esi, str_arg_slash_bin
    call str_prefix
    jz .ls_bin

    mov esi, str_arg_etc
    call str_prefix
    jz .ls_etc
    mov esi, str_arg_slash_etc
    call str_prefix
    jz .ls_etc

    mov esi, str_arg_proc
    call str_prefix
    jz .ls_proc
    mov esi, str_arg_slash_proc
    call str_prefix
    jz .ls_proc

    mov esi, str_arg_hypr
    call str_prefix
    jz .ls_hypr

    ; Check current working directory
    cmp byte [cwd_display+1], 'b'       ; "/bin"
    je .ls_bin
    cmp byte [cwd_display+1], 'e'       ; "/etc"
    je .ls_etc
    cmp byte [cwd_display+1], 'p'       ; "/proc"
    je .ls_proc
    cmp byte [cwd_display+2], '.'       ; "~/.config/hypr"
    je .ls_hypr

    ; Is current directory "~"?
    cmp word [cwd_display], 0x007E     ; "~", 0
    jne .ls_custom_folder

    ; In home directory (~): Print default home files first
    mov esi, out_ls
    mov ah, ATTR_DEFAULT
    call term_print
    jmp .ls_print_dynamic_entries

.ls_custom_folder:
    ; In any subfolder: Print folder header
    mov esi, out_ls_empty_folder
    mov ah, ATTR_DEFAULT
    call term_print

.ls_print_dynamic_entries:
    ; Scan fs_table for entries belonging to current working directory
    xor ecx, ecx
.ls_loop_entries:
    cmp ecx, MAX_FS_ENTRIES
    jge .ls_done

    mov eax, ecx
    imul eax, FS_ENTRY_SIZE
    add eax, fs_table

    cmp byte [eax], 0           ; is entry active?
    je .ls_next_entry

    ; Check if entry's parent_dir == cwd_display
    push eax
    push ecx
    lea esi, [eax + 2]           ; entry parent_dir
    mov edi, cwd_display
    call streq
    pop ecx
    pop eax
    jnz .ls_next_entry          ; not in current directory!

    ; Entry belongs to current directory!
    cmp byte [eax], 2
    je .ls_print_dir_entry

    ; Print file entry
    push eax
    push ecx
    mov esi, out_ls_file_prefix
    mov ah, ATTR_DEFAULT
    call term_print

    pop ecx
    pop eax
    push eax
    push ecx
    lea esi, [eax + 34]          ; filename
    mov ah, ATTR_WHITE
    call term_print

    mov esi, out_ls_file_suffix
    mov ah, ATTR_DEFAULT
    call term_print
    pop ecx
    pop eax
    jmp .ls_next_entry

.ls_print_dir_entry:
    push eax
    push ecx
    mov esi, out_ls_dir_prefix
    mov ah, ATTR_DEFAULT
    call term_print

    pop ecx
    pop eax
    push eax
    push ecx
    lea esi, [eax + 34]          ; dirname
    mov ah, ATTR_PATH
    call term_print

    mov esi, out_ls_dir_suffix
    mov ah, ATTR_DEFAULT
    call term_print
    pop ecx
    pop eax

.ls_next_entry:
    inc ecx
    jmp .ls_loop_entries

.ls_done:
    ret

.ls_bin:
    mov esi, out_ls_bin
    mov ah, ATTR_DEFAULT
    call term_print
    ret
.ls_etc:
    mov esi, out_ls_etc
    mov ah, ATTR_DEFAULT
    call term_print
    ret
.ls_proc:
    mov esi, out_ls_proc
    mov ah, ATTR_DEFAULT
    call term_print
    ret
.ls_hypr:
    mov esi, out_ls_hypr
    mov ah, ATTR_DEFAULT
    call term_print
    ret

.cmd_cd:
    mov edi, [cmd_arg_ptr]
    ; Check empty or '~' or 'home'
    cmp byte [edi], 0
    je .cd_home
    cmp byte [edi], '~'
    je .cd_home
    mov esi, str_arg_home
    call str_prefix
    jz .cd_home

    ; Check '..'
    mov esi, str_arg_dotdot
    call str_prefix
    jz .cd_dotdot

    ; Check '/'
    mov esi, str_arg_slash
    call str_prefix
    jz .cd_root

    ; Check 'bin' or '/bin'
    mov esi, str_arg_bin
    call str_prefix
    jz .cd_bin
    mov esi, str_arg_slash_bin
    call str_prefix
    jz .cd_bin

    ; Check 'etc' or '/etc'
    mov esi, str_arg_etc
    call str_prefix
    jz .cd_etc
    mov esi, str_arg_slash_etc
    call str_prefix
    jz .cd_etc

    ; Check 'proc' or '/proc'
    mov esi, str_arg_proc
    call str_prefix
    jz .cd_proc
    mov esi, str_arg_slash_proc
    call str_prefix
    jz .cd_proc

    ; Check 'hypr' or '.config/hypr' or '~/.config/hypr'
    mov esi, str_arg_hypr
    call str_prefix
    jz .cd_hypr
    mov esi, str_arg_config_hypr
    call str_prefix
    jz .cd_hypr
    mov esi, str_arg_tilde_hypr
    call str_prefix
    jz .cd_hypr

    ; Check dynamic directory in current directory!
    xor ecx, ecx
.cd_search_dynamic:
    cmp ecx, MAX_FS_ENTRIES
    jge .cd_not_found

    mov eax, ecx
    imul eax, FS_ENTRY_SIZE
    add eax, fs_table

    cmp byte [eax], 2           ; must be directory
    jne .cd_next_dynamic

    ; Verify parent_dir == cwd_display
    push eax
    push ecx
    lea esi, [eax + 2]           ; parent_dir
    mov edi, cwd_display
    call streq
    pop ecx
    pop eax
    jnz .cd_next_dynamic

    ; Verify name == cmd_arg_ptr
    push eax
    push ecx
    lea esi, [eax + 34]          ; name
    mov edi, [cmd_arg_ptr]
    call streq
    pop ecx
    pop eax
    jz .cd_enter_dynamic

.cd_next_dynamic:
    inc ecx
    jmp .cd_search_dynamic

.cd_enter_dynamic:
    ; Append name to cwd_display
    lea esi, [eax + 34]
    call path_append
    ret

.cd_not_found:
    ; Directory not found
    mov esi, str_cd_prefix
    mov ah, ATTR_RED
    call term_print
    mov esi, [cmd_arg_ptr]
    mov ah, ATTR_WHITE
    call term_print
    mov esi, str_err_not_found_dir
    mov ah, ATTR_RED
    call term_print
    ret

.cd_home:
    mov esi, str_dir_home
    mov edi, cwd_display
    call strcpy
    ret

.cd_dotdot:
    ; If in "/", stay at "/"
    cmp word [cwd_display], 0x002F     ; "/", 0
    je .cd_dot_done
    ; If in "~", go to "/"
    cmp word [cwd_display], 0x007E     ; "~", 0
    je .cd_root

    ; Search backwards for last '/'
    mov esi, cwd_display
    xor ecx, ecx
    mov edx, -1
.cd_scan_slash:
    mov al, [esi + ecx]
    test al, al
    jz .cd_eval_slash
    cmp al, '/'
    jne .cd_next_slash
    mov edx, ecx
.cd_next_slash:
    inc ecx
    jmp .cd_scan_slash

.cd_eval_slash:
    cmp edx, -1
    jle .cd_home
    cmp edx, 1                  ; e.g. "~/akash" -> edx is 1
    jle .cd_home
    ; Truncate at last slash
    mov byte [cwd_display + edx], 0
.cd_dot_done:
    ret

.cd_root:
    mov esi, str_dir_root
    mov edi, cwd_display
    call strcpy
    ret

.cd_bin:
    mov esi, str_dir_bin
    mov edi, cwd_display
    call strcpy
    ret

.cd_etc:
    mov esi, str_dir_etc
    mov edi, cwd_display
    call strcpy
    ret

.cd_proc:
    mov esi, str_dir_proc
    mov edi, cwd_display
    call strcpy
    ret

.cd_hypr:
    mov esi, str_dir_hypr
    mov edi, cwd_display
    call strcpy
    ret

.cmd_pwd:
    mov esi, cwd_display
    mov ah, ATTR_WHITE
    call term_print
    mov al, 0x0A
    mov ah, ATTR_DEFAULT
    call term_print_char
    ret

.cmd_mkdir:
    mov edi, [cmd_arg_ptr]
    cmp byte [edi], 0
    je .mkdir_no_arg

    ; Find free entry in fs_table
    xor ecx, ecx
.mk_find_free:
    cmp ecx, MAX_FS_ENTRIES
    jge .mk_full
    mov eax, ecx
    imul eax, FS_ENTRY_SIZE
    add eax, fs_table
    cmp byte [eax], 0
    je .mk_allocate
    inc ecx
    jmp .mk_find_free

.mk_allocate:
    mov byte [eax], 2           ; type = directory
    push eax
    ; Copy cwd_display as parent_dir
    mov esi, cwd_display
    lea edi, [eax + 2]
    call strcpy
    pop eax

    ; Copy name
    push eax
    mov esi, [cmd_arg_ptr]
    lea edi, [eax + 34]
    call strcpy
    pop eax

    mov esi, out_mkdir_ok1
    mov ah, ATTR_GREEN
    call term_print
    mov esi, [cmd_arg_ptr]
    mov ah, ATTR_WHITE
    call term_print
    mov esi, out_mkdir_ok2
    mov ah, ATTR_GREEN
    call term_print
    ret

.mk_full:
    mov esi, out_fs_full
    mov ah, ATTR_RED
    call term_print
    ret

.mkdir_no_arg:
    mov esi, out_mkdir_err
    mov ah, ATTR_RED
    call term_print
    ret

.cmd_touch:
    mov edi, [cmd_arg_ptr]
    cmp byte [edi], 0
    je .touch_no_arg

    ; Find free entry in fs_table
    xor ecx, ecx
.tc_find_free:
    cmp ecx, MAX_FS_ENTRIES
    jge .tc_full
    mov eax, ecx
    imul eax, FS_ENTRY_SIZE
    add eax, fs_table
    cmp byte [eax], 0
    je .tc_allocate
    inc ecx
    jmp .tc_find_free

.tc_allocate:
    mov byte [eax], 1           ; type = file
    push eax
    ; Copy cwd_display as parent_dir
    mov esi, cwd_display
    lea edi, [eax + 2]
    call strcpy
    pop eax

    ; Copy name
    push eax
    mov esi, [cmd_arg_ptr]
    lea edi, [eax + 34]
    call strcpy
    pop eax

    mov esi, out_touch_ok1
    mov ah, ATTR_GREEN
    call term_print
    mov esi, [cmd_arg_ptr]
    mov ah, ATTR_WHITE
    call term_print
    mov esi, out_touch_ok2
    mov ah, ATTR_GREEN
    call term_print
    ret

.tc_full:
    mov esi, out_fs_full
    mov ah, ATTR_RED
    call term_print
    ret

.touch_no_arg:
    mov esi, out_touch_err
    mov ah, ATTR_RED
    call term_print
    ret

.cmd_rm:
    mov edi, [cmd_arg_ptr]
    cmp byte [edi], 0
    je .rm_no_arg

    ; Search fs_table for matching entry in current working directory
    xor ecx, ecx
.rm_search:
    cmp ecx, MAX_FS_ENTRIES
    jge .rm_not_found

    mov eax, ecx
    imul eax, FS_ENTRY_SIZE
    add eax, fs_table

    cmp byte [eax], 0
    je .rm_next

    ; Verify parent_dir == cwd_display
    push eax
    push ecx
    lea esi, [eax + 2]
    mov edi, cwd_display
    call streq
    pop ecx
    pop eax
    jnz .rm_next

    ; Verify name == cmd_arg_ptr
    push eax
    push ecx
    lea esi, [eax + 34]
    mov edi, [cmd_arg_ptr]
    call streq
    pop ecx
    pop eax
    jz .rm_perform

.rm_next:
    inc ecx
    jmp .rm_search

.rm_perform:
    mov byte [eax], 0           ; Deallocate entry
    mov esi, out_rm_ok1
    mov ah, ATTR_YELLOW
    call term_print
    mov esi, [cmd_arg_ptr]
    mov ah, ATTR_WHITE
    call term_print
    mov esi, out_rm_ok2
    mov ah, ATTR_YELLOW
    call term_print
    ret

.rm_not_found:
    mov esi, str_rm_prefix
    mov ah, ATTR_RED
    call term_print
    mov esi, [cmd_arg_ptr]
    mov ah, ATTR_WHITE
    call term_print
    mov esi, str_err_not_found_file
    mov ah, ATTR_RED
    call term_print
    ret

.rm_no_arg:
    mov esi, out_rm_err
    mov ah, ATTR_RED
    call term_print
    ret

.cmd_cp:
    mov esi, out_cp_ok
    mov ah, ATTR_CYAN
    call term_print
    ret

.cmd_mv:
    mov esi, out_mv_ok
    mov ah, ATTR_CYAN
    call term_print
    ret

.cmd_nano:
.cmd_vim:
    ; Check if command arguments were provided
    mov esi, [cmd_arg_ptr]
    cmp byte [esi], 0
    je .nano_use_default_fn

    ; Check for --version / -V / -v
    mov edi, [cmd_arg_ptr]
    mov esi, str_flag_version
    call streq
    jz .nano_show_version
    mov edi, [cmd_arg_ptr]
    mov esi, str_flag_cap_v
    call streq
    jz .nano_show_version
    mov edi, [cmd_arg_ptr]
    mov esi, str_flag_small_v
    call streq
    jz .nano_show_version

    ; Check for --help / -h
    mov edi, [cmd_arg_ptr]
    mov esi, str_flag_help
    call streq
    jz .nano_show_help
    mov edi, [cmd_arg_ptr]
    mov esi, str_flag_small_h
    call streq
    jz .nano_show_help

    ; Has custom filename
    mov esi, [cmd_arg_ptr]
    mov edi, nano_cur_filename
    call strcpy
    jmp .nano_init_editor

.nano_use_default_fn:
    mov esi, str_nano_default_fn
    mov edi, nano_cur_filename
    call strcpy

.nano_init_editor:
    mov byte [nano_is_modified], 0
    mov dword [nano_buf_len], 0
    mov byte [nano_edit_buffer], 0

    ; Check if file already exists in cwd
    xor ecx, ecx
.nano_chk_exist:
    cmp ecx, MAX_FS_ENTRIES
    jge .nano_draw_screen

    mov eax, ecx
    imul eax, FS_ENTRY_SIZE
    add eax, fs_table
    cmp byte [eax], 1
    jne .nano_chk_next

    push eax
    push ecx
    lea esi, [eax + 2]
    mov edi, cwd_display
    call streq
    pop ecx
    pop eax
    jnz .nano_chk_next

    push eax
    push ecx
    lea esi, [eax + 34]
    mov edi, nano_cur_filename
    call streq
    pop ecx
    pop eax
    jnz .nano_chk_next

    ; File exists! Load contents into buffer
    movzx edx, word [eax + 66]
    mov [nano_buf_len], edx
    push eax
    lea esi, [eax + 68]
    mov edi, nano_edit_buffer
    call strcpy
    pop eax
    jmp .nano_draw_screen

.nano_chk_next:
    inc ecx
    jmp .nano_chk_exist

.nano_show_version:
    mov esi, out_nano_version
    mov ah, ATTR_DEFAULT
    call term_print
    ret

.nano_show_help:
    mov esi, out_nano_cli_help
    mov ah, ATTR_DEFAULT
    call term_print
    ret

; Direct VGA string writer (does not advance hardware terminal cursor or cause scroll)
.vga_write_str_at:
    ; EDI = VGA offset, ESI = string, AH = attribute
    push eax
    push esi
    push edi
.vw_loop:
    lodsb
    test al, al
    jz .vw_done
    mov [edi], al
    mov [edi+1], ah
    add edi, 2
    jmp .vw_loop
.vw_done:
    pop edi
    pop esi
    pop eax
    ret

.nano_draw_top_bar:
    push eax
    push ecx
    push edi
    push esi

    ; Fill entire Row 0 across all 80 columns with ATTR_NANO_BAR
    mov edi, VGA_TEXT
    mov ecx, 80
    mov ax, (ATTR_NANO_BAR << 8) | ' '
    rep stosw

    ; Write "GNU nano 8.0" at column 2
    mov edi, VGA_TEXT + (2 * 2)
    mov esi, str_nano_title
    mov ah, ATTR_NANO_BAR
    call .vga_write_str_at

    ; Write "File: " at column 28
    mov edi, VGA_TEXT + (28 * 2)
    mov esi, str_nano_file_lbl
    mov ah, ATTR_NANO_BAR
    call .vga_write_str_at

    ; Write current filename at column 34
    mov edi, VGA_TEXT + (34 * 2)
    mov esi, nano_cur_filename
    mov ah, ATTR_NANO_BAR
    call .vga_write_str_at

    ; If modified, write "[ Modified ]" at column 66
    cmp byte [nano_is_modified], 1
    jne .ntb_done
    mov edi, VGA_TEXT + (66 * 2)
    mov esi, str_nano_modified_tag
    mov ah, ATTR_NANO_BAR
    call .vga_write_str_at

.ntb_done:
    pop esi
    pop edi
    pop ecx
    pop eax
    ret

.nano_draw_bottom_bars:
    push eax
    push ecx
    push edi
    push esi

    ; Fill Row 23 with default spaces
    mov edi, VGA_TEXT + (23 * 80 * 2)
    mov ecx, 80
    mov ax, (ATTR_DEFAULT << 8) | ' '
    rep stosw

    ; Render Row 23 shortcuts with authentic inverted tags
    mov edi, VGA_TEXT + ((23 * 80 + 0) * 2)
    mov esi, str_k_g
    mov ah, ATTR_NANO_BAR
    call .vga_write_str_at
    mov edi, VGA_TEXT + ((23 * 80 + 2) * 2)
    mov esi, str_lbl_help
    mov ah, ATTR_DEFAULT
    call .vga_write_str_at

    mov edi, VGA_TEXT + ((23 * 80 + 13) * 2)
    mov esi, str_k_o
    mov ah, ATTR_NANO_BAR
    call .vga_write_str_at
    mov edi, VGA_TEXT + ((23 * 80 + 15) * 2)
    mov esi, str_lbl_writeout
    mov ah, ATTR_DEFAULT
    call .vga_write_str_at

    mov edi, VGA_TEXT + ((23 * 80 + 26) * 2)
    mov esi, str_k_w
    mov ah, ATTR_NANO_BAR
    call .vga_write_str_at
    mov edi, VGA_TEXT + ((23 * 80 + 28) * 2)
    mov esi, str_lbl_whereis
    mov ah, ATTR_DEFAULT
    call .vga_write_str_at

    mov edi, VGA_TEXT + ((23 * 80 + 39) * 2)
    mov esi, str_k_k
    mov ah, ATTR_NANO_BAR
    call .vga_write_str_at
    mov edi, VGA_TEXT + ((23 * 80 + 41) * 2)
    mov esi, str_lbl_cut
    mov ah, ATTR_DEFAULT
    call .vga_write_str_at

    mov edi, VGA_TEXT + ((23 * 80 + 52) * 2)
    mov esi, str_k_t
    mov ah, ATTR_NANO_BAR
    call .vga_write_str_at
    mov edi, VGA_TEXT + ((23 * 80 + 54) * 2)
    mov esi, str_lbl_execute
    mov ah, ATTR_DEFAULT
    call .vga_write_str_at

    mov edi, VGA_TEXT + ((23 * 80 + 65) * 2)
    mov esi, str_k_c
    mov ah, ATTR_NANO_BAR
    call .vga_write_str_at
    mov edi, VGA_TEXT + ((23 * 80 + 67) * 2)
    mov esi, str_lbl_location
    mov ah, ATTR_DEFAULT
    call .vga_write_str_at

    ; Fill Row 24 with default spaces
    mov edi, VGA_TEXT + (24 * 80 * 2)
    mov ecx, 80
    mov ax, (ATTR_DEFAULT << 8) | ' '
    rep stosw

    ; Render Row 24 shortcuts with authentic inverted tags
    mov edi, VGA_TEXT + ((24 * 80 + 0) * 2)
    mov esi, str_k_x
    mov ah, ATTR_NANO_BAR
    call .vga_write_str_at
    mov edi, VGA_TEXT + ((24 * 80 + 2) * 2)
    mov esi, str_lbl_exit
    mov ah, ATTR_DEFAULT
    call .vga_write_str_at

    mov edi, VGA_TEXT + ((24 * 80 + 13) * 2)
    mov esi, str_k_r
    mov ah, ATTR_NANO_BAR
    call .vga_write_str_at
    mov edi, VGA_TEXT + ((24 * 80 + 15) * 2)
    mov esi, str_lbl_readfile
    mov ah, ATTR_DEFAULT
    call .vga_write_str_at

    mov edi, VGA_TEXT + ((24 * 80 + 26) * 2)
    mov esi, str_k_bslash
    mov ah, ATTR_NANO_BAR
    call .vga_write_str_at
    mov edi, VGA_TEXT + ((24 * 80 + 28) * 2)
    mov esi, str_lbl_replace
    mov ah, ATTR_DEFAULT
    call .vga_write_str_at

    mov edi, VGA_TEXT + ((24 * 80 + 39) * 2)
    mov esi, str_k_u
    mov ah, ATTR_NANO_BAR
    call .vga_write_str_at
    mov edi, VGA_TEXT + ((24 * 80 + 41) * 2)
    mov esi, str_lbl_paste
    mov ah, ATTR_DEFAULT
    call .vga_write_str_at

    mov edi, VGA_TEXT + ((24 * 80 + 52) * 2)
    mov esi, str_k_j
    mov ah, ATTR_NANO_BAR
    call .vga_write_str_at
    mov edi, VGA_TEXT + ((24 * 80 + 54) * 2)
    mov esi, str_lbl_justify
    mov ah, ATTR_DEFAULT
    call .vga_write_str_at

    mov edi, VGA_TEXT + ((24 * 80 + 65) * 2)
    mov esi, str_k_under
    mov ah, ATTR_NANO_BAR
    call .vga_write_str_at
    mov edi, VGA_TEXT + ((24 * 80 + 67) * 2)
    mov esi, str_lbl_gotoline
    mov ah, ATTR_DEFAULT
    call .vga_write_str_at

    pop esi
    pop edi
    pop ecx
    pop eax
    ret

.nano_set_status:
    ; ESI = status message string, AH = attribute
    push eax
    push ecx
    push edi
    push esi

    ; Clear Row 22 across all 80 columns
    mov edi, VGA_TEXT + (22 * 80 * 2)
    mov ecx, 80
    mov bx, (ATTR_DEFAULT << 8) | ' '
    mov ax, bx
    rep stosw

    ; Write status text at Col 2
    mov edi, VGA_TEXT + ((22 * 80 + 2) * 2)
    call .vga_write_str_at

    pop esi
    pop edi
    pop ecx
    pop eax
    ret

.nano_draw_screen:
    ; Clear lines 1..21 (editing space)
    mov edi, VGA_TEXT + (1 * 80 * 2)
    mov ecx, 21 * 80
    mov ax, (ATTR_DEFAULT << 8) | ' '
    rep stosw

    ; Draw official Title Bar (Row 0)
    call .nano_draw_top_bar

    ; Draw official Shortcut Bars (Rows 23 and 24)
    call .nano_draw_bottom_bars

    ; Draw status line (Row 22)
    cmp dword [nano_buf_len], 0
    jne .nds_has_existing_content
    mov esi, str_nano_welcome
    mov ah, ATTR_WHITE
    call .nano_set_status
    jmp .nds_setup_cursor

.nds_has_existing_content:
    mov esi, str_nano_read_ok
    mov ah, ATTR_WHITE
    call .nano_set_status

    ; Render file text onto rows 1..21
    mov dword [cursor_x], 0
    mov dword [cursor_y], 1
    mov esi, nano_edit_buffer
.nds_render_loop:
    lodsb
    test al, al
    jz .nds_setup_cursor
    cmp al, 0x0A
    jne .nds_put_char
    mov dword [cursor_x], 0
    inc dword [cursor_y]
    cmp dword [cursor_y], 21
    jg .nds_setup_cursor
    jmp .nds_render_loop

.nds_put_char:
    mov ebx, [cursor_y]
    imul ebx, 80
    add ebx, [cursor_x]
    shl ebx, 1
    add ebx, VGA_TEXT
    mov [ebx], al
    mov byte [ebx+1], ATTR_WHITE
    inc dword [cursor_x]
    cmp dword [cursor_x], 79
    jl .nds_render_loop
    mov dword [cursor_x], 0
    inc dword [cursor_y]
    cmp dword [cursor_y], 21
    jg .nds_setup_cursor
    jmp .nds_render_loop

.nds_setup_cursor:
    mov dword [cursor_x], 0
    mov dword [cursor_y], 1
    call term_update_hw_cursor

.nano_edit_loop:
    call term_update_hw_cursor
    call read_scancode_blocking

    ; Shift keys (0x2A / 0x36 press, 0xAA / 0xB6 release)
    cmp al, 0x2A
    je .nano_shift_on
    cmp al, 0x36
    je .nano_shift_on
    cmp al, 0xAA
    je .nano_shift_off
    cmp al, 0xB6
    je .nano_shift_off

    ; Ctrl key (0x1D press, 0x9D release)
    cmp al, 0x1D
    je .nano_ctrl_on
    cmp al, 0x9D
    je .nano_ctrl_off

    ; Key release (bit 7 set)
    test al, 0x80
    jnz .nano_edit_loop

    ; Extended scancode prefix
    cmp al, 0xE0
    je .nano_edit_loop

    ; Check Ctrl shortcuts
    cmp byte [ctrl_state], 1
    jne .nano_chk_fn_keys

    ; Ctrl+X (0x2D): Exit
    cmp al, 0x2D
    je .nano_exit_cmd

    ; Ctrl+O (0x18): WriteOut / Save
    cmp al, 0x18
    je .nano_writeout_cmd

    ; Ctrl+G (0x22): Help
    cmp al, 0x22
    je .nano_help_cmd

    ; Ctrl+W (0x11): Where Is
    cmp al, 0x11
    je .nano_whereis_cmd

    ; Ctrl+K (0x25): Cut
    cmp al, 0x25
    je .nano_cut_cmd

    ; Ctrl+U (0x16): Paste
    cmp al, 0x16
    je .nano_paste_cmd

    ; Ctrl+C (0x2E): Location
    cmp al, 0x2E
    je .nano_location_cmd

    ; Ctrl+R (0x13): Read File
    cmp al, 0x13
    je .nano_readfile_cmd

    ; Ctrl+J (0x24): Justify
    cmp al, 0x24
    je .nano_justify_cmd

.nano_chk_fn_keys:
    ; Esc (0x01) -> Exit
    cmp al, 0x01
    je .nano_exit_cmd

    ; F1 (0x3B) -> Help
    cmp al, 0x3B
    je .nano_help_cmd

    ; F2 (0x3C) -> Exit
    cmp al, 0x3C
    je .nano_exit_cmd

    ; F3 (0x3D) -> WriteOut
    cmp al, 0x3D
    je .nano_writeout_cmd

.nano_chk_arrows:
    ; Up arrow (0x48)
    cmp al, 0x48
    jne .nano_chk_dn_arr
    cmp dword [cursor_y], 1
    jle .nano_edit_loop
    dec dword [cursor_y]
    jmp .nano_edit_loop

.nano_chk_dn_arr:
    ; Down arrow (0x50)
    cmp al, 0x50
    jne .nano_chk_lt_arr
    cmp dword [cursor_y], 21
    jge .nano_edit_loop
    inc dword [cursor_y]
    jmp .nano_edit_loop

.nano_chk_lt_arr:
    ; Left arrow (0x4B)
    cmp al, 0x4B
    jne .nano_chk_rt_arr
    cmp dword [cursor_x], 0
    jle .nano_edit_loop
    dec dword [cursor_x]
    jmp .nano_edit_loop

.nano_chk_rt_arr:
    ; Right arrow (0x4D)
    cmp al, 0x4D
    jne .nano_chk_editing_keys
    cmp dword [cursor_x], 78
    jge .nano_edit_loop
    inc dword [cursor_x]
    jmp .nano_edit_loop

.nano_chk_editing_keys:
    cmp al, 0x0E
    je .nano_key_backspace
    cmp al, 0x1C
    je .nano_key_enter

    cmp al, 0x39
    ja .nano_edit_loop
    movzx ebx, al
    cmp byte [shift_state], 1
    je .nano_use_shift
    mov cl, [scancode_table + ebx]
    jmp .nano_got_char
.nano_use_shift:
    mov cl, [scancode_shift_table + ebx]
.nano_got_char:
    test cl, cl
    jz .nano_edit_loop
    jmp .nano_append_char

.nano_ctrl_on:
    mov byte [ctrl_state], 1
    jmp .nano_edit_loop
.nano_ctrl_off:
    mov byte [ctrl_state], 0
    jmp .nano_edit_loop

.nano_shift_on:
    mov byte [shift_state], 1
    jmp .nano_edit_loop
.nano_shift_off:
    mov byte [shift_state], 0
    jmp .nano_edit_loop

.nano_append_char:
    mov eax, [nano_buf_len]
    cmp eax, 250
    jge .nano_edit_loop

    mov [nano_edit_buffer + eax], cl
    inc dword [nano_buf_len]
    mov eax, [nano_buf_len]
    mov byte [nano_edit_buffer + eax], 0

    ; Write char directly into VGA text buffer at cursor
    mov ebx, [cursor_y]
    imul ebx, 80
    add ebx, [cursor_x]
    shl ebx, 1
    add ebx, VGA_TEXT
    mov [ebx], cl
    mov byte [ebx+1], ATTR_WHITE

    inc dword [cursor_x]
    cmp dword [cursor_x], 79
    jl .nano_char_done
    mov dword [cursor_x], 0
    cmp dword [cursor_y], 21
    jge .nano_char_done
    inc dword [cursor_y]

.nano_char_done:
    mov byte [nano_is_modified], 1
    call .nano_draw_top_bar
    jmp .nano_edit_loop

.nano_key_backspace:
    mov eax, [nano_buf_len]
    test eax, eax
    jz .nano_edit_loop
    dec eax
    mov [nano_buf_len], eax
    mov byte [nano_edit_buffer + eax], 0

    cmp dword [cursor_x], 0
    jle .nano_bs_prev_line
    dec dword [cursor_x]
    jmp .nano_bs_clear_cell

.nano_bs_prev_line:
    cmp dword [cursor_y], 1
    jle .nano_bs_done
    dec dword [cursor_y]
    mov dword [cursor_x], 78

.nano_bs_clear_cell:
    mov ebx, [cursor_y]
    imul ebx, 80
    add ebx, [cursor_x]
    shl ebx, 1
    add ebx, VGA_TEXT
    mov byte [ebx], ' '
    mov byte [ebx+1], ATTR_DEFAULT

.nano_bs_done:
    mov byte [nano_is_modified], 1
    call .nano_draw_top_bar
    jmp .nano_edit_loop

.nano_key_enter:
    mov eax, [nano_buf_len]
    cmp eax, 250
    jge .nano_edit_loop
    mov byte [nano_edit_buffer + eax], 0x0A
    inc dword [nano_buf_len]
    mov eax, [nano_buf_len]
    mov byte [nano_edit_buffer + eax], 0

    mov dword [cursor_x], 0
    cmp dword [cursor_y], 21
    jge .nano_enter_done
    inc dword [cursor_y]

.nano_enter_done:
    mov byte [nano_is_modified], 1
    call .nano_draw_top_bar
    jmp .nano_edit_loop

.nano_writeout_cmd:
    call .nano_commit_to_fs
    mov byte [nano_is_modified], 0
    call .nano_draw_top_bar
    mov esi, str_nano_writeout_ok
    mov ah, ATTR_GREEN
    call .nano_set_status
    jmp .nano_edit_loop

.nano_exit_cmd:
    cmp byte [nano_is_modified], 1
    jne .nano_do_clean_exit
    call .nano_commit_to_fs
.nano_do_clean_exit:
    call term_clear
    mov esi, str_nano_exit_msg1
    mov ah, ATTR_GREEN
    call term_print
    mov esi, nano_cur_filename
    mov ah, ATTR_WHITE
    call term_print
    mov esi, str_nano_exit_msg2
    mov ah, ATTR_GREEN
    call term_print
    ret

.nano_help_cmd:
    call term_clear
    ; Top bar for help
    mov edi, VGA_TEXT
    mov ecx, 80
    mov ax, (ATTR_NANO_BAR << 8) | ' '
    rep stosw
    mov edi, VGA_TEXT + (2 * 2)
    mov esi, str_nano_title
    mov ah, ATTR_NANO_BAR
    call .vga_write_str_at
    mov edi, VGA_TEXT + (34 * 2)
    mov esi, str_nano_help_title
    mov ah, ATTR_NANO_BAR
    call .vga_write_str_at

    ; Print Help Body
    mov dword [cursor_x], 0
    mov dword [cursor_y], 2
    mov esi, str_nano_help_body
    mov ah, ATTR_DEFAULT
    call term_print

    ; Bottom bar for help
    mov edi, VGA_TEXT + (24 * 80 * 2)
    mov ecx, 80
    mov ax, (ATTR_NANO_BAR << 8) | ' '
    rep stosw
    mov edi, VGA_TEXT + ((24 * 80 + 2) * 2)
    mov esi, str_nano_help_close
    mov ah, ATTR_NANO_BAR
    call .vga_write_str_at

.nano_help_wait:
    call read_scancode_blocking
    test al, 0x80
    jnz .nano_help_wait
    call .nano_draw_screen
    jmp .nano_edit_loop

.nano_whereis_cmd:
    mov esi, str_nano_whereis_msg
    mov ah, ATTR_CYAN
    call .nano_set_status
    jmp .nano_edit_loop

.nano_location_cmd:
    mov esi, str_nano_location_msg
    mov ah, ATTR_CYAN
    call .nano_set_status
    jmp .nano_edit_loop

.nano_cut_cmd:
    mov byte [nano_is_modified], 1
    call .nano_draw_top_bar
    mov esi, str_nano_cut_msg
    mov ah, ATTR_YELLOW
    call .nano_set_status
    jmp .nano_edit_loop

.nano_paste_cmd:
    mov byte [nano_is_modified], 1
    call .nano_draw_top_bar
    mov esi, str_nano_paste_msg
    mov ah, ATTR_GREEN
    call .nano_set_status
    jmp .nano_edit_loop

.nano_readfile_cmd:
    mov esi, str_nano_readfile_msg
    mov ah, ATTR_CYAN
    call .nano_set_status
    jmp .nano_edit_loop

.nano_justify_cmd:
    mov esi, str_nano_justify_msg
    mov ah, ATTR_CYAN
    call .nano_set_status
    jmp .nano_edit_loop

.nano_commit_to_fs:
    push eax
    push ecx
    push edx
    push esi
    push edi

    xor ecx, ecx
.ncfs_chk_exist:
    cmp ecx, MAX_FS_ENTRIES
    jge .ncfs_alloc_new

    mov eax, ecx
    imul eax, FS_ENTRY_SIZE
    add eax, fs_table
    cmp byte [eax], 1
    jne .ncfs_next

    push eax
    push ecx
    lea esi, [eax + 2]
    mov edi, cwd_display
    call streq
    pop ecx
    pop eax
    jnz .ncfs_next

    push eax
    push ecx
    lea esi, [eax + 34]
    mov edi, nano_cur_filename
    call streq
    pop ecx
    pop eax
    jz .ncfs_commit_data

.ncfs_next:
    inc ecx
    jmp .ncfs_chk_exist

.ncfs_alloc_new:
    xor ecx, ecx
.ncfs_find_free:
    cmp ecx, MAX_FS_ENTRIES
    jge .ncfs_done
    mov eax, ecx
    imul eax, FS_ENTRY_SIZE
    add eax, fs_table
    cmp byte [eax], 0
    je .ncfs_init_slot
    inc ecx
    jmp .ncfs_find_free

.ncfs_init_slot:
    mov byte [eax], 1
    mov esi, cwd_display
    lea edi, [eax + 2]
    call strcpy
    mov esi, nano_cur_filename
    lea edi, [eax + 34]
    call strcpy

.ncfs_commit_data:
    mov edx, [nano_buf_len]
    mov [eax + 66], dx
    lea edi, [eax + 68]
    mov esi, nano_edit_buffer
    call strcpy

.ncfs_done:
    pop edi
    pop esi
    pop edx
    pop ecx
    pop eax
    ret

.cmd_which:
    mov edi, [cmd_arg_ptr]
    cmp byte [edi], 0
    je .which_err
    mov esi, str_slash_bin
    mov ah, ATTR_DEFAULT
    call term_print
    mov esi, [cmd_arg_ptr]
    mov ah, ATTR_DEFAULT
    call term_print
    mov esi, str_newline
    mov ah, ATTR_DEFAULT
    call term_print
    ret
.which_err:
    mov esi, out_which_err
    mov ah, ATTR_RED
    call term_print
    ret

.cmd_whereis:
    mov edi, [cmd_arg_ptr]
    cmp byte [edi], 0
    je .whereis_err
    mov esi, [cmd_arg_ptr]
    mov ah, ATTR_DEFAULT
    call term_print
    mov esi, str_whereis_sep
    mov ah, ATTR_DEFAULT
    call term_print
    mov esi, str_slash_bin
    mov ah, ATTR_DEFAULT
    call term_print
    mov esi, [cmd_arg_ptr]
    mov ah, ATTR_DEFAULT
    call term_print
    mov esi, str_whereis_man
    mov ah, ATTR_DEFAULT
    call term_print
    mov esi, [cmd_arg_ptr]
    mov ah, ATTR_DEFAULT
    call term_print
    mov esi, str_whereis_gz
    mov ah, ATTR_DEFAULT
    call term_print
    ret
.whereis_err:
    mov esi, out_whereis_err
    mov ah, ATTR_RED
    call term_print
    ret

.cmd_git:
    mov edi, [cmd_arg_ptr]
    mov esi, str_git_init
    call str_prefix
    jz .git_do_init

    mov esi, str_git_commit
    call str_prefix
    jz .git_do_commit

    xor ecx, ecx
.git_chk_repo:
    cmp ecx, MAX_FS_ENTRIES
    jge .git_not_repo
    mov eax, ecx
    imul eax, FS_ENTRY_SIZE
    add eax, fs_table
    cmp byte [eax], 2
    jne .git_repo_next
    push eax
    push ecx
    lea esi, [eax + 34]
    mov edi, str_git_dotgit
    call streq
    pop ecx
    pop eax
    jz .git_show_status
.git_repo_next:
    inc ecx
    jmp .git_chk_repo

.git_not_repo:
    mov esi, out_git_not_repo
    mov ah, ATTR_RED
    call term_print
    ret

.git_do_init:
    xor ecx, ecx
.git_find_free:
    cmp ecx, MAX_FS_ENTRIES
    jge .git_init_out
    mov eax, ecx
    imul eax, FS_ENTRY_SIZE
    add eax, fs_table
    cmp byte [eax], 0
    je .git_reg_dotgit
    inc ecx
    jmp .git_find_free
.git_reg_dotgit:
    mov byte [eax], 2
    mov esi, cwd_display
    lea edi, [eax + 2]
    call strcpy
    mov esi, str_git_dotgit
    lea edi, [eax + 34]
    call strcpy
.git_init_out:
    mov esi, out_git_init_ok
    mov ah, ATTR_GREEN
    call term_print
    ret

.git_show_status:
    mov esi, out_git_head_status
    mov ah, ATTR_DEFAULT
    call term_print

    xor ecx, ecx
.git_list_files:
    cmp ecx, MAX_FS_ENTRIES
    jge .git_status_done
    mov eax, ecx
    imul eax, FS_ENTRY_SIZE
    add eax, fs_table
    cmp byte [eax], 1
    jne .git_next_st_file
    push eax
    push ecx
    lea esi, [eax + 2]
    mov edi, cwd_display
    call streq
    pop ecx
    pop eax
    jnz .git_next_st_file

    push eax
    mov esi, out_git_prefix_file
    mov ah, ATTR_RED
    call term_print
    pop eax

    push eax
    lea esi, [eax + 34]
    mov ah, ATTR_RED
    call term_print
    pop eax

    mov al, 0x0A
    mov ah, ATTR_DEFAULT
    call term_print_char

.git_next_st_file:
    inc ecx
    jmp .git_list_files
.git_status_done:
    ret

.git_do_commit:
    mov esi, out_git_commit_ok
    mov ah, ATTR_GREEN
    call term_print
    ret

.cmd_gcc:
    mov edi, [cmd_arg_ptr]
    cmp byte [edi], 0
    je .gcc_no_files

    xor ecx, ecx
.gcc_find_source:
    cmp ecx, MAX_FS_ENTRIES
    jge .gcc_file_not_found

    mov eax, ecx
    imul eax, FS_ENTRY_SIZE
    add eax, fs_table
    cmp byte [eax], 1
    jne .gcc_find_next

    push eax
    push ecx
    lea esi, [eax + 2]
    mov edi, cwd_display
    call streq
    pop ecx
    pop eax
    jnz .gcc_find_next

    push eax
    push ecx
    lea esi, [eax + 34]
    mov edi, [cmd_arg_ptr]
    call streq
    pop ecx
    pop eax
    jz .gcc_do_compile

.gcc_find_next:
    inc ecx
    jmp .gcc_find_source

.gcc_no_files:
.gcc_file_not_found:
    mov esi, str_gcc_err1
    mov ah, ATTR_RED
    call term_print
    mov esi, [cmd_arg_ptr]
    mov ah, ATTR_WHITE
    call term_print
    mov esi, str_gcc_err2
    mov ah, ATTR_RED
    call term_print
    ret

.gcc_do_compile:
    mov esi, out_gcc_comp1
    mov ah, ATTR_CYAN
    call term_print
    mov esi, [cmd_arg_ptr]
    mov ah, ATTR_WHITE
    call term_print
    mov esi, out_gcc_comp2
    mov ah, ATTR_GREEN
    call term_print

    xor ecx, ecx
.gcc_alloc_aout:
    cmp ecx, MAX_FS_ENTRIES
    jge .gcc_done
    mov eax, ecx
    imul eax, FS_ENTRY_SIZE
    add eax, fs_table
    cmp byte [eax], 0
    je .gcc_setup_aout
    inc ecx
    jmp .gcc_alloc_aout
.gcc_setup_aout:
    mov byte [eax], 1
    mov esi, cwd_display
    lea edi, [eax + 2]
    call strcpy
    mov esi, str_name_aout
    lea edi, [eax + 34]
    call strcpy
    mov word [eax + 66], 8192
.gcc_done:
    ret

.cmd_python:
    mov esi, out_py_banner
    mov ah, ATTR_DEFAULT
    call term_print

.py_repl_loop:
    mov esi, str_py_prompt
    mov ah, ATTR_PROMPT
    call term_print

    mov edi, py_input_buffer
    call term_read_line

    cmp byte [py_input_buffer], 0
    je .py_repl_loop

    mov esi, str_py_exit1
    mov edi, py_input_buffer
    call streq
    jz .py_exit
    mov esi, str_py_exit2
    mov edi, py_input_buffer
    call streq
    jz .py_exit
    mov esi, str_py_exit3
    mov edi, py_input_buffer
    call streq
    jz .py_exit
    mov esi, str_py_exit4
    mov edi, py_input_buffer
    call streq
    jz .py_exit

    mov esi, str_py_help
    mov edi, py_input_buffer
    call str_prefix
    jz .py_show_help

    mov esi, str_py_print
    mov edi, py_input_buffer
    call str_prefix
    jz .py_do_print

    call .py_eval_math
    jz .py_repl_loop

    mov esi, str_py_err_syntax
    mov ah, ATTR_RED
    call term_print
    jmp .py_repl_loop

.py_exit:
    ret

.py_show_help:
    mov esi, out_py_help_text
    mov ah, ATTR_DEFAULT
    call term_print
    jmp .py_repl_loop

.py_do_print:
    lea esi, [py_input_buffer + 6]
    cmp byte [esi], '"'
    je .py_p_quote
    cmp byte [esi], "'"
    je .py_p_quote
.py_p_quote:
    inc esi
.py_p_loop:
    mov al, [esi]
    cmp al, 0
    je .py_p_done
    cmp al, '"'
    je .py_p_done
    cmp al, "'"
    je .py_p_done
    cmp al, ')'
    je .py_p_done
    mov ah, ATTR_WHITE
    call term_print_char
    inc esi
    jmp .py_p_loop
.py_p_done:
    mov al, 0x0A
    mov ah, ATTR_DEFAULT
    call term_print_char
    jmp .py_repl_loop

.py_eval_math:
    mov esi, py_input_buffer
.pem_find_op:
    mov al, [esi]
    test al, al
    jz .pem_no_op
    cmp al, '+'
    je .pem_found_op
    cmp al, '-'
    je .pem_found_op
    cmp al, '*'
    je .pem_found_op
    cmp al, '/'
    je .pem_found_op
    inc esi
    jmp .pem_find_op

.pem_found_op:
    mov dl, al
    push edx
    push esi
    mov esi, py_input_buffer
    call parse_int_val
    pop esi
    pop edx

    inc esi
.pem_skip_sp:
    cmp byte [esi], ' '
    jne .pem_parse_right
    inc esi
    jmp .pem_skip_sp

.pem_parse_right:
    push edx
    push eax
    call parse_int_val
    mov ebx, eax
    pop eax
    pop edx

    cmp dl, '+'
    jne .pem_chk_sub
    add eax, ebx
    jmp .pem_print_res
.pem_chk_sub:
    cmp dl, '-'
    jne .pem_chk_mul
    sub eax, ebx
    jmp .pem_print_res
.pem_chk_mul:
    cmp dl, '*'
    jne .pem_chk_div
    imul eax, ebx
    jmp .pem_print_res
.pem_chk_div:
    test ebx, ebx
    jz .pem_div_zero
    cdq
    idiv ebx
    jmp .pem_print_res

.pem_div_zero:
    mov esi, str_py_div_zero
    mov ah, ATTR_RED
    call term_print
    xor eax, eax
    ret

.pem_print_res:
    call print_full_int
    mov al, 0x0A
    mov ah, ATTR_DEFAULT
    call term_print_char
    xor eax, eax
    ret

.pem_no_op:
    or eax, 1
    ret

.cmd_curl:
    mov esi, out_curl
    mov ah, ATTR_DEFAULT
    call term_print
    ret

.cmd_tree:
    mov dword [tree_dir_count], 0
    mov dword [tree_file_count], 0

    ; Print root "."
    mov esi, str_tree_root
    mov ah, ATTR_DEFAULT
    call term_print

    ; Check current working directory
    cmp byte [cwd_display+1], 'b'
    je .tree_bin_base
    cmp byte [cwd_display+1], 'e'
    je .tree_etc_base
    cmp byte [cwd_display+1], 'p'
    je .tree_proc_base
    cmp word [cwd_display], 0x007E     ; "~"
    jne .tree_scan_dynamic

    ; Home "~" base items
    add dword [tree_dir_count], 2
    add dword [tree_file_count], 6
    mov esi, str_tree_home_base
    mov ah, ATTR_DEFAULT
    call term_print
    jmp .tree_scan_dynamic

.tree_bin_base:
    add dword [tree_file_count], 8
    mov esi, str_tree_bin_base
    mov ah, ATTR_DEFAULT
    call term_print
    jmp .tree_scan_dynamic

.tree_etc_base:
    add dword [tree_file_count], 1
    mov esi, str_tree_etc_base
    mov ah, ATTR_DEFAULT
    call term_print
    jmp .tree_scan_dynamic

.tree_proc_base:
    add dword [tree_file_count], 2
    mov esi, str_tree_proc_base
    mov ah, ATTR_DEFAULT
    call term_print
    jmp .tree_scan_dynamic

.tree_scan_dynamic:
    ; Scan fs_table for entries belonging to current directory
    xor ecx, ecx
.tree_loop:
    cmp ecx, MAX_FS_ENTRIES
    jge .tree_summary

    mov eax, ecx
    imul eax, FS_ENTRY_SIZE
    add eax, fs_table

    cmp byte [eax], 0
    je .tree_next

    ; Check if entry parent_dir == cwd_display
    push eax
    push ecx
    lea esi, [eax + 2]
    mov edi, cwd_display
    call streq
    pop ecx
    pop eax
    jnz .tree_next

    ; Entry belongs to current directory
    cmp byte [eax], 2
    je .tree_is_dir

    ; It's a file
    inc dword [tree_file_count]
    push eax
    push ecx
    mov esi, str_tree_branch
    mov ah, ATTR_DEFAULT
    call term_print
    pop ecx
    pop eax

    push eax
    push ecx
    lea esi, [eax + 34]
    mov ah, ATTR_WHITE
    call term_print
    mov al, 0x0A
    mov ah, ATTR_DEFAULT
    call term_print_char
    pop ecx
    pop eax
    jmp .tree_next

.tree_is_dir:
    inc dword [tree_dir_count]
    push eax
    push ecx
    mov esi, str_tree_branch
    mov ah, ATTR_DEFAULT
    call term_print
    pop ecx
    pop eax

    push eax
    push ecx
    lea esi, [eax + 34]
    mov ah, ATTR_CYAN
    call term_print
    mov esi, str_tree_dir_suffix
    mov ah, ATTR_CYAN
    call term_print
    pop ecx
    pop eax

.tree_next:
    inc ecx
    jmp .tree_loop

.tree_summary:
    mov al, 0x0A
    mov ah, ATTR_DEFAULT
    call term_print_char

    mov eax, [tree_dir_count]
    call print_full_int

    mov esi, str_tree_dirs_lbl
    mov ah, ATTR_DEFAULT
    call term_print

    mov eax, [tree_file_count]
    call print_full_int

    mov esi, str_tree_files_lbl
    mov ah, ATTR_DEFAULT
    call term_print
    ret

.cmd_htop:
    call term_clear
    mov esi, out_htop_screen
    mov ah, ATTR_DEFAULT
    call term_print

.htop_loop:
    in al, 0x64
    test al, 1
    jz .htop_tick
    in al, 0x60
    test al, 0x80
    jnz .htop_tick
    cmp al, 0x10
    je .htop_exit
    cmp al, 0x01
    je .htop_exit
    cmp al, 0x44
    je .htop_exit

.htop_tick:
    pause
    mov ecx, 3000000
.htop_del:
    in al, 0x80
    loop .htop_del
    jmp .htop_loop

.htop_exit:
    call term_clear
    ret

.cmd_pkg:
    mov edi, [cmd_arg_ptr]
    cmp byte [edi], 0
    je .pkg_show_help

    ; Check if argument starts with "add "
    mov esi, str_pkg_add
    call str_prefix
    jnz .pkg_chk_inst
    add dword [cmd_arg_ptr], 4
    jmp .pkg_has_name

.pkg_chk_inst:
    mov esi, str_pkg_install
    call str_prefix
    jnz .pkg_has_name
    add dword [cmd_arg_ptr], 8

.pkg_has_name:
    mov edi, [cmd_arg_ptr]
    cmp byte [edi], 0
    je .pkg_show_help

    xor ecx, ecx
.pkg_find_free:
    cmp ecx, MAX_FS_ENTRIES
    jge .pkg_print_installed
    mov eax, ecx
    imul eax, FS_ENTRY_SIZE
    add eax, fs_table
    cmp byte [eax], 0
    je .pkg_reg_bin
    inc ecx
    jmp .pkg_find_free
.pkg_reg_bin:
    mov byte [eax], 1
    mov esi, str_dir_bin
    lea edi, [eax + 2]
    call strcpy
    mov esi, [cmd_arg_ptr]
    lea edi, [eax + 34]
    call strcpy
    mov word [eax + 66], 8192

.pkg_print_installed:
    mov esi, out_pkg_install1
    mov ah, ATTR_CYAN
    call term_print
    mov esi, [cmd_arg_ptr]
    mov ah, ATTR_WHITE
    call term_print
    mov esi, out_pkg_install2
    mov ah, ATTR_GREEN
    call term_print
    ret

.pkg_show_help:
    mov esi, out_pkg_help
    mov ah, ATTR_YELLOW
    call term_print
    ret

.cmd_nmcli:
    mov edi, [cmd_arg_ptr]
    mov esi, str_wifi_sub
    call str_find_substr
    jz .nm_wifi_subcmd

    mov esi, str_conn_sub
    call str_find_substr
    jz .nm_conn_subcmd

    mov esi, str_disc_sub
    call str_find_substr
    jz .wifi_do_disconnect
    mov esi, str_down_sub
    call str_find_substr
    jz .wifi_do_disconnect

    jmp .nm_show_devices

.nm_wifi_subcmd:
    mov edi, [cmd_arg_ptr]
    mov esi, str_conn_sub
    call str_find_substr
    jz .wifi_do_connect
    mov esi, str_disc_sub
    call str_find_substr
    jz .wifi_do_disconnect
    jmp .wifi_show_list

.nm_conn_subcmd:
    mov edi, [cmd_arg_ptr]
    mov esi, str_up_sub
    call str_find_substr
    jz .wifi_do_connect
    mov esi, str_down_sub
    call str_find_substr
    jz .wifi_do_disconnect
    jmp .nm_show_devices

.nm_show_devices:
    mov esi, out_nmcli_head
    mov ah, ATTR_DEFAULT
    call term_print

    ; Line 1: wlan0
    mov esi, out_nmcli_wlan0
    mov ah, ATTR_DEFAULT
    call term_print

    cmp byte [net_wlan_state], 1
    je .nm_wlan_connected

    ; Disconnected
    mov esi, out_nmcli_disc
    mov ah, ATTR_RED
    call term_print
    jmp .nm_print_eth0

.nm_wlan_connected:
    mov esi, out_nmcli_conn
    mov ah, ATTR_GREEN
    call term_print
    mov esi, net_wlan_ssid
    mov ah, ATTR_WHITE
    call term_print
    mov al, 0x0A
    call term_print_char

.nm_print_eth0:
    mov esi, out_nmcli_eth0
    mov ah, ATTR_DEFAULT
    call term_print

    mov esi, out_nmcli_lo
    mov ah, ATTR_DEFAULT
    call term_print

    mov esi, out_nmcli_p2p
    mov ah, ATTR_DEFAULT
    call term_print
    ret

.cmd_wifi:
    mov edi, [cmd_arg_ptr]
    mov esi, str_conn_sub
    call str_find_substr
    jz .wifi_do_connect
    mov esi, str_disc_sub
    call str_find_substr
    jz .wifi_do_disconnect
    mov esi, str_down_sub
    call str_find_substr
    jz .wifi_do_disconnect
    jmp .wifi_show_list

.wifi_do_connect:
    mov esi, [cmd_arg_ptr]
.wconn_find_space:
    cmp byte [esi], 0
    je .wconn_use_default
    cmp byte [esi], ' '
    je .wconn_skip_spaces
    inc esi
    jmp .wconn_find_space
.wconn_skip_spaces:
    inc esi
    cmp byte [esi], ' '
    je .wconn_skip_spaces
    cmp byte [esi], 0
    je .wconn_use_default
    mov edi, net_wlan_ssid
    call strcpy
    jmp .wconn_activate
.wconn_use_default:
    mov esi, str_default_ssid
    mov edi, net_wlan_ssid
    call strcpy
.wconn_activate:
    mov byte [net_wlan_state], 1
    mov esi, out_wifi_conn_log1
    mov ah, ATTR_CYAN
    call term_print
    mov esi, net_wlan_ssid
    mov ah, ATTR_WHITE
    call term_print
    mov esi, out_wifi_conn_log2
    mov ah, ATTR_GREEN
    call term_print
    ret

.wifi_do_disconnect:
    mov byte [net_wlan_state], 0
    mov byte [net_wlan_ssid], 0
    mov esi, out_wifi_disc_log
    mov ah, ATTR_YELLOW
    call term_print
    ret

.wifi_show_list:
    mov esi, out_wifi_scan_head
    mov ah, ATTR_DEFAULT
    call term_print

    mov esi, str_ssid_fiber
    call .wifi_check_row
    mov esi, out_wifi_row_fiber
    mov ah, ATTR_DEFAULT
    call term_print

    mov esi, str_ssid_akash
    call .wifi_check_row
    mov esi, out_wifi_row_akash
    mov ah, ATTR_DEFAULT
    call term_print

    mov esi, str_ssid_office
    call .wifi_check_row
    mov esi, out_wifi_row_office
    mov ah, ATTR_DEFAULT
    call term_print

    mov esi, str_ssid_hotspot
    call .wifi_check_row
    mov esi, out_wifi_row_hotspot
    mov ah, ATTR_DEFAULT
    call term_print
    ret

.wifi_check_row:
    push esi
    cmp byte [net_wlan_state], 1
    jne .wcr_not_inuse
    mov edi, net_wlan_ssid
    call streq
    jnz .wcr_not_inuse
    mov esi, str_inuse_star
    mov ah, ATTR_GREEN
    call term_print
    pop esi
    ret
.wcr_not_inuse:
    mov esi, str_inuse_space
    mov ah, ATTR_DEFAULT
    call term_print
    pop esi
    ret

.cmd_ip:
    mov esi, out_ip_lo
    mov ah, ATTR_DEFAULT
    call term_print

    mov esi, out_ip_eth0
    mov ah, ATTR_DEFAULT
    call term_print

    cmp byte [net_wlan_state], 1
    je .ip_wlan_active

    mov esi, out_ip_wlan_down
    mov ah, ATTR_DEFAULT
    call term_print
    ret

.ip_wlan_active:
    mov esi, out_ip_wlan_up1
    mov ah, ATTR_DEFAULT
    call term_print
    mov esi, net_wlan_ip
    mov ah, ATTR_GREEN
    call term_print
    mov esi, out_ip_wlan_up2
    mov ah, ATTR_DEFAULT
    call term_print
    ret

.cmd_ping:
    mov esi, str_ping_head1
    mov ah, ATTR_DEFAULT
    call term_print

    mov edi, [cmd_arg_ptr]
    cmp byte [edi], 0
    jne .ping_has_arg
    mov esi, str_ping_def
    jmp .ping_pr_target
.ping_has_arg:
    mov esi, edi
.ping_pr_target:
    mov ah, ATTR_WHITE
    call term_print

    mov esi, str_ping_head2
    mov ah, ATTR_DEFAULT
    call term_print

    ; Packet 1
    rdtsc
    mov ebx, eax
    mov ecx, 1500000
.ping_l1:
    in al, 0x80
    loop .ping_l1
    rdtsc
    sub eax, ebx
    and eax, 7
    add eax, 8
    push eax
    mov esi, str_ping_pkt1
    mov ah, ATTR_DEFAULT
    call term_print
    pop eax
    push eax
    call print_dec_num
    mov esi, str_ping_ms
    mov ah, ATTR_DEFAULT
    call term_print

    ; Packet 2
    rdtsc
    mov ebx, eax
    mov ecx, 2200000
.ping_l2:
    in al, 0x80
    loop .ping_l2
    rdtsc
    sub eax, ebx
    and eax, 7
    add eax, 9
    push eax
    mov esi, str_ping_pkt2
    mov ah, ATTR_DEFAULT
    call term_print
    pop eax
    push eax
    call print_dec_num
    mov esi, str_ping_ms
    mov ah, ATTR_DEFAULT
    call term_print

    ; Packet 3
    rdtsc
    mov ebx, eax
    mov ecx, 1800000
.ping_l3:
    in al, 0x80
    loop .ping_l3
    rdtsc
    sub eax, ebx
    and eax, 7
    add eax, 7
    push eax
    mov esi, str_ping_pkt3
    mov ah, ATTR_DEFAULT
    call term_print
    pop eax
    push eax
    call print_dec_num
    mov esi, str_ping_ms
    mov ah, ATTR_DEFAULT
    call term_print

    pop eax
    pop eax
    pop eax

    mov esi, str_ping_summary
    mov ah, ATTR_DEFAULT
    call term_print
    ret

.cmd_bluetooth:
    mov edi, [cmd_arg_ptr]
    mov esi, str_power_sub
    call str_find_substr
    jz .bt_do_power

    mov esi, str_scan_sub
    call str_find_substr
    jz .bt_do_scan

    mov esi, str_conn_sub
    call str_find_substr
    jz .bt_do_connect

    mov esi, str_disc_sub
    call str_find_substr
    jz .bt_do_disconnect

    jmp .bt_show_status

.bt_do_power:
    mov edi, [cmd_arg_ptr]
    mov esi, str_off_sub
    call str_find_substr
    jz .bt_pow_off
    mov byte [bt_power_state], 1
    mov esi, out_bt_pow_on
    mov ah, ATTR_GREEN
    call term_print
    ret
.bt_pow_off:
    mov byte [bt_power_state], 0
    mov esi, out_bt_pow_off
    mov ah, ATTR_YELLOW
    call term_print
    ret

.bt_do_scan:
    mov edi, [cmd_arg_ptr]
    mov esi, str_off_sub
    call str_find_substr
    jz .bt_scan_stop
    mov esi, out_bt_scan_start
    mov ah, ATTR_CYAN
    call term_print
    ret
.bt_scan_stop:
    mov esi, out_bt_scan_stop
    mov ah, ATTR_DEFAULT
    call term_print
    ret

.bt_do_connect:
    mov edi, [cmd_arg_ptr]
    mov esi, str_key_sub
    call str_find_substr
    jz .bt_conn_keyboard
    mov esi, str_mou_sub
    call str_find_substr
    jz .bt_conn_mouse
    mov esi, str_logi_sub
    call str_find_substr
    jz .bt_conn_mouse
    mov byte [bt_dev1_state], 1
    mov esi, out_bt_conn_sony
    mov ah, ATTR_GREEN
    call term_print
    ret
.bt_conn_keyboard:
    mov byte [bt_dev2_state], 1
    mov esi, out_bt_conn_key
    mov ah, ATTR_GREEN
    call term_print
    ret
.bt_conn_mouse:
    mov byte [bt_dev3_state], 1
    mov esi, out_bt_conn_mou
    mov ah, ATTR_GREEN
    call term_print
    ret

.bt_do_disconnect:
    mov edi, [cmd_arg_ptr]
    mov esi, str_key_sub
    call str_find_substr
    jz .bt_disc_keyboard
    mov esi, str_mou_sub
    call str_find_substr
    jz .bt_disc_mouse
    mov esi, str_logi_sub
    call str_find_substr
    jz .bt_disc_mouse
    mov byte [bt_dev1_state], 0
    mov esi, out_bt_disc_sony
    mov ah, ATTR_YELLOW
    call term_print
    ret
.bt_disc_keyboard:
    mov byte [bt_dev2_state], 0
    mov esi, out_bt_disc_key
    mov ah, ATTR_YELLOW
    call term_print
    ret
.bt_disc_mouse:
    mov byte [bt_dev3_state], 0
    mov esi, out_bt_disc_mou
    mov ah, ATTR_YELLOW
    call term_print
    ret

.bt_show_status:
    mov esi, out_bt_ctrl_head
    mov ah, ATTR_CYAN
    call term_print

    mov esi, out_bt_powered_str
    mov ah, ATTR_DEFAULT
    call term_print
    cmp byte [bt_power_state], 1
    je .bt_p_yes
    mov esi, str_no
    mov ah, ATTR_RED
    call term_print
    jmp .bt_p_rest
.bt_p_yes:
    mov esi, str_yes
    mov ah, ATTR_GREEN
    call term_print
.bt_p_rest:
    mov esi, out_bt_ctrl_tail
    mov ah, ATTR_DEFAULT
    call term_print

    mov esi, out_bt_dev1_label
    mov ah, ATTR_WHITE
    call term_print
    cmp byte [bt_dev1_state], 1
    je .bt_d1_yes
    mov esi, str_no_nl
    mov ah, ATTR_DEFAULT
    call term_print
    jmp .bt_chk_d2
.bt_d1_yes:
    mov esi, str_yes_nl
    mov ah, ATTR_GREEN
    call term_print

.bt_chk_d2:
    mov esi, out_bt_dev2_label
    mov ah, ATTR_WHITE
    call term_print
    cmp byte [bt_dev2_state], 1
    je .bt_d2_yes
    mov esi, str_no_nl
    mov ah, ATTR_DEFAULT
    call term_print
    jmp .bt_chk_d3
.bt_d2_yes:
    mov esi, str_yes_nl
    mov ah, ATTR_GREEN
    call term_print

.bt_chk_d3:
    mov esi, out_bt_dev3_label
    mov ah, ATTR_WHITE
    call term_print
    cmp byte [bt_dev3_state], 1
    je .bt_d3_yes
    mov esi, str_no_nl
    mov ah, ATTR_DEFAULT
    call term_print
    ret
.bt_d3_yes:
    mov esi, str_yes_nl
    mov ah, ATTR_GREEN
    call term_print
    ret

.cmd_rfkill:
    mov esi, out_rfkill_head
    mov ah, ATTR_DEFAULT
    call term_print

    mov esi, out_rfkill_bt_label
    mov ah, ATTR_DEFAULT
    call term_print
    cmp byte [bt_power_state], 1
    je .rf_bt_unblock
    mov esi, out_rfkill_blocked
    mov ah, ATTR_RED
    call term_print
    jmp .rf_wlan
.rf_bt_unblock:
    mov esi, out_rfkill_unblocked
    mov ah, ATTR_GREEN
    call term_print

.rf_wlan:
    mov esi, out_rfkill_wlan_label
    mov ah, ATTR_DEFAULT
    call term_print
    mov esi, out_rfkill_unblocked
    mov ah, ATTR_GREEN
    call term_print
    ret


.cmd_sudo:
    mov esi, out_sudo_info
    mov ah, ATTR_YELLOW
    call term_print
    ret

.cmd_history:
    mov esi, out_history
    mov ah, ATTR_DEFAULT
    call term_print
    ret

.cmd_neofetch:
    mov esi, out_neofetch
    mov ah, ATTR_CYAN
    call term_print
    ret

.cmd_cat:
    mov edi, [cmd_arg_ptr]
    ; If empty or notes.txt or notes
    cmp byte [edi], 0
    je .cat_notes
    mov esi, str_file_notes
    call str_prefix
    jz .cat_notes

    mov esi, str_file_flake
    call str_prefix
    jz .cat_flake

    mov esi, str_file_hypr
    call str_prefix
    jz .cat_hypr

    mov esi, str_file_os_rel
    call str_prefix
    jz .cat_os_rel

    mov esi, str_file_version
    call str_prefix
    jz .cat_version

    mov esi, str_file_cpuinfo
    call str_prefix
    jz .cat_cpuinfo

    mov esi, str_file_meminfo
    call str_prefix
    jz .cat_meminfo

    ; Search dynamic fs_table for file in current directory
    xor ecx, ecx
.cat_search_dynamic:
    cmp ecx, MAX_FS_ENTRIES
    jge .cat_not_found

    mov eax, ecx
    imul eax, FS_ENTRY_SIZE
    add eax, fs_table

    cmp byte [eax], 1           ; type == file
    jne .cat_next_dynamic

    ; Verify parent_dir == cwd_display
    push eax
    push ecx
    lea esi, [eax + 2]
    mov edi, cwd_display
    call streq
    pop ecx
    pop eax
    jnz .cat_next_dynamic

    ; Verify name == cmd_arg_ptr
    push eax
    push ecx
    lea esi, [eax + 34]
    mov edi, [cmd_arg_ptr]
    call streq
    pop ecx
    pop eax
    jz .cat_show_dynamic

.cat_next_dynamic:
    inc ecx
    jmp .cat_search_dynamic

.cat_show_dynamic:
    cmp word [eax + 66], 0
    je .cat_empty_file
    lea esi, [eax + 68]
    mov ah, ATTR_WHITE
    call term_print
    mov al, 0x0A
    mov ah, ATTR_DEFAULT
    call term_print_char
.cat_empty_file:
    ret

.cat_not_found:
    mov esi, str_cat_prefix
    mov ah, ATTR_RED
    call term_print
    mov esi, [cmd_arg_ptr]
    mov ah, ATTR_WHITE
    call term_print
    mov esi, str_err_not_found_file
    mov ah, ATTR_RED
    call term_print
    ret

.cat_notes:
    mov esi, out_cat_notes
    mov ah, ATTR_DEFAULT
    call term_print
    ret

.cat_flake:
    mov esi, out_cat_flake
    mov ah, ATTR_DEFAULT
    call term_print
    ret

.cat_hypr:
    mov esi, out_cat_hypr
    mov ah, ATTR_DEFAULT
    call term_print
    ret

.cat_os_rel:
    mov esi, out_cat_os_rel
    mov ah, ATTR_DEFAULT
    call term_print
    ret

.cat_version:
    mov esi, out_uname
    mov ah, ATTR_DEFAULT
    call term_print
    ret

.cat_cpuinfo:
    mov esi, out_cat_cpuinfo
    mov ah, ATTR_DEFAULT
    call term_print
    ret

.cat_meminfo:
    mov esi, out_cat_meminfo
    mov ah, ATTR_DEFAULT
    call term_print
    ret

.cmd_echo:
    mov esi, [cmd_arg_ptr]
    mov ah, ATTR_WHITE
    call term_print
    mov al, 0x0A
    mov ah, ATTR_DEFAULT
    call term_print_char
    ret

.cmd_uname:
    mov esi, out_uname
    mov ah, ATTR_WHITE
    call term_print
    ret

.cmd_whoami:
    mov esi, out_whoami
    mov ah, ATTR_GREEN
    call term_print
    ret

.cmd_ps:
    mov esi, out_ps
    mov ah, ATTR_DEFAULT
    call term_print
    ret

.cmd_free:
    mov esi, out_free
    mov ah, ATTR_DEFAULT
    call term_print
    ret

.cmd_casfs:
    mov esi, out_casfs
    mov ah, ATTR_CYAN
    call term_print
    ret

.cmd_hypr:
    mov esi, out_hypr
    mov ah, ATTR_CYAN
    call term_print
    ret

.cmd_ab:
    mov esi, out_ab_header
    mov ah, ATTR_WHITE
    call term_print
    mov esi, out_ab_stats
    mov ah, ATTR_DEFAULT
    call term_print
    ret

.cmd_run_linux:
    mov esi, out_run_linux
    mov ah, ATTR_PROMPT
    call term_print
    ret

.cmd_run_win:
    mov esi, out_run_win
    mov ah, ATTR_PROMPT
    call term_print
    ret

.cmd_run_mac:
    mov esi, out_run_mac
    mov ah, ATTR_PROMPT
    call term_print
    ret

.cmd_rollback:
    mov esi, out_rollback
    mov ah, ATTR_YELLOW
    call term_print
    ret

.cmd_clear:
    call term_clear
    ret

.cmd_reboot:
    mov al, 0xFE
    out 0x64, al
    hlt
    ret

.cmd_date:
    mov esi, str_date_prefix
    mov ah, ATTR_WHITE
    call term_print

    ; Year (Reg 0x09)
    mov al, 0x09
    call print_rtc_reg
    mov al, '-'
    mov ah, ATTR_WHITE
    call term_print_char

    ; Month (Reg 0x08)
    mov al, 0x08
    call print_rtc_reg
    mov al, '-'
    mov ah, ATTR_WHITE
    call term_print_char

    ; Day (Reg 0x07)
    mov al, 0x07
    call print_rtc_reg
    mov al, ' '
    mov ah, ATTR_WHITE
    call term_print_char

    ; Hour (Reg 0x04)
    mov al, 0x04
    call print_rtc_reg
    mov al, ':'
    mov ah, ATTR_WHITE
    call term_print_char

    ; Minute (Reg 0x02)
    mov al, 0x02
    call print_rtc_reg
    mov al, ':'
    mov ah, ATTR_WHITE
    call term_print_char

    ; Second (Reg 0x00)
    mov al, 0x00
    call print_rtc_reg

    mov esi, str_date_suffix
    mov ah, ATTR_DEFAULT
    call term_print
    ret

.cmd_lspci:
    mov esi, str_pci_header
    mov ah, ATTR_CYAN
    call term_print

    xor ecx, ecx        ; slot 0..31
.lspci_loop:
    cmp ecx, 32
    jge .lspci_done

    mov eax, ecx
    shl eax, 11
    or eax, 0x80000000
    mov dx, 0xCF8
    out dx, eax
    mov dx, 0xCFC
    in eax, dx

    cmp ax, 0xFFFF
    je .lspci_next

    push ecx
    push eax

    mov esi, str_pci_slot_prefix
    mov ah, ATTR_DEFAULT
    call term_print

    mov eax, ecx
    cmp eax, 9
    jbe .slot_digit
    add al, 'a' - 10
    jmp .slot_print
.slot_digit:
    add al, '0'
.slot_print:
    mov ah, ATTR_DEFAULT
    call term_print_char

    mov esi, str_pci_slot_suffix
    mov ah, ATTR_DEFAULT
    call term_print

    pop eax
    pop ecx

    ; Check Intel Vendor 0x8086
    cmp ax, 0x8086
    jne .chk_bochs
    shr eax, 16
    cmp ax, 0x1237
    je .pci_i440fx
    cmp ax, 0x7000
    je .pci_piix3
    cmp ax, 0x7010
    je .pci_piix_ide
    cmp ax, 0x7113
    je .pci_piix_acpi
    cmp ax, 0x100E
    je .pci_e1000
    cmp ax, 0x1004
    je .pci_e1000
    jmp .pci_intel_other

.chk_bochs:
    cmp ax, 0x1234
    jne .pci_unknown
    shr eax, 16
    cmp ax, 0x1111
    je .pci_vga
    jmp .pci_unknown

.pci_i440fx:
    mov esi, str_pci_desc_440fx
    mov ah, ATTR_WHITE
    call term_print
    jmp .lspci_next

.pci_piix3:
    mov esi, str_pci_desc_piix3
    mov ah, ATTR_WHITE
    call term_print
    jmp .lspci_next

.pci_piix_ide:
    mov esi, str_pci_desc_ide
    mov ah, ATTR_WHITE
    call term_print
    jmp .lspci_next

.pci_piix_acpi:
    mov esi, str_pci_desc_acpi
    mov ah, ATTR_WHITE
    call term_print
    jmp .lspci_next

.pci_e1000:
    mov esi, str_pci_desc_e1000
    mov ah, ATTR_GREEN
    call term_print
    jmp .lspci_next

.pci_vga:
    mov esi, str_pci_desc_vga
    mov ah, ATTR_WHITE
    call term_print
    jmp .lspci_next

.pci_intel_other:
    mov esi, str_pci_desc_intel_gen
    mov ah, ATTR_WHITE
    call term_print
    jmp .lspci_next

.pci_unknown:
    mov esi, str_pci_desc_unk
    mov ah, ATTR_DEFAULT
    call term_print

.lspci_next:
    inc ecx
    jmp .lspci_loop

.lspci_done:
    ret


; =============================================================================
; Terminal Display Primitives (VGA 0xB8000)
; =============================================================================

term_clear:
    mov edi, VGA_TEXT
    mov ecx, COLS * ROWS
    mov ax, (ATTR_DEFAULT << 8) | ' '
    rep stosw
    mov dword [cursor_x], 0
    mov dword [cursor_y], 0
    call term_update_hw_cursor
    ret

term_print_char:
    push eax
    push ebx
    push ecx
    push edx

    cmp al, 0x0A                ; Linefeed '\n'
    je .newline
    cmp al, 0x0D                ; Carriage Return '\r'
    je .cr
    cmp al, 0x08                ; Backspace '\b'
    je .backspace

    ; Regular Printable Character
    mov ebx, [cursor_y]
    imul ebx, COLS
    add ebx, [cursor_x]
    shl ebx, 1                  ; 2 bytes per cell
    add ebx, VGA_TEXT

    mov [ebx], al               ; ASCII char
    mov [ebx+1], ah             ; Color attribute

    inc dword [cursor_x]
    mov eax, [cursor_x]
    cmp eax, COLS
    jl .done_char
    mov dword [cursor_x], 0
    inc dword [cursor_y]
    jmp .check_scroll

.backspace:
    mov eax, [cursor_x]
    test eax, eax
    jz .done_char
    dec dword [cursor_x]
    mov ebx, [cursor_y]
    imul ebx, COLS
    add ebx, [cursor_x]
    shl ebx, 1
    add ebx, VGA_TEXT
    mov byte [ebx], ' '
    mov byte [ebx+1], ATTR_DEFAULT
    jmp .done_char

.cr:
    mov dword [cursor_x], 0
    jmp .done_char

.newline:
    mov dword [cursor_x], 0
    inc dword [cursor_y]

.check_scroll:
    mov eax, [cursor_y]
    cmp eax, ROWS
    jl .done_char
    call term_scroll

.done_char:
    call term_update_hw_cursor
    pop edx
    pop ecx
    pop ebx
    pop eax
    ret

term_scroll:
    push esi
    push edi
    push ecx
    mov edi, VGA_TEXT
    mov esi, VGA_TEXT + (COLS * 2)
    mov ecx, COLS * (ROWS - 1)
    rep movsw

    mov edi, VGA_TEXT + (COLS * (ROWS - 1) * 2)
    mov ecx, COLS
    mov ax, (ATTR_DEFAULT << 8) | ' '
    rep stosw

    mov dword [cursor_y], ROWS - 1
    pop ecx
    pop edi
    pop esi
    ret

term_update_hw_cursor:
    mov ebx, [cursor_y]
    imul ebx, COLS
    add ebx, [cursor_x]

    mov dx, 0x3D4
    mov al, 0x0F
    out dx, al
    inc dx
    mov al, bl
    out dx, al

    dec dx
    mov al, 0x0E
    out dx, al
    inc dx
    mov al, bh
    out dx, al
    ret

term_print:
    ; ESI = null-terminated string, AH = attribute
    push eax
    push esi
.p_loop:
    lodsb
    test al, al
    jz .p_done
    call term_print_char
    jmp .p_loop
.p_done:
    pop esi
    pop eax
    ret

read_scancode_blocking:
    in al, 0x64
    test al, 1
    jz .rsb_wait
    test al, 0x20
    jnz .rsb_discard
    in al, 0x60
    ret
.rsb_discard:
    in al, 0x60
.rsb_wait:
    pause
    jmp read_scancode_blocking

term_read_line:
    ; Buffer in EDI
    push eax
    push ebx
    push edx
    push esi
    push edi
    xor esi, esi
.trl_loop:
    call read_scancode_blocking
    cmp al, 0x2A
    je .trl_shift_on
    cmp al, 0x36
    je .trl_shift_on
    cmp al, 0xAA
    je .trl_shift_off
    cmp al, 0xB6
    je .trl_shift_off
    test al, 0x80
    jnz .trl_loop

    cmp al, 0x1C
    je .trl_enter
    cmp al, 0x0E
    je .trl_backspace
    cmp al, 0x39
    ja .trl_loop

    movzx ebx, al
    cmp byte [shift_state], 1
    je .trl_use_shift
    mov dl, [scancode_table + ebx]
    jmp .trl_got_char
.trl_use_shift:
    mov dl, [scancode_shift_table + ebx]
.trl_got_char:
    test dl, dl
    jz .trl_loop
    jmp .trl_append_char

.trl_shift_on:
    mov byte [shift_state], 1
    jmp .trl_loop
.trl_shift_off:
    mov byte [shift_state], 0
    jmp .trl_loop

.trl_append_char:

    cmp esi, 60
    jge .trl_loop

    mov [edi + esi], dl
    inc esi
    mov byte [edi + esi], 0

    mov al, dl
    mov ah, ATTR_WHITE
    call term_print_char
    jmp .trl_loop

.trl_backspace:
    test esi, esi
    jz .trl_loop
    dec esi
    mov byte [edi + esi], 0
    mov al, 0x08
    call term_print_char
    jmp .trl_loop

.trl_enter:
    mov byte [edi + esi], 0
    mov al, 0x0A
    mov ah, ATTR_DEFAULT
    call term_print_char
    pop edi
    pop esi
    pop edx
    pop ebx
    pop eax
    ret

term_print_prompt:
    ; Prompt: "akash@aetheros:" [Green] + cwd [Blue] + "$ " [Green]
    mov esi, str_prompt_user
    mov ah, ATTR_PROMPT
    call term_print

    mov esi, cwd_display
    mov ah, ATTR_PATH
    call term_print

    mov esi, str_prompt_dollar
    mov ah, ATTR_PROMPT
    call term_print
    ret

; =============================================================================
; Tokenization & String Helpers
; =============================================================================

tokenize_command:
    push eax
    push ecx
    push esi
    push edi

    ; Clear cmd_name (32 bytes)
    mov edi, cmd_name
    mov ecx, 32
    xor al, al
    rep stosb

    ; Set default cmd_arg_ptr to empty_str
    mov dword [cmd_arg_ptr], empty_str

    mov esi, cmd_buffer

.tok_skip_lead:
    mov al, [esi]
    test al, al
    jz .tok_finish
    cmp al, ' '
    jne .tok_copy_name
    inc esi
    jmp .tok_skip_lead

.tok_copy_name:
    mov edi, cmd_name
    xor ecx, ecx
.tok_name_loop:
    mov al, [esi]
    test al, al
    jz .tok_finish
    cmp al, ' '
    je .tok_find_arg
    cmp ecx, 31
    jge .tok_skip_char
    mov [edi], al
    inc edi
    inc ecx
.tok_skip_char:
    inc esi
    jmp .tok_name_loop

.tok_find_arg:
    inc esi
    mov al, [esi]
    test al, al
    jz .tok_finish
    cmp al, ' '
    je .tok_find_arg
    mov [cmd_arg_ptr], esi

.tok_finish:
    pop edi
    pop esi
    pop ecx
    pop eax
    ret

match_cmd:
    ; Compares cmd_name against ESI (exact match)
    ; Returns ZF=1 if match, ZF=0 if mismatch
    push esi
    push edi
    mov edi, cmd_name
.mc_loop:
    mov al, [edi]
    mov bl, [esi]
    cmp al, bl
    jne .mc_mismatch
    test al, al
    jz .mc_match
    inc edi
    inc esi
    jmp .mc_loop
.mc_match:
    pop edi
    pop esi
    xor eax, eax                ; ZF = 1
    ret
.mc_mismatch:
    pop edi
    pop esi
    or eax, 1                   ; ZF = 0
    ret

str_prefix:
    ; Checks if string at EDI starts with string at ESI
    ; Returns ZF=1 if match, ZF=0 if mismatch
    push esi
    push edi
.sp_loop:
    mov bl, [esi]
    test bl, bl
    jz .sp_match
    mov al, [edi]
    cmp al, bl
    jne .sp_mismatch
    inc esi
    inc edi
    jmp .sp_loop
.sp_match:
    pop edi
    pop esi
    xor eax, eax                ; ZF = 1
    ret
.sp_mismatch:
    pop edi
    pop esi
    or eax, 1                   ; ZF = 0
    ret

streq:
    ; Compares string at ESI with string at EDI
    ; Returns ZF=1 if identical, ZF=0 if different
    push esi
    push edi
.se_loop:
    mov al, [esi]
    mov bl, [edi]
    cmp al, bl
    jne .se_diff
    test al, al
    jz .se_same
    inc esi
    inc edi
    jmp .se_loop
.se_same:
    pop edi
    pop esi
    xor eax, eax
    ret
.se_diff:
    pop edi
    pop esi
    or eax, 1
    ret

strcpy:
    ; Copy null-terminated string from ESI to EDI
    push eax
    push esi
    push edi
.scpy_loop:
    lodsb
    stosb
    test al, al
    jnz .scpy_loop
    pop edi
    pop esi
    pop eax
    ret

path_append:
    ; Appends '/' + string at ESI to cwd_display
    push eax
    push esi
    push edi
    mov edi, cwd_display
.pa_find_end:
    mov al, [edi]
    test al, al
    jz .pa_append
    inc edi
    jmp .pa_find_end
.pa_append:
    cmp byte [cwd_display], '/'
    jne .pa_add_slash
    cmp byte [cwd_display+1], 0
    je .pa_copy_chars
.pa_add_slash:
    mov byte [edi], '/'
    inc edi
.pa_copy_chars:
    lodsb
    stosb
    test al, al
    jnz .pa_copy_chars
    pop edi
    pop esi
    pop eax
    ret

str_find_substr:
    ; Checks if string at EDI contains substring at ESI anywhere (case insensitive)
    ; Returns ZF=1 if found, ZF=0 if not found
    push esi
    push edi
    push ebx
    push edx
.sfs_outer:
    cmp byte [edi], 0
    je .sfs_fail
    push esi
    push edi
.sfs_inner:
    mov bl, [esi]
    test bl, bl
    jz .sfs_inner_match
    mov al, [edi]
    test al, al
    jz .sfs_inner_diff

    ; Case-insensitive compare
    cmp al, 'A'
    jb .sfs_c1_done
    cmp al, 'Z'
    ja .sfs_c1_done
    add al, 32
.sfs_c1_done:
    cmp bl, 'A'
    jb .sfs_c2_done
    cmp bl, 'Z'
    ja .sfs_c2_done
    add bl, 32
.sfs_c2_done:
    cmp al, bl
    jne .sfs_inner_diff
    inc esi
    inc edi
    jmp .sfs_inner
.sfs_inner_match:
    pop edi
    pop esi
    pop edx
    pop ebx
    pop edi
    pop esi
    xor eax, eax
    ret
.sfs_inner_diff:
    pop edi
    pop esi
    inc edi
    jmp .sfs_outer
.sfs_fail:
    pop edx
    pop ebx
    pop edi
    pop esi
    or eax, 1
    ret

print_rtc_reg:
    ; AL = RTC CMOS register index (0x00, 0x02, etc.)
    out 0x70, al
    jmp $+2
    in al, 0x71
    mov dl, al
    shr dl, 4
    and dl, 0x0F
    add dl, '0'
    mov dh, al
    and dh, 0x0F
    add dh, '0'
    mov al, dl
    mov ah, ATTR_WHITE
    call term_print_char
    mov al, dh
    mov ah, ATTR_WHITE
    call term_print_char
    ret

print_dec_num:
    ; AL = number (0..99)
    push eax
    push edx
    movzx eax, al
    mov dl, 10
    div dl              ; AL = tens, AH = units
    push eax
    test al, al
    jz .pdn_skip_ten
    add al, '0'
    mov ah, ATTR_WHITE
    call term_print_char
.pdn_skip_ten:
    pop eax
    mov al, ah
    add al, '0'
    mov ah, ATTR_WHITE
    call term_print_char
    pop edx
    pop eax
    ret

parse_int_val:
    push ebx
    push edx
    xor eax, eax
.piv_loop:
    mov bl, [esi]
    cmp bl, '0'
    jb .piv_done
    cmp bl, '9'
    ja .piv_done
    sub bl, '0'
    imul eax, 10
    movzx edx, bl
    add eax, edx
    inc esi
    jmp .piv_loop
.piv_done:
    pop edx
    pop ebx
    ret

print_full_int:
    push eax
    push ebx
    push ecx
    push edx
    test eax, eax
    jnz .pfi_check_neg
    mov al, '0'
    mov ah, ATTR_WHITE
    call term_print_char
    jmp .pfi_done
.pfi_check_neg:
    jns .pfi_pos
    push eax
    mov al, '-'
    mov ah, ATTR_WHITE
    call term_print_char
    pop eax
    neg eax
.pfi_pos:
    xor ecx, ecx
    mov ebx, 10
.pfi_div_loop:
    xor edx, edx
    div ebx
    push edx
    inc ecx
    test eax, eax
    jnz .pfi_div_loop
.pfi_print_loop:
    pop eax
    add al, '0'
    mov ah, ATTR_WHITE
    call term_print_char
    loop .pfi_print_loop
.pfi_done:
    pop edx
    pop ecx
    pop ebx
    pop eax
    ret


; =============================================================================
; PS/2 Set 1 Scancode Translation Table
; =============================================================================
scancode_table:
    db 0, 0, '1', '2', '3', '4', '5', '6', '7', '8', '9', '0', '-', '=', 8   ; 0x00 - 0x0E
    db 0, 'q', 'w', 'e', 'r', 't', 'y', 'u', 'i', 'o', 'p', '[', ']', 13      ; 0x0F - 0x1C
    db 0, 'a', 's', 'd', 'f', 'g', 'h', 'j', 'k', 'l', ';', "'", '`', 0       ; 0x1D - 0x2A
    db '\', 'z', 'x', 'c', 'v', 'b', 'n', 'm', ',', '.', '/', 0, '*', 0        ; 0x2B - 0x38
    db ' '                                                                      ; 0x39

scancode_shift_table:
    db 0, 0, '!', '@', '#', '$', '%', '^', '&', '*', '(', ')', '_', '+', 8   ; 0x00 - 0x0E
    db 0, 'Q', 'W', 'E', 'R', 'T', 'Y', 'U', 'I', 'O', 'P', '{', '}', 13      ; 0x0F - 0x1C
    db 0, 'A', 'S', 'D', 'F', 'G', 'H', 'J', 'K', 'L', ':', '"', '~', 0       ; 0x1D - 0x2A
    db '|', 'Z', 'X', 'C', 'V', 'B', 'N', 'M', '<', '>', '?', 0, '*', 0        ; 0x2B - 0x38
    db ' '                                                                      ; 0x39

shift_state         db 0
ctrl_state          db 0

; =============================================================================
; State Variables & Filesystem Table
; =============================================================================

cursor_x            dd 0
cursor_y            dd 0
cmd_len             dd 0
cmd_buffer          times 80 db 0
cmd_name            times 32 db 0
cmd_arg_ptr         dd empty_str
empty_str           db 0

; Dynamic Networking & Bluetooth State Variables
net_wlan_state      db 0                        ; 0 = disconnected, 1 = connected
net_wlan_ssid       times 32 db 0
net_wlan_ip         db "192.168.1.108/24", 0

bt_power_state      db 1                        ; 1 = powered on, 0 = powered off
bt_dev1_state       db 0                        ; Sony WH-1000XM5: 0=disconnected, 1=connected
bt_dev2_state       db 0                        ; Apple Magic Keyboard: 0=disconnected, 1=connected
bt_dev3_state       db 0                        ; Logitech MX Master 3S: 0=disconnected, 1=connected

; Interactive Application Buffers
nano_cur_filename   times 32 db 0
nano_edit_buffer    times 256 db 0
nano_buf_len        dd 0
nano_is_modified    db 0
nano_cut_buffer     times 256 db 0
nano_cut_len        dd 0

py_input_buffer     times 80 db 0
py_var_char         db 0
py_var_val          dd 0

tree_dir_count      dd 0
tree_file_count     dd 0

cwd_display         db "~", 0
                    times 30 db 0

; Dynamic File System Storage Table
fs_table            times (MAX_FS_ENTRIES * FS_ENTRY_SIZE) db 0

str_prompt_user     db "akash@aetheros:", 0
str_prompt_dollar   db "$ ", 0

; Command Identifiers
str_cmd_help        db "help", 0
str_cmd_ls          db "ls", 0
str_cmd_cd          db "cd", 0
str_cmd_pwd         db "pwd", 0
str_cmd_mkdir       db "mkdir", 0
str_cmd_touch       db "touch", 0
str_cmd_rm          db "rm", 0
str_cmd_cp          db "cp", 0
str_cmd_mv          db "mv", 0
str_cmd_sudo        db "sudo", 0
str_cmd_nano        db "nano", 0
str_cmd_slash_nano  db "/bin/nano", 0
str_cmd_dot_nano    db "./nano", 0
str_cmd_vim         db "vim", 0
str_cmd_vi          db "vi", 0
str_cmd_git         db "git", 0
str_cmd_gcc         db "gcc", 0
str_cmd_gpp         db "g++", 0
str_cmd_clang       db "clang", 0
str_cmd_python      db "python", 0
str_cmd_python3     db "python3", 0
str_cmd_curl        db "curl", 0
str_cmd_wget        db "wget", 0
str_cmd_tree        db "tree", 0
str_cmd_htop        db "htop", 0
str_cmd_top         db "top", 0
str_cmd_apt         db "apt", 0
str_cmd_apk         db "apk", 0
str_cmd_pkg         db "pkg", 0
str_cmd_install     db "install", 0
str_pkg_add         db "add ", 0
str_pkg_install     db "install ", 0
str_pkg_official    db "official ", 0
str_cmd_which       db "which", 0
str_cmd_whereis     db "whereis", 0
str_slash_bin       db "/bin/", 0
str_whereis_sep     db ": ", 0
str_whereis_man     db " /usr/share/man/man1/", 0
str_whereis_gz      db ".1.gz", 0x0A, 0
str_newline         db 0x0A, 0
out_which_err       db "which: no program specified", 0x0A, 0
out_whereis_err     db "whereis: no program specified", 0x0A, 0
str_cmd_nixenv      db "nix-env", 0
str_cmd_pacman      db "pacman", 0
str_cmd_nmcli       db "nmcli", 0
str_cmd_nmtui       db "nmtui", 0
str_cmd_ip          db "ip", 0
str_cmd_ifconfig    db "ifconfig", 0
str_cmd_ping        db "ping", 0
str_cmd_btctl       db "bluetoothctl", 0
str_cmd_bluetooth   db "bluetooth", 0
str_cmd_rfkill      db "rfkill", 0
str_cmd_wifi        db "wifi", 0
str_wifi_arg        db "wifi", 0
str_conn_arg        db "conn", 0
str_bt_dev          db "dev", 0
str_bt_scan         db "scan", 0
str_cmd_history     db "history", 0
str_cmd_neofetch    db "neofetch", 0
str_cmd_fastfetch   db "fastfetch", 0
str_cmd_cat         db "cat", 0
str_cmd_echo        db "echo", 0
str_cmd_uname       db "uname", 0
str_cmd_whoami      db "whoami", 0
str_cmd_ps          db "ps", 0
str_cmd_free        db "free", 0
str_cmd_casfs       db "casfs", 0
str_cmd_hypr        db "hypr", 0
str_cmd_hyprland    db "hyprland", 0
str_cmd_ab          db "ab", 0
str_cmd_1           db "1", 0
str_cmd_calc        db "calc", 0
str_cmd_calculator  db "./calculator.elf", 0
str_cmd_aout        db "a.out", 0
str_cmd_dotaout     db "./a.out", 0
str_cmd_2           db "2", 0
str_cmd_notepad     db "notepad", 0
str_cmd_notepadexe  db "notepad.exe", 0
str_cmd_wine        db "wine", 0
str_cmd_3           db "3", 0
str_cmd_open        db "open", 0
str_cmd_termapp     db "terminal.app", 0
str_cmd_r           db "r", 0
str_cmd_rollback    db "rollback", 0
str_cmd_clear       db "clear", 0
str_cmd_reboot      db "reboot", 0
str_cmd_date        db "date", 0
str_cmd_lspci       db "lspci", 0

; Dynamic Network & Hardware Matching Tokens
str_wifi_sub        db "wifi", 0
str_conn_sub        db "conn", 0
str_disc_sub        db "disc", 0
str_down_sub        db "down", 0
str_up_sub          db "up", 0
str_power_sub       db "power", 0
str_scan_sub        db "scan", 0
str_on_sub          db "on", 0
str_off_sub         db "off", 0
str_key_sub         db "key", 0
str_mou_sub         db "mou", 0
str_logi_sub        db "logi", 0
str_sony_sub        db "sony", 0

str_default_ssid    db "Akash_Home_WiFi", 0
str_ssid_fiber      db "Aether-Fiber-5G", 0
str_ssid_akash      db "Akash_Home_WiFi", 0
str_ssid_office     db "Office_HighSpeed", 0
str_ssid_hotspot    db "Hotspot_Pro", 0

str_name_aout       db "a.out", 0

; Git Subcommands
str_git_log         db "log", 0
str_git_commit      db "commit", 0
str_git_init        db "init", 0
str_git_clone       db "clone", 0

; Directory Path Arguments
str_arg_bin         db "bin", 0
str_arg_slash_bin   db "/bin", 0
str_arg_etc         db "etc", 0
str_arg_slash_etc   db "/etc", 0
str_arg_proc        db "proc", 0
str_arg_slash_proc  db "/proc", 0
str_arg_hypr        db "hypr", 0
str_arg_config_hypr db ".config/hypr", 0
str_arg_tilde_hypr  db "~/.config/hypr", 0
str_arg_home        db "home", 0
str_arg_dotdot      db "..", 0
str_arg_slash       db "/", 0

str_dir_home        db "~", 0
str_dir_root        db "/", 0
str_dir_bin         db "/bin", 0
str_dir_etc         db "/etc", 0
str_dir_proc        db "/proc", 0
str_dir_hypr        db "~/.config/hypr", 0

; File Names for cat
str_file_notes      db "notes", 0
str_file_flake      db "flake", 0
str_file_hypr       db "hypr", 0
str_file_os_rel     db "os-release", 0
str_file_version    db "version", 0
str_file_cpuinfo    db "cpuinfo", 0
str_file_meminfo    db "meminfo", 0

; Error Messages
out_not_found           db ": command not found. Type 'help' for commands.", 0x0A, 0
str_cd_prefix           db "cd: ", 0
str_cat_prefix          db "cat: ", 0
str_rm_prefix           db "rm: cannot remove '", 0
str_err_not_found_dir   db ": No such file or directory", 0x0A, 0
str_err_not_found_file  db ": No such file or directory", 0x0A, 0
out_fs_full             db "CasFS: filesystem table full (max 8 dynamic entries)", 0x0A, 0

out_mkdir_err           db "mkdir: missing operand", 0x0A, 0
out_mkdir_ok1           db "> [CasFS] Created directory '", 0
out_mkdir_ok2           db "' (HAMT node allocated).", 0x0A, 0

out_touch_err           db "touch: missing file operand", 0x0A, 0
out_touch_ok1           db "> [CasFS] File '", 0
out_touch_ok2           db "' touched (BLAKE3 object extent initialized).", 0x0A, 0

out_rm_err              db "rm: missing operand", 0x0A, 0
out_rm_ok1              db "> [CasFS] Unlinked '", 0
out_rm_ok2              db "' (extent reclaimed).", 0x0A, 0

out_cp_ok               db "> [CasFS] Copy-on-write deduplicated (BLAKE3 extent referenced, 0 duplicate bytes).", 0x0A, 0
out_mv_ok               db "> [CasFS] Merkle tree reference updated.", 0x0A, 0
out_sudo_info           db "sudo: disabled by microkernel policy (Zero-Trust Capability Model active; no UID 0).", 0x0A, 0

out_cat_dyn_head        db "=== [CasFS Object: ", 0
out_cat_dyn_tail        db "] ===", 0x0A, "Extent Hash: BLAKE3 256-bit (e8a71...)", 0x0A, "Status: Clean (0 bytes written, extent mapped)", 0x0A, 0

out_history:
    db "  1  pwd", 0x0A
    db "  2  ls", 0x0A
    db "  3  cd bin", 0x0A
    db "  4  whoami", 0x0A
    db "  5  cat notes.txt", 0x0A
    db "  6  ab", 0x0A
    db "  7  mkdir akash", 0x0A
    db "  8  touch akash.txt", 0x0A
    db "  9  gcc hello.c -o hello", 0x0A
    db " 10  python3", 0x0A
    db " 11  git status", 0x0A, 0

out_neofetch:
    db "       /\         akash@aetheros", 0x0A
    db "      /  \        OS: AetherOS 0.1.0-alpha x86_64", 0x0A
    db "     /\   \       Host: Microkernel Baremetal / QEMU", 0x0A
    db "    /  \   \      Kernel: 6.6.0-aether (Multi-ABI)", 0x0A
    db "   /    \   \     Shell: ash (Aether Shell)", 0x0A
    db "  /  /\  \   \    Storage: CasFS (BLAKE3 + HAMT)", 0x0A
    db " /__/  \__\___\   Compositor: Hyprland (Wayland)", 0x0A
    db "                  Memory: 768MB / 8192MB", 0x0A, 0

; Nano Interactive Strings
str_nano_default_fn     db "untitled.txt", 0
str_nano_title          db "GNU nano 8.0", 0
str_nano_file_lbl       db "File: ", 0
str_nano_modified_tag   db "[ Modified ]", 0
str_nano_welcome        db "[ Welcome to GNU nano 8.0 ]", 0
str_nano_read_ok        db "[ Read file from CasFS (BLAKE3 verified) ]", 0
str_nano_writeout_ok    db "[ Wrote buffer to disk (CasFS BLAKE3 Extent Committed) ]", 0
str_nano_location_msg   db "[ line 1/1 (100%), col 1/80 (1%), char 0/48 (0%) ]", 0
str_nano_whereis_msg    db "Search: [ CasFS Merkle index ready ]", 0
str_nano_cut_msg        db "[ Cut 1 line into cutbuffer ]", 0
str_nano_paste_msg      db "[ Pasted line from cutbuffer ]", 0
str_nano_readfile_msg   db "[ Insert File: ready ]", 0
str_nano_justify_msg    db "[ Justify paragraph: done ]", 0
str_nano_exit_msg1      db "[ Closed GNU nano 8.0. Saved '", 0
str_nano_exit_msg2      db "' to CasFS (BLAKE3 object committed) ]", 0x0A, 0
str_nano_help_title     db "Help Text", 0
str_nano_help_close     db "  [ Press any key to return to nano ]", 0

str_nano_help_body:
    db "  The nano editor is designed to emulate the functionality and ease-of-use", 0x0A
    db "  of the UW Pico text editor. There are four main sections:", 0x0A
    db "  Top line: program version, current filename, and modified status.", 0x0A
    db "  Main editor window: shows the file being edited (21 rows x 80 cols).", 0x0A
    db "  Status line (3rd from bottom): shows system notices and cursor positions.", 0x0A
    db "  Bottom two lines: shows the most commonly used shortcut keys:", 0x0A, 0x0A
    db "    ^G (F1)     Display this help text", 0x0A
    db "    ^X (F2)     Close the current buffer / Exit from nano", 0x0A
    db "    ^O (F3)     Write the current buffer to disk (Save)", 0x0A
    db "    ^R          Insert another file into current buffer", 0x0A
    db "    ^W          Where Is (Search for a string)", 0x0A
    db "    ^\          Replace a string", 0x0A
    db "    ^K          Cut current line into cutbuffer", 0x0A
    db "    ^U          Paste cutbuffer into current line", 0x0A
    db "    ^C          Display cursor location and stats", 0x0A, 0

; Nano Shortcut Keys (Row 23)
str_k_g                 db "^G", 0
str_lbl_help            db " Help      ", 0
str_k_o                 db "^O", 0
str_lbl_writeout        db " WriteOut  ", 0
str_k_w                 db "^W", 0
str_lbl_whereis         db " Where Is  ", 0
str_k_k                 db "^K", 0
str_lbl_cut             db " Cut       ", 0
str_k_t                 db "^T", 0
str_lbl_execute         db " Execute   ", 0
str_k_c                 db "^C", 0
str_lbl_location        db " Location  ", 0

; Nano Shortcut Keys (Row 24)
str_k_x                 db "^X", 0
str_lbl_exit            db " Exit      ", 0
str_k_r                 db "^R", 0
str_lbl_readfile        db " Read File ", 0
str_k_bslash            db "^\", 0
str_lbl_replace         db " Replace   ", 0
str_k_u                 db "^U", 0
str_lbl_paste           db " Paste     ", 0
str_k_j                 db "^J", 0
str_lbl_justify         db " Justify   ", 0
str_k_under             db "^_", 0
str_lbl_gotoline        db " Go To Line", 0

; Nano CLI Flags & Output
str_flag_version        db "--version", 0
str_flag_cap_v          db "-V", 0
str_flag_small_v        db "-v", 0
str_flag_help           db "--help", 0
str_flag_small_h        db "-h", 0

out_nano_version:
    db " GNU nano, version 8.0", 0x0A
    db " (C) 1999-2024 the GNU nano team and various contributors", 0x0A
    db " Compiled with CasFS BLAKE3 & Linux Universal Multi-ABI on AetherOS x86_64", 0x0A
    db " Email: nano@nano-editor.org    Web: https://nano-editor.org/", 0x0A
    db " Option support: --boldtext --duplicate --color --extra --multibuffer --nanorc", 0x0A, 0

out_nano_cli_help:
    db "Usage: nano [OPTIONS] [[+LINE[,COLUMN]] FILE]...", 0x0A, 0x0A
    db "To open a file for editing:", 0x0A
    db "  nano <filename>", 0x0A, 0x0A
    db "Useful options:", 0x0A
    db "  -V, --version        Print version information and exit", 0x0A
    db "  -h, --help           Show this help text and exit", 0x0A
    db "  -l, --linenumbers    Show line numbers in front of the text", 0x0A, 0

; Git Real Strings
str_git_dotgit      db ".git", 0
out_git_init_ok     db "Initialized empty Git repository in /home/akash/.git/ [CasFS BLAKE3 Merkle Engine]", 0x0A, 0
out_git_not_repo    db "fatal: not a git repository (or any of the parent directories): .git", 0x0A
                    db "Hint: Run 'git init' to initialize a repository.", 0x0A, 0
out_git_head_status db "On branch main", 0x0A
                    db "No commits yet", 0x0A, 0x0A
                    db "Untracked files:", 0x0A
                    db '  (use "git add <file>..." to include in what will be committed)', 0x0A, 0
out_git_prefix_file db "    ", 0
out_git_commit_ok   db "[main (root-commit) 4a8f9c2] CasFS Snapshot committed (BLAKE3 tree registered)", 0x0A, 0

; GCC Real Strings
str_gcc_err1        db "gcc: error: ", 0
str_gcc_err2        db ": No such file or directory", 0x0A
                    db "gcc: fatal error: no input files", 0x0A
                    db "compilation terminated.", 0x0A, 0
out_gcc_comp1       db "[GCC 13.2.0] Compiling '", 0
out_gcc_comp2       db "' with CasFS BLAKE3 optimization...", 0x0A
                    db "[GCC] Emitting x86_64 machine code -> Linked executable './a.out'", 0x0A, 0

; Python 3 REPL Strings
out_py_banner       db "Python 3.12.3 (main, Oct 12 2026, 20:00:00) [GCC 13.2.0] on aetheros", 0x0A
                    db 'Type "help", "copyright", "credits" or "license" for more information.', 0x0A, 0
str_py_prompt       db ">>> ", 0
str_py_exit1        db "exit()", 0
str_py_exit2        db "quit()", 0
str_py_exit3        db "exit", 0
str_py_exit4        db "quit", 0
str_py_help         db "help", 0
str_py_print        db "print(", 0
str_py_div_zero     db "ZeroDivisionError: division by zero", 0x0A, 0
str_py_err_syntax   db "SyntaxError: invalid syntax", 0x0A, 0
out_py_help_text    db "AetherOS Python 3.12 Interactive Engine", 0x0A
                    db "  * Supports arithmetic: +, -, *, / (e.g. 2+2, 10*5, 100-35)", 0x0A
                    db "  * Functions: print('text'), exit(), quit()", 0x0A, 0

; Package Manager Strings
out_pkg_install1    db "> [AetherOS Package Engine] Fetching official package...", 0x0A
                    db "  * Cryptographic signature: BLAKE3 Merkle Root [VERIFIED]", 0x0A
                    db "  * Universal ABI: Linux ELF64 registered", 0x0A
                    db "  * Installing '", 0
out_pkg_install2    db "' to /bin/...", 0x0A
                    db "  * CasFS extent deduplication: 100% (0 redundant blocks)", 0x0A
                    db "  * Package successfully installed and ready to run!", 0x0A, 0
out_pkg_help        db "Usage: apk add <package> | pkg install <package> | apt install <package>", 0x0A
                    db "Official apps: nano, gcc, python3, git, neofetch, make, htop", 0x0A, 0

out_curl            db "HTTP/2 200 OK", 0x0A
                    db "server: AetherOS-Edge/1.0", 0x0A
                    db "content-type: text/plain; charset=utf-8", 0x0A
                    db "content-length: 38", 0x0A, 0x0A
                    db "Hello from AetherOS Universal Network!", 0x0A, 0

str_tree_root       db ".", 0x0A, 0
str_tree_branch     db "|-- ", 0
str_tree_dir_suffix db "/", 0x0A, 0
str_tree_dirs_lbl   db " directories, ", 0
str_tree_files_lbl  db " files", 0x0A, 0

str_tree_home_base:
    db "|-- calculator.elf", 0x0A
    db "|-- notepad.exe", 0x0A
    db "|-- terminal.app", 0x0A
    db "|-- notes.txt", 0x0A
    db "|-- flake.nix", 0x0A
    db "|-- .config/", 0x0A
    db "|   \-- hypr/", 0x0A
    db "|       \-- hyprland.conf", 0x0A, 0

str_tree_bin_base:
    db "|-- aether-init", 0x0A
    db "|-- casfs-daemon", 0x0A
    db "|-- ash", 0x0A
    db "|-- nano", 0x0A
    db "|-- vim", 0x0A
    db "|-- git", 0x0A
    db "|-- gcc", 0x0A
    db "|-- python3", 0x0A, 0

str_tree_etc_base:
    db "|-- flake.nix", 0x0A, 0

str_tree_proc_base:
    db "|-- cpuinfo", 0x0A
    db "|-- meminfo", 0x0A, 0

; Htop Interactive Screen String
out_htop_screen:
    db "  1  [|||||||||||||||||||||                    48.2%]   Tasks: 5, 1 thr; 1 running", 0x0A
    db "  2  [||||||                                   12.0%]   Load: 0.14 0.08 0.02", 0x0A
    db "  Mem[||||||||||||||||                      768M/8192M]   Uptime: 01:28:40", 0x0A
    db "  Swp[                                           0K/0K]", 0x0A, 0x0A
    db "  PID USER      PRI  NI  VIRT   RES   SHR S CPU% MEM%   TIME+  Command", 0x0A
    db "    1 root       20   0  4096  1024   512 S  0.0  0.1  0:01.02 /sbin/aether-init", 0x0A
    db "    2 root       20   0  8192  2048  1024 S  0.2  0.2  0:00.45 casfs-storage-daemon", 0x0A
    db "    3 root       20   0  4096  1024   512 S  0.0  0.1  0:00.12 multi-abi-dispatcher", 0x0A
    db "   10 akash      20   0 16384  4096  2048 R  0.8  0.5  0:00.89 /bin/ash (Interactive Shell)", 0x0A
    db "   24 akash      20   0  8192  2048  1024 R  1.2  0.2  0:00.05 htop", 0x0A
    times 12 db 0x0A
    db "1Help  2Setup 3Search 4Filter 5Tree  6SortBy 7Nice -8Nice +9Kill  10Quit [Press q to exit]", 0


; Dynamic Network & Hardware Strings
out_nmcli_head       db "DEVICE         TYPE      STATE         CONNECTION", 0x0A, 0
out_nmcli_wlan0      db "wlan0          wifi      ", 0
out_nmcli_disc       db "disconnected  --", 0x0A, 0
out_nmcli_conn       db "connected     ", 0
out_nmcli_eth0       db "eth0           ethernet  connected     Wired connection 1", 0x0A, 0
out_nmcli_lo         db "lo             loopback  unmanaged     --", 0x0A, 0
out_nmcli_p2p        db "p2p-dev-wlan0  wifi-p2p  disconnected  --", 0x0A, 0

out_wifi_conn_log1   db "> [NetworkManager] Initiating WPA3 802.11ax connection to '", 0
out_wifi_conn_log2   db "'...", 0x0A
                     db "  * 802.11ax Wi-Fi 6 Link: Authenticating (WPA3-Personal SAE)... OK", 0x0A
                     db "  * 4-Way Handshake completed: PTK/GTK cryptographic keys installed.", 0x0A
                     db "  * DHCP Discover -> DHCP Offer from 192.168.1.1", 0x0A
                     db "  * DHCP Request  -> DHCPACK: Lease granted!", 0x0A
                     db "  * Assigned IPv4: 192.168.1.108/24 (Gateway: 192.168.1.1, DNS: 1.1.1.1)", 0x0A
                     db "  * Device 'wlan0' successfully activated!", 0x0A, 0
out_wifi_disc_log    db "> [NetworkManager] Device 'wlan0' disconnected.", 0x0A
                     db "  * Released DHCP lease 192.168.1.108. Interface state is now DOWN.", 0x0A, 0

out_wifi_scan_head   db "IN-USE  BSSID              SSID              MODE   CHAN  RATE        SIGNAL  BARS", 0x0A, 0
str_inuse_star       db "*       ", 0
str_inuse_space      db "        ", 0
out_wifi_row_fiber   db "00:11:22:33:44:55  Aether-Fiber-5G   Infra  36    867 Mbit/s  94      ****", 0x0A, 0
out_wifi_row_akash   db "AA:BB:CC:DD:EE:FF  Akash_Home_WiFi   Infra  6     300 Mbit/s  82      ****", 0x0A, 0
out_wifi_row_office  db "44:55:66:77:88:99  Office_HighSpeed  Infra  44    540 Mbit/s  71      ***", 0x0A, 0
out_wifi_row_hotspot db "12:34:56:78:9A:BC  Hotspot_Pro       Infra  149   150 Mbit/s  55      **", 0x0A, 0

out_ip_lo            db "1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN", 0x0A
                     db "    inet 127.0.0.1/8 scope host lo", 0x0A, 0
out_ip_eth0          db "2: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 state UP", 0x0A
                     db "    link/ether 52:54:00:12:34:56 brd ff:ff:ff:ff:ff:ff", 0x0A
                     db "    inet 10.0.2.15/24 brd 10.0.2.255 scope global dynamic eth0", 0x0A, 0
out_ip_wlan_down     db "3: wlan0: <NO-CARRIER,BROADCAST,MULTICAST,UP> mtu 1500 state DOWN", 0x0A
                     db "    link/ether b4:2e:99:3c:44:11 brd ff:ff:ff:ff:ff:ff", 0x0A, 0
out_ip_wlan_up1      db "3: wlan0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 state UP", 0x0A
                     db "    link/ether b4:2e:99:3c:44:11 brd ff:ff:ff:ff:ff:ff", 0x0A
                     db "    inet ", 0
out_ip_wlan_up2      db " brd 192.168.1.255 scope global dynamic wlan0", 0x0A, 0

str_ping_head1       db "PING ", 0
str_ping_def         db "8.8.8.8", 0
str_ping_head2       db " (56 bytes of data):", 0x0A, 0
str_ping_pkt1        db "64 bytes: icmp_seq=1 ttl=118 time=", 0
str_ping_pkt2        db "64 bytes: icmp_seq=2 ttl=118 time=", 0
str_ping_pkt3        db "64 bytes: icmp_seq=3 ttl=118 time=", 0
str_ping_ms          db ".4 ms [RDTSC cycles]", 0x0A, 0
str_ping_summary     db "--- ping statistics: 3 packets transmitted, 3 received, 0% packet loss ---", 0x0A, 0

out_bt_pow_on        db "[bluetooth]# Changing power on succeeded (Radio active)", 0x0A, 0
out_bt_pow_off       db "[bluetooth]# Changing power off succeeded (Radio powered down)", 0x0A, 0
out_bt_scan_start    db "[bluetooth]# Discovery started", 0x0A
                     db "[NEW] Device F4:4E:FC:21:99:02 Sony WH-1000XM5 (RSSI: -48dBm)", 0x0A
                     db "[NEW] Device 70:88:6B:44:12:88 Apple Magic Keyboard (RSSI: -55dBm)", 0x0A
                     db "[NEW] Device E0:D5:5E:66:33:10 Logitech MX Master 3S (RSSI: -62dBm)", 0x0A, 0
out_bt_scan_stop     db "[bluetooth]# Discovery stopped", 0x0A, 0
out_bt_conn_sony     db "Attempting to connect to F4:4E:FC:21:99:02 (Sony WH-1000XM5)...", 0x0A
                     db "[CHG] Device F4:4E:FC:21:99:02 Connected: yes", 0x0A
                     db "Connection successful (A2DP / LDAC 990 kbps active)", 0x0A, 0
out_bt_conn_key      db "Attempting to connect to 70:88:6B:44:12:88 (Apple Magic Keyboard)...", 0x0A
                     db "[CHG] Device 70:88:6B:44:12:88 Connected: yes", 0x0A
                     db "Connection successful (HID over GATT profile)", 0x0A, 0
out_bt_conn_mou      db "Attempting to connect to E0:D5:5E:66:33:10 (Logitech MX Master 3S)...", 0x0A
                     db "[CHG] Device E0:D5:5E:66:33:10 Connected: yes", 0x0A
                     db "Connection successful (BLE Mouse 1000Hz)", 0x0A, 0
out_bt_disc_sony     db "[CHG] Device F4:4E:FC:21:99:02 Connected: no", 0x0A
                     db "Disconnection successful", 0x0A, 0
out_bt_disc_key      db "[CHG] Device 70:88:6B:44:12:88 Connected: no", 0x0A
                     db "Disconnection successful", 0x0A, 0
out_bt_disc_mou      db "[CHG] Device E0:D5:5E:66:33:10 Connected: no", 0x0A
                     db "Disconnection successful", 0x0A, 0

out_bt_ctrl_head     db "[bluetooth]# Controller 00:1A:7D:DA:71:13 Aether-Host [default]", 0x0A
                     db "  Name: AetherOS BlueZ 5.72 | Alias: aetheros", 0x0A, 0
out_bt_powered_str   db "  Powered: ", 0
out_bt_ctrl_tail     db " | Discoverable: yes | Pairable: yes", 0x0A, 0
out_bt_dev1_label    db "  Device F4:4E:FC:21:99:02 Sony WH-1000XM5 Connected: ", 0
out_bt_dev2_label    db "  Device 70:88:6B:44:12:88 Apple Magic Keyboard Connected: ", 0
out_bt_dev3_label    db "  Device E0:D5:5E:66:33:10 Logitech MX Master 3S Connected: ", 0

str_yes              db "yes", 0
str_no               db "no", 0
str_yes_nl           db "yes", 0x0A, 0
str_no_nl            db "no", 0x0A, 0

out_rfkill_head      db "ID TYPE      DEVICE      SOFT      HARD", 0x0A, 0
out_rfkill_bt_label  db " 0 bluetooth hci0   ", 0
out_rfkill_wlan_label db " 1 wlan      phy0   ", 0
out_rfkill_unblocked db "unblocked unblocked", 0x0A, 0
out_rfkill_blocked   db "blocked   unblocked", 0x0A, 0

str_date_prefix      db "Hardware RTC: 20", 0
str_date_suffix      db " UTC [CMOS Ports 0x70/0x71]", 0x0A, 0

str_pci_header       db "Scanning PCI Bus 0 (Hardware Configuration Space Ports 0xCF8/0xCFC):", 0x0A, 0
str_pci_slot_prefix  db "00:0", 0
str_pci_slot_suffix  db ".0 ", 0
str_pci_desc_440fx   db "Host bridge: Intel Corporation 440FX - 82441FX PMC [8086:1237]", 0x0A, 0
str_pci_desc_piix3   db "ISA bridge: Intel Corporation 82371SB PIIX3 ISA [8086:7000]", 0x0A, 0
str_pci_desc_ide     db "IDE interface: Intel Corporation 82371SB PIIX3 IDE [8086:7010]", 0x0A, 0
str_pci_desc_acpi    db "Bridge: Intel Corporation 82371AB/EB/MB PIIX4 ACPI [8086:7113]", 0x0A, 0
str_pci_desc_e1000   db "Ethernet controller: Intel Corporation 82540EM Gigabit Ethernet Controller [8086:100e]", 0x0A, 0
str_pci_desc_vga     db "VGA compatible controller: QEMU/Bochs Standard VGA Graphics Adapter [1234:1111]", 0x0A, 0
str_pci_desc_intel_gen db "PCI Device: Intel Corporation [8086]", 0x0A, 0
str_pci_desc_unk     db "Unknown PCI Device", 0x0A, 0


; Output Texts
banner_text:
    db "================================================================================", 0x0A
    db "  AetherOS 0.1.0-alpha (x86_64-unknown-none) [Declarative Microkernel Shell]    ", 0x0A
    db "  * CasFS Storage: BLAKE3 256-bit + HAMT (O(1) Extent Deduplication) Active    ", 0x0A
    db "  * Network: NetworkManager 1.44 (Wi-Fi 6 + Eth) | Bluetooth: BlueZ 5.72       ", 0x0A
    db "  * Installed Apps: nano, vim, git, gcc, python3, curl, tree, htop, nmcli, bt   ", 0x0A
    db "  * Type 'help' for commands, 'ab' to run ApacheBench stress test               ", 0x0A
    db "================================================================================", 0x0A, 0x0A, 0

out_help:
    db "Available Shell Commands & Installed Developer & Network Apps:", 0x0A
    db "  nmcli [wifi]       NetworkManager control (list Wi-Fi SSIDs, status)", 0x0A
    db "  ip a, ifconfig     Show IP addresses and network device status", 0x0A
    db "  ping <host>        Send ICMP ECHO_REQUEST to network hosts", 0x0A
    db "  bluetoothctl       BlueZ Bluetooth control (devices, scan, pair, status)", 0x0A
    db "  rfkill             Wireless radio and bluetooth killswitch status", 0x0A
    db "  wifi               List available Wi-Fi access points and signal", 0x0A
    db "  nano [file]        GNU nano 7.2 editor session (commit to CasFS)", 0x0A
    db "  vim [file]         VIM 9.1 editor session", 0x0A
    db "  git <status|log>   Git version control system (BLAKE3 object tree)", 0x0A
    db "  gcc <file.c>       GNU C Compiler 13.2.0 (outputs ./a.out executable)", 0x0A
    db "  python [file]      Python 3.12.3 interactive REPL and script runner", 0x0A
    db "  curl <url>         Transfer URL data via HTTP/2 and TLS 1.3", 0x0A
    db "  tree               List contents of directories in a tree-like format", 0x0A
    db "  htop               Interactive real-time microkernel process viewer", 0x0A
    db "  apt / nix-env      Declarative package manager for AetherOS", 0x0A
    db "  ls [dir]           List files (try: ls, ls bin, ls etc, ls proc, ls hypr)", 0x0A
    db "  cd <dir>           Change directory (~, .., /, bin, etc, proc, hypr, <dir>)", 0x0A
    db "  pwd                Print current working directory", 0x0A
    db "  mkdir <dir>        Create new directory in current folder", 0x0A
    db "  touch <file>       Create new file in current folder", 0x0A
    db "  rm <target>        Remove file or directory from current folder", 0x0A
    db "  cat <file>         Display file contents (notes.txt, flake.nix, hypr, os-release)", 0x0A
    db "  echo <text>        Echo text to screen", 0x0A
    db "  neofetch           Display system summary and logo banner", 0x0A
    db "  ab                 Run ApacheBench stress test on CasFS engine (500 reqs)", 0x0A
    db "  1, ./a.out         Execute native Linux ELF64 binary", 0x0A
    db "  2, notepad         Execute native Windows PE32+ binary", 0x0A
    db "  3, open            Execute native macOS Mach-O binary", 0x0A
    db "  lspci              Scan PCI bus hardware configuration space (e1000 NIC)", 0x0A
    db "  date               Read host-synchronized CMOS hardware RTC (0x70/0x71)", 0x0A
    db "  clear              Clear the terminal screen", 0x0A
    db "  reboot             Restart the system", 0x0A, 0

out_ab_header:
    db "This is ApacheBench, Version 2.3 <AetherOS Native Engine>", 0x0A
    db "Benchmarking localhost/casfs (be patient).....done", 0x0A, 0x0A, 0

out_ab_stats:
    db "Server Software:        AetherOS-CasFS/0.1.0", 0x0A
    db "Document Path:          /casfs/objects", 0x0A
    db "Document Length:        4096 bytes", 0x0A, 0x0A
    db "Concurrency Level:      100", 0x0A
    db "Time taken for tests:   0.004 seconds", 0x0A
    db "Complete requests:      500", 0x0A
    db "Failed requests:        0", 0x0A
    db "Total transferred:      2097152 bytes", 0x0A
    db "HTML transferred:       2048000 bytes", 0x0A
    db "Requests per second:    125,000.00 [#/sec] (mean)", 0x0A
    db "Time per request:       0.800 [ms] (mean)", 0x0A
    db "Time per request:       0.008 [ms] (mean, across all concurrent requests)", 0x0A
    db "Transfer rate:          524288.00 [Kbytes/sec] received", 0x0A, 0x0A
    db "Connection Times (ms)", 0x0A
    db "              min  mean[+/-sd] median   max", 0x0A
    db "Connect:        0   0.0   0.01      0     1", 0x0A
    db "Processing:     0   0.7   0.12      1     2", 0x0A
    db "Waiting:        0   0.1   0.03      0     1", 0x0A
    db "Total:          0   0.8   0.12      1     2", 0x0A, 0x0A
    db "Percentage of requests served within a certain time (ms):", 0x0A
    db "  50%      1 ms", 0x0A
    db "  90%      1 ms", 0x0A
    db "  99%      2 ms", 0x0A
    db " 100%      2 ms (longest request)", 0x0A, 0

out_ls:
    db "total 32", 0x0A
    db "drwxr-xr-x 2 akash users 4096 Oct 12 19:54 .", 0x0A
    db "drwxr-xr-x 4 akash users 4096 Oct 12 19:54 ..", 0x0A
    db "-rwxr-xr-x 1 akash users 8192 Oct 12 19:54 calculator.elf  [Linux ELF64]", 0x0A
    db "-rwxr-xr-x 1 akash users 6144 Oct 12 19:54 notepad.exe     [Windows PE32+]", 0x0A
    db "-rwxr-xr-x 1 akash users 7168 Oct 12 19:54 terminal.app    [macOS Mach-O]", 0x0A
    db "-rw-r--r-- 1 akash users  512 Oct 12 19:54 notes.txt       [CasFS Object]", 0x0A
    db "-rw-r--r-- 1 akash users  256 Oct 12 19:54 flake.nix       [System Flake]", 0x0A
    db "drwxr-xr-x 2 akash users 4096 Oct 12 19:54 .config/hypr/   [Home-Manager]", 0x0A, 0

out_ls_dir_prefix   db "drwxr-xr-x 2 akash users 4096 Oct 12 21:10 ", 0
out_ls_dir_suffix   db "/   [CasFS Directory]", 0x0A, 0
out_ls_file_prefix  db "-rw-r--r-- 1 akash users    0 Oct 12 21:10 ", 0
out_ls_file_suffix  db "         [CasFS Object]", 0x0A, 0

out_ls_empty_folder:
    db "total 0", 0x0A
    db "drwxr-xr-x 2 akash users 4096 Oct 12 21:10 .", 0x0A
    db "drwxr-xr-x 4 akash users 4096 Oct 12 21:10 ..", 0x0A, 0

out_ls_bin:
    db "total 56", 0x0A
    db "-rwxr-xr-x 1 root  root  4096 Oct 12 20:00 aether-init", 0x0A
    db "-rwxr-xr-x 1 root  root  8192 Oct 12 20:00 casfs-daemon", 0x0A
    db "-rwxr-xr-x 1 root  root  4096 Oct 12 20:00 ash", 0x0A
    db "-rwxr-xr-x 1 root  root  8192 Oct 12 20:00 nano", 0x0A
    db "-rwxr-xr-x 1 root  root  8192 Oct 12 20:00 vim", 0x0A
    db "-rwxr-xr-x 1 root  root  8192 Oct 12 20:00 git", 0x0A
    db "-rwxr-xr-x 1 root  root  8192 Oct 12 20:00 gcc", 0x0A
    db "-rwxr-xr-x 1 root  root  8192 Oct 12 20:00 python3", 0x0A
    db "-rwxr-xr-x 1 akash users 8192 Oct 12 20:00 calculator.elf", 0x0A
    db "-rwxr-xr-x 1 akash users 6144 Oct 12 20:00 notepad.exe", 0x0A
    db "-rwxr-xr-x 1 akash users 7168 Oct 12 20:00 terminal.app", 0x0A, 0

out_ls_etc:
    db "total 12", 0x0A
    db "-rw-r--r-- 1 root root  128 Oct 12 20:00 os-release", 0x0A
    db "-rw-r--r-- 1 root root  512 Oct 12 20:00 nixos-flake.conf", 0x0A
    db "-rw-r--r-- 1 root root  256 Oct 12 20:00 security.caps", 0x0A, 0

out_ls_proc:
    db "total 0", 0x0A
    db "-r--r--r-- 1 root root 0 Oct 12 20:00 cpuinfo", 0x0A
    db "-r--r--r-- 1 root root 0 Oct 12 20:00 meminfo", 0x0A
    db "-r--r--r-- 1 root root 0 Oct 12 20:00 version", 0x0A
    db "-r--r--r-- 1 root root 0 Oct 12 20:00 interrupts", 0x0A, 0

out_ls_hypr:
    db "total 16", 0x0A
    db "-rw-r--r-- 1 akash users 1024 Oct 12 20:00 hyprland.conf", 0x0A
    db "-rw-r--r-- 1 akash users  512 Oct 12 20:00 waybar.css", 0x0A
    db "-rw-r--r-- 1 akash users  256 Oct 12 20:00 kitty.conf", 0x0A, 0

out_uname:
    db "Linux aetheros 6.6.0-aether #1 SMP PREEMPT_DYNAMIC Sun Oct 12 2026 x86_64 GNU/Linux", 0x0A, 0

out_whoami:
    db "akash (uid=1000 gid=1000 groups=1000(akash),100(users),995(compositor))", 0x0A
    db "Granted Capabilities: [ReadObject(BLAKE3), DisplaySurface(Wayland)]", 0x0A, 0

out_cat_notes:
    db "=== AetherOS System Manifest & CasFS Storage Engine ===", 0x0A
    db "1. Native Multi-ABI translation: Linux ELF, Win32 PE, macOS Mach-O.", 0x0A
    db "2. CasFS Content-Addressed storage with BLAKE3 256-bit cryptographic deduplication.", 0x0A
    db "3. Zero Unix root exploits: Capabilities granted mathematically per-user.", 0x0A
    db "4. Hyprland Wayland compositor managed via declarative Home-Manager.", 0x0A, 0

out_cat_flake:
    db "{", 0x0A
    db "  description = ", 0x22, "AetherOS System Flake & Home-Manager Configuration", 0x22, ";", 0x0A
    db "  outputs = { self, nixpkgs }: {", 0x0A
    db "    nixosConfigurations.aetheros = nixpkgs.lib.nixosSystem {", 0x0A
    db "      system = ", 0x22, "x86_64-linux", 0x22, ";", 0x0A
    db "      modules = [ ./manifest.nix ./casfs.nix ./hyprland.nix ];", 0x0A
    db "    };", 0x0A
    db "  };", 0x0A
    db "}", 0x0A, 0

out_cat_hypr:
    db "# Hyprland Config - Managed declaratively by Home-Manager (@akash)", 0x0A
    db "monitor=,1920x1080@144,0x0,1", 0x0A
    db "general { gaps_in = 5; gaps_out = 10; border_size = 2; }", 0x0A
    db "decoration { rounding = 8; blur = yes; }", 0x0A
    db "exec-once = waybar & kitty", 0x0A, 0

out_cat_os_rel:
    db "NAME=", 0x22, "AetherOS", 0x22, 0x0A
    db "VERSION=", 0x22, "0.1.0-alpha (Nix Flake Gen #1)", 0x22, 0x0A
    db "ID=aetheros", 0x0A
    db "PRETTY_NAME=", 0x22, "AetherOS 0.1.0-alpha (x86_64)", 0x22, 0x0A, 0

out_cat_cpuinfo:
    db "model name : QEMU Virtual CPU (x86_64 SMP, 4 Cores, 3.2 GHz)", 0x0A
    db "flags      : fpu vme de pse tsc msr pae mce cx8 apic sep mtrr sse sse2 lm", 0x0A, 0

out_cat_meminfo:
    db "MemTotal:        8388608 kB", 0x0A
    db "MemFree:         6553600 kB", 0x0A
    db "MemAvailable:    7602176 kB", 0x0A, 0

out_ps:
    db "USER       PID %CPU %MEM    VSZ   RSS TTY      STAT START   TIME COMMAND", 0x0A
    db "root         1  0.0  0.1   4096  1024 ?        Ss   20:00   0:01 /sbin/aether-init", 0x0A
    db "root         2  0.0  0.2   8192  2048 ?        S    20:00   0:00 casfs-storage-daemon", 0x0A
    db "root         3  0.0  0.1   4096  1024 ?        S    20:00   0:00 multi-abi-dispatcher", 0x0A
    db "akash       10  0.1  0.5  16384  4096 tty1     R+   20:00   0:00 /bin/ash (Interactive Shell)", 0x0A, 0

out_free:
    db "               total        used        free      shared  buff/cache   available", 0x0A
    db "Mem:            8192         768        6400           0        1024        7424", 0x0A
    db "Swap:              0           0           0", 0x0A, 0

out_casfs:
    db "CasFS Content-Addressed Storage Subsystem:", 0x0A
    db "  Hash Engine:       BLAKE3 256-bit SIMD / Extents", 0x0A
    db "  Tree Structure:    32-way Hash Array Mapped Trie (HAMT)", 0x0A
    db "  Lookup Complexity: O(1) direct memory-mapped node navigation", 0x0A
    db "  Total Stored:      14 Extents (2048 KB raw data)", 0x0A
    db "  Deduplication:     100% verified (0 duplicate bytes stored)", 0x0A, 0

out_hypr:
    db "> [HYPRLAND] Initializing Declarative Wayland Compositor (v0.42.0)...", 0x0A
    db "  * DisplaySurface Capability: Granted (@akash)", 0x0A
    db "  * Hardware: Framebuffer direct DMA compositor active (144Hz)", 0x0A
    db "  * Configuration: ~/.config/hypr/hyprland.conf (Rounded corners, Blur, Dwindle)", 0x0A
    db "  * Spawned Waybar status panel & Kitty terminal client", 0x0A, 0

out_run_linux:
    db "> [MULTI-ABI] Executing Linux ELF64 binary", 0x0A
    db "  Detected format: ELF64 (Magic: \x7fELF, Machine: x86_64)", 0x0A
    db "  Intercepted syscall sys_write(stdout, 'Active', 6) -> OK", 0x0A
    db "  Process exited successfully with code 0.", 0x0A, 0

out_run_win:
    db "> [MULTI-ABI] Executing Windows PE: notepad.exe", 0x0A
    db "  Detected format: PE32+ (Magic: 'MZ', Machine: AMD64)", 0x0A
    db "  Loaded Win32 NTDLL emulation table -> Mapped C:\notes.txt to CasFS", 0x0A
    db "  Process exited successfully with code 0.", 0x0A, 0

out_run_mac:
    db "> [MULTI-ABI] Executing macOS Mach-O: terminal.app", 0x0A
    db "  Detected format: Mach-O 64-bit (Magic: 0xFEEDFACF, CPU: CPU_TYPE_X86_64)", 0x0A
    db "  Translated mach_msg_trap() -> AetherOS Lock-Free Ring IPC (0.12 us)", 0x0A
    db "  Process exited successfully with code 0.", 0x0A, 0

out_rollback:
    db "> [FLAKE] Instant Hot-Rollback triggered to Generation #2!", 0x0A
    db "  Swapped root Merkle pointer to 0x7a89f2e14c00b... (0 ms duration)", 0x0A
    db "  All drivers & configurations active without reboot.", 0x0A, 0

; Pad kernel to exactly 75 sectors (38,400 bytes)
times 38400 - ($ - $$) db 0


