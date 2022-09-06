.PHONY: all
all: build install

NASM := nasm
entry := 0xc0001500
build_dir := build
# bochs 软件位置
bochsPath := /home/yujt/software/bochs

.PHONY: build
build:
	mkdir -p $(build_dir)
	$(NASM) -I boot/include boot/mbr.S -o build/mbr.bin
	$(NASM) -I boot/include boot/loader.S -o build/loader.bin
	$(NASM) -f elf lib/kernel/print.S -o build/print.o
	$(NASM) -f elf kernel/kernel.S -o build/kernel.o
	$(CC) -I lib/kernel/ -I lib/ -I kernel/ -c -fno-builtin -m32 kernel/main.c -o build/main.o
	$(CC) -I lib/kernel/ -I lib/ -I kernel/ -c -fno-builtin -m32 kernel/interrupt.c -o build/interrupt.o
	$(CC) -I lib/kernel/ -I lib/ -I kernel/ -c -fno-builtin -m32 kernel/init.c -o build/init.o
	$(LD) -m elf_i386 -Ttext $(entry) -e main build/main.o build/print.o  \
    build/init.o build/interrupt.o build/kernel.o -o build/kernel.bin && \
    strip --remove-section=.note.gnu.property build/kernel.bin

.PHONY: install
install:
	dd if=/dev/zero of=$(bochsPath)/hd60M.img bs=512 count=300 conv=notrunc
	dd if=build/mbr.bin of=$(bochsPath)/hd60M.img bs=512 count=1 conv=notrunc
	dd if=build/loader.bin of=$(bochsPath)/hd60M.img bs=512 count=4 seek=2 conv=notrunc
	dd if=build/kernel.bin of=$(bochsPath)/hd60M.img bs=512 count=200 seek=9 conv=notrunc
	@echo "install into disk success"

.PHONY: clean
clean:
	$(RM) -r ./build

.PHONY: qemu
qemu:
	qemu-system-i386 -hda $(bochsPath)/hd60M.img -boot c # -serial stdio