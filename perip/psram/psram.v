localparam CMD_QSPI_READ = 8'heb;
localparam CMD_QSPI_WRITE = 8'h38;
localparam CMD_QPI_ENABLE = 8'h35;

// only support 8-bit, 16-bit and 32-bit rw for each command
module psram(
  input sck,
  input ce_n,
  inout [3:0] dio
);

  localparam [1:0]  S0_CMD = 2'd0,
                    S1_ADDR = 2'd1,
                    S2_WAIT = 2'd2,
                    S3_DATA = 2'd3;

  wire reset = ce_n;

  reg [3:0] dio_o;
  // assign dio = 4'bz;

  reg [1:0] state;
  reg [7:0] counter;
  reg [7:0] cmd;
  reg [23:0] addr;
  reg [31:0] data;

  reg qpi_mode;
  reg state_switch;

  wire ren = (state == S2_WAIT) && (counter == 8'd5);
  wire wen = (state == S3_DATA) && counter[0];
  wire valid = ((cmd == CMD_QSPI_READ) & ren) | ((cmd == CMD_QSPI_WRITE) & wen);
  wire [31:0] rdata, wdata;
  reg [3:0] rdata_latched;
  reg [3:0] wdata_latched;
  wire [1:0] w_offset;

  psram_cmd psram_cmd_i(
    .clock(sck),
    .valid(valid),
    .wen(wen),
    .cmd(cmd),
    .addr({8'd0, addr[23:2], 2'd0}),
    // Write 1 byte each time
    // Use counter[2:1] for increment
    // each byte transfer 2 cycles
    // so we use counter[2:1] for each byte
    .wmask(4'b1 << w_offset),
    .wdata(wdata),
    .rdata(rdata)
  );

  always @(posedge sck or posedge reset) begin
    if (reset) state <= S0_CMD;
    else begin
      case (state)
        S0_CMD: state <= state_switch ? S1_ADDR : state;
        S1_ADDR: state <= state_switch ? (cmd == CMD_QSPI_READ ? S2_WAIT : S3_DATA) : state;
        S2_WAIT: state <= state_switch ? S3_DATA : state;
        S3_DATA: state <= state;
        default: begin
          state <= state;
          $warning("[psram] Assertion failed: Unsupported state %xh\n", state);
          $fatal;
        end
      endcase
    end
  end

  always @(*) begin
    case (state)
      S0_CMD: state_switch = qpi_mode ? (counter == 8'd1) : (counter == 8'd7);
      S1_ADDR: state_switch = (counter == 8'd5);
      S2_WAIT: state_switch = (counter == 8'd5);
      S3_DATA: state_switch = 1'd0;
    endcase
  end

  always @(posedge sck or posedge reset) begin
    if (reset) counter <= 8'd0;
    else begin
      case (state)
        S0_CMD: counter <=  (qpi_mode ? (counter < 8'd1) : (counter < 8'd7))
                                      ? counter + 8'd1 : 8'd0;
        S1_ADDR: counter <= (counter < 8'd5) ? counter + 8'd1 : 8'd0;
        S2_WAIT: counter <= (counter < 8'd5) ? counter + 8'd1 : 8'd0;
        S3_DATA: counter <= (counter < 8'd7) ? counter + 8'd1 : 8'd0;
        default: counter <= counter + 8'd1;
        endcase
    end
  end

  always @(posedge sck or posedge reset) begin
    if (reset) cmd <= 8'd0;
    else if (state == S0_CMD) cmd <= qpi_mode ? {cmd[3:0], dio} : {cmd[6:0], dio[0]};
  end

  always @(posedge sck or posedge reset) begin
    if (reset) addr <= 24'd0;
    else if (state == S1_ADDR) addr <= {addr[19:0], dio};
  end

  // TODO: I don't know how to reset qpi_mode while maintain
  //        correct setting
  always @(posedge sck) begin
    if (state == S0_CMD && state_switch)
      qpi_mode <= ({cmd[6:0], dio[0]} == CMD_QPI_ENABLE) | qpi_mode;
  end
  // assign qpi_mode = 1'b1;

  always @(posedge sck) begin
    wdata_latched <= (cmd == CMD_QSPI_WRITE) ? dio : 4'd0;
  end

  assign w_offset = addr[1:0] + counter[2:1];
  assign wdata = {24'd0, wdata_latched,
                  (cmd == CMD_QSPI_WRITE) ? dio : 4'd0}
                  << (w_offset * 8);

  wire [2:0] cnt5 = {counter[2:1], ~counter[0]};
  assign dio_o = rdata_latched;
  assign dio = (state == S3_DATA && cmd == CMD_QSPI_READ) ? dio_o : 4'bz;

  always @(posedge sck) begin
    // `+ addr[1:0] for 8-bit, 16-bit rw bias`
    rdata_latched <= {rdata >> (4 * (cnt5 + addr[1:0]))}[3:0];
  end

endmodule

import "DPI-C" function void psram_read(input int addr, output int data);
import "DPI-C" function void psram_write(input int addr, input int data, input int wmask);

// Only support 32-bit aligned rw
module psram_cmd(
  input clock,
  input valid,
  input wen,
  input [7:0] cmd,
  input [31:0] addr,
  input [3:0] wmask,
  input [31:0] wdata,
  output reg [31:0] rdata
);

  always @(posedge clock) begin
    if (valid) begin
      if (~wen && cmd == CMD_QSPI_READ) psram_read(addr, rdata);
      else if (wen && cmd == CMD_QSPI_WRITE) psram_write(addr, wdata, {28'd0, wmask});
      else begin
        $warning("[psram] Assertion failed: Unsupport command %xh\n", cmd);
        $fatal;
      end
    end
  end

endmodule
