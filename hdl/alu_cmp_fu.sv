module alu_cmp_fu
import rv32i_types::*;
(
    input logic clk, rst, branch_mispredict,
    input issue_fu_data_t input_data,
    input logic fu_start, cdb_ack,

    output fu_cdb_data_t output_data,
    output logic fu_busy, fu_done
);
    logic busy, done;
    logic br_en, br_en_reg;
    logic [31:0] pd_v, pd_v_reg;
    logic [31:0] br_target, br_target_reg;
    issue_fu_data_t input_data_reg;

    // "FSM" logic
    always_ff @(posedge clk)
    begin
        if ((rst == 1'b1) || (branch_mispredict == 1'b1))
        begin
            busy <= 1'b0;
            done <= 1'b0;
            pd_v_reg <= 'x;
            br_target_reg <= 'x;
            input_data_reg <= 'x;
            br_en_reg <= 1'b0; // set to 1'b0 so that in ROB, we can set branch_mispredicted to br_en from CDB
        end
        else if ((busy == 1'b0) && (done == 1'b0) && (fu_start == 1'b1))
        begin
            busy <= 1'b1;
            done <= 1'b0;
            input_data_reg <= input_data;
        end
        else if (busy == 1'b1 && done == 1'b0) // get rid of this state to decrease alu/cmp latency to 1 clk
        begin
            busy <= 1'b1;
            done <= 1'b1;
            pd_v_reg <= pd_v;
            br_target_reg <= br_target;
            br_en_reg <= br_en;
        end
        else if ((busy == 1'b1) && (done == 1'b1) && (cdb_ack == 1'b1))
        begin
            busy <= 1'b0;
            done <= 1'b0;
            pd_v_reg <= 'x;
            br_target_reg <= 'x;
            input_data_reg <= 'x;
            br_en_reg <= 1'b0;
        end
    end

    // combinationally calculate output
    logic [2:0] funct3;
    logic [6:0] funct7;
    logic [6:0] opcode;
    logic [31:0] i_imm, s_imm, b_imm, u_imm, j_imm;
    logic [31:0] instr;
    logic [31:0] pc;
    logic [31:0] ps1_v, ps2_v;

    logic [31:0] alu_a, alu_b, cmp_a, cmp_b, alu_out;
    logic [2:0] aluop, cmpop;
    logic cmp_out;
    
    // decode instruction
    always_comb
    begin
        instr = input_data_reg.instr.word;
        pc = input_data_reg.pc;
        ps1_v = input_data_reg.ps1_v;
        ps2_v = input_data_reg.ps2_v;

        funct3 = instr[14:12];
        funct7 = instr[31:25];
        opcode = instr[6:0];
        i_imm  = {{21{instr[31]}}, instr[30:20]};
        s_imm  = {{21{instr[31]}}, instr[30:25], instr[11:7]};
        b_imm  = {{20{instr[31]}}, instr[7], instr[30:25], instr[11:8], 1'b0};
        u_imm  = {instr[31:12], 12'h000};
        j_imm  = {{12{instr[31]}}, instr[19:12], instr[20], instr[30:21], 1'b0};
    end

    // calculate pd_v
    alu alu(
        .f(alu_out),
        .a(alu_a),
        .b(alu_b),
        .aluop(aluop)
    );

    cmp cmp(
        .cmpop(cmpop),
        .a(cmp_a),
        .b(cmp_b),
        .br_en(cmp_out)
    );

    always_comb
    begin
        alu_a = 'x;
        alu_b = 'x;
        cmp_a = 'x;
        cmp_b = 'x;
        aluop = 'x;
        cmpop = 'x;
        pd_v = 'x;
        br_en = 1'b0;
        br_target = 'x;
        unique case (opcode)
            op_lui:
            begin
                pd_v = u_imm;
            end
            op_auipc:
            begin
                alu_a = pc;
                alu_b = u_imm;
                aluop = alu_add;
                pd_v = alu_out;
            end
            op_imm:
            begin
                alu_a = ps1_v;
                alu_b = i_imm;
                cmp_a = ps1_v;
                cmp_b = i_imm;
                unique case (funct3)
                    slt: begin
                        cmpop = blt;
                        pd_v = {31'd0, cmp_out};
                    end
                    sltu: begin
                        cmpop = bltu;
                        pd_v = {31'd0, cmp_out};
                    end
                    sr: begin
                        if (funct7[5]) begin
                            aluop = alu_sra;
                        end else begin
                            aluop = alu_srl;
                        end
                        pd_v = alu_out;
                    end
                    default: begin
                        aluop = funct3;
                        pd_v = alu_out;
                    end
                endcase
            end
            op_reg:
            begin
                alu_a = ps1_v;
                alu_b = ps2_v;
                cmp_a = ps1_v;
                cmp_b = ps2_v;
                unique case (funct3)
                    slt: begin
                        cmpop = blt;
                        pd_v = {31'd0, cmp_out};
                    end
                    sltu: begin
                        cmpop = bltu;
                        pd_v = {31'd0, cmp_out};
                    end
                    sr: begin
                        if (funct7[5]) begin
                            aluop = alu_sra;
                        end else begin
                            aluop = alu_srl;
                        end
                        pd_v = alu_out;
                    end
                    add: begin
                        if (funct7[5]) begin
                            aluop = alu_sub;
                        end else begin
                            aluop = alu_add;
                        end
                        pd_v = alu_out;
                    end
                    default: begin
                        aluop = funct3;
                        pd_v = alu_out;
                    end
                endcase
            end
            op_jal:
            begin
                pd_v = pc + 'd4;
                br_target = pc + j_imm;
                br_en = 1'b1;
            end
            op_jalr:
            begin
                pd_v = pc + 'd4;
                br_target = (ps1_v + i_imm) & 32'hfffffffe; // probably can be optimized
                br_en = 1'b1;
            end
            op_br:
            begin
                cmpop = funct3;
                cmp_a = ps1_v;
                cmp_b = ps2_v;
                br_target = pc + b_imm;
                br_en = cmp_out;
            end
            default:
            begin
                alu_a = 'x;
                alu_b = 'x;
                cmp_a = 'x;
                cmp_b = 'x;
                aluop = 'x;
                cmpop = 'x;
                pd_v = 'x;
                br_en = 1'b0;
                br_target = 'x;
            end
        endcase
    end

    // calculate alu_cmp_fu outputs
    always_comb
    begin
        fu_busy = busy;
        fu_done = done;

        output_data.pd_s = input_data_reg.pd_s;
        output_data.rob_num = input_data_reg.rob_num;
        output_data.pd_v = pd_v_reg;
        output_data.rvfi_data = input_data_reg.rvfi_data;
        output_data.rvfi_data.rd_wdata = pd_v_reg;
        if (br_en_reg) // change rvfi next pc for jmps and branches
        begin
            output_data.rvfi_data.pc_wdata = br_target_reg; 
        end
        // output_data.br_en = br_en_reg; 
        if (br_en_reg != input_data_reg.br_taken_pred)
        begin
            output_data.br_en = 1'b1; // for backwards compatibility, repurpose br_en as mispredict signal
        end
        else
        begin
            output_data.br_en = 1'b0;
        end
        // output_data.br_target = br_target_reg; // br_target is repurposed to be the destination of control instruction, so not always target
        if (br_en_reg)
        begin
            output_data.br_target = br_target_reg;
        end
        else
        begin
            output_data.br_target = input_data_reg.pc + 'd4; // if branch not taken, then its "target" should be pc + 4
        end

        output_data.instr_pc = input_data_reg.pc;
        output_data.instr_is_br = (opcode == op_br);
        output_data.br_taken = br_en_reg;
    end

endmodule