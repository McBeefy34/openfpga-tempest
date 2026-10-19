//============================================================================
//  Double-buffered 512 x 512 x 3-bit frame buffer for the Pocket port.
//
//  The rasterizer draws into the back buffer (core clock). At the end of
//  each pass of the display list the buffers are swapped at the next video
//  vertical blank, and the new back buffer is cleared before drawing
//  resumes. While that happens 'busy' holds the vector generator.
//
//  Video timing (18.5625 MHz pixel clock):
//    576 x 537 total, 512 x 512 active -> 60.01 Hz
//============================================================================
`default_nettype none

module vector_fb
(
  input  wire        clk,
  input  wire        reset,

  input  wire        px_we,
  input  wire [17:0] px_addr,      // {y[8:0], x[8:0]}
  input  wire [2:0]  px_rgb,

  input  wire        frame_end,    // pulse: display list pass complete
  input  wire        drain_idle,   // no lines queued or in the rasterizer
  output wire        busy,

  input  wire        clk_vid,
  input  wire        dbg_en,       // draw controller stick values as bars
  input  wire [63:0] dbg_joy,      // {cont2_joy, cont1_joy}, any clock domain
  output reg  [23:0] vid_rgb,
  output reg         vid_de,
  output reg         vid_hs,
  output reg         vid_vs
);

  localparam H_TOTAL = 576, H_START = 40, V_TOTAL = 537, V_START = 16, ACTIVE = 512;

  //--------------------------------------------------------------------------
  // Swap handshake. The video side owns 'front' (== ack toggle).
  //--------------------------------------------------------------------------
  reg       req_tgl = 1'b0;          // clk domain
  reg       ack_tgl = 1'b0;          // clk_vid domain, also the front buffer index
  reg [2:0] ack_s   = 3'b000;        // ack synchronised into clk
  reg [2:0] req_s   = 3'b000;        // req synchronised into clk_vid

  always @(posedge clk)     ack_s <= {ack_s[1:0], ack_tgl};
  always @(posedge clk_vid) req_s <= {req_s[1:0], req_tgl};

  wire front_s = ack_s[2];
  wire back    = ~front_s;

  localparam ST_IDLE = 2'd0, ST_DRAIN = 2'd1, ST_SWAP = 2'd2, ST_CLEAR = 2'd3;
  reg [1:0]  st = ST_IDLE;
  reg [2:0]  drain_cnt;
  reg [17:0] clr_addr;

  assign busy = (st != ST_IDLE);

  always @(posedge clk) begin
    if (reset) begin
      st <= ST_IDLE;
    end else begin
      case (st)
        ST_IDLE:  if (frame_end) begin
                    st        <= ST_DRAIN;
                    drain_cnt <= 3'd0;
                  end
        ST_DRAIN: if (drain_idle) begin
                    drain_cnt <= drain_cnt + 3'd1;
                    if (drain_cnt == 3'd7) begin
                      req_tgl <= ~req_tgl;
                      st      <= ST_SWAP;
                    end
                  end else begin
                    drain_cnt <= 3'd0;
                  end
        ST_SWAP:  if (front_s == req_tgl) begin
                    clr_addr <= 18'd0;
                    st       <= ST_CLEAR;
                  end
        ST_CLEAR: begin
                    clr_addr <= clr_addr + 18'd1;
                    if (clr_addr == 18'h3FFFF) st <= ST_IDLE;
                  end
      endcase
    end
  end

  wire        w_en   = (st == ST_CLEAR) | (px_we & (st != ST_SWAP));
  wire [17:0] w_addr = (st == ST_CLEAR) ? clr_addr : px_addr;
  wire [2:0]  w_data = (st == ST_CLEAR) ? 3'b000   : px_rgb;

  //--------------------------------------------------------------------------
  // Buffers: write port on clk, read port on clk_vid
  //--------------------------------------------------------------------------
  reg [2:0] buf_a [0:262143];
  reg [2:0] buf_b [0:262143];
  reg [2:0] q_a, q_b;
  wire [17:0] r_addr;

  always @(posedge clk) if (w_en & ~back) buf_a[w_addr] <= w_data;
  always @(posedge clk) if (w_en &  back) buf_b[w_addr] <= w_data;
  always @(posedge clk_vid) q_a <= buf_a[r_addr];
  always @(posedge clk_vid) q_b <= buf_b[r_addr];

  //--------------------------------------------------------------------------
  // Video timing
  //--------------------------------------------------------------------------
  reg [9:0] hcnt = 10'd0;
  reg [9:0] vcnt = 10'd0;

  always @(posedge clk_vid) begin
    if (hcnt == H_TOTAL-1) begin
      hcnt <= 10'd0;
      vcnt <= (vcnt == V_TOTAL-1) ? 10'd0 : vcnt + 10'd1;
    end else begin
      hcnt <= hcnt + 10'd1;
    end

    // flip the front buffer just after the last active line
    if (hcnt == 10'd0 && vcnt == V_START + ACTIVE && req_s[2] != ack_tgl)
      ack_tgl <= req_s[2];
  end

  wire       h_act = (hcnt >= H_START) && (hcnt < H_START + ACTIVE);
  wire       v_act = (vcnt >= V_START) && (vcnt < V_START + ACTIVE);
  localparam [9:0] H0 = H_START, V0 = V_START;
  wire [9:0] hx    = hcnt - H0;
  wire [9:0] vy    = vcnt - V0;
  assign r_addr = {vy[8:0], hx[8:0]};

  // One register stage lines the controls up with the RAM output (q_a/q_b
  // hold the data for the address presented one clock earlier); a second
  // registers the outputs.
  reg de_p, hs_p, vs_p, front_p;
  reg [2:0] drow_p;
  always @(posedge clk_vid) drow_p <= drow;

  // Stick debug overlay: eight rows at the top left, one per axis
  // (cont1 lx, ly, rx, ry, then cont2 lx, ly, rx, and finally player 1's
  // controller type x 32). Bar length = raw value (0..255),
  // red ticks at 0, 128 (centre) and 255. Values are slow-changing, so a
  // double register is enough to bring them into this clock domain.
  reg  [63:0] dbg_s1, dbg_s2;
  reg         dbg_en_s1, dbg_en_s2;
  reg         dbg_on, dbg_bar, dbg_tick;
  wire [9:0]  dx   = hx - 10'd16;
  wire [9:0]  dyr  = vy - 10'd8;
  wire [2:0]  drow = dyr[6:4];                          // 16-pixel row pitch
  wire        d_in = dbg_en_s2 && (vy >= 10'd8) && (vy < 10'd136) && (dyr[3:0] < 4'd10)
                     && (hx >= 10'd14) && (hx < 10'd274);
  wire [7:0]  dval = dbg_s2[{drow, 3'b000} +: 8];
  always @(posedge clk_vid) begin
    dbg_s1 <= dbg_joy;   dbg_s2 <= dbg_s1;
    dbg_en_s1 <= dbg_en; dbg_en_s2 <= dbg_en_s1;
    dbg_on   <= d_in;
    dbg_tick <= d_in && (dx == 10'd0 || dx == 10'd128 || dx == 10'd255 || hx == 10'd14 || hx == 10'd15);
    dbg_bar  <= d_in && (hx >= 10'd16) && (dx[8:0] <= {1'b0, dval}) && (dyr[3:0] >= 4'd2) && (dyr[3:0] < 4'd8);
  end

  always @(posedge clk_vid) begin
    de_p    <= h_act & v_act;
    hs_p    <= (hcnt == 10'd3);
    vs_p    <= (hcnt == 10'd0) && (vcnt == 10'd0);
    front_p <= ack_tgl;

    vid_de  <= de_p;
    vid_hs  <= hs_p;
    vid_vs  <= vs_p;
    if (de_p && dbg_on && (dbg_tick || dbg_bar)) begin
      vid_rgb <= dbg_tick ? 24'hFF0000 : (drow_p[2] ? 24'h00FFFF : 24'hFFFFFF);
    end else if (de_p) begin
      // buffer 0 = A, 1 = B
      vid_rgb <= front_p ? {{8{q_b[2]}}, {8{q_b[1]}}, {8{q_b[0]}}}
                         : {{8{q_a[2]}}, {8{q_a[1]}}, {8{q_a[0]}}};
    end else begin
      vid_rgb <= 24'h000000;
    end
  end

endmodule

`default_nettype wire
