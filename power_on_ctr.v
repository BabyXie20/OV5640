`timescale 1ns / 1ps
//----------------------------------------------------------------------// 
//    Module: ov5640 image sensor power on timing requirement ctrol     //
//----------------------------------------------------------------------//
//    Version: V1_0  => program creat,  2018-08-24, by caoxun           //
//----------------------------------------------------------------------//

module power_on_ctr(
    input  wire clk, rst,
	output wire camera_rstn, 		// high level width
	output wire camera_pwnd, 		// high level width
	input  wire soft_rst,
    output wire power_on_vd			// high level width
);

//______________________ Variable Declare ______________________
reg  camera_pwnd_r, camera_pwnd_r1;
wire neg_camera_pwnd;
reg  [18: 0] camera_pwnd_delay;

reg  camera_rstn_r, camera_rstn_r1;
reg  camera_rstn_rdy;
wire pos_camera_rstn;
reg  [16: 0] camera_rstn_delay;

reg  power_on_vd_r, power_on_vd_r1;
reg  [20: 0] power_on_lelay;



parameter  Delay_6mS   = 150000;  // 6ms, clk_24M Hz
parameter  Delay_1_5mS = 37500;   // 1.5ms, clk_24M Hz
parameter  Delay_22mS  = 550000;


//______________________ Main Body of Code ______________________

// Process: requiring 5ms delayed from AVDD power on to sensor's power is stable,  
//          which sensor pin PWDN high level(>=5ms) changed to low level 
always@(posedge clk)
    if(rst) begin
	    camera_pwnd_r <= 1;
		camera_pwnd_r1 <= 1;
		camera_pwnd_delay <= 0;
	end
	else begin
	    camera_pwnd_r1 <= camera_pwnd_r;
		
		if(camera_pwnd_delay == Delay_6mS) begin
		    camera_pwnd_r <= 0;
		    camera_pwnd_delay <= camera_pwnd_delay;
		end
		else begin
		    camera_pwnd_r <= 1;
		    camera_pwnd_delay <= camera_pwnd_delay + 1;
		end
	end

// high level width
assign  camera_pwnd = camera_pwnd_r;
assign  neg_camera_pwnd = (~camera_pwnd_r) & camera_pwnd_r1;



// Process: requiring 1ms delayed from sensor's power stable to ResetB changed to high level,  
//          which sensor pin RSTB low level(>=1ms) changed to high level
always@(posedge clk)
    if(rst) begin
	    camera_rstn_rdy <= 0;
	end
	else begin
	    if(neg_camera_pwnd) begin
		    camera_rstn_rdy <= 1;
		end
		else if(pos_camera_rstn) begin
		    camera_rstn_rdy <= 0;
		end
	end


always@(posedge clk)
    if(rst) begin
	    camera_rstn_r <= 0;
		camera_rstn_r1 <= 0;
		camera_rstn_delay <= 0;
	end
	else begin
	    camera_rstn_r1 <= camera_rstn_r;
		
		if(camera_rstn_delay == Delay_1_5mS) begin
		    camera_rstn_r <= 1;
		end
//		else if(camera_rstn_rdy)begin
//		    camera_rstn_r <= 0;
//		end
		
		if(neg_camera_pwnd) begin
		    camera_rstn_delay <= 0;
		end
		else if(camera_rstn_rdy)begin
		    camera_rstn_delay <= camera_rstn_delay + 1;  
		end
	end	
	
assign  pos_camera_rstn = camera_rstn_r & (~camera_rstn_r1);

// high level width
assign  camera_rstn = camera_rstn_r;


// Process: requiring 20ms delayed from ResetB high level to initial sensor register by iic interface,  
//          which sensor pin RSTB high level(>=20ms) to initial sensor register
always@(posedge clk)
    if(rst) begin
	    power_on_vd_r <= 0;
		power_on_vd_r1 <= 0;
		power_on_lelay <= 0;
	end
	else begin
	    power_on_vd_r1 <= power_on_vd_r;
		
		if(power_on_lelay == Delay_22mS) begin
		    power_on_vd_r <= 1;
			power_on_lelay <= power_on_lelay;
		end
		else if(camera_rstn_r) begin
		    power_on_vd_r <= 0;
		    power_on_lelay <= power_on_lelay + 1;
		end
		else begin
		    power_on_vd_r <= 0;
		    power_on_lelay <= 0;
		end
	end

// high level pulse
//assign  power_on_vd = power_on_vd_r & (~power_on_vd_r1);

// high level width
assign  power_on_vd = power_on_vd_r; 


endmodule



