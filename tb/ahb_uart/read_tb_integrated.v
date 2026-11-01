`timescale 1ns/1ps

module read_tb;

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
wire selb;
wire [31:0] hrdata;

// APB bridge <-> UART
wire psel0, psel1, psel2, psel3;
wire penable, pwrite;
wire [31:0] paddr, pwdata, prdata;
wire pready_uart, pready_bridge, pslverr, pslverr_bridge;

// UART pins
reg rx, cts;
wire tx, intrr_tx, intrr_rx, rts;

// APB wait-state injection
reg force_wait;
reg force_error;
reg [3:0] wait_count;
reg wait_done;

integer errors, tests;
integer low_cycles, apb_access_cycles;
integer i;
reg transaction_active;

localparam WORD   = 2'b10;
localparam SINGLE = 3'b000;

assign pready_bridge =
    (force_error && psel0 && penable) ? 1'b1 :
    ((force_wait && psel0 && penable) ? wait_done : pready_uart);

assign pslverr_bridge =
    (force_error && psel0 && penable) ? 1'b1 : pslverr;

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
    .hwdata(hwdata),
    .hselb(selb)
);

//====================================================
// AHB-TO-APB BRIDGE
//====================================================
top_apb dut_bridge (
    .hclk(clk),
    .hreset(reset),
    .hwrite(hwrite),
    .hselb(selb),
    .pready(pready_bridge),
    .pslverr(pslverr_bridge),
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
    $dumpfile("read_tb.vcd");
    $dumpvars(0, read_tb);

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
    force_error = 1'b0;
    transaction_active = 1'b0;

    repeat (3) @(negedge clk);
    reset = 1'b0;
    repeat (2) @(negedge clk);
end
endtask

//====================================================
// AHB SINGLE WRITE
// Copied from the successful write_tb_integrated
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

//====================================================
// AHB SINGLE READ
//====================================================
task ahb_read;
input [31:0] addr;
input [31:0] expected;
input check_data;
input expect_error;
input inject_wait;
integer n;
begin
    @(negedge clk);
    req_valid = 1'b1;
    req_write = 1'b0;
    req_addr = addr;
    req_size = WORD;
    req_burst = SINGLE;
    wdata = 0;
    last_beat = 1'b0;
    force_wait = inject_wait;
    force_error = expect_error;
    low_cycles = 0;
    apb_access_cycles = 0;
    transaction_active = 1'b1;

    n = 0;
    while ((htrans !== 2'b10) && (n < 30)) begin
        @(negedge clk);
        n = n + 1;
    end

    if (htrans !== 2'b10) begin
        $display("FAIL: READ address phase timeout addr=%h", addr);
        errors = errors + 1;
        transaction_active = 1'b0;
        req_valid = 1'b0;
        force_wait = 1'b0;
        force_error = 1'b0;
    end
    else begin
        $display("AHB SINGLE READ : addr=%h", addr);
        @(posedge clk);
        #1 req_valid = 1'b0;

        n = 0;
        while ((ready !== 1'b1) && (n < 200)) begin
            @(negedge clk);
            n = n + 1;
        end

        transaction_active = 1'b0;
        force_wait = 1'b0;
        force_error = 1'b0;

        if (n >= 200) begin
            $display("FAIL: READ completion timeout addr=%h", addr);
            errors = errors + 1;
        end
        else if (expect_error) begin
            if (resp_error || hresp) begin
                $display("PASS: READ error response addr=%h resp_error=%b hresp=%b",
                         addr, resp_error, hresp);
                tests = tests + 1;
            end
            else begin
                $display("FAIL: Expected READ error at addr=%h", addr);
                errors = errors + 1;
            end
        end
        else begin
            if (resp_error || hresp) begin
                $display("FAIL: Unexpected READ error addr=%h resp_error=%b hresp=%b",
                         addr, resp_error, hresp);
                errors = errors + 1;
            end
            else if (check_data && (resp_rdata !== expected)) begin
                $display("FAIL: READ addr=%h expected=%h actual=%h",
                         addr, expected, resp_rdata);
                errors = errors + 1;
            end
            else begin
                $display("PASS: READ addr=%h data=%h HREADY-low-cycles=%0d APB-access-cycles=%0d",
                         addr, resp_rdata, low_cycles, apb_access_cycles);

                if (addr == 32'h10)
                    $display("RX DATA: %02h", resp_rdata[7:0]);

                tests = tests + 1;
            end
        end

        if (inject_wait && (apb_access_cycles < 4)) begin
            $display("FAIL: READ APB wait was not observed; access cycles=%0d",
                     apb_access_cycles);
            errors = errors + 1;
        end

        if (!expect_error && (low_cycles == 0)) begin
            $display("FAIL: READ did not show bridge HREADY wait");
            errors = errors + 1;
        end
    end

    req_valid = 1'b0;
    force_wait = 1'b0;
    repeat (2) @(negedge clk);
end
endtask

//====================================================
// UART RX BIT AND FRAME TASKS
//====================================================
task send_bit;
input bit_val;
begin
    rx = bit_val;
    #4210;
end
endtask

task send_uart_frame;
input [7:0] data;
input parity;
input stop;
integer k;
begin
    if (rts) begin
        send_bit(1'b0);

        for (k = 0; k < 8; k = k + 1)
            send_bit(data[k]);

        send_bit(parity);
        send_bit(stop);
        #4210;
    end
end
endtask

//====================================================
// MAIN TEST SEQUENCE
//====================================================
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
    force_error = 0;
    wait_count = 0;
    wait_done = 0;
    transaction_active = 0;
    low_cycles = 0;
    apb_access_cycles = 0;

    do_reset();
    cts = 1'b1;

    $display("\n===== AHB -> BRIDGE -> UART : READ TESTS =====");

    // Initial UART configuration and baud writes use the working write TB sequence.
    ahb_write(32'h00, 32'h01010101, 0, 0);
    ahb_write(32'h08, 32'h000001B2, 0, 0);

    // Keep the AHB master idle after configuration.
    req_valid = 1'b0;
    req_write = 1'b0;
    repeat (2) @(negedge clk);

    // Send RX frames while no AHB transaction is active.
    send_uart_frame(8'h11, 1'b1, 1'b1);
    send_uart_frame(8'hA5, 1'b1, 1'b1);
    send_uart_frame(8'h55, 1'b0, 1'b1); // parity-error frame
    send_uart_frame(8'h33, 1'b1, 1'b0); // framing-error frame
    send_uart_frame(8'h77, 1'b1, 1'b1);
    send_uart_frame(8'h88, 1'b1, 1'b1);
    send_uart_frame(8'h99, 1'b1, 1'b1);

    i = 0;
    while ((intrr_rx !== 1'b1) && (i < 100000)) begin
        @(posedge clk);
        i = i + 1;
    end

    if (intrr_rx !== 1'b1) begin
        $display("FAIL: RX interrupt/near-full indication did not assert after RX frames");
        errors = errors + 1;
    end
    else begin
        $display("PASS: RX frames received; intrr_rx asserted");
    end

    // Read RX data through individual AHB single transfers.
    ahb_read(32'h10, 32'h00000000, 0, 0, 0);
    ahb_read(32'h10, 32'h00000000, 0, 0, 0);
    ahb_read(32'h10, 32'h00000000, 0, 0, 0);
    ahb_read(32'h10, 32'h00000000, 0, 0, 0);
    ahb_read(32'h10, 32'h00000000, 0, 0, 0);
    ahb_read(32'h10, 32'h00000000, 0, 0, 0);
    ahb_read(32'h10, 32'h00000000, 0, 0, 0);

    $display("\n===== READ TEST SUMMARY =====");
    $display("Tests passed: %0d", tests);
    $display("Errors:       %0d", errors);

    if (errors == 0)
        $display("READ TESTBENCH PASSED");
    else
        $display("READ TESTBENCH FAILED");

    $finish;
end

initial begin
    #1000000;
    $display("FATAL: READ testbench timeout");
    $finish;
end

endmodule
