.section .text
.globl _start
    # Refer to the RISC-V ISA Spec for the functionality of
    # the instructions in this test program.
_start:
    # Note that the comments in this file should not be taken as
    # an example of good commenting style!!  They are merely provided
    # in an effort to help you understand the assembly style.

    addi x1, x0, 4  # x1 <= 4
    nop
    nop
    nop             # nops in between to prevent hazard
    nop
    addi x3, x1, 8  # x3 <= x1 + 8
    nop
    nop
    nop
    auipc x5, 30
    nop
    nop
    nop
    lui x20, 500
    nop
    nop
    nop
    sltu x3, x0, x4
    slti x3, x0, 5
    nop
    nop
    nop
    sub x4, x3, x5
    nop
    nop
    nop
    

    # Add your own test cases here!

    slti x0, x0, -256 # this is the magic instruction to end the simulation
