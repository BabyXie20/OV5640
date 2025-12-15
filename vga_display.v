
`timescale 1ns / 1ps
//----------------------------------------------------------------------// 
//    Module: VGA interface display image - 1280*768 VGA 60Hz           //
//----------------------------------------------------------------------//
//    Version: V1_0  => program creat,  2018-08-29, by caoxun           //
//----------------------------------------------------------------------//
//    Note: Vedio image format => 720P(1280*720), 30fps, RGB565         //
//----------------------------------------------------------------------//

module vga_display(
    input  wire  vga_clk_i,
	input  wire  vga_rst_i,
	
	output wire  vga_Hsync_o,
	output wire  vga_Vsync_o,
	output wire  [4 : 0] vga_R_o, 
	output wire  [5 : 0] vga_G_o, 
	output wire  [4 : 0] vga_B_o,
	
	output wire  ddr3_rd_addr_rst_o,
	output wire  ddr3_rd_req_o,
	output wire  ddr3_rd_en_o,
	input  wire  [63: 0] ddr3_data_vga_i
 
);


//______________________ Variable Declare ______________________

// horizon scan parameter setting
parameter  HorTotalPixel  = 1664;
parameter  HorActivePixel = 1280;
parameter  HorSyncPulse   = 128;
parameter  HorBackPorch   = 192;
parameter  HorFrontPorch  = 64;
parameter  HorStartPixel  = HorSyncPulse + HorBackPorch;    // 320, actually active pixel is 321th
parameter  HorEndPixel    = HorTotalPixel - HorFrontPorch;  // 1600


// vertical scan parameter setting
// note: camera video image is 1280*720, active lines num. is 720
parameter  VerTotalPixel  = 798;
parameter  VerActivePixel = 768;
parameter  VerSyncPulse   = 7;
parameter  VerBackPorch   = 20;
parameter  VerFrontPorch  = 3;
parameter  VerStartPixel  = VerSyncPulse + VerBackPorch;    // 27, actually active pixel is 28th
parameter  VerEndPixel    = VerStartPixel + 720;  // 795
//parameter  VerEndPixel    = VerTotalPixel - VerFrontPorch;  // 795


wire vga_clk, vga_rst;

reg  vga_Hsync, vga_Vsync;
reg  vga_vsync_r1 = 0, vga_vsync_r2 = 0;
wire pos_vga_vsync, neg_vga_vsync;
reg  hor_pixel_vd, ver_pixel_vd;    // level width
reg  [4 : 0] vga_R;
reg  [5 : 0] vga_G;
reg  [4 : 0] vga_B;
reg  [10: 0] hor_pix_cnt;
reg  [10: 0] ver_pix_cnt;

reg  ddr3_rd_addr_rst;
reg  ddr3_rd_req;
reg  ddr3_rd_en;
reg  [3 : 0] shift_cnt;
wire [63: 0] ddr3_data_vga;

// 用于将ddr3_data_vga_i缓存为本模块的data,可避免因ddr3_data_vga_i的变化对后续赋值的影响
reg  [63: 0] ddr3_data_vga_reg;    

// equal pixel interval is 160pixels, totally 8 fragment ==> 1280pixels
`define  HorPix_P1  (hor_pix_cnt == 250)
`define  HorPix_P2  (hor_pix_cnt == 410)
`define  HorPix_P3  (hor_pix_cnt == 570)
`define  HorPix_P4  (hor_pix_cnt == 730)
`define  HorPix_P5  (hor_pix_cnt == 890)
`define  HorPix_P6  (hor_pix_cnt == 1050) 
`define  HorPix_P7  (hor_pix_cnt == 1210)
`define  HorPix_P8  (hor_pix_cnt == 1370) 


//______________________ Main Body of Code ______________________
assign  vga_Hsync_o = vga_Hsync;
assign  vga_Vsync_o = vga_Vsync;
assign  vga_R_o = (hor_pixel_vd && ver_pixel_vd) ? vga_R : 0;
assign  vga_G_o = (hor_pixel_vd && ver_pixel_vd) ? vga_G : 0;
assign  vga_B_o = (hor_pixel_vd && ver_pixel_vd) ? vga_B : 0;

assign  ddr3_rd_addr_rst_o = ddr3_rd_addr_rst;
assign  ddr3_rd_req_o = ddr3_rd_req;
assign  ddr3_rd_en_o  = ddr3_rd_en;

assign  vga_clk = vga_clk_i;
assign  vga_rst = vga_rst_i;
assign  ddr3_data_vga = ddr3_data_vga_i;


//------------------------------------------------------------------------+
// Process: horizon scan pixel counter
always@(posedge vga_clk)
    if(vga_rst) begin
	    hor_pix_cnt <= 1;
	end
	else begin
	    if(hor_pix_cnt == HorTotalPixel) begin
		    hor_pix_cnt <= 1;
		end
		else begin
		    hor_pix_cnt <= hor_pix_cnt + 1;
		end
	end


// Process: gener vga Hsync, horizon valid pixel signal
always@(posedge vga_clk)
    if(vga_rst) begin
	    vga_Hsync <= 1;
		hor_pixel_vd <= 0;
	end
	else begin
	    if(hor_pix_cnt == 1) vga_Hsync <= 0;
		else if(hor_pix_cnt == HorSyncPulse) vga_Hsync <= 1;
		else vga_Hsync <= vga_Hsync;
		
		if(hor_pix_cnt == HorStartPixel) hor_pixel_vd <= 1;
		else if(hor_pix_cnt == HorEndPixel) hor_pixel_vd <= 0;
		else hor_pixel_vd <= hor_pixel_vd;
	end
//------------------------------------------------------------------------=



//------------------------------------------------------------------------+
// Process: vertical scan pixel counter
always@(posedge vga_clk)
    if(vga_rst) begin
	    ver_pix_cnt <= 1;
	end
	else begin
	    if(ver_pix_cnt == VerTotalPixel) begin
		    ver_pix_cnt <= 1;
		end
		// 上一行全部像素点数据输出完毕,切换到下一行
		else if(hor_pix_cnt == HorTotalPixel) begin
		    ver_pix_cnt <= ver_pix_cnt + 1;
		end
	end

	
// Process: gener vga Vsync, vertical valid pixel signal
always@(posedge vga_clk)
    if(vga_rst) begin
	    vga_Vsync <= 1;
		ver_pixel_vd <= 0;
	end
	else begin
	    if(ver_pix_cnt == 1) vga_Vsync <= 0;
		else if(ver_pix_cnt == VerSyncPulse) vga_Vsync <= 1;
		else vga_Vsync <= vga_Vsync;
		
		if(ver_pix_cnt == VerStartPixel) ver_pixel_vd <= 1;
		else if(ver_pix_cnt == VerEndPixel) ver_pixel_vd <= 0;
		else ver_pixel_vd <= ver_pixel_vd;
	end
//------------------------------------------------------------------------=



//------------------------------------------------------------------------+
// Process: Once one frame trans over, reset ddr3 rd address
assign  neg_vga_vsync = (~vga_vsync_r1) & vga_vsync_r2;
assign  pos_vga_vsync = vga_vsync_r1 & (~vga_vsync_r2);

always@(posedge vga_clk)
    if(vga_rst) begin
	    vga_vsync_r1 <= 0;
		vga_vsync_r2 <= 0;
		ddr3_rd_addr_rst <= 0;
	end
	else begin
		vga_vsync_r1 <= vga_Vsync;
		vga_vsync_r2 <= vga_vsync_r1;
		
		if(neg_vga_vsync) begin    
			ddr3_rd_addr_rst <= 1;
		end
		else begin
			ddr3_rd_addr_rst <= 0;
		end
	end


// Process: gener ddr3 rd request pulse
always@(posedge vga_clk)
    if(vga_rst) begin
	    ddr3_rd_req <= 0;
	end
	else begin
	    if(ver_pixel_vd) begin
		    //每行指定像素点处产生ddr3 busrt读请求
			if(`HorPix_P1||`HorPix_P2||`HorPix_P3||`HorPix_P4||`HorPix_P5||`HorPix_P6||`HorPix_P7||`HorPix_P8) begin
			    ddr3_rd_req <= 1;
			end
			else begin
			    ddr3_rd_req <= 0;
			end
		end
		else begin
		    ddr3_rd_req <= 0;
		end
	end


// Process: ddr3 vga data(64bits)
always@(posedge vga_clk)
    if(vga_rst) begin
	    vga_R <= 0; vga_G <= 0; vga_B <= 0;
		ddr3_data_vga_reg <= 0;
		ddr3_rd_en <= 0;
		shift_cnt  <= 4'b0001;
	end
	else begin
	    if(hor_pixel_vd && ver_pixel_vd) begin
		    case(shift_cnt)
			    4'b0001: begin
				    vga_R <= ddr3_data_vga_reg[63:59]; 
					vga_G <= ddr3_data_vga_reg[58:53]; 
					vga_B <= ddr3_data_vga_reg[52:48];
					ddr3_data_vga_reg <= ddr3_data_vga_reg;
					ddr3_rd_en <= 1;						//ddr3读数据使能
					shift_cnt  <= 4'b0010;
				end
				
				4'b0010: begin
				    vga_R <= ddr3_data_vga_reg[47:43]; 
					vga_G <= ddr3_data_vga_reg[42:37]; 
					vga_B <= ddr3_data_vga_reg[36:32];
					ddr3_data_vga_reg <= ddr3_data_vga_reg;
					ddr3_rd_en <= 0;
					shift_cnt  <= 4'b0100;
				end
				
				4'b0100: begin
				    vga_R <= ddr3_data_vga_reg[31:27]; 
					vga_G <= ddr3_data_vga_reg[26:21]; 
					vga_B <= ddr3_data_vga_reg[20:16];
					ddr3_data_vga_reg <= ddr3_data_vga_reg;
					ddr3_rd_en <= 0;
					shift_cnt  <= 4'b1000;
				end
				
				4'b1000: begin
				    vga_R <= ddr3_data_vga_reg[15:11]; 
					vga_G <= ddr3_data_vga_reg[10: 5]; 
					vga_B <= ddr3_data_vga_reg[4 : 0];
					ddr3_data_vga_reg <= ddr3_data_vga;    // ddr3数据改变 
					ddr3_rd_en <= 0;
					shift_cnt  <= 4'b0001;
				end
				
				default: shift_cnt  <= 4'b0001;
			endcase
		end
		else begin
		    vga_R <= 0; vga_G <= 0; vga_B <= 0;
			ddr3_data_vga_reg <= ddr3_data_vga;
			ddr3_rd_en <= 0;
			shift_cnt  <= 4'b0001;
		end
	end
//------------------------------------------------------------------------=

endmodule

