build_dir := build
bochs_path := /home/yujt/software/bochs
_entry := 0xc0001500

.PHONY: all
all: build install

.PHONY:build
build:
	mkdir -p $(build_dir)
	nasm -I boot/include boot/mbr.S -o $(build_dir)/mbr.bin
	nasm -I boot/include boot/loader.S -o $(build_dir)/loader.bin
	gcc -c -m32 -o $(build_dir)/main.o kernel/main.c && \
	ld -m elf_i386 $(build_dir)/main.o -Ttext $(_entry) -e main -o $(build_dir)/kernel.bin

.PHONY:install
install:
	dd if=/dev/zero of=$(bochs_path)/hd60M.img bs=512 count=300 conv=notrunc
	dd if=$(build_dir)/mbr.bin of=$(bochs_path)/hd60M.img bs=512 count=1 conv=notrunc
	dd if=$(build_dir)/loader.bin of=$(bochs_path)/hd60M.img bs=512 count=4 seek=2 conv=notrunc
	dd if=$(build_dir)/kernel.bin of=$(bochs_path)/hd60M.img bs=512 count=200 seek=9 conv=notrunc
	@echo "install into disk success"

.PHONY:clean
clean:
	$(RM) -r $(build_dir)

.PHONY:qemu
qemu:
	qemu-system-i386 -hda $(bochs_path)/hd60M.img -boot c # -serial stdio