module fifo_ctrl_tx #(parameter DEPTH=8, 
                        WIDTH=8,
                        N=$clog2(DEPTH)
                )(
                  input          clk_rd,clk_wr,en,clr,wr,
                  input   [N:0]  gray_adrs_wr,gray_adrs_rd,bin_adrs_wr,bin_adrs_rd,
                  output   reg   full,nr_full,empty,nr_empty,rd_en,wr_en
                  );
                 
                 reg  [N:0] g_syn_wr,g_syn_rd,bin_syn_rd,bin_syn_wr,bin_nxt_wr,gray_nxt_wr,gray_nxt_rd,bin_nxt_rd; 
                 reg  [N:0] g_wr,g_rd;
                 integer i,j;
                 
                // 2FF sync
always @(posedge clk_wr or posedge clr)begin
    if(clr)begin
    g_rd<={(N){1'b0}};
    g_syn_rd<={(N){1'b0}};
    end
    else begin
    g_rd      <= gray_adrs_rd;
    g_syn_rd  <= g_rd;
    end
end

// Gray → Binary
always @(*) begin
    bin_syn_rd[N] = g_syn_rd[N];
    for (i = N-1; i >= 0; i = i-1)
        bin_syn_rd[i] = bin_syn_rd[i+1] ^ g_syn_rd[i];
end

// Next pointer
always @(*) begin
    bin_nxt_wr  = bin_adrs_wr + (wr_en && wr);  // 1 changed to (wr_en && wr) to stop increment after full
    gray_nxt_wr = bin_nxt_wr ^ (bin_nxt_wr >> 1);
end

// FULL
always @(posedge clk_wr) begin
    full <= (gray_nxt_wr == {~g_syn_rd[N:N-1], g_syn_rd[N-2:0]});
end

// ALMOST FULL
always @(posedge clk_wr) begin
    nr_full <= ((bin_adrs_wr - bin_syn_rd) >= DEPTH-2);
end

// WRITE ENABLE
always @(posedge clk_wr) begin
    wr_en <= en && !full;
end

// ================================
// 2FF sync (write pointer → read domain)
// ================================
always @(posedge clk_rd or posedge clr) begin
    if(clr)begin
    g_wr<={(N){1'b0}};
    g_syn_wr<={(N){1'b0}};
    end
else begin
    g_wr      <= gray_adrs_wr;
    g_syn_wr  <= g_wr;
end
end

// ================================
// Gray → Binary (synchronized write pointer)
// ================================
always @(*) begin
    bin_syn_wr[N] = g_syn_wr[N];
    for (j = N-1; j >= 0; j = j-1)
        bin_syn_wr[j] = bin_syn_wr[j+1] ^ g_syn_wr[j];
end

// ================================
// Next pointer (read side)
// ================================
always @(*) begin
    bin_nxt_rd  = bin_adrs_rd + 1;
    gray_nxt_rd = bin_nxt_rd ^ (bin_nxt_rd >> 1);
end

// ================================
// EMPTY
// ================================
always @(posedge clk_rd) begin
    empty <= (gray_adrs_rd == g_syn_wr);
end

// ================================
// ALMOST EMPTY
// ================================
always @(posedge clk_rd) begin
    nr_empty <= ((bin_syn_wr - bin_adrs_rd) <= 2);
end

// ================================
// READ ENABLE
// ================================
always @(posedge clk_rd) begin
    rd_en <= en && !empty ;
end
endmodule


                 

                

                      
                      
                    






