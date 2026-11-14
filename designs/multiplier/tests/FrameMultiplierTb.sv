// 中文：这是“Frame 集成测试”。信号会经过外部 user_io、FrameTop 和你的设计。
//       它检查 design 编号能否被选中，以及输入和输出能否通过真实连接传递。
//       标有“通常保留”的选择流程不要随意修改；标有“按设计修改”的功能检查
//       应替换为你自己的输入和期望输出。
// English: This is the Frame integration test. Signals travel through user_io,
//          FrameTop, and your design. Keep the selection sequence unless the
//          frame protocol changes. Edit the marked functional checks.

module FrameMultiplierTb;

  // 由构建工具为本次 Frame 测试注入临时或正式 ID，用户无需填写。
  // The build tool injects a temporary or registered ID for this Frame test.
`ifndef FRAME_TEST_DESIGN_ID
  initial $error("FRAME_TEST_DESIGN_ID must be provided by the build tool");
`endif

  // 通常保留 / Usually keep:
  localparam int IO_WIDTH = 73;
  localparam int DESIGN_ID_WIDTH = 7;
  localparam logic [DESIGN_ID_WIDTH-1:0] DESIGN_ID = `FRAME_TEST_DESIGN_ID;
  localparam time HALF_PERIOD = 5ns;

  // 按设计修改 / Edit for your design:
  // 与单元测试一致：流水线 R1..R4 共 4 级（3-2 与 CPA 合并在末级）。
  localparam int LATENCY = 4;

  // test_io_out 是测试环境准备驱动的值；test_io_oe 对应位为 1 时才真正驱动。
  // test_io_out holds values from the test; test_io_oe enables each driven pin.
  // 构建工具使用 reset、test_io_oe 和 dut 连接自动生成的争用检查，请勿重命名。
  logic clock = 1'b0;
  logic reset = 1'b1;
  logic [IO_WIDTH-1:0] test_io_out = '0;
  logic [IO_WIDTH-1:0] test_io_oe = '0;
  tri [IO_WIDTH-1:0] user_io;

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

  // 送入一组输入（经 user_io 通路），等待 LATENCY 拍后校验输出。
  task automatic run_case(input int tag,
                          input logic [15:0] a, input logic [15:0] b,
                          input bit verbose);
    begin
      sa       = {{16{a[15]}}, a};
      sb       = {{16{b[15]}}, b};
      expected = sa * sb;

      @(negedge clock);
      test_io_out[DESIGN_ID_WIDTH+15 : DESIGN_ID_WIDTH+0]  = a;
      test_io_out[DESIGN_ID_WIDTH+31 : DESIGN_ID_WIDTH+16] = b;
      test_io_out[DESIGN_ID_WIDTH+64] = 1'b1;

      repeat (LATENCY) @(posedge clock);
      #1ns;

      if (user_io[DESIGN_ID_WIDTH+65] !== 1'b1)
        $fatal(1, "tag %0d: a=%0d b=%0d: valid_o did not assert at user_io[72]",
               tag, sa, sb);
      if ($signed(user_io[DESIGN_ID_WIDTH+63 : DESIGN_ID_WIDTH+32]) !== expected)
        $fatal(1, "tag %0d: a=%0d b=%0d: got %0d, expected %0d",
               tag, sa, sb,
               $signed(user_io[DESIGN_ID_WIDTH+63 : DESIGN_ID_WIDTH+32]), expected);
      pass_count++;
      if (verbose)
        $display("tag %0d: %0d * %0d = %0d  OK", tag, sa, sb, expected);
    end
  endtask

  always #(HALF_PERIOD) clock = ~clock;

  // 通常保留 / Usually keep:
  for (genvar io_index = 0; io_index < IO_WIDTH; io_index++) begin : gen_test_io
    assign user_io[io_index] = test_io_oe[io_index]
      ? test_io_out[io_index]
      : 1'bz;
  end

  FrameTop dut (
    .clock(clock), .reset(reset), .user_io(user_io)
  );

  initial begin
    // 通常保留 / Usually keep:
    // 在 reset=1 期间，用 user_io[6:0] 驱动本设计编号。
    test_io_oe[DESIGN_ID_WIDTH-1:0] = '1;
    test_io_out[DESIGN_ID_WIDTH-1:0] = DESIGN_ID;
    repeat (20) @(posedge clock);
    @(negedge clock);
    reset = 1'b0;
    repeat (4) @(posedge clock);
    #1ns;

    if (!dut.selection_valid || !dut.design_selected[DESIGN_ID])
      $fatal(1, "generated design was not selected through FrameTop");

    // 按设计修改 / Edit for your design:
    // payload 换算：设计 io_*[n] <-> 外部 user_io[n+7]。
    // 输入：a = io_in[15:0]  -> user_io[22:7]
    //       b = io_in[31:16] -> user_io[38:23]
    //       valid_i = io_in[64] -> user_io[71]
    // 输出：result = io_out[63:32] -> user_io[70:39]
    //       valid_o = io_out[65] -> user_io[72]
    // 只驱动设计未使能输出的引脚。
    test_io_oe[DESIGN_ID_WIDTH+15 : DESIGN_ID_WIDTH+0]  = '1;  // a
    test_io_oe[DESIGN_ID_WIDTH+31 : DESIGN_ID_WIDTH+16] = '1;  // b
    test_io_oe[DESIGN_ID_WIDTH+64] = 1'b1;                     // valid_i

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

    $display("MULTIPLIER FRAME TEST PASS (%0d total cases)", pass_count);
    $finish;
  end

endmodule
