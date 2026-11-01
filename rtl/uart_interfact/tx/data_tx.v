//==============================================================================
// Module Name : data_tx
// Project     : UART Transmitter
// Author      : Ansh Shinde
//
// Description :
//
// UART transmitter datapath.
//
// Features:
// - FIFO-based transmission buffering
// - Programmable baud-rate generation
// - Configurable UART baud-rate operation
// - Parallel-In Serial-Out (PISO) serialization
// - Even/Odd parity generation
// - UART serial transmission
// - Parameterized FIFO depth and width
//
// Architecture:
// FIFO -> Baud Counter -> Parity Generator -> PISO Serializer
//
// Baud Configuration:
// - Baud-rate divider value is provided externally
//   through the `div` input
// - Current implementation uses a 9-bit divider
// - Supported divider range: 1 to 511
//
// Notes:
// - Current implementation uses fixed UART frame format
// - Current implementation supports single stop bit
// - Dynamic UART framing is not yet implemented
// - Current transmitter control logic is not FSM-based
//
// Submodules:
// - top          : FIFO buffer
// - baud_counter : Baud timing generator
// - parity       : Parity generation logic
// - piso         : UART serializer
//
//==============================================================================

module data_tx #(parameter DEPTH=8, 
                        WIDTH=8,
                        N=$clog2(DEPTH)
                      )
                (
                 input clk,
                 input rst,
                 input ld_data,
                 input shift_en,
                 input parity_en,
                 input parity_odd,
                 input [8:0]div,
                 input [7:0]data_in,
                 input rd,
                 input wr,
                 input fifo_en,
                 output nr_full,
                 output full,
                 output empty,
                 output nr_empty,
                 output [8:0]count,
                 output tx
                );

                wire  [7:0]r1;
                wire       parity_w;
                reg ld_data_d;


                always@(posedge clk or posedge rst)begin
                    if (rst) begin
                        ld_data_d<=0;
                    end
                    else begin
                        ld_data_d<=ld_data;
                    end
                end


 //------------------------------------------------------------------------------
// FIFO Instance
//------------------------------------------------------------------------------
                top_fifo_tx #(.DEPTH(DEPTH),
                      .WIDTH(WIDTH)
                      )fifo(
                          .clk_wr(clk),
                          .clk_rd(clk),
                          .rd(rd),
                          .wr(wr),
                          .clr(rst),
                          .en(fifo_en),
                          .data_in(data_in),
                          .data_out(r1),
                          .full(full),
                          .empty(empty),
                          .nr_full(nr_full),
                          .nr_empty(nr_empty)
                          );
                            
//------------------------------------------------------------------------------
// Baud Counter
//------------------------------------------------------------------------------                
                baud_counter c1(
                                .div(div),
                                .clk(clk),
                                .rst(rst),
                                .count(count)
                               );
 
//------------------------------------------------------------------------------
// Parity Generator
//------------------------------------------------------------------------------
                parity p1(
                          .in(r1),
                          .parity_en(parity_en),
                          .parity_odd(parity_odd),
                          .par_bit(parity_w)
                         );
                
//------------------------------------------------------------------------------
// UART Serializer
//------------------------------------------------------------------------------
                piso pi1(
                        .data_in(r1),
                        .shift_en(shift_en),
                        .ld_data(ld_data_d),
                        .rst(rst),
                        .clk(clk),
                        .parity_bit(parity_w),
                        .count(count),
                        .serial_out(tx)
                       );

endmodule

//------------------------------------------------------------------------------
// Module Name : baud_counter
// Description :
// Generates baud-rate timing counter for UART transmission.
//------------------------------------------------------------------------------
module baud_counter(
                    input      [8:0]div,
                    input           clk,
                    input           rst,
                    output reg [8:0]count=9'b0
                    );
                    always@(posedge clk or posedge rst)begin
                    if(rst)begin
                    count<=9'b0;
                    end
                    else if(count==(div-1))begin
                    count<=9'b0;
                    end
                    else begin
                    count<=count+1;
                    end
                    end
endmodule 


//------------------------------------------------------------------------------
// Module Name : parity
// Description :
// Generates even or odd parity bit for UART transmission.
//------------------------------------------------------------------------------
module parity(
              input [7:0]in,
              input      parity_en,
              input      parity_odd,

              output par_bit
             );
             wire parity_calc;
             assign parity_calc=^in;
             assign par_bit=parity_en?(parity_odd?~parity_calc:parity_calc):1'b0;
endmodule


//------------------------------------------------------------------------------
// Module Name : piso
// Description :
// Parallel-In Serial-Out shift register used for UART transmission.
//
// UART Frame Format:
// START + DATA + PARITY + STOP
//
// LSB is transmitted first.
//------------------------------------------------------------------------------
module piso(
            input [7:0]  data_in,
            input        shift_en,  
            input        ld_data,
            input        rst,
            input        clk,
            input        parity_bit,
            input [8:0]  count,
            output       serial_out
           );
            reg    [10:0]shift_reg;
            reg          transmitting;
            always@(posedge clk or posedge rst)begin
            if(rst)begin
            shift_reg<=11'b0;
            transmitting<=1'b0;
            end
            else if(ld_data)begin
            transmitting<=1'b1;
            shift_reg[8:1]<=data_in;
            shift_reg[10]<=1'b1;
            shift_reg[0]<=1'b0;
            shift_reg[9]<=parity_bit;
            end
            else if(shift_en)begin
            shift_reg<={1'b0,shift_reg[10:1]};
            end
            else if(shift_reg == 11'b0)begin
            transmitting <= 1'b0;
            end
            end
            assign serial_out = transmitting ? shift_reg[0] : 1'b1;

endmodule




    

    


