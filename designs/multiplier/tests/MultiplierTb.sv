// 中文：这是“单元测试”，只检查你的电路，不经过 FrameTop。
//       标有“通常保留”的部分负责搭建测试环境；标有“按设计修改”的部分
//       是你为自己的功能编写输入和检查结果的位置。
// English: This is the unit test. It checks only your circuit, without FrameTop.
//          Keep the test setup unless you know it must change. Edit the marked
//          stimulus/check section to match your circuit.

module MultiplierTb;

  // 通常保留 / Usually keep:
  // 用户设计固定有 66 位 IO；测试时钟每 5 ns 翻转一次。
  // A user design has 66 IO bits; the test clock toggles every 5 ns.
  localparam int IO_WIDTH = 66;
  localparam time HALF_PERIOD = 5ns;

  // 按设计修改 / Edit for your design:
  // Booth 部分积 + 修正项进入流水线，R1..R5 共 5 级寄存器。
  localparam int LATENCY = 5;

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
  // 有符号 16 位乘法的测试向量。
  logic [15:0] a_vec [0:7];
  logic [15:0] b_vec [0:7];
  logic signed [31:0] sa, sb, expected;

  initial begin
    a_vec[0] = 16'h0003;   b_vec[0] = 16'h0005;   // 15
    a_vec[1] = 16'hFFFD;   b_vec[1] = 16'h0005;   // -15
    a_vec[2] = 16'h0003;   b_vec[2] = 16'hFFFB;   // -15
    a_vec[3] = 16'hFFFD;   b_vec[3] = 16'hFFFB;   // 15
    a_vec[4] = 16'h7FFF;   b_vec[4] = 16'h7FFF;   // 1073676289
    a_vec[5] = 16'h8000;   b_vec[5] = 16'h8000;   // 1073741824
    a_vec[6] = 16'h0000;   b_vec[6] = 16'h3039;   // 0
    a_vec[7] = 16'h8000;   b_vec[7] = 16'h7FFF;   // -1073709056

    // 保持复位两个时钟，检查复位时的初始输出。
    repeat (2) @(posedge clock);
    #1ns;
    if (io_out[65] !== 1'b0 || io_out[63:32] !== 32'd0)
      $fatal(1, "reset state is incorrect");
    if (io_oe[65] !== 1'b1 || io_oe[64] !== 1'b0 ||
        io_oe[63:32] !== 32'hFFFF_FFFF || io_oe[31:0] !== 32'd0)
      $fatal(1, "io_oe mapping is incorrect");

    // 释放复位。
    @(negedge clock);
    reset = 1'b0;

    // 逐个送入向量，等待流水线延迟后检查结果。
    for (int i = 0; i < 8; i++) begin
      @(negedge clock);
      io_in[15:0]  = a_vec[i];
      io_in[31:16] = b_vec[i];
      io_in[64]    = 1'b1;

      repeat (LATENCY) @(posedge clock);
      #1ns;

      sa       = {{16{a_vec[i][15]}}, a_vec[i]};
      sb       = {{16{b_vec[i][15]}}, b_vec[i]};
      expected = sa * sb;

      if (io_out[65] !== 1'b1)
        $fatal(1, "case %0d: valid_o did not assert", i);
      if ($signed(io_out[63:32]) !== expected)
        $fatal(1, "case %0d: got %0d, expected %0d",
               i, $signed(io_out[63:32]), expected);
      $display("case %0d: %0d * %0d = %0d  OK", i, sa, sb, expected);
    end

    $display("MULTIPLIER UNIT TEST PASS");
    $finish;
  end

endmodule
