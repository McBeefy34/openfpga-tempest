//============================================================================
//  Spinner emulation for Tempest: turns the D-pad (and optionally a docked
//  controller's left stick) into the 4-bit rotary encoder count the game
//  reads. The knob is 72 counts per turn on the real cabinet.
//============================================================================
`default_nettype none

module spinner
(
  input  wire       clk,          // 49.5 MHz
  input  wire       left,
  input  wire       right,
  input  wire [1:0] speed,        // 0 slow, 1 medium, 2 fast, 3 very fast
  input  wire       reverse,
  input  wire       analog_en,
  input  wire [7:0] analog_x,     // 0x80 = centre
  output wire [3:0] pos
);

  // 1 ms tick
  reg [15:0] tick_div = 16'd0;
  wire tick = (tick_div == 16'd49499);
  always @(posedge clk) tick_div <= tick ? 16'd0 : tick_div + 16'd1;

  // rate in 1/256 count per ms:  12 -> 47/s, 25 -> 98/s, 41 -> 160/s, 64 -> 250/s
  reg [7:0] dpad_rate;
  always @(*) begin
    case (speed)
      2'd0:    dpad_rate = 8'd12;
      2'd1:    dpad_rate = 8'd25;
      2'd2:    dpad_rate = 8'd41;
      default: dpad_rate = 8'd64;
    endcase
  end

  // analog: deflection beyond a dead zone, full tilt ~ 1.5x the D-pad rate
  wire       a_neg = (analog_x < 8'h80);
  wire [7:0] a_mag = a_neg ? (8'h80 - analog_x) : (analog_x - 8'h80);
  wire [7:0] a_eff = (a_mag > 8'd16) ? (a_mag - 8'd16) : 8'd0;          // 0..112
  wire [15:0] a_rate_w = (a_eff * dpad_rate * 8'd3) >> 8;                 // ~1.3x at full tilt
  wire [7:0]  a_rate   = (a_rate_w > 16'd255) ? 8'd255 : a_rate_w[7:0];

  wire dir_cw  = right | (analog_en & ~a_neg & (a_eff != 0));
  wire dir_ccw = left  | (analog_en &  a_neg & (a_eff != 0));
  wire [7:0] rate = (left | right) ? dpad_rate : (analog_en ? a_rate : 8'd0);

  reg [11:0] acc = 12'd0;   // 4.8 fixed point position
  assign pos = acc[11:8];

  always @(posedge clk) begin
    if (tick && (dir_cw ^ dir_ccw)) begin
      if (dir_cw ^ reverse) acc <= acc + {4'd0, rate};
      else                  acc <= acc - {4'd0, rate};
    end
  end

endmodule

`default_nettype wire
