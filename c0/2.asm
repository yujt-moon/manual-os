section .text
mov eax, 0x10
jmp $

section file2data           ; 自定义的数据段，未使用“传统”的.data数据段

file2var db 3

section file2text           ; 自定义的代码段，未使用“传统”的.text

global print                ; 导出print，供其他模块使用

print:
    mov edx, [esp+8]        ; 字符串长度
    mov ecx, [esp+4]        ; 字符串

    mov ebx, 1
    mov eax, 4              ; sys_write
    int 0x80                ; 系统调用
    ret