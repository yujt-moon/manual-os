#include "ide.h"
#include "../thread/sync.h"
#include "../lib/kernel/io.h"
#include "../lib/stdio.h"
#include "../lib/kernel/stdio-kernel.h"
#include "../kernel/interrupt.h"
#include "../kernel/memory.h"
#include "../kernel/debug.h"
#include "../lib/string.h"
#include "../device/timer.h"

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

/* 选择读写的硬盘 */
static void select_disk(struct disk* hd) {
    uint8_t reg_device = BIT_DEV_MBS | BIT_DEV_LBA;
    if (hd->dev_no == 1) {      // 若是从盘就置 DEV 位为 1
        reg_device |= BIT_DEV_DEV;
    }
    outb(reg_dev(hd->my_channel), reg_device);
}

/* 向硬盘控制器写入起始扇区地址及要读写的扇区数 */
static void select_sector(struct disk* hd, uint32_t lba, uint8_t sec_cnt) {
    ASSERT(lba <= max_lba);
    struct ide_channel* channel = hd->my_channel;

    /* 写入要读写的扇区数 */
    outb(reg_sect_cnt(channel), sec_cnt);   // 如果 sec_cnt 为 0,则表示写入 256 个扇区

    /* 写入 lba 地址（即扇区号） */
    outb(reg_lba_l(channel), lba);          // lba 地址的低 8 位，不用单独取出低 8 位，outb 函数中的汇编指令 outb %b0, %w1 只会用 al
    outb(reg_lba_m(channel), lba >> 8); // lba 地址的 8 ~ 15 位
    outb(reg_lba_h(channel), lba >> 16);// lba 地址的 16 ~ 23 位

    /* 因为 lba 地址的 24~27 位要存储在 device 寄存器的 0 ~ 3 位，
     * 无法单独写入这 4 位，所以在此处把 device 寄存器再重新写入一次 */
    outb(reg_dev(channel), BIT_DEV_MBS | BIT_DEV_LBA | (hd->dev_no == 1 ? BIT_DEV_DEV : 0) | lba >> 24);
}

/* 向通道 channel 发命令 cmd */
static void cmd_out(struct ide_channel* channel, uint8_t cmd) {
    /* 只要向硬盘发出命令便将此标记置为 true，硬盘中断处理程序需要根据它来判断 */
    channel->expecting_intr = true;
    outb(reg_cmd(channel), cmd);
}

/* 硬盘读入 sec_cnt 个扇区的数据到 buf */
static void read_from_sector(struct disk* hd, void* buf, uint8_t sec_cnt) {
    uint32_t size_in_byte;
    if (sec_cnt == 0) {
        /* 因为 sec_cnt 是 8 位变量，由主调函数将其赋值时，若为 256 则会将最高位的 1 丢掉变为 0 */
        size_in_byte = 256 * 512;
    } else {
        size_in_byte = sec_cnt * 512;
    }
    insw(reg_data(hd->my_channel), buf, size_in_byte / 2);
}

/* 将 buf 中 sec_cnt 扇区的数据写入硬盘 */
static void write2sector(struct disk* hd, void* buf, uint8_t sec_cnt) {
    uint32_t size_in_byte;
    if (sec_cnt == 0) {
        /* 因为 sec_cnt 是 8 位变量，由主调函数将其赋值时，若为 256 则会将最高位的 1 丢掉变为 0 */
        size_in_byte = 256 * 512;
    } else {
        size_in_byte = sec_cnt * 512;
    }
    outsw(reg_data(hd->my_channel), buf, size_in_byte / 2);
}

/* 等待 30 秒 */
static bool busy_wait(struct disk* hd) {
    struct ide_channel* channel = hd->my_channel;
    uint16_t time_limit = 30 * 1000;        // 可以等待 30000 毫秒
    while (time_limit -= 10 >= 0) {
        if (!(inb(reg_status(channel)) & BIT_STAT_BSY)) {
            return (inb(reg_status(channel)) & BIT_STAT_DRQ);
        } else {
            mtime_sleep(10);    // 睡眠 10 毫秒
        }
    }
    return false;
}

/* 从硬盘读取 sec_cnt 个扇区到 buf */
void ide_read(struct disk* hd, uint32_t lba, void* buf, uint32_t sec_cnt) {
    ASSERT(lba <= max_lba);
    ASSERT(sec_cnt > 0);
    lock_acquire(&hd->my_channel->lock);

    /* 1 先选择操作的硬盘 */
    select_disk(hd);

    uint32_t secs_op;       // 每次操作的扇区数
    uint32_t secs_done = 0; // 已完成的扇区数
    while (secs_done < sec_cnt) {
        if ((secs_done + 256) <= sec_cnt) {
            secs_op = 256;
        } else {
            secs_op = sec_cnt - secs_done;
        }

        /* 2 写入待读入的扇区数和起始扇区号 */
        select_sector(hd, lba + secs_done, secs_op);

        /* 3 执行的命令写入 reg_cmd 寄存器 */
        cmd_out(hd->my_channel, CMD_READ_SECTOR);   // 准备开始读数据

        /*********************   阻塞自己的时机  ***********************
        在硬盘已经开始工作(开始在内部读数据或写数据)后才能阻塞自己,现在硬盘已经开始忙了,
        将自己阻塞,等待硬盘完成读操作后通过中断处理程序唤醒自己*/
        sema_down(&hd->my_channel->disk_done);
        /************************************************************/

        /* 4 检测硬盘状态是否可读 */
        /* 醒来后开始执行下面代码 */
        if (!busy_wait(hd)) {   // 若失败
            char error[64];
            sprintf(error, "%s read sector %d failed!!!!!\n", hd->name, lba);
            PANIC(error);
        }

        /* 5 把数据从硬盘的缓冲区读出 */
        read_from_sector(hd, (void*)((uint32_t)buf + secs_done * 512), secs_op);
        secs_done += secs_op;
    }
    lock_release(&hd->my_channel->lock);
}

/* 将 buf 中 sec_cnt 扇区数据写入硬盘 */
void ide_write(struct disk* hd, uint32_t lba, void* buf, uint32_t sec_cnt) {
    ASSERT(lba <= max_lba);
    ASSERT(sec_cnt > 0);
    lock_acquire(&hd->my_channel->lock);

    /* 1 先选择操作的硬盘 */
    select_disk(hd);

    uint32_t secs_op;       // 每次操作的扇区数
    uint32_t secs_done = 0; // 已完成的扇区数
    while (secs_done < sec_cnt) {
        if ((secs_done + 256) <= sec_cnt) {
            secs_op = 256;
        } else {
            secs_op = sec_cnt - secs_done;
        }

        /* 2 写入待写入的扇区数和起始扇区号 */
        select_sector(hd, lba + secs_done, secs_op);

        /* 3 执行的命令写入 reg_cmd 寄存器 */
        cmd_out(hd->my_channel, CMD_WRITE_SECTOR);  // 准备开始写数据

        /* 4 检测硬盘的状态是否可读 */
        if (!busy_wait(hd)) {       // 若失败
            char error[64];
            sprintf(error, "%s write sector %d failed!!!!!!\n", hd->name, lba);
            PANIC(error);
        }

        /* 5 将数据写入硬盘 */
        write2sector(hd, (void*)((uint32_t)buf + secs_done * 512), secs_op);

        /* 在硬盘响应期间阻塞自己 */
        sema_down(&hd->my_channel->disk_done);
        secs_done += secs_op;
    }
    /* 醒来后开始释放锁 */
    lock_release(&hd->my_channel->lock);
}

/* 硬盘中断处理程序 */
void intr_hd_handler(uint8_t irq_no) {
    ASSERT(irq_no == 0x2e || irq_no == 0x2f);
    uint8_t ch_no = irq_no - 0x2e;
    struct ide_channel* channel = &channels[ch_no];
    ASSERT(channel->irq_no == irq_no);
    /* 不必担心此中断是否对应的是这一次的 expecting_intr,
     * 每次读写硬盘时都会申请锁，从而保证了同步一致性 */
    if (channel -> expecting_intr) {
        channel->expecting_intr = false;
        sema_up(&channel->disk_done);

        /* 读取状态寄存器使硬盘控制器认为此次的中断已被处理，从而硬盘可以继续执行新的读写 */
        inb(reg_status(channel));
    }
}

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

        register_handler(channel->irq_no, intr_hd_handler);
        channel_no++;       // 下一个 channel
    }
    printk("ide_init done\n");
}