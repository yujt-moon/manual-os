build_dir := build

$(build_dir)/%.o: %.asm
	mkdir -p $(dir $@)
	nasm -f elf $^ -o $@
$(build_dir)/12: $(build_dir)/1.o $(build_dir)/2.o
	ld -m elf_i386 $^ -o $@

# 编译链接文件
.PHONY: all
all: $(build_dir)/12

# 清理文件
.PHONY:clean
clean:
	$(RM) -r ./$(build_dir)

# 运行
.PHONY: run
run:
	$(build_dir)/12

# 读取文件头信息
.PHONY: readelf
readelf:
	readelf -e $(build_dir)/12