module vga_top_apb(
  input         clock,
  input         reset,
  input  [31:0] in_paddr,
  input         in_psel,
  input         in_penable,
  input  [2:0]  in_pprot,
  input         in_pwrite,
  input  [31:0] in_pwdata,
  input  [3:0]  in_pstrb,
  output        in_pready,
  output [31:0] in_prdata,
  output        in_pslverr,

  output [7:0]  vga_r,
  output [7:0]  vga_g,
  output [7:0]  vga_b,
  output        vga_hsync,
  output        vga_vsync,
  output        vga_valid
);

localparam S_IDLE = 0, S_ACCESS = 1;

reg state_r;
reg [31:0] addr_q;
reg [31:0] wdata_q;

wire load_w, fin_w;
wire isWr;

wire [9:0] w_h_addr, w_v_addr;

wire [9:0] vga_h_addr, vga_v_addr;
wire [23:0] vga_data;

// State Machine
always @(posedge clock or posedge reset) begin
  if (reset) state_r <= S_IDLE;
  else if (fin_w) state_r <= S_IDLE;
  else if (in_psel) state_r <= S_ACCESS;
end

// APB Info Load
always @(posedge clock or posedge reset) begin
  if (reset) addr_q <= 0;
  else if (load_w) addr_q <= in_paddr;
  else if (fin_w) addr_q <= 0;

  if (reset) wdata_q <= 0;
  else if (load_w & isWr) wdata_q <= in_pwdata;
  else if (fin_w) wdata_q <= 0;
end

vga_ctrl ctrl(
  .pclk(clock),
  .reset(reset),
  .vga_data(vga_data),
  // .vga_data({4'd0, vga_v_addr, vga_h_addr}),
  .h_addr(vga_h_addr),
  .v_addr(vga_v_addr),
  .hsync(vga_hsync),
  .vsync(vga_vsync),
  .valid(vga_valid),
  .vga_r(vga_r),
  .vga_g(vga_g),
  .vga_b(vga_b)
);

vga_sram sram(
  .clk(clock),
  .wr(fin_w & isWr),
  .w_h_addr(w_h_addr),
  .w_v_addr(w_v_addr),
  .w_data(wdata_q[23:0]),
  .r_h_addr(vga_h_addr),
  .r_v_addr(vga_v_addr),
  .r_data(vga_data)
);

// Control Signals
assign load_w = (state_r == S_IDLE) & in_psel;
assign fin_w  = (state_r == S_ACCESS) & in_penable;
assign isWr = in_pwrite;

// VGA Write Signals
// 640x480=0x4b000
wire [18:0] w_valid_addr = addr_q[20:2] & 19'h7ffff;
assign w_h_addr = {w_valid_addr % 19'd640}[9:0];
assign w_v_addr = {w_valid_addr / 19'd640}[9:0];

// Output
assign in_pready = fin_w;
assign in_prdata = 0;
assign in_pslverr = 0;

endmodule

// Copy from NJU CS exp
module vga_ctrl(
    input           pclk,     //25MHz时钟
    input           reset,    //置位
    input  [23:0]   vga_data, //上层模块提供的VGA颜色数据
    output [9:0]    h_addr,   //提供给上层模块的当前扫描像素点坐标
    output [9:0]    v_addr,
    output          hsync,    //行同步和列同步信号
    output          vsync,
    output          valid,    //消隐信号
    output [7:0]    vga_r,    //红绿蓝颜色信号
    output [7:0]    vga_g,
    output [7:0]    vga_b
    );

  //640x480分辨率下的VGA参数设置
  parameter    h_frontporch = 96;
  parameter    h_active = 144;
  parameter    h_backporch = 784;
  parameter    h_total = 800;

  parameter    v_frontporch = 2;
  parameter    v_active = 35;
  parameter    v_backporch = 515;
  parameter    v_total = 525;

  //像素计数值
  reg [9:0]    x_cnt;
  reg [9:0]    y_cnt;
  wire         h_valid;
  wire         v_valid;

  always @(posedge reset or posedge pclk) //行像素计数
      if (reset == 1'b1)
        x_cnt <= 1;
      else
      begin
        if (x_cnt == h_total)
            x_cnt <= 1;
        else
            x_cnt <= x_cnt + 10'd1;
      end

  always @(posedge pclk)  //列像素计数
      if (reset == 1'b1)
        y_cnt <= 1;
      else
      begin
        if (y_cnt == v_total & x_cnt == h_total)
            y_cnt <= 1;
        else if (x_cnt == h_total)
            y_cnt <= y_cnt + 10'd1;
      end
  //生成同步信号
  assign hsync = (x_cnt > h_frontporch);
  assign vsync = (y_cnt > v_frontporch);
  //生成消隐信号
  assign h_valid = (x_cnt > h_active) & (x_cnt <= h_backporch);
  assign v_valid = (y_cnt > v_active) & (y_cnt <= v_backporch);
  assign valid = h_valid & v_valid;
  //计算当前有效像素坐标
  assign h_addr = h_valid ? (x_cnt - 10'd145) : {10{1'b0}};
  assign v_addr = v_valid ? (y_cnt - 10'd36) : {10{1'b0}};
  //设置输出的颜色值
  assign vga_r = vga_data[23:16];
  assign vga_g = vga_data[15:8];
  assign vga_b = vga_data[7:0];
endmodule

module vga_sram(
  input clk,
  input wr,
  input [9:0] w_h_addr, w_v_addr,
  input [23:0] w_data,
  input [9:0] r_h_addr, r_v_addr,
  output [23:0] r_data
);

// 640x480
reg [23:0] ram[640][480];

always @(posedge clk) begin
  if (wr) ram[w_h_addr][w_v_addr[8:0]] <= w_data;
end

assign r_data = ram[r_h_addr][r_v_addr[8:0]];

endmodule
