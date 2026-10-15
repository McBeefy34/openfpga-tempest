//============================================================================
//  POKEY sound / pot interface for the Tempest Pocket core.
//
//  Sound generation follows MAME's pokey_device::step_one_clock() and
//  process_channel() (src/devices/sound/pokey.cpp): prescalers (/28, /114),
//  8-bit and joined 16-bit counters with their borrow delays, 1.79 MHz
//  clocking for channels 1 and 3, poly4/5/9/17 noise, distortion selection,
//  high-pass filters, volume-only mode and STIMER.
//
//  Bus side: registers are written / read on the rising edge of phi2 (the
//  CPU bus clock). Sound side: the chip steps on step_en, which the top
//  level generates at Tempest's exact 1.512 MHz POKEY clock.
//
//  Replaces the original Battlezone-project POKEY, whose tones came out an
//  octave low (an extra divide-by-2 stage) and whose distortion wiring did
//  not match the chip.
//
//  Not implemented (unused by Tempest): serial port, keyboard scan, IRQs,
//  pot counters (ALLPOT returns the switch inputs directly, as on the board).
//============================================================================
`default_nettype none

module POKEY
  (
   input  logic [7:0] Din,
   output logic [7:0] Dout,
   input  logic [3:0] A,
   input  logic [7:0] P,
   input  logic       phi2,
   input  logic       readHighWriteLow,
   input  logic       cs0Bar,
   input  logic       step_en,      // one pulse per POKEY clock (1.512 MHz)
   output logic [5:0] vol,          // sum of active channel volumes, 0..60
   input  logic       clk
   );

  //--------------------------------------------------------------------------
  // Registers
  //--------------------------------------------------------------------------
  logic [7:0] audf [0:3];
  logic [7:0] audc [0:3];
  logic [7:0] audctl, skctl;
  logic [7:0] dataOut;
  logic       phi2_d;
  logic       stimer;               // pulse: STIMER written

  wire phi2Rising = phi2 & ~phi2_d;
  wire bus        = phi2Rising & ~cs0Bar;
  wire running    = (skctl[1:0] != 2'b00);

  assign Dout = dataOut;

  // AUDCTL bits
  wire POLY9   = audctl[7];
  wire CH1_HI  = audctl[6];
  wire CH3_HI  = audctl[5];
  wire J12     = audctl[4];
  wire J34     = audctl[3];
  wire FILT1   = audctl[2];
  wire FILT2   = audctl[1];
  wire CLK15   = audctl[0];

  //--------------------------------------------------------------------------
  // Polynomial counters (equivalent to MAME's precomputed tables)
  //--------------------------------------------------------------------------
  logic [3:0]  p4;
  logic [4:0]  p5;
  logic [8:0]  p9;
  logic [16:0] p17;

  wire [3:0]  p4_n  = {p4[2:0], ~(p4[2] ^ p4[3])};
  wire [4:0]  p5_n  = {p5[3:0], ~(p5[2] ^ p5[4])};
  wire [8:0]  p9_n  = {p9[0] ^ p9[5], p9[8:1]};
  wire [16:0] p17_s = {p17[0], p17[16:1]};
  wire [16:0] p17_n = {p17_s[16:8], p17[8] ^ p17[13], p17_s[6:0]};

  //--------------------------------------------------------------------------
  // Channel state
  //--------------------------------------------------------------------------
  logic [7:0] cnt    [0:3];
  logic [2:0] borrow [0:3];
  logic [3:0] outb;                  // channel output flip-flops
  logic [1:0] filt;                  // high-pass samples for channels 1, 2
  logic [6:0] pre28;
  logic [6:0] pre114;

  wire trig28  = (pre28  == 7'd27);
  wire trig114 = (pre114 == 7'd113);
  wire base    = CLK15 ? trig114 : trig28;

  // which counters advance this step, and their borrow delay
  wire [3:0] inc_en = { base & ~J34,
                        CH3_HI | base,
                        base & ~J12,
                        CH1_HI | base };
  wire [2:0] cyc0 = CH1_HI ? (J12 ? 3'd7 : 3'd4) : 3'd1;
  wire [2:0] cyc2 = CH3_HI ? (J34 ? 3'd7 : 3'd4) : 3'd1;

  function automatic logic poly_bit(input logic [7:0] ac, input logic [3:0] p4v,
                                    input logic [8:0] p9v, input logic [16:0] p17v,
                                    input logic poly9);
    if (ac[6])      poly_bit = p4v[0];
    else if (poly9) poly_bit = p9v[0];
    else            poly_bit = p17v[0];
  endfunction

  // MAME runs the borrow checks in the order 3, 4, 1, 2 after the
  // increments; model that sequence with blocking variables.
  logic [7:0] c [0:3];
  logic [2:0] b [0:3];
  logic [3:0] o;
  logic [1:0] fs;

  always_ff @(posedge clk) begin
    phi2_d <= phi2;

    //------------------------------------------------------------------------
    // Bus access
    //------------------------------------------------------------------------
    stimer <= 1'b0;
    if (bus) begin
      if (readHighWriteLow) begin
        case (A)
          4'h8:    dataOut <= P;                                   // ALLPOT
          4'hA:    dataOut <= POLY9 ? p9[7:0] : p17[15:8];         // RANDOM
          default: dataOut <= 8'hFF;
        endcase
      end else begin
        case (A)
          4'h0: audf[0] <= Din;   4'h1: audc[0] <= Din;
          4'h2: audf[1] <= Din;   4'h3: audc[1] <= Din;
          4'h4: audf[2] <= Din;   4'h5: audc[2] <= Din;
          4'h6: audf[3] <= Din;   4'h7: audc[3] <= Din;
          4'h8: audctl <= Din;
          4'h9: stimer <= 1'b1;
          4'hF: skctl  <= Din;
          default: ;
        endcase
      end
    end

    //------------------------------------------------------------------------
    // Sound
    //------------------------------------------------------------------------
    if (stimer) begin
      for (int i = 0; i < 4; i++) begin
        cnt[i]    <= audf[i] ^ 8'hFF;
        borrow[i] <= 3'd0;
      end
      outb <= 4'b0000;
      filt <= 2'b11;
    end else if (step_en) begin
      for (int i = 0; i < 4; i++) begin c[i] = cnt[i]; b[i] = borrow[i]; end
      o  = outb;
      fs = filt;

      if (running) begin
        for (int i = 0; i < 4; i++) begin
          if (inc_en[i]) begin
            c[i] = c[i] + 8'd1;
            if (c[i] == 8'd0 && b[i] == 3'd0) b[i] = (i == 0) ? cyc0 : (i == 2) ? cyc2 : 3'd1;
          end
        end
      end

      // Channel 3 borrow
      if (b[2] != 3'd0) begin
        b[2] = b[2] - 3'd1;
        if (b[2] == 3'd0) begin
          if (J34) begin
            c[3] = c[3] + 8'd1;
            if (c[3] == 8'd0 && b[3] == 3'd0) b[3] = 3'd1;
          end else begin
            c[2] = audf[2] ^ 8'hFF;
          end
          if (audc[2][7] || p5[0]) o[2] = audc[2][5] ? ~o[2] : poly_bit(audc[2], p4, p9, p17, POLY9);
          fs[0] = FILT1 ? o[0] : 1'b1;
        end
      end

      // Channel 4 borrow
      if (b[3] != 3'd0) begin
        b[3] = b[3] - 3'd1;
        if (b[3] == 3'd0) begin
          if (J34) begin c[2] = audf[2] ^ 8'hFF; b[2] = 3'd0; end
          c[3] = audf[3] ^ 8'hFF;
          if (audc[3][7] || p5[0]) o[3] = audc[3][5] ? ~o[3] : poly_bit(audc[3], p4, p9, p17, POLY9);
          fs[1] = FILT2 ? o[1] : 1'b1;
        end
      end

      // Channel 1 borrow
      if (b[0] != 3'd0) begin
        b[0] = b[0] - 3'd1;
        if (b[0] == 3'd0) begin
          if (J12) begin
            c[1] = c[1] + 8'd1;
            if (c[1] == 8'd0 && b[1] == 3'd0) b[1] = 3'd1;
          end else begin
            c[0] = audf[0] ^ 8'hFF;
          end
          if (audc[0][7] || p5[0]) o[0] = audc[0][5] ? ~o[0] : poly_bit(audc[0], p4, p9, p17, POLY9);
        end
      end

      // Channel 2 borrow
      if (b[1] != 3'd0) begin
        b[1] = b[1] - 3'd1;
        if (b[1] == 3'd0) begin
          if (J12) begin c[0] = audf[0] ^ 8'hFF; b[0] = 3'd0; end
          c[1] = audf[1] ^ 8'hFF;
          if (audc[1][7] || p5[0]) o[1] = audc[1][5] ? ~o[1] : poly_bit(audc[1], p4, p9, p17, POLY9);
        end
      end

      for (int i = 0; i < 4; i++) begin cnt[i] <= c[i]; borrow[i] <= b[i]; end
      outb <= o;
      filt <= fs;
    end

    // poly counters and prescalers: run while SKCTL releases reset
    if (!running) begin
      p4 <= 4'h1; p5 <= 5'h01; p9 <= 9'h1FF; p17 <= 17'h1FFFF;
      pre28 <= 7'd0; pre114 <= 7'd0;
    end else if (step_en) begin
      p4 <= p4_n; p5 <= p5_n; p9 <= p9_n; p17 <= p17_n;
      pre28  <= trig28  ? 7'd0 : pre28  + 7'd1;
      pre114 <= trig114 ? 7'd0 : pre114 + 7'd1;
    end
  end

  //--------------------------------------------------------------------------
  // Output: sum of volumes of channels whose output is high
  //--------------------------------------------------------------------------
  wire [3:0] on = {
    outb[3]             | audc[3][4],
    outb[2]             | audc[2][4],
    (outb[1] ^ filt[1]) | audc[1][4],
    (outb[0] ^ filt[0]) | audc[0][4]
  };

  always_ff @(posedge clk) begin
    vol <= (on[0] ? {2'b00, audc[0][3:0]} : 6'd0) +
           (on[1] ? {2'b00, audc[1][3:0]} : 6'd0) +
           (on[2] ? {2'b00, audc[2][3:0]} : 6'd0) +
           (on[3] ? {2'b00, audc[3][3:0]} : 6'd0);
  end

  initial begin
    skctl = 8'h00; audctl = 8'h00; dataOut = 8'hFF; phi2_d = 1'b0; stimer = 1'b0;
    for (int i = 0; i < 4; i++) begin audf[i] = 8'h00; audc[i] = 8'h00; cnt[i] = 8'h00; borrow[i] = 3'd0; end
    outb = 4'b0000; filt = 2'b11; pre28 = 7'd0; pre114 = 7'd0;
    p4 = 4'h1; p5 = 5'h01; p9 = 9'h1FF; p17 = 17'h1FFFF; vol = 6'd0;
  end

endmodule

`default_nettype wire
