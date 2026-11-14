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
  // Booth 部分积 + 修正项进入流水线，R1..R4 共 4 级寄存器（3-2 与 CPA 合并在末级）。
  localparam int LATENCY = 4;

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
  // 有符号 16 位乘法：参考模型 sa*sb（16x16 -> 32 位补码结果，不会溢出 32 位）。

  // ---- A 组：定向边界用例（元素编码为 {b[15:0], a[15:0]}）----
  localparam int DIR_N = 22;
  localparam logic [31:0] DIR_CASES [DIR_N] = '{
    32'h0003_0005,  // a=+5      b=+3     -> +15
    32'h0003_FFFB,  // a=-5      b=+3     -> -15
    32'hFFFD_0005,  // a=+5      b=-3     -> -15
    32'hFFFD_FFFB,  // a=-5      b=-3     -> +15
    32'h0000_0000,  // a=0       b=0      -> 0
    32'h3039_0000,  // a=0       b=12345  -> 0
    32'h0000_7FFF,  // a=32767   b=0      -> 0
    32'h0001_0001,  // a=1       b=1      -> 1
    32'h7FFF_0001,  // a=1       b=32767  -> 32767（最大正数）
    32'h8000_FFFF,  // a=-32768  b=-1     -> 32768（-1 翻转最小负）
    32'hFFFF_7FFF,  // a=32767   b=-1     -> -32767
    32'h7FFF_7FFF,  // a=32767   b=32767  -> 1073676289（最大正积）
    32'h8000_7FFF,  // a=32767   b=-32768 -> -1073709056（最负积）
    32'h7FFF_8000,  // a=-32768  b=32767  -> -1073709056
    32'h8000_8000,  // a=-32768  b=-32768 -> 2^30 = 1073741824（最大积）
    32'h4000_4000,  // a=16384   b=16384  -> 2^28
    32'hC000_4000,  // a=16384   b=-16384 -> -2^28
    32'h4000_C000,  // a=-16384  b=16384  -> -2^28
    32'h0002_7FFF,  // a=32767   b=2      -> 65534（触发 +2x 高位保护）
    32'hFFFE_7FFF,  // a=32767   b=-2     -> -65534（触发 -2x 取反）
    32'h0002_8000,  // a=-32768  b=2      -> -65536
    32'hFFFE_8000   // a=-32768  b=-2     -> 65536（负倍数取反+1 的极端）
  };

  // ---- B 组：交叉乘积的边界常数 ----
  localparam int BND_N = 14;
  localparam logic [15:0] BND [BND_N] = '{
    16'h0000,  // 0
    16'h0001,  // 1
    16'hFFFF,  // -1
    16'h0002,  // 2
    16'hFFFE,  // -2
    16'h4000,  // 16384 (2^14)
    16'hC000,  // -16384
    16'h7FFF,  // 32767（最大正）
    16'h8001,  // -32767
    16'h8000,  // -32768（最小负）
    16'h7FFE,  // 32766
    16'h2000,  // 8192 (2^13)
    16'h5555,  // 21845（01 交替位型）
    16'hAAAA   // -21846（10 交替位型）
  };

  // ---- 可复现伪随机源：Xorshift32 ----
  logic [31:0] rng = 32'h89AB_CDEF;
  function automatic logic [31:0] next_rand(input logic [31:0] x);
    logic [31:0] y;
    y = x ^ (x << 13);
    y = y ^ (y >> 17);
    y = y ^ (y << 5);
    return y;
  endfunction

  // ---- 运行与检查 ----
  logic [15:0] a_i, b_i;
  logic signed [31:0] sa, sb, expected;
  int unsigned pass_count = 0;

  // 送入一组输入，等待 LATENCY 拍后校验输出。
  task automatic run_case(input int tag,
                          input logic [15:0] a, input logic [15:0] b,
                          input bit verbose);
    begin
      sa       = {{16{a[15]}}, a};
      sb       = {{16{b[15]}}, b};
      expected = sa * sb;

      @(negedge clock);
      io_in[15:0]  = a;
      io_in[31:16] = b;
      io_in[64]    = 1'b1;

      repeat (LATENCY) @(posedge clock);
      #1ns;

      if (io_out[65] !== 1'b1)
        $fatal(1, "tag %0d: a=%0d b=%0d: valid_o did not assert",
               tag, sa, sb);
      if ($signed(io_out[63:32]) !== expected)
        $fatal(1, "tag %0d: a=%0d b=%0d: got %0d, expected %0d",
               tag, sa, sb, $signed(io_out[63:32]), expected);
      pass_count++;
      if (verbose)
        $display("tag %0d: %0d * %0d = %0d  OK", tag, sa, sb, expected);
    end
  endtask

  initial begin
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

    // 逐组运行：
    //  A 组：定向边界（逐个打印）
    for (int i = 0; i < DIR_N; i++)
      run_case(i, DIR_CASES[i][15:0], DIR_CASES[i][31:16], 1'b1);
    $display("A: %0d/%0d directed boundary cases passed", pass_count, DIR_N);

    //  B 组：边界常数两两全乘（14 x 14 = 196）
    for (int i = 0; i < BND_N; i++)
      for (int j = 0; j < BND_N; j++)
        run_case(1000 + i * BND_N + j, BND[i], BND[j], 1'b0);
    $display("B: %0d/%0d boundary cross cases passed",
             pass_count, DIR_N + BND_N * BND_N);

    //  C 组：固定种子伪随机（Xorshift32，可复现）
    for (int i = 0; i < 512; i++) begin
      rng = next_rand(rng);
      a_i = rng[31:16];
      rng = next_rand(rng);
      b_i = rng[15:0];
      run_case(2000 + i, a_i, b_i, 1'b0);
    end
    $display("C: %0d/%0d random cases passed",
             pass_count - (DIR_N + BND_N * BND_N), 512);

    $display("MULTIPLIER UNIT TEST PASS (%0d total cases)", pass_count);
    $finish;
  end

endmodule
