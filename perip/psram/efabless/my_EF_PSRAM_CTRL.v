`timescale              1ns/1ps
`default_nettype        none

module my_PSRAM_READER (
    input   wire            clk,
    input   wire            rst_n,
    input   wire [23:0]     addr,
    input   wire            rd,
    input   wire [2:0]      size,
    output  wire            done,
    output  wire [31:0]     line,

    output  reg             sck,
    output  reg             ce_n,
    input   wire [3:0]      din,
    output  wire [3:0]      dout,
    output  wire            douten
);

    localparam  IDLE = 1'b0,
                READ = 1'b1;

    wire [7:0]  FINAL_COUNT = 19 + size*2; // was 27: Always read 1 word

    reg         state, nstate;
    reg [7:0]   counter;
    reg [23:0]  saddr;
    reg [7:0]   data [3:0];

    wire[7:0]   CMD_EBH = 8'heb;

    always @*
        case (state)
            IDLE: if(rd) nstate = READ; else nstate = IDLE;
            READ: if(done) nstate = IDLE; else nstate = READ;
        endcase

    always @ (posedge clk or negedge rst_n)
        if(!rst_n) state <= IDLE;
        else state <= nstate;

    // Drive the Serial Clock (sck) @ clk/2
    always @ (posedge clk or negedge rst_n)
        if(!rst_n)
            sck <= 1'b0;
        else if(~ce_n)
            sck <= ~ sck;
        else if(state == IDLE)
            sck <= 1'b0;

    // ce_n logic
    always @ (posedge clk or negedge rst_n)
        if(!rst_n)
            ce_n <= 1'b1;
        else if(state == READ)
            ce_n <= 1'b0;
        else
            ce_n <= 1'b1;

    // NOTE: Changes adapt to QPI -- Simply set the reset value to 6
    always @ (posedge clk or negedge rst_n)
        if(!rst_n)
            counter <= 8'd6;
        else if(sck & ~done)
            counter <= counter + 1'b1;
        else if(state == IDLE)
            counter <= 8'd6;

    always @ (posedge clk or negedge rst_n)
        if(!rst_n)
            saddr <= 24'b0;
        else if((state == IDLE) && rd)
            //saddr <= {addr[23:2], 2'b0};
            saddr <= {addr[23:0]};

    // Sample with the negedge of sck
    wire[1:0] byte_index = {counter[7:1] - 8'd10}[1:0];
    always @ (posedge clk)
        if(counter >= 20 && counter <= FINAL_COUNT)
            if(sck)
                data[byte_index] <= {data[byte_index][3:0], din}; // Optimize!

    // NOTE: Changes adapt to QPI -- counter 6, 7 binds to cmdH, cmdL
    assign dout     =   (counter < 7)   ?   CMD_EBH[7:4]        :
                        (counter == 7)  ?   CMD_EBH[3:0]        :
                        (counter == 8)  ?   saddr[23:20]        :
                        (counter == 9)  ?   saddr[19:16]        :
                        (counter == 10) ?   saddr[15:12]        :
                        (counter == 11) ?   saddr[11:8]         :
                        (counter == 12) ?   saddr[7:4]          :
                        (counter == 13) ?   saddr[3:0]          :
                        4'h0;

    assign douten   = (counter < 14);

    assign done     = (counter == FINAL_COUNT+1);

    generate
        genvar i;
        for(i=0; i<4; i=i+1)
            assign line[i*8+7: i*8] = data[i];
    endgenerate


endmodule

// Using 38H Command
module my_PSRAM_WRITER (
    input   wire            clk,
    input   wire            rst_n,
    input   wire [23:0]     addr,
    input   wire [31: 0]    line,
    input   wire [2:0]      size,
    input   wire            wr,
    output  wire            done,

    output  reg             sck,
    output  reg             ce_n,
    input   wire [3:0]      din,
    output  wire [3:0]      dout,
    output  wire            douten
);
    //localparam  DATA_START = 14;
    localparam  IDLE = 1'b0,
                WRITE = 1'b1;

    wire[7:0]        FINAL_COUNT = 13 + size*2;

    reg         state, nstate;
    reg [7:0]   counter;
    reg [23:0]  saddr;
    //reg [7:0]   data [3:0];

    wire[7:0]   CMD_38H = 8'h38;

    always @*
        case (state)
            IDLE: if(wr) nstate = WRITE; else nstate = IDLE;
            WRITE: if(done) nstate = IDLE; else nstate = WRITE;
        endcase

    always @ (posedge clk or negedge rst_n)
        if(!rst_n) state <= IDLE;
        else state <= nstate;

    // Drive the Serial Clock (sck) @ clk/2
    always @ (posedge clk or negedge rst_n)
        if(!rst_n)
            sck <= 1'b0;
        else if(~ce_n)
            sck <= ~ sck;
        else if(state == IDLE)
            sck <= 1'b0;

    // ce_n logic
    always @ (posedge clk or negedge rst_n)
        if(!rst_n)
            ce_n <= 1'b1;
        else if(state == WRITE)
            ce_n <= 1'b0;
        else
            ce_n <= 1'b1;

    // NOTE: Changes adapt to QPI -- counter 6, 7 binds to cmdH, cmdL
    always @ (posedge clk or negedge rst_n)
        if(!rst_n)
            counter <= 8'd6;
        else if(sck & ~done)
            counter <= counter + 1'b1;
        else if(state == IDLE)
            counter <= 8'd6;

    always @ (posedge clk or negedge rst_n)
        if(!rst_n)
            saddr <= 24'b0;
        else if((state == IDLE) && wr)
            saddr <= addr;

    // NOTE: Changes adapt to QPI -- counter 6, 7 binds to cmdH, cmdL
    assign dout     =   (counter < 7)   ?   CMD_38H[7:4]        :
                        (counter == 7)  ?   CMD_38H[3:0]        :
                        (counter == 8)  ?   saddr[23:20]        :
                        (counter == 9)  ?   saddr[19:16]        :
                        (counter == 10) ?   saddr[15:12]        :
                        (counter == 11) ?   saddr[11:8]         :
                        (counter == 12) ?   saddr[7:4]          :
                        (counter == 13) ?   saddr[3:0]          :
                        (counter == 14) ?   line[7:4]           :
                        (counter == 15) ?   line[3:0]           :
                        (counter == 16) ?   line[15:12]         :
                        (counter == 17) ?   line[11:8]          :
                        (counter == 18) ?   line[23:20]         :
                        (counter == 19) ?   line[19:16]         :
                        (counter == 20) ?   line[31:28]         :
                        line[27:24];

    assign douten   = (~ce_n);

    assign done     = (counter == FINAL_COUNT + 1);


endmodule

// Using 35H Command
module my_PSRAM_QPI_EN (
    input   wire            clk,
    input   wire            rst_n,
    input   wire            er,
    output  reg             done,

    output  reg             sck,
    output  wire            ce_n,
    // input   wire [3:0]      din,
    output  wire [3:0]      dout,
    output  wire            douten
);
    reg[2:0]    counter;

    wire[7:0]   CMD_35H = 8'h35;

    // Drive the Serial Clock (sck) @ clk/2
    always @ (posedge clk or negedge rst_n)
        if(!rst_n)
            sck <= 1'b0;
        else if(~ce_n)
            sck <= ~ sck;
        else
            sck <= 1'b0;

    // ce_n logic
    assign ce_n = ~er;

    always @ (posedge clk or negedge rst_n)
        if(!rst_n)
            counter <= 3'd7;
        else if(sck & ~done)
            counter <= counter - 1'b1;
        else if(~er)
            counter <= 3'd7;

    // done logic
    always @ (posedge clk or negedge rst_n)
        if(!rst_n)
            done <= 1'b0;
        else
            done <= (counter == 3'd0);

    assign dout     =   {3'd0, CMD_35H[counter]};

    assign douten   = (~ce_n);


endmodule
