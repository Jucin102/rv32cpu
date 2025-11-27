module reservation_station
import rv32i_types::*;
(
    input logic clk, rst,
    input logic [NUM_RES_STATIONS-1:0] rs_we,
    input rs_entry_t rs_wdata [NUM_RES_STATIONS],
    input logic [NUM_RES_STATIONS-1:0] rs_to_free,
    input logic branch_mispredict, // TO_SET
    output logic [NUM_RES_STATIONS-1:0] busy_rs, 
    output rs_entry_t rs_curr [NUM_RES_STATIONS]
);
    rs_entry_t rs_entries[NUM_RES_STATIONS];
    rs_entry_t rs_next[NUM_RES_STATIONS];

    always_comb 
    begin
        rs_next = rs_entries;
        for (int unsigned i = 0; i < NUM_RES_STATIONS; ++i)
        begin
            if ((rst == 1'b1) || (branch_mispredict == 1'b1))
            begin
                rs_next[i] = '0;
            end
            else if (rs_we[i])
            begin
                rs_next[i] = rs_wdata[i];
                rs_next[i].busy = 1'b1;
            end
            else if (rs_to_free[i])
            begin
                rs_next[i].busy = 1'b0;
            end
        end
    end

    always_ff @(posedge clk)
    begin
        rs_entries <= rs_next;
    end

    always_comb 
    begin
        for (int unsigned i = 0; i < NUM_RES_STATIONS; ++i)
        begin
            busy_rs[i] = rs_entries[i].busy;
        end

        rs_curr = rs_entries;
    end
endmodule

// endmodule

// module reservation_station_mul
// import rv32i_types::*;
// (
//     input logic clk, rst,
//     input logic [WIDTH - 1: 0] real_input_ligma,
//     output logic [WIDTH - 1: 0] real_output_ligma,
//     input logic push, pop,  
//     output logic full, empty
// );

// endmodule

// module reservation_station_st_ld
// import rv32i_types::*;
// (
//     input logic clk, rst,
//     input logic [WIDTH - 1: 0] real_input_ligma,
//     output logic [WIDTH - 1: 0] real_output_ligma,
//     input logic push, pop,  
//     output logic full, empty
// );

// endmodule