#include "inode.h"
#include "fs.h"
#include "file.h"
#include "../kernel/global.h"
#include "../kernel/debug.h"
#include "../kernel/memory.h"
#include "../kernel/interrupt.h"
#include "../lib/kernel/list.h"
#include "../lib/kernel/stdio-kernel.h"
#include "../lib/string.h"
#include "super_block.h"

/* 用来存储 inode 位置 */
struct inode_position {
    bool two_sec;       // inode 是否跨扇区
    uint32_t sec_lba;   // inode 所在的扇区号
    uint32_t off_size;  // inode 在扇区内的字节偏移
};

/* 获取 inode 所在的扇区和扇区内的偏移量 */
static void inode_locate(struct partition* part, uint32_t inode_no, struct inode_position* inode_pos) {
    /* inode_table 在硬盘上是连续的 */
    ASSERT(inode_no < 4096);
    uint32_t inode_table_lba = part->sb->inode_table_lba;

    uint32_t inode_size = sizeof(struct inode);
    uint32_t off_size = inode_no * inode_size;      // 第 inode_no 号i结点相对于 inode_table_lba 的字节偏移量
    uint32_t off_sec = off_size / 512;              // 第 inode_no 号i结点相对于 inode_table_lba 的扇区偏移量
    uint32_t off_size_in_sec = off_size % 512;      // 待查找的 inode 所在扇区中的起始地址

    /* 判断此i结点是否跨越 2 个扇区 */
    uint32_t left_in_sec = 512 - off_size_in_sec;
    if (left_in_sec < inode_size) {     // 若扇区内剩下的空间不足以容纳一个 inode，必然是i结点跨越了 2 个扇区
        inode_pos->two_sec = true;
    } else {        // 否则，所查找的 inode 未跨扇区
        inode_pos->two_sec = false;
    }
    inode_pos->sec_lba = inode_table_lba + off_sec;
    inode_pos->off_size = off_size_in_sec;
}

/* 将 inode 写入到分区 part */
void inode_sync(struct partition* part, struct inode* inode, void* io_buf) {       // io_buf 是用于硬盘 io 的缓冲区
    uint8_t inode_no = inode->i_no;
    struct inode_position inode_pos;
    inode_locate(part, inode_no, &inode_pos);       // inode 位置信息会存入 inode_pos
    ASSERT(inode_pos.sec_lba <= (part->start_lba + part->sec_cnt));

    /* 硬盘中的 inode 中的成员 inode_tag 和 i_open_cnts 是不需要的，
     * 它们只在内存中记录链表位置和被多少进程共享 */
    struct inode pure_inode;
    memcpy(&pure_inode, inode, sizeof(struct inode));

    /* 以下 inode 的三个成员只存在于内存中，现将 inode 同步到硬盘，清掉这三项即可 */
    pure_inode.i_open_cnts = 0;
    pure_inode.write_deny = false;      // 置为 false，以保证在硬盘中读出时为可写
    pure_inode.inode_tag.prev = pure_inode.inode_tag.next = NULL;

    char* inode_buf = (char*)io_buf;
    if (inode_pos.two_sec) {        // 若是跨了两个扇区，就要读出两个扇区再写入两个扇区
        /* 读写硬盘是以扇区为单位，若写入的数据小于一个扇区，要将原硬盘上的内容先读出来再和新数据拼成一扇区后再写入 */
        ide_read(part->my_disk, inode_pos.sec_lba, inode_buf, 2);   // inode 在 format 中写入硬盘时是连续写入的，所以读入两块扇区

        /* 开始将待写入的 inode 拼入到这 2 个扇区中的相应位置 */
        memcpy((inode_buf + inode_pos.off_size), &pure_inode, sizeof(struct inode));

        /* 将拼接号的数据再写入磁盘 */
        ide_write(part->my_disk, inode_pos.sec_lba, inode_buf, 2);
    } else {    // 若只是一个扇区
        ide_read(part->my_disk, inode_pos.sec_lba, inode_buf, 1);
        memcpy((inode_buf + inode_pos.off_size), &pure_inode, sizeof(struct inode));
        ide_write(part->my_disk, inode_pos.sec_lba, inode_buf, 1);
    }
}

/* 根据i结点 */
struct inode* inode_open(struct partition* part, uint32_t inode_no) {
    /* 先在已打开 inode 链表中找到 inode，此链表是为了提速创建的缓冲区 */
    struct list_elem* elem = part->open_inodes.head.next;
    struct inode* inode_found;
    while (elem != &part->open_inodes.tail) {
        inode_found = elem2entry(struct inode, inode_tag, elem);
        if (inode_found->i_no == inode_no) {
            inode_found->i_open_cnts++;
            return inode_found;
        }
        elem = elem->next;
    }

    /* 由于 open_inodes 链表中找不到，下面从硬盘上读入此 inode 并加入到此链表 */
    struct inode_position inode_pos;

    /* inode 位置信息会存入 inode_pos，包括 inode 所在扇区地址和 */
    inode_locate(part, inode_no, &inode_pos);

    /* 为使通过 sys_malloc 创建的新 inode 被所有任务共享，需要将 inode 置于内核空间，故需要临时将 cur_pbc->pgdir 置为 NULL */
    struct task_struct* cur = running_thread();
    uint32_t* cur_pagedir_bak = cur->pgdir;
    cur->pgdir = NULL;
    /* 以上三行代码完成后下面分配的内存将位于内核区 */
    inode_found = (struct inode*)sys_malloc(sizeof(struct inode));
    /* 恢复 pgdir */
    cur->pgdir = cur_pagedir_bak;

    char* inode_buf;
    if (inode_pos.two_sec) {    // 考虑跨扇区的情况
        inode_buf = (char*)sys_malloc(1024);

        /* i结点表是被 partition_format 函数连续写入扇区的，所以下面可以连续读出来 */
        ide_read(part->my_disk, inode_pos.sec_lba, inode_buf, 2);
    } else {    // 否则，所查找的 inode 未跨扇区，一个扇区大小的缓冲区足够
        inode_buf = (char*)sys_malloc(512);
        ide_read(part->my_disk, inode_pos.sec_lba, inode_buf, 1);
    }
    memcpy(inode_found, inode_buf + inode_pos.off_size, sizeof(struct inode));

    /* 因为一会很可能要用到此 inode，故将其插入到队首便于提前检索到 */
    list_push(&part->open_inodes, &inode_found->inode_tag);
    inode_found->i_open_cnts = 1;

    sys_free(inode_buf);
    return inode_found;
}

/* 关闭 inode 或减少 inode 的打开数 */
void inode_close(struct inode* inode) {
    /* 若没有进程再打开此文件，将此 inode 去掉并释放空间 */
    enum intr_status old_status = intr_disable();
    if (--inode->i_open_cnts == 0) {
        list_remove(&inode->inode_tag);     // 将i结点从 part->open_inodes 中去掉
        /* inode_open 时为实现 inode 被所有进程共享，
         * 已经在 sys_malloc 为 inode 分配了内核空间，
         * 释放 inode 时也要确保释放的是内核内存池 */
        struct task_struct* cur = running_thread();
        uint32_t* cur_pagedir_bak = cur->pgdir;
        cur->pgdir = NULL;
        sys_free(inode);
        cur->pgdir = cur_pagedir_bak;
    }
    intr_set_status(old_status);
}

/* 初始化 new_inode */
void inode_init(uint32_t inode_no, struct inode* new_inode) {
    new_inode->i_no = inode_no;
    new_inode->i_size = 0;
    new_inode->i_open_cnts = 0;
    new_inode->write_deny = false;

    /* 初始化块索引数组 i_sector */
    uint8_t sec_idx = 0;
    while (sec_idx < 13) {
        /* i_sectors[12] 为一级间接块地址 */
        new_inode->i_sectors[sec_idx] = 0;
        sec_idx++;
    }
}