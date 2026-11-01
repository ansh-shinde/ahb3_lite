
`timescale 1ns/1ps

module single_trans_tb;

    reg clk, reset;
    reg req_valid, last_beat, req_write;
    reg [31:0] req_addr;
    reg [1:0] req_size;
    reg [2:0] req_burst;
    reg [31:0] wdata, hrdata;
    reg hready, hresp;

    wire [31:0] resp_rdata;
    wire hwrite, nxt_beat, rd_available, resp_error, ready;
    wire [1:0] htrans, hsize;
    wire [31:0] haddr, hwdata;
    wire [2:0] hburst;

    localparam BYTE     = 2'b00;
    localparam HALFWORD = 2'b01;
    localparam WORD     = 2'b10;
    localparam RESERVED = 2'b11;
    localparam SINGLE   = 3'b000;

    integer errors;
    integer tests;
    integer timeout;
    integer errors_before;

    //====================================================
    // DUT
    //====================================================
    top dut (
        .clk(clk),
        .reset(reset),
        .req_valid(req_valid),
        .last_beat(last_beat),
        .req_write(req_write),
        .req_addr(req_addr),
        .req_size(req_size),
        .req_burst(req_burst),
        .wdata(wdata),
        .hrdata(hrdata),
        .hready(hready),
        .hresp(hresp),
        .resp_rdata(resp_rdata),
        .hwrite(hwrite),
        .nxt_beat(nxt_beat),
        .rd_available(rd_available),
        .resp_error(resp_error),
        .ready(ready),
        .htrans(htrans),
        .haddr(haddr),
        .hsize(hsize),
        .hburst(hburst),
        .hwdata(hwdata)
    );

    //====================================================
    // CLOCK
    //====================================================
    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    //====================================================
    // WAVEFORM
    //====================================================
    initial begin
        $dumpfile("single_trans.vcd");
        $dumpvars(0, single_trans_tb);
    end

    //====================================================
    // RESET
    //====================================================
    task do_reset;
        begin
            @(negedge clk);

            reset     = 1'b1;
            req_valid = 1'b0;
            req_write = 1'b1;
            req_addr  = 32'b0;
            req_size  = WORD;
            req_burst = SINGLE;
            wdata     = 32'b0;
            hrdata    = 32'b0;
            hready    = 1'b1;
            hresp     = 1'b0;
            last_beat = 1'b0;

            repeat (3) @(negedge clk);

            reset = 1'b0;

            repeat (2) @(negedge clk);
        end
    endtask

    //====================================================
    // WAIT FOR SINGLE ADDRESS PHASE
    //====================================================
    task wait_address;
        input [31:0] addr;
        input is_write;

        begin
            timeout = 0;

            while ((htrans !== 2'b10) && (timeout < 10)) begin
                @(negedge clk);
                timeout = timeout + 1;
            end

            #1;

            if (htrans !== 2'b10) begin
                $display("FAIL: Address timeout addr=%h", addr);
                errors = errors + 1;
            end
            else begin
                if (haddr !== addr) begin
                    $display("FAIL: haddr expected=%h actual=%h",
                             addr, haddr);
                    errors = errors + 1;
                end

                if (hwrite !== is_write) begin
                    $display("FAIL: hwrite expected=%b actual=%b",
                             is_write, hwrite);
                    errors = errors + 1;
                end

                if (hburst !== SINGLE) begin
                    $display("FAIL: hburst expected SINGLE actual=%b",
                             hburst);
                    errors = errors + 1;
                end
            end
        end
    endtask

    //====================================================
    // NORMAL SINGLE READ OR WRITE
    //====================================================
    task valid_transfer;
        input is_write;
        input [31:0] addr;
        input [1:0] size;
        input [31:0] write_data;
        input [31:0] read_data;
        input [31:0] expected_hwdata;
        input [31:0] expected_rdata;

        begin
            errors_before = errors;

            @(negedge clk);

            req_valid = 1'b1;
            req_write = is_write;
            req_addr  = addr;
            req_size  = size;
            req_burst = SINGLE;
            wdata     = write_data;
            hrdata    = read_data;
            hready    = 1'b1;
            hresp     = 1'b0;
            last_beat = 1'b0;

            wait_address(addr, is_write);

            tests = tests + 1;

            if (htrans === 2'b10) begin

                if (hsize !== size) begin
                    $display("FAIL: hsize expected=%b actual=%b",
                             size, hsize);
                    errors = errors + 1;
                end

                // Address phase is accepted on this rising edge.
                @(posedge clk);
                #1;

                // SINGLE_DATA state: check the actual data phase.
                if (ready !== 1'b1) begin
                    $display("FAIL: ready expected 1 actual=%b", ready);
                    errors = errors + 1;
                end

                if (resp_error !== 1'b0) begin
                    $display("FAIL: Unexpected resp_error");
                    errors = errors + 1;
                end

                if (is_write) begin
                    if (hwdata !== expected_hwdata) begin
                        $display("FAIL: WRITE data expected=%h actual=%h",
                                 expected_hwdata, hwdata);
                        errors = errors + 1;
                    end

                    if (rd_available !== 1'b0) begin
                        $display("FAIL: rd_available on WRITE");
                        errors = errors + 1;
                    end
                end
                else begin
                    if (resp_rdata !== expected_rdata) begin
                        $display("FAIL: READ data expected=%h actual=%h",
                                 expected_rdata, resp_rdata);
                        errors = errors + 1;
                    end

                    if (rd_available !== 1'b1) begin
                        $display("FAIL: rd_available should be 1 during successful READ");
                        errors = errors + 1;
                    end
                end
            end

            if (errors == errors_before) begin
                if (is_write)
                    $display("PASS: WRITE addr=%h size=%b data=%h",
                             addr, size, hwdata);
                else
                    $display("PASS: READ addr=%h size=%b data=%h",
                             addr, size, resp_rdata);
            end

            // Drop request before the next rising edge.
            @(negedge clk);
            req_valid = 1'b0;

            repeat (2) @(negedge clk);
        end
    endtask

    //====================================================
    // INVALID SIZE OR ALIGNMENT
    //====================================================
    task invalid_transfer;
        input is_write;
        input [31:0] addr;
        input [1:0] size;

        begin
            @(negedge clk);

            req_valid = 1'b1;
            req_write = is_write;
            req_addr  = addr;
            req_size  = size;
            req_burst = SINGLE;
            wdata     = 32'hA5A5_1234;
            hrdata    = 32'hDEAD_BEEF;
            hready    = 1'b1;
            hresp     = 1'b0;
            last_beat = 1'b0;

            #1;
            tests = tests + 1;

            if (resp_error !== 1'b1) begin
                $display("FAIL: Invalid %s not rejected addr=%h size=%b",
                         is_write ? "WRITE" : "READ", addr, size);
                errors = errors + 1;
            end
            else if (htrans !== 2'b00) begin
                $display("FAIL: Invalid request generated transfer");
                errors = errors + 1;
            end
            else begin
                $display("PASS: Invalid %s rejected addr=%h size=%b",
                         is_write ? "WRITE" : "READ", addr, size);
            end

            repeat (2) begin
                @(posedge clk);
                #1;

                if (htrans !== 2'b00) begin
                    $display("FAIL: Invalid request started a transfer");
                    errors = errors + 1;
                end
            end

            @(negedge clk);
            req_valid = 1'b0;

            repeat (2) @(negedge clk);
        end
    endtask

    //====================================================
    // ADDRESS-PHASE WAIT-STATE TEST
    //
    // The master must hold address/control stable when
    // HREADY is low and the address phase is stalled.
    //====================================================
    task address_wait_test;
        input is_write;
        input [31:0] addr;
        input [1:0] size;

        integer i;

        begin
            $display("\n--- ADDRESS WAIT TEST: %s ---",
                     is_write ? "WRITE" : "READ");

            @(negedge clk);

            req_valid = 1'b1;
            req_write = is_write;
            req_addr  = addr;
            req_size  = size;
            req_burst = SINGLE;
            wdata     = 32'h1234_ABCD;
            hrdata    = 32'hCAFE_BABE;
            hready    = 1'b1;
            hresp     = 1'b0;
            last_beat = 1'b0;

            wait_address(addr, is_write);
            tests = tests + 1;

            if (htrans === 2'b10) begin

                // Stall the address phase before its
                // accepting rising edge.
                // Assert HREADY low immediately, without #1.
                @(posedge clk);
                hready = 1'b0;
                hresp  = 1'b0;

                for (i = 0; i < 2; i = i + 1) begin
                    if (htrans !== 2'b10) begin
                        $display("FAIL: HTRANS not held NONSEQ during address stall");
                        errors = errors + 1;
                    end

                    if (haddr !== addr) begin
                        $display("FAIL: HADDR changed during stall expected=%h actual=%h",
                                 addr, haddr);
                        errors = errors + 1;
                    end

                    if (hsize !== size || hwrite !== is_write) begin
                        $display("FAIL: Address control changed during stall");
                        errors = errors + 1;
                    end

                    @(posedge clk);
                    #1;
                end

                if (htrans !== 2'b10 || haddr !== addr) begin
                    $display("FAIL: Address phase not restored after releasing HREADY");
                    errors = errors + 1;
                end
                // Release the stalled address phase.
                @(posedge clk);
                hready = 1'b1;
                #1;

                // Accept address and inspect data phase.

                if (is_write && hwdata !== 32'h1234_ABCD) begin
                    $display("FAIL: Write data wrong after address stall actual=%h", hwdata);
                    errors = errors + 1;
                end

                if (!is_write && rd_available !== 1'b1) begin
                    $display("FAIL: Read data not available after address stall");
                    errors = errors + 1;
                end
            end

            @(negedge clk);
            req_valid = 1'b0;
            hready = 1'b1;
            hresp = 1'b0;

            repeat (2) @(negedge clk);
        end
    endtask 

    //====================================================
    // DATA-PHASE WAIT-STATE TEST
    //
    // HREADY low must stall completion. Write data must
    // remain stable. Read data must not be marked valid
    // until the successful completion cycle.
    //====================================================
    task data_wait_test;
        input is_write;
        input [31:0] addr;
        input [1:0] size;
        input [31:0] write_data;
        input [31:0] read_data;
        input [31:0] expected_hwdata;

        integer i;

        begin
            $display("\n--- DATA WAIT TEST: %s ---",
                     is_write ? "WRITE" : "READ");

            @(negedge clk);

            req_valid = 1'b1;
            req_write = is_write;
            req_addr  = addr;
            req_size  = size;
            req_burst = SINGLE;
            wdata     = write_data;
            hrdata    = read_data;
            hready    = 1'b1;
            hresp     = 1'b0;
            last_beat = 1'b0;

            wait_address(addr, is_write);
            tests = tests + 1;

            if (htrans === 2'b10) begin
                // Address phase accepted; enter data phase.
                // Wait until the falling edge to apply the
                // data-phase stall before the next rising edge.
                @(posedge clk);
                hready = 1'b0;
                hresp  = 1'b0;

                for (i = 0; i < 2; i = i + 1) begin
                    if (ready !== 1'b0) begin
                        $display("FAIL: ready should be low during data wait");
                        errors = errors + 1;
                    end

                    if (is_write) begin
                        #1;
                        if (hwdata !== expected_hwdata) begin
                            $display("FAIL: Write data changed during wait expected=%h actual=%h",
                                     expected_hwdata, hwdata);
                            errors = errors + 1;
                        end
                    end
                    else begin
                        if (rd_available !== 1'b0) begin
                            $display("FAIL: rd_available asserted during read wait");
                            errors = errors + 1;
                        end
                        #1;
                        // Current RTL passes hrdata through even
                        // during a wait. Check stability only.
                        if (resp_rdata !== read_data) begin
                            $display("FAIL: Read data changed during wait");
                            errors = errors + 1;
                        end
                    end

                    @(posedge clk);
                    #1;
                end

                // Complete the data phase successfully.
                @(posedge clk);
                hready = 1'b1;
                hresp  = 1'b0;
                #1;

                if (ready !== 1'b1) begin
                    $display("FAIL: ready not asserted when HREADY returns high");
                    errors = errors + 1;
                end

                if (is_write) begin
                    if (hwdata !== expected_hwdata) begin
                        $display("FAIL: Write data wrong at completion");
                        errors = errors + 1;
                    end
                end
                else begin
                    if (rd_available !== 1'b1) begin
                        $display("FAIL: rd_available not asserted on successful completion");
                        errors = errors + 1;
                    end

                    if (resp_rdata !== read_data) begin
                        $display("FAIL: Read data wrong at completion");
                        errors = errors + 1;
                    end
                end
            end

            // Drop request before next rising edge.
            req_valid = 1'b0;

            @(posedge clk);
            #1;

            hready = 1'b1;
            hresp = 1'b0;

            repeat (2) @(negedge clk);

            if (errors == 0)
                $display("PASS: Data wait test completed");
        end
    endtask

    //====================================================
    // TWO-CYCLE AHB-LITE ERROR RESPONSE
    //
    // Cycle 1: HRESP=1, HREADY=0
    // Cycle 2: HRESP=1, HREADY=1
    //====================================================
    task error_response_test;
        input is_write;
        input [31:0] addr;
        input [1:0] size;

        begin
            $display("\n--- ERROR RESPONSE TEST: %s ---",
                     is_write ? "WRITE" : "READ");

            @(negedge clk);

            req_valid = 1'b1;
            req_write = is_write;
            req_addr  = addr;
            req_size  = size;
            req_burst = SINGLE;
            wdata     = 32'h1234_ABCD;
            hrdata    = 32'hCAFE_BABE;
            hready    = 1'b1;
            hresp     = 1'b0;
            last_beat = 1'b0;

            wait_address(addr, is_write);
            tests = tests + 1;

            if (htrans === 2'b10) begin
                // Accept address; enter data phase.
                @(posedge clk);

                // First error-response cycle.
                hready = 1'b0;
                hresp  = 1'b1;
                #1;

                if (ready !== 1'b0) begin
                    $display("FAIL: ready should be low during first error cycle");
                    errors = errors + 1;
                end

                if (resp_error !== 1'b0) begin
                    $display("FAIL: resp_error asserted too early");
                    errors = errors + 1;
                end

                // At this rising edge, controller should
                // move from SINGLE_DATA to ERROR.
                @(posedge clk);
                #1;

                if (ready !== 1'b0 || resp_error !== 1'b0) begin
                    $display("FAIL: Incorrect first ERROR-state cycle");
                    errors = errors + 1;
                end

                // Second error-response cycle.
                @(negedge clk);
                hready = 1'b1;
                hresp  = 1'b1;
                #1;

                if (resp_error !== 1'b1) begin
                    $display("FAIL: resp_error not asserted in second error cycle");
                    errors = errors + 1;
                end

                if (ready !== 1'b1) begin
                    $display("FAIL: ready should be high in second error cycle");
                    errors = errors + 1;
                end

                // Remove request before controller returns to IDLE.
                req_valid = 1'b0;

                @(posedge clk);
                #1;

                hresp  = 1'b0;
                hready = 1'b1;

                if (resp_error !== 1'b0) begin
                    $display("FAIL: resp_error did not clear after error completion");
                    errors = errors + 1;
                end
                else begin
                    $display("PASS: Two-cycle error response handled for %s",
                             is_write ? "WRITE" : "READ");
                end
            end

            repeat (2) @(negedge clk);
        end
    endtask

    //====================================================
    // MAIN TEST SEQUENCE
    //====================================================
    initial begin
        errors = 0;
        tests  = 0;

        reset     = 1'b1;
        req_valid = 1'b0;
        req_write = 1'b1;
        req_addr  = 0;
        req_size  = WORD;
        req_burst = SINGLE;
        wdata     = 0;
        hrdata    = 0;
        hready    = 1'b1;
        hresp     = 1'b0;
        last_beat = 1'b0;

        do_reset();

        //================================================
        // ORIGINAL VALID WRITE TESTS
        //================================================
        $display("\n===== SINGLE BYTE WRITES =====");

        valid_transfer(1'b1, 32'h1000, BYTE,
            32'h1122_33D4, 32'h0,
            32'h0000_00D4, 32'h0);

        valid_transfer(1'b1, 32'h1001, BYTE,
            32'h2233_44C3, 32'h0,
            32'h0000_C300, 32'h0);

        valid_transfer(1'b1, 32'h1002, BYTE,
            32'h3344_55B2, 32'h0,
            32'h00B2_0000, 32'h0);

        valid_transfer(1'b1, 32'h1003, BYTE,
            32'h4455_66A1, 32'h0,
            32'hA100_0000, 32'h0);

        $display("\n===== SINGLE HALFWORD WRITES =====");

        valid_transfer(1'b1, 32'h2000, HALFWORD,
            32'h5566_7788, 32'h0,
            32'h0000_7788, 32'h0);

        valid_transfer(1'b1, 32'h2002, HALFWORD,
            32'h6677_8899, 32'h0,
            32'h8899_0000, 32'h0);

        $display("\n===== SINGLE WORD WRITE =====");

        valid_transfer(1'b1, 32'h3000, WORD,
            32'h89AB_CDEF, 32'h0,
            32'h89AB_CDEF, 32'h0);

        //================================================
        // ORIGINAL VALID READ TESTS
        //================================================
        $display("\n===== SINGLE BYTE READS =====");

        valid_transfer(1'b0, 32'h5000, BYTE,
            32'h0, 32'h1234_5678, 32'h0, 32'h1234_5678);

        valid_transfer(1'b0, 32'h5001, BYTE,
            32'h0, 32'h89AB_CDEF, 32'h0, 32'h89AB_CDEF);

        valid_transfer(1'b0, 32'h5002, BYTE,
            32'h0, 32'hDEAD_BEEF, 32'h0, 32'hDEAD_BEEF);

        valid_transfer(1'b0, 32'h5003, BYTE,
            32'h0, 32'hCAFE_BABE, 32'h0, 32'hCAFE_BABE);

        $display("\n===== SINGLE HALFWORD READS =====");

        valid_transfer(1'b0, 32'h6000, HALFWORD,
            32'h0, 32'h1234_5678, 32'h0, 32'h1234_5678);

        valid_transfer(1'b0, 32'h6002, HALFWORD,
            32'h0, 32'h89AB_CDEF, 32'h0, 32'h89AB_CDEF);

        $display("\n===== SINGLE WORD READ =====");

        valid_transfer(1'b0, 32'h7000, WORD,
            32'h0, 32'hDEAD_BEEF, 32'h0, 32'hDEAD_BEEF);

        //================================================
        // INVALID HALFWORD ALIGNMENTS
        //================================================
        $display("\n===== INVALID HALFWORD ALIGNMENTS =====");

        invalid_transfer(1'b1, 32'h2001, HALFWORD);
        invalid_transfer(1'b1, 32'h2003, HALFWORD);
        invalid_transfer(1'b0, 32'h6001, HALFWORD);
        invalid_transfer(1'b0, 32'h6003, HALFWORD);

        //================================================
        // INVALID WORD ALIGNMENTS
        //================================================
        $display("\n===== INVALID WORD ALIGNMENTS =====");

        invalid_transfer(1'b1, 32'h3001, WORD);
        invalid_transfer(1'b1, 32'h3002, WORD);
        invalid_transfer(1'b1, 32'h3003, WORD);

        invalid_transfer(1'b0, 32'h7001, WORD);
        invalid_transfer(1'b0, 32'h7002, WORD);
        invalid_transfer(1'b0, 32'h7003, WORD);

        //================================================
        // RESERVED SIZE
        //================================================
        $display("\n===== RESERVED SIZE =====");

        invalid_transfer(1'b1, 32'h4000, RESERVED);
        invalid_transfer(1'b0, 32'h8000, RESERVED);

        //================================================
        // DATA-PHASE WAIT STATES
        //================================================
        data_wait_test(1'b1, 32'h9000, WORD,
                       32'h1234_ABCD, 32'h0,
                       32'h1234_ABCD);

        data_wait_test(1'b0, 32'h9004, WORD,
                       32'h0, 32'hCAFE_BABE,
                       32'h0);

        //================================================
        // ADDRESS-PHASE WAIT STATES
        //================================================
        address_wait_test(1'b1, 32'hA000, WORD);
        address_wait_test(1'b0, 32'hA004, WORD);

        //================================================
        // TWO-CYCLE ERROR RESPONSES
        //================================================
        error_response_test(1'b1, 32'hB000, WORD);
        error_response_test(1'b0, 32'hB004, WORD);

        //================================================
        // FINAL RESULT
        //================================================
        $display("\n===== FINAL RESULT =====");
        $display("Tests executed: %0d", tests);
        $display("Errors:         %0d", errors);

        if (errors == 0)
            $display("ALL TESTS PASSED");
        else
            $display("SOME TESTS FAILED - CHECK RTL AND WAVEFORM");

        $finish;
    end
endmodule

