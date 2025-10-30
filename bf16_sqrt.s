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
    # TC1: sqrt(4.0) = 2.0
    # a = 0x4080 (4.0), exp = 0x4000 (2.0)
    li      a0, 0x4080            # a = 4.0 (bf16)
    jal     ra, bf16_sqrt
    li      t0, 0x4000            # expected = 2.0 (bf16)
    bne     a0, t0, 1f            # if result != expected -> fail++
    j       2f
1:
    addi    s10, s10, 1
2:

    # ------------- case2 (edge) --------
    # TC2 (edge): sqrt(-1.0) = NaN
    # a = 0xBF80 (-1.0)
    li      a0, 0xBF80            # -1.0 (bf16)
    jal     ra, bf16_sqrt
    li      t1, 0x7F80            # mask exp bits
    and     t2, a0, t1            # 取 exponent
    bne     t2, t1, 3f            # exp != 0xFF -> fail
    andi    t3, a0, 0x7F          # 取 mantissa
    beqz    t3, 3f                # mant == 0 -> 不是 NaN -> fail
    j       4f
3:
    addi    s10, s10, 1
4:

    # ------------- case3 ---------------
    # TC3: sqrt(+Inf) = +Inf
    # a = 0x7F80 (+Inf), exp = 0x7F80 (+Inf)
    li      a0, 0x7F80            # +Inf
    jal     ra, bf16_sqrt
    li      t0, 0x7F80            # expected = +Inf (bf16)
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

bf16_sqrt:
    srli    t0, a0, 15
    andi    t0, t0, 1      # sign

    srli    t1, a0, 7
    andi    t1, t1, 0xFF   # exp

    andi    t2, a0, 0x7F   # mant
    
check_FF:
    addi    t3, x0, 0xFF
    bne     t1, t3, check_zerocase

    bne     t2, x0, nan
    bne     t0, x0, nan
    jal     x0, inf

check_zerocase:
    bne     t1, x0, check_negative
    bne     t2, x0, check_negative
    jal     x0, zero

check_negative:
    beq     t0, x0, check_too_small
    jal     x0, nan

check_too_small:
    beq     t1, x0, zero

real_exp:
    addi    t1, t1, -127    # e 取代 exp
    li      t4, 0           # new_exp
    
implict_1:
    ori     t2, t2, 0x80    # m 取代 mant
      
start_square_root:
    andi    t6, t1, 1
    sll     t2, t2, t6 # mant <<= mask
    sub     t4, t1, t6 # new_exp = e - mask
    srai    t4, t4, 1  # new_exp >>= 1 new_exp is int32_t so need use arithmetic shift
    addi    t4, t4, 127 # new_exp += BF16_EXP_BIAS

binary_search_init:
    li      a1, 90          # low
    li      a2, 255         # high
    li      a3, 128         # result
    
binary_search_loop:
     bgt    a1, a2, binary_loop_end
     add    a4, a1, a2      
     srli   a4, a4, 1       # mid

mul_loop_init:  
     li     a5, 0           # sq
     li     s0, 0           # i
     li     s1, 32
     
mul_loop:
    bge     s0, s1, mul_loop_end
    srl     t6, a4, s0      # mask
    andi    t6, t6, 1 
    sub     t6, x0, t6  
    sll     s3, a4, s0     
    and     s3, s3, t6  
    add     a5, a5, s3  
    addi    s0, s0, 1       # i++
    j       mul_loop
    
mul_loop_end:
    srli    a5, a5, 7
    ble     a5, t2, set_result
    addi    a2, a4, -1
    j       binary_search_loop
    
set_result:
    mv      a3, a4
    addi    a1, a4, 1
    j       binary_search_loop
    
binary_loop_end:
    li      s6, 0xFF
    andi    t2, a3, 0x7F
    blt     t4, s6, chk_new_exp
    jal     x0, inf
    
chk_new_exp:
    bgt     t4, x0, return
    jal     x0, zero
    
return:
    andi    t4, t4, 0xFF
    slli    t4, t4, 7
    or      a0, t4, t2
    ret
    
inf:
    slli    a0, t0, 15
    addi    t0, x0, 255
    slli    t0, t0, 7
    or      a0, a0, t0
    jalr    x0, ra, 0

nan:                       # 0x7FC0
    li      t0, 0          # sign = 0
    addi    t1, x0, 255
    slli    t1, t1, 7
    ori     a0, t1, 0x40   # mant = 0x40
    jalr    x0, ra, 0

zero:                      # 0x0000
    mv      a0, x0
    jalr    x0, ra, 0
