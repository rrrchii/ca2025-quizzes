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
    li      a0, 0x00004000           # a = 4.0 (bf16)
    jal     ra, bf16_sqrt
    li      t0, 0x00003FB5           # expected = 2.0 (bf16)
    bne     a0, t0, 1f            # if result != expected -> fail++
    j       2f
1:
    addi    s10, s10, 1
2:

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
    li      t5, 1
    and     t6, t1, t5
    beq     t6, x0, else
    slli    t2, t2, 1
    addi    t4, t1, -1
    srli    t4, t4, 1
    addi    t4, t4, 127     # new_exp
    
else:
    srli    t4, t1, 1
    addi    t4, t4, 127     # new_exp


    
    li      a1, 90          # low
    li      a2, 256         # high
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
    srl     s2, a4, s0      # mask
    andi    s2, s2, 1 
    sub     s2, x0, s2  
    sll     s3, a4, s0     
    and     s3, s3, s2  
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
    li      s4, 256
    li      s5, 128
    bge     a3, s4, adjust_lower
    blt     a3, s5, adjust_upper
    
adjust_lower:
    srli    a3, a3, 1
    addi    t4, t4, 1
    j       adjust_done
    
adjust_upper:
    ble     t4, t5, adjust_done
    slli    a3, a3, 1
    addi    t4, t4, -1
    j       adjust_upper
    
adjust_done:
    andi    t2, a3, 0x7F  # new_mant
    
    li      t5, 0xFF
    bge     t4, t5, inf
    ble     t4, x0, zero
    
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
