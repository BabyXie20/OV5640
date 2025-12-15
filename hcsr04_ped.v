module hcsr04_ped #(
    parameter integer THRESH_CM = 20,   // 小于等于该距离判定“有人”
    parameter integer PULSE_MS  = 50,   // ped_req 保持时间（ms）
    parameter integer PERIOD_MS = 60    // 测距周期（ms，建议 >= 60ms）
)(
    input  wire clk,
    input  wire rst_n,
    input  wire echo_in,     // 外部需先转换到 3.3V
    output reg  trig_out,    // 10us 触发脉冲
    output reg  ped_req      // 保持 PULSE_MS 的请求电平
);

    localparam integer CLK_HZ     = 50_000_000;
    localparam integer US_DIV     = CLK_HZ / 1_000_000;      // 50
    localparam integer TRIG_US    = 10;
    localparam integer TIMEOUT_US = 30_000;                  // 30ms 超时
    localparam integer PERIOD_US  = PERIOD_MS * 1000;
    localparam integer HOLD_US    = PULSE_MS  * 1000;

    localparam integer THRESH_US  = THRESH_CM * 58;          // 距离换算：us/58 ≈ cm

    // ---- echo 同步（两级）----
    reg echo_ff1, echo_ff2;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            echo_ff1 <= 1'b0;
            echo_ff2 <= 1'b0;
        end else begin
            echo_ff1 <= echo_in;
            echo_ff2 <= echo_ff1;
        end
    end
    wire echo = echo_ff2;

    // ---- 1us tick ----
    reg [$clog2(US_DIV)-1:0] us_cnt;
    reg us_tick;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            us_cnt  <= 0;
            us_tick <= 1'b0;
        end else begin
            if (us_cnt == US_DIV-1) begin
                us_cnt  <= 0;
                us_tick <= 1'b1;
            end else begin
                us_cnt  <= us_cnt + 1;
                us_tick <= 1'b0;
            end
        end
    end

    // ---- 测距 FSM ----
    localparam [2:0]
        ST_WAIT   = 3'd0,
        ST_TRIG   = 3'd1,
        ST_ECHO_H = 3'd2,
        ST_ECHO_W = 3'd3,
        ST_DONE   = 3'd4;

    reg [2:0] st;

    reg [31:0] t_us;          // 通用 us 计数
    reg [31:0] echo_w_us;     // echo 高电平宽度(us)

    reg near_now;
    reg near_prev;

    reg [31:0] hold_us;       // ped_req 保持计数(us)

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st        <= ST_WAIT;
            trig_out  <= 1'b0;
            t_us      <= 0;
            echo_w_us <= 0;
            near_now  <= 1'b0;
            near_prev <= 1'b0;
            ped_req   <= 1'b0;
            hold_us   <= 0;
        end else begin
            // ped_req 保持逻辑（独立）
            if (us_tick) begin
                if (hold_us != 0) begin
                    hold_us <= hold_us - 1;
                    ped_req <= 1'b1;
                end else begin
                    ped_req <= 1'b0;
                end
            end

            if (us_tick) begin
                case (st)
                    ST_WAIT: begin
                        trig_out <= 1'b0;
                        if (t_us >= PERIOD_US) begin
                            t_us <= 0;
                            st   <= ST_TRIG;
                        end else begin
                            t_us <= t_us + 1;
                        end
                    end

                    ST_TRIG: begin
                        trig_out <= 1'b1;
                        if (t_us >= TRIG_US) begin
                            trig_out  <= 1'b0;
                            t_us      <= 0;
                            echo_w_us <= 0;
                            st        <= ST_ECHO_H;
                        end else begin
                            t_us <= t_us + 1;
                        end
                    end

                    ST_ECHO_H: begin
                        // 等待 echo 拉高（带超时）
                        if (echo) begin
                            t_us <= 0;
                            st   <= ST_ECHO_W;
                        end else if (t_us >= TIMEOUT_US) begin
                            t_us <= 0;
                            st   <= ST_DONE;
                        end else begin
                            t_us <= t_us + 1;
                        end
                    end

                    ST_ECHO_W: begin
                        // 统计 echo 高电平宽度（带超时）
                        if (!echo) begin
                            st <= ST_DONE;
                        end else if (echo_w_us >= TIMEOUT_US) begin
                            st <= ST_DONE;
                        end else begin
                            echo_w_us <= echo_w_us + 1;
                        end
                    end

                    ST_DONE: begin
                        // 计算 near_now（一次测距结果）
                        // echo_w_us=0 表示无有效回波：near_now=0
                        if (echo_w_us != 0 && echo_w_us <= THRESH_US)
                            near_now <= 1'b1;
                        else
                            near_now <= 1'b0;

                        // “有人”上升沿 -> 发一次 ped_req（保持 HOLD_US）
                        if ((echo_w_us != 0 && echo_w_us <= THRESH_US) && !near_prev) begin
                            hold_us <= HOLD_US;
                        end

                        near_prev <= (echo_w_us != 0 && echo_w_us <= THRESH_US);

                        // 回到等待
                        t_us      <= 0;
                        echo_w_us <= 0;
                        st        <= ST_WAIT;
                    end

                    default: st <= ST_WAIT;
                endcase
            end
        end
    end

endmodule
