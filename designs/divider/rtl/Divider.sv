// Replace the example behavior while preserving the five-port frame contract.

// ============================================================================
// 除法器：16 位无符号除法，不恢复余数（non-restoring）迭代算法
//
// 参考 ysyx_26010007_divider 的实现方式，仅保留无符号除法路径。
//
// Payload 分配（与 frame 契约一致，66 位正好填满）：
//   dividend = io_in[15:0]
//   divisor  = io_in[31:16]
//   valid_i  = io_in[64]
//   quotient = io_out[63:48]
//   reminder = io_out[47:32]
//   valid_o  = io_out[65]
// ============================================================================

module Divider #(
  parameter int IO_WIDTH = 66
) (
  input  logic                clock,
  input  logic                reset,
  input  logic [IO_WIDTH-1:0] io_in,
  output logic [IO_WIDTH-1:0] io_out,
  output logic [IO_WIDTH-1:0] io_oe
);

  // ---- Payload ----
  wire [15:0] dividend = io_in[15:0];
  wire [15:0] divisor  = io_in[31:16];
  wire        valid_i  = io_in[64];

  // ---- IO 输出使能：quotient [63:48]、reminder [47:32]、valid_o [65] ----
  assign io_oe = {1'b1, 1'b0, 16'hFFFF, 16'hFFFF, 32'd0};

  //------------------------------------------------------------------------
  // 状态机 + 不恢复余数迭代（n = 16，A 需 n+2 = 18 位避免移位溢出）
  //------------------------------------------------------------------------
  localparam [1:0] IDLE    = 2'd0,
                   COMPUTE = 2'd1,
                   DONE    = 2'd2;

  reg [1:0]  state;
  reg [4:0]  cnt;
  reg [17:0] A;            // 部分余数
  reg [15:0] Q;            // 商
  reg [17:0] M;            // 除数（无符号扩展）
  reg [15:0] div_dividend; // 原始被除数（除零返回用）
  reg        div_zero_r;   // 除零标志
  reg [15:0] q_out;
  reg [15:0] r_out;
  wire       valid_o;

  // 一次不恢复余数迭代：{A,Q} 左移 1 位后，根据符号加减除数
  wire [17:0] A_shifted = {A[16:0], Q[15]};
  wire [17:0] A_next    = A_shifted[17] ? (A_shifted + M) : (A_shifted - M);
  wire [15:0] Q_next    = {Q[14:0], ~A_next[17]};

  // 末次校正：若余数为负，加回除数
  wire [17:0] A_final = A_next[17] ? (A_next + M) : A_next;

  // 无符号结果：商 = Q_next，余数 = A_final 低 16 位
  wire [15:0] quotient = Q_next;
  wire [15:0] reminder = A_final[15:0];

  // 除零：商 = 全 1，余数 = 被除数（与 RISC-V DIVU/REMU 语义一致）
  wire [15:0] q_res = div_zero_r ? 16'hFFFF     : quotient;
  wire [15:0] r_res = div_zero_r ? div_dividend : reminder;

  always @(posedge clock) begin
    if (reset) begin
      state        <= IDLE;
      cnt          <= 5'd0;
      A            <= 18'd0;
      Q            <= 16'd0;
      M            <= 18'd0;
      div_dividend <= 16'd0;
      div_zero_r   <= 1'b0;
      q_out        <= 16'd0;
      r_out        <= 16'd0;
    end else begin
      case (state)
        IDLE: begin
          if (valid_i) begin
            A            <= 18'd0;
            Q            <= dividend;
            M            <= {2'b00, divisor};
            cnt          <= 5'd0;
            div_dividend <= dividend;
            div_zero_r   <= (divisor == 16'd0);
            state        <= COMPUTE;
          end
        end
        COMPUTE: begin
          A   <= A_next;
          Q   <= Q_next;
          cnt <= cnt + 1'b1;
          if (cnt == 5'd15) begin
            q_out <= q_res;
            r_out <= r_res;
            state <= DONE;
          end
        end
        DONE: begin
          state <= IDLE;
        end
        default: state <= IDLE;
      endcase
    end
  end

  assign valid_o = (state == DONE);

  // ---- 输出 ----
  assign io_out = {valid_o, 1'b0, q_out, r_out, 32'd0};

endmodule


