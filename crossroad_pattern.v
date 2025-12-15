// crossroad_pattern.v
// 十字路口 + 周边人行道 + 斑马线 + 四方向红绿灯 + 右上角 HUD 数字面板
// [ADD] anim / boom_amp：HUD 扫描线、灯光 glow、闯红灯 boom 冲击效果（组合像素着色）

module crossroad_pattern (
    input  wire [9:0] x,
    input  wire [9:0] y,
    input  wire       video_on,
    input  wire [2:0] light_ns,
    input  wire [2:0] light_ew,

    input  wire [3:0] ns_tens,
    input  wire [3:0] ns_ones,
    input  wire [3:0] ew_tens,
    input  wire [3:0] ew_ones,
    input  wire [3:0] mode_num,

    // 四辆车的位置
    input  wire [9:0] car_n_y,  // 北向车（竖直左车道）
    input  wire [9:0] car_s_y,  // 南向车（竖直右车道）
    input  wire [9:0] car_w_x,  // 西向车（水平上车道）
    input  wire [9:0] car_e_x,  // 东向车（水平下车道）

    // 闯红灯状态
    input  wire       viol_n,
    input  wire       viol_s,
    input  wire       viol_w,
    input  wire       viol_e,

    // 动画相位/冲击幅度（顶层 pixel_clk 域产生并同步）
    input  wire [7:0] anim,
    input  wire [7:0] boom_amp,

    output reg  [7:0] r,
    output reg  [7:0] g,
    output reg  [7:0] b
);

    //========================
    // 几何常量
    //========================
    // 道路
    localparam [9:0] V_ROAD_X_L = 10'd260;
    localparam [9:0] V_ROAD_X_R = 10'd380;   // 右边界不含
    localparam [9:0] H_ROAD_Y_T = 10'd180;
    localparam [9:0] H_ROAD_Y_B = 10'd300;   // 下边界不含

    // 人行道宽度
    localparam [9:0] SIDEWALK_W = 10'd16;

    // 小车尺寸（保留，但绘制用 NS/EW 的长宽）
    localparam [9:0] CAR_SIZE = 10'd10;

    // 车道中心线
    localparam [9:0] V_ROAD_CENTER_X = (V_ROAD_X_L + V_ROAD_X_R) >> 1;
    localparam [9:0] H_ROAD_CENTER_Y = (H_ROAD_Y_T + H_ROAD_Y_B) >> 1;

    localparam [9:0] V_LANE_EAST_CENTER_X  =
        V_ROAD_X_L + ((V_ROAD_X_R - V_ROAD_X_L) * 3) / 4;  // ≈350
    localparam [9:0] H_LANE_SOUTH_CENTER_Y =
        H_ROAD_Y_T + ((H_ROAD_Y_B - H_ROAD_Y_T) * 3) / 4;  // ≈270

    localparam [9:0] V_LANE_WEST_CENTER_X  =
        V_ROAD_X_L + ((V_ROAD_X_R - V_ROAD_X_L) * 1) / 4;  // ≈290
    localparam [9:0] H_LANE_NORTH_CENTER_Y =
        H_ROAD_Y_T + ((H_ROAD_Y_B - H_ROAD_Y_T) * 1) / 4;  // ≈210

    // 小车长宽
    localparam [9:0] CAR_NS_LEN = 10'd20;
    localparam [9:0] CAR_NS_WID = 10'd12;
    localparam [9:0] CAR_EW_LEN = 10'd20;
    localparam [9:0] CAR_EW_WID = 10'd12;

    // 画面尺寸
    localparam [9:0] X_MAX = 10'd640;
    localparam [9:0] Y_MAX = 10'd480;

    // 斑马线条纹参数
    localparam [9:0] STRIPE_PERIOD = 10'd12;
    localparam [9:0] STRIPE_WIDTH  = 10'd6;

    // 红绿灯尺寸
    localparam [9:0] TL_LONG   = 10'd30;
    localparam [9:0] TL_SHORT  = 10'd10;
    localparam [9:0] TL_SEG    = 10'd10;
    localparam [9:0] TL_MARGIN = 10'd4;

    // 北向灯（横向）
    localparam [9:0] TLN_X = 10'd320 - (TL_LONG >> 1);
    localparam [9:0] TLN_Y = H_ROAD_Y_T - SIDEWALK_W - TL_SHORT - TL_MARGIN;

    // 南向灯（横向）
    localparam [9:0] TLS_X = 10'd320 - (TL_LONG >> 1);
    localparam [9:0] TLS_Y = H_ROAD_Y_B + SIDEWALK_W + TL_MARGIN;

    // 西向灯（竖向）
    localparam [9:0] TLW_X = V_ROAD_X_L - SIDEWALK_W - TL_SHORT - TL_MARGIN;
    localparam [9:0] TLW_Y = 10'd240 - (TL_LONG >> 1);

    // 东向灯（竖向）
    localparam [9:0] TLE_X = V_ROAD_X_R + SIDEWALK_W + TL_MARGIN;
    localparam [9:0] TLE_Y = 10'd240 - (TL_LONG >> 1);

    //========================
    // HUD 参数
    //========================
    localparam [9:0] HUD_X_MIN = 10'd500;
    localparam [9:0] HUD_X_MAX = 10'd640;
    localparam [9:0] HUD_Y_MIN = 10'd0;
    localparam [9:0] HUD_Y_MAX = 10'd150;

    localparam [9:0] DIGIT_WIDTH   = 10'd14;
    localparam [9:0] DIGIT_HEIGHT  = 10'd22;
    localparam [9:0] DIGIT_GAP     = 10'd4;
    localparam [9:0] DIGIT_SPACING = 10'd16;
    localparam [9:0] SEG_WIDTH     = 10'd4;

    // 这里用 11-bit 做中间运算，避免 32->10 截断 warning
    localparam [10:0] TOTAL_DIGIT_AREA_WIDTH = (11'd5 * {1'b0,DIGIT_WIDTH}) + (11'd4 * {1'b0,DIGIT_GAP});
    localparam [10:0] HUD_CENTER_X           = ({1'b0,HUD_X_MIN} + {1'b0,HUD_X_MAX}) >> 1;
    localparam [10:0] START_X                = HUD_CENTER_X - (TOTAL_DIGIT_AREA_WIDTH >> 1);

    localparam [10:0] GLYPH0_X = START_X;
    localparam [10:0] GLYPH1_X = GLYPH0_X + {1'b0,DIGIT_WIDTH} + {1'b0,DIGIT_GAP};
    localparam [10:0] GLYPH2_X = GLYPH1_X + {1'b0,DIGIT_WIDTH} + {1'b0,DIGIT_GAP};
    localparam [10:0] GLYPH3_X = GLYPH2_X + {1'b0,DIGIT_WIDTH} + {1'b0,DIGIT_GAP};
    localparam [10:0] GLYPH4_X = GLYPH3_X + {1'b0,DIGIT_WIDTH} + {1'b0,DIGIT_GAP};

    localparam [9:0] NS_Y    = HUD_Y_MIN + 10'd8;
    localparam [9:0] EW_Y    = NS_Y   + DIGIT_HEIGHT + DIGIT_SPACING;
    localparam [9:0] MODE_Y  = EW_Y   + DIGIT_HEIGHT + DIGIT_SPACING;
    localparam [9:0] ALARM_Y = MODE_Y + DIGIT_HEIGHT + DIGIT_SPACING;

    // alias（同样保留 11-bit，调用处再切 [9:0]）
    localparam [10:0] NS_TENS_X   = GLYPH0_X;
    localparam [10:0] NS_ONES_X   = GLYPH1_X;
    localparam [10:0] NS_EW_SEP_X = GLYPH2_X;
    localparam [10:0] EW_TENS_X   = GLYPH3_X;
    localparam [10:0] EW_ONES_X   = GLYPH4_X;

    //========================
    // 小工具：饱和加减 / 三角波
    //========================
    function [7:0] add_sat8;
        input [7:0] a;
        input [7:0] b2;
        integer sum;
        begin
            sum = a + b2;
            if (sum > 255) add_sat8 = 8'hFF;
            else           add_sat8 = sum[7:0];
        end
    endfunction

    function [7:0] sub_sat8;
        input [7:0] a;
        input [7:0] b2;
        integer diff;
        begin
            diff = a - b2;
            if (diff < 0)  sub_sat8 = 8'h00;
            else           sub_sat8 = diff[7:0];
        end
    endfunction

    function [7:0] tri_wave8;
        input [7:0] t;
        begin
            if (t[7]) tri_wave8 = 8'hFF - t;
            else      tri_wave8 = t;
        end
    endfunction

    //========================
    // 七段段位置函数（拐角重叠避免断点）
    //========================
    function [0:0] segment_a;
        input [9:0] px, py, dx, dy;
        begin
            segment_a = (py >= dy && py < dy + SEG_WIDTH &&
                         px >= dx && px < dx + DIGIT_WIDTH);
        end
    endfunction

    function [0:0] segment_b;
        input [9:0] px, py, dx, dy;
        begin
            segment_b = (px >= dx + DIGIT_WIDTH - SEG_WIDTH && px < dx + DIGIT_WIDTH &&
                         py >= dy && py < dy + (DIGIT_HEIGHT/2) + 1);
        end
    endfunction

    function [0:0] segment_c;
        input [9:0] px, py, dx, dy;
        begin
            segment_c = (px >= dx + DIGIT_WIDTH - SEG_WIDTH && px < dx + DIGIT_WIDTH &&
                         py >= dy + (DIGIT_HEIGHT/2) - 1 && py < dy + DIGIT_HEIGHT);
        end
    endfunction

    function [0:0] segment_d;
        input [9:0] px, py, dx, dy;
        begin
            segment_d = (py >= dy + DIGIT_HEIGHT - SEG_WIDTH && py < dy + DIGIT_HEIGHT &&
                         px >= dx && px < dx + DIGIT_WIDTH);
        end
    endfunction

    function [0:0] segment_e;
        input [9:0] px, py, dx, dy;
        begin
            segment_e = (px >= dx && px < dx + SEG_WIDTH &&
                         py >= dy + (DIGIT_HEIGHT/2) - 1 && py < dy + DIGIT_HEIGHT);
        end
    endfunction

    function [0:0] segment_f;
        input [9:0] px, py, dx, dy;
        begin
            segment_f = (px >= dx && px < dx + SEG_WIDTH &&
                         py >= dy && py < dy + (DIGIT_HEIGHT/2) + 1);
        end
    endfunction

    function [0:0] segment_g;
        input [9:0] px, py, dx, dy;
        begin
            segment_g = (py >= dy + (DIGIT_HEIGHT/2) - (SEG_WIDTH/2) - 1 &&
                         py <  dy + (DIGIT_HEIGHT/2) + (SEG_WIDTH/2) + 1 &&
                         px >= dx && px < dx + DIGIT_WIDTH);
        end
    endfunction

    //========================
    // 七段编码
    //========================
    function [6:0] digit_pattern;
        input [3:0] digit;
        begin
            case(digit)
                4'd0: digit_pattern = 7'b1111110;
                4'd1: digit_pattern = 7'b0110000;
                4'd2: digit_pattern = 7'b1101101;
                4'd3: digit_pattern = 7'b1111001;
                4'd4: digit_pattern = 7'b0110011;
                4'd5: digit_pattern = 7'b1011011;
                4'd6: digit_pattern = 7'b1011111;
                4'd7: digit_pattern = 7'b1110000;
                4'd8: digit_pattern = 7'b1111111;
                4'd9: digit_pattern = 7'b1111011;
                default: digit_pattern = 7'b0000000;
            endcase
        end
    endfunction

    function [6:0] mode_pattern;
        input [3:0] mode;
        begin
            case(mode)
                4'd1: mode_pattern = 7'b0110000;
                4'd2: mode_pattern = 7'b1101101;
                4'd3: mode_pattern = 7'b1111001;
                4'd4: mode_pattern = 7'b0110011;
                default: mode_pattern = 7'b0000000;
            endcase
        end
    endfunction

    function [6:0] char_pattern;
        input [3:0] ch;
        begin
            case (ch)
                4'd0: char_pattern = 7'b1110110; // N/H 近似
                4'd1: char_pattern = 7'b1011011; // S
                4'd2: char_pattern = 7'b1001111; // E
                4'd3: char_pattern = 7'b0111011; // W
                4'd4: char_pattern = 7'b1110110; // M 近似
                4'd5: char_pattern = 7'b0111101; // D
                4'd6: char_pattern = 7'b1111110; // O
                default: char_pattern = 7'b0000000;
            endcase
        end
    endfunction

    //========================
    // 绘制数字/字母/冒号
    //========================
    function [0:0] draw_digit;
        input [9:0] px, py;
        input [9:0] dx, dy;
        input [3:0] digit;
        reg [6:0] pattern;
        reg seg_a_on, seg_b_on, seg_c_on, seg_d_on, seg_e_on, seg_f_on, seg_g_on;
        begin
            pattern   = digit_pattern(digit);
            seg_a_on  = pattern[6] && segment_a(px, py, dx, dy);
            seg_b_on  = pattern[5] && segment_b(px, py, dx, dy);
            seg_c_on  = pattern[4] && segment_c(px, py, dx, dy);
            seg_d_on  = pattern[3] && segment_d(px, py, dx, dy);
            seg_e_on  = pattern[2] && segment_e(px, py, dx, dy);
            seg_f_on  = pattern[1] && segment_f(px, py, dx, dy);
            seg_g_on  = pattern[0] && segment_g(px, py, dx, dy);
            draw_digit = seg_a_on || seg_b_on || seg_c_on ||
                         seg_d_on || seg_e_on || seg_f_on || seg_g_on;
        end
    endfunction

    function [0:0] draw_mode;
        input [9:0] px, py;
        input [9:0] dx, dy;
        input [3:0] mode;
        reg [6:0] pattern;
        reg seg_a_on, seg_b_on, seg_c_on, seg_d_on, seg_e_on, seg_f_on, seg_g_on;
        begin
            pattern   = mode_pattern(mode);
            seg_a_on  = pattern[6] && segment_a(px, py, dx, dy);
            seg_b_on  = pattern[5] && segment_b(px, py, dx, dy);
            seg_c_on  = pattern[4] && segment_c(px, py, dx, dy);
            seg_d_on  = pattern[3] && segment_d(px, py, dx, dy);
            seg_e_on  = pattern[2] && segment_e(px, py, dx, dy);
            seg_f_on  = pattern[1] && segment_f(px, py, dx, dy);
            seg_g_on  = pattern[0] && segment_g(px, py, dx, dy);
            draw_mode = seg_a_on || seg_b_on || seg_c_on ||
                        seg_d_on || seg_e_on || seg_f_on || seg_g_on;
        end
    endfunction

    function [0:0] draw_char;
        input [9:0] px, py;
        input [9:0] dx, dy;
        input [3:0] ch;
        reg [6:0] pattern;
        reg seg_a_on, seg_b_on, seg_c_on, seg_d_on, seg_e_on, seg_f_on, seg_g_on;
        begin
            pattern   = char_pattern(ch);
            seg_a_on  = pattern[6] && segment_a(px, py, dx, dy);
            seg_b_on  = pattern[5] && segment_b(px, py, dx, dy);
            seg_c_on  = pattern[4] && segment_c(px, py, dx, dy);
            seg_d_on  = pattern[3] && segment_d(px, py, dx, dy);
            seg_e_on  = pattern[2] && segment_e(px, py, dx, dy);
            seg_f_on  = pattern[1] && segment_f(px, py, dx, dy);
            seg_g_on  = pattern[0] && segment_g(px, py, dx, dy);
            draw_char = seg_a_on || seg_b_on || seg_c_on ||
                        seg_d_on || seg_e_on || seg_f_on || seg_g_on;
        end
    endfunction

    function [0:0] draw_colon;
        input [9:0] px, py;
        input [9:0] dx, dy;
        begin
            if (px >= dx + DIGIT_WIDTH/2 - 2 && px < dx + DIGIT_WIDTH/2 + 2 &&
               ((py >= dy + DIGIT_HEIGHT/3 - 2      && py < dy + DIGIT_HEIGHT/3 + 2) ||
                (py >= dy + (2*DIGIT_HEIGHT)/3 - 2 && py < dy + (2*DIGIT_HEIGHT)/3 + 2))) begin
                draw_colon = 1'b1;
            end else begin
                draw_colon = 1'b0;
            end
        end
    endfunction

    //========================
    // 点阵 "M","O","D"（修 latch：全部默认赋值）
    //========================
    function [0:0] draw_char_mod;
        input [9:0] px, py;
        input [9:0] dx, dy;
        input [3:0] ch;
        integer cx, cy;
        integer x0, y0;
        reg [2:0] row;
        reg [2:0] col;
        reg [4:0] row_bits;
        localparam FONT_W = 5;
        localparam FONT_H = 7;
        localparam SCALE  = 2;
        localparam PIX_W  = FONT_W*SCALE;   // 10
        localparam PIX_H  = FONT_H*SCALE;   // 14
        begin
            // 默认值（关键：避免 latch warning）
            draw_char_mod = 1'b0;
            cx = 0; cy = 0;
            x0 = 0; y0 = 0;
            row = 3'd0;
            col = 3'd0;
            row_bits = 5'b00000;

            // 居中
            x0 = dx + (DIGIT_WIDTH  - PIX_W)/2;
            y0 = dy + (DIGIT_HEIGHT - PIX_H)/2;

            cx = px - x0;
            cy = py - y0;

            if (cx >= 0 && cx < PIX_W && cy >= 0 && cy < PIX_H) begin
                col = (cx >> 1);
                row = (cy >> 1);

                // row_bits 默认已是 0，这里按行赋值
                case (ch)
                    4'd4: begin // 'M'
                        case (row)
                            3'd0: row_bits = 5'b11111;
                            3'd1: row_bits = 5'b10001;
                            3'd2: row_bits = 5'b11011;
                            3'd3: row_bits = 5'b10101;
                            3'd4: row_bits = 5'b10001;
                            3'd5: row_bits = 5'b10001;
                            3'd6: row_bits = 5'b10001;
                            default: row_bits = 5'b00000;
                        endcase
                    end
                    4'd6: begin // 'O'
                        case (row)
                            3'd0: row_bits = 5'b01110;
                            3'd1: row_bits = 5'b10001;
                            3'd2: row_bits = 5'b10001;
                            3'd3: row_bits = 5'b10001;
                            3'd4: row_bits = 5'b10001;
                            3'd5: row_bits = 5'b10001;
                            3'd6: row_bits = 5'b01110;
                            default: row_bits = 5'b00000;
                        endcase
                    end
                    4'd5: begin // 'D'
                        case (row)
                            3'd0: row_bits = 5'b11110;
                            3'd1: row_bits = 5'b10001;
                            3'd2: row_bits = 5'b10001;
                            3'd3: row_bits = 5'b10001;
                            3'd4: row_bits = 5'b10001;
                            3'd5: row_bits = 5'b10001;
                            3'd6: row_bits = 5'b11110;
                            default: row_bits = 5'b00000;
                        endcase
                    end
                    default: row_bits = 5'b00000;
                endcase

                if (row_bits[4-col])
                    draw_char_mod = 1'b1;
            end
        end
    endfunction

    //========================
    // 组合像素着色：科技风 + 动态 glow/scanline + boom
    // （修 latch：所有临时变量 always 先给默认值）
    //========================
    integer dx_i, dy_i, d_i, ring_pos, diff_i;
    reg [7:0] glow_phase;
    reg [7:0] glow_lvl;
    reg [7:0] glow2;

    always @* begin
        // --------- 默认值：避免 latch 推断（关键）---------
        glow_phase = 8'd0;
        glow_lvl   = 8'd0;
        glow2      = 8'd0;

        dx_i     = 0;
        dy_i     = 0;
        d_i      = 0;
        ring_pos = 0;
        diff_i   = 0;

        // ---------------------------------------------------
        if (!video_on) begin
            r = 8'd0; g = 8'd0; b = 8'd0;
        end else begin
            // 0) 背景：深色科技风 + 网格（anim 流动）
            r = 8'd6;  g = 8'd10; b = 8'd18;

            if ( (((x + {2'b0,anim}) & 10'd31) == 10'd0) ||
                 (((y + {2'b0,anim}) & 10'd31) == 10'd0) ) begin
                r = add_sat8(r, 8'd10);
                g = add_sat8(g, 8'd18);
                b = add_sat8(b, 8'd30);
            end

            if ( ((((x ^ y) + {2'b0,anim}) & 10'd63) == 10'd0) ) begin
                b = add_sat8(b, 8'd10);
            end

            // 计算 glow（每像素都定义）
            glow_phase = tri_wave8(anim);
            glow_lvl   = (glow_phase >> 4);                 // 0..15
            glow2      = add_sat8((glow_phase >> 2), (boom_amp >> 3)); // 0..63 + boom

            // 1) 人行道（冷灰蓝）
            if (x >= V_ROAD_X_L - SIDEWALK_W && x < V_ROAD_X_L && y < Y_MAX) begin
                r = 8'd70; g = 8'd80; b = 8'd95;
            end
            if (x >= V_ROAD_X_R && x < V_ROAD_X_R + SIDEWALK_W && y < Y_MAX) begin
                r = 8'd70; g = 8'd80; b = 8'd95;
            end
            if (y >= H_ROAD_Y_T - SIDEWALK_W && y < H_ROAD_Y_T && x < X_MAX) begin
                r = 8'd70; g = 8'd80; b = 8'd95;
            end
            if (y >= H_ROAD_Y_B && y < H_ROAD_Y_B + SIDEWALK_W && x < X_MAX) begin
                r = 8'd70; g = 8'd80; b = 8'd95;
            end

            // 2) 机动车道（深灰）
            if (x >= V_ROAD_X_L && x < V_ROAD_X_R) begin
                r = 8'd24; g = 8'd24; b = 8'd26;
            end
            if (y >= H_ROAD_Y_T && y < H_ROAD_Y_B) begin
                r = 8'd24; g = 8'd24; b = 8'd26;
            end

            // 3) 斑马线（白 + 微蓝）
            if (x >= V_ROAD_X_L && x < V_ROAD_X_R &&
                y >= H_ROAD_Y_T - SIDEWALK_W && y < H_ROAD_Y_T) begin
                if ( ((x - V_ROAD_X_L) % STRIPE_PERIOD) < STRIPE_WIDTH ) begin
                    r = 8'd235; g = 8'd240; b = 8'd255;
                end
            end
            if (x >= V_ROAD_X_L && x < V_ROAD_X_R &&
                y >= H_ROAD_Y_B && y < H_ROAD_Y_B + SIDEWALK_W) begin
                if ( ((x - V_ROAD_X_L) % STRIPE_PERIOD) < STRIPE_WIDTH ) begin
                    r = 8'd235; g = 8'd240; b = 8'd255;
                end
            end
            if (x >= V_ROAD_X_L - SIDEWALK_W && x < V_ROAD_X_L &&
                y >= H_ROAD_Y_T && y < H_ROAD_Y_B) begin
                if ( ((y - H_ROAD_Y_T) % STRIPE_PERIOD) < STRIPE_WIDTH ) begin
                    r = 8'd235; g = 8'd240; b = 8'd255;
                end
            end
            if (x >= V_ROAD_X_R && x < V_ROAD_X_R + SIDEWALK_W &&
                y >= H_ROAD_Y_T && y < H_ROAD_Y_B) begin
                if ( ((y - H_ROAD_Y_T) % STRIPE_PERIOD) < STRIPE_WIDTH ) begin
                    r = 8'd235; g = 8'd240; b = 8'd255;
                end
            end

            // 4) 中心线：霓虹青（呼吸）
            if (x >= 10'd318 && x < 10'd322 && y < Y_MAX) begin
                r = 8'd20;
                g = add_sat8(8'd180, glow_lvl);
                b = add_sat8(8'd200, glow_lvl);
            end
            if (y >= 10'd238 && y < 10'd242 && x < X_MAX) begin
                r = 8'd20;
                g = add_sat8(8'd180, glow_lvl);
                b = add_sat8(8'd200, glow_lvl);
            end

            // 5) 小车（更丰富）
            if (x >= V_LANE_WEST_CENTER_X - (CAR_NS_WID >> 1) &&
                x <  V_LANE_WEST_CENTER_X + (CAR_NS_WID >> 1) &&
                y >= car_n_y && y < car_n_y + CAR_NS_LEN) begin
                r = 8'd40; g = 8'd90; b = 8'd220;
                if (y < car_n_y + (CAR_NS_LEN/3)) begin
                    r = 8'd170; g = 8'd230; b = 8'd255;
                end
                if ( (y >= car_n_y + (CAR_NS_LEN*2/3)) &&
                     ( (x <  V_LANE_WEST_CENTER_X - (CAR_NS_WID>>1) + 2) ||
                       (x >= V_LANE_WEST_CENTER_X + (CAR_NS_WID>>1) - 2) ) ) begin
                    r = 8'd20; g = 8'd20; b = 8'd20;
                end
            end

            if (x >= V_LANE_EAST_CENTER_X - (CAR_NS_WID >> 1) &&
                x <  V_LANE_EAST_CENTER_X + (CAR_NS_WID >> 1) &&
                y >= car_s_y && y < car_s_y + CAR_NS_LEN) begin
                r = 8'd200; g = 8'd60; b = 8'd220;
                if (y > car_s_y + (CAR_NS_LEN*2/3)) begin
                    r = 8'd255; g = 8'd210; b = 8'd255;
                end
                if ( (y <= car_s_y + (CAR_NS_LEN/3)) &&
                     ( (x <  V_LANE_EAST_CENTER_X - (CAR_NS_WID>>1) + 2) ||
                       (x >= V_LANE_EAST_CENTER_X + (CAR_NS_WID>>1) - 2) ) ) begin
                    r = 8'd20; g = 8'd20; b = 8'd20;
                end
            end

            if (y >= H_LANE_NORTH_CENTER_Y - (CAR_EW_WID >> 1) &&
                y <  H_LANE_NORTH_CENTER_Y + (CAR_EW_WID >> 1) &&
                x >= car_w_x && x < car_w_x + CAR_EW_LEN) begin
                r = 8'd240; g = 8'd120; b = 8'd30;
                if (x < car_w_x + (CAR_EW_LEN/3)) begin
                    r = 8'd255; g = 8'd230; b = 8'd180;
                end
                if ( (x >= car_w_x + (CAR_EW_LEN*2/3)) &&
                     ( (y <  H_LANE_NORTH_CENTER_Y - (CAR_EW_WID>>1) + 2) ||
                       (y >= H_LANE_NORTH_CENTER_Y + (CAR_EW_WID>>1) - 2) ) ) begin
                    r = 8'd20; g = 8'd20; b = 8'd20;
                end
            end

            if (y >= H_LANE_SOUTH_CENTER_Y - (CAR_EW_WID >> 1) &&
                y <  H_LANE_SOUTH_CENTER_Y + (CAR_EW_WID >> 1) &&
                x >= car_e_x && x < car_e_x + CAR_EW_LEN) begin
                r = 8'd60; g = 8'd220; b = 8'd160;
                if (x > car_e_x + (CAR_EW_LEN*2/3)) begin
                    r = 8'd200; g = 8'd255; b = 8'd230;
                end
                if ( (x <= car_e_x + (CAR_EW_LEN/3)) &&
                     ( (y <  H_LANE_SOUTH_CENTER_Y - (CAR_EW_WID>>1) + 2) ||
                       (y >= H_LANE_SOUTH_CENTER_Y + (CAR_EW_WID>>1) - 2) ) ) begin
                    r = 8'd20; g = 8'd20; b = 8'd20;
                end
            end

            // 6) 红绿灯 halo（先 halo 后灯体灯芯）
            // 北向 halo
            if (light_ns[2] &&
                x >= TLN_X - 3 && x < TLN_X + TL_SEG + 3 &&
                y >= TLN_Y - 3 && y < TLN_Y + TL_SHORT + 3) begin
                r = add_sat8(r, 8'd30 + (glow2 >> 1));
            end
            if (light_ns[1] &&
                x >= TLN_X + TL_SEG - 3 && x < TLN_X + (TL_SEG*2) + 3 &&
                y >= TLN_Y - 3 && y < TLN_Y + TL_SHORT + 3) begin
                r = add_sat8(r, 8'd18 + (glow2 >> 2));
                g = add_sat8(g, 8'd18 + (glow2 >> 2));
            end
            if (light_ns[0] &&
                x >= TLN_X + (TL_SEG*2) - 3 && x < TLN_X + (TL_SEG*3) + 3 &&
                y >= TLN_Y - 3 && y < TLN_Y + TL_SHORT + 3) begin
                g = add_sat8(g, 8'd30 + (glow2 >> 1));
            end

            // 南向 halo
            if (light_ns[2] &&
                x >= TLS_X - 3 && x < TLS_X + TL_SEG + 3 &&
                y >= TLS_Y - 3 && y < TLS_Y + TL_SHORT + 3) begin
                r = add_sat8(r, 8'd30 + (glow2 >> 1));
            end
            if (light_ns[1] &&
                x >= TLS_X + TL_SEG - 3 && x < TLS_X + (TL_SEG*2) + 3 &&
                y >= TLS_Y - 3 && y < TLS_Y + TL_SHORT + 3) begin
                r = add_sat8(r, 8'd18 + (glow2 >> 2));
                g = add_sat8(g, 8'd18 + (glow2 >> 2));
            end
            if (light_ns[0] &&
                x >= TLS_X + (TL_SEG*2) - 3 && x < TLS_X + (TL_SEG*3) + 3 &&
                y >= TLS_Y - 3 && y < TLS_Y + TL_SHORT + 3) begin
                g = add_sat8(g, 8'd30 + (glow2 >> 1));
            end

            // 西向 halo
            if (light_ew[2] &&
                x >= TLW_X - 3 && x < TLW_X + TL_SHORT + 3 &&
                y >= TLW_Y - 3 && y < TLW_Y + TL_SEG + 3) begin
                r = add_sat8(r, 8'd30 + (glow2 >> 1));
            end
            if (light_ew[1] &&
                x >= TLW_X - 3 && x < TLW_X + TL_SHORT + 3 &&
                y >= TLW_Y + TL_SEG - 3 && y < TLW_Y + (TL_SEG*2) + 3) begin
                r = add_sat8(r, 8'd18 + (glow2 >> 2));
                g = add_sat8(g, 8'd18 + (glow2 >> 2));
            end
            if (light_ew[0] &&
                x >= TLW_X - 3 && x < TLW_X + TL_SHORT + 3 &&
                y >= TLW_Y + (TL_SEG*2) - 3 && y < TLW_Y + (TL_SEG*3) + 3) begin
                g = add_sat8(g, 8'd30 + (glow2 >> 1));
            end

            // 东向 halo
            if (light_ew[2] &&
                x >= TLE_X - 3 && x < TLE_X + TL_SHORT + 3 &&
                y >= TLE_Y - 3 && y < TLE_Y + TL_SEG + 3) begin
                r = add_sat8(r, 8'd30 + (glow2 >> 1));
            end
            if (light_ew[1] &&
                x >= TLE_X - 3 && x < TLE_X + TL_SHORT + 3 &&
                y >= TLE_Y + TL_SEG - 3 && y < TLE_Y + (TL_SEG*2) + 3) begin
                r = add_sat8(r, 8'd18 + (glow2 >> 2));
                g = add_sat8(g, 8'd18 + (glow2 >> 2));
            end
            if (light_ew[0] &&
                x >= TLE_X - 3 && x < TLE_X + TL_SHORT + 3 &&
                y >= TLE_Y + (TL_SEG*2) - 3 && y < TLE_Y + (TL_SEG*3) + 3) begin
                g = add_sat8(g, 8'd30 + (glow2 >> 1));
            end

            // 灯体壳
            if (x >= TLN_X && x < TLN_X + TL_LONG && y >= TLN_Y && y < TLN_Y + TL_SHORT) begin
                r = 8'd28; g = 8'd28; b = 8'd30;
            end
            if (x >= TLS_X && x < TLS_X + TL_LONG && y >= TLS_Y && y < TLS_Y + TL_SHORT) begin
                r = 8'd28; g = 8'd28; b = 8'd30;
            end
            if (x >= TLW_X && x < TLW_X + TL_SHORT && y >= TLW_Y && y < TLW_Y + TL_LONG) begin
                r = 8'd28; g = 8'd28; b = 8'd30;
            end
            if (x >= TLE_X && x < TLE_X + TL_SHORT && y >= TLE_Y && y < TLE_Y + TL_LONG) begin
                r = 8'd28; g = 8'd28; b = 8'd30;
            end

            // 灯芯
            // 北向
            if (light_ns[2] &&
                x >= TLN_X + 1 && x < TLN_X + TL_SEG - 1 &&
                y >= TLN_Y + 1 && y < TLN_Y + TL_SHORT - 1) begin
                r = 8'd255; g = 8'd20;  b = 8'd20;
            end
            if (light_ns[1] &&
                x >= TLN_X + TL_SEG + 1 && x < TLN_X + (TL_SEG*2) - 1 &&
                y >= TLN_Y + 1 && y < TLN_Y + TL_SHORT - 1) begin
                r = 8'd255; g = 8'd230; b = 8'd40;
            end
            if (light_ns[0] &&
                x >= TLN_X + (TL_SEG*2) + 1 && x < TLN_X + (TL_SEG*3) - 1 &&
                y >= TLN_Y + 1 && y < TLN_Y + TL_SHORT - 1) begin
                r = 8'd30;  g = 8'd255; b = 8'd80;
            end

            // 南向
            if (light_ns[2] &&
                x >= TLS_X + 1 && x < TLS_X + TL_SEG - 1 &&
                y >= TLS_Y + 1 && y < TLS_Y + TL_SHORT - 1) begin
                r = 8'd255; g = 8'd20;  b = 8'd20;
            end
            if (light_ns[1] &&
                x >= TLS_X + TL_SEG + 1 && x < TLS_X + (TL_SEG*2) - 1 &&
                y >= TLS_Y + 1 && y < TLS_Y + TL_SHORT - 1) begin
                r = 8'd255; g = 8'd230; b = 8'd40;
            end
            if (light_ns[0] &&
                x >= TLS_X + (TL_SEG*2) + 1 && x < TLS_X + (TL_SEG*3) - 1 &&
                y >= TLS_Y + 1 && y < TLS_Y + TL_SHORT - 1) begin
                r = 8'd30;  g = 8'd255; b = 8'd80;
            end

            // 西向（竖）
            if (light_ew[2] &&
                x >= TLW_X + 1 && x < TLW_X + TL_SHORT - 1 &&
                y >= TLW_Y + 1 && y < TLW_Y + TL_SEG - 1) begin
                r = 8'd255; g = 8'd20;  b = 8'd20;
            end
            if (light_ew[1] &&
                x >= TLW_X + 1 && x < TLW_X + TL_SHORT - 1 &&
                y >= TLW_Y + TL_SEG + 1 && y < TLW_Y + (TL_SEG*2) - 1) begin
                r = 8'd255; g = 8'd230; b = 8'd40;
            end
            if (light_ew[0] &&
                x >= TLW_X + 1 && x < TLW_X + TL_SHORT - 1 &&
                y >= TLW_Y + (TL_SEG*2) + 1 && y < TLW_Y + (TL_SEG*3) - 1) begin
                r = 8'd30;  g = 8'd255; b = 8'd80;
            end

            // 东向（竖）
            if (light_ew[2] &&
                x >= TLE_X + 1 && x < TLE_X + TL_SHORT - 1 &&
                y >= TLE_Y + 1 && y < TLE_Y + TL_SEG - 1) begin
                r = 8'd255; g = 8'd20;  b = 8'd20;
            end
            if (light_ew[1] &&
                x >= TLE_X + 1 && x < TLE_X + TL_SHORT - 1 &&
                y >= TLE_Y + TL_SEG + 1 && y < TLE_Y + (TL_SEG*2) - 1) begin
                r = 8'd255; g = 8'd230; b = 8'd40;
            end
            if (light_ew[0] &&
                x >= TLE_X + 1 && x < TLE_X + TL_SHORT - 1 &&
                y >= TLE_Y + (TL_SEG*2) + 1 && y < TLE_Y + (TL_SEG*3) - 1) begin
                r = 8'd30;  g = 8'd255; b = 8'd80;
            end

            // 7) HUD（动态扫描线 + 动态边框）
            if (x >= HUD_X_MIN && x < HUD_X_MAX &&
                y >= HUD_Y_MIN && y < HUD_Y_MAX) begin

                // 背景
                r = 8'd16; g = 8'd18; b = 8'd22;

                // 边框 + 流动高光
                if (x == HUD_X_MIN || x == HUD_X_MAX-1 || y == HUD_Y_MIN || y == HUD_Y_MAX-1) begin
                    r = 8'd60; g = 8'd70; b = 8'd90;
                    if ( (((x + {2'b0,anim}) & 10'd15) == 10'd0) ||
                         (((y + {2'b0,anim}) & 10'd15) == 10'd0) ) begin
                        r = add_sat8(r, 8'd40);
                        g = add_sat8(g, 8'd40);
                        b = add_sat8(b, 8'd60);
                    end
                end

                // 扫描线
                if ( (((y + {2'b0,anim}) % 10'd6) == 10'd0) ) begin
                    r = add_sat8(r, 8'd10);
                    g = add_sat8(g, 8'd14);
                    b = add_sat8(b, 8'd22);
                end

                // 亮扫描带
                if ( ((y + {2'b0,anim}) & 10'd31) == 10'd0 ) begin
                    r = add_sat8(r, 8'd18);
                    g = add_sat8(g, 8'd25);
                    b = add_sat8(b, 8'd35);
                end

                // 行 1: "NS:TT"
                if (draw_char (x, y, NS_TENS_X[9:0], NS_Y, 4'd0)) begin r=8'd220; g=8'd235; b=8'd255; end
                if (draw_char (x, y, NS_ONES_X[9:0], NS_Y, 4'd1)) begin r=8'd220; g=8'd235; b=8'd255; end
                if (draw_colon(x, y, NS_EW_SEP_X[9:0], NS_Y))       begin r=8'd220; g=8'd235; b=8'd255; end
                if (draw_digit(x, y, EW_TENS_X[9:0], NS_Y, ns_tens)) begin r=8'd220; g=8'd235; b=8'd255; end
                if (draw_digit(x, y, EW_ONES_X[9:0], NS_Y, ns_ones)) begin r=8'd220; g=8'd235; b=8'd255; end

                // 行 2: "EW:TT"
                if (draw_char (x, y, NS_TENS_X[9:0], EW_Y, 4'd2)) begin r=8'd220; g=8'd235; b=8'd255; end
                if (draw_char (x, y, NS_ONES_X[9:0], EW_Y, 4'd3)) begin r=8'd220; g=8'd235; b=8'd255; end
                if (draw_colon(x, y, NS_EW_SEP_X[9:0], EW_Y))       begin r=8'd220; g=8'd235; b=8'd255; end
                if (draw_digit(x, y, EW_TENS_X[9:0], EW_Y, ew_tens)) begin r=8'd220; g=8'd235; b=8'd255; end
                if (draw_digit(x, y, EW_ONES_X[9:0], EW_Y, ew_ones)) begin r=8'd220; g=8'd235; b=8'd255; end

                // 行 3: "MOD:N"
                if (draw_char_mod(x, y, NS_TENS_X[9:0], MODE_Y, 4'd4)) begin r=8'd220; g=8'd235; b=8'd255; end
                if (draw_char_mod(x, y, NS_ONES_X[9:0], MODE_Y, 4'd6)) begin r=8'd220; g=8'd235; b=8'd255; end
                if (draw_char_mod(x, y, NS_EW_SEP_X[9:0], MODE_Y, 4'd5)) begin r=8'd220; g=8'd235; b=8'd255; end
                if (draw_colon   (x, y, EW_TENS_X[9:0], MODE_Y)) begin r=8'd220; g=8'd235; b=8'd255; end
                if (draw_mode    (x, y, EW_ONES_X[9:0], MODE_Y, mode_num)) begin r=8'd255; g=8'd120; b=8'd140; end

                // 行 4: ALARM（N/S/W/E）
                if (draw_char(x, y, NS_TENS_X[9:0], ALARM_Y, 4'd0)) begin
                    if (viol_n) begin r=8'd255; g=8'd40;  b=8'd40; end
                    else        begin r=8'd170; g=8'd180; b=8'd200; end
                end
                if (draw_char(x, y, NS_ONES_X[9:0], ALARM_Y, 4'd1)) begin
                    if (viol_s) begin r=8'd255; g=8'd40;  b=8'd40; end
                    else        begin r=8'd170; g=8'd180; b=8'd200; end
                end
                if (draw_char(x, y, EW_TENS_X[9:0], ALARM_Y, 4'd3)) begin
                    if (viol_w) begin r=8'd255; g=8'd40;  b=8'd40; end
                    else        begin r=8'd170; g=8'd180; b=8'd200; end
                end
                if (draw_char(x, y, EW_ONES_X[9:0], ALARM_Y, 4'd2)) begin
                    if (viol_e) begin r=8'd255; g=8'd40;  b=8'd40; end
                    else        begin r=8'd170; g=8'd180; b=8'd200; end
                end
            end

            // 8) boom feeling：冲击闪光 + 环形冲击波（最后叠加）
            if (boom_amp != 8'd0) begin
                if ((x >= V_ROAD_X_L && x < V_ROAD_X_R) ||
                    (y >= H_ROAD_Y_T && y < H_ROAD_Y_B)) begin
                    r = add_sat8(r, boom_amp);
                    g = add_sat8(g, (boom_amp >> 2));
                    b = sub_sat8(b, (boom_amp >> 3));
                end

                dx_i = (x >= 10'd320) ? (x - 10'd320) : (10'd320 - x);
                dy_i = (y >= 10'd240) ? (y - 10'd240) : (10'd240 - y);
                d_i  = dx_i + dy_i;

                ring_pos = (anim << 1); // 扩散半径
                diff_i   = (d_i >= ring_pos) ? (d_i - ring_pos) : (ring_pos - d_i);

                if (diff_i < 4) begin
                    r = add_sat8(r, (boom_amp >> 1));
                    g = add_sat8(g, (boom_amp >> 3));
                    b = add_sat8(b, (boom_amp >> 2));
                end
            end
        end
    end

endmodule
