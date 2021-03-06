#include "../lib/kernel/print.h"
#include "init.h"
#include "../thread/thread.h"
#include "../kernel/interrupt.h"
#include "../device/console.h"
#include "../userprog/process.h"
#include "../userprog/syscall-init.h"
#include "../lib/user/syscall.h"
#include "../lib/stdio.h"

void k_thread_a(void*);
void k_thread_b(void*);
void u_prog_a(void);
void u_prog_b(void);
int prog_a_pid = 0, prog_b_pid = 0;

int main(void) {
    put_str("I am kernel\n");
    init_all();

    process_execute(u_prog_a, "user_prog_a");
    process_execute(u_prog_b, "user_prog_b");

    intr_enable();      // 打开中断，使时钟中断起作用
    console_put_str(" I am main, my pid:0x");
    console_put_int(sys_getpid());
    console_put_char('\n');
    thread_start("k_thread_a", 31, k_thread_a, "I am thread_a");
    thread_start("k_thread_b", 31, k_thread_b, "I am thread_b");
    while (1);
    return 0;
}

/* 在线程中运行的函数 */
void k_thread_a(void* arg) {
    /* 用 void* 来通用表示参数，被调用的函数知道自己需要什么类型的参数，自己转换再用 */
    char* para = arg;
    console_put_str(" I am thread_a, my pid:0x");
    console_put_int(sys_getpid());
    console_put_char('\n');
    while (1);
}

/* 在线程中运行的函数 */
void k_thread_b(void* arg) {
    /* 被调用的函数知道自己需要什么类型的参数，自己转换再使用 */
    char* para = arg;
    console_put_str(" I am thread_b, my pid:0x");
    console_put_int(sys_getpid());
    console_put_char('\n');
    while (1);
}

/* 测试用户进程 */
void u_prog_a(void) {
    char* name = "prog_a";
    printf(" I am %s, my pid:0x%d%c", name, getpid(), '\n');
    while (1);
}

/* 测试用户进程 */
void u_prog_b(void) {
    char* name = "prog_b";
    printf(" I am %s, my pid:0x%d%c", name, getpid(), '\n');
    while (1);
}