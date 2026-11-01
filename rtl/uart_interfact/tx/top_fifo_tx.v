module top_fifo_tx #(parameter DEPTH=8, 
                        WIDTH=8,
                        N=$clog2(DEPTH)
             )(
               input clk_wr,clk_rd,rd,wr,clr,en,
               input  [WIDTH-1:0] data_in,
               output full,nr_full,empty,nr_empty,
               output [WIDTH-1:0] data_out
              );
    wire [N:0] gray_adrs_wr,gray_adrs_rd,bin_adrs_wr,bin_adrs_rd;
    wire rd_en,wr_en;
    fifo_tx #(.DEPTH(DEPTH),
           .WIDTH(WIDTH)
          )dat_fifo_tx(
               .clk_wr(clk_wr),
               .clk_rd(clk_rd),
               .full(full),
               .empty(empty),
               .nr_full(nr_full),
               .nr_empty(nr_empty),
               .wr(wr),
               .rd(rd),
               .clr(clr),
               .wr_en(wr_en),
               .rd_en(rd_en),
               .data_in(data_in),
               .data_out(data_out),
               .gray_adrs_wr(gray_adrs_wr),
               .gray_adrs_rd(gray_adrs_rd),
               .bin_adrs_wr(bin_adrs_wr),
               .bin_adrs_rd(bin_adrs_rd)
              );
    
     fifo_ctrl_tx #(.DEPTH(DEPTH),
               .WIDTH(WIDTH)
              )ctrl_fifo_tx(
                    .wr(wr),
                    .clk_rd(clk_rd),
                    .clk_wr(clk_wr),
                    .en(en),
                    .gray_adrs_wr(gray_adrs_wr),
                    .gray_adrs_rd(gray_adrs_rd),
                    .full(full),
                    .nr_full(nr_full),
                    .empty(empty),
                    .nr_empty(nr_empty),
                    .rd_en(rd_en),
                    .wr_en(wr_en),
                    .bin_adrs_wr(bin_adrs_wr),
                    .bin_adrs_rd(bin_adrs_rd),
                    .clr(clr)
                   );
endmodule



               
