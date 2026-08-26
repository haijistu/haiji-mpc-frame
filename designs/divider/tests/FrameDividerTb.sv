// 中文：这是“Frame 集成测试”。信号会经过外部 user_io、FrameTop 和你的设计。
//       它检查 design 编号能否被选中，以及输入和输出能否通过真实连接传递。
//       标有“通常保留”的选择流程不要随意修改；标有“按设计修改”的功能检查
//       应替换为你自己的输入和期望输出。
// English: This is the Frame integration test. Signals travel through user_io,
//          FrameTop, and your design. Keep the selection sequence unless the
//          frame protocol changes. Edit the marked functional checks.

module FrameDividerTb;

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
  // 状态机延迟：1 拍载入（IDLE）+ 16 拍迭代（COMPUTE）+ 1 拍 DONE。
  // 测试用 valid_o 握手等待完成，case 之间等待 valid_o 拉低回到 IDLE。

  // test_io_out 是测试环境准备驱动的值；test_io_oe 对应位为 1 时才真正驱动。
  // test_io_out holds values from the test; test_io_oe enables each driven pin.
  // 构建工具使用 reset、test_io_oe 和 dut 连接自动生成的争用检查，请勿重命名。
  logic clock = 1'b0;
  logic reset = 1'b1;
  logic [IO_WIDTH-1:0] test_io_out = '0;
  logic [IO_WIDTH-1:0] test_io_oe = '0;
  tri [IO_WIDTH-1:0] user_io;

  // 按设计修改 / Edit for your design:
  // 测试向量与期望结果。
  logic [15:0] a_vec [0:3];
  logic [15:0] b_vec [0:3];
  logic [15:0] q_exp [0:3];
  logic [15:0] r_exp [0:3];

  always #(HALF_PERIOD) clock = ~clock;

  // 通常保留 / Usually keep:
  // 用三态连接模拟真实双向引脚。oe=0 时测试环境释放该引脚，允许设计驱动。
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
    // 在 reset=1 期间，用 user_io[6:0] 驱动本设计编号。FrameTop 只在复位期间
    // 读取编号，复位释放后不会因为这些引脚变化而切换设计。
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
    // 输入：dividend = io_in[15:0]  -> user_io[22:7]
    //       divisor  = io_in[31:16] -> user_io[38:23]
    //       valid_i  = io_in[64]    -> user_io[71]
    // 输出：quotient = io_out[63:48] -> user_io[70:55]
    //       reminder = io_out[47:32] -> user_io[54:39]
    //       valid_o  = io_out[65]   -> user_io[72]
    test_io_oe[DESIGN_ID_WIDTH+15 : DESIGN_ID_WIDTH+0]  = '1;  // dividend
    test_io_oe[DESIGN_ID_WIDTH+31 : DESIGN_ID_WIDTH+16] = '1;  // divisor
    test_io_oe[DESIGN_ID_WIDTH+64] = 1'b1;                     // valid_i

    a_vec[0] = 16'd100;    b_vec[0] = 16'd7;     q_exp[0] = 16'd14;     r_exp[0] = 16'd2;
    a_vec[1] = 16'd65535;  b_vec[1] = 16'd65535; q_exp[1] = 16'd1;      r_exp[1] = 16'd0;
    a_vec[2] = 16'd12345;  b_vec[2] = 16'd0;     q_exp[2] = 16'hFFFF;   r_exp[2] = 16'd12345; // 除零
    a_vec[3] = 16'd50000;  b_vec[3] = 16'd10;    q_exp[3] = 16'd5000;   r_exp[3] = 16'd0;

    for (int i = 0; i < 4; i++) begin
      @(negedge clock);
      test_io_out[DESIGN_ID_WIDTH+15 : DESIGN_ID_WIDTH+0]  = a_vec[i];
      test_io_out[DESIGN_ID_WIDTH+31 : DESIGN_ID_WIDTH+16] = b_vec[i];
      test_io_out[DESIGN_ID_WIDTH+64] = 1'b1;

      repeat (17) @(posedge clock);
      #1ns;

      if (user_io[DESIGN_ID_WIDTH+65] !== 1'b1)
        $fatal(1, "case %0d: valid_o did not assert at user_io[72]", i);
      if (user_io[DESIGN_ID_WIDTH+63 : DESIGN_ID_WIDTH+48] !== q_exp[i])
        $fatal(1, "case %0d: quotient got %0d, expected %0d",
               i, user_io[DESIGN_ID_WIDTH+63 : DESIGN_ID_WIDTH+48], q_exp[i]);
      if (user_io[DESIGN_ID_WIDTH+47 : DESIGN_ID_WIDTH+32] !== r_exp[i])
        $fatal(1, "case %0d: reminder got %0d, expected %0d",
               i, user_io[DESIGN_ID_WIDTH+47 : DESIGN_ID_WIDTH+32], r_exp[i]);
      $display("case %0d: %0d / %0d = %0d r %0d  OK", i, a_vec[i], b_vec[i], q_exp[i], r_exp[i]);

      // 释放请求并等设计回到 IDLE（valid_o 拉低）
      @(negedge clock);
      test_io_out[DESIGN_ID_WIDTH+64] = 1'b0;
      wait (user_io[DESIGN_ID_WIDTH+65] === 1'b0);
    end

    $display("DIVIDER FRAME TEST PASS");
    $finish;
  end

endmodule
