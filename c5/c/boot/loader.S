    %include "boot.inc"
    section loader vstart=LOADER_BASE_ADDR
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

loader_start:               ; 0x300 + LOADER_BASE_ADDR = 0xc00

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
    mov ax, 0x88
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
    in al, 0x92
    or al, 0000_0010B
    out 0x92, al

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

;-----------------------------  加载kernel  ---------------------------------
    mov eax, KERNEL_START_SECTOR        ; kernel.bin 所在扇区号
    mov ebx, KERNEL_BIN_BASE_ADDR       ; 从磁盘读出后，写入到 ebx 指定的地址
    mov ecx, 200                        ; 读入扇区数

    call rd_disk_m_32

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

;;;;;;;;;;;;;;;;;;;;;;;;;;;;  此时不刷新流水线也没问题  ;;;;;;;;;;;;;;;;;;;;;;;;
;由于一直处在32位下,原则上不需要强制刷新,经过实际测试没有以下这两句也没问题.
;但以防万一，还是加上啦，免得将来出来莫名奇妙的问题.
    jmp SELECTOR_CODE:enter_kernel	  ;强制刷新流水线,更新gdt
enter_kernel:
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
    call kernel_init
    mov esp, 0xc009f000
    jmp KERNEL_ENTRY_POINT          ; 用地址 0x1500 访问测试，结果 ok


;----------------------- 将 kernel.bin 中的 segment 拷贝到编译的地址 --------------------------
kernel_init:
    xor eax, eax
    xor ebx, ebx        ; ebx 记录程序头表地址
    xor ecx, ecx        ; cx 记录程序头表中的 program header 数量
    xor edx, edx        ; dx 记录 program header 尺寸，即 e_phentsize

    mov dx, [KERNEL_BIN_BASE_ADDR + 42]     ; 偏移文件42字节处的属性是 e_phentsize ， 表示 program header 大小
    mov ebx, [KERNEL_BIN_BASE_ADDR + 28]    ; 偏移文件开始部分 28 字节的地方是 e_phoff，表示第1个 program header 在文件中的偏移量
                                            ; 其实该值是 0x34，不过还是谨慎一点，这里来读取实际值
    add ebx, KERNEL_BIN_BASE_ADDR
    mov cx, [KERNEL_BIN_BASE_ADDR + 44]     ; 偏移文件开始部分44字节的地方是 e_phnum，表示有几个 program header
.each_segment:
    cmp byte [ebx + 0], PT_NULL             ; 若 p_type 等于 PT_NULL，说明此 program header 未使用
    je .PTNULL

    ; 为函数 memcpy 压入参数，参数是从右往左依次压入，函数原型类似于 memcpy(dst, src, size)
    push dword [ebx + 16]                   ; program header 中偏移 16 字节的地方是 p_filesz，压入函数的第三个参数:size
    mov eax, [ebx + 4]                      ; 距程序头偏移量为 4 字节的位置是 p_offset
    add eax, KERNEL_BIN_BASE_ADDR           ; 加上 kernel.bin 被加载到的物理地址，eax 为该段的物理地址
    push eax                                ; 压入函数 memcpy 的第二个参数：源地址
    push dword [ebx + 8]                    ; 压入函数 memcpy 的第一个参数：目的地址，偏移程序头 8 字节的位置是 p_vaddr，这就是目的地址
    call mem_cpy                            ; 调用 mem_cpy 完成段复制
    add esp, 12                             ; 清理栈中压入的三个参数
.PTNULL:
    add ebx, edx                            ; edx 为 program header 大小，即 e_phentsize，在此 ebx 指向下一个 program header
    loop .each_segment
    ret

;---------------- 逐字节拷贝 mem_cpy(dst, src, size) ------------------
; 输入：栈中的三个参数（dst, src, size）
; 输出：无
;--------------------------------------------------------------------
mem_cpy:
    cld
    push ebp
    mov ebp, esp
    push ecx                                ; rep 指令用到了 ecx，但 ecx 对于外层段的循环还有用，故先入栈备份
    mov edi, [ebp + 8]                      ; dst
    mov esi, [ebp + 12]                     ; src
    mov ecx, [ebp + 16]                     ; size
    rep movsb                               ; 逐字节拷贝

    ; 恢复环境
    pop ecx
    pop ebp
    ret


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


;----------------------------------------------------------------------------
            ; 功能：读取硬盘 n 个扇区
rd_disk_m_32:
;----------------------------------------------------------------------------
                        ; eax=LBA 扇区号
                        ; ebx=将数据写入的内存地址
                        ; ecx=读入的扇区数
    mov esi, eax    ; 备份 eax
    mov di, cx      ; 备份扇区数到 di
; 读写硬盘：
; 第1步：设置要读取的扇区数
    mov dx, 0x1f2
    mov al, cl
    out dx, al      ; 读取的扇区

    mov eax, esi    ; 恢复 eax

; 第2步：将 LBA 地址存入 0x1f3 ~ 0x1f6

    ; LBA 地址 7 ~ 0 位写入端口 0x1f3
    mov dx, 0x1f3
    out dx, al

    ; LBA 地址 15 ~ 8 位写入端口 0x1f4
    mov cl, 8
    shr eax, cl
    mov dx, 0x1f4
    out dx, al

    ; LBA 地址 23 ~ 16 位写入端口 0x1f5
    shr eax, cl
    mov dx, 0x1f5
    out dx, al

    shr eax, cl
    and al, 0x0f    ; lba 第 24 ~ 27位
    or al, 0xe0     ; 设置 7 ~ 4 位为 1110，表示 lba 模式
    mov dx, 0x1f6
    out dx, al

; 第3步：向 0x1f7 端口写入读命令，0x20
    mov dx, 0x1f7
    mov al, 0x20
    out dx, al

;;;;;;; 至此,硬盘控制器便从指定的lba地址(eax)处,读出连续的cx个扇区,下面检查硬盘状态,不忙就能把这cx个扇区的数据读出来

; 第4步：检测硬盘状态
    .not_ready:         ; 测试 0x1f7 端口（status 寄存器）的 BSY 位
        ; 同一端口，写时表示写入命令字，读时表示读入硬盘状态
        nop
        in al, dx
        and al, 0x88    ; 第4位为1表示硬盘控制器已准备好数据传输，第7位为1表示硬盘忙
        cmp al, 0x08
        jnz .not_ready  ; 若未准备好，继续等。

; 第5步：从 0x1f0 端口读数据
    mov ax, di          ; 以下从硬盘端口读数据用 insw 指令更快捷，不过尽可能多的演示命令使用，
                        ; 在此先用这种方法，在后面内容会用到 insw 和 outsw 等

    mov dx, 256         ; di 为要读取的扇区数，一个扇区有 512 字节，每次读入一个字，共需读取 di*512/2 次，所以 di * 256
    mul dx
    mov cx, ax
    mov dx, 0x1f0
.go_on_read:
    in ax, dx
    mov [ebx], ax
    add ebx, 2
            ; 由于在实模式下偏移地址为16位,所以用bx只会访问到0~FFFFh的偏移。
            ; loader的栈指针为0x900,bx为指向的数据输出缓冲区,且为16位，
            ; 超过0xffff后,bx部分会从0开始,所以当要读取的扇区数过大,待写入的地址超过bx的范围时，
            ; 从硬盘上读出的数据会把0x0000~0xffff的覆盖，
            ; 造成栈被破坏,所以ret返回时,返回地址被破坏了,已经不是之前正确的地址,
            ; 故程序出会错,不知道会跑到哪里去。
            ; 所以改为ebx代替bx指向缓冲区,这样生成的机器码前面会有0x66和0x67来反转。
            ; 0X66用于反转默认的操作数大小! 0X67用于反转默认的寻址方式.
            ; cpu处于16位模式时,会理所当然的认为操作数和寻址都是16位,处于32位模式时,
            ; 也会认为要执行的指令是32位.
            ; 当我们在其中任意模式下用了另外模式的寻址方式或操作数大小(姑且认为16位模式用16位字节操作数，
            ; 32位模式下用32字节的操作数)时,编译器会在指令前帮我们加上0x66或0x67，
            ; 临时改变当前cpu模式到另外的模式下.
            ; 假设当前运行在16位模式,遇到0X66时,操作数大小变为32位.
            ; 假设当前运行在32位模式,遇到0X66时,操作数大小变为16位.
            ; 假设当前运行在16位模式,遇到0X67时,寻址方式变为32位寻址
            ; 假设当前运行在32位模式,遇到0X67时,寻址方式变为16位寻址.
    loop .go_on_read
    ret