.section .text
.globl _start
    # Refer to the RISC-V ISA Spec for the functionality of
    # the instructions in this test program.
_start:
    # Note that the comments in this file should not be taken as
    # an example of good commenting style!!  They are merely provided
    # in an effort to help you understand the assembly style.
    jal x1, _skip_1

    # Add your own test cases here!
    addi x1, x0, 4
    addi x2, x1, 8
    addi x3, x1, 9
    addi x4, x1, 10
    addi x6, x1, 11

_skip_1:
    addi x2, x0, 0
    addi x3, x2, 1
    la x1, _skip_2
    addi x1, x1, -1
    addi x4, x2, 2
    addi x6, x2, 3

_skip_2:
    addi x2, x0, 0
    addi x3, x2, 4
    addi x4, x2, 5
    addi x6, x2, 6

    bne x6, x4, _branch_target
    addi x7, x0, 0

_branch_target:
    beq x6, x6, _halt
    addi x7, x0, 1




    slti x0, x0, -256 # this is the magic instruction to end the simulation

_halt:
    addi x2, x0, 0
    addi x3, x2, 4
    addi x4, x2, 5
    addi x6, x2, 6
    slti x0, x0, -256 # this is the magic instruction to end the simulation

_data: .word 0x4