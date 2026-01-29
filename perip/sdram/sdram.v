`timescale 1ns/1ps

module sdram(
  input        clk,
  input        cke,
  input        cs,
  input        ras,
  input        cas,
  input        we,
  input [12:0] a,
  input [ 1:0] ba,
  input [ 1:0] dqm,
  inout [15:0] dq
);

  // TODO: 先实现 LOAD MODE, ACTIVATE, READ 命令, 再实现 WRITE 命令
  // TODO: 为简化实现, 仅支持 CAS Latency = 2

localparam SDRAM_BANK_W = 2;
localparam SDRAM_ROW_W  = 13;
localparam SDRAM_COL_W  = 9;
localparam SDRAM_BANKS  = 2 ** SDRAM_BANK_W;

localparam CMD_W             = 4;
localparam CMD_NOP           = 4'b0111;
localparam CMD_ACTIVE        = 4'b0011;
localparam CMD_READ          = 4'b0101;
localparam CMD_WRITE         = 4'b0100;
localparam CMD_TERMINATE     = 4'b0110;
localparam CMD_PRECHARGE     = 4'b0010;
localparam CMD_REFRESH       = 4'b0001;
localparam CMD_LOAD_MODE     = 4'b0000;

localparam ALL_BANKS         = 10;

localparam STATE_W           = 3;
localparam STATE_IDLE        = 3'd0;
localparam STATE_CAS         = 3'd1;
localparam STATE_READ0       = 3'd2;
localparam STATE_READ1       = 3'd3;
localparam STATE_WRITE       = 3'd4;

  assign dq = 16'bz;
  
  /* Reset */
  // CKE masks CLK, regard as rst_n signal
  wire reset = ~cke;

  /* Mode Register */
  reg [12:0] Mode;
  wire [2:0] cas_w = Mode[6:4];
  wire [2:0] bl_w  = {4'd2 ** Mode[2:0] - 1}[2:0];

  /* Command */
  wire [CMD_W-1:0] cmd;
  reg rd_pend_q;

  /* Row Buffers */
  reg [SDRAM_BANKS-1:0] bank_open_q;
  reg [SDRAM_ROW_W-1:0] row_active_q[SDRAM_BANKS];

  /* Address */
  reg [SDRAM_BANK_W-1:0]  bank_q, bank_pend_q;
  reg [SDRAM_COL_W-1:0]   col_q, col_pend_q;
  wire [SDRAM_BANK_W-1:0] bank_w;
  wire [SDRAM_ROW_W-1:0]  row_w;
  wire [SDRAM_COL_W-1:0]  col_w;

  /* Counters */
  reg [2:0] burst_cnt;
  wire no_burst_w = bl_w == 0;
  wire burst_toend_w = burst_cnt == (bl_w - 1);
  wire burst_end_w = burst_cnt == bl_w;

  /* State Machine */
  reg [STATE_W-1:0] state_r;
  reg [STATE_W-1:0] state_next_w;

  // CS# indicates a valid command is asserted
  assign cmd = {cs, ras, cas, we};

  // State Machine
  always @(posedge clk) begin
    if (reset) state_r <= STATE_IDLE;
    else state_r <= state_next_w;

    if (reset) rd_pend_q <= 0;
    else rd_pend_q <= state_r == STATE_READ1 ? (rd_pend_q && cmd == CMD_READ) :
                      state_r != STATE_IDLE ? cmd == CMD_READ : 0;
  end

  always @(*) begin
    state_next_w = state_r;

    case (state_r)
      STATE_IDLE: begin
        if (cmd == CMD_WRITE) state_next_w = no_burst_w ? STATE_IDLE : STATE_WRITE;
        else if (cmd == CMD_READ) state_next_w = STATE_CAS;
      end

      STATE_CAS: state_next_w = no_burst_w ? STATE_READ1 : STATE_READ0;
      STATE_READ0: state_next_w = burst_toend_w ? STATE_READ1 : STATE_READ0;
      STATE_READ1: begin
        if (rd_pend_q) state_next_w = no_burst_w ? STATE_READ1 : STATE_READ0;
        else if (cmd == CMD_READ) state_next_w = STATE_CAS;  // no rd_pend
        else state_next_w = STATE_IDLE;
      end

      STATE_WRITE: state_next_w = burst_end_w ? STATE_IDLE : STATE_WRITE;

      default: ;
    endcase
  end

  // Mode register can only be issued when all banks are idle
  always @(posedge clk) begin
    if (reset) Mode <= 0;
    else if (cmd == CMD_LOAD_MODE && state_r == STATE_IDLE) Mode <= a;
  end

  // Row active
  always @(posedge clk) begin
    if (reset) begin
      bank_open_q  <= 0;
      for (integer idx=0;idx<SDRAM_BANK_W;idx=idx+1)
        row_active_q[idx] <= 0;
    end
    else if (cmd == CMD_ACTIVE) begin
      bank_open_q[ba] <= 1;
      row_active_q[ba] <= a;
    end
    else if (cmd == CMD_PRECHARGE) begin
      if (a[ALL_BANKS]) begin
        bank_open_q <= 0;
        for (integer idx=0;idx<SDRAM_BANK_W;idx=idx+1)
          row_active_q[idx] <= 0;
      end
      else begin
        bank_open_q[ba] <= 0;
        row_active_q[ba] <= 0;
      end
    end
  end

  // Address
  always @(posedge clk) begin
    if (reset) begin
      bank_q <= 0;
      bank_pend_q <= 0;
      col_q  <= 0;
      col_pend_q <= 0;
    end
    else if (cmd == CMD_READ) begin
      if (state_r != STATE_IDLE) begin
        bank_pend_q <= ba;
        col_pend_q  <= a[8:0];
      end

      if (rd_pend_q) begin
        bank_q <= bank_pend_q;
        col_q <= col_pend_q;
      end
      else begin  // assume READ/WRITE won't overlap current burst
        bank_q <= ba;
        col_q <= a[8:0];
      end
    end
    else if (cmd == CMD_WRITE) begin
      bank_q <= ba;
      col_q <= a[8:0];
    end
  end
  // only WRITE apply immediately, can't use reg for the first burst
  assign bank_w = cmd == CMD_WRITE ? ba : bank_q;
  assign row_w = row_active_q[bank_w];

  // READ data is driven 1 cycle before CAS Latency
  // BUT WRITE data is asserted with command at the same time
  // each unit is 16-bit based
  assign col_w = (cmd == CMD_WRITE ? a[8:0] : col_q) + {{(SDRAM_COL_W-3){1'b0}}, burst_cnt};

  // Burst count
  always @(posedge clk) begin
    if (reset) burst_cnt <= 0;
    else if (burst_end_w) burst_cnt <= 0;
    else if (cmd == CMD_WRITE && state_r == STATE_IDLE) burst_cnt <= 1;
    else if (state_r == STATE_READ0 || state_r == STATE_READ1) burst_cnt <= burst_cnt + 1;
  end

  // assume every row are active

  // Data
  wire s_isWr;
  wire s_rd_valid_w, s_wr_valid_w;
  wire s_valid_w;
  wire [31:0] wdata_w, rdata_w;

  sdram_cmd sdram_cmd_i(
    .clock(clk),
    .valid(s_valid_w),
    .isWr(s_isWr),
    .addr(32'ha000_0000 + {7'd0, bank_w, row_w, col_w, 1'b0}),
    .wdata(wdata_w),
    .wmask({2'd0, ~dqm}),
    .rdata(rdata_w)
  );

  assign s_isWr = cmd == CMD_WRITE || state_r == STATE_WRITE;
  assign s_wr_valid_w = cmd == CMD_WRITE || state_r == STATE_WRITE;
  // driven READ at CAS end for random or consecutive burst
  assign s_rd_valid_w = state_r == STATE_CAS || (state_r == STATE_READ1 && rd_pend_q);
  assign s_valid_w = bank_open_q[bank_w] & (s_isWr ? s_wr_valid_w : s_rd_valid_w);

  wire onRead = state_r == STATE_READ0 || state_r == STATE_READ1;
  assign wdata_w = onRead ? 32'd0 : {16'd0, dq};
  // sdram_cmd is 32-bit aligned
  wire [15:0] rdq_align_w = col_w[0] ? rdata_w[31:16] : rdata_w[15:0];
  assign dq = onRead ? rdq_align_w : 16'bz;

endmodule

import "DPI-C" function void sdram_read(input int addr, output int data);
import "DPI-C" function void sdram_write(input int addr, input int data, input int wmask);

module sdram_cmd(
  input wire clock,
  input wire valid,
  input wire isWr,
  input wire [31:0] addr,
  input wire [31:0] wdata,
  input wire [3:0] wmask,
  output reg [31:0] rdata
);
  always @(posedge clock) begin
    if (valid)
      if (isWr)
        sdram_write(addr, wdata, {28'd0, wmask});
      else
        sdram_read(addr, rdata);
  end
endmodule
