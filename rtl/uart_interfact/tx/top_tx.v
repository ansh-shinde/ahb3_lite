//==============================================================================
// Module Name : top_tx
// Project     : UART Transmitter
// Author      : Ansh Shinde
//
// Description :
//
// Top-level UART transmitter module.
//
// Integrates:
// - UART transmitter datapath
// - UART transmitter control path
//
// Features:
// - FIFO-based transmission buffering
// - Baud-rate synchronized transmission
// - Parity generation
// - UART serial transmission
// - Parameterized FIFO depth and width
//
//==============================================================================
module top_tx #(parameter DEPTH=8, 
                        WIDTH=8,
                        N=$clog2(DEPTH)
               )(
                 input       clk,
                 input       wr,
                 input       parity_en,parity_odd,
                 input       en,rst,
                 input [7:0] data_in,
                 input [8:0] div,
                 output      tx,busy,nr_full,nr_empty,full
                );

                 wire empty,rd;
                 wire [8:0] count;
                 wire ld_data,shift_en;

//------------------------------------------------------------------------------
// UART Transmitter Datapath
//------------------------------------------------------------------------------
data_tx #(.DEPTH(DEPTH),
               .WIDTH(WIDTH)
               )dat_tx(
                    .clk(clk),
                    .rst(rst),
                    .fifo_en(en),
                    .rd(rd),
                    .wr(wr),
                    .shift_en(shift_en),
                    .ld_data(ld_data),
                    .nr_full(nr_full),
                    .nr_empty(nr_empty),
                    .full(full),
                    .empty(empty),
                    .count(count),
                    .tx(tx),
                    .parity_en(parity_en),
                    .parity_odd(parity_odd),
                    .div(div),
                    .data_in(data_in)
                   );

//------------------------------------------------------------------------------
// UART Transmitter Control Path
//------------------------------------------------------------------------------
control_tx #(.DEPTH(DEPTH),
               .WIDTH(WIDTH)
                 )ctrl_tx(
                       .clk(clk),
                       .rst(rst),
                       .empty(empty),
                       .en(en),
                       .count(count),
                       .div(div),
                       .rd(rd),
                       .ld_data(ld_data),
                       .busy(busy),
                       .shift_en(shift_en)
                      );
endmodule
                           

