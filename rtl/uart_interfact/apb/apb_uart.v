//==============================================================================
// Module Name : apb_uart
// Project     : APB UART Peripheral
// Author      : Ansh Shinde
//
// Description :
//
// AMBA APB-compliant UART peripheral integrating UART transmitter,
// UART receiver, APB slave interface, register bank, interrupt
// generation, hardware flow control, and error reporting.
//
// The module allows a processor to configure UART operation through
// memory-mapped registers and exchange data using APB transactions.
//
// Features:
// - AMBA APB Slave Interface
// - UART Transmission and Reception
// - Configurable Baud Rate Generator
// - TX and RX FIFO Buffering
// - RTS/CTS Hardware Flow Control
// - TX and RX Interrupt Generation
// - Parity Error Detection
// - Framing Error Detection
// - Overrun Error Detection
// - Memory-Mapped Register Interface
//
// Register Map:
// - 0x00 : Control Register
// - 0x04 : Status Register
// - 0x08 : Baud Rate Register
// - 0x0C : TX Data Register
// - 0x10 : RX Data Register
//
// Notes:
// - Address decoding uses paddr[4:2].
// - TX FIFO writes occur through TX Data Register (0x0C).
// - RX FIFO reads occur through RX Data Register (0x10).
// - PREADY is generated for a single APB access cycle.
// - Invalid register accesses generate PSLVERR.
//
// Submodules:
// - top_tx : UART transmitter with FIFO
// - top_rx : UART receiver with FIFO
//
//==============================================================================
module apb_uart( 
    input            preset,
    input            pclk,
    // APB control signals
    input            penable,
    input            pwrite,
    input            psel,
    // APB addess and data
    input  [31:0]    paddr,
    input  [31:0]   pwdata,
    // APB response signals
    output  reg         pready,
    output  reg         pslverr,
    output  reg [31:0]  prdata,
    // UART signals
    input           rx,
    input           cts,
    output   reg    rts,
    output   reg    intrr_rx,
    output   reg    intrr_tx,
    output          tx
);
    // 8 registers of 32 bit width
    // address range 0x00 - 0x13
    // byte addressable memory 
    // control_reg: 0x00
    // status_reg : 0x04
    // baud_reg   : 0x08
    // data_reg_tx: 0x0C
    // data_reg_rx: 0x10
    reg [31:0]regfile[7:0];

    // For byte addressable memory
    wire [2:0]reg_no;
    integer i;

    
    wire parity_err, 
         frame_err, 
         overrun_err, 
         busy_tx;

    wire nr_full_tx,
         nr_empty_tx,
         full_tx,
         nr_full_rx,
         nr_empty_rx;

    wire [8:0]baud_uart;

    wire [7:0] data_out_rx,
               data_in_tx;

    wire parity_en_uart,
         parity_odd_uart,
         tx_mode,
         rx_mode;

    wire fifo_tx_wr,fifo_rx_rd;
    wire tx_enable,rx_enable;

    top_tx transmitter(
           .clk(pclk),
           .wr(fifo_tx_wr),
           .en(tx_enable),
           .rst(preset),
           .tx(tx),
           .full(full_tx),
           .nr_full(nr_full_tx),
           .parity_en(parity_en_uart),
           .parity_odd(parity_odd_uart),
           .nr_empty(nr_empty_tx),
           .div(baud_uart),
           .data_in(data_in_tx),
           .busy(busy_tx)
    );

    top_rx receiver(
             .clk(pclk),
             .rst(preset),
             .en(rx_enable),
             .rd(fifo_rx_rd),
             .rx(rx),
             .parity_en(parity_en_uart),
             .parity_odd(parity_odd_uart),
             .div(baud_uart),
             .data_out(data_out_rx),
             .frame_error(frame_err),
             .parity_error(parity_err),
             .nr_full(nr_full_rx),
             .nr_empty(nr_empty_rx),
             .overrun_error(overrun_err)
            );

    assign reg_no=paddr[4:2];   // Address decoding into reg numbers

    assign tx_enable = cts && tx_mode;  // Enabling tx depending on wr and cts because we need to stop sending if cts is low
    
    assign rx_enable = rx_mode;        // only depends on rx_mode because transmitting tx will stop when rts is low
                                      //  and fifo will be on so that data can be read by apb
                                      //  so if it depends on rts then if rx_fifo is nr_full then it will compeletely shut down rx also disabeling rd  

    assign fifo_tx_wr = psel && pwrite && access_start_d && (reg_no==3);  // enable fifo wr only when addr is reg3 and pwrite==1/0 to avoide writing every cycle
    assign fifo_rx_rd = psel && !pwrite && access_start_d && (reg_no == 4); // single cycle access_start_d to get single cycle wr/rd signal for fifo avoiding multiple rd/wr
                                                                            // and delayed  because data was arriving late and missing the wr signal

//=====================================================================================
// this block checks if preset is on and resets
// if psel is active then read/write takes place depending on pwrite
// before setting pready checks if tx fifo is nearly full to stop and
// wait for tx to finish transmitting
//======================================================================================
    
    reg penable_d, access_start_d;

    always @(posedge pclk or posedge preset) begin
        if (preset)
            penable_d <= 0;
        else
            penable_d <= penable;
        end

    wire access_start = psel & penable & ~penable_d;  // to make pready just 1 cycle

        always@(posedge pclk or posedge preset)begin
        if (preset) begin
            access_start_d<=0;
        end
        else begin
            access_start_d<=access_start;
        end
    end


    always@(posedge pclk or posedge preset)begin
        if (preset) begin
            regfile[0]<=32'b0;
            regfile[2]<=32'b0;
            regfile[3]<=32'b0;
            pready    <= 0;
            pslverr   <= 0;
        end
        else if (access_start_d && (reg_no<=4)) begin
            if (!full_tx) begin
                if (pwrite) begin
                   case (reg_no)
                        3'd0: regfile[0] <= pwdata;
                        3'd2: regfile[2] <= pwdata;
                        3'd3: regfile[3] <= pwdata;
                        default: ;
                        endcase 
                    pready<=1;
                    pslverr<=0;
                end
                else begin
                    prdata<=regfile[reg_no];
                    pready<=1;
                end
            end
            else pready<=0; 
        end
        else if (access_start && !(reg_no<=4)) begin
                pready<=0;
                pslverr<=1;
            end
        else begin
            pready<=0;
            pslverr<=0;
        end
    end

//============================================================================================
// This block connects the regs to ports of Uart tx and rx through wires 
//=============================================================================================

    assign  tx_mode         = regfile[0][0]; 
    assign  rx_mode         = regfile[0][8]; 
    assign  parity_en_uart  = regfile[0][16]; 
    assign  parity_odd_uart = regfile[0][24]; 
    assign  baud_uart       = regfile[2][8:0]; 
    assign  data_in_tx      = regfile[3][7:0]; 

    always@(posedge pclk)begin
        if (preset) begin
            regfile[1] <= 32'b0;
            regfile[4] <= 32'b0;
        end
            regfile[1][0]     <= parity_err;
            regfile[1][8]     <= frame_err;
            regfile[1][16]    <= overrun_err;
            regfile[1][24]    <= busy_tx;
            regfile[4][7:0]   <= data_out_rx;
    end


//======================================================================================================
// This block checks the near full of receiver and generates request to send
// and interrupt signal indicating rx fifo if full
//======================================================================================================

    always@(posedge pclk or posedge preset)begin
        intrr_rx<=0;
        if (preset) begin
            rts<=0;
            intrr_rx<=0;
        end
        else if (nr_full_rx) begin
                rts<=0;
                intrr_rx<=1;
            end
            else rts<=1;
        end

//======================================================================================================
// Interrupt signal for tx fifo
//======================================================================================================

    always@(posedge pclk or posedge preset)begin
        intrr_tx<=0;
        if (preset) begin
            intrr_tx<=0;
        end
        else if (nr_empty_tx) begin
            intrr_tx<=1;
        end
    end

endmodule
