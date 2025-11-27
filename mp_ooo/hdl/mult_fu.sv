module mult_fu
import rv32i_types::*;
(
    input logic clk, rst, branch_mispredict,
    input issue_fu_data_t input_data,
    input logic fu_start, cdb_ack,

    output fu_cdb_data_t output_data,
    output logic fu_busy, fu_done
);
    logic busy, done, mul_done;
    logic [63:0] product;
    fu_cdb_data_t data;

    logic [1:0] mul_type;
    logic lu, lu_next; // 0 if result is lower bits 32, 1 if result is upper 32 bits

    always_ff @(posedge clk)
    begin
        if ((rst == 1'b1) || (branch_mispredict == 1'b1))
        begin
            busy <= 1'b0;
            done <= 1'b0;
            data <= 'x;
            lu <= 'x;
        end
        else if (fu_start)
        begin
            busy <= 1'b1;
            done <= 1'b0;

            data.pd_s <= input_data.pd_s;
            data.rob_num <= input_data.rob_num;
            data.rvfi_data <= input_data.rvfi_data;

            lu <= lu_next;
        end
        else if (mul_done)
        begin
            busy <= 1'b1; // issue arbiter cannot send another multiplication yet
            done <= 1'b1;

            if (lu)
            begin
                data.pd_v <= product[63:32];
                data.rvfi_data.rd_wdata <= product[63:32]; // set rvfi data
            end
            else
            begin
                data.pd_v <= product[31:0];
                data.rvfi_data.rd_wdata <= product[31:0]; // set rvfi data
            end
        end
        else if (cdb_ack)
        begin
            busy <= 1'b0; // no longer busy after cdb reads data from fu
            done <= 1'b0;
            data <= 'x;
            lu <= 'x;
        end
    end

    always_comb
    // assign outputs
    begin
        output_data = data;
        // branch related outputs
        output_data.br_en = 1'b0;
        output_data.br_target = 'x;
        output_data.instr_pc = 'x;
        output_data.instr_is_br = 1'b0;
        output_data.br_taken = 1'b0;

        fu_busy = busy;
        fu_done = done;
    end

    always_comb 
    // selecting mul_type
    begin
        unique case (input_data.instr.r_type.funct3)
            mul:
            begin
                mul_type = 2'b00;
                lu_next = 1'b0;
            end
            mulh:
            begin
                mul_type = 2'b01;
                lu_next = 1'b1;
            end
            mulhsu:
            begin
                mul_type = 2'b10;
                lu_next = 1'b1;
            end
            mulhu:
            begin
                mul_type = 2'b00;
                lu_next = 1'b1;
            end
            default:
            begin
                mul_type = 2'bxx;
                lu_next = 1'bx;
            end
        endcase
    end

    // shift_add_multiplier #(.OPERAND_WIDTH(32)) mult_i(
    //     .clk(clk), 
    //     .rst(rst | branch_mispredict), // TODO: need to change later for branch mispredict
    //     .start(fu_start),
    //     .mul_type(mul_type),
    //     .a(input_data.ps1_v),
    //     .b(input_data.ps2_v),
    //     .p(product),
    //     .done(mul_done)
    // );
    cheese_multiplier #(.OPERAND_WIDTH(32)) mult_i(
        .clk(clk), 
        .rst(rst | branch_mispredict), // TODO: need to change later for branch mispredict
        .start(fu_start),
        .mul_type(mul_type),
        .a(input_data.ps1_v),
        .b(input_data.ps2_v),
        .p(product),
        .done(mul_done)
    );
    
endmodule