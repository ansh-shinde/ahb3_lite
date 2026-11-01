`timescale 1ns/1ps

module incr_tb;

    reg clk, reset;
    reg req_valid, last_beat, req_write;
    reg [31:0] req_addr, wdata, hrdata;
    reg [1:0] req_size;
    reg [2:0] req_burst;
    reg hready, hresp;

    wire [31:0] resp_rdata, haddr, hwdata;
    wire [1:0] htrans, hsize;
    wire [2:0] hburst;
    wire hwrite, nxt_beat, rd_available, resp_error, ready;

    localparam WORD   = 2'b10;
    localparam INCR4  = 3'b011;
    localparam INCR8  = 3'b101;
    localparam INCR16 = 3'b111;

    integer errors;
    integer tests;
    integer i, j, timeout;
    integer burst_len;
    integer error_beat;
    reg [2:0] burst_type;
    reg [31:0] base_addr;
    reg is_write;
    reg inject_error;
    reg [31:0] expected_addr;

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

    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    initial begin
        $dumpfile("incr.vcd");
        $dumpvars(0, incr_tb);
    end

    task reset_dut;
    begin
        @(negedge clk);
        reset     = 1'b1;
        req_valid = 1'b0;
        req_write = 1'b0;
        req_addr  = 0;
        req_size  = WORD;
        req_burst = INCR4;
        wdata     = 0;
        hrdata    = 0;
        hready    = 1'b1;
        hresp     = 1'b0;
        last_beat = 1'b0;

        repeat (3) @(negedge clk);
        reset = 1'b0;
        repeat (2) @(negedge clk);
    end
    endtask

    //====================================================
    // BURST TEST WITH TWO WAIT CYCLES
    //====================================================
    task burst_wait_test;
        input is_wr;
        input [31:0] start_addr;
        input [2:0] burst;
        input integer length;

        begin
            $display("\n===== INCR%0d %s WITH WAIT STATES =====",
                     length, is_wr ? "WRITE" : "READ");

            @(negedge clk);
            req_valid = 1'b1;
            req_write = is_wr;
            req_addr  = start_addr;
            req_size  = WORD;
            req_burst = burst;
            wdata     = 32'h1234_ABCD;
            hrdata    = 32'hCAFE_BABE;
            hready    = 1'b1;
            hresp     = 1'b0;
            last_beat = 1'b0;

            // Allow the controller to launch the burst.
            @(negedge clk);

            for (i = 0; i < length; i = i + 1) begin
                // Unique write data for every beat.
                wdata = 32'h1234_ABCD + i;

                expected_addr = start_addr + (i * 4);
                timeout = 0;

                while ((htrans == 2'b00) && (timeout < 10)) begin
                    @(negedge clk);
                    timeout = timeout + 1;
                end

                #1;
                tests = tests + 1;

                if (timeout >= 10) begin
                    $display("FAIL: Timeout waiting for beat %0d", i+1);
                    errors = errors + 1;
                end
                else begin
                    if (haddr !== expected_addr) begin
                        $display("FAIL: Beat %0d address expected=%h actual=%h",
                                 i+1, expected_addr, haddr);
                        errors = errors + 1;
                    end

                    if (i == 0 && htrans !== 2'b10) begin
                        $display("FAIL: First beat must be NONSEQ");
                        errors = errors + 1;
                    end

                    if (i > 0 && htrans !== 2'b11) begin
                        $display("FAIL: Beat %0d must be SEQ, actual HTRANS=%b",
                                 i+1, htrans);
                        errors = errors + 1;
                    end

                    if (hwrite !== is_wr || hsize !== WORD ||
                        hburst !== burst) begin
                        $display("FAIL: Control mismatch on beat %0d", i+1);
                        errors = errors + 1;
                    end
                    else begin
                        $display("BEAT %0d: HTRANS=%b HADDR=%h HWRITE=%b",
                                 i+1, htrans, haddr, hwrite);
                    end
                end

                // Address phase is accepted on this rising edge.
                @(posedge clk);

                if (is_wr)
                    $display("HWDATA=%h", hwdata);
                else
                    $display("RDATA=%h RD_AVAILABLE=%b",
                             resp_rdata, rd_available);

                // Insert two wait cycles during beat 2.
                if (i == 1) begin
                    hready = 1'b0;
                    hresp  = 1'b0;

                    repeat (2) begin
                        @(posedge clk);
                        #1;
                        if (ready !== 1'b0) begin
                            $display("FAIL: READY should be low during wait");
                            errors = errors + 1;
                        end
                        if (is_wr &&
                            hwdata !== (32'h1234_ABCD + i)) begin
                            $display("FAIL: Write data changed during wait");
                            errors = errors + 1;
                        end
                        $display("WAIT: HREADY=%b READY=%b", hready, ready);
                    end

                    @(posedge clk);
                    hready = 1'b1;
                    hresp  = 1'b0;
                end

                @(negedge clk);
            end

            req_valid = 1'b0;
            hready = 1'b1;
            hresp = 1'b0;
            repeat (3) @(negedge clk);

            $display("INCR%0d %s WAIT TEST FINISHED",
                     length, is_wr ? "WRITE" : "READ");
        end
    endtask

    //====================================================
    // BURST ERROR TEST
    //
    // Injects a two-cycle AHB-Lite error response during
    // the selected beat. The burst is expected to abort.
    //====================================================
    task burst_error_test;
        input is_wr;
        input [31:0] start_addr;
        input [2:0] burst;
        input integer length;
        input integer bad_beat;

        begin
            $display("\n===== INCR%0d %s ERROR AT BEAT %0d =====",
                     length, is_wr ? "WRITE" : "READ", bad_beat);

            @(negedge clk);
            req_valid = 1'b1;
            req_write = is_wr;
            req_addr  = start_addr;
            req_size  = WORD;
            req_burst = burst;
            wdata     = 32'h1234_ABCD;
            hrdata    = 32'hCAFE_BABE;
            hready    = 1'b1;
            hresp     = 1'b0;
            last_beat = 1'b0;

            @(negedge clk);

            for (j = 0; j < bad_beat; j = j + 1) begin
                // Unique write data for every beat.
                wdata = 32'h1234_ABCD + j;

                expected_addr = start_addr + (j * 4);
                timeout = 0;

                while ((htrans == 2'b00) && (timeout < 10)) begin
                    @(negedge clk);
                    timeout = timeout + 1;
                end

                #1;
                tests = tests + 1;

                if (timeout >= 10) begin
                    $display("FAIL: Timeout before error beat %0d", j+1);
                    errors = errors + 1;
                    j = bad_beat;
                end
                else begin
                    if (haddr !== expected_addr) begin
                        $display("FAIL: Address at beat %0d expected=%h actual=%h",
                                 j+1, expected_addr, haddr);
                        errors = errors + 1;
                    end

                    if (j == 0 && htrans !== 2'b10) begin
                        $display("FAIL: First beat should be NONSEQ");
                        errors = errors + 1;
                    end
                    else if (j > 0 && htrans !== 2'b11) begin
                        $display("FAIL: Expected SEQ at beat %0d", j+1);
                        errors = errors + 1;
                    end

                    $display("ERROR TEST BEAT %0d: HTRANS=%b HADDR=%h",
                             j+1, htrans, haddr);

                    @(posedge clk);
                    #1;

                    if (j == bad_beat-1) begin
                        // First error response cycle.
                        hready = 1'b0;
                        hresp  = 1'b1;
                        #1;

                        if (ready !== 1'b0) begin
                            $display("FAIL: READY should be low in first error cycle");
                            errors = errors + 1;
                        end

                        @(posedge clk);
                        #1;

                        // Second error response cycle.
                        @(negedge clk);
                        hready = 1'b1;
                        hresp  = 1'b1;
                        #1;

                        if (ready !== 1'b1 || resp_error !== 1'b1) begin
                            $display("FAIL: Incorrect second error response cycle");
                            errors = errors + 1;
                        end
                        else begin
                            $display("PASS: Two-cycle error response observed");
                        end

                        req_valid = 1'b0;
                        @(posedge clk);
                        #1;
                        hready = 1'b1;
                        hresp  = 1'b0;
                        j = bad_beat;
                    end
                    else begin
                        @(negedge clk);
                    end
                end
            end

            hready = 1'b1;
            hresp  = 1'b0;
            req_valid = 1'b0;
            repeat (3) @(negedge clk);
        end
    endtask

    //====================================================
    // MAIN TEST SEQUENCE
    //====================================================
    initial begin
        errors = 0;
        tests  = 0;

        reset = 1'b1;
        req_valid = 0;
        last_beat = 0;
        req_write = 0;
        req_addr = 0;
        req_size = WORD;
        req_burst = INCR4;
        wdata = 0;
        hrdata = 0;
        hready = 1;
        hresp = 0;

        reset_dut();

        // INCR4 normal read/write with wait states.
        burst_wait_test(1'b1, 32'h0000_1000, INCR4, 4);
        reset_dut();
        burst_wait_test(1'b0, 32'h0000_2000, INCR4, 4);

        // INCR8 normal read/write with wait states.
        reset_dut();
        burst_wait_test(1'b1, 32'h0000_3000, INCR8, 8);
        reset_dut();
        burst_wait_test(1'b0, 32'h0000_4000, INCR8, 8);

        // INCR16 normal read/write with wait states.
        reset_dut();
        burst_wait_test(1'b1, 32'h0000_5000, INCR16, 16);
        reset_dut();
        burst_wait_test(1'b0, 32'h0000_6000, INCR16, 16);

        // Error tests: inject an error on beat 3 of each burst.
        reset_dut();
        burst_error_test(1'b1, 32'h0000_7000, INCR4, 4, 3);
        reset_dut();
        burst_error_test(1'b0, 32'h0000_8000, INCR4, 4, 3);

        reset_dut();
        burst_error_test(1'b1, 32'h0000_9000, INCR8, 8, 3);
        reset_dut();
        burst_error_test(1'b0, 32'h0000_A000, INCR8, 8, 3);

        reset_dut();
        burst_error_test(1'b1, 32'h0000_B000, INCR16, 16, 3);
        reset_dut();
        burst_error_test(1'b0, 32'h0000_C000, INCR16, 16, 3);

        $display("\n===== FINAL RESULT =====");
        $display("Checks executed: %0d", tests);
        $display("Errors: %0d", errors);

        if (errors == 0)
            $display("ALL CHECKS PASSED");
        else
            $display("TEST FAILURES FOUND - inspect waveform and RTL");

        $finish;
    end

endmodule
