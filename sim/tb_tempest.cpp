// Verilator testbench for tempest_top with the synthetic test ROM.
// Usage: tb_tempest test.rom out_dir
#include "Vtempest_top.h"
#include "Vtempest_top___024root.h"
#include "verilated.h"
#include <cstdio>
#include <cstdlib>
#include <cstdint>
#include <vector>
#include <string>

static const uint64_t SYS_PS = 20202;   // 49.5 MHz
static const uint64_t VID_PS = 53872;   // 18.5625 MHz

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    if (argc < 3) { fprintf(stderr, "usage: tb rom outdir\n"); return 2; }
    FILE* f = fopen(argv[1], "rb");
    std::vector<uint8_t> rom(0x6000);
    if (!f || fread(rom.data(), 1, rom.size(), f) != rom.size()) { fprintf(stderr, "rom read failed\n"); return 2; }
    fclose(f);
    std::string outdir = argv[2];

    Vtempest_top* t = new Vtempest_top;
    auto* r = t->rootp;
    t->clk = 0; t->clk_vid = 0; t->reset = 1;
    t->dl_wr = 0; t->ea_dl_wr = 0; t->ea_rd_word = 0;
    t->coin = 0; t->start1 = 0; t->start2 = 0; t->fire = 0; t->zap = 0; t->service = 0;
    t->knob = 5; t->dsw1 = 0; t->dsw2 = 0; t->in2_dip = 7; t->flip_x = 0; t->flip_y = 0;

    uint64_t now = 0, next_sys = SYS_PS / 2, next_vid = VID_PS / 2;
    uint64_t sys_cycles = 0;
    size_t dl_idx = 0;
    bool loading = true;
    int frames = 0, frames_with_pixels = 0;
    std::vector<uint32_t> fb(512 * 512, 0), last(512 * 512, 0);
    int vx = 0, vy = -1;
    bool prev_de = false;
    long audio_min = 1 << 30, audio_max = -(1 << 30);
    int swaps = 0; bool prev_busy = false;
    const uint64_t SYS_TOTAL = 50 * 49500ULL * 60;   // ~60 ms... trimmed below by frames

    while (sys_cycles < SYS_TOTAL && frames < 6) {
        if (next_sys <= next_vid) {
            now = next_sys; next_sys += SYS_PS / 2;
            t->clk = !t->clk;
            if (t->clk) {
                sys_cycles++;
                // drive inputs before the edge settles (applied for next cycle)
                if (loading) {
                    if (dl_idx < rom.size()) {
                        t->dl_wr = 1; t->dl_addr = dl_idx; t->dl_data = rom[dl_idx]; dl_idx++;
                    } else {
                        t->dl_wr = 0; loading = false;
                    }
                } else if (sys_cycles == rom.size() + 100) {
                    t->reset = 0;
                }
                if (sys_cycles == 1500000) t->fire = 1;     // press fire later on
            }
            t->eval();
            if (t->clk) {
                long a = (int16_t)t->audio;
                if (sys_cycles > 1000000) { if (a < audio_min) audio_min = a; if (a > audio_max) audio_max = a; }
                bool busy = r->tempest_top__DOT__fb__DOT__st != 0;
                if (busy && !prev_busy) swaps++;
                prev_busy = busy;
            }
        } else {
            now = next_vid; next_vid += VID_PS / 2;
            t->clk_vid = !t->clk_vid;
            t->eval();
            if (t->clk_vid) {
                if (t->vid_vs) {
                    if (vy >= 0) {
                        frames++;
                        int lit = 0;
                        for (auto p : fb) if (p) lit++;
                        if (lit) frames_with_pixels++;
                        last = fb;
                        printf("frame %d: %d lit pixels, %d lines\n", frames, lit, vy);
                    }
                    std::fill(fb.begin(), fb.end(), 0);
                    vy = 0; vx = 0;
                }
                if (t->vid_hs) { if (prev_de) vy++; vx = 0; prev_de = false; }
                if (t->vid_de) {
                    if (vy >= 0 && vy < 512 && vx < 512) fb[vy * 512 + vx] = t->vid_rgb;
                    vx++; prev_de = true;
                }
            }
        }
    }

    // dump last frame
    std::string p = outdir + "/frame.ppm";
    FILE* o = fopen(p.c_str(), "wb");
    fprintf(o, "P6 512 512 255\n");
    for (auto px : last) { uint8_t c[3] = {(uint8_t)(px >> 16), (uint8_t)(px >> 8), (uint8_t)px}; fwrite(c, 1, 3, o); }
    fclose(o);

    auto ram = [&](int a) { return (int)r->tempest_top__DOT__ram[a]; };
    printf("sys cycles %llu, frames %d (with pixels %d), fb swaps %d\n",
           (unsigned long long)sys_cycles, frames, frames_with_pixels, swaps);
    printf("IRQ count $00=%d  ALLPOT1 $10=%02X  IN0 $11=%02X  ALLPOT2 $12=%02X  EAROM $13=%02X\n",
           ram(0), ram(0x10), ram(0x11), ram(0x12), ram(0x13));
    printf("EAROM[5]=%02X  audio range %ld..%ld\n", (int)r->tempest_top__DOT__earom[5], audio_min, audio_max);

    // pixel checks on the last frame (yellow horizontal, green vertical)
    auto px = [&](int x, int y) { return last[y * 512 + x]; };
    int yel = 0, grn = 0, other = 0;
    for (int y = 0; y < 512; y++) for (int x = 0; x < 512; x++) {
        uint32_t c = px(x, y);
        if (!c) continue;
        if (c == 0xFFFF00) yel++; else if (c == 0x00FF00) grn++; else other++;
    }
    printf("yellow %d green %d other %d\n", yel, grn, other);
    printf("sample: (256,256)=%06X (300,256)=%06X (343,256)=%06X (343,300)=%06X (343,343)=%06X (300,300)=%06X\n",
           px(256,256), px(300,256), px(343,256), px(343,300), px(343,343), px(300,300));
    int fails = 0;
    auto check = [&](bool ok, const char* what) { printf("%s %s\n", ok ? "PASS" : "FAIL", what); if (!ok) fails++; };
    check(frames_with_pixels >= 4,                       "frames reach the video output");
    check(ram(0) >= 20,                                  "IRQ at 250 Hz, acknowledged via $5000");
    check(ram(0x10) == 0x0A,                             "spinner read through POKEY 1 ALLPOT");
    check((ram(0x11) & 0x7F) == 0x3F,                    "IN0 switches and VG-halted bit");
    check(ram(0x12) == 0x10,                             "fire button read through POKEY 2 ALLPOT");
    check(ram(0x13) == 0x5A,                             "EAROM write / read back");
    check(audio_max - audio_min > 1000,                  "POKEY audio present");
    check(yel >= 80 && grn >= 80 && other == 0,          "coloured vectors from colour RAM");
    check(px(300,256) == 0xFFFF00 && px(343,300) == 0x00FF00 && px(300,300) == 0, "vector positions");
    printf("%s\n", fails ? "SIMULATION FAILED" : "ALL CHECKS PASSED");
    delete t;
    return fails ? 1 : 0;
}
