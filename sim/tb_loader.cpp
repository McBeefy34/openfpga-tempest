// Bridge loader test: big-endian 32-bit words on clk_74a -> byte writes on clk.
#include "Vpocket_loader.h"
#include "verilated.h"
#include <cstdio>
#include <cstdint>
#include <vector>
int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    Vpocket_loader* t = new Vpocket_loader;
    const uint64_t P74 = 13468, PSYS = 20202;
    uint64_t n74 = P74/2, nsys = PSYS/2;
    std::vector<int> rom(0x6000, -1), ea(64, -1);
    // words to send: ROM 0..0x5FFC, plus 16 EAROM words at 0x20000000
    std::vector<std::pair<uint32_t,uint32_t>> words;
    for (uint32_t a = 0; a < 0x6000; a += 4) words.push_back({a, (a*2654435761u) ^ 0xA5A5A5A5u});
    for (uint32_t a = 0; a < 64; a += 4) words.push_back({0x20000000u + a, 0x01020304u * (a/4 + 1)});
    size_t wi = 0; int gap = 0; int c74 = 0;
    t->clk_74a = 0; t->clk = 0; t->bridge_wr = 0;
    for (int it = 0; it < 4000000; it++) {
        if (n74 <= nsys) {
            n74 += P74/2; t->clk_74a = !t->clk_74a;
            if (t->clk_74a) {
                // one write every 12 clk_74a cycles (faster than the real bridge)
                t->bridge_wr = 0;
                if (++c74 % 12 == 0 && wi < words.size()) {
                    t->bridge_wr = 1; t->bridge_addr = words[wi].first; t->bridge_wr_data = words[wi].second; wi++;
                }
            }
            t->eval();
        } else {
            nsys += PSYS/2; t->clk = !t->clk; t->eval();
            if (t->clk) {
                if (t->rom_wr) rom[t->rom_addr] = t->data;
                if (t->ea_wr)  ea[t->ea_addr] = t->data;
            }
        }
        if (wi == words.size() && it > 3900000) break;
    }
    int bad = 0;
    for (uint32_t a = 0; a < 0x6000; a++) {
        uint32_t w = ((a & ~3u)*2654435761u) ^ 0xA5A5A5A5u;
        int exp = (w >> (24 - 8*(a & 3))) & 0xFF;
        if (rom[a] != exp) { if (bad < 5) printf("ROM %04X got %d exp %02X\n", a, rom[a], exp); bad++; }
    }
    for (int a = 0; a < 64; a++) {
        uint32_t w = 0x01020304u * (a/4 + 1);
        int exp = (w >> (24 - 8*(a & 3))) & 0xFF;
        if (ea[a] != exp) { if (bad < 10) printf("EA %d got %d exp %02X\n", a, ea[a], exp); bad++; }
    }
    printf("words sent %zu, mismatches %d\n", wi, bad);
    delete t; return bad != 0;
}
