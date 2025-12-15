// vga_sync_640x480.v
// 生成 640x480@60Hz 的 HS/VS 和扫屏坐标

module vga_sync_640x480 (
    input  wire       clk,       // 约 25 MHz 像素时钟
    input  wire       reset_n,   // 低有效复位
    output reg [9:0]  h_count,   // 0..799
    output reg [9:0]  v_count,   // 0..524
    output wire       hsync,     // 负极性
    output wire       vsync,     // 负极性
    output wire       video_on   // 仅在可视区为 1
);

    // 水平参数
    localparam H_VISIBLE = 640;
    localparam H_FRONT   = 16;
    localparam H_SYNC    = 96;
    localparam H_BACK    = 48;
    localparam H_MAX     = H_VISIBLE + H_FRONT + H_SYNC + H_BACK; // 800

    // 垂直参数
    localparam V_VISIBLE = 480;
    localparam V_FRONT   = 10;
    localparam V_SYNC    = 2;
    localparam V_BACK    = 33;
    localparam V_MAX     = V_VISIBLE + V_FRONT + V_SYNC + V_BACK; // 525

    // 行列计数
    wire h_end = (h_count == H_MAX - 1);
    wire v_end = (v_count == V_MAX - 1);

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            h_count <= 10'd0;
            v_count <= 10'd0;
        end else begin
            if (h_end) begin
                h_count <= 10'd0;
                if (v_end)
                    v_count <= 10'd0;
                else
                    v_count <= v_count + 10'd1;
            end else begin
                h_count <= h_count + 10'd1;
            end
        end
    end

    // 同步脉冲位置（负极性）
    localparam HSYNC_START = H_VISIBLE + H_FRONT;        // 656
    localparam HSYNC_END   = HSYNC_START + H_SYNC;       // 752 (非包含上界)

    localparam VSYNC_START = V_VISIBLE + V_FRONT;        // 490
    localparam VSYNC_END   = VSYNC_START + V_SYNC;       // 492

    assign hsync = ~((h_count >= HSYNC_START) && (h_count < HSYNC_END));
    assign vsync = ~((v_count >= VSYNC_START) && (v_count < VSYNC_END));

    // 有效显示区
    assign video_on = (h_count < H_VISIBLE) && (v_count < V_VISIBLE);

endmodule
