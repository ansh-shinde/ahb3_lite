`timescale 1ns/1ps

module write_tb;

reg clk, reset;

// AHB master request interface
reg req_valid, last_beat, req_write;
reg [31:0] req_addr, wdata;
reg [1:0] req_size;
reg [2:0] req_burst;

// AHB master <-> bridge
wire [31:0] resp_rdata;
wire hwrite, nxt_beat, rd_available, resp_error, ready;
wire [1:0] htrans, hsize;
wire [2:0] hburst;
wire [31:0] haddr, hwdata;
wire hready, hresp;
wire [31:0] hrdata;

// APB bridge <-> UART
wire psel0, psel1, psel2, psel3;
wire penable, pwrite;
wire [31:0] paddr, pwdata, prdata;
wire pready_uart, pready_bridge, pslverr;

// UART pins
reg rx, cts;
wire tx, intrr_tx, intrr_rx, rts;

// APB wait-state injection. The UART's own PREADY is a one-cycle pulse,
// so the bridge-side PREADY is stretched independently when force_wait=1.
reg force_wait;
reg [3:0] wait_count;
reg wait_done;

integer errors, tests;
integer low_cycles, apb_access_cycles;
integer i;
reg transaction_active;

localparam WORD   = 2'b10;
localparam SINGLE = 3'b000;

assign pready_bridge =
    (force_wait && psel0 && penable) ? wait_done : pready_uart;

//====================================================
// AHB MASTER
//====================================================
top_ahb dut_ahb (
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
// AHB-TO-APB BRIDGE
//====================================================
top_apb dut_bridge (
    .hclk(clk),
    .hreset(reset),
    .hwrite(hwrite),
    .hselb(1'b1),
    .pready(pready_bridge),
    .pslverr(pslverr),
    .hwdata(hwdata),
    .prdata(prdata),
    .htrans(htrans),
    .hsize({1'b0, hsize}),
    .hburst(hburst),
    .haddr(haddr),
    .hready(hready),
    .hresp(hresp),
    .psel0(psel0),
    .psel1(psel1),
    .psel2(psel2),
    .psel3(psel3),
    .penable(penable),
    .pwrite(pwrite),
    .pwdata(pwdata),
    .paddr(paddr),
    .hrdata(hrdata)
);

//====================================================
// UART APB SLAVE
//====================================================
apb_uart dut_uart (
    .preset(reset),
    .pclk(clk),
    .penable(penable),
    .pwrite(pwrite),
    .psel(psel0),
    .paddr(paddr),
    .pwdata(pwdata),
    .pready(pready_uart),
    .pslverr(pslverr),
    .prdata(prdata),
    .rx(rx),
    .cts(cts),
    .rts(rts),
    .intrr_tx(intrr_tx),
    .intrr_rx(intrr_rx),
    .tx(tx)
);

//====================================================
// CLOCK, WAIT INJECTION, AND WAVEFORM
//====================================================
initial begin
    clk = 1'b0;
    forever #5 clk = ~clk;
end

always @(posedge clk or posedge reset) begin
    if (reset) begin
        wait_count <= 0;
        wait_done  <= 0;
    end
    else if (!(psel0 && penable)) begin
        wait_count <= 0;
        wait_done  <= 0;
    end
    else if (force_wait && !wait_done) begin
        if (wait_count == 3) begin
            wait_done <= 1'b1;
        end
        else begin
            wait_count <= wait_count + 1'b1;
        end
    end
end

always @(posedge clk) begin
    if (transaction_active) begin
        if (!hready)
            low_cycles = low_cycles + 1;
        if (psel0 && penable)
            apb_access_cycles = apb_access_cycles + 1;
    end

    if (psel0) begin
        $display("APB: PSEL=%b PENABLE=%b PWRITE=%b PADDR=%h PWDATA=%h PREADY_UART=%b PREADY_BRIDGE=%b PRDATA=%h PSLVERR=%b",
                 psel0, penable, pwrite, paddr, pwdata,
                 pready_uart, pready_bridge, prdata, pslverr);
    end
end

initial begin
    $dumpfile("write_tb.vcd");
    $dumpvars(0, write_tb);
     $dumpvars(0,dut_uart.regfile[0]);
        $dumpvars(0,dut_uart.regfile[1]);
        $dumpvars(0,dut_uart.regfile[2]);
        $dumpvars(0,dut_uart.regfile[3]);
        $dumpvars(0,dut_uart.regfile[4]);
        $dumpvars(0,dut_uart.regfile[5]);
        $dumpvars(0,dut_uart.regfile[6]);
        $dumpvars(0,dut_uart.regfile[7]);

        $dumpvars(0,dut_uart.transmitter.dat_tx.fifo.dat_fifo_tx.str.regfile[0]);
        $dumpvars(0,dut_uart.transmitter.dat_tx.fifo.dat_fifo_tx.str.regfile[1]);
        $dumpvars(0,dut_uart.transmitter.dat_tx.fifo.dat_fifo_tx.str.regfile[2]);
        $dumpvars(0,dut_uart.transmitter.dat_tx.fifo.dat_fifo_tx.str.regfile[3]);
        $dumpvars(0,dut_uart.transmitter.dat_tx.fifo.dat_fifo_tx.str.regfile[4]);
        $dumpvars(0,dut_uart.transmitter.dat_tx.fifo.dat_fifo_tx.str.regfile[5]);
        $dumpvars(0,dut_uart.transmitter.dat_tx.fifo.dat_fifo_tx.str.regfile[6]);
        $dumpvars(0,dut_uart.transmitter.dat_tx.fifo.dat_fifo_tx.str.regfile[7]);

        $dumpvars(0,dut_uart.receiver.dat_rx.fifo.dat_fifo_rx.str.regfile[0]);
        $dumpvars(0,dut_uart.receiver.dat_rx.fifo.dat_fifo_rx.str.regfile[1]);
        $dumpvars(0,dut_uart.receiver.dat_rx.fifo.dat_fifo_rx.str.regfile[2]);
        $dumpvars(0,dut_uart.receiver.dat_rx.fifo.dat_fifo_rx.str.regfile[3]);
        $dumpvars(0,dut_uart.receiver.dat_rx.fifo.dat_fifo_rx.str.regfile[4]);
        $dumpvars(0,dut_uart.receiver.dat_rx.fifo.dat_fifo_rx.str.regfile[5]);
        $dumpvars(0,dut_uart.receiver.dat_rx.fifo.dat_fifo_rx.str.regfile[6]);
        $dumpvars(0,dut_uart.receiver.dat_rx.fifo.dat_fifo_rx.str.regfile[7]);
end

//====================================================
// RESET
//====================================================
task do_reset;
begin
    @(negedge clk);
    reset = 1'b1;
    req_valid = 1'b0;
    last_beat = 1'b0;
    req_write = 1'b0;
    req_addr = 0;
    req_size = WORD;
    req_burst = SINGLE;
    wdata = 0;
    rx = 1'b1;
    cts = 1'b0;
    force_wait = 1'b0;
    transaction_active = 1'b0;
    repeat (3) @(negedge clk);
    reset = 1'b0;
    repeat (2) @(negedge clk);
end
endtask

//====================================================
// AHB SINGLE WRITE
// expect_error=1 injects an APB slave error response.
// inject_wait=1 stretches bridge-side PREADY for the APB access.
//====================================================
task ahb_write;
input [31:0] addr;
input [31:0] data;
input expect_error;
input inject_wait;
integer n;
begin
    @(negedge clk);
    req_valid = 1'b1;
    req_write = 1'b1;
    req_addr = addr;
    req_size = WORD;
    req_burst = SINGLE;
    wdata = data;
    last_beat = 1'b0;
    force_wait = inject_wait;
    low_cycles = 0;
    apb_access_cycles = 0;
    transaction_active = 1'b1;

    n = 0;
    while ((htrans !== 2'b10) && (n < 30)) begin
        @(negedge clk);
        n = n + 1;
    end

    if (htrans !== 2'b10) begin
        $display("FAIL: WRITE address phase timeout addr=%h", addr);
        errors = errors + 1;
        transaction_active = 1'b0;
        req_valid = 1'b0;
        force_wait = 1'b0;
    end
    else begin
        $display("AHB SINGLE WRITE: addr=%h data=%h", addr, data);
        @(posedge clk);
        #1 req_valid = 1'b0;

        // Inject a completed APB error response for this transaction.
        if (expect_error) begin
            n = 0;
            while (!(psel0 && penable) && (n < 30)) begin
                @(negedge clk);
                n = n + 1;
            end
            if (psel0 && penable) begin
                force pready_bridge = 1'b1;
                force pslverr = 1'b1;
            end
        end

        n = 0;
        while ((ready !== 1'b1) && (n < 200)) begin
            @(negedge clk);
            n = n + 1;
        end

        if (expect_error) begin
            release pready_bridge;
            release pslverr;
        end

        transaction_active = 1'b0;
        force_wait = 1'b0;

        if (n >= 200) begin
            $display("FAIL: WRITE completion timeout addr=%h", addr);
            errors = errors + 1;
        end
        else if (expect_error) begin
            if (resp_error || hresp) begin
                $display("PASS: WRITE error response addr=%h resp_error=%b hresp=%b",
                         addr, resp_error, hresp);
                tests = tests + 1;
            end
            else begin
                $display("FAIL: Expected WRITE error at addr=%h", addr);
                errors = errors + 1;
            end
        end
        else begin
            if (resp_error || hresp) begin
                $display("FAIL: Unexpected WRITE error addr=%h resp_error=%b hresp=%b",
                         addr, resp_error, hresp);
                errors = errors + 1;
            end
            else begin
                $display("PASS: WRITE addr=%h data=%h HREADY-low-cycles=%0d APB-access-cycles=%0d",
                         addr, data, low_cycles, apb_access_cycles);
                tests = tests + 1;
            end
        end

        if (inject_wait && (apb_access_cycles < 4)) begin
            $display("FAIL: WRITE APB wait was not observed; access cycles=%0d",
                     apb_access_cycles);
            errors = errors + 1;
        end
        if (!expect_error && (low_cycles == 0)) begin
            $display("FAIL: WRITE did not show bridge HREADY wait");
            errors = errors + 1;
        end
    end

    req_valid = 1'b0;
    force_wait = 1'b0;
    repeat (2) @(negedge clk);
end
endtask

initial begin
    errors = 0;
    tests = 0;
    reset = 1'b1;
    req_valid = 0;
    req_write = 0;
    req_addr = 0;
    req_size = WORD;
    req_burst = SINGLE;
    wdata = 0;
    last_beat = 0;
    rx = 1'b1;
    cts = 1'b1;
    force_wait = 0;
    wait_count = 0;
    wait_done = 0;
    transaction_active = 0;
    low_cycles = 0;
    apb_access_cycles = 0;

    do_reset();
    cts = 1'b1;

    $display("\n===== AHB -> BRIDGE -> UART : WRITE TESTS =====");

    // UART configuration and baud rate, matching the bridge write reference.
    ahb_write(32'h00, 32'h00000101, 0, 0);
    if (dut_uart.regfile[0] !== 32'h00000101) begin
        $display("FAIL: CONTROL expected=00000101 actual=%h", dut_uart.regfile[0]);
        errors = errors + 1;
    end
    else $display("PASS: CONTROL register=%h", dut_uart.regfile[0]);

    ahb_write(32'h08, 32'h000001B2, 0, 0);
    if (dut_uart.regfile[2] !== 32'h000001B2) begin
        $display("FAIL: BAUD expected=000001B2 actual=%h", dut_uart.regfile[2]);
        errors = errors + 1;
    end
    else $display("PASS: BAUD register=%h", dut_uart.regfile[2]);

    // TX FIFO writes follow the byte sequence in the supplied bridge write TB.
    ahb_write(32'h0C, 32'h00000011, 0, 0);
    ahb_write(32'h0C, 32'h00000022, 0, 0);
    ahb_write(32'h0C, 32'h00000033, 0, 0);
    ahb_write(32'h0C, 32'h00000044, 0, 0);
    ahb_write(32'h0C, 32'h00000055, 0, 0);
    ahb_write(32'h0C, 32'h00000066, 0, 0);
    ahb_write(32'h0C, 32'h00000077, 0, 0);
    ahb_write(32'h0C, 32'h00000000, 0, 1); // Inject APB data-phase wait.

    // Valid UART address; inject PREADY=1 and PSLVERR=1 for error response.
    ahb_write(32'h00, 32'hDEADBEEF, 1, 0);

    $display("\n===== WRITE TEST SUMMARY =====");
    $display("Tests passed: %0d", tests);
    $display("Errors:       %0d", errors);
    if (errors == 0) $display("WRITE TESTBENCH PASSED");
    else             $display("WRITE TESTBENCH FAILED");
    $finish;
end

initial begin
    #1000000;
    $display("FATAL: WRITE testbench timeout");
    $finish;
end

endmodule
