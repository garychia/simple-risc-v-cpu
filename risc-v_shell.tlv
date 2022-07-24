\m4_TLV_version 1d: tl-x.org
\SV
   // This code can be found in: https://github.com/stevehoover/LF-Building-a-RISC-V-CPU-Core/risc-v_shell.tlv
   
   m4_include_lib(['https://raw.githubusercontent.com/stevehoover/warp-v_includes/1d1023ccf8e7b0a8cf8e8fc4f0a823ebb61008e3/risc-v_defs.tlv'])
   m4_include_lib(['https://raw.githubusercontent.com/stevehoover/LF-Building-a-RISC-V-CPU-Core/main/lib/risc-v_shell_lib.tlv'])



   //---------------------------------------------------------------------------------
   // /====================\
   // | Sum 1 to 9 Program |
   // \====================/
   //
   // Program to test RV32I
   // Add 1,2,3,...,9 (in that order).
   //
   // Regs:
   //  x12 (a2): 10
   //  x13 (a3): 1..10
   //  x14 (a4): Sum
   // 
   // m4_asm(ADDI, x14, x0, 0)             // Initialize sum register a4 with 0
   // m4_asm(ADDI, x12, x0, 1010)          // Store count of 10 in register a2.
   // m4_asm(ADDI, x13, x0, 1)             // Initialize loop count register a3 with 0
   // Loop:
   // m4_asm(ADD, x14, x13, x14)           // Incremental summation
   // m4_asm(ADDI, x13, x13, 1)            // Increment loop count by 1
   // m4_asm(BLT, x13, x12, 1111111111000) // If a3 is less than a2, branch to label named <loop>
   // Test result value in x14, and set x31 to reflect pass/fail.
   // m4_asm(ADDI, x30, x14, 111111010100) // Subtract expected value of 44 to set x30 to 1 if and only iff the result is 45 (1 + 2 + ... + 9).
   // m4_asm(BGE, x0, x0, 0) // Done. Jump to itself (infinite loop). (Up to 20-bit signed immediate plus implicit 0 bit (unlike JALR) provides byte address; last immediate bit should also be 0)
   // m4_asm_end()
   // m4_define(['M4_MAX_CYC'], 50)
   //---------------------------------------------------------------------------------
   m4_test_prog()


\SV
   m4_makerchip_module   // (Expanded in Nav-TLV pane.)
   /* verilator lint_on WIDTH */
\TLV
   
   $reset = *reset;
   
   
   // Program Counter Implementation
   $next_pc[31:0] = $reset ? 32'b0 :
                    $is_b && $taken_br && $is_jalr ? $jalr_tgt_pc :
                    $is_b && $taken_br ? $br_tgt_pc :
                    $pc + 32'd4;
   $pc[31:0] = >>1$next_pc;
   
   // IMem (Instruction Memory)
   `READONLY_MEM($pc, $$instr[31:0])
   
   // Decode an Instruction
   $is_i_instr = $instr[6:2] == 5'b00000 ||
                 $instr[6:2] == 5'b00001 ||
                 $instr[6:2] == 5'b00100 ||
                 $instr[6:2] == 5'b00110 ||
                 $instr[6:2] == 5'b11001;
   $is_s_instr = $instr[6:2] ==? 5'b0100x;
   $is_r_instr = $instr[6:2] == 5'b01011 ||
                 $instr[6:2] == 5'b01100 ||
                 $instr[6:2] == 5'b01110 ||
                 $instr[6:2] == 5'b10100;
   $is_u_instr = $instr[6:2] ==? 5'b0x101;
   $is_b_instr = $instr[6:2] == 5'b11000;
   $is_j_instr = $instr[6:2] == 5'b11011;
   
   // Extract instruction fields
   $funct3[2:0] = $instr[14:12];
   $rs1[4:0] = $instr[19:15];
   $rs2[4:0] = $instr[24:20];
   $rd[4:0] = $instr[11:7];
   $opcode[6:0] = $instr[6:0];
   
   // Check if each of the fields is valid.
   $funct3_valid = $is_r_instr || $is_i_instr || $is_s_instr || $is_b_instr;
   $rs1_valid = $is_r_instr || $is_i_instr || $is_s_instr || $is_b_instr;
   $rs2_valid = $is_r_instr || $is_s_instr || $is_b_instr;
   $rd_valid = $rd != 5'b0 && ($is_r_instr || $is_i_instr || $is_u_instr || $is_j_instr);
   $imm_valid = $is_i_instr || $is_s_instr || $is_b_instr || $is_u_instr || $is_j_instr;
   // Suppress warnings.
   `BOGUS_USE($rd $rd_valid $rs1 $rs1_valid $funct3 $funct3_valid $rs2 $rs2_valid $imm_valid);
   // Extract the immediate field.
   $imm[31:0] = $is_i_instr ? { { 21{ $instr[31] } }, $instr[30:20] } :
                $is_s_instr ? { { 21{ $instr[31] } }, $instr[30:25], $instr[11:7] } :
                $is_b_instr ? { { 20{ $instr[31] } }, $instr[7], $instr[30:25], $instr[11:8], 1'b0 } :
                $is_u_instr ? { $instr[31:12], 12'b0 } :
                $is_j_instr ? { { 12{ $instr[31] } }, $instr[19:12], $instr[20], $instr[30:21], 1'b0 } :
                32'b0; // Default Value

   // Decode instruction
   // Branching
   $dec_bits[10:0] = { $instr[30], $funct3, $opcode };
   $is_beq  = $dec_bits ==? 11'bx_000_1100011;
   $is_bne  = $dec_bits ==? 11'bx_001_1100011;
   $is_blt  = $dec_bits ==? 11'bx_100_1100011;
   $is_bge  = $dec_bits ==? 11'bx_101_1100011;
   $is_bltu = $dec_bits ==? 11'bx_110_1100011;
   $is_bgeu = $dec_bits ==? 11'bx_111_1100011;
   // Arithmetic Operations
   $is_addi = $dec_bits ==? 11'bx_000_0010011;
   $is_add  = $dec_bits ==  11'b0_000_0110011;
   $is_sub  = $dec_bits ==  11'b1_000_0110011;
   // Load/Store Instructions
   // Load
   $is_lb  = $dec_bits ==? 11'bx_000_0000011;
   $is_lh  = $dec_bits ==? 11'bx_001_0000011;
   $is_lw  = $dec_bits ==? 11'bx_010_0000011;
   $is_lbu = $dec_bits ==? 11'bx_100_0000011;
   $is_lhu = $dec_bits ==? 11'bx_101_0000011;
   // Store
   $is_sb  = $dec_bits ==? 11'bx_000_0100011;
   $is_sh  = $dec_bits ==? 11'bx_001_0100011;
   $is_sw  = $dec_bits ==? 11'bx_010_0100011;
   // Other Instructions
   $is_lui   = $dec_bits ==? 11'bx_xxx_0110111;
   $is_auipc = $dec_bits ==? 11'bx_xxx_0010111;
   $is_jal   = $dec_bits ==? 11'bx_xxx_1101111;
   $is_jalr  = $dec_bits ==? 11'bx_000_1100111;
   $is_slti  = $dec_bits ==? 11'bx_010_0010011;
   $is_sltiu = $dec_bits ==? 11'bx_011_0010011;
   $is_xori  = $dec_bits ==? 11'bx_100_0010011;
   $is_ori   = $dec_bits ==? 11'bx_110_0010011;
   $is_andi  = $dec_bits ==? 11'bx_111_0010011;
   $is_slli  = $dec_bits ==  11'b0_001_0010011;
   $is_srli  = $dec_bits ==  11'b0_101_0010011;
   $is_srai  = $dec_bits ==  11'b1_101_0010011;
   $is_sll   = $dec_bits ==  11'b0_001_0110011;
   $is_slt   = $dec_bits ==  11'b0_010_0110011;
   $is_sltu  = $dec_bits ==  11'b0_011_0110011;
   $is_xor   = $dec_bits ==  11'b0_100_0110011;
   $is_srl   = $dec_bits ==  11'b0_101_0110011;
   $is_sra   = $dec_bits ==  11'b1_101_0110011;
   $is_or    = $dec_bits ==  11'b0_110_0110011;
   $is_and   = $dec_bits ==  11'b0_111_0110011;
   // Determine if the current instruction is a load instruction.
   $is_load  = $dec_bits[6:0] == 7'b0000011;
   `BOGUS_USE($is_beq $is_bne $is_blt $is_bge $is_bltu $is_bgeu $is_addi $is_add)
   
   // Sign-extended Source 1
   $sext_src1[63:0]  = { { 32{ $src1_value[31] } }, $src1_value };
   // ALU
   $andi_rslt[31:0]  = $src1_value & $imm;
   $ori_rslt[31:0]   = $src1_value | $imm;
   $xori_rslt[31:0]  = $src1_value ^ $imm;
   $addi_rslt[31:0]  = $src1_value + $imm;
   $slli_rslt[31:0]  = $src1_value << $imm[5:0];
   $srli_rslt[31:0]  = $src1_value >> $imm[5:0];
   $and_rslt[31:0]   = $src1_value & $src2_value;
   $or_rslt[31:0]    = $src1_value | $src2_value;
   $xor_rslt[31:0]   = $src1_value ^ $src2_value;
   $add_rslt[31:0]   = $src1_value + $src2_value;
   $sub_rslt[31:0]   = $src1_value - $src2_value;
   $sll_rslt[31:0]   = $src1_value << $src2_value[4:0];
   $srl_rslt[31:0]   = $src1_value >> $src2_value[4:0];
   // SLTU and SLTI (set if less than) results
   $sltu_rslt[31:0]  = { 31'b0, $src1_value < $src2_value };
   $sltiu_rslt[31:0] = { 31'b0, $src1_value < $imm };
   $lui_rslt[31:0]   = { $imm[31:12], 12'b0 };
   $auipc_rslt[31:0] = $pc + $imm;
   $jal_rslt[31:0]   = $pc + 32'd4;
   $jalr_rslt[31:0]  = $pc + 32'd4;
   $slt_rslt[31:0]   = (($src1_value[31] == $src2_value[31]) ? $sltu_rslt : { 31'b0, $src1_value[31] });
   $slti_rslt[31:0]  = (($src1_value[31] == $imm[31]) ? $sltiu_rslt : { 31'b0, $src1_value[31] });
   // SRA and SRAI (shift right) results
   $sra_rslt[63:0]   = $sext_src1 >> $src2_value[4:0];
   $srai_rslt[63:0]  = $sext_src1 >> $imm[4:0];
   
   // Select one of the results of ALU.
   $result[31:0] = $is_addi  ? $addi_rslt       :
                   $is_add   ? $add_rslt        :
                   $is_sub   ? $sub_rslt        :
                   $is_lui   ? $lui_rslt        :
                   $is_auipc ? $auipc_rslt      :
                   $is_jal   ? $jal_rslt        :
                   $is_jalr  ? $jalr_rslt       :
                   $is_slti  ? $slti_rslt       :
                   $is_sltiu ? $sltiu_rslt      :
                   $is_xori  ? $xori_rslt       :
                   $is_ori   ? $ori_rslt        :
                   $is_andi  ? $andi_rslt       :
                   $is_slli  ? $slli_rslt       :
                   $is_srli  ? $srli_rslt       :
                   $is_srai  ? $srai_rslt[31:0] :
                   $is_sll   ? $sll_rslt        :
                   $is_slt   ? $slt_rslt        :
                   $is_sltu  ? $sltu_rslt       :
                   $is_xor   ? $xor_rslt        :
                   $is_srl   ? $srl_rslt        :
                   $is_sra   ? $sra_rslt[31:0]  :
                   $is_or    ? $or_rslt         :
                   $is_and   ? $and_rslt        :
                   $is_load  ? $addi_rslt       :
                   $is_s_instr ? $addi_rslt     :
                   32'b0;
   $reg_rslt[31:0] = $is_load ? $ld_data : $result;
   // Branch
   $is_b = $is_beq || $is_bne || $is_blt || $is_bge || $is_bltu || $is_bgeu || $is_jal || $is_jalr;
   $taken_br = $is_beq  ? $src1_value == $src2_value                                           :
               $is_bne  ? $src1_value != $src2_value                                           :
               $is_blt  ? ($src1_value < $src2_value)  ^ ($src1_value[31] != $src2_value[31])  :
               $is_bge  ? ($src1_value >= $src2_value) ^ ($src1_value[31] != $src2_value[31])  :
               $is_bltu ? $src1_value < $src2_value                                            :
               $is_bgeu ? $src1_value >= $src2_value                                           :
               $is_jal || $is_jalr;
   $jalr_tgt_pc[31:0] = $src1_value + $imm;
   $br_tgt_pc[31:0] = $pc + $imm;
   
   // Assert these to end simulation (before Makerchip cycle limit).
   m4+tb()
   *failed = *cyc_cnt > M4_MAX_CYC;

   // Register File
   m4+rf(32, 32, $reset, $rd_valid, $rd, $reg_rslt, $rs1_valid, $rs1, $src1_value, $rs2_valid, $rs2, $src2_value)
   // Data Memory
   m4+dmem(32, 32, $reset, $result[6:2], $is_s_instr, $src2_value, $is_load, $ld_data)
   m4+cpu_viz()
\SV
   endmodule