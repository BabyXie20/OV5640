module clk_div_sec #(
    //50MHz 时钟 -> 1 秒一个 tick
    parameter CNT_MAX = 32'd50_000_000 - 1
)(
    input       clk,
    input       rst_n,
    output reg  tick_1s
);
    reg [31:0] cnt;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cnt     <= 32'd0;
            tick_1s <= 1'b0;
        end else begin
            if (cnt >= CNT_MAX) begin
                cnt     <= 32'd0;
                tick_1s <= 1'b1;   // 产生一个周期为 1 个 clk 的脉冲  
            end else begin
                cnt     <= cnt + 32'd1;
                tick_1s <= 1'b0;
            end
        end
    end

endmodule
