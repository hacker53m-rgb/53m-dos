[BITS 16]
[ORG 0x7C00]

; ==================================================================
; SECTOR 1: BOOTLOADER
; ==================================================================
boot_start:
    xor ax, ax
    mov ds, ax
    mov es, ax

    mov ah, 0x00
    int 0x13                ; Reset disk controller

    ; Read Kernel + Credentials Sector (Sectors 2-16 = 8KB)
    mov ah, 0x02
    mov al, 15
    mov ch, 0
    mov cl, 2
    mov dh, 0
    mov bx, 0x7E00
    int 0x13

    jmp 0x0000:0x7E00

times 510-($-$$) db 0
dw 0xAA55

; ==================================================================
; SECTORS 2-16: 53M-DOS KERNEL
; ==================================================================
kernel_start:
    mov ax, 0x0003          ; Set 80x25 Video Text Mode
    int 0x10

    ; Install Custom System Call Interrupt Handler (INT 21h)
    cli
    mov word [0x0084], int21_handler
    mov word [0x0086], 0x0000
    sti

login_screen:
    mov byte [text_color], 0x07 ; Default light gray text
    mov si, msg_banner
    call print_string_color

.get_user:
    mov si, msg_ask_user
    call print_string_color
    mov di, active_user
    call read_line

    mov si, active_user
    mov di, user_admin
    call strcmp
    jc .check_admin_pass

    mov si, active_user
    mov di, user_guest
    call strcmp
    jc .check_guest_pass

    mov si, msg_invalid_user
    call print_string_color
    jmp .get_user

.check_admin_pass:
    mov si, msg_ask_pass
    call print_string_color
    mov di, pass_buffer
    call read_line_masked

    mov si, pass_buffer
    mov di, pass_admin
    call strcmp
    jc .login_success

    mov si, msg_login_fail
    call print_string_color
    jmp .get_user

.check_guest_pass:
    mov si, msg_ask_pass
    call print_string_color
    mov di, pass_buffer
    call read_line_masked

    mov si, pass_buffer
    mov di, pass_guest
    call strcmp
    jc .login_success

    mov si, msg_login_fail
    call print_string_color
    jmp .get_user

.login_success:
    mov si, msg_login_ok
    call print_string_color

prompt_loop:
    mov si, active_user
    call print_string_color
    mov si, msg_at
    call print_string_color
    mov si, current_drive
    call print_string_color
    mov si, msg_colon
    call print_string_color
    mov si, current_path
    call print_string_color
    mov si, msg_prompt_suffix
    call print_string_color

    mov di, buffer
    mov byte [buffer_len], 0

read_key:
    mov ah, 0x00
    int 0x16                ; BIOS Keyboard Input

    ; KEYBOARD SHORTCUTS
    cmp al, 0x0C            ; Ctrl + L -> Clear Screen
    je shortcut_cls

    cmp al, 0x0B            ; Ctrl + K -> Emergency Poweroff
    je do_shutdown

    cmp al, 0x0D            ; Enter
    je parse_and_execute_chain

    cmp al, 0x08            ; Backspace
    je handle_backspace

    mov [di], al
    inc di
    inc byte [buffer_len]
    call print_char_color
    jmp read_key

shortcut_cls:
    mov ax, 0x0003
    int 0x10
    jmp prompt_loop

handle_backspace:
    cmp byte [buffer_len], 0
    je read_key
    dec di
    dec byte [buffer_len]
    mov al, 0x08
    call print_char_color
    mov al, ' '
    call print_char_color
    mov al, 0x08
    call print_char_color
    jmp read_key

; ==================================================================
; COMMAND CHAINING ENGINE (&& PARSER)
; ==================================================================
parse_and_execute_chain:
    mov byte [di], 0
    mov si, msg_newline
    call print_string_color

    cmp byte [buffer_len], 0
    je prompt_loop

    mov si, buffer

.next_subcommand:
    call trim_leading_spaces
    cmp byte [si], 0
    je prompt_loop

    mov di, current_subcmd

.copy_subcmd:
    lodsb
    cmp al, 0
    je .run_last_subcmd
    cmp al, '&'
    je .check_second_amp
    stosb
    jmp .copy_subcmd

.check_second_amp:
    cmp byte [si], '&'
    je .found_chain
    mov byte [di], '&'
    inc di
    jmp .copy_subcmd

.found_chain:
    inc si                  ; Skip second '&'
    mov byte [di], 0
    push si                 ; Save remaining command buffer on stack
    call trim_trailing_spaces
    call process_single_command
    pop si                  ; Restore remaining command buffer
    jmp .next_subcommand

.run_last_subcmd:
    mov byte [di], 0
    call trim_trailing_spaces
    call process_single_command
    jmp prompt_loop

trim_leading_spaces:
.loop:
    cmp byte [si], ' '
    jne .done
    inc si
    jmp .loop
.done:
    ret

trim_trailing_spaces:
    push di
    dec di
.loop:
    cmp di, current_subcmd
    jb .done
    cmp byte [di], ' '
    jne .done
    mov byte [di], 0
    dec di
    jmp .loop
.done:
    pop di
    ret

; ==================================================================
; COMMAND DISPATCHER
; ==================================================================
process_single_command:
    cmp byte [current_subcmd], 0
    je .done

    ; DRIVE SELECTION
    mov si, current_subcmd
    mov di, cmd_c_drive
    call strcmp
    jc select_c

    mov si, current_subcmd
    mov di, cmd_d_drive
    call strcmp
    jc select_d

    ; EXACT COMMAND MATCHES
    mov si, current_subcmd
    mov di, cmd_ls
    call strcmp
    jc do_ls

    mov si, current_subcmd
    mov di, cmd_dir
    call strcmp
    jc do_ls

    mov si, current_subcmd
    mov di, cmd_nano
    call strcmp
    jc do_nano

    mov si, current_subcmd
    mov di, cmd_whoami
    call strcmp
    jc do_whoami

    mov si, current_subcmd
    mov di, cmd_logout
    call strcmp
    jc do_logout

    mov si, current_subcmd
    mov di, cmd_format
    call strcmp
    jc do_format

    mov si, current_subcmd
    mov di, cmd_cls
    call strcmp
    jc do_cls

    mov si, current_subcmd
    mov di, cmd_time
    call strcmp
    jc do_time

    mov si, current_subcmd
    mov di, cmd_date
    call strcmp
    jc do_date

    mov si, current_subcmd
    mov di, cmd_beep
    call strcmp
    jc do_beep

    mov si, current_subcmd
    mov di, cmd_ver
    call strcmp
    jc do_ver

    mov si, current_subcmd
    mov di, cmd_matrix
    call strcmp
    jc do_matrix

    mov si, current_subcmd
    mov di, cmd_passwd_reset
    call strcmp
    jc do_passwd_reset

    mov si, current_subcmd
    mov di, cmd_passwd_chng
    call strcmp
    jc do_passwd_reset

    mov si, current_subcmd
    mov di, cmd_help
    call strcmp
    jc do_help

    mov si, current_subcmd
    mov di, cmd_shutdown
    call strcmp
    jc do_shutdown

    mov si, current_subcmd
    mov di, cmd_poweroff
    call strcmp
    jc do_shutdown

    ; PREFIX COMMANDS
    mov si, current_subcmd
    mov di, cmd_echo_prefix
    call strncmp
    jc do_echo

    mov si, current_subcmd
    mov di, cmd_mkdir_prefix
    call strncmp
    jc do_mkdir

    mov si, current_subcmd
    mov di, cmd_cd_prefix
    call strncmp
    jc do_cd

    mov si, current_subcmd
    mov di, cmd_cat_prefix
    call strncmp
    jc do_cat

    mov si, current_subcmd
    mov di, cmd_color_prefix
    call strncmp
    jc do_color

    mov si, msg_unknown
    call print_string_color
.done:
    ret

; ==================================================================
; SYSTEM CALL INTERRUPT (INT 21h) HANDLER
; ==================================================================
int21_handler:
    cmp ah, 0x09            ; AH = 0x09: Print string (DS:SI)
    je .print
    cmp ah, 0x01            ; AH = 0x01: Read char
    je .read
    iret
.print:
    call print_string_color
    iret
.read:
    mov ah, 0x00
    int 0x16
    iret

; ==================================================================
; COMMAND IMPLEMENTATIONS
; ==================================================================

select_c:
    mov byte [active_disk_id], 0x80
    mov byte [current_drive], 'C'
    mov byte [current_path], '\'
    mov byte [current_path + 1], 0
    mov si, msg_drive_changed
    call print_string_color
    ret

select_d:
    mov byte [active_disk_id], 0x81
    mov byte [current_drive], 'D'
    mov byte [current_path], '\'
    mov byte [current_path + 1], 0
    mov si, msg_drive_changed
    call print_string_color
    ret

do_whoami:
    mov si, msg_user_is
    call print_string_color
    mov si, active_user
    call print_string_color
    mov si, msg_newline
    call print_string_color
    ret

do_ver:
    mov si, msg_ver_info
    call print_string_color
    ret

do_echo:
    mov si, current_subcmd + 5
    call print_string_color
    mov si, msg_newline
    call print_string_color
    ret

do_logout:
    jmp kernel_start

do_cls:
    mov ax, 0x0003
    int 0x10
    ret

do_time:
    mov ah, 0x02
    int 0x1A

    mov al, ch              ; Hours
    call print_bcd
    mov al, ':'
    call print_char_color

    mov al, cl              ; Minutes
    call print_bcd
    mov al, ':'
    call print_char_color

    mov al, dh              ; Seconds
    call print_bcd

    mov si, msg_newline
    call print_string_color
    ret

do_date:
    mov ah, 0x04
    int 0x1A
    jc .date_err

    mov al, ch              ; Century
    call print_bcd
    mov al, cl              ; Year
    call print_bcd

    mov al, '/'
    call print_char_color

    mov al, dh              ; Month
    call print_bcd

    mov al, '/'
    call print_char_color

    mov al, dl              ; Day
    call print_bcd

    mov si, msg_newline
    call print_string_color
    ret

.date_err:
    mov si, msg_disk_err
    call print_string_color
    ret

print_bcd:
    push ax
    shr al, 4
    add al, '0'
    call print_char_color
    pop ax
    and al, 0x0F
    add al, '0'
    call print_char_color
    ret

; ==================================================================
; PERSISTENT PASSWORD RESET IMPLEMENTATION
; ==================================================================
do_passwd_reset:
    mov si, msg_pass_curr
    call print_string_color
    mov di, pass_buffer
    call read_line_masked

    ; Verify Current Password
    mov si, active_user
    mov di, user_admin
    call strcmp
    jc .check_curr_admin

    mov si, pass_buffer
    mov di, pass_guest
    call strcmp
    jc .get_new_pass
    jmp .bad_old_pass

.check_curr_admin:
    mov si, pass_buffer
    mov di, pass_admin
    call strcmp
    jnc .bad_old_pass

.get_new_pass:
    mov si, msg_pass_new
    call print_string_color
    mov di, new_pass_temp
    call read_line_masked

    mov si, msg_pass_confirm
    call print_string_color
    mov di, pass_buffer
    call read_line_masked

    ; Compare New Password with Confirmation
    mov si, new_pass_temp
    mov di, pass_buffer
    call strcmp
    jnc .mismatch

    ; Copy new password to active account in RAM
    mov si, active_user
    mov di, user_admin
    call strcmp
    jc .update_admin_ram

    mov si, new_pass_temp
    mov di, pass_guest
    call strcpy
    jmp .commit_disk

.update_admin_ram:
    mov si, new_pass_temp
    mov di, pass_admin
    call strcpy

.commit_disk:
    ; Write updated Sector 3 (Sector offset from origin) directly back to disk
    mov ah, 0x03            ; BIOS Write Sector
    mov al, 1               ; 1 sector
    mov ch, 0               ; Cylinder 0
    mov cl, 3               ; Sector 3 (Credentials Sector)
    mov dh, 0               ; Head 0
    mov dl, 0x80            ; Primary Boot Drive
    mov bx, sector_3_start  ; Memory location of credentials block
    int 0x13

    jc .disk_write_err

    mov si, msg_pass_success
    call print_string_color
    ret

.bad_old_pass:
    mov si, msg_pass_err_curr
    call print_string_color
    ret

.mismatch:
    mov si, msg_pass_mismatch
    call print_string_color
    ret

.disk_write_err:
    mov si, msg_disk_err
    call print_string_color
    ret

strcpy:
.loop:
    lodsb
    stosb
    or al, al
    jnz .loop
    ret

do_beep:
    mov al, 0xB6
    out 0x43, al
    mov ax, 0x0B6C
    out 0x42, al
    mov al, ah
    out 0x42, al

    in al, 0x61
    or al, 0x03
    out 0x61, al

    mov cx, 0xFFFF
.delay:
    loop .delay

    in al, 0x61
    and al, 0xFC
    out 0x61, al
    ret

do_matrix:
    mov ax, 0x0003
    int 0x10
    mov cx, 150
.m_loop:
    mov ah, 0x00
    int 0x1A                ; Get tick count
    mov al, dl
    and al, 0x7F
    add al, 33

    mov ah, 0x0E
    mov bh, 0x00
    mov bl, 0x02            ; Green Matrix
    int 0x10

    push cx
    mov cx, 0x1000
.d: loop .d
    pop cx

    mov ah, 0x01
    int 0x16
    jnz .m_exit
    loop .m_loop

.m_exit:
    mov ax, 0x0003
    int 0x10
    ret

do_cat:
    mov si, current_subcmd + 4
    cmp byte [si], 0
    je .cat_usage

    mov ah, 0x02
    mov al, 1
    mov ch, 0
    mov cl, 2
    mov dh, 0
    mov dl, [active_disk_id]
    mov bx, sector_buffer
    int 0x13

    jc .cat_err

    mov si, sector_buffer
    cmp byte [si], 0
    je .cat_empty

    mov ah, 0x09
    int 0x21

    mov si, msg_newline
    call print_string_color
    ret

.cat_empty:
    mov si, msg_dir_empty
    call print_string_color
    ret

.cat_usage:
    mov si, msg_cat_usage
    call print_string_color
    ret

.cat_err:
    mov si, msg_disk_err
    call print_string_color
    ret

do_color:
    mov si, current_subcmd + 6

    mov di, col_green
    call strcmp
    jc .set_green

    mov di, col_cyan
    call strcmp
    jc .set_cyan

    mov di, col_red
    call strcmp
    jc .set_red

    mov di, col_white
    call strcmp
    jc .set_white

    mov si, msg_color_usage
    call print_string_color
    ret

.set_green:
    mov byte [text_color], 0x0A
    ret

.set_cyan:
    mov byte [text_color], 0x0B
    ret

.set_red:
    mov byte [text_color], 0x0C
    ret

.set_white:
    mov byte [text_color], 0x07
    ret

do_shutdown:
    mov si, msg_shutting_down
    call print_string_color

    mov ax, 0x2000
    mov dx, 0x604
    out dx, ax

    mov ax, 0x5301
    xor bx, bx
    int 0x15

    mov ax, 0x530E
    xor bx, bx
    mov cx, 0x0102
    int 0x15

    mov ax, 0x5307
    mov bx, 0x0001
    mov cx, 0x0003
    int 0x15

.halt_loop:
    cli
    hlt
    jmp .halt_loop

do_cd:
    mov si, current_subcmd + 3
    cmp byte [si], 0
    je .show_path

    mov di, cmd_dotdot
    call strcmp
    jc .go_root

    mov di, current_path

.find_end:
    cmp byte [di], 0
    je .append
    inc di
    jmp .find_end

.append:
    cmp byte [current_path + 1], 0
    je .copy_folder
    mov byte [di], '\'
    inc di

.copy_folder:
    lodsb
    or al, al
    jz .done_cd
    stosb
    jmp .copy_folder

.done_cd:
    mov byte [di], 0
    ret

.go_root:
    mov byte [current_path], '\'
    mov byte [current_path + 1], 0
    ret

.show_path:
    mov si, current_path
    call print_string_color
    mov si, msg_newline
    call print_string_color
    ret

do_ls:
    mov ah, 0x02
    mov al, 1
    mov ch, 0
    mov cl, 2
    mov dh, 0
    mov dl, [active_disk_id]
    mov bx, sector_buffer
    int 0x13

    jc .ls_err

    mov si, msg_ls_header
    call print_string_color

    mov si, sector_buffer
    cmp byte [si], 0
    je .empty

    call print_string_color
    mov si, msg_newline
    call print_string_color
    ret

.empty:
    mov si, msg_dir_empty
    call print_string_color
    ret

.ls_err:
    mov si, msg_disk_err
    call print_string_color
    ret

do_mkdir:
    mov si, current_subcmd + 6
    cmp byte [si], 0
    je .missing_arg

    mov di, sector_buffer
    mov cx, 512
    xor al, al
    rep stosb

    mov di, sector_buffer
    mov byte [di], '<'
    inc di
    mov byte [di], 'D'
    inc di
    mov byte [di], 'I'
    inc di
    mov byte [di], 'R'
    inc di
    mov byte [di], '>'
    inc di
    mov byte [di], ' '
    inc di

.copy_dirname:
    lodsb
    or al, al
    jz .write_dir_disk
    stosb
    jmp .copy_dirname

.write_dir_disk:
    mov ah, 0x03
    mov al, 1
    mov ch, 0
    mov cl, 2
    mov dh, 0
    mov dl, [active_disk_id]
    mov bx, sector_buffer
    int 0x13

    jc .mkdir_err

    mov si, msg_mkdir_ok
    call print_string_color
    ret

.missing_arg:
    mov si, msg_mkdir_usage
    call print_string_color
    ret

.mkdir_err:
    mov si, msg_disk_err
    call print_string_color
    ret

do_nano:
    mov si, msg_nano_header
    call print_string_color

    mov di, file_buffer
    mov cx, 512
    xor al, al
    rep stosb

    mov di, file_buffer
    mov word [file_size], 0

.nano_loop:
    mov ah, 0x00
    int 0x16

    cmp al, 0x0F            ; Ctrl + O
    je .prompt_save

    cmp al, 0x18            ; Ctrl + X
    je .exit_nano

    cmp al, 0x0D            ; Enter
    je .nano_newline

    cmp al, 0x08            ; Backspace
    je .nano_backspace

    mov [di], al
    inc di
    inc word [file_size]
    call print_char_color
    jmp .nano_loop

.nano_newline:
    mov byte [di], 0x0D
    inc di
    mov byte [di], 0x0A
    inc di
    add word [file_size], 2
    mov si, msg_newline
    call print_string_color
    jmp .nano_loop

.nano_backspace:
    cmp word [file_size], 0
    je .nano_loop
    dec di
    dec word [file_size]
    mov al, 0x08
    call print_char_color
    mov al, ' '
    call print_char_color
    mov al, 0x08
    call print_char_color
    jmp .nano_loop

.prompt_save:
    mov si, msg_newline
    call print_string_color
    mov si, msg_nano_file_prompt
    call print_string_color

    mov di, filename_buffer
    call read_line

    mov di, sector_buffer
    mov si, filename_buffer

.copy_fname:
    lodsb
    or al, al
    jz .fname_done
    stosb
    jmp .copy_fname

.fname_done:
    mov byte [di], ':'
    inc di
    mov byte [di], ' '
    inc di

    mov si, file_buffer
.copy_content:
    lodsb
    or al, al
    jz .write_disk
    stosb
    jmp .copy_content

.write_disk:
    mov ah, 0x03
    mov al, 1
    mov ch, 0
    mov cl, 2
    mov dh, 0
    mov dl, [active_disk_id]
    mov bx, sector_buffer
    int 0x13

    jc .nano_err

    mov si, msg_nano_saved
    call print_string_color
    jmp .nano_loop

.nano_err:
    mov si, msg_disk_err
    call print_string_color
    ret

.exit_nano:
    mov si, msg_newline
    call print_string_color
    mov si, msg_nano_exit
    call print_string_color
    ret

do_format:
    mov di, sector_buffer
    mov cx, 512
    xor al, al
    rep stosb

    mov ah, 0x03
    mov al, 1
    mov ch, 0
    mov cl, 2
    mov dh, 0
    mov dl, [active_disk_id]
    mov bx, sector_buffer
    int 0x13

    jc .format_err

    mov si, msg_format_success
    call print_string_color
    ret

.format_err:
    mov si, msg_disk_err
    call print_string_color
    ret

do_help:
    mov si, msg_help
    call print_string_color
    ret

; ==================================================================
; UTILITIES & COLOR PRINTING
; ==================================================================
read_line:
    mov cx, 0
.loop:
    mov ah, 0x00
    int 0x16
    cmp al, 0x0D
    je .done
    cmp al, 0x08
    je .backspace
    mov [di], al
    inc di
    inc cx
    call print_char_color
    jmp .loop
.backspace:
    jcxz .loop
    dec di
    dec cx
    mov al, 0x08
    call print_char_color
    mov al, ' '
    call print_char_color
    mov al, 0x08
    call print_char_color
    jmp .loop
.done:
    mov byte [di], 0
    mov si, msg_newline
    call print_string_color
    ret

read_line_masked:
.loop:
    mov ah, 0x00
    int 0x16
    cmp al, 0x0D
    je .done
    cmp al, 0x08
    je .loop
    mov [di], al
    inc di
    mov al, '*'
    call print_char_color
    jmp .loop
.done:
    mov byte [di], 0
    mov si, msg_newline
    call print_string_color
    ret

print_char_color:
    mov ah, 0x0E
    mov bh, 0x00
    mov bl, [text_color]
    int 0x10
    ret

print_string_color:
    lodsb
    or al, al
    jz .done
    call print_char_color
    jmp print_string_color
.done:
    ret

strcmp:
.loop:
    mov al, [si]
    mov bl, [di]
    cmp al, bl
    jne .not_equal
    or al, al
    jz .equal
    inc si
    inc di
    jmp .loop
.equal:
    stc
    ret
.not_equal:
    clc
    ret

strncmp:
.loop:
    mov al, [si]
    mov bl, [di]
    cmp bl, 0
    je .equal
    cmp al, bl
    jne .not_equal
    inc si
    inc di
    jmp .loop
.equal:
    stc
    ret
.not_equal:
    clc
    ret

; ==================================================================
; DATA STORAGE
; ==================================================================
buffer              times 128 db 0
current_subcmd      times 64 db 0
filename_buffer     times 32 db 0
pass_buffer         times 32 db 0
new_pass_temp       times 32 db 0
active_user         times 32 db 0
current_path        db "\", 0
                    times 64 db 0

buffer_len          db 0
text_color          db 0x07        ; BIOS Color Attribute
file_buffer         times 512 db 0
sector_buffer       times 512 db 0
file_size           dw 0

; ==================================================================
; SECTOR 3: CREDENTIALS BLOCK (PERSISTENT ON DISK)
; ==================================================================
sector_3_start:
user_admin          db "admin", 0
pass_admin          db "admin123", 0
                    times 32 db 0

user_guest          db "guest", 0
pass_guest          db "guest123", 0
                    times 424 db 0

active_disk_id      db 0x80
current_drive       db 'C', 0

cmd_c_drive         db "c:", 0
cmd_d_drive         db "d:", 0
cmd_ls              db "ls", 0
cmd_dir             db "dir", 0
cmd_nano            db "nano", 0
cmd_whoami          db "whoami", 0
cmd_logout          db "logout", 0
cmd_format          db "format", 0
cmd_cls             db "cls", 0
cmd_time            db "time", 0
cmd_date            db "date", 0
cmd_beep            db "beep", 0
cmd_ver             db "ver", 0
cmd_matrix          db "matrix", 0
cmd_passwd_reset    db "passwd reset", 0
cmd_passwd_chng     db "passwd chng", 0
cmd_help            db "help", 0
cmd_shutdown        db "shutdown", 0
cmd_poweroff        db "poweroff", 0
cmd_echo_prefix     db "echo ", 0
cmd_mkdir_prefix    db "mkdir ", 0
cmd_cd_prefix       db "cd ", 0
cmd_cat_prefix      db "cat ", 0
cmd_color_prefix    db "color ", 0
cmd_dotdot          db "..", 0

col_green           db "green", 0
col_cyan            db "cyan", 0
col_red             db "red", 0
col_white           db "white", 0

msg_banner          db "==========================================", 0x0D, 0x0A
                    db "  53M-DOS 19.0 REAL-MODE OS (v1.0 Persistent)", 0x0D, 0x0A
                    db "==========================================", 0x0D, 0x0A, 0x0D, 0x0A, 0
msg_ask_user        db "Username (admin / guest): ", 0
msg_ask_pass        db "Password: ", 0
msg_invalid_user    db "User account not found!", 0x0D, 0x0A, 0x0D, 0x0A, 0
msg_login_fail      db "Access Denied: Incorrect password.", 0x0D, 0x0A, 0x0D, 0x0A, 0
msg_login_ok        db "Authentication Successful! Loading Kernel...", 0x0D, 0x0A, 0x0D, 0x0A, 0

msg_at              db "@", 0
msg_colon           db ":", 0
msg_prompt_suffix   db "> ", 0
msg_newline         db 0x0D, 0x0A, 0
msg_unknown         db "Bad command or file name. Type 'help'.", 0x0D, 0x0A, 0
msg_drive_changed   db "Switched active drive pointer.", 0x0D, 0x0A, 0
msg_user_is         db "Currently authenticated user: ", 0
msg_ver_info        db "53M-DOS Kernel Version 19.0 (16-bit x86 Real Mode)", 0x0D, 0x0A, 0
msg_dir_empty       db "Directory empty. Use 'mkdir' or 'nano'.", 0x0D, 0x0A, 0
msg_disk_err        db "HARDWARE ERROR: BIOS Sector I/O Fault.", 0x0D, 0x0A, 0
msg_format_success  db "Drive Sector 2 cleared successfully.", 0x0D, 0x0A, 0
msg_mkdir_ok        db "Directory created successfully!", 0x0D, 0x0A, 0
msg_mkdir_usage     db "Usage: mkdir <folder_name>", 0x0D, 0x0A, 0
msg_cat_usage       db "Usage: cat <file_name>", 0x0D, 0x0A, 0
msg_color_usage     db "Usage: color [green|cyan|red|white]", 0x0D, 0x0A, 0
msg_shutting_down   db "Shutting down system power...", 0x0D, 0x0A, 0

msg_pass_curr       db "Enter current password: ", 0
msg_pass_new        db "Enter new password: ", 0
msg_pass_confirm    db "Confirm new password: ", 0
msg_pass_err_curr   db "Error: Incorrect current password.", 0x0D, 0x0A, 0
msg_pass_mismatch   db "Error: Passwords do not match.", 0x0D, 0x0A, 0
msg_pass_success    db "Password updated and committed persistently to disk sector!", 0x0D, 0x0A, 0

msg_help            db "Commands: c:, d:, cd, mkdir, ls, nano, cat, echo, color, time, date, beep, ver, matrix, passwd reset, passwd chng, whoami, logout, shutdown, cls", 0x0D, 0x0A
                    db "Feature: Chain commands using '&&' (e.g. time && date)", 0x0D, 0x0A
                    db "Shortcuts: Ctrl+L (Clear Screen) | Ctrl+K (Shutdown)", 0x0D, 0x0A, 0

msg_nano_header     db "--- 53M-DOS Nano --- [Ctrl+O = WriteOut | Ctrl+X = Exit]", 0x0D, 0x0A, 0x0D, 0x0A, 0
msg_nano_file_prompt db "File Name to Write: ", 0
msg_nano_saved      db "[File committed directly to disk sector!]", 0x0D, 0x0A, 0
msg_nano_exit       db "Exited Nano Editor.", 0x0D, 0x0A, 0
msg_ls_header       db "Directory Listing:", 0x0D, 0x0A, 0

times 8192-($-$$) db 0