riscv32-elf-as -march=rv32i -mabi=ilp32 -o prog.o prog.s
riscv32-elf-ld -Ttext=0x0 -o prog.elf prog.o
riscv32-elf-objcopy -O verilog --verilog-data-width=4 prog.elf prog.hex
