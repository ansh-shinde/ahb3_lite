//==============================================================================
// Module Name : control_tx
// Project     : UART Transmitter
// Author      : Ansh Shinde
//
// Description :
//
// UART transmitter control path.
//
// Features:
// - FIFO read control
// - UART transmission control
// - Baud-rate synchronized shifting
// - Transmission busy tracking
// - UART frame bit counting
//
// Functionality:
// - Reads data from FIFO when transmitter is idle
// - Loads serializer with UART frame
// - Generates shift enable pulses
// - Tracks transmission progress using bit counter
//
//============================================================================== 
module control_tx #(parameter DEPTH=8, 
                                    WIDTH=8,
                             N=$clog2(DEPTH)
                          )(
                            input clk,
                            input rst,
                            input empty,
                            input en,
                            input [8:0]count,
                            input [8:0]div,
                            output reg rd,
                            output reg ld_data,
                            output reg busy,
                            output reg shift_en
                           );
                           reg [3:0]bit_count=4'b0;

//------------------------------------------------------------------------------
// Transmission Control Logic
//------------------------------------------------------------------------------
                          always@(posedge clk or posedge rst)begin
                          if(rst)begin
                          busy<=0;
                          bit_count<=4'b0;
                          end
                          else if(en)begin
                          if(ld_data)begin
                          busy<=1'b1;
                          bit_count<=16'b0;
                          end
                          else if(busy && shift_en)begin
                          busy<=1'b1;
                          bit_count<=bit_count+1;
                          if(bit_count==4'b1010)begin
                          busy<=1'b0;
                          end
                          end
                          end
                          end
      
//------------------------------------------------------------------------------
// Control Signal Generation
//------------------------------------------------------------------------------
                          always@(posedge clk or posedge rst)begin
                          if(rst)begin
                          ld_data<=1'b0;
                          rd<=1'b0;
                          shift_en<=1'b0;
                          end
                          else if(en)begin
                                  ld_data  <= 0;
                                  rd       <= 0;
                                  shift_en <= 0;
                          if(!empty && !busy && count==9'd3)begin
                          rd<=1'b1;
                          ld_data<=1;
                          end
                          else if((count==div-1)&& busy)begin
                          shift_en<=1'b1;
                          end
                          end
                          end

endmodule
                          

                          

