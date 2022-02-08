.PHONY:build
build:
	nasm boot/mbr.S -o boot/mbr.bin
	@echo "build success"

bochsPath = /home/yujt/software/bochs

.PHONY:install
install:
	dd if=/dev/zero of=$(bochsPath)/hd60M.img bs=512 count=200 conv=notrunc
	dd if=boot/mbr.bin of=$(bochsPath)/hd60M.img bs=512 count=1 conv=notrunc
	@echo "install into disk success"

.PHONY:clean
clean:
	$(RM) boot/mbr.bin

.PHONY:qemu
qemu:
	qemu-system-i386 -hda $(bochsPath)/hd60M.img  # -serial stdio
