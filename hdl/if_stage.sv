module if_stage
import rv32i_types ::*; 
(
    input logic clk,
    input logic rst,

    output  logic   [31:0]  imem_addr,
    output  logic   [INSTR_WIDTH / 8 - 1 : 0]   imem_rmask,
    input   logic           imem_resp,
    input   logic   [INSTR_WIDTH - 1:0] imem_rdata,

    output logic    [INSTR_WIDTH * 2 - 1 : 0] instr_queue_input,
    output logic instr_queue_push,
    input logic instr_queue_full,

    input logic mispredict,
    input brq_entry_t br_PC
);

    // might need to store imem_addr of the previous clock cycle to push into instr queue

    logic [31:0] pc, pc_inc, pc_rvfi, pc_next;

    always_ff @ (posedge clk) begin
        if(rst) begin
            pc <= 32'h60000000;
            pc_rvfi <= 32'h60000000;
        end else if (imem_resp && !instr_queue_full || mispredict) begin
            pc <= pc_next; // this should be pc_next, use pc_inc for now becuase there's no branching
            pc_rvfi <= imem_addr;
        end else begin
            pc <= pc;
            pc_rvfi <= imem_addr;
        end
    end

    // reading instruction from imem
    always_comb begin
        imem_addr = pc;
        imem_rmask = '1;
        if (!rst && !instr_queue_full && imem_resp || mispredict) begin
            imem_addr = pc_next; // use pc_next when we have branches
        end
    end

    // pc update logic. fill in later.
    always_comb begin
        pc_inc = pc + 4;
        unique case (mispredict)
            0: begin
                pc_next = pc_inc;
            end
            1: begin
                pc_next = br_PC.branch_pc;
            end
            default: begin
                pc_next = pc_inc;
            end
        endcase 
    end

    // push into queue
    always_comb begin
        instr_queue_input = '0;
        instr_queue_push = '0;
        if (!rst && imem_resp && !instr_queue_full) begin
            instr_queue_input = {pc_rvfi, imem_rdata};
            instr_queue_push = 1'b1;
        end
    end

endmodule: if_stage