    .text
    .globl bf16_div
main:
    li a0, 0x3FC0
    li a1, 0x3FC0
    

bf16_div:
    # -------- 取 sign/exp/mant --------
    srli    t0, a0, 15           # t0 = sign_a
    andi    t0, t0, 1
    srli    t1, a1, 15           # t1 = sign_b
    andi    t1, t1, 1

    srli    t2, a0, 7            # t2 = exp_a (8-bit)
    andi    t2, t2, 0xFF
    srli    t3, a1, 7            # t3 = exp_b (8-bit)
    andi    t3, t3, 0xFF

    andi    t4, a0, 0x7F         # t4 = mant_a (7-bit)
    andi    t5, a1, 0x7F         # t5 = mant_b (7-bit)

    xor     s0, t0, t1           # s0 = result_sign (用 a2 暫存)

    li      a3, 0xFF             # a3 = 0xFF (常數)
    li      a6, 0x80             # a6 = 0x80 (隱含位 bit7)

# --------- 特殊情況檢查：b 的類別 ---------
check_b_FF:
    bne     t3, a3, check_b_zero         # if (exp_b != 0xFF) -> 下一關
    beqz    t5, inf                      # mant_b == 0 => b = ±Inf
    # b is NaN, return b
    mv      a0, a5
    ret

check_b_zero:
    # if b == ±0 ?
    beqz    t3, check_b_zero_mant        # exp_b == 0 ?
    j       check_a_FF                   # exp_b != 0 -> 繼續
check_b_zero_mant:
    bnez    t5, check_a_FF               # mant_b != 0 -> 次正規數，不是 0
    # b == ±0
    #   if a == ±0 -> NaN
    beqz    t2, check_b_zero_a_mant
    j       inf                          # a 非 0
check_b_zero_a_mant:
    beqz    t4, nan            # a mant==0 -> a == 0
    j       inf                          # a 非 0（mant!=0 但 exp=0 => 次正規 ≠ 0）

# --------- 特殊情況檢查：a 的類別 ---------
check_a_FF:
    bne     t2, a3, check_a_zero         # if (exp_a != 0xFF) -> 下一關
    bnez    t4, inf                 # mant_a != 0 => NaN
    # a is ±Inf -> return ±Inf (依 result_sign)
a_is_nan:
    j       nan

check_a_zero:
    beqz    t2, check_a_zero_mant        # exp_a == 0 ?
    j       normalize_mantissas
check_a_zero_mant:
    bnez    t4, normalize_mantissas      # 次正規 ≠ 0
    # a is 0 -> 回傳 ±0 （前面已處理 0/0）
    j       zero

# --------- 將隱含 1 補上 (若為正規數) ---------
normalize_mantissas:
    beqz    t2, skip_set_msba            # if (exp_a == 0) 不補隱含位
    or      t4, t4, a6                   # mant_a |= 0x80
skip_set_msba:
    beqz    t3, skip_set_msbb            # if (exp_b == 0) 不補隱含位
    or      t5, t5, a6                   # mant_b |= 0x80
skip_set_msbb:

    # dividend = mant_a << 15 (32-bit)
    slli    a7, t4, 15                   # a7 = dividend
    # divisor = mant_b (32-bit)
    mv      t6, t5                       # t6 = divisor
    li      a4, 0                        # a4 = quotient = 0 (暫借 a0, 最後會覆蓋)
# --------- 16 次迭代的二進位長除法 ---------
start_div_loop:
    li      a6, 15                       # t0 = shift = 15
    li      t1, 16                       # t1 = loop count = 16

do_div_loop:
    slli    a0, a0, 1                    # quotient <<= 1

    # temp = divisor << shift
    sll     t2, t6, t0                   # t2 = divisor << shift

    # if (dividend >= temp) { dividend -= temp; quotient |= 1; }
    # 用 sltu 判斷 dividend < temp
    sltu    t3, a7, t2                   # t3 = (dividend < temp)
    bne     t3, zero, skip_sub_q1        # 若 dividend < temp -> 跳過減法
    sub     a7, a7, t2                   # dividend -= temp
    ori     a0, a0, 1                    # quotient |= 1
skip_sub_q1:

    addi    t0, t0, -1                   # shift--
    addi    t1, t1, -1                   # count--
    bnez    t1, do_div_loop
    # result_exp = (int32)exp_a - exp_b + 127
    li      a5, 127                      # a5 = 127
    sub     s1, t2, t3                   # a1 = exp_a - exp_b
    add     s1, s1, a5                   # (先不用，下面直接重算) ——(保留位置)

    # denorm 調整
    beqz    t2, adj_a_sub1               # if (!exp_a) result_exp--
    j       after_adj_a
adj_a_sub1:
    addi    a1, a1, -1
after_adj_a:
    beqz    t3, adj_b_add1               # if (!exp_b) result_exp++
    j       start_div_loop
adj_b_add1:
    addi    a1, a1, 1



# --------- 正規化 quotient 與 exponent ---------
# if (quotient & 0x8000) quotient >>= 8;
# else while (!(quotient & 0x8000) && result_exp > 1) { quotient<<=1; result_exp--; }
normalize_and_align:
    li      t2, 0x8000
    and     t3, a0, t2                   # t3 = quotient & 0x8000
    bnez    t3, msb15_ready

    # while 部分
norm_while:
    and     t3, a0, t2
    bnez    t3, norm_done_loop           # 若已經有 MSB15，跳出
    addi    t4, a1, -1                   # (result_exp > 1) ?
    blez    t4, norm_done_loop           # 若 <=0 表示 result_exp <= 1，停止左移
    slli    a0, a0, 1                    # quotient <<= 1
    addi    a1, a1, -1                   # result_exp--
    j       norm_while

norm_done_loop:
    # 對齊：把 bit15 對齊到 mantissa bit7，要 >>8
    srli    a0, a0, 8
    j       after_shift8

msb15_ready:
    # 已經 >=2，直接 >>8
    srli    a0, a0, 8

after_shift8:
    # mantissa 取低 7 bits
    andi    a0, a0, 0x7F

# --------- 溢位 / 次正規/零 檢查 ---------
    # if (result_exp >= 0xFF) -> ±Inf
    slti    t2, a1, 0xFF                 # t2 = (result_exp < 255)
    bnez    t2, check_underflow
    # 溢位：返回 ±Inf
    slli    s0, s0, 15
    or      a0, s0, a4
    ret

check_underflow:
    # if (result_exp <= 0) -> ±0
    blez    a1, zero

# --------- 組回 BF16 ---------
pack_result:
    # a0 = mantissa(7)
    # 準備 exp bits 到 t2 = (result_exp & 0xFF) << 7
    andi    t2, a1, 0xFF
    slli    t2, t2, 7
    # sign << 15
    slli    s0, s0, 15
    # result = sign | exp | mant
    or      a0, a0, t2
    or      a0, a0, a2
    ret

zero:
    slli    a0, s0, 15
    ret

inf:
    slli    a0, s0, 15
    li      s8, 0x7F80
    or      a0, a0, s8
    ret

nan:
    li      a0, 0x7FC0           # NaN
    ret
