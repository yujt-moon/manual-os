section .data
str: db "asm_print syas hello world!", 0xa, 0
; 0xa 是换行符，0 是手工加上的字符串结束符\0 的 ASCII 码
str_len equ $-str

section .text
extern c_print
global _start
_start:
;;;;;;;;;;;;;;; 调用 a 代码中的函数 c_print ;;;;;;;;;;;;;;;;;
    push str            ; 传入参数
    call c_print        ; 调用 a 函数
    add esp, 4          ; 回收栈空间

;;;;;;;;;;;;;; 退出程序 ;;;;;;;;;;;;;;;;
    mov eax, 1          ; 第 1 号子功能是 exit 系统调用
    int 0x80            ; 发起中断，通知 Linux 完成请求的功能

global asm_print        ; 相当于 asm_print(str, size)
asm_print:
    push ebp            ; 备份 ebp
    mov ebp, esp
    mov eax, 4          ; 第 4 号子功能是 write 系统调用
    mov ebx, 1          ; 此项固定为文件描述符 1，标准输出（stdout）指向屏幕
    mov ecx, [ebp+8]    ; 第 1 个参数
    mov edx, [ebp+12]   ; 第 2 个参数
    int 0x80            ; 发起中断，通知 Linux 完成请求的功能
    pop ebp             ; 恢复 ebp
    ret
