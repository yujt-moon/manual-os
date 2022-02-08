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
    ; 故 total_mem_bytes 内存地址是 0xb00 将来在内核中咱们会引用此地址
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
    jc .error_hlt
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
.error_hlt:                            ; 出错则挂起
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

    ; 创建页目录及页表初始化页内存位图
    call setup_page

    ; 要将描述符地址及偏移量写入内存 gdt_ptr，一会儿用新地址重新加载
    sgdt [gdt_ptr]                  ; 存储到原来 gdt 所有的位置

    ; 将 gdt 描述符中视频段描述符中的段基址+0xc0000000
    mov ebx, [gdt_ptr + 2]
    or dword [ebx + 0x18 + 4], 0xc0000000   ; 视频段是第 3 个段描述符，每个描述符是 8 字节，故 0x18
    ; 段描述符的高 4 字节的最高位是段基址的第 31 ~ 24 位

    ; 将 gdt 的基址加上 0xc0000000 使其成为内核所在的高地址
    add dword [gdt_ptr + 2], 0xc0000000

    add esp, 0xc0000000                     ; 将栈指针同样映射到内核地址

    ; 把页目录地址赋予给 cr3
    mov eax, PAGE_DIR_TABLE_POS
    mov cr3, eax

    ; 打开 cr0 的 pg 位（第 31 位）
    mov eax, cr0
    or eax, 0x80000000
    mov cr0, eax

    ; 在开启分页后，用 gdt 新的地址重新加载
    lgdt [gdt_ptr]              ; 重新加载

    mov byte [gs:160], 'V'      ; 视频段段基址已经被更新，用字符 v 表示 virtual addr

    jmp $

;------------  创建页目录及页表   ---------------
setup_page:
; 先把页目录占用的空间逐字清 0
    mov ecx, 4096
    mov esi, 0
.clear_page_dir:
    mov byte [PAGE_DIR_TABLE_POS + esi], 0
    inc esi
    loop .clear_page_dir

; 开始创建页目录项（PDE）
.create_pde:                ; 创建 Page Directory Entry
    mov eax, PAGE_DIR_TABLE_POS
    add eax, 0x1000         ; 此时 eax 为第一个页表的位置及属性
    mov ebx, eax            ; 此处为 ebx 赋值，是为 .create_pte 做准备，ebx 为基址

; 下面将页目录项 0 和 0xc00 都存为第一个页表的地址，每个页表表示 4MB 内存
; 这样 0xc03fffff 以下的地址和 0x003fffff 以下的地址都指向相同的页表
; 这是为将地址映射为内核地址做准备
    or eax, PG_US_U | PG_RW_W | PG_P    ; 页目录项的属性 RW 和 P 位为 1，US 为 1，表示用户属性，所有特权级都可以访问
    mov [PAGE_DIR_TABLE_POS + 0x0], eax ; 第 1 个目录项，在页目录表中的第 1 个目录项写入第一个页表的位置（0x101000）及属性（7）
    mov [PAGE_DIR_TABLE_POS + 0xc00], eax   ; 一个页表项占用 4 字节，0xc00 表示第 768 个页表占用的目录项，0xc00 以上的目录用于内核空间
    ; 也就是页表的 0xc0000000 ~ 0xffffffff 共计 1G 属于内核，0x0 ~ 0xbfffffff 共计 3G 属于用户进程
    sub eax, 0x1000
    mov [PAGE_DIR_TABLE_POS + 4092], eax    ; 使最后一个目录项指向页目录表自己的地址

; 下面创建页表项（PTE）
    mov ecx, 256                        ; 1M 低端内存 / 每页大小 4k = 256
    mov esi, 0
    mov edx, PG_US_U | PG_RW_W | PG_P   ; 属性为 7，US=1,RW=1,P=1
.create_pte:                            ; 创建 Page Table Entry
    mov [ebx+esi*4], edx                ; 此时的 ebx 已经在上面通过 eax 赋值为 0x101000，也就是第一个页表的地址
    add edx, 4096
    inc esi
    loop .create_pte

; 创建内核其他页表的 PDE
    mov eax, PAGE_DIR_TABLE_POS
    add eax, 0x2000                     ; 此时 eax 为第二个页表的位置
    or eax, PG_US_U | PG_RW_W | PG_P    ; 页目录项的属性 US、RW 和 P 位都为 1
    mov ebx, PAGE_DIR_TABLE_POS
    mov ecx, 254                        ; 范围为第 769 ~ 1022 的所有目录项数量
    mov esi, 769
.create_kernel_pde:
    mov [ebx+esi*4], eax
    inc esi
    add eax, 0x1000
    loop .create_kernel_pde
    ret

