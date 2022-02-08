> nasm -I include/ -o loader.bin loader.S

> nasm -I include/ -o mbr.bin mbr.S

> dd if=mbr.bin of=/home/yujt/software/bochs/hd60M.img bs=512 count=1 conv=notrunc

> dd if=loader.bin of=/home/yujt/software/bochs/hd60M.img bs=512 count=4 seek=2 conv=notrunc

> gcc -c -o kernel/main.o kernel/main.c && ld kernel/main.o -Ttext 0xc0001500 -e main -o kernel/kernel.bin && dd if=kernel/kernel.bin of=/home/yujt/software/bochs/hd60M.img bs=512 count=200 seek=9 conv=notrunc

存在bug，后期需要找到问题