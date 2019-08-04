// -*- mode: verilog; c-basic-offset:4; indent-tabs-mode:nil -*-
// This is derived from symbiflow-arch-defs examples
module top (
            input         clk,
            input         rx,
            output        tx,
            input [15:0]  sw,
            output [15:0] led,
);

   localparam BITS = 4;
   localparam LOG2DELAY = 22;

   reg [BITS+LOG2DELAY-1:0] counter = 0;

   always @(posedge clk) begin
      counter <= counter + 1;
   end

   assign led[3:0] = counter >> LOG2DELAY;
   assign led[14:4] = sw[14:4];
   assign tx = rx;
   assign led[15] = ^sw;
endmodule
