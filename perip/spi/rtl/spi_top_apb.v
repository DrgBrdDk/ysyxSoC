// define this macro to enable fast behavior simulation
// for flash by skipping SPI transfers
// `define FAST_FLASH

module spi_top_apb #(
  parameter flash_addr_start = 32'h30000000,
  parameter flash_addr_end   = 32'h3fffffff,
  parameter spi_ss_num       = 8
) (
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

  output                  spi_sck,
  output [spi_ss_num-1:0] spi_ss,
  output                  spi_mosi,
  input                   spi_miso,
  output                  spi_irq_out
);

`ifdef FAST_FLASH

wire [31:0] data;
parameter invalid_cmd = 8'h0;
flash_cmd flash_cmd_i(
  .clock(clock),
  .valid(in_psel && !in_penable),
  .cmd(in_pwrite ? invalid_cmd : 8'h03),
  .addr({8'b0, in_paddr[23:2], 2'b0}),
  .data(data)
);
assign spi_sck    = 1'b0;
assign spi_ss     = 8'b0;
assign spi_mosi   = 1'b1;
assign spi_irq_out= 1'b0;
assign in_pslverr = 1'b0;
assign in_pready  = in_penable && in_psel && !in_pwrite;
assign in_prdata  = data[31:0];

`else

  wire is_xip;
  wire [4:0] xip_paddr;
  wire [32-1:0] xip_pwdata, xip_prdata;
  wire [3:0] xip_pstrb;
  wire xip_pwrite, xip_penable;
  wire xip_ack_o;

  wire [4:0] wb_adr_i;
  wire [32-1:0] wb_dat_i, wb_dat_o;
  wire [3:0] wb_sel_i;
  wire wb_we_i, wb_stb_i, wb_cyc_i;
  wire wb_ack_o;

  assign is_xip = in_psel
                  && ((32'h3000_0000 <= in_paddr)
                  && (in_paddr <= 32'h3fff_ffff));

  xip xip(
    .clock(clock),
    .reset(reset),
    .is_xip(is_xip),
    .in_paddr(in_paddr),
    .xip_paddr(xip_paddr),
    .xip_pwdata(xip_pwdata),
    .xip_pstrb(xip_pstrb),
    .xip_pwrite(xip_pwrite),
    .xip_penable(xip_penable),
    .xip_bsy(wb_dat_o[8]),  // bit-GO_BSY[8] of SPI Master
    .wb_ack_o(wb_ack_o),
    .xip_ack_o(xip_ack_o)
  );
  // flash read data are byte MSB first, for we need LSB first
  assign xip_prdata = {wb_dat_o[7:0], wb_dat_o[15:8], wb_dat_o[23:16], wb_dat_o[31:24]};
  // assign xip_prdata = wb_dat_o;

  assign wb_adr_i = is_xip ? xip_paddr : in_paddr[4:0];
  assign wb_dat_i = is_xip ? xip_pwdata : in_pwdata;
  assign wb_sel_i = is_xip ? xip_pstrb : in_pstrb;
  assign wb_we_i  = is_xip ? xip_pwrite : in_pwrite;
  assign wb_cyc_i = is_xip ? xip_penable : in_penable;

  assign in_pready = is_xip ? xip_ack_o : wb_ack_o;
  assign in_prdata = is_xip ? xip_prdata : wb_dat_o;

spi_top u0_spi_top (
  .wb_clk_i(clock),
  .wb_rst_i(reset),
  .wb_adr_i(wb_adr_i),
  .wb_dat_i(wb_dat_i),
  .wb_dat_o(wb_dat_o),
  .wb_sel_i(wb_sel_i),
  .wb_we_i (wb_we_i),
  .wb_stb_i(in_psel),
  .wb_cyc_i(wb_cyc_i),
  .wb_ack_o(wb_ack_o),
  .wb_err_o(in_pslverr),
  .wb_int_o(spi_irq_out),

  .ss_pad_o(spi_ss),
  .sclk_pad_o(spi_sck),
  .mosi_pad_o(spi_mosi),
  .miso_pad_i(spi_miso)
);

`endif // FAST_FLASH

endmodule
