#include "init.h"
#include "../lib/kernel/print.h"
#include "interrupt.h"
#include "../device/timer.h"        // 用相对路径演示头文件包含
#include "memory.h"

/* 负责初始化所有模块 */
void init_all() {
    put_str("init_all\n");
    idt_init();     // 初始化中断
    timer_init();   // 初始化 PIT
    mem_init();     // 初始化内存池
}