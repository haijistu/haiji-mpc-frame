// 中文：这是“单元测试”，只检查你的电路，不经过 FrameTop。
//       标有“通常保留”的部分负责搭建测试环境；标有“按设计修改”的部分
//       是你为自己的功能编写输入和检查结果的位置。
// English: This is the unit test. It checks only your circuit, without FrameTop.
//          Keep the test setup unless you know it must change. Edit the marked
//          stimulus/check section to match your circuit.

module Gcd16Tb;

  // 通常保留 / Usually keep:
  // 用户设计固定有 66 位 IO；测试时钟每 5 ns 翻转一次。
  // A user design has 66 IO bits; the test clock toggles every 5 ns.
  localparam int IO_WIDTH = 66;
  localparam time HALF_PERIOD = 5ns;

  // 按设计修改 / Edit for your design:
  // 欧几里得取模迭代的拍数不固定（最坏约 24 轮 x 16 拍），
  // 因此用 wait_valid_o 任务 + 超时保护等待完成，而不是固定拍数。

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
  // 16 位无符号最大公约数的测试向量（含 a==0 / b==0 / 最坏 Fibonacci 情况）。
  logic [15:0] a_vec [0:8];
  logic [15:0] b_vec [0:8];
  logic [15:0] g_exp [0:8];
  integer watchdog;

  // 等待 valid_o 置位，带超时保护。
  // Wait for valid_o to assert, with a timeout guard.
  task automatic wait_valid_o(input integer case_idx);
    watchdog = 0;
    while (io_out[65] !== 1'b1) begin
      @(posedge clock);
      #1;  // 偏离时钟沿，等 NBA 提交后再采样，避免读到 DONE 拍的旧值
      watchdog = watchdog + 1;
      if (watchdog > 2000)
        $fatal(1, "case %0d: valid_o timeout", case_idx);
    end
  endtask

  initial begin
    a_vec[0] = 16'd48;     b_vec[0] = 16'd18;    g_exp[0] = 16'd6;
    a_vec[1] = 16'd100;    b_vec[1] = 16'd7;     g_exp[1] = 16'd1;
    a_vec[2] = 16'd65535;  b_vec[2] = 16'd65535; g_exp[2] = 16'd65535;
    a_vec[3] = 16'd0;      b_vec[3] = 16'd7;     g_exp[3] = 16'd7;
    a_vec[4] = 16'd7;      b_vec[4] = 16'd0;     g_exp[4] = 16'd7;
    a_vec[5] = 16'd0;      b_vec[5] = 16'd0;     g_exp[5] = 16'd0;
    a_vec[6] = 16'd12345;  b_vec[6] = 16'd100;   g_exp[6] = 16'd5;
    a_vec[7] = 16'd46368;  b_vec[7] = 16'd28657; g_exp[7] = 16'd1; // Fibonacci 最坏情况
    a_vec[8] = 16'd50000;  b_vec[8] = 16'd25000; g_exp[8] = 16'd25000;

    // 保持复位两个时钟，检查复位时的初始输出。
    // Hold reset for two clocks and check the initial outputs.
    repeat (2) @(posedge clock);
    #1ns;
    if (io_out[65] !== 1'b0 || io_out[15:0] !== 16'd0)
      $fatal(1, "reset state is incorrect");
    // gcd 区 oe 只在 DONE 时打开，复位期间应为 0。
    // The gcd output-enable is only active in DONE; during reset it is 0.
    if (io_oe[65] !== 1'b1 || io_oe[64] !== 1'b0 ||
        io_oe[63:16] !== 48'd0 || io_oe[15:0] !== 16'd0)
      $fatal(1, "io_oe mapping is incorrect");

    // 释放复位。
    // Release reset.
    @(negedge clock);
    reset = 1'b0;

    // 逐个送入向量：等待 valid_o 握手完成后检查结果；每次请求后把 valid_i
    // 拉低，等 valid_o 拉低（回到 IDLE）再送下一个。
    // Drive each vector, wait for the valid_o handshake, then release valid_i
    // and wait for valid_o to fall before sending the next one.
    for (int i = 0; i < 9; i++) begin
      @(negedge clock);
      io_in[15:0]  = a_vec[i];
      io_in[31:16] = b_vec[i];
      io_in[64]    = 1'b1;

      wait_valid_o(i);
      #1ns;

      // DONE 拍：valid_o=1，gcd 区 oe 打开并输出结果。
      // In DONE, valid_o is high, the gcd output-enable is on, and the result is out.
      if (io_out[65] !== 1'b1 || io_oe[15:0] !== 16'hFFFF)
        $fatal(1, "case %0d: valid_o or gcd oe is incorrect", i);
      if (io_out[15:0] !== g_exp[i])
        $fatal(1, "case %0d: gcd got %0d, expected %0d",
               i, io_out[15:0], g_exp[i]);
      $display("case %0d: gcd(%0d, %0d) = %0d  OK", i, a_vec[i], b_vec[i], g_exp[i]);

      // 释放请求并等设计回到 IDLE（valid_o 拉低）。
      // Release the request and wait for the design to return to IDLE.
      @(negedge clock);
      io_in[64] = 1'b0;
      wait (io_out[65] === 1'b0);
    end

    $display("GCD16 UNIT TEST PASS");
    $finish;
  end

endmodule
