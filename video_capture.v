`timescale 1ns / 1ps
//----------------------------------------------------------------------// 
//    Module: ov5640 image sensor video capture                         //
//----------------------------------------------------------------------//
//    Version: V1_0  => program creat,  2018-08-29, by caoxun           //
//----------------------------------------------------------------------//
//    Note: Vedio image format => 720P(1280*720), 30fps, RGB565         //
//----------------------------------------------------------------------//

module video_capture(
    input  wire  camera_PCLK_i,
	input  wire  camera_HREF_i, 
	input  wire  camera_VSYNC_i,  //帧同步信号
	
	input  wire  config_reg_done_i,
	input  wire  [7 : 0] camera_data_i,
	
	output wire  ddr3_wren_o,
	output wire  ddr3_wr_addr_rst_o,
	output wire  [63: 0] ddr3_data_camera_o,
	
	output wire  [1 : 0]frame_switch_o
);


//______________________ Variable Declare ______________________
reg  [10 : 0] camera_horiz_cnt, camera_verti_cnt;

reg  [1 : 0] frame_switch;
reg  ddr3_wren, ddr3_wren_reg;
reg  ddr3_wr_addr_rst;
reg  [63: 0] ddr3_data_camera = 0;
reg  [63: 0] ddr3_data_camera_reg;
reg  [7 : 0] shift_cnt;

wire camera_PCLK, camera_HREF, camera_VSYNC;
reg  camera_VSYNC_r1, camera_VSYNC_r2;
wire pos_camera_VSYNC, neg_camera_VSYNC;

parameter  HORIZ_PIXEL = 1280;

//______________________ Main Body of Code ______________________
assign  camera_PCLK        = camera_PCLK_i;
assign  camera_HREF        = camera_HREF_i;
assign  camera_VSYNC       = camera_VSYNC_i;

assign  ddr3_wren_o        = ddr3_wren;
assign  ddr3_wr_addr_rst_o = ddr3_wr_addr_rst;
assign  ddr3_data_camera_o = ddr3_data_camera;
assign  frame_switch_o     = frame_switch;


// Process: gener camera frame row(horizon) counter
always@(posedge camera_PCLK)
    if(!config_reg_done_i) begin
	    camera_horiz_cnt <= 1;		// ???起始像素点地址从1开始
	end
	else begin
	    if((camera_HREF == 1) && (camera_VSYNC == 0)) begin
		   camera_horiz_cnt <= camera_horiz_cnt + 1; 
		end
		else begin
			camera_horiz_cnt <= 1;
		end
    end


// Process: gener camera frame line counter
always@(posedge camera_PCLK)
    if(!config_reg_done_i) begin
	    camera_verti_cnt <= 1;    // ??? camera_verti_cnt从1开始计数
	end
	else begin
	    if(camera_horiz_cnt == HORIZ_PIXEL) begin
		    camera_verti_cnt <= camera_verti_cnt + 1;
		end
		else begin
		    camera_verti_cnt <= camera_verti_cnt;
		end
	end



// Process: gener request signal for wr camera data to ddr3	
always@(posedge camera_PCLK)
    if(!config_reg_done_i) begin
	    ddr3_data_camera_reg <= 64'd0;
		ddr3_wren_reg <= 0;
		shift_cnt <= 0;
	end
	else begin
	    if((camera_HREF == 1) && (camera_VSYNC == 0)) begin
		    if(shift_cnt == 7) begin
			    ddr3_data_camera_reg <= {ddr3_data_camera_reg[55:0],camera_data_i};
				ddr3_wren_reg <= 1;
				shift_cnt <= 0;
			end
			else begin
				ddr3_data_camera_reg <= {ddr3_data_camera_reg[55:0],camera_data_i};
		        ddr3_wren_reg <= 0;
				shift_cnt <= shift_cnt + 1;
			end
		end
		else begin
		    ddr3_data_camera_reg <= 64'd0;
		    ddr3_wren_reg <= 0;
		    shift_cnt <= 0;
		end
	end	
		
always@(posedge camera_PCLK)
    if(ddr3_wren_reg == 1) begin
	    ddr3_wren <= 1;
		ddr3_data_camera <= ddr3_data_camera_reg;  
	end
	else begin
	    ddr3_wren <= 0;
		ddr3_data_camera <= ddr3_data_camera;
	end	
	
	
	
// Process: gener image frame store memory switch pulse and ddr3 wr address reset
// Note: DDR3作用是两帧图像数据的乒乓缓存,第一帧图像存储完毕后(memory1),在memory2存储图像数据,
//       于此同时,读取第一帧图像数据出给VGA进行显示;
always@(posedge camera_PCLK)
    if(!config_reg_done_i) begin
	    camera_VSYNC_r1 <= 0;
		camera_VSYNC_r2 <= 0;
	end
	else begin
	    camera_VSYNC_r1 <= camera_VSYNC;
		camera_VSYNC_r2 <= camera_VSYNC_r1;
	end

assign  pos_camera_VSYNC = camera_VSYNC_r1 & (~camera_VSYNC_r2);	
assign  neg_camera_VSYNC = (~camera_VSYNC_r1) & camera_VSYNC_r2;


always@(posedge camera_PCLK)
    if(!config_reg_done_i) begin
	    ddr3_wr_addr_rst <= 0;
		frame_switch     <= 0;
	end
	else begin
	    // 检测到VSYNC下降沿时,上一帧图像数据传输完毕,dr3_wr_addr复位,下一帧图像准备
		if(neg_camera_VSYNC) begin
		    ddr3_wr_addr_rst <= 1;
		end
		else begin
		    ddr3_wr_addr_rst <= 0;
		end
		
		// 检测到VSYNC上升沿时,当前帧图像数据传输完毕,读写地址空间切换
	    if(pos_camera_VSYNC) begin
		    frame_switch <= frame_switch + 1;
		end
		else begin
		    frame_switch <= frame_switch;
		end
	end


endmodule


