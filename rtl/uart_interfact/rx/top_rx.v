//==============================================================================
// Module Name : top_rx
// Project     : UART Receiver
// Author      : Ansh Shinde
//
// Description :
//
// Top-level UART receiver module.
//
// Integrates:
// - UART receiver datapath
// - FSM-based UART receiver control path
//
// Features:
// - FIFO-based receive buffering
// - 16x oversampling
// - UART frame deserialization
// - Parity checking
// - Frame error detection
// - Overrun error detection
// - Parameterized FIFO architecture
//
// Architecture:
// control_path_rx <-> data_path_rx
//
// Notes:
// - Current implementation uses fixed UART frame format
// - Dynamic UART framing is not yet implemented
// - Current implementation supports single stop bit
//
//==============================================================================
module top_rx #(parameter DEPTH=8, 
                        WIDTH=8,
                        N=$clog2(DEPTH)
               )(
                 input clk,
                 input rst,
                 input en,
                 input rx,
                 input rd,
                 input parity_en,
                 input parity_odd,
                 input [8:0]div,
                 output [7:0]data_out,
                 output nr_full,
                 output nr_empty,
                 output frame_error,
                 output parity_error,
                 output overrun_error
                );
                wire start,stop,full,empty,calculated_parity,parity_bit,wr,sample_bit,clr_shiftreg,latch,edge_detect;
                wire [3:0]bit_count,sample_count;
                wire [10:0]raw_byte;

//------------------------------------------------------------------------------
// UART Receiver Control Path
//------------------------------------------------------------------------------
                control_rx #(.DEPTH(DEPTH),
                                  .WIDTH(WIDTH)
                                  )ctrl_rx(
                                        .clk(clk),
                                        .rst(rst),
                                        .en(en),
                                        .parity_en(parity_en),
                                        .parity_odd(parity_odd),
                                        .div(div),
                                        .start(start),
                                        .stop(stop),
                                        .bit_count(bit_count),
                                        .sample_count(sample_count),
                                        .full(full),
                                        .empty(empty),
                                        .calculated_parity(calculated_parity),
                                        .parity_bit(parity_bit),
                                        .wr(wr),
                                        .sample_bit(sample_bit),
                                        .clr_shiftreg(clr_shiftreg),
                                        .frame_error(frame_error),
                                        .parity_error(parity_error),
                                        .overrun_error(overrun_error),
                                        .latch(latch),
                                        .edge_detect(edge_detect),
                                        .raw_byte(raw_byte)
                                        );

//------------------------------------------------------------------------------
// UART Receiver Datapath
//------------------------------------------------------------------------------
               data_rx     #(.DEPTH(DEPTH),
                                  .WIDTH(WIDTH)
                                  )dat_rx(
                                        .clk(clk),
                                        .rst(rst),
                                        .en(en),
                                        .rx(rx),
                                        .parity_en(parity_en),
                                        .parity_odd(parity_odd),
                                        .div(div),
                                        .start(start),
                                        .stop(stop),
                                        .bit_count(bit_count),
                                        .sample_count(sample_count),
                                        .full(full),
                                        .empty(empty),
                                        .calculated_parity(calculated_parity),
                                        .parity_bit(parity_bit),
                                        .rd(rd),
                                        .wr(wr),
                                        .sample_bit(sample_bit),
                                        .clr_shiftreg(clr_shiftreg),
                                        .latch(latch),
                                        .nr_empty(nr_empty),
                                        .nr_full(nr_full),
                                        .data_out(data_out),
                                        .en_counter(edge_detect),
                                        .raw_byte(raw_byte)
                                        );

endmodule



                                        
