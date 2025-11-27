.section .text
.globl _start
    # Refer to the RISC-V ISA Spec for the functionality of
    # the instructions in this test program.
_start:
    auipc x1, 0
    jalr 40(x1)
    
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    addi x2, x1, 5
    addi x3, x2, 1
    addi x1, x2, 1



    slti x0, x0, -256 # this is the magic instruction to end the simulation
