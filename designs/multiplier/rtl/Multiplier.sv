// Replace the example behavior while preserving the five-port frame contract.

// ============================================================================
// 乘法器：Booth4（Radix-4）+ 3-2/4-2 压缩树，有符号 16 位 x 有符号 16 位
//
// Payload 分配:
//   a       = io_in[15:0]
//   b       = io_in[31:16]
//   valid_i = io_in[64]
//   result  = io_out[63:32]
//   valid_o = io_out[65]
// ============================================================================

module Multiplier #(
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

  // ---- IO 输出使能：result 位于 [63:32]，valid_o 位于 [65]；
  assign io_oe = {1'b1, 1'b0, {32{1'b1}}, 32'd0};

  //---------------------------------------------------------------------------
  // Booth 扫描窗口：b_ext = {b, 0}，
  //   窗口 i 的 3 位为 b_ext[2*i+2 -: 3] = {b[2i+1], b[2i], b[2i-1]}，b[-1]=0
  //---------------------------------------------------------------------------
  wire [16:0] b_ext = {b, 1'b0};

  wire [16:0] mult_arr [0:7];   // 17 位倍数（负倍数取反形式）
  wire        neg_arr  [0:7];   // 负倍数标志（需要在 bit 2i 补偿 +1）
  wire [31:0] pp       [0:7];   // 32 位部分积（已符号扩展并移位）

  genvar i;
  generate
    for (i = 0; i < 8; i = i + 1) begin : GEN_PP
      booth_pp_gen u_pp (
        .x    (a),
        .code (b_ext[2*i+2 -: 3]),
        .mult (mult_arr[i]),
        .neg  (neg_arr[i])
      );
      // 17 位倍数符号扩展到 32 位，再左移 2*i
      assign pp[i] = {{15{mult_arr[i][16]}}, mult_arr[i]} << (2*i);
    end
  endgenerate

  //---------------------------------------------------------------------------
  // 修正项：负倍数的 +1 补偿位（位于 bit 2*i）
  //---------------------------------------------------------------------------
  logic [31:0] correction;
  always_comb begin
    correction = 32'd0;
    for (int k = 0; k < 8; k++)
      correction[2*k] = neg_arr[k];
  end

  // ==========================================================================
  // 流水线：9 输入 → 5 → 3 → 1（共 4 级寄存器 R1..R4）
  //   R1    : Booth 部分积 + 修正项（9 个操作数）
  //   4-2×2 (9→5)  → R2
  //   4-2    (5→3)  → R3
  //   3-2 (3→2) + CPA (2→1) → R4（result / valid_o；R3/R4 合并为末级）
  // ==========================================================================

  // ---- R1 ----
  logic [31:0] r1_op [0:8];
  logic        r1_valid;
  always_ff @(posedge clock or posedge reset) begin
    if (reset) begin
      r1_valid <= 1'b0;
      for (int k = 0; k < 9; k++) r1_op[k] <= 32'd0;
    end else begin
      r1_valid <= valid_i;
      for (int k = 0; k < 8; k++) r1_op[k] <= pp[k];
      r1_op[8] <= correction;
    end
  end

  // ---- 压缩级 1：9 → 5（两个 4-2 压缩器，余 1 个直通）----
  wire [31:0] l1_op [0:4];
  compressor4_2 u_c42_0 (
    .a(r1_op[0]), .b(r1_op[1]), .c(r1_op[2]), .d(r1_op[3]),
    .sum(l1_op[0]), .carry(l1_op[1])
  );
  compressor4_2 u_c42_1 (
    .a(r1_op[4]), .b(r1_op[5]), .c(r1_op[6]), .d(r1_op[7]),
    .sum(l1_op[2]), .carry(l1_op[3])
  );
  assign l1_op[4] = r1_op[8];

  // ---- R2：5 个操作数 ----
  logic [31:0] r2_op [0:4];
  logic        r2_valid;
  always_ff @(posedge clock or posedge reset) begin
    if (reset) begin
      r2_valid <= 1'b0;
      for (int k = 0; k < 5; k++) r2_op[k] <= 32'd0;
    end else begin
      r2_valid <= r1_valid;
      for (int k = 0; k < 5; k++) r2_op[k] <= l1_op[k];
    end
  end

  // ---- 压缩级 2：5 → 3（一个 4-2 压缩器，余 1 个直通）----
  wire [31:0] l2_op [0:2];
  compressor4_2 u_c42_2 (
    .a(r2_op[0]), .b(r2_op[1]), .c(r2_op[2]), .d(r2_op[3]),
    .sum(l2_op[0]), .carry(l2_op[1])
  );
  assign l2_op[2] = r2_op[4];

  // ---- R3：3 个操作数 ----
  logic [31:0] r3_op [0:2];
  logic        r3_valid;
  always_ff @(posedge clock or posedge reset) begin
    if (reset) begin
      r3_valid <= 1'b0;
      for (int k = 0; k < 3; k++) r3_op[k] <= 32'd0;
    end else begin
      r3_valid <= r2_valid;
      for (int k = 0; k < 3; k++) r3_op[k] <= l2_op[k];
    end
  end

  // ---- 压缩级 3：3 → 2（一个 3-2 压缩器）----
  wire [31:0] l3_op [0:1];
  csa3_2 u_csa_final (
    .a(r3_op[0]), .b(r3_op[1]), .c(r3_op[2]),
    .sum(l3_op[0]), .carry(l3_op[1])
  );

  wire [31:0] sum_final = l3_op[0] + l3_op[1];

  // ---- R4 ----
  logic [31:0] result;
  logic        valid_o;
  always_ff @(posedge clock or posedge reset) begin
    if (reset) begin
      result  <= 32'd0;
      valid_o <= 1'b0;
    end else begin
      result  <= sum_final;
      valid_o <= r3_valid;
    end
  end

  // ---- 输出 ----
  assign io_out = {valid_o, 1'b0, result, 32'd0};

endmodule

// ============================================================================
// 3-2 压缩器：3 个 W 位操作数 → 1 个 W 位和 + 1 个 W 位进位
// ============================================================================
module csa3_2 #(
  parameter int W = 32
) (
  input  logic [W-1:0] a,
  input  logic [W-1:0] b,
  input  logic [W-1:0] c,
  output logic [W-1:0] sum,
  output logic [W-1:0] carry
);
  logic [W-1:0] cout_bits;

  wire [W-1:0] ab = a ^ b;
  assign sum = ab ^ c;
  assign cout_bits = (a & b) | (c & ab);

  // carry 左移 1 位（权重 +1），最高位进位丢弃
  assign carry = {cout_bits[W-2:0], 1'b0};
endmodule

// ============================================================================
// 4-2 压缩器：4 个 W 位操作数 → 1 个 W 位和 + 1 个 W 位进位
// 满足 a + b + c + d = sum + 2 * carry（carry 权重 +1）
// ============================================================================
module compressor4_2 #(
  parameter int W = 32
) (
  input  logic [W-1:0] a, b, c, d,
  output logic [W-1:0] sum,
  output logic [W-1:0] carry
);
  // 第一级 3-2：复用 a^b
  wire [W-1:0] ab  = a ^ b;
  wire [W-1:0] s1  = ab ^ c;
  wire [W-1:0] c1  = (a & b) | (c & ab);     // majority(a,b,c)
  wire [W-1:0] cin = {c1[W-2:0], 1'b0};

  // 第二级 3-2：复用 s1^d
  wire [W-1:0] s1d = s1 ^ d;
  wire [W-1:0] s2  = s1d ^ cin;
  wire [W-1:0] c2  = (s1 & d) | (cin & s1d); // majority(s1,d,cin)

  assign sum   = s2;
  assign carry = {c2[W-2:0], 1'b0};
endmodule

// ============================================================================
// Booth 部分积生成器：输出取反后的 17 位倍数 + 负倍数标志
// ============================================================================
module booth_pp_gen (
  input  logic [15:0] x,
  input  logic [2:0]  code,
  output logic [16:0] mult,
  output logic        neg
);
  wire [16:0] x_ext  = {x[15], x};   // +x，符号扩展到 17 位
  wire [16:0] x2_ext = {x, 1'b0};    // +2x

  always_comb begin
    neg = 1'b0;
    case (code)
      3'b000, 3'b111: mult = 17'd0;
      3'b001, 3'b010: mult = x_ext;                       // +1x
      3'b011:         mult = x2_ext;                      // +2x
      3'b101, 3'b110: begin mult = ~x_ext;  neg = 1'b1; end // -1x → 取反并标记补偿
      3'b100:         begin mult = ~x2_ext; neg = 1'b1; end // -2x → 取反并标记补偿
      default:        mult = 17'd0;
    endcase
  end
endmodule

