module apb_delayer(
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

  output [31:0] out_paddr,
  output        out_psel,
  output        out_penable,
  output [2:0]  out_pprot,
  output        out_pwrite,
  output [31:0] out_pwdata,
  output [3:0]  out_pstrb,
  input         out_pready,
  input  [31:0] out_prdata,
  input         out_pslverr
);

localparam SDRAM_LEFT  = 32'ha000_0000;
localparam SDRAM_RIGHT = 32'hbfff_ffff;

// TODO: 仅用于 APB 接口的 SDRAM
localparam f_cpu = 64'd840;
localparam f_dev = 64'd100;
localparam amp   = 64'd7;
localparam ratio = (f_cpu << amp) / f_dev;

  initial $display("apb delayer ratio: %f", real'(f_cpu) / real'(f_dev));

  // paddr, pwrite will keep steady during APB transfer
  wire in_range = (SDRAM_LEFT <= in_paddr && in_paddr <= SDRAM_RIGHT);

  // TODO: 我错了, 还是状态机香啊, 这个留着引以为戒
  reg [63:0] access, cnt;
  reg access_on, delay_on;

  wire [63:0] acc_amp = access * ratio;
  wire [63:0] delay   = acc_amp >> amp;

  wire a_start = in_range & in_psel & ~in_penable;
  wire a_stop  = in_range & in_penable & out_pready;
  wire d_start = in_range & a_stop;
  wire d_stop  = in_range & ((a_stop | delay_on) & cnt == delay);

  // make device inputs to default when delaying
  wire        psel    = in_range ? (delay_on ? 0 : in_psel) : in_psel;
  wire        penable = in_range ? (delay_on ? 0 : in_penable) : in_penable;

  // stage device outputs when delaying
  reg  [31:0] staged_prdata;
  reg         staged_pslverr;
  wire [31:0] d_prdata  = a_stop ? out_prdata : staged_prdata;
  wire        d_pslverr = a_stop ? out_pslverr : staged_pslverr;

  wire        pready  = in_range ? d_stop : out_pready;
  wire [31:0] prdata  = in_range ? (d_stop ? d_prdata : 32'd0) : out_prdata;
  wire        pslverr = in_range ? (d_stop ? d_pslverr : 1'd0) : out_pslverr;

  // ordinary APB device access
  always @(posedge clock) begin
    if (reset) access_on <= 0;
    else if (a_stop | delay_on) access_on <= 0;
    else if (a_start) access_on <= 1;
  end

  always @(posedge clock) begin
    if (reset) access <= 0;
    else if (a_stop | delay_on) access <= access;
    else if (access_on) access <= access + 1;
    else if (a_start) access <= 2;
  end

  // extended delayed response
  always @(posedge clock) begin
    if (reset) delay_on <= 0;
    else if (d_stop) delay_on <= 0;
    else if (d_start) delay_on <= 1;
  end

  always @(posedge clock) begin
    if (reset) cnt <= 0;
    else if (d_stop) cnt <= cnt;
    else if (access_on | delay_on) cnt <= cnt + 1;
    else if (a_start) cnt <= 2;
  end

  // stage device outputs when delaying
  always @(posedge clock) begin
    if (reset) begin
      staged_prdata  <= 0;
      staged_pslverr <= 0;
    end
    else if (a_stop) begin
      staged_prdata  <= out_prdata;
      staged_pslverr <= out_pslverr;
    end
  end

  assign out_paddr   = in_paddr;
  assign out_psel    = psel;
  assign out_penable = penable;
  assign out_pprot   = in_pprot;
  assign out_pwrite  = in_pwrite;
  assign out_pwdata  = in_pwdata;
  assign out_pstrb   = in_pstrb;
  assign in_pready   = pready;
  assign in_prdata   = prdata;
  assign in_pslverr  = pslverr;

  // assign out_paddr   = in_paddr;
  // assign out_psel    = in_psel;
  // assign out_penable = in_penable;
  // assign out_pprot   = in_pprot;
  // assign out_pwrite  = in_pwrite;
  // assign out_pwdata  = in_pwdata;
  // assign out_pstrb   = in_pstrb;
  // assign in_pready   = out_pready;
  // assign in_prdata   = out_prdata;
  // assign in_pslverr  = out_pslverr;

endmodule
