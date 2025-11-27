module rat
import rv32i_types::*;
#(
    parameter WIDTH = NUM_PHYS_REGS_BITS,
    parameter SS = SS_FACTOR,
    parameter SS_BITS = SS_FACTOR_BITS
)
(
    input logic clk, rst, mispredict,

    // input logic [SS_BITS : 0] rat_update,
    input arch_reg rd_dispatch[SS],
    input phys_reg pd_dispatch[SS],

    input logic [WIDTH - 1:0] rrf_mispredict_table[32],

    input arch_reg rs1[SS],
    input arch_reg rs2[SS],

    output phys_reg ps1[SS],
    output phys_reg ps2[SS]
);

    logic [WIDTH - 1:0] rat_table[32];
    logic [WIDTH - 1:0] rat_table_next[32];

    always_ff @(posedge clk) begin

        // Set mapping all of architectural registers to physical Rx on reset. Architectural R0 should always map to physical R0 (deal with in free list
        if(rst) begin
            for(int unsigned i = 0; i < 32; i++) begin
                rat_table[i] <= (WIDTH)'(i);
            end
        end
        // For super scalar, update multiple register translations when processing multiple instructions
        else begin
            rat_table <= rat_table_next;
        end
    end

    always_comb begin
        // Physical register translation output to continue operation
        rat_table_next = rat_table;
        for(int unsigned i = 0; i < SS; i++) begin
            ps1[i] = rat_table_next[rs1[i]];
            ps2[i] = rat_table_next[rs2[i]];
            // if(i < 32'(rat_update)) begin
            rat_table_next[rd_dispatch[i]] = pd_dispatch[i];
            // end
        end
        
        // On a mispredict generated from the ROB, the rat should be updated to rrf
        if(mispredict) begin
            rat_table_next = rrf_mispredict_table;
        end
    end

endmodule

module rrf
import rv32i_types::*;
#(
    parameter WIDTH = NUM_PHYS_REGS_BITS,
    parameter SS = SS_FACTOR,
    parameter SS_BITS = SS_FACTOR_BITS
)
(
    input logic clk, rst,

    input logic [SS_BITS:0] commit_cnt,
    input arch_reg rd_rob[SS],
    input phys_reg pd_rob[SS],

    output logic [SS_BITS:0] free_list_push,
    output phys_reg old_phys_reg[SS],
    output logic [WIDTH-1:0] rrf_mispredict_table[32]
);

    logic [WIDTH-1:0] rrf_table[32];
    logic [WIDTH-1:0] rrf_table_next[32];

    always_ff @(posedge clk) begin

        // Set mapping all of architectural registers to physical R0 on reset
        // Branch mispredicts shouldn't impact RRF
        if(rst) begin
            for(int unsigned i = 0; i < 32; i++) begin
                rrf_table[i] <= (WIDTH)'(i);
            end
        end 

        // We should update RRF when ROB commits. ROB should commit commit_cnt updates
        else begin
            rrf_table <= rrf_table_next;
        end
    end

    // Update free list with the freed translation register when we commit
    always_comb begin
        // Always output the mispredict table for branch mispredicts. On mispredict, rat will update to rrf_mispredict_table. Otherwise it doesn't do anything
        rrf_table_next = rrf_table;
        free_list_push = '0;
        for (int unsigned i = 0; i < SS; i++) begin
            old_phys_reg[i] = '0;
        end
        // Every commit for now pushes a physical register out. Use combinational save of table. Commit cnt = 0 means no commits.
        for(int unsigned i = 0; i < SS; i++) begin
            if(i < 32'(commit_cnt)) begin
                if(rd_rob[i] != '0) begin
                    old_phys_reg[free_list_push] = rrf_table_next[rd_rob[i]];
                    rrf_table_next[rd_rob[i]] = pd_rob[i];
                    free_list_push += (SS_BITS + unsigned'(1))'(unsigned'(1));
                end
            end
        end
        rrf_mispredict_table = rrf_table_next;
    end

endmodule
