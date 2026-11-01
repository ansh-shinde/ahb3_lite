module top_apb(
    input        hclk,
    input        hreset,
    input        hwrite,
    input        hselb,
    input        pready,
    input        pslverr,
    input [31:0] hwdata,
    input [31:0] prdata,
    input [1:0]  htrans,
    input [2:0]  hsize,
    input [2:0]  hburst,
    input [31:0] haddr,
    output       hready,
    output       hresp,
    output       psel0,psel1,psel2,psel3,
    output       penable,
    output       pwrite,
    output [31:0]pwdata,
    output [31:0]paddr,
    output [31:0]hrdata
);

        wire pw_addr_data_top,
             valid_top,
             valid_size_top,
             valid_addr_top,
             hwrite_reg_top,
             en_psel_top,
             pr_addr_top;

data_apb dat_apb(
    .hclk(hclk),
    .hreset(hreset),
    .htrans(htrans),
    .hsize(hsize),
    .hwrite(hwrite),
    .hselb(hselb),
    .en_psel(en_psel_top),
    .pw_addr_data(pw_addr_data_top),
    .pr_addr(pr_addr_top),
    .haddr(haddr),
    .prdata(prdata),
    .hwdata(hwdata),
    .hwrite_reg(hwrite_reg_top),
    .psel0(psel0),
    .psel1(psel1),
    .psel2(psel2),
    .psel3(psel3),
    .valid(valid_top),
    .valid_size(valid_size_top),
    .valid_addr(valid_addr_top),
    .paddr(paddr),
    .pwdata(pwdata),
    .hrdata(hrdata)
);

control_apb ctrl_apb(
    .hclk(hclk),
    .hreset(hreset),
    .hselb(hselb),
    .hwrite(hwrite),
    .hwrite_reg(hwrite_reg_top),
    .valid(valid_top),
    .valid_size(valid_size_top),
    .valid_addr(valid_addr_top),
    .pready(pready),
    .pslverr(pslverr),
    .en_psel(en_psel_top),
    .pw_addr_data(pw_addr_data_top),
    .pr_addr(pr_addr_top),
    .penable(penable),
    .hready(hready),
    .hresp(hresp),
    .pwrite(pwrite)
);

endmodule
