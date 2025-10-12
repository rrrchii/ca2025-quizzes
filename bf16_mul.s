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
    # TC1: 1.5 * 0.5 = 0.75
    # a = 0x3FC0 (1.5), b = 0x3F00 (0.5), exp = 0x3F40 (0.75)
    li      a0, 0x3FC0            # a = 1.5 (bf16)
    li      a1, 0x3F00            # b = 0.5 (bf16)
    jal     ra, bf16_mul
    li      t0, 0x3F40            # expected = 0.75 (bf16)
    bne     a0, t0, 1f            # if result != expected -> fail++
    j       2f
1:
    addi    s10, s10, 1
2:

    # ------------- case2 (edge) --------
    # TC2 (edge): +Inf * +0 = NaN
    # a = 0x7F80 (+Inf), b = 0x0000 (+0)
    li      a0, 0x7F80            # +Inf
    li      a1, 0x0000            # +0
    jal     ra, bf16_mul
    li      t1, 0x7F80
    and     t2, a0, t1            # �� exponent bits
    bne     t2, t1, 3f            # exp != 0xFF -> fail
    andi    t3, a0, 0x7F          # �� mantissa
    beqz    t3, 3f                # mant == 0 -> ���O NaN -> fail
    j       4f
3:
    addi    s10, s10, 1
4:

    # ------------- case3 ---------------
    # TC3: (-2.0) * (-0.5) = +1.0
    # a = 0xC000 (-2.0), b = 0xBF00 (-0.5), exp = 0x3F80 (+1.0)
    li      a0, 0xC000            # -2.0 (bf16)
    li      a1, 0xBF00            # -0.5 (bf16)
    jal     ra, bf16_mul
    li      t0, 0x3F80            # +1.0 (bf16)
    bne     a0, t0, 5f
    j       6f
5:
    addi    s10, s10, 1
6:


    # ----------------------------
    # print result
    # ----------------------------
    beqz    s10, print_pass       # fail_count == 0 �� pass
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


bf16_mul:
    srli    t0, a0, 15            
    andi    t0, t0, 1             # t0 = sign_a (0/1)

    srli    t1, a1, 15            # t1 = sign_b (0/1)
    andi    t1, t1, 1

    srli    t2, a0, 7             
    andi    t2, t2, 0xFF          # t2 = exp_a (8-bit)
    srli    t3, a1, 7             
    andi    t3, t3, 0xFF          # t3 = exp_b (8-bit)

    andi    t4, a0, 0x7F          # t4 = mant_a (7-bit)
    andi    t5, a1, 0x7F          # t5 = mant_b (7-bit)
    
    xor     s0, t0, t1            # s0 = result_sign
    
    li      a4, 0xFF
    bne     t2, a4, 1f            # exp_a != 0xFF ?
    bnez    t4, nan               # mant_a != 0 => NaN
    
1:
    bne     t3, a4, 2f            # exp_b != 0xFF ?
    bnez    t5, nan               # mant_b != 0 => NaN
    
2:
    beq     t2, a4, 3f
    j       4f

3:  beqz    t3, 5f
    j       4f
    
5:   
    beqz    t5, nan                # a = Inf b = 0 return nan
4:
    bne     t3, a4, 6f             
    beqz    t2, 7f
    j       6f
7:
    beqz    t4, nan                # b = Inf a = 0 return nan
6:
    beq     t2, a4, inf
    beq     t3, a4, inf
    
    beqz    t2, 8f
    j       9f
    
8:  
    beqz    t4, zero
    
9:
    beqz    t3, 10f
    j       11f
    
10:
    beqz    t5, zero

11:
    li      a2, 0
    
    beqz    t2, 12f
    li      s7, 0x80
    or      t4, t4, s7
    j       13f
12:                               # while (!(mant_a & 0x80)) { mant_a <<=1; exp_adjust--; }
    andi    a4, t4, 0x80          # (mant_a & 0x80)
    bnez    a4, done_adjust_a
    slli    t4, t4, 1
    addi    a2, a2, -1
    j       12b
    
done_adjust_a:
    li      t2, 1
    
13:
    beqz    t3, 14f
    ori     t5, t5, 0x80
    j       15f
    
14:
    andi    a4, t5, 0x80
    bnez    a4, done_adjust_b
    slli    t5, t5, 1
    addi    a2, a2, -1
    j       14b
    
done_adjust_b:
    li      t3, 1

15:
    li      a3, 0
    li      a4, 8
    
mul_loop:
    andi    a5, t5, 1
    beqz    a5, skip_add
    add     a3, a3, t4
    
skip_add:
    slli    t4, t4, 1
    srli    t5, t5, 1
    addi    a4, a4, -1
    bnez    a4, mul_loop

    # result_exp = exp_a + exp_b - 127 + exp_adjust
    add     a4, t2, t3            # exp_a + exp_b
    add     a4, a4, a2            # + exp_adjust
    addi    a4, a4, -127          # BF16_EXP_BIAS
    
    li      a5, 0x8000
    and     a5, a3, a5
    beqz    a5, no_big
    srli    a3, a3, 8
    andi    a3, a3, 0x7F
    addi    a4, a4, 1
    j       scaled
    
no_big:
    srli    a3, a3, 7
    andi    a3, a3, 0x7F
    
scaled:
    li      a5, 0xFF
    ble     a5, a4, inf
    
    blez    a4, underflow
    
    slli    t0, t6, 15            # sign
    andi    t1, a4, 0xFF
    slli    t1, t1, 7             # exp<<7
    or      t0, t0, t1
    or      t0, t0, a3            # + mant
    andi    a0, t0, 0xFF
    ret
inf:
    slli    a0, s0, 15
    li      s8, 0x7F80
    or      a0, a0, s8
    ret

zero:
    slli    a0, s0, 15            # ��0
    ret

nan:
    li      a0, 0x7FC0           # NaN
    ret
    
underflow:
    li      a5, -6
    blt     a4, a5, zero
    
    li      a5, 1
    sub     a5, a5, a4

shift_dn:
    beqz    a5, pack_den
    srli    a3, a3, 1
    addi    a5, a5, -1
    j       shift_dn
pack_den:
    andi    a3, a3, 0x7F
    slli    t0, t6, 15            # sign
    or      t0, t0, a3            # exp=0
    andi    a0, t0, 0xFF
    ret
