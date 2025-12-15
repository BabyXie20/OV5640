module tlc_stage1_top(
    input         CLOCK_50,
    input  [3:0]  KEY,
    input  [9:0]  SW,
    output [9:0]  LEDR,
    output [6:0]  HEX0,
    output [6:0]  HEX1,
    output [6:0]  HEX2,
    output [6:0]  HEX3,
    output [6:0]  HEX4,
    output [6:0]  HEX5,
    output [7:0]  VGA_R,
    output [7:0]  VGA_G,
    output [7:0]  VGA_B,
    output        VGA_HS,
    output        VGA_VS,
    output        VGA_BLANK_N,
    output        VGA_SYNC_N,
    output        VGA_CLK,
    input         PS2_CLK,
    input         PS2_DAT,
    inout  [5:0]  GPIO_0,
    inout  [5:0]  GPIO_1,

    // 画中画摄像头输入（RGB888 + 有效 + 缩放档位）
    input  [7:0]  pip_cam_r,
    input  [7:0]  pip_cam_g,
    input  [7:0]  pip_cam_b,
    input         pip_cam_valid,
    input  [1:0]  pip_zoom
);

    //================================================
    // 0. 模式 / 状态编码
    //================================================
    localparam [1:0] MODE_FIXED = 2'b00;
    localparam [1:0] MODE_ACT   = 2'b01;
    localparam [1:0] MODE_NIGHT = 2'b10;
    localparam [1:0] MODE_LOCK  = 2'b11;

    localparam [3:0]
        S_NS_GREEN  = 4'd0,
        S_NS_YELLOW = 4'd1,
        S_ALL_RED_1 = 4'd2,
        S_EW_GREEN  = 4'd3,
        S_EW_YELLOW = 4'd4,
        S_ALL_RED_2 = 4'd5;

    //================================================
    // 交通灯核心输出
    //================================================
    wire [2:0] light_ns;  // {R,Y,G}
    wire [2:0] light_ew;  // {R,Y,G}
    wire [3:0] phase_id;
    wire [7:0] time_left;

    //================================================
    // 小车参数
    //================================================
    localparam [9:0] CAR_SIZE       = 10'd10;
    localparam [9:0] CAR_NS_Y_START = 10'd0;
    localparam [9:0] CAR_NS_Y_MAX   = 10'd480 - CAR_SIZE;

    localparam [9:0] CAR_EW_X_START = 10'd0;
    localparam [9:0] CAR_EW_X_MAX   = 10'd640 - CAR_SIZE;

    localparam [3:0] CAR_STEP_PIX   = 4'd8;

    // 与 crossroad_pattern 对齐的几何常量
    localparam [9:0] V_ROAD_X_L = 10'd260;
    localparam [9:0] V_ROAD_X_R = 10'd380;
    localparam [9:0] H_ROAD_Y_T = 10'd180;
    localparam [9:0] H_ROAD_Y_B = 10'd300;

    localparam [9:0] CAR_NS_LEN = 10'd20;
    localparam [9:0] CAR_EW_LEN = 10'd20;

    reg [9:0] car_n_y;
    reg [9:0] car_s_y;
    reg [9:0] car_w_x;
    reg [9:0] car_e_x;

    //================================================
    // 1. 复位与键盘复位整合
    //================================================
    wire rst_button_n = KEY[0];  // 按下为0
    wire rst_n;

    //================================================
    // 2. PS/2 底层接收 + 键盘解码
    //================================================
    wire [7:0] kb_scan;
    wire       kb_new;

    ps2 u_ps2 (
        .clock_key (PS2_CLK),
        .data_key  (PS2_DAT),
        .clock_fpga(CLOCK_50),
        .reset     (rst_button_n),
        .led       (),
        .data_out  (kb_scan),
        .new_code  (kb_new)
    );

    wire [1:0] mode_sel_kbd;
    wire       veh_NS_level_kbd, veh_EW_level_kbd;
    wire       veh_NS_pulse_kbd, veh_EW_pulse_kbd;
    wire       reset_pulse_kbd;
    wire       ns_up, ns_down, ew_left, ew_right;
    wire       ped_NS_req_kbd, ped_EW_req_kbd;

    ps2_keyboard u_kbd (
        .clk          (CLOCK_50),
        .rst_n        (rst_button_n),

        .scan_code    (kb_scan),
        .new_code     (kb_new),

        .mode_sel     (mode_sel_kbd),

        .veh_NS_level (veh_NS_level_kbd),
        .veh_EW_level (veh_EW_level_kbd),
        .veh_NS_pulse (veh_NS_pulse_kbd),
        .veh_EW_pulse (veh_EW_pulse_kbd),
        .reset_pulse  (reset_pulse_kbd),

        .ns_up        (ns_up),
        .ns_down      (ns_down),
        .ew_left      (ew_left),
        .ew_right     (ew_right),

        .ped_NS_req   (ped_NS_req_kbd),
        .ped_EW_req   (ped_EW_req_kbd)
    );

    assign rst_n = rst_button_n & ~reset_pulse_kbd;

    //================================================
    // 3. 模式选择
    //================================================
    wire [1:0] mode_sel = mode_sel_kbd;

    //================================================
    // 4. 感应输入（车辆检测）
    //================================================
    wire veh_NS_level = veh_NS_level_kbd;
    wire veh_EW_level = veh_EW_level_kbd;

    wire veh_NS_btn = veh_NS_pulse_kbd;
    wire veh_EW_btn = veh_EW_pulse_kbd;

    reg veh_NS_req;
    reg veh_EW_req;

    always @(posedge CLOCK_50 or negedge rst_n) begin
        if (!rst_n) begin
            veh_NS_req <= 1'b0;
            veh_EW_req <= 1'b0;
        end else if (mode_sel == MODE_ACT) begin
            if (veh_NS_btn)                  veh_NS_req <= 1'b1;
            else if (phase_id == S_NS_GREEN) veh_NS_req <= 1'b0;

            if (veh_EW_btn)                  veh_EW_req <= 1'b1;
            else if (phase_id == S_EW_GREEN) veh_EW_req <= 1'b0;
        end else begin
            veh_NS_req <= 1'b0;
            veh_EW_req <= 1'b0;
        end
    end

    wire veh_NS = veh_NS_level | veh_NS_req;
    wire veh_EW = veh_EW_level | veh_EW_req;

    //================================================
    // 5. 交通灯 1s 节拍
    //================================================
    wire tick_1s;
    clk_div_sec u_clk_div(
        .clk     (CLOCK_50),
        .rst_n   (rst_n),
        .tick_1s (tick_1s)
    );

    //================================================
    // 5.5 HC-SR04 行人请求输入（两路：NS / EW）
    //   你的接线：
    //     NS: TRIG=GPIO_0[4], ECHO=GPIO_0[5]
    //     EW: TRIG=GPIO_1[4], ECHO=GPIO_1[5]
    //================================================
    wire hcsr_ns_trig, hcsr_ew_trig;

    // Echo 作为输入：给这两位一个 Z 驱动，确保不会被 FPGA 输出误驱动
    assign GPIO_0[5] = 1'bz;
    assign GPIO_1[5] = 1'bz;

    wire hcsr_ns_echo = GPIO_0[5];
    wire hcsr_ew_echo = GPIO_1[5];

    // Trig 输出到对应 GPIO
    assign GPIO_0[4] = hcsr_ns_trig;
    assign GPIO_1[4] = hcsr_ew_trig;

    wire ped_NS_req_hc;
    wire ped_EW_req_hc;

    hcsr04_ped #(
        .THRESH_CM (20),
        .PULSE_MS  (50),
        .PERIOD_MS (60)
    ) u_hc_ns (
        .clk      (CLOCK_50),
        .rst_n    (rst_n),
        .echo_in  (hcsr_ns_echo),
        .trig_out (hcsr_ns_trig),
        .ped_req  (ped_NS_req_hc)
    );

    hcsr04_ped #(
        .THRESH_CM (20),
        .PULSE_MS  (50),
        .PERIOD_MS (60)
    ) u_hc_ew (
        .clk      (CLOCK_50),
        .rst_n    (rst_n),
        .echo_in  (hcsr_ew_echo),
        .trig_out (hcsr_ew_trig),
        .ped_req  (ped_EW_req_hc)
    );

    // 键盘请求 OR 超声波请求
    wire ped_NS_req = ped_NS_req_kbd | ped_NS_req_hc;
    wire ped_EW_req = ped_EW_req_kbd | ped_EW_req_hc;

    //================================================
    // 6. 交通灯核心状态机
    //================================================
    tlc_core_stage1 u_core(
        .clk       (CLOCK_50),
        .rst_n     (rst_n),
        .tick_1s   (tick_1s),
        .mode_sel  (mode_sel),
        .veh_NS    (veh_NS),
        .veh_EW    (veh_EW),
        .ped_NS    (ped_NS_req),
        .ped_EW    (ped_EW_req),
        .light_ns  (light_ns),
        .light_ew  (light_ew),
        .phase_id  (phase_id),
        .time_left (time_left)
    );

    //================================================
    // 7. 顶层拆分：NS / EW 独立倒计时
    //================================================
    reg [7:0] time_left_ns;
    reg [7:0] time_left_ew;

    always @(*) begin
        time_left_ns = 8'd0;
        time_left_ew = 8'd0;

        if (mode_sel == MODE_FIXED || mode_sel == MODE_ACT) begin
            case (phase_id)
                S_NS_GREEN,
                S_NS_YELLOW: begin
                    time_left_ns = time_left;
                    time_left_ew = 8'd0;
                end
                S_EW_GREEN,
                S_EW_YELLOW: begin
                    time_left_ns = 8'd0;
                    time_left_ew = time_left;
                end
                default: begin
                    time_left_ns = 8'd0;
                    time_left_ew = 8'd0;
                end
            endcase
        end
    end

    wire [3:0] ns_ones;
    wire [3:0] ns_tens;
    wire [3:0] ew_ones;
    wire [3:0] ew_tens;

    assign ns_tens = time_left_ns / 10;
    assign ns_ones = time_left_ns % 10;
    assign ew_tens = time_left_ew / 10;
    assign ew_ones = time_left_ew % 10;

    wire [3:0] mode_num  = {2'b00, mode_sel} + 4'd1;
    wire [3:0] mode_ones = mode_num % 10;

    //================================================
    // 8. LED / HEX
    //================================================
    assign LEDR[2:0] = light_ns;
    assign LEDR[5:3] = light_ew;
    assign LEDR[9:6] = 4'b0000;

    hex7seg u_hex0(.hex(ns_ones),   .seg(HEX0));
    hex7seg u_hex1(.hex(ns_tens),   .seg(HEX1));
    hex7seg u_hex2(.hex(ew_ones),   .seg(HEX2));
    hex7seg u_hex3(.hex(ew_tens),   .seg(HEX3));
    hex7seg u_hex4(.hex(phase_id),  .seg(HEX4));
    hex7seg u_hex5(.hex(mode_ones), .seg(HEX5));

    //================================================
    // 9. 外接红黄绿灯模块：GPIO_0[2:0] / GPIO_1[2:0]
    //================================================
    assign GPIO_0[0] = light_ns[2]; // NS_R
    assign GPIO_0[1] = light_ns[0]; // NS_G
    assign GPIO_0[2] = light_ns[1]; // NS_Y

    assign GPIO_1[0] = light_ew[2]; // EW_R
    assign GPIO_1[1] = light_ew[0]; // EW_G
    assign GPIO_1[2] = light_ew[1]; // EW_Y

    // GPIO_0[3] / GPIO_1[3] 未使用，保持高阻
    assign GPIO_0[3] = 1'bz;
    assign GPIO_1[3] = 1'bz;

    //================================================
    // 10. VGA 像素时钟 25 MHz
    //================================================
    reg pixclk_reg;
    always @(posedge CLOCK_50 or negedge rst_n) begin
        if (!rst_n) pixclk_reg <= 1'b0;
        else        pixclk_reg <= ~pixclk_reg;
    end
    wire pixel_clk = pixclk_reg;
    assign VGA_CLK = pixel_clk;

    //================================================
    // 11. 小车 5Hz 节拍
    //================================================
    reg [25:0] car_div_cnt;
    reg        tick_car;

    always @(posedge CLOCK_50 or negedge rst_n) begin
        if (!rst_n) begin
            car_div_cnt <= 26'd0;
            tick_car    <= 1'b0;
        end else begin
            if (car_div_cnt == 26'd4_999_999) begin
                car_div_cnt <= 26'd0;
                tick_car    <= 1'b1;
            end else begin
                car_div_cnt <= car_div_cnt + 26'd1;
                tick_car    <= 1'b0;
            end
        end
    end

    //================================================
    // 12. 小车位置更新（支持多键同时按：四个 if 不互斥）
    //================================================
    always @(posedge CLOCK_50 or negedge rst_n) begin
        if (!rst_n) begin
            car_n_y <= CAR_NS_Y_MAX;
            car_s_y <= CAR_NS_Y_START;
            car_w_x <= CAR_EW_X_MAX;
            car_e_x <= CAR_EW_X_START;
        end else if (tick_car) begin
            if (ns_up) begin
                if (car_n_y > CAR_NS_Y_START + CAR_STEP_PIX) car_n_y <= car_n_y - CAR_STEP_PIX;
                else                                        car_n_y <= CAR_NS_Y_MAX;
            end
            if (ns_down) begin
                if (car_s_y + CAR_STEP_PIX < CAR_NS_Y_MAX)  car_s_y <= car_s_y + CAR_STEP_PIX;
                else                                        car_s_y <= CAR_NS_Y_START;
            end
            if (ew_left) begin
                if (car_w_x > CAR_EW_X_START + CAR_STEP_PIX) car_w_x <= car_w_x - CAR_STEP_PIX;
                else                                         car_w_x <= CAR_EW_X_MAX;
            end
            if (ew_right) begin
                if (car_e_x + CAR_STEP_PIX < CAR_EW_X_MAX)   car_e_x <= car_e_x + CAR_STEP_PIX;
                else                                         car_e_x <= CAR_EW_X_START;
            end
        end
    end

    //================================================
    // 13. 闯红灯判定（保留你现有逻辑）
    //================================================
    wire red_ns = light_ns[2];
    wire red_ew = light_ew[2];

    reg viol_n, viol_s, viol_w, viol_e;

    always @(posedge CLOCK_50 or negedge rst_n) begin
        if (!rst_n) begin
            viol_n <= 1'b0;
            viol_s <= 1'b0;
            viol_w <= 1'b0;
            viol_e <= 1'b0;
        end else if (tick_car) begin
            if (ns_up    && !(car_n_y > (CAR_NS_Y_START + CAR_STEP_PIX))) viol_n <= 1'b0;
            if (ns_down  && !((car_s_y + CAR_STEP_PIX) < CAR_NS_Y_MAX))   viol_s <= 1'b0;
            if (ew_left  && !(car_w_x > (CAR_EW_X_START + CAR_STEP_PIX))) viol_w <= 1'b0;
            if (ew_right && !((car_e_x + CAR_STEP_PIX) < CAR_EW_X_MAX))   viol_e <= 1'b0;

            if (ns_up &&
                (car_n_y > (CAR_NS_Y_START + CAR_STEP_PIX)) &&
                (car_n_y >= H_ROAD_Y_B) &&
                ((car_n_y - CAR_STEP_PIX) < H_ROAD_Y_B)) begin
                viol_n <= red_ns;
            end

            if (ns_down &&
                ((car_s_y + CAR_STEP_PIX) < CAR_NS_Y_MAX) &&
                ((car_s_y + CAR_NS_LEN) <= H_ROAD_Y_T) &&
                ((car_s_y + CAR_STEP_PIX + CAR_NS_LEN) > H_ROAD_Y_T)) begin
                viol_s <= red_ns;
            end

            if (ew_left &&
                (car_w_x > (CAR_EW_X_START + CAR_STEP_PIX)) &&
                (car_w_x >= V_ROAD_X_R) &&
                ((car_w_x - CAR_STEP_PIX) < V_ROAD_X_R)) begin
                viol_w <= red_ew;
            end

            if (ew_right &&
                ((car_e_x + CAR_STEP_PIX) < CAR_EW_X_MAX) &&
                ((car_e_x + CAR_EW_LEN) <= V_ROAD_X_L) &&
                ((car_e_x + CAR_STEP_PIX + CAR_EW_LEN) > V_ROAD_X_L)) begin
                viol_e <= red_ew;
            end
        end
    end

    //================================================
    // 14. VGA 同步
    //================================================
    wire [9:0] h_count;
    wire [9:0] v_count;
    wire       video_on;

    vga_sync_640x480 u_sync (
        .clk      (pixel_clk),
        .reset_n  (rst_n),
        .h_count  (h_count),
        .v_count  (v_count),
        .hsync    (VGA_HS),
        .vsync    (VGA_VS),
        .video_on (video_on)
    );
	 
	//================================================
	// [ADD] 动画相位 anim（建议：pixel_clk 域）
	//   anim_frame : 每帧 +1（60Hz）
	//   anim_1s    : 每秒 +16（可选）
	//================================================
	reg  vs_d;
	reg  [7:0] anim_frame;

	// VSYNC 通常是低有效：用下降沿（1->0）作为“每帧一次”的 tick
	// 若你确认 VSYNC 是高有效，再把条件改成：(!vs_d && VGA_VS)
	always @(posedge pixel_clk or negedge rst_n) begin
		 if (!rst_n) begin
			  vs_d       <= 1'b1;
			  anim_frame <= 8'd0;
		 end else begin
			  if (vs_d && !VGA_VS) begin
					anim_frame <= anim_frame + 8'd1;
			  end
			  vs_d <= VGA_VS;
		 end
	end

	//------------------------------
	// [OPTION] 叠加 1s 相位：把 tick_1s 同步到 pixel_clk
	//------------------------------
	reg t1_meta, t1_sync, t1_sync_d;
	always @(posedge pixel_clk or negedge rst_n) begin
		 if (!rst_n) begin
			  t1_meta   <= 1'b0;
			  t1_sync   <= 1'b0;
			  t1_sync_d <= 1'b0;
		 end else begin
			  t1_meta   <= tick_1s;
			  t1_sync   <= t1_meta;
			  t1_sync_d <= t1_sync;
		 end
	end
	wire tick_1s_pix = t1_sync & ~t1_sync_d;

	reg [7:0] anim_1s;
	always @(posedge pixel_clk or negedge rst_n) begin
		 if (!rst_n) begin
			  anim_1s <= 8'd0;
		 end else if (tick_1s_pix) begin
			  anim_1s <= anim_1s + 8'd16;   // 每秒推进一小段（更“呼吸感”）
		 end
	end

	// 最终喂给图案模块的 anim（你也可以只用 anim_frame）
	wire [7:0] anim = anim_frame + anim_1s;

		// 任意方向闯红灯
	wire alarm_any_50 = viol_n | viol_s | viol_w | viol_e;

	// 同步到 pixel_clk 域 + 上升沿检测
	reg alarm_meta, alarm_sync, alarm_sync_d;
	always @(posedge pixel_clk or negedge rst_n) begin
		 if (!rst_n) begin
			  alarm_meta   <= 1'b0;
			  alarm_sync   <= 1'b0;
			  alarm_sync_d <= 1'b0;
		 end else begin
			  alarm_meta   <= alarm_any_50;
			  alarm_sync   <= alarm_meta;
			  alarm_sync_d <= alarm_sync;
		 end
	end
	wire alarm_rise = alarm_sync & ~alarm_sync_d;

	// 用 VSYNC 下降沿作为每帧 tick（与你 anim 的 frame_tick 同步）
	wire frame_tick = (vs_d && !VGA_VS);

	// boom 幅度：触发置满，按帧快速衰减（大概 16 帧 ~0.27s）
	reg [7:0] boom_amp;
	always @(posedge pixel_clk or negedge rst_n) begin
		 if (!rst_n) begin
			  boom_amp <= 8'd0;
		 end else if (alarm_rise) begin
			  boom_amp <= 8'hFF;
		 end else if (frame_tick) begin
			  if (boom_amp != 8'd0) begin
					if (boom_amp > 8'd16) boom_amp <= boom_amp - 8'd16;
					else                  boom_amp <= 8'd0;
			  end
		 end
	end

    //================================================
    // 15. 十字路口图案
    //================================================
    crossroad_pattern u_pattern (
        .x        (h_count),
        .y        (v_count),
        .video_on (video_on),

        .light_ns (light_ns),
        .light_ew (light_ew),

        .ns_tens  (ns_tens),
        .ns_ones  (ns_ones),
        .ew_tens  (ew_tens),
        .ew_ones  (ew_ones),
        .mode_num (mode_num),

        .car_n_y  (car_n_y),
        .car_s_y  (car_s_y),
        .car_w_x  (car_w_x),
        .car_e_x  (car_e_x),

        .viol_n   (viol_n),
        .viol_s   (viol_s),
        .viol_w   (viol_w),
        .viol_e   (viol_e),

        .anim     (anim),
        .boom_amp (boom_amp),

        .pip_cam_r    (pip_cam_r),
        .pip_cam_g    (pip_cam_g),
        .pip_cam_b    (pip_cam_b),
        .pip_cam_valid(pip_cam_valid),
        .pip_zoom     (pip_zoom),

        .r        (r),
        .g        (g),
        .b        (b)
    );

    assign VGA_R = r;
    assign VGA_G = g;
    assign VGA_B = b;

    assign VGA_BLANK_N = video_on;
    assign VGA_SYNC_N  = 1'b0;

endmodule
