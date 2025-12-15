//============================================================
// ps2_keyboard (Revised)
//  - 解析 PS/2 Set 2 扫描码
//  - 正确处理 E0(扩展) / F0(释放)
//  - 方向键 + W/S/A/D：全部为 level，可同时按住多键
//  - 感应模式 veh_* 改用 T/G/F/H（T/G level，F/H pulse）
//============================================================
module ps2_keyboard (
    input  wire       clk,
    input  wire       rst_n,

    input  wire [7:0] scan_code,
    input  wire       new_code,

    output reg  [1:0] mode_sel,

    // 感应模式输入：改键
    output reg        veh_NS_level,   // T (level)
    output reg        veh_EW_level,   // G (level)
    output reg        veh_NS_pulse,   // F (1-cycle)
    output reg        veh_EW_pulse,   // H (1-cycle)

    output reg        reset_pulse,    // R (1-cycle)

    // 方向键（level，可多键同时按住）
    output reg        ns_up,          // E0 75
    output reg        ns_down,        // E0 72
    output reg        ew_left,        // E0 6B
    output reg        ew_right,       // E0 74

    // [ADD] 第二套车控：W/S 与 A/D（level，可多键同时按住）
    output reg        ns_ws_fwd,      // W (level)
    output reg        ns_ws_bwd,      // S (level)
    output reg        ew_ad_fwd,      // D (level)
    output reg        ew_ad_bwd,      // A (level)

    output reg        ped_NS_req,     // O (1-cycle)
    output reg        ped_EW_req      // P (1-cycle)
);

    //--------------------------------------------------------
    // Set 2 扫描码常量（US QWERTY）
    //--------------------------------------------------------
    localparam [7:0]
        // 车控（level）
        SCAN_A = 8'h1C,
        SCAN_S = 8'h1B,
        SCAN_D = 8'h23,
        SCAN_W = 8'h1D,

        // 复位/模式
        SCAN_R = 8'h2D,
        SCAN_1 = 8'h16,
        SCAN_2 = 8'h1E,
        SCAN_3 = 8'h26,
        SCAN_4 = 8'h25,

        // 感应模式改键：T/G level，F/H pulse
        SCAN_T = 8'h2C,
        SCAN_G = 8'h34,
        SCAN_F = 8'h2B,
        SCAN_H = 8'h33,

        // 方向键：必须带 E0 前缀
        SCAN_UP    = 8'h75,   // E0 75
        SCAN_DOWN  = 8'h72,   // E0 72
        SCAN_LEFT  = 8'h6B,   // E0 6B
        SCAN_RIGHT = 8'h74,   // E0 74

        // 行人请求
        SCAN_O = 8'h44,
        SCAN_P = 8'h4D;

    //--------------------------------------------------------
    // 前缀标志：E0 / F0
    //--------------------------------------------------------
    reg break_flag;   // 收到 F0 后置 1：下一字节是释放码
    reg ext_flag;     // 收到 E0 后置 1：下一字节是扩展键码

    wire make     = ~break_flag;  // 1=按下(make) 0=释放(break)
    wire extended =  ext_flag;    // 1=扩展键(E0 xx)

    //--------------------------------------------------------
    // 脉冲键按下锁存，避免 typematic 重复码连发
    //--------------------------------------------------------
    reg f_down, h_down, r_down, o_down, p_down;

    //--------------------------------------------------------
    // 主逻辑
    //--------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            break_flag   <= 1'b0;
            ext_flag     <= 1'b0;

            mode_sel     <= 2'b00;

            veh_NS_level <= 1'b0;
            veh_EW_level <= 1'b0;
            veh_NS_pulse <= 1'b0;
            veh_EW_pulse <= 1'b0;

            reset_pulse  <= 1'b0;

            ns_up        <= 1'b0;
            ns_down      <= 1'b0;
            ew_left      <= 1'b0;
            ew_right     <= 1'b0;

            ns_ws_fwd    <= 1'b0;
            ns_ws_bwd    <= 1'b0;
            ew_ad_fwd    <= 1'b0;
            ew_ad_bwd    <= 1'b0;

            ped_NS_req   <= 1'b0;
            ped_EW_req   <= 1'b0;

            f_down       <= 1'b0;
            h_down       <= 1'b0;
            r_down       <= 1'b0;
            o_down       <= 1'b0;
            p_down       <= 1'b0;

        end else begin
            // 默认清零所有“脉冲类”输出（保持 1-cycle）
            veh_NS_pulse <= 1'b0;
            veh_EW_pulse <= 1'b0;
            reset_pulse  <= 1'b0;
            ped_NS_req   <= 1'b0;
            ped_EW_req   <= 1'b0;

            if (new_code) begin
                // 前缀字节
                if (scan_code == 8'hE0) begin
                    ext_flag <= 1'b1;
                end else if (scan_code == 8'hF0) begin
                    break_flag <= 1'b1;
                end else begin
                    // ---- 处理一个实际键码字节（使用当前 ext/break 状态） ----

                    if (extended) begin
                        // 扩展键：方向键 level（可多键同时按住）
                        case (scan_code)
                            SCAN_UP:    ns_up    <= make;
                            SCAN_DOWN:  ns_down  <= make;
                            SCAN_LEFT:  ew_left  <= make;
                            SCAN_RIGHT: ew_right <= make;
                            default: ; // ignore
                        endcase
                    end else begin
                        // 非扩展键
                        if (!make) begin
                            // 释放：level 清 0；脉冲键 down 标志清 0
                            case (scan_code)
                                // 车控 level
                                SCAN_W: ns_ws_fwd <= 1'b0;
                                SCAN_S: ns_ws_bwd <= 1'b0;
                                SCAN_D: ew_ad_fwd <= 1'b0;
                                SCAN_A: ew_ad_bwd <= 1'b0;

                                // 感应 level
                                SCAN_T: veh_NS_level <= 1'b0;
                                SCAN_G: veh_EW_level <= 1'b0;

                                // 脉冲锁存释放
                                SCAN_F: f_down <= 1'b0;
                                SCAN_H: h_down <= 1'b0;
                                SCAN_R: r_down <= 1'b0;
                                SCAN_O: o_down <= 1'b0;
                                SCAN_P: p_down <= 1'b0;
                                default: ; // ignore
                            endcase
                        end else begin
                            // 按下
                            case (scan_code)
                                // 模式选择（按下即切）
                                SCAN_1: mode_sel <= 2'b00;
                                SCAN_2: mode_sel <= 2'b01;
                                SCAN_3: mode_sel <= 2'b10;
                                SCAN_4: mode_sel <= 2'b11;

                                // 车控 level（可多键同时按住）
                                SCAN_W: ns_ws_fwd <= 1'b1;
                                SCAN_S: ns_ws_bwd <= 1'b1;
                                SCAN_D: ew_ad_fwd <= 1'b1;
                                SCAN_A: ew_ad_bwd <= 1'b1;

                                // 感应 level
                                SCAN_T: veh_NS_level <= 1'b1;
                                SCAN_G: veh_EW_level <= 1'b1;

                                // 感应 pulse：仅首次按下出脉冲
                                SCAN_F: begin
                                    if (!f_down) begin
                                        veh_NS_pulse <= 1'b1;
                                        f_down       <= 1'b1;
                                    end
                                end
                                SCAN_H: begin
                                    if (!h_down) begin
                                        veh_EW_pulse <= 1'b1;
                                        h_down       <= 1'b1;
                                    end
                                end

                                // reset / ped：pulse
                                SCAN_R: begin
                                    if (!r_down) begin
                                        reset_pulse <= 1'b1;
                                        r_down      <= 1'b1;
                                    end
                                end
                                SCAN_O: begin
                                    if (!o_down) begin
                                        ped_NS_req <= 1'b1;
                                        o_down     <= 1'b1;
                                    end
                                end
                                SCAN_P: begin
                                    if (!p_down) begin
                                        ped_EW_req <= 1'b1;
                                        p_down     <= 1'b1;
                                    end
                                end

                                default: ; // ignore
                            endcase
                        end
                    end

                    // 消费完一个实际键码字节后，清前缀状态
                    break_flag <= 1'b0;
                    ext_flag   <= 1'b0;
                end
            end
        end
    end

endmodule
