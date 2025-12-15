
`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date:    16:09:46 08/31/2018 
// Design Name: 
// Module Name:    ov5640_vga_top 
// Project Name: 
// Target Devices: 
// Tool versions: 
// Description: 
//
// Dependencies: 
//
// Revision: 
// Revision 0.01 - File Created
// Additional Comments: 
//
//////////////////////////////////////////////////////////////////////////////////
module ov5640_vga_top(
    input  wire clk_50M,
	input  wire reset_n,
    output wire [3:0] led,               //led灯指示
	input  wire strobe_key,              //control the camera flash LED 

	//Camera接口信号
	output wire camera_xclk,             //cmos externl clock
	output wire camera_reset,
    output wire camera_pwnd,
	
	input  wire camera_pclk,              //cmos pxiel clock
    input  wire camera_href,              //cmos hsync refrence
	input  wire camera_vsync,             //cmos vsync
	input  wire [7:0] camera_data,        //cmos data
	output wire i2c_sclk,                 //cmos i2c clock
	inout  tri  i2c_sdat,	              //cmos i2c data

    //DDR的接口信号
    inout  tri  [15:0]            mcb3_dram_dq,
    output wire [12:0]            mcb3_dram_a,
    output wire [2:0]             mcb3_dram_ba,
    output wire                   mcb3_dram_ras_n,
    output wire                   mcb3_dram_cas_n,
    output wire                   mcb3_dram_we_n,
    output wire                   mcb3_dram_odt,
    output wire                   mcb3_dram_cke,
    output wire                   mcb3_dram_dm,
    inout  tri                    mcb3_dram_udqs,
    inout  tri                    mcb3_dram_udqs_n,
    inout  tri                    mcb3_rzq,
    inout  tri                    mcb3_zio,
    output wire                   mcb3_dram_udm,
    inout  tri                    mcb3_dram_dqs,
    inout  tri                    mcb3_dram_dqs_n,
    output wire                   mcb3_dram_ck,
    output wire                   mcb3_dram_ck_n,
	
	 //VGA的接口信号
	output wire [4:0]            vga_r,
    output wire [5:0]            vga_g,
    output wire [4:0]            vga_b,
    output wire                  vga_hsync,
    output wire                  vga_vsync

    );


//______________________ Variable Declare ______________________
wire  [63: 0] ddr3_data_camera;	
wire  [1 : 0] frame_switch;

wire          vga_clk;         // 78.125MHz
wire  [4 : 0] vga_R; 
wire  [5 : 0] vga_G; 
wire  [4 : 0] vga_B;
wire  [63: 0] ddr3_data_vga;

wire  c3_rst0;

//______________________ Main Body of Code ______________________
assign led[0] = calib_done      ? 1'b0 : 1'b1;               //led0为ddr calibrate完成指示信号,亮说明初始化完成
assign led[1] = config_reg_done ? 1'b0 : 1'b1;               //led1亮,说明sensor init已完成
assign led[2] = p0_cmd_full     ? 1'b0 : 1'b1;               //led2亮,说明写ddr3操作出现错误
assign led[3] = p1_cmd_full     ? 1'b0 : 1'b1;               //led3亮,说明读ddr3操作出现错误

assign camera_xclk  = camera_clk;		// 24MHz
assign camera_reset = camera_rstn;
assign i2c_sclk     = iic_sclk;
assign i2c_sdat     = iic_sda;

assign vga_r     = vga_R;
assign vga_g     = vga_G;
assign vga_b     = vga_B;
assign vga_hsync = vga_Hsync;
assign vga_vsync = vga_Vsync;


// 1 - power_on_ctr instance
power_on_ctr power_on_ctr (
    .clk(camera_clk), 
    .rst(c3_rst0), 
    .camera_rstn(camera_rstn),  
    .camera_pwnd(camera_pwnd), 
    .soft_rst(soft_rst), 
    .power_on_vd(power_on_vd) 
    ); 


// 2 - register_config instance
register_config register_config (
    .clk(camera_clk),
    .rst(c3_rst0),	
    .camera_rstn_i(camera_rstn), 
    .init_reg_rdy_i(power_on_vd), 
    .strobe_light_key_i(strobe_key), 
    .clc_20K_o(), 
    .reg_index_o(), 
    .strobe_flash_o(), 
    .config_reg_done_o(config_reg_done), 
    .iic_sclk_o(iic_sclk), 
    .iic_sda(iic_sda)
    );

//reg_config	reg_config_inst(
//	.clk_25M                 (camera_clk),
//	.camera_rstn             (camera_rstn),
//	.initial_en              (power_on_vd),		
//	.i2c_sclk                (iic_sclk),
//	.i2c_sdat                (iic_sda),
//	.reg_conf_done           (config_reg_done),
//	.strobe_flash            (strobe_flash),
//	.reg_index               (),
//	.clock_20k               (),
//	.key1                    (strobe_key)
//);



// 3 - video_capture instance
video_capture video_capture (
    .camera_PCLK_i(camera_pclk), 	// 79.6M Hz
    .camera_HREF_i(camera_href), 
    .camera_VSYNC_i(camera_vsync), 
    .config_reg_done_i(config_reg_done), 
    .camera_data_i(camera_data), 
    .ddr3_wren_o(ddr3_wren), 
    .ddr3_wr_addr_rst_o(ddr3_wr_addr_rst), 
    .ddr3_data_camera_o(ddr3_data_camera), 
    .frame_switch_o(frame_switch)
    );


// 4 - vga_display instance
vga_display vga_display (
    .vga_clk_i(vga_clk), 
    .vga_rst_i(c3_rst0), 
    .vga_Hsync_o(vga_Hsync), 
    .vga_Vsync_o(vga_Vsync), 
    .vga_R_o(vga_R), 
    .vga_G_o(vga_G), 
    .vga_B_o(vga_B), 
    .ddr3_rd_addr_rst_o(ddr3_rd_addr_rst), 
    .ddr3_rd_req_o(ddr3_rd_req), 
    .ddr3_rd_en_o(ddr3_rd_en), 
    .ddr3_data_vga_i(ddr3_data_vga)
    );



// 5 - ddr3 wr ctr instance
ddr3_wr_ctr ddr3_wr_ctr (
    .camera_pclk_i(camera_pclk),
	.camera_clk_o(camera_clk), 
    .vga_clk_o(vga_clk), 
    .frame_switch_i(frame_switch), 
    .ddr3_wren_i(ddr3_wren), 
    .ddr3_wr_addr_rst_i(ddr3_wr_addr_rst), 
    .ddr3_data_camera_i(ddr3_data_camera), 
    .ddr3_rd_addr_rst_i(ddr3_rd_addr_rst), 
    .ddr3_rd_req_i(ddr3_rd_req), 
    .ddr3_rd_en_i(ddr3_rd_en), 
    .ddr3_data_vga_o(ddr3_data_vga), 
    .p0_cmd_full_o(p0_cmd_full), 
    .p1_cmd_full_o(p1_cmd_full), 
    .mcb3_dram_dq(mcb3_dram_dq), 
    .mcb3_dram_a(mcb3_dram_a), 
    .mcb3_dram_ba(mcb3_dram_ba), 
    .mcb3_dram_ras_n(mcb3_dram_ras_n), 
    .mcb3_dram_cas_n(mcb3_dram_cas_n), 
    .mcb3_dram_we_n(mcb3_dram_we_n), 
    .mcb3_dram_odt(mcb3_dram_odt), 
    .mcb3_dram_cke(mcb3_dram_cke), 
    .mcb3_dram_dm(mcb3_dram_dm), 
    .mcb3_dram_udqs(mcb3_dram_udqs), 
    .mcb3_dram_udqs_n(mcb3_dram_udqs_n), 
    .mcb3_rzq(mcb3_rzq), 
    .mcb3_zio(mcb3_zio), 
    .mcb3_dram_udm(mcb3_dram_udm), 
    .c3_sys_clk(clk_50M), 
    .c3_sys_rst_n(reset_n), 
    .c3_rst0(c3_rst0),
    .c3_calib_done(calib_done),	
    .mcb3_dram_dqs(mcb3_dram_dqs), 
    .mcb3_dram_dqs_n(mcb3_dram_dqs_n), 
    .mcb3_dram_ck(mcb3_dram_ck), 
    .mcb3_dram_ck_n(mcb3_dram_ck_n)
    );



endmodule



