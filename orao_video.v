`timescale 1ns / 1ps

module orao_video
(
   output reg     pix,
   output reg     HSync,
   output reg     VSync,
   output reg     de,

   output reg [12:0]  video_addr,   // Video RAM intf
   input  [7:0]   video_data,

   output         video_on,         // control sigs
   input          video_blank,
   input          clk
);

assign video_on   = (vc < 11'd600);

reg  [10:0] hc;
reg  [10:0] vc;

reg  [9:0] screen_x, screen_y;

always @(posedge clk) begin
   hc <= hc + 1'd1;
   if(hc == 1040) begin 
      hc <=0;
      vc <= vc + 1'd1;
      if(vc == 666) vc <= 0;
   end

   if(hc == 856) HSync <= 1;
   if(hc == 976) HSync <= 0;
   if(vc == 637) VSync <= 1;
   if(vc == 643) VSync <= 0;
   
   screen_x <= hc > 11'd143 && hc < 11'd657 ? hc - 11'd143 : 11'h1;        // Offset to center
   screen_y <= vc > 11'd43  && vc < 11'd556 ? vc - 11'd44  : 11'h0;        // Offset to center

   video_addr <= {screen_y[8:1], screen_x[8:4]};

   pix <= (hc > 11'd144 && vc > 11'd43 && hc < 11'd656 && vc < 11'd556) ? video_data[screen_x[3:1] - 1'b1] : 1'b0;
   de <= ((hc < 11'd800) && (vc < 11'd600));       
   
end

reg [7:0] vdata;
reg       inv;

endmodule