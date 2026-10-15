// POKEY pitch test: drive registers, measure tone frequency, compare with
// the POKEY formulas at Tempest's 1.512 MHz clock:
//   64 kHz / 15 kHz base : f = base / (2 (AUDF+1))
//   1.79 MHz (ch1/ch3)   : f = clk  / (2 (AUDF+4))
//   16-bit joined, ch1 at 1.79 MHz : f = clk / (2 (AUDF12+7))
#include "VPOKEY.h"
#include <cstdio>
#include <cmath>
static VPOKEY* p; static unsigned long cyc = 0; static unsigned acc = 0;
static void tick() {
    p->clk = 0; p->eval();
    acc += 1512; p->step_en = 0; if (acc >= 49500) { acc -= 49500; p->step_en = 1; }
    p->phi2 = ((cyc / 16) & 1);
    p->clk = 1; p->eval(); cyc++;
}
static void wr(int a, int d) { p->cs0Bar = 0; p->readHighWriteLow = 0; p->A = a; p->Din = d; for (int i = 0; i < 40; i++) tick(); p->cs0Bar = 1; p->readHighWriteLow = 1; }
static double measure(int volume) {
    const long T = 49500000L * 2;     // 2 s
    long rises = 0; int last = 0;
    for (long i = 0; i < T; i++) { tick(); int s = p->vol >= volume; if (!last && s) rises++; last = s; }
    return rises / 2.0;
}
int main() {
    p = new VPOKEY; p->cs0Bar = 1; p->readHighWriteLow = 1; p->P = 0; p->step_en = 0;
    wr(0xF, 0x00); wr(0xF, 0x03);
    struct T { int audctl, f1, f2; double expect; const char* name; } tests[] = {
        {0x00, 0x40, 0, 1512000.0/28/(2*(0x40+1)),  "64 kHz base, AUDF 0x40"},
        {0x00, 0x10, 0, 1512000.0/28/(2*(0x10+1)),  "64 kHz base, AUDF 0x10"},
        {0x00, 0xC0, 0, 1512000.0/28/(2*(0xC0+1)),  "64 kHz base, AUDF 0xC0"},
        {0x01, 0x20, 0, 1512000.0/114/(2*(0x20+1)), "15 kHz base, AUDF 0x20"},
        {0x40, 0xF0, 0, 1512000.0/(2*(0xF0+4)),     "1.79 MHz ch1, AUDF 0xF0"},
        {0x50, 0x00, 0x08, 1512000.0/(2*(0x0800+7)),"16-bit ch1+2 at 1.79 MHz, 0x0800"},
    };
    int fails = 0;
    for (auto& t : tests) {
        wr(0x8, t.audctl); wr(0x9, 0);                    // AUDCTL, STIMER
        wr(0x1, 0x00); wr(0x3, 0x00);
        wr(0x0, t.f1); wr(0x2, t.f2);
        if (t.audctl & 0x10) wr(0x3, 0xAF); else wr(0x1, 0xAF);   // pure tone, vol 15 on the sounding channel
        double f = measure(15);
        double err = fabs(f - t.expect) / t.expect * 100.0;
        bool ok = err < 0.5 || fabs(f - t.expect) <= 0.5;
        printf("%s %-34s measured %8.1f Hz  expected %8.1f Hz\n", ok ? "PASS" : "FAIL", t.name, f, t.expect);
        if (!ok) fails++;
    }
    // noise channel must actually make noise (poly17, distortion 0)
    wr(0x8, 0x00); wr(0x1, 0x00); wr(0x0, 0x02); wr(0x1, 0x0F);
    double nf = measure(15) * 2;
    bool nok = nf > 500;
    printf("%s %-34s %8.1f transitions/s\n", nok ? "PASS" : "FAIL", "poly17 noise", nf);
    if (!nok) fails++;
    printf("%s\n", fails ? "POKEY PITCH MISMATCH" : "POKEY PITCH MATCHES");
    return fails ? 1 : 0;
}
