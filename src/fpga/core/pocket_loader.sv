//============================================================================
//  Bridge -> core loader for the Tempest Pocket port.
//
//  The APF writes data slots as big-endian 32-bit words on clk_74a. Words
//  for the ROM (0x0xxxxxxx) and the high-score save (0x2xxxxxxx) cross into
//  the core clock through a small gray-coded asynchronous FIFO and come out
//  as byte writes.
//============================================================================
`default_nettype none

module pocket_loader
(
  input  wire        clk_74a,
  input  wire        bridge_wr,
  input  wire [31:0] bridge_addr,
  input  wire [31:0] bridge_wr_data,

  input  wire        clk,
  output reg         rom_wr,
  output reg  [14:0] rom_addr,
  output reg         ea_wr,
  output reg  [5:0]  ea_addr,
  output reg  [7:0]  data
);

  wire hit_rom = bridge_wr && (bridge_addr[31:28] == 4'h0) && (bridge_addr[27:15] == 13'd0);
  wire hit_ea  = bridge_wr && (bridge_addr[31:28] == 4'h2) && (bridge_addr[27:6]  == 22'd0);

  // {is_earom, word address, data}
  wire [45:0] fifo_din = {hit_ea, bridge_addr[14:2], bridge_wr_data};
  wire [45:0] fifo_dout;
  wire        fifo_empty;
  reg         fifo_rd;

  async_fifo #(.W(46), .AW(4)) fifo
  (
    .wclk  (clk_74a),
    .wr    (hit_rom | hit_ea),
    .din   (fifo_din),
    .rclk  (clk),
    .rd    (fifo_rd),
    .dout  (fifo_dout),
    .empty (fifo_empty)
  );

  // Serialise each word into four byte writes, most significant byte first
  reg [2:0]  phase = 3'd0;
  reg [31:0] word;
  reg [12:0] waddr;
  reg        wea;

  always @(posedge clk) begin
    fifo_rd <= 1'b0;
    rom_wr  <= 1'b0;
    ea_wr   <= 1'b0;

    if (phase == 3'd0) begin
      if (!fifo_empty && !fifo_rd) begin
        {wea, waddr, word} <= fifo_dout;
        fifo_rd <= 1'b1;
        phase   <= 3'd1;
      end
    end else begin
      data     <= word[31:24];
      word     <= {word[23:0], 8'h00};
      rom_addr <= {waddr, phase[1:0] - 2'd1};
      ea_addr  <= {waddr[3:0], phase[1:0] - 2'd1};
      rom_wr   <= ~wea;
      ea_wr    <=  wea;
      phase    <= (phase == 3'd4) ? 3'd0 : phase + 3'd1;
    end
  end

endmodule

//----------------------------------------------------------------------------
// Minimal asynchronous FIFO (first-word-fall-through), gray-coded pointers
//----------------------------------------------------------------------------
module async_fifo
#(
  parameter W  = 8,
  parameter AW = 4
)
(
  input  wire         wclk,
  input  wire         wr,
  input  wire [W-1:0] din,
  input  wire         rclk,
  input  wire         rd,
  output wire [W-1:0] dout,
  output wire         empty
);

  reg [W-1:0] mem [0:(1<<AW)-1];

  reg [AW:0] wbin = '0, wgray = '0;
  reg [AW:0] rbin = '0, rgray = '0;
  reg [AW:0] wgray_r1 = '0, wgray_r2 = '0;   // write pointer in read domain

  always @(posedge wclk) begin
    if (wr) begin
      mem[wbin[AW-1:0]] <= din;
      wbin  <= wbin + 1'b1;
      wgray <= (wbin + 1'b1) ^ ((wbin + 1'b1) >> 1);
    end
  end

  always @(posedge rclk) begin
    wgray_r1 <= wgray;
    wgray_r2 <= wgray_r1;
    if (rd && !empty) begin
      rbin  <= rbin + 1'b1;
      rgray <= (rbin + 1'b1) ^ ((rbin + 1'b1) >> 1);
    end
  end

  assign empty = (rgray == wgray_r2);
  assign dout  = mem[rbin[AW-1:0]];

endmodule

`default_nettype wire
