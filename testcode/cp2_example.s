.section .text
.globl _start
    # Refer to the RISC-V ISA Spec for the functionality of
    # the instructions in this test program.
# cheese:          .word 0x60000900
_start:
    # Note that the comments in this file should not be taken as
    # an example of good commenting style!!  They are merely provided
    # in an effort to help you understand the assembly style.
    addi x10, x0, 0
    auipc x10, 0
    addi x10, x10, -4
    addi x1, x0, 4  # x1 <= 4
    addi x3, x1, 8  # x3 <= x1 + 8
    sub  x3, x3, x1
    addi x3, x3, 5
    lui  x3, 1234
    auipc x3, 40
    nop
    nop
    nop
    addi x1, x0, 5
    addi x2, x1, 4
    lui x9, 5124
    addi x9, x9, 15
    auipc x7, 40
    sw x9, 0(x7)
    nop
    nop
    nop
    addi x8, x7, -4
    addi x1, x1, 5
    addi x1, x1, 5
    lw x1, bad
    lw x1, 0(x1)
    addi x1, x1, 5
    addi x1, x1, 5
    sh x9, 2(x7)
    lhu x1, 2(x7)
    sb x9, 3(x7)
    lb x1, 3(x7)
    lh x1, 4(x8)
    addi x1, x0, 4
    addi x2, x1, 0
    nop
    nop
    addi x1, x0, 4
    # addi x2, x0, 4
    lh x2, 0(x7)
    # ble x1, x2, br
    addi x3, x0, 5
    addi x4, x0, -5
    auipc x1, 40
    auipc x2, 0
    addi x2, x2, -172
    addi x1, x10, 0
    # sw x1, 4(x7)
    lw x1, 0(x10)
    beq x1, x2, br
    jal x3, br
    jalr x1, 4(x1)
    nop
    nop
    nop
    nop
br: 
    addi x1, x0, -4
    addi x2, x0, -2
    # bge x2, x1, nuts
    # bgeu x1, x2, nuts
    addi x1, x0, 4
    jal x1, nuts
    addi x1, x1, 5
    jal x1, ligma
    nop
nuts:
    nop
    nop
    nop
    nop
    auipc x1, 123
    lw x2, bad
    lw x1, a
    jalr x2, 40(x1)
    addi x1, x0, 4
    nop
    nop
    addi x1, x1, 40
    nop
    # jalr x1, -4(x1)
    nop
    nop
    nop
    nop
ligma:
    nop
    nop
    nop
    nop
    lw x1, a
    addi x1, x0, 4
    addi x2, x0, 5

    addi x1, x0, 5
    addi x2, x0, 10
    # lw x1, bad
    lw x2, b
    lw x1, bad
    blt x1, x2, halt
    lw x1, a
    addi x1, x2, 5


    # Add your own test cases here!
bofa:
    auipc x1, 0
    sw x1, 48(x1)
    lw x2, s
    jalr x2, 20(x2)
    lw x3, bad
    add x3, x3, x1

halt:
    # bltu x1, x2, halt
    slti x0, x0, -256 # this is the magic instruction to end the simulation


bad:        .word 0x60000040
b:          .word 0x60000000
a:          .word 0x600000f4
s:          .word 0xb0fa0000