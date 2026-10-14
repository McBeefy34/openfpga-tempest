#
# Tempest core constraints
#
# PLL outputs:
#   general[0]  clk_sys     49.5 MHz    core logic
#   general[1]  clk_vid     18.5625 MHz pixel clock
#   general[2]  clk_vid_90  18.5625 MHz pixel clock, 90 degrees (to the scaler only)
#
# Every crossing between these domains goes through a synchroniser, a
# toggle handshake or the gray-coded loader FIFO, so they are declared
# asynchronous to each other.

set_clock_groups -asynchronous \
 -group { bridge_spiclk } \
 -group { clk_74a } \
 -group { clk_74b } \
 -group { ic|mp1|mf_pllbase_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk } \
 -group { ic|mp1|mf_pllbase_inst|altera_pll_i|general[1].gpll~PLL_OUTPUT_COUNTER|divclk \
          ic|mp1|mf_pllbase_inst|altera_pll_i|general[2].gpll~PLL_OUTPUT_COUNTER|divclk }
