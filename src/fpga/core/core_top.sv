//
// User core top-level
//
// Instantiated by the real top-level: apf_top
//

`default_nettype none

module core_top (

//
// physical connections
//

///////////////////////////////////////////////////
// clock inputs 74.25mhz. not phase aligned, so treat these domains as asynchronous

input   wire            clk_74a, // mainclk1
input   wire            clk_74b, // mainclk1 

///////////////////////////////////////////////////
// cartridge interface
// switches between 3.3v and 5v mechanically
// output enable for multibit translators controlled by pic32

// GBA AD[15:8]
inout   wire    [7:0]   cart_tran_bank2,
output  wire            cart_tran_bank2_dir,

// GBA AD[7:0]
inout   wire    [7:0]   cart_tran_bank3,
output  wire            cart_tran_bank3_dir,

// GBA A[23:16]
inout   wire    [7:0]   cart_tran_bank1,
output  wire            cart_tran_bank1_dir,

// GBA [7] PHI#
// GBA [6] WR#
// GBA [5] RD#
// GBA [4] CS1#/CS#
//     [3:0] unwired
inout   wire    [7:4]   cart_tran_bank0,
output  wire            cart_tran_bank0_dir,

// GBA CS2#/RES#
inout   wire            cart_tran_pin30,
output  wire            cart_tran_pin30_dir,
// when GBC cart is inserted, this signal when low or weak will pull GBC /RES low with a special circuit
// the goal is that when unconfigured, the FPGA weak pullups won't interfere.
// thus, if GBC cart is inserted, FPGA must drive this high in order to let the level translators
// and general IO drive this pin.
output  wire            cart_pin30_pwroff_reset,

// GBA IRQ/DRQ
inout   wire            cart_tran_pin31,
output  wire            cart_tran_pin31_dir,

// infrared
input   wire            port_ir_rx,
output  wire            port_ir_tx,
output  wire            port_ir_rx_disable, 

// GBA link port
inout   wire            port_tran_si,
output  wire            port_tran_si_dir,
inout   wire            port_tran_so,
output  wire            port_tran_so_dir,
inout   wire            port_tran_sck,
output  wire            port_tran_sck_dir,
inout   wire            port_tran_sd,
output  wire            port_tran_sd_dir,
 
///////////////////////////////////////////////////
// cellular psram 0 and 1, two chips (64mbit x2 dual die per chip)

output  wire    [21:16] cram0_a,
inout   wire    [15:0]  cram0_dq,
input   wire            cram0_wait,
output  wire            cram0_clk,
output  wire            cram0_adv_n,
output  wire            cram0_cre,
output  wire            cram0_ce0_n,
output  wire            cram0_ce1_n,
output  wire            cram0_oe_n,
output  wire            cram0_we_n,
output  wire            cram0_ub_n,
output  wire            cram0_lb_n,

output  wire    [21:16] cram1_a,
inout   wire    [15:0]  cram1_dq,
input   wire            cram1_wait,
output  wire            cram1_clk,
output  wire            cram1_adv_n,
output  wire            cram1_cre,
output  wire            cram1_ce0_n,
output  wire            cram1_ce1_n,
output  wire            cram1_oe_n,
output  wire            cram1_we_n,
output  wire            cram1_ub_n,
output  wire            cram1_lb_n,

///////////////////////////////////////////////////
// sdram, 512mbit 16bit

output  wire    [12:0]  dram_a,
output  wire    [1:0]   dram_ba,
inout   wire    [15:0]  dram_dq,
output  wire    [1:0]   dram_dqm,
output  wire            dram_clk,
output  wire            dram_cke,
output  wire            dram_ras_n,
output  wire            dram_cas_n,
output  wire            dram_we_n,

///////////////////////////////////////////////////
// sram, 1mbit 16bit

output  wire    [16:0]  sram_a,
inout   wire    [15:0]  sram_dq,
output  wire            sram_oe_n,
output  wire            sram_we_n,
output  wire            sram_ub_n,
output  wire            sram_lb_n,

///////////////////////////////////////////////////
// vblank driven by dock for sync in a certain mode

input   wire            vblank,

///////////////////////////////////////////////////
// i/o to 6515D breakout usb uart

output  wire            dbg_tx,
input   wire            dbg_rx,

///////////////////////////////////////////////////
// i/o pads near jtag connector user can solder to

output  wire            user1,
input   wire            user2,

///////////////////////////////////////////////////
// RFU internal i2c bus 

inout   wire            aux_sda,
output  wire            aux_scl,

///////////////////////////////////////////////////
// RFU, do not use
output  wire            vpll_feed,


//
// logical connections
//

///////////////////////////////////////////////////
// video, audio output to scaler
output  wire    [23:0]  video_rgb,
output  wire            video_rgb_clock,
output  wire            video_rgb_clock_90,
output  wire            video_de,
output  wire            video_skip,
output  wire            video_vs,
output  wire            video_hs,
    
output  wire            audio_mclk,
input   wire            audio_adc,
output  wire            audio_dac,
output  wire            audio_lrck,

///////////////////////////////////////////////////
// bridge bus connection
// synchronous to clk_74a
output  wire            bridge_endian_little,
input   wire    [31:0]  bridge_addr,
input   wire            bridge_rd,
output  reg     [31:0]  bridge_rd_data,
input   wire            bridge_wr,
input   wire    [31:0]  bridge_wr_data,

///////////////////////////////////////////////////
// controller data
// 
// key bitmap:
//   [0]    dpad_up
//   [1]    dpad_down
//   [2]    dpad_left
//   [3]    dpad_right
//   [4]    face_a
//   [5]    face_b
//   [6]    face_x
//   [7]    face_y
//   [8]    trig_l1
//   [9]    trig_r1
//   [10]   trig_l2
//   [11]   trig_r2
//   [12]   trig_l3
//   [13]   trig_r3
//   [14]   face_select
//   [15]   face_start
//   [31:28] type
// joy values - unsigned
//   [ 7: 0] lstick_x
//   [15: 8] lstick_y
//   [23:16] rstick_x
//   [31:24] rstick_y
// trigger values - unsigned
//   [ 7: 0] ltrig
//   [15: 8] rtrig
//
input   wire    [31:0]  cont1_key,
input   wire    [31:0]  cont2_key,
input   wire    [31:0]  cont3_key,
input   wire    [31:0]  cont4_key,
input   wire    [31:0]  cont1_joy,
input   wire    [31:0]  cont2_joy,
input   wire    [31:0]  cont3_joy,
input   wire    [31:0]  cont4_joy,
input   wire    [15:0]  cont1_trig,
input   wire    [15:0]  cont2_trig,
input   wire    [15:0]  cont3_trig,
input   wire    [15:0]  cont4_trig
    
);

// not using the IR port, so turn off both the LED, and
// disable the receive circuit to save power
assign port_ir_tx = 0;
assign port_ir_rx_disable = 1;

// bridge endianness
assign bridge_endian_little = 0;

// cart is unused, so set all level translators accordingly
// directions are 0:IN, 1:OUT
assign cart_tran_bank3 = 8'hzz;
assign cart_tran_bank3_dir = 1'b0;
assign cart_tran_bank2 = 8'hzz;
assign cart_tran_bank2_dir = 1'b0;
assign cart_tran_bank1 = 8'hzz;
assign cart_tran_bank1_dir = 1'b0;
assign cart_tran_bank0 = 4'hf;
assign cart_tran_bank0_dir = 1'b1;
assign cart_tran_pin30 = 1'b0;      // reset or cs2, we let the hw control it by itself
assign cart_tran_pin30_dir = 1'bz;
assign cart_pin30_pwroff_reset = 1'b0;  // hardware can control this
assign cart_tran_pin31 = 1'bz;      // input
assign cart_tran_pin31_dir = 1'b0;  // input

// link port is unused, set to input only to be safe
// each bit may be bidirectional in some applications
assign port_tran_so = 1'bz;
assign port_tran_so_dir = 1'b0;     // SO is output only
assign port_tran_si = 1'bz;
assign port_tran_si_dir = 1'b0;     // SI is input only
assign port_tran_sck = 1'bz;
assign port_tran_sck_dir = 1'b0;    // clock direction can change
assign port_tran_sd = 1'bz;
assign port_tran_sd_dir = 1'b0;     // SD is input and not used

// tie off the rest of the pins we are not using
assign cram0_a = 'h0;
assign cram0_dq = {16{1'bZ}};
assign cram0_clk = 0;
assign cram0_adv_n = 1;
assign cram0_cre = 0;
assign cram0_ce0_n = 1;
assign cram0_ce1_n = 1;
assign cram0_oe_n = 1;
assign cram0_we_n = 1;
assign cram0_ub_n = 1;
assign cram0_lb_n = 1;

assign cram1_a = 'h0;
assign cram1_dq = {16{1'bZ}};
assign cram1_clk = 0;
assign cram1_adv_n = 1;
assign cram1_cre = 0;
assign cram1_ce0_n = 1;
assign cram1_ce1_n = 1;
assign cram1_oe_n = 1;
assign cram1_we_n = 1;
assign cram1_ub_n = 1;
assign cram1_lb_n = 1;

assign dram_a = 'h0;
assign dram_ba = 'h0;
assign dram_dq = {16{1'bZ}};
assign dram_dqm = 'h0;
assign dram_clk = 'h0;
assign dram_cke = 'h0;
assign dram_ras_n = 'h1;
assign dram_cas_n = 'h1;
assign dram_we_n = 'h1;

assign sram_a = 'h0;
assign sram_dq = {16{1'bZ}};
assign sram_oe_n  = 1;
assign sram_we_n  = 1;
assign sram_ub_n  = 1;
assign sram_lb_n  = 1;

assign dbg_tx = 1'bZ;
assign user1 = 1'bZ;
assign aux_scl = 1'bZ;
assign vpll_feed = 1'bZ;


wire [31:0] ea_bridge_word;   // EAROM contents for the save slot
wire        clk_sys;          // 49.5 MHz core clock
wire        clk_vid;          // 18.5625 MHz pixel clock
wire        clk_vid_90;
wire        pll_core_locked;
wire        pll_core_locked_s;

// for bridge write data, we just broadcast it to all bus devices
// for bridge read data, we have to mux it
// add your own devices here
always @(*) begin
    casex(bridge_addr)
    default: begin
        bridge_rd_data <= 0;
    end
    32'h2xxxxxxx: begin
        // high-score save slot (EAROM), read by the APF when saving
        bridge_rd_data <= ea_bridge_word;
    end
    32'hF8xxxxxx: begin
        bridge_rd_data <= cmd_bridge_rd_data;
    end
    endcase
end


//
// host/target command handler
//
    wire            reset_n;                // driven by host commands, can be used as core-wide reset
    wire    [31:0]  cmd_bridge_rd_data;
    
// bridge host commands
// synchronous to clk_74a
    wire            status_boot_done = pll_core_locked_s;
    wire            status_setup_done = pll_core_locked_s; // rising edge triggers a target command
    wire            status_running = reset_n; // we are running as soon as reset_n goes high

    wire            dataslot_requestread;
    wire    [15:0]  dataslot_requestread_id;
    wire            dataslot_requestread_ack = 1;
    wire            dataslot_requestread_ok = 1;

    wire            dataslot_requestwrite;
    wire    [15:0]  dataslot_requestwrite_id;
    wire    [31:0]  dataslot_requestwrite_size;
    wire            dataslot_requestwrite_ack = 1;
    wire            dataslot_requestwrite_ok = 1;

    wire            dataslot_update;
    wire    [15:0]  dataslot_update_id;
    wire    [31:0]  dataslot_update_size;
    
    wire            dataslot_allcomplete;

    wire     [31:0] rtc_epoch_seconds;
    wire     [31:0] rtc_date_bcd;
    wire     [31:0] rtc_time_bcd;
    wire            rtc_valid;

    wire            savestate_supported;
    wire    [31:0]  savestate_addr;
    wire    [31:0]  savestate_size;
    wire    [31:0]  savestate_maxloadsize;

    wire            savestate_start;
    wire            savestate_start_ack;
    wire            savestate_start_busy;
    wire            savestate_start_ok;
    wire            savestate_start_err;

    wire            savestate_load;
    wire            savestate_load_ack;
    wire            savestate_load_busy;
    wire            savestate_load_ok;
    wire            savestate_load_err;
    
    wire            osnotify_inmenu;

// bridge target commands
// synchronous to clk_74a

    reg             target_dataslot_read;       
    reg             target_dataslot_write;
    reg             target_dataslot_getfile;    // require additional param/resp structs to be mapped
    reg             target_dataslot_openfile;   // require additional param/resp structs to be mapped
    
    wire            target_dataslot_ack;        
    wire            target_dataslot_done;
    wire    [2:0]   target_dataslot_err;

    reg     [15:0]  target_dataslot_id;
    reg     [31:0]  target_dataslot_slotoffset;
    reg     [31:0]  target_dataslot_bridgeaddr;
    reg     [31:0]  target_dataslot_length;
    
    wire    [31:0]  target_buffer_param_struct; // to be mapped/implemented when using some Target commands
    wire    [31:0]  target_buffer_resp_struct;  // to be mapped/implemented when using some Target commands
    
// bridge data slot access
// synchronous to clk_74a

    wire    [9:0]   datatable_addr;
    wire            datatable_wren;
    wire    [31:0]  datatable_data;
    wire    [31:0]  datatable_q;

core_bridge_cmd icb (

    .clk                ( clk_74a ),
    .reset_n            ( reset_n ),

    .bridge_endian_little   ( bridge_endian_little ),
    .bridge_addr            ( bridge_addr ),
    .bridge_rd              ( bridge_rd ),
    .bridge_rd_data         ( cmd_bridge_rd_data ),
    .bridge_wr              ( bridge_wr ),
    .bridge_wr_data         ( bridge_wr_data ),
    
    .status_boot_done       ( status_boot_done ),
    .status_setup_done      ( status_setup_done ),
    .status_running         ( status_running ),

    .dataslot_requestread       ( dataslot_requestread ),
    .dataslot_requestread_id    ( dataslot_requestread_id ),
    .dataslot_requestread_ack   ( dataslot_requestread_ack ),
    .dataslot_requestread_ok    ( dataslot_requestread_ok ),

    .dataslot_requestwrite      ( dataslot_requestwrite ),
    .dataslot_requestwrite_id   ( dataslot_requestwrite_id ),
    .dataslot_requestwrite_size ( dataslot_requestwrite_size ),
    .dataslot_requestwrite_ack  ( dataslot_requestwrite_ack ),
    .dataslot_requestwrite_ok   ( dataslot_requestwrite_ok ),

    .dataslot_update            ( dataslot_update ),
    .dataslot_update_id         ( dataslot_update_id ),
    .dataslot_update_size       ( dataslot_update_size ),
    
    .dataslot_allcomplete   ( dataslot_allcomplete ),

    .rtc_epoch_seconds      ( rtc_epoch_seconds ),
    .rtc_date_bcd           ( rtc_date_bcd ),
    .rtc_time_bcd           ( rtc_time_bcd ),
    .rtc_valid              ( rtc_valid ),
    
    .savestate_supported    ( savestate_supported ),
    .savestate_addr         ( savestate_addr ),
    .savestate_size         ( savestate_size ),
    .savestate_maxloadsize  ( savestate_maxloadsize ),

    .savestate_start        ( savestate_start ),
    .savestate_start_ack    ( savestate_start_ack ),
    .savestate_start_busy   ( savestate_start_busy ),
    .savestate_start_ok     ( savestate_start_ok ),
    .savestate_start_err    ( savestate_start_err ),

    .savestate_load         ( savestate_load ),
    .savestate_load_ack     ( savestate_load_ack ),
    .savestate_load_busy    ( savestate_load_busy ),
    .savestate_load_ok      ( savestate_load_ok ),
    .savestate_load_err     ( savestate_load_err ),

    .osnotify_inmenu        ( osnotify_inmenu ),
    
    .target_dataslot_read       ( target_dataslot_read ),
    .target_dataslot_write      ( target_dataslot_write ),
    .target_dataslot_getfile    ( target_dataslot_getfile ),
    .target_dataslot_openfile   ( target_dataslot_openfile ),
    
    .target_dataslot_ack        ( target_dataslot_ack ),
    .target_dataslot_done       ( target_dataslot_done ),
    .target_dataslot_err        ( target_dataslot_err ),

    .target_dataslot_id         ( target_dataslot_id ),
    .target_dataslot_slotoffset ( target_dataslot_slotoffset ),
    .target_dataslot_bridgeaddr ( target_dataslot_bridgeaddr ),
    .target_dataslot_length     ( target_dataslot_length ),

    .target_buffer_param_struct ( target_buffer_param_struct ),
    .target_buffer_resp_struct  ( target_buffer_resp_struct ),
    
    .datatable_addr         ( datatable_addr ),
    .datatable_wren         ( datatable_wren ),
    .datatable_data         ( datatable_data ),
    .datatable_q            ( datatable_q )

);



////////////////////////////////////////////////////////////////////////////////////////



////////////////////////////////////////////////////////////////////////////////////////
//
//  Atari Tempest
//
////////////////////////////////////////////////////////////////////////////////////////

synch_3 s01(pll_core_locked, pll_core_locked_s, clk_74a);

mf_pllbase mp1 (
    .refclk         ( clk_74a ),
    .rst            ( 0 ),
    .outclk_0       ( clk_sys ),
    .outclk_1       ( clk_vid ),
    .outclk_2       ( clk_vid_90 ),
    .outclk_3       ( ),
    .outclk_4       ( ),
    .locked         ( pll_core_locked )
);

//--------------------------------------------------------------------------------------
// Settings written by the Pocket menu (interact.json), clk_74a domain
//--------------------------------------------------------------------------------------
    reg  [1:0]  set_coinage    = 2'd0;   // DSW1[1:0]: 0 1C/1C, 1 2C/1C, 3 1C/2C, 2 free play
    reg  [1:0]  set_lives      = 2'd0;   // DSW2[7:6]: 0 3, 1 4, 2 5, 3 2
    reg  [2:0]  set_bonus      = 3'd0;   // DSW2[5:3]
    reg  [1:0]  set_language   = 2'd0;   // DSW2[2:1]
    reg         set_mincredit  = 1'b0;   // DSW2[0]
    reg  [1:0]  set_difficulty = 2'd3;   // IN2[1:0]: 2 easy, 3 medium1, 0 medium2, 1 hard
    reg         set_rating     = 1'b1;   // IN2[2]:  1 = 1,3,5,7,9  0 = tied to high score
    reg  [1:0]  set_speed      = 2'd1;
    reg         set_reverse    = 1'b0;
    reg         set_analog     = 1'b0;
    reg         set_flip_x     = 1'b0;
    reg         set_flip_y     = 1'b0;
    reg         set_service    = 1'b0;
    reg  [23:0] menu_reset_cnt = 24'd0; // held reset after "Reset" in the menu

always @(posedge clk_74a) begin
    if (menu_reset_cnt != 0) menu_reset_cnt <= menu_reset_cnt - 24'd1;
    if (bridge_wr && bridge_addr[31:8] == 24'h800000) begin
        case (bridge_addr[7:0])
        8'h00: if (bridge_wr_data[0]) menu_reset_cnt <= 24'd7_425_000;   // 100 ms
        8'h04: set_coinage    <= bridge_wr_data[1:0];
        8'h08: set_lives      <= bridge_wr_data[1:0];
        8'h0C: set_bonus      <= bridge_wr_data[2:0];
        8'h10: set_language   <= bridge_wr_data[1:0];
        8'h14: set_mincredit  <= bridge_wr_data[0];
        8'h18: set_difficulty <= bridge_wr_data[1:0];
        8'h1C: set_rating     <= bridge_wr_data[0];
        8'h20: set_speed      <= bridge_wr_data[1:0];
        8'h24: set_reverse    <= bridge_wr_data[0];
        8'h28: set_analog     <= bridge_wr_data[0];
        8'h2C: set_flip_x     <= bridge_wr_data[0];
        8'h30: set_flip_y     <= bridge_wr_data[0];
        8'h34: set_service    <= bridge_wr_data[0];
        default: ;
        endcase
    end
end

    // These change rarely (menu), so plain double registering is enough.
    wire [7:0]  dsw1_74a = {3'b000, 1'b0, 2'b00, set_coinage};
    wire [7:0]  dsw2_74a = {set_lives, set_bonus, set_language, set_mincredit};
    wire [2:0]  in2_74a  = {set_rating, set_difficulty};
    wire [7:0]  opt_74a  = {set_speed, set_reverse, set_analog, set_flip_x, set_flip_y, set_service, 1'b0};

    reg  [7:0]  dsw1_s1, dsw1_s, dsw2_s1, dsw2_s, opt_s1, opt_s;
    reg  [2:0]  in2_s1, in2_s;
always @(posedge clk_sys) begin
    dsw1_s1 <= dsw1_74a;  dsw1_s <= dsw1_s1;
    dsw2_s1 <= dsw2_74a;  dsw2_s <= dsw2_s1;
    in2_s1  <= in2_74a;   in2_s  <= in2_s1;
    opt_s1  <= opt_74a;   opt_s  <= opt_s1;
end

//--------------------------------------------------------------------------------------
// Reset: hold the machine until the PLL is locked, the host has released
// reset and every data slot (ROM, save) has been loaded
//--------------------------------------------------------------------------------------
    wire        run_74a = reset_n & dataslot_allcomplete & (menu_reset_cnt == 0);
    reg  [2:0]  run_s = 3'b000;
    reg         core_reset = 1'b1;
always @(posedge clk_sys) begin
    run_s      <= {run_s[1:0], run_74a};
    core_reset <= ~run_s[2];
end

//--------------------------------------------------------------------------------------
// Controls
//--------------------------------------------------------------------------------------
    reg  [15:0] key_s1, key_s;
    reg  [7:0]  joyx_s1, joyx_s;
always @(posedge clk_sys) begin
    key_s1  <= cont1_key[15:0];  key_s  <= key_s1;
    joyx_s1 <= cont1_joy[7:0];   joyx_s <= joyx_s1;
end

    wire btn_left   = key_s[2];
    wire btn_right  = key_s[3];
    wire btn_fire   = key_s[4] | key_s[6];    // A or X
    wire btn_zap    = key_s[5] | key_s[7];    // B or Y
    wire btn_start2 = key_s[8];               // L
    wire btn_coin   = key_s[14];              // Select
    wire btn_start1 = key_s[15];              // Start

    wire [3:0] knob;
spinner spin (
    .clk        ( clk_sys ),
    .left       ( btn_left ),
    .right      ( btn_right ),
    .speed      ( opt_s[7:6] ),
    .reverse    ( opt_s[5] ),
    .analog_en  ( opt_s[4] ),
    .analog_x   ( joyx_s ),
    .pos        ( knob )
);

//--------------------------------------------------------------------------------------
// ROM / save loading
//--------------------------------------------------------------------------------------
    wire        dl_rom_wr, dl_ea_wr;
    wire [14:0] dl_rom_addr;
    wire [5:0]  dl_ea_addr;
    wire [7:0]  dl_data;

pocket_loader loader (
    .clk_74a        ( clk_74a ),
    .bridge_wr      ( bridge_wr ),
    .bridge_addr    ( bridge_addr ),
    .bridge_wr_data ( bridge_wr_data ),
    .clk            ( clk_sys ),
    .rom_wr         ( dl_rom_wr ),
    .rom_addr       ( dl_rom_addr ),
    .ea_wr          ( dl_ea_wr ),
    .ea_addr        ( dl_ea_addr ),
    .data           ( dl_data )
);

//--------------------------------------------------------------------------------------
// The machine
//--------------------------------------------------------------------------------------
    wire [23:0] t_rgb;
    wire        t_de, t_hs, t_vs;
    wire [15:0] t_audio;
    wire        ea_dirty;

tempest_top tempest (
    .clk        ( clk_sys ),
    .reset      ( core_reset ),

    .dl_wr      ( dl_rom_wr ),
    .dl_addr    ( dl_rom_addr ),
    .dl_data    ( dl_data ),

    .ea_dl_wr   ( dl_ea_wr ),
    .ea_dl_addr ( dl_ea_addr ),
    .ea_dl_data ( dl_data ),
    .ea_rd_word ( bridge_addr[5:2] ),
    .ea_rd_data ( ea_bridge_word ),
    .ea_dirty   ( ea_dirty ),

    .coin       ( btn_coin ),
    .start1     ( btn_start1 ),
    .start2     ( btn_start2 ),
    .fire       ( btn_fire ),
    .zap        ( btn_zap ),
    .service    ( opt_s[1] ),
    .knob       ( knob ),

    .dsw1       ( dsw1_s ),
    .dsw2       ( dsw2_s ),
    .in2_dip    ( in2_s ),

    .flip_x     ( opt_s[3] ),
    .flip_y     ( opt_s[2] ),

    .clk_vid    ( clk_vid ),
    .vid_rgb    ( t_rgb ),
    .vid_de     ( t_de ),
    .vid_hs     ( t_hs ),
    .vid_vs     ( t_vs ),

    .audio      ( t_audio )
);

assign video_rgb_clock    = clk_vid;
assign video_rgb_clock_90 = clk_vid_90;
assign video_rgb          = t_rgb;
assign video_de           = t_de;
assign video_skip         = 1'b0;
assign video_vs           = t_vs;
assign video_hs           = t_hs;

//--------------------------------------------------------------------------------------
// High-score saving. The Pocket only writes a nonvolatile slot back to a file
// it has loaded, so the core asks for the save itself (target_dataslot_write)
// two seconds after the game last wrote its EAROM, when the menu opens, and
// once shortly after boot so the file exists.
//--------------------------------------------------------------------------------------
    wire        ea_dirty_s, inmenu_s;
synch_3 s02(ea_dirty, ea_dirty_s, clk_74a);
synch_3 s03(osnotify_inmenu, inmenu_s, clk_74a);
    reg         ea_dirty_d = 1'b0, inmenu_d = 1'b0;
    reg         nv_pending = 1'b0;
    reg         nv_loaded  = 1'b0;
    reg  [27:0] nv_timer   = 28'd0;
    reg  [28:0] boot_timer = 29'd0;
    reg  [1:0]  nv_state   = 2'd0;
    localparam  NV_SETTLE  = 28'd148_500_000;   // 2 s at 74.25 MHz
    localparam  NV_BOOT    = 29'd371_250_000;   // 5 s

initial begin
    target_dataslot_read     = 1'b0;
    target_dataslot_write    = 1'b0;
    target_dataslot_getfile  = 1'b0;
    target_dataslot_openfile = 1'b0;
end

always @(posedge clk_74a) begin
    ea_dirty_d <= ea_dirty_s;
    inmenu_d   <= inmenu_s;
    target_dataslot_read       <= 1'b0;
    target_dataslot_getfile    <= 1'b0;
    target_dataslot_openfile   <= 1'b0;
    target_dataslot_id         <= 16'd1;
    target_dataslot_slotoffset <= 32'd0;
    target_dataslot_bridgeaddr <= 32'h2000_0000;
    target_dataslot_length     <= 32'd64;

    if (dataslot_allcomplete) nv_loaded <= 1'b1;
    if (nv_loaded && boot_timer != NV_BOOT) boot_timer <= boot_timer + 29'd1;

    if (ea_dirty_s != ea_dirty_d) begin
        nv_pending <= 1'b1;
        nv_timer   <= 28'd0;
    end else if (nv_timer != NV_SETTLE) begin
        nv_timer   <= nv_timer + 28'd1;
    end

    case (nv_state)
    2'd0: begin
        target_dataslot_write <= 1'b0;
        if ((nv_pending && nv_loaded && (nv_timer == NV_SETTLE || (inmenu_s && !inmenu_d)))
            || (boot_timer == NV_BOOT - 29'd1)) begin
            target_dataslot_write <= 1'b1;
            nv_pending <= 1'b0;
            nv_state   <= 2'd1;
        end
    end
    2'd1: if (target_dataslot_ack)  begin target_dataslot_write <= 1'b0; nv_state <= 2'd2; end
    2'd2: if (target_dataslot_done) nv_state <= 2'd0;
    default: nv_state <= 2'd0;
    endcase
end

//--------------------------------------------------------------------------------------
// Audio: 48 kHz I2S, 16-bit signed, mono to both channels
//--------------------------------------------------------------------------------------
    reg  [15:0] aud_s1, aud_s2;

    reg  [21:0] audgen_accum = 22'd0;
    reg         audgen_mclk  = 1'b0;
    parameter   [20:0] CYCLE_48KHZ = 21'd122880 * 2;
always @(posedge clk_74a) begin
    audgen_accum <= audgen_accum + CYCLE_48KHZ;
    if (audgen_accum >= 21'd742500) begin
        audgen_mclk  <= ~audgen_mclk;
        audgen_accum <= audgen_accum - 21'd742500 + CYCLE_48KHZ;
    end
end

    reg  [1:0]  aud_mclk_divider = 2'd0;
    wire        audgen_sclk = aud_mclk_divider[1] /* synthesis keep*/;
always @(posedge audgen_mclk) aud_mclk_divider <= aud_mclk_divider + 1'b1;

    reg  [4:0]  audgen_lrck_cnt = 5'd0;
    reg         audgen_lrck = 1'b0;
    reg         audgen_dac  = 1'b0;
    reg  [31:0] aud_shift = 32'd0;
always @(negedge audgen_sclk) begin
    aud_s1 <= t_audio;               // sample slowly-changing audio from clk_sys
    aud_s2 <= aud_s1;
    audgen_dac      <= aud_shift[31];
    audgen_lrck_cnt <= audgen_lrck_cnt + 1'b1;
    if (audgen_lrck_cnt == 5'd31) begin
        audgen_lrck <= ~audgen_lrck;
        aud_shift   <= {aud_s2, 16'h0000};
    end else begin
        aud_shift   <= {aud_shift[30:0], 1'b0};
    end
end

assign audio_mclk = audgen_mclk;
assign audio_dac  = audgen_dac;
assign audio_lrck = audgen_lrck;

endmodule
