module fifo_rx #(parameter DEPTH=8, 
                        WIDTH=8,
                        N=$clog2(DEPTH)
              )(
                input clk_wr,clk_rd,full,empty,nr_full,nr_empty,wr,rd,clr,wr_en,rd_en,
                input  [WIDTH-1:0] data_in,
                output [WIDTH-1:0] data_out,
                output [N:0]       gray_adrs_wr,gray_adrs_rd, bin_adrs_wr,bin_adrs_rd
                );
                   
              memo_rx #(.DEPTH(DEPTH),
                     .WIDTH(WIDTH)
                     )str(
                          .data_in(data_in),
                          .data_out(data_out),
                          .clk_rd(clk_rd),
                          .clk_wr(clk_wr),
                          .wr(wr),
                          .rd(rd),
                          .clr(clr),
                          .adrs_rd(bin_adrs_rd[N-1:0]),
                          .adrs_wr(bin_adrs_wr[N-1:0]),
                          .full(full),
                          .nr_full(nr_full),
                          .empty(empty),
                          .nr_empty(nr_empty),
                          .wr_en(wr_en),
                          .rd_en(rd_en)
                         );

             wr_ptr_rx  #(.DEPTH(DEPTH),
                     .WIDTH(WIDTH)
                     )ptr1(
                           .wr(wr),
                           .clk_wr(clk_wr),
                           .clr(clr),
                           .wr_en(wr_en),
                           .full(full),
                           .nr_full(nr_full),
                           .bin_adrs_wr(bin_adrs_wr),
                           .gray_adrs_wr(gray_adrs_wr)
                          );

             rd_ptr_rx  #(.DEPTH(DEPTH),
                     .WIDTH(WIDTH)
                     )ptr2(
                           .rd(rd),
                           .clk_rd(clk_rd),
                           .clr(clr),
                           .rd_en(rd_en),
                           .empty(empty),
                           .nr_empty(nr_empty),
                           .bin_adrs_rd(bin_adrs_rd),
                           .gray_adrs_rd(gray_adrs_rd)
                          );

endmodule

module memo_rx #(parameter DEPTH=8, 
                        WIDTH=8,
                        N=$clog2(DEPTH)
              )(
                input                  clk_rd,clk_wr,clr,wr,rd,full,nr_full,empty,nr_empty,rd_en,wr_en,
                input      [WIDTH-1:0] data_in,
                output reg [WIDTH-1:0] data_out,
                input          [N-1:0]   adrs_rd,
                input          [N-1:0]   adrs_wr
                );

               reg [WIDTH-1:0] regfile[0:DEPTH-1];
               integer i;

              always@(posedge clk_rd or posedge clr)begin
              if(clr)begin
              data_out<=0;    
              end
              else if(rd_en && rd )begin
              data_out<=regfile[adrs_rd];
              end
              end
              always@(posedge clk_wr or posedge clr)begin
              if(clr)begin
              for (i = 0; i < DEPTH; i=i+1) begin
                  regfile[i]<=0;
              end    
              end
              else if(wr_en && wr )begin
              regfile[adrs_wr]<=data_in;
              end
              end
endmodule

       
module wr_ptr_rx#(
         parameter DEPTH=8, 
                   WIDTH=8,
                   N=$clog2(DEPTH)
        )(
          input          wr,clk_wr,clr,wr_en,full,nr_full,
          output    [N:0] gray_adrs_wr,
          output reg[N:0] bin_adrs_wr
         );

        always@(posedge clk_wr or posedge clr)begin
        if(clr)begin
        bin_adrs_wr<={(N+1){1'b0}};
        end
        else if(wr_en && wr )begin
        bin_adrs_wr<=bin_adrs_wr+1;
        end
        end

        assign gray_adrs_wr=bin_adrs_wr^(bin_adrs_wr>>1);

endmodule


module rd_ptr_rx#(
         parameter DEPTH=8, 
                   WIDTH=8,
                   N=$clog2(DEPTH)
        )(
          input          rd,clk_rd,clr,rd_en,empty,nr_empty,
          output    [N:0] gray_adrs_rd,
          output reg[N:0] bin_adrs_rd
         );

        always@(posedge clk_rd or posedge clr)begin
        if(clr)begin
        bin_adrs_rd<={(N+1){1'b0}};
        end
        else if(rd_en && rd )begin
        bin_adrs_rd<=bin_adrs_rd+1;
        end
        end

        assign gray_adrs_rd=bin_adrs_rd^(bin_adrs_rd>>1);

endmodule


