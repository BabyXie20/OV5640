module tlc_core_stage1(
    input        clk,
    input        rst_n,
    input        tick_1s,
    input  [1:0] mode_sel,     // 00:固定配时, 01:感应, 10:夜间黄闪, 11:封禁(全红/默认)
    input        veh_NS,
    input        veh_EW,
    // 新增：行人过街请求（NS / EW 两个方向）
    input        ped_NS,       // NS 方向行人过街请求（按钮或感应信号）
    input        ped_EW,       // EW 方向行人过街请求

    output reg [2:0] light_ns, // {R,Y,G}
    output reg [2:0] light_ew,
    output reg [3:0] phase_id,
    output reg [7:0] time_left
);

    //============================
    // 模式编码
    //============================
    localparam [1:0] MODE_FIXED = 2'b00; // 模式1 固定配时
    localparam [1:0] MODE_ACT   = 2'b01; // 模式2 感应
    localparam [1:0] MODE_NIGHT = 2'b10; // 模式3 夜间黄闪
    localparam [1:0] MODE_LOCK  = 2'b11; // 模式4 封禁（全红）

    wire mode_fixed = (mode_sel == MODE_FIXED);
    wire mode_act   = (mode_sel == MODE_ACT);
    wire mode_night = (mode_sel == MODE_NIGHT);
    wire mode_lock  = (mode_sel == MODE_LOCK);

    //============================
    // 配时（单位：s）
    //============================
    localparam integer T_NS_GREEN_MIN  = 15; // NS 最小绿
    localparam integer T_NS_GREEN_MAX  = 25; // NS 最大绿
    localparam integer T_EW_GREEN_MIN  = 10; // EW 最小绿
    localparam integer T_EW_GREEN_MAX  = 20; // EW 最大绿
    localparam integer T_YELLOW        = 5;  // 黄灯总时间
    localparam integer T_ALL_RED       = 2;  // 全红总时间

    // 行人过街专用：车辆全红时间（单位：s）
    localparam integer T_PED_RED       = 10; // 行人过街时，车灯全红 10 秒

    //============================
    // 状态编码（仅车灯相关）
    //============================
    localparam [3:0]
        S_NS_GREEN  = 4'd0,
        S_NS_YELLOW = 4'd1,
        S_ALL_RED_1 = 4'd2,
        S_EW_GREEN  = 4'd3,
        S_EW_YELLOW = 4'd4,
        S_ALL_RED_2 = 4'd5;

    reg [3:0] state, next_state;
    reg [7:0] sec_counter;    // 秒计数

    //============================
    // 夜间黄闪
    //============================
    reg [23:0] blink_cnt;
    reg        blink_on;

    //============================
    // [ADD] 固定/感应模式：黄灯相位也闪烁（1Hz：0.5s 亮 / 0.5s 灭）
    //============================
    wire in_yellow = (state == S_NS_YELLOW) || (state == S_EW_YELLOW);

    localparam integer YBLINK_HALF = 25_000_000; // 50MHz 下 0.5 秒
    reg [24:0] yellow_cnt;
    reg        yellow_blink;  // 1:亮黄, 0:灭

    //============================
    // 行人过街覆盖逻辑
    //============================
    reg        ped_active;        // 行人过街覆盖是否正在进行
    reg [3:0]  ped_sec_counter;   // 行人过街已持续的秒数（0~10）

    //============================
    // 行人过街覆盖计时与触发
    //============================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ped_active      <= 1'b0;
            ped_sec_counter <= 4'd0;
        end else begin
            // 仅在固定/感应模式下才允许行人覆盖，其它模式清零
            if (!(mode_fixed || mode_act)) begin
                ped_active      <= 1'b0;
                ped_sec_counter <= 4'd0;
            end else if (ped_active) begin
                // 已经在行人过街覆盖期间：计满 10 秒后结束
                if (tick_1s) begin
                    if (ped_sec_counter >= T_PED_RED-1) begin
                        ped_active      <= 1'b0;
                        ped_sec_counter <= 4'd0;
                    end else begin
                        ped_sec_counter <= ped_sec_counter + 4'd1;
                    end
                end
            end else begin
                // 当前没有行人覆盖：在对应方向处于绿灯时检测行人请求
                if ((state == S_NS_GREEN) && ped_NS) begin
                    ped_active      <= 1'b1;
                    ped_sec_counter <= 4'd0;
                end else if ((state == S_EW_GREEN) && ped_EW) begin
                    ped_active      <= 1'b1;
                    ped_sec_counter <= 4'd0;
                end
            end
        end
    end

    //============================
    // 状态寄存器与秒计数
    //============================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state       <= S_NS_GREEN;
            sec_counter <= 8'd0;
        end else begin
            // 行人过街期间：冻结车辆状态和计时
            if (ped_active && (mode_fixed || mode_act)) begin
                state       <= state;       // 保持当前相位
                sec_counter <= sec_counter; // 冻结倒计时
            end else begin
                state <= next_state;

                // 夜间 / 封禁模式：不计时，统一清零
                if (mode_night || mode_lock) begin
                    sec_counter <= 8'd0;
                end else if (next_state != state) begin
                    // 相位切换时清零计时
                    sec_counter <= 8'd0;
                end else if (tick_1s) begin
                    sec_counter <= sec_counter + 8'd1;
                end
            end
        end
    end

    //============================
    // 状态转移逻辑（仅固定配时 / 感应模式生效）
    //============================
    always @(*) begin
        // 默认保持当前状态
        next_state = state;

        // 行人过街时，车辆状态机完全冻结
        if (ped_active && (mode_fixed || mode_act)) begin
            next_state = state;
        end else if (mode_fixed || mode_act) begin
            case (state)
                // 主干道 NS 绿
                S_NS_GREEN: begin
                    if (mode_fixed) begin
                        // 固定配时
                        if (sec_counter >= T_NS_GREEN_MIN-1)
                            next_state = S_NS_YELLOW;
                    end else begin
                        // 感应模式：NS 为主干道
                        if (sec_counter < T_NS_GREEN_MIN-1) begin
                            next_state = S_NS_GREEN;
                        end else if (veh_EW) begin
                            // 支路有车等待
                            next_state = S_NS_YELLOW;
                        end else if (sec_counter >= T_NS_GREEN_MAX-1) begin
                            // 达到最大绿
                            next_state = S_NS_YELLOW;
                        end else begin
                            next_state = S_NS_GREEN;
                        end
                    end
                end

                // NS 黄
                S_NS_YELLOW: begin
                    if (sec_counter >= T_YELLOW-1)
                        next_state = S_ALL_RED_1;
                end

                // 全红，从 NS -> EW 过渡
                S_ALL_RED_1: begin
                    if (sec_counter >= T_ALL_RED-1)
                        next_state = S_EW_GREEN;
                end

                // EW 绿
                S_EW_GREEN: begin
                    if (mode_fixed) begin
                        if (sec_counter >= T_EW_GREEN_MIN-1)
                            next_state = S_EW_YELLOW;
                    end else begin
                        // 感应：支路绿尽快放完
                        if (sec_counter < T_EW_GREEN_MIN-1) begin
                            next_state = S_EW_GREEN;
                        end else if (veh_NS) begin
                            next_state = S_EW_YELLOW;
                        end else if (sec_counter >= T_EW_GREEN_MAX-1) begin
                            next_state = S_EW_YELLOW;
                        end else begin
                            next_state = S_EW_GREEN;
                        end
                    end
                end

                // EW 黄
                S_EW_YELLOW: begin
                    if (sec_counter >= T_YELLOW-1)
                        next_state = S_ALL_RED_2;
                end

                // 全红，从 EW -> NS 过渡
                S_ALL_RED_2: begin
                    if (sec_counter >= T_ALL_RED-1)
                        next_state = S_NS_GREEN;
                end

                default: begin
                    next_state = S_NS_GREEN;
                end
            endcase
        end
        // 夜间 / 封禁模式：next_state 保持 state（已在默认赋值）
    end

    //============================
    // time_left：当前相位剩余时间
    //============================
    always @(*) begin
        // 默认：非车辆模式（夜间 / 封禁）下为 0
        time_left = 8'd0;

        if (mode_fixed || mode_act) begin
            case (state)
                // NS 绿灯
                S_NS_GREEN: begin
                    if (mode_fixed) begin
                        time_left = (sec_counter >= T_NS_GREEN_MIN) ? 8'd0
                                   : (T_NS_GREEN_MIN - sec_counter);
                    end else begin
                        if (sec_counter < T_NS_GREEN_MIN)
                            time_left = T_NS_GREEN_MIN - sec_counter;
                        else
                            time_left = (sec_counter >= T_NS_GREEN_MAX) ? 8'd0
                                       : (T_NS_GREEN_MAX - sec_counter);
                    end
                end

                // EW 绿灯
                S_EW_GREEN: begin
                    if (mode_fixed) begin
                        time_left = (sec_counter >= T_EW_GREEN_MIN) ? 8'd0
                                   : (T_EW_GREEN_MIN - sec_counter);
                    end else begin
                        if (sec_counter < T_EW_GREEN_MIN)
                            time_left = T_EW_GREEN_MIN - sec_counter;
                        else
                            time_left = (sec_counter >= T_EW_GREEN_MAX) ? 8'd0
                                       : (T_EW_GREEN_MAX - sec_counter);
                    end
                end

                // 黄灯（NS/EW 共用逻辑）
                S_NS_YELLOW,
                S_EW_YELLOW: begin
                    time_left = (sec_counter >= T_YELLOW) ? 8'd0
                               : (T_YELLOW - sec_counter);
                end

                // 全红
                S_ALL_RED_1,
                S_ALL_RED_2: begin
                    time_left = (sec_counter >= T_ALL_RED) ? 8'd0
                               : (T_ALL_RED - sec_counter);
                end

                default: begin
                    time_left = 8'd0;
                end
            endcase
        end
        // mode_night / mode_lock: 保持默认 0
    end

    //============================
    // 相位号：直接等于状态编码
    //============================
    always @(*) begin
        phase_id = state;
    end

    //============================
    // 夜间黄闪计数
    //============================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            blink_cnt <= 24'd0;
            blink_on  <= 1'b0;
        end else if (mode_night) begin
            blink_cnt <= blink_cnt + 24'd1;
            // 取高位做闪烁（频率大约几百毫秒）
            blink_on  <= blink_cnt[22];
        end else begin
            blink_cnt <= 24'd0;
            blink_on  <= 1'b0;
        end
    end

    //============================
    // [ADD] 固定/感应模式下：黄灯相位闪烁计数
    // 仅在黄灯相位且未被行人覆盖时计数
    //============================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            yellow_cnt   <= 25'd0;
            yellow_blink <= 1'b1;
        end else if (!(mode_fixed || mode_act)) begin
            yellow_cnt   <= 25'd0;
            yellow_blink <= 1'b1;
        end else if (ped_active) begin
            yellow_cnt   <= 25'd0;
            yellow_blink <= 1'b1;
        end else if (!in_yellow) begin
            yellow_cnt   <= 25'd0;
            yellow_blink <= 1'b1;
        end else begin
            if (yellow_cnt == YBLINK_HALF-1) begin
                yellow_cnt   <= 25'd0;
                yellow_blink <= ~yellow_blink; // 每 0.5s 翻转 -> 1Hz 闪烁
            end else begin
                yellow_cnt <= yellow_cnt + 25'd1;
            end
        end
    end

    //============================
    // 输出灯状态（仅车灯，无行人灯）
    //============================
    always @(*) begin
        // 默认：封禁模式/异常情况 -> 全红
        light_ns = 3'b100;
        light_ew = 3'b100;

        if (mode_night) begin
            // 夜间模式：全部黄闪
            if (blink_on) begin
                light_ns = 3'b010; // Y
                light_ew = 3'b010; // Y
            end else begin
                light_ns = 3'b000; // 全灭
                light_ew = 3'b000;
            end

        end else if (mode_fixed || mode_act) begin
            // 固定/感应模式：先看是否有行人过街覆盖
            if (ped_active) begin
                // 行人过街期间：两方向车灯全红
                light_ns = 3'b100;
                light_ew = 3'b100;
            end else begin
                // 正常车辆控制模式：按状态机输出
                case (state)
                    S_NS_GREEN: begin
                        light_ns = 3'b001; // G
                        light_ew = 3'b100; // R
                    end
                    S_NS_YELLOW: begin
                        // [MOD] 黄灯相位改为闪烁
                        light_ns = yellow_blink ? 3'b010 : 3'b000; // Y 闪
                        light_ew = 3'b100;                         // 对向红
                    end
                    S_ALL_RED_1: begin
                        light_ns = 3'b100; // R
                        light_ew = 3'b100; // R
                    end
                    S_EW_GREEN: begin
                        light_ns = 3'b100; // R
                        light_ew = 3'b001; // G
                    end
                    S_EW_YELLOW: begin
                        // [MOD] 黄灯相位改为闪烁
                        light_ns = 3'b100;                         // 对向红
                        light_ew = yellow_blink ? 3'b010 : 3'b000; // Y 闪
                    end
                    S_ALL_RED_2: begin
                        light_ns = 3'b100; // R
                        light_ew = 3'b100; // R
                    end
                    default: begin
                        light_ns = 3'b100; // R
                        light_ew = 3'b100; // R
                    end
                endcase
            end
        end
        // mode_lock：保持默认全红
    end

endmodule
