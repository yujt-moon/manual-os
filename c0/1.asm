section .bss
resb 2 * 32

section file1data       ; 自定义的数据段，未使用“传统”的.data

strHello db "Hello,world!", 0Ah
STRLEN equ $ - strHello

section file1text       ; 自定义的代码段，未使用“传统“的.text
extern print            ; 声明此函数在别的文件中，
                        ; 告诉编译器在编译本文件时找不到此符号也没关系，在链接时会找到
global _start           ; 连接器把_start当作程序的入口

_start:
    push STRLEN         ; 传入参数，字符串长度
    push strHello       ; 传入参数，待打印的字符串
    call print          ; 此函数定义在2.asm

; 返回到系统
mov ebx, 0              ; 返回值4
mov eax, 1              ; 系统调用号1：sys_exit
int 0x80                ; 系统调用