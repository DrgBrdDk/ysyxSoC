module ps2_top_apb(
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

  input         ps2_clk,
  input         ps2_data
);

localparam ADDR_PS2 = 32'h1001_1000;

localparam S_IDLE = 0, S_ACCESS = 1;

wire kbd_ready;
reg kbd_next_n_q;
wire [7:0] kbd_data_w;
reg [7:0] kbd_buffer_q;

reg state_r;
wire load_w, fin_w;

// Control Signals
assign load_w = state_r == S_IDLE && in_psel;
assign fin_w = state_r == S_ACCESS && in_penable;

// State Machine
always @(posedge clock or posedge reset) begin
  if (reset) state_r <= S_IDLE;
  else if (fin_w) state_r <= S_IDLE;
  else if (in_psel) state_r <= S_ACCESS;
end

// PS/2 Read
always @(posedge clock or posedge reset) begin
  if (reset) kbd_buffer_q <= 0;
  else if (load_w && in_paddr == ADDR_PS2)
    kbd_buffer_q <= kbd_ready ? kbd_data_w : 0;

  if (reset) kbd_next_n_q <= 1;
  else if (load_w && in_paddr == ADDR_PS2 && kbd_ready)
    kbd_next_n_q <= 0;
  else kbd_next_n_q <= 1;
end

ps2_kbd kbd(
  .clk(clock),
  .rstn(~reset),
  .ps2_clk(ps2_clk),
  .ps2_data(ps2_data),
  .nextdata_n(kbd_next_n_q),
  .data(kbd_data_w),
  .ready(kbd_ready),
  .overflow()
);

// Output
assign in_pready = fin_w;
assign in_prdata = {24'd0, kbd_buffer_q};
assign in_pslverr = 0;

endmodule

// Copy from NJU CS exp
module ps2_kbd(
  input            clk,
  input            rstn,
  input            ps2_clk,
  input            ps2_data,
  input            nextdata_n,
  output     [7:0] data,
  output reg       ready,
  output reg       overflow
);
// internal signal, for test
reg [9:0] buffer;  // ps2_data bits
reg [7:0] fifo                     [7:0];  // data fifo
reg [2:0] w_ptr, r_ptr;  // fifo write and read pointers
reg [3:0] count;  // count ps2_data bits
// detect falling edge of ps2_clk
reg [2:0] ps2_clk_sync;

always @(posedge clk) begin
  ps2_clk_sync <= {ps2_clk_sync[1:0], ps2_clk};
end

wire sampling = ps2_clk_sync[2] & ~ps2_clk_sync[1];

always @(posedge clk) begin
  if (rstn == 0) begin  // reset
    count <= 0;
    w_ptr <= 0;
    r_ptr <= 0;
    overflow <= 0;
    ready <= 0;
  end else begin
    if (ready) begin  // read to output next data
      if(nextdata_n == 1'b0) //read next data
              begin
        r_ptr <= r_ptr + 3'b1;
        if (w_ptr == (r_ptr + 1'b1))  //empty
          ready <= 1'b0;
      end
    end
    if (sampling) begin
      if (count == 4'd10) begin
        if ((buffer[0] == 0) &&  // start bit
            (ps2_data) &&  // stop bit
            (^buffer[9:1])) begin  // odd  parity
          fifo[w_ptr] <= buffer[8:1];  // kbd scan code
          w_ptr <= w_ptr + 3'b1;
          ready <= 1'b1;
          overflow <= overflow | (r_ptr == (w_ptr + 3'b1));
        end
        count <= 0;  // for next
      end else begin
        buffer[count] <= ps2_data;  // store ps2_data
        count <= count + 3'b1;
      end
    end
  end
end
assign data = fifo[r_ptr];  //always set output data

endmodule
