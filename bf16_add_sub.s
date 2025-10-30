.data
msg_pass:
    .asciz "tests pass\n"
msg_fail:
    .asciz "some tests fail\n"

    
.text
.globl main
main:
    li      s10, 0                 # fail_count = 0

    # ------------- case1(add) ---------------
    # TC1: 0x0000 + 0x3FC0 (0 + 1.5) = 0x3FC0 (1.5)
    # ----------------------------
    li      a0, 0x0000            # a = +0
    li      a1, 0x3FC0            # b = 1.5 (bf16)
    jal     ra, bf16_add
    li      t0, 0x3FC0
    bne     a0, t0, 1f            # if result != expected -> fail++
    j       2f
1:
    addi    s10, s10, 1
2:

    # ------------- case2(add) ---------------
    # TC2 (edge): +Inf + (-Inf) = NaN
    # a = 0x7F80 (+Inf), b = 0xFF80 (-Inf)
    # ----------------------------
    li      a0, 0x7F80            # +Inf
    li      a1, 0xFF80            # -Inf
    jal     ra, bf16_add
    li      t1, 0x7F80
    and     t2, a0, t1            # �� exponent bits
    bne     t2, t1, 3f            # exp != 0xFF -> fail
    andi    t3, a0, 0x7F          # �� mantissa
    beqz    t3, 3f                # mant == 0 -> ���O NaN -> fail
    j       4f
3:
    addi    s10, s10, 1
4:

    # ------------- case3(add) ---------------
    # TC3: 0x3FC0 + 0x3F00 (1.5 + 0.5) = 0x4000 (2.0)
    # ----------------------------
    li      a0, 0x3FC0            # 1.5 (bf16)
    li      a1, 0x3F00            # 0.5 (bf16)
    jal     ra, bf16_add
    li      t0, 0x4000            # 2.0 (bf16)
    bne     a0, t0, 5f
    j       6f
5:
    addi    s10, s10, 1
6:

    # ------------- case4(sub) ---------------
    # TC4:0x0000 - 0x3FC0 (0 - 1.5) = 0xBFC0 (-1.5)
    # ----------------------------
    li      a0, 0x0000            # a = +0
    li      a1, 0x3FC0            # b = 1.5 (bf16)
    jal     ra, bf16_sub
    li      t0, 0xBFC0            # -1.5 (bf16)
    bne     a0, t0, 7f
    j       8f
7:
    addi    s10, s10, 1
8:

    # ------------- case5(sub) ---------------
    # TC5:+Inf - (-Inf) = +Inf
    # a = 0x7F80 (+Inf), b = 0xFF80 (-Inf)
    # ----------------------------
    li      a0, 0x7F80            # +Inf
    li      a1, 0xFF80            # -Inf
    jal     ra, bf16_sub
    li      t0, 0x7F80            # +Inf
    bne     a0, t0, 9f
    j       10f
9:
    addi    s10, s10, 1
10:

    # ------------- case6(sub) ---------------
    # TC6:0x3FC0 - 0x3F00 (1.5 - 0.5) = 0x3F80 (1.0)
    # ----------------------------
    li      a0, 0x3FC0            # 1.5 (bf16)
    li      a1, 0x3F00            # 0.5 (bf16)
    jal     ra, bf16_sub
    li      t0, 0x3F80            # 1.0 (bf16)
    bne     a0, t0, 11f
    j       12f
11:
    addi    s10, s10, 1
12:


    # ----------------------------
    # print result
    # ----------------------------
    beqz    s10, print_pass       # if (fail_count == 0) >> pass
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


bf16_add:
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
    
    li      t6, 0xFF
    bne     t2, t6, check_exp_b_FF
    beqz    t4, a_is_Inf
    
    mv      a0, a0
    ret                           # a is NaN
    
a_is_Inf:
    bne     t3, t6, ret_a_inf     # a is Inf b is not NaN or Inf
    bnez    t5, ret_b             # b is NaN return b
    bne     t0, t1, nan           # +Inf + -Inf = NaN

ret_b:
    mv      a0, a1
    ret                           # b is NaN

ret_a_inf:
    mv      a0, a0
    ret                           # a and b are same sign Inf

check_exp_b_FF:                   # a is not NaN or Inf
    bne     t3, t6, check_a_zero  # b is not NaN or Inf either
    mv      a0, a1                # b is NaN return NaN, b is Inf return Inf
    ret
    
check_a_zero:
    bnez    t2, check_b_zero      
    bnez    t4, check_b_zero      
    
    mv      a0, a1                # a is zero
    ret                           # return b
    
check_b_zero:
    bnez    t3, add_implict1
    bnez    t5, add_implict1      # a and b are not NaN Inf zero
    
    mv      a0, a0                # b is zero 
    ret                           # return a
add_implict1:
    beqz    t2, a_no_implict1
    ori     t4, t4, 0x80
     
a_no_implict1:
    beqz    t3, b_no_implict1
    ori     t5, t5, 0x80
b_no_implict1:
    
    sub     t6, t2, t3           # t6 <- exp_diff
    bgez    t6, exp_diff_ge0    
    
    mv      s0, t3              # s0 = result_exp <- exp_b
    li      s1, -8
    blt     t6, s1, ret_b       # a is too small
    
    neg     s1, t6              # s1 = -exp_diff
    srl     t4, t4, s1
    j       exp_aligned
    
exp_diff_ge0:
    beqz    t6, exp_equal
    mv      s0, t2              # s0 = result_exp <- exp_a
    li      s1, 8
    bgt     t6, s1, ret_a       # b is too small
    
    srl     t5, t5, t6
    j       exp_aligned
    
exp_equal:
    mv      s0, t2              # s0 = result_exp <- exp_a

exp_aligned:
    bne     t0, t1, diff_sign
    mv      s2, t0              # s2 = result_sign <- sign_a
    add     s3, t4, t5          # s3 = result_mant <- mant_a + mant_b
    
    andi    s5, s3, 0x100       # check is matissa overflow ?
    beqz    s5, pack            
    srli    s3, s3, 1
    addi    s0, s0, 1
    li      s4, 0xFF
    blt     s0, s4, pack        # check is exp overflow
    
    li      a0, 0x7F80          
    slli    s2, s2, 15
    or      a0, a0, s2
    ret                         # exp overflow return +-Inf
    
diff_sign:
    blt     t4, t5, b_bigger
    mv      s2, t0              # s2 = result_sign <- sign_a
    sub     s3, t4, t5          # s3 = result_mant <- mant_a - mant_b
    j       after_sub
    
b_bigger:
    mv      s2, t1              # s2 = result_sign <- sign_b
    sub     s3, t5, t4          # s3 = result_mant <- mant_b - mant_a
    
after_sub:
    beqz    s3, ret_zero
    
norm_loop:
    andi    s5, s3, 0x80
    bnez    s5, pack           # while (!(result_mant & 0x80))
    slli    s3, s3, 1
    addi    s0, s0, -1
    blez    s0, ret_zero
    j       norm_loop
    
pack:                          # s0 : result_exp s2 : result_sign s3 : result_mant
    andi    s3, s3, 0x7F
    andi    s0, s0, 0xFF
    slli    s0, s0, 7
    slli    s2, s2, 15
    or      a0, s0, s3
    or      a0, a0, s2
    ret
     
ret_a:
    mv      a0, a0
    ret
nan:
    li      a0, 0x7FC0           
    ret
    
ret_zero:
    mv      a0, x0               
    ret
    
    
bf16_sub:
    li      t0, 0x8000
    xor     a1, a1, t0             # reverse b
    j       bf16_add               
