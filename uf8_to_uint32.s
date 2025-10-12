.data
.text
.globl clz
clz:
    
    addi t1, x0, 32
    addi t2, x0, 16
    
    1:
        srl t0, a0, t2
        beq t0, x0, 2
    
        sub t1, t1, t2
        mv  a0,t0
    
        ret
    2:
        srli t2,t2, 1
        bne  t2, x0, 1
        
        sub  a0, t1, a0
        ret
    
Decode:
    andi t0, a0, 0x0F    # t0 is mantissa
    srli t1 , a0, 4      # t1 is exponent
    
    li   t2, 15
    sub  t2, t2, t1      # t2 = 15 - exponent
    
    li   t3, 0x7FFF
    srl  t3, t3, t2
    slli t3, t3, 4       # t3 is offset
    
    sll  t0, t0, t1      # mantissa << exponent
    add  a0, t0, t3      # fl = (mantissa << exponent) + offset    
    
    ret
    
Encode:
    addi sp, sp, -16     # �w�dstack�Ŷ��O�@ra�A�]���n�b�禡�̩I�s�禡
    sw   ra, 12(sp)      # �򥻤W��bstack�����m(0,4,8,12)���i�H�A�u�nreturn�e�hload
    
    li   t1, 16
    bltu a0, t1, L_result_output #bltu : Branch Less Then Unsigned
    
    mv   t0, a0          # t0 is a0
    
    jal  ra, clz         # clz(value)  -> a0 = lz
    li   t2, 31
    sub  t1, t2, a0      # t1 <- 31 - lz for msb
    
    li t2, 0             # t2 <- 0 for exp
    li t3, 0             # t3 <- 0 for offset
    
    li t4, 5             # t4 <- 5
    blt t1, t4, L_skip_msb_ge5    #if msb < 5
    addi t2, t1 ,-4      #exp = msb - 4
    
    
    .L_skip_msb_ge5:
        subi 
        
        
        
    .L_result_output:
        lw ra, 12(sp)
        addi sp, sp, 16
        ret
        
     
