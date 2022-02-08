#include "../lib/kernel/print.h"
#include "init.h"
#include "../thread/thread.h"
#include "../kernel/interrupt.h"
#include "../device/console.h"
#include "../userprog/process.h"
#include "../userprog/syscall-init.h"
#include "../lib/user/syscall.h"
#include "../lib/stdio.h"
#include "memory.h"

void k_thread_a(void*);
void k_thread_b(void*);
void u_prog_a(void);
void u_prog_b(void);
int prog_a_pid = 0, prog_b_pid = 0;

int main(void) {
    put_str("I am kernel\n");
    init_all();
    intr_enable();      // 打开中断，使时钟中断起作用
    thread_start("k_thread_a", 31, k_thread_a, "I am thread_a");
    thread_start("k_thread_b", 31, k_thread_b, "I am thread_b");
    while (1);
    return 0;
}

/* 在线程中运行的函数 */
void k_thread_a(void* arg) {
    /* 用 void* 来通用表示参数，被调用的函数知道自己需要什么类型的参数，自己转换再用 */
    char* para = arg;
    void* addr = sys_malloc(33);
    console_put_str(" I am thread_a, sys_malloc(33), addr is 0x");
    console_put_int((int)addr);
    console_put_char('\n');
    while (1);
}

/* 在线程中运行的函数 */
void k_thread_b(void* arg) {
    /* 被调用的函数知道自己需要什么类型的参数，自己转换再使用 */
    char* para = arg;
    void* addr = sys_malloc(63);
    console_put_str(" I am thread_b, sys_malloc(63), addr is 0x");
    console_put_int((int)addr);
    console_put_char('\n');
    while (1);
}