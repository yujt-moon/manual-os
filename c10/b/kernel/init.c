#include "init.h"
#include "../lib/kernel/print.h"
#include "interrupt.h"
#include "../device/timer.h"        // 用相对路径演示头文件包含
#include "memory.h"
#include "../thread/thread.h"
#include "../device/console.h"

/* 负责初始化所有模块 */
void init_all() {
    put_str("init_all\n");
    idt_init();     // 初始化中断
    mem_init();     // 初始化内存池
    thread_init();  // 初始化线程相关结构
    timer_init();   // 初始化 PIT
    console_init(); // 控制台初始化最好放在开中断之前
}