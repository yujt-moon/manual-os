[bits 32]
%define ERROR_CODE nop          ; 若在相关的异常中 CPU 已经自动压入了，错误码，为保持栈中格式统一，这里不做操作
%define ZERO push 0             ; 若在相关的异常中 CPU 没有压入错误码，为了统一栈中格式，就手工压入一个 0

extern idt_table                  ; idt_table 是 c 中注册的中断处理程序数组

section .data
global intr_entry_table
intr_entry_table:

%macro VECTOR 2
section .text
intr%1entry:                    ; 每个中断处理程序都要压入中断向量号，所以一个中断类型一个中断处理程序，自己知道自己的中断向量号是多少

    %2
; 以下是保存上下文环境
    push ds
    push es
    push fs
    push gs
    pushad                      ; PUSHAD 指令压入 32 位寄存器，其入栈顺序是：EAX,ECX,EDX,EBX,ESP,EBP,ESI,EDI,EAX 最先入栈

    ; 如果是从片上进入的中断，除了往从片上发送 EOI 外，还要往主片上发送 EOI
    mov al, 0x20                ; 中断结束命令 EOI
    out 0xa0, al                ; 向从片发送
    out 0x20, al                ; 向主片发送

    push %1                     ; 不管 idt_table 中的目标是否需要参数都一律压入中断向量号，调试时很方便
    call [idt_table + %1*4]     ; 调用 idt_table 中的 C 版本中断处理函数
    jmp intr_exit

section .data
    dd intr%1entry             ; 存储各个中断入口程序的地址，形成 intr_entry_table 数组
%endmacro

section .text
global intr_exit
intr_exit:
; 以下是恢复上下文系统
    add esp, 4                  ; 跳过中断号
    popad
    pop gs
    pop fs
    pop es
    pop ds
    add esp, 4                  ; 跳过 error_code
    iretd

VECTOR 0x00, ZERO
VECTOR 0x01, ZERO
VECTOR 0x02, ZERO
VECTOR 0x03, ZERO
VECTOR 0x04, ZERO
VECTOR 0x05, ZERO
VECTOR 0x06, ZERO
VECTOR 0x07, ZERO
VECTOR 0x08, ERROR_CODE
VECTOR 0x09, ZERO
VECTOR 0x0a, ERROR_CODE
VECTOR 0x0b, ERROR_CODE
VECTOR 0x0c, ZERO
VECTOR 0x0d, ERROR_CODE
VECTOR 0x0e, ERROR_CODE
VECTOR 0x0f, ZERO
VECTOR 0x10, ZERO
VECTOR 0x11, ERROR_CODE
VECTOR 0x12, ZERO
VECTOR 0x13, ZERO
VECTOR 0x14, ZERO
VECTOR 0x15, ZERO
VECTOR 0x16, ZERO
VECTOR 0x17, ZERO
VECTOR 0x18, ERROR_CODE
VECTOR 0x19, ZERO
VECTOR 0x1a, ERROR_CODE
VECTOR 0x1b, ERROR_CODE
VECTOR 0x1c, ZERO
VECTOR 0x1d, ERROR_CODE
VECTOR 0x1e, ERROR_CODE
VECTOR 0x1f, ZERO
VECTOR 0x20, ZERO           ; 时钟中断对应的入口
VECTOR 0x21, ZERO           ; 键盘中断对应的入口
VECTOR 0x22, ZERO           ; 级联用的
VECTOR 0x23, ZERO           ; 串口 2 对应的入口
VECTOR 0x24, ZERO           ; 串口 1 对应的入口
VECTOR 0x25, ZERO           ; 并口 2 对应的入口
VECTOR 0x26, ZERO           ; 软盘对应的入口
VECTOR 0x27, ZERO           ; 并口 1 对应的入口
VECTOR 0x28, ZERO           ; 实时时钟对应的入口
VECTOR 0x29, ZERO           ; 重定向
VECTOR 0x2a, ZERO           ; 保留
VECTOR 0x2b, ZERO           ; 保留
VECTOR 0x2c, ZERO           ; ps/2 鼠标
VECTOR 0x2d, ZERO           ; fpu 浮点单元异常
VECTOR 0x2e, ZERO           ; 硬盘
VECTOR 0x2f, ZERO           ; 保留

;;;;;;;;;;;;;;;; 0x80 号中断 ;;;;;;;;;;;;;;;;
[bits 32]
extern syscall_table
section .text
global syscall_handler
syscall_handler:
;1 保护上下文环境
    push 0          ; 压入 0,使栈中格式统一

    push ds
    push es
    push fs
    push gs
    pushad          ; PUSHAD 指令压入 32 位寄存器，其入栈顺序是：
                    ; EAX,ECX,EDX,EBX,ESP,EBP,ESI,EDI

    push 0x80       ; 此位置压入 0x80 也是为了保持统一的栈格式

;2 从内核栈中获取 cpu 自动压入的用户栈指针 esp 的值
    mov ebx, [esp + 4 + 48 + 4 +12]

;3 再把参数重新压在内核栈中，此时 ebx 是用户栈指针
; 由于此处只压入了三个参数，所以目前系统调用最多支持 3 个参数
    push dword [ebx + 12]       ; 系统调用的第 3 个参数
    push dword [ebx + 8]        ; 系统调用的第 2 个参数
    push dword [ebx + 4]        ; 系统调用的第 1 个参数
    mov edx, [ebx]              ; 系统调用的子功能号

    ; 编译器会在栈中根据 C 函数声明匹配正确数量的参数
    call [syscall_table + edx*4]
    add esp, 12                 ; 跨过上面的三个参数

;4 将 call 调用后的返回值存入当前内核栈中 eax 的位置
    mov [esp + 8*4], eax
    jmp intr_exit   ; intr_exit 返回，恢复上下文