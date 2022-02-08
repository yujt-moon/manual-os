#include "ide.h"
#include "../thread/sync.h"
#include "../lib/stdio.h"
#include "../lib/kernel/stdio-kernel.h"
#include "../kernel/interrupt.h"
#include "../kernel/memory.h"
#include "../kernel/debug.h"
#include "../lib/string.h"

/* 定义硬盘各寄存器的端口号 */
#define reg_data(channel)       (channel->port_base + 0)
#define reg_error(channel)      (channel->port_base + 1)
#define reg_sect_cnt(channel)   (channel->port_base + 2)
#define reg_lba_l(channel)      (channel->port_base + 3)
#define reg_lba_m(channel)      (channel->port_base + 4)
#define reg_lba_h(channel)      (channel->port_base + 5)
#define reg_dev(channel)        (channel->port_base + 6)
#define reg_status(channel)     (channel->port_base + 7)
#define reg_cmd(channel)        (reg_status(channel))
#define reg_alt_status(channel) (channel->port_base + 0x206)
#define reg_ctl(channel)        reg_alt_status(channel)

/* reg_alt_status 寄存器的一些关键位 */
#define BIT_STAT_BSY      0x80          // 硬盘忙
#define BIT_STAT_DRDY     0x40          // 驱动器准备好
#define BIT_STAT_DRQ      0X8           // 数据传输准备好了

/* device 寄存器的一些关键位 */
#define BIT_DEV_MBS     0xa0            // 第 7 位和第 5 位固定为 1
#define BIT_DEV_LBA     0x40
#define BIT_DEV_DEV     0x10

/* 一些硬盘的操作指令 */
#define CMD_IDENTIFY        0xec    // identify 指令
#define CMD_READ_SECTOR     0x20    // 读扇区指令
#define CMD_WRITE_SECTOR    0x30    // 写扇区指令

/* 定义可读写的最大扇区数，调试用 */
#define max_lba ((80*1024*1024/512) - 1)        // 只支持 80 MB 硬盘

uint8_t channel_cnt;        // 按硬盘数计算的通道数
struct ide_channel channels[2];     // 有两个 ide 通道

/* 硬盘数据结构初始化 */
void ide_init() {
    printk("ide_init start\n");
    uint8_t hd_cnt = *((uint8_t*)(0x475));      // 获取硬盘的数量
    ASSERT(hd_cnt > 0);
    channel_cnt = DIV_ROUND_UP(hd_cnt, 2);  // 一个 ide 通道上有两个硬盘，根据硬盘数量反推有几个 ide通道
    struct ide_channel* channel;
    uint8_t channel_no = 0;

    /* 处理每个通道上的硬盘 */
    while (channel_no < channel_cnt) {
        channel = &channels[channel_no];
        sprintf(channel->name, "ide%d", channel_no);

        /* 为每个 ide 通道初始化端口基址及中断向量 */
        switch (channel_no) {
            case 0:
                channel->port_base = 0x1f0;     // ide0 通道的起始端口号是 0x1f0
                channel->irq_no = 0x20 + 14;    // 从片 8259a 上倒数第二的中断引脚，温盘，也就是 ide0 通道的中断向量号
                break;
            case 1:
                channel->port_base = 0x170;     // ide1 通道的起始端口号是 0x170
                channel->irq_no = 0x20 + 15;    // 从 8259A 的最后一个中断引脚，我们用来响应 ide1 通道上的硬盘中断
                break;
        }

        channel->expecting_intr = false;        // 未向硬盘写入指令时不期待硬盘的中断
        lock_init(&channel->lock);

        /* 初始化为 0，目的是向硬盘控制器请求数据后，硬盘驱动 sema_down 此信号会阻塞线程
         * 直到硬盘完成后通过发中断，由中断处理程序将此信号量 sema_up，唤醒线程。 */
        sema_init(&channel->disk_done, 0);
        channel_no++;       // 下一个 channel
    }
    printk("ide_init done\n");
}