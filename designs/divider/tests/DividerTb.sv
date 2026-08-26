// 中文：这是“单元测试”，只检查你的电路，不经过 FrameTop。
//       标有“通常保留”的部分负责搭建测试环境；标有“按设计修改”的部分
//       是你为自己的功能编写输入和检查结果的位置。
// English: This is the unit test. It checks only your circuit, without FrameTop.
//          Keep the test setup unless you know it must change. Edit the marked
//          stimulus/check section to match your circuit.

module DividerTb;

  // 通常保留 / Usually keep:
  // 用户设计固定有 66 位 IO；测试时钟每 5 ns 翻转一次。
  // A user design has 66 IO bits; the test clock toggles every 5 ns.
  localparam int IO_WIDTH = 66;
  localparam time HALF_PERIOD = 5ns;

  // 按设计修改 / Edit for your design:
  // 状态机延迟：1 拍载入（IDLE）+ 16 拍迭代（COMPUTE）+ 1 拍 DONE。
  // 测试用 valid_o 握手等待完成，case 之间等待 valid_o 拉低回到 IDLE。

  // 通常保留 / Usually keep:
  logic clock = 1'b0;
  logic reset = 1'b1;
  logic [IO_WIDTH-1:0] io_in = '0;
  wire [IO_WIDTH-1:0] io_out;
  wire [IO_WIDTH-1:0] io_oe;

  always #(HALF_PERIOD) clock = ~clock;

  // 不要修改模块名 UserDesignDut。构建工具会让它连接到你的顶层模块。
  // Do not rename UserDesignDut. The build tool connects it to your top module.
  UserDesignDut #(.IO_WIDTH(IO_WIDTH)) dut (
    .clock(clock), .reset(reset), .io_in(io_in),
    .io_out(io_out), .io_oe(io_oe)
  );

  // 按设计修改 / Edit for your design:
  // 16 位无符号除法的测试向量（含除零）。
  logic [15:0] a_vec [0:7];
  logic [15:0] b_vec [0:7];
  logic [15:0] q_exp [0:7];
  logic [15:0] r_exp [0:7];

  initial begin
    a_vec[0] = 16'd100;    b_vec[0] = 16'd7;     q_exp[0] = 16'd14;     r_exp[0] = 16'd2;
    a_vec[1] = 16'd65535;  b_vec[1] = 16'd1;     q_exp[1] = 16'd65535;  r_exp[1] = 16'd0;
    a_vec[2] = 16'd50000;  b_vec[2] = 16'd10;    q_exp[2] = 16'd5000;   r_exp[2] = 16'd0;
    a_vec[3] = 16'd12345;  b_vec[3] = 16'd100;   q_exp[3] = 16'd123;    r_exp[3] = 16'd45;
    a_vec[4] = 16'd0;      b_vec[4] = 16'd7;     q_exp[4] = 16'd0;      r_exp[4] = 16'd0;
    a_vec[5] = 16'd65535;  b_vec[5] = 16'd65535; q_exp[5] = 16'd1;      r_exp[5] = 16'd0;
    a_vec[6] = 16'd12345;  b_vec[6] = 16'd0;     q_exp[6] = 16'hFFFF;   r_exp[6] = 16'd12345; // 除零
    a_vec[7] = 16'd1000;   b_vec[7] = 16'd333;   q_exp[7] = 16'd3;      r_exp[7] = 16'd1;

    // 保持复位两个时钟，检查复位时的初始输出。
    repeat (2) @(posedge clock);
    #1ns;
    if (io_out[65] !== 1'b0 || io_out[63:48] !== 16'd0 || io_out[47:32] !== 16'd0)
      $fatal(1, "reset state is incorrect");
    if (io_oe[65] !== 1'b1 || io_oe[64] !== 1'b0 ||
        io_oe[63:48] !== 16'hFFFF || io_oe[47:32] !== 16'hFFFF || io_oe[31:0] !== 32'd0)
      $fatal(1, "io_oe mapping is incorrect");

    // 释放复位。
    @(negedge clock);
    reset = 1'b0;

    // 逐个送入向量：等待状态机完成（17 拍：载入+16 迭代）后检查结果；
    // 每次请求后把 valid_i 拉低，等 valid_o 拉低（回到 IDLE）再送下一个，
    // 避免 DONE 周期吞掉下一次请求或 IDLE 重复采样。
    for (int i = 0; i < 8; i++) begin
      @(negedge clock);
      io_in[15:0]  = a_vec[i];
      io_in[31:16] = b_vec[i];
      io_in[64]    = 1'b1;

      repeat (17) @(posedge clock);
      #1ns;

      if (io_out[65] !== 1'b1)
        $fatal(1, "case %0d: valid_o did not assert", i);
      if (io_out[63:48] !== q_exp[i])
        $fatal(1, "case %0d: quotient got %0d, expected %0d",
               i, io_out[63:48], q_exp[i]);
      if (io_out[47:32] !== r_exp[i])
        $fatal(1, "case %0d: reminder got %0d, expected %0d",
               i, io_out[47:32], r_exp[i]);
      $display("case %0d: %0d / %0d = %0d r %0d  OK", i, a_vec[i], b_vec[i], q_exp[i], r_exp[i]);

      // 释放请求并等设计回到 IDLE（valid_o 拉低）
      @(negedge clock);
      io_in[64] = 1'b0;
      wait (io_out[65] === 1'b0);
    end

    $display("DIVIDER UNIT TEST PASS");
    $finish;
  end

endmodule
