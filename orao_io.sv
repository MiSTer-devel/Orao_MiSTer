`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
//
// Copyright (C) 2019, Hrvoje Cavrak
//
// Copyright (C) 2011, Thomas Skibo.  All rights reserved.
// 
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are met:
// * Redistributions of source code must retain the above copyright
//   notice, this list of conditions and the following disclaimer.
// * Redistributions in binary form must reproduce the above copyright
//   notice, this list of conditions and the following disclaimer in the
//   documentation and/or other materials provided with the distribution.
// * The names of contributors may not be used to endorse or promote products
//   derived from this software without specific prior written permission.
// 
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
// AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
// IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
// ARE DISCLAIMED. IN NO EVENT SHALL Thomas Skibo OR CONTRIBUTORS BE LIABLE FOR
// ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
// DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
// SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
// CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
// LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
// OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
// SUCH DAMAGE.
//
//////////////////////////////////////////////////////////////////////////////

module orao_io
(
   output reg [7:0] data_out,    // CPU interface
   input  [7:0]  data_in,
   input [15:0]  addr,
   input         we,

   input  [10:0] ps2_key,

   input         ioctl_download,
   input   [7:0] ioctl_index,
   input         ioctl_wr,
   input  [24:0] ioctl_addr,
   input   [7:0] ioctl_dout,
   output reg    ioctl_wait,
   
   output        video_blank,    // Video controls
   input         video_sync,

   output reg    audio,       

   input         ce,
   input         clk,
   input         reset
   
);

//////////////////////////////////////////////////////////////////////
// PS/2 to Orao keyboard interface
//////////////////////////////////////////////////////////////////////
wire  [7:0] kbd_data_out, tape_data_out;

reg [24:0] old_ioctl_addr;
reg [15:0] old_read_addr;

keyboard keyboard(.*,
                  .ps2_key(ps2_key)
                  );

reg old_ioctl_wr, old_ioctl_download;
reg read_counter;

reg [31:0] timeout = 0;                                              // Provides a control mechanism to abort a "stuck" tape download

//////////////////////////////////////////////////////////////////////
// Memory address space demultiplex and tape interface
//////////////////////////////////////////////////////////////////////

always @(posedge clk) begin
   old_ioctl_addr <= ioctl_addr;
   old_read_addr <= addr;  
   old_ioctl_download <= ioctl_download;										// Used to detect transitions
	
   timeout <= timeout + 1'b1;
   
   if(~old_ioctl_download && ioctl_download)									// Detect start of download
       timeout <= 32'b0;
			
   if (old_ioctl_addr != ioctl_addr) begin								   // Detect when userspace sends us a new byte
      ioctl_wait <= 1'b1;
      tape_data_out <= ioctl_dout > 8'h7f ? 8'hff : 8'h0;				// Comparator. Set to all ones or zeros, depending what's closer.
   end
	
   else if(old_read_addr != addr && addr == 16'h87ff) begin				// Detect when the Orao reads a new byte (access to 0x87ff)
      read_counter <= ~read_counter; 
      if (~read_counter)															// Slow down input so it's not too fast for the read-out routine.
			ioctl_wait <= 1'b0;
         
      timeout <= 32'b0;    
   end
	
   else if (addr == 16'h87ff)														// 0x87ff is used to access current bit coming in from tape
      data_out <= tape_data_out;
         
   else if (addr[15:11] == 5'b10000)											// Addresses with 0b10000 in high bits are for reading the keyboard
      data_out <= kbd_data_out;     
      
   else
      data_out <= 8'hff;   														// This handles the remaining address space, return all ones.
		
	
	if (ce && addr[15:11] == 5'b10001)
		audio <= ~audio;																// When location with 10001 in address high bits is read or 
																							// written, flip-flop is switched. Used to generate audio.
      
   if(timeout > 32'd75000000) 						  							// After 1,5 seconds after last read from tape, disable 
		ioctl_wait <= 0;																// ioctl_wait to remove the loading box from screen.
end																						

assign video_blank = 1'b0;
 
endmodule // orao_io
