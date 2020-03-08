//============================================================================
//  ORAO 
//
//  Core for MiSTer
//  Copyright (C) 2017 Sorgelig
//  Copyright (C) 2019 Hrvoje Cavrak
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 2 of the License, or (at your option)
//  any later version.
//
//  This program is distributed in the hope that it will be useful, but WITHOUT
//  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
//  FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
//  more details.
//
//  You should have received a copy of the GNU General Public License along
//  with this program; if not, write to the Free Software Foundation, Inc.,
//  51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
//============================================================================

module emu
(
	//Master input clock
	input         CLK_50M,

	//Async reset from top-level module.
	//Can be used as initial reset.
	input         RESET,

	//Must be passed to hps_io module
	inout  [45:0] HPS_BUS,

	//Base video clock. Usually equals to CLK_SYS.
	output        CLK_VIDEO,

	//Multiple resolutions are supported using different CE_PIXEL rates.
	//Must be based on CLK_VIDEO
	output        CE_PIXEL,

	//Video aspect ratio for HDMI. Most retro systems have ratio 4:3.
	output  [7:0] VIDEO_ARX,
	output  [7:0] VIDEO_ARY,

	output  [7:0] VGA_R,
	output  [7:0] VGA_G,
	output  [7:0] VGA_B,
	output        VGA_HS,
	output        VGA_VS,
	output        VGA_DE,    // = ~(VBlank | HBlank)
	output        VGA_F1,
	output  [1:0] VGA_SL,

	output        LED_USER,  // 1 - ON, 0 - OFF.

	// b[1]: 0 - LED status is system status OR'd with b[0]
	//       1 - LED status is controled solely by b[0]
	// hint: supply 2'b00 to let the system control the LED.
	output  [1:0] LED_POWER,
	output  [1:0] LED_DISK,

	// I/O board button press simulation (active high)
	// b[1]: user button
	// b[0]: osd button
	output  [1:0] BUTTONS,

	output [15:0] AUDIO_L,
	output [15:0] AUDIO_R,
	output        AUDIO_S,   // 1 - signed audio samples, 0 - unsigned
	output  [1:0] AUDIO_MIX, // 0 - no mix, 1 - 25%, 2 - 50%, 3 - 100% (mono)

	//ADC
	inout   [3:0] ADC_BUS,

	//SD-SPI
	output        SD_SCK,
	output        SD_MOSI,
	input         SD_MISO,
	output        SD_CS,
	input         SD_CD,

	//High latency DDR3 RAM interface
	//Use for non-critical time purposes
	output        DDRAM_CLK,
	input         DDRAM_BUSY,
	output  [7:0] DDRAM_BURSTCNT,
	output [28:0] DDRAM_ADDR,
	input  [63:0] DDRAM_DOUT,
	input         DDRAM_DOUT_READY,
	output        DDRAM_RD,
	output [63:0] DDRAM_DIN,
	output  [7:0] DDRAM_BE,
	output        DDRAM_WE,

	//SDRAM interface with lower latency
	output        SDRAM_CLK,
	output        SDRAM_CKE,
	output [12:0] SDRAM_A,
	output  [1:0] SDRAM_BA,
	inout  [15:0] SDRAM_DQ,
	output        SDRAM_DQML,
	output        SDRAM_DQMH,
	output        SDRAM_nCS,
	output        SDRAM_nCAS,
	output        SDRAM_nRAS,
	output        SDRAM_nWE,

	input         UART_CTS,
	output        UART_RTS,
	input         UART_RXD,
	output        UART_TXD,
	output        UART_DTR,
	input         UART_DSR,

	// Open-drain User port.
	// 0 - D+/RX
	// 1 - D-/TX
	// 2..6 - USR2..USR6
	// Set USER_OUT to 1 to read from USER_IN.
	input   [6:0] USER_IN,
	output  [6:0] USER_OUT,

	input         OSD_STATUS
);

assign {SD_SCK, SD_MOSI, SD_CS} = 'Z;
assign {SDRAM_DQ, SDRAM_A, SDRAM_BA, SDRAM_CLK, SDRAM_CKE, SDRAM_DQML, SDRAM_DQMH, SDRAM_nWE, SDRAM_nCAS, SDRAM_nRAS, SDRAM_nCS} = 'Z;

assign LED_USER  = ioctl_download;
assign LED_DISK  = 0;
assign LED_POWER = 0;

assign USER_OUT  = '1;
assign VGA_F1    = 0;

assign VIDEO_ARX = status[1] ? 8'd16 : 8'd4;
assign VIDEO_ARY = status[1] ? 8'd9  : 8'd3; 

`include "build_id.v" 
localparam CONF_STR = 
{
   "ORAO;;",
   "-;",
   "F,TAP;",
   "-;",
	"O2,Screen Color,White,Green;",
   "O1,Aspect Ratio,4:3,16:9;",
   "-;",
   "T6,Reset;",
   "V,v0.9.",`BUILD_DATE
};

////////////////////   CLOCKS   ///////////////////

wire clk_sys;
assign clk_sys = CLK_50M;
reg reset = 1;

always @(posedge clk_sys) begin
   integer   initRESET = 20000000;
   reg [3:0] reset_cnt;

   if ((!(RESET | status[0] | buttons[1] | status[6]) && reset_cnt==4'd14) && !initRESET)
      reset <= 0;
   else begin
      if(initRESET) initRESET <= initRESET - 1;
      reset <= 1;
      reset_cnt <= reset_cnt+4'd1;
   end
end

reg  ce_1m;

always @(posedge clk_sys) begin
   reg  [6:0] cpu_div = 0;
   reg  [6:0] cpu_rate = 7'd50;     // For a 50 MHz clock

   if(cpu_div == cpu_rate) begin
      cpu_div  <= 0;
	end
	else
		cpu_div <= cpu_div + 1'd1;
   
      
   ce_1m <= (cpu_div == 7'd8);
end


///////////////////////////////////////////////////
// RAM
///////////////////////////////////////////////////

wire [31:0] status;
wire  [1:0] buttons;

wire        ioctl_download;
wire  [7:0] ioctl_index;
wire        ioctl_wr;
wire [26:0] ioctl_addr;
wire  [7:0] ioctl_dout;
wire [31:0] ioctl_file_ext;

wire [10:0] ps2_key;

hps_io #(.STRLEN($size(CONF_STR)>>3), .WIDE(0)) hps_io
(
   .clk_sys(clk_sys),
   .HPS_BUS(HPS_BUS),

   .conf_str(CONF_STR),

   .buttons(buttons),
   .status(status),

   .ps2_key(ps2_key),

   .ioctl_download(ioctl_download),
   .ioctl_index(ioctl_index),
   .ioctl_wr(ioctl_wr),
   .ioctl_addr(ioctl_addr),
   .ioctl_dout(ioctl_dout),
   .ioctl_wait(0)
);


///////////////////////////////////////////////////
// CPU
///////////////////////////////////////////////////

wire [15:0] addr;
wire [7:0]  cpu_data_out;
wire [7:0]  cpu_data_in;

wire we;
wire irq;

cpu6502 cpu
(
   .clk(clk_sys),
   .ce(ce_1m & (~ioctl_download)),
   .reset(reset),
   .nmi(0),
   .irq(irq),
   .din(cpu_data_in),
   .dout(cpu_data_out),
   .addr(addr),
   .we(we)
);

///////////////////////////////////////////////////
// Orao hardware
///////////////////////////////////////////////////

wire pix;
wire HSync, VSync, HBlank, VBlank;
wire audioDat;

assign VGA_G = {8{pix}};
assign VGA_R = status[2] ? 8'd0 : VGA_G;
assign VGA_B = VGA_R;

assign CLK_VIDEO = clk_sys;
assign CE_PIXEL  = 1'b1;

orao_hw hw
(
   .*,
	.HSync(VGA_HS),
	.VSync(VGA_VS),
   .clk(clk_sys),

   .data_out(cpu_data_in),
   .data_in(cpu_data_out),

   .de(VGA_DE),   
   .ps2_key(ps2_key),
   
   .audio(audioDat)
);


////////////////////////////////////////////////////////////////////
// Audio                                                          //
////////////////////////////////////////////////////////////////////    

assign AUDIO_S = 1'b0;
wire audio = {audioDat ^ (ioctl_download & ioctl_dout[6])};

assign AUDIO_L = { audio, 3'b0, audio, 9'b0};
assign AUDIO_R = AUDIO_L;

endmodule
