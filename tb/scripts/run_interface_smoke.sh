#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
HARNESS=${ROOT_DIR}/tb/harness/noc_interface_smoke_top.sv
DRIVER=${ROOT_DIR}/tb/verilator/interface_smoke.cpp
SOURCES=(
  "${ROOT_DIR}/rtl/noc_pkg.sv"
  "${ROOT_DIR}/rtl/noc_link_if.sv"
  "${ROOT_DIR}/rtl/fifo.sv"
  "${ROOT_DIR}/rtl/rr_arbiter.sv"
  "${ROOT_DIR}/rtl/route_compute_torus.sv"
  "${ROOT_DIR}/rtl/router_vc_in.sv"
  "${ROOT_DIR}/rtl/router_port_in.sv"
  "${ROOT_DIR}/rtl/router_crossbar.sv"
  "${ROOT_DIR}/rtl/router_core.sv"
  "${ROOT_DIR}/rtl/router.sv"
  "${ROOT_DIR}/rtl/torus4x4_core.sv"
  "${ROOT_DIR}/rtl/torus4x4.sv"
)

run_target() {
  local target=$1
  local name=$2
  local build_dir=${ROOT_DIR}/tb/sim_build/interface_smoke_flat/${name}

  mkdir -p "${build_dir}"
  verilator --cc --exe --build --flatten -Wall \
    -Wno-IMPORTSTAR -Wno-DECLFILENAME -Wno-UNUSED -Wno-PINCONNECTEMPTY \
    -DSYNTHESIS --top-module noc_interface_smoke_top \
    -GTARGET=${target} --Mdir "${build_dir}" \
    -CFLAGS "-DINTERFACE_TARGET=${target}" \
    "${SOURCES[@]}" "${HARNESS}" "${DRIVER}"
  "${build_dir}/Vnoc_interface_smoke_top"
}

run_target 0 router
run_target 1 torus4x4
