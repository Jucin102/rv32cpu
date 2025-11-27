module register_file
import rv32i_types::*;
(
    input logic clk, rst,
    input cdb_t cdb [NUM_CDB],
    input phys_reg ps1_s [NUM_ISSUE],
    input phys_reg ps2_s [NUM_ISSUE],
    input phys_reg invalid_reg [SS_FACTOR],
    input logic [SS_FACTOR - 1 : 0] invalid_mask,

    output logic [31:0] ps1_v [NUM_ISSUE],
    output logic [31:0] ps2_v [NUM_ISSUE],
    output logic [NUM_PHYS_REGS - 1 : 0] valid_reg
);
    logic [31:0] data [NUM_PHYS_REGS];
    logic [31:0] data_next [NUM_PHYS_REGS];
    logic [NUM_PHYS_REGS - 1 : 0] valid_reg_mask;
    logic [NUM_PHYS_REGS - 1 : 0] valid_reg_mask_next;

    always_ff @(posedge clk)
    begin
        data <= data_next;
        valid_reg_mask <= valid_reg_mask_next;
    end

    always_comb 
    begin
        // changing the value of data
        data_next = data;
        if (rst)
        begin
            for (int i = 0; i < NUM_PHYS_REGS; ++i)
            begin
                data_next[i] = '0;
            end
        end
        else
        begin
            for (int unsigned i = 0; i < NUM_CDB; ++i)
            begin
                if (cdb[i].valid)
                begin
                    if (cdb[i].pd_s != '0)
                    begin
                        data_next[cdb[i].pd_s] = cdb[i].pd_v;
                    end
                end
            end
        end
    end

    always_comb
    begin
        // changing the value of valid_reg_mask
        valid_reg_mask_next = valid_reg_mask;
        if (rst)
        begin
            // on reset p0 - p31 are valid
            valid_reg_mask_next = '0;
            for (int i = 0; i < 32; ++i)
            begin
                valid_reg_mask_next[i] = 1'b1;
            end
        end

        // invalidate registers from dispatch
        for (int i = 0; i < SS_FACTOR; ++i)
        begin
            if (invalid_mask[i])
            begin
                valid_reg_mask_next[invalid_reg[i]] = 1'b0;
            end
        end

        // validate registers from cdb
        for (int unsigned i = 0; i < NUM_CDB; ++i)
        begin
            if (cdb[i].valid)
            begin
                if (cdb[i].pd_s != '0)
                begin
                    valid_reg_mask_next[cdb[i].pd_s] = 1'b1;
                end
            end
        end
    end

    always_comb 
    begin
        valid_reg = valid_reg_mask;

        for (int unsigned i = 0; i < NUM_ISSUE; ++i)
        begin
            ps1_v[i] = (ps1_s[i] != '0) ? data[ps1_s[i]] : '0;
            ps2_v[i] = (ps2_s[i] != '0) ? data[ps2_s[i]] : '0;
        end
    end

endmodule