bochsPath = /home/yujt/software/bochs

.PHONY: clean build install qemu
build:
	nasm -I boot/include boot/mbr.S -o build/mbr.bin
	nasm -I boot/include boot/loader.S -o build/loader.bin
	nasm -f elf lib/kernel/print.S -o build/print.o
	nasm -f elf kernel/kernel.S -o build/kernel.o
	gcc -I lib/kernel/ -I lib/ -I kernel/ -c -fno-builtin -m32 kernel/main.c -o build/main.o
	gcc -I lib/kernel/ -I lib/ -I kernel/ -c -fno-builtin -m32 kernel/interrupt.c -o build/interrupt.o
	gcc -I lib/kernel/ -I lib/ -I kernel/ -c -fno-builtin -m32 kernel/init.c -o build/init.o
	gcc -I lib/kernel/ -I lib/ -I kernel/ -c -fno-builtin -m32 device/timer.c -o build/timer.o
	gcc -I lib/kernel/ -I lib/ -I kernel/ -c -fno-builtin -m32 kernel/debug.c -o build/debug.o
	ld -m elf_i386 -Ttext 0xc0001500 -e main build/main.o build/print.o  \
    build/init.o build/interrupt.o build/timer.o build/debug.o build/kernel.o -o build/kernel.bin && \
    strip --remove-section=.note.gnu.property build/kernel.bin

install:
	dd if=/dev/zero of=$(bochsPath)/hd60M.img bs=512 count=300 conv=notrunc
	dd if=build/mbr.bin of=$(bochsPath)/hd60M.img bs=512 count=1 conv=notrunc
	dd if=build/loader.bin of=$(bochsPath)/hd60M.img bs=512 count=4 seek=2 conv=notrunc
	dd if=build/kernel.bin of=$(bochsPath)/hd60M.img bs=512 count=200 seek=9 conv=notrunc
	@echo "install into disk success"

clean:
	$(RM) -r build/*

qemu:
	qemu-system-i386 -hda $(bochsPath)/hd60M.img -boot c # -serial stdio

all: clean build install