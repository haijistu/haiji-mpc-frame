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
  // 与单元测试一致：流水线 R1..R5 共 5 级。
  localparam int LATENCY = 5;

  // test_io_out 是测试环境准备驱动的值；test_io_oe 对应位为 1 时才真正驱动。
  // test_io_out holds values from the test; test_io_oe enables each driven pin.
  // 构建工具使用 reset、test_io_oe 和 dut 连接自动生成的争用检查，请勿重命名。
  logic clock = 1'b0;
  logic reset = 1'b1;
  logic [IO_WIDTH-1:0] test_io_out = '0;
  logic [IO_WIDTH-1:0] test_io_oe = '0;
  tri [IO_WIDTH-1:0] user_io;

  // 按设计修改 / Edit for your design:
  // 测试向量与参考结果变量。
  logic [15:0] a_vec [0:3];
  logic [15:0] b_vec [0:3];
  logic signed [31:0] sa, sb, expected;

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

    // 测试向量
    a_vec[0] = 16'hFFFD;   b_vec[0] = 16'h0005;   // -15
    a_vec[1] = 16'h7FFF;   b_vec[1] = 16'h7FFF;   // 1073676289
    a_vec[2] = 16'h8000;   b_vec[2] = 16'h8000;   // 1073741824
    a_vec[3] = 16'h8000;   b_vec[3] = 16'h7FFF;   // -1073709056

    for (int i = 0; i < 4; i++) begin
      @(negedge clock);
      test_io_out[DESIGN_ID_WIDTH+15 : DESIGN_ID_WIDTH+0]  = a_vec[i];
      test_io_out[DESIGN_ID_WIDTH+31 : DESIGN_ID_WIDTH+16] = b_vec[i];
      test_io_out[DESIGN_ID_WIDTH+64] = 1'b1;

      repeat (LATENCY) @(posedge clock);
      #1ns;

      sa       = {{16{a_vec[i][15]}}, a_vec[i]};
      sb       = {{16{b_vec[i][15]}}, b_vec[i]};
      expected = sa * sb;

      if (user_io[DESIGN_ID_WIDTH+65] !== 1'b1)
        $fatal(1, "case %0d: valid_o did not assert at user_io[72]", i);
      if ($signed(user_io[DESIGN_ID_WIDTH+63 : DESIGN_ID_WIDTH+32]) !== expected)
        $fatal(1, "case %0d: got %0d, expected %0d",
               i, $signed(user_io[DESIGN_ID_WIDTH+63 : DESIGN_ID_WIDTH+32]), expected);
      $display("case %0d: %0d * %0d = %0d  OK", i, sa, sb, expected);
    end

    $display("MULTIPLIER FRAME TEST PASS");
    $finish;
  end

endmodule
