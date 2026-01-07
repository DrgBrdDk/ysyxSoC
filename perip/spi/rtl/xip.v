module xip (
    clock,
    reset,
    is_xip,
    in_paddr,
    xip_paddr,
    xip_pwdata,
    xip_pstrb,
    xip_pwrite,
    xip_penable,
    xip_bsy,
    wb_ack_o,
    xip_ack_o
);

  localparam XIP_S0_IDLE = 3'd0;
  localparam XIP_S1_TX1 = 3'd1;
  localparam XIP_S2_DIV = 3'd2;
  localparam XIP_S3_SS = 3'd3;
  localparam XIP_S4_CTRL = 3'd4;
  localparam XIP_S5_BSY = 3'd5;
  localparam XIP_S6_RX0 = 3'd6;

  localparam APB_S0_SETUP = 1'b0;
  localparam APB_S1_ACCESS = 1'b1;

  input clock;
  input reset;
  input is_xip;
  input [32-1:0] in_paddr;
  output [4:0] xip_paddr;
  output [32-1:0] xip_pwdata;
  output [3:0] xip_pstrb;
  output xip_pwrite;
  output xip_penable;
  input xip_bsy;
  input wb_ack_o;
  output xip_ack_o;

  reg [4:0] xip_paddr;
  reg [32-1:0] xip_pwdata;
  wire [3:0] xip_pstrb;
  reg xip_pwrite, xip_penable;
  wire xip_ack_o;

  reg [2:0] stage;
  reg stage_switch;

  // xip stage
  always @(posedge clock) begin
    if (reset) stage <= XIP_S0_IDLE;
    else begin
      case (stage)
        XIP_S0_IDLE: stage <= stage_switch ? XIP_S1_TX1 : XIP_S0_IDLE;
        XIP_S1_TX1:  stage <= stage_switch ? XIP_S2_DIV : XIP_S1_TX1;
        XIP_S2_DIV:  stage <= stage_switch ? XIP_S3_SS : XIP_S2_DIV;
        XIP_S3_SS:   stage <= stage_switch ? XIP_S4_CTRL : XIP_S3_SS;
        XIP_S4_CTRL: stage <= stage_switch ? XIP_S5_BSY : XIP_S4_CTRL;
        XIP_S5_BSY:  stage <= stage_switch ? XIP_S6_RX0 : XIP_S5_BSY;
        XIP_S6_RX0:  stage <= stage_switch ? XIP_S0_IDLE : XIP_S6_RX0;

        default: stage <= XIP_S0_IDLE;
      endcase
    end
  end

  // xip stage switch logic
  always @(*) begin
    case (stage)
      XIP_S0_IDLE: stage_switch = is_xip;
      XIP_S1_TX1:  stage_switch = wb_ack_o;
      XIP_S2_DIV:  stage_switch = wb_ack_o;
      XIP_S3_SS:   stage_switch = wb_ack_o;
      XIP_S4_CTRL: stage_switch = wb_ack_o;
      XIP_S5_BSY:  stage_switch = wb_ack_o & ~xip_bsy;
      XIP_S6_RX0:  stage_switch = wb_ack_o;

      default: stage_switch = 0;
    endcase
  end

  reg apb_stage;

  // apb stage
  always @(posedge clock) begin
    if (reset) apb_stage <= APB_S0_SETUP;
    else begin
      case (apb_stage)
        APB_S0_SETUP:  apb_stage <= (stage != XIP_S0_IDLE) ? APB_S1_ACCESS : APB_S0_SETUP;
        APB_S1_ACCESS: apb_stage <= wb_ack_o ? APB_S0_SETUP : APB_S1_ACCESS;

        default: apb_stage <= APB_S0_SETUP;
      endcase
    end
  end

  /* apb signals */
  // apb enable
  assign xip_penable = apb_stage == APB_S1_ACCESS;
  // apb byte strobe
  assign xip_pstrb = 4'hf;
  // apb ack
  assign xip_ack_o = (stage == XIP_S6_RX0) & wb_ack_o;

  // apb adr
  always @(*) begin
    case (stage)
      XIP_S0_IDLE: xip_paddr = 5'h04;
      XIP_S1_TX1:  xip_paddr = 5'h04;
      XIP_S2_DIV:  xip_paddr = 5'h14;
      XIP_S3_SS:   xip_paddr = 5'h18;
      XIP_S4_CTRL: xip_paddr = 5'h10;
      XIP_S5_BSY:  xip_paddr = 5'h10;
      XIP_S6_RX0:  xip_paddr = 5'h00;

      default: xip_paddr = 5'h04;
    endcase
  end

  // apb data
  always @(*) begin
    case (stage)
      XIP_S0_IDLE: xip_pwdata = {8'h03, in_paddr[23:2], 2'b00};  // {READ, addr[23:0]}
      XIP_S1_TX1:  xip_pwdata = {8'h03, in_paddr[23:2], 2'b00};
      XIP_S2_DIV:  xip_pwdata = 32'h01;  // just for fast simulation
      XIP_S3_SS:   xip_pwdata = 32'h1;  // flash
      // TODO: seperate GO_BSY with other bits
      XIP_S4_CTRL: xip_pwdata = 32'h00002540;
      XIP_S5_BSY:  xip_pwdata = 32'h0;
      XIP_S6_RX0:  xip_pwdata = 32'h0;

      // ctrl.char_len = 64
      // ctrl.rx_neg = 0
      // ctrl.tx_neg = 1
      // ctrl.lsb = 0
      // ctrl.ie = 0
      // ctrl.ass = 1

      default: xip_pwdata = 32'h0;
    endcase
  end

  // apb write enable
  always @(*) begin
    case (stage)
      XIP_S0_IDLE: xip_pwrite = 1'b1;
      XIP_S1_TX1:  xip_pwrite = 1'b1;
      XIP_S2_DIV:  xip_pwrite = 1'b1;
      XIP_S3_SS:   xip_pwrite = 1'b1;
      XIP_S4_CTRL: xip_pwrite = 1'b1;
      XIP_S5_BSY:  xip_pwrite = 1'b0;
      XIP_S6_RX0:  xip_pwrite = 1'b0;

      default: xip_pwrite = 1'b0;
    endcase
  end

  /* apb signals */
endmodule
