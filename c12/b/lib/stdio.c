#include "stdio.h"
#include "../kernel/interrupt.h"
#include "../kernel/global.h"
#include "string.h"
#include "user/syscall.h"
#include "kernel/print.h"

#define va_start(ap, v) ap = (va_list)&v        // 把 ap 指向第一个固定参数 v
#define va_arg(ap, t) *((t*)(ap += 4))          // ap 指向下一个参数并返回其值
#define va_end(ap) ap = NULL                    // 清除 ap

/* 将整数转换成字符（integer to ascii） */
static void itoa(uint32_t value, char** buf_ptr_addr, uint8_t base) {
    uint32_t m = value % base;          // 求模，最先掉下来的是最低位
    uint32_t i = value / base;          // 求整
    if (i) {                            // 如果倍数不为0,则递归调用
        itoa(i, buf_ptr_addr, base);
    }
    if (m < 10) {       // 如果余数是 0 ~ 9
        *((*buf_ptr_addr)++) = m + '0';     // 将数字 0~9 转换为字符 '0'~'9'
    } else {        // 否则余数是 A~F
        *((*buf_ptr_addr)++) = m - 10 + 'A';    // 将数字 A~F 转换为字符 'A'~'F'
    }
}

/* 将参数 ap 按照格式 format 输出到字符串 str，并返回替换后 str 长度 */
uint32_t vsprintf(char* str, const char* format, va_list ap) {
    char* buf_ptr = str;
    const char* index_ptr = format;
    char index_char = *index_ptr;
    int32_t arg_int;
    while (index_char) {
        if (index_char != '%') {
            *(buf_ptr++) = index_char;
            index_char = *(++index_ptr);
            continue;
        }
        index_char = *(++index_ptr);        // 得到%后面的字符
        switch (index_char) {
            case 'x':
                arg_int = va_arg(ap, int);
                itoa(arg_int, &buf_ptr, 16);
                index_char = *(++index_ptr);    // 跳过格式字符串并更新 index_char
                break;
        }
    }
    return strlen(str);
}

/* 格式化输出字符串 format */
uint32_t printf(const char* format, ...) {
    va_list args;
    va_start(args, format);         // 使 args 指向 format
    char buf[1024] = {0};           // 用于存储拼接后的字符串
    vsprintf(buf, format, args);
    va_end(args);
    return write(buf);
}