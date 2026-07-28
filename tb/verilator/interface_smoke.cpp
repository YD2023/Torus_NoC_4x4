#include <cstdint>
#include <exception>
#include <iostream>
#include <stdexcept>
#include <string>

#include "Vnoc_interface_smoke_top.h"
#include "verilated.h"

#ifndef INTERFACE_TARGET
#define INTERFACE_TARGET 1
#endif

namespace {
constexpr int kNumNodes = 16;
constexpr int kFlitWords = 32;
constexpr int kPortLocal = 4;
constexpr uint16_t kActiveOutputMask =
    INTERFACE_TARGET == 0 ? UINT16_C(0x001f) : UINT16_C(0xffff);

uint64_t make_flit(int dst_x, int dst_y, int src_x, int src_y,
                   uint64_t payload) {
  return (UINT64_C(3) << 62) |
         (static_cast<uint64_t>(dst_x & 3) << 60) |
         (static_cast<uint64_t>(dst_y & 3) << 58) |
         (static_cast<uint64_t>(src_x & 3) << 56) |
         (static_cast<uint64_t>(src_y & 3) << 54) |
         (UINT64_C(1) << 46) |
         (payload & ((UINT64_C(1) << 46) - 1));
}

void clear_flits(WData* bus) {
  for (int word = 0; word < kFlitWords; ++word) {
    bus[word] = 0;
  }
}

void set_flit(WData* bus, int index, uint64_t flit) {
  bus[index * 2] = static_cast<uint32_t>(flit);
  bus[index * 2 + 1] = static_cast<uint32_t>(flit >> 32);
}

uint64_t get_flit(const WData* bus, int index) {
  return static_cast<uint64_t>(bus[index * 2]) |
         (static_cast<uint64_t>(bus[index * 2 + 1]) << 32);
}

void rise(Vnoc_interface_smoke_top& top) {
  top.clk = 1;
  top.eval();
}

void fall(Vnoc_interface_smoke_top& top) {
  top.clk = 0;
  top.eval();
}

void cycle(Vnoc_interface_smoke_top& top) {
  rise(top);
  fall(top);
}

void reset(Vnoc_interface_smoke_top& top) {
  top.clk = 0;
  top.rst_n = 1;
  top.eval();
  top.rst_n = 0;
  top.local_in_valid_i = 0;
  top.local_in_vc_i = 0;
  top.local_out_ready_i = 0xffff;
  clear_flits(top.local_in_flit_i);
  top.eval();
  cycle(top);
  cycle(top);
  top.rst_n = 1;
  top.eval();
}

void inject_and_expect(Vnoc_interface_smoke_top& top, int input, int output,
                       uint64_t flit, int input_vc, int output_vc) {
  top.local_in_valid_i = static_cast<uint16_t>(1U << input);
  top.local_in_vc_i = static_cast<uint16_t>((input_vc & 1) << input);
  clear_flits(top.local_in_flit_i);
  set_flit(top.local_in_flit_i, input, flit);
  top.eval();

  bool accepted = false;
  for (int wait = 0; wait < 64; ++wait) {
    const bool ready = (top.local_in_ready_o >> input) & 1U;
    rise(top);
    fall(top);
    if (ready) {
      accepted = true;
      break;
    }
  }
  if (!accepted) {
    throw std::runtime_error(
        "interface injection on input " + std::to_string(input) +
        " did not become ready; ready mask " +
        std::to_string(top.local_in_ready_o & kActiveOutputMask));
  }

  top.local_in_valid_i = 0;
  top.local_in_vc_i = 0;
  clear_flits(top.local_in_flit_i);
  top.eval();

  for (int wait = 0; wait < 96; ++wait) {
    const uint16_t valid = top.local_out_valid_o & kActiveOutputMask;
    if (valid != 0) {
      const uint16_t expected_mask = static_cast<uint16_t>(1U << output);
      if (valid != expected_mask) {
        throw std::runtime_error(
            "interface wrapper asserted output mask " +
            std::to_string(valid) + " for input " + std::to_string(input) +
            "; expected " + std::to_string(expected_mask) + " on output " +
            std::to_string(output));
      }
      if (get_flit(top.local_out_flit_o, output) != flit) {
        throw std::runtime_error("interface wrapper changed the flit payload");
      }
      if (((top.local_out_vc_o >> output) & 1U) !=
          static_cast<unsigned>(output_vc)) {
        throw std::runtime_error("interface wrapper produced the wrong VC");
      }
      cycle(top);
      return;
    }
    cycle(top);
  }

  throw std::runtime_error(
      "interface ejection timed out for input " + std::to_string(input) +
      " to output " + std::to_string(output));
}

void test_router(Vnoc_interface_smoke_top& top) {
  for (int input = 0; input < 5; ++input) {
    const uint64_t flit = make_flit(3, 0, 1, 1, 0x100 + input);
    inject_and_expect(top, input, kPortLocal, flit, 0, 0);
  }

  const int dst_x[5] = {3, 3, 0, 2, 3};
  const int dst_y[5] = {3, 1, 0, 0, 0};
  const int expected_vc[5] = {1, 0, 1, 0, 0};
  for (int output = 0; output < 5; ++output) {
    const uint64_t flit =
        make_flit(dst_x[output], dst_y[output], 3, 0, 0x200 + output);
    inject_and_expect(top, kPortLocal, output, flit, 0, expected_vc[output]);
  }
}

void test_torus(Vnoc_interface_smoke_top& top) {
  for (int node = 0; node < kNumNodes; ++node) {
    const int x = node / 4;
    const int y = node % 4;
    const uint64_t flit = make_flit(x, y, x, y, 0x300 + node);
    inject_and_expect(top, node, node, flit, 0, 0);
  }

  const uint64_t wrap = make_flit(3, 0, 0, 0, 0x400);
  inject_and_expect(top, 0, 12, wrap, 0, 1);
}
}  // namespace

int main(int argc, char** argv) {
  Verilated::commandArgs(argc, argv);
  Verilated::randReset(0);
  Vnoc_interface_smoke_top top;

  try {
    reset(top);
#if INTERFACE_TARGET == 0
    test_router(top);
    std::cout << "PASS: router noc_link_if wrapper smoke" << std::endl;
#else
    test_torus(top);
    std::cout << "PASS: torus4x4 noc_link_if wrapper smoke" << std::endl;
#endif
    top.final();
    return 0;
  } catch (const std::exception& error) {
    std::cerr << "FAIL: " << error.what() << std::endl;
    top.final();
    return 1;
  }
}
