// 中文：这是“Frame 集成测试”。信号会经过外部 user_io、FrameTop 和你的设计。
//       它检查 design 编号能否被选中，以及输入和输出能否通过真实连接传递。
//       标有“通常保留”的选择流程不要随意修改；标有“按设计修改”的功能检查
//       应替换为你自己的输入和期望输出。
// English: This is the Frame integration test. Signals travel through user_io,
//          FrameTop, and your design. Keep the selection sequence unless the
//          frame protocol changes. Edit the marked functional checks.

module FrameGcd16Tb;

  // 由构建工具为本次 Frame 测试注入临时或正式 ID，用户无需填写。
  // The build tool injects a temporary or registered ID for this Frame test.
`ifndef FRAME_TEST_DESIGN_ID
  initial $error("FRAME_TEST_DESIGN_ID must be provided by the build tool");
`endif

  // 通常保留 / Usually keep:
  // FrameTop 一共有 73 根 user_io：低 7 位选择 design，其余 66 位连接设计 IO。
  // FrameTop has 73 user_io pins: the low 7 select a design; the other 66
  // connect to the selected design.
  localparam int IO_WIDTH = 73;
  localparam int DESIGN_ID_WIDTH = 7;
  localparam logic [DESIGN_ID_WIDTH-1:0] DESIGN_ID = `FRAME_TEST_DESIGN_ID;
  localparam time HALF_PERIOD = 5ns;

  // 按设计修改 / Edit for your design:
  // gcd 输出区与 a 输入区重叠（都在 [15:0]），因此请求被采样后必须释放 a 引脚，
  // 设计才好在 valid_o（DONE）时驱动 gcd；b 与 valid_i 不与输出重叠，可保持驱动。
  // payload 引脚换算：设计 io_*[n] <-> 外部 user_io[n+7]。
  localparam int PIN_A  = DESIGN_ID_WIDTH + 0;   // a       = io_in[15:0]
  localparam int PIN_B  = DESIGN_ID_WIDTH + 16;  // b       = io_in[31:16]
  localparam int PIN_VI = DESIGN_ID_WIDTH + 64;  // valid_i = io_in[64]
  localparam int PIN_VO = DESIGN_ID_WIDTH + 65;  // valid_o = io_out[65]

  // test_io_out 是测试环境准备驱动的值；test_io_oe 对应位为 1 时才真正驱动。
  // test_io_out holds values from the test; test_io_oe enables each driven pin.
  // 构建工具使用 reset、test_io_oe 和 dut 连接自动生成的争用检查，请勿重命名。
  // The generated contention monitor connects through reset, test_io_oe, and
  // dut, so keep these infrastructure names.
  logic clock = 1'b0;
  logic reset = 1'b1;
  logic [IO_WIDTH-1:0] test_io_out = '0;
  logic [IO_WIDTH-1:0] test_io_oe = '0;
  tri [IO_WIDTH-1:0] user_io;

  // 按设计修改 / Edit for your design:
  // 测试向量与期望结果。
  logic [15:0] a_vec [0:3];
  logic [15:0] b_vec [0:3];
  logic [15:0] g_exp [0:3];
  integer watchdog;

  always #(HALF_PERIOD) clock = ~clock;

  // 通常保留 / Usually keep:
  // 用三态连接模拟真实双向引脚。oe=0 时测试环境释放该引脚，允许设计驱动。
  // This tri-state connection models real bidirectional pins. With oe=0, the
  // test releases a pin so the design can drive it.
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
    // While reset=1, drive this design ID on user_io[6:0]. FrameTop reads the ID
    // during reset and does not switch designs when these pins change later.
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
    a_vec[0] = 16'd48;     b_vec[0] = 16'd18;    g_exp[0] = 16'd6;
    a_vec[1] = 16'd65535;  b_vec[1] = 16'd65535; g_exp[1] = 16'd65535;
    a_vec[2] = 16'd12345;  b_vec[2] = 16'd100;   g_exp[2] = 16'd5;
    a_vec[3] = 16'd0;      b_vec[3] = 16'd7;     g_exp[3] = 16'd7;

    for (int i = 0; i < 4; i++) begin
      @(negedge clock);
      test_io_out[PIN_A +: 16] = a_vec[i];
      test_io_out[PIN_B +: 16] = b_vec[i];
      test_io_out[PIN_VI] = 1'b1;
      test_io_oe[PIN_A +: 16] = '1;
      test_io_oe[PIN_B +: 16] = '1;
      test_io_oe[PIN_VI] = 1'b1;

      // 等待 IDLE 采样请求并离开 IDLE（进入 START），然后释放 valid_i 与 a 引脚，
      // 设计才好在 DONE 时驱动 gcd 而不会与测试产生争用。
      // 立即完成的 case（a==0 或 b==0）会在采样后的第二拍进入 DONE，因此必须在
      // 采样后第一个 negedge 就释放 a 引脚。
      // Let IDLE sample the request and move on, then release valid_i and the a
      // pins so the design can drive gcd in DONE without contention. Cases that
      // finish immediately (a==0 or b==0) reach DONE on the second cycle after
      // sampling, so the a pins must be released on the first negedge after it.
      repeat (1) @(posedge clock);
      @(negedge clock);
      test_io_out[PIN_VI] = 1'b0;
      test_io_oe[PIN_A +: 16] = '0;

      // 等待结果（带超时保护）。
      // Wait for the result with a timeout guard.
      watchdog = 0;
      while (user_io[PIN_VO] !== 1'b1) begin
        @(posedge clock);
        #1;  // 偏离时钟沿，等 NBA 提交后再采样
        watchdog = watchdog + 1;
        if (watchdog > 2000)
          $fatal(1, "case %0d: valid_o timeout", i);
      end
      #1ns;
      if (user_io[PIN_A +: 16] !== g_exp[i])
        $fatal(1, "case %0d: gcd got %0d, expected %0d",
               i, user_io[PIN_A +: 16], g_exp[i]);
      $display("case %0d: gcd(%0d, %0d) = %0d  OK", i, a_vec[i], b_vec[i], g_exp[i]);

      // 等待设计回到 IDLE（valid_o 拉低）。
      // Wait for the design to return to IDLE.
      watchdog = 0;
      while (user_io[PIN_VO] !== 1'b0) begin
        @(posedge clock);
        #1;  // 偏离时钟沿，等 NBA 提交后再采样
        watchdog = watchdog + 1;
        if (watchdog > 2000)
          $fatal(1, "case %0d: valid_o did not deassert", i);
      end
    end

    $display("GCD16 FRAME TEST PASS");
    $finish;
  end

endmodule
