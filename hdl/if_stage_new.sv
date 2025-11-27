module if_stage_new
import rv32i_types ::*; 
(
    input logic clk,
    input logic rst,

    output  logic   [31:0]  imem_addr,
    output  logic   [31:0]  imem_addr_curr,

    output  logic   [INSTR_WIDTH / 8 - 1 : 0]   imem_rmask, // change
    input   logic           imem_resp,
    input   logic   [(INSTR_WIDTH * INSTR_FETCH_NUM) - 1:0] imem_rdata, // change

    output pc_instr_t [INSTR_FETCH_NUM - 1 : 0] instr_queue_input, // change
    output logic instr_queue_push,
    input logic instr_queue_full,

    input logic mispredict,
    input brq_entry_t br_PC,

    input logic [INSTR_FETCH_NUM - 1 : 0] br_taken
);
    enum logic [0 : 0] {IF_VALID, IF_INVALID} state, state_next;
    logic [31 : 0] pc, pc_next, br_PC_reg, br_PC_reg_next;
    
    logic [31:0] pc_next_temp;
    logic [6:0] opcode[INSTR_FETCH_NUM];
    logic [31:0] b_imm[INSTR_FETCH_NUM];
    logic [31:0] j_imm[INSTR_FETCH_NUM];

    logic [31:0] imem_addr_next;

    // partially decode instructions for br/jal
    always_comb
    begin
        logic [31:0] instr;
        for (int unsigned i = 0; i < INSTR_FETCH_NUM; ++i)
        begin
            instr = imem_rdata[32*i +: 32];
            opcode[i] = instr[6:0];
            b_imm[i] = {{20{instr[31]}}, instr[7], instr[30:25], instr[11:8], 1'b0};
            j_imm[i] = {{12{instr[31]}}, instr[19:12], instr[20], instr[30:21], 1'b0};
        end
    end

    // setting state variables
    always_comb // setting state_next
    begin
        if (rst)
        begin
            state_next = IF_VALID;
        end
        else
        begin
            if (imem_resp)
            begin
                state_next = IF_VALID;
            end
            else
            begin
                if (mispredict)
                begin
                    state_next = IF_INVALID;
                end
                else
                begin
                    state_next = state;
                end
            end
        end
    end

    always_comb // setting br_PC_reg_next
    begin
        if (rst)
        begin
            br_PC_reg_next = 'x;
        end
        else 
        begin
            if (imem_resp)
            begin
                br_PC_reg_next = 'x;
            end
            else
            begin
                if (mispredict)
                begin
                    br_PC_reg_next = br_PC.branch_pc;
                end
                else
                begin
                    br_PC_reg_next = br_PC_reg;
                end
            end
        end
    end

    always_comb // setting pc_next
    begin
        if (rst)
        begin
            pc_next = 32'h60000000;
        end
        else
        begin
            if (imem_resp)
            begin
                if (mispredict == 1'b0 && state == IF_INVALID)
                begin
                    pc_next = br_PC_reg;
                end
                else if (mispredict == 1'b0 && state == IF_VALID)
                begin
                    if (instr_queue_full)
                    begin
                        pc_next = pc;
                    end
                    else
                    begin
                        // pc_next = pc + SS_FACTOR * 'd4; // TO CHANGE
                        // pc_next = {{pc_next[31:SS_FACTOR_BITS + 2]}, {(SS_FACTOR_BITS + 2)'(0)}};
                        pc_next = pc_next_temp;
                    end
                end
                else if (mispredict == 1'b1 && state == IF_INVALID) // should be impossible to reach this state
                begin
                    pc_next = 'x;
                end
                else // mispredict == 1'b1 and state == IF_VALID
                begin
                    pc_next = br_PC.branch_pc;
                end
            end
            else
            begin
                pc_next = pc;
            end
        end
    end

    // calculating pc_next_temp;
    always_comb
    begin
        pc_next_temp = pc + INSTR_FETCH_NUM *'d4;
        pc_next_temp = {{pc_next_temp[31:INSTR_FETCH_NUM_BITS + 2]}, {(INSTR_FETCH_NUM_BITS + 2)'(0)}};

        for (int unsigned i = 0; i < INSTR_FETCH_NUM; ++i)
        begin
            if (imem_addr_curr + i*'d4 >= pc) // only consider valid instructions
            begin  
                if (opcode[i] == op_jal)
                begin
                    pc_next_temp = imem_addr_curr + i*'d4 + j_imm[i];
                    break;
                end
                else if (opcode[i] == op_br && br_taken[i] == 1'b1)
                begin
                    pc_next_temp = imem_addr_curr + i*'d4 + b_imm[i];
                    break;
                end
                // predict jalr jumps to pc + 4 for now
            end
        end
    end

    always_ff @(posedge clk)
    begin
        state <= state_next;
        pc <= pc_next;
        br_PC_reg <= br_PC_reg_next;
    end

    // setting outputs
    always_comb // imem_addr_curr and imem_rmask
    begin
        imem_rmask = '1;
        imem_addr_next = {{pc_next[31:INSTR_FETCH_NUM_BITS + 2]}, {(INSTR_FETCH_NUM_BITS + 2)'(0)}}; //changed
        imem_addr_curr = {{pc[31:INSTR_FETCH_NUM_BITS + 2]}, {(INSTR_FETCH_NUM_BITS + 2)'(0)}}; //change
        imem_addr = imem_resp ? imem_addr_next : imem_addr_curr;
    end

    // always_comb // instr_queue_input
    // begin
    //     instr_queue_input = {pc, imem_rdata}; //change (valid bit first)
    //     for(int unsigned i = 0; i < SS_FACTOR; i++) begin
    //         instr_queue_input[i] = '0;
    //         if(imem_addr_curr + i * 4 >= pc) begin
    //             instr_queue_input[i].valid = 1'b1;
    //             instr_queue_input[i].pc = imem_addr_curr + i * 4;
    //             instr_queue_input[i].instruction = imem_rdata[32 * i +: 32];
    //         end
    //     end
    // end

    always_comb // instr_queue_input
    begin
        for (int unsigned i = 0; i < INSTR_FETCH_NUM; ++i)
        begin
            instr_queue_input[i] = '0;
        end

        for (int unsigned i = 0; i < INSTR_FETCH_NUM; ++i)
        begin
            if (imem_addr_curr + i*'d4 >= pc)
            begin
                instr_queue_input[i].valid = 1'b1;
                instr_queue_input[i].pc = imem_addr_curr + i * 4;
                instr_queue_input[i].instruction = imem_rdata[32 * i +: 32];
                instr_queue_input[i].br_taken_pred = 1'b0;

                if (opcode[i] == op_jal)
                begin
                    instr_queue_input[i].br_taken_pred = 1'b1; // doesn't really matter for jumps, but just set it to 1 for now (for compatibility with alu_cmp_fu)
                    break;
                end
                else if (opcode[i] == op_br && br_taken[i] == 1'b1)
                begin
                    instr_queue_input[i].br_taken_pred = 1'b1; // we predict that the branch has been taken
                    break;
                end
                // again, predict jalr jumps to pc + 4
            end
        end
    end

    always_comb // instr_queue_push
    begin
        if (imem_resp)
        begin
            if ((instr_queue_full == 1'b0) && (mispredict == 1'b0) && (state == IF_VALID))
            begin
                instr_queue_push = 1'b1;
            end
            else
            begin
                instr_queue_push = 1'b0;
            end
        end
        else
        begin
            instr_queue_push = 1'b0;
        end
    end
endmodule: if_stage_new