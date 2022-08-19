build_dir := build
bochsPath := /home/yujt/software/bochs

.PHONY: all
all: build install

.PHONY:build
build:
	mkdir -p $(build_dir)
	nasm boot/mbr.S -o $(build_dir)/mbr.bin
	@echo "build success!"

.PHONY:install
install:
	# 清空硬盘中信息
	dd if=/dev/zero of=$(bochsPath)/hd60M.img bs=512 count=500 conv=notrunc
	dd if=$(build_dir)/mbr.bin of=$(bochsPath)/hd60M.img bs=512 count=1 conv=notrunc
	@echo "install into disk success!"

.PHONY:clean
clean:
	$(RM) $(build_dir)/mbr.bin

.PHONY:qemu
qemu:
	qemu-system-i386 -hda $(bochsPath)/hd60M.img  # -serial stdio

.PHONY:bochs
bochs: SHELL:=/bin/bash
bochs:
	$(bochsPath)/bin/bochs -f $(bochsPath)/bochsrc.disk
