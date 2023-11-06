# mkimg-d1
Allwinner D1 kernel & SBI & U-Boot CI

this repo is not maintained as userland also need to recompiled with `thead` extension.
as mainline kernel does not contain xthead support, this project had lost its origin purpose.

Update:
- currently d1-kernel branch d1/vector-support is not work. That means ANY kernel that do not
use the baseline kernel versioned `5.4.61` would not having working `v0p7` extension.
- the baseline kernel have some caveats.
   1. sunxi did not make the final `board.dts` open source, but released `sun20iw1p1.dtsi` for
   reference. It may be easy to use it to create the board tree, however, i have no time for
   extra work. For ease i picked the dtb from rvboards directly which should working on lichee
   rv dock except 8723ds which i have not tested.
   2. T-Head had changed some non-standard ISA subset to other name. so need to patch CFLAGS in
   `arch/riscv/Makefile` to make compiler happy.