.section .text
.globl _start
    # Refer to the RISC-V ISA Spec for the functionality of
    # the instructions in this test program.
_start:
    # Note that the comments in this file should not be taken as
    # an example of good commenting style!!  They are merely provided
    # in an effort to help you understand the assembly style.
    
    # what happens when we try to write to x0 in register operations
    auipc x0, 20
    addi x1, x0, 4
    addi x0, x1, 4

    # spam loads
    la x1, _loc_2
    lw x0, 0(x1)
    lbu x0, 1(x1)
    lb x0, 1(x1)
    lh x0, 2(x1)
    lhu x0, 2(x1)

    lw x1, _loc_2
    lhu x2, _loc_2
    lh x3, _loc_2
    lbu x4, _loc_2
    lb x6, _loc_2
    lw x6, _loc_2
    lhu x4, _loc_2
    lh x3, _loc_2
    lbu x2, _loc_2
    lb x1, _loc_2

    # test specific offsets
    la x1, _loc_2
    lh x2, 2(x1)
    lhu x3, 2(x1)
    lb x4, 3(x1)
    lbu x6, 3(x1)
    lb x7, 1(x1)
    lbu x8, 1(x1)

    # spam stores
    la x2, _loc_3
    lw x1, _loc_2
    sw x1, 0(x2)
    sw x1, 8(x2)
    sh x1, 0(x2)
    sb x1, 5(x2)
    sh x1, 6(x2)
    sb x1, 0(x2)

    slti x0, x0, -256 # this is the magic instruction to end the simulation

_loc_1: .word 0x4
_loc_2: .word 0x76543210
_loc_3: .word 0xa5a5a5a5