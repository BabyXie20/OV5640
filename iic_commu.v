  //sclk，sdin数据传输时序代码（i2c写控制代码）
  
  
module iic_commu(iic_clk_i,          //i2c控制接口传输所需时钟，0-400khz，此处为20khz
               iic_rstn_i,     
               camera_clk_i,
			   iic_ack_o,              //应答信号
               iic_data_i,          //sdin接口传输的32位数据
               iic_start_i,             //开始传输标志
               iic_end_o,           //传输结束标志
               iic_sclk_o,          //FPGA与camera iic时钟接口
               iic_sda);         //FPGA与camera iic数据接口
    input [31:0]iic_data_i;
    input iic_rstn_i;
    input iic_clk_i;
	input camera_clk_i;
    output iic_ack_o;
    input iic_start_i;
    output iic_end_o;
    output iic_sclk_o;
    inout iic_sda;
    reg [5:0] cyc_count;
    reg reg_sdat;
    reg sclk;
    reg ack1,ack2,ack3;
    reg iic_end_o;
 
   
    wire iic_sclk_o;
    wire iic_sda;
    wire iic_ack_o;
   
    // assign iic_ack_o=ack1|ack2|ack3;
    // assign iic_sclk_o=sclk|(((cyc_count>=4)&(cyc_count<=39))?~iic_clk_i:0);
	// assign iic_sclk_o = sclk | (~iic_clk_i);
    // assign iic_sda=reg_sdat?1'bz:0;
   
   
    // always@(posedge iic_clk_i or  negedge iic_rstn_i)
    // begin
       // if(!iic_rstn_i)
         // cyc_count<=6'b111111;
       // else 
		   // begin
           // if(iic_start_i==0)
             // cyc_count<=0;
           // else if(cyc_count<6'b111111)
             // cyc_count<=cyc_count+1;
         // end
    // end

//----------------------------------------------------------------
reg  [15:0] iic_clk_cnt;
reg  iic_clk_r;
parameter  Div_20K = 1200 - 1;

assign iic_ack_o=ack1|ack2|ack3;
assign iic_sclk_o = sclk | (((cyc_count>=3)&(cyc_count<=39)) ? iic_clk_r : 0);	// 核心语句
assign iic_sda=reg_sdat?1'bz:0;

always@(posedge camera_clk_i or negedge iic_rstn_i)
    if(~iic_rstn_i) begin
	    iic_clk_r   <= 1;
		iic_clk_cnt <= 0;
		cyc_count   <= 6'b111111;
	end
	else begin
	    if((~iic_start_i) || (iic_clk_cnt == Div_20K)) begin
            iic_clk_cnt <= 0;
		end
		else begin
		    iic_clk_cnt <= iic_clk_cnt + 1;
		end
		
		if(iic_start_i == 0) begin			
			cyc_count <= 6'b111111;
		end
		else if(cyc_count == 6'b111110) begin
		    cyc_count <= cyc_count;
		end
		else if(iic_clk_cnt == 100) begin
            cyc_count <= cyc_count + 1;
		end
		
		if(iic_clk_cnt == 0) begin
		    iic_clk_r   <= 0;
		end
		else if(iic_clk_cnt == 200) begin
		    iic_clk_r   <= 1;
		end
		else if(iic_clk_cnt == 800) begin
		    iic_clk_r   <= 0;
		end		
	end
//----------------------------------------------------------------	

	 
    always@(posedge camera_clk_i or negedge iic_rstn_i)
    begin
       if(!iic_rstn_i)
       begin
          iic_end_o<=0;
          ack1<=1;
          ack2<=1;
          ack3<=1;
          sclk<=1;
          reg_sdat<=1;
       end
       else
          case(cyc_count)
          0:begin ack1<=1;ack2<=1;ack3<=1;iic_end_o<=0;sclk<=1;reg_sdat<=1;end
          1:reg_sdat<=0;                 //开始传输
          2:sclk<=0;
          3:reg_sdat<=iic_data_i[31];
          4:reg_sdat<=iic_data_i[30];
          5:reg_sdat<=iic_data_i[29];
          6:reg_sdat<=iic_data_i[28];
          7:reg_sdat<=iic_data_i[27];
          8:reg_sdat<=iic_data_i[26];
          9:reg_sdat<=iic_data_i[25];
          10:reg_sdat<=iic_data_i[24];
          11:reg_sdat<=1;                //应答信号
          12:begin reg_sdat<=iic_data_i[23];ack1<=iic_sda;end
          13:reg_sdat<=iic_data_i[22];
          14:reg_sdat<=iic_data_i[21];
          15:reg_sdat<=iic_data_i[20];
          16:reg_sdat<=iic_data_i[19];
          17:reg_sdat<=iic_data_i[18];
          18:reg_sdat<=iic_data_i[17];
          19:reg_sdat<=iic_data_i[16];
          20:reg_sdat<=1;                //应答信号       
          21:begin reg_sdat<=iic_data_i[15];ack1<=iic_sda;end
          22:reg_sdat<=iic_data_i[14];
          23:reg_sdat<=iic_data_i[13];
          24:reg_sdat<=iic_data_i[12];
          25:reg_sdat<=iic_data_i[11];
          26:reg_sdat<=iic_data_i[10];
          27:reg_sdat<=iic_data_i[9];
          28:reg_sdat<=iic_data_i[8];
          29:reg_sdat<=1;                //应答信号       
          30:begin reg_sdat<=iic_data_i[7];ack2<=iic_sda;end
          31:reg_sdat<=iic_data_i[6];
          32:reg_sdat<=iic_data_i[5];
          33:reg_sdat<=iic_data_i[4];
          34:reg_sdat<=iic_data_i[3];
          35:reg_sdat<=iic_data_i[2];
          36:reg_sdat<=iic_data_i[1];
          37:reg_sdat<=iic_data_i[0];
          38:reg_sdat<=1;                //应答信号       
          39:begin ack3<=iic_sda;sclk<=0;reg_sdat<=0;end
          40:sclk<=1;
          41:begin reg_sdat<=1;iic_end_o<=1;end
          endcase
       
end
endmodule









/*
`timescale 1ns / 1ps
//----------------------------------------------------------------------// 
//    Module: iic interface commu. for sensor register config.          //
//----------------------------------------------------------------------//
//    Version: V1_0  => program creat,  2018+08+24, by caoxun           //
//----------------------------------------------------------------------//

module iic_commu(
    input  wire  iic_clk_i,
	input  wire  iic_rstn_i,
	
	output wire  iic_ack_o,
	input  wire  iic_start_i,
	output wire  iic_end_o,
	input  wire  [31:0] iic_data_i,
	
	output wire  iic_sclk_o,
	inout  tri   iic_sda

);


//______________________ Variable Declare ______________________
reg  sclk_ce;
reg  sda_io, sda_reg;
reg  iic_end;
reg  iic_ack1, iic_ack2, iic_ack3, iic_ack4;
reg  [9 : 0] cycle_cnt;

parameter  CycleNum = 63;


//______________________ Main Body of Code ______________________

// 璁惧畾sda_io涓轰笁鎬侀棬鐨勬柟鍚戞帶鍒剁鑴鏈緥sda_io=1鏃iic_sda浜嶧PGA鐢ㄤ綔杈撳叆
assign  iic_sda = sda_io ? 1'dz : sda_reg;    // iic_sda鐢佃矾寮曡剼澶栭儴涓婃媺
assign  iic_sclk_o = sclk_ce | (~iic_clk_i);
assign  iic_ack_o  = iic_ack1 | iic_ack2 | iic_ack3 | iic_ack4;


// Process: write init value to sensor register by iic interface
always@(posedge iic_clk_i)
    if((~iic_rstn_i) | (~iic_start_i)) begin
		cycle_cnt <= 0;
	end
	else if((cycle_cnt == CycleNum) && (iic_ack1 | iic_ack2 | iic_ack3 | iic_ack4)) begin
	    cycle_cnt <= 0;  // 鍑虹幇鏃犳晥ack鏃閲嶅鍙戦�佽iic閫氫俊鏁版嵁
	end
	else if(cycle_cnt < CycleNum) begin
	    cycle_cnt <= cycle_cnt + 1;
	end

	
always@(posedge iic_clk_i)
    if(~iic_rstn_i) begin
	    sclk_ce <= 1;
	    sda_io  <= 1;
		sda_reg <= 1;
		iic_end <= 0;
		iic_ack1 <= 1;
		iic_ack2 <= 1;
		iic_ack3 <= 1;
		iic_ack4 <= 1;
	end
	else begin
	    case(cycle_cnt)
		    10'd0: begin
			    sda_io <= 1;   sda_reg <= 1; iic_end <= 0;  sclk_ce <= 1;
				iic_ack1 <= 1; iic_ack2 <= 1; iic_ack3 <= 1; iic_ack4 <= 1;
			end
			
			10'd1: begin
			    sda_io <=  0;	// iic_sda output to slave device
			    sda_reg <= 0;
			end
			
			10'd2: ;  //begin sclk_ce <= 0; end     // Start Bit Timing: firstly,sda = 0;  secondly, sclk_ce = 0
						
			// trans slave device address
			10'd3:  begin sda_io <=  0; sclk_ce <= 0; sda_reg <= iic_data_i[31]; end  // Start Bit
			10'd4:  begin sda_io <=  0; sclk_ce <= 0; sda_reg <= iic_data_i[30]; end
			10'd5:  begin sda_io <=  0; sclk_ce <= 0; sda_reg <= iic_data_i[29]; end
			10'd6:  begin sda_io <=  0; sclk_ce <= 0; sda_reg <= iic_data_i[28]; end
			10'd7:  begin sda_io <=  0; sclk_ce <= 0; sda_reg <= iic_data_i[27]; end
			10'd8:  begin sda_io <=  0; sclk_ce <= 0; sda_reg <= iic_data_i[26]; end
			10'd9:  begin sda_io <=  0; sclk_ce <= 0; sda_reg <= iic_data_i[25]; end
			10'd10: begin sda_io <=  0; sclk_ce <= 0; sda_reg <= iic_data_i[24]; end			
			// wait iic device acknow
			10'd11: begin sda_io <=  1; end	// iic_sda input from slave device
			
			// trans high byte word address and receiv prev iic_ack_o
			10'd12: begin
			    sda_io <=  0; sclk_ce <= 0; iic_ack1 <= iic_sda;
				sda_reg <= iic_data_i[23];  
			end
			10'd13:  begin sda_io <=  0; sclk_ce <= 0; sda_reg <= iic_data_i[22]; end
			10'd14:  begin sda_io <=  0; sclk_ce <= 0; sda_reg <= iic_data_i[21]; end
			10'd15:  begin sda_io <=  0; sclk_ce <= 0; sda_reg <= iic_data_i[20]; end
			10'd16:  begin sda_io <=  0; sclk_ce <= 0; sda_reg <= iic_data_i[19]; end
			10'd17:  begin sda_io <=  0; sclk_ce <= 0; sda_reg <= iic_data_i[18]; end
			10'd18:  begin sda_io <=  0; sclk_ce <= 0; sda_reg <= iic_data_i[17]; end
			10'd19:  begin sda_io <=  0; sclk_ce <= 0; sda_reg <= iic_data_i[16]; end
			10'd20:  begin sda_io <=  1; end  // iic iic_ack_o
			
			// trans low byte word address and receiv prev iic_ack_o
			10'd21: begin
			    sda_io <=  0; sclk_ce <= 0; iic_ack2 <= iic_sda;
				sda_reg <= iic_data_i[15];  
			end
			10'd22:  begin sda_io <=  0; sclk_ce <= 0; sda_reg <= iic_data_i[14]; end
			10'd23:  begin sda_io <=  0; sclk_ce <= 0; sda_reg <= iic_data_i[13]; end
			10'd24:  begin sda_io <=  0; sclk_ce <= 0; sda_reg <= iic_data_i[12]; end
			10'd25:  begin sda_io <=  0; sclk_ce <= 0; sda_reg <= iic_data_i[11]; end
			10'd26:  begin sda_io <=  0; sclk_ce <= 0; sda_reg <= iic_data_i[10]; end
			10'd27:  begin sda_io <=  0; sclk_ce <= 0; sda_reg <= iic_data_i[9]; end
			10'd28:  begin sda_io <=  0; sclk_ce <= 0; sda_reg <= iic_data_i[8]; end
			10'd29:  begin sda_io <=  1; end  // iic iic_ack_o
			
			// trans low byte word address and receiv prev iic_ack_o
			10'd30: begin
			    sda_io <=  0; sclk_ce <= 0; iic_ack3 <= iic_sda;
				sda_reg <= iic_data_i[7];  
			end
			10'd31:  begin sda_io <=  0; sclk_ce <= 0; sda_reg <= iic_data_i[6]; end
			10'd32:  begin sda_io <=  0; sclk_ce <= 0; sda_reg <= iic_data_i[5]; end
			10'd33:  begin sda_io <=  0; sclk_ce <= 0; sda_reg <= iic_data_i[4]; end
			10'd34:  begin sda_io <=  0; sclk_ce <= 0; sda_reg <= iic_data_i[3]; end
			10'd35:  begin sda_io <=  0; sclk_ce <= 0; sda_reg <= iic_data_i[2]; end
			10'd36:  begin sda_io <=  0; sclk_ce <= 0; sda_reg <= iic_data_i[1]; end
			10'd37:  begin sda_io <=  0; sclk_ce <= 0; sda_reg <= iic_data_i[0]; end
			10'd38:  begin sda_io <=  1; end  // iic iic_ack_o
			
			10'd39:  begin iic_ack4 <= iic_sda; sda_io <=  0; sclk_ce <= 0; end
			10'd40:  begin sclk_ce <= 1; end
			10'd41:  begin sda_reg <= 1; iic_end <= 1; end
			
		    default: begin
			    sda_io <= 1;   sda_reg <= 1; iic_end <= 0;  sclk_ce <= 1;
				iic_ack1 <= 1; iic_ack2 <= 1; iic_ack3 <= 1; iic_ack4 <= 1;
			end
		endcase
	end	

endmodule

*/









