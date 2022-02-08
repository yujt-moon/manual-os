.PHONY:build
build:
	nasm -I boot/include boot/mbr.S -o boot/mbr.bin
	nasm -I boot/include boot/loader.S -o boot/loader.bin

bochsPath = /home/yujt/software/bochs

.PHONY:install
install:
	dd if=/dev/zero of=$(bochsPath)/hd60M.img bs=512 count=200 conv=notrunc
	dd if=boot/mbr.bin of=$(bochsPath)/hd60M.img bs=512 count=1 conv=notrunc
	dd if=boot/loader.bin of=$(bochsPath)/hd60M.img bs=512 count=4 seek=2 conv=notrunc
	@echo "install into disk success"

.PHONY:clean
clean:
	$(RM) boot/mbr.bin boot/loader.bin

.PHONY:qemu
qemu:
	qemu-system-i386 -hda $(bochsPath)/hd60M.img  # -serial stdio
