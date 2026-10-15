#!/bin/sh
# Lint the RTL and run the self-checking simulations (Verilator 5.x).
#   sim/run_tests.sh
set -e
cd "$(dirname "$0")"
CORE=../src/fpga/core
T=$CORE/tempest
RTL="$T/tempest_top.sv $T/vector_fb.sv $T/cpu.sv $T/ALU.sv $T/mathbox.sv $T/matoro.sv $T/avg.sv $T/avg_decode.sv $T/rasterizer.sv $T/POKEY.sv"
QUIET="-Wno-fatal -Wno-WIDTH -Wno-UNOPTFLAT -Wno-CASEX -Wno-TIMESCALEMOD -Wno-SYNCASYNCNET -Wno-PINCONNECTEMPTY -Wno-PINNOCONNECT -Wno-PINMISSING"
OBJ=${OBJ:-obj}
mkdir -p $OBJ/loader $OBJ/tempest $OBJ/mathbox $OBJ/pokey

echo "== lint: Pocket top level"
verilator --lint-only $QUIET -Wno-UNUSEDSIGNAL -Wno-UNDRIVEN -Wno-MULTIDRIVEN -I$T --top-module core_top \
  $CORE/core_top.sv $CORE/pocket_loader.sv $CORE/spinner.sv $RTL $CORE/core_bridge_cmd.v ../src/fpga/apf/common.v stubs/ip_stubs.v

echo "== sim: bridge loader"
verilator --cc --exe --build -O2 -j 0 $QUIET --top-module pocket_loader -Mdir $OBJ/loader $CORE/pocket_loader.sv "$PWD/tb_loader.cpp" >/dev/null
$OBJ/loader/Vpocket_loader

echo "== sim: mathbox against MAME's mathbox (randomised)"
verilator --cc --exe --build -O2 -j 0 $QUIET --top-module mathBox -Mdir $OBJ/mathbox $T/mathbox.sv $T/matoro.sv "$PWD/tb_mathbox.cpp" >/dev/null
$OBJ/mathbox/VmathBox

echo "== sim: POKEY pitch against the chip formulas"
verilator --cc --exe --build -O2 -j 0 $QUIET --top-module POKEY -Mdir $OBJ/pokey $T/POKEY.sv "$PWD/tb_pokey.cpp" >/dev/null
$OBJ/pokey/VPOKEY

echo "== sim: Tempest machine with a synthetic test ROM"
python3 make_test_rom.py $OBJ/test.rom
verilator --cc --exe --build -O2 -j 0 --public-flat-rw $QUIET -I$T --top-module tempest_top -Mdir $OBJ/tempest $RTL "$PWD/tb_tempest.cpp" >/dev/null
$OBJ/tempest/Vtempest_top $OBJ/test.rom $OBJ
