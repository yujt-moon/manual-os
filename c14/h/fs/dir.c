#include "dir.h"
#include "../lib/stdint.h"
#include "inode.h"
#include "file.h"
#include "fs.h"
#include "../lib/kernel/stdio-kernel.h"
#include "../kernel/global.h"
#include "../kernel/debug.h"
#include "../kernel/memory.h"
#include "../lib/string.h"
#include "../kernel/interrupt.h"
#include "super_block.h"

struct dir root_dir;        // 根目录

/* 打开根目录 */
void open_root_dir(struct partition* part) {
    root_dir.inode = inode_open(part, part->sb->root_inode_no);
    root_dir.dir_pos = 0;
}

/* 在分区 part 上打开i结点为 inode_no 的目录并返回目录指针 */
struct dir* dir_open(struct partition* part, uint32_t inode_no) {
    struct dir* pdir = (struct dir*)sys_malloc(sizeof(struct dir));
    pdir->inode = inode_open(part, inode_no);
    pdir->dir_pos = 0;
    return pdir;
}

/* 在 part 分区内的 pdir 目录内寻找名为 name 的文件或目录，
 * 找到后返回 true 并将其目录项存入 dir_e，否则返回 false */
bool search_dir_entry(struct partition* part, struct dir* pdir, \
        const char* name, struct dir_entry* dir_e) {
    uint32_t block_cnt = 140;       // 12 个直接块 + 128 个一级间接块 = 140 块

    /* 12 个直接块大小 + 128 个间接块，共 560 字节 */
    uint32_t* all_blocks = (uint32_t*)sys_malloc(48 + 512);
    if (all_blocks == NULL) {
        printk("search_dir_entry: sys_malloc for all blocks failed");
        return false;
    }

    uint32_t block_idx = 0;
    while (block_idx < 12) {
        all_blocks[block_idx] = pdir->inode->i_sectors[block_idx];
        block_idx++;
    }
    block_idx = 0;

    if (pdir->inode->i_sectors[12] != 0) {      // 若含有一级间接块表
        ide_read(part->my_disk, pdir->inode->i_sectors[12], all_blocks + 12, 1);
    }
    /* 至此，all_blocks 存储的是该文件或目录的所有扇区地址 */

    /* 写目录项的时候已保证不跨扇区，
     * 这样读目录项时容易处理，只申请容纳 1 个扇区的内存*/
    uint8_t* buf = (uint8_t*)sys_malloc(SECTOR_SIZE);
    struct dir_entry* p_de = (struct dir_entry*)buf;        // p_de 指向目录项指针，值为 buf 的起始地址
    uint32_t dir_entry_size = part->sb->dir_entry_size;
    uint32_t dir_entry_cnt = SECTOR_SIZE / dir_entry_size;  // 1 扇区内可容纳的目录项的个数

    /* 开始在所有块中查找目录项 */
    while (block_idx < block_cnt) {
        /* 块地址为 0 时，表示该块中无数据，继续在其他块中找 */
        if (all_blocks[block_idx] == 0) {
            block_idx++;
            continue;
        }
        ide_read(part->my_disk, all_blocks[block_idx], buf, 1);

        uint32_t dir_entry_idx = 0;
        /* 遍历扇区中所有目录项 */
        while (dir_entry_idx < dir_entry_cnt) {
            /* 若找到了，就直接复制整个目录项 */
            if (!strcmp(p_de->filename, name)) {
                memcpy(dir_e, p_de, dir_entry_size);
                sys_free(buf);
                sys_free(all_blocks);
                return true;
            }
            dir_entry_idx++;
            p_de++;
        }
        block_idx++;
        p_de = (struct dir_entry*)buf;      // 此时 p_de 已经指向扇区内最后一个完整目录项了，需要恢复 p_de 指向为 buf
        memset(buf, 0, SECTOR_SIZE);// 将 buf 清 0,下次再用
    }
    sys_free(buf);
    sys_free(all_blocks);
    return false;
}

/* 关闭目录 */
void dir_close(struct dir* dir) {
    /************ 根目录不能关闭 *************
     * 1 根目录自打开后就不应该关闭，否则还需要再次 open_root_dir();
     * 2 root_dir 所在的内存是低端 1M 之内，并非在堆中，free 会出问题 */
    if (dir == &root_dir) {
        /* 不做任何处理直接返回 */
        return;
    }
    inode_close(dir->inode);
    sys_free(dir);
}

/* 在内存中初始化目录项 p_de */
void create_dir_entry(char* filename, uint32_t inode_no, uint8_t file_type, struct dir_entry* p_de) {
    ASSERT(strlen(filename) <= MAX_FILE_NAME_LEN);

    /* 初始化目录项 */
    memcpy(p_de->filename, filename, strlen(filename));
    p_de->i_no = inode_no;
    p_de->f_type = file_type;
}

/* 将目录项 p_de 写入父目录 parent_dir 中，io_buf 由主调函数提供 */
bool sync_dir_entry(struct dir* parent_dir, struct dir_entry* p_de, void* io_buf) {
    struct inode* dir_inode = parent_dir->inode;
    uint32_t dir_size = dir_inode->i_size;
    uint32_t dir_entry_size = cur_part->sb->dir_entry_size;

    ASSERT(dir_size % dir_entry_size == 0);     // dir_size 应该是 dir_entry_size 的整数倍

    uint32_t dir_entrys_per_sec = (512 / dir_entry_size);   // 每扇区最大的目录项数
    int32_t block_lba = -1;

    /* 将该目录的所有扇区地址（12 个直接块 + 128 个间接块）存入 all_blocks */
    uint8_t block_idx = 0;
    uint32_t all_blocks[140] = {0};     // all_blocks 保存目录所有的块

    /* 将 12 个直接块存入 all_blocks */
    while (block_idx < 12) {
        all_blocks[block_idx] = dir_inode->i_sectors[block_idx];
        block_idx++;
    }

    struct dir_entry* dir_e = (struct dir_entry*)io_buf;        // dir_e 用来在 io_buf 中遍历目录项
    int32_t block_bitmap_idx = -1;

    /* 开始遍历所有块以寻找目录项空位，若已有扇区中没有空闲位，
     * 在不超过文件大小的情况下申请新扇区来存储新目录项 */
    block_idx = 0;
    while (block_idx < 140) {       // 文件（包括目录）最大支持 12 个直接块 + 128 个间接块 = 140 个块
        block_bitmap_idx = -1;
        if (all_blocks[block_idx] == 0) {   // 在三种情况下分配块
            block_lba = block_bitmap_alloc(cur_part);
            if (block_lba == -1) {
                printk("alloc block bitmap for sync_dir_entry failed\n");
                return false;
            }

            /* 每分配一个块就同步一次 block_bitmap */
            block_bitmap_idx = block_lba - cur_part->sb->data_start_lba;
            ASSERT(block_bitmap_idx != -1);
            bitmap_sync(cur_part, block_bitmap_idx, BLOCK_BITMAP);

            block_bitmap_idx = -1;
            if (block_idx < 12) {       // 若是直接块
                dir_inode->i_sectors[block_idx] = all_blocks[block_idx] = block_lba;
            } else if (block_idx == 12) {   // 若是尚未分配一级直接块表（block_idx 等于 12，表示第 0 个间接块地址为 0）
                dir_inode->i_sectors[12] = block_lba;   // 将上面分配的块作为一级间接块表地址
                block_lba = -1;
                block_lba = block_bitmap_alloc(cur_part);       // 再分配一个作为第 0 个间接块
                if (block_lba == -1) {
                    block_bitmap_idx = dir_inode->i_sectors[12] - cur_part->sb->data_start_lba;
                    bitmap_set(&cur_part->block_bitmap, block_bitmap_idx, 0);
                    dir_inode->i_sectors[12] = 0;
                    printk("alloc block bitmap for sync_dir_entry failed\n");
                    return false;
                }

                /* 每分配一个块就同步一次 block_bitmap */
                block_bitmap_idx = block_lba - cur_part->sb->data_start_lba;
                ASSERT(block_bitmap_idx != -1);
                bitmap_sync(cur_part, block_bitmap_idx, BLOCK_BITMAP);

                all_blocks[12] = block_lba;
                /* 把新分配的第 0 个间接块地址写入一级间接块表 */
                ide_write(cur_part->my_disk, dir_inode->i_sectors[12], all_blocks + 12, 1);
            } else {        // 若是间接块未分配
                all_blocks[block_idx] = block_lba;
                /* 把新分配的第（block_idx - 12）个间接块地址写入一级间接块表 */
                ide_write(cur_part->my_disk, dir_inode->i_sectors[12], all_blocks + 12, 1);
            }

            /* 再将新目录项 p_de 写入新分配的间接块 */
            memset(io_buf, 0, 512);
            memcpy(io_buf, p_de, dir_entry_size);
            ide_write(cur_part->my_disk, all_blocks[block_idx], io_buf, 1);
            dir_inode->i_size += dir_entry_size;
            return true;
        }

        /* 若第 block_idx 块已存在，将其读进内存，然后在该块中查找空目录项 */
        ide_read(cur_part->my_disk, all_blocks[block_idx], io_buf, 1);
        /* 在扇区内查找空目录项 */
        uint8_t dir_entry_idx = 0;
        while (dir_entry_idx < dir_entrys_per_sec) {
            if ((dir_e + dir_entry_idx)->f_type == FT_UNKNOWN) {        // FT_UNKNOWN 为 0，无论是初始化或是删除文件后，都会将 f_type 置为 FT_UNKNOWN
                memcpy(dir_e + dir_entry_idx, p_de, dir_entry_size);
                ide_write(cur_part->my_disk, all_blocks[block_idx], io_buf, 1);

                dir_inode->i_size += dir_entry_size;
                return true;
            }
            dir_entry_idx++;
        }
        block_idx++;
    }
    printk("directory is full!\n");
    return false;
}

/* 把分区 part 目录 pdir 中编号为 inode_no 的目录项删除 */
bool delete_dir_entry(struct partition* part, struct dir* pdir, uint32_t inode_no, void* io_buf) {
    struct inode* dir_inode = pdir->inode;
    uint32_t block_idx = 0, all_blocks[140] = {0};
    /* 收集目录全部块地址 */
    while (block_idx < 12) {
        all_blocks[block_idx] = dir_inode->i_sectors[block_idx];
        block_idx++;
    }
    if (dir_inode->i_sectors[12]) {
        ide_read(part->my_disk, dir_inode->i_sectors[12], all_blocks + 12, 1);
    }

    /* 目录项在存储时保证不会跨扇区 */
    uint32_t dir_entry_size = part->sb->dir_entry_size;
    uint32_t dir_entries_per_sec = (SECTOR_SIZE / dir_entry_size);      // 每扇区最大的目录项数目
    struct dir_entry* dir_e = (struct dir_entry*)io_buf;
    struct dir_entry* dir_entry_found = NULL;
    uint8_t dir_entry_idx, dir_entry_cnt;
    bool is_dir_first_block = false;        // 目录的第一个块

    /* 遍历所有块，寻找目录项 */
    block_idx = 0;
    while (block_idx < 140) {
        is_dir_first_block = false;
        if (all_blocks[block_idx] == 0) {
            block_idx++;
            continue;
        }
        dir_entry_idx = dir_entry_cnt = 0;
        memset(io_buf, 0, SECTOR_SIZE);
        /* 读取扇区，获得目录项 */
        ide_read(part->my_disk, all_blocks[block_idx], io_buf, 1);

        /* 遍历所有的目录项，统计该扇区的目录项数量及是否有待删除的目录项 */
        while (dir_entry_idx < dir_entries_per_sec) {
            if ((dir_e + dir_entry_idx)->f_type != FT_UNKNOWN) {
                if (!strcmp((dir_e + dir_entry_idx)->filename, ".")) {
                    is_dir_first_block = true;
                } else if (strcmp((dir_e + dir_entry_idx)->filename, ".") &&
                    strcmp((dir_e + dir_entry_idx)->filename, "..")) {
                    dir_entry_cnt++;        // 统计此扇区内的目录项个数
                    if ((dir_e + dir_entry_idx)->i_no == inode_no) {    // 如果找到此i结点，就将其记录在 dir_entry_found
                        ASSERT(dir_entry_found == NULL);    // 确保目录中只有一个编号为 inode_no 的 inode，找到一次后 dir_entry_found 就不在是 NULL
                        dir_entry_found = dir_e + dir_entry_idx;
                        /* 找到后也继续遍历，统计总共的目录项数 */
                    }
                }
            }
            dir_entry_idx++;
        }

        /* 若此扇区未找到该目录项，继续在下个扇区中找 */
        if (dir_entry_found == NULL) {
            block_idx++;
            continue;
        }

        /* 在此扇区中找到目录项后，清除该目录项并判断是否回收扇区，随后退出循环直接返回 */
        ASSERT(dir_entry_cnt >= 1);
        /* 除目录第1个扇区外，若该扇区上只有该目录项自己，则将整个扇区回收 */
        if (dir_entry_cnt == 1 && !is_dir_first_block) {
            /* a 在块位图中回收该块 */
            uint32_t block_bitmap_idx = all_blocks[block_idx] - part->sb->data_start_lba;
            bitmap_set(&part->block_bitmap, block_bitmap_idx, 0);
            bitmap_sync(cur_part, block_bitmap_idx, BLOCK_BITMAP);

            /* b 将块地址从数组 i_sectors 或索引表中去掉 */
            if (block_idx < 12) {
                dir_inode->i_sectors[block_idx] = 0;
            } else {    // 在一级间接索引表中擦除该间接块地址
                /* 先判断一级间接索引表中间块的数量，如果仅有这1个间接块，连同间接索引表所在的块一通同回收 */
                uint32_t indirect_blocks = 0;
                uint32_t indirect_block_idx = 12;
                while (indirect_block_idx < 140) {  // TODO
                    if (all_blocks[indirect_block_idx] != 0) {
                        indirect_blocks++;
                    }
                }
                ASSERT(indirect_blocks >= 1);   // 包括当前间接块

                if (indirect_blocks > 1) {      // 间接索引表中还包括其他间接块，仅在索引表中擦除当前这个间接块地址
                    all_blocks[block_idx] = 0;
                    ide_write(part->my_disk, dir_inode->i_sectors[12], all_blocks + 12, 1);
                } else {    // 间接索引表中就当前这1个间接块，直接把间接索引表所在的块回收，然后擦除间接索引表块地址
                    /* 回收间接索引表所在的块 */
                    block_bitmap_idx = dir_inode->i_sectors[12] - part->sb->data_start_lba;
                    bitmap_set(&part->block_bitmap, block_bitmap_idx, 0);
                    bitmap_sync(cur_part, block_bitmap_idx, BLOCK_BITMAP);

                    /* 将间接索引表地址清 0 */
                    dir_inode->i_sectors[12] = 0;
                }
            }
        } else {    // 仅将该目录项清空
            memset(dir_entry_found, 0, dir_entry_size);
            ide_write(part->my_disk, all_blocks[block_idx], io_buf, 1);
        }

        /* 更新i结点信息并同步到硬盘 */
        ASSERT(dir_inode->i_size >= dir_entry_size);
        dir_inode->i_size -= dir_entry_size;
        memset(io_buf, 0, SECTOR_SIZE * 2);
        inode_sync(part, dir_inode, io_buf);

        return true;
    }
    /* 所有块中未能找到则返回 false，若出现这种情况应该是 search_file 出错了 */
    return false;
}