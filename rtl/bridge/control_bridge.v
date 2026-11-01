//==============================================================================
// Module Name : control_bridge
// Project     : AHB to APB Bridge
// Author      : Ansh Shinde
//
// Description :
//
// Control path of the AHB-to-APB bridge. This module implements the
// bridge finite state machine (FSM), generates APB control signals,
// manages AHB handshaking, and handles error responses.
//
// The FSM monitors incoming AHB transactions, validates transfers,
// initiates APB setup/access phases, and generates appropriate AHB
// response signals.
//
// Features:
// - AHB transaction monitoring
// - APB setup and access phase generation
// - AHB ready/response generation
// - Write and read transaction support
// - Error handling through PSLVERR propagation
// - FSM-based control path implementation
//
// FSM States:
// - IDLE    : Wait for valid AHB transfer
// - SETUP_W : APB write setup phase
// - SETUP_R : APB read setup phase
// - ACCESS  : APB access phase
// - ERROR   : Error response generation
//
// Notes:
// - Transaction type is stored internally to maintain stable control
//   signals throughout the APB access phase.
// - Supports both read and write transfers.
// - Invalid transfers generate AHB error responses.
//
//==============================================================================
module control_apb(
    input           hclk,
    input           hreset,
    input           hselb,
    input           hwrite,
    input           hwrite_reg,
    input           valid,
    input           pready,
    input           pslverr,
    input           valid_addr,
    input           valid_size,
    output  reg     en_psel,
    output  reg     pw_addr_data,
    output  reg     pr_addr,
    output  reg     penable,
    output  reg     hready,
    output  reg     hresp,
    output  reg     pwrite
);

    parameter IDLE=3'b000, 
              SETUP_W=3'b001,
              SETUP_R=3'b010, 
              ACCESS=3'b011, 
              ERROR=3'b100;
    
    reg [2:0]ns,ps;



//================================================================================
// next state assignment block
//================================================================================
    
    always@(posedge hclk or posedge hreset)begin
        if (hreset) begin
            ps<=3'b0;
        end
        else if (hselb) begin
            ps<=ns;
        end
    end


//=================================================================================
// next state calculation block
// ================================================================================

    always@(*)begin
        case (ps)
            IDLE: begin
                if (valid) begin
                    if (hwrite) begin  
                        ns=SETUP_W;
                    end
                    else begin
                        ns=SETUP_R;
                    end
                end
                else begin
                    ns=IDLE;
                end
            end
            SETUP_W: begin
                ns=ACCESS;
            end
            SETUP_R: begin
                ns=ACCESS;
            end
            ACCESS: begin
                if (pslverr) begin
                    ns=ERROR;
                end
                else if (pready) begin
                    ns=IDLE;
                end
                else begin
                    ns=ACCESS;
                end
            end
            ERROR: begin
                ns=IDLE;
            end
            default: begin
                ns=IDLE;
            end
        endcase
    end

//==================================================================================
// Signal generation depending on present state
// =================================================================================

    always@(*)begin
        hready=1;
        hresp=0;
        pw_addr_data=0;
        pr_addr=0;
        en_psel=0;
        penable=0;
        pwrite=0;
        case (ps)
            IDLE: begin
                if (valid) begin
                    hresp=0;
                    pw_addr_data=0;
                    pr_addr=0;
                    en_psel=0;
                    penable=0;
                    pwrite=0;
                   if (hwrite_reg) begin    
                       hready=1;            
                   end                      
                   else begin                 
                       hready=0;          
                   end
                end
                else begin
                    hready=1;
                    pw_addr_data=0;
                    pr_addr=0;
                    en_psel=0;
                    penable=0;
                    pwrite=0;
                    if (!(valid_size) || !(valid_addr)) begin
                        hresp=1;
                    end
                    else begin
                        hresp=0;
                    end
                end
            end
            SETUP_W: begin
                pw_addr_data=0;
                pwrite=1;
                en_psel=1;
                hready=0;
                hresp=0;
                pr_addr=0;
                penable=0;
            end
            SETUP_R: begin
                pw_addr_data=0;
                pwrite=0;
                en_psel=1;
                hready=0;
                hresp=0;
                pr_addr=1;
                penable=0;
            end
            ACCESS: begin
                en_psel=1;
                penable=1;
                if (hwrite_reg) begin
                    pw_addr_data=1;
                    pwrite=1;
                    pr_addr=0;
                end
                else begin
                    pr_addr=1;
                    pwrite=0;
                    pw_addr_data=0;
                end
                if (pslverr) begin
                    hresp=1;
                    hready=0;
                end
                else if (pready) begin
                    hresp=0;
                    hready=1;
                end
                else begin
                    hresp=0;
                    hready=0;
                end
            end
            ERROR: begin
                hresp=1;
                hready=1;
            end
            
            default: begin
                hready=1;
                hresp=0;
                pw_addr_data=0;
                pr_addr=0;
                en_psel=0;
                penable=0;
                pwrite=0;
            end
        endcase
    end
endmodule
