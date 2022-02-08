%.o:%.asm
	nasm -f elf $^ -o $@
object_file = 1.o 2.o
12: $(object_file)
	ld -m elf_i386 $^ -o $@

# 编译链接文件
.PHONY:build
build: 12

# 清理文件
.PHONY:clean
clean:
	$(RM) $(object_file) 12