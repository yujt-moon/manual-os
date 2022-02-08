.PHONY:build
build:
	nasm -I boot/include boot/mbr.S -o boot/mbr.bin
	nasm -I boot/include boot/loader.S -o boot/loader.bin
	gcc -c -m32 -o kernel/main.o kernel/main.c && \
	ld -m elf_i386 kernel/main.o -Ttext 0xc0001500 -e main -o kernel/kernel.bin

bochsPath = /home/yujt/software/bochs

.PHONY:install
install:
	dd if=/dev/zero of=$(bochsPath)/hd60M.img bs=512 count=300 conv=notrunc
	dd if=boot/mbr.bin of=$(bochsPath)/hd60M.img bs=512 count=1 conv=notrunc
	dd if=boot/loader.bin of=$(bochsPath)/hd60M.img bs=512 count=4 seek=2 conv=notrunc
	dd if=kernel/kernel.bin of=$(bochsPath)/hd60M.img bs=512 count=200 seek=9 conv=notrunc
	@echo "install into disk success"

.PHONY:clean
clean:
	$(RM) boot/mbr.bin boot/loader.bin kernel/main.o kernel/kernel.bin

.PHONY:qemu
qemu:
	qemu-system-i386 -hda $(bochsPath)/hd60M.img -boot c # -serial stdio