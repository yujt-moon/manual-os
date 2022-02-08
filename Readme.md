编译 mbr.S
> nasm -I boot/include/ boot/mbr.S -o boot/mbr.bin
> dd if=boot/mbr.bin of=/home/yujt/software/bochs/hd60M.img bs=512 count=1 conv=notrunc

编译 loader.S
> nasm -I boot/include/ boot/loader.S -o boot/loader.bin
> dd if=boot/loader.bin of=/home/yujt/software/bochs/hd60M.img bs=512 count=4 seek=2 conv=notrunc

编译 print.S
> nasm -f elf -o lib/kernel/print.o lib/kernel/print.S

编译 main.c
> gcc -I lib/kernel/ -c -m32 -o kernel/main.o kernel/main.c

链接 main.o 和 print.o
> ld -m elf_i386 -Ttext 0xc0001500 -e main -o kernel/kernel.bin kernel/main.o lib/kernel/print.o

写入虚拟硬盘
> dd if=kernel/kernel.bin of=/home/yujt/software/bochs/hd60M.img bs=512 count=200 seek=9 conv=notrunc


反汇编
> ndisasm -o 0x7c00 boot/mbr.bin >> boot/dismbr.S


断点位置
0x7c00
0xc00
0xc20
0xca7   -- .mem_get_ok


[fdisk cylinder sector](https://www.imooc.com/qadetail/58073)

fdisk -c=dos -u=cylinders ./hd80M.img