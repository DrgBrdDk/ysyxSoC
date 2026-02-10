module gpio_top_apb(
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

  output reg [15:0] gpio_out,
  input      [15:0] gpio_in,
  output reg [7:0]  gpio_seg_0,
  output reg [7:0]  gpio_seg_1,
  output reg [7:0]  gpio_seg_2,
  output reg [7:0]  gpio_seg_3,
  output reg [7:0]  gpio_seg_4,
  output reg [7:0]  gpio_seg_5,
  output reg [7:0]  gpio_seg_6,
  output reg [7:0]  gpio_seg_7
);

localparam ADDR_LED = 32'h1000_2000;
localparam ADDR_SW  = 32'h1000_2004;
localparam ADDR_SEG = 32'h1000_2008;

localparam S_IDLE = 0, S_ACCESS = 1;

  reg state_r;
  reg [31:0] addr_q;
  reg [31:0] wdata_q, rdata_q;

  wire [7:0] segs [7:0];

  wire load_w, fin_w;
  wire isWr;

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
    else if (load_w &&  isWr) wdata_q <= in_pwdata;
    else if (fin_w) wdata_q <= 0;

    if (reset) rdata_q <= 0;
    else if (load_w && !isWr) rdata_q <= {16'd0, gpio_in};
    else if (fin_w) rdata_q <= 0;
  end

  // GPIO Drive
  always @(posedge clock or posedge reset) begin
    if (reset) begin
      gpio_out <= 0;
      gpio_seg_0 <= 0;
      gpio_seg_1 <= 0;
      gpio_seg_2 <= 0;
      gpio_seg_3 <= 0;
      gpio_seg_4 <= 0;
      gpio_seg_5 <= 0;
      gpio_seg_6 <= 0;
      gpio_seg_7 <= 0;
    end
    else if (fin_w && isWr)
      case (addr_q)
        ADDR_LED: gpio_out <= wdata_q[15:0];
        ADDR_SEG: begin
          gpio_seg_0 <= segs[0];
          gpio_seg_1 <= segs[1];
          gpio_seg_2 <= segs[2];
          gpio_seg_3 <= segs[3];
          gpio_seg_4 <= segs[4];
          gpio_seg_5 <= segs[5];
          gpio_seg_6 <= segs[6];
          gpio_seg_7 <= segs[7];
        end
        default: ;
      endcase
  end

  genvar i;
  generate
    for (i=0; i<8; i=i+1) begin
      seg u_seg(
        .i_dec(wdata_q[4*i+3:4*i]),
        .o_seg(segs[i])
      );
    end
  endgenerate

  // Control Signals
  assign load_w = state_r == S_IDLE && in_psel;
  assign fin_w = state_r == S_ACCESS && in_penable;

  assign isWr = in_pwrite;

  // Output
  assign in_pready = fin_w;
  assign in_prdata = addr_q == ADDR_SW ? rdata_q : 0;
  assign in_pslverr = 0;

endmodule

module seg(
  input  [3:0] i_dec,
  output [7:0] o_seg
);

  wire [7:0] segs [15:0];
  assign segs[0] = 8'b00000010;
  assign segs[1] = 8'b10011111;
  assign segs[2] = 8'b00100101;
  assign segs[3] = 8'b00001101;
  assign segs[4] = 8'b10011001;
  assign segs[5] = 8'b01001001;
  assign segs[6] = 8'b01000001;
  assign segs[7] = 8'b00011111;
  assign segs[8] = 8'b00000001;
  assign segs[9] = 8'b00001001;
  assign segs[10] = 8'b00010001;
  assign segs[11] = 8'b11000001;
  assign segs[12] = 8'b01100011;
  assign segs[13] = 8'b10000101;
  assign segs[14] = 8'b01100001;
  assign segs[15] = 8'b01110001;

  assign o_seg = segs[i_dec];

endmodule
