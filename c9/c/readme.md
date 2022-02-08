启动会有 GP 异常

去掉 strip --remove-section=.note.gnu.property $@
可以通过 nm build/kernel.bin | grep thread_start 获取地址