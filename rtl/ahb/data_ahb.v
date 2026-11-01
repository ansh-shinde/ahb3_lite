//==============================================================================
// Module Name : data_ahb
// Project     : AHB Lite Master
// Author      : Ansh Shinde
//
// Description :
//
// Datapath of the AHB Lite master. This module handles address
// generation, burst management, transfer size validation, write
// data alignment, and read data capture.
//
// The datapath receives transaction requests and generates the
// corresponding AHB address, transfer control, and data signals.
//
// Features:
// - AHB address generation
// - Burst transfer management
// - Incrementing and wrapping burst support
// - Transfer size validation
// - Address alignment checking
// - Address and data phase counters
// - Write data lane alignment
// - Read data capture
//
// Supported Burst Types:
// - SINGLE
// - INCR
// - WRAP4 / INCR4
// - WRAP8 / INCR8
// - WRAP16 / INCR16
//
// Supported Transfer Sizes:
// - Byte (8-bit)
// - Halfword (16-bit)
// - Word (32-bit)
//
// Notes:
// - Address generation is controlled by init, cont, and gen_addr.
// - Transfer size and address alignment are checked before
//   generating a valid transfer.
// - Burst counters track address and data phase progress separately.
// - Wrapping bursts use a calculated base address and burst boundary.
// - Write data is aligned according to the transfer size and
//   address offset.
// - Read data is captured from the AHB read data bus.
//
//==============================================================================
module  data_ahb(
    input            hclk,
    input            hreset,
    input            init,
    input            cont,
    input            req_valid,
    input            clr,
    input            check_size,
    input            gen_addr,
    input            sel_lane,
    input            req_write,
    input      [31:0]req_addr,
    input      [1:0] req_size,
    input      [2:0] req_burst,
    input      [31:0]wdata,
    input      [31:0]hrdata,
    output reg       valid_size,
    output reg [4:0] data_count,
    output reg [4:0] addr_count,
    output reg [31:0]resp_rdata,
    output reg       hwrite,
    output reg [4:0] burst_beats, // 5 bit reg because count max value goes till 16 and 4bit reg can hold only 15
    output reg [31:0]haddr,
    output reg [1:0] hsize,
    output reg [2:0] hburst,
    output reg [31:0]hwdata
);

    reg req_valid_d,data_sent,addr_sent;
    reg [31:0]burst_bytes,base,diff,incr_addr,current_addr,data_hold,addr_hold;

    localparam SINGLE=3'b000, 
               INCR  =3'b001, 
               WRAP4 =3'b010, 
               INCR4  =3'b011, 
               WRAP8 =3'b100, 
               INCR8  =3'b101, 
               WRAP16=3'b110,
               INCR16 =3'b111;
    
    localparam BYTE    =2'b00, 
               HALFWORD=2'b01,
               WORD    =2'b10;

           
//================================================================================================
// data hold
//================================================================================================
    always@(posedge hclk or hreset)begin
        if (hreset) begin
            data_hold<=32'b0;
        end
        else if (clr) begin
            data_hold<=32'b0;
        end
        else if (sel_lane) begin
            data_hold<=wdata;
        end
    end


//================================================================================================
// address hold
//================================================================================================
    always@(posedge hclk or hreset)begin
        if (hreset) begin
            addr_hold<=32'b0;
        end
        else if (clr) begin
            addr_hold<=32'b0;
        end
        else if (gen_addr) begin
            addr_hold<=haddr;
        end
    end

//================================================================================================
// address counter
//================================================================================================
    always@(posedge hclk or posedge hreset)begin
        if (hreset) begin
            addr_count<=5'b0;
        end
        else if (clr) begin
            addr_count<=5'b0;
        end
        else if (addr_count==burst_beats) begin
            addr_count<=5'b0;
        end
        else if (addr_sent && gen_addr) begin
            addr_count<=addr_count+1;
        end
    end


//================================================================================================
// data phase counter
//================================================================================================
    always@(posedge hclk or posedge hreset)begin
        if (hreset) begin
            data_count<=5'b0;
        end
        else if (clr) begin
            data_count<=5'b0;
        end
        else if (data_count==burst_beats) begin
            data_count<=5'b0;
        end
        else if (data_sent && sel_lane) begin
           data_count<=data_count+1; 
        end
    end

//=================================================================================================================
// no. of beats depending on burst
//=================================================================================================================
    always@(*)begin
        if (hreset) begin
            burst_beats=5'b0;
        end
        else begin
        case (req_burst)
            SINGLE,INCR: begin
                burst_beats=1;
            end
            WRAP4,INCR4:begin
                burst_beats=4;
            end
            WRAP8,INCR8:begin
                burst_beats=8;
            end
            WRAP16,INCR16:begin
                burst_beats=16;
            end
            default: begin
                burst_beats=0;
            end
        endcase
        end
    end


//================================================================================================
// size validation / alignment check block (cycle 1)
//================================================================================================
    always@(*)begin
        if (clr) begin
            valid_size=0;
        end
        else if (req_size>2) begin
            valid_size=0;
        end
        else if(check_size)begin
            case (req_size)
                BYTE: begin
                    valid_size=1;
                end
                HALFWORD: begin
                    if (req_addr[0]==1'b0) begin
                        valid_size=1;
                    end
                    else valid_size=0;
                end
                WORD: begin
                    if (req_addr[1:0]==2'b00) begin
                        valid_size=1;
                    end
                    else valid_size=0;
                end
                default: begin
                    valid_size=0;
                end
            endcase
        end
        else begin
            valid_size=0;
        end
    end


//================================================================================================
// Address calculation block (cycle 2)
//================================================================================================
always @(*) begin
    hburst   = 3'b000;
    hsize    = 2'b00;
    hwrite   = 1'b0;
    haddr    = 32'b0;
    incr_addr = 32'b0;
    diff     = 32'b0;
    addr_sent= 0;

    if (!clr && gen_addr) begin
        hburst = req_burst;
        hsize  = req_size;
        hwrite = req_write;
        case (req_burst)
            SINGLE: begin
                haddr = req_addr;
            end
            INCR, INCR4, INCR8, INCR16: begin
                if (init)begin
                    haddr = req_addr;
                    addr_sent=1;
                end
                else if (cont) begin
                    haddr = current_addr + (32'd1 << req_size);
                    addr_sent=1;
                end
            end
            WRAP4, WRAP8, WRAP16: begin
                if (init) begin
                    haddr = req_addr;
                    addr_sent=1;
                end
                else if (cont) begin
                    incr_addr = current_addr + (32'd1 << req_size);
                    diff = incr_addr - base;
                if (diff >= burst_bytes)begin
                    haddr = base;
                    addr_sent=1;
                end
                else begin
                    haddr = incr_addr;
                    addr_sent=1;
                end
            end
        end
            default: begin
                haddr = 32'b0;
                addr_sent=0;
            end
        endcase
    end
    else begin
        haddr=addr_hold;
        addr_sent=0;
    end
end


//================================================================================================
// Sequential address and wrapping registers
//================================================================================================
always @(posedge hclk or posedge hreset) begin
    if (hreset) begin
        current_addr <= 32'b0;
        base         <= 32'b0;
        burst_bytes  <= 32'b0;
    end
    else if (clr) begin
        current_addr <= 32'b0;
        base    <= 32'b0;
        burst_bytes   <= 32'b0;
    end
    else if (gen_addr && (init || cont)) begin
        current_addr <= haddr;
        if (init &&
            (req_burst == WRAP4 ||
             req_burst == WRAP8 ||
             req_burst == WRAP16)) begin
            burst_bytes <= {27'b0, burst_beats} << req_size;
            base <= req_addr & ~(({27'b0, burst_beats} << req_size) - 1'b1);
        end
    end
end

//================================================================================================
// lane selection depending on address (cycle 3)
//================================================================================================
    always@(*)begin
        if (hreset) begin
            hwdata=32'b0;
            data_sent=0;
        end
        else if(sel_lane) begin
            resp_rdata=hrdata;
            case (req_size)
                BYTE:begin
                    case (req_addr[1:0])
                        2'b00:begin
                            hwdata={24'b0,wdata[7:0]};
                            resp_rdata=hrdata;
                            data_sent=1;
                        end
                        2'b01:begin
                            hwdata={16'b0,wdata[7:0],8'b0};
                            resp_rdata=hrdata;
                            data_sent=1;
                        end
                        2'b10:begin
                            hwdata={8'b0,wdata[7:0],16'b0};
                            resp_rdata=hrdata;
                            data_sent=1;
                        end
                        2'b11:begin
                            hwdata={wdata[7:0],24'b0};
                            resp_rdata=hrdata;
                            data_sent=1;
                        end
                        default: begin
                            hwdata=32'bx;
                            data_sent=0;
                            resp_rdata=hrdata;
                        end
                    endcase
                    end
                HALFWORD:begin
                    if (req_addr[1]) begin
                        hwdata={wdata[15:0],16'b0};
                        resp_rdata=hrdata;
                        data_sent=1;
                    end
                    else begin
                        hwdata={16'b0,wdata[15:0]};
                        resp_rdata=hrdata;
                        data_sent=1;
                    end
                    end
                WORD:begin
                    hwdata=wdata;
                    resp_rdata=hrdata;
                    data_sent=1;
                end
                default: begin
                    hwdata=32'bx;
                    resp_rdata=hrdata;
                    data_sent=0;
                end
            endcase
        end
        else begin
            hwdata=data_hold;
            data_sent=0;
        end
    end
endmodule
















