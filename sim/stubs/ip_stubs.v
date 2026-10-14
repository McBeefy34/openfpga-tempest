// Simulation / lint stand-ins for Altera IP used by the Pocket shell.
module mf_pllbase (input wire refclk, input wire rst,
                   output wire outclk_0, output wire outclk_1, output wire outclk_2,
                   output wire outclk_3, output wire outclk_4, output wire locked);
  assign outclk_0 = refclk; assign outclk_1 = refclk; assign outclk_2 = refclk;
  assign outclk_3 = 1'b0; assign outclk_4 = 1'b0; assign locked = 1'b1;
endmodule
module mf_datatable (input wire [9:0] address_a, input wire [9:0] address_b,
                     input wire clock_a, input wire clock_b,
                     input wire [31:0] data_a, input wire [31:0] data_b,
                     input wire wren_a, input wire wren_b,
                     output reg [31:0] q_a, output reg [31:0] q_b);
  reg [31:0] m [0:1023];
  always @(posedge clock_a) begin if (wren_a) m[address_a] <= data_a; q_a <= m[address_a]; end
  always @(posedge clock_b) begin if (wren_b) m[address_b] <= data_b; q_b <= m[address_b]; end
endmodule
