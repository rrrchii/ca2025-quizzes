.data
msg_pass:
    .asciz "tests pass\n"
msg_fail:
    .asciz "some tests fail\n"


.text
.globl main
main:
    li      s10, 0                 # fail_count = 0

    # ------------- case1 ---------------
    # TC1: 1.5 / 0.5 = 3.0
    # a = 0x3FC0 (1.5), b = 0x3F00 (0.5), exp = 0x4040 (3.0)
    li      a0, 0x3FC0            # a = 1.5 (bf16)
    li      a1, 0x3F00            # b = 0.5 (bf16)
    jal     ra, bf16_div
    li      t0, 0x4040            # expected = 3.0 (bf16)
    bne     a0, t0, 1f            # if result != expected -> fail++
    j       2f
1:
    addi    s10, s10, 1
2:

    # ------------- case2 (edge) --------
    # TC2 (edge): +2.0 / +0 = +Inf
    # a = 0x4000 (+2.0), b = 0x0000 (+0), exp = 0x7F80 (+Inf)
    li      a0, 0x4000            # +2.0 (bf16)
    li      a1, 0x0000            # +0
    jal     ra, bf16_div
    li      t1, 0x7F80            # +Inf exponent/mantissa pattern
    bne     a0, t1, 3f            # 直接比對 == +Inf（正號、尾數=0）
    j       4f
3:
    addi    s10, s10, 1
4:

    # ------------- case3 ---------------
    # TC3: (-2.0) / (-0.5) = +4.0
    # a = 0xC000 (-2.0), b = 0xBF00 (-0.5), exp = 0x4080 (+4.0)
    li      a0, 0xC000            # -2.0 (bf16)
    li      a1, 0xBF00            # -0.5 (bf16)
    jal     ra, bf16_div
    li      t0, 0x4080            # +4.0 (bf16)
    bne     a0, t0, 5f
    j       6f
5:
    addi    s10, s10, 1
6:

    # ----------------------------
    # print result
    # ----------------------------
    beqz    s10, print_pass       # fail_count == 0 -> pass
    la      a0, msg_fail
    li      a7, 4                 # print_string
    ecall
    j       exit

print_pass:
    la      a0, msg_pass
    li      a7, 4                 # print_string
    ecall

exit:
    li      a7, 10                # exit
    ecall

bf16_div:
    srli    t0, a0, 15
    andi    t0, t0, 1

    srli    t1, a1, 15
    andi    t1, t1, 1

    srli    t2, a0, 7
    andi    t2, t2, 0xFF

    srli    t3, a1, 7
    andi    t3, t3, 0xFF

    andi    t4, a0, 0x7F
    andi    t5, a1, 0x7F

    xor     a2, t0, t1
    
check_b_FF:
    addi    t6, x0, 255
    bne     t3, t6, check_b_zerocase

    bne     t5, x0, ret_b
    bne     t2, t6, zero
    beq     t4, x0, nan
    jal     x0, zero

check_b_zerocase:
    bne     t3, x0, check_a_FF
    bne     t5, x0, check_a_FF
    bne     t2, x0, inf
    beq     t4, x0, nan
    jal     x0, inf

check_a_FF:
    bne     t2, t6, check_a_zerocase
    bne     t4, x0, ret_a
    jal     x0, inf

check_a_zerocase:
    bne     t2, x0, implict_1_a
    beq     t4, x0, zero

implict_1_a:
    beq     t2, x0, implict_1_b
    ori     t4, t4, 0x80
    
implict_1_b:
    beq     t3, x0, start_divide
    ori     t5, t5, 0x80
    
start_divide:
    slli    a4, t4, 15
    addi    a5, x0, 0

    slli    t6, t5, 15

    addi    t0, x0, 16

div_loop:
    slli    a5, a5, 1

    sltu    t1, a4, t6
    bne     t1, x0, no_sub
    sub     a4, a4, t6
    ori     a5, a5, 1   
no_sub:
    srli    t6, t6, 1
    addi    t0, t0, -1
    bne     t0, x0, div_loop
    
result_exp:
    sub     a3, t2, t3
    addi    a3, a3, 127

    beq     t2, x0, dec_exp_a
    jal     x0, chk_exp_b
dec_exp_a:
    addi    a3, a3, -1

chk_exp_b:
    beq     t3, x0, inc_exp_b
    jal     x0, norm_q
inc_exp_b:
    addi    a3, a3, 1

norm_q:
    lui     t0, 0x8
    and     t1, a5, t0
    beq     t1, x0, shift_left_phase

    srli    a5, a5, 8
    jal     x0, combine_all_component

shift_left_phase:
norm_loop:
    and     t1, a5, t0
    bne     t1, x0, after_left_norm
    addi    t1, x0, 1
    slt     t1, t1, a3
    beq     t1, x0, after_left_norm
    slli    a5, a5, 1
    addi    a3, a3, -1
    jal     x0, norm_loop

after_left_norm:
    srli    a5, a5, 8

combine_all_component:
    andi    a5, a5, 0x7F

    addi    t0, x0, 255
    bge     a3, t0, inf

    beq     a3, x0, zero
    slt     t1, a3, x0
    bne     t1, x0, zero

    andi    t0, a3, 255
    slli    t0, t0, 7
    slli    a0, a2, 15
    or      a0, a0, t0
    or      a0, a0, a5
    jalr    x0, ra, 0


ret_a:
    addi    a0, a0, 0
    jalr    x0, ra, 0

ret_b:
    addi    a0, a1, 0
    jalr    x0, ra, 0

inf:
    slli    a0, a2, 15
    addi    t0, x0, 255
    slli    t0, t0, 7
    or      a0, a0, t0
    jalr    x0, ra, 0

nan:
    addi    t0, x0, 255
    slli    t0, t0, 7
    ori     a0, t0, 0x40
    jalr    x0, ra, 0

zero:
    slli    a0, a2, 15
    jalr    x0, ra, 0
