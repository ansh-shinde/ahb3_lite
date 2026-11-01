//==============================================================================
// Module Name : data_rx
// Project     : UART Receiver
// Author      : Ansh Shinde
//
// Description :
//
// UART receiver datapath.
//
// Features:
// - FIFO-based receive buffering
// - 16x oversampling
// - Start-bit edge detection
// - UART frame deserialization (SIPO)
// - Even/Odd parity checking
// - Stop-bit detection
// - RX input synchronization
// - Parameterized FIFO depth and width
//
// Architecture:
// RX Synchronizer -> Oversampling Counter -> SIPO ->
// Parity Checker -> FIFO Buffer
//
// Baud Configuration:
// - Oversampling timing derived from external divider input
// - Divider value provided through `div` input
// - Current implementation uses 9-bit divider input
// - Supported divider range: 1 to 511
//
// UART Frame Format:
// START + 8 DATA + PARITY + STOP
//
// Notes:
// - Current implementation uses fixed UART frame format
// - Current implementation supports single stop bit
// - Dynamic UART framing is not yet implemented
// - Current receiver control logic is not fully FSM-based
//
// Submodules:
// - top          : FIFO buffer
// - baud_counter : Oversampling counter
// - parity       : Parity checker
// - sipo         : UART deserializer
//
//==============================================================================
module data_rx #(parameter DEPTH=8, 
                        WIDTH=8,
                        N=$clog2(DEPTH)
                      )(
                        input clk,
                        input en,
                        input parity_en,
                        input parity_odd,
                        input [8:0]div,
                        input latch,
                        input rst,
                        input rx,
                        input wr,
                        input rd,
                        input sample_bit,
                        input clr_shiftreg,
                        output nr_full,
                        output full,
                        output [3:0]bit_count,
                        output [3:0]sample_count,
                        output empty,
                        output reg start,
                        output reg stop,
                        output nr_empty,
                        output reg en_counter,
                        output calculated_parity,
                        output reg parity_bit,
                        output [7:0]data_out,
                        output [10:0]raw_byte  // needed in control path to check the stop bit is valid or not
                       );
                       reg [7:0]data_byte;
                       reg sync,sync_rx,start_check,start_check1,start_check2;

                       always@(posedge clk)begin
                       start_check1<=start_check;
                       start_check2<=start_check1;   // delaying the check 1 cycle to avoide checking right at the change
                       end
                    
//------------------------------------------------------------------------------
// Start-Bit Detection
// - Detects valid UART start bit
// - Validates received start condition
//------------------------------------------------------------------------------
                       
                       always@(posedge clk or posedge rst)begin
                       if(rst)begin
                       start<=1'b0;
                       end
                       else if(en)begin
                       if((bit_count==0) && start_check2)begin  // Using start_check instead of sample_bit because the shifting happens after sample_bit
                       if(raw_byte[10]==0)begin                // so the old values of raw_byte[10](which is stop bit of previous frame)is getting checked as start bit 
                       start<=1'b1;                            // hence the condition will be false as start_bit=0 & stop_bit=1 and it will not trigger the start 
                       end                                      // eventually failing to generate sample_bit in control path
                       else begin
                       start<=1'b0;
                       end
                       end
                       else begin
                        start<=1'b0;
                       end
                       end
                       end

//------------------------------------------------------------------------------
// Stop-Bit Detection
// - Captures received UART stop bit
// - Clears stop flag on frame reset
//------------------------------------------------------------------------------
                       
                       always@(posedge clk or posedge rst)begin
                       if(rst)begin
                       stop<=1'b0;
                       end
                       else if(en)begin
                       if((bit_count==11) && sample_bit)begin
                       stop<=raw_byte[10];
                       end
                       else if(clr_shiftreg) stop<=1'b0;
                       else stop<=0;
                       end
                       end

//------------------------------------------------------------------------------
// UART Receive Enable Control
// - Enables baud counter after start-edge detection
//------------------------------------------------------------------------------

                       always@(posedge clk or posedge rst)begin
                       if(rst)begin
                       en_counter<=1'b0;
                       end
                       else if((sync==0 )&&(sync_rx==1))begin
                       en_counter<=1'b1;
                       end
                       end

//------------------------------------------------------------------------------
// UART Receive Enable Control
// - Enables baud counter after start-edge detection
//------------------------------------------------------------------------------

                       always@(posedge clk or posedge rst)begin
                       if(rst)begin
                       sync_rx<=0;
                       sync<=0;
                       end
                       else if(en)begin
                       sync<=rx;
                       sync_rx<=sync;
                       end
                       end

//------------------------------------------------------------------------------
// Oversampling Counter Logic
// - Generates UART sampling timing
// - Tracks UART frame progress
//------------------------------------------------------------------------------

                       always@(posedge clk or posedge rst)begin
                       if(rst)begin
                       data_byte<=8'b0;
                       parity_bit<=1'b0;
                       end
                       else if(en)begin
                       if(clr_shiftreg)begin
                       data_byte<=8'b0;
                       parity_bit<=1'b0;
                       end
                       else if(latch)begin
                       data_byte<=raw_byte[8:1];
                       parity_bit<=raw_byte[9];
                       end
                       end
                       end

                      
//------------------------------------------------------------------------------
// FIFO Buffer
//------------------------------------------------------------------------------
                       top_fifo_rx #(.DEPTH(DEPTH),
                             .WIDTH(WIDTH)
                             )fifo(
                                 .clk_wr(clk),
                                 .clk_rd(clk),
                                 .rd(rd),
                                 .wr(wr),
                                 .clr(rst),
                                 .en(en),
                                 .data_in(data_byte),
                                 .data_out(data_out),
                                 .full(full),
                                 .empty(empty),
                                 .nr_full(nr_full),
                                 .nr_empty(nr_empty)
                                 );
                       
//------------------------------------------------------------------------------
// Oversampling Baud Counter
//------------------------------------------------------------------------------
                       baud_counter_rx bc1(
                                        .div_baud(div),
                                        .clk_baud(clk),
                                        .rst_baud(rst),
                                        .en_counter_baud(en_counter),
                                        .bit_count(bit_count),
                                        .sample_count_16(sample_count)
                                        );

//------------------------------------------------------------------------------
// UART Parity Checker
//------------------------------------------------------------------------------
                       parity_rx p1 (
                                  .in(data_byte),
                                  .parity_en_parity(parity_en),
                                  .parity_odd_parity(parity_odd),
                                  .par_bit_parity(calculated_parity)
                                 );
             
//------------------------------------------------------------------------------
// UART Deserializer (SIPO)
//------------------------------------------------------------------------------
                       sipo_rx po1(
                                .serial_in(sync_rx),
                                .shift_en_sipo(sample_bit),
                                .rst_sipo(rst),
                                .clr_shiftreg_sipo(clr_shiftreg),
                                .clk_sipo(clk),
                                .start_check(start_check),
                                .bit_count_sipo(bit_count),
                                .shift_reg_sipo(raw_byte)
                               );

endmodule


//------------------------------------------------------------------------------
// Module Name : baud_counter
// Description :
// Generates 16x oversampling counters for UART reception.
//
// Functionality:
// - Generates sample timing
// - Tracks UART bit positions
// - Oversampling rate derived from divider input
//------------------------------------------------------------------------------
module baud_counter_rx(
                    input      [8:0]div_baud,
                    input           clk_baud,
                    input           rst_baud,
                    input           en_counter_baud,
                    output reg [3:0]bit_count,
                    output reg [3:0]sample_count_16=4'b0
                    );
                    wire [4:0]div_by_16;
                    reg [4:0]clk_per_sample;

                    assign div_by_16=div_baud>>4;
                              
                    always@(posedge clk_baud or posedge rst_baud)begin
                    if(rst_baud)begin
                    bit_count<=4'b0;
                    sample_count_16<=4'b0;
                    clk_per_sample<=5'b0;
                    end
                    else if(en_counter_baud)begin
                    if(bit_count==12)begin
                    bit_count<=4'b0;
                    end
                    else if(sample_count_16==15)begin
                    bit_count<=bit_count+1;
                    sample_count_16<=4'b0;
                    end
                    else if(clk_per_sample==div_by_16)begin
                    sample_count_16<=sample_count_16+1;
                    clk_per_sample<=5'b0;
                    end
                    else if(clk_per_sample<div_by_16)begin
                    clk_per_sample<=clk_per_sample+1;
                    end
                    end
                    end
endmodule
  
//------------------------------------------------------------------------------
// Module Name : parity
// Description :
// Generates expected UART parity value for received data.
//
// Features:
// - Even parity support
// - Odd parity support
// - XOR-based parity calculation
//------------------------------------------------------------------------------
module parity_rx(
              input [7:0]in,
              input      parity_en_parity,
              input      parity_odd_parity,
              output     par_bit_parity
             );
             wire parity_calc;
             
             assign parity_calc=^in;
             assign par_bit_parity=parity_en_parity?(parity_odd_parity?~parity_calc:parity_calc):1'b0;
endmodule

//------------------------------------------------------------------------------
// Module Name : sipo
// Description :
// Serial-In Parallel-Out (SIPO) shift register used for
// UART frame deserialization.
//
// Functionality:
// - Receives serial UART data
// - Shifts sampled bits into parallel register
// - Reconstructs UART frame
//
// UART Frame Format:
// START + 8 DATA + PARITY + STOP
//
// Notes:
// - LSB received first
// - Current implementation uses fixed frame length
//------------------------------------------------------------------------------
module sipo_rx(
            input            serial_in,
            input            shift_en_sipo,  
            input            rst_sipo,
            input            clr_shiftreg_sipo,
            input            clk_sipo,
            input      [3:0] bit_count_sipo,
            output reg       start_check,
            output reg [10:0]shift_reg_sipo      
           );
            reg sync1,sync2;
            reg shift_pulse;

            always@(posedge clk_sipo or posedge rst_sipo)begin
            if(rst_sipo)begin
            sync1<=0;
            sync2<=0;
            end
            else begin
            sync1<=shift_en_sipo;
            sync2<=sync1;
            end
            end

            always @(posedge clk_sipo or posedge rst_sipo) begin  // this block is added so that shift signal is active for only 1 cycle to avoide miltiple shifts
            if(rst_sipo)
            shift_pulse <= 1'b0;
            else
            shift_pulse <= sync1 & ~sync2;
            end

            always@(posedge clk_sipo or posedge rst_sipo)begin
            if(rst_sipo)begin
            shift_reg_sipo<=11'b0;
            start_check<=0;
            end
            else if(clr_shiftreg_sipo)begin
            shift_reg_sipo <= 11'b0;
            start_check<=0;
            end
            else if(shift_pulse && (bit_count_sipo<11))begin
            shift_reg_sipo<={serial_in,shift_reg_sipo[10:1]};
            start_check<=1;
            end
            else start_check<=0;
            end
endmodule 
            
        
