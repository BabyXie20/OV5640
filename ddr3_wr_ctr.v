`timescale 1ns / 1ps 
//----------------------------------------------------------------------// 
//    Module: ddr3 wr & rd ctrol module                                 //
//----------------------------------------------------------------------//
//    Version: V1_0  => program creat,  2018-08-29, by caoxun           //
//----------------------------------------------------------------------//
//    Note: ddr3 used for image data buffer, divide into 4 parts        //
//----------------------------------------------------------------------//

// 1- 采用P0口写入摄像头图像数据, P1口读取图像用于VGA显示
// 2- frame_switch 信号来切换读写ddr3的地址空间,实现ddr3读和写的乒乓操作;

module ddr3_wr_ctr #(
    // External memory data width
	parameter C3_NUM_DQ_PINS          = 16,       
    // External memory address width                                   
    parameter C3_MEM_ADDR_WIDTH       = 13,       
    // External memory bank address width                                   
    parameter C3_MEM_BANKADDR_WIDTH   = 3                                               
)
(
    input  wire  camera_pclk_i,
	output wire  camera_clk_o,
    output wire  vga_clk_o,
	
	// video capture signal
	input  wire  [1 : 0] frame_switch_i, // level width
	input  wire  ddr3_wren_i,            // level pulse
	input  wire  ddr3_wr_addr_rst_i,     // level pulse
	input  wire  [63: 0] ddr3_data_camera_i,	
	
	// vga display signal
	input  wire  ddr3_rd_addr_rst_i,  // level pulse
	input  wire  ddr3_rd_req_i,       // level pulse
	input  wire  ddr3_rd_en_i,        // level pulse
	output wire  [63: 0] ddr3_data_vga_o,
	
    // ddr3 mig status signal
	output wire  p0_cmd_full_o,
	output wire  p1_cmd_full_o,
	
	// ddr3 mig interface signal
	inout  tri   [C3_NUM_DQ_PINS-1:0]                     mcb3_dram_dq,     
    output wire  [C3_MEM_ADDR_WIDTH-1:0]                  mcb3_dram_a,      
    output wire  [C3_MEM_BANKADDR_WIDTH-1:0]              mcb3_dram_ba,
    output wire                                           mcb3_dram_ras_n,
    output wire                                           mcb3_dram_cas_n,
    output wire                                           mcb3_dram_we_n,
    output wire                                           mcb3_dram_odt,
    output wire                                           mcb3_dram_cke,
    output wire                                           mcb3_dram_dm,
    inout  tri                                            mcb3_dram_udqs,
    inout  tri                                            mcb3_dram_udqs_n,
    inout  tri                                            mcb3_rzq,
    inout  tri                                            mcb3_zio,
    output wire                                           mcb3_dram_udm,
    input  wire                                           c3_sys_clk,
    input  wire                                           c3_sys_rst_n,
    output wire                                           c3_rst0,
    output wire                                           c3_calib_done,
	inout  tri                                            mcb3_dram_dqs,
    inout  tri                                            mcb3_dram_dqs_n,
    output wire                                           mcb3_dram_ck,
    output wire                                           mcb3_dram_ck_n
	
);


//______________________ Variable Declare ______________________

// ddr3 mig interface variable
//wire            c3_calib_done;			
wire            c3_clk0;

//ddr3 p0 user interface
reg				c3_p0_cmd_en;
reg [2 :0]		c3_p0_cmd_instr;
reg [5 :0]		c3_p0_cmd_bl;
reg [29:0]		c3_p0_cmd_byte_addr;
wire			c3_p0_cmd_empty;
wire			c3_p0_cmd_full;

reg				c3_p0_wr_en;
reg [7 :0]	    c3_p0_wr_mask;
reg [63:0]	    c3_p0_wr_data;
wire			c3_p0_wr_full;
wire			c3_p0_wr_empty;
wire [6:0]		c3_p0_wr_count;
wire			c3_p0_wr_underrun;
wire			c3_p0_wr_error;

reg				c3_p0_rd_en;
wire [63:0]	    c3_p0_rd_data;
wire			c3_p0_rd_full;
wire			c3_p0_rd_empty;
wire [6 :0]		c3_p0_rd_count;
wire			c3_p0_rd_overflow;
wire			c3_p0_rd_error;

//ddr3 p1 user interface
reg				c3_p1_cmd_en;
reg  [2 :0]		c3_p1_cmd_instr;
reg  [5 :0]		c3_p1_cmd_bl;
reg  [29:0]		c3_p1_cmd_byte_addr;
wire			c3_p1_cmd_empty;
wire			c3_p1_cmd_full;

reg				c3_p1_wr_en;
reg  [7 :0]	    c3_p1_wr_mask;
reg  [63:0]	    c3_p1_wr_data;
wire			c3_p1_wr_full;
wire			c3_p1_wr_empty;
wire [6 :0]		c3_p1_wr_count;
wire			c3_p1_wr_underrun;
wire			c3_p1_wr_error;

wire			c3_p1_rd_en;
wire [63:0]	    c3_p1_rd_data;
wire			c3_p1_rd_full;
wire			c3_p1_rd_empty;
wire [6 :0]		c3_p1_rd_count;
wire			c3_p1_rd_overflow;
wire			c3_p1_rd_error;

// ddr3 wr variable
wire ddr3_clk;
reg  wr_addr_rst_en;               //level pulse
reg  [29: 0] wr_start_addr_byte;	
reg  [2 : 0] wr_state;


// ddr3 rd variable
reg  rd_addr_rst_en;               //level pulse
reg  [29: 0] rd_start_addr_byte;
reg  [2 : 0] rd_state;


// ddr3 wr status
parameter write_idle      =3'b000;
parameter write_fifo      =3'b001;
parameter write_data_done =3'b010;
parameter write_cmd_start =3'b011;
parameter write_cmd       =3'b100;
parameter write_done      =3'b101;

// ddr3 rd status
parameter read_idle       =3'b000;
parameter read_cmd_start  =3'b001;
parameter read_cmd        =3'b010;
parameter read_wait       =3'b011;
parameter read_data       =3'b100;
parameter read_done       =3'b101;


//______________________ Main Body of Code ______________________ 
assign  ddr3_clk = c3_clk0;  
assign  c3_p1_rd_en = pos_ddr3_rd_en;
assign  ddr3_data_vga_o = c3_p1_rd_data;

//------------------------------------------------------------
//      video capture模块与ddr3 ctr模块二者处于不同的时钟域,
//      故需要对二者连接信号进行脉宽转化,转化为本地时钟域信号
//------------------------------------------------------------
reg  ddr3_wren_r1, ddr3_wren_r2;
reg  ddr3_wr_addr_rst_r1, ddr3_wr_addr_rst_r2;

reg  ddr3_rd_addr_rst_r1, ddr3_rd_addr_rst_r2;
reg  ddr3_rd_req_r1, ddr3_rd_req_r2;
reg  ddr3_rd_en_r1,  ddr3_rd_en_r2;

wire pos_ddr3_wren,  pos_ddr3_wr_addr_rst;
wire pos_ddr3_rd_en, pos_ddr3_rd_req, pos_ddr3_rd_addr_rst;

//always@(posedge ddr3_clk)
//    if(c3_rst0 || (!c3_calib_done)) begin
//	    ddr3_wren_r1 		<= 0; 
//		ddr3_wren_r2 		<= 0;
//		ddr3_wr_addr_rst_r1 <= 0;
//		ddr3_wr_addr_rst_r2 <= 0;
//		
//		ddr3_rd_addr_rst_r1 <= 0;
//		ddr3_rd_addr_rst_r2 <= 0;
//		ddr3_rd_req_r1      <= 0;
//		ddr3_rd_req_r2      <= 0;
//		ddr3_rd_en_r1       <= 0;
//		ddr3_rd_en_r2       <= 0;	
//	end
//	else begin
//	    ddr3_wren_r1 		<= ddr3_wren_i; 
//		ddr3_wren_r2 		<= ddr3_wren_r1;
//		ddr3_wr_addr_rst_r1 <= ddr3_wr_addr_rst_i;
//		ddr3_wr_addr_rst_r2 <= ddr3_wr_addr_rst_r1;
//		
//		ddr3_rd_addr_rst_r1 <= ddr3_rd_addr_rst_i;
//		ddr3_rd_addr_rst_r2 <= ddr3_rd_addr_rst_r1;
//		ddr3_rd_req_r1      <= ddr3_rd_req_i;
//		ddr3_rd_req_r2      <= ddr3_rd_req_r1;
//		ddr3_rd_en_r1       <= ddr3_rd_en_i;
//		ddr3_rd_en_r2       <= ddr3_rd_en_r1; 
//	end

assign  pos_ddr3_wren 		 = ddr3_wren_r1 	   & (~ddr3_wren_r2);
assign  pos_ddr3_wr_addr_rst = ddr3_wr_addr_rst_r1 & (~ddr3_wr_addr_rst_r2);
assign  pos_ddr3_rd_addr_rst = ddr3_rd_addr_rst_r1 & (~ddr3_rd_addr_rst_r2);
assign  pos_ddr3_rd_req      = ddr3_rd_req_r1      & (~ddr3_rd_req_r2);
assign  pos_ddr3_rd_en       = ddr3_rd_en_r1       & (~ddr3_rd_en_r2);


// Process: reset ddr3 p0 interface wr start address
always@(posedge camera_pclk_i)
    if(c3_rst0 || (!c3_calib_done)) begin
	    ddr3_wren_r1 		<= 0; 
		ddr3_wren_r2 		<= 0;
		ddr3_wr_addr_rst_r1 <= 0;
		ddr3_wr_addr_rst_r2 <= 0;
		
//		ddr3_rd_addr_rst_r1 <= 0;
//		ddr3_rd_addr_rst_r2 <= 0;
//		ddr3_rd_req_r1      <= 0;
//		ddr3_rd_req_r2      <= 0;
//		ddr3_rd_en_r1       <= 0;
//		ddr3_rd_en_r2       <= 0;	
	end
	else begin
	    ddr3_wren_r1 		<= ddr3_wren_i; 
		ddr3_wren_r2 		<= ddr3_wren_r1;
		ddr3_wr_addr_rst_r1 <= ddr3_wr_addr_rst_i;
		ddr3_wr_addr_rst_r2 <= ddr3_wr_addr_rst_r1;
		
//		ddr3_rd_addr_rst_r1 <= ddr3_rd_addr_rst_i;
//		ddr3_rd_addr_rst_r2 <= ddr3_rd_addr_rst_r1;
//		ddr3_rd_req_r1      <= ddr3_rd_req_i;
//		ddr3_rd_req_r2      <= ddr3_rd_req_r1;
//		ddr3_rd_en_r1       <= ddr3_rd_en_i;
//		ddr3_rd_en_r2       <= ddr3_rd_en_r1; 
	end




always@(posedge camera_pclk_i)
    if(c3_rst0 || (!c3_calib_done)) begin
	    wr_addr_rst_en <= 0;
		wr_start_addr_byte <= 0;  
	end
	else begin
	    if(pos_ddr3_wr_addr_rst) begin
		    wr_addr_rst_en <= 1;         
			case(frame_switch_i)
			    2'b00: wr_start_addr_byte <= 0;
				2'b01: wr_start_addr_byte <= 1000_0000;
				2'b10: wr_start_addr_byte <= 2000_0000;
				2'b11: wr_start_addr_byte <= 3000_0000;
                default: wr_start_addr_byte <= 0;				
			endcase
		end
		else begin
		    wr_addr_rst_en <= 0;
		    wr_start_addr_byte <= wr_start_addr_byte; 
		end
	end


// Process: camera data wr to ddr3 relative fragment
always@(posedge camera_pclk_i)
    if(c3_rst0 || (!c3_calib_done)) begin
	    c3_p0_wr_en   <= 0;
		c3_p0_wr_mask <= 0;
		c3_p0_wr_data <= 0;
		c3_p0_cmd_en  <=1'b0;
        c3_p0_cmd_instr <=3'd0;
        c3_p0_cmd_bl    <=6'd0;
        c3_p0_cmd_byte_addr <=30'd0;
        wr_state        <=write_idle;		
	end
	else begin
	    if(wr_addr_rst_en) begin
		    c3_p0_cmd_byte_addr <= wr_start_addr_byte;
	//		wr_state  <=write_idle;	
		end
		else begin
		    case(wr_state)
			    write_idle: begin
				    c3_p0_wr_en   <= 0;
		            c3_p0_wr_mask <= 0;
		            if(pos_ddr3_wren) begin
					    c3_p0_wr_data <= ddr3_data_camera_i;
						wr_state <= write_fifo;
					end
				end
				
				write_fifo: begin
				    if(!c3_p0_wr_full) begin             //如p0写fifo数据不满,写入FIFO
					    c3_p0_wr_en <= 1'b1;    
				        wr_state    <= write_data_done;
				    end	 
				end
				
				write_data_done: begin
				    c3_p0_wr_en <= 0;  
					wr_state    <= write_cmd_start;
				end
				
				write_cmd_start:begin
					c3_p0_cmd_en   <=1'b0;                    
					c3_p0_cmd_instr<=3'b010;           //010为写命令
					c3_p0_cmd_bl   <=6'd0;             //burst length为1
					wr_state       <=write_cmd;
			    end
			
				write_cmd:begin
					if (!c3_p0_cmd_full) begin            
						c3_p0_cmd_en <=1'b1;           
						wr_state     <=write_done;
					end
				end
				
				write_done:begin
					c3_p0_cmd_en   <=1'b0;
					wr_state       <=write_idle;
					c3_p0_cmd_byte_addr <= c3_p0_cmd_byte_addr + 8;	   // byte * 8 = 64 bits
				end
								
			    default: begin
				    wr_state <=write_idle;
                    c3_p0_wr_en   <= 0;
					c3_p0_wr_mask <= 0;
					c3_p0_wr_data <= 0;
					c3_p0_cmd_en  <=1'b0;
					c3_p0_cmd_instr <=3'd0;
					c3_p0_cmd_bl    <=6'd0;
					c3_p0_cmd_byte_addr <=30'd0;
				end	
					
			endcase
		end
	end



// Process: rd ddr3 relative fragment data to vga display
always@(posedge vga_clk_o)
    if(c3_rst0 || (!c3_calib_done)) begin
//	    ddr3_wren_r1 		<= 0; 
//		ddr3_wren_r2 		<= 0;
//		ddr3_wr_addr_rst_r1 <= 0;
//		ddr3_wr_addr_rst_r2 <= 0;
		
		ddr3_rd_addr_rst_r1 <= 0;
		ddr3_rd_addr_rst_r2 <= 0;
		ddr3_rd_req_r1      <= 0;
		ddr3_rd_req_r2      <= 0;
		ddr3_rd_en_r1       <= 0;
		ddr3_rd_en_r2       <= 0;	
	end
	else begin
//	    ddr3_wren_r1 		<= ddr3_wren_i; 
//		ddr3_wren_r2 		<= ddr3_wren_r1;
//		ddr3_wr_addr_rst_r1 <= ddr3_wr_addr_rst_i;
//		ddr3_wr_addr_rst_r2 <= ddr3_wr_addr_rst_r1;
		
		ddr3_rd_addr_rst_r1 <= ddr3_rd_addr_rst_i;
		ddr3_rd_addr_rst_r2 <= ddr3_rd_addr_rst_r1;
		ddr3_rd_req_r1      <= ddr3_rd_req_i;
		ddr3_rd_req_r2      <= ddr3_rd_req_r1;
		ddr3_rd_en_r1       <= ddr3_rd_en_i;
		ddr3_rd_en_r2       <= ddr3_rd_en_r1; 
	end


always@(posedge vga_clk_o)
    if(c3_rst0 || (!c3_calib_done)) begin
	    rd_addr_rst_en <= 0;
		rd_start_addr_byte <= 0;  
	end
	else begin
	    if(pos_ddr3_rd_addr_rst) begin
		    rd_addr_rst_en <= 1;         
			case(frame_switch_i)
			    2'b00: rd_start_addr_byte <= 2000_0000;
				2'b01: rd_start_addr_byte <= 3000_0000;
				2'b10: rd_start_addr_byte <= 0;
				2'b11: rd_start_addr_byte <= 1000_0000;
                default: rd_start_addr_byte <= 0;				
			endcase
		end
		else begin
		    rd_addr_rst_en <= 0;
		    rd_start_addr_byte <= rd_start_addr_byte; 
		end
	end


always@(posedge vga_clk_o)
    if(c3_rst0 || (!c3_calib_done)) begin
		c3_p1_cmd_en    <= 1'b0;
        c3_p1_cmd_instr <= 3'd0;
        c3_p1_cmd_bl    <= 6'd0;
//      c3_p1_cmd_byte_addr <= 2000_0000;
		c3_p1_cmd_byte_addr <= 10000000;
        rd_state    <= read_idle; 
	end
	else begin
        if(rd_addr_rst_en) begin
		    c3_p1_cmd_byte_addr <= rd_start_addr_byte;
	//		rd_state <= read_idle; 
		end
		else begin
		    case(rd_state)
			    read_idle: begin
					c3_p1_cmd_en    <= 1'b0;
					c3_p1_cmd_instr <= 3'd0;
					c3_p1_cmd_bl    <= 6'd0;
					if(pos_ddr3_rd_req) begin 
					    rd_state    <= read_cmd_start;
					end
				end
				
				read_cmd_start:begin
				    c3_p1_cmd_en    <=1'b0;
					c3_p1_cmd_instr <=3'b001;               //鍛戒护瀛椾负璇
					c3_p1_cmd_bl    <=6'd39;                   //40涓暟鎹
					rd_state        <=read_cmd; 
				end						 
				
				read_cmd:begin			
					if(!c3_p1_cmd_full) begin
					    c3_p1_cmd_en    <=1'b1;                    //ddr璇诲懡浠や娇鑳
					    rd_state        <=read_done;
				    end
				end

				read_done:begin
					c3_p1_cmd_en        <= 1'b0; 
					c3_p1_cmd_byte_addr <= c3_p1_cmd_byte_addr+320;    //ddr鐨勮鍦板潃鍔2 (40*64bit/8)
					rd_state            <= read_idle;
				end
							
			    default: begin
				    c3_p1_cmd_en    <= 1'b0;
					c3_p1_cmd_instr <= 3'd0;
					c3_p1_cmd_bl    <= 6'd0;
//					c3_p1_cmd_byte_addr <= 20000000;
					c3_p1_cmd_byte_addr <= 10000000;
					rd_state        <= read_idle; 
				end
			endcase
		end
	end

	

// ddr3 mig ctrol instance
      ddr3_mig #
      (
         .C3_P0_MASK_SIZE                (8),
         .C3_P0_DATA_PORT_SIZE           (64),
         .C3_P1_MASK_SIZE                (8),
         .C3_P1_DATA_PORT_SIZE           (64),			
         .DEBUG_EN                       (0),           //   = 0, Disable debug signals/controls.
         .C3_MEMCLK_PERIOD               (3200),
         .C3_CALIB_SOFT_IP               ("TRUE"),      // # = TRUE, Enables the soft calibration logic,
         .C3_SIMULATION                  ("FALSE"),     // # = FALSE, Implementing the design.
         .C3_RST_ACT_LOW                 (1),           // # = 1 for active low reset         change for AX516 board
         .C3_INPUT_CLK_TYPE              ("SINGLE_ENDED"),
         .C3_MEM_ADDR_ORDER              ("ROW_BANK_COLUMN"),
         .C3_NUM_DQ_PINS                 (16),
         .C3_MEM_ADDR_WIDTH              (13),  
         .C3_MEM_BANKADDR_WIDTH          (3)
         )
      ddr3_mig_inst
      (
         .mcb3_dram_dq			                 (mcb3_dram_dq),
         .mcb3_dram_a			                 (mcb3_dram_a), 
         .mcb3_dram_ba			                 (mcb3_dram_ba),
         .mcb3_dram_ras_n			             (mcb3_dram_ras_n),
         .mcb3_dram_cas_n			             (mcb3_dram_cas_n),
         .mcb3_dram_we_n  	                     (mcb3_dram_we_n),
         .mcb3_dram_odt			                 (mcb3_dram_odt),
         .mcb3_dram_cke                          (mcb3_dram_cke),
         .mcb3_dram_dm                           (mcb3_dram_dm),
         .mcb3_dram_udqs                         (mcb3_dram_udqs),
         .mcb3_dram_udqs_n	                     (mcb3_dram_udqs_n),
         .mcb3_rzq	                             (mcb3_rzq),
         .mcb3_zio	                             (mcb3_zio),
         .mcb3_dram_udm	                         (mcb3_dram_udm),
         .c3_sys_clk	                         (c3_sys_clk),
         .c3_sys_rst_i	                         (c3_sys_rst_n),			
		 .c3_calib_done	                         (c3_calib_done),
         .c3_clk0	                             (c3_clk0),
		 .camera_clk	                         (camera_clk_o),                //AX516: added for camera clock
		 .vga_clk	                             (vga_clk_o),                   //AX516: added for vga clock
         .c3_rst0	                             (c3_rst0),			
	     .mcb3_dram_dqs                          (mcb3_dram_dqs),
	 	 .mcb3_dram_dqs_n	                     (mcb3_dram_dqs_n),
		 .mcb3_dram_ck	                         (mcb3_dram_ck),			
		 .mcb3_dram_ck_n	                     (mcb3_dram_ck_n),				
			
         // User Port-0 command interface
         .c3_p0_cmd_clk                  (camera_pclk_i),          //c3_p0_cmd_clk->c3_clk0			
         .c3_p0_cmd_en                   (c3_p0_cmd_en),
         .c3_p0_cmd_instr                (c3_p0_cmd_instr),
         .c3_p0_cmd_bl                   (c3_p0_cmd_bl),
         .c3_p0_cmd_byte_addr            (c3_p0_cmd_byte_addr),
         .c3_p0_cmd_empty                (c3_p0_cmd_empty),
         .c3_p0_cmd_full                 (p0_cmd_full_o),	
			
         // User Port-0 data write interface 			
         .c3_p0_wr_clk                   (camera_pclk_i),          //c3_p0_wr_clk->c3_clk0
		 .c3_p0_wr_en                    (c3_p0_wr_en),
         .c3_p0_wr_mask                  (c3_p0_wr_mask),
         .c3_p0_wr_data                  (c3_p0_wr_data),
         .c3_p0_wr_full                  (c3_p0_wr_full),
         .c3_p0_wr_empty                 (c3_p0_wr_empty),
         .c3_p0_wr_count                 (c3_p0_wr_count),
         .c3_p0_wr_underrun              (c3_p0_wr_underrun),
         .c3_p0_wr_error                 (c3_p0_wr_error),	
			
         // User Port-0 data read interface 
		 .c3_p0_rd_clk                   (camera_pclk_i),          //c3_p0_rd_clk->c3_clk0
         .c3_p0_rd_en                    (c3_p0_rd_en),
         .c3_p0_rd_data                  (c3_p0_rd_data),
         .c3_p0_rd_full                  (c3_p0_rd_full),			
         .c3_p0_rd_empty                 (c3_p0_rd_empty),
         .c3_p0_rd_count                 (c3_p0_rd_count),
         .c3_p0_rd_overflow              (c3_p0_rd_overflow),
         .c3_p0_rd_error                 (c3_p0_rd_error),
			
			
         // User Port-1 command interface
         .c3_p1_cmd_clk                  (vga_clk_o),          //c3_p1_cmd_clk->c3_clk0			
         .c3_p1_cmd_en                   (c3_p1_cmd_en),
         .c3_p1_cmd_instr                (c3_p1_cmd_instr),
         .c3_p1_cmd_bl                   (c3_p1_cmd_bl),
         .c3_p1_cmd_byte_addr            (c3_p1_cmd_byte_addr),
         .c3_p1_cmd_empty                (c3_p1_cmd_empty),
         .c3_p1_cmd_full                 (p1_cmd_full_o),	
			
         // User Port-1 data write interface 			
         .c3_p1_wr_clk                   (vga_clk_o),          //c3_p1_wr_clk->c3_clk0
		 .c3_p1_wr_en                    (c3_p1_wr_en),
         .c3_p1_wr_mask                  (c3_p1_wr_mask),
         .c3_p1_wr_data                  (c3_p1_wr_data),
         .c3_p1_wr_full                  (c3_p1_wr_full),
         .c3_p1_wr_empty                 (c3_p1_wr_empty),
         .c3_p1_wr_count                 (c3_p1_wr_count),
         .c3_p1_wr_underrun              (c3_p1_wr_underrun),
         .c3_p1_wr_error                 (c3_p1_wr_error),	
			
         // User Port-1 data read interface 
		 .c3_p1_rd_clk                   (vga_clk_o),          //c3_p1_rd_clk->c3_clk0
         .c3_p1_rd_en                    (c3_p1_rd_en),
         .c3_p1_rd_data                  (c3_p1_rd_data),
         .c3_p1_rd_full                  (c3_p1_rd_full),			
         .c3_p1_rd_empty                 (c3_p1_rd_empty),
         .c3_p1_rd_count                 (c3_p1_rd_count),
         .c3_p1_rd_overflow              (c3_p1_rd_overflow),
         .c3_p1_rd_error                 (c3_p1_rd_error)
       );

	   
endmodule

