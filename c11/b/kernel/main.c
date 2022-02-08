#include "../lib/kernel/print.h"
#include "init.h"
#include "../thread/thread.h"
#include "../kernel/interrupt.h"
#include "../device/console.h"
#include "../userprog/process.h"

void k_thread_a(void*);
void k_thread_b(void*);
void u_prog_a(void);
void u_prog_b(void);
int test_var_a = 0, test_var_b = 0;

int main(void) {
    put_str("I am kernel\n");
    init_all();

    thread_start("k_thread_a", 31, k_thread_a, "argA ");
    thread_start("k_thread_b", 31, k_thread_b, "argB ");
    process_execute(u_prog_a, "user_prog_a");
    process_execute(u_prog_b, "user_prog_b");

    intr_enable();      // 打开中断，使时钟中断起作用
    while (1);
    return 0;
}

/* 在线程中运行的函数 */
void k_thread_a(void* arg) {
    /* 用 void* 来通用表示参数，被调用的函数知道自己需要什么类型的参数，自己转换再用 */
    char* para = arg;
    while (1) {
        console_put_str(" v_a:0x");
        console_put_int(test_var_a);
    }
}

/* 在线程中运行的函数 */
void k_thread_b(void* arg) {
    /* 被调用的函数知道自己需要什么类型的参数，自己转换再使用 */
    char* para = arg;
    while (1) {
        console_put_str(" v_b:0x");
        console_put_int(test_var_b);
    }
}

/* 测试用户进程 */
void u_prog_a(void) {
    while (1) {
        test_var_a++;
    }
}

/* 测试用户进程 */
void u_prog_b(void) {
    while (1) {
        test_var_b++;
    }
}