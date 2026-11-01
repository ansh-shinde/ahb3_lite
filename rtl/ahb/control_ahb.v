//================================================================================================
// Module Name : control_ahb
// Project     : AHB Lite Master
// Author      : Ansh Shinde
//
// Description :
//
// Control path of the AHB Lite master. This module implements the
// finite state machine (FSM) responsible for controlling AHB
// transactions, address phases, data phases, and burst transfers.
//
// It receives transaction status and request information and
// generates the required control signals for the AHB datapath
// and the AHB interface.
//
// Features:
// - Finite State Machine (FSM) based control
// - Single transfer handling
// - Burst transfer handling
// - Address and data phase sequencing
// - AHB ready and next-beat indication
// - Transfer size validation control
// - Read data availability indication
// - Error response handling
// - Burst completion detection
//
// Supported States:
// - IDLE
// - SINGLE_ADDR
// - BURST_ADDR
// - SINGLE_DATA
// - BURST_DATA
// - ERROR
//
// Supported Burst Types:
// - SINGLE
// - INCR
// - WRAP4 / INC4
// - WRAP8 / INC8
// - WRAP16 / INC16
//
// Notes:
// - The FSM transitions between states based on requests,
//   transfer validity, HREADY, and HRESP.
// - SINGLE_ADDR and BURST_ADDR control the AHB address phase.
// - SINGLE_DATA and BURST_DATA control the data phase.
// - Burst completion is determined using the data phase counter
//   and the configured number of burst beats.
// - The gen_addr, init, and cont signals control datapath operation.
// - The sel_lane signal controls write-data lane selection.
// - Invalid transfer sizes generate a response error.
// - The ERROR state handles AHB error response completion.
//
//================================================================================================
module control_ahb(
    input            hclk,
    input            hreset,
    input            hready,
    input            hresp,
    input            req_valid,
    input            req_write,
    input      [2:0] req_burst,
    input            last_beat,
    input            valid_size,
    input      [4:0] data_count,
    input      [4:0] addr_count,
    input      [4:0] burst_beats,
    output reg       init,
    output reg       cont,
    output           clr,
    output reg       check_size,
    output reg       gen_addr,
    output reg       sel_lane,
    output reg [1:0] htrans,
    output reg       ready, // when =1 master is ready for new transaction
    output reg       nxt_beat, // when =1 master is ready for next beat in current transaction
    output reg       rd_available, // used to indicate rd data is available
    output reg       hselb,
    output reg       resp_error
);

    localparam IDLE        = 3'b000, 
               SINGLE_ADDR = 3'b001, 
               BURST_ADDR  = 3'b010, 
               SINGLE_DATA = 3'b011, 
               BURST_DATA  = 3'b100,
               ERROR       = 3'b101;

    localparam SINGLE=3'b000, 
               INCR  =3'b001, 
               WRAP4 =3'b010, 
               INC4  =3'b011, 
               WRAP8 =3'b100, 
               INC8  =3'b101, 
               WRAP16=3'b110,
               INC16 =3'b111;

    reg [2:0]ns,ps;
    reg burst_complete,clr_control;

    assign clr = hreset | clr_control;

    always@(posedge hclk or posedge hreset)begin
        if (hreset) begin
            burst_complete<=0;
        end
        else if (clr) begin
            burst_complete<=0;
        end
        else if (data_count==(burst_beats-1)) begin
            burst_complete<=1;
        end
    end

//=================================================================================================================
// present state assignment
//=================================================================================================================
    always@(posedge hclk or posedge hreset)begin
        if (hreset) begin
            ps<=0;
        end
        else ps<=ns;
    end

//=================================================================================================================
// next state calculation block
//=================================================================================================================
    always@(*)begin
        case (ps)
            IDLE:begin
                if (req_valid && valid_size) begin
                    if (req_burst==3'b0) begin
                        ns=SINGLE_ADDR;
                    end
                    else begin
                        ns=BURST_ADDR;
                    end
                end
                else begin
                    ns=IDLE;
                end
            end
            SINGLE_ADDR:begin
                ns=SINGLE_DATA;
            end
            BURST_ADDR:begin
                if (hready) begin
                    ns=BURST_DATA;
                end
                else begin
                    ns=BURST_ADDR;
                end
            end
            SINGLE_DATA:begin
                if (hresp && !hready) begin
                    ns=ERROR;
                end
                else if (hready && !hresp) begin
                    ns=IDLE;
                end
                else begin
                    ns=SINGLE_DATA;
                end
            end
            BURST_DATA:begin
                if (!hready && hresp) begin
                    ns=ERROR;
                end
                else if (hready && !hresp) begin
                    if (req_burst==INCR) begin
                        if (last_beat) begin
                            ns=IDLE;
                        end
                        else begin
                            ns=BURST_DATA;
                        end
                    end
                    else begin
                        if (burst_complete) begin
                            ns=IDLE;
                        end
                        else begin
                            ns=BURST_DATA;
                        end
                    end
                end
                else begin
                    ns=BURST_DATA;
                end
            end
            ERROR:begin
                if (hready) begin
                    ns=IDLE;
                end
                else begin
                    ns=ERROR;
                end
            end
            default: begin
                ns=IDLE;
            end
        endcase
    end 


//=================================================================================================================
// signal generation block
//=================================================================================================================
    always@(*)begin
        htrans=2'b00;
        ready=1;
        nxt_beat=0;
        clr_control=0;
        resp_error=0;
        gen_addr=0;
        init=0;
        cont=0;
        check_size=0;
        rd_available=0;
        sel_lane=0;
        hselb=0;
        case (ps)
            IDLE: begin
                htrans=2'b0;
                check_size=1;
                sel_lane=0;
                gen_addr=0;
                if (req_valid && valid_size) begin
                    ready=0;
                    resp_error=0;
                    nxt_beat=0;
                end
                else if (req_valid && !valid_size) begin
                    ready=1;
                    nxt_beat=1;
                    resp_error=1;
                end
                else begin
                    ready=1;
                    nxt_beat=1;
                    resp_error=0;
                end
            end
            SINGLE_ADDR:begin
                ready=0;
                nxt_beat=0;
                gen_addr=1;
                sel_lane=0;
                htrans=2'b10;
                hselb=1;
            end
            BURST_ADDR:begin
                ready=0;
                sel_lane=0;
                hselb=1;
                if(hready)begin
                    gen_addr=1;
                    if (addr_count==5'b0) begin
                        init=1;
                        cont=0;
                        htrans=2'b10;
                    end
                    else begin
                        cont=1;
                        init=0;
                        htrans=2'b11;
                    end
                end
                else begin
                    if (addr_count==5'b0) begin
                        init=1;
                        cont=0;
                        htrans=2'b10;
                        gen_addr=1;
                    end
                    else begin
                        cont=1;
                        init=0;
                        gen_addr=0;
                        htrans=2'b11;
                    end
                end
            end
            SINGLE_DATA:begin
                sel_lane=1;
                gen_addr=1;
                hselb=1;
                if (hready && !hresp) begin
                    htrans=2'b0;
                    ready=1;
                    if (req_write) begin
                        rd_available=0;
                    end
                    else begin
                        rd_available=1;
                    end
                end
                else begin
                    rd_available=0;
                    htrans=2'b10;
                    ready=0;
                end
            end
            BURST_DATA:begin
                ready=0;
                hselb=1;
                if (!burst_complete) begin
                   if (!hready) begin
                       gen_addr=0;
                       rd_available=0;
                       if (addr_count==5'b0) begin
                           htrans=2'b10;
                           init=1;
                           cont=0;
                       end
                       else if(addr_count<=(burst_beats-1))begin
                           htrans=2'b11;
                           cont=1;
                           init=0;
                       end
                       else begin
                           htrans=2'b0;
                           init=0;
                           cont=0;
                       end
                       if (data_count==5'b0) begin
                           sel_lane=1;
                       end
                       else begin
                           sel_lane=0;
                       end
                   end
                   else begin
                       gen_addr=1;
                       sel_lane=1;
                       if (!req_write) begin
                           rd_available=1;
                       end
                       else begin
                           rd_available=0;
                       end
                       if (addr_count==5'b0) begin
                           htrans=2'b10;
                           init=1;
                           cont=0;
                       end
                       else if(addr_count<=(burst_beats-1))begin
                           htrans=2'b11;
                           cont=1;
                           init=0;
                       end
                       else begin
                           htrans=2'b0;
                           init=0;
                           cont=0;
                       end
                   end
               end
               else begin
                   gen_addr=0;
                   sel_lane=0;
                   htrans=2'b0;
                   clr_control=1;
               end
            end
            ERROR:begin
                hselb=1;
                if (hready) begin
                    resp_error=1;
                    nxt_beat=1;
                    ready=1;
                    clr_control=1;
                end
                else begin
                    resp_error=0;
                    nxt_beat=0;
                    ready=0;
                    clr_control=0;
                end
            end
            default: begin
                htrans=2'b00;
                ready=0;
                nxt_beat=0;
                clr_control=0;
                resp_error=0;
                rd_available=0;
                sel_lane=0;
            end
        endcase
    end

endmodule
