//============================================================================
//  Atari Tempest (1980) for the Analogue Pocket
//
//  Game logic is the "Tempest from Battlezone" core by Alan Steremberg and
//  the Battlezone FPGA student project it grew from (6502 by Arlet Ottens).
//  This top level is new for the Pocket port: it replaces the embedded
//  program ROM with RAM loaded from the user's ROM file, and adds what the
//  MiSTer version did not yet have for Tempest: the IRQ / watchdog-clear
//  scheme, colour RAM, the spinner and switch inputs read through the POKEY
//  pot lines, the EAROM high-score chip and a frame buffer that follows the
//  Tempest AVG's endless display-list loop.
//
//  Memory map (from MAME tempest.cpp):
//    0000-07FF RAM            0800-080F colour RAM (w)
//    0C00 IN0  0D00 DSW1  0E00 DSW2
//    2000-2FFF vector RAM     3000-3FFF vector ROM
//    4000 coin counters / flip (w)   4800 VG GO   5000 IRQ ack   5800 VG reset
//    6000-603F EAROM write    6040 mathbox status (r) / EAROM control (w)
//    6050 EAROM read          6060/6070 mathbox result   6080-609F mathbox go
//    60C0-60CF POKEY 1        60D0-60DF POKEY 2          60E0 LEDs / player
//    9000-DFFF program ROM    F000-FFFF mirror of D000-DFFF (vectors)
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 2 of the License, or (at your option)
//  any later version.
//============================================================================
`default_nettype none

module tempest_top
(
  input  wire        clk,            // 49.5 MHz core clock
  input  wire        reset,          // synchronous, active high

  // ROM file loader (clk domain). 0x0000-0x4FFF program, 0x5000-0x5FFF vector ROM
  input  wire        dl_wr,
  input  wire [14:0] dl_addr,
  input  wire [7:0]  dl_data,

  // EAROM (high scores): load from SD, read back for saving
  input  wire        ea_dl_wr,
  input  wire [5:0]  ea_dl_addr,
  input  wire [7:0]  ea_dl_data,
  input  wire [3:0]  ea_rd_word,     // read back for saving (any clock; data is static)
  output wire [31:0] ea_rd_data,     // big-endian: byte 0 in [31:24]
  output reg         ea_dirty,       // toggles whenever the game writes the EAROM

  // controls (active high)
  input  wire        coin,
  input  wire        start1,
  input  wire        start2,
  input  wire        fire,
  input  wire        zap,
  input  wire        service,
  input  wire [3:0]  knob,           // spinner position (4-bit counter)

  // DIP switches, MAME bit layout
  input  wire [7:0]  dsw1,           // 0D00
  input  wire [7:0]  dsw2,           // 0E00
  input  wire [2:0]  in2_dip,        // IN2 bits 2:0 (rating, difficulty)

  // display options
  input  wire        flip_x,
  input  wire        flip_y,

  // video (clk_vid domain)
  input  wire        clk_vid,
  output wire [23:0] vid_rgb,
  output wire        vid_de,
  output wire        vid_hs,
  output wire        vid_vs,

  // audio (clk domain), signed
  output reg  [15:0] audio,
  output reg         audio_tgl       // toggles when a new audio sample is ready
);

  //--------------------------------------------------------------------------
  // Clock enables
  //--------------------------------------------------------------------------
  // CPU and POKEY: 49.5 MHz / 32 = 1.547 MHz (arcade: 1.512 MHz)
  reg [4:0] div32 = 5'd0;
  always @(posedge clk) div32 <= div32 + 5'd1;
  wire cpu_en  = (div32 == 5'd15);   // one cycle before phi2 rises, as in the MiSTer core
  wire phi2    = div32[4];
  wire vg_en   = (div32[2:0] == 3'd7);

  // "3 kHz" source: 49.5 MHz / 16384 = 3.02 kHz
  reg [13:0] div3k = 14'd0;
  always @(posedge clk) div3k <= div3k + 14'd1;
  wire clk_3k  = div3k[13];
  wire tick_3k = (div3k == 14'h3FFF);

  reg cpu_reset = 1'b1;
  always @(posedge clk) begin
    if (reset)       cpu_reset <= 1'b1;
    else if (cpu_en) cpu_reset <= 1'b0;
  end

  //--------------------------------------------------------------------------
  // CPU
  //--------------------------------------------------------------------------
  wire [15:0] AB;
  wire [7:0]  DO;
  wire        WE;
  reg  [7:0]  DI;
  reg         irq;

  cpu core
  (
    .clk    (clk),
    .clk_en (cpu_en),
    .reset  (cpu_reset),
    .AB     (AB),
    .DI     (DI),
    .DO     (DO),
    .WE     (WE),
    .IRQ    (irq),
    .NMI    (1'b0),
    .RDY    (1'b1)
  );

  wire wr = WE & cpu_en;

  // Address decode
  wire sel_ram    = (AB[15:11] == 5'b00000);              // 0000-07FF
  wire sel_cram   = (AB[15:4]  == 12'h080);               // 0800-080F
  wire sel_in0    = (AB == 16'h0C00);
  wire sel_dsw1   = (AB == 16'h0D00);
  wire sel_dsw2   = (AB == 16'h0E00);
  wire sel_vec    = (AB[15:13] == 3'b001);                // 2000-3FFF
  wire sel_vggo   = (AB == 16'h4800);
  wire sel_irqack = (AB == 16'h5000);
  wire sel_vgrst  = (AB == 16'h5800);
  wire sel_eawr   = (AB[15:6]  == 10'b0110_0000_00);      // 6000-603F
  wire sel_6040   = (AB == 16'h6040);
  wire sel_earead = (AB == 16'h6050);
  wire sel_mbread = (AB == 16'h6060) | (AB == 16'h6070);
  wire sel_mbgo   = (AB[15:5]  == 11'b0110_0000_100);     // 6080-609F
  wire sel_pokey1 = (AB[15:4]  == 12'h60C);
  wire sel_pokey2 = (AB[15:4]  == 12'h60D);
  wire sel_rom    = (AB >= 16'h9000 && AB < 16'hE000) || (AB[15:12] == 4'hF);
  wire sel_math   = sel_6040 | sel_mbread | sel_mbgo;

  //--------------------------------------------------------------------------
  // Interrupt: 3 kHz / 12 = 250 Hz, held until the game writes 5000
  //--------------------------------------------------------------------------
  reg [3:0] irq_div;
  always @(posedge clk) begin
    if (reset) begin
      irq     <= 1'b0;
      irq_div <= 4'd0;
    end else begin
      if (tick_3k) begin
        if (irq_div == 4'd11) begin
          irq_div <= 4'd0;
          irq     <= 1'b1;
        end else begin
          irq_div <= irq_div + 4'd1;
        end
      end
      if (wr & sel_irqack) irq <= 1'b0;
    end
  end

  //--------------------------------------------------------------------------
  // Program RAM 0000-07FF
  //--------------------------------------------------------------------------
  reg [7:0] ram [0:2047];
  reg [7:0] ram_q;
  always @(posedge clk) begin
    if (cpu_en) begin
      ram_q <= ram[AB[10:0]];
      if (WE & sel_ram) ram[AB[10:0]] <= DO;
    end
  end

  //--------------------------------------------------------------------------
  // Program ROM 9000-DFFF (+ F000-FFFF mirror), loaded from the ROM file
  //--------------------------------------------------------------------------
  wire [15:0] rom_off  = (AB[15:12] == 4'hF) ? (AB - 16'hB000) : (AB - 16'h9000);
  reg  [7:0]  prog_rom [0:20479];
  reg  [7:0]  rom_q;
  always @(posedge clk) begin
    if (dl_wr && dl_addr < 15'h5000) prog_rom[dl_addr] <= dl_data;
  end
  always @(posedge clk) begin
    if (cpu_en) rom_q <= prog_rom[rom_off[14:0]];
  end

  //--------------------------------------------------------------------------
  // Vector memory 2000-3FFF, split into even/odd bytes so the AVG can fetch
  // one 16-bit word per access while the CPU (or loader) uses the other port
  //--------------------------------------------------------------------------
  wire [15:0] avg_pc;
  // ROM file 0x5000-0x5FFF -> vector space 0x3000-0x3FFF (word 0x800-0xFFF)
  wire [11:0] vec_cpu_word = dl_wr ? dl_addr[12:1] : AB[12:1];
  wire        vec_cpu_odd  = dl_wr ? dl_addr[0] : AB[0];
  wire [7:0]  vec_cpu_din  = dl_wr ? dl_data : DO;
  wire        vec_dl_hit   = dl_wr && (dl_addr >= 15'h5000) && (dl_addr < 15'h6000);
  // CPU may only write the RAM half (2000-2FFF); 3000-3FFF is ROM
  wire        vec_cpu_we   = vec_dl_hit | (wr & sel_vec & ~AB[12]);

  reg [7:0] vec_even [0:4095];
  reg [7:0] vec_odd  [0:4095];
  reg [7:0] vec_even_r, vec_odd_r;     // CPU side, read every clock
  reg [7:0] vec_even_q, vec_odd_q;     // CPU side, held for the bus cycle
  reg [7:0] vec_even_a, vec_odd_a;     // AVG side
  reg       vec_sel_odd;

  always @(posedge clk) begin
    if (vec_cpu_we & ~vec_cpu_odd) vec_even[vec_cpu_word] <= vec_cpu_din;
    vec_even_r <= vec_even[vec_cpu_word];
  end
  always @(posedge clk) begin
    if (vec_cpu_we &  vec_cpu_odd) vec_odd[vec_cpu_word]  <= vec_cpu_din;
    vec_odd_r  <= vec_odd[vec_cpu_word];
  end
  // AB is stable between enables, so the raw read already holds this cycle's data
  always @(posedge clk) begin
    if (cpu_en) begin
      vec_even_q <= vec_even_r;
      vec_odd_q  <= vec_odd_r;
    end
  end
  always @(posedge clk) begin
    vec_even_a <= vec_even[avg_pc[12:1]];
    vec_odd_a  <= vec_odd[avg_pc[12:1]];
  end
  // Same two-stage fetch as the original core: {even byte, odd byte}
  reg [15:0] avg_inst;
  always @(posedge clk) avg_inst <= {vec_even_a, vec_odd_a};

  //--------------------------------------------------------------------------
  // Colour RAM 0800-080F
  //--------------------------------------------------------------------------
  reg [3:0] color_ram [0:15];
  always @(posedge clk) begin
    if (wr & sel_cram) color_ram[AB[3:0]] <= DO[3:0];
  end

  //--------------------------------------------------------------------------
  // Mathbox
  //--------------------------------------------------------------------------
  wire [7:0] mb_q;
  mathBox mb
  (
    .addr         (sel_math ? AB[7:0] : 8'h00),
    .DI           (DO),
    .we           (WE & sel_mbgo),
    .clk          (clk),
    .clk_en       (cpu_en),
    .rst          (reset),
    .mod_tempest  (1'b1),
    .mod_redbaron (1'b0),
    .dataOut      (mb_q)
  );

  //--------------------------------------------------------------------------
  // EAROM (ER2055, 64 bytes) - behaviour follows MAME er2055.cpp
  //--------------------------------------------------------------------------
  reg [7:0] earom [0:63];
  reg [5:0] ea_addr;
  reg [7:0] ea_data;
  reg       ea_ck, ea_c1, ea_c2, ea_cs1;

  assign ea_rd_data = {earom[{ea_rd_word, 2'd0}], earom[{ea_rd_word, 2'd1}],
                       earom[{ea_rd_word, 2'd2}], earom[{ea_rd_word, 2'd3}]};
  wire ea_ctl_chg = ({~DO[2], DO[1], DO[3]} != {ea_c1, ea_c2, ea_cs1});
  wire ea_fall    = ea_ck & ~DO[0];

  integer k;
  initial begin
    for (k = 0; k < 64; k = k + 1) earom[k] = 8'hFF;
    ea_dirty = 1'b0;
  end

  always @(posedge clk) begin
    if (ea_dl_wr) earom[ea_dl_addr] <= ea_dl_data;

    if (wr & sel_eawr) begin
      ea_addr <= AB[5:0];
      ea_data <= DO;
    end

    if (wr & sel_6040) begin
      // CK = D0, C1 = /D2, C2 = D1, CS1 = D3 (CS2 tied active)
      ea_ck  <= DO[0];
      ea_c1  <= ~DO[2];
      ea_c2  <= DO[1];
      ea_cs1 <= DO[3];
      if (DO[3]) begin
        // falling clock edge in read mode (C1 set) latches the cell
        if (ea_fall & ~DO[2]) ea_data <= earom[ea_addr];
        // a control change or a falling clock applies write / erase
        if (ea_ctl_chg | ea_fall) begin
          if (DO[2] & ~DO[1]) begin earom[ea_addr] <= earom[ea_addr] & ea_data; ea_dirty <= ~ea_dirty; end
          if (DO[2] &  DO[1]) begin earom[ea_addr] <= 8'hFF;                    ea_dirty <= ~ea_dirty; end
        end
      end
    end
  end

  //--------------------------------------------------------------------------
  // POKEYs. Switches are read through the pot lines (ALLPOT); MAME returns
  // pot value 0 for a set input bit, so ALLPOT reads back the inverted port.
  //--------------------------------------------------------------------------
  // IN1/DSW0: spinner (4 bits), cabinet = upright (1), bits 7:5 unused (1)
  wire [7:0] in1 = {3'b111, 1'b1, knob};
  // IN2: start2, start1 (active low), buttons via player select, DIPs
  //   bit 3 = BUTTON2 (superzapper), bit 4 = BUTTON1 (fire), active low
  wire [7:0] in2 = {1'b1, ~start2, ~start1, ~fire, ~zap, in2_dip};

  wire [7:0] pokey1_q, pokey2_q;
  reg  [7:0] pokey1_h, pokey2_h;   // held for the CPU bus cycle
  always @(posedge clk) begin
    if (cpu_en) begin
      pokey1_h <= pokey1_q;
      pokey2_h <= pokey2_q;
    end
  end
  wire [5:0] pokey1_vol, pokey2_vol;

  // POKEY clock: exactly 1.512 MHz (MASTER_CLOCK / 8) from 49.5 MHz
  reg  [16:0] pk_acc = 17'd0;
  wire [16:0] pk_sum = pk_acc + 17'd1512;
  wire        pokey_step = (pk_sum >= 17'd49500);
  always @(posedge clk) pk_acc <= pokey_step ? pk_sum - 17'd49500 : pk_sum;

  POKEY pokey1
  (
    .Din              (DO),
    .Dout             (pokey1_q),
    .A                (AB[3:0]),
    .P                (~in1),
    .phi2             (phi2),
    .readHighWriteLow (~(WE & sel_pokey1)),
    .cs0Bar           (~sel_pokey1),
    .step_en          (pokey_step),
    .vol              (pokey1_vol),
    .clk              (clk)
  );

  POKEY pokey2
  (
    .Din              (DO),
    .Dout             (pokey2_q),
    .A                (AB[3:0]),
    .P                (~in2),
    .phi2             (phi2),
    .readHighWriteLow (~(WE & sel_pokey2)),
    .cs0Bar           (~sel_pokey2),
    .step_en          (pokey_step),
    .vol              (pokey2_vol),
    .clk              (clk)
  );

  //--------------------------------------------------------------------------
  // IN0: coins / tilt / test active low, bit 6 = VG halted, bit 7 = 3 kHz
  //--------------------------------------------------------------------------
  wire       avg_halt;
  wire [7:0] in0 = {clk_3k, avg_halt, 1'b1 /*diag step*/, ~service, 1'b1 /*tilt*/, ~coin, 1'b1, 1'b1};

  //--------------------------------------------------------------------------
  // CPU read mux (select registered on cpu_en, like the RAM outputs)
  //--------------------------------------------------------------------------
  localparam S_NONE = 4'd0, S_RAM = 4'd1, S_ROM = 4'd2, S_VEC = 4'd3, S_IO = 4'd4,
             S_MATH = 4'd5, S_POKEY1 = 4'd6, S_POKEY2 = 4'd7;
  reg [3:0] rd_sel;
  reg [7:0] io_q;

  always @(posedge clk) begin
    if (cpu_en) begin
      vec_sel_odd <= AB[0];
      io_q        <= 8'h00;
      if      (sel_ram)    rd_sel <= S_RAM;
      else if (sel_rom)    rd_sel <= S_ROM;
      else if (sel_vec)    rd_sel <= S_VEC;
      else if (sel_6040 | sel_mbread) rd_sel <= S_MATH;
      else if (sel_pokey1) rd_sel <= S_POKEY1;
      else if (sel_pokey2) rd_sel <= S_POKEY2;
      else begin
        rd_sel <= S_IO;
        if (sel_in0)    io_q <= in0;
        if (sel_dsw1)   io_q <= dsw1;
        if (sel_dsw2)   io_q <= dsw2;
        if (sel_earead) io_q <= ea_data;
      end
    end
  end

  always @(*) begin
    case (rd_sel)
      S_RAM:    DI = ram_q;
      S_ROM:    DI = rom_q;
      S_VEC:    DI = vec_sel_odd ? vec_odd_q : vec_even_q;
      S_MATH:   DI = mb_q;
      S_POKEY1: DI = pokey1_h;
      S_POKEY2: DI = pokey2_h;
      default:  DI = io_q;
    endcase
  end

  //--------------------------------------------------------------------------
  // Vector generator
  //--------------------------------------------------------------------------
  wire        vggo  = (AB == 16'h4800) & WE;
  wire        vgrst = (AB == 16'h5800) & WE;
  wire [12:0] vStartX, vStartY, vEndX, vEndY;
  wire [3:0]  vIntensity;
  wire        vWrite;
  wire [3:0]  vColorIdx;
  wire        vFrameDone;
  wire        q_full, q_empty, q_almost_full;
  wire        fb_busy;

  avg_core #(.CLK_DIV("TRUE")) avgc
  (
    .startX      (vStartX),
    .startY      (vStartY),
    .endX        (vEndX),
    .endY        (vEndY),
    .intensity   (vIntensity),
    .lrWrite     (vWrite),
    .pcOut       (avg_pc),
    .halt        (avg_halt),
    .colorIdx    (vColorIdx),
    .frameDone   (vFrameDone),
    .stall       (q_almost_full | fb_busy),
    .inst        (avg_inst),
    .clk_in      (clk),
    .clk_6MHz_en (vg_en),
    .rst_in      (reset | vgrst),
    .vggo        (vggo)
  );

  // AVG units -> 512x512 screen. Tempest's picture spans about 580 x 570
  // units (MAME visible area), so scale by 7/8 around the centre.
  // AVG +Y points up the screen (confirmed on hardware); the Flip settings
  // mirror either axis.
  function automatic [12:0] to_screen(input [12:0] v, input flip);
    reg signed [15:0] sv;
    reg signed [15:0] sc;
    reg signed [15:0] r;
    begin
      sv = $signed({{3{v[12]}}, v});
      sc = (sv * 16'sd7) >>> 3;
      r  = flip ? (16'sd255 - sc) : (16'sd256 + sc);
      to_screen = r[12:0];
    end
  endfunction

  // Colour comes from colour RAM (active-low bits): 3=G, 2=B, 1=R (0=R low)
  wire [3:0] cram_out = color_ram[vColorIdx];
  wire [2:0] line_rgb = {~cram_out[1], ~cram_out[3], ~cram_out[2]};
  wire       line_vis = vWrite & (vIntensity != 4'd0) & (line_rgb != 3'b000);

  wire [12:0] qStartX, qStartY, qEndX, qEndY;
  wire [3:0]  qColor;
  wire        lineDone;

  lineRegQueue lrq
  (
    .QStartX    (qStartX),
    .QStartY    (qStartY),
    .QEndX      (qEndX),
    .QEndY      (qEndY),
    .QIntensity (qColor),
    .full       (q_full),
    .empty      (q_empty),
    .almostFull (q_almost_full),
    .DStartX    (to_screen(vStartX, flip_x)),
    .DStartY    (to_screen(vStartY, ~flip_y)),   // AVG +Y is up on the Tempest monitor
    .DEndX      (to_screen(vEndX,   flip_x)),
    .DEndY      (to_screen(vEndY,   ~flip_y)),
    .DIntensity ({1'b0, line_rgb}),
    .read       (lineDone),
    .currWrite  (line_vis),
    .clk        (clk),
    .rst        (reset)
  );

  wire [17:0] px_addr;
  wire [3:0]  px_color;
  wire        px_we;
  wire        rast_ready;

  rasterizer rast
  (
    .startX      (qStartX),
    .endX        (qEndX),
    .startY      (qStartY),
    .endY        (qEndY),
    .lineColor   (qColor),
    .clk         (clk),
    .rst         (reset),
    .readyIn     (~q_empty),
    .addressOut  (px_addr),
    .pixelX      (),
    .pixelY      (),
    .pixelColor  (px_color),
    .goodPixel   (px_we),
    .done        (lineDone),
    .rastReady   (rast_ready)
  );

  // Frame end: Tempest's JMP-to-0 loop, or a HALT for safety
  reg halt_d;
  always @(posedge clk) halt_d <= avg_halt;
  wire frame_end = vFrameDone | (avg_halt & ~halt_d);

  vector_fb fb
  (
    .clk        (clk),
    .reset      (reset),
    .px_we      (px_we),
    .px_addr    (px_addr),
    .px_rgb     (px_color[2:0]),
    .frame_end  (frame_end),
    .drain_idle (q_empty & rast_ready & ~line_vis),
    .busy       (fb_busy),
    .clk_vid    (clk_vid),
    .vid_rgb    (vid_rgb),
    .vid_de     (vid_de),
    .vid_hs     (vid_hs),
    .vid_vs     (vid_vs)
  );

  //--------------------------------------------------------------------------
  // Audio. Both POKEY volume sums (0..60 each) are averaged over 1024
  // clocks (48.3 kHz), passed through a one-pole lowpass at about 3 kHz
  // standing in for the POKEY output RC network MAME models for Tempest
  // (10k / 0.015uF), then a DC blocker. audio_tgl marks each new sample so
  // the I2S side can take it without catching a value mid-change.
  //--------------------------------------------------------------------------
  reg  [9:0]         aud_cnt = 10'd0;
  reg  [16:0]        acc = 17'd0;                 // sum over 1024 clocks: 0..122880
  reg  signed [23:0] lp  = 24'sd0;                // lowpass state, 8 fractional bits
  reg  signed [27:0] dc  = 28'sd0;                // DC estimate, 12 fractional bits
  wire [6:0]         mixv = {1'b0, pokey1_vol} + {1'b0, pokey2_vol};
  wire signed [23:0] x    = {2'b00, acc[16:3], 8'd0};               // acc/8 = 0..15360, 8 fractional bits
  wire signed [31:0] lp_d = ({{8{x[23]}}, x} - {{8{lp[23]}}, lp}) * 32'sd83;
  wire signed [31:0] lp_s = lp_d >>> 8;
  wire signed [23:0] lp_n = lp + lp_s[23:0];                        // alpha = 83/256 (fc ~ 3 kHz)
  wire signed [27:0] lp_w = {{4{lp_n[23]}}, lp_n} <<< 4;             // 12 fractional bits
  wire signed [27:0] dc_n = dc + ((lp_w - dc) >>> 10);               // ~7.5 Hz high-pass
  wire signed [27:0] ac   = (lp_w - dc_n) >>> 11;                    // +-15360 -> 1 bit gain
  always @(posedge clk) begin
    aud_cnt <= aud_cnt + 10'd1;
    if (aud_cnt == 10'd0) begin
      lp        <= lp_n;
      dc        <= dc_n;
      audio     <= (ac > 28'sd32767) ? 16'sd32767 : (ac < -28'sd32768) ? -16'sd32768 : ac[15:0];
      audio_tgl <= ~audio_tgl;
      acc       <= {10'd0, mixv};
    end else begin
      acc       <= acc + {10'd0, mixv};
    end
  end

  initial audio_tgl = 1'b0;

endmodule

`default_nettype wire
