// Compare the RTL mathbox against a C++ port of MAME's mathbox_device::go_w.
// Tempest maps the mathbox at $6080-$609F: RTL address = 0x80 + MAME offset.
#include "VmathBox.h"
#include "verilated.h"
#include <cstdio>
#include <cstdint>
#include <cstdlib>

struct Ref {
    int16_t r[16] = {0}; int16_t result = 0;
#define REG0 r[0]
#define REG1 r[1]
#define REG2 r[2]
#define REG3 r[3]
#define REG4 r[4]
#define REG5 r[5]
#define REG6 r[6]
#define REG7 r[7]
#define REG8 r[8]
#define REG9 r[9]
#define REGa r[10]
#define REGb r[11]
#define REGc r[12]
#define REGd r[13]
#define REGe r[14]
#define REGf r[15]
    void go(int off, uint8_t data) {
        int32_t t; int16_t q; int msb;
        switch (off) {
        case 0x00: result = REG0 = (REG0 & 0xff00) | data; break;
        case 0x01: result = REG0 = (REG0 & 0x00ff) | (data << 8); break;
        case 0x02: result = REG1 = (REG1 & 0xff00) | data; break;
        case 0x03: result = REG1 = (REG1 & 0x00ff) | (data << 8); break;
        case 0x04: result = REG2 = (REG2 & 0xff00) | data; break;
        case 0x05: result = REG2 = (REG2 & 0x00ff) | (data << 8); break;
        case 0x06: result = REG3 = (REG3 & 0xff00) | data; break;
        case 0x07: result = REG3 = (REG3 & 0x00ff) | (data << 8); break;
        case 0x08: result = REG4 = (REG4 & 0xff00) | data; break;
        case 0x09: result = REG4 = (REG4 & 0x00ff) | (data << 8); break;
        case 0x0a: result = REG5 = (REG5 & 0xff00) | data; break;
        case 0x0c: result = REG6 = data; break;
        case 0x15: result = REG7 = (REG7 & 0xff00) | data; break;
        case 0x16: result = REG7 = (REG7 & 0x00ff) | (data << 8); break;
        case 0x1a: result = REG8 = (REG8 & 0xff00) | data; break;
        case 0x1b: result = REG8 = (REG8 & 0x00ff) | (data << 8); break;
        case 0x0d: result = REGa = (REGa & 0xff00) | data; break;
        case 0x0e: result = REGa = (REGa & 0x00ff) | (data << 8); break;
        case 0x0f: result = REGb = (REGb & 0xff00) | data; break;
        case 0x10: result = REGb = (REGb & 0x00ff) | (data << 8); break;
        case 0x17: result = REG7; break;
        case 0x19: result = REG8; break;
        case 0x18: result = REG9; break;
        case 0x0b:
            REG5 = (REG5 & 0x00ff) | (data << 8);
            REGf = (int16_t)0xffff; REG4 -= REG2; REG5 -= REG3;
        step_048:
            t = ((int32_t)REG0) * ((int32_t)REG4); REGc = t >> 16; REGe = t & 0xffff;
            t = ((int32_t)-REG1) * ((int32_t)REG5); REG7 = t >> 16; q = t & 0xffff;
            REG7 += REGc;
            REGe = (REGe >> 1) & 0x7fff; REGc = (q >> 1) & 0x7fff; q = REGc + REGe;
            if (q < 0) REG7++;
            result = REG7;
            if (REGf < 0) break;
            REG7 += REG2;
            [[fallthrough]];
        case 0x12:
            t = ((int32_t)REG1) * ((int32_t)REG4); REGc = t >> 16; REG9 = t & 0xffff;
            t = ((int32_t)REG0) * ((int32_t)REG5); REG8 = t >> 16; q = t & 0xffff;
            REG8 += REGc;
            REG9 = (REG9 >> 1) & 0x7fff; REGc = (q >> 1) & 0x7fff; REG9 += REGc;
            if (REG9 < 0) REG8++;
            REG9 <<= 1;
            result = REG8;
            if (REGf < 0) break;
            REG8 += REG3; REG9 &= 0xff00;
            [[fallthrough]];
        case 0x13:
            REGc = REG9; q = REG8; goto step_0bf;
        case 0x14:
            REGc = REGa; q = REGb;
        step_0bf:
            REGe = REG7 ^ q; REGd = q;
            if (q >= 0) q = REGc;
            else { REGd = -q - 1; q = -REGc - 1; if ((q < 0) && ((q + 1) < 0)) REGd++; q++; }
            if (REG7 >= 0) REGc = REG7; else REGc = -REG7;
            REGf = REG6;
            do {
                REGd -= REGc; msb = ((q & 0x8000) != 0); q <<= 1;
                if (REGd >= 0) q++; else REGd += REGc;
                REGd <<= 1; REGd += msb;
            } while (--REGf >= 0);
            if (REGe >= 0) result = q; else result = -q;
            break;
        case 0x11:
            REG5 = (REG5 & 0x00ff) | (data << 8); REGf = 0x0000; goto step_048;
        case 0x1c:
            REG5 = (REG5 & 0x00ff) | (data << 8);
            do {
                REGe = (REG4 + REG7) >> 1; REGf = (REG5 + REG8) >> 1;
                if ((REGb < REGe) && (REGf < REGe) && ((REGe + REGf) >= 0)) { REG7 = REGe; REG8 = REGf; }
                else { REG4 = REGe; REG5 = REGf; }
            } while (--REG6 >= 0);
            result = REG8; break;
        case 0x1d:
            REG3 = (REG3 & 0x00ff) | (data << 8);
            REG2 -= REG0; if (REG2 < 0) REG2 = -REG2;
            REG3 -= REG1; if (REG3 < 0) REG3 = -REG3;
            [[fallthrough]];
        case 0x1e:
            if (REG3 >= REG2) { REGc = REG2; REGd = REG3; } else { REGd = REG2; REGc = REG3; }
            REGc >>= 2; REGd += REGc; REGc >>= 1;
            result = REGd = (REGc + REGd); break;
        }
    }
};

static VmathBox* m;
static void tick() { m->clk = 0; m->eval(); m->clk = 1; m->eval(); }
static uint8_t rd(uint8_t a) { m->we = 0; m->addr = a; tick(); tick(); return m->dataOut; }
static void wr(int off, uint8_t d) {
    m->addr = 0x80 + off; m->DI = d; m->we = 1; tick();
    m->we = 0; m->addr = 0;
    for (int i = 0; i < 200; i++) { tick(); if (rd(0x40) == 0) break; }
}

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    m = new VmathBox; m->clk_en = 1; m->mod_tempest = 1; m->mod_redbaron = 0;
    m->rst = 1; tick(); tick(); m->rst = 0; tick();
    Ref ref; srand(12345);
    const int cmds[] = {0x0b, 0x11, 0x12, 0x13, 0x14, 0x1d, 0x1e, 0x1c};
    int fails[0x20] = {0}, runs[0x20] = {0}, total_fail = 0;
    for (int it = 0; it < 4000; it++) {
        // load data registers like the game does, keeping REG6 (loop count) small
        for (int off = 0x00; off <= 0x09; off++) { uint8_t d = rand() & 0xff; wr(off, d); ref.go(off, d); }
        { uint8_t d = rand() & 0xff; wr(0x0a, d); ref.go(0x0a, d); }
        { uint8_t d = rand() % 16; wr(0x0c, d); ref.go(0x0c, d); }
        for (int off = 0x0d; off <= 0x10; off++) { uint8_t d = rand() & 0xff; wr(off, d); ref.go(off, d); }
        int c = cmds[rand() % 8]; uint8_t d = rand() & 0xff;
        wr(c, d); ref.go(c, d);
        uint16_t got = rd(0x60) | (rd(0x70) << 8);
        runs[c]++;
        if (got != (uint16_t)ref.result) {
            if (fails[c] < 2) printf("cmd %02X data %02X: rtl %04X mame %04X\n", c, d, got, (uint16_t)ref.result);
            fails[c]++; total_fail++;
            // resync state after a mismatch
            m->rst = 1; tick(); tick(); m->rst = 0; tick(); ref = Ref();
        }
    }
    for (int c : cmds) printf("cmd %02X: %d/%d match\n", c, runs[c] - fails[c], runs[c]);
    printf("%s\n", total_fail ? "MATHBOX MISMATCH" : "MATHBOX MATCHES MAME");
    return total_fail ? 1 : 0;
}
