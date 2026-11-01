`timescale 1ns/1ps

module wrap_tb;

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

    localparam WORD   = 2'b10;
    localparam WRAP4  = 3'b010;
    localparam WRAP8  = 3'b100;
    localparam WRAP16 = 3'b110;

    integer errors;
    integer tests;
    integer timeout;
    integer i;
    integer length;

    reg [31:0] start_addr;
    reg [31:0] expected_addr;
    reg [31:0] wrap_base;
    reg [31:0] wrap_bytes;
    reg [31:0] expected_data;
    reg [31:0] expected_rdata;
    reg [31:0] held_addr;
    reg [31:0] held_hwdata;
    reg [1:0] held_htrans;

    reg [2:0] burst;
    reg is_write;

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
        $dumpfile("wrap.vcd");
        $dumpvars(0, wrap_tb);
    end

    //====================================================
    // RESET
    //====================================================
    task do_reset;
        begin
            @(negedge clk);

            reset     = 1'b1;
            req_valid = 1'b0;
            req_write = 1'b0;
            req_addr  = 32'b0;
            req_size  = WORD;
            req_burst = WRAP4;
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
    // WRAP BURST TEST
    //
    // wait_beat  = beat on which to insert two wait cycles
    // error_beat = beat on which to inject an AHB-Lite error
    //
    // Set either argument to zero to disable that test.
    //====================================================
    task wrap_burst_test;
        input is_wr;
        input [31:0] base_addr;
        input [2:0] burst_type;
        input integer burst_length;
        input integer wait_beat;
        input integer error_beat;

        begin
            $display("\n==============================================");
            $display("WRAP%0d %s TEST",
                     burst_length, is_wr ? "WRITE" : "READ");
            $display("Starting address = %h", base_addr);

            if (wait_beat != 0)
                $display("Two wait cycles at beat %0d", wait_beat);

            if (error_beat != 0)
                $display("Error injected at beat %0d", error_beat);

            $display("==============================================");

            start_addr = base_addr;
            length     = burst_length;
            burst      = burst_type;
            is_write   = is_wr;

            // Word transfer: 4 bytes per beat.
            wrap_bytes = burst_length * 4;

            // Align to the wrap boundary.
            wrap_base = start_addr & ~(wrap_bytes - 1);

            @(negedge clk);

            req_valid = 1'b1;
            req_write = is_wr;
            req_addr  = start_addr;
            req_size  = WORD;
            req_burst = burst_type;
            hready    = 1'b1;
            hresp     = 1'b0;
            last_beat = 1'b0;

            wdata  = 32'hA000_0000;
            hrdata = 32'hB000_0000;

            // Allow the controller to launch the burst.
            @(negedge clk);

            for (i = 0; i < burst_length; i = i + 1) begin

                // Calculate expected wrapped address.
                expected_addr =
                    wrap_base |
                    ((start_addr + (i * 4)) & (wrap_bytes - 1));

                // Unique data for each beat.
                expected_data =
                    32'hA000_0000 |
                    (burst_length << 8) |
                    i;

                expected_rdata =
                    32'hB000_0000 |
                    (burst_length << 8) |
                    i;

                wdata  = expected_data;
                hrdata = expected_rdata;

                timeout = 0;

                // Wait for the address phase.
                while ((htrans == 2'b00) && (timeout < 10)) begin
                    @(negedge clk);
                    timeout = timeout + 1;
                end

                #1;
                tests = tests + 1;

                if (timeout >= 10) begin
                    $display("FAIL: Timeout waiting for beat %0d",
                             i + 1);
                    errors = errors + 1;
                end
                else begin

                    // Check wrapped address.
                    if (haddr !== expected_addr) begin
                        $display(
                            "FAIL: Beat %0d HADDR expected=%h actual=%h",
                            i + 1, expected_addr, haddr
                        );
                        errors = errors + 1;
                    end

                    // First beat must be NONSEQ.
                    if (i == 0 && htrans !== 2'b10) begin
                        $display(
                            "FAIL: First beat must be NONSEQ, actual=%b",
                            htrans
                        );
                        errors = errors + 1;
                    end

                    // Remaining beats must be SEQ.
                    if (i > 0 && htrans !== 2'b11) begin
                        $display(
                            "FAIL: Beat %0d must be SEQ, actual=%b",
                            i + 1, htrans
                        );
                        errors = errors + 1;
                    end

                    // Check burst controls.
                    if (hwrite !== is_wr ||
                        hsize  !== WORD ||
                        hburst !== burst_type) begin

                        $display(
                            "FAIL: Control mismatch at beat %0d: HWRITE=%b HSIZE=%b HBURST=%b",
                            i + 1, hwrite, hsize, hburst
                        );
                        errors = errors + 1;
                    end

                    $display(
                        "BEAT %0d: HTRANS=%b HADDR=%h HWRITE=%b",
                        i + 1, htrans, haddr, hwrite
                    );

                    // Accept address phase and inspect data phase.
                    @(posedge clk);
                    #1;

                    if (is_wr) begin

                        if (hwdata !== expected_data) begin
                            $display(
                                "FAIL: Beat %0d HWDATA expected=%h actual=%h",
                                i + 1, expected_data, hwdata
                            );
                            errors = errors + 1;
                        end
                        else begin
                            $display(
                                "PASS: Beat %0d HWDATA=%h",
                                i + 1, hwdata
                            );
                        end

                        if (rd_available !== 1'b0) begin
                            $display(
                                "FAIL: rd_available asserted during WRITE"
                            );
                            errors = errors + 1;
                        end

                    end
                    else begin

                        if (resp_rdata !== expected_rdata) begin
                            $display(
                                "FAIL: Beat %0d RDATA expected=%h actual=%h",
                                i + 1, expected_rdata, resp_rdata
                            );
                            errors = errors + 1;
                        end
                        else begin
                            $display(
                                "PASS: Beat %0d RDATA=%h",
                                i + 1, resp_rdata
                            );
                        end

                        if (rd_available !== 1'b1) begin
                            $display(
                                "FAIL: rd_available should be high during successful READ"
                            );
                            errors = errors + 1;
                        end

                    end

                end

                // Move to the falling edge before driving inputs.
                @(negedge clk);

                //========================================
                // WAIT-STATE TEST
                //========================================
                if ((wait_beat == i + 1) &&
                    (timeout < 10)) begin

                    $display(
                        "\nWAIT TEST: WRAP%0d beat %0d",
                        burst_length, i + 1
                    );

                    // Stall the current data phase.
                    hready = 1'b0;
                    hresp  = 1'b0;

                    // Let combinational outputs settle before
                    // taking the baseline stability values.
                    #1;

                    held_addr  = haddr;
                    held_hwdata = hwdata;
                    held_htrans = htrans;

                    repeat (2) begin
                        @(posedge clk);
                        #1;

                        tests = tests + 1;

                        if (hready !== 1'b0) begin
                            $display("FAIL: HREADY was not held low");
                            errors = errors + 1;
                        end

                        if (haddr !== held_addr) begin
                            $display(
                                "FAIL: HADDR changed during wait: expected=%h actual=%h",
                                held_addr, haddr
                            );
                            errors = errors + 1;
                        end

                        if (hwdata !== held_hwdata) begin
                            $display(
                                "FAIL: HWDATA changed during wait: expected=%h actual=%h",
                                held_hwdata, hwdata
                            );
                            errors = errors + 1;
                        end

                        if (htrans !== held_htrans) begin
                            $display(
                                "FAIL: HTRANS changed during wait: expected=%b actual=%b",
                                held_htrans, htrans
                            );
                            errors = errors + 1;
                        end

                        $display(
                            "WAIT: HREADY=%b HADDR=%h HWDATA=%h HTRANS=%b",
                            hready, haddr, hwdata, htrans
                        );
                    end

                    // Release the stall at a falling edge.
                    @(negedge clk);
                    hready = 1'b1;
                    hresp  = 1'b0;
                    #1;

                    $display("WAIT TEST FINISHED\n");
                end

                //========================================
                // TWO-CYCLE AHB-LITE ERROR TEST
                //========================================
                if ((error_beat == i + 1) &&
                    (timeout < 10)) begin

                    $display(
                        "\nERROR TEST: WRAP%0d beat %0d",
                        burst_length, i + 1
                    );

                    // First error response cycle:
                    // HRESP=1, HREADY=0.
                    hready = 1'b0;
                    hresp  = 1'b1;

                    #1;

                    @(posedge clk);
                    #1;

                    tests = tests + 1;

                    if (ready !== 1'b0) begin
                        $display(
                            "FAIL: READY should be low during first error cycle"
                        );
                        errors = errors + 1;
                    end

                    if (resp_error !== 1'b0) begin
                        $display(
                            "FAIL: resp_error should be low during first error cycle"
                        );
                        errors = errors + 1;
                    end

                    $display(
                        "ERROR CYCLE 1: HREADY=%b HRESP=%b READY=%b RESP_ERROR=%b",
                        hready, hresp, ready, resp_error
                    );

                    // Second error response cycle:
                    // HRESP=1, HREADY=1.
                    @(negedge clk);
                    hready = 1'b1;
                    hresp  = 1'b1;

                    #1;

                    tests = tests + 1;

                    if (ready !== 1'b1 || resp_error !== 1'b1) begin
                        $display(
                            "FAIL: Incorrect second error response: READY=%b RESP_ERROR=%b",
                            ready, resp_error
                        );
                        errors = errors + 1;
                    end
                    else begin
                        $display(
                            "PASS: Two-cycle error response observed"
                        );
                    end

                    $display(
                        "ERROR CYCLE 2: HREADY=%b HRESP=%b READY=%b RESP_ERROR=%b",
                        hready, hresp, ready, resp_error
                    );

                    // Stop the request after the error.
                    req_valid = 1'b0;

                    @(posedge clk);
                    #1;

                    hready = 1'b1;
                    hresp  = 1'b0;

                    // Stop the loop because the burst should abort.
                    i = burst_length - 1;
                end

            end

            req_valid = 1'b0;
            last_beat = 1'b0;
            hready    = 1'b1;
            hresp     = 1'b0;

            repeat (3) @(negedge clk);

            $display(
                "WRAP%0d %s TEST FINISHED",
                burst_length, is_wr ? "WRITE" : "READ"
            );
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
        req_write = 1'b0;
        req_addr  = 0;
        req_size  = WORD;
        req_burst = WRAP4;
        wdata     = 0;
        hrdata    = 0;
        hready    = 1'b1;
        hresp     = 1'b0;
        last_beat = 1'b0;

        do_reset();

        //================================================
        // WRAP4: READ AND WRITE WITH WAIT STATES
        //================================================
        wrap_burst_test(
            1'b1, 32'h0000_1008, WRAP4, 4, 2, 0
        );

        do_reset();

        wrap_burst_test(
            1'b0, 32'h0000_2008, WRAP4, 4, 2, 0
        );

        //================================================
        // WRAP8: READ AND WRITE WITH WAIT STATES
        //================================================
        do_reset();

        wrap_burst_test(
            1'b1, 32'h0000_2018, WRAP8, 8, 2, 0
        );

        do_reset();

        wrap_burst_test(
            1'b0, 32'h0000_3018, WRAP8, 8, 2, 0
        );

        //================================================
        // WRAP16: READ AND WRITE WITH WAIT STATES
        //================================================
        do_reset();

        wrap_burst_test(
            1'b1, 32'h0000_503C, WRAP16, 16, 2, 0
        );

        do_reset();

        wrap_burst_test(
            1'b0, 32'h0000_603C, WRAP16, 16, 2, 0
        );

        //================================================
        // WRAP4: READ AND WRITE WITH ERRORS
        //================================================
        do_reset();

        wrap_burst_test(
            1'b1, 32'h0000_1008, WRAP4, 4, 0, 3
        );

        do_reset();

        wrap_burst_test(
            1'b0, 32'h0000_2008, WRAP4, 4, 0, 3
        );

        //================================================
        // WRAP8: READ AND WRITE WITH ERRORS
        //================================================
        do_reset();

        wrap_burst_test(
            1'b1, 32'h0000_2018, WRAP8, 8, 0, 3
        );

        do_reset();

        wrap_burst_test(
            1'b0, 32'h0000_3018, WRAP8, 8, 0, 3
        );

        //================================================
        // WRAP16: READ AND WRITE WITH ERRORS
        //================================================
        do_reset();

        wrap_burst_test(
            1'b1, 32'h0000_503C, WRAP16, 16, 0, 3
        );

        do_reset();

        wrap_burst_test(
            1'b0, 32'h0000_603C, WRAP16, 16, 0, 3
        );

        //================================================
        // FINAL RESULT
        //================================================
        $display("\n==============================================");
        $display("FINAL RESULT");
        $display("Checks executed: %0d", tests);
        $display("Errors: %0d", errors);

        if (errors == 0)
            $display("ALL CHECKS PASSED");
        else
            $display("TEST FAILURES FOUND - INSPECT RTL AND WAVEFORM");

        $finish;
    end

endmodule
