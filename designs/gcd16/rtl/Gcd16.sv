// Replace the example behavior while preserving the five-port frame contract.

// ============================================================================
// GCD：16 位无符号最大公约数，更相减损法
//
// 每轮比较当前的 a 和 b，较大的数减去较小的数；两数相等时即为最大公约数。
// 这种实现每拍完成一次减法，但最坏情况下需要约 65534 拍（例如 65535 和 1）。
//
// Payload 分配（与 frame 契约一致，66 位正好填满）：
//   a       = io_in[15:0]
//   b       = io_in[31:16]
//   valid_i = io_in[64]
//   gcd     = io_out[15:0]
//   valid_o = io_out[65]
//
// 注意：gcd 输出区与 a 输入区同位于 [15:0]。为避免 Frame 集成测试中二者
// 争用同一物理引脚，gcd 区的输出使能只在 valid_o（DONE）时打开；同时结果
// 统一在采样之后至少一拍输出，给测试环境留出释放 a 引脚的时间。
// ============================================================================

module Gcd16 #(
  parameter int IO_WIDTH = 66
) (
  input  logic                clock,
  input  logic                reset,
  input  logic [IO_WIDTH-1:0] io_in,
  output logic [IO_WIDTH-1:0] io_out,
  output logic [IO_WIDTH-1:0] io_oe
);

  // ---- Payload ----
  wire [15:0] a       = io_in[15:0];
  wire [15:0] b       = io_in[31:16];
  wire        valid_i = io_in[64];

  //------------------------------------------------------------------------
  // 状态机
  //   IDLE    : 采样 a/b/valid_i
  //   START   : 用已寄存的 ra/rb 判断是否直接出结果（a==0 或 b==0）
  //   SUB_RUN : 更相减损法，每拍让较大的数减去较小的数
  //   DONE    : 输出 gcd 一拍
  //------------------------------------------------------------------------
  localparam [2:0] IDLE    = 3'd0,
                   START   = 3'd1,
                   SUB_RUN = 3'd2,
                   DONE    = 3'd3;

  reg [2:0]  state;
  reg [15:0] ra;         // 被除数 / 当前的 a
  reg [15:0] rb;         // 除数   / 当前的 b
  reg [15:0] gcd_reg;    // 结果

  wire valid_o = (state == DONE);

  // ---- IO 输出使能 ----
  //   bit 65        : valid_o，始终使能（非 DONE 时输出 0）
  //   bit 64        : valid_i 输入，不驱动
  //   bits [63:16]  : 保留，不驱动
  //   bits [15:0]   : gcd，仅在 valid_o（DONE）时驱动，避免与 a 输入争用
  assign io_oe = {1'b1, 1'b0, 48'd0, {16{valid_o}}};

  always_ff @(posedge clock) begin
    if (reset) begin
      state   <= IDLE;
      ra      <= 16'd0;
      rb      <= 16'd0;
      gcd_reg <= 16'd0;
    end else begin
      case (state)
        IDLE: begin
          if (valid_i) begin
            ra <= a;
            rb <= b;
            state <= START;
          end
        end
        START: begin
          if (ra == 16'd0 || rb == 16'd0) begin
            // gcd(a,0)=a、gcd(0,b)=b、gcd(0,0)=0
            gcd_reg <= (ra == 16'd0) ? rb : ra;
            state   <= DONE;
          end else begin
            state   <= SUB_RUN;
          end
        end
        SUB_RUN: begin
          if (ra == rb) begin
            gcd_reg <= ra;
            state   <= DONE;
          end else if (ra > rb) begin
            ra <= ra - rb;
          end else begin
            rb <= rb - ra;
          end
        end
        DONE: begin
          state <= IDLE;
        end
        default: state <= IDLE;
      endcase
    end
  end

  // ---- 输出：valid_o 在 [65]，gcd 在 [15:0] ----
  assign io_out = {valid_o, 1'b0, 48'd0, gcd_reg};

endmodule
