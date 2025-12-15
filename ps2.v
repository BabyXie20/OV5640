// ============================================================
// PS/2 Receiver (单时钟域重构版)
// 接口保持与原 ps2 模块一致：
//   - clock_key : PS/2 键盘时钟引脚
//   - data_key  : PS/2 键盘数据引脚
//   - clock_fpga: FPGA 系统时钟（例如 50 MHz）
//   - reset     : 低有效复位
//   - data_out  : 8-bit 扫描码（make code 的 data 字节）
//   - new_code  : 在 data_out 有新且合法数据时拉高一个 clock_fpga 周期
//   - led       : 这里简单等于 new_code
// ============================================================
module ps2 (
    // PS/2 物理引脚
    input  wire clock_key,   // PS/2 clock
    input  wire data_key,    // PS/2 data

    // FPGA 侧
    input  wire clock_fpga,  // FPGA 主时钟
    input  wire reset,       // 低有效复位

    output wire led,         // 指示灯：有新码时亮一个周期
    output wire [7:0] data_out, // 输出扫描码
    output wire new_code     // 新码到达脉冲（1 个 clock_fpga 周期）
);

    // ========================================================
    // 1. 将 PS/2 时钟与数据同步到 FPGA 时钟域（两级打拍）
    // ========================================================
    reg [2:0] ps2_clk_sync;
    reg [2:0] ps2_data_sync;

    always @(posedge clock_fpga or negedge reset) begin
        if (!reset) begin
            ps2_clk_sync  <= 3'b111;  // PS/2 空闲为高电平
            ps2_data_sync <= 3'b111;
        end else begin
            ps2_clk_sync  <= {ps2_clk_sync[1:0],  clock_key};
            ps2_data_sync <= {ps2_data_sync[1:0], data_key};
        end
    end

    // 同步后的 PS/2 数据（取最后一级）
    wire ps2_data_s = ps2_data_sync[2];

    // 检测 PS/2 时钟在 FPGA 时钟域中的下降沿：11 -> 10
    wire ps2_clk_falling = (ps2_clk_sync[2:1] == 2'b10);

    // ========================================================
    // 2. 在 PS/2 时钟下降沿上串行移位，构造 11bit 帧
    //    帧格式：bit0=start(0), bit[8:1]=data[7:0], bit9=parity, bit10=stop(1)
    // ========================================================
    reg [10:0] shift_reg;   // 串入并出移位寄存器
    reg [3:0]  bit_count;   // 计数 0..10，共 11 位

    // 预先组合出“下一拍移完后的寄存器内容”
    wire [10:0] next_shift = {ps2_data_s, shift_reg[10:1]};

    // 当 bit_count == 10 时，这一拍再来一个下降沿，就正好收齐 11 位
    wire frame_done = (bit_count == 4'd10);

    // ========================================================
    // 3. 并行检查一帧数据的合法性（start/stop/奇校验）
    // ========================================================
    // 按照 next_shift 的定义，位含义为：
    //   next_shift[0]  = start
    //   next_shift[8:1]= data[7:0]
    //   next_shift[9]  = parity
    //   next_shift[10] = stop
    wire start_ok   = (next_shift[0]  == 1'b0); // PS/2 start must be 0
    wire stop_ok    = (next_shift[10] == 1'b1); // PS/2 stop must be 1

    // PS/2 为奇校验：data[7:0] + parity 的 1 的个数应为奇数
    // 对 9bit {parity, data[7:0]} 做 XOR 归约，结果为 1 表示奇数个 1
    wire parity_odd = ^{next_shift[9], next_shift[8:1]};
    wire parity_ok  = parity_odd;  // 1 表示满足奇校验

    wire frame_valid = start_ok & stop_ok & parity_ok;

    // ========================================================
    // 4. 在帧收齐时，如果合法则输出扫描码 + new_code 脉冲
    // ========================================================
    reg [7:0] data_reg;
    reg       new_code_reg;

    always @(posedge clock_fpga or negedge reset) begin
        if (!reset) begin
            shift_reg    <= 11'd0;
            bit_count    <= 4'd0;
            data_reg     <= 8'd0;
            new_code_reg <= 1'b0;
        end else begin
            // 默认 new_code 拉低（产生 1 个周期的脉冲）
            new_code_reg <= 1'b0;

            if (ps2_clk_falling) begin
                // 每个 PS/2 时钟下降沿移入 1 位
                shift_reg <= next_shift;

                if (frame_done) begin
                    // 收满 11 位，准备开始下一帧
                    bit_count <= 4'd0;

                    // 在这一拍使用 next_shift 的值做合法性检查
                    if (frame_valid) begin
                        data_reg     <= next_shift[8:1]; // 8-bit 扫描码
                        new_code_reg <= 1'b1;            // 有新且合法数据
                    end
                    // 如果不合法，则丢弃本帧，new_code 保持 0
                end else begin
                    // 还没收满 11 位，继续计数
                    bit_count <= bit_count + 4'd1;
                end
            end
        end
    end

    // ========================================================
    // 5. 输出映射
    // ========================================================
    assign data_out = data_reg;
    assign new_code = new_code_reg;
    assign led      = new_code_reg;  // 简单起见：有新码时闪灯

endmodule
