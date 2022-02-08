#ifndef __FS_INODE_H
#define __FS_INODE_H
#include "../lib/stdint.h"
#include "../lib/kernel/list.h"
#include "../device/ide.h"

/* inode 结构 */
struct inode {
    uint32_t i_no;      // inode 编号

    /* 当此 inode 是文件时，i_size 是指文件大小，
     * 若此 inode 是目录，i_size 是指该目录下所有目录项大小之和 */
    uint32_t i_size;

    uint32_t i_open_cnts;   // 记录此文件被打开的次数
    bool write_deny;        // 写文件不能并行，进程写文件前检查此标识

    /* i_sectors[0-11] 是直接块，i_sectors[12] 用来存储一级间接块指针 */
    uint32_t i_sectors[13];
    struct list_elem inode_tag;
};

struct inode* inode_open(struct partition* part, uint32_t inode_no);
void inode_sync(struct partition* part, struct inode* inode, void* io_buf);
void inode_init(uint32_t inode_no, struct inode* new_inode);
void inode_close(struct inode* inode);
void inode_release(struct partition* part, uint32_t inode_no);
#endif