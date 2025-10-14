    .data
 text1:      .asciz ": produces value "
 text2:      .asciz " but encodes back to "
 text3:      .asciz ": value "
 text4:      .asciz " <= previous_value "
 text5:      .asciz "tests pass\n"
 text6:      .asciz "some tests failed.\n"

 newline:    .asciz "\n"
    
    .text
    .globl main
main:
    jal ra, test
    beq a0, x0, fail       # a0 is passed flag if (passed == 0) means check fail
    la    a0, text5
    li    a7, 4
    ecall                  # print "All tests passed.\n"
    li    a0, 0            # a0 return 1 means success
    li    a7, 10
    ecall                  # exit
    
test:
    addi  sp, sp, -4
    sw    ra, 0(sp)        # protect ra
    addi  s0, x0, -1       # previous value   
    li    s1, 1            # defult s1(passed flag) = 1 mean ture
    li    s2, 0            # counter i    s2 is counter i
    li    s3, 256          # s3 is the end of counter i

test_loop:
    bgeu  s2, s3, return_passed
    mv    a0, s2
    jal   ra, uf8_decode   
    mv    s4, a0           # s4 decode value
    jal   ra, uf8_encode
    mv    s5, a0           # the value has been decode and encode
    
check_1:
    beq   s2, s5, check_2  # if s2 == s5 mean check_1 success 
    mv    a0, s2
    li    a7, 34           
    ecall                  # print "i" in hex
    la    a0, text1         
    li    a7, 4
    ecall                  # print "produces value"
    mv    a0, s4           
    li    a7, 1
    ecall                  # print "value" in dec
    la    a0, text2
    li    a7, 4
    ecall                  # print "but encodes back to"
    mv    a0, s5           
    li    a7, 34
    ecall                  # print the "value" that has been decode and encode in hex
    la    a0, newline
    li    a7, 4
    ecall                  # print "\n" for newline
    li    s1, 0            # set s1 = 0 means passed = false
    
check_2:
    bgt   s2, s0, check_done
    mv    a0, s2
    li    a7, 34
    ecall                  # print "i" in hex
    la    a0, text3
    li    a7, 4            
    ecall                  # print ": value"
    mv    a0, s4           
    li    a7, 1
    ecall                  # print "value" in dec
    la    a0, text4
    li    a7, 4
    ecall                  # print " <= previous_value "
    mv    a0, s0           
    li    a7, 34
    ecall                  # print "previous_value value" in hex
    la    a0, newline      
    li    a7, 4
    ecall                  # print newline
    li    s1, 0            # set s1 = 0 means passed = false
    
check_done:
    mv    s0, s2           # to check the increase
    mv    a0, s1           # return passed
    addi  s2, s2, 1
    j     test_loop

fail:
    la    a0, text6
    li    a7, 4
    ecall                  # print "Some tests failed.\n"
    li    a0, 1            # a0 return 1 means fail
    li    a7, 10
    ecall                  # exit
    
return_passed:
    lw    ra, 0(sp)        # load back the return address from main:
    addi  sp, sp, 4
    ret
    
clz:
    li    t0, 32           # t0 = n = 32
    li    t1, 16           # t1 = c = 16
    mv    t2, a0           # t2 = x

1:  
    srl   t3, t2, t1       # t3 = y = x >> c
    beq   t3, x0, 2f       # if (y == 0) skip  #2f is local label means label2 forward
    sub   t0, t0, t1       # t0 = n = n - c
    mv    t2, t3           # t2 = x = y
    
2:  
    srli  t1, t1, 1        # c >>= 1
    bne   t1, x0, 1b       # while (c != 0)

    sub   a0, t0, t2       # return a0 = n - x
    ret
    
    
uf8_decode:
    andi  t0, a0, 0x0F     # t0 is mantissa
    srli  t1, a0, 4        # t1 is exponent
    
    li    t2, 15
    sub   t2, t2, t1       # t2 = 15 - exponent
    
    li    t3, 0x7FFF
    srl   t3, t3, t2
    slli  t3, t3, 4        # t3 is offset
    
    sll   t0, t0, t1       # mantissa << exponent
    add   a0, t0, t3       # fl = (mantissa << exponent) + offset    
    
    ret
    
    
uf8_encode:
    addi  sp, sp, -4
    sw    ra, 0(sp)        # because it will call CLZ in this function
    
    li    t4, 16           # t4 = 16
    bltu  a0, t4, fast_return    # if( value < 16 ) return value;
    
    mv    t5, a0           # t5 = value use t5 input clz
    jal   ra, clz
    mv    t0, a0           # t0 = lz
    li    t1, 31
    sub   t1, t1, t0       # t1 = msb
    
    li    t2, 0            # exponent = 0
    li    t3, 0            # overflow = 0
    
    li    t4, 5            # t4 = 5
    blt   t1, t4, after_adjust_down
    addi  t2, t1, -4       # exponent = msb - 4
    
    li    t4, 15           # t4 = 15
    bleu  t2, t4, exp_ok   # if(exp > 15)
    li    t2, 15           # exp = 15
    
exp_ok:   
    li     t4, 0            # t4 = counter e = 0
    
build_overflow:
    bgeu   t4, t2, adjust_overflow
    slli   t3, t3, 1       # overflow <<= 1
    addi   t3, t3, 16      # (overflow << 1) + 16
    addi   t4, t4, 1       # e ++
    j      build_overflow
    
adjust_overflow:

adjust_down:
    beq    t2, x0, after_adjust_down     # exp > 0
    bgeu   t5, t3, after_adjust_down     # value < overflow
    addi   t3, t3, -16                   # overflow - 16
    srli   t3, t3, 1                     # (overflow - 16) >> 1
    addi   t2, t2, -1                    # exp --
    j      adjust_down

after_adjust_down:
    li     t6, 15
    li     t4, 0
    
adjust_up:
    bgeu   t2, t6, after_estimate_overflow
    slli   t4, t3, 1                     # next_overflow = (overflow << 1)
    addi   t4, t4, 16                    # next_overflow = (overflow << 1) + 16
    blt    t5, t4, after_estimate_overflow
    mv     t3, t4                        # overflow = next_overflow
    addi   t2, t2, 1                     # exp ++
    j      adjust_up

after_estimate_overflow:
    
ret_val:
    sub    t5, t5, t3
    srl    t5, t5, t2                    # t5 is mantissa
    
    slli   a0, t2, 4
    or     a0, a0, t5
    
fast_return:
    lw ra, 0(sp)
    addi sp, sp, 4
    ret
