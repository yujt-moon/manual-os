    %include "boot.inc"
    section loader vstart=LOADER_BASE_ADDR
    LOADER_STACK_TOP equ LOADER_BASE_ADDR

;构建gdt及其内部的描述符
    GDT_BASE:   dd    0x00000000    ; 全局描述符基址（共8位），第0位没有用
                dd    0x00000000

    CODE_DESC:  dd    0x0000FFFF   ; 代码段描述符
	            dd    DESC_CODE_HIGH4

    DATA_STACK_DESC:  dd    0x0000FFFF  ; 数据段和栈段描述符
		                dd    DESC_DATA_HIGH4

    VIDEO_DESC: dd    0x80000007	       ;limit=(0xbffff-0xb8000)/4k=0x7 显存段描述符
	            dd    DESC_VIDEO_HIGH4  ; 此时dpl已改为0

    GDT_SIZE     equ   $ - GDT_BASE
    GDT_LIMIT    equ   GDT_SIZE - 1
    times 60 dq 0					 ; 此处预留60个描述符的slot
    SELECTOR_CODE equ (0x0001<<3) + TI_GDT + RPL0     ; 相当于(CODE_DESC - GDT_BASE)/8 + TI_GDT + RPL0
    SELECTOR_DATA equ (0x0002<<3) + TI_GDT + RPL0	 ; 同上
    SELECTOR_VIDEO equ (0x0003<<3) + TI_GDT + RPL0	 ; 同上

    ; total_mem_bytes 用于保存内存容量，以字节为单位，此位置比较好记
    ; 当前偏移 loader.bin 文件头 (4+60)*8 = 512 = 0x200 字节 loader.bin 的加载地址是 0x900
    ; 故 total_mem_bytes 内存地址是 0xb00 将来在内核种咱们会引用此地址
    total_mem_bytes dd 0
    ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

    ;以下是定义gdt的指针，前2字节是gdt界限，后4字节是gdt起始地址
    gdt_ptr  dw  GDT_LIMIT
                dd  GDT_BASE

    ; 人工对齐：total_mem_bytes4+gdt_ptr6+ards_buf244+ards_nr2，共 256 字节
    ards_buf times 244 db 0
    ards_nr dw 0                ; 用于记录 ARDS 结构体数量

    loader_start:               ; 0x300

    ; int 15h eax = 0000E820h , edx = 534D4150h ('SMAP') 获取内存布局

    xor ebx, ebx                ; 第一次调用时，ebx 值要为 0
    mov edx, 0x534d4150         ; edx 只赋值一次，在循环体中不会改变
    mov di, ards_buf            ; ards 结构缓冲区
.e820_mem_get_loop:
    mov eax, 0x0000e820         ; 执行 int 0x15 后，eax 值变为 0x534d4150，所以每次执行 int 前都要更新位子功能号
    mov ecx, 20                 ; ARDS 地址范围描述符结构大小是 20 字节
    int 0x15
    jc .e820_failed_so_try_e801 ; 若 cf 位为 1 则有错误发生，尝试 0xe801 子功能
    add di, cx                  ; 使 di 增加 20 字节指向缓冲区的新的 ARDS 结构位置
    inc word [ards_nr]        ; 记录 ARDS 数量
    cmp ebx, 0                  ; 若 ebx 为 0 且 cf 不为 1，说明 ards 全部返回
    jnz .e820_mem_get_loop

    ; 在所有 ards 结构中，找出(base_add_low + length_low)的最大值，即内存的容量
    mov cx, [ards_nr]         ; 遍历每一个 ARDS 结构体，循环次数是 ARDS 的数量
    mov ebx, ards_buf
    xor edx, edx                ; edx 为最大的内存容量，在此先清 0
.find_max_mem_area:             ; 无需判断 type 是否为 1,最大的内存块一定是可被使用的
    mov eax, [ebx]              ; base_add_low
    add eax, [ebx+8]            ; length_low
    add ebx, 20                 ; 指向缓冲区中下一个 ARDS 结构
    cmp edx, eax                ; 冒泡排序，找出最大，edx 寄存器始终是最大的内存容量
    jge .next_ards
    mov edx, eax                ; edx为总内存大小
.next_ards:
    loop .find_max_mem_area
    jmp .mem_get_ok

; ------   int 15h ax = E801h 获取内存大小，最大支持 4G   -------
; 返回后，ax cx 值一样，以 KB 为单位，bx dx 值一样，以 64KB 为单位
; 在 ax 和 cx 寄存器中为低 16MB，在 bx 和 dx 寄存器中为 16MB 到 4GB
.e820_failed_so_try_e801:
    mov ax, 0xe801
    int 0x15
    jc .e801_failed_so_try88    ; 若当前 e801 方法失败，就尝试 0x88 方法

    ; 1 先算出低 15MB 的内存  ax 和 cx 中是以 KB 为单位的内存数量，将其转换为以 byte 为单位
    mov cx, 0x400               ; cx 和 ax 值一样，cx 用作乘数
    mul cx
    shl edx, 16
    and eax, 0x0000FFFF
    or edx, eax
    add edx, 0x100000           ; ax 只是 15MB，故要加 1MB
    mov esi, edx                ; 先把低 15MB 的内存容量存入 esi 寄存器备份

    ; 2 再将 16MB 以上的内存转换为 byte 为单位，寄存器 bx 和 dx 中是以 64KB 为单位的内存数量
    xor eax, eax
    mov ax, bx
    mov ecx, 0x10000            ; 0x10000 十进制为 64KB
    mul ecx                     ; 32 位乘法，默认的被乘数是 eax，积为 64 位，高 32 位存入 edx，低 32 位存入 eax
    add esi, eax                ; 由于此方法只能测出 4GB 以内的内存，故 32 位 eax 足够了，edx 肯定为 0,只加 eax 便可
    mov edx, esi                ; edx 为总内存大小
    jmp .mem_get_ok

;-----  int 15h ah = 0x88 获取内存大小，只能获取 64MB 之内  ------
.e801_failed_so_try88:
    ; int 15 后，ax 存入的是以 KB 为单位的内存容量
    mov ah, 0x88
    int 0x15
    jc .error_halt
    and eax, 0x0000FFFF

    ; 16 位乘法，被乘数是 ax，积为 32 位。积的高 16 位在 dx 中，积的低 16 位在 ax 中
    mov cx, 0x400               ; 0x400 等于 1024，将 ax 中的内存容量换为以 byte 为单位
    mul cx
    shl edx, 16                 ; 把 dx 移到高 16 位
    or edx, eax                 ; 把积的低 16 位组合到 edx，为 32 位的积
    add edx, 0x100000           ; 0x88 子功能只会返回 1MB 以上的内存，故实际内存大小要加上 1MB

.mem_get_ok:
    mov [total_mem_bytes], edx  ; 将内存换为 byte 单位后存入 total_mem_bytes 处


;-----------------   准备进入保护模式   -------------------
;1 打开A20
;2 加载gdt
;3 将cr0的pe位置1

    ;-----------------  打开A20  ----------------
    in al,0x92
    or al,0000_0010B
    out 0x92,al

    ;-----------------  加载GDT  ----------------
    lgdt [gdt_ptr]

    ;-----------------  cr0第0位置1  ----------------
    mov eax, cr0
    or eax, 0x00000001
    mov cr0, eax

    jmp dword SELECTOR_CODE:p_mode_start	     ; 刷新流水线，避免分支预测的影响,这种cpu优化策略，最怕jmp跳转，
                                        ; 这将导致之前做的预测失效，从而起到了刷新的作用。
.error_halt:                            ; 出错则挂起
    hlt

[bits 32]
p_mode_start:
    mov ax, SELECTOR_DATA
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov esp,LOADER_STACK_TOP
    mov ax, SELECTOR_VIDEO
    mov gs, ax

    mov byte [gs:160], 'P'

    jmp $