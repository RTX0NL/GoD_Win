.section .text1


.global sym_0
sym_0:
_prolog:
    blr
    nop

.global sym_1
sym_1:
    lis r3, dol_00001234@ha
    addi r3, r3, dol_00001234@l
    stw r3, 0x8(r1)
    li r0, 0x1
    .4byte sym_0
    blr
