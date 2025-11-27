module load_rs_entry
import rv32i_types::*;
(
    input logic clk, rst,
    
    input load_rs_entry_t input_entry,
    input logic [NUM_PHYS_REGS - 1 : 0] valid_reg,
    input cdb_t store_load_cdb,
    input logic we,

    output load_rs_entry_t output_entry
);
    load_rs_entry_t entry, entry_next;

    // next state logic
    always_comb
    begin
        entry_next = entry;

        if (rst)
        begin
            entry_next.state = EMPTY;
        end
        else if (we)
        begin
            entry_next = input_entry;
        end
        else
        begin
            unique case (entry.state)
                WAIT_FOR_STORE:
                begin
                    if (store_load_cdb.valid == 1'b1 && store_load_cdb.rob_num == entry.store_dependency)
                    begin
                        entry_next.state = WAIT_FOR_REG;
                    end
                end
                WAIT_FOR_REG:
                begin
                    if (valid_reg[entry.ps1_s] == 1'b1)
                    begin
                        entry_next.state = READY;
                    end
                end
                default:
                begin
                    entry_next.state = entry.state;
                end
            endcase
        end
    end

    always_ff @(posedge clk)
    begin
        entry <= entry_next;
    end

    // assign outputs
    assign output_entry = entry;
endmodule