module bitrev (
  input  sck,
  input  ss,
  input  mosi,
  output miso
);
  // CTRL: LSB first, with negedge latches, posedge changes
  //  .ASS    = 0
  //  .IE     = 0
  //  .LSB    = 1
  //  .Tx_NEG = 0
  //  .Rx_NEG = 1
  //  .CHAR_LEN = 16

  assign miso = 1'b1;

  reg [7:0] num;
  wire [7:0] rev;
  reg [2:0] cnt;
  reg stage;

  always @(negedge sck) begin
    if (ss) cnt <= 3'b0;
    else begin
      if (cnt == 3'd7) cnt <= 3'b0;
      else cnt <= cnt + 1;

      if (cnt == 3'd7) stage <= ~stage;

      if (~stage) num[cnt] <= mosi;
    end
  end

  assign rev[0] = num[7];
  assign rev[1] = num[6];
  assign rev[2] = num[5];
  assign rev[3] = num[4];
  assign rev[4] = num[3];
  assign rev[5] = num[2];
  assign rev[6] = num[1];
  assign rev[7] = num[0];

  assign miso = ~stage ? 1'b1 : rev[cnt];
endmodule
