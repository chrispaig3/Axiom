; ModuleID = 'fixed.ll'
source_filename = "fixed.ll"
target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i8:8:32-i16:16:32-i64:64-i128:128-n32:64-S128-Fn32"
target triple = "aarch64-unknown-linux-gnu"

@__axiom_argc = internal unnamed_addr global i64 0
@__axiom_argv = internal unnamed_addr global i64 0
@__axiom_bump = internal unnamed_addr global i64 0
@__axiom_bump_end = internal unnamed_addr global i64 0
@__axiom_chunk = internal unnamed_addr global i64 0
@__axiom_free = internal unnamed_addr global i64 0
@__axiom_high = internal unnamed_addr global i64 0
@__axiom_slabs = internal unnamed_addr global [4097 x i64] zeroinitializer
@__axiom_divzero_msg = private unnamed_addr constant [24 x i8] c"axiom: division by zero\0A"
@__axiom_oom_msg = private unnamed_addr constant [35 x i8] c"axiom: out of memory (mmap failed)\0A"
@__axiom_recover_top = internal unnamed_addr global i64 0
@str_0 = private unnamed_addr constant [21 x i8] c"-9223372036854775808\00"
@strhdr_0 = private unnamed_addr constant { i64, i64, i64, ptr, i64 } { i64 -1, i64 0, i64 20, ptr @str_0, i64 0 }, align 16
@str_1 = private unnamed_addr constant [2 x i8] c"-\00"
@strhdr_1 = private unnamed_addr constant { i64, i64, i64, ptr, i64 } { i64 -1, i64 0, i64 1, ptr @str_1, i64 0 }, align 16
@str_2 = private unnamed_addr constant [2 x i8] c"0\00"
@strhdr_2 = private unnamed_addr constant { i64, i64, i64, ptr, i64 } { i64 -1, i64 0, i64 1, ptr @str_2, i64 0 }, align 16
@str_3 = private unnamed_addr constant [2 x i8] c".\00"
@strhdr_3 = private unnamed_addr constant { i64, i64, i64, ptr, i64 } { i64 -1, i64 0, i64 1, ptr @str_3, i64 0 }, align 16
@str_4 = private unnamed_addr constant [1 x i8] zeroinitializer
@strhdr_4 = private unnamed_addr constant { i64, i64, i64, ptr, i64 } { i64 -1, i64 0, i64 0, ptr @str_4, i64 0 }, align 16
@str_5 = private unnamed_addr constant [2 x i8] c"=\00"
@strhdr_5 = private unnamed_addr constant { i64, i64, i64, ptr, i64 } { i64 -1, i64 0, i64 1, ptr @str_5, i64 0 }, align 16
@str_6 = private unnamed_addr constant [5 x i8] c"PATH\00"
@strhdr_6 = private unnamed_addr constant { i64, i64, i64, ptr, i64 } { i64 -1, i64 0, i64 4, ptr @str_6, i64 0 }, align 16
@str_7 = private unnamed_addr constant [2 x i8] c"/\00"
@strhdr_7 = private unnamed_addr constant { i64, i64, i64, ptr, i64 } { i64 -1, i64 0, i64 1, ptr @str_7, i64 0 }, align 16
@str_8 = private unnamed_addr constant [4 x i8] c"af=\00"
@strhdr_8 = private unnamed_addr constant { i64, i64, i64, ptr, i64 } { i64 -1, i64 0, i64 3, ptr @str_8, i64 0 }, align 16
@str_9 = private unnamed_addr constant [3 x i8] c"::\00"
@strhdr_9 = private unnamed_addr constant { i64, i64, i64, ptr, i64 } { i64 -1, i64 0, i64 2, ptr @str_9, i64 0 }, align 16
@str_10 = private unnamed_addr constant [2 x i8] c":\00"
@strhdr_10 = private unnamed_addr constant { i64, i64, i64, ptr, i64 } { i64 -1, i64 0, i64 1, ptr @str_10, i64 0 }, align 16
@str_11 = private unnamed_addr constant [2 x i8] c"[\00"
@strhdr_11 = private unnamed_addr constant { i64, i64, i64, ptr, i64 } { i64 -1, i64 0, i64 1, ptr @str_11, i64 0 }, align 16
@str_12 = private unnamed_addr constant [3 x i8] c"]:\00"
@strhdr_12 = private unnamed_addr constant { i64, i64, i64, ptr, i64 } { i64 -1, i64 0, i64 2, ptr @str_12, i64 0 }, align 16
@str_13 = private unnamed_addr constant [2 x i8] c"\0A\00"
@strhdr_13 = private unnamed_addr constant { i64, i64, i64, ptr, i64 } { i64 -1, i64 0, i64 1, ptr @str_13, i64 0 }, align 16
@str_14 = private unnamed_addr constant [3 x i8] c"..\00"
@strhdr_14 = private unnamed_addr constant { i64, i64, i64, ptr, i64 } { i64 -1, i64 0, i64 2, ptr @str_14, i64 0 }, align 16
@str_15 = private unnamed_addr constant [11 x i8] c"recovered \00"
@strhdr_15 = private unnamed_addr constant { i64, i64, i64, ptr, i64 } { i64 -1, i64 0, i64 10, ptr @str_15, i64 0 }, align 16
@str_16 = private unnamed_addr constant [8 x i8] c"usable \00"
@strhdr_16 = private unnamed_addr constant { i64, i64, i64, ptr, i64 } { i64 -1, i64 0, i64 7, ptr @str_16, i64 0 }, align 16
@str_17 = private unnamed_addr constant [56 x i8] c"UNREACHABLE: the trap outside a recovery point returned\00"
@str_18 = private unnamed_addr constant [5 x i8] c"true\00"
@strhdr_18 = private unnamed_addr constant { i64, i64, i64, ptr, i64 } { i64 -1, i64 0, i64 4, ptr @str_18, i64 0 }, align 16
@str_19 = private unnamed_addr constant [6 x i8] c"false\00"
@strhdr_19 = private unnamed_addr constant { i64, i64, i64, ptr, i64 } { i64 -1, i64 0, i64 5, ptr @str_19, i64 0 }, align 16
@__axiom_symn_0 = private unnamed_addr constant [4 x i8] c"main"
@__axiom_symn_1 = private unnamed_addr constant [11 x i8] c"axiom_alloc"
@__axiom_symn_2 = private unnamed_addr constant [12 x i8] c"axiom_retain"
@__axiom_symn_3 = private unnamed_addr constant [13 x i8] c"axiom_release"
@__axiom_symn_4 = private unnamed_addr constant [21 x i8] c"__axiom_arena_mark_fn"
@__axiom_symn_5 = private unnamed_addr constant [22 x i8] c"__axiom_arena_reset_fn"
@__axiom_symn_6 = private unnamed_addr constant [30 x i8] c"__axiom_arena_reset_keeping_fn"
@__axiom_symn_7 = private unnamed_addr constant [19 x i8] c"__axiom_div_by_zero"
@__axiom_symn_8 = private unnamed_addr constant [21 x i8] c"__axiom_out_of_memory"
@__axiom_symn_9 = private unnamed_addr constant [21 x i8] c"__axiom_recover_abort"
@__axiom_symn_10 = private unnamed_addr constant [14 x i8] c"__axiom_str_eq"
@__axiom_symn_11 = private unnamed_addr constant [20 x i8] c"Sys.Platform$sysRead"
@__axiom_symn_12 = private unnamed_addr constant [21 x i8] c"Sys.Platform$sysWrite"
@__axiom_symn_13 = private unnamed_addr constant [20 x i8] c"Sys.Platform$sysOpen"
@__axiom_symn_14 = private unnamed_addr constant [21 x i8] c"Sys.Platform$sysClose"
@__axiom_symn_15 = private unnamed_addr constant [20 x i8] c"Sys.Platform$sysExit"
@__axiom_symn_16 = private unnamed_addr constant [21 x i8] c"Sys.Platform$sysLseek"
@__axiom_symn_17 = private unnamed_addr constant [27 x i8] c"Sys.Platform$openNeedsDirFd"
@__axiom_symn_18 = private unnamed_addr constant [20 x i8] c"Sys.Platform$atFdCwd"
@__axiom_symn_19 = private unnamed_addr constant [20 x i8] c"Sys.Platform$oRdonly"
@__axiom_symn_20 = private unnamed_addr constant [31 x i8] c"Sys.Platform$oWronlyCreateTrunc"
@__axiom_symn_21 = private unnamed_addr constant [32 x i8] c"Sys.Platform$oWronlyCreateAppend"
@__axiom_symn_22 = private unnamed_addr constant [20 x i8] c"Sys.Platform$seekEnd"
@__axiom_symn_23 = private unnamed_addr constant [20 x i8] c"Sys.Platform$seekSet"
@__axiom_symn_24 = private unnamed_addr constant [32 x i8] c"Sys.Platform$spawnUsesPosixSpawn"
@__axiom_symn_25 = private unnamed_addr constant [20 x i8] c"Sys.Platform$sysFork"
@__axiom_symn_26 = private unnamed_addr constant [23 x i8] c"Sys.Platform$sysForkArg"
@__axiom_symn_27 = private unnamed_addr constant [22 x i8] c"Sys.Platform$sysExecve"
@__axiom_symn_28 = private unnamed_addr constant [21 x i8] c"Sys.Platform$sysWait4"
@__axiom_symn_29 = private unnamed_addr constant [26 x i8] c"Sys.Platform$sysPosixSpawn"
@__axiom_symn_30 = private unnamed_addr constant [25 x i8] c"Sys.Platform$sysUnlinkNum"
@__axiom_symn_31 = private unnamed_addr constant [24 x i8] c"Sys.Platform$sysMkdirNum"
@__axiom_symn_32 = private unnamed_addr constant [24 x i8] c"Sys.Platform$sysRmdirNum"
@__axiom_symn_33 = private unnamed_addr constant [25 x i8] c"Sys.Platform$sysRenameNum"
@__axiom_symn_34 = private unnamed_addr constant [27 x i8] c"Sys.Platform$sysGetdentsNum"
@__axiom_symn_35 = private unnamed_addr constant [33 x i8] c"Sys.Platform$dirReadNeedsPosition"
@__axiom_symn_36 = private unnamed_addr constant [29 x i8] c"Sys.Platform$direntNameOffset"
@__axiom_symn_37 = private unnamed_addr constant [29 x i8] c"Sys.Platform$cwdUsesFcntlPath"
@__axiom_symn_38 = private unnamed_addr constant [22 x i8] c"Sys.Platform$sysCwdNum"
@__axiom_symn_39 = private unnamed_addr constant [21 x i8] c"Sys.Platform$fGetPath"
@__axiom_symn_40 = private unnamed_addr constant [19 x i8] c"Sys.Platform$eExist"
@__axiom_symn_41 = private unnamed_addr constant [19 x i8] c"Sys.Platform$eIsDir"
@__axiom_symn_42 = private unnamed_addr constant [25 x i8] c"Sys.Platform$sysGetPidNum"
@__axiom_symn_43 = private unnamed_addr constant [24 x i8] c"Sys.Platform$sysClockNum"
@__axiom_symn_44 = private unnamed_addr constant [32 x i8] c"Sys.Platform$clockIsGettimeofday"
@__axiom_symn_45 = private unnamed_addr constant [30 x i8] c"Sys.Platform$clockHasMonotonic"
@__axiom_symn_46 = private unnamed_addr constant [25 x i8] c"Sys.Platform$sysSocketNum"
@__axiom_symn_47 = private unnamed_addr constant [23 x i8] c"Sys.Platform$sysBindNum"
@__axiom_symn_48 = private unnamed_addr constant [25 x i8] c"Sys.Platform$sysListenNum"
@__axiom_symn_49 = private unnamed_addr constant [25 x i8] c"Sys.Platform$sysAcceptNum"
@__axiom_symn_50 = private unnamed_addr constant [26 x i8] c"Sys.Platform$sysConnectNum"
@__axiom_symn_51 = private unnamed_addr constant [29 x i8] c"Sys.Platform$sysSetSockOptNum"
@__axiom_symn_52 = private unnamed_addr constant [29 x i8] c"Sys.Platform$sysGetSockOptNum"
@__axiom_symn_53 = private unnamed_addr constant [27 x i8] c"Sys.Platform$sysShutdownNum"
@__axiom_symn_54 = private unnamed_addr constant [24 x i8] c"Sys.Platform$sysFcntlNum"
@__axiom_symn_55 = private unnamed_addr constant [19 x i8] c"Sys.Platform$afInet"
@__axiom_symn_56 = private unnamed_addr constant [20 x i8] c"Sys.Platform$afInet6"
@__axiom_symn_57 = private unnamed_addr constant [23 x i8] c"Sys.Platform$sockStream"
@__axiom_symn_58 = private unnamed_addr constant [22 x i8] c"Sys.Platform$solSocket"
@__axiom_symn_59 = private unnamed_addr constant [24 x i8] c"Sys.Platform$soReuseAddr"
@__axiom_symn_60 = private unnamed_addr constant [24 x i8] c"Sys.Platform$soReusePort"
@__axiom_symn_61 = private unnamed_addr constant [20 x i8] c"Sys.Platform$soError"
@__axiom_symn_62 = private unnamed_addr constant [19 x i8] c"Sys.Platform$fGetFl"
@__axiom_symn_63 = private unnamed_addr constant [19 x i8] c"Sys.Platform$fSetFl"
@__axiom_symn_64 = private unnamed_addr constant [22 x i8] c"Sys.Platform$oNonblock"
@__axiom_symn_65 = private unnamed_addr constant [19 x i8] c"Sys.Platform$eAgain"
@__axiom_symn_66 = private unnamed_addr constant [31 x i8] c"Sys.Platform$sockaddrHasLenByte"
@__axiom_symn_67 = private unnamed_addr constant [27 x i8] c"Sys.Platform$pollUsesKqueue"
@__axiom_symn_68 = private unnamed_addr constant [29 x i8] c"Sys.Platform$sysPollCreateNum"
@__axiom_symn_69 = private unnamed_addr constant [27 x i8] c"Sys.Platform$sysPollWaitNum"
@__axiom_symn_70 = private unnamed_addr constant [26 x i8] c"Sys.Platform$sysPollCtlNum"
@__axiom_symn_71 = private unnamed_addr constant [26 x i8] c"Sys.Platform$pollEventSize"
@__axiom_symn_72 = private unnamed_addr constant [30 x i8] c"Sys.Platform$pollEventFdOffset"
@__axiom_symn_73 = private unnamed_addr constant [27 x i8] c"Sys.Platform$pollReadFilter"
@__axiom_symn_74 = private unnamed_addr constant [22 x i8] c"Sys.Platform$pollAddOp"
@__axiom_symn_75 = private unnamed_addr constant [22 x i8] c"Sys.Platform$pollDelOp"
@__axiom_symn_76 = private unnamed_addr constant [27 x i8] c"Sys.Platform$pollSigsetSize"
@__axiom_symn_77 = private unnamed_addr constant [25 x i8] c"Sys.Platform$sysRandomNum"
@__axiom_symn_78 = private unnamed_addr constant [31 x i8] c"Sys.Platform$randomIsGetentropy"
@__axiom_symn_79 = private unnamed_addr constant [27 x i8] c"Sys.Platform$randomMaxChunk"
@__axiom_symn_80 = private unnamed_addr constant [31 x i8] c"Sys.Platform$signalUsesSignalFd"
@__axiom_symn_81 = private unnamed_addr constant [30 x i8] c"Sys.Platform$sysSigProcMaskNum"
@__axiom_symn_82 = private unnamed_addr constant [24 x i8] c"Sys.Platform$sigBlockHow"
@__axiom_symn_83 = private unnamed_addr constant [24 x i8] c"Sys.Platform$sigsetBytes"
@__axiom_symn_84 = private unnamed_addr constant [27 x i8] c"Sys.Platform$sysSignalFdNum"
@__axiom_symn_85 = private unnamed_addr constant [24 x i8] c"Sys.Platform$sigInfoSize"
@__axiom_symn_86 = private unnamed_addr constant [29 x i8] c"Sys.Platform$pollSignalFilter"
@__axiom_symn_87 = private unnamed_addr constant [23 x i8] c"Sys.Platform$sysKillNum"
@__axiom_symn_88 = private unnamed_addr constant [20 x i8] c"Sys.Platform$sigTerm"
@__axiom_symn_89 = private unnamed_addr constant [19 x i8] c"Sys.Platform$sigInt"
@__axiom_symn_90 = private unnamed_addr constant [28 x i8] c"Sys.Platform$forkChildIsZero"
@__axiom_symn_91 = private unnamed_addr constant [31 x i8] c"Sys.Platform$acceptNonblockFlag"
@__axiom_symn_92 = private unnamed_addr constant [12 x i8] c"Mem$memAlloc"
@__axiom_symn_93 = private unnamed_addr constant [18 x i8] c"Mem$memAllocMapped"
@__axiom_symn_94 = private unnamed_addr constant [16 x i8] c"Mem$memMarkArray"
@__axiom_symn_95 = private unnamed_addr constant [15 x i8] c"Mem$memMarkLeaf"
@__axiom_symn_96 = private unnamed_addr constant [11 x i8] c"Mem$memCopy"
@__axiom_symn_97 = private unnamed_addr constant [15 x i8] c"Mem$memCopyFrom"
@__axiom_symn_98 = private unnamed_addr constant [10 x i8] c"Mem$memSet"
@__axiom_symn_99 = private unnamed_addr constant [14 x i8] c"Mem$memSetFrom"
@__axiom_symn_100 = private unnamed_addr constant [10 x i8] c"Mem$memCmp"
@__axiom_symn_101 = private unnamed_addr constant [14 x i8] c"Mem$memCmpFrom"
@__axiom_symn_102 = private unnamed_addr constant [14 x i8] c"Mem$memGetWord"
@__axiom_symn_103 = private unnamed_addr constant [17 x i8] c"Mem$memGetWordStr"
@__axiom_symn_104 = private unnamed_addr constant [14 x i8] c"Mem$memSetWord"
@__axiom_symn_105 = private unnamed_addr constant [14 x i8] c"Mem$memGetByte"
@__axiom_symn_106 = private unnamed_addr constant [14 x i8] c"Mem$memPutByte"
@__axiom_symn_107 = private unnamed_addr constant [17 x i8] c"Vec$vecDefaultCap"
@__axiom_symn_108 = private unnamed_addr constant [10 x i8] c"Vec$vecNew"
@__axiom_symn_109 = private unnamed_addr constant [19 x i8] c"Vec$vecWithCapacity"
@__axiom_symn_110 = private unnamed_addr constant [22 x i8] c"Vec$vecWithCapacityRef"
@__axiom_symn_111 = private unnamed_addr constant [13 x i8] c"Vec$vecNewRef"
@__axiom_symn_112 = private unnamed_addr constant [12 x i8] c"Vec$vecBuild"
@__axiom_symn_113 = private unnamed_addr constant [11 x i8] c"Vec$vecFree"
@__axiom_symn_114 = private unnamed_addr constant [15 x i8] c"Vec$vecOwnsRefs"
@__axiom_symn_115 = private unnamed_addr constant [10 x i8] c"Vec$vecLen"
@__axiom_symn_116 = private unnamed_addr constant [10 x i8] c"Vec$vecCap"
@__axiom_symn_117 = private unnamed_addr constant [11 x i8] c"Vec$vecData"
@__axiom_symn_118 = private unnamed_addr constant [10 x i8] c"Vec$vecGet"
@__axiom_symn_119 = private unnamed_addr constant [10 x i8] c"Vec$vecTry"
@__axiom_symn_120 = private unnamed_addr constant [13 x i8] c"Vec$vecGetStr"
@__axiom_symn_121 = private unnamed_addr constant [10 x i8] c"Vec$vecSet"
@__axiom_symn_122 = private unnamed_addr constant [14 x i8] c"Vec$vecReserve"
@__axiom_symn_123 = private unnamed_addr constant [15 x i8] c"Vec$vecGrownCap"
@__axiom_symn_124 = private unnamed_addr constant [21 x i8] c"Vec$vecReserveExactly"
@__axiom_symn_125 = private unnamed_addr constant [11 x i8] c"Vec$vecPush"
@__axiom_symn_126 = private unnamed_addr constant [10 x i8] c"Vec$vecPop"
@__axiom_symn_127 = private unnamed_addr constant [11 x i8] c"Vec$vecLast"
@__axiom_symn_128 = private unnamed_addr constant [12 x i8] c"Vec$vecClear"
@__axiom_symn_129 = private unnamed_addr constant [13 x i8] c"Vec$vecDropAt"
@__axiom_symn_130 = private unnamed_addr constant [15 x i8] c"Vec$vecDropFrom"
@__axiom_symn_131 = private unnamed_addr constant [10 x i8] c"Vec$vecSum"
@__axiom_symn_132 = private unnamed_addr constant [14 x i8] c"Vec$vecSumFrom"
@__axiom_symn_133 = private unnamed_addr constant [11 x i8] c"Vec$vecHash"
@__axiom_symn_134 = private unnamed_addr constant [15 x i8] c"Vec$vecHashFrom"
@__axiom_symn_135 = private unnamed_addr constant [11 x i8] c"Str$strWrap"
@__axiom_symn_136 = private unnamed_addr constant [16 x i8] c"Str$strWrapOwned"
@__axiom_symn_137 = private unnamed_addr constant [12 x i8] c"Str$strAlloc"
@__axiom_symn_138 = private unnamed_addr constant [14 x i8] c"Str$strFromLit"
@__axiom_symn_139 = private unnamed_addr constant [11 x i8] c"Str$cstrLen"
@__axiom_symn_140 = private unnamed_addr constant [10 x i8] c"Str$strLen"
@__axiom_symn_141 = private unnamed_addr constant [11 x i8] c"Str$strData"
@__axiom_symn_142 = private unnamed_addr constant [12 x i8] c"Str$strOwner"
@__axiom_symn_143 = private unnamed_addr constant [11 x i8] c"Str$strByte"
@__axiom_symn_144 = private unnamed_addr constant [11 x i8] c"Str$strCStr"
@__axiom_symn_145 = private unnamed_addr constant [14 x i8] c"Str$strIsEmpty"
@__axiom_symn_146 = private unnamed_addr constant [10 x i8] c"Str$strCmp"
@__axiom_symn_147 = private unnamed_addr constant [9 x i8] c"Str$strEq"
@__axiom_symn_148 = private unnamed_addr constant [12 x i8] c"Str$strSlice"
@__axiom_symn_149 = private unnamed_addr constant [10 x i8] c"Str$strDup"
@__axiom_symn_150 = private unnamed_addr constant [13 x i8] c"Str$strConcat"
@__axiom_symn_151 = private unnamed_addr constant [15 x i8] c"Str$strFindByte"
@__axiom_symn_152 = private unnamed_addr constant [17 x i8] c"Str$strStartsWith"
@__axiom_symn_153 = private unnamed_addr constant [14 x i8] c"Str$strIsDigit"
@__axiom_symn_154 = private unnamed_addr constant [14 x i8] c"Str$strIsAlpha"
@__axiom_symn_155 = private unnamed_addr constant [14 x i8] c"Str$strIsSpace"
@__axiom_symn_156 = private unnamed_addr constant [13 x i8] c"Str$strHexVal"
@__axiom_symn_157 = private unnamed_addr constant [17 x i8] c"Str$strIsHexDigit"
@__axiom_symn_158 = private unnamed_addr constant [12 x i8] c"Str$strSplit"
@__axiom_symn_159 = private unnamed_addr constant [16 x i8] c"Str$strSplitFrom"
@__axiom_symn_160 = private unnamed_addr constant [15 x i8] c"Str$strFromByte"
@__axiom_symn_161 = private unnamed_addr constant [21 x i8] c"Fmt$intIsMostNegative"
@__axiom_symn_162 = private unnamed_addr constant [15 x i8] c"Fmt$fmtIntWidth"
@__axiom_symn_163 = private unnamed_addr constant [10 x i8] c"Fmt$fmtInt"
@__axiom_symn_164 = private unnamed_addr constant [10 x i8] c"Fmt$fmtNat"
@__axiom_symn_165 = private unnamed_addr constant [13 x i8] c"Fmt$fmtDigits"
@__axiom_symn_166 = private unnamed_addr constant [14 x i8] c"Fmt$fmtHexShr4"
@__axiom_symn_167 = private unnamed_addr constant [10 x i8] c"Fmt$fmtHex"
@__axiom_symn_168 = private unnamed_addr constant [15 x i8] c"Fmt$fmtHexWidth"
@__axiom_symn_169 = private unnamed_addr constant [16 x i8] c"Fmt$fmtHexDigits"
@__axiom_symn_170 = private unnamed_addr constant [14 x i8] c"Fmt$fmtPadLeft"
@__axiom_symn_171 = private unnamed_addr constant [15 x i8] c"Fmt$fmtPadRight"
@__axiom_symn_172 = private unnamed_addr constant [16 x i8] c"Fmt$fmtPadCenter"
@__axiom_symn_173 = private unnamed_addr constant [19 x i8] c"Fmt$fmtPadZerosLeft"
@__axiom_symn_174 = private unnamed_addr constant [15 x i8] c"Fmt$fmtHexUpper"
@__axiom_symn_175 = private unnamed_addr constant [21 x i8] c"Fmt$fmtHexDigitsUpper"
@__axiom_symn_176 = private unnamed_addr constant [10 x i8] c"Fmt$powTen"
@__axiom_symn_177 = private unnamed_addr constant [15 x i8] c"Fmt$fmtPadZeros"
@__axiom_symn_178 = private unnamed_addr constant [12 x i8] c"Fmt$fmtFloat"
@__axiom_symn_179 = private unnamed_addr constant [16 x i8] c"Fmt$fmtFloatPrec"
@__axiom_symn_180 = private unnamed_addr constant [15 x i8] c"Fmt$fmtFloatAbs"
@__axiom_symn_181 = private unnamed_addr constant [9 x i8] c"Sys$stdin"
@__axiom_symn_182 = private unnamed_addr constant [10 x i8] c"Sys$stdout"
@__axiom_symn_183 = private unnamed_addr constant [10 x i8] c"Sys$stderr"
@__axiom_symn_184 = private unnamed_addr constant [14 x i8] c"Sys$sysWriteFd"
@__axiom_symn_185 = private unnamed_addr constant [17 x i8] c"Sys$sysWriteAllFd"
@__axiom_symn_186 = private unnamed_addr constant [13 x i8] c"Sys$sysReadFd"
@__axiom_symn_187 = private unnamed_addr constant [15 x i8] c"Sys$sysOpenPath"
@__axiom_symn_188 = private unnamed_addr constant [19 x i8] c"Sys$sysOpenPathMode"
@__axiom_symn_189 = private unnamed_addr constant [14 x i8] c"Sys$sysCloseFd"
@__axiom_symn_190 = private unnamed_addr constant [11 x i8] c"Sys$sysSeek"
@__axiom_symn_191 = private unnamed_addr constant [15 x i8] c"Sys$sysExitWith"
@__axiom_symn_192 = private unnamed_addr constant [13 x i8] c"Sys$sysFailed"
@__axiom_symn_193 = private unnamed_addr constant [12 x i8] c"Sys$sysErrno"
@__axiom_symn_194 = private unnamed_addr constant [15 x i8] c"Sys$sysReadFile"
@__axiom_symn_195 = private unnamed_addr constant [14 x i8] c"Sys$sysReadAll"
@__axiom_symn_196 = private unnamed_addr constant [11 x i8] c"Sys$sysArgc"
@__axiom_symn_197 = private unnamed_addr constant [10 x i8] c"Sys$sysArg"
@__axiom_symn_198 = private unnamed_addr constant [16 x i8] c"Sys$sysWriteFile"
@__axiom_symn_199 = private unnamed_addr constant [17 x i8] c"Sys$sysAppendFile"
@__axiom_symn_200 = private unnamed_addr constant [13 x i8] c"Sys$sysRename"
@__axiom_symn_201 = private unnamed_addr constant [13 x i8] c"Sys$sysUnlink"
@__axiom_symn_202 = private unnamed_addr constant [12 x i8] c"Sys$sysMkdir"
@__axiom_symn_203 = private unnamed_addr constant [14 x i8] c"Sys$sysDirMode"
@__axiom_symn_204 = private unnamed_addr constant [12 x i8] c"Sys$sysRmdir"
@__axiom_symn_205 = private unnamed_addr constant [17 x i8] c"Sys$sysFileExists"
@__axiom_symn_206 = private unnamed_addr constant [15 x i8] c"Sys$sysFileSize"
@__axiom_symn_207 = private unnamed_addr constant [16 x i8] c"Sys$sysReadErrno"
@__axiom_symn_208 = private unnamed_addr constant [12 x i8] c"Sys$sysIsDir"
@__axiom_symn_209 = private unnamed_addr constant [18 x i8] c"Sys$sysDirBufBytes"
@__axiom_symn_210 = private unnamed_addr constant [14 x i8] c"Sys$sysReadDir"
@__axiom_symn_211 = private unnamed_addr constant [18 x i8] c"Sys$sysReadDirLoop"
@__axiom_symn_212 = private unnamed_addr constant [20 x i8] c"Sys$sysReadDirDecode"
@__axiom_symn_213 = private unnamed_addr constant [13 x i8] c"Sys$sysGetCwd"
@__axiom_symn_214 = private unnamed_addr constant [14 x i8] c"Sys$sysEnvSlot"
@__axiom_symn_215 = private unnamed_addr constant [15 x i8] c"Sys$sysEnvCount"
@__axiom_symn_216 = private unnamed_addr constant [19 x i8] c"Sys$sysEnvCountFrom"
@__axiom_symn_217 = private unnamed_addr constant [10 x i8] c"Sys$sysEnv"
@__axiom_symn_218 = private unnamed_addr constant [16 x i8] c"Sys$sysEnvLookup"
@__axiom_symn_219 = private unnamed_addr constant [11 x i8] c"Sys$sysEnvp"
@__axiom_symn_220 = private unnamed_addr constant [15 x i8] c"Sys$sysEnvpFill"
@__axiom_symn_221 = private unnamed_addr constant [12 x i8] c"Sys$sysSpawn"
@__axiom_symn_222 = private unnamed_addr constant [14 x i8] c"Sys$sysWaitPid"
@__axiom_symn_223 = private unnamed_addr constant [15 x i8] c"Sys$sysExitCode"
@__axiom_symn_224 = private unnamed_addr constant [17 x i8] c"Sys$sysTermSignal"
@__axiom_symn_225 = private unnamed_addr constant [10 x i8] c"Sys$sysRun"
@__axiom_symn_226 = private unnamed_addr constant [14 x i8] c"Sys$sysRunPath"
@__axiom_symn_227 = private unnamed_addr constant [16 x i8] c"Sys$sysRunSearch"
@__axiom_symn_228 = private unnamed_addr constant [13 x i8] c"Sys$sysGetPid"
@__axiom_symn_229 = private unnamed_addr constant [16 x i8] c"Sys$sysNowMicros"
@__axiom_symn_230 = private unnamed_addr constant [19 x i8] c"Sys$sysNowMonotonic"
@__axiom_symn_231 = private unnamed_addr constant [16 x i8] c"Sys$netSocketTcp"
@__axiom_symn_232 = private unnamed_addr constant [17 x i8] c"Sys$netSocketTcp6"
@__axiom_symn_233 = private unnamed_addr constant [17 x i8] c"Sys$netAddr4Bytes"
@__axiom_symn_234 = private unnamed_addr constant [17 x i8] c"Sys$netAddr6Bytes"
@__axiom_symn_235 = private unnamed_addr constant [19 x i8] c"Sys$netAddrMaxBytes"
@__axiom_symn_236 = private unnamed_addr constant [12 x i8] c"Sys$netAddr4"
@__axiom_symn_237 = private unnamed_addr constant [12 x i8] c"Sys$netAddr6"
@__axiom_symn_238 = private unnamed_addr constant [15 x i8] c"Sys$netPutGroup"
@__axiom_symn_239 = private unnamed_addr constant [15 x i8] c"Sys$netGetGroup"
@__axiom_symn_240 = private unnamed_addr constant [17 x i8] c"Sys$netAddrFamily"
@__axiom_symn_241 = private unnamed_addr constant [15 x i8] c"Sys$netAddrPort"
@__axiom_symn_242 = private unnamed_addr constant [15 x i8] c"Sys$netAddrSize"
@__axiom_symn_243 = private unnamed_addr constant [11 x i8] c"Sys$netBind"
@__axiom_symn_244 = private unnamed_addr constant [13 x i8] c"Sys$netListen"
@__axiom_symn_245 = private unnamed_addr constant [13 x i8] c"Sys$netAccept"
@__axiom_symn_246 = private unnamed_addr constant [19 x i8] c"Sys$netAcceptFinish"
@__axiom_symn_247 = private unnamed_addr constant [17 x i8] c"Sys$netAcceptFrom"
@__axiom_symn_248 = private unnamed_addr constant [18 x i8] c"Sys$netAddrLenRead"
@__axiom_symn_249 = private unnamed_addr constant [15 x i8] c"Sys$netPutInt32"
@__axiom_symn_250 = private unnamed_addr constant [15 x i8] c"Sys$netGetInt32"
@__axiom_symn_251 = private unnamed_addr constant [15 x i8] c"Sys$netAddrText"
@__axiom_symn_252 = private unnamed_addr constant [16 x i8] c"Sys$netAddrText4"
@__axiom_symn_253 = private unnamed_addr constant [18 x i8] c"Sys$netAddrZeroRun"
@__axiom_symn_254 = private unnamed_addr constant [23 x i8] c"Sys$netAddrZeroRunStart"
@__axiom_symn_255 = private unnamed_addr constant [16 x i8] c"Sys$netAddrText6"
@__axiom_symn_256 = private unnamed_addr constant [19 x i8] c"Sys$netAddrTextPort"
@__axiom_symn_257 = private unnamed_addr constant [18 x i8] c"Sys$netSetBlocking"
@__axiom_symn_258 = private unnamed_addr constant [14 x i8] c"Sys$netConnect"
@__axiom_symn_259 = private unnamed_addr constant [15 x i8] c"Sys$netShutdown"
@__axiom_symn_260 = private unnamed_addr constant [16 x i8] c"Sys$netSetOptInt"
@__axiom_symn_261 = private unnamed_addr constant [21 x i8] c"Sys$netSetNonBlocking"
@__axiom_symn_262 = private unnamed_addr constant [17 x i8] c"Sys$netWouldBlock"
@__axiom_symn_263 = private unnamed_addr constant [14 x i8] c"Sys$netPutWord"
@__axiom_symn_264 = private unnamed_addr constant [14 x i8] c"Sys$netGetWord"
@__axiom_symn_265 = private unnamed_addr constant [19 x i8] c"Sys$netPollBufBytes"
@__axiom_symn_266 = private unnamed_addr constant [17 x i8] c"Sys$netPollCreate"
@__axiom_symn_267 = private unnamed_addr constant [14 x i8] c"Sys$netPollRec"
@__axiom_symn_268 = private unnamed_addr constant [18 x i8] c"Sys$netPollAddRead"
@__axiom_symn_269 = private unnamed_addr constant [18 x i8] c"Sys$netPollDelRead"
@__axiom_symn_270 = private unnamed_addr constant [15 x i8] c"Sys$netPollWait"
@__axiom_symn_271 = private unnamed_addr constant [15 x i8] c"Sys$netPollFdAt"
@__axiom_symn_272 = private unnamed_addr constant [18 x i8] c"Sys$sysRandomBytes"
@__axiom_symn_273 = private unnamed_addr constant [13 x i8] c"Sys$sysSigBit"
@__axiom_symn_274 = private unnamed_addr constant [18 x i8] c"Sys$sysSignalBlock"
@__axiom_symn_275 = private unnamed_addr constant [17 x i8] c"Sys$netSignalOpen"
@__axiom_symn_276 = private unnamed_addr constant [19 x i8] c"Sys$netPollSignalAt"
@__axiom_symn_277 = private unnamed_addr constant [11 x i8] c"Sys$sysKill"
@__axiom_symn_278 = private unnamed_addr constant [18 x i8] c"Sys$sysForkProcess"
@__axiom_symn_279 = private unnamed_addr constant [11 x i8] c"IO$writeStr"
@__axiom_symn_280 = private unnamed_addr constant [11 x i8] c"IO$printLit"
@__axiom_symn_281 = private unnamed_addr constant [13 x i8] c"IO$printlnLit"
@__axiom_symn_282 = private unnamed_addr constant [14 x i8] c"IO$readFileLit"
@__axiom_symn_283 = private unnamed_addr constant [11 x i8] c"IO$readFile"
@__axiom_symn_284 = private unnamed_addr constant [9 x i8] c"IO$ioPath"
@__axiom_symn_285 = private unnamed_addr constant [12 x i8] c"IO$writeFile"
@__axiom_symn_286 = private unnamed_addr constant [13 x i8] c"IO$appendFile"
@__axiom_symn_287 = private unnamed_addr constant [13 x i8] c"IO$removeFile"
@__axiom_symn_288 = private unnamed_addr constant [13 x i8] c"IO$renamePath"
@__axiom_symn_289 = private unnamed_addr constant [11 x i8] c"IO$copyFile"
@__axiom_symn_290 = private unnamed_addr constant [13 x i8] c"IO$fileExists"
@__axiom_symn_291 = private unnamed_addr constant [8 x i8] c"IO$isDir"
@__axiom_symn_292 = private unnamed_addr constant [11 x i8] c"IO$fileSize"
@__axiom_symn_293 = private unnamed_addr constant [12 x i8] c"IO$readErrno"
@__axiom_symn_294 = private unnamed_addr constant [10 x i8] c"IO$makeDir"
@__axiom_symn_295 = private unnamed_addr constant [13 x i8] c"IO$makeDirAll"
@__axiom_symn_296 = private unnamed_addr constant [17 x i8] c"IO$makeDirAllFrom"
@__axiom_symn_297 = private unnamed_addr constant [12 x i8] c"IO$makeDirOk"
@__axiom_symn_298 = private unnamed_addr constant [12 x i8] c"IO$removeDir"
@__axiom_symn_299 = private unnamed_addr constant [10 x i8] c"IO$listDir"
@__axiom_symn_300 = private unnamed_addr constant [14 x i8] c"IO$listDirKeep"
@__axiom_symn_301 = private unnamed_addr constant [16 x i8] c"IO$listDirInsert"
@__axiom_symn_302 = private unnamed_addr constant [14 x i8] c"IO$listDirSift"
@__axiom_symn_303 = private unnamed_addr constant [6 x i8] c"IO$cwd"
@__axiom_symn_304 = private unnamed_addr constant [7 x i8] c"IO$exit"
@__axiom_symn_305 = private unnamed_addr constant [6 x i8] c"IO$die"
@__axiom_symn_306 = private unnamed_addr constant [3 x i8] c"ask"
@__axiom_symn_307 = private unnamed_addr constant [6 x i8] c"usable"
@__axiom_symn_308 = private unnamed_addr constant [17 x i8] c"__axiom_user_main"
@__axiom_symn_309 = private unnamed_addr constant [6 x i8] c"_lam_0"
@__axiom_symn_310 = private unnamed_addr constant [16 x i8] c"Show#String#show"
@__axiom_symn_311 = private unnamed_addr constant [13 x i8] c"Show#Int#show"
@__axiom_symn_312 = private unnamed_addr constant [14 x i8] c"Show#Bool#show"
@__axiom_symn_313 = private unnamed_addr constant [15 x i8] c"Show#Float#show"
@__axiom_symn_314 = private unnamed_addr constant [20 x i8] c"__axiom_recover_save"
@__axiom_symn_315 = private unnamed_addr constant [20 x i8] c"__axiom_recover_load"
@__axiom_symtab = internal unnamed_addr constant [948 x i64] [i64 ptrtoint (ptr @main to i64), i64 ptrtoint (ptr @__axiom_symn_0 to i64), i64 4, i64 ptrtoint (ptr @axiom_alloc to i64), i64 ptrtoint (ptr @__axiom_symn_1 to i64), i64 11, i64 ptrtoint (ptr @axiom_retain to i64), i64 ptrtoint (ptr @__axiom_symn_2 to i64), i64 12, i64 ptrtoint (ptr @axiom_release to i64), i64 ptrtoint (ptr @__axiom_symn_3 to i64), i64 13, i64 ptrtoint (ptr @__axiom_arena_mark_fn to i64), i64 ptrtoint (ptr @__axiom_symn_4 to i64), i64 21, i64 ptrtoint (ptr @__axiom_arena_reset_fn to i64), i64 ptrtoint (ptr @__axiom_symn_5 to i64), i64 22, i64 ptrtoint (ptr @__axiom_arena_reset_keeping_fn to i64), i64 ptrtoint (ptr @__axiom_symn_6 to i64), i64 30, i64 ptrtoint (ptr @__axiom_div_by_zero to i64), i64 ptrtoint (ptr @__axiom_symn_7 to i64), i64 19, i64 ptrtoint (ptr @__axiom_out_of_memory to i64), i64 ptrtoint (ptr @__axiom_symn_8 to i64), i64 21, i64 ptrtoint (ptr @__axiom_recover_abort to i64), i64 ptrtoint (ptr @__axiom_symn_9 to i64), i64 21, i64 ptrtoint (ptr @__axiom_str_eq to i64), i64 ptrtoint (ptr @__axiom_symn_10 to i64), i64 14, i64 ptrtoint (ptr @"Sys.Platform$sysRead" to i64), i64 ptrtoint (ptr @__axiom_symn_11 to i64), i64 20, i64 ptrtoint (ptr @"Sys.Platform$sysWrite" to i64), i64 ptrtoint (ptr @__axiom_symn_12 to i64), i64 21, i64 ptrtoint (ptr @"Sys.Platform$sysOpen" to i64), i64 ptrtoint (ptr @__axiom_symn_13 to i64), i64 20, i64 ptrtoint (ptr @"Sys.Platform$sysClose" to i64), i64 ptrtoint (ptr @__axiom_symn_14 to i64), i64 21, i64 ptrtoint (ptr @"Sys.Platform$sysExit" to i64), i64 ptrtoint (ptr @__axiom_symn_15 to i64), i64 20, i64 ptrtoint (ptr @"Sys.Platform$sysLseek" to i64), i64 ptrtoint (ptr @__axiom_symn_16 to i64), i64 21, i64 ptrtoint (ptr @"Sys.Platform$openNeedsDirFd" to i64), i64 ptrtoint (ptr @__axiom_symn_17 to i64), i64 27, i64 ptrtoint (ptr @"Sys.Platform$atFdCwd" to i64), i64 ptrtoint (ptr @__axiom_symn_18 to i64), i64 20, i64 ptrtoint (ptr @"Sys.Platform$oRdonly" to i64), i64 ptrtoint (ptr @__axiom_symn_19 to i64), i64 20, i64 ptrtoint (ptr @"Sys.Platform$oWronlyCreateTrunc" to i64), i64 ptrtoint (ptr @__axiom_symn_20 to i64), i64 31, i64 ptrtoint (ptr @"Sys.Platform$oWronlyCreateAppend" to i64), i64 ptrtoint (ptr @__axiom_symn_21 to i64), i64 32, i64 ptrtoint (ptr @"Sys.Platform$seekEnd" to i64), i64 ptrtoint (ptr @__axiom_symn_22 to i64), i64 20, i64 ptrtoint (ptr @"Sys.Platform$seekSet" to i64), i64 ptrtoint (ptr @__axiom_symn_23 to i64), i64 20, i64 ptrtoint (ptr @"Sys.Platform$spawnUsesPosixSpawn" to i64), i64 ptrtoint (ptr @__axiom_symn_24 to i64), i64 32, i64 ptrtoint (ptr @"Sys.Platform$sysFork" to i64), i64 ptrtoint (ptr @__axiom_symn_25 to i64), i64 20, i64 ptrtoint (ptr @"Sys.Platform$sysForkArg" to i64), i64 ptrtoint (ptr @__axiom_symn_26 to i64), i64 23, i64 ptrtoint (ptr @"Sys.Platform$sysExecve" to i64), i64 ptrtoint (ptr @__axiom_symn_27 to i64), i64 22, i64 ptrtoint (ptr @"Sys.Platform$sysWait4" to i64), i64 ptrtoint (ptr @__axiom_symn_28 to i64), i64 21, i64 ptrtoint (ptr @"Sys.Platform$sysPosixSpawn" to i64), i64 ptrtoint (ptr @__axiom_symn_29 to i64), i64 26, i64 ptrtoint (ptr @"Sys.Platform$sysUnlinkNum" to i64), i64 ptrtoint (ptr @__axiom_symn_30 to i64), i64 25, i64 ptrtoint (ptr @"Sys.Platform$sysMkdirNum" to i64), i64 ptrtoint (ptr @__axiom_symn_31 to i64), i64 24, i64 ptrtoint (ptr @"Sys.Platform$sysRmdirNum" to i64), i64 ptrtoint (ptr @__axiom_symn_32 to i64), i64 24, i64 ptrtoint (ptr @"Sys.Platform$sysRenameNum" to i64), i64 ptrtoint (ptr @__axiom_symn_33 to i64), i64 25, i64 ptrtoint (ptr @"Sys.Platform$sysGetdentsNum" to i64), i64 ptrtoint (ptr @__axiom_symn_34 to i64), i64 27, i64 ptrtoint (ptr @"Sys.Platform$dirReadNeedsPosition" to i64), i64 ptrtoint (ptr @__axiom_symn_35 to i64), i64 33, i64 ptrtoint (ptr @"Sys.Platform$direntNameOffset" to i64), i64 ptrtoint (ptr @__axiom_symn_36 to i64), i64 29, i64 ptrtoint (ptr @"Sys.Platform$cwdUsesFcntlPath" to i64), i64 ptrtoint (ptr @__axiom_symn_37 to i64), i64 29, i64 ptrtoint (ptr @"Sys.Platform$sysCwdNum" to i64), i64 ptrtoint (ptr @__axiom_symn_38 to i64), i64 22, i64 ptrtoint (ptr @"Sys.Platform$fGetPath" to i64), i64 ptrtoint (ptr @__axiom_symn_39 to i64), i64 21, i64 ptrtoint (ptr @"Sys.Platform$eExist" to i64), i64 ptrtoint (ptr @__axiom_symn_40 to i64), i64 19, i64 ptrtoint (ptr @"Sys.Platform$eIsDir" to i64), i64 ptrtoint (ptr @__axiom_symn_41 to i64), i64 19, i64 ptrtoint (ptr @"Sys.Platform$sysGetPidNum" to i64), i64 ptrtoint (ptr @__axiom_symn_42 to i64), i64 25, i64 ptrtoint (ptr @"Sys.Platform$sysClockNum" to i64), i64 ptrtoint (ptr @__axiom_symn_43 to i64), i64 24, i64 ptrtoint (ptr @"Sys.Platform$clockIsGettimeofday" to i64), i64 ptrtoint (ptr @__axiom_symn_44 to i64), i64 32, i64 ptrtoint (ptr @"Sys.Platform$clockHasMonotonic" to i64), i64 ptrtoint (ptr @__axiom_symn_45 to i64), i64 30, i64 ptrtoint (ptr @"Sys.Platform$sysSocketNum" to i64), i64 ptrtoint (ptr @__axiom_symn_46 to i64), i64 25, i64 ptrtoint (ptr @"Sys.Platform$sysBindNum" to i64), i64 ptrtoint (ptr @__axiom_symn_47 to i64), i64 23, i64 ptrtoint (ptr @"Sys.Platform$sysListenNum" to i64), i64 ptrtoint (ptr @__axiom_symn_48 to i64), i64 25, i64 ptrtoint (ptr @"Sys.Platform$sysAcceptNum" to i64), i64 ptrtoint (ptr @__axiom_symn_49 to i64), i64 25, i64 ptrtoint (ptr @"Sys.Platform$sysConnectNum" to i64), i64 ptrtoint (ptr @__axiom_symn_50 to i64), i64 26, i64 ptrtoint (ptr @"Sys.Platform$sysSetSockOptNum" to i64), i64 ptrtoint (ptr @__axiom_symn_51 to i64), i64 29, i64 ptrtoint (ptr @"Sys.Platform$sysGetSockOptNum" to i64), i64 ptrtoint (ptr @__axiom_symn_52 to i64), i64 29, i64 ptrtoint (ptr @"Sys.Platform$sysShutdownNum" to i64), i64 ptrtoint (ptr @__axiom_symn_53 to i64), i64 27, i64 ptrtoint (ptr @"Sys.Platform$sysFcntlNum" to i64), i64 ptrtoint (ptr @__axiom_symn_54 to i64), i64 24, i64 ptrtoint (ptr @"Sys.Platform$afInet" to i64), i64 ptrtoint (ptr @__axiom_symn_55 to i64), i64 19, i64 ptrtoint (ptr @"Sys.Platform$afInet6" to i64), i64 ptrtoint (ptr @__axiom_symn_56 to i64), i64 20, i64 ptrtoint (ptr @"Sys.Platform$sockStream" to i64), i64 ptrtoint (ptr @__axiom_symn_57 to i64), i64 23, i64 ptrtoint (ptr @"Sys.Platform$solSocket" to i64), i64 ptrtoint (ptr @__axiom_symn_58 to i64), i64 22, i64 ptrtoint (ptr @"Sys.Platform$soReuseAddr" to i64), i64 ptrtoint (ptr @__axiom_symn_59 to i64), i64 24, i64 ptrtoint (ptr @"Sys.Platform$soReusePort" to i64), i64 ptrtoint (ptr @__axiom_symn_60 to i64), i64 24, i64 ptrtoint (ptr @"Sys.Platform$soError" to i64), i64 ptrtoint (ptr @__axiom_symn_61 to i64), i64 20, i64 ptrtoint (ptr @"Sys.Platform$fGetFl" to i64), i64 ptrtoint (ptr @__axiom_symn_62 to i64), i64 19, i64 ptrtoint (ptr @"Sys.Platform$fSetFl" to i64), i64 ptrtoint (ptr @__axiom_symn_63 to i64), i64 19, i64 ptrtoint (ptr @"Sys.Platform$oNonblock" to i64), i64 ptrtoint (ptr @__axiom_symn_64 to i64), i64 22, i64 ptrtoint (ptr @"Sys.Platform$eAgain" to i64), i64 ptrtoint (ptr @__axiom_symn_65 to i64), i64 19, i64 ptrtoint (ptr @"Sys.Platform$sockaddrHasLenByte" to i64), i64 ptrtoint (ptr @__axiom_symn_66 to i64), i64 31, i64 ptrtoint (ptr @"Sys.Platform$pollUsesKqueue" to i64), i64 ptrtoint (ptr @__axiom_symn_67 to i64), i64 27, i64 ptrtoint (ptr @"Sys.Platform$sysPollCreateNum" to i64), i64 ptrtoint (ptr @__axiom_symn_68 to i64), i64 29, i64 ptrtoint (ptr @"Sys.Platform$sysPollWaitNum" to i64), i64 ptrtoint (ptr @__axiom_symn_69 to i64), i64 27, i64 ptrtoint (ptr @"Sys.Platform$sysPollCtlNum" to i64), i64 ptrtoint (ptr @__axiom_symn_70 to i64), i64 26, i64 ptrtoint (ptr @"Sys.Platform$pollEventSize" to i64), i64 ptrtoint (ptr @__axiom_symn_71 to i64), i64 26, i64 ptrtoint (ptr @"Sys.Platform$pollEventFdOffset" to i64), i64 ptrtoint (ptr @__axiom_symn_72 to i64), i64 30, i64 ptrtoint (ptr @"Sys.Platform$pollReadFilter" to i64), i64 ptrtoint (ptr @__axiom_symn_73 to i64), i64 27, i64 ptrtoint (ptr @"Sys.Platform$pollAddOp" to i64), i64 ptrtoint (ptr @__axiom_symn_74 to i64), i64 22, i64 ptrtoint (ptr @"Sys.Platform$pollDelOp" to i64), i64 ptrtoint (ptr @__axiom_symn_75 to i64), i64 22, i64 ptrtoint (ptr @"Sys.Platform$pollSigsetSize" to i64), i64 ptrtoint (ptr @__axiom_symn_76 to i64), i64 27, i64 ptrtoint (ptr @"Sys.Platform$sysRandomNum" to i64), i64 ptrtoint (ptr @__axiom_symn_77 to i64), i64 25, i64 ptrtoint (ptr @"Sys.Platform$randomIsGetentropy" to i64), i64 ptrtoint (ptr @__axiom_symn_78 to i64), i64 31, i64 ptrtoint (ptr @"Sys.Platform$randomMaxChunk" to i64), i64 ptrtoint (ptr @__axiom_symn_79 to i64), i64 27, i64 ptrtoint (ptr @"Sys.Platform$signalUsesSignalFd" to i64), i64 ptrtoint (ptr @__axiom_symn_80 to i64), i64 31, i64 ptrtoint (ptr @"Sys.Platform$sysSigProcMaskNum" to i64), i64 ptrtoint (ptr @__axiom_symn_81 to i64), i64 30, i64 ptrtoint (ptr @"Sys.Platform$sigBlockHow" to i64), i64 ptrtoint (ptr @__axiom_symn_82 to i64), i64 24, i64 ptrtoint (ptr @"Sys.Platform$sigsetBytes" to i64), i64 ptrtoint (ptr @__axiom_symn_83 to i64), i64 24, i64 ptrtoint (ptr @"Sys.Platform$sysSignalFdNum" to i64), i64 ptrtoint (ptr @__axiom_symn_84 to i64), i64 27, i64 ptrtoint (ptr @"Sys.Platform$sigInfoSize" to i64), i64 ptrtoint (ptr @__axiom_symn_85 to i64), i64 24, i64 ptrtoint (ptr @"Sys.Platform$pollSignalFilter" to i64), i64 ptrtoint (ptr @__axiom_symn_86 to i64), i64 29, i64 ptrtoint (ptr @"Sys.Platform$sysKillNum" to i64), i64 ptrtoint (ptr @__axiom_symn_87 to i64), i64 23, i64 ptrtoint (ptr @"Sys.Platform$sigTerm" to i64), i64 ptrtoint (ptr @__axiom_symn_88 to i64), i64 20, i64 ptrtoint (ptr @"Sys.Platform$sigInt" to i64), i64 ptrtoint (ptr @__axiom_symn_89 to i64), i64 19, i64 ptrtoint (ptr @"Sys.Platform$forkChildIsZero" to i64), i64 ptrtoint (ptr @__axiom_symn_90 to i64), i64 28, i64 ptrtoint (ptr @"Sys.Platform$acceptNonblockFlag" to i64), i64 ptrtoint (ptr @__axiom_symn_91 to i64), i64 31, i64 ptrtoint (ptr @"Mem$memAlloc" to i64), i64 ptrtoint (ptr @__axiom_symn_92 to i64), i64 12, i64 ptrtoint (ptr @"Mem$memAllocMapped" to i64), i64 ptrtoint (ptr @__axiom_symn_93 to i64), i64 18, i64 ptrtoint (ptr @"Mem$memMarkArray" to i64), i64 ptrtoint (ptr @__axiom_symn_94 to i64), i64 16, i64 ptrtoint (ptr @"Mem$memMarkLeaf" to i64), i64 ptrtoint (ptr @__axiom_symn_95 to i64), i64 15, i64 ptrtoint (ptr @"Mem$memCopy" to i64), i64 ptrtoint (ptr @__axiom_symn_96 to i64), i64 11, i64 ptrtoint (ptr @"Mem$memCopyFrom" to i64), i64 ptrtoint (ptr @__axiom_symn_97 to i64), i64 15, i64 ptrtoint (ptr @"Mem$memSet" to i64), i64 ptrtoint (ptr @__axiom_symn_98 to i64), i64 10, i64 ptrtoint (ptr @"Mem$memSetFrom" to i64), i64 ptrtoint (ptr @__axiom_symn_99 to i64), i64 14, i64 ptrtoint (ptr @"Mem$memCmp" to i64), i64 ptrtoint (ptr @__axiom_symn_100 to i64), i64 10, i64 ptrtoint (ptr @"Mem$memCmpFrom" to i64), i64 ptrtoint (ptr @__axiom_symn_101 to i64), i64 14, i64 ptrtoint (ptr @"Mem$memGetWord" to i64), i64 ptrtoint (ptr @__axiom_symn_102 to i64), i64 14, i64 ptrtoint (ptr @"Mem$memGetWordStr" to i64), i64 ptrtoint (ptr @__axiom_symn_103 to i64), i64 17, i64 ptrtoint (ptr @"Mem$memSetWord" to i64), i64 ptrtoint (ptr @__axiom_symn_104 to i64), i64 14, i64 ptrtoint (ptr @"Mem$memGetByte" to i64), i64 ptrtoint (ptr @__axiom_symn_105 to i64), i64 14, i64 ptrtoint (ptr @"Mem$memPutByte" to i64), i64 ptrtoint (ptr @__axiom_symn_106 to i64), i64 14, i64 ptrtoint (ptr @"Vec$vecDefaultCap" to i64), i64 ptrtoint (ptr @__axiom_symn_107 to i64), i64 17, i64 ptrtoint (ptr @"Vec$vecNew" to i64), i64 ptrtoint (ptr @__axiom_symn_108 to i64), i64 10, i64 ptrtoint (ptr @"Vec$vecWithCapacity" to i64), i64 ptrtoint (ptr @__axiom_symn_109 to i64), i64 19, i64 ptrtoint (ptr @"Vec$vecWithCapacityRef" to i64), i64 ptrtoint (ptr @__axiom_symn_110 to i64), i64 22, i64 ptrtoint (ptr @"Vec$vecNewRef" to i64), i64 ptrtoint (ptr @__axiom_symn_111 to i64), i64 13, i64 ptrtoint (ptr @"Vec$vecBuild" to i64), i64 ptrtoint (ptr @__axiom_symn_112 to i64), i64 12, i64 ptrtoint (ptr @"Vec$vecFree" to i64), i64 ptrtoint (ptr @__axiom_symn_113 to i64), i64 11, i64 ptrtoint (ptr @"Vec$vecOwnsRefs" to i64), i64 ptrtoint (ptr @__axiom_symn_114 to i64), i64 15, i64 ptrtoint (ptr @"Vec$vecLen" to i64), i64 ptrtoint (ptr @__axiom_symn_115 to i64), i64 10, i64 ptrtoint (ptr @"Vec$vecCap" to i64), i64 ptrtoint (ptr @__axiom_symn_116 to i64), i64 10, i64 ptrtoint (ptr @"Vec$vecData" to i64), i64 ptrtoint (ptr @__axiom_symn_117 to i64), i64 11, i64 ptrtoint (ptr @"Vec$vecGet" to i64), i64 ptrtoint (ptr @__axiom_symn_118 to i64), i64 10, i64 ptrtoint (ptr @"Vec$vecTry" to i64), i64 ptrtoint (ptr @__axiom_symn_119 to i64), i64 10, i64 ptrtoint (ptr @"Vec$vecGetStr" to i64), i64 ptrtoint (ptr @__axiom_symn_120 to i64), i64 13, i64 ptrtoint (ptr @"Vec$vecSet" to i64), i64 ptrtoint (ptr @__axiom_symn_121 to i64), i64 10, i64 ptrtoint (ptr @"Vec$vecReserve" to i64), i64 ptrtoint (ptr @__axiom_symn_122 to i64), i64 14, i64 ptrtoint (ptr @"Vec$vecGrownCap" to i64), i64 ptrtoint (ptr @__axiom_symn_123 to i64), i64 15, i64 ptrtoint (ptr @"Vec$vecReserveExactly" to i64), i64 ptrtoint (ptr @__axiom_symn_124 to i64), i64 21, i64 ptrtoint (ptr @"Vec$vecPush" to i64), i64 ptrtoint (ptr @__axiom_symn_125 to i64), i64 11, i64 ptrtoint (ptr @"Vec$vecPop" to i64), i64 ptrtoint (ptr @__axiom_symn_126 to i64), i64 10, i64 ptrtoint (ptr @"Vec$vecLast" to i64), i64 ptrtoint (ptr @__axiom_symn_127 to i64), i64 11, i64 ptrtoint (ptr @"Vec$vecClear" to i64), i64 ptrtoint (ptr @__axiom_symn_128 to i64), i64 12, i64 ptrtoint (ptr @"Vec$vecDropAt" to i64), i64 ptrtoint (ptr @__axiom_symn_129 to i64), i64 13, i64 ptrtoint (ptr @"Vec$vecDropFrom" to i64), i64 ptrtoint (ptr @__axiom_symn_130 to i64), i64 15, i64 ptrtoint (ptr @"Vec$vecSum" to i64), i64 ptrtoint (ptr @__axiom_symn_131 to i64), i64 10, i64 ptrtoint (ptr @"Vec$vecSumFrom" to i64), i64 ptrtoint (ptr @__axiom_symn_132 to i64), i64 14, i64 ptrtoint (ptr @"Vec$vecHash" to i64), i64 ptrtoint (ptr @__axiom_symn_133 to i64), i64 11, i64 ptrtoint (ptr @"Vec$vecHashFrom" to i64), i64 ptrtoint (ptr @__axiom_symn_134 to i64), i64 15, i64 ptrtoint (ptr @"Str$strWrap" to i64), i64 ptrtoint (ptr @__axiom_symn_135 to i64), i64 11, i64 ptrtoint (ptr @"Str$strWrapOwned" to i64), i64 ptrtoint (ptr @__axiom_symn_136 to i64), i64 16, i64 ptrtoint (ptr @"Str$strAlloc" to i64), i64 ptrtoint (ptr @__axiom_symn_137 to i64), i64 12, i64 ptrtoint (ptr @"Str$strFromLit" to i64), i64 ptrtoint (ptr @__axiom_symn_138 to i64), i64 14, i64 ptrtoint (ptr @"Str$cstrLen" to i64), i64 ptrtoint (ptr @__axiom_symn_139 to i64), i64 11, i64 ptrtoint (ptr @"Str$strLen" to i64), i64 ptrtoint (ptr @__axiom_symn_140 to i64), i64 10, i64 ptrtoint (ptr @"Str$strData" to i64), i64 ptrtoint (ptr @__axiom_symn_141 to i64), i64 11, i64 ptrtoint (ptr @"Str$strOwner" to i64), i64 ptrtoint (ptr @__axiom_symn_142 to i64), i64 12, i64 ptrtoint (ptr @"Str$strByte" to i64), i64 ptrtoint (ptr @__axiom_symn_143 to i64), i64 11, i64 ptrtoint (ptr @"Str$strCStr" to i64), i64 ptrtoint (ptr @__axiom_symn_144 to i64), i64 11, i64 ptrtoint (ptr @"Str$strIsEmpty" to i64), i64 ptrtoint (ptr @__axiom_symn_145 to i64), i64 14, i64 ptrtoint (ptr @"Str$strCmp" to i64), i64 ptrtoint (ptr @__axiom_symn_146 to i64), i64 10, i64 ptrtoint (ptr @"Str$strEq" to i64), i64 ptrtoint (ptr @__axiom_symn_147 to i64), i64 9, i64 ptrtoint (ptr @"Str$strSlice" to i64), i64 ptrtoint (ptr @__axiom_symn_148 to i64), i64 12, i64 ptrtoint (ptr @"Str$strDup" to i64), i64 ptrtoint (ptr @__axiom_symn_149 to i64), i64 10, i64 ptrtoint (ptr @"Str$strConcat" to i64), i64 ptrtoint (ptr @__axiom_symn_150 to i64), i64 13, i64 ptrtoint (ptr @"Str$strFindByte" to i64), i64 ptrtoint (ptr @__axiom_symn_151 to i64), i64 15, i64 ptrtoint (ptr @"Str$strStartsWith" to i64), i64 ptrtoint (ptr @__axiom_symn_152 to i64), i64 17, i64 ptrtoint (ptr @"Str$strIsDigit" to i64), i64 ptrtoint (ptr @__axiom_symn_153 to i64), i64 14, i64 ptrtoint (ptr @"Str$strIsAlpha" to i64), i64 ptrtoint (ptr @__axiom_symn_154 to i64), i64 14, i64 ptrtoint (ptr @"Str$strIsSpace" to i64), i64 ptrtoint (ptr @__axiom_symn_155 to i64), i64 14, i64 ptrtoint (ptr @"Str$strHexVal" to i64), i64 ptrtoint (ptr @__axiom_symn_156 to i64), i64 13, i64 ptrtoint (ptr @"Str$strIsHexDigit" to i64), i64 ptrtoint (ptr @__axiom_symn_157 to i64), i64 17, i64 ptrtoint (ptr @"Str$strSplit" to i64), i64 ptrtoint (ptr @__axiom_symn_158 to i64), i64 12, i64 ptrtoint (ptr @"Str$strSplitFrom" to i64), i64 ptrtoint (ptr @__axiom_symn_159 to i64), i64 16, i64 ptrtoint (ptr @"Str$strFromByte" to i64), i64 ptrtoint (ptr @__axiom_symn_160 to i64), i64 15, i64 ptrtoint (ptr @"Fmt$intIsMostNegative" to i64), i64 ptrtoint (ptr @__axiom_symn_161 to i64), i64 21, i64 ptrtoint (ptr @"Fmt$fmtIntWidth" to i64), i64 ptrtoint (ptr @__axiom_symn_162 to i64), i64 15, i64 ptrtoint (ptr @"Fmt$fmtInt" to i64), i64 ptrtoint (ptr @__axiom_symn_163 to i64), i64 10, i64 ptrtoint (ptr @"Fmt$fmtNat" to i64), i64 ptrtoint (ptr @__axiom_symn_164 to i64), i64 10, i64 ptrtoint (ptr @"Fmt$fmtDigits" to i64), i64 ptrtoint (ptr @__axiom_symn_165 to i64), i64 13, i64 ptrtoint (ptr @"Fmt$fmtHexShr4" to i64), i64 ptrtoint (ptr @__axiom_symn_166 to i64), i64 14, i64 ptrtoint (ptr @"Fmt$fmtHex" to i64), i64 ptrtoint (ptr @__axiom_symn_167 to i64), i64 10, i64 ptrtoint (ptr @"Fmt$fmtHexWidth" to i64), i64 ptrtoint (ptr @__axiom_symn_168 to i64), i64 15, i64 ptrtoint (ptr @"Fmt$fmtHexDigits" to i64), i64 ptrtoint (ptr @__axiom_symn_169 to i64), i64 16, i64 ptrtoint (ptr @"Fmt$fmtPadLeft" to i64), i64 ptrtoint (ptr @__axiom_symn_170 to i64), i64 14, i64 ptrtoint (ptr @"Fmt$fmtPadRight" to i64), i64 ptrtoint (ptr @__axiom_symn_171 to i64), i64 15, i64 ptrtoint (ptr @"Fmt$fmtPadCenter" to i64), i64 ptrtoint (ptr @__axiom_symn_172 to i64), i64 16, i64 ptrtoint (ptr @"Fmt$fmtPadZerosLeft" to i64), i64 ptrtoint (ptr @__axiom_symn_173 to i64), i64 19, i64 ptrtoint (ptr @"Fmt$fmtHexUpper" to i64), i64 ptrtoint (ptr @__axiom_symn_174 to i64), i64 15, i64 ptrtoint (ptr @"Fmt$fmtHexDigitsUpper" to i64), i64 ptrtoint (ptr @__axiom_symn_175 to i64), i64 21, i64 ptrtoint (ptr @"Fmt$powTen" to i64), i64 ptrtoint (ptr @__axiom_symn_176 to i64), i64 10, i64 ptrtoint (ptr @"Fmt$fmtPadZeros" to i64), i64 ptrtoint (ptr @__axiom_symn_177 to i64), i64 15, i64 ptrtoint (ptr @"Fmt$fmtFloat" to i64), i64 ptrtoint (ptr @__axiom_symn_178 to i64), i64 12, i64 ptrtoint (ptr @"Fmt$fmtFloatPrec" to i64), i64 ptrtoint (ptr @__axiom_symn_179 to i64), i64 16, i64 ptrtoint (ptr @"Fmt$fmtFloatAbs" to i64), i64 ptrtoint (ptr @__axiom_symn_180 to i64), i64 15, i64 ptrtoint (ptr @"Sys$stdin" to i64), i64 ptrtoint (ptr @__axiom_symn_181 to i64), i64 9, i64 ptrtoint (ptr @"Sys$stdout" to i64), i64 ptrtoint (ptr @__axiom_symn_182 to i64), i64 10, i64 ptrtoint (ptr @"Sys$stderr" to i64), i64 ptrtoint (ptr @__axiom_symn_183 to i64), i64 10, i64 ptrtoint (ptr @"Sys$sysWriteFd" to i64), i64 ptrtoint (ptr @__axiom_symn_184 to i64), i64 14, i64 ptrtoint (ptr @"Sys$sysWriteAllFd" to i64), i64 ptrtoint (ptr @__axiom_symn_185 to i64), i64 17, i64 ptrtoint (ptr @"Sys$sysReadFd" to i64), i64 ptrtoint (ptr @__axiom_symn_186 to i64), i64 13, i64 ptrtoint (ptr @"Sys$sysOpenPath" to i64), i64 ptrtoint (ptr @__axiom_symn_187 to i64), i64 15, i64 ptrtoint (ptr @"Sys$sysOpenPathMode" to i64), i64 ptrtoint (ptr @__axiom_symn_188 to i64), i64 19, i64 ptrtoint (ptr @"Sys$sysCloseFd" to i64), i64 ptrtoint (ptr @__axiom_symn_189 to i64), i64 14, i64 ptrtoint (ptr @"Sys$sysSeek" to i64), i64 ptrtoint (ptr @__axiom_symn_190 to i64), i64 11, i64 ptrtoint (ptr @"Sys$sysExitWith" to i64), i64 ptrtoint (ptr @__axiom_symn_191 to i64), i64 15, i64 ptrtoint (ptr @"Sys$sysFailed" to i64), i64 ptrtoint (ptr @__axiom_symn_192 to i64), i64 13, i64 ptrtoint (ptr @"Sys$sysErrno" to i64), i64 ptrtoint (ptr @__axiom_symn_193 to i64), i64 12, i64 ptrtoint (ptr @"Sys$sysReadFile" to i64), i64 ptrtoint (ptr @__axiom_symn_194 to i64), i64 15, i64 ptrtoint (ptr @"Sys$sysReadAll" to i64), i64 ptrtoint (ptr @__axiom_symn_195 to i64), i64 14, i64 ptrtoint (ptr @"Sys$sysArgc" to i64), i64 ptrtoint (ptr @__axiom_symn_196 to i64), i64 11, i64 ptrtoint (ptr @"Sys$sysArg" to i64), i64 ptrtoint (ptr @__axiom_symn_197 to i64), i64 10, i64 ptrtoint (ptr @"Sys$sysWriteFile" to i64), i64 ptrtoint (ptr @__axiom_symn_198 to i64), i64 16, i64 ptrtoint (ptr @"Sys$sysAppendFile" to i64), i64 ptrtoint (ptr @__axiom_symn_199 to i64), i64 17, i64 ptrtoint (ptr @"Sys$sysRename" to i64), i64 ptrtoint (ptr @__axiom_symn_200 to i64), i64 13, i64 ptrtoint (ptr @"Sys$sysUnlink" to i64), i64 ptrtoint (ptr @__axiom_symn_201 to i64), i64 13, i64 ptrtoint (ptr @"Sys$sysMkdir" to i64), i64 ptrtoint (ptr @__axiom_symn_202 to i64), i64 12, i64 ptrtoint (ptr @"Sys$sysDirMode" to i64), i64 ptrtoint (ptr @__axiom_symn_203 to i64), i64 14, i64 ptrtoint (ptr @"Sys$sysRmdir" to i64), i64 ptrtoint (ptr @__axiom_symn_204 to i64), i64 12, i64 ptrtoint (ptr @"Sys$sysFileExists" to i64), i64 ptrtoint (ptr @__axiom_symn_205 to i64), i64 17, i64 ptrtoint (ptr @"Sys$sysFileSize" to i64), i64 ptrtoint (ptr @__axiom_symn_206 to i64), i64 15, i64 ptrtoint (ptr @"Sys$sysReadErrno" to i64), i64 ptrtoint (ptr @__axiom_symn_207 to i64), i64 16, i64 ptrtoint (ptr @"Sys$sysIsDir" to i64), i64 ptrtoint (ptr @__axiom_symn_208 to i64), i64 12, i64 ptrtoint (ptr @"Sys$sysDirBufBytes" to i64), i64 ptrtoint (ptr @__axiom_symn_209 to i64), i64 18, i64 ptrtoint (ptr @"Sys$sysReadDir" to i64), i64 ptrtoint (ptr @__axiom_symn_210 to i64), i64 14, i64 ptrtoint (ptr @"Sys$sysReadDirLoop" to i64), i64 ptrtoint (ptr @__axiom_symn_211 to i64), i64 18, i64 ptrtoint (ptr @"Sys$sysReadDirDecode" to i64), i64 ptrtoint (ptr @__axiom_symn_212 to i64), i64 20, i64 ptrtoint (ptr @"Sys$sysGetCwd" to i64), i64 ptrtoint (ptr @__axiom_symn_213 to i64), i64 13, i64 ptrtoint (ptr @"Sys$sysEnvSlot" to i64), i64 ptrtoint (ptr @__axiom_symn_214 to i64), i64 14, i64 ptrtoint (ptr @"Sys$sysEnvCount" to i64), i64 ptrtoint (ptr @__axiom_symn_215 to i64), i64 15, i64 ptrtoint (ptr @"Sys$sysEnvCountFrom" to i64), i64 ptrtoint (ptr @__axiom_symn_216 to i64), i64 19, i64 ptrtoint (ptr @"Sys$sysEnv" to i64), i64 ptrtoint (ptr @__axiom_symn_217 to i64), i64 10, i64 ptrtoint (ptr @"Sys$sysEnvLookup" to i64), i64 ptrtoint (ptr @__axiom_symn_218 to i64), i64 16, i64 ptrtoint (ptr @"Sys$sysEnvp" to i64), i64 ptrtoint (ptr @__axiom_symn_219 to i64), i64 11, i64 ptrtoint (ptr @"Sys$sysEnvpFill" to i64), i64 ptrtoint (ptr @__axiom_symn_220 to i64), i64 15, i64 ptrtoint (ptr @"Sys$sysSpawn" to i64), i64 ptrtoint (ptr @__axiom_symn_221 to i64), i64 12, i64 ptrtoint (ptr @"Sys$sysWaitPid" to i64), i64 ptrtoint (ptr @__axiom_symn_222 to i64), i64 14, i64 ptrtoint (ptr @"Sys$sysExitCode" to i64), i64 ptrtoint (ptr @__axiom_symn_223 to i64), i64 15, i64 ptrtoint (ptr @"Sys$sysTermSignal" to i64), i64 ptrtoint (ptr @__axiom_symn_224 to i64), i64 17, i64 ptrtoint (ptr @"Sys$sysRun" to i64), i64 ptrtoint (ptr @__axiom_symn_225 to i64), i64 10, i64 ptrtoint (ptr @"Sys$sysRunPath" to i64), i64 ptrtoint (ptr @__axiom_symn_226 to i64), i64 14, i64 ptrtoint (ptr @"Sys$sysRunSearch" to i64), i64 ptrtoint (ptr @__axiom_symn_227 to i64), i64 16, i64 ptrtoint (ptr @"Sys$sysGetPid" to i64), i64 ptrtoint (ptr @__axiom_symn_228 to i64), i64 13, i64 ptrtoint (ptr @"Sys$sysNowMicros" to i64), i64 ptrtoint (ptr @__axiom_symn_229 to i64), i64 16, i64 ptrtoint (ptr @"Sys$sysNowMonotonic" to i64), i64 ptrtoint (ptr @__axiom_symn_230 to i64), i64 19, i64 ptrtoint (ptr @"Sys$netSocketTcp" to i64), i64 ptrtoint (ptr @__axiom_symn_231 to i64), i64 16, i64 ptrtoint (ptr @"Sys$netSocketTcp6" to i64), i64 ptrtoint (ptr @__axiom_symn_232 to i64), i64 17, i64 ptrtoint (ptr @"Sys$netAddr4Bytes" to i64), i64 ptrtoint (ptr @__axiom_symn_233 to i64), i64 17, i64 ptrtoint (ptr @"Sys$netAddr6Bytes" to i64), i64 ptrtoint (ptr @__axiom_symn_234 to i64), i64 17, i64 ptrtoint (ptr @"Sys$netAddrMaxBytes" to i64), i64 ptrtoint (ptr @__axiom_symn_235 to i64), i64 19, i64 ptrtoint (ptr @"Sys$netAddr4" to i64), i64 ptrtoint (ptr @__axiom_symn_236 to i64), i64 12, i64 ptrtoint (ptr @"Sys$netAddr6" to i64), i64 ptrtoint (ptr @__axiom_symn_237 to i64), i64 12, i64 ptrtoint (ptr @"Sys$netPutGroup" to i64), i64 ptrtoint (ptr @__axiom_symn_238 to i64), i64 15, i64 ptrtoint (ptr @"Sys$netGetGroup" to i64), i64 ptrtoint (ptr @__axiom_symn_239 to i64), i64 15, i64 ptrtoint (ptr @"Sys$netAddrFamily" to i64), i64 ptrtoint (ptr @__axiom_symn_240 to i64), i64 17, i64 ptrtoint (ptr @"Sys$netAddrPort" to i64), i64 ptrtoint (ptr @__axiom_symn_241 to i64), i64 15, i64 ptrtoint (ptr @"Sys$netAddrSize" to i64), i64 ptrtoint (ptr @__axiom_symn_242 to i64), i64 15, i64 ptrtoint (ptr @"Sys$netBind" to i64), i64 ptrtoint (ptr @__axiom_symn_243 to i64), i64 11, i64 ptrtoint (ptr @"Sys$netListen" to i64), i64 ptrtoint (ptr @__axiom_symn_244 to i64), i64 13, i64 ptrtoint (ptr @"Sys$netAccept" to i64), i64 ptrtoint (ptr @__axiom_symn_245 to i64), i64 13, i64 ptrtoint (ptr @"Sys$netAcceptFinish" to i64), i64 ptrtoint (ptr @__axiom_symn_246 to i64), i64 19, i64 ptrtoint (ptr @"Sys$netAcceptFrom" to i64), i64 ptrtoint (ptr @__axiom_symn_247 to i64), i64 17, i64 ptrtoint (ptr @"Sys$netAddrLenRead" to i64), i64 ptrtoint (ptr @__axiom_symn_248 to i64), i64 18, i64 ptrtoint (ptr @"Sys$netPutInt32" to i64), i64 ptrtoint (ptr @__axiom_symn_249 to i64), i64 15, i64 ptrtoint (ptr @"Sys$netGetInt32" to i64), i64 ptrtoint (ptr @__axiom_symn_250 to i64), i64 15, i64 ptrtoint (ptr @"Sys$netAddrText" to i64), i64 ptrtoint (ptr @__axiom_symn_251 to i64), i64 15, i64 ptrtoint (ptr @"Sys$netAddrText4" to i64), i64 ptrtoint (ptr @__axiom_symn_252 to i64), i64 16, i64 ptrtoint (ptr @"Sys$netAddrZeroRun" to i64), i64 ptrtoint (ptr @__axiom_symn_253 to i64), i64 18, i64 ptrtoint (ptr @"Sys$netAddrZeroRunStart" to i64), i64 ptrtoint (ptr @__axiom_symn_254 to i64), i64 23, i64 ptrtoint (ptr @"Sys$netAddrText6" to i64), i64 ptrtoint (ptr @__axiom_symn_255 to i64), i64 16, i64 ptrtoint (ptr @"Sys$netAddrTextPort" to i64), i64 ptrtoint (ptr @__axiom_symn_256 to i64), i64 19, i64 ptrtoint (ptr @"Sys$netSetBlocking" to i64), i64 ptrtoint (ptr @__axiom_symn_257 to i64), i64 18, i64 ptrtoint (ptr @"Sys$netConnect" to i64), i64 ptrtoint (ptr @__axiom_symn_258 to i64), i64 14, i64 ptrtoint (ptr @"Sys$netShutdown" to i64), i64 ptrtoint (ptr @__axiom_symn_259 to i64), i64 15, i64 ptrtoint (ptr @"Sys$netSetOptInt" to i64), i64 ptrtoint (ptr @__axiom_symn_260 to i64), i64 16, i64 ptrtoint (ptr @"Sys$netSetNonBlocking" to i64), i64 ptrtoint (ptr @__axiom_symn_261 to i64), i64 21, i64 ptrtoint (ptr @"Sys$netWouldBlock" to i64), i64 ptrtoint (ptr @__axiom_symn_262 to i64), i64 17, i64 ptrtoint (ptr @"Sys$netPutWord" to i64), i64 ptrtoint (ptr @__axiom_symn_263 to i64), i64 14, i64 ptrtoint (ptr @"Sys$netGetWord" to i64), i64 ptrtoint (ptr @__axiom_symn_264 to i64), i64 14, i64 ptrtoint (ptr @"Sys$netPollBufBytes" to i64), i64 ptrtoint (ptr @__axiom_symn_265 to i64), i64 19, i64 ptrtoint (ptr @"Sys$netPollCreate" to i64), i64 ptrtoint (ptr @__axiom_symn_266 to i64), i64 17, i64 ptrtoint (ptr @"Sys$netPollRec" to i64), i64 ptrtoint (ptr @__axiom_symn_267 to i64), i64 14, i64 ptrtoint (ptr @"Sys$netPollAddRead" to i64), i64 ptrtoint (ptr @__axiom_symn_268 to i64), i64 18, i64 ptrtoint (ptr @"Sys$netPollDelRead" to i64), i64 ptrtoint (ptr @__axiom_symn_269 to i64), i64 18, i64 ptrtoint (ptr @"Sys$netPollWait" to i64), i64 ptrtoint (ptr @__axiom_symn_270 to i64), i64 15, i64 ptrtoint (ptr @"Sys$netPollFdAt" to i64), i64 ptrtoint (ptr @__axiom_symn_271 to i64), i64 15, i64 ptrtoint (ptr @"Sys$sysRandomBytes" to i64), i64 ptrtoint (ptr @__axiom_symn_272 to i64), i64 18, i64 ptrtoint (ptr @"Sys$sysSigBit" to i64), i64 ptrtoint (ptr @__axiom_symn_273 to i64), i64 13, i64 ptrtoint (ptr @"Sys$sysSignalBlock" to i64), i64 ptrtoint (ptr @__axiom_symn_274 to i64), i64 18, i64 ptrtoint (ptr @"Sys$netSignalOpen" to i64), i64 ptrtoint (ptr @__axiom_symn_275 to i64), i64 17, i64 ptrtoint (ptr @"Sys$netPollSignalAt" to i64), i64 ptrtoint (ptr @__axiom_symn_276 to i64), i64 19, i64 ptrtoint (ptr @"Sys$sysKill" to i64), i64 ptrtoint (ptr @__axiom_symn_277 to i64), i64 11, i64 ptrtoint (ptr @"Sys$sysForkProcess" to i64), i64 ptrtoint (ptr @__axiom_symn_278 to i64), i64 18, i64 ptrtoint (ptr @"IO$writeStr" to i64), i64 ptrtoint (ptr @__axiom_symn_279 to i64), i64 11, i64 ptrtoint (ptr @"IO$printLit" to i64), i64 ptrtoint (ptr @__axiom_symn_280 to i64), i64 11, i64 ptrtoint (ptr @"IO$printlnLit" to i64), i64 ptrtoint (ptr @__axiom_symn_281 to i64), i64 13, i64 ptrtoint (ptr @"IO$readFileLit" to i64), i64 ptrtoint (ptr @__axiom_symn_282 to i64), i64 14, i64 ptrtoint (ptr @"IO$readFile" to i64), i64 ptrtoint (ptr @__axiom_symn_283 to i64), i64 11, i64 ptrtoint (ptr @"IO$ioPath" to i64), i64 ptrtoint (ptr @__axiom_symn_284 to i64), i64 9, i64 ptrtoint (ptr @"IO$writeFile" to i64), i64 ptrtoint (ptr @__axiom_symn_285 to i64), i64 12, i64 ptrtoint (ptr @"IO$appendFile" to i64), i64 ptrtoint (ptr @__axiom_symn_286 to i64), i64 13, i64 ptrtoint (ptr @"IO$removeFile" to i64), i64 ptrtoint (ptr @__axiom_symn_287 to i64), i64 13, i64 ptrtoint (ptr @"IO$renamePath" to i64), i64 ptrtoint (ptr @__axiom_symn_288 to i64), i64 13, i64 ptrtoint (ptr @"IO$copyFile" to i64), i64 ptrtoint (ptr @__axiom_symn_289 to i64), i64 11, i64 ptrtoint (ptr @"IO$fileExists" to i64), i64 ptrtoint (ptr @__axiom_symn_290 to i64), i64 13, i64 ptrtoint (ptr @"IO$isDir" to i64), i64 ptrtoint (ptr @__axiom_symn_291 to i64), i64 8, i64 ptrtoint (ptr @"IO$fileSize" to i64), i64 ptrtoint (ptr @__axiom_symn_292 to i64), i64 11, i64 ptrtoint (ptr @"IO$readErrno" to i64), i64 ptrtoint (ptr @__axiom_symn_293 to i64), i64 12, i64 ptrtoint (ptr @"IO$makeDir" to i64), i64 ptrtoint (ptr @__axiom_symn_294 to i64), i64 10, i64 ptrtoint (ptr @"IO$makeDirAll" to i64), i64 ptrtoint (ptr @__axiom_symn_295 to i64), i64 13, i64 ptrtoint (ptr @"IO$makeDirAllFrom" to i64), i64 ptrtoint (ptr @__axiom_symn_296 to i64), i64 17, i64 ptrtoint (ptr @"IO$makeDirOk" to i64), i64 ptrtoint (ptr @__axiom_symn_297 to i64), i64 12, i64 ptrtoint (ptr @"IO$removeDir" to i64), i64 ptrtoint (ptr @__axiom_symn_298 to i64), i64 12, i64 ptrtoint (ptr @"IO$listDir" to i64), i64 ptrtoint (ptr @__axiom_symn_299 to i64), i64 10, i64 ptrtoint (ptr @"IO$listDirKeep" to i64), i64 ptrtoint (ptr @__axiom_symn_300 to i64), i64 14, i64 ptrtoint (ptr @"IO$listDirInsert" to i64), i64 ptrtoint (ptr @__axiom_symn_301 to i64), i64 16, i64 ptrtoint (ptr @"IO$listDirSift" to i64), i64 ptrtoint (ptr @__axiom_symn_302 to i64), i64 14, i64 ptrtoint (ptr @"IO$cwd" to i64), i64 ptrtoint (ptr @__axiom_symn_303 to i64), i64 6, i64 ptrtoint (ptr @"IO$exit" to i64), i64 ptrtoint (ptr @__axiom_symn_304 to i64), i64 7, i64 ptrtoint (ptr @"IO$die" to i64), i64 ptrtoint (ptr @__axiom_symn_305 to i64), i64 6, i64 ptrtoint (ptr @ask to i64), i64 ptrtoint (ptr @__axiom_symn_306 to i64), i64 3, i64 ptrtoint (ptr @usable to i64), i64 ptrtoint (ptr @__axiom_symn_307 to i64), i64 6, i64 ptrtoint (ptr @__axiom_user_main to i64), i64 ptrtoint (ptr @__axiom_symn_308 to i64), i64 17, i64 ptrtoint (ptr @_lam_0 to i64), i64 ptrtoint (ptr @__axiom_symn_309 to i64), i64 6, i64 ptrtoint (ptr @"Show#String#show" to i64), i64 ptrtoint (ptr @__axiom_symn_310 to i64), i64 16, i64 ptrtoint (ptr @"Show#Int#show" to i64), i64 ptrtoint (ptr @__axiom_symn_311 to i64), i64 13, i64 ptrtoint (ptr @"Show#Bool#show" to i64), i64 ptrtoint (ptr @__axiom_symn_312 to i64), i64 14, i64 ptrtoint (ptr @"Show#Float#show" to i64), i64 ptrtoint (ptr @__axiom_symn_313 to i64), i64 15, i64 ptrtoint (ptr @__axiom_recover_save to i64), i64 ptrtoint (ptr @__axiom_symn_314 to i64), i64 20, i64 ptrtoint (ptr @__axiom_recover_load to i64), i64 ptrtoint (ptr @__axiom_symn_315 to i64), i64 20]
@__axiom_bt_hdr = private unnamed_addr constant [42 x i8] c"axiom: backtrace (most recent call first)\0A"
@__axiom_bt_at = private unnamed_addr constant [5 x i8] c"  at "
@__axiom_bt_nl = private unnamed_addr constant [1 x i8] c"\0A"
@__axiom_bt_unk = private unnamed_addr constant [9 x i8] c"<unknown>"

define i64 @main(i64 %argc, i64 %argv) #0 {
entry:
  store i64 %argc, ptr @__axiom_argc, align 8
  store i64 %argv, ptr @__axiom_argv, align 8
  %r = tail call i64 @__axiom_user_main()
  ret i64 %r
}

; Function Attrs: nounwind
define i64 @axiom_alloc(i64 %size) #1 {
entry:
  %iszero = icmp eq i64 %size, 0
  br i1 %iszero, label %zero, label %sized

common.ret:                                       ; preds = %wiped, %zero
  %common.ret.op = phi i64 [ %zb, %zero ], [ %user, %wiped ]
  ret i64 %common.ret.op

zero:                                             ; preds = %entry
  %zb = load i64, ptr @__axiom_bump, align 8
  br label %common.ret

sized:                                            ; preds = %entry
  %padded = add i64 %size, 15
  %sz0 = and i64 %padded, -16
  %sz = add i64 %sz0, 16
  %small = icmp ult i64 %sz0, 65537
  br i1 %small, label %try_pop, label %bump_path

try_pop:                                          ; preds = %sized
  %cls = lshr i64 %padded, 4
  %slotp = getelementptr i64, ptr @__axiom_slabs, i64 %cls
  %shead = load i64, ptr %slotp, align 8
  %sempty = icmp eq i64 %shead, 0
  br i1 %sempty, label %bump_path, label %pop

pop:                                              ; preds = %try_pop
  %pnextp = inttoptr i64 %shead to ptr
  %pnext = load i64, ptr %pnextp, align 8
  store i64 %pnext, ptr %slotp, align 8
  %pe = add i64 %shead, %sz
  %ph = load i64, ptr @__axiom_high, align 8
  br label %handout

bump_path:                                        ; preds = %try_pop, %sized
  %cur = load i64, ptr @__axiom_bump, align 8
  %next = add i64 %cur, %sz
  %end = load i64, ptr @__axiom_bump_end, align 8
  %fits.not = icmp ugt i64 %next, %end
  br i1 %fits.not, label %refill, label %fast

fast:                                             ; preds = %bump_path
  store i64 %next, ptr @__axiom_bump, align 8
  %high = load i64, ptr @__axiom_high, align 8
  br label %handout

refill:                                           ; preds = %bump_path
  %0 = add i64 %sz0, -1048545
  %big = icmp ult i64 %0, -1048577
  %rounded0 = add i64 %sz0, 65567
  %rounded = and i64 %rounded0, -65536
  %chunk = select i1 %big, i64 %rounded, i64 1048576
  %fhead = load i64, ptr @__axiom_free, align 8
  br label %scan

scan:                                             ; preds = %scan_test, %refill
  %cand = phi i64 [ %fhead, %refill ], [ %cnext, %scan_test ]
  %prev = phi i64 [ 0, %refill ], [ %cand, %scan_test ]
  %exhausted = icmp eq i64 %cand, 0
  br i1 %exhausted, label %map, label %scan_test

scan_test:                                        ; preds = %scan
  %candp = inttoptr i64 %cand to ptr
  %candsz = load i64, ptr %candp, align 8
  %candlink = add i64 %cand, 8
  %candlinkp = inttoptr i64 %candlink to ptr
  %cnext = load i64, ptr %candlinkp, align 8
  %roomy.not = icmp ult i64 %candsz, %chunk
  br i1 %roomy.not, label %scan, label %unlink

unlink:                                           ; preds = %scan_test
  %cand_end = add i64 %candsz, %cand
  %at_head = icmp eq i64 %prev, 0
  br i1 %at_head, label %unlink_head, label %unlink_mid

unlink_head:                                      ; preds = %unlink
  store i64 %cnext, ptr @__axiom_free, align 8
  br label %install

unlink_mid:                                       ; preds = %unlink
  %prevlink = add i64 %prev, 8
  %prevlinkp = inttoptr i64 %prevlink to ptr
  store i64 %cnext, ptr %prevlinkp, align 8
  br label %install

map:                                              ; preds = %scan
  %addr = tail call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 222, i64 0, i64 %chunk, i64 3, i64 34, i64 -1, i64 0) #15
  %1 = add i64 %addr, 4095
  %failed = icmp ult i64 %1, 8191
  br i1 %failed, label %oom, label %mapped

mapped:                                           ; preds = %map
  %virgin_high = add nuw i64 %addr, 16
  br label %install

install:                                          ; preds = %mapped, %unlink_mid, %unlink_head
  %base = phi i64 [ %addr, %mapped ], [ %cand, %unlink_head ], [ %cand, %unlink_mid ]
  %bsize = phi i64 [ %chunk, %mapped ], [ %candsz, %unlink_head ], [ %candsz, %unlink_mid ]
  %chunk_high = phi i64 [ %virgin_high, %mapped ], [ %cand_end, %unlink_head ], [ %cand_end, %unlink_mid ]
  %basep = inttoptr i64 %base to ptr
  store i64 %bsize, ptr %basep, align 8
  %baselink = add i64 %base, 8
  %baselinkp = inttoptr i64 %baselink to ptr
  %chead = load i64, ptr @__axiom_chunk, align 8
  store i64 %chead, ptr %baselinkp, align 8
  store i64 %base, ptr @__axiom_chunk, align 8
  %data = add i64 %base, 16
  %new_bump = add i64 %data, %sz
  store i64 %new_bump, ptr @__axiom_bump, align 8
  %new_end = add i64 %bsize, %base
  store i64 %new_end, ptr @__axiom_bump_end, align 8
  br label %handout

handout:                                          ; preds = %install, %fast, %pop
  %hb = phi i64 [ %cur, %fast ], [ %data, %install ], [ %shead, %pop ]
  %he = phi i64 [ %next, %fast ], [ %new_bump, %install ], [ %pe, %pop ]
  %hh = phi i64 [ %high, %fast ], [ %chunk_high, %install ], [ %ph, %pop ]
  %recyc = phi i1 [ false, %fast ], [ false, %install ], [ true, %pop ]
  %bstop = tail call i64 @llvm.umin.i64(i64 %he, i64 %hh)
  %stop = select i1 %recyc, i64 %he, i64 %bstop
  %nh = tail call i64 @llvm.umax.i64(i64 %he, i64 %hh)
  %newhigh = select i1 %recyc, i64 %hh, i64 %nh
  store i64 %newhigh, ptr @__axiom_high, align 8
  %wmore3 = icmp ult i64 %hb, %stop
  br i1 %wmore3, label %wipe_body, label %wiped

wipe_body:                                        ; preds = %handout, %wipe_body
  %wi4 = phi i64 [ %wnext, %wipe_body ], [ %hb, %handout ]
  %wp = inttoptr i64 %wi4 to ptr
  store i64 0, ptr %wp, align 8
  %wnext = add i64 %wi4, 8
  %wmore = icmp ult i64 %wnext, %stop
  br i1 %wmore, label %wipe_body, label %wiped

wiped:                                            ; preds = %wipe_body, %handout
  %cwp = inttoptr i64 %hb to ptr
  store i64 0, ptr %cwp, align 8
  %shpw = add i64 %hb, 8
  %shpwp = inttoptr i64 %shpw to ptr
  %wcnt = lshr exact i64 %sz0, 2
  %wbig = icmp ugt i64 %sz0, 131064
  %wleaf = select i1 %wbig, i64 0, i64 %wcnt
  store i64 %wleaf, ptr %shpwp, align 8
  %user = add i64 %hb, 16
  br label %common.ret

oom:                                              ; preds = %map
  %2 = tail call i64 @__axiom_out_of_memory()
  unreachable
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(readwrite, inaccessiblemem: none, target_mem0: none, target_mem1: none)
define void @axiom_retain(i64 %h) #2 {
entry:
  %imm = icmp slt i64 %h, 4096
  br i1 %imm, label %done, label %chk

chk:                                              ; preds = %entry
  %hoff = add nsw i64 %h, -16
  %cp = inttoptr i64 %hoff to ptr
  %c = load i64, ptr %cp, align 8
  %stat = icmp eq i64 %c, -1
  br i1 %stat, label %done, label %bump

bump:                                             ; preds = %chk
  %c1 = add nuw i64 %c, 1
  store i64 %c1, ptr %cp, align 8
  br label %done

done:                                             ; preds = %bump, %chk, %entry
  ret void
}

define void @axiom_release(i64 %h0) #0 {
start:
  br label %relone

relone:                                           ; preds = %relchild, %start
  %dead.0 = phi i64 [ 0, %start ], [ %dead.2.ph, %relchild ]
  %cur.0 = phi i64 [ %h0, %start ], [ %wval, %relchild ]
  %D.0 = phi i64 [ 0, %start ], [ %D.1.ph, %relchild ]
  %wi.0 = phi i64 [ undef, %start ], [ %wi.2, %relchild ]
  %wm.0 = phi i64 [ undef, %start ], [ %wm.2, %relchild ]
  %warr.0 = phi i64 [ 0, %start ], [ %warr.114, %relchild ]
  %imm = icmp slt i64 %cur.0, 4096
  br i1 %imm, label %after, label %chk

chk:                                              ; preds = %relone
  %hoff = add nsw i64 %cur.0, -16
  %cp = inttoptr i64 %hoff to ptr
  %c = load i64, ptr %cp, align 8
  %c.off = add i64 %c, -1
  %switch = icmp ult i64 %c.off, -2
  br i1 %switch, label %dec, label %after

dec:                                              ; preds = %chk
  store i64 %c.off, ptr %cp, align 8
  %isdead = icmp eq i64 %c.off, 0
  br i1 %isdead, label %dead0, label %after

dead0:                                            ; preds = %dec
  %shq = add nsw i64 %cur.0, -8
  %shqp = inttoptr i64 %shq to ptr
  %shw = load i64, ptr %shqp, align 8
  %formb = and i64 %shw, 1
  %isrec = icmp eq i64 %formb, 0
  %needw = icmp ugt i64 %shw, 32767
  %dowalk = and i1 %needw, %isrec
  br i1 %dowalk, label %defer, label %notrec

notrec:                                           ; preds = %dead0
  br i1 %isrec, label %filev, label %foreign

foreign:                                          ; preds = %notrec
  %fdp = inttoptr i64 %cur.0 to ptr
  %fdrop = load i64, ptr %fdp, align 8
  %fa1 = add nuw i64 %cur.0, 8
  %fap = inttoptr i64 %fa1 to ptr
  %farg = load i64, ptr %fap, align 8
  %fhas = icmp ne i64 %fdrop, 0
  %fliv = icmp ne i64 %farg, 0
  %fdo = and i1 %fhas, %fliv
  br i1 %fdo, label %fcall, label %filev

fcall:                                            ; preds = %foreign
  store i64 0, ptr %fap, align 8
  %ffp = inttoptr i64 %fdrop to ptr
  %fres = tail call i64 %ffp(i64 %farg)
  br label %filev

defer:                                            ; preds = %dead0
  store i64 %dead.0, ptr %cp, align 8
  br label %after

filev:                                            ; preds = %fcall, %foreign, %notrec
  %bcnt0 = lshr i64 %shw, 1
  %bcnt = and i64 %bcnt0, 16383
  %0 = add nsw i64 %bcnt, -1
  %ok = icmp ult i64 %0, 8192
  br i1 %ok, label %push, label %after

push:                                             ; preds = %filev
  %pcls = lshr i64 %bcnt, 1
  %pslotp = getelementptr i64, ptr @__axiom_slabs, i64 %pcls
  %ohead = load i64, ptr %pslotp, align 8
  store i64 %ohead, ptr %cp, align 8
  store i64 %hoff, ptr %pslotp, align 8
  br label %after

after:                                            ; preds = %chk, %push, %filev, %defer, %dec, %relone
  %dead.1 = phi i64 [ %dead.0, %relone ], [ %cur.0, %defer ], [ %dead.0, %push ], [ %dead.0, %filev ], [ %dead.0, %dec ], [ %dead.0, %chk ]
  %hasD.not = icmp eq i64 %D.0, 0
  br i1 %hasD.not, label %drain, label %walk.peel

walk.peel:                                        ; preds = %after, %popD
  %dead.2.ph = phi i64 [ %nxt, %popD ], [ %dead.1, %after ]
  %D.1.ph = phi i64 [ %dead.3, %popD ], [ %D.0, %after ]
  %wi.1.ph = phi i64 [ 0, %popD ], [ %wi.0, %after ]
  %wm.1.ph = phi i64 [ %pwm, %popD ], [ %wm.0, %after ]
  %warr.1.ph = phi i64 [ %parr.lobit, %popD ], [ %warr.0, %after ]
  %mzero.peel = icmp eq i64 %wm.1.ph, 0
  br i1 %mzero.peel, label %fileD, label %stepone.peel

stepone.peel:                                     ; preds = %walk.peel
  %wisarr.not.peel = icmp eq i64 %warr.1.ph, 0
  br i1 %wisarr.not.peel, label %testbit.peel, label %arrstep

testbit.peel:                                     ; preds = %stepone.peel
  %bit.peel = and i64 %wm.1.ph, 1
  %m1.peel = lshr i64 %wm.1.ph, 1
  %i1.peel = add i64 %wi.1.ph, 1
  %isset.not.peel = icmp eq i64 %bit.peel, 0
  br i1 %isset.not.peel, label %walk, label %relchild

walk:                                             ; preds = %testbit.peel, %testbit
  %wi.1 = phi i64 [ %i1, %testbit ], [ %i1.peel, %testbit.peel ]
  %wm.1 = phi i64 [ %m1, %testbit ], [ %m1.peel, %testbit.peel ]
  %mzero = icmp eq i64 %wm.1, 0
  br i1 %mzero, label %fileD, label %testbit

arrstep:                                          ; preds = %stepone.peel
  %am1 = add nsw i64 %wm.1.ph, -1
  %ai1 = add i64 %wi.1.ph, 1
  br label %relchild

testbit:                                          ; preds = %walk
  %bit = and i64 %wm.1, 1
  %m1 = lshr i64 %wm.1, 1
  %i1 = add i64 %wi.1, 1
  %isset.not = icmp eq i64 %bit, 0
  br i1 %isset.not, label %walk, label %relchild, !llvm.loop !0

relchild:                                         ; preds = %testbit, %testbit.peel, %arrstep
  %wi.119 = phi i64 [ %wi.1.ph, %arrstep ], [ %wi.1.ph, %testbit.peel ], [ %wi.1, %testbit ]
  %warr.114 = phi i64 [ 1, %arrstep ], [ 0, %testbit.peel ], [ 0, %testbit ]
  %wi.2 = phi i64 [ %ai1, %arrstep ], [ %i1.peel, %testbit.peel ], [ %i1, %testbit ]
  %wm.2 = phi i64 [ %am1, %arrstep ], [ %m1.peel, %testbit.peel ], [ %m1, %testbit ]
  %woff = shl i64 %wi.119, 3
  %waddr = add i64 %woff, %D.1.ph
  %waddrp = inttoptr i64 %waddr to ptr
  %wval = load i64, ptr %waddrp, align 8
  br label %relone

fileD:                                            ; preds = %walk, %walk.peel
  %dq = add i64 %D.1.ph, -8
  %dqp = inttoptr i64 %dq to ptr
  %dshw = load i64, ptr %dqp, align 8
  %dcnt0 = lshr i64 %dshw, 1
  %dcnt = and i64 %dcnt0, 16383
  %1 = add nsw i64 %dcnt, -1
  %dok = icmp ult i64 %1, 8192
  br i1 %dok, label %pushD, label %drain

pushD:                                            ; preds = %fileD
  %dcls = lshr i64 %dcnt, 1
  %dslotp = getelementptr i64, ptr @__axiom_slabs, i64 %dcls
  %dohead = load i64, ptr %dslotp, align 8
  %dbase = add i64 %D.1.ph, -16
  %dbasep = inttoptr i64 %dbase to ptr
  store i64 %dohead, ptr %dbasep, align 8
  store i64 %dbase, ptr %dslotp, align 8
  br label %drain

drain:                                            ; preds = %pushD, %fileD, %after
  %dead.3 = phi i64 [ %dead.2.ph, %pushD ], [ %dead.2.ph, %fileD ], [ %dead.1, %after ]
  %empty = icmp eq i64 %dead.3, 0
  br i1 %empty, label %done, label %popD

popD:                                             ; preds = %drain
  %lp0 = add i64 %dead.3, -16
  %lpp = inttoptr i64 %lp0 to ptr
  %nxt = load i64, ptr %lpp, align 8
  %pq = add i64 %dead.3, -8
  %pqp = inttoptr i64 %pq to ptr
  %pshw = load i64, ptr %pqp, align 8
  %pmap = lshr i64 %pshw, 16
  %parr = and i64 %pshw, 32768
  %pisarr.not.not = icmp eq i64 %parr, 0
  %pcnt0 = lshr i64 %pshw, 1
  %pcnt = and i64 %pcnt0, 16383
  %pwm = select i1 %pisarr.not.not, i64 %pmap, i64 %pcnt
  %parr.lobit = lshr exact i64 %parr, 15
  br label %walk.peel

done:                                             ; preds = %drain
  ret void
}

; Function Attrs: nounwind
define internal i64 @__axiom_arena_mark_fn() #1 {
entry:
  %cell = tail call i64 @axiom_alloc(i64 24)
  %bump = load i64, ptr @__axiom_bump, align 8
  %end = load i64, ptr @__axiom_bump_end, align 8
  %chunk = load i64, ptr @__axiom_chunk, align 8
  %p0 = inttoptr i64 %cell to ptr
  store i64 %bump, ptr %p0, align 8
  %a1 = add i64 %cell, 8
  %p1 = inttoptr i64 %a1 to ptr
  store i64 %end, ptr %p1, align 8
  %a2 = add i64 %cell, 16
  %p2 = inttoptr i64 %a2 to ptr
  store i64 %chunk, ptr %p2, align 8
  ret i64 %cell
}

; Function Attrs: nofree norecurse nosync nounwind memory(readwrite, inaccessiblemem: none, target_mem0: none, target_mem1: none)
define internal noundef i64 @__axiom_arena_reset_fn(i64 %cell) #3 {
entry:
  br label %slabclear

slabclear:                                        ; preds = %slabclear, %entry
  %si = phi i64 [ 0, %entry ], [ %si1, %slabclear ]
  %sp = getelementptr i64, ptr @__axiom_slabs, i64 %si
  store i64 0, ptr %sp, align 8
  %si1 = add nuw nsw i64 %si, 1
  %sdone = icmp eq i64 %si1, 4097
  br i1 %sdone, label %resetbody, label %slabclear

resetbody:                                        ; preds = %slabclear
  %p0 = inttoptr i64 %cell to ptr
  %sbump = load i64, ptr %p0, align 8
  %a1 = add i64 %cell, 8
  %p1 = inttoptr i64 %a1 to ptr
  %send = load i64, ptr %p1, align 8
  %a2 = add i64 %cell, 16
  %p2 = inttoptr i64 %a2 to ptr
  %schunk = load i64, ptr %p2, align 8
  %chead = load i64, ptr @__axiom_chunk, align 8
  %same = icmp eq i64 %chead, %schunk
  br i1 %same, label %restore, label %unwind.preheader

unwind.preheader:                                 ; preds = %resetbody
  %ranout1 = icmp eq i64 %chead, 0
  br i1 %ranout1, label %tail, label %unwind_body

unwind_body:                                      ; preds = %unwind.preheader, %unwind_body
  %c2 = phi i64 [ %cnext, %unwind_body ], [ %chead, %unwind.preheader ]
  %clink = add i64 %c2, 8
  %clinkp = inttoptr i64 %clink to ptr
  %cnext = load i64, ptr %clinkp, align 8
  %fhead = load i64, ptr @__axiom_free, align 8
  store i64 %fhead, ptr %clinkp, align 8
  store i64 %c2, ptr @__axiom_free, align 8
  %reached = icmp eq i64 %cnext, %schunk
  %ranout = icmp eq i64 %cnext, 0
  %stop = or i1 %reached, %ranout
  br i1 %stop, label %tail, label %unwind_body

tail:                                             ; preds = %unwind_body, %unwind.preheader
  store i64 %send, ptr @__axiom_high, align 8
  br label %restore

restore:                                          ; preds = %tail, %resetbody
  store i64 %sbump, ptr @__axiom_bump, align 8
  store i64 %send, ptr @__axiom_bump_end, align 8
  store i64 %schunk, ptr @__axiom_chunk, align 8
  ret i64 0
}

; Function Attrs: nounwind
define internal i64 @__axiom_arena_reset_keeping_fn(i64 %cell, i64 %src, i64 %bytes) #1 {
entry:
  br label %slabclear.i

slabclear.i:                                      ; preds = %slabclear.i, %entry
  %si.i = phi i64 [ 0, %entry ], [ %si1.i, %slabclear.i ]
  %sp.i = getelementptr i64, ptr @__axiom_slabs, i64 %si.i
  store i64 0, ptr %sp.i, align 8
  %si1.i = add nuw nsw i64 %si.i, 1
  %sdone.i = icmp eq i64 %si1.i, 4097
  br i1 %sdone.i, label %resetbody.i, label %slabclear.i

resetbody.i:                                      ; preds = %slabclear.i
  %p0.i = inttoptr i64 %cell to ptr
  %sbump.i = load i64, ptr %p0.i, align 8
  %a1.i = add i64 %cell, 8
  %p1.i = inttoptr i64 %a1.i to ptr
  %send.i = load i64, ptr %p1.i, align 8
  %a2.i = add i64 %cell, 16
  %p2.i = inttoptr i64 %a2.i to ptr
  %schunk.i = load i64, ptr %p2.i, align 8
  %chead.i = load i64, ptr @__axiom_chunk, align 8
  %same.i = icmp eq i64 %chead.i, %schunk.i
  br i1 %same.i, label %__axiom_arena_reset_fn.exit, label %unwind.preheader.i

unwind.preheader.i:                               ; preds = %resetbody.i
  %ranout1.i = icmp eq i64 %chead.i, 0
  br i1 %ranout1.i, label %tail.i, label %unwind_body.i

unwind_body.i:                                    ; preds = %unwind.preheader.i, %unwind_body.i
  %c2.i = phi i64 [ %cnext.i, %unwind_body.i ], [ %chead.i, %unwind.preheader.i ]
  %clink.i = add i64 %c2.i, 8
  %clinkp.i = inttoptr i64 %clink.i to ptr
  %cnext.i = load i64, ptr %clinkp.i, align 8
  %fhead.i = load i64, ptr @__axiom_free, align 8
  store i64 %fhead.i, ptr %clinkp.i, align 8
  store i64 %c2.i, ptr @__axiom_free, align 8
  %reached.i = icmp eq i64 %cnext.i, %schunk.i
  %ranout.i = icmp eq i64 %cnext.i, 0
  %stop.i = or i1 %reached.i, %ranout.i
  br i1 %stop.i, label %tail.i, label %unwind_body.i

tail.i:                                           ; preds = %unwind_body.i, %unwind.preheader.i
  store i64 %send.i, ptr @__axiom_high, align 8
  br label %__axiom_arena_reset_fn.exit

__axiom_arena_reset_fn.exit:                      ; preds = %resetbody.i, %tail.i
  store i64 %sbump.i, ptr @__axiom_bump, align 8
  store i64 %send.i, ptr @__axiom_bump_end, align 8
  store i64 %schunk.i, ptr @__axiom_chunk, align 8
  %sz0 = add i64 %bytes, 15
  %szr = and i64 %sz0, -16
  %sz = add i64 %szr, 16
  %stop = add i64 %sbump.i, %sz
  %fits.not = icmp ugt i64 %stop, %send.i
  br i1 %fits.not, label %fresh, label %inplace

inplace:                                          ; preds = %__axiom_arena_reset_fn.exit
  store i64 %stop, ptr @__axiom_bump, align 8
  br label %copy

fresh:                                            ; preds = %__axiom_arena_reset_fn.exit
  %rounded0 = add i64 %szr, 65567
  %want = and i64 %rounded0, -65536
  %addr = tail call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 222, i64 0, i64 %want, i64 3, i64 34, i64 -1, i64 0) #15
  %0 = add i64 %addr, 4095
  %failed = icmp ult i64 %0, 8191
  br i1 %failed, label %oom, label %adopt

adopt:                                            ; preds = %fresh
  %basep = inttoptr i64 %addr to ptr
  store i64 %want, ptr %basep, align 8
  %baselink = add nuw i64 %addr, 8
  %baselinkp = inttoptr i64 %baselink to ptr
  %chead = load i64, ptr @__axiom_chunk, align 8
  store i64 %chead, ptr %baselinkp, align 8
  store i64 %addr, ptr @__axiom_chunk, align 8
  %fdata = add nuw i64 %addr, 16
  %fbump = add i64 %fdata, %sz
  store i64 %fbump, ptr @__axiom_bump, align 8
  %fend = add i64 %addr, %want
  store i64 %fend, ptr @__axiom_bump_end, align 8
  store i64 %fbump, ptr @__axiom_high, align 8
  br label %copy

copy:                                             ; preds = %adopt, %inplace
  %dstbase = phi i64 [ %sbump.i, %inplace ], [ %fdata, %adopt ]
  %dcp = inttoptr i64 %dstbase to ptr
  store i64 0, ptr %dcp, align 8
  %dsh = add i64 %dstbase, 8
  %dshp = inttoptr i64 %dsh to ptr
  %kcnt = lshr exact i64 %szr, 2
  %kbig = icmp ugt i64 %szr, 131064
  %kleaf = select i1 %kbig, i64 0, i64 %kcnt
  store i64 %kleaf, ptr %dshp, align 8
  %dst = add i64 %dstbase, 16
  %more1.not = icmp eq i64 %bytes, 0
  br i1 %more1.not, label %done, label %loop_body

loop_body:                                        ; preds = %copy, %loop_body
  %i3 = phi i64 [ %i2, %loop_body ], [ 0, %copy ]
  %sa = add i64 %i3, %src
  %sp = inttoptr i64 %sa to ptr
  %b = load i8, ptr %sp, align 1
  %da = add i64 %i3, %dst
  %dp = inttoptr i64 %da to ptr
  store i8 %b, ptr %dp, align 1
  %i2 = add nuw i64 %i3, 1
  %exitcond.not = icmp eq i64 %i2, %bytes
  br i1 %exitcond.not, label %done, label %loop_body

done:                                             ; preds = %loop_body, %copy
  ret i64 %dst

oom:                                              ; preds = %fresh
  %1 = tail call i64 @__axiom_out_of_memory()
  unreachable
}

; Function Attrs: noreturn nounwind
define internal noundef i64 @__axiom_div_by_zero() #4 {
entry:
  %0 = tail call i64 @__axiom_recover_abort(i64 72)
  %1 = tail call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 64, i64 2, i64 ptrtoint (ptr @__axiom_divzero_msg to i64), i64 24, i64 0, i64 0, i64 0) #15
  tail call fastcc void @__axiom_backtrace()
  %2 = tail call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 94, i64 72, i64 0, i64 0, i64 0, i64 0, i64 0) #15
  unreachable
}

; Function Attrs: noreturn nounwind
define internal noundef i64 @__axiom_out_of_memory() #4 {
entry:
  %0 = tail call i64 @__axiom_recover_abort(i64 70)
  %1 = tail call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 64, i64 2, i64 ptrtoint (ptr @__axiom_oom_msg to i64), i64 35, i64 0, i64 0, i64 0) #15
  tail call fastcc void @__axiom_backtrace()
  %2 = tail call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 94, i64 70, i64 0, i64 0, i64 0, i64 0, i64 0) #15
  unreachable
}

; Function Attrs: nounwind
define internal noundef i64 @__axiom_recover_abort(i64 %code) #1 {
entry:
  %top = load i64, ptr @__axiom_recover_top, align 8
  %armed.not = icmp eq i64 %top, 0
  br i1 %armed.not, label %none, label %jump

none:                                             ; preds = %entry
  ret i64 0

jump:                                             ; preds = %entry
  %recp = inttoptr i64 %top to ptr
  %sp = load i64, ptr %recp, align 8
  %a1 = add i64 %top, 8
  %p1 = inttoptr i64 %a1 to ptr
  %fp = load i64, ptr %p1, align 8
  %a2 = add i64 %top, 16
  %p2 = inttoptr i64 %a2 to ptr
  %pc = load i64, ptr %p2, align 8
  %a3 = add i64 %top, 24
  %p3 = inttoptr i64 %a3 to ptr
  %mark = load i64, ptr %p3, align 8
  %a5 = add i64 %top, 40
  %p5 = inttoptr i64 %a5 to ptr
  store i64 %code, ptr %p5, align 8
  %0 = tail call i64 @__axiom_arena_reset_fn(i64 %mark)
  tail call void asm sideeffect "mov x9, $0\0Amov sp, $1\0Amov x29, $2\0Abr $3", "r,r,r,r,~{x9},~{memory}"(i64 %top, i64 %sp, i64 %fp, i64 %pc) #15
  unreachable
}

; Function Attrs: nofree norecurse nosync nounwind memory(read, inaccessiblemem: none, target_mem0: none, target_mem1: none)
define internal range(i64 0, 2) i64 @__axiom_str_eq(i64 %a, i64 %b) #5 {
entry:
  %same = icmp eq i64 %a, %b
  br i1 %same, label %common.ret, label %chk

chk:                                              ; preds = %entry
  %anull = icmp eq i64 %a, 0
  %bnull = icmp eq i64 %b, 0
  %null = or i1 %anull, %bnull
  br i1 %null, label %common.ret, label %lens

lens:                                             ; preds = %chk
  %ap = inttoptr i64 %a to ptr
  %la = load i64, ptr %ap, align 8
  %bp = inttoptr i64 %b to ptr
  %lb = load i64, ptr %bp, align 8
  %lne.not = icmp eq i64 %la, %lb
  br i1 %lne.not, label %data, label %common.ret

data:                                             ; preds = %lens
  %aa = add i64 %a, 8
  %aap = inttoptr i64 %aa to ptr
  %da = load i64, ptr %aap, align 8
  %ba = add i64 %b, 8
  %bap = inttoptr i64 %ba to ptr
  %db = load i64, ptr %bap, align 8
  br label %loop

loop:                                             ; preds = %body, %data
  %i = phi i64 [ 0, %data ], [ %i2, %body ]
  %exitcond.not = icmp eq i64 %i, %la
  br i1 %exitcond.not, label %common.ret, label %body

body:                                             ; preds = %loop
  %sa = add i64 %i, %da
  %sap = inttoptr i64 %sa to ptr
  %ca = load i8, ptr %sap, align 1
  %sb = add i64 %i, %db
  %sbp = inttoptr i64 %sb to ptr
  %cb = load i8, ptr %sbp, align 1
  %cne.not = icmp eq i8 %ca, %cb
  %i2 = add i64 %i, 1
  br i1 %cne.not, label %loop, label %common.ret

common.ret:                                       ; preds = %body, %loop, %chk, %lens, %entry
  %common.ret.op = phi i64 [ 1, %entry ], [ 0, %lens ], [ 0, %chk ], [ 1, %loop ], [ 0, %body ]
  ret i64 %common.ret.op
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(none)
define noundef i64 @"Sys.Platform$sysRead"() #6 {
  ret i64 63
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(none)
define noundef i64 @"Sys.Platform$sysWrite"() #6 {
  ret i64 64
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(none)
define noundef i64 @"Sys.Platform$sysOpen"() #6 {
  ret i64 56
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(none)
define noundef i64 @"Sys.Platform$sysClose"() #6 {
  ret i64 57
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(none)
define noundef i64 @"Sys.Platform$sysExit"() #6 {
  ret i64 94
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(none)
define noundef i64 @"Sys.Platform$sysLseek"() #6 {
  ret i64 62
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(none)
define noundef i64 @"Sys.Platform$openNeedsDirFd"() #6 {
  ret i64 1
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(none)
define noundef i64 @"Sys.Platform$atFdCwd"() #6 {
  ret i64 -100
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(none)
define noundef i64 @"Sys.Platform$oRdonly"() #6 {
  ret i64 0
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(none)
define noundef i64 @"Sys.Platform$oWronlyCreateTrunc"() #6 {
  ret i64 577
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(none)
define noundef i64 @"Sys.Platform$oWronlyCreateAppend"() #6 {
  ret i64 1089
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(none)
define noundef i64 @"Sys.Platform$seekEnd"() #6 {
  ret i64 2
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(none)
define noundef i64 @"Sys.Platform$seekSet"() #6 {
  ret i64 0
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(none)
define noundef i64 @"Sys.Platform$spawnUsesPosixSpawn"() #6 {
  ret i64 0
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(none)
define noundef i64 @"Sys.Platform$sysFork"() #6 {
  ret i64 220
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(none)
define noundef i64 @"Sys.Platform$sysForkArg"() #6 {
  ret i64 17
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(none)
define noundef i64 @"Sys.Platform$sysExecve"() #6 {
  ret i64 221
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(none)
define noundef i64 @"Sys.Platform$sysWait4"() #6 {
  ret i64 260
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(none)
define noundef i64 @"Sys.Platform$sysPosixSpawn"() #6 {
  ret i64 0
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(none)
define noundef i64 @"Sys.Platform$sysUnlinkNum"() #6 {
  ret i64 35
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(none)
define noundef i64 @"Sys.Platform$sysMkdirNum"() #6 {
  ret i64 34
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(none)
define noundef i64 @"Sys.Platform$sysRmdirNum"() #6 {
  ret i64 35
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(none)
define noundef i64 @"Sys.Platform$sysRenameNum"() #6 {
  ret i64 38
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(none)
define noundef i64 @"Sys.Platform$sysGetdentsNum"() #6 {
  ret i64 61
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(none)
define noundef i64 @"Sys.Platform$dirReadNeedsPosition"() #6 {
  ret i64 0
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(none)
define noundef i64 @"Sys.Platform$direntNameOffset"() #6 {
  ret i64 19
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(none)
define noundef i64 @"Sys.Platform$cwdUsesFcntlPath"() #6 {
  ret i64 0
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(none)
define noundef i64 @"Sys.Platform$sysCwdNum"() #6 {
  ret i64 17
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(none)
define noundef i64 @"Sys.Platform$fGetPath"() #6 {
  ret i64 0
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(none)
define noundef i64 @"Sys.Platform$eExist"() #6 {
  ret i64 17
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(none)
define noundef i64 @"Sys.Platform$eIsDir"() #6 {
  ret i64 21
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(none)
define noundef i64 @"Sys.Platform$sysGetPidNum"() #6 {
  ret i64 172
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(none)
define noundef i64 @"Sys.Platform$sysClockNum"() #6 {
  ret i64 113
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(none)
define noundef i64 @"Sys.Platform$clockIsGettimeofday"() #6 {
  ret i64 0
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(none)
define noundef i64 @"Sys.Platform$clockHasMonotonic"() #6 {
  ret i64 1
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(none)
define noundef i64 @"Sys.Platform$sysSocketNum"() #6 {
  ret i64 198
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(none)
define noundef i64 @"Sys.Platform$sysBindNum"() #6 {
  ret i64 200
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(none)
define noundef i64 @"Sys.Platform$sysListenNum"() #6 {
  ret i64 201
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(none)
define noundef i64 @"Sys.Platform$sysAcceptNum"() #6 {
  ret i64 242
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(none)
define noundef i64 @"Sys.Platform$sysConnectNum"() #6 {
  ret i64 203
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(none)
define noundef i64 @"Sys.Platform$sysSetSockOptNum"() #6 {
  ret i64 208
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(none)
define noundef i64 @"Sys.Platform$sysGetSockOptNum"() #6 {
  ret i64 209
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(none)
define noundef i64 @"Sys.Platform$sysShutdownNum"() #6 {
  ret i64 210
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(none)
define noundef i64 @"Sys.Platform$sysFcntlNum"() #6 {
  ret i64 25
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(none)
define noundef i64 @"Sys.Platform$afInet"() #6 {
  ret i64 2
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(none)
define noundef i64 @"Sys.Platform$afInet6"() #6 {
  ret i64 10
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(none)
define noundef i64 @"Sys.Platform$sockStream"() #6 {
  ret i64 1
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(none)
define noundef i64 @"Sys.Platform$solSocket"() #6 {
  ret i64 1
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(none)
define noundef i64 @"Sys.Platform$soReuseAddr"() #6 {
  ret i64 2
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(none)
define noundef i64 @"Sys.Platform$soReusePort"() #6 {
  ret i64 15
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(none)
define noundef i64 @"Sys.Platform$soError"() #6 {
  ret i64 4
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(none)
define noundef i64 @"Sys.Platform$fGetFl"() #6 {
  ret i64 3
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(none)
define noundef i64 @"Sys.Platform$fSetFl"() #6 {
  ret i64 4
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(none)
define noundef i64 @"Sys.Platform$oNonblock"() #6 {
  ret i64 2048
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(none)
define noundef i64 @"Sys.Platform$eAgain"() #6 {
  ret i64 11
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(none)
define noundef i64 @"Sys.Platform$sockaddrHasLenByte"() #6 {
  ret i64 0
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(none)
define noundef i64 @"Sys.Platform$pollUsesKqueue"() #6 {
  ret i64 0
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(none)
define noundef i64 @"Sys.Platform$sysPollCreateNum"() #6 {
  ret i64 20
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(none)
define noundef i64 @"Sys.Platform$sysPollWaitNum"() #6 {
  ret i64 22
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(none)
define noundef i64 @"Sys.Platform$sysPollCtlNum"() #6 {
  ret i64 21
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(none)
define noundef i64 @"Sys.Platform$pollEventSize"() #6 {
  ret i64 16
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(none)
define noundef i64 @"Sys.Platform$pollEventFdOffset"() #6 {
  ret i64 8
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(none)
define noundef i64 @"Sys.Platform$pollReadFilter"() #6 {
  ret i64 1
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(none)
define noundef i64 @"Sys.Platform$pollAddOp"() #6 {
  ret i64 1
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(none)
define noundef i64 @"Sys.Platform$pollDelOp"() #6 {
  ret i64 2
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(none)
define noundef i64 @"Sys.Platform$pollSigsetSize"() #6 {
  ret i64 8
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(none)
define noundef i64 @"Sys.Platform$sysRandomNum"() #6 {
  ret i64 278
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(none)
define noundef i64 @"Sys.Platform$randomIsGetentropy"() #6 {
  ret i64 0
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(none)
define noundef i64 @"Sys.Platform$randomMaxChunk"() #6 {
  ret i64 256
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(none)
define noundef i64 @"Sys.Platform$signalUsesSignalFd"() #6 {
  ret i64 1
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(none)
define noundef i64 @"Sys.Platform$sysSigProcMaskNum"() #6 {
  ret i64 135
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(none)
define noundef i64 @"Sys.Platform$sigBlockHow"() #6 {
  ret i64 0
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(none)
define noundef i64 @"Sys.Platform$sigsetBytes"() #6 {
  ret i64 8
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(none)
define noundef i64 @"Sys.Platform$sysSignalFdNum"() #6 {
  ret i64 74
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(none)
define noundef i64 @"Sys.Platform$sigInfoSize"() #6 {
  ret i64 128
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(none)
define noundef i64 @"Sys.Platform$pollSignalFilter"() #6 {
  ret i64 0
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(none)
define noundef i64 @"Sys.Platform$sysKillNum"() #6 {
  ret i64 129
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(none)
define noundef i64 @"Sys.Platform$sigTerm"() #6 {
  ret i64 15
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(none)
define noundef i64 @"Sys.Platform$sigInt"() #6 {
  ret i64 2
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(none)
define noundef i64 @"Sys.Platform$forkChildIsZero"() #6 {
  ret i64 1
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(none)
define noundef i64 @"Sys.Platform$acceptNonblockFlag"() #6 {
  ret i64 2048
}

; Function Attrs: nounwind
define i64 @"Mem$memAlloc"(i64 %bytes) #1 {
  %t0 = tail call i64 @axiom_alloc(i64 %bytes)
  ret i64 %t0
}

; Function Attrs: nounwind
define i64 @"Mem$memAllocMapped"(i64 %bytes, i64 %map) #1 {
  %t0 = tail call i64 @axiom_alloc(i64 %bytes)
  %c1 = icmp eq i64 %bytes, 0
  br i1 %c1, label %label_6, label %label_5

label_5:                                          ; preds = %0
  %t7 = add i64 %t0, -8
  %t8 = inttoptr i64 %t7 to ptr
  %t10 = load i64, ptr %t8, align 8
  %t11 = lshr i64 %t10, 1
  %t12 = and i64 %t11, 16383
  %.t12 = tail call i64 @llvm.umin.i64(i64 %t12, i64 47)
  %notmask = shl nsw i64 -1, %.t12
  %t22 = xor i64 %notmask, -1
  %t23 = and i64 %map, %t22
  %t24 = shl nuw nsw i64 %t23, 16
  %t25 = or i64 %t24, %t10
  store i64 %t25, ptr %t8, align 8
  br label %label_6

label_6:                                          ; preds = %0, %label_5
  ret i64 %t0
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(readwrite, inaccessiblemem: none, target_mem0: none, target_mem1: none)
define i64 @"Mem$memMarkArray"(i64 returned %h) #2 {
  %t0 = add i64 %h, -8
  %t2 = inttoptr i64 %t0 to ptr
  %t4 = load i64, ptr %t2, align 8
  %t5 = or i64 %t4, 32768
  store i64 %t5, ptr %t2, align 8
  ret i64 %h
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(readwrite, inaccessiblemem: none, target_mem0: none, target_mem1: none)
define i64 @"Mem$memMarkLeaf"(i64 returned %h) #2 {
  %t0 = add i64 %h, -8
  %t2 = inttoptr i64 %t0 to ptr
  %t4 = load i64, ptr %t2, align 8
  %t7 = and i64 %t4, -32769
  store i64 %t7, ptr %t2, align 8
  ret i64 %h
}

; Function Attrs: nofree norecurse nosync nounwind memory(readwrite, inaccessiblemem: none, target_mem0: none, target_mem1: none)
define i64 @"Mem$memCopy"(i64 returned %dst, i64 %src, i64 %count) #3 {
  %c54.i = icmp sgt i64 %count, 0
  br i1 %c54.i, label %label_2.lr.ph.i, label %"Mem$memCopyFrom.exit"

label_2.lr.ph.i:                                  ; preds = %0
  %t10.i = inttoptr i64 %src to ptr
  %t14.i = inttoptr i64 %dst to ptr
  br label %label_2.i

label_2.i:                                        ; preds = %label_2.i, %label_2.lr.ph.i
  %s.0.05.i = phi i64 [ 0, %label_2.lr.ph.i ], [ %t18.i, %label_2.i ]
  %t11.i = getelementptr i8, ptr %t10.i, i64 %s.0.05.i
  %t12.i = load i8, ptr %t11.i, align 1
  %t15.i = getelementptr i8, ptr %t14.i, i64 %s.0.05.i
  store i8 %t12.i, ptr %t15.i, align 1
  %t18.i = add nuw nsw i64 %s.0.05.i, 1
  %exitcond.not.i = icmp eq i64 %t18.i, %count
  br i1 %exitcond.not.i, label %"Mem$memCopyFrom.exit", label %label_2.i

"Mem$memCopyFrom.exit":                           ; preds = %label_2.i, %0
  ret i64 %dst
}

; Function Attrs: nofree norecurse nosync nounwind memory(readwrite, inaccessiblemem: none, target_mem0: none, target_mem1: none)
define i64 @"Mem$memCopyFrom"(i64 returned %dst, i64 %src, i64 %count, i64 %start) #3 {
  %c54 = icmp slt i64 %start, %count
  br i1 %c54, label %label_2.lr.ph, label %label_3

label_2.lr.ph:                                    ; preds = %0
  %t10 = inttoptr i64 %src to ptr
  %t14 = inttoptr i64 %dst to ptr
  br label %label_2

label_2:                                          ; preds = %label_2.lr.ph, %label_2
  %s.0.05 = phi i64 [ %start, %label_2.lr.ph ], [ %t18, %label_2 ]
  %t11 = getelementptr i8, ptr %t10, i64 %s.0.05
  %t12 = load i8, ptr %t11, align 1
  %t15 = getelementptr i8, ptr %t14, i64 %s.0.05
  store i8 %t12, ptr %t15, align 1
  %t18 = add nsw i64 %s.0.05, 1
  %exitcond.not = icmp eq i64 %t18, %count
  br i1 %exitcond.not, label %label_3, label %label_2

label_3:                                          ; preds = %label_2, %0
  ret i64 %dst
}

; Function Attrs: nofree norecurse nosync nounwind memory(write, inaccessiblemem: none, target_mem0: none, target_mem1: none)
define i64 @"Mem$memSet"(i64 returned %addr, i64 %value, i64 %count) #7 {
  %c53.i = icmp sgt i64 %count, 0
  br i1 %c53.i, label %label_2.lr.ph.i, label %"Mem$memSetFrom.exit"

label_2.lr.ph.i:                                  ; preds = %0
  %t9.i = inttoptr i64 %addr to ptr
  %t11.i = trunc i64 %value to i8
  br label %label_2.i

label_2.i:                                        ; preds = %label_2.i, %label_2.lr.ph.i
  %s.0.04.i = phi i64 [ 0, %label_2.lr.ph.i ], [ %t13.i, %label_2.i ]
  %t10.i = getelementptr i8, ptr %t9.i, i64 %s.0.04.i
  store i8 %t11.i, ptr %t10.i, align 1
  %t13.i = add nuw nsw i64 %s.0.04.i, 1
  %exitcond.not.i = icmp eq i64 %t13.i, %count
  br i1 %exitcond.not.i, label %"Mem$memSetFrom.exit", label %label_2.i

"Mem$memSetFrom.exit":                            ; preds = %label_2.i, %0
  ret i64 %addr
}

; Function Attrs: nofree norecurse nosync nounwind memory(write, inaccessiblemem: none, target_mem0: none, target_mem1: none)
define i64 @"Mem$memSetFrom"(i64 returned %addr, i64 %value, i64 %count, i64 %start) #7 {
  %c53 = icmp slt i64 %start, %count
  br i1 %c53, label %label_2.lr.ph, label %label_3

label_2.lr.ph:                                    ; preds = %0
  %t9 = inttoptr i64 %addr to ptr
  %t11 = trunc i64 %value to i8
  br label %label_2

label_2:                                          ; preds = %label_2.lr.ph, %label_2
  %s.0.04 = phi i64 [ %start, %label_2.lr.ph ], [ %t13, %label_2 ]
  %t10 = getelementptr i8, ptr %t9, i64 %s.0.04
  store i8 %t11, ptr %t10, align 1
  %t13 = add nsw i64 %s.0.04, 1
  %exitcond.not = icmp eq i64 %t13, %count
  br i1 %exitcond.not, label %label_3, label %label_2

label_3:                                          ; preds = %label_2, %0
  ret i64 %addr
}

; Function Attrs: nofree norecurse nosync nounwind memory(read, inaccessiblemem: none, target_mem0: none, target_mem1: none)
define range(i64 -255, 256) i64 @"Mem$memCmp"(i64 %a, i64 %b, i64 %count) #5 {
  %c65.i = icmp sgt i64 %count, 0
  br i1 %c65.i, label %label_3.lr.ph.i, label %"Mem$memCmpFrom.exit"

label_3.lr.ph.i:                                  ; preds = %0
  %t20.i = inttoptr i64 %a to ptr
  %t25.i = inttoptr i64 %b to ptr
  br label %label_3.i

label_3.i:                                        ; preds = %label_3.i, %label_3.lr.ph.i
  %s.0.06.i = phi i64 [ 0, %label_3.lr.ph.i ], [ %t31.i, %label_3.i ]
  %t21.i = getelementptr i8, ptr %t20.i, i64 %s.0.06.i
  %t22.i = load i8, ptr %t21.i, align 1
  %t23.i = zext i8 %t22.i to i64
  %t26.i = getelementptr i8, ptr %t25.i, i64 %s.0.06.i
  %t27.i = load i8, ptr %t26.i, align 1
  %t28.i = zext i8 %t27.i to i64
  %t29.i = sub nsw i64 %t23.i, %t28.i
  %t31.i = add nuw nsw i64 %s.0.06.i, 1
  %c6.i = icmp slt i64 %t31.i, %count
  %c13.i = icmp eq i64 %t29.i, 0
  %narrow.i = select i1 %c6.i, i1 %c13.i, i1 false
  br i1 %narrow.i, label %label_3.i, label %"Mem$memCmpFrom.exit"

"Mem$memCmpFrom.exit":                            ; preds = %label_3.i, %0
  %s.1.0.lcssa.i = phi i64 [ 0, %0 ], [ %t29.i, %label_3.i ]
  ret i64 %s.1.0.lcssa.i
}

; Function Attrs: nofree norecurse nosync nounwind memory(read, inaccessiblemem: none, target_mem0: none, target_mem1: none)
define range(i64 -255, 256) i64 @"Mem$memCmpFrom"(i64 %a, i64 %b, i64 %count, i64 %start) #5 {
  %c65 = icmp slt i64 %start, %count
  br i1 %c65, label %label_3.lr.ph, label %label_4

label_3.lr.ph:                                    ; preds = %0
  %t20 = inttoptr i64 %a to ptr
  %t25 = inttoptr i64 %b to ptr
  br label %label_3

label_3:                                          ; preds = %label_3.lr.ph, %label_3
  %s.0.06 = phi i64 [ %start, %label_3.lr.ph ], [ %t31, %label_3 ]
  %t21 = getelementptr i8, ptr %t20, i64 %s.0.06
  %t22 = load i8, ptr %t21, align 1
  %t23 = zext i8 %t22 to i64
  %t26 = getelementptr i8, ptr %t25, i64 %s.0.06
  %t27 = load i8, ptr %t26, align 1
  %t28 = zext i8 %t27 to i64
  %t29 = sub nsw i64 %t23, %t28
  %t31 = add nsw i64 %s.0.06, 1
  %c6 = icmp slt i64 %t31, %count
  %c13 = icmp eq i64 %t29, 0
  %narrow = select i1 %c6, i1 %c13, i1 false
  br i1 %narrow, label %label_3, label %label_4

label_4:                                          ; preds = %label_3, %0
  %s.1.0.lcssa = phi i64 [ 0, %0 ], [ %t29, %label_3 ]
  ret i64 %s.1.0.lcssa
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(read, inaccessiblemem: none, target_mem0: none, target_mem1: none)
define i64 @"Mem$memGetWord"(i64 %addr, i64 %index) #8 {
  %t0 = inttoptr i64 %addr to ptr
  %t1 = getelementptr i64, ptr %t0, i64 %index
  %t2 = load i64, ptr %t1, align 8
  ret i64 %t2
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(readwrite, inaccessiblemem: none, target_mem0: none, target_mem1: none)
define i64 @"Mem$memGetWordStr"(i64 %addr, i64 %index) #2 {
  %t0.i = inttoptr i64 %addr to ptr
  %t1.i = getelementptr i64, ptr %t0.i, i64 %index
  %t2.i = load i64, ptr %t1.i, align 8
  %imm.i = icmp slt i64 %t2.i, 4096
  br i1 %imm.i, label %axiom_retain.exit, label %chk.i

chk.i:                                            ; preds = %0
  %hoff.i = add nsw i64 %t2.i, -16
  %cp.i = inttoptr i64 %hoff.i to ptr
  %c.i = load i64, ptr %cp.i, align 8
  %stat.i = icmp eq i64 %c.i, -1
  br i1 %stat.i, label %axiom_retain.exit, label %bump.i

bump.i:                                           ; preds = %chk.i
  %c1.i = add nuw i64 %c.i, 1
  store i64 %c1.i, ptr %cp.i, align 8
  br label %axiom_retain.exit

axiom_retain.exit:                                ; preds = %0, %chk.i, %bump.i
  ret i64 %t2.i
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(readwrite, inaccessiblemem: none, target_mem0: none, target_mem1: none)
define i64 @"Mem$memSetWord"(i64 returned %addr, i64 %index, i64 %value, i64 %__evw.h) #2 {
  %t1 = and i64 %__evw.h, 1
  %t2.not = icmp eq i64 %t1, 0
  %imm.i = icmp slt i64 %value, 4096
  %or.cond = select i1 %t2.not, i1 true, i1 %imm.i
  br i1 %or.cond, label %label_4, label %chk.i

chk.i:                                            ; preds = %0
  %hoff.i = add nsw i64 %value, -16
  %cp.i = inttoptr i64 %hoff.i to ptr
  %c.i = load i64, ptr %cp.i, align 8
  %stat.i = icmp eq i64 %c.i, -1
  br i1 %stat.i, label %label_4, label %bump.i

bump.i:                                           ; preds = %chk.i
  %c1.i = add nuw i64 %c.i, 1
  store i64 %c1.i, ptr %cp.i, align 8
  br label %label_4

label_4:                                          ; preds = %bump.i, %chk.i, %0
  %t5 = inttoptr i64 %addr to ptr
  %t6 = getelementptr i64, ptr %t5, i64 %index
  store i64 %value, ptr %t6, align 8
  ret i64 %addr
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(read, inaccessiblemem: none, target_mem0: none, target_mem1: none)
define range(i64 0, 256) i64 @"Mem$memGetByte"(i64 %addr, i64 %index) #8 {
  %t0 = inttoptr i64 %addr to ptr
  %t1 = getelementptr i8, ptr %t0, i64 %index
  %t2 = load i8, ptr %t1, align 1
  %t3 = zext i8 %t2 to i64
  ret i64 %t3
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(write, inaccessiblemem: none, target_mem0: none, target_mem1: none)
define i64 @"Mem$memPutByte"(i64 returned %addr, i64 %index, i64 %value) #9 {
  %t0 = inttoptr i64 %addr to ptr
  %t1 = getelementptr i8, ptr %t0, i64 %index
  %t2 = trunc i64 %value to i8
  store i8 %t2, ptr %t1, align 1
  ret i64 %addr
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(none)
define noundef i64 @"Vec$vecDefaultCap"() #6 {
  ret i64 8
}

; Function Attrs: nounwind
define i64 @"Vec$vecNew"() #1 {
  %t0.i.i.i = tail call i64 @axiom_alloc(i64 32)
  %t7.i.i.i = add i64 %t0.i.i.i, -8
  %t8.i.i.i = inttoptr i64 %t7.i.i.i to ptr
  %t10.i.i.i = load i64, ptr %t8.i.i.i, align 8
  %t11.i.i.i = lshr i64 %t10.i.i.i, 1
  %t12.i.i.i = and i64 %t11.i.i.i, 16383
  %.t12.i.i.i = tail call i64 @llvm.umin.i64(i64 %t12.i.i.i, i64 47)
  %t22.i.i.i = shl nsw i64 -65536, %.t12.i.i.i
  %t23.i.i.i = and i64 %t22.i.i.i, 262144
  %t24.i.i.i = xor i64 %t23.i.i.i, 262144
  %t25.i.i.i = or i64 %t24.i.i.i, %t10.i.i.i
  store i64 %t25.i.i.i, ptr %t8.i.i.i, align 8
  %t0.i1.i.i = tail call i64 @axiom_alloc(i64 64)
  %imm.i.i.i = icmp slt i64 %t0.i.i.i, 4096
  br i1 %imm.i.i.i, label %axiom_retain.exit.i.i, label %chk.i.i.i

chk.i.i.i:                                        ; preds = %0
  %hoff.i.i.i = add nsw i64 %t0.i.i.i, -16
  %cp.i.i.i = inttoptr i64 %hoff.i.i.i to ptr
  %c.i.i.i = load i64, ptr %cp.i.i.i, align 8
  %stat.i.i.i = icmp eq i64 %c.i.i.i, -1
  br i1 %stat.i.i.i, label %axiom_retain.exit.i.i, label %bump.i.i.i

bump.i.i.i:                                       ; preds = %chk.i.i.i
  %c1.i.i.i = add nuw i64 %c.i.i.i, 1
  store i64 %c1.i.i.i, ptr %cp.i.i.i, align 8
  br label %axiom_retain.exit.i.i

axiom_retain.exit.i.i:                            ; preds = %bump.i.i.i, %chk.i.i.i, %0
  %imm.i2.i.i = icmp slt i64 %t0.i1.i.i, 4096
  br i1 %imm.i2.i.i, label %"Vec$vecWithCapacity.exit", label %chk.i3.i.i

chk.i3.i.i:                                       ; preds = %axiom_retain.exit.i.i
  %hoff.i4.i.i = add nsw i64 %t0.i1.i.i, -16
  %cp.i5.i.i = inttoptr i64 %hoff.i4.i.i to ptr
  %c.i6.i.i = load i64, ptr %cp.i5.i.i, align 8
  %stat.i7.i.i = icmp eq i64 %c.i6.i.i, -1
  br i1 %stat.i7.i.i, label %"Vec$vecWithCapacity.exit", label %bump.i8.i.i

bump.i8.i.i:                                      ; preds = %chk.i3.i.i
  %c1.i9.i.i = add nuw i64 %c.i6.i.i, 1
  store i64 %c1.i9.i.i, ptr %cp.i5.i.i, align 8
  br label %"Vec$vecWithCapacity.exit"

"Vec$vecWithCapacity.exit":                       ; preds = %axiom_retain.exit.i.i, %chk.i3.i.i, %bump.i8.i.i
  %t5.i12.i.i = inttoptr i64 %t0.i.i.i to ptr
  store i64 0, ptr %t5.i12.i.i, align 8
  %t6.i.i.i = getelementptr i8, ptr %t5.i12.i.i, i64 8
  store i64 8, ptr %t6.i.i.i, align 8
  %t6.i16.i.i = getelementptr i8, ptr %t5.i12.i.i, i64 16
  store i64 %t0.i1.i.i, ptr %t6.i16.i.i, align 8
  %t6.i19.i.i = getelementptr i8, ptr %t5.i12.i.i, i64 24
  store i64 0, ptr %t6.i19.i.i, align 8
  ret i64 %t0.i.i.i
}

; Function Attrs: nounwind
define i64 @"Vec$vecWithCapacity"(i64 %cap) #1 {
  %.cap.i = tail call i64 @llvm.smax.i64(i64 %cap, i64 1)
  %t0.i.i = tail call i64 @axiom_alloc(i64 32)
  %t7.i.i = add i64 %t0.i.i, -8
  %t8.i.i = inttoptr i64 %t7.i.i to ptr
  %t10.i.i = load i64, ptr %t8.i.i, align 8
  %t11.i.i = lshr i64 %t10.i.i, 1
  %t12.i.i = and i64 %t11.i.i, 16383
  %.t12.i.i = tail call i64 @llvm.umin.i64(i64 %t12.i.i, i64 47)
  %t22.i.i = shl nsw i64 -65536, %.t12.i.i
  %t23.i.i = and i64 %t22.i.i, 262144
  %t24.i.i = xor i64 %t23.i.i, 262144
  %t25.i.i = or i64 %t24.i.i, %t10.i.i
  store i64 %t25.i.i, ptr %t8.i.i, align 8
  %t8.i = shl i64 %.cap.i, 3
  %t0.i1.i = tail call i64 @axiom_alloc(i64 %t8.i)
  %imm.i.i = icmp slt i64 %t0.i.i, 4096
  br i1 %imm.i.i, label %axiom_retain.exit.i, label %chk.i.i

chk.i.i:                                          ; preds = %0
  %hoff.i.i = add nsw i64 %t0.i.i, -16
  %cp.i.i = inttoptr i64 %hoff.i.i to ptr
  %c.i.i = load i64, ptr %cp.i.i, align 8
  %stat.i.i = icmp eq i64 %c.i.i, -1
  br i1 %stat.i.i, label %axiom_retain.exit.i, label %bump.i.i

bump.i.i:                                         ; preds = %chk.i.i
  %c1.i.i = add nuw i64 %c.i.i, 1
  store i64 %c1.i.i, ptr %cp.i.i, align 8
  br label %axiom_retain.exit.i

axiom_retain.exit.i:                              ; preds = %bump.i.i, %chk.i.i, %0
  %imm.i2.i = icmp slt i64 %t0.i1.i, 4096
  br i1 %imm.i2.i, label %"Vec$vecBuild.exit", label %chk.i3.i

chk.i3.i:                                         ; preds = %axiom_retain.exit.i
  %hoff.i4.i = add nsw i64 %t0.i1.i, -16
  %cp.i5.i = inttoptr i64 %hoff.i4.i to ptr
  %c.i6.i = load i64, ptr %cp.i5.i, align 8
  %stat.i7.i = icmp eq i64 %c.i6.i, -1
  br i1 %stat.i7.i, label %"Vec$vecBuild.exit", label %bump.i8.i

bump.i8.i:                                        ; preds = %chk.i3.i
  %c1.i9.i = add nuw i64 %c.i6.i, 1
  store i64 %c1.i9.i, ptr %cp.i5.i, align 8
  br label %"Vec$vecBuild.exit"

"Vec$vecBuild.exit":                              ; preds = %axiom_retain.exit.i, %chk.i3.i, %bump.i8.i
  %t5.i12.i = inttoptr i64 %t0.i.i to ptr
  store i64 0, ptr %t5.i12.i, align 8
  %t6.i.i = getelementptr i8, ptr %t5.i12.i, i64 8
  store i64 %.cap.i, ptr %t6.i.i, align 8
  %t6.i16.i = getelementptr i8, ptr %t5.i12.i, i64 16
  store i64 %t0.i1.i, ptr %t6.i16.i, align 8
  %t6.i19.i = getelementptr i8, ptr %t5.i12.i, i64 24
  store i64 0, ptr %t6.i19.i, align 8
  ret i64 %t0.i.i
}

; Function Attrs: nounwind
define i64 @"Vec$vecWithCapacityRef"(i64 %cap) #1 {
  %.cap.i = tail call i64 @llvm.smax.i64(i64 %cap, i64 1)
  %t0.i.i = tail call i64 @axiom_alloc(i64 32)
  %t7.i.i = add i64 %t0.i.i, -8
  %t8.i.i = inttoptr i64 %t7.i.i to ptr
  %t10.i.i = load i64, ptr %t8.i.i, align 8
  %t11.i.i = lshr i64 %t10.i.i, 1
  %t12.i.i = and i64 %t11.i.i, 16383
  %.t12.i.i = tail call i64 @llvm.umin.i64(i64 %t12.i.i, i64 47)
  %t22.i.i = shl nsw i64 -65536, %.t12.i.i
  %t23.i.i = and i64 %t22.i.i, 262144
  %t24.i.i = xor i64 %t23.i.i, 262144
  %t25.i.i = or i64 %t24.i.i, %t10.i.i
  store i64 %t25.i.i, ptr %t8.i.i, align 8
  %t8.i = shl i64 %.cap.i, 3
  %t0.i1.i = tail call i64 @axiom_alloc(i64 %t8.i)
  %imm.i.i = icmp slt i64 %t0.i.i, 4096
  br i1 %imm.i.i, label %axiom_retain.exit.i, label %chk.i.i

chk.i.i:                                          ; preds = %0
  %hoff.i.i = add nsw i64 %t0.i.i, -16
  %cp.i.i = inttoptr i64 %hoff.i.i to ptr
  %c.i.i = load i64, ptr %cp.i.i, align 8
  %stat.i.i = icmp eq i64 %c.i.i, -1
  br i1 %stat.i.i, label %axiom_retain.exit.i, label %bump.i.i

bump.i.i:                                         ; preds = %chk.i.i
  %c1.i.i = add nuw i64 %c.i.i, 1
  store i64 %c1.i.i, ptr %cp.i.i, align 8
  br label %axiom_retain.exit.i

axiom_retain.exit.i:                              ; preds = %bump.i.i, %chk.i.i, %0
  %imm.i2.i = icmp slt i64 %t0.i1.i, 4096
  br i1 %imm.i2.i, label %"Vec$vecBuild.exit", label %chk.i3.i

chk.i3.i:                                         ; preds = %axiom_retain.exit.i
  %hoff.i4.i = add nsw i64 %t0.i1.i, -16
  %cp.i5.i = inttoptr i64 %hoff.i4.i to ptr
  %c.i6.i = load i64, ptr %cp.i5.i, align 8
  %stat.i7.i = icmp eq i64 %c.i6.i, -1
  br i1 %stat.i7.i, label %"Vec$vecBuild.exit", label %bump.i8.i

bump.i8.i:                                        ; preds = %chk.i3.i
  %c1.i9.i = add nuw i64 %c.i6.i, 1
  store i64 %c1.i9.i, ptr %cp.i5.i, align 8
  br label %"Vec$vecBuild.exit"

"Vec$vecBuild.exit":                              ; preds = %axiom_retain.exit.i, %chk.i3.i, %bump.i8.i
  %t0.i11.i = add i64 %t0.i1.i, -8
  %t2.i.i = inttoptr i64 %t0.i11.i to ptr
  %t4.i.i = load i64, ptr %t2.i.i, align 8
  %t5.i.i = or i64 %t4.i.i, 32768
  store i64 %t5.i.i, ptr %t2.i.i, align 8
  %t5.i12.i = inttoptr i64 %t0.i.i to ptr
  store i64 0, ptr %t5.i12.i, align 8
  %t6.i.i = getelementptr i8, ptr %t5.i12.i, i64 8
  store i64 %.cap.i, ptr %t6.i.i, align 8
  %t6.i16.i = getelementptr i8, ptr %t5.i12.i, i64 16
  store i64 %t0.i1.i, ptr %t6.i16.i, align 8
  %t6.i19.i = getelementptr i8, ptr %t5.i12.i, i64 24
  store i64 1, ptr %t6.i19.i, align 8
  ret i64 %t0.i.i
}

; Function Attrs: nounwind
define i64 @"Vec$vecNewRef"() #1 {
  %t0.i.i.i = tail call i64 @axiom_alloc(i64 32)
  %t7.i.i.i = add i64 %t0.i.i.i, -8
  %t8.i.i.i = inttoptr i64 %t7.i.i.i to ptr
  %t10.i.i.i = load i64, ptr %t8.i.i.i, align 8
  %t11.i.i.i = lshr i64 %t10.i.i.i, 1
  %t12.i.i.i = and i64 %t11.i.i.i, 16383
  %.t12.i.i.i = tail call i64 @llvm.umin.i64(i64 %t12.i.i.i, i64 47)
  %t22.i.i.i = shl nsw i64 -65536, %.t12.i.i.i
  %t23.i.i.i = and i64 %t22.i.i.i, 262144
  %t24.i.i.i = xor i64 %t23.i.i.i, 262144
  %t25.i.i.i = or i64 %t24.i.i.i, %t10.i.i.i
  store i64 %t25.i.i.i, ptr %t8.i.i.i, align 8
  %t0.i1.i.i = tail call i64 @axiom_alloc(i64 64)
  %imm.i.i.i = icmp slt i64 %t0.i.i.i, 4096
  br i1 %imm.i.i.i, label %axiom_retain.exit.i.i, label %chk.i.i.i

chk.i.i.i:                                        ; preds = %0
  %hoff.i.i.i = add nsw i64 %t0.i.i.i, -16
  %cp.i.i.i = inttoptr i64 %hoff.i.i.i to ptr
  %c.i.i.i = load i64, ptr %cp.i.i.i, align 8
  %stat.i.i.i = icmp eq i64 %c.i.i.i, -1
  br i1 %stat.i.i.i, label %axiom_retain.exit.i.i, label %bump.i.i.i

bump.i.i.i:                                       ; preds = %chk.i.i.i
  %c1.i.i.i = add nuw i64 %c.i.i.i, 1
  store i64 %c1.i.i.i, ptr %cp.i.i.i, align 8
  br label %axiom_retain.exit.i.i

axiom_retain.exit.i.i:                            ; preds = %bump.i.i.i, %chk.i.i.i, %0
  %imm.i2.i.i = icmp slt i64 %t0.i1.i.i, 4096
  br i1 %imm.i2.i.i, label %"Vec$vecWithCapacityRef.exit", label %chk.i3.i.i

chk.i3.i.i:                                       ; preds = %axiom_retain.exit.i.i
  %hoff.i4.i.i = add nsw i64 %t0.i1.i.i, -16
  %cp.i5.i.i = inttoptr i64 %hoff.i4.i.i to ptr
  %c.i6.i.i = load i64, ptr %cp.i5.i.i, align 8
  %stat.i7.i.i = icmp eq i64 %c.i6.i.i, -1
  br i1 %stat.i7.i.i, label %"Vec$vecWithCapacityRef.exit", label %bump.i8.i.i

bump.i8.i.i:                                      ; preds = %chk.i3.i.i
  %c1.i9.i.i = add nuw i64 %c.i6.i.i, 1
  store i64 %c1.i9.i.i, ptr %cp.i5.i.i, align 8
  br label %"Vec$vecWithCapacityRef.exit"

"Vec$vecWithCapacityRef.exit":                    ; preds = %axiom_retain.exit.i.i, %chk.i3.i.i, %bump.i8.i.i
  %t0.i11.i.i = add i64 %t0.i1.i.i, -8
  %t2.i.i.i = inttoptr i64 %t0.i11.i.i to ptr
  %t4.i.i.i = load i64, ptr %t2.i.i.i, align 8
  %t5.i.i.i = or i64 %t4.i.i.i, 32768
  store i64 %t5.i.i.i, ptr %t2.i.i.i, align 8
  %t5.i12.i.i = inttoptr i64 %t0.i.i.i to ptr
  store i64 0, ptr %t5.i12.i.i, align 8
  %t6.i.i.i = getelementptr i8, ptr %t5.i12.i.i, i64 8
  store i64 8, ptr %t6.i.i.i, align 8
  %t6.i16.i.i = getelementptr i8, ptr %t5.i12.i.i, i64 16
  store i64 %t0.i1.i.i, ptr %t6.i16.i.i, align 8
  %t6.i19.i.i = getelementptr i8, ptr %t5.i12.i.i, i64 24
  store i64 1, ptr %t6.i19.i.i, align 8
  ret i64 %t0.i.i.i
}

; Function Attrs: nounwind
define i64 @"Vec$vecBuild"(i64 %cap, i64 %refs) #1 {
label_5:
  %.cap = tail call i64 @llvm.smax.i64(i64 %cap, i64 1)
  %t0.i = tail call i64 @axiom_alloc(i64 32)
  %t7.i = add i64 %t0.i, -8
  %t8.i = inttoptr i64 %t7.i to ptr
  %t10.i = load i64, ptr %t8.i, align 8
  %t11.i = lshr i64 %t10.i, 1
  %t12.i = and i64 %t11.i, 16383
  %.t12.i = tail call i64 @llvm.umin.i64(i64 %t12.i, i64 47)
  %t22.i = shl nsw i64 -65536, %.t12.i
  %t23.i = and i64 %t22.i, 262144
  %t24.i = xor i64 %t23.i, 262144
  %t25.i = or i64 %t24.i, %t10.i
  store i64 %t25.i, ptr %t8.i, align 8
  %t8 = shl i64 %.cap, 3
  %t0.i1 = tail call i64 @axiom_alloc(i64 %t8)
  %imm.i = icmp slt i64 %t0.i, 4096
  br i1 %imm.i, label %axiom_retain.exit, label %chk.i

chk.i:                                            ; preds = %label_5
  %hoff.i = add nsw i64 %t0.i, -16
  %cp.i = inttoptr i64 %hoff.i to ptr
  %c.i = load i64, ptr %cp.i, align 8
  %stat.i = icmp eq i64 %c.i, -1
  br i1 %stat.i, label %axiom_retain.exit, label %bump.i

bump.i:                                           ; preds = %chk.i
  %c1.i = add nuw i64 %c.i, 1
  store i64 %c1.i, ptr %cp.i, align 8
  br label %axiom_retain.exit

axiom_retain.exit:                                ; preds = %label_5, %chk.i, %bump.i
  %imm.i2 = icmp slt i64 %t0.i1, 4096
  br i1 %imm.i2, label %axiom_retain.exit10, label %chk.i3

chk.i3:                                           ; preds = %axiom_retain.exit
  %hoff.i4 = add nsw i64 %t0.i1, -16
  %cp.i5 = inttoptr i64 %hoff.i4 to ptr
  %c.i6 = load i64, ptr %cp.i5, align 8
  %stat.i7 = icmp eq i64 %c.i6, -1
  br i1 %stat.i7, label %axiom_retain.exit10, label %bump.i8

bump.i8:                                          ; preds = %chk.i3
  %c1.i9 = add nuw i64 %c.i6, 1
  store i64 %c1.i9, ptr %cp.i5, align 8
  br label %axiom_retain.exit10

axiom_retain.exit10:                              ; preds = %axiom_retain.exit, %chk.i3, %bump.i8
  %c10 = icmp eq i64 %refs, 1
  br i1 %c10, label %label_13, label %label_15

label_13:                                         ; preds = %axiom_retain.exit10
  %t0.i11 = add i64 %t0.i1, -8
  %t2.i = inttoptr i64 %t0.i11 to ptr
  %t4.i = load i64, ptr %t2.i, align 8
  %t5.i = or i64 %t4.i, 32768
  store i64 %t5.i, ptr %t2.i, align 8
  br label %label_15

label_15:                                         ; preds = %axiom_retain.exit10, %label_13
  %t5.i12 = inttoptr i64 %t0.i to ptr
  store i64 0, ptr %t5.i12, align 8
  %t6.i = getelementptr i8, ptr %t5.i12, i64 8
  store i64 %.cap, ptr %t6.i, align 8
  %t6.i16 = getelementptr i8, ptr %t5.i12, i64 16
  store i64 %t0.i1, ptr %t6.i16, align 8
  %t6.i19 = getelementptr i8, ptr %t5.i12, i64 24
  store i64 %refs, ptr %t6.i19, align 8
  ret i64 %t0.i
}

define noundef i64 @"Vec$vecFree"(i64 %v) #0 {
  tail call void @axiom_release(i64 %v)
  ret i64 0
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(read, inaccessiblemem: none, target_mem0: none, target_mem1: none)
define range(i64 0, 2) i64 @"Vec$vecOwnsRefs"(i64 %v) #8 {
  %t0.i = inttoptr i64 %v to ptr
  %t1.i = getelementptr i8, ptr %t0.i, i64 24
  %t2.i = load i64, ptr %t1.i, align 8
  %c1 = icmp eq i64 %t2.i, 1
  %t2 = zext i1 %c1 to i64
  ret i64 %t2
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(read, inaccessiblemem: none, target_mem0: none, target_mem1: none)
define i64 @"Vec$vecLen"(i64 %v) #8 {
  %t0.i = inttoptr i64 %v to ptr
  %t2.i = load i64, ptr %t0.i, align 8
  ret i64 %t2.i
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(read, inaccessiblemem: none, target_mem0: none, target_mem1: none)
define i64 @"Vec$vecCap"(i64 %v) #8 {
  %t0.i = inttoptr i64 %v to ptr
  %t1.i = getelementptr i8, ptr %t0.i, i64 8
  %t2.i = load i64, ptr %t1.i, align 8
  ret i64 %t2.i
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(read, inaccessiblemem: none, target_mem0: none, target_mem1: none)
define i64 @"Vec$vecData"(i64 %v) #8 {
  %t0.i = inttoptr i64 %v to ptr
  %t1.i = getelementptr i8, ptr %t0.i, i64 16
  %t2.i = load i64, ptr %t1.i, align 8
  ret i64 %t2.i
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(read, inaccessiblemem: none, target_mem0: none, target_mem1: none)
define i64 @"Vec$vecGet"(i64 %v, i64 %i) #8 {
  %c0 = icmp slt i64 %i, 0
  br i1 %c0, label %label_5, label %label_4

label_4:                                          ; preds = %0
  %t0.i.i = inttoptr i64 %v to ptr
  %t2.i.i = load i64, ptr %t0.i.i, align 8
  %c7.not = icmp slt i64 %i, %t2.i.i
  br i1 %c7.not, label %label_11, label %label_5

label_11:                                         ; preds = %label_4
  %t1.i.i = getelementptr i8, ptr %t0.i.i, i64 16
  %t2.i.i2 = load i64, ptr %t1.i.i, align 8
  %t0.i = inttoptr i64 %t2.i.i2 to ptr
  %t1.i = getelementptr i64, ptr %t0.i, i64 %i
  %t2.i = load i64, ptr %t1.i, align 8
  br label %label_5

label_5:                                          ; preds = %label_11, %label_4, %0
  %t16 = phi i64 [ 0, %0 ], [ %t2.i, %label_11 ], [ 0, %label_4 ]
  ret i64 %t16
}

; Function Attrs: nounwind
define i64 @"Vec$vecTry"(i64 %v, i64 %i) #1 {
  %c0 = icmp slt i64 %i, 0
  br i1 %c0, label %label_5, label %label_4

label_4:                                          ; preds = %0
  %t0.i.i = inttoptr i64 %v to ptr
  %t2.i.i = load i64, ptr %t0.i.i, align 8
  %c7.not = icmp slt i64 %i, %t2.i.i
  br i1 %c7.not, label %label_11, label %label_5

label_11:                                         ; preds = %label_4
  %t13 = tail call i64 @axiom_alloc(i64 16)
  %t14 = add i64 %t13, -8
  %t15 = inttoptr i64 %t14 to ptr
  store i64 4, ptr %t15, align 8
  %t16 = inttoptr i64 %t13 to ptr
  store i64 0, ptr %t16, align 8
  %t18 = add i64 %t13, -16
  %t19 = inttoptr i64 %t18 to ptr
  store i64 1, ptr %t19, align 8
  %t1.i.i = getelementptr i8, ptr %t0.i.i, i64 16
  %t2.i.i2 = load i64, ptr %t1.i.i, align 8
  %t0.i = inttoptr i64 %t2.i.i2 to ptr
  %t1.i = getelementptr i64, ptr %t0.i, i64 %i
  %t2.i = load i64, ptr %t1.i, align 8
  %t23 = getelementptr i8, ptr %t16, i64 8
  store i64 %t2.i, ptr %t23, align 8
  br label %label_5

label_5:                                          ; preds = %label_11, %label_4, %0
  %t25 = phi i64 [ 1, %0 ], [ %t13, %label_11 ], [ 1, %label_4 ]
  ret i64 %t25
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(readwrite, inaccessiblemem: none, target_mem0: none, target_mem1: none)
define i64 @"Vec$vecGetStr"(i64 %v, i64 %i) #2 {
  %c0.i = icmp slt i64 %i, 0
  br i1 %c0.i, label %"Vec$vecGet.exit", label %label_4.i

label_4.i:                                        ; preds = %0
  %t0.i.i.i = inttoptr i64 %v to ptr
  %t2.i.i.i = load i64, ptr %t0.i.i.i, align 8
  %c7.not.i = icmp slt i64 %i, %t2.i.i.i
  br i1 %c7.not.i, label %label_11.i, label %"Vec$vecGet.exit"

label_11.i:                                       ; preds = %label_4.i
  %t1.i.i.i = getelementptr i8, ptr %t0.i.i.i, i64 16
  %t2.i.i2.i = load i64, ptr %t1.i.i.i, align 8
  %t0.i.i = inttoptr i64 %t2.i.i2.i to ptr
  %t1.i.i = getelementptr i64, ptr %t0.i.i, i64 %i
  %t2.i.i = load i64, ptr %t1.i.i, align 8
  br label %"Vec$vecGet.exit"

"Vec$vecGet.exit":                                ; preds = %0, %label_4.i, %label_11.i
  %t16.i = phi i64 [ 0, %0 ], [ %t2.i.i, %label_11.i ], [ 0, %label_4.i ]
  %imm.i = icmp slt i64 %t16.i, 4096
  br i1 %imm.i, label %axiom_retain.exit, label %chk.i

chk.i:                                            ; preds = %"Vec$vecGet.exit"
  %hoff.i = add nsw i64 %t16.i, -16
  %cp.i = inttoptr i64 %hoff.i to ptr
  %c.i = load i64, ptr %cp.i, align 8
  %stat.i = icmp eq i64 %c.i, -1
  br i1 %stat.i, label %axiom_retain.exit, label %bump.i

bump.i:                                           ; preds = %chk.i
  %c1.i = add nuw i64 %c.i, 1
  store i64 %c1.i, ptr %cp.i, align 8
  br label %axiom_retain.exit

axiom_retain.exit:                                ; preds = %"Vec$vecGet.exit", %chk.i, %bump.i
  ret i64 %t16.i
}

define i64 @"Vec$vecSet"(i64 returned %v, i64 %i, i64 %x, i64 %__evw.h) #0 {
  %c0 = icmp slt i64 %i, 0
  br i1 %c0, label %label_5, label %label_4

label_4:                                          ; preds = %0
  %t0.i.i = inttoptr i64 %v to ptr
  %t2.i.i = load i64, ptr %t0.i.i, align 8
  %c7.not = icmp slt i64 %i, %t2.i.i
  br i1 %c7.not, label %label_11, label %label_5

label_11:                                         ; preds = %label_4
  %t1.i.i = getelementptr i8, ptr %t0.i.i, i64 24
  %t2.i.i2 = load i64, ptr %t1.i.i, align 8
  %c1.i.not = icmp eq i64 %t2.i.i2, 1
  br i1 %c1.i.not, label %label_15, label %label_17

label_15:                                         ; preds = %label_11
  %t1.i.i.i = getelementptr i8, ptr %t0.i.i, i64 16
  %t2.i.i.i = load i64, ptr %t1.i.i.i, align 8
  %t0.i.i3 = inttoptr i64 %t2.i.i.i to ptr
  %t1.i.i4 = getelementptr i64, ptr %t0.i.i3, i64 %i
  %t2.i.i5 = load i64, ptr %t1.i.i4, align 8
  store i64 0, ptr %t1.i.i4, align 8
  tail call void @axiom_release(i64 %t2.i.i5)
  br label %label_17

label_17:                                         ; preds = %label_11, %label_15
  %t1.i.i7 = getelementptr i8, ptr %t0.i.i, i64 16
  %t2.i.i8 = load i64, ptr %t1.i.i7, align 8
  %t22 = and i64 %__evw.h, 1
  %t2.not.i = icmp eq i64 %t22, 0
  %imm.i.i = icmp slt i64 %x, 4096
  %or.cond.i = select i1 %t2.not.i, i1 true, i1 %imm.i.i
  br i1 %or.cond.i, label %"Mem$memSetWord.exit", label %chk.i.i

chk.i.i:                                          ; preds = %label_17
  %hoff.i.i = add nsw i64 %x, -16
  %cp.i.i = inttoptr i64 %hoff.i.i to ptr
  %c.i.i = load i64, ptr %cp.i.i, align 8
  %stat.i.i = icmp eq i64 %c.i.i, -1
  br i1 %stat.i.i, label %"Mem$memSetWord.exit", label %bump.i.i

bump.i.i:                                         ; preds = %chk.i.i
  %c1.i.i = add nuw i64 %c.i.i, 1
  store i64 %c1.i.i, ptr %cp.i.i, align 8
  br label %"Mem$memSetWord.exit"

"Mem$memSetWord.exit":                            ; preds = %label_17, %chk.i.i, %bump.i.i
  %t5.i = inttoptr i64 %t2.i.i8 to ptr
  %t6.i = getelementptr i64, ptr %t5.i, i64 %i
  store i64 %x, ptr %t6.i, align 8
  br label %label_5

label_5:                                          ; preds = %"Mem$memSetWord.exit", %label_4, %0
  ret i64 %v
}

define i64 @"Vec$vecReserve"(i64 returned %v, i64 %need) #0 {
  %t0.i.i = inttoptr i64 %v to ptr
  %t1.i.i = getelementptr i8, ptr %t0.i.i, i64 8
  %t2.i.i = load i64, ptr %t1.i.i, align 8
  %c1.not = icmp sgt i64 %need, %t2.i.i
  br i1 %c1.not, label %label_0.i, label %label_6

label_0.i:                                        ; preds = %0, %label_0.i
  %s.1.0.i = phi i64 [ %t13.i, %label_0.i ], [ %t2.i.i, %0 ]
  %c5.not.i = icmp slt i64 %s.1.0.i, %need
  %t13.i = shl i64 %s.1.0.i, 1
  br i1 %c5.not.i, label %label_0.i, label %"Vec$vecGrownCap.exit"

"Vec$vecGrownCap.exit":                           ; preds = %label_0.i
  %t1.i.i.i = getelementptr i8, ptr %t0.i.i, i64 16
  %t2.i.i.i = load i64, ptr %t1.i.i.i, align 8
  %t1.i = shl i64 %s.1.0.i, 3
  %t0.i.i4 = tail call i64 @axiom_alloc(i64 %t1.i)
  %imm.i.i = icmp slt i64 %t0.i.i4, 4096
  br i1 %imm.i.i, label %axiom_retain.exit.i, label %chk.i.i

chk.i.i:                                          ; preds = %"Vec$vecGrownCap.exit"
  %hoff.i.i = add nsw i64 %t0.i.i4, -16
  %cp.i.i = inttoptr i64 %hoff.i.i to ptr
  %c.i.i = load i64, ptr %cp.i.i, align 8
  %stat.i.i = icmp eq i64 %c.i.i, -1
  br i1 %stat.i.i, label %axiom_retain.exit.i, label %bump.i.i

bump.i.i:                                         ; preds = %chk.i.i
  %c1.i.i = add nuw i64 %c.i.i, 1
  store i64 %c1.i.i, ptr %cp.i.i, align 8
  br label %axiom_retain.exit.i

axiom_retain.exit.i:                              ; preds = %bump.i.i, %chk.i.i, %"Vec$vecGrownCap.exit"
  %t1.i.i2.i = getelementptr i8, ptr %t0.i.i, i64 24
  %t2.i.i3.i = load i64, ptr %t1.i.i2.i, align 8
  %c1.i4.not.i = icmp eq i64 %t2.i.i3.i, 1
  br i1 %c1.i4.not.i, label %label_5.i, label %label_7.i

label_5.i:                                        ; preds = %axiom_retain.exit.i
  %t0.i5.i = add i64 %t0.i.i4, -8
  %t2.i6.i = inttoptr i64 %t0.i5.i to ptr
  %t4.i.i = load i64, ptr %t2.i6.i, align 8
  %t5.i.i = or i64 %t4.i.i, 32768
  store i64 %t5.i.i, ptr %t2.i6.i, align 8
  br label %label_7.i

label_7.i:                                        ; preds = %label_5.i, %axiom_retain.exit.i
  %t2.i.i8.i = load i64, ptr %t0.i.i, align 8
  %t11.i = shl i64 %t2.i.i8.i, 3
  %c54.i.i.i = icmp sgt i64 %t11.i, 0
  br i1 %c54.i.i.i, label %label_2.lr.ph.i.i.i, label %"Vec$vecReserveExactly.exit"

label_2.lr.ph.i.i.i:                              ; preds = %label_7.i
  %t10.i.i.i = inttoptr i64 %t2.i.i.i to ptr
  %t14.i.i.i = inttoptr i64 %t0.i.i4 to ptr
  br label %label_2.i.i.i

label_2.i.i.i:                                    ; preds = %label_2.i.i.i, %label_2.lr.ph.i.i.i
  %s.0.05.i.i.i = phi i64 [ 0, %label_2.lr.ph.i.i.i ], [ %t18.i.i.i, %label_2.i.i.i ]
  %t11.i.i.i = getelementptr i8, ptr %t10.i.i.i, i64 %s.0.05.i.i.i
  %t12.i.i.i = load i8, ptr %t11.i.i.i, align 1
  %t15.i.i.i = getelementptr i8, ptr %t14.i.i.i, i64 %s.0.05.i.i.i
  store i8 %t12.i.i.i, ptr %t15.i.i.i, align 1
  %t18.i.i.i = add nuw nsw i64 %s.0.05.i.i.i, 1
  %exitcond.not.i.i.i = icmp eq i64 %t18.i.i.i, %t11.i
  br i1 %exitcond.not.i.i.i, label %"Vec$vecReserveExactly.exit", label %label_2.i.i.i

"Vec$vecReserveExactly.exit":                     ; preds = %label_2.i.i.i, %label_7.i
  store i64 %t0.i.i4, ptr %t1.i.i.i, align 8
  store i64 %s.1.0.i, ptr %t1.i.i, align 8
  %t0.i13.i = add i64 %t2.i.i.i, -8
  %t2.i14.i = inttoptr i64 %t0.i13.i to ptr
  %t4.i15.i = load i64, ptr %t2.i14.i, align 8
  %t7.i.i = and i64 %t4.i15.i, -32769
  store i64 %t7.i.i, ptr %t2.i14.i, align 8
  tail call void @axiom_release(i64 %t2.i.i.i)
  br label %label_6

label_6:                                          ; preds = %0, %"Vec$vecReserveExactly.exit"
  ret i64 %v
}

; Function Attrs: nofree norecurse nosync nounwind memory(none)
define i64 @"Vec$vecGrownCap"(i64 %cap, i64 %need) #10 {
  br label %label_0

label_0:                                          ; preds = %label_0, %0
  %s.1.0 = phi i64 [ %cap, %0 ], [ %t13, %label_0 ]
  %c5.not = icmp slt i64 %s.1.0, %need
  %t13 = shl i64 %s.1.0, 1
  br i1 %c5.not, label %label_0, label %label_8

label_8:                                          ; preds = %label_0
  ret i64 %s.1.0
}

define i64 @"Vec$vecReserveExactly"(i64 returned %v, i64 %newCap) #0 {
  %t0.i.i = inttoptr i64 %v to ptr
  %t1.i.i = getelementptr i8, ptr %t0.i.i, i64 16
  %t2.i.i = load i64, ptr %t1.i.i, align 8
  %t1 = shl i64 %newCap, 3
  %t0.i = tail call i64 @axiom_alloc(i64 %t1)
  %imm.i = icmp slt i64 %t0.i, 4096
  br i1 %imm.i, label %axiom_retain.exit, label %chk.i

chk.i:                                            ; preds = %0
  %hoff.i = add nsw i64 %t0.i, -16
  %cp.i = inttoptr i64 %hoff.i to ptr
  %c.i = load i64, ptr %cp.i, align 8
  %stat.i = icmp eq i64 %c.i, -1
  br i1 %stat.i, label %axiom_retain.exit, label %bump.i

bump.i:                                           ; preds = %chk.i
  %c1.i = add nuw i64 %c.i, 1
  store i64 %c1.i, ptr %cp.i, align 8
  br label %axiom_retain.exit

axiom_retain.exit:                                ; preds = %0, %chk.i, %bump.i
  %t1.i.i2 = getelementptr i8, ptr %t0.i.i, i64 24
  %t2.i.i3 = load i64, ptr %t1.i.i2, align 8
  %c1.i4.not = icmp eq i64 %t2.i.i3, 1
  br i1 %c1.i4.not, label %label_5, label %label_7

label_5:                                          ; preds = %axiom_retain.exit
  %t0.i5 = add i64 %t0.i, -8
  %t2.i6 = inttoptr i64 %t0.i5 to ptr
  %t4.i = load i64, ptr %t2.i6, align 8
  %t5.i = or i64 %t4.i, 32768
  store i64 %t5.i, ptr %t2.i6, align 8
  br label %label_7

label_7:                                          ; preds = %axiom_retain.exit, %label_5
  %t2.i.i8 = load i64, ptr %t0.i.i, align 8
  %t11 = shl i64 %t2.i.i8, 3
  %c54.i.i = icmp sgt i64 %t11, 0
  br i1 %c54.i.i, label %label_2.lr.ph.i.i, label %"Mem$memCopy.exit"

label_2.lr.ph.i.i:                                ; preds = %label_7
  %t10.i.i = inttoptr i64 %t2.i.i to ptr
  %t14.i.i = inttoptr i64 %t0.i to ptr
  br label %label_2.i.i

label_2.i.i:                                      ; preds = %label_2.i.i, %label_2.lr.ph.i.i
  %s.0.05.i.i = phi i64 [ 0, %label_2.lr.ph.i.i ], [ %t18.i.i, %label_2.i.i ]
  %t11.i.i = getelementptr i8, ptr %t10.i.i, i64 %s.0.05.i.i
  %t12.i.i = load i8, ptr %t11.i.i, align 1
  %t15.i.i = getelementptr i8, ptr %t14.i.i, i64 %s.0.05.i.i
  store i8 %t12.i.i, ptr %t15.i.i, align 1
  %t18.i.i = add nuw nsw i64 %s.0.05.i.i, 1
  %exitcond.not.i.i = icmp eq i64 %t18.i.i, %t11
  br i1 %exitcond.not.i.i, label %"Mem$memCopy.exit", label %label_2.i.i

"Mem$memCopy.exit":                               ; preds = %label_2.i.i, %label_7
  store i64 %t0.i, ptr %t1.i.i, align 8
  %t6.i12 = getelementptr i8, ptr %t0.i.i, i64 8
  store i64 %newCap, ptr %t6.i12, align 8
  %t0.i13 = add i64 %t2.i.i, -8
  %t2.i14 = inttoptr i64 %t0.i13 to ptr
  %t4.i15 = load i64, ptr %t2.i14, align 8
  %t7.i = and i64 %t4.i15, -32769
  store i64 %t7.i, ptr %t2.i14, align 8
  tail call void @axiom_release(i64 %t2.i.i)
  ret i64 %v
}

define i64 @"Vec$vecPush"(i64 returned %v, i64 %x, i64 %__evw.h) #0 {
  %t0.i.i = inttoptr i64 %v to ptr
  %t2.i.i = load i64, ptr %t0.i.i, align 8
  %t1 = add i64 %t2.i.i, 1
  %t1.i.i.i = getelementptr i8, ptr %t0.i.i, i64 8
  %t2.i.i.i = load i64, ptr %t1.i.i.i, align 8
  %c1.not.i = icmp sgt i64 %t1, %t2.i.i.i
  br i1 %c1.not.i, label %label_0.i.i, label %"Vec$vecReserve.exit"

label_0.i.i:                                      ; preds = %0, %label_0.i.i
  %s.1.0.i.i = phi i64 [ %t13.i.i, %label_0.i.i ], [ %t2.i.i.i, %0 ]
  %c5.not.i.i = icmp slt i64 %s.1.0.i.i, %t1
  %t13.i.i = shl i64 %s.1.0.i.i, 1
  br i1 %c5.not.i.i, label %label_0.i.i, label %"Vec$vecGrownCap.exit.i"

"Vec$vecGrownCap.exit.i":                         ; preds = %label_0.i.i
  %t1.i.i.i.i = getelementptr i8, ptr %t0.i.i, i64 16
  %t2.i.i.i.i = load i64, ptr %t1.i.i.i.i, align 8
  %t1.i.i = shl i64 %s.1.0.i.i, 3
  %t0.i.i4.i = tail call i64 @axiom_alloc(i64 %t1.i.i)
  %imm.i.i.i = icmp slt i64 %t0.i.i4.i, 4096
  br i1 %imm.i.i.i, label %axiom_retain.exit.i.i, label %chk.i.i.i

chk.i.i.i:                                        ; preds = %"Vec$vecGrownCap.exit.i"
  %hoff.i.i.i = add nsw i64 %t0.i.i4.i, -16
  %cp.i.i.i = inttoptr i64 %hoff.i.i.i to ptr
  %c.i.i.i = load i64, ptr %cp.i.i.i, align 8
  %stat.i.i.i = icmp eq i64 %c.i.i.i, -1
  br i1 %stat.i.i.i, label %axiom_retain.exit.i.i, label %bump.i.i.i

bump.i.i.i:                                       ; preds = %chk.i.i.i
  %c1.i.i.i = add nuw i64 %c.i.i.i, 1
  store i64 %c1.i.i.i, ptr %cp.i.i.i, align 8
  br label %axiom_retain.exit.i.i

axiom_retain.exit.i.i:                            ; preds = %bump.i.i.i, %chk.i.i.i, %"Vec$vecGrownCap.exit.i"
  %t1.i.i2.i.i = getelementptr i8, ptr %t0.i.i, i64 24
  %t2.i.i3.i.i = load i64, ptr %t1.i.i2.i.i, align 8
  %c1.i4.not.i.i = icmp eq i64 %t2.i.i3.i.i, 1
  br i1 %c1.i4.not.i.i, label %label_5.i.i, label %label_7.i.i

label_5.i.i:                                      ; preds = %axiom_retain.exit.i.i
  %t0.i5.i.i = add i64 %t0.i.i4.i, -8
  %t2.i6.i.i = inttoptr i64 %t0.i5.i.i to ptr
  %t4.i.i.i = load i64, ptr %t2.i6.i.i, align 8
  %t5.i.i.i = or i64 %t4.i.i.i, 32768
  store i64 %t5.i.i.i, ptr %t2.i6.i.i, align 8
  br label %label_7.i.i

label_7.i.i:                                      ; preds = %label_5.i.i, %axiom_retain.exit.i.i
  %t2.i.i8.i.i = load i64, ptr %t0.i.i, align 8
  %t11.i.i = shl i64 %t2.i.i8.i.i, 3
  %c54.i.i.i.i = icmp sgt i64 %t11.i.i, 0
  br i1 %c54.i.i.i.i, label %label_2.lr.ph.i.i.i.i, label %"Vec$vecReserveExactly.exit.i"

label_2.lr.ph.i.i.i.i:                            ; preds = %label_7.i.i
  %t10.i.i.i.i = inttoptr i64 %t2.i.i.i.i to ptr
  %t14.i.i.i.i = inttoptr i64 %t0.i.i4.i to ptr
  br label %label_2.i.i.i.i

label_2.i.i.i.i:                                  ; preds = %label_2.i.i.i.i, %label_2.lr.ph.i.i.i.i
  %s.0.05.i.i.i.i = phi i64 [ 0, %label_2.lr.ph.i.i.i.i ], [ %t18.i.i.i.i, %label_2.i.i.i.i ]
  %t11.i.i.i.i = getelementptr i8, ptr %t10.i.i.i.i, i64 %s.0.05.i.i.i.i
  %t12.i.i.i.i = load i8, ptr %t11.i.i.i.i, align 1
  %t15.i.i.i.i = getelementptr i8, ptr %t14.i.i.i.i, i64 %s.0.05.i.i.i.i
  store i8 %t12.i.i.i.i, ptr %t15.i.i.i.i, align 1
  %t18.i.i.i.i = add nuw nsw i64 %s.0.05.i.i.i.i, 1
  %exitcond.not.i.i.i.i = icmp eq i64 %t18.i.i.i.i, %t11.i.i
  br i1 %exitcond.not.i.i.i.i, label %"Vec$vecReserveExactly.exit.i", label %label_2.i.i.i.i

"Vec$vecReserveExactly.exit.i":                   ; preds = %label_2.i.i.i.i, %label_7.i.i
  store i64 %t0.i.i4.i, ptr %t1.i.i.i.i, align 8
  store i64 %s.1.0.i.i, ptr %t1.i.i.i, align 8
  %t0.i13.i.i = add i64 %t2.i.i.i.i, -8
  %t2.i14.i.i = inttoptr i64 %t0.i13.i.i to ptr
  %t4.i15.i.i = load i64, ptr %t2.i14.i.i, align 8
  %t7.i.i.i = and i64 %t4.i15.i.i, -32769
  store i64 %t7.i.i.i, ptr %t2.i14.i.i, align 8
  tail call void @axiom_release(i64 %t2.i.i.i.i)
  br label %"Vec$vecReserve.exit"

"Vec$vecReserve.exit":                            ; preds = %0, %"Vec$vecReserveExactly.exit.i"
  %t1.i.i2 = getelementptr i8, ptr %t0.i.i, i64 16
  %t2.i.i3 = load i64, ptr %t1.i.i2, align 8
  %t5 = and i64 %__evw.h, 1
  %t2.not.i = icmp eq i64 %t5, 0
  %imm.i.i = icmp slt i64 %x, 4096
  %or.cond.i = select i1 %t2.not.i, i1 true, i1 %imm.i.i
  br i1 %or.cond.i, label %"Mem$memSetWord.exit", label %chk.i.i

chk.i.i:                                          ; preds = %"Vec$vecReserve.exit"
  %hoff.i.i = add nsw i64 %x, -16
  %cp.i.i = inttoptr i64 %hoff.i.i to ptr
  %c.i.i = load i64, ptr %cp.i.i, align 8
  %stat.i.i = icmp eq i64 %c.i.i, -1
  br i1 %stat.i.i, label %"Mem$memSetWord.exit", label %bump.i.i

bump.i.i:                                         ; preds = %chk.i.i
  %c1.i.i = add nuw i64 %c.i.i, 1
  store i64 %c1.i.i, ptr %cp.i.i, align 8
  br label %"Mem$memSetWord.exit"

"Mem$memSetWord.exit":                            ; preds = %"Vec$vecReserve.exit", %chk.i.i, %bump.i.i
  %t5.i = inttoptr i64 %t2.i.i3 to ptr
  %t6.i = getelementptr i64, ptr %t5.i, i64 %t2.i.i
  store i64 %x, ptr %t6.i, align 8
  store i64 %t1, ptr %t0.i.i, align 8
  ret i64 %v
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(readwrite, inaccessiblemem: none, target_mem0: none, target_mem1: none)
define i64 @"Vec$vecPop"(i64 %v) #2 {
  %t0.i.i = inttoptr i64 %v to ptr
  %t2.i.i = load i64, ptr %t0.i.i, align 8
  %c1 = icmp eq i64 %t2.i.i, 0
  br i1 %c1, label %label_6, label %label_5

label_5:                                          ; preds = %0
  %t1.i.i = getelementptr i8, ptr %t0.i.i, i64 16
  %t2.i.i2 = load i64, ptr %t1.i.i, align 8
  %t8 = add i64 %t2.i.i, -1
  %t0.i = inttoptr i64 %t2.i.i2 to ptr
  %t1.i = getelementptr i64, ptr %t0.i, i64 %t8
  %t2.i = load i64, ptr %t1.i, align 8
  store i64 0, ptr %t1.i, align 8
  store i64 %t8, ptr %t0.i.i, align 8
  br label %label_6

label_6:                                          ; preds = %0, %label_5
  %t15 = phi i64 [ %t2.i, %label_5 ], [ 0, %0 ]
  ret i64 %t15
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(read, inaccessiblemem: none, target_mem0: none, target_mem1: none)
define i64 @"Vec$vecLast"(i64 %v) #8 {
  %t0.i.i = inttoptr i64 %v to ptr
  %t2.i.i = load i64, ptr %t0.i.i, align 8
  %or.cond = icmp sgt i64 %t2.i.i, 0
  br i1 %or.cond, label %label_11.i, label %"Vec$vecGet.exit"

label_11.i:                                       ; preds = %0
  %t1.i.i.i = getelementptr i8, ptr %t0.i.i, i64 16
  %t2.i.i2.i = load i64, ptr %t1.i.i.i, align 8
  %t0.i.i1 = inttoptr i64 %t2.i.i2.i to ptr
  %1 = getelementptr i64, ptr %t0.i.i1, i64 %t2.i.i
  %t1.i.i = getelementptr i8, ptr %1, i64 -8
  %t2.i.i2 = load i64, ptr %t1.i.i, align 8
  br label %"Vec$vecGet.exit"

"Vec$vecGet.exit":                                ; preds = %0, %label_11.i
  %t16.i = phi i64 [ 0, %0 ], [ %t2.i.i2, %label_11.i ]
  ret i64 %t16.i
}

define i64 @"Vec$vecClear"(i64 returned %v) #0 {
  %t0.i.i = inttoptr i64 %v to ptr
  %t1.i.i = getelementptr i8, ptr %t0.i.i, i64 24
  %t2.i.i = load i64, ptr %t1.i.i, align 8
  %c1.i.not = icmp eq i64 %t2.i.i, 1
  br i1 %c1.i.not, label %label_2, label %label_4

label_2:                                          ; preds = %0
  %t2.i.i8.i = load i64, ptr %t0.i.i, align 8
  %c6.not9.i = icmp sgt i64 %t2.i.i8.i, 0
  br i1 %c6.not9.i, label %label_10.lr.ph.i, label %label_4

label_10.lr.ph.i:                                 ; preds = %label_2
  %t1.i.i.i.i = getelementptr i8, ptr %t0.i.i, i64 16
  br label %label_10.i

label_10.i:                                       ; preds = %label_10.i, %label_10.lr.ph.i
  %s.2.010.i = phi i64 [ 0, %label_10.lr.ph.i ], [ %t18.i, %label_10.i ]
  %t2.i.i.i.i = load i64, ptr %t1.i.i.i.i, align 8
  %t0.i.i6.i = inttoptr i64 %t2.i.i.i.i to ptr
  %t1.i.i.i = getelementptr i64, ptr %t0.i.i6.i, i64 %s.2.010.i
  %t2.i.i7.i = load i64, ptr %t1.i.i.i, align 8
  store i64 0, ptr %t1.i.i.i, align 8
  tail call void @axiom_release(i64 %t2.i.i7.i)
  %t18.i = add nuw nsw i64 %s.2.010.i, 1
  %t2.i.i.i = load i64, ptr %t0.i.i, align 8
  %c6.not.i = icmp slt i64 %t18.i, %t2.i.i.i
  br i1 %c6.not.i, label %label_10.i, label %label_4

label_4:                                          ; preds = %label_10.i, %label_2, %0
  store i64 0, ptr %t0.i.i, align 8
  ret i64 %v
}

define i64 @"Vec$vecDropAt"(i64 returned %v, i64 %i) #0 {
  %t0.i.i = inttoptr i64 %v to ptr
  %t1.i.i = getelementptr i8, ptr %t0.i.i, i64 16
  %t2.i.i = load i64, ptr %t1.i.i, align 8
  %t0.i = inttoptr i64 %t2.i.i to ptr
  %t1.i = getelementptr i64, ptr %t0.i, i64 %i
  %t2.i = load i64, ptr %t1.i, align 8
  store i64 0, ptr %t1.i, align 8
  tail call void @axiom_release(i64 %t2.i)
  ret i64 %v
}

define i64 @"Vec$vecDropFrom"(i64 returned %v, i64 %i) #0 {
  %t0.i.i = inttoptr i64 %v to ptr
  %t2.i.i8 = load i64, ptr %t0.i.i, align 8
  %c6.not9 = icmp slt i64 %i, %t2.i.i8
  br i1 %c6.not9, label %label_10.lr.ph, label %label_9

label_10.lr.ph:                                   ; preds = %0
  %t1.i.i.i = getelementptr i8, ptr %t0.i.i, i64 16
  br label %label_10

label_9:                                          ; preds = %label_10, %0
  ret i64 %v

label_10:                                         ; preds = %label_10.lr.ph, %label_10
  %s.2.010 = phi i64 [ %i, %label_10.lr.ph ], [ %t18, %label_10 ]
  %t2.i.i.i = load i64, ptr %t1.i.i.i, align 8
  %t0.i.i6 = inttoptr i64 %t2.i.i.i to ptr
  %t1.i.i = getelementptr i64, ptr %t0.i.i6, i64 %s.2.010
  %t2.i.i7 = load i64, ptr %t1.i.i, align 8
  store i64 0, ptr %t1.i.i, align 8
  tail call void @axiom_release(i64 %t2.i.i7)
  %t18 = add nsw i64 %s.2.010, 1
  %t2.i.i = load i64, ptr %t0.i.i, align 8
  %c6.not = icmp slt i64 %t18, %t2.i.i
  br i1 %c6.not, label %label_10, label %label_9
}

; Function Attrs: nofree norecurse nosync nounwind memory(read, inaccessiblemem: none, target_mem0: none, target_mem1: none)
define i64 @"Vec$vecSum"(i64 %v) #5 {
  %t0.i.i.i = inttoptr i64 %v to ptr
  %t2.i.i.i = load i64, ptr %t0.i.i.i, align 8
  %c7.not8.i = icmp sgt i64 %t2.i.i.i, 0
  br i1 %c7.not8.i, label %label_11.lr.ph.i, label %"Vec$vecSumFrom.exit"

label_11.lr.ph.i:                                 ; preds = %0
  %t1.i.i.i.i = getelementptr i8, ptr %t0.i.i.i, i64 16
  %t2.i.i2.i.i = load i64, ptr %t1.i.i.i.i, align 8
  %t0.i.i6.i = inttoptr i64 %t2.i.i2.i.i to ptr
  br label %label_11.i

label_11.i:                                       ; preds = %label_11.i, %label_11.lr.ph.i
  %s.3.010.i = phi i64 [ 0, %label_11.lr.ph.i ], [ %t21.i, %label_11.i ]
  %s.2.09.i = phi i64 [ 0, %label_11.lr.ph.i ], [ %t16.i, %label_11.i ]
  %t16.i = add nuw nsw i64 %s.2.09.i, 1
  %t1.i.i.i = getelementptr i64, ptr %t0.i.i6.i, i64 %s.2.09.i
  %t2.i.i7.i = load i64, ptr %t1.i.i.i, align 8
  %t21.i = add i64 %t2.i.i7.i, %s.3.010.i
  %exitcond.not.i = icmp eq i64 %t16.i, %t2.i.i.i
  br i1 %exitcond.not.i, label %"Vec$vecSumFrom.exit", label %label_11.i

"Vec$vecSumFrom.exit":                            ; preds = %label_11.i, %0
  %s.3.0.lcssa.i = phi i64 [ 0, %0 ], [ %t21.i, %label_11.i ]
  ret i64 %s.3.0.lcssa.i
}

; Function Attrs: nofree norecurse nosync nounwind memory(read, inaccessiblemem: none, target_mem0: none, target_mem1: none)
define i64 @"Vec$vecSumFrom"(i64 %v, i64 %i, i64 %acc) #5 {
  %t0.i.i = inttoptr i64 %v to ptr
  %t2.i.i = load i64, ptr %t0.i.i, align 8
  %c7.not8 = icmp slt i64 %i, %t2.i.i
  br i1 %c7.not8, label %label_11.lr.ph, label %label_10

label_11.lr.ph:                                   ; preds = %0
  %t1.i.i.i = getelementptr i8, ptr %t0.i.i, i64 16
  br label %label_11

label_10:                                         ; preds = %"Vec$vecGet.exit", %0
  %s.3.0.lcssa = phi i64 [ %acc, %0 ], [ %t21, %"Vec$vecGet.exit" ]
  ret i64 %s.3.0.lcssa

label_11:                                         ; preds = %label_11.lr.ph, %"Vec$vecGet.exit"
  %s.3.010 = phi i64 [ %acc, %label_11.lr.ph ], [ %t21, %"Vec$vecGet.exit" ]
  %s.2.09 = phi i64 [ %i, %label_11.lr.ph ], [ %t16, %"Vec$vecGet.exit" ]
  %t16 = add nsw i64 %s.2.09, 1
  %c0.i = icmp slt i64 %s.2.09, 0
  br i1 %c0.i, label %"Vec$vecGet.exit", label %label_11.i

label_11.i:                                       ; preds = %label_11
  %t2.i.i2.i = load i64, ptr %t1.i.i.i, align 8
  %t0.i.i6 = inttoptr i64 %t2.i.i2.i to ptr
  %t1.i.i = getelementptr i64, ptr %t0.i.i6, i64 %s.2.09
  %t2.i.i7 = load i64, ptr %t1.i.i, align 8
  br label %"Vec$vecGet.exit"

"Vec$vecGet.exit":                                ; preds = %label_11, %label_11.i
  %t16.i = phi i64 [ 0, %label_11 ], [ %t2.i.i7, %label_11.i ]
  %t21 = add i64 %t16.i, %s.3.010
  %exitcond.not = icmp eq i64 %t16, %t2.i.i
  br i1 %exitcond.not, label %label_10, label %label_11
}

; Function Attrs: nofree norecurse nosync nounwind memory(read, inaccessiblemem: none, target_mem0: none, target_mem1: none)
define range(i64 -1000000006, 1000000007) i64 @"Vec$vecHash"(i64 %v) #5 {
  %t0.i.i.i = inttoptr i64 %v to ptr
  %t2.i.i.i = load i64, ptr %t0.i.i.i, align 8
  %c7.not8.i = icmp sgt i64 %t2.i.i.i, 0
  br i1 %c7.not8.i, label %label_11.lr.ph.i, label %"Vec$vecHashFrom.exit"

label_11.lr.ph.i:                                 ; preds = %0
  %t1.i.i.i.i = getelementptr i8, ptr %t0.i.i.i, i64 16
  %t2.i.i2.i.i = load i64, ptr %t1.i.i.i.i, align 8
  %t0.i.i6.i = inttoptr i64 %t2.i.i2.i.i to ptr
  br label %label_11.i

label_11.i:                                       ; preds = %label_11.i, %label_11.lr.ph.i
  %s.3.010.i = phi i64 [ 1, %label_11.lr.ph.i ], [ %t26.i, %label_11.i ]
  %s.2.09.i = phi i64 [ 0, %label_11.lr.ph.i ], [ %t16.i, %label_11.i ]
  %t1.i.i.i = getelementptr i64, ptr %t0.i.i6.i, i64 %s.2.09.i
  %t2.i.i7.i = load i64, ptr %t1.i.i.i, align 8
  %t18.i = mul nsw i64 %s.3.010.i, 31
  %t22.i = add i64 %t2.i.i7.i, %t18.i
  %t16.i = add nuw nsw i64 %s.2.09.i, 1
  %t26.i = srem i64 %t22.i, 1000000007
  %exitcond.not.i = icmp eq i64 %t16.i, %t2.i.i.i
  br i1 %exitcond.not.i, label %"Vec$vecHashFrom.exit", label %label_11.i

"Vec$vecHashFrom.exit":                           ; preds = %label_11.i, %0
  %s.3.0.lcssa.i = phi i64 [ 1, %0 ], [ %t26.i, %label_11.i ]
  ret i64 %s.3.0.lcssa.i
}

; Function Attrs: nofree norecurse nosync nounwind memory(read, inaccessiblemem: none, target_mem0: none, target_mem1: none)
define i64 @"Vec$vecHashFrom"(i64 %v, i64 %i, i64 %h) #5 {
  %t0.i.i = inttoptr i64 %v to ptr
  %t2.i.i = load i64, ptr %t0.i.i, align 8
  %c7.not8 = icmp slt i64 %i, %t2.i.i
  br i1 %c7.not8, label %label_11.lr.ph, label %label_10

label_11.lr.ph:                                   ; preds = %0
  %t1.i.i.i = getelementptr i8, ptr %t0.i.i, i64 16
  br label %label_11

label_10:                                         ; preds = %"Vec$vecGet.exit", %0
  %s.3.0.lcssa = phi i64 [ %h, %0 ], [ %t26, %"Vec$vecGet.exit" ]
  ret i64 %s.3.0.lcssa

label_11:                                         ; preds = %label_11.lr.ph, %"Vec$vecGet.exit"
  %s.3.010 = phi i64 [ %h, %label_11.lr.ph ], [ %t26, %"Vec$vecGet.exit" ]
  %s.2.09 = phi i64 [ %i, %label_11.lr.ph ], [ %t16, %"Vec$vecGet.exit" ]
  %c0.i = icmp slt i64 %s.2.09, 0
  br i1 %c0.i, label %"Vec$vecGet.exit", label %label_11.i

label_11.i:                                       ; preds = %label_11
  %t2.i.i2.i = load i64, ptr %t1.i.i.i, align 8
  %t0.i.i6 = inttoptr i64 %t2.i.i2.i to ptr
  %t1.i.i = getelementptr i64, ptr %t0.i.i6, i64 %s.2.09
  %t2.i.i7 = load i64, ptr %t1.i.i, align 8
  br label %"Vec$vecGet.exit"

"Vec$vecGet.exit":                                ; preds = %label_11, %label_11.i
  %t16.i = phi i64 [ 0, %label_11 ], [ %t2.i.i7, %label_11.i ]
  %t18 = mul i64 %s.3.010, 31
  %t22 = add i64 %t16.i, %t18
  %t16 = add nsw i64 %s.2.09, 1
  %t26 = srem i64 %t22, 1000000007
  %exitcond.not = icmp eq i64 %t16, %t2.i.i
  br i1 %exitcond.not, label %label_10, label %label_11
}

; Function Attrs: nounwind
define i64 @"Str$strWrap"(i64 %bytes, i64 %len) #1 {
  %t0.i.i = tail call i64 @axiom_alloc(i64 24)
  %t7.i.i = add i64 %t0.i.i, -8
  %t8.i.i = inttoptr i64 %t7.i.i to ptr
  %t10.i.i = load i64, ptr %t8.i.i, align 8
  %t11.i.i = lshr i64 %t10.i.i, 1
  %t12.i.i = and i64 %t11.i.i, 16383
  %.t12.i.i = tail call i64 @llvm.umin.i64(i64 %t12.i.i, i64 47)
  %t22.i.i = shl nsw i64 -65536, %.t12.i.i
  %t23.i.i = and i64 %t22.i.i, 262144
  %t24.i.i = xor i64 %t23.i.i, 262144
  %t25.i.i = or i64 %t24.i.i, %t10.i.i
  store i64 %t25.i.i, ptr %t8.i.i, align 8
  %t5.i.i = inttoptr i64 %t0.i.i to ptr
  store i64 %len, ptr %t5.i.i, align 8
  %t6.i.i = getelementptr i8, ptr %t5.i.i, i64 8
  store i64 %bytes, ptr %t6.i.i, align 8
  %t6.i5.i = getelementptr i8, ptr %t5.i.i, i64 16
  store i64 0, ptr %t6.i5.i, align 8
  %imm.i.i = icmp slt i64 %t0.i.i, 4096
  br i1 %imm.i.i, label %"Str$strWrapOwned.exit", label %chk.i.i

chk.i.i:                                          ; preds = %0
  %hoff.i.i = add nsw i64 %t0.i.i, -16
  %cp.i.i = inttoptr i64 %hoff.i.i to ptr
  %c.i.i = load i64, ptr %cp.i.i, align 8
  %stat.i.i = icmp eq i64 %c.i.i, -1
  br i1 %stat.i.i, label %"Str$strWrapOwned.exit", label %bump.i.i

bump.i.i:                                         ; preds = %chk.i.i
  %c1.i.i = add nuw i64 %c.i.i, 1
  store i64 %c1.i.i, ptr %cp.i.i, align 8
  br label %"Str$strWrapOwned.exit"

"Str$strWrapOwned.exit":                          ; preds = %0, %chk.i.i, %bump.i.i
  ret i64 %t0.i.i
}

; Function Attrs: nounwind
define i64 @"Str$strWrapOwned"(i64 %bytes, i64 %len, i64 %owner) #1 {
  %t0.i = tail call i64 @axiom_alloc(i64 24)
  %t7.i = add i64 %t0.i, -8
  %t8.i = inttoptr i64 %t7.i to ptr
  %t10.i = load i64, ptr %t8.i, align 8
  %t11.i = lshr i64 %t10.i, 1
  %t12.i = and i64 %t11.i, 16383
  %.t12.i = tail call i64 @llvm.umin.i64(i64 %t12.i, i64 47)
  %t22.i = shl nsw i64 -65536, %.t12.i
  %t23.i = and i64 %t22.i, 262144
  %t24.i = xor i64 %t23.i, 262144
  %t25.i = or i64 %t24.i, %t10.i
  store i64 %t25.i, ptr %t8.i, align 8
  %t5.i = inttoptr i64 %t0.i to ptr
  store i64 %len, ptr %t5.i, align 8
  %t6.i = getelementptr i8, ptr %t5.i, i64 8
  store i64 %bytes, ptr %t6.i, align 8
  %t6.i5 = getelementptr i8, ptr %t5.i, i64 16
  store i64 %owner, ptr %t6.i5, align 8
  %imm.i = icmp slt i64 %t0.i, 4096
  br i1 %imm.i, label %axiom_retain.exit, label %chk.i

chk.i:                                            ; preds = %0
  %hoff.i = add nsw i64 %t0.i, -16
  %cp.i = inttoptr i64 %hoff.i to ptr
  %c.i = load i64, ptr %cp.i, align 8
  %stat.i = icmp eq i64 %c.i, -1
  br i1 %stat.i, label %axiom_retain.exit, label %bump.i

bump.i:                                           ; preds = %chk.i
  %c1.i = add nuw i64 %c.i, 1
  store i64 %c1.i, ptr %cp.i, align 8
  br label %axiom_retain.exit

axiom_retain.exit:                                ; preds = %0, %chk.i, %bump.i
  ret i64 %t0.i
}

; Function Attrs: nounwind
define i64 @"Str$strAlloc"(i64 %len) #1 {
  %t0 = add i64 %len, 1
  %t0.i = tail call i64 @axiom_alloc(i64 %t0)
  %imm.i = icmp slt i64 %t0.i, 4096
  br i1 %imm.i, label %axiom_retain.exit, label %chk.i

chk.i:                                            ; preds = %0
  %hoff.i = add nsw i64 %t0.i, -16
  %cp.i = inttoptr i64 %hoff.i to ptr
  %c.i = load i64, ptr %cp.i, align 8
  %stat.i = icmp eq i64 %c.i, -1
  br i1 %stat.i, label %axiom_retain.exit, label %bump.i

bump.i:                                           ; preds = %chk.i
  %c1.i = add nuw i64 %c.i, 1
  store i64 %c1.i, ptr %cp.i, align 8
  br label %axiom_retain.exit

axiom_retain.exit:                                ; preds = %0, %chk.i, %bump.i
  %t0.i.i = tail call i64 @axiom_alloc(i64 24)
  %t7.i.i = add i64 %t0.i.i, -8
  %t8.i.i = inttoptr i64 %t7.i.i to ptr
  %t10.i.i = load i64, ptr %t8.i.i, align 8
  %t11.i.i = lshr i64 %t10.i.i, 1
  %t12.i.i = and i64 %t11.i.i, 16383
  %.t12.i.i = tail call i64 @llvm.umin.i64(i64 %t12.i.i, i64 47)
  %t22.i.i = shl nsw i64 -65536, %.t12.i.i
  %t23.i.i = and i64 %t22.i.i, 262144
  %t24.i.i = xor i64 %t23.i.i, 262144
  %t25.i.i = or i64 %t24.i.i, %t10.i.i
  store i64 %t25.i.i, ptr %t8.i.i, align 8
  %t5.i.i = inttoptr i64 %t0.i.i to ptr
  store i64 %len, ptr %t5.i.i, align 8
  %t6.i.i = getelementptr i8, ptr %t5.i.i, i64 8
  store i64 %t0.i, ptr %t6.i.i, align 8
  %t6.i5.i = getelementptr i8, ptr %t5.i.i, i64 16
  store i64 %t0.i, ptr %t6.i5.i, align 8
  %imm.i.i = icmp slt i64 %t0.i.i, 4096
  br i1 %imm.i.i, label %"Str$strWrapOwned.exit", label %chk.i.i

chk.i.i:                                          ; preds = %axiom_retain.exit
  %hoff.i.i = add nsw i64 %t0.i.i, -16
  %cp.i.i = inttoptr i64 %hoff.i.i to ptr
  %c.i.i = load i64, ptr %cp.i.i, align 8
  %stat.i.i = icmp eq i64 %c.i.i, -1
  br i1 %stat.i.i, label %"Str$strWrapOwned.exit", label %bump.i.i

bump.i.i:                                         ; preds = %chk.i.i
  %c1.i.i = add nuw i64 %c.i.i, 1
  store i64 %c1.i.i, ptr %cp.i.i, align 8
  br label %"Str$strWrapOwned.exit"

"Str$strWrapOwned.exit":                          ; preds = %axiom_retain.exit, %chk.i.i, %bump.i.i
  ret i64 %t0.i.i
}

; Function Attrs: nounwind
define i64 @"Str$strFromLit"(i64 %cstr) #1 {
  %t5.i = inttoptr i64 %cstr to ptr
  br label %label_0.i

label_0.i:                                        ; preds = %label_0.i, %0
  %s.2.0.i = phi i64 [ 0, %0 ], [ %t18.i, %label_0.i ]
  %t6.i = getelementptr i8, ptr %t5.i, i64 %s.2.0.i
  %t7.i = load i8, ptr %t6.i, align 1
  %c9.i = icmp eq i8 %t7.i, 0
  %t18.i = add i64 %s.2.0.i, 1
  br i1 %c9.i, label %"Str$cstrLen.exit", label %label_0.i

"Str$cstrLen.exit":                               ; preds = %label_0.i
  %t0.i.i.i = tail call i64 @axiom_alloc(i64 24)
  %t7.i.i.i = add i64 %t0.i.i.i, -8
  %t8.i.i.i = inttoptr i64 %t7.i.i.i to ptr
  %t10.i.i.i = load i64, ptr %t8.i.i.i, align 8
  %t11.i.i.i = lshr i64 %t10.i.i.i, 1
  %t12.i.i.i = and i64 %t11.i.i.i, 16383
  %.t12.i.i.i = tail call i64 @llvm.umin.i64(i64 %t12.i.i.i, i64 47)
  %t22.i.i.i = shl nsw i64 -65536, %.t12.i.i.i
  %t23.i.i.i = and i64 %t22.i.i.i, 262144
  %t24.i.i.i = xor i64 %t23.i.i.i, 262144
  %t25.i.i.i = or i64 %t24.i.i.i, %t10.i.i.i
  store i64 %t25.i.i.i, ptr %t8.i.i.i, align 8
  %t5.i.i.i = inttoptr i64 %t0.i.i.i to ptr
  store i64 %s.2.0.i, ptr %t5.i.i.i, align 8
  %t6.i.i.i = getelementptr i8, ptr %t5.i.i.i, i64 8
  store i64 %cstr, ptr %t6.i.i.i, align 8
  %t6.i5.i.i = getelementptr i8, ptr %t5.i.i.i, i64 16
  store i64 0, ptr %t6.i5.i.i, align 8
  %imm.i.i.i = icmp slt i64 %t0.i.i.i, 4096
  br i1 %imm.i.i.i, label %"Str$strWrap.exit", label %chk.i.i.i

chk.i.i.i:                                        ; preds = %"Str$cstrLen.exit"
  %hoff.i.i.i = add nsw i64 %t0.i.i.i, -16
  %cp.i.i.i = inttoptr i64 %hoff.i.i.i to ptr
  %c.i.i.i = load i64, ptr %cp.i.i.i, align 8
  %stat.i.i.i = icmp eq i64 %c.i.i.i, -1
  br i1 %stat.i.i.i, label %"Str$strWrap.exit", label %bump.i.i.i

bump.i.i.i:                                       ; preds = %chk.i.i.i
  %c1.i.i.i = add nuw i64 %c.i.i.i, 1
  store i64 %c1.i.i.i, ptr %cp.i.i.i, align 8
  br label %"Str$strWrap.exit"

"Str$strWrap.exit":                               ; preds = %"Str$cstrLen.exit", %chk.i.i.i, %bump.i.i.i
  ret i64 %t0.i.i.i
}

; Function Attrs: nofree norecurse nosync nounwind memory(read, inaccessiblemem: none, target_mem0: none, target_mem1: none)
define i64 @"Str$cstrLen"(i64 %addr, i64 %i) #5 {
  %t5 = inttoptr i64 %addr to ptr
  br label %label_0

label_0:                                          ; preds = %label_0, %0
  %s.2.0 = phi i64 [ %i, %0 ], [ %t18, %label_0 ]
  %t6 = getelementptr i8, ptr %t5, i64 %s.2.0
  %t7 = load i8, ptr %t6, align 1
  %c9 = icmp eq i8 %t7, 0
  %t18 = add i64 %s.2.0, 1
  br i1 %c9, label %label_12, label %label_0

label_12:                                         ; preds = %label_0
  ret i64 %s.2.0
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(read, inaccessiblemem: none, target_mem0: none, target_mem1: none)
define i64 @"Str$strLen"(i64 %s) #8 {
  %t0.i = inttoptr i64 %s to ptr
  %t2.i = load i64, ptr %t0.i, align 8
  ret i64 %t2.i
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(read, inaccessiblemem: none, target_mem0: none, target_mem1: none)
define i64 @"Str$strData"(i64 %s) #8 {
  %t0.i = inttoptr i64 %s to ptr
  %t1.i = getelementptr i8, ptr %t0.i, i64 8
  %t2.i = load i64, ptr %t1.i, align 8
  ret i64 %t2.i
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(read, inaccessiblemem: none, target_mem0: none, target_mem1: none)
define i64 @"Str$strOwner"(i64 %s) #8 {
  %t0.i = inttoptr i64 %s to ptr
  %t1.i = getelementptr i8, ptr %t0.i, i64 16
  %t2.i = load i64, ptr %t1.i, align 8
  ret i64 %t2.i
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(read, inaccessiblemem: none, target_mem0: none, target_mem1: none)
define range(i64 0, 256) i64 @"Str$strByte"(i64 %s, i64 %i) #8 {
  %c0 = icmp slt i64 %i, 0
  br i1 %c0, label %label_5, label %label_4

label_4:                                          ; preds = %0
  %t0.i.i = inttoptr i64 %s to ptr
  %t2.i.i = load i64, ptr %t0.i.i, align 8
  %c7.not = icmp slt i64 %i, %t2.i.i
  br i1 %c7.not, label %label_11, label %label_5

label_11:                                         ; preds = %label_4
  %t1.i.i = getelementptr i8, ptr %t0.i.i, i64 8
  %t2.i.i2 = load i64, ptr %t1.i.i, align 8
  %t14 = inttoptr i64 %t2.i.i2 to ptr
  %t15 = getelementptr i8, ptr %t14, i64 %i
  %t16 = load i8, ptr %t15, align 1
  %t17 = zext i8 %t16 to i64
  br label %label_5

label_5:                                          ; preds = %label_11, %label_4, %0
  %t19 = phi i64 [ 0, %0 ], [ %t17, %label_11 ], [ 0, %label_4 ]
  ret i64 %t19
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(read, inaccessiblemem: none, target_mem0: none, target_mem1: none)
define i64 @"Str$strCStr"(i64 %s) #8 {
  %t0.i.i = inttoptr i64 %s to ptr
  %t1.i.i = getelementptr i8, ptr %t0.i.i, i64 8
  %t2.i.i = load i64, ptr %t1.i.i, align 8
  ret i64 %t2.i.i
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(read, inaccessiblemem: none, target_mem0: none, target_mem1: none)
define range(i64 0, 2) i64 @"Str$strIsEmpty"(i64 %s) #8 {
  %t0.i.i = inttoptr i64 %s to ptr
  %t2.i.i = load i64, ptr %t0.i.i, align 8
  %c1 = icmp eq i64 %t2.i.i, 0
  %t2 = zext i1 %c1 to i64
  ret i64 %t2
}

; Function Attrs: nofree norecurse nosync nounwind memory(read, inaccessiblemem: none, target_mem0: none, target_mem1: none)
define i64 @"Str$strCmp"(i64 %a, i64 %b) #5 {
label_7:
  %t0.i.i = inttoptr i64 %a to ptr
  %t2.i.i = load i64, ptr %t0.i.i, align 8
  %t0.i.i1 = inttoptr i64 %b to ptr
  %t2.i.i2 = load i64, ptr %t0.i.i1, align 8
  %t0.t1 = tail call i64 @llvm.smin.i64(i64 %t2.i.i, i64 %t2.i.i2)
  %c65.i.i = icmp sgt i64 %t0.t1, 0
  br i1 %c65.i.i, label %label_3.lr.ph.i.i, label %"Mem$memCmp.exit"

label_3.lr.ph.i.i:                                ; preds = %label_7
  %t1.i.i6 = getelementptr i8, ptr %t0.i.i1, i64 8
  %t2.i.i7 = load i64, ptr %t1.i.i6, align 8
  %t1.i.i = getelementptr i8, ptr %t0.i.i, i64 8
  %t2.i.i4 = load i64, ptr %t1.i.i, align 8
  %t20.i.i = inttoptr i64 %t2.i.i4 to ptr
  %t25.i.i = inttoptr i64 %t2.i.i7 to ptr
  br label %label_3.i.i

label_3.i.i:                                      ; preds = %label_3.i.i, %label_3.lr.ph.i.i
  %s.0.06.i.i = phi i64 [ 0, %label_3.lr.ph.i.i ], [ %t31.i.i, %label_3.i.i ]
  %t21.i.i = getelementptr i8, ptr %t20.i.i, i64 %s.0.06.i.i
  %t22.i.i = load i8, ptr %t21.i.i, align 1
  %t23.i.i = zext i8 %t22.i.i to i64
  %t26.i.i = getelementptr i8, ptr %t25.i.i, i64 %s.0.06.i.i
  %t27.i.i = load i8, ptr %t26.i.i, align 1
  %t28.i.i = zext i8 %t27.i.i to i64
  %t29.i.i = sub nsw i64 %t23.i.i, %t28.i.i
  %t31.i.i = add nuw nsw i64 %s.0.06.i.i, 1
  %c6.i.i = icmp slt i64 %t31.i.i, %t0.t1
  %c13.i.i = icmp eq i64 %t29.i.i, 0
  %narrow.i.i = select i1 %c6.i.i, i1 %c13.i.i, i1 false
  br i1 %narrow.i.i, label %label_3.i.i, label %"Mem$memCmp.exit"

"Mem$memCmp.exit":                                ; preds = %label_3.i.i, %label_7
  %s.1.0.lcssa.i.i = phi i64 [ 0, %label_7 ], [ %t29.i.i, %label_3.i.i ]
  %c12.not = icmp eq i64 %s.1.0.lcssa.i.i, 0
  %t18 = sub i64 %t2.i.i, %t2.i.i2
  %t19 = select i1 %c12.not, i64 %t18, i64 %s.1.0.lcssa.i.i
  ret i64 %t19
}

; Function Attrs: nofree norecurse nosync nounwind memory(read, inaccessiblemem: none, target_mem0: none, target_mem1: none)
define range(i64 0, 2) i64 @"Str$strEq"(i64 %a, i64 %b) #5 {
  %t0.i.i = inttoptr i64 %a to ptr
  %t2.i.i = load i64, ptr %t0.i.i, align 8
  %t0.i.i1 = inttoptr i64 %b to ptr
  %t2.i.i2 = load i64, ptr %t0.i.i1, align 8
  %c2.not = icmp eq i64 %t2.i.i, %t2.i.i2
  br i1 %c2.not, label %label_6, label %label_7

label_6:                                          ; preds = %0
  %c65.i.i = icmp sgt i64 %t2.i.i, 0
  br i1 %c65.i.i, label %label_3.lr.ph.i.i, label %label_7

label_3.lr.ph.i.i:                                ; preds = %label_6
  %t1.i.i6 = getelementptr i8, ptr %t0.i.i1, i64 8
  %t2.i.i7 = load i64, ptr %t1.i.i6, align 8
  %t1.i.i = getelementptr i8, ptr %t0.i.i, i64 8
  %t2.i.i4 = load i64, ptr %t1.i.i, align 8
  %t20.i.i = inttoptr i64 %t2.i.i4 to ptr
  %t25.i.i = inttoptr i64 %t2.i.i7 to ptr
  br label %label_3.i.i

label_3.i.i:                                      ; preds = %label_3.i.i, %label_3.lr.ph.i.i
  %s.0.06.i.i = phi i64 [ 0, %label_3.lr.ph.i.i ], [ %t31.i.i, %label_3.i.i ]
  %t21.i.i = getelementptr i8, ptr %t20.i.i, i64 %s.0.06.i.i
  %t22.i.i = load i8, ptr %t21.i.i, align 1
  %t26.i.i = getelementptr i8, ptr %t25.i.i, i64 %s.0.06.i.i
  %t27.i.i = load i8, ptr %t26.i.i, align 1
  %t31.i.i = add nuw nsw i64 %s.0.06.i.i, 1
  %c6.i.i = icmp slt i64 %t31.i.i, %t2.i.i
  %c13.i.i = icmp eq i8 %t22.i.i, %t27.i.i
  %narrow.i.i = select i1 %c6.i.i, i1 %c13.i.i, i1 false
  br i1 %narrow.i.i, label %label_3.i.i, label %"Mem$memCmp.exit.loopexit"

"Mem$memCmp.exit.loopexit":                       ; preds = %label_3.i.i
  %1 = icmp eq i8 %t22.i.i, %t27.i.i
  %2 = zext i1 %1 to i64
  br label %label_7

label_7:                                          ; preds = %label_6, %"Mem$memCmp.exit.loopexit", %0
  %t13 = phi i64 [ 0, %0 ], [ 1, %label_6 ], [ %2, %"Mem$memCmp.exit.loopexit" ]
  ret i64 %t13
}

; Function Attrs: nounwind
define i64 @"Str$strSlice"(i64 %s, i64 %start, i64 %count) #1 {
label_6:
  %t0.i.i = inttoptr i64 %s to ptr
  %t2.i.i = load i64, ptr %t0.i.i, align 8
  %c1 = icmp slt i64 %start, 0
  %t0.start = tail call i64 @llvm.smin.i64(i64 %start, i64 %t2.i.i)
  %t14 = select i1 %c1, i64 0, i64 %t0.start
  %t15 = sub i64 %t2.i.i, %t14
  %c16 = icmp slt i64 %count, 0
  %t15.count = tail call i64 @llvm.smin.i64(i64 %count, i64 %t15)
  %t29 = select i1 %c16, i64 0, i64 %t15.count
  %t1.i.i = getelementptr i8, ptr %t0.i.i, i64 16
  %t2.i.i2 = load i64, ptr %t1.i.i, align 8
  %imm.i = icmp slt i64 %t2.i.i2, 4096
  br i1 %imm.i, label %axiom_retain.exit, label %chk.i

chk.i:                                            ; preds = %label_6
  %hoff.i = add nsw i64 %t2.i.i2, -16
  %cp.i = inttoptr i64 %hoff.i to ptr
  %c.i = load i64, ptr %cp.i, align 8
  %stat.i = icmp eq i64 %c.i, -1
  br i1 %stat.i, label %axiom_retain.exit, label %bump.i

bump.i:                                           ; preds = %chk.i
  %c1.i = add nuw i64 %c.i, 1
  store i64 %c1.i, ptr %cp.i, align 8
  br label %axiom_retain.exit

axiom_retain.exit:                                ; preds = %label_6, %chk.i, %bump.i
  %t1.i.i4 = getelementptr i8, ptr %t0.i.i, i64 8
  %t2.i.i5 = load i64, ptr %t1.i.i4, align 8
  %t32 = add i64 %t2.i.i5, %t14
  %t0.i.i6 = tail call i64 @axiom_alloc(i64 24)
  %t7.i.i = add i64 %t0.i.i6, -8
  %t8.i.i = inttoptr i64 %t7.i.i to ptr
  %t10.i.i = load i64, ptr %t8.i.i, align 8
  %t11.i.i = lshr i64 %t10.i.i, 1
  %t12.i.i = and i64 %t11.i.i, 16383
  %.t12.i.i = tail call i64 @llvm.umin.i64(i64 %t12.i.i, i64 47)
  %t22.i.i = shl nsw i64 -65536, %.t12.i.i
  %t23.i.i = and i64 %t22.i.i, 262144
  %t24.i.i = xor i64 %t23.i.i, 262144
  %t25.i.i = or i64 %t24.i.i, %t10.i.i
  store i64 %t25.i.i, ptr %t8.i.i, align 8
  %t5.i.i = inttoptr i64 %t0.i.i6 to ptr
  store i64 %t29, ptr %t5.i.i, align 8
  %t6.i.i = getelementptr i8, ptr %t5.i.i, i64 8
  store i64 %t32, ptr %t6.i.i, align 8
  %t6.i5.i = getelementptr i8, ptr %t5.i.i, i64 16
  store i64 %t2.i.i2, ptr %t6.i5.i, align 8
  %imm.i.i = icmp slt i64 %t0.i.i6, 4096
  br i1 %imm.i.i, label %"Str$strWrapOwned.exit", label %chk.i.i

chk.i.i:                                          ; preds = %axiom_retain.exit
  %hoff.i.i = add nsw i64 %t0.i.i6, -16
  %cp.i.i = inttoptr i64 %hoff.i.i to ptr
  %c.i.i = load i64, ptr %cp.i.i, align 8
  %stat.i.i = icmp eq i64 %c.i.i, -1
  br i1 %stat.i.i, label %"Str$strWrapOwned.exit", label %bump.i.i

bump.i.i:                                         ; preds = %chk.i.i
  %c1.i.i = add nuw i64 %c.i.i, 1
  store i64 %c1.i.i, ptr %cp.i.i, align 8
  br label %"Str$strWrapOwned.exit"

"Str$strWrapOwned.exit":                          ; preds = %axiom_retain.exit, %chk.i.i, %bump.i.i
  ret i64 %t0.i.i6
}

; Function Attrs: nounwind
define i64 @"Str$strDup"(i64 %s) #1 {
  %t0.i.i = inttoptr i64 %s to ptr
  %t2.i.i = load i64, ptr %t0.i.i, align 8
  %t0.i = add i64 %t2.i.i, 1
  %t0.i.i1 = tail call i64 @axiom_alloc(i64 %t0.i)
  %imm.i.i = icmp slt i64 %t0.i.i1, 4096
  br i1 %imm.i.i, label %axiom_retain.exit.i, label %chk.i.i

chk.i.i:                                          ; preds = %0
  %hoff.i.i = add nsw i64 %t0.i.i1, -16
  %cp.i.i = inttoptr i64 %hoff.i.i to ptr
  %c.i.i = load i64, ptr %cp.i.i, align 8
  %stat.i.i = icmp eq i64 %c.i.i, -1
  br i1 %stat.i.i, label %axiom_retain.exit.i, label %bump.i.i

bump.i.i:                                         ; preds = %chk.i.i
  %c1.i.i = add nuw i64 %c.i.i, 1
  store i64 %c1.i.i, ptr %cp.i.i, align 8
  br label %axiom_retain.exit.i

axiom_retain.exit.i:                              ; preds = %bump.i.i, %chk.i.i, %0
  %t0.i.i.i = tail call i64 @axiom_alloc(i64 24)
  %t7.i.i.i = add i64 %t0.i.i.i, -8
  %t8.i.i.i = inttoptr i64 %t7.i.i.i to ptr
  %t10.i.i.i = load i64, ptr %t8.i.i.i, align 8
  %t11.i.i.i = lshr i64 %t10.i.i.i, 1
  %t12.i.i.i = and i64 %t11.i.i.i, 16383
  %.t12.i.i.i = tail call i64 @llvm.umin.i64(i64 %t12.i.i.i, i64 47)
  %t22.i.i.i = shl nsw i64 -65536, %.t12.i.i.i
  %t23.i.i.i = and i64 %t22.i.i.i, 262144
  %t24.i.i.i = xor i64 %t23.i.i.i, 262144
  %t25.i.i.i = or i64 %t24.i.i.i, %t10.i.i.i
  store i64 %t25.i.i.i, ptr %t8.i.i.i, align 8
  %t5.i.i.i = inttoptr i64 %t0.i.i.i to ptr
  store i64 %t2.i.i, ptr %t5.i.i.i, align 8
  %t6.i.i.i = getelementptr i8, ptr %t5.i.i.i, i64 8
  store i64 %t0.i.i1, ptr %t6.i.i.i, align 8
  %t6.i5.i.i = getelementptr i8, ptr %t5.i.i.i, i64 16
  store i64 %t0.i.i1, ptr %t6.i5.i.i, align 8
  %imm.i.i.i = icmp slt i64 %t0.i.i.i, 4096
  br i1 %imm.i.i.i, label %"Str$strAlloc.exit", label %chk.i.i.i

chk.i.i.i:                                        ; preds = %axiom_retain.exit.i
  %hoff.i.i.i = add nsw i64 %t0.i.i.i, -16
  %cp.i.i.i = inttoptr i64 %hoff.i.i.i to ptr
  %c.i.i.i = load i64, ptr %cp.i.i.i, align 8
  %stat.i.i.i = icmp eq i64 %c.i.i.i, -1
  br i1 %stat.i.i.i, label %"Str$strAlloc.exit", label %bump.i.i.i

bump.i.i.i:                                       ; preds = %chk.i.i.i
  %c1.i.i.i = add nuw i64 %c.i.i.i, 1
  store i64 %c1.i.i.i, ptr %cp.i.i.i, align 8
  br label %"Str$strAlloc.exit"

"Str$strAlloc.exit":                              ; preds = %axiom_retain.exit.i, %chk.i.i.i, %bump.i.i.i
  %c54.i.i = icmp sgt i64 %t2.i.i, 0
  br i1 %c54.i.i, label %label_2.lr.ph.i.i, label %"Mem$memCopy.exit"

label_2.lr.ph.i.i:                                ; preds = %"Str$strAlloc.exit"
  %t1.i.i5 = getelementptr i8, ptr %t0.i.i, i64 8
  %t2.i.i6 = load i64, ptr %t1.i.i5, align 8
  %t2.i.i3 = load i64, ptr %t6.i.i.i, align 8
  %t10.i.i = inttoptr i64 %t2.i.i6 to ptr
  %t14.i.i = inttoptr i64 %t2.i.i3 to ptr
  br label %label_2.i.i

label_2.i.i:                                      ; preds = %label_2.i.i, %label_2.lr.ph.i.i
  %s.0.05.i.i = phi i64 [ 0, %label_2.lr.ph.i.i ], [ %t18.i.i, %label_2.i.i ]
  %t11.i.i = getelementptr i8, ptr %t10.i.i, i64 %s.0.05.i.i
  %t12.i.i = load i8, ptr %t11.i.i, align 1
  %t15.i.i = getelementptr i8, ptr %t14.i.i, i64 %s.0.05.i.i
  store i8 %t12.i.i, ptr %t15.i.i, align 1
  %t18.i.i = add nuw nsw i64 %s.0.05.i.i, 1
  %exitcond.not.i.i = icmp eq i64 %t18.i.i, %t2.i.i
  br i1 %exitcond.not.i.i, label %"Mem$memCopy.exit", label %label_2.i.i

"Mem$memCopy.exit":                               ; preds = %label_2.i.i, %"Str$strAlloc.exit"
  ret i64 %t0.i.i.i
}

; Function Attrs: nounwind
define i64 @"Str$strConcat"(i64 %a, i64 %b) #1 {
  %t0.i.i = inttoptr i64 %a to ptr
  %t2.i.i = load i64, ptr %t0.i.i, align 8
  %t0.i.i1 = inttoptr i64 %b to ptr
  %t2.i.i2 = load i64, ptr %t0.i.i1, align 8
  %t2 = add i64 %t2.i.i2, %t2.i.i
  %t0.i = add i64 %t2, 1
  %t0.i.i3 = tail call i64 @axiom_alloc(i64 %t0.i)
  %imm.i.i = icmp slt i64 %t0.i.i3, 4096
  br i1 %imm.i.i, label %axiom_retain.exit.i, label %chk.i.i

chk.i.i:                                          ; preds = %0
  %hoff.i.i = add nsw i64 %t0.i.i3, -16
  %cp.i.i = inttoptr i64 %hoff.i.i to ptr
  %c.i.i = load i64, ptr %cp.i.i, align 8
  %stat.i.i = icmp eq i64 %c.i.i, -1
  br i1 %stat.i.i, label %axiom_retain.exit.i, label %bump.i.i

bump.i.i:                                         ; preds = %chk.i.i
  %c1.i.i = add nuw i64 %c.i.i, 1
  store i64 %c1.i.i, ptr %cp.i.i, align 8
  br label %axiom_retain.exit.i

axiom_retain.exit.i:                              ; preds = %bump.i.i, %chk.i.i, %0
  %t0.i.i.i = tail call i64 @axiom_alloc(i64 24)
  %t7.i.i.i = add i64 %t0.i.i.i, -8
  %t8.i.i.i = inttoptr i64 %t7.i.i.i to ptr
  %t10.i.i.i = load i64, ptr %t8.i.i.i, align 8
  %t11.i.i.i = lshr i64 %t10.i.i.i, 1
  %t12.i.i.i = and i64 %t11.i.i.i, 16383
  %.t12.i.i.i = tail call i64 @llvm.umin.i64(i64 %t12.i.i.i, i64 47)
  %t22.i.i.i = shl nsw i64 -65536, %.t12.i.i.i
  %t23.i.i.i = and i64 %t22.i.i.i, 262144
  %t24.i.i.i = xor i64 %t23.i.i.i, 262144
  %t25.i.i.i = or i64 %t24.i.i.i, %t10.i.i.i
  store i64 %t25.i.i.i, ptr %t8.i.i.i, align 8
  %t5.i.i.i = inttoptr i64 %t0.i.i.i to ptr
  store i64 %t2, ptr %t5.i.i.i, align 8
  %t6.i.i.i = getelementptr i8, ptr %t5.i.i.i, i64 8
  store i64 %t0.i.i3, ptr %t6.i.i.i, align 8
  %t6.i5.i.i = getelementptr i8, ptr %t5.i.i.i, i64 16
  store i64 %t0.i.i3, ptr %t6.i5.i.i, align 8
  %imm.i.i.i = icmp slt i64 %t0.i.i.i, 4096
  br i1 %imm.i.i.i, label %"Str$strAlloc.exit", label %chk.i.i.i

chk.i.i.i:                                        ; preds = %axiom_retain.exit.i
  %hoff.i.i.i = add nsw i64 %t0.i.i.i, -16
  %cp.i.i.i = inttoptr i64 %hoff.i.i.i to ptr
  %c.i.i.i = load i64, ptr %cp.i.i.i, align 8
  %stat.i.i.i = icmp eq i64 %c.i.i.i, -1
  br i1 %stat.i.i.i, label %"Str$strAlloc.exit", label %bump.i.i.i

bump.i.i.i:                                       ; preds = %chk.i.i.i
  %c1.i.i.i = add nuw i64 %c.i.i.i, 1
  store i64 %c1.i.i.i, ptr %cp.i.i.i, align 8
  br label %"Str$strAlloc.exit"

"Str$strAlloc.exit":                              ; preds = %axiom_retain.exit.i, %chk.i.i.i, %bump.i.i.i
  %c54.i.i = icmp sgt i64 %t2.i.i, 0
  br i1 %c54.i.i, label %label_2.lr.ph.i.i, label %"Mem$memCopy.exit"

label_2.lr.ph.i.i:                                ; preds = %"Str$strAlloc.exit"
  %t1.i.i7 = getelementptr i8, ptr %t0.i.i, i64 8
  %t2.i.i8 = load i64, ptr %t1.i.i7, align 8
  %t2.i.i5 = load i64, ptr %t6.i.i.i, align 8
  %t10.i.i = inttoptr i64 %t2.i.i8 to ptr
  %t14.i.i = inttoptr i64 %t2.i.i5 to ptr
  br label %label_2.i.i

label_2.i.i:                                      ; preds = %label_2.i.i, %label_2.lr.ph.i.i
  %s.0.05.i.i = phi i64 [ 0, %label_2.lr.ph.i.i ], [ %t18.i.i, %label_2.i.i ]
  %t11.i.i = getelementptr i8, ptr %t10.i.i, i64 %s.0.05.i.i
  %t12.i.i = load i8, ptr %t11.i.i, align 1
  %t15.i.i = getelementptr i8, ptr %t14.i.i, i64 %s.0.05.i.i
  store i8 %t12.i.i, ptr %t15.i.i, align 1
  %t18.i.i = add nuw nsw i64 %s.0.05.i.i, 1
  %exitcond.not.i.i = icmp eq i64 %t18.i.i, %t2.i.i
  br i1 %exitcond.not.i.i, label %"Mem$memCopy.exit", label %label_2.i.i

"Mem$memCopy.exit":                               ; preds = %label_2.i.i, %"Str$strAlloc.exit"
  %c54.i.i15 = icmp sgt i64 %t2.i.i2, 0
  br i1 %c54.i.i15, label %label_2.lr.ph.i.i16, label %"Mem$memCopy.exit26"

label_2.lr.ph.i.i16:                              ; preds = %"Mem$memCopy.exit"
  %t1.i.i13 = getelementptr i8, ptr %t0.i.i1, i64 8
  %t2.i.i14 = load i64, ptr %t1.i.i13, align 8
  %t2.i.i11 = load i64, ptr %t6.i.i.i, align 8
  %t8 = add i64 %t2.i.i11, %t2.i.i
  %t10.i.i17 = inttoptr i64 %t2.i.i14 to ptr
  %t14.i.i18 = inttoptr i64 %t8 to ptr
  br label %label_2.i.i19

label_2.i.i19:                                    ; preds = %label_2.i.i19, %label_2.lr.ph.i.i16
  %s.0.05.i.i20 = phi i64 [ 0, %label_2.lr.ph.i.i16 ], [ %t18.i.i24, %label_2.i.i19 ]
  %t11.i.i21 = getelementptr i8, ptr %t10.i.i17, i64 %s.0.05.i.i20
  %t12.i.i22 = load i8, ptr %t11.i.i21, align 1
  %t15.i.i23 = getelementptr i8, ptr %t14.i.i18, i64 %s.0.05.i.i20
  store i8 %t12.i.i22, ptr %t15.i.i23, align 1
  %t18.i.i24 = add nuw nsw i64 %s.0.05.i.i20, 1
  %exitcond.not.i.i25 = icmp eq i64 %t18.i.i24, %t2.i.i2
  br i1 %exitcond.not.i.i25, label %"Mem$memCopy.exit26", label %label_2.i.i19

"Mem$memCopy.exit26":                             ; preds = %label_2.i.i19, %"Mem$memCopy.exit"
  ret i64 %t0.i.i.i
}

define i64 @"Str$strFindByte"(i64 %s, i64 %byte, i64 %from) #0 {
  %imm.i = icmp slt i64 %s, 4096
  br i1 %imm.i, label %axiom_retain.exit, label %chk.i

chk.i:                                            ; preds = %0
  %hoff.i = add nsw i64 %s, -16
  %cp.i = inttoptr i64 %hoff.i to ptr
  %c.i = load i64, ptr %cp.i, align 8
  %stat.i = icmp eq i64 %c.i, -1
  br i1 %stat.i, label %axiom_retain.exit, label %bump.i

bump.i:                                           ; preds = %chk.i
  %c1.i = add nuw i64 %c.i, 1
  store i64 %c1.i, ptr %cp.i, align 8
  br label %axiom_retain.exit

axiom_retain.exit:                                ; preds = %0, %chk.i, %bump.i
  %t0.i.i = inttoptr i64 %s to ptr
  %t2.i.i = load i64, ptr %t0.i.i, align 8
  %c7.not9 = icmp slt i64 %from, %t2.i.i
  br i1 %c7.not9, label %label_11.lr.ph, label %label_12

label_11.lr.ph:                                   ; preds = %axiom_retain.exit
  %t1.i.i.i = getelementptr i8, ptr %t0.i.i, i64 8
  br label %label_11

label_11:                                         ; preds = %label_11.lr.ph, %label_22
  %s.3.010 = phi i64 [ %from, %label_11.lr.ph ], [ %t28, %label_22 ]
  %c0.i = icmp slt i64 %s.3.010, 0
  br i1 %c0.i, label %"Str$strByte.exit", label %label_11.i

label_11.i:                                       ; preds = %label_11
  %t2.i.i2.i = load i64, ptr %t1.i.i.i, align 8
  %t14.i = inttoptr i64 %t2.i.i2.i to ptr
  %t15.i = getelementptr i8, ptr %t14.i, i64 %s.3.010
  %t16.i = load i8, ptr %t15.i, align 1
  %t17.i = zext i8 %t16.i to i64
  br label %"Str$strByte.exit"

"Str$strByte.exit":                               ; preds = %label_11, %label_11.i
  %t19.i = phi i64 [ 0, %label_11 ], [ %t17.i, %label_11.i ]
  %c18 = icmp eq i64 %t19.i, %byte
  br i1 %c18, label %label_12, label %label_22

label_22:                                         ; preds = %"Str$strByte.exit"
  %t28 = add nsw i64 %s.3.010, 1
  %exitcond.not = icmp eq i64 %t28, %t2.i.i
  br i1 %exitcond.not, label %label_12, label %label_11

label_12:                                         ; preds = %label_22, %"Str$strByte.exit", %axiom_retain.exit
  %t30 = phi i64 [ -1, %axiom_retain.exit ], [ -1, %label_22 ], [ %s.3.010, %"Str$strByte.exit" ]
  tail call void @axiom_release(i64 %s)
  ret i64 %t30
}

; Function Attrs: nofree norecurse nosync nounwind memory(read, inaccessiblemem: none, target_mem0: none, target_mem1: none)
define range(i64 0, 2) i64 @"Str$strStartsWith"(i64 %s, i64 %prefix) #5 {
  %t0.i.i = inttoptr i64 %prefix to ptr
  %t2.i.i = load i64, ptr %t0.i.i, align 8
  %t0.i.i1 = inttoptr i64 %s to ptr
  %t2.i.i2 = load i64, ptr %t0.i.i1, align 8
  %c2 = icmp sgt i64 %t2.i.i, %t2.i.i2
  br i1 %c2, label %label_7, label %label_6

label_6:                                          ; preds = %0
  %c65.i.i = icmp sgt i64 %t2.i.i, 0
  br i1 %c65.i.i, label %label_3.lr.ph.i.i, label %label_7

label_3.lr.ph.i.i:                                ; preds = %label_6
  %t1.i.i6 = getelementptr i8, ptr %t0.i.i, i64 8
  %t2.i.i7 = load i64, ptr %t1.i.i6, align 8
  %t1.i.i = getelementptr i8, ptr %t0.i.i1, i64 8
  %t2.i.i4 = load i64, ptr %t1.i.i, align 8
  %t20.i.i = inttoptr i64 %t2.i.i4 to ptr
  %t25.i.i = inttoptr i64 %t2.i.i7 to ptr
  br label %label_3.i.i

label_3.i.i:                                      ; preds = %label_3.i.i, %label_3.lr.ph.i.i
  %s.0.06.i.i = phi i64 [ 0, %label_3.lr.ph.i.i ], [ %t31.i.i, %label_3.i.i ]
  %t21.i.i = getelementptr i8, ptr %t20.i.i, i64 %s.0.06.i.i
  %t22.i.i = load i8, ptr %t21.i.i, align 1
  %t26.i.i = getelementptr i8, ptr %t25.i.i, i64 %s.0.06.i.i
  %t27.i.i = load i8, ptr %t26.i.i, align 1
  %t31.i.i = add nuw nsw i64 %s.0.06.i.i, 1
  %c6.i.i = icmp slt i64 %t31.i.i, %t2.i.i
  %c13.i.i = icmp eq i8 %t22.i.i, %t27.i.i
  %narrow.i.i = select i1 %c6.i.i, i1 %c13.i.i, i1 false
  br i1 %narrow.i.i, label %label_3.i.i, label %"Mem$memCmp.exit.loopexit"

"Mem$memCmp.exit.loopexit":                       ; preds = %label_3.i.i
  %1 = icmp eq i8 %t22.i.i, %t27.i.i
  %2 = zext i1 %1 to i64
  br label %label_7

label_7:                                          ; preds = %label_6, %"Mem$memCmp.exit.loopexit", %0
  %t13 = phi i64 [ 0, %0 ], [ 1, %label_6 ], [ %2, %"Mem$memCmp.exit.loopexit" ]
  ret i64 %t13
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(none)
define range(i64 0, 2) i64 @"Str$strIsDigit"(i64 %ch) #6 {
label_5:
  %0 = add i64 %ch, -48
  %narrow = icmp ult i64 %0, 10
  %t8 = zext i1 %narrow to i64
  ret i64 %t8
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(none)
define range(i64 0, 2) i64 @"Str$strIsAlpha"(i64 %ch) #6 {
  %c0 = icmp sgt i64 %ch, 64
  br i1 %c0, label %label_3, label %label_5

label_3:                                          ; preds = %0
  %c6 = icmp slt i64 %ch, 91
  br i1 %c6, label %label_5, label %label_10

label_10:                                         ; preds = %label_3
  %1 = add nsw i64 %ch, -97
  %narrow = icmp ult i64 %1, 26
  %t20 = zext i1 %narrow to i64
  br label %label_5

label_5:                                          ; preds = %0, %label_10, %label_3
  %t22 = phi i64 [ 1, %label_3 ], [ %t20, %label_10 ], [ 0, %0 ]
  ret i64 %t22
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(none)
define range(i64 0, 2) i64 @"Str$strIsSpace"(i64 %ch) #6 {
  switch i64 %ch, label %label_10 [
    i64 32, label %label_5
    i64 10, label %label_5
  ]

label_10:                                         ; preds = %0
  %1 = and i64 %ch, -5
  %narrow = icmp eq i64 %1, 9
  %t25 = zext i1 %narrow to i64
  br label %label_5

label_5:                                          ; preds = %0, %0, %label_10
  %t27 = phi i64 [ 1, %0 ], [ %t25, %label_10 ], [ 1, %0 ]
  ret i64 %t27
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(none)
define i64 @"Str$strHexVal"(i64 %ch) #6 {
label_5:
  %0 = add i64 %ch, -48
  %narrow = icmp ult i64 %0, 10
  br i1 %narrow, label %label_14, label %label_13

label_13:                                         ; preds = %label_5
  %1 = add i64 %ch, -97
  %narrow1 = icmp ult i64 %1, 6
  br i1 %narrow1, label %label_28, label %label_29

label_28:                                         ; preds = %label_13
  %t32 = add nsw i64 %ch, -87
  br label %label_14

label_29:                                         ; preds = %label_13
  %2 = add i64 %ch, -65
  %narrow2 = icmp ult i64 %2, 6
  %t49 = add i64 %ch, -55
  %t51 = select i1 %narrow2, i64 %t49, i64 -1
  br label %label_14

label_14:                                         ; preds = %label_5, %label_28, %label_29
  %t53 = phi i64 [ %t51, %label_29 ], [ %t32, %label_28 ], [ %0, %label_5 ]
  ret i64 %t53
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(none)
define range(i64 0, 2) i64 @"Str$strIsHexDigit"(i64 %ch) #6 {
  %1 = add i64 %ch, -48
  %narrow.i = icmp ult i64 %1, 10
  br i1 %narrow.i, label %"Str$strHexVal.exit", label %label_13.i

label_13.i:                                       ; preds = %0
  %2 = add i64 %ch, -97
  %narrow1.i = icmp ult i64 %2, 6
  br i1 %narrow1.i, label %label_28.i, label %label_29.i

label_28.i:                                       ; preds = %label_13.i
  %t32.i = add nsw i64 %ch, -87
  br label %"Str$strHexVal.exit"

label_29.i:                                       ; preds = %label_13.i
  %3 = add i64 %ch, -65
  %narrow2.i = icmp ult i64 %3, 6
  %t49.i = add i64 %ch, -55
  %t51.i = select i1 %narrow2.i, i64 %t49.i, i64 -1
  br label %"Str$strHexVal.exit"

"Str$strHexVal.exit":                             ; preds = %0, %label_28.i, %label_29.i
  %t53.i = phi i64 [ %t51.i, %label_29.i ], [ %t32.i, %label_28.i ], [ %1, %0 ]
  %c1 = icmp sgt i64 %t53.i, -1
  %t2 = zext i1 %c1 to i64
  ret i64 %t2
}

define i64 @"Str$strSplit"(i64 %s, i64 %byte) #0 {
  %t0.i.i.i.i = tail call i64 @axiom_alloc(i64 32)
  %t7.i.i.i.i = add i64 %t0.i.i.i.i, -8
  %t8.i.i.i.i = inttoptr i64 %t7.i.i.i.i to ptr
  %t10.i.i.i.i = load i64, ptr %t8.i.i.i.i, align 8
  %t11.i.i.i.i = lshr i64 %t10.i.i.i.i, 1
  %t12.i.i.i.i = and i64 %t11.i.i.i.i, 16383
  %.t12.i.i.i.i = tail call i64 @llvm.umin.i64(i64 %t12.i.i.i.i, i64 47)
  %t22.i.i.i.i = shl nsw i64 -65536, %.t12.i.i.i.i
  %t23.i.i.i.i = and i64 %t22.i.i.i.i, 262144
  %t24.i.i.i.i = xor i64 %t23.i.i.i.i, 262144
  %t25.i.i.i.i = or i64 %t24.i.i.i.i, %t10.i.i.i.i
  store i64 %t25.i.i.i.i, ptr %t8.i.i.i.i, align 8
  %t0.i1.i.i.i = tail call i64 @axiom_alloc(i64 64)
  %imm.i.i.i.i = icmp slt i64 %t0.i.i.i.i, 4096
  br i1 %imm.i.i.i.i, label %axiom_retain.exit.i.i.i, label %chk.i.i.i.i

chk.i.i.i.i:                                      ; preds = %0
  %hoff.i.i.i.i = add nsw i64 %t0.i.i.i.i, -16
  %cp.i.i.i.i = inttoptr i64 %hoff.i.i.i.i to ptr
  %c.i.i.i.i = load i64, ptr %cp.i.i.i.i, align 8
  %stat.i.i.i.i = icmp eq i64 %c.i.i.i.i, -1
  br i1 %stat.i.i.i.i, label %axiom_retain.exit.i.i.i, label %bump.i.i.i.i

bump.i.i.i.i:                                     ; preds = %chk.i.i.i.i
  %c1.i.i.i.i = add nuw i64 %c.i.i.i.i, 1
  store i64 %c1.i.i.i.i, ptr %cp.i.i.i.i, align 8
  br label %axiom_retain.exit.i.i.i

axiom_retain.exit.i.i.i:                          ; preds = %bump.i.i.i.i, %chk.i.i.i.i, %0
  %imm.i2.i.i.i = icmp slt i64 %t0.i1.i.i.i, 4096
  br i1 %imm.i2.i.i.i, label %"Vec$vecNew.exit", label %chk.i3.i.i.i

chk.i3.i.i.i:                                     ; preds = %axiom_retain.exit.i.i.i
  %hoff.i4.i.i.i = add nsw i64 %t0.i1.i.i.i, -16
  %cp.i5.i.i.i = inttoptr i64 %hoff.i4.i.i.i to ptr
  %c.i6.i.i.i = load i64, ptr %cp.i5.i.i.i, align 8
  %stat.i7.i.i.i = icmp eq i64 %c.i6.i.i.i, -1
  br i1 %stat.i7.i.i.i, label %"Vec$vecNew.exit", label %bump.i8.i.i.i

bump.i8.i.i.i:                                    ; preds = %chk.i3.i.i.i
  %c1.i9.i.i.i = add nuw i64 %c.i6.i.i.i, 1
  store i64 %c1.i9.i.i.i, ptr %cp.i5.i.i.i, align 8
  br label %"Vec$vecNew.exit"

"Vec$vecNew.exit":                                ; preds = %axiom_retain.exit.i.i.i, %chk.i3.i.i.i, %bump.i8.i.i.i
  %t5.i12.i.i.i = inttoptr i64 %t0.i.i.i.i to ptr
  store i64 0, ptr %t5.i12.i.i.i, align 8
  %t6.i.i.i.i = getelementptr i8, ptr %t5.i12.i.i.i, i64 8
  store i64 8, ptr %t6.i.i.i.i, align 8
  %t6.i16.i.i.i = getelementptr i8, ptr %t5.i12.i.i.i, i64 16
  store i64 %t0.i1.i.i.i, ptr %t6.i16.i.i.i, align 8
  %t6.i19.i.i.i = getelementptr i8, ptr %t5.i12.i.i.i, i64 24
  store i64 0, ptr %t6.i19.i.i.i, align 8
  %t1 = tail call i64 @"Str$strSplitFrom"(i64 %s, i64 %byte, i64 0, i64 %t0.i.i.i.i)
  ret i64 %t0.i.i.i.i
}

define noundef i64 @"Str$strSplitFrom"(i64 %s, i64 %byte, i64 %from, i64 %out) #0 {
  %imm.i = icmp slt i64 %s, 4096
  br i1 %imm.i, label %axiom_retain.exit, label %chk.i

chk.i:                                            ; preds = %0
  %hoff.i = add nsw i64 %s, -16
  %cp.i = inttoptr i64 %hoff.i to ptr
  %c.i = load i64, ptr %cp.i, align 8
  %stat.i = icmp eq i64 %c.i, -1
  br i1 %stat.i, label %axiom_retain.exit, label %bump.i

bump.i:                                           ; preds = %chk.i
  %c1.i = add nuw i64 %c.i, 1
  store i64 %c1.i, ptr %cp.i, align 8
  br label %axiom_retain.exit

axiom_retain.exit:                                ; preds = %0, %chk.i, %bump.i
  %t0.i.i.i = inttoptr i64 %s to ptr
  %hoff.i.i = add nsw i64 %s, -16
  %cp.i.i = inttoptr i64 %hoff.i.i to ptr
  %t1.i.i.i.i = getelementptr i8, ptr %t0.i.i.i, i64 8
  %t1.i.i.i = getelementptr i8, ptr %t0.i.i.i, i64 16
  %t1.i.i4.i = getelementptr i8, ptr %t0.i.i.i, i64 8
  br label %label_0

label_0:                                          ; preds = %"Str$strSlice.exit", %axiom_retain.exit
  %s.3.0 = phi i64 [ %from, %axiom_retain.exit ], [ %t33, %"Str$strSlice.exit" ]
  br i1 %imm.i, label %axiom_retain.exit.i, label %chk.i.i

chk.i.i:                                          ; preds = %label_0
  %c.i.i = load i64, ptr %cp.i.i, align 8
  %stat.i.i = icmp eq i64 %c.i.i, -1
  br i1 %stat.i.i, label %axiom_retain.exit.i, label %bump.i.i

bump.i.i:                                         ; preds = %chk.i.i
  %c1.i.i = add nuw i64 %c.i.i, 1
  store i64 %c1.i.i, ptr %cp.i.i, align 8
  br label %axiom_retain.exit.i

axiom_retain.exit.i:                              ; preds = %bump.i.i, %chk.i.i, %label_0
  %t2.i.i.i = load i64, ptr %t0.i.i.i, align 8
  %c7.not9.i = icmp slt i64 %s.3.0, %t2.i.i.i
  br i1 %c7.not9.i, label %label_11.i, label %"Str$strFindByte.exit"

label_11.i:                                       ; preds = %axiom_retain.exit.i, %label_22.i
  %s.3.010.i = phi i64 [ %t28.i, %label_22.i ], [ %s.3.0, %axiom_retain.exit.i ]
  %c0.i.i = icmp slt i64 %s.3.010.i, 0
  br i1 %c0.i.i, label %"Str$strByte.exit.i", label %label_11.i.i

label_11.i.i:                                     ; preds = %label_11.i
  %t2.i.i2.i.i = load i64, ptr %t1.i.i.i.i, align 8
  %t14.i.i = inttoptr i64 %t2.i.i2.i.i to ptr
  %t15.i.i = getelementptr i8, ptr %t14.i.i, i64 %s.3.010.i
  %t16.i.i = load i8, ptr %t15.i.i, align 1
  %t17.i.i = zext i8 %t16.i.i to i64
  br label %"Str$strByte.exit.i"

"Str$strByte.exit.i":                             ; preds = %label_11.i.i, %label_11.i
  %t19.i.i = phi i64 [ 0, %label_11.i ], [ %t17.i.i, %label_11.i.i ]
  %c18.i = icmp eq i64 %t19.i.i, %byte
  br i1 %c18.i, label %"Str$strFindByte.exit", label %label_22.i

label_22.i:                                       ; preds = %"Str$strByte.exit.i"
  %t28.i = add nsw i64 %s.3.010.i, 1
  %exitcond.not.i = icmp eq i64 %t28.i, %t2.i.i.i
  br i1 %exitcond.not.i, label %"Str$strFindByte.exit", label %label_11.i

"Str$strFindByte.exit":                           ; preds = %"Str$strByte.exit.i", %label_22.i, %axiom_retain.exit.i
  %t30.i = phi i64 [ -1, %axiom_retain.exit.i ], [ -1, %label_22.i ], [ %s.3.010.i, %"Str$strByte.exit.i" ]
  tail call void @axiom_release(i64 %s)
  %c9 = icmp slt i64 %t30.i, 0
  br i1 %c9, label %label_12, label %label_14

label_12:                                         ; preds = %"Str$strFindByte.exit"
  %t2.i.i = load i64, ptr %t0.i.i.i, align 8
  br label %label_14

label_14:                                         ; preds = %"Str$strFindByte.exit", %label_12
  %t17 = phi i64 [ %t2.i.i, %label_12 ], [ %t30.i, %"Str$strFindByte.exit" ]
  %t22 = sub i64 %t17, %s.3.0
  %t2.i.i.i10 = load i64, ptr %t0.i.i.i, align 8
  %c1.i11 = icmp slt i64 %s.3.0, 0
  %t0.start.i = tail call i64 @llvm.smin.i64(i64 %s.3.0, i64 %t2.i.i.i10)
  %t14.i = select i1 %c1.i11, i64 0, i64 %t0.start.i
  %t15.i = sub i64 %t2.i.i.i10, %t14.i
  %c16.i = icmp slt i64 %t22, 0
  %t15.count.i = tail call i64 @llvm.smin.i64(i64 %t22, i64 %t15.i)
  %t29.i = select i1 %c16.i, i64 0, i64 %t15.count.i
  %t2.i.i2.i = load i64, ptr %t1.i.i.i, align 8
  %imm.i.i12 = icmp slt i64 %t2.i.i2.i, 4096
  br i1 %imm.i.i12, label %axiom_retain.exit.i20, label %chk.i.i13

chk.i.i13:                                        ; preds = %label_14
  %hoff.i.i14 = add nsw i64 %t2.i.i2.i, -16
  %cp.i.i15 = inttoptr i64 %hoff.i.i14 to ptr
  %c.i.i16 = load i64, ptr %cp.i.i15, align 8
  %stat.i.i17 = icmp eq i64 %c.i.i16, -1
  br i1 %stat.i.i17, label %axiom_retain.exit.i20, label %bump.i.i18

bump.i.i18:                                       ; preds = %chk.i.i13
  %c1.i.i19 = add nuw i64 %c.i.i16, 1
  store i64 %c1.i.i19, ptr %cp.i.i15, align 8
  br label %axiom_retain.exit.i20

axiom_retain.exit.i20:                            ; preds = %bump.i.i18, %chk.i.i13, %label_14
  %t2.i.i5.i = load i64, ptr %t1.i.i4.i, align 8
  %t32.i = add i64 %t2.i.i5.i, %t14.i
  %t0.i.i6.i = tail call i64 @axiom_alloc(i64 24)
  %t7.i.i.i = add i64 %t0.i.i6.i, -8
  %t8.i.i.i = inttoptr i64 %t7.i.i.i to ptr
  %t10.i.i.i = load i64, ptr %t8.i.i.i, align 8
  %t11.i.i.i = lshr i64 %t10.i.i.i, 1
  %t12.i.i.i = and i64 %t11.i.i.i, 16383
  %.t12.i.i.i = tail call i64 @llvm.umin.i64(i64 %t12.i.i.i, i64 47)
  %t22.i.i.i = shl nsw i64 -65536, %.t12.i.i.i
  %t23.i.i.i = and i64 %t22.i.i.i, 262144
  %t24.i.i.i = xor i64 %t23.i.i.i, 262144
  %t25.i.i.i = or i64 %t24.i.i.i, %t10.i.i.i
  store i64 %t25.i.i.i, ptr %t8.i.i.i, align 8
  %t5.i.i.i = inttoptr i64 %t0.i.i6.i to ptr
  store i64 %t29.i, ptr %t5.i.i.i, align 8
  %t6.i.i.i = getelementptr i8, ptr %t5.i.i.i, i64 8
  store i64 %t32.i, ptr %t6.i.i.i, align 8
  %t6.i5.i.i = getelementptr i8, ptr %t5.i.i.i, i64 16
  store i64 %t2.i.i2.i, ptr %t6.i5.i.i, align 8
  %imm.i.i.i = icmp slt i64 %t0.i.i6.i, 4096
  br i1 %imm.i.i.i, label %"Str$strSlice.exit", label %chk.i.i.i

chk.i.i.i:                                        ; preds = %axiom_retain.exit.i20
  %hoff.i.i.i = add nsw i64 %t0.i.i6.i, -16
  %cp.i.i.i = inttoptr i64 %hoff.i.i.i to ptr
  %c.i.i.i = load i64, ptr %cp.i.i.i, align 8
  %stat.i.i.i = icmp eq i64 %c.i.i.i, -1
  br i1 %stat.i.i.i, label %"Str$strSlice.exit", label %bump.i.i.i

bump.i.i.i:                                       ; preds = %chk.i.i.i
  %c1.i.i.i = add nuw i64 %c.i.i.i, 1
  store i64 %c1.i.i.i, ptr %cp.i.i.i, align 8
  br label %"Str$strSlice.exit"

"Str$strSlice.exit":                              ; preds = %axiom_retain.exit.i20, %chk.i.i.i, %bump.i.i.i
  %t24 = tail call i64 @"Vec$vecPush"(i64 %out, i64 %t0.i.i6.i, i64 0)
  %t33 = add i64 %t17, 1
  br i1 %c9, label %label_30, label %label_0

label_30:                                         ; preds = %"Str$strSlice.exit"
  ret i64 0
}

; Function Attrs: nounwind
define i64 @"Str$strFromByte"(i64 %b) #1 {
  %t0.i.i = tail call i64 @axiom_alloc(i64 2)
  %imm.i.i = icmp slt i64 %t0.i.i, 4096
  br i1 %imm.i.i, label %axiom_retain.exit.i, label %chk.i.i

chk.i.i:                                          ; preds = %0
  %hoff.i.i = add nsw i64 %t0.i.i, -16
  %cp.i.i = inttoptr i64 %hoff.i.i to ptr
  %c.i.i = load i64, ptr %cp.i.i, align 8
  %stat.i.i = icmp eq i64 %c.i.i, -1
  br i1 %stat.i.i, label %axiom_retain.exit.i, label %bump.i.i

bump.i.i:                                         ; preds = %chk.i.i
  %c1.i.i = add nuw i64 %c.i.i, 1
  store i64 %c1.i.i, ptr %cp.i.i, align 8
  br label %axiom_retain.exit.i

axiom_retain.exit.i:                              ; preds = %bump.i.i, %chk.i.i, %0
  %t0.i.i.i = tail call i64 @axiom_alloc(i64 24)
  %t7.i.i.i = add i64 %t0.i.i.i, -8
  %t8.i.i.i = inttoptr i64 %t7.i.i.i to ptr
  %t10.i.i.i = load i64, ptr %t8.i.i.i, align 8
  %t11.i.i.i = lshr i64 %t10.i.i.i, 1
  %t12.i.i.i = and i64 %t11.i.i.i, 16383
  %.t12.i.i.i = tail call i64 @llvm.umin.i64(i64 %t12.i.i.i, i64 47)
  %t22.i.i.i = shl nsw i64 -65536, %.t12.i.i.i
  %t23.i.i.i = and i64 %t22.i.i.i, 262144
  %t24.i.i.i = xor i64 %t23.i.i.i, 262144
  %t25.i.i.i = or i64 %t24.i.i.i, %t10.i.i.i
  store i64 %t25.i.i.i, ptr %t8.i.i.i, align 8
  %t5.i.i.i = inttoptr i64 %t0.i.i.i to ptr
  store i64 1, ptr %t5.i.i.i, align 8
  %t6.i.i.i = getelementptr i8, ptr %t5.i.i.i, i64 8
  store i64 %t0.i.i, ptr %t6.i.i.i, align 8
  %t6.i5.i.i = getelementptr i8, ptr %t5.i.i.i, i64 16
  store i64 %t0.i.i, ptr %t6.i5.i.i, align 8
  %imm.i.i.i = icmp slt i64 %t0.i.i.i, 4096
  br i1 %imm.i.i.i, label %"Str$strAlloc.exit", label %chk.i.i.i

chk.i.i.i:                                        ; preds = %axiom_retain.exit.i
  %hoff.i.i.i = add nsw i64 %t0.i.i.i, -16
  %cp.i.i.i = inttoptr i64 %hoff.i.i.i to ptr
  %c.i.i.i = load i64, ptr %cp.i.i.i, align 8
  %stat.i.i.i = icmp eq i64 %c.i.i.i, -1
  br i1 %stat.i.i.i, label %"Str$strAlloc.exit", label %bump.i.i.i

bump.i.i.i:                                       ; preds = %chk.i.i.i
  %c1.i.i.i = add nuw i64 %c.i.i.i, 1
  store i64 %c1.i.i.i, ptr %cp.i.i.i, align 8
  br label %"Str$strAlloc.exit"

"Str$strAlloc.exit":                              ; preds = %axiom_retain.exit.i, %chk.i.i.i, %bump.i.i.i
  %t2.i.i = load i64, ptr %t6.i.i.i, align 8
  %t2 = inttoptr i64 %t2.i.i to ptr
  %t4 = trunc i64 %b to i8
  store i8 %t4, ptr %t2, align 1
  ret i64 %t0.i.i.i
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(none)
define range(i64 0, 2) i64 @"Fmt$intIsMostNegative"(i64 %n) #6 {
label_5:
  %narrow = icmp eq i64 %n, -9223372036854775808
  %t11 = zext i1 %narrow to i64
  ret i64 %t11
}

; Function Attrs: nofree nosync nounwind memory(none)
define i64 @"Fmt$fmtIntWidth"(i64 %n) #11 {
  br label %tailrecurse

tailrecurse:                                      ; preds = %label_4.sink.split, %0
  %accumulator.tr = phi i64 [ 0, %0 ], [ %t13, %label_4.sink.split ]
  %n.tr = phi i64 [ %n, %0 ], [ %t11.sink, %label_4.sink.split ]
  %narrow.i.not = icmp eq i64 %n.tr, -9223372036854775808
  br i1 %narrow.i.not, label %label_4, label %label_3

label_3:                                          ; preds = %tailrecurse
  %c5 = icmp slt i64 %n.tr, 0
  br i1 %c5, label %label_8, label %label_9

label_8:                                          ; preds = %label_3
  %t11 = sub nsw i64 0, %n.tr
  br label %label_4.sink.split

label_9:                                          ; preds = %label_3
  %c14 = icmp slt i64 %n.tr, 10
  br i1 %c14, label %label_4, label %divok_22

divok_22:                                         ; preds = %label_9
  %t23 = udiv i64 %n.tr, 10
  br label %label_4.sink.split

label_4.sink.split:                               ; preds = %divok_22, %label_8
  %t11.sink = phi i64 [ %t11, %label_8 ], [ %t23, %divok_22 ]
  %t13 = add i64 %accumulator.tr, 1
  br label %tailrecurse

label_4:                                          ; preds = %label_9, %tailrecurse
  %t28 = phi i64 [ 20, %tailrecurse ], [ 1, %label_9 ]
  %accumulator.ret.tr = add i64 %accumulator.tr, %t28
  ret i64 %accumulator.ret.tr
}

define i64 @"Fmt$fmtInt"(i64 %n) #0 {
  %narrow.i.not = icmp eq i64 %n, -9223372036854775808
  br i1 %narrow.i.not, label %label_4, label %label_3

label_3:                                          ; preds = %0
  %c6 = icmp slt i64 %n, 0
  br i1 %c6, label %label_9, label %label_10

label_9:                                          ; preds = %label_3
  %t13 = sub nsw i64 0, %n
  %t14 = tail call i64 @"Fmt$fmtNat"(i64 %t13)
  %t15 = tail call i64 @"Str$strConcat"(i64 ptrtoint (ptr getelementptr inbounds nuw (i8, ptr @strhdr_1, i64 16) to i64), i64 %t14)
  tail call void @axiom_release(i64 ptrtoint (ptr getelementptr inbounds nuw (i8, ptr @strhdr_1, i64 16) to i64))
  tail call void @axiom_release(i64 %t14)
  br label %label_4

label_10:                                         ; preds = %label_3
  %t16 = tail call i64 @"Fmt$fmtNat"(i64 %n)
  br label %label_4

label_4:                                          ; preds = %0, %label_9, %label_10
  %t18 = phi i64 [ %t16, %label_10 ], [ %t15, %label_9 ], [ ptrtoint (ptr getelementptr inbounds nuw (i8, ptr @strhdr_0, i64 16) to i64), %0 ]
  ret i64 %t18
}

; Function Attrs: nounwind
define i64 @"Fmt$fmtNat"(i64 %n) #1 {
  %t0 = tail call i64 @"Fmt$fmtIntWidth"(i64 %n)
  %t0.i = add i64 %t0, 1
  %t0.i.i = tail call i64 @axiom_alloc(i64 %t0.i)
  %imm.i.i = icmp slt i64 %t0.i.i, 4096
  br i1 %imm.i.i, label %axiom_retain.exit.i, label %chk.i.i

chk.i.i:                                          ; preds = %0
  %hoff.i.i = add nsw i64 %t0.i.i, -16
  %cp.i.i = inttoptr i64 %hoff.i.i to ptr
  %c.i.i = load i64, ptr %cp.i.i, align 8
  %stat.i.i = icmp eq i64 %c.i.i, -1
  br i1 %stat.i.i, label %axiom_retain.exit.i, label %bump.i.i

bump.i.i:                                         ; preds = %chk.i.i
  %c1.i.i = add nuw i64 %c.i.i, 1
  store i64 %c1.i.i, ptr %cp.i.i, align 8
  br label %axiom_retain.exit.i

axiom_retain.exit.i:                              ; preds = %bump.i.i, %chk.i.i, %0
  %t0.i.i.i = tail call i64 @axiom_alloc(i64 24)
  %t7.i.i.i = add i64 %t0.i.i.i, -8
  %t8.i.i.i = inttoptr i64 %t7.i.i.i to ptr
  %t10.i.i.i = load i64, ptr %t8.i.i.i, align 8
  %t11.i.i.i = lshr i64 %t10.i.i.i, 1
  %t12.i.i.i = and i64 %t11.i.i.i, 16383
  %.t12.i.i.i = tail call i64 @llvm.umin.i64(i64 %t12.i.i.i, i64 47)
  %t22.i.i.i = shl nsw i64 -65536, %.t12.i.i.i
  %t23.i.i.i = and i64 %t22.i.i.i, 262144
  %t24.i.i.i = xor i64 %t23.i.i.i, 262144
  %t25.i.i.i = or i64 %t24.i.i.i, %t10.i.i.i
  store i64 %t25.i.i.i, ptr %t8.i.i.i, align 8
  %t5.i.i.i = inttoptr i64 %t0.i.i.i to ptr
  store i64 %t0, ptr %t5.i.i.i, align 8
  %t6.i.i.i = getelementptr i8, ptr %t5.i.i.i, i64 8
  store i64 %t0.i.i, ptr %t6.i.i.i, align 8
  %t6.i5.i.i = getelementptr i8, ptr %t5.i.i.i, i64 16
  store i64 %t0.i.i, ptr %t6.i5.i.i, align 8
  %imm.i.i.i = icmp slt i64 %t0.i.i.i, 4096
  br i1 %imm.i.i.i, label %"Str$strAlloc.exit", label %chk.i.i.i

chk.i.i.i:                                        ; preds = %axiom_retain.exit.i
  %hoff.i.i.i = add nsw i64 %t0.i.i.i, -16
  %cp.i.i.i = inttoptr i64 %hoff.i.i.i to ptr
  %c.i.i.i = load i64, ptr %cp.i.i.i, align 8
  %stat.i.i.i = icmp eq i64 %c.i.i.i, -1
  br i1 %stat.i.i.i, label %"Str$strAlloc.exit", label %bump.i.i.i

bump.i.i.i:                                       ; preds = %chk.i.i.i
  %c1.i.i.i = add nuw i64 %c.i.i.i, 1
  store i64 %c1.i.i.i, ptr %cp.i.i.i, align 8
  br label %"Str$strAlloc.exit"

"Str$strAlloc.exit":                              ; preds = %axiom_retain.exit.i, %chk.i.i.i, %bump.i.i.i
  %t2.i.i = load i64, ptr %t6.i.i.i, align 8
  %t3 = add i64 %t0, -1
  %t12.i = inttoptr i64 %t2.i.i to ptr
  %t86.i = srem i64 %n, 10
  %t137.i = getelementptr i8, ptr %t12.i, i64 %t3
  %1 = trunc nsw i64 %t86.i to i8
  %t148.i = add nsw i8 %1, 48
  store i8 %t148.i, ptr %t137.i, align 1
  %c169.i = icmp slt i64 %n, 10
  br i1 %c169.i, label %"Fmt$fmtDigits.exit", label %divok_27.i

divok_27.i:                                       ; preds = %"Str$strAlloc.exit", %divok_27.i
  %s.3.011.i = phi i64 [ %t30.i, %divok_27.i ], [ %t3, %"Str$strAlloc.exit" ]
  %s.2.010.i = phi i64 [ %t28.i, %divok_27.i ], [ %n, %"Str$strAlloc.exit" ]
  %t28.i = udiv i64 %s.2.010.i, 10
  %t30.i = add i64 %s.3.011.i, -1
  %t8.i = urem i64 %t28.i, 10
  %t13.i = getelementptr i8, ptr %t12.i, i64 %t30.i
  %2 = trunc nuw nsw i64 %t8.i to i8
  %t14.i = or disjoint i8 %2, 48
  store i8 %t14.i, ptr %t13.i, align 1
  %c16.i = icmp samesign ult i64 %s.2.010.i, 100
  br i1 %c16.i, label %"Fmt$fmtDigits.exit", label %divok_27.i

"Fmt$fmtDigits.exit":                             ; preds = %divok_27.i, %"Str$strAlloc.exit"
  ret i64 %t0.i.i.i
}

; Function Attrs: nofree norecurse nosync nounwind memory(write, inaccessiblemem: none, target_mem0: none, target_mem1: none)
define i64 @"Fmt$fmtDigits"(i64 returned %buf, i64 %n, i64 %at) #7 {
  %t12 = inttoptr i64 %buf to ptr
  %t86 = srem i64 %n, 10
  %t137 = getelementptr i8, ptr %t12, i64 %at
  %1 = trunc nsw i64 %t86 to i8
  %t148 = add nsw i8 %1, 48
  store i8 %t148, ptr %t137, align 1
  %c169 = icmp slt i64 %n, 10
  br i1 %c169, label %label_19, label %divok_27

label_19:                                         ; preds = %divok_27, %0
  ret i64 %buf

divok_27:                                         ; preds = %0, %divok_27
  %s.3.011 = phi i64 [ %t30, %divok_27 ], [ %at, %0 ]
  %s.2.010 = phi i64 [ %t28, %divok_27 ], [ %n, %0 ]
  %t28 = udiv i64 %s.2.010, 10
  %t30 = add i64 %s.3.011, -1
  %t8 = urem i64 %t28, 10
  %t13 = getelementptr i8, ptr %t12, i64 %t30
  %2 = trunc nuw nsw i64 %t8 to i8
  %t14 = or disjoint i8 %2, 48
  store i8 %t14, ptr %t13, align 1
  %c16 = icmp samesign ult i64 %s.2.010, 100
  br i1 %c16, label %label_19, label %divok_27
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(none)
define range(i64 0, 1152921504606846976) i64 @"Fmt$fmtHexShr4"(i64 %n) #6 {
  %t0 = lshr i64 %n, 4
  ret i64 %t0
}

; Function Attrs: nounwind
define i64 @"Fmt$fmtHex"(i64 %n) #1 {
  %c0 = icmp eq i64 %n, 0
  br i1 %c0, label %label_5, label %label_8.i

label_8.i:                                        ; preds = %0, %label_8.i
  %s.2.05.i = phi i64 [ %t14.i, %label_8.i ], [ 0, %0 ]
  %s.1.04.i = phi i64 [ %t0.i.i, %label_8.i ], [ %n, %0 ]
  %t0.i.i = lshr i64 %s.1.04.i, 4
  %t14.i = add nuw nsw i64 %s.2.05.i, 1
  %c4.i = icmp eq i64 %t0.i.i, 0
  br i1 %c4.i, label %"Fmt$fmtHexWidth.exit", label %label_8.i

"Fmt$fmtHexWidth.exit":                           ; preds = %label_8.i
  %t0.i = add nuw i64 %s.2.05.i, 2
  %t0.i.i1 = tail call i64 @axiom_alloc(i64 %t0.i)
  %imm.i.i = icmp slt i64 %t0.i.i1, 4096
  br i1 %imm.i.i, label %axiom_retain.exit.i, label %chk.i.i

chk.i.i:                                          ; preds = %"Fmt$fmtHexWidth.exit"
  %hoff.i.i = add nsw i64 %t0.i.i1, -16
  %cp.i.i = inttoptr i64 %hoff.i.i to ptr
  %c.i.i = load i64, ptr %cp.i.i, align 8
  %stat.i.i = icmp eq i64 %c.i.i, -1
  br i1 %stat.i.i, label %axiom_retain.exit.i, label %bump.i.i

bump.i.i:                                         ; preds = %chk.i.i
  %c1.i.i = add nuw i64 %c.i.i, 1
  store i64 %c1.i.i, ptr %cp.i.i, align 8
  br label %axiom_retain.exit.i

axiom_retain.exit.i:                              ; preds = %bump.i.i, %chk.i.i, %"Fmt$fmtHexWidth.exit"
  %t0.i.i.i = tail call i64 @axiom_alloc(i64 24)
  %t7.i.i.i = add i64 %t0.i.i.i, -8
  %t8.i.i.i = inttoptr i64 %t7.i.i.i to ptr
  %t10.i.i.i = load i64, ptr %t8.i.i.i, align 8
  %t11.i.i.i = lshr i64 %t10.i.i.i, 1
  %t12.i.i.i = and i64 %t11.i.i.i, 16383
  %.t12.i.i.i = tail call i64 @llvm.umin.i64(i64 %t12.i.i.i, i64 47)
  %t22.i.i.i = shl nsw i64 -65536, %.t12.i.i.i
  %t23.i.i.i = and i64 %t22.i.i.i, 262144
  %t24.i.i.i = xor i64 %t23.i.i.i, 262144
  %t25.i.i.i = or i64 %t24.i.i.i, %t10.i.i.i
  store i64 %t25.i.i.i, ptr %t8.i.i.i, align 8
  %t5.i.i.i = inttoptr i64 %t0.i.i.i to ptr
  store i64 %t14.i, ptr %t5.i.i.i, align 8
  %t6.i.i.i = getelementptr i8, ptr %t5.i.i.i, i64 8
  store i64 %t0.i.i1, ptr %t6.i.i.i, align 8
  %t6.i5.i.i = getelementptr i8, ptr %t5.i.i.i, i64 16
  store i64 %t0.i.i1, ptr %t6.i5.i.i, align 8
  %imm.i.i.i = icmp slt i64 %t0.i.i.i, 4096
  br i1 %imm.i.i.i, label %"Str$strAlloc.exit", label %chk.i.i.i

chk.i.i.i:                                        ; preds = %axiom_retain.exit.i
  %hoff.i.i.i = add nsw i64 %t0.i.i.i, -16
  %cp.i.i.i = inttoptr i64 %hoff.i.i.i to ptr
  %c.i.i.i = load i64, ptr %cp.i.i.i, align 8
  %stat.i.i.i = icmp eq i64 %c.i.i.i, -1
  br i1 %stat.i.i.i, label %"Str$strAlloc.exit", label %bump.i.i.i

bump.i.i.i:                                       ; preds = %chk.i.i.i
  %c1.i.i.i = add nuw i64 %c.i.i.i, 1
  store i64 %c1.i.i.i, ptr %cp.i.i.i, align 8
  br label %"Str$strAlloc.exit"

"Str$strAlloc.exit":                              ; preds = %axiom_retain.exit.i, %chk.i.i.i, %bump.i.i.i
  %t2.i.i = load i64, ptr %t6.i.i.i, align 8
  %t17.i = inttoptr i64 %t2.i.i to ptr
  br label %label_0.i

label_0.i:                                        ; preds = %label_0.i, %"Str$strAlloc.exit"
  %s.2.0.i = phi i64 [ %n, %"Str$strAlloc.exit" ], [ %t0.i.i4, %label_0.i ]
  %s.3.0.i = phi i64 [ %s.2.05.i, %"Str$strAlloc.exit" ], [ %t31.i, %label_0.i ]
  %t5.i = and i64 %s.2.0.i, 15
  %c6.i = icmp samesign ult i64 %t5.i, 10
  %t12.i = or disjoint i64 %t5.i, 48
  %t13.i = add nuw nsw i64 %t5.i, 87
  %t14.i3 = select i1 %c6.i, i64 %t12.i, i64 %t13.i
  %t18.i = getelementptr i8, ptr %t17.i, i64 %s.3.0.i
  %t19.i = trunc nuw nsw i64 %t14.i3 to i8
  store i8 %t19.i, ptr %t18.i, align 1
  %t0.i.i4 = lshr i64 %s.2.0.i, 4
  %c22.i = icmp eq i64 %t0.i.i4, 0
  %t31.i = add nsw i64 %s.3.0.i, -1
  br i1 %c22.i, label %label_5, label %label_0.i

label_5:                                          ; preds = %label_0.i, %0
  %t12 = phi i64 [ ptrtoint (ptr getelementptr inbounds nuw (i8, ptr @strhdr_2, i64 16) to i64), %0 ], [ %t0.i.i.i, %label_0.i ]
  ret i64 %t12
}

; Function Attrs: nofree norecurse nosync nounwind memory(none)
define i64 @"Fmt$fmtHexWidth"(i64 %n, i64 %acc) #10 {
  %c43 = icmp eq i64 %n, 0
  br i1 %c43, label %label_7, label %label_8

label_7:                                          ; preds = %label_8, %0
  %s.2.0.lcssa = phi i64 [ %acc, %0 ], [ %t14, %label_8 ]
  ret i64 %s.2.0.lcssa

label_8:                                          ; preds = %0, %label_8
  %s.2.05 = phi i64 [ %t14, %label_8 ], [ %acc, %0 ]
  %s.1.04 = phi i64 [ %t0.i, %label_8 ], [ %n, %0 ]
  %t0.i = lshr i64 %s.1.04, 4
  %t14 = add i64 %s.2.05, 1
  %c4 = icmp eq i64 %t0.i, 0
  br i1 %c4, label %label_7, label %label_8
}

; Function Attrs: nofree norecurse nosync nounwind memory(write, inaccessiblemem: none, target_mem0: none, target_mem1: none)
define i64 @"Fmt$fmtHexDigits"(i64 returned %buf, i64 %n, i64 %at) #7 {
  %t17 = inttoptr i64 %buf to ptr
  br label %label_0

label_0:                                          ; preds = %label_0, %0
  %s.2.0 = phi i64 [ %n, %0 ], [ %t0.i, %label_0 ]
  %s.3.0 = phi i64 [ %at, %0 ], [ %t31, %label_0 ]
  %t5 = and i64 %s.2.0, 15
  %c6 = icmp samesign ult i64 %t5, 10
  %t12 = or disjoint i64 %t5, 48
  %t13 = add nuw nsw i64 %t5, 87
  %t14 = select i1 %c6, i64 %t12, i64 %t13
  %t18 = getelementptr i8, ptr %t17, i64 %s.3.0
  %t19 = trunc nuw nsw i64 %t14 to i8
  store i8 %t19, ptr %t18, align 1
  %t0.i = lshr i64 %s.2.0, 4
  %c22 = icmp eq i64 %t0.i, 0
  %t31 = add i64 %s.3.0, -1
  br i1 %c22, label %label_25, label %label_0

label_25:                                         ; preds = %label_0
  ret i64 %buf
}

; Function Attrs: nounwind
define i64 @"Fmt$fmtPadLeft"(i64 %s, i64 %width) #1 {
  %t0.i.i = inttoptr i64 %s to ptr
  %t2.i.i = load i64, ptr %t0.i.i, align 8
  %c1.not = icmp slt i64 %t2.i.i, %width
  br i1 %c1.not, label %label_5, label %label_4

label_4:                                          ; preds = %0
  %imm.i = icmp slt i64 %s, 4096
  br i1 %imm.i, label %label_6, label %chk.i

chk.i:                                            ; preds = %label_4
  %hoff.i = add nsw i64 %s, -16
  %cp.i = inttoptr i64 %hoff.i to ptr
  %c.i = load i64, ptr %cp.i, align 8
  %stat.i = icmp eq i64 %c.i, -1
  br i1 %stat.i, label %label_6, label %bump.i

bump.i:                                           ; preds = %chk.i
  %c1.i = add nuw i64 %c.i, 1
  store i64 %c1.i, ptr %cp.i, align 8
  br label %label_6

label_5:                                          ; preds = %0
  %t0.i = add i64 %width, 1
  %t0.i.i1 = tail call i64 @axiom_alloc(i64 %t0.i)
  %imm.i.i = icmp slt i64 %t0.i.i1, 4096
  br i1 %imm.i.i, label %axiom_retain.exit.i, label %chk.i.i

chk.i.i:                                          ; preds = %label_5
  %hoff.i.i = add nsw i64 %t0.i.i1, -16
  %cp.i.i = inttoptr i64 %hoff.i.i to ptr
  %c.i.i = load i64, ptr %cp.i.i, align 8
  %stat.i.i = icmp eq i64 %c.i.i, -1
  br i1 %stat.i.i, label %axiom_retain.exit.i, label %bump.i.i

bump.i.i:                                         ; preds = %chk.i.i
  %c1.i.i = add nuw i64 %c.i.i, 1
  store i64 %c1.i.i, ptr %cp.i.i, align 8
  br label %axiom_retain.exit.i

axiom_retain.exit.i:                              ; preds = %bump.i.i, %chk.i.i, %label_5
  %t0.i.i.i = tail call i64 @axiom_alloc(i64 24)
  %t7.i.i.i = add i64 %t0.i.i.i, -8
  %t8.i.i.i = inttoptr i64 %t7.i.i.i to ptr
  %t10.i.i.i = load i64, ptr %t8.i.i.i, align 8
  %t11.i.i.i = lshr i64 %t10.i.i.i, 1
  %t12.i.i.i = and i64 %t11.i.i.i, 16383
  %.t12.i.i.i = tail call i64 @llvm.umin.i64(i64 %t12.i.i.i, i64 47)
  %t22.i.i.i = shl nsw i64 -65536, %.t12.i.i.i
  %t23.i.i.i = and i64 %t22.i.i.i, 262144
  %t24.i.i.i = xor i64 %t23.i.i.i, 262144
  %t25.i.i.i = or i64 %t24.i.i.i, %t10.i.i.i
  store i64 %t25.i.i.i, ptr %t8.i.i.i, align 8
  %t5.i.i.i = inttoptr i64 %t0.i.i.i to ptr
  store i64 %width, ptr %t5.i.i.i, align 8
  %t6.i.i.i = getelementptr i8, ptr %t5.i.i.i, i64 8
  store i64 %t0.i.i1, ptr %t6.i.i.i, align 8
  %t6.i5.i.i = getelementptr i8, ptr %t5.i.i.i, i64 16
  store i64 %t0.i.i1, ptr %t6.i5.i.i, align 8
  %imm.i.i.i = icmp slt i64 %t0.i.i.i, 4096
  br i1 %imm.i.i.i, label %"Str$strAlloc.exit", label %chk.i.i.i

chk.i.i.i:                                        ; preds = %axiom_retain.exit.i
  %hoff.i.i.i = add nsw i64 %t0.i.i.i, -16
  %cp.i.i.i = inttoptr i64 %hoff.i.i.i to ptr
  %c.i.i.i = load i64, ptr %cp.i.i.i, align 8
  %stat.i.i.i = icmp eq i64 %c.i.i.i, -1
  br i1 %stat.i.i.i, label %"Str$strAlloc.exit", label %bump.i.i.i

bump.i.i.i:                                       ; preds = %chk.i.i.i
  %c1.i.i.i = add nuw i64 %c.i.i.i, 1
  store i64 %c1.i.i.i, ptr %cp.i.i.i, align 8
  br label %"Str$strAlloc.exit"

"Str$strAlloc.exit":                              ; preds = %axiom_retain.exit.i, %chk.i.i.i, %bump.i.i.i
  %t9 = sub i64 %width, %t2.i.i
  %c53.i.i = icmp sgt i64 %t9, 0
  br i1 %c53.i.i, label %label_2.lr.ph.i.i, label %"Mem$memSet.exit"

label_2.lr.ph.i.i:                                ; preds = %"Str$strAlloc.exit"
  %t2.i.i3 = load i64, ptr %t6.i.i.i, align 8
  %t9.i.i = inttoptr i64 %t2.i.i3 to ptr
  br label %label_2.i.i

label_2.i.i:                                      ; preds = %label_2.i.i, %label_2.lr.ph.i.i
  %s.0.04.i.i = phi i64 [ 0, %label_2.lr.ph.i.i ], [ %t13.i.i, %label_2.i.i ]
  %t10.i.i = getelementptr i8, ptr %t9.i.i, i64 %s.0.04.i.i
  store i8 32, ptr %t10.i.i, align 1
  %t13.i.i = add nuw nsw i64 %s.0.04.i.i, 1
  %exitcond.not.i.i = icmp eq i64 %t13.i.i, %t9
  br i1 %exitcond.not.i.i, label %"Mem$memSet.exit", label %label_2.i.i

"Mem$memSet.exit":                                ; preds = %label_2.i.i, %"Str$strAlloc.exit"
  %c54.i.i = icmp sgt i64 %t2.i.i, 0
  br i1 %c54.i.i, label %label_2.lr.ph.i.i10, label %label_6

label_2.lr.ph.i.i10:                              ; preds = %"Mem$memSet.exit"
  %t1.i.i8 = getelementptr i8, ptr %t0.i.i, i64 8
  %t2.i.i9 = load i64, ptr %t1.i.i8, align 8
  %t2.i.i6 = load i64, ptr %t6.i.i.i, align 8
  %t13 = add i64 %t2.i.i6, %t9
  %t10.i.i11 = inttoptr i64 %t2.i.i9 to ptr
  %t14.i.i = inttoptr i64 %t13 to ptr
  br label %label_2.i.i12

label_2.i.i12:                                    ; preds = %label_2.i.i12, %label_2.lr.ph.i.i10
  %s.0.05.i.i = phi i64 [ 0, %label_2.lr.ph.i.i10 ], [ %t18.i.i, %label_2.i.i12 ]
  %t11.i.i = getelementptr i8, ptr %t10.i.i11, i64 %s.0.05.i.i
  %t12.i.i = load i8, ptr %t11.i.i, align 1
  %t15.i.i = getelementptr i8, ptr %t14.i.i, i64 %s.0.05.i.i
  store i8 %t12.i.i, ptr %t15.i.i, align 1
  %t18.i.i = add nuw nsw i64 %s.0.05.i.i, 1
  %exitcond.not.i.i13 = icmp eq i64 %t18.i.i, %t2.i.i
  br i1 %exitcond.not.i.i13, label %label_6, label %label_2.i.i12

label_6:                                          ; preds = %label_2.i.i12, %"Mem$memSet.exit", %bump.i, %chk.i, %label_4
  %t16 = phi i64 [ %s, %bump.i ], [ %s, %label_4 ], [ %s, %chk.i ], [ %t0.i.i.i, %"Mem$memSet.exit" ], [ %t0.i.i.i, %label_2.i.i12 ]
  ret i64 %t16
}

; Function Attrs: nounwind
define i64 @"Fmt$fmtPadRight"(i64 %s, i64 %width) #1 {
  %t0.i.i = inttoptr i64 %s to ptr
  %t2.i.i = load i64, ptr %t0.i.i, align 8
  %c1.not = icmp slt i64 %t2.i.i, %width
  br i1 %c1.not, label %label_5, label %label_4

label_4:                                          ; preds = %0
  %imm.i = icmp slt i64 %s, 4096
  br i1 %imm.i, label %label_6, label %chk.i

chk.i:                                            ; preds = %label_4
  %hoff.i = add nsw i64 %s, -16
  %cp.i = inttoptr i64 %hoff.i to ptr
  %c.i = load i64, ptr %cp.i, align 8
  %stat.i = icmp eq i64 %c.i, -1
  br i1 %stat.i, label %label_6, label %bump.i

bump.i:                                           ; preds = %chk.i
  %c1.i = add nuw i64 %c.i, 1
  store i64 %c1.i, ptr %cp.i, align 8
  br label %label_6

label_5:                                          ; preds = %0
  %t0.i = add i64 %width, 1
  %t0.i.i1 = tail call i64 @axiom_alloc(i64 %t0.i)
  %imm.i.i = icmp slt i64 %t0.i.i1, 4096
  br i1 %imm.i.i, label %axiom_retain.exit.i, label %chk.i.i

chk.i.i:                                          ; preds = %label_5
  %hoff.i.i = add nsw i64 %t0.i.i1, -16
  %cp.i.i = inttoptr i64 %hoff.i.i to ptr
  %c.i.i = load i64, ptr %cp.i.i, align 8
  %stat.i.i = icmp eq i64 %c.i.i, -1
  br i1 %stat.i.i, label %axiom_retain.exit.i, label %bump.i.i

bump.i.i:                                         ; preds = %chk.i.i
  %c1.i.i = add nuw i64 %c.i.i, 1
  store i64 %c1.i.i, ptr %cp.i.i, align 8
  br label %axiom_retain.exit.i

axiom_retain.exit.i:                              ; preds = %bump.i.i, %chk.i.i, %label_5
  %t0.i.i.i = tail call i64 @axiom_alloc(i64 24)
  %t7.i.i.i = add i64 %t0.i.i.i, -8
  %t8.i.i.i = inttoptr i64 %t7.i.i.i to ptr
  %t10.i.i.i = load i64, ptr %t8.i.i.i, align 8
  %t11.i.i.i = lshr i64 %t10.i.i.i, 1
  %t12.i.i.i = and i64 %t11.i.i.i, 16383
  %.t12.i.i.i = tail call i64 @llvm.umin.i64(i64 %t12.i.i.i, i64 47)
  %t22.i.i.i = shl nsw i64 -65536, %.t12.i.i.i
  %t23.i.i.i = and i64 %t22.i.i.i, 262144
  %t24.i.i.i = xor i64 %t23.i.i.i, 262144
  %t25.i.i.i = or i64 %t24.i.i.i, %t10.i.i.i
  store i64 %t25.i.i.i, ptr %t8.i.i.i, align 8
  %t5.i.i.i = inttoptr i64 %t0.i.i.i to ptr
  store i64 %width, ptr %t5.i.i.i, align 8
  %t6.i.i.i = getelementptr i8, ptr %t5.i.i.i, i64 8
  store i64 %t0.i.i1, ptr %t6.i.i.i, align 8
  %t6.i5.i.i = getelementptr i8, ptr %t5.i.i.i, i64 16
  store i64 %t0.i.i1, ptr %t6.i5.i.i, align 8
  %imm.i.i.i = icmp slt i64 %t0.i.i.i, 4096
  br i1 %imm.i.i.i, label %"Str$strAlloc.exit", label %chk.i.i.i

chk.i.i.i:                                        ; preds = %axiom_retain.exit.i
  %hoff.i.i.i = add nsw i64 %t0.i.i.i, -16
  %cp.i.i.i = inttoptr i64 %hoff.i.i.i to ptr
  %c.i.i.i = load i64, ptr %cp.i.i.i, align 8
  %stat.i.i.i = icmp eq i64 %c.i.i.i, -1
  br i1 %stat.i.i.i, label %"Str$strAlloc.exit", label %bump.i.i.i

bump.i.i.i:                                       ; preds = %chk.i.i.i
  %c1.i.i.i = add nuw i64 %c.i.i.i, 1
  store i64 %c1.i.i.i, ptr %cp.i.i.i, align 8
  br label %"Str$strAlloc.exit"

"Str$strAlloc.exit":                              ; preds = %axiom_retain.exit.i, %chk.i.i.i, %bump.i.i.i
  %c54.i.i = icmp sgt i64 %t2.i.i, 0
  br i1 %c54.i.i, label %label_2.lr.ph.i.i, label %"Mem$memCopy.exit"

label_2.lr.ph.i.i:                                ; preds = %"Str$strAlloc.exit"
  %t1.i.i5 = getelementptr i8, ptr %t0.i.i, i64 8
  %t2.i.i6 = load i64, ptr %t1.i.i5, align 8
  %t2.i.i3 = load i64, ptr %t6.i.i.i, align 8
  %t10.i.i = inttoptr i64 %t2.i.i6 to ptr
  %t14.i.i = inttoptr i64 %t2.i.i3 to ptr
  br label %label_2.i.i

label_2.i.i:                                      ; preds = %label_2.i.i, %label_2.lr.ph.i.i
  %s.0.05.i.i = phi i64 [ 0, %label_2.lr.ph.i.i ], [ %t18.i.i, %label_2.i.i ]
  %t11.i.i = getelementptr i8, ptr %t10.i.i, i64 %s.0.05.i.i
  %t12.i.i = load i8, ptr %t11.i.i, align 1
  %t15.i.i = getelementptr i8, ptr %t14.i.i, i64 %s.0.05.i.i
  store i8 %t12.i.i, ptr %t15.i.i, align 1
  %t18.i.i = add nuw nsw i64 %s.0.05.i.i, 1
  %exitcond.not.i.i = icmp eq i64 %t18.i.i, %t2.i.i
  br i1 %exitcond.not.i.i, label %"Mem$memCopy.exit", label %label_2.i.i

"Mem$memCopy.exit":                               ; preds = %label_2.i.i, %"Str$strAlloc.exit"
  %t13 = sub i64 %width, %t2.i.i
  %c53.i.i = icmp sgt i64 %t13, 0
  br i1 %c53.i.i, label %label_2.lr.ph.i.i10, label %label_6

label_2.lr.ph.i.i10:                              ; preds = %"Mem$memCopy.exit"
  %t2.i.i9 = load i64, ptr %t6.i.i.i, align 8
  %t12 = add i64 %t2.i.i9, %t2.i.i
  %t9.i.i = inttoptr i64 %t12 to ptr
  br label %label_2.i.i11

label_2.i.i11:                                    ; preds = %label_2.i.i11, %label_2.lr.ph.i.i10
  %s.0.04.i.i = phi i64 [ 0, %label_2.lr.ph.i.i10 ], [ %t13.i.i, %label_2.i.i11 ]
  %t10.i.i12 = getelementptr i8, ptr %t9.i.i, i64 %s.0.04.i.i
  store i8 32, ptr %t10.i.i12, align 1
  %t13.i.i = add nuw nsw i64 %s.0.04.i.i, 1
  %exitcond.not.i.i13 = icmp eq i64 %t13.i.i, %t13
  br i1 %exitcond.not.i.i13, label %label_6, label %label_2.i.i11

label_6:                                          ; preds = %label_2.i.i11, %"Mem$memCopy.exit", %bump.i, %chk.i, %label_4
  %t15 = phi i64 [ %s, %bump.i ], [ %s, %label_4 ], [ %s, %chk.i ], [ %t0.i.i.i, %"Mem$memCopy.exit" ], [ %t0.i.i.i, %label_2.i.i11 ]
  ret i64 %t15
}

; Function Attrs: nounwind
define i64 @"Fmt$fmtPadCenter"(i64 %s, i64 %width) #1 {
  %t0.i.i = inttoptr i64 %s to ptr
  %t2.i.i = load i64, ptr %t0.i.i, align 8
  %c1.not = icmp slt i64 %t2.i.i, %width
  br i1 %c1.not, label %divok_10, label %label_4

label_4:                                          ; preds = %0
  %imm.i = icmp slt i64 %s, 4096
  br i1 %imm.i, label %label_6, label %chk.i

chk.i:                                            ; preds = %label_4
  %hoff.i = add nsw i64 %s, -16
  %cp.i = inttoptr i64 %hoff.i to ptr
  %c.i = load i64, ptr %cp.i, align 8
  %stat.i = icmp eq i64 %c.i, -1
  br i1 %stat.i, label %label_6, label %bump.i

bump.i:                                           ; preds = %chk.i
  %c1.i = add nuw i64 %c.i, 1
  store i64 %c1.i, ptr %cp.i, align 8
  br label %label_6

divok_10:                                         ; preds = %0
  %t7 = sub i64 %width, %t2.i.i
  %t11 = sdiv i64 %t7, 2
  %t0.i = add i64 %width, 1
  %t0.i.i1 = tail call i64 @axiom_alloc(i64 %t0.i)
  %imm.i.i = icmp slt i64 %t0.i.i1, 4096
  br i1 %imm.i.i, label %axiom_retain.exit.i, label %chk.i.i

chk.i.i:                                          ; preds = %divok_10
  %hoff.i.i = add nsw i64 %t0.i.i1, -16
  %cp.i.i = inttoptr i64 %hoff.i.i to ptr
  %c.i.i = load i64, ptr %cp.i.i, align 8
  %stat.i.i = icmp eq i64 %c.i.i, -1
  br i1 %stat.i.i, label %axiom_retain.exit.i, label %bump.i.i

bump.i.i:                                         ; preds = %chk.i.i
  %c1.i.i = add nuw i64 %c.i.i, 1
  store i64 %c1.i.i, ptr %cp.i.i, align 8
  br label %axiom_retain.exit.i

axiom_retain.exit.i:                              ; preds = %bump.i.i, %chk.i.i, %divok_10
  %t0.i.i.i = tail call i64 @axiom_alloc(i64 24)
  %t7.i.i.i = add i64 %t0.i.i.i, -8
  %t8.i.i.i = inttoptr i64 %t7.i.i.i to ptr
  %t10.i.i.i = load i64, ptr %t8.i.i.i, align 8
  %t11.i.i.i = lshr i64 %t10.i.i.i, 1
  %t12.i.i.i = and i64 %t11.i.i.i, 16383
  %.t12.i.i.i = tail call i64 @llvm.umin.i64(i64 %t12.i.i.i, i64 47)
  %t22.i.i.i = shl nsw i64 -65536, %.t12.i.i.i
  %t23.i.i.i = and i64 %t22.i.i.i, 262144
  %t24.i.i.i = xor i64 %t23.i.i.i, 262144
  %t25.i.i.i = or i64 %t24.i.i.i, %t10.i.i.i
  store i64 %t25.i.i.i, ptr %t8.i.i.i, align 8
  %t5.i.i.i = inttoptr i64 %t0.i.i.i to ptr
  store i64 %width, ptr %t5.i.i.i, align 8
  %t6.i.i.i = getelementptr i8, ptr %t5.i.i.i, i64 8
  store i64 %t0.i.i1, ptr %t6.i.i.i, align 8
  %t6.i5.i.i = getelementptr i8, ptr %t5.i.i.i, i64 16
  store i64 %t0.i.i1, ptr %t6.i5.i.i, align 8
  %imm.i.i.i = icmp slt i64 %t0.i.i.i, 4096
  br i1 %imm.i.i.i, label %"Str$strAlloc.exit", label %chk.i.i.i

chk.i.i.i:                                        ; preds = %axiom_retain.exit.i
  %hoff.i.i.i = add nsw i64 %t0.i.i.i, -16
  %cp.i.i.i = inttoptr i64 %hoff.i.i.i to ptr
  %c.i.i.i = load i64, ptr %cp.i.i.i, align 8
  %stat.i.i.i = icmp eq i64 %c.i.i.i, -1
  br i1 %stat.i.i.i, label %"Str$strAlloc.exit", label %bump.i.i.i

bump.i.i.i:                                       ; preds = %chk.i.i.i
  %c1.i.i.i = add nuw i64 %c.i.i.i, 1
  store i64 %c1.i.i.i, ptr %cp.i.i.i, align 8
  br label %"Str$strAlloc.exit"

"Str$strAlloc.exit":                              ; preds = %axiom_retain.exit.i, %chk.i.i.i, %bump.i.i.i
  %c53.i.i = icmp sgt i64 %t7, 1
  br i1 %c53.i.i, label %label_2.lr.ph.i.i, label %"Mem$memSet.exit"

label_2.lr.ph.i.i:                                ; preds = %"Str$strAlloc.exit"
  %t2.i.i3 = load i64, ptr %t6.i.i.i, align 8
  %t9.i.i = inttoptr i64 %t2.i.i3 to ptr
  br label %label_2.i.i

label_2.i.i:                                      ; preds = %label_2.i.i, %label_2.lr.ph.i.i
  %s.0.04.i.i = phi i64 [ 0, %label_2.lr.ph.i.i ], [ %t13.i.i, %label_2.i.i ]
  %t10.i.i = getelementptr i8, ptr %t9.i.i, i64 %s.0.04.i.i
  store i8 32, ptr %t10.i.i, align 1
  %t13.i.i = add nuw nsw i64 %s.0.04.i.i, 1
  %exitcond.not.i.i = icmp eq i64 %t13.i.i, %t11
  br i1 %exitcond.not.i.i, label %"Mem$memSet.exit", label %label_2.i.i

"Mem$memSet.exit":                                ; preds = %label_2.i.i, %"Str$strAlloc.exit"
  %c54.i.i = icmp sgt i64 %t2.i.i, 0
  br i1 %c54.i.i, label %label_2.lr.ph.i.i10, label %"Mem$memCopy.exit"

label_2.lr.ph.i.i10:                              ; preds = %"Mem$memSet.exit"
  %t1.i.i8 = getelementptr i8, ptr %t0.i.i, i64 8
  %t2.i.i9 = load i64, ptr %t1.i.i8, align 8
  %t2.i.i6 = load i64, ptr %t6.i.i.i, align 8
  %t16 = add i64 %t2.i.i6, %t11
  %t10.i.i11 = inttoptr i64 %t2.i.i9 to ptr
  %t14.i.i = inttoptr i64 %t16 to ptr
  br label %label_2.i.i12

label_2.i.i12:                                    ; preds = %label_2.i.i12, %label_2.lr.ph.i.i10
  %s.0.05.i.i = phi i64 [ 0, %label_2.lr.ph.i.i10 ], [ %t18.i.i, %label_2.i.i12 ]
  %t11.i.i = getelementptr i8, ptr %t10.i.i11, i64 %s.0.05.i.i
  %t12.i.i = load i8, ptr %t11.i.i, align 1
  %t15.i.i = getelementptr i8, ptr %t14.i.i, i64 %s.0.05.i.i
  store i8 %t12.i.i, ptr %t15.i.i, align 1
  %t18.i.i = add nuw nsw i64 %s.0.05.i.i, 1
  %exitcond.not.i.i13 = icmp eq i64 %t18.i.i, %t2.i.i
  br i1 %exitcond.not.i.i13, label %"Mem$memCopy.exit", label %label_2.i.i12

"Mem$memCopy.exit":                               ; preds = %label_2.i.i12, %"Mem$memSet.exit"
  %t22 = sub i64 %t7, %t11
  %c53.i.i17 = icmp sgt i64 %t22, 0
  br i1 %c53.i.i17, label %label_2.lr.ph.i.i18, label %label_6

label_2.lr.ph.i.i18:                              ; preds = %"Mem$memCopy.exit"
  %t2.i.i16 = load i64, ptr %t6.i.i.i, align 8
  %t20 = add i64 %t11, %t2.i.i
  %t21 = add i64 %t20, %t2.i.i16
  %t9.i.i19 = inttoptr i64 %t21 to ptr
  br label %label_2.i.i20

label_2.i.i20:                                    ; preds = %label_2.i.i20, %label_2.lr.ph.i.i18
  %s.0.04.i.i21 = phi i64 [ 0, %label_2.lr.ph.i.i18 ], [ %t13.i.i23, %label_2.i.i20 ]
  %t10.i.i22 = getelementptr i8, ptr %t9.i.i19, i64 %s.0.04.i.i21
  store i8 32, ptr %t10.i.i22, align 1
  %t13.i.i23 = add nuw nsw i64 %s.0.04.i.i21, 1
  %exitcond.not.i.i24 = icmp eq i64 %t13.i.i23, %t22
  br i1 %exitcond.not.i.i24, label %label_6, label %label_2.i.i20

label_6:                                          ; preds = %label_2.i.i20, %"Mem$memCopy.exit", %bump.i, %chk.i, %label_4
  %t24 = phi i64 [ %s, %bump.i ], [ %s, %label_4 ], [ %s, %chk.i ], [ %t0.i.i.i, %"Mem$memCopy.exit" ], [ %t0.i.i.i, %label_2.i.i20 ]
  ret i64 %t24
}

; Function Attrs: nounwind
define i64 @"Fmt$fmtPadZerosLeft"(i64 %s, i64 %width) #1 {
  %t0.i.i = inttoptr i64 %s to ptr
  %t2.i.i = load i64, ptr %t0.i.i, align 8
  %c1.not = icmp slt i64 %t2.i.i, %width
  br i1 %c1.not, label %label_5, label %label_4

label_4:                                          ; preds = %0
  %imm.i = icmp slt i64 %s, 4096
  br i1 %imm.i, label %label_6, label %chk.i

chk.i:                                            ; preds = %label_4
  %hoff.i = add nsw i64 %s, -16
  %cp.i = inttoptr i64 %hoff.i to ptr
  %c.i = load i64, ptr %cp.i, align 8
  %stat.i = icmp eq i64 %c.i, -1
  br i1 %stat.i, label %label_6, label %bump.i

bump.i:                                           ; preds = %chk.i
  %c1.i = add nuw i64 %c.i, 1
  store i64 %c1.i, ptr %cp.i, align 8
  br label %label_6

label_5:                                          ; preds = %0
  %c7.not.i = icmp sgt i64 %t2.i.i, 0
  br i1 %c7.not.i, label %label_11.i, label %label_12

label_11.i:                                       ; preds = %label_5
  %t1.i.i.i = getelementptr i8, ptr %t0.i.i, i64 8
  %t2.i.i2.i = load i64, ptr %t1.i.i.i, align 8
  %t14.i = inttoptr i64 %t2.i.i2.i to ptr
  %t16.i = load i8, ptr %t14.i, align 1
  %1 = icmp eq i8 %t16.i, 45
  %2 = zext i1 %1 to i64
  br label %label_12

label_12:                                         ; preds = %label_11.i, %label_5
  %t21 = phi i64 [ 0, %label_5 ], [ %2, %label_11.i ]
  %t0.i = add i64 %width, 1
  %t0.i.i1 = tail call i64 @axiom_alloc(i64 %t0.i)
  %imm.i.i = icmp slt i64 %t0.i.i1, 4096
  br i1 %imm.i.i, label %axiom_retain.exit.i, label %chk.i.i

chk.i.i:                                          ; preds = %label_12
  %hoff.i.i = add nsw i64 %t0.i.i1, -16
  %cp.i.i = inttoptr i64 %hoff.i.i to ptr
  %c.i.i = load i64, ptr %cp.i.i, align 8
  %stat.i.i = icmp eq i64 %c.i.i, -1
  br i1 %stat.i.i, label %axiom_retain.exit.i, label %bump.i.i

bump.i.i:                                         ; preds = %chk.i.i
  %c1.i.i = add nuw i64 %c.i.i, 1
  store i64 %c1.i.i, ptr %cp.i.i, align 8
  br label %axiom_retain.exit.i

axiom_retain.exit.i:                              ; preds = %bump.i.i, %chk.i.i, %label_12
  %t0.i.i.i2 = tail call i64 @axiom_alloc(i64 24)
  %t7.i.i.i = add i64 %t0.i.i.i2, -8
  %t8.i.i.i = inttoptr i64 %t7.i.i.i to ptr
  %t10.i.i.i = load i64, ptr %t8.i.i.i, align 8
  %t11.i.i.i = lshr i64 %t10.i.i.i, 1
  %t12.i.i.i = and i64 %t11.i.i.i, 16383
  %.t12.i.i.i = tail call i64 @llvm.umin.i64(i64 %t12.i.i.i, i64 47)
  %t22.i.i.i = shl nsw i64 -65536, %.t12.i.i.i
  %t23.i.i.i = and i64 %t22.i.i.i, 262144
  %t24.i.i.i = xor i64 %t23.i.i.i, 262144
  %t25.i.i.i = or i64 %t24.i.i.i, %t10.i.i.i
  store i64 %t25.i.i.i, ptr %t8.i.i.i, align 8
  %t5.i.i.i = inttoptr i64 %t0.i.i.i2 to ptr
  store i64 %width, ptr %t5.i.i.i, align 8
  %t6.i.i.i = getelementptr i8, ptr %t5.i.i.i, i64 8
  store i64 %t0.i.i1, ptr %t6.i.i.i, align 8
  %t6.i5.i.i = getelementptr i8, ptr %t5.i.i.i, i64 16
  store i64 %t0.i.i1, ptr %t6.i5.i.i, align 8
  %imm.i.i.i = icmp slt i64 %t0.i.i.i2, 4096
  br i1 %imm.i.i.i, label %"Str$strAlloc.exit", label %chk.i.i.i

chk.i.i.i:                                        ; preds = %axiom_retain.exit.i
  %hoff.i.i.i = add nsw i64 %t0.i.i.i2, -16
  %cp.i.i.i = inttoptr i64 %hoff.i.i.i to ptr
  %c.i.i.i = load i64, ptr %cp.i.i.i, align 8
  %stat.i.i.i = icmp eq i64 %c.i.i.i, -1
  br i1 %stat.i.i.i, label %"Str$strAlloc.exit", label %bump.i.i.i

bump.i.i.i:                                       ; preds = %chk.i.i.i
  %c1.i.i.i = add nuw i64 %c.i.i.i, 1
  store i64 %c1.i.i.i, ptr %cp.i.i.i, align 8
  br label %"Str$strAlloc.exit"

"Str$strAlloc.exit":                              ; preds = %axiom_retain.exit.i, %chk.i.i.i, %bump.i.i.i
  %c23.not = icmp eq i64 %t21, 0
  br i1 %c23.not, label %label_28, label %label_26

label_26:                                         ; preds = %"Str$strAlloc.exit"
  %t2.i.i4 = load i64, ptr %t6.i.i.i, align 8
  %t30 = inttoptr i64 %t2.i.i4 to ptr
  store i8 45, ptr %t30, align 1
  br label %label_28

label_28:                                         ; preds = %"Str$strAlloc.exit", %label_26
  %t36 = sub i64 %width, %t2.i.i
  %c53.i.i = icmp sgt i64 %t36, 0
  br i1 %c53.i.i, label %label_2.lr.ph.i.i, label %"Mem$memSet.exit"

label_2.lr.ph.i.i:                                ; preds = %label_28
  %t2.i.i7 = load i64, ptr %t6.i.i.i, align 8
  %t35 = add i64 %t2.i.i7, %t21
  %t9.i.i = inttoptr i64 %t35 to ptr
  br label %label_2.i.i

label_2.i.i:                                      ; preds = %label_2.i.i, %label_2.lr.ph.i.i
  %s.0.04.i.i = phi i64 [ 0, %label_2.lr.ph.i.i ], [ %t13.i.i, %label_2.i.i ]
  %t10.i.i = getelementptr i8, ptr %t9.i.i, i64 %s.0.04.i.i
  store i8 48, ptr %t10.i.i, align 1
  %t13.i.i = add nuw nsw i64 %s.0.04.i.i, 1
  %exitcond.not.i.i = icmp eq i64 %t13.i.i, %t36
  br i1 %exitcond.not.i.i, label %"Mem$memSet.exit", label %label_2.i.i

"Mem$memSet.exit":                                ; preds = %label_2.i.i, %label_28
  %t44 = sub i64 %t2.i.i, %t21
  %c54.i.i = icmp sgt i64 %t44, 0
  br i1 %c54.i.i, label %label_2.lr.ph.i.i14, label %label_6

label_2.lr.ph.i.i14:                              ; preds = %"Mem$memSet.exit"
  %t1.i.i12 = getelementptr i8, ptr %t0.i.i, i64 8
  %t2.i.i13 = load i64, ptr %t1.i.i12, align 8
  %t43 = add i64 %t2.i.i13, %t21
  %t2.i.i10 = load i64, ptr %t6.i.i.i, align 8
  %t40 = add i64 %t21, %t36
  %t41 = add i64 %t40, %t2.i.i10
  %t10.i.i15 = inttoptr i64 %t43 to ptr
  %t14.i.i = inttoptr i64 %t41 to ptr
  br label %label_2.i.i16

label_2.i.i16:                                    ; preds = %label_2.i.i16, %label_2.lr.ph.i.i14
  %s.0.05.i.i = phi i64 [ 0, %label_2.lr.ph.i.i14 ], [ %t18.i.i, %label_2.i.i16 ]
  %t11.i.i = getelementptr i8, ptr %t10.i.i15, i64 %s.0.05.i.i
  %t12.i.i = load i8, ptr %t11.i.i, align 1
  %t15.i.i = getelementptr i8, ptr %t14.i.i, i64 %s.0.05.i.i
  store i8 %t12.i.i, ptr %t15.i.i, align 1
  %t18.i.i = add nuw nsw i64 %s.0.05.i.i, 1
  %exitcond.not.i.i17 = icmp eq i64 %t18.i.i, %t44
  br i1 %exitcond.not.i.i17, label %label_6, label %label_2.i.i16

label_6:                                          ; preds = %label_2.i.i16, %"Mem$memSet.exit", %bump.i, %chk.i, %label_4
  %t46 = phi i64 [ %s, %bump.i ], [ %s, %label_4 ], [ %s, %chk.i ], [ %t0.i.i.i2, %"Mem$memSet.exit" ], [ %t0.i.i.i2, %label_2.i.i16 ]
  ret i64 %t46
}

; Function Attrs: nounwind
define i64 @"Fmt$fmtHexUpper"(i64 %n) #1 {
  %c0 = icmp eq i64 %n, 0
  br i1 %c0, label %label_5, label %label_8.i

label_8.i:                                        ; preds = %0, %label_8.i
  %s.2.05.i = phi i64 [ %t14.i, %label_8.i ], [ 0, %0 ]
  %s.1.04.i = phi i64 [ %t0.i.i, %label_8.i ], [ %n, %0 ]
  %t0.i.i = lshr i64 %s.1.04.i, 4
  %t14.i = add nuw nsw i64 %s.2.05.i, 1
  %c4.i = icmp eq i64 %t0.i.i, 0
  br i1 %c4.i, label %"Fmt$fmtHexWidth.exit", label %label_8.i

"Fmt$fmtHexWidth.exit":                           ; preds = %label_8.i
  %t0.i = add nuw i64 %s.2.05.i, 2
  %t0.i.i1 = tail call i64 @axiom_alloc(i64 %t0.i)
  %imm.i.i = icmp slt i64 %t0.i.i1, 4096
  br i1 %imm.i.i, label %axiom_retain.exit.i, label %chk.i.i

chk.i.i:                                          ; preds = %"Fmt$fmtHexWidth.exit"
  %hoff.i.i = add nsw i64 %t0.i.i1, -16
  %cp.i.i = inttoptr i64 %hoff.i.i to ptr
  %c.i.i = load i64, ptr %cp.i.i, align 8
  %stat.i.i = icmp eq i64 %c.i.i, -1
  br i1 %stat.i.i, label %axiom_retain.exit.i, label %bump.i.i

bump.i.i:                                         ; preds = %chk.i.i
  %c1.i.i = add nuw i64 %c.i.i, 1
  store i64 %c1.i.i, ptr %cp.i.i, align 8
  br label %axiom_retain.exit.i

axiom_retain.exit.i:                              ; preds = %bump.i.i, %chk.i.i, %"Fmt$fmtHexWidth.exit"
  %t0.i.i.i = tail call i64 @axiom_alloc(i64 24)
  %t7.i.i.i = add i64 %t0.i.i.i, -8
  %t8.i.i.i = inttoptr i64 %t7.i.i.i to ptr
  %t10.i.i.i = load i64, ptr %t8.i.i.i, align 8
  %t11.i.i.i = lshr i64 %t10.i.i.i, 1
  %t12.i.i.i = and i64 %t11.i.i.i, 16383
  %.t12.i.i.i = tail call i64 @llvm.umin.i64(i64 %t12.i.i.i, i64 47)
  %t22.i.i.i = shl nsw i64 -65536, %.t12.i.i.i
  %t23.i.i.i = and i64 %t22.i.i.i, 262144
  %t24.i.i.i = xor i64 %t23.i.i.i, 262144
  %t25.i.i.i = or i64 %t24.i.i.i, %t10.i.i.i
  store i64 %t25.i.i.i, ptr %t8.i.i.i, align 8
  %t5.i.i.i = inttoptr i64 %t0.i.i.i to ptr
  store i64 %t14.i, ptr %t5.i.i.i, align 8
  %t6.i.i.i = getelementptr i8, ptr %t5.i.i.i, i64 8
  store i64 %t0.i.i1, ptr %t6.i.i.i, align 8
  %t6.i5.i.i = getelementptr i8, ptr %t5.i.i.i, i64 16
  store i64 %t0.i.i1, ptr %t6.i5.i.i, align 8
  %imm.i.i.i = icmp slt i64 %t0.i.i.i, 4096
  br i1 %imm.i.i.i, label %"Str$strAlloc.exit", label %chk.i.i.i

chk.i.i.i:                                        ; preds = %axiom_retain.exit.i
  %hoff.i.i.i = add nsw i64 %t0.i.i.i, -16
  %cp.i.i.i = inttoptr i64 %hoff.i.i.i to ptr
  %c.i.i.i = load i64, ptr %cp.i.i.i, align 8
  %stat.i.i.i = icmp eq i64 %c.i.i.i, -1
  br i1 %stat.i.i.i, label %"Str$strAlloc.exit", label %bump.i.i.i

bump.i.i.i:                                       ; preds = %chk.i.i.i
  %c1.i.i.i = add nuw i64 %c.i.i.i, 1
  store i64 %c1.i.i.i, ptr %cp.i.i.i, align 8
  br label %"Str$strAlloc.exit"

"Str$strAlloc.exit":                              ; preds = %axiom_retain.exit.i, %chk.i.i.i, %bump.i.i.i
  %t2.i.i = load i64, ptr %t6.i.i.i, align 8
  %t17.i = inttoptr i64 %t2.i.i to ptr
  br label %label_0.i

label_0.i:                                        ; preds = %label_0.i, %"Str$strAlloc.exit"
  %s.2.0.i = phi i64 [ %n, %"Str$strAlloc.exit" ], [ %t0.i.i4, %label_0.i ]
  %s.3.0.i = phi i64 [ %s.2.05.i, %"Str$strAlloc.exit" ], [ %t31.i, %label_0.i ]
  %t5.i = and i64 %s.2.0.i, 15
  %c6.i = icmp samesign ult i64 %t5.i, 10
  %t12.i = or disjoint i64 %t5.i, 48
  %t13.i = add nuw nsw i64 %t5.i, 55
  %t14.i3 = select i1 %c6.i, i64 %t12.i, i64 %t13.i
  %t18.i = getelementptr i8, ptr %t17.i, i64 %s.3.0.i
  %t19.i = trunc nuw nsw i64 %t14.i3 to i8
  store i8 %t19.i, ptr %t18.i, align 1
  %t0.i.i4 = lshr i64 %s.2.0.i, 4
  %c22.i = icmp eq i64 %t0.i.i4, 0
  %t31.i = add nsw i64 %s.3.0.i, -1
  br i1 %c22.i, label %label_5, label %label_0.i

label_5:                                          ; preds = %label_0.i, %0
  %t12 = phi i64 [ ptrtoint (ptr getelementptr inbounds nuw (i8, ptr @strhdr_2, i64 16) to i64), %0 ], [ %t0.i.i.i, %label_0.i ]
  ret i64 %t12
}

; Function Attrs: nofree norecurse nosync nounwind memory(write, inaccessiblemem: none, target_mem0: none, target_mem1: none)
define i64 @"Fmt$fmtHexDigitsUpper"(i64 returned %buf, i64 %n, i64 %at) #7 {
  %t17 = inttoptr i64 %buf to ptr
  br label %label_0

label_0:                                          ; preds = %label_0, %0
  %s.2.0 = phi i64 [ %n, %0 ], [ %t0.i, %label_0 ]
  %s.3.0 = phi i64 [ %at, %0 ], [ %t31, %label_0 ]
  %t5 = and i64 %s.2.0, 15
  %c6 = icmp samesign ult i64 %t5, 10
  %t12 = or disjoint i64 %t5, 48
  %t13 = add nuw nsw i64 %t5, 55
  %t14 = select i1 %c6, i64 %t12, i64 %t13
  %t18 = getelementptr i8, ptr %t17, i64 %s.3.0
  %t19 = trunc nuw nsw i64 %t14 to i8
  store i8 %t19, ptr %t18, align 1
  %t0.i = lshr i64 %s.2.0, 4
  %c22 = icmp eq i64 %t0.i, 0
  %t31 = add i64 %s.3.0, -1
  br i1 %c22, label %label_25, label %label_0

label_25:                                         ; preds = %label_0
  ret i64 %buf
}

; Function Attrs: nofree nosync nounwind memory(none)
define i64 @"Fmt$powTen"(i64 %n) #11 {
  br label %tailrecurse

tailrecurse:                                      ; preds = %label_4, %0
  %accumulator.tr = phi i64 [ 1, %0 ], [ %t8, %label_4 ]
  %n.tr = phi i64 [ %n, %0 ], [ %t6, %label_4 ]
  %c0 = icmp slt i64 %n.tr, 1
  br i1 %c0, label %label_5, label %label_4

label_4:                                          ; preds = %tailrecurse
  %t6 = add nsw i64 %n.tr, -1
  %t8 = mul i64 %accumulator.tr, 10
  br label %tailrecurse

label_5:                                          ; preds = %tailrecurse
  %accumulator.ret.tr = mul i64 %accumulator.tr, 1
  ret i64 %accumulator.ret.tr
}

define i64 @"Fmt$fmtPadZeros"(i64 %n, i64 %width) #0 {
  %t0 = tail call i64 @"Fmt$fmtNat"(i64 %n)
  %t1 = tail call i64 @"Fmt$fmtPadZerosLeft"(i64 %t0, i64 %width)
  tail call void @axiom_release(i64 %t0)
  ret i64 %t1
}

define i64 @"Fmt$fmtFloat"(i64 %x) #0 {
  %d0.i = bitcast i64 %x to double
  %c2.i = fcmp olt double %d0.i, 0.000000e+00
  br i1 %c2.i, label %label_5.i, label %label_6.i

label_5.i:                                        ; preds = %0
  %d11.i = fsub double 0.000000e+00, %d0.i
  %t12.i = bitcast double %d11.i to i64
  %t13.i = tail call i64 @"Fmt$fmtFloatAbs"(i64 %t12.i, i64 6)
  %t14.i = tail call i64 @"Str$strConcat"(i64 ptrtoint (ptr getelementptr inbounds nuw (i8, ptr @strhdr_1, i64 16) to i64), i64 %t13.i)
  tail call void @axiom_release(i64 ptrtoint (ptr getelementptr inbounds nuw (i8, ptr @strhdr_1, i64 16) to i64))
  tail call void @axiom_release(i64 %t13.i)
  br label %"Fmt$fmtFloatPrec.exit"

label_6.i:                                        ; preds = %0
  %t15.i = tail call i64 @"Fmt$fmtFloatAbs"(i64 %x, i64 6)
  br label %"Fmt$fmtFloatPrec.exit"

"Fmt$fmtFloatPrec.exit":                          ; preds = %label_5.i, %label_6.i
  %t16.i = phi i64 [ %t14.i, %label_5.i ], [ %t15.i, %label_6.i ]
  ret i64 %t16.i
}

define i64 @"Fmt$fmtFloatPrec"(i64 %x, i64 %places) #0 {
  %d0 = bitcast i64 %x to double
  %c2 = fcmp olt double %d0, 0.000000e+00
  br i1 %c2, label %label_5, label %label_6

label_5:                                          ; preds = %0
  %d11 = fsub double 0.000000e+00, %d0
  %t12 = bitcast double %d11 to i64
  %t13 = tail call i64 @"Fmt$fmtFloatAbs"(i64 %t12, i64 %places)
  %t14 = tail call i64 @"Str$strConcat"(i64 ptrtoint (ptr getelementptr inbounds nuw (i8, ptr @strhdr_1, i64 16) to i64), i64 %t13)
  tail call void @axiom_release(i64 ptrtoint (ptr getelementptr inbounds nuw (i8, ptr @strhdr_1, i64 16) to i64))
  tail call void @axiom_release(i64 %t13)
  br label %label_7

label_6:                                          ; preds = %0
  %t15 = tail call i64 @"Fmt$fmtFloatAbs"(i64 %x, i64 %places)
  br label %label_7

label_7:                                          ; preds = %label_6, %label_5
  %t16 = phi i64 [ %t14, %label_5 ], [ %t15, %label_6 ]
  ret i64 %t16
}

define i64 @"Fmt$fmtFloatAbs"(i64 %x, i64 %places) #0 {
label_26:
  %d0 = bitcast i64 %x to double
  %t1 = fptosi double %d0 to i64
  %d2 = sitofp i64 %t1 to double
  %d6 = fsub double %d0, %d2
  %t8 = tail call i64 @"Fmt$powTen"(i64 %places)
  %d9 = sitofp i64 %t8 to double
  %d13 = fmul double %d6, %d9
  %d17 = fadd double %d13, 5.000000e-01
  %t20 = fptosi double %d17 to i64
  %c21.not = icmp sle i64 %t8, %t20
  %. = zext i1 %c21.not to i64
  %t28 = add i64 %., %t1
  %c31 = icmp slt i64 %places, 1
  br i1 %c31, label %label_34, label %label_35

label_34:                                         ; preds = %label_26
  %narrow.i.not.i = icmp eq i64 %t28, -9223372036854775808
  br i1 %narrow.i.not.i, label %label_36, label %label_3.i

label_3.i:                                        ; preds = %label_34
  %c6.i = icmp slt i64 %t28, 0
  br i1 %c6.i, label %label_9.i, label %label_10.i

label_9.i:                                        ; preds = %label_3.i
  %t13.i = sub nsw i64 0, %t28
  %t14.i = tail call i64 @"Fmt$fmtNat"(i64 %t13.i)
  %t15.i = tail call i64 @"Str$strConcat"(i64 ptrtoint (ptr getelementptr inbounds nuw (i8, ptr @strhdr_1, i64 16) to i64), i64 %t14.i)
  tail call void @axiom_release(i64 ptrtoint (ptr getelementptr inbounds nuw (i8, ptr @strhdr_1, i64 16) to i64))
  tail call void @axiom_release(i64 %t14.i)
  br label %label_36

label_10.i:                                       ; preds = %label_3.i
  %t16.i = tail call i64 @"Fmt$fmtNat"(i64 %t28)
  br label %label_36

label_35:                                         ; preds = %label_26
  %t29 = select i1 %c21.not, i64 %t8, i64 0
  %t30 = sub i64 %t20, %t29
  %narrow.i.not.i1 = icmp eq i64 %t28, -9223372036854775808
  br i1 %narrow.i.not.i1, label %"Fmt$fmtInt.exit11", label %label_3.i2

label_3.i2:                                       ; preds = %label_35
  %c6.i3 = icmp slt i64 %t28, 0
  br i1 %c6.i3, label %label_9.i7, label %label_10.i4

label_9.i7:                                       ; preds = %label_3.i2
  %t13.i8 = sub nsw i64 0, %t28
  %t14.i9 = tail call i64 @"Fmt$fmtNat"(i64 %t13.i8)
  %t15.i10 = tail call i64 @"Str$strConcat"(i64 ptrtoint (ptr getelementptr inbounds nuw (i8, ptr @strhdr_1, i64 16) to i64), i64 %t14.i9)
  tail call void @axiom_release(i64 ptrtoint (ptr getelementptr inbounds nuw (i8, ptr @strhdr_1, i64 16) to i64))
  tail call void @axiom_release(i64 %t14.i9)
  br label %"Fmt$fmtInt.exit11"

label_10.i4:                                      ; preds = %label_3.i2
  %t16.i5 = tail call i64 @"Fmt$fmtNat"(i64 %t28)
  br label %"Fmt$fmtInt.exit11"

"Fmt$fmtInt.exit11":                              ; preds = %label_35, %label_9.i7, %label_10.i4
  %t18.i6 = phi i64 [ %t16.i5, %label_10.i4 ], [ %t15.i10, %label_9.i7 ], [ ptrtoint (ptr getelementptr inbounds nuw (i8, ptr @strhdr_0, i64 16) to i64), %label_35 ]
  %t40 = tail call i64 @"Str$strConcat"(i64 %t18.i6, i64 ptrtoint (ptr getelementptr inbounds nuw (i8, ptr @strhdr_3, i64 16) to i64))
  tail call void @axiom_release(i64 %t18.i6)
  tail call void @axiom_release(i64 ptrtoint (ptr getelementptr inbounds nuw (i8, ptr @strhdr_3, i64 16) to i64))
  %t0.i = tail call i64 @"Fmt$fmtNat"(i64 %t30)
  %t1.i = tail call i64 @"Fmt$fmtPadZerosLeft"(i64 %t0.i, i64 %places)
  tail call void @axiom_release(i64 %t0.i)
  %t42 = tail call i64 @"Str$strConcat"(i64 %t40, i64 %t1.i)
  tail call void @axiom_release(i64 %t40)
  tail call void @axiom_release(i64 %t1.i)
  br label %label_36

label_36:                                         ; preds = %label_10.i, %label_9.i, %label_34, %"Fmt$fmtInt.exit11"
  %t43 = phi i64 [ %t42, %"Fmt$fmtInt.exit11" ], [ %t16.i, %label_10.i ], [ %t15.i, %label_9.i ], [ ptrtoint (ptr getelementptr inbounds nuw (i8, ptr @strhdr_0, i64 16) to i64), %label_34 ]
  ret i64 %t43
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(none)
define noundef i64 @"Sys$stdin"() #6 {
  ret i64 0
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(none)
define noundef i64 @"Sys$stdout"() #6 {
  ret i64 1
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(none)
define noundef i64 @"Sys$stderr"() #6 {
  ret i64 2
}

; Function Attrs: nounwind
define i64 @"Sys$sysWriteFd"(i64 %fd, i64 %buf, i64 %count) #1 {
  %t1 = tail call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 64, i64 %fd, i64 %buf, i64 %count, i64 0, i64 0, i64 0) #15
  ret i64 %t1
}

; Function Attrs: nounwind
define i64 @"Sys$sysWriteAllFd"(i64 %fd, i64 %buf, i64 %count, i64 %done) #1 {
  %c7.not11 = icmp slt i64 %done, %count
  br i1 %c7.not11, label %label_11, label %label_12

label_11:                                         ; preds = %0, %label_26
  %s.4.012 = phi i64 [ %t40, %label_26 ], [ %done, %0 ]
  %t17 = add i64 %s.4.012, %buf
  %t20 = sub i64 %count, %s.4.012
  %t1.i = tail call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 64, i64 %fd, i64 %t17, i64 %t20, i64 0, i64 0, i64 0) #15
  %c22 = icmp slt i64 %t1.i, 1
  br i1 %c22, label %label_25, label %label_26

label_25:                                         ; preds = %label_11
  %c28.not = icmp eq i64 %t1.i, 0
  %t35 = select i1 %c28.not, i64 %s.4.012, i64 %t1.i
  br label %label_12

label_26:                                         ; preds = %label_11
  %t40 = add i64 %t1.i, %s.4.012
  %c7.not = icmp slt i64 %t40, %count
  br i1 %c7.not, label %label_11, label %label_12

label_12:                                         ; preds = %label_26, %0, %label_25
  %t41 = phi i64 [ %t35, %label_25 ], [ %done, %0 ], [ %t40, %label_26 ]
  ret i64 %t41
}

; Function Attrs: nounwind
define i64 @"Sys$sysReadFd"(i64 %fd, i64 %buf, i64 %count) #1 {
  %t1 = tail call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 63, i64 %fd, i64 %buf, i64 %count, i64 0, i64 0, i64 0) #15
  ret i64 %t1
}

; Function Attrs: nounwind
define i64 @"Sys$sysOpenPath"(i64 %path, i64 %flags) #1 {
  %t9.i = tail call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 56, i64 -100, i64 %path, i64 %flags, i64 420, i64 0, i64 0) #15
  ret i64 %t9.i
}

; Function Attrs: nounwind
define i64 @"Sys$sysOpenPathMode"(i64 %path, i64 %flags, i64 %mode) #1 {
label_4:
  %t9 = tail call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 56, i64 -100, i64 %path, i64 %flags, i64 %mode, i64 0, i64 0) #15
  ret i64 %t9
}

; Function Attrs: nounwind
define i64 @"Sys$sysCloseFd"(i64 %fd) #1 {
  %t1 = tail call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 57, i64 %fd, i64 0, i64 0, i64 0, i64 0, i64 0) #15
  ret i64 %t1
}

; Function Attrs: nounwind
define i64 @"Sys$sysSeek"(i64 %fd, i64 %offset, i64 %whence) #1 {
  %t1 = tail call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 62, i64 %fd, i64 %offset, i64 %whence, i64 0, i64 0, i64 0) #15
  ret i64 %t1
}

; Function Attrs: nounwind
define noundef i64 @"Sys$sysExitWith"(i64 %code) #1 {
  %t1 = tail call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 94, i64 %code, i64 0, i64 0, i64 0, i64 0, i64 0) #15
  ret i64 0
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(none)
define range(i64 0, 2) i64 @"Sys$sysFailed"(i64 %result) #6 {
  %result.lobit = lshr i64 %result, 63
  ret i64 %result.lobit
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(none)
define i64 @"Sys$sysErrno"(i64 %result) #6 {
label_5:
  %c0 = icmp slt i64 %result, 0
  %t6 = sub i64 0, %result
  %t7 = select i1 %c0, i64 %t6, i64 0
  ret i64 %t7
}

define i64 @"Sys$sysReadFile"(i64 %path) #0 {
  %t9.i.i = tail call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 56, i64 -100, i64 %path, i64 0, i64 420, i64 0, i64 0) #15
  %t3.not = icmp sgt i64 %t9.i.i, -1
  br i1 %t3.not, label %label_5, label %label_6

label_5:                                          ; preds = %0
  %t0.i.i = tail call i64 @axiom_alloc(i64 65537)
  %imm.i.i = icmp slt i64 %t0.i.i, 4096
  br i1 %imm.i.i, label %axiom_retain.exit.i, label %chk.i.i

chk.i.i:                                          ; preds = %label_5
  %hoff.i.i = add nsw i64 %t0.i.i, -16
  %cp.i.i = inttoptr i64 %hoff.i.i to ptr
  %c.i.i = load i64, ptr %cp.i.i, align 8
  %stat.i.i = icmp eq i64 %c.i.i, -1
  br i1 %stat.i.i, label %axiom_retain.exit.i, label %bump.i.i

bump.i.i:                                         ; preds = %chk.i.i
  %c1.i.i = add nuw i64 %c.i.i, 1
  store i64 %c1.i.i, ptr %cp.i.i, align 8
  br label %axiom_retain.exit.i

axiom_retain.exit.i:                              ; preds = %bump.i.i, %chk.i.i, %label_5
  %t0.i.i.i = tail call i64 @axiom_alloc(i64 24)
  %t7.i.i.i = add i64 %t0.i.i.i, -8
  %t8.i.i.i = inttoptr i64 %t7.i.i.i to ptr
  %t10.i.i.i = load i64, ptr %t8.i.i.i, align 8
  %t11.i.i.i = lshr i64 %t10.i.i.i, 1
  %t12.i.i.i = and i64 %t11.i.i.i, 16383
  %.t12.i.i.i = tail call i64 @llvm.umin.i64(i64 %t12.i.i.i, i64 47)
  %t22.i.i.i = shl nsw i64 -65536, %.t12.i.i.i
  %t23.i.i.i = and i64 %t22.i.i.i, 262144
  %t24.i.i.i = xor i64 %t23.i.i.i, 262144
  %t25.i.i.i = or i64 %t24.i.i.i, %t10.i.i.i
  store i64 %t25.i.i.i, ptr %t8.i.i.i, align 8
  %t5.i.i.i = inttoptr i64 %t0.i.i.i to ptr
  store i64 65536, ptr %t5.i.i.i, align 8
  %t6.i.i.i = getelementptr i8, ptr %t5.i.i.i, i64 8
  store i64 %t0.i.i, ptr %t6.i.i.i, align 8
  %t6.i5.i.i = getelementptr i8, ptr %t5.i.i.i, i64 16
  store i64 %t0.i.i, ptr %t6.i5.i.i, align 8
  %imm.i.i.i = icmp slt i64 %t0.i.i.i, 4096
  br i1 %imm.i.i.i, label %"Str$strAlloc.exit", label %chk.i.i.i

chk.i.i.i:                                        ; preds = %axiom_retain.exit.i
  %hoff.i.i.i = add nsw i64 %t0.i.i.i, -16
  %cp.i.i.i = inttoptr i64 %hoff.i.i.i to ptr
  %c.i.i.i = load i64, ptr %cp.i.i.i, align 8
  %stat.i.i.i = icmp eq i64 %c.i.i.i, -1
  br i1 %stat.i.i.i, label %"Str$strAlloc.exit", label %bump.i.i.i

bump.i.i.i:                                       ; preds = %chk.i.i.i
  %c1.i.i.i = add nuw i64 %c.i.i.i, 1
  store i64 %c1.i.i.i, ptr %cp.i.i.i, align 8
  br label %"Str$strAlloc.exit"

"Str$strAlloc.exit":                              ; preds = %axiom_retain.exit.i, %chk.i.i.i, %bump.i.i.i
  %t9 = tail call i64 @"Sys$sysReadAll"(i64 %t9.i.i, i64 %t0.i.i.i, i64 0, i64 65536)
  tail call void @axiom_release(i64 %t0.i.i.i)
  %t1.i = tail call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 57, i64 %t9.i.i, i64 0, i64 0, i64 0, i64 0, i64 0) #15
  br label %label_6

label_6:                                          ; preds = %0, %"Str$strAlloc.exit"
  %t11 = phi i64 [ %t9, %"Str$strAlloc.exit" ], [ ptrtoint (ptr getelementptr inbounds nuw (i8, ptr @strhdr_4, i64 16) to i64), %0 ]
  ret i64 %t11
}

define i64 @"Sys$sysReadAll"(i64 %fd, i64 %buf, i64 %used, i64 %cap) #0 {
  %imm.i = icmp slt i64 %buf, 4096
  br i1 %imm.i, label %label_0.outer.preheader, label %chk.i

chk.i:                                            ; preds = %0
  %hoff.i = add nsw i64 %buf, -16
  %cp.i = inttoptr i64 %hoff.i to ptr
  %c.i = load i64, ptr %cp.i, align 8
  %stat.i = icmp eq i64 %c.i, -1
  br i1 %stat.i, label %label_0.outer.preheader, label %bump.i

bump.i:                                           ; preds = %chk.i
  %c1.i = add nuw i64 %c.i, 1
  store i64 %c1.i, ptr %cp.i, align 8
  br label %label_0.outer.preheader

label_0.outer.preheader:                          ; preds = %0, %chk.i, %bump.i
  br label %label_0.outer

label_0.outer:                                    ; preds = %label_0.outer.preheader, %axiom_retain.exit60
  %s.2.0.ph = phi i64 [ %t0.i.i.i, %axiom_retain.exit60 ], [ %buf, %label_0.outer.preheader ]
  %s.3.0.ph = phi i64 [ %t36, %axiom_retain.exit60 ], [ %used, %label_0.outer.preheader ]
  %s.4.0.ph = phi i64 [ %t49, %axiom_retain.exit60 ], [ %cap, %label_0.outer.preheader ]
  %t0.i.i = inttoptr i64 %s.2.0.ph to ptr
  %t1.i.i = getelementptr i8, ptr %t0.i.i, i64 8
  br label %label_0

label_0:                                          ; preds = %label_0.outer, %label_18
  %s.3.0 = phi i64 [ %t36, %label_18 ], [ %s.3.0.ph, %label_0.outer ]
  %t2.i.i = load i64, ptr %t1.i.i, align 8
  %t9 = add i64 %t2.i.i, %s.3.0
  %t12 = sub i64 %s.4.0.ph, %s.3.0
  %t1.i = tail call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 63, i64 %fd, i64 %t9, i64 %t12, i64 0, i64 0, i64 0) #15
  %c14 = icmp slt i64 %t1.i, 1
  br i1 %c14, label %label_17, label %label_18

label_17:                                         ; preds = %label_0
  %t1.i.i.le65 = getelementptr i8, ptr %t0.i.i, i64 8
  %c21 = icmp eq i64 %s.3.0, 0
  br i1 %c21, label %label_19, label %label_25

label_25:                                         ; preds = %label_17
  %t1.i.i19 = getelementptr i8, ptr %t0.i.i, i64 16
  %t2.i.i20 = load i64, ptr %t1.i.i19, align 8
  %imm.i21 = icmp slt i64 %t2.i.i20, 4096
  br i1 %imm.i21, label %axiom_retain.exit29, label %chk.i22

chk.i22:                                          ; preds = %label_25
  %hoff.i23 = add nsw i64 %t2.i.i20, -16
  %cp.i24 = inttoptr i64 %hoff.i23 to ptr
  %c.i25 = load i64, ptr %cp.i24, align 8
  %stat.i26 = icmp eq i64 %c.i25, -1
  br i1 %stat.i26, label %axiom_retain.exit29, label %bump.i27

bump.i27:                                         ; preds = %chk.i22
  %c1.i28 = add nuw i64 %c.i25, 1
  store i64 %c1.i28, ptr %cp.i24, align 8
  br label %axiom_retain.exit29

axiom_retain.exit29:                              ; preds = %label_25, %chk.i22, %bump.i27
  %t2.i.i32 = load i64, ptr %t1.i.i.le65, align 8
  %t0.i.i33 = tail call i64 @axiom_alloc(i64 24)
  %t7.i.i = add i64 %t0.i.i33, -8
  %t8.i.i = inttoptr i64 %t7.i.i to ptr
  %t10.i.i = load i64, ptr %t8.i.i, align 8
  %t11.i.i = lshr i64 %t10.i.i, 1
  %t12.i.i = and i64 %t11.i.i, 16383
  %.t12.i.i = tail call i64 @llvm.umin.i64(i64 %t12.i.i, i64 47)
  %t22.i.i = shl nsw i64 -65536, %.t12.i.i
  %t23.i.i = and i64 %t22.i.i, 262144
  %t24.i.i = xor i64 %t23.i.i, 262144
  %t25.i.i = or i64 %t24.i.i, %t10.i.i
  store i64 %t25.i.i, ptr %t8.i.i, align 8
  %t5.i.i = inttoptr i64 %t0.i.i33 to ptr
  store i64 %s.3.0, ptr %t5.i.i, align 8
  %t6.i.i = getelementptr i8, ptr %t5.i.i, i64 8
  store i64 %t2.i.i32, ptr %t6.i.i, align 8
  %t6.i5.i = getelementptr i8, ptr %t5.i.i, i64 16
  store i64 %t2.i.i20, ptr %t6.i5.i, align 8
  %imm.i.i = icmp slt i64 %t0.i.i33, 4096
  br i1 %imm.i.i, label %label_19, label %chk.i.i

chk.i.i:                                          ; preds = %axiom_retain.exit29
  %hoff.i.i = add nsw i64 %t0.i.i33, -16
  %cp.i.i = inttoptr i64 %hoff.i.i to ptr
  %c.i.i = load i64, ptr %cp.i.i, align 8
  %stat.i.i = icmp eq i64 %c.i.i, -1
  br i1 %stat.i.i, label %label_19, label %bump.i.i

bump.i.i:                                         ; preds = %chk.i.i
  %c1.i.i = add nuw i64 %c.i.i, 1
  store i64 %c1.i.i, ptr %cp.i.i, align 8
  br label %label_19

label_18:                                         ; preds = %label_0
  %t36 = add i64 %t1.i, %s.3.0
  %c38 = icmp slt i64 %t36, %s.4.0.ph
  br i1 %c38, label %label_0, label %label_42

label_42:                                         ; preds = %label_18
  %t1.i.i.le = getelementptr i8, ptr %t0.i.i, i64 8
  %t49 = shl i64 %s.4.0.ph, 1
  %t0.i = or disjoint i64 %t49, 1
  %t0.i.i34 = tail call i64 @axiom_alloc(i64 %t0.i)
  %imm.i.i35 = icmp slt i64 %t0.i.i34, 4096
  br i1 %imm.i.i35, label %axiom_retain.exit.i, label %chk.i.i36

chk.i.i36:                                        ; preds = %label_42
  %hoff.i.i37 = add nsw i64 %t0.i.i34, -16
  %cp.i.i38 = inttoptr i64 %hoff.i.i37 to ptr
  %c.i.i39 = load i64, ptr %cp.i.i38, align 8
  %stat.i.i40 = icmp eq i64 %c.i.i39, -1
  br i1 %stat.i.i40, label %axiom_retain.exit.i, label %bump.i.i41

bump.i.i41:                                       ; preds = %chk.i.i36
  %c1.i.i42 = add nuw i64 %c.i.i39, 1
  store i64 %c1.i.i42, ptr %cp.i.i38, align 8
  br label %axiom_retain.exit.i

axiom_retain.exit.i:                              ; preds = %bump.i.i41, %chk.i.i36, %label_42
  %t0.i.i.i = tail call i64 @axiom_alloc(i64 24)
  %t7.i.i.i = add i64 %t0.i.i.i, -8
  %t8.i.i.i = inttoptr i64 %t7.i.i.i to ptr
  %t10.i.i.i = load i64, ptr %t8.i.i.i, align 8
  %t11.i.i.i = lshr i64 %t10.i.i.i, 1
  %t12.i.i.i = and i64 %t11.i.i.i, 16383
  %.t12.i.i.i = tail call i64 @llvm.umin.i64(i64 %t12.i.i.i, i64 47)
  %t22.i.i.i = shl nsw i64 -65536, %.t12.i.i.i
  %t23.i.i.i = and i64 %t22.i.i.i, 262144
  %t24.i.i.i = xor i64 %t23.i.i.i, 262144
  %t25.i.i.i = or i64 %t24.i.i.i, %t10.i.i.i
  store i64 %t25.i.i.i, ptr %t8.i.i.i, align 8
  %t5.i.i.i = inttoptr i64 %t0.i.i.i to ptr
  store i64 %t49, ptr %t5.i.i.i, align 8
  %t6.i.i.i = getelementptr i8, ptr %t5.i.i.i, i64 8
  store i64 %t0.i.i34, ptr %t6.i.i.i, align 8
  %t6.i5.i.i = getelementptr i8, ptr %t5.i.i.i, i64 16
  store i64 %t0.i.i34, ptr %t6.i5.i.i, align 8
  %imm.i.i.i = icmp slt i64 %t0.i.i.i, 4096
  br i1 %imm.i.i.i, label %"Str$strAlloc.exit", label %chk.i.i.i

chk.i.i.i:                                        ; preds = %axiom_retain.exit.i
  %hoff.i.i.i = add nsw i64 %t0.i.i.i, -16
  %cp.i.i.i = inttoptr i64 %hoff.i.i.i to ptr
  %c.i.i.i = load i64, ptr %cp.i.i.i, align 8
  %stat.i.i.i = icmp eq i64 %c.i.i.i, -1
  br i1 %stat.i.i.i, label %"Str$strAlloc.exit", label %bump.i.i.i

bump.i.i.i:                                       ; preds = %chk.i.i.i
  %c1.i.i.i = add nuw i64 %c.i.i.i, 1
  store i64 %c1.i.i.i, ptr %cp.i.i.i, align 8
  br label %"Str$strAlloc.exit"

"Str$strAlloc.exit":                              ; preds = %axiom_retain.exit.i, %chk.i.i.i, %bump.i.i.i
  %c54.i.i = icmp sgt i64 %t36, 0
  br i1 %c54.i.i, label %label_2.lr.ph.i.i, label %"Mem$memCopy.exit"

label_2.lr.ph.i.i:                                ; preds = %"Str$strAlloc.exit"
  %t2.i.i48 = load i64, ptr %t1.i.i.le, align 8
  %t2.i.i45 = load i64, ptr %t6.i.i.i, align 8
  %t10.i.i49 = inttoptr i64 %t2.i.i48 to ptr
  %t14.i.i = inttoptr i64 %t2.i.i45 to ptr
  br label %label_2.i.i

label_2.i.i:                                      ; preds = %label_2.i.i, %label_2.lr.ph.i.i
  %s.0.05.i.i = phi i64 [ 0, %label_2.lr.ph.i.i ], [ %t18.i.i, %label_2.i.i ]
  %t11.i.i50 = getelementptr i8, ptr %t10.i.i49, i64 %s.0.05.i.i
  %t12.i.i51 = load i8, ptr %t11.i.i50, align 1
  %t15.i.i = getelementptr i8, ptr %t14.i.i, i64 %s.0.05.i.i
  store i8 %t12.i.i51, ptr %t15.i.i, align 1
  %t18.i.i = add nuw nsw i64 %s.0.05.i.i, 1
  %exitcond.not.i.i = icmp eq i64 %t18.i.i, %t36
  br i1 %exitcond.not.i.i, label %"Mem$memCopy.exit", label %label_2.i.i

"Mem$memCopy.exit":                               ; preds = %label_2.i.i, %"Str$strAlloc.exit"
  br i1 %imm.i.i.i, label %axiom_retain.exit60, label %chk.i53

chk.i53:                                          ; preds = %"Mem$memCopy.exit"
  %hoff.i54 = add nsw i64 %t0.i.i.i, -16
  %cp.i55 = inttoptr i64 %hoff.i54 to ptr
  %c.i56 = load i64, ptr %cp.i55, align 8
  %stat.i57 = icmp eq i64 %c.i56, -1
  br i1 %stat.i57, label %axiom_retain.exit60, label %bump.i58

bump.i58:                                         ; preds = %chk.i53
  %c1.i59 = add nuw i64 %c.i56, 1
  store i64 %c1.i59, ptr %cp.i55, align 8
  br label %axiom_retain.exit60

axiom_retain.exit60:                              ; preds = %"Mem$memCopy.exit", %chk.i53, %bump.i58
  tail call void @axiom_release(i64 %s.2.0.ph)
  tail call void @axiom_release(i64 %t0.i.i.i)
  br label %label_0.outer

label_19:                                         ; preds = %bump.i.i, %chk.i.i, %axiom_retain.exit29, %label_17
  %t34 = phi i64 [ ptrtoint (ptr getelementptr inbounds nuw (i8, ptr @strhdr_4, i64 16) to i64), %label_17 ], [ %t0.i.i33, %axiom_retain.exit29 ], [ %t0.i.i33, %chk.i.i ], [ %t0.i.i33, %bump.i.i ]
  tail call void @axiom_release(i64 %s.2.0.ph)
  ret i64 %t34
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(read, argmem: none, inaccessiblemem: none, target_mem0: none, target_mem1: none)
define i64 @"Sys$sysArgc"() #12 {
  %t0 = load i64, ptr @__axiom_argc, align 8
  ret i64 %t0
}

; Function Attrs: nounwind
define i64 @"Sys$sysArg"(i64 %i) #1 {
label_5:
  %c0 = icmp slt i64 %i, 0
  %t6 = load i64, ptr @__axiom_argc, align 8
  %c7 = icmp sge i64 %i, %t6
  %narrow = select i1 %c0, i1 true, i1 %c7
  br i1 %narrow, label %label_15, label %label_14

label_14:                                         ; preds = %label_5
  %t17 = load i64, ptr @__axiom_argv, align 8
  %p18 = inttoptr i64 %t17 to ptr
  %g19 = getelementptr i64, ptr %p18, i64 %i
  %t20 = load i64, ptr %g19, align 8
  %t5.i.i = inttoptr i64 %t20 to ptr
  br label %label_0.i.i

label_0.i.i:                                      ; preds = %label_0.i.i, %label_14
  %s.2.0.i.i = phi i64 [ 0, %label_14 ], [ %t18.i.i, %label_0.i.i ]
  %t6.i.i = getelementptr i8, ptr %t5.i.i, i64 %s.2.0.i.i
  %t7.i.i = load i8, ptr %t6.i.i, align 1
  %c9.i.i = icmp eq i8 %t7.i.i, 0
  %t18.i.i = add i64 %s.2.0.i.i, 1
  br i1 %c9.i.i, label %"Str$cstrLen.exit.i", label %label_0.i.i

"Str$cstrLen.exit.i":                             ; preds = %label_0.i.i
  %t0.i.i.i.i = tail call i64 @axiom_alloc(i64 24)
  %t7.i.i.i.i = add i64 %t0.i.i.i.i, -8
  %t8.i.i.i.i = inttoptr i64 %t7.i.i.i.i to ptr
  %t10.i.i.i.i = load i64, ptr %t8.i.i.i.i, align 8
  %t11.i.i.i.i = lshr i64 %t10.i.i.i.i, 1
  %t12.i.i.i.i = and i64 %t11.i.i.i.i, 16383
  %.t12.i.i.i.i = tail call i64 @llvm.umin.i64(i64 %t12.i.i.i.i, i64 47)
  %t22.i.i.i.i = shl nsw i64 -65536, %.t12.i.i.i.i
  %t23.i.i.i.i = and i64 %t22.i.i.i.i, 262144
  %t24.i.i.i.i = xor i64 %t23.i.i.i.i, 262144
  %t25.i.i.i.i = or i64 %t24.i.i.i.i, %t10.i.i.i.i
  store i64 %t25.i.i.i.i, ptr %t8.i.i.i.i, align 8
  %t5.i.i.i.i = inttoptr i64 %t0.i.i.i.i to ptr
  store i64 %s.2.0.i.i, ptr %t5.i.i.i.i, align 8
  %t6.i.i.i.i = getelementptr i8, ptr %t5.i.i.i.i, i64 8
  store i64 %t20, ptr %t6.i.i.i.i, align 8
  %t6.i5.i.i.i = getelementptr i8, ptr %t5.i.i.i.i, i64 16
  store i64 0, ptr %t6.i5.i.i.i, align 8
  %imm.i.i.i.i = icmp slt i64 %t0.i.i.i.i, 4096
  br i1 %imm.i.i.i.i, label %label_15, label %chk.i.i.i.i

chk.i.i.i.i:                                      ; preds = %"Str$cstrLen.exit.i"
  %hoff.i.i.i.i = add nsw i64 %t0.i.i.i.i, -16
  %cp.i.i.i.i = inttoptr i64 %hoff.i.i.i.i to ptr
  %c.i.i.i.i = load i64, ptr %cp.i.i.i.i, align 8
  %stat.i.i.i.i = icmp eq i64 %c.i.i.i.i, -1
  br i1 %stat.i.i.i.i, label %label_15, label %bump.i.i.i.i

bump.i.i.i.i:                                     ; preds = %chk.i.i.i.i
  %c1.i.i.i.i = add nuw i64 %c.i.i.i.i, 1
  store i64 %c1.i.i.i.i, ptr %cp.i.i.i.i, align 8
  br label %label_15

label_15:                                         ; preds = %bump.i.i.i.i, %chk.i.i.i.i, %"Str$cstrLen.exit.i", %label_5
  %t22 = phi i64 [ ptrtoint (ptr getelementptr inbounds nuw (i8, ptr @strhdr_4, i64 16) to i64), %label_5 ], [ %t0.i.i.i.i, %"Str$cstrLen.exit.i" ], [ %t0.i.i.i.i, %chk.i.i.i.i ], [ %t0.i.i.i.i, %bump.i.i.i.i ]
  ret i64 %t22
}

; Function Attrs: nounwind
define i64 @"Sys$sysWriteFile"(i64 %path, i64 %s) #1 {
  %t9.i.i = tail call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 56, i64 -100, i64 %path, i64 577, i64 420, i64 0, i64 0) #15
  %t3.not = icmp sgt i64 %t9.i.i, -1
  br i1 %t3.not, label %label_5, label %label_6

label_5:                                          ; preds = %0
  %t0.i.i = inttoptr i64 %s to ptr
  %t1.i.i = getelementptr i8, ptr %t0.i.i, i64 8
  %t2.i.i = load i64, ptr %t1.i.i, align 8
  %t2.i.i2 = load i64, ptr %t0.i.i, align 8
  %c7.not11.i = icmp sgt i64 %t2.i.i2, 0
  br i1 %c7.not11.i, label %label_11.i, label %"Sys$sysWriteAllFd.exit"

label_11.i:                                       ; preds = %label_5, %label_26.i
  %s.4.012.i = phi i64 [ %t40.i, %label_26.i ], [ 0, %label_5 ]
  %t17.i = add i64 %s.4.012.i, %t2.i.i
  %t20.i = sub i64 %t2.i.i2, %s.4.012.i
  %t1.i.i3 = tail call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 64, i64 %t9.i.i, i64 %t17.i, i64 %t20.i, i64 0, i64 0, i64 0) #15
  %c22.i = icmp slt i64 %t1.i.i3, 1
  br i1 %c22.i, label %label_25.i, label %label_26.i

label_25.i:                                       ; preds = %label_11.i
  %c28.not.i = icmp eq i64 %t1.i.i3, 0
  %t35.i = select i1 %c28.not.i, i64 %s.4.012.i, i64 %t1.i.i3
  br label %"Sys$sysWriteAllFd.exit"

label_26.i:                                       ; preds = %label_11.i
  %t40.i = add i64 %t1.i.i3, %s.4.012.i
  %c7.not.i = icmp slt i64 %t40.i, %t2.i.i2
  br i1 %c7.not.i, label %label_11.i, label %"Sys$sysWriteAllFd.exit"

"Sys$sysWriteAllFd.exit":                         ; preds = %label_26.i, %label_5, %label_25.i
  %t41.i = phi i64 [ %t35.i, %label_25.i ], [ 0, %label_5 ], [ %t40.i, %label_26.i ]
  %t1.i = tail call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 57, i64 %t9.i.i, i64 0, i64 0, i64 0, i64 0, i64 0) #15
  br label %label_6

label_6:                                          ; preds = %0, %"Sys$sysWriteAllFd.exit"
  %t11 = phi i64 [ %t41.i, %"Sys$sysWriteAllFd.exit" ], [ %t9.i.i, %0 ]
  ret i64 %t11
}

; Function Attrs: nounwind
define i64 @"Sys$sysAppendFile"(i64 %path, i64 %s) #1 {
  %t9.i.i = tail call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 56, i64 -100, i64 %path, i64 1089, i64 420, i64 0, i64 0) #15
  %t3.not = icmp sgt i64 %t9.i.i, -1
  br i1 %t3.not, label %label_5, label %label_6

label_5:                                          ; preds = %0
  %t0.i.i = inttoptr i64 %s to ptr
  %t1.i.i = getelementptr i8, ptr %t0.i.i, i64 8
  %t2.i.i = load i64, ptr %t1.i.i, align 8
  %t2.i.i2 = load i64, ptr %t0.i.i, align 8
  %c7.not11.i = icmp sgt i64 %t2.i.i2, 0
  br i1 %c7.not11.i, label %label_11.i, label %"Sys$sysWriteAllFd.exit"

label_11.i:                                       ; preds = %label_5, %label_26.i
  %s.4.012.i = phi i64 [ %t40.i, %label_26.i ], [ 0, %label_5 ]
  %t17.i = add i64 %s.4.012.i, %t2.i.i
  %t20.i = sub i64 %t2.i.i2, %s.4.012.i
  %t1.i.i3 = tail call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 64, i64 %t9.i.i, i64 %t17.i, i64 %t20.i, i64 0, i64 0, i64 0) #15
  %c22.i = icmp slt i64 %t1.i.i3, 1
  br i1 %c22.i, label %label_25.i, label %label_26.i

label_25.i:                                       ; preds = %label_11.i
  %c28.not.i = icmp eq i64 %t1.i.i3, 0
  %t35.i = select i1 %c28.not.i, i64 %s.4.012.i, i64 %t1.i.i3
  br label %"Sys$sysWriteAllFd.exit"

label_26.i:                                       ; preds = %label_11.i
  %t40.i = add i64 %t1.i.i3, %s.4.012.i
  %c7.not.i = icmp slt i64 %t40.i, %t2.i.i2
  br i1 %c7.not.i, label %label_11.i, label %"Sys$sysWriteAllFd.exit"

"Sys$sysWriteAllFd.exit":                         ; preds = %label_26.i, %label_5, %label_25.i
  %t41.i = phi i64 [ %t35.i, %label_25.i ], [ 0, %label_5 ], [ %t40.i, %label_26.i ]
  %t1.i = tail call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 57, i64 %t9.i.i, i64 0, i64 0, i64 0, i64 0, i64 0) #15
  br label %label_6

label_6:                                          ; preds = %0, %"Sys$sysWriteAllFd.exit"
  %t11 = phi i64 [ %t41.i, %"Sys$sysWriteAllFd.exit" ], [ %t9.i.i, %0 ]
  ret i64 %t11
}

; Function Attrs: nounwind
define i64 @"Sys$sysRename"(i64 %old, i64 %new) #1 {
label_4:
  %t10 = tail call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 38, i64 -100, i64 %old, i64 -100, i64 %new, i64 0, i64 0) #15
  ret i64 %t10
}

; Function Attrs: nounwind
define i64 @"Sys$sysUnlink"(i64 %path) #1 {
label_4:
  %t9 = tail call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 35, i64 -100, i64 %path, i64 0, i64 0, i64 0, i64 0) #15
  ret i64 %t9
}

; Function Attrs: nounwind
define i64 @"Sys$sysMkdir"(i64 %path, i64 %mode) #1 {
label_4:
  %t9 = tail call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 34, i64 -100, i64 %path, i64 %mode, i64 0, i64 0, i64 0) #15
  ret i64 %t9
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(none)
define noundef i64 @"Sys$sysDirMode"() #6 {
  ret i64 493
}

; Function Attrs: nounwind
define i64 @"Sys$sysRmdir"(i64 %path) #1 {
label_4:
  %t9 = tail call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 35, i64 -100, i64 %path, i64 512, i64 0, i64 0, i64 0) #15
  ret i64 %t9
}

; Function Attrs: nounwind
define range(i64 0, 2) i64 @"Sys$sysFileExists"(i64 %path) #1 {
  %t9.i.i = tail call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 56, i64 -100, i64 %path, i64 0, i64 420, i64 0, i64 0) #15
  %c2 = icmp slt i64 %t9.i.i, 0
  br i1 %c2, label %label_7, label %label_6

label_6:                                          ; preds = %0
  %t1.i = tail call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 57, i64 %t9.i.i, i64 0, i64 0, i64 0, i64 0, i64 0) #15
  br label %label_7

label_7:                                          ; preds = %0, %label_6
  %t9 = phi i64 [ 1, %label_6 ], [ 0, %0 ]
  ret i64 %t9
}

; Function Attrs: nounwind
define i64 @"Sys$sysFileSize"(i64 %path) #1 {
  %t9.i.i = tail call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 56, i64 -100, i64 %path, i64 0, i64 420, i64 0, i64 0) #15
  %c2 = icmp slt i64 %t9.i.i, 0
  br i1 %c2, label %label_7, label %label_6

label_6:                                          ; preds = %0
  %t1.i = tail call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 62, i64 %t9.i.i, i64 0, i64 2, i64 0, i64 0, i64 0) #15
  %t1.i1 = tail call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 57, i64 %t9.i.i, i64 0, i64 0, i64 0, i64 0, i64 0) #15
  br label %label_7

label_7:                                          ; preds = %0, %label_6
  %t11 = phi i64 [ %t1.i, %label_6 ], [ %t9.i.i, %0 ]
  ret i64 %t11
}

define i64 @"Sys$sysReadErrno"(i64 %path) #0 {
  %t9.i.i = tail call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 56, i64 -100, i64 %path, i64 0, i64 420, i64 0, i64 0) #15
  %t3.not = icmp sgt i64 %t9.i.i, -1
  br i1 %t3.not, label %label_5, label %label_4

label_4:                                          ; preds = %0
  %t6.i = sub i64 0, %t9.i.i
  br label %label_6

label_5:                                          ; preds = %0
  %t0.i.i = tail call i64 @axiom_alloc(i64 2)
  %imm.i.i = icmp slt i64 %t0.i.i, 4096
  br i1 %imm.i.i, label %axiom_retain.exit.i, label %chk.i.i

chk.i.i:                                          ; preds = %label_5
  %hoff.i.i = add nsw i64 %t0.i.i, -16
  %cp.i.i = inttoptr i64 %hoff.i.i to ptr
  %c.i.i = load i64, ptr %cp.i.i, align 8
  %stat.i.i = icmp eq i64 %c.i.i, -1
  br i1 %stat.i.i, label %axiom_retain.exit.i, label %bump.i.i

bump.i.i:                                         ; preds = %chk.i.i
  %c1.i.i = add nuw i64 %c.i.i, 1
  store i64 %c1.i.i, ptr %cp.i.i, align 8
  br label %axiom_retain.exit.i

axiom_retain.exit.i:                              ; preds = %bump.i.i, %chk.i.i, %label_5
  %t0.i.i.i = tail call i64 @axiom_alloc(i64 24)
  %t7.i.i.i = add i64 %t0.i.i.i, -8
  %t8.i.i.i = inttoptr i64 %t7.i.i.i to ptr
  %t10.i.i.i = load i64, ptr %t8.i.i.i, align 8
  %t11.i.i.i = lshr i64 %t10.i.i.i, 1
  %t12.i.i.i = and i64 %t11.i.i.i, 16383
  %.t12.i.i.i = tail call i64 @llvm.umin.i64(i64 %t12.i.i.i, i64 47)
  %t22.i.i.i = shl nsw i64 -65536, %.t12.i.i.i
  %t23.i.i.i = and i64 %t22.i.i.i, 262144
  %t24.i.i.i = xor i64 %t23.i.i.i, 262144
  %t25.i.i.i = or i64 %t24.i.i.i, %t10.i.i.i
  store i64 %t25.i.i.i, ptr %t8.i.i.i, align 8
  %t5.i.i.i = inttoptr i64 %t0.i.i.i to ptr
  store i64 1, ptr %t5.i.i.i, align 8
  %t6.i.i.i = getelementptr i8, ptr %t5.i.i.i, i64 8
  store i64 %t0.i.i, ptr %t6.i.i.i, align 8
  %t6.i5.i.i = getelementptr i8, ptr %t5.i.i.i, i64 16
  store i64 %t0.i.i, ptr %t6.i5.i.i, align 8
  %imm.i.i.i = icmp slt i64 %t0.i.i.i, 4096
  br i1 %imm.i.i.i, label %"Str$strAlloc.exit", label %chk.i.i.i

chk.i.i.i:                                        ; preds = %axiom_retain.exit.i
  %hoff.i.i.i = add nsw i64 %t0.i.i.i, -16
  %cp.i.i.i = inttoptr i64 %hoff.i.i.i to ptr
  %c.i.i.i = load i64, ptr %cp.i.i.i, align 8
  %stat.i.i.i = icmp eq i64 %c.i.i.i, -1
  br i1 %stat.i.i.i, label %"Str$strAlloc.exit", label %bump.i.i.i

bump.i.i.i:                                       ; preds = %chk.i.i.i
  %c1.i.i.i = add nuw i64 %c.i.i.i, 1
  store i64 %c1.i.i.i, ptr %cp.i.i.i, align 8
  br label %"Str$strAlloc.exit"

"Str$strAlloc.exit":                              ; preds = %axiom_retain.exit.i, %chk.i.i.i, %bump.i.i.i
  %t2.i.i = load i64, ptr %t6.i.i.i, align 8
  %t1.i = tail call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 63, i64 %t9.i.i, i64 %t2.i.i, i64 1, i64 0, i64 0, i64 0) #15
  %t1.i2 = tail call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 57, i64 %t9.i.i, i64 0, i64 0, i64 0, i64 0, i64 0) #15
  %c12 = icmp slt i64 %t1.i, 0
  %t6.i4 = sub i64 0, %t1.i
  %spec.select = select i1 %c12, i64 %t6.i4, i64 0
  tail call void @axiom_release(i64 %t0.i.i.i)
  br label %label_6

label_6:                                          ; preds = %"Str$strAlloc.exit", %label_4
  %t20 = phi i64 [ %t6.i, %label_4 ], [ %spec.select, %"Str$strAlloc.exit" ]
  ret i64 %t20
}

define range(i64 0, 2) i64 @"Sys$sysIsDir"(i64 %path) #0 {
  %t0 = tail call i64 @"Sys$sysReadErrno"(i64 %path)
  %c2 = icmp eq i64 %t0, 21
  %t3 = zext i1 %c2 to i64
  ret i64 %t3
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(none)
define noundef i64 @"Sys$sysDirBufBytes"() #6 {
  ret i64 32768
}

define i64 @"Sys$sysReadDir"(i64 %path) #0 {
  %t0.i.i.i.i = tail call i64 @axiom_alloc(i64 32)
  %t7.i.i.i.i = add i64 %t0.i.i.i.i, -8
  %t8.i.i.i.i = inttoptr i64 %t7.i.i.i.i to ptr
  %t10.i.i.i.i = load i64, ptr %t8.i.i.i.i, align 8
  %t11.i.i.i.i = lshr i64 %t10.i.i.i.i, 1
  %t12.i.i.i.i = and i64 %t11.i.i.i.i, 16383
  %.t12.i.i.i.i = tail call i64 @llvm.umin.i64(i64 %t12.i.i.i.i, i64 47)
  %t22.i.i.i.i = shl nsw i64 -65536, %.t12.i.i.i.i
  %t23.i.i.i.i = and i64 %t22.i.i.i.i, 262144
  %t24.i.i.i.i = xor i64 %t23.i.i.i.i, 262144
  %t25.i.i.i.i = or i64 %t24.i.i.i.i, %t10.i.i.i.i
  store i64 %t25.i.i.i.i, ptr %t8.i.i.i.i, align 8
  %t0.i1.i.i.i = tail call i64 @axiom_alloc(i64 64)
  %imm.i.i.i.i = icmp slt i64 %t0.i.i.i.i, 4096
  br i1 %imm.i.i.i.i, label %axiom_retain.exit.i.i.i, label %chk.i.i.i.i

chk.i.i.i.i:                                      ; preds = %0
  %hoff.i.i.i.i = add nsw i64 %t0.i.i.i.i, -16
  %cp.i.i.i.i = inttoptr i64 %hoff.i.i.i.i to ptr
  %c.i.i.i.i = load i64, ptr %cp.i.i.i.i, align 8
  %stat.i.i.i.i = icmp eq i64 %c.i.i.i.i, -1
  br i1 %stat.i.i.i.i, label %axiom_retain.exit.i.i.i, label %bump.i.i.i.i

bump.i.i.i.i:                                     ; preds = %chk.i.i.i.i
  %c1.i.i.i.i = add nuw i64 %c.i.i.i.i, 1
  store i64 %c1.i.i.i.i, ptr %cp.i.i.i.i, align 8
  br label %axiom_retain.exit.i.i.i

axiom_retain.exit.i.i.i:                          ; preds = %bump.i.i.i.i, %chk.i.i.i.i, %0
  %imm.i2.i.i.i = icmp slt i64 %t0.i1.i.i.i, 4096
  br i1 %imm.i2.i.i.i, label %"Vec$vecNew.exit", label %chk.i3.i.i.i

chk.i3.i.i.i:                                     ; preds = %axiom_retain.exit.i.i.i
  %hoff.i4.i.i.i = add nsw i64 %t0.i1.i.i.i, -16
  %cp.i5.i.i.i = inttoptr i64 %hoff.i4.i.i.i to ptr
  %c.i6.i.i.i = load i64, ptr %cp.i5.i.i.i, align 8
  %stat.i7.i.i.i = icmp eq i64 %c.i6.i.i.i, -1
  br i1 %stat.i7.i.i.i, label %"Vec$vecNew.exit", label %bump.i8.i.i.i

bump.i8.i.i.i:                                    ; preds = %chk.i3.i.i.i
  %c1.i9.i.i.i = add nuw i64 %c.i6.i.i.i, 1
  store i64 %c1.i9.i.i.i, ptr %cp.i5.i.i.i, align 8
  br label %"Vec$vecNew.exit"

"Vec$vecNew.exit":                                ; preds = %axiom_retain.exit.i.i.i, %chk.i3.i.i.i, %bump.i8.i.i.i
  %t5.i12.i.i.i = inttoptr i64 %t0.i.i.i.i to ptr
  store i64 0, ptr %t5.i12.i.i.i, align 8
  %t6.i.i.i.i = getelementptr i8, ptr %t5.i12.i.i.i, i64 8
  store i64 8, ptr %t6.i.i.i.i, align 8
  %t6.i16.i.i.i = getelementptr i8, ptr %t5.i12.i.i.i, i64 16
  store i64 %t0.i1.i.i.i, ptr %t6.i16.i.i.i, align 8
  %t6.i19.i.i.i = getelementptr i8, ptr %t5.i12.i.i.i, i64 24
  store i64 0, ptr %t6.i19.i.i.i, align 8
  %t9.i.i = tail call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 56, i64 -100, i64 %path, i64 0, i64 420, i64 0, i64 0) #15
  %t4.not = icmp sgt i64 %t9.i.i, -1
  br i1 %t4.not, label %label_6, label %label_7

label_6:                                          ; preds = %"Vec$vecNew.exit"
  %t0.i = tail call i64 @axiom_alloc(i64 32768)
  %t0.i1 = tail call i64 @axiom_alloc(i64 8)
  %t5.i = inttoptr i64 %t0.i1 to ptr
  store i64 0, ptr %t5.i, align 8
  %t228.i = tail call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 61, i64 %t9.i.i, i64 %t0.i, i64 32768, i64 0, i64 0, i64 0) #15
  %c249.i = icmp slt i64 %t228.i, 1
  br i1 %c249.i, label %"Sys$sysReadDirLoop.exit", label %label_28.i

label_28.i:                                       ; preds = %label_6, %label_28.i
  %t2210.i = phi i64 [ %t22.i, %label_28.i ], [ %t228.i, %label_6 ]
  %t32.i = tail call i64 @"Sys$sysReadDirDecode"(i64 %t0.i, i64 0, i64 %t2210.i, i64 %t0.i.i.i.i)
  %t22.i = tail call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 61, i64 %t9.i.i, i64 %t0.i, i64 32768, i64 0, i64 0, i64 0) #15
  %c24.i = icmp slt i64 %t22.i, 1
  br i1 %c24.i, label %"Sys$sysReadDirLoop.exit", label %label_28.i

"Sys$sysReadDirLoop.exit":                        ; preds = %label_28.i, %label_6
  %t1.i = tail call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 57, i64 %t9.i.i, i64 0, i64 0, i64 0, i64 0, i64 0) #15
  br label %label_7

label_7:                                          ; preds = %"Vec$vecNew.exit", %"Sys$sysReadDirLoop.exit"
  ret i64 %t0.i.i.i.i
}

define range(i64 -9223372036854775808, 1) i64 @"Sys$sysReadDirLoop"(i64 %fd, i64 %buf, i64 %pos, i64 %out) #0 {
  %t228 = tail call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 61, i64 %fd, i64 %buf, i64 32768, i64 0, i64 0, i64 0) #15
  %c249 = icmp slt i64 %t228, 1
  br i1 %c249, label %label_29, label %label_28

label_28:                                         ; preds = %0, %label_28
  %t2210 = phi i64 [ %t22, %label_28 ], [ %t228, %0 ]
  %t32 = tail call i64 @"Sys$sysReadDirDecode"(i64 %buf, i64 0, i64 %t2210, i64 %out)
  %t22 = tail call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 61, i64 %fd, i64 %buf, i64 32768, i64 0, i64 0, i64 0) #15
  %c24 = icmp slt i64 %t22, 1
  br i1 %c24, label %label_29, label %label_28

label_29:                                         ; preds = %label_28, %0
  %t22.lcssa = phi i64 [ %t228, %0 ], [ %t22, %label_28 ]
  ret i64 %t22.lcssa
}

define noundef i64 @"Sys$sysReadDirDecode"(i64 %buf, i64 %off, i64 %n, i64 %out) #0 {
  %t612 = add i64 %off, 18
  %c813 = icmp sgt i64 %t612, %n
  br i1 %c813, label %label_13, label %label_12

label_12:                                         ; preds = %0, %"Str$strFromLit.exit"
  %s.2.014 = phi i64 [ %t29, %"Str$strFromLit.exit" ], [ %off, %0 ]
  %t16 = add i64 %s.2.014, %buf
  %t0.i = inttoptr i64 %t16 to ptr
  %t1.i = getelementptr i8, ptr %t0.i, i64 16
  %t2.i = load i8, ptr %t1.i, align 1
  %t3.i = zext i8 %t2.i to i64
  %t1.i9 = getelementptr i8, ptr %t0.i, i64 17
  %t2.i10 = load i8, ptr %t1.i9, align 1
  %t3.i11 = zext i8 %t2.i10 to i64
  %t19 = shl nuw nsw i64 %t3.i11, 8
  %t20 = or disjoint i64 %t19, %t3.i
  %c22 = icmp samesign ugt i64 %t20, 19
  %t29 = add i64 %t20, %s.2.014
  %c31 = icmp sle i64 %t29, %n
  %t35 = and i1 %c22, %c31
  br i1 %t35, label %label_38, label %label_13

label_38:                                         ; preds = %label_12
  %t42 = add i64 %t16, 19
  %t5.i.i = inttoptr i64 %t42 to ptr
  br label %label_0.i.i

label_0.i.i:                                      ; preds = %label_0.i.i, %label_38
  %s.2.0.i.i = phi i64 [ 0, %label_38 ], [ %t18.i.i, %label_0.i.i ]
  %t6.i.i = getelementptr i8, ptr %t5.i.i, i64 %s.2.0.i.i
  %t7.i.i = load i8, ptr %t6.i.i, align 1
  %c9.i.i = icmp eq i8 %t7.i.i, 0
  %t18.i.i = add i64 %s.2.0.i.i, 1
  br i1 %c9.i.i, label %"Str$cstrLen.exit.i", label %label_0.i.i

"Str$cstrLen.exit.i":                             ; preds = %label_0.i.i
  %t0.i.i.i.i = tail call i64 @axiom_alloc(i64 24)
  %t7.i.i.i.i = add i64 %t0.i.i.i.i, -8
  %t8.i.i.i.i = inttoptr i64 %t7.i.i.i.i to ptr
  %t10.i.i.i.i = load i64, ptr %t8.i.i.i.i, align 8
  %t11.i.i.i.i = lshr i64 %t10.i.i.i.i, 1
  %t12.i.i.i.i = and i64 %t11.i.i.i.i, 16383
  %.t12.i.i.i.i = tail call i64 @llvm.umin.i64(i64 %t12.i.i.i.i, i64 47)
  %t22.i.i.i.i = shl nsw i64 -65536, %.t12.i.i.i.i
  %t23.i.i.i.i = and i64 %t22.i.i.i.i, 262144
  %t24.i.i.i.i = xor i64 %t23.i.i.i.i, 262144
  %t25.i.i.i.i = or i64 %t24.i.i.i.i, %t10.i.i.i.i
  store i64 %t25.i.i.i.i, ptr %t8.i.i.i.i, align 8
  %t5.i.i.i.i = inttoptr i64 %t0.i.i.i.i to ptr
  store i64 %s.2.0.i.i, ptr %t5.i.i.i.i, align 8
  %t6.i.i.i.i = getelementptr i8, ptr %t5.i.i.i.i, i64 8
  store i64 %t42, ptr %t6.i.i.i.i, align 8
  %t6.i5.i.i.i = getelementptr i8, ptr %t5.i.i.i.i, i64 16
  store i64 0, ptr %t6.i5.i.i.i, align 8
  %imm.i.i.i.i = icmp slt i64 %t0.i.i.i.i, 4096
  br i1 %imm.i.i.i.i, label %"Str$strFromLit.exit", label %chk.i.i.i.i

chk.i.i.i.i:                                      ; preds = %"Str$cstrLen.exit.i"
  %hoff.i.i.i.i = add nsw i64 %t0.i.i.i.i, -16
  %cp.i.i.i.i = inttoptr i64 %hoff.i.i.i.i to ptr
  %c.i.i.i.i = load i64, ptr %cp.i.i.i.i, align 8
  %stat.i.i.i.i = icmp eq i64 %c.i.i.i.i, -1
  br i1 %stat.i.i.i.i, label %"Str$strFromLit.exit", label %bump.i.i.i.i

bump.i.i.i.i:                                     ; preds = %chk.i.i.i.i
  %c1.i.i.i.i = add nuw i64 %c.i.i.i.i, 1
  store i64 %c1.i.i.i.i, ptr %cp.i.i.i.i, align 8
  br label %"Str$strFromLit.exit"

"Str$strFromLit.exit":                            ; preds = %"Str$cstrLen.exit.i", %chk.i.i.i.i, %bump.i.i.i.i
  %t44 = tail call i64 @"Str$strDup"(i64 %t0.i.i.i.i)
  tail call void @axiom_release(i64 %t0.i.i.i.i)
  %t45 = tail call i64 @"Vec$vecPush"(i64 %out, i64 %t44, i64 0)
  %t6 = add i64 %t29, 18
  %c8 = icmp sgt i64 %t6, %n
  br i1 %c8, label %label_13, label %label_12

label_13:                                         ; preds = %"Str$strFromLit.exit", %label_12, %0
  ret i64 0
}

define i64 @"Sys$sysGetCwd"() #0 {
label_6:
  %t0.i = tail call i64 @axiom_alloc(i64 4097)
  %t32 = tail call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 17, i64 %t0.i, i64 4096, i64 0, i64 0, i64 0, i64 0) #15
  %c33 = icmp slt i64 %t32, 0
  br i1 %c33, label %label_7, label %label_37

label_37:                                         ; preds = %label_6
  %t5.i.i = inttoptr i64 %t0.i to ptr
  br label %label_0.i.i

label_0.i.i:                                      ; preds = %label_0.i.i, %label_37
  %s.2.0.i.i = phi i64 [ 0, %label_37 ], [ %t18.i.i, %label_0.i.i ]
  %t6.i.i = getelementptr i8, ptr %t5.i.i, i64 %s.2.0.i.i
  %t7.i.i = load i8, ptr %t6.i.i, align 1
  %c9.i.i = icmp eq i8 %t7.i.i, 0
  %t18.i.i = add i64 %s.2.0.i.i, 1
  br i1 %c9.i.i, label %"Str$cstrLen.exit.i", label %label_0.i.i

"Str$cstrLen.exit.i":                             ; preds = %label_0.i.i
  %t0.i.i.i.i = tail call i64 @axiom_alloc(i64 24)
  %t7.i.i.i.i = add i64 %t0.i.i.i.i, -8
  %t8.i.i.i.i = inttoptr i64 %t7.i.i.i.i to ptr
  %t10.i.i.i.i = load i64, ptr %t8.i.i.i.i, align 8
  %t11.i.i.i.i = lshr i64 %t10.i.i.i.i, 1
  %t12.i.i.i.i = and i64 %t11.i.i.i.i, 16383
  %.t12.i.i.i.i = tail call i64 @llvm.umin.i64(i64 %t12.i.i.i.i, i64 47)
  %t22.i.i.i.i = shl nsw i64 -65536, %.t12.i.i.i.i
  %t23.i.i.i.i = and i64 %t22.i.i.i.i, 262144
  %t24.i.i.i.i = xor i64 %t23.i.i.i.i, 262144
  %t25.i.i.i.i = or i64 %t24.i.i.i.i, %t10.i.i.i.i
  store i64 %t25.i.i.i.i, ptr %t8.i.i.i.i, align 8
  %t5.i.i.i.i = inttoptr i64 %t0.i.i.i.i to ptr
  store i64 %s.2.0.i.i, ptr %t5.i.i.i.i, align 8
  %t6.i.i.i.i = getelementptr i8, ptr %t5.i.i.i.i, i64 8
  store i64 %t0.i, ptr %t6.i.i.i.i, align 8
  %t6.i5.i.i.i = getelementptr i8, ptr %t5.i.i.i.i, i64 16
  store i64 0, ptr %t6.i5.i.i.i, align 8
  %imm.i.i.i.i = icmp slt i64 %t0.i.i.i.i, 4096
  br i1 %imm.i.i.i.i, label %"Str$strFromLit.exit", label %chk.i.i.i.i

chk.i.i.i.i:                                      ; preds = %"Str$cstrLen.exit.i"
  %hoff.i.i.i.i = add nsw i64 %t0.i.i.i.i, -16
  %cp.i.i.i.i = inttoptr i64 %hoff.i.i.i.i to ptr
  %c.i.i.i.i = load i64, ptr %cp.i.i.i.i, align 8
  %stat.i.i.i.i = icmp eq i64 %c.i.i.i.i, -1
  br i1 %stat.i.i.i.i, label %"Str$strFromLit.exit", label %bump.i.i.i.i

bump.i.i.i.i:                                     ; preds = %chk.i.i.i.i
  %c1.i.i.i.i = add nuw i64 %c.i.i.i.i, 1
  store i64 %c1.i.i.i.i, ptr %cp.i.i.i.i, align 8
  br label %"Str$strFromLit.exit"

"Str$strFromLit.exit":                            ; preds = %"Str$cstrLen.exit.i", %chk.i.i.i.i, %bump.i.i.i.i
  %t41 = tail call i64 @"Str$strDup"(i64 %t0.i.i.i.i)
  tail call void @axiom_release(i64 %t0.i.i.i.i)
  br label %label_7

label_7:                                          ; preds = %label_6, %"Str$strFromLit.exit"
  %t43 = phi i64 [ %t41, %"Str$strFromLit.exit" ], [ ptrtoint (ptr getelementptr inbounds nuw (i8, ptr @strhdr_4, i64 16) to i64), %label_6 ]
  ret i64 %t43
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(read, inaccessiblemem: none, target_mem0: none, target_mem1: none)
define i64 @"Sys$sysEnvSlot"(i64 %i) #8 {
  %t0 = load i64, ptr @__axiom_argc, align 8
  %t3 = load i64, ptr @__axiom_argv, align 8
  %p4 = inttoptr i64 %t3 to ptr
  %1 = getelementptr i64, ptr %p4, i64 %t0
  %2 = getelementptr i8, ptr %1, i64 8
  %g5 = getelementptr i64, ptr %2, i64 %i
  %t6 = load i64, ptr %g5, align 8
  ret i64 %t6
}

; Function Attrs: nofree norecurse nosync nounwind memory(read, inaccessiblemem: none, target_mem0: none, target_mem1: none)
define i64 @"Sys$sysEnvCount"() #5 {
  %t0.i.i = load i64, ptr @__axiom_argc, align 8
  %t3.i.i = load i64, ptr @__axiom_argv, align 8
  %p4.i.i = inttoptr i64 %t3.i.i to ptr
  %1 = getelementptr i64, ptr %p4.i.i, i64 %t0.i.i
  %2 = getelementptr i8, ptr %1, i64 8
  br label %label_0.i

label_0.i:                                        ; preds = %label_0.i, %0
  %s.1.0.i = phi i64 [ 0, %0 ], [ %t12.i, %label_0.i ]
  %g5.i.i = getelementptr i64, ptr %2, i64 %s.1.0.i
  %t6.i.i = load i64, ptr %g5.i.i, align 8
  %c4.i = icmp eq i64 %t6.i.i, 0
  %t12.i = add i64 %s.1.0.i, 1
  br i1 %c4.i, label %"Sys$sysEnvCountFrom.exit", label %label_0.i

"Sys$sysEnvCountFrom.exit":                       ; preds = %label_0.i
  ret i64 %s.1.0.i
}

; Function Attrs: nofree norecurse nosync nounwind memory(read, inaccessiblemem: none, target_mem0: none, target_mem1: none)
define i64 @"Sys$sysEnvCountFrom"(i64 %i) #5 {
  %t0.i = load i64, ptr @__axiom_argc, align 8
  %t3.i = load i64, ptr @__axiom_argv, align 8
  %p4.i = inttoptr i64 %t3.i to ptr
  %1 = getelementptr i64, ptr %p4.i, i64 %t0.i
  %2 = getelementptr i8, ptr %1, i64 8
  br label %label_0

label_0:                                          ; preds = %label_0, %0
  %s.1.0 = phi i64 [ %i, %0 ], [ %t12, %label_0 ]
  %g5.i = getelementptr i64, ptr %2, i64 %s.1.0
  %t6.i = load i64, ptr %g5.i, align 8
  %c4 = icmp eq i64 %t6.i, 0
  %t12 = add i64 %s.1.0, 1
  br i1 %c4, label %label_7, label %label_0

label_7:                                          ; preds = %label_0
  ret i64 %s.1.0
}

define i64 @"Sys$sysEnv"(i64 %name) #0 {
  %t1 = tail call i64 @"Str$strConcat"(i64 %name, i64 ptrtoint (ptr getelementptr inbounds nuw (i8, ptr @strhdr_5, i64 16) to i64))
  tail call void @axiom_release(i64 ptrtoint (ptr getelementptr inbounds nuw (i8, ptr @strhdr_5, i64 16) to i64))
  %t2 = tail call i64 @"Sys$sysEnvLookup"(i64 %t1, i64 0)
  tail call void @axiom_release(i64 %t1)
  ret i64 %t2
}

define i64 @"Sys$sysEnvLookup"(i64 %prefix, i64 %i) #0 {
  %imm.i = icmp slt i64 %prefix, 4096
  br i1 %imm.i, label %axiom_retain.exit, label %chk.i

chk.i:                                            ; preds = %0
  %hoff.i = add nsw i64 %prefix, -16
  %cp.i = inttoptr i64 %hoff.i to ptr
  %c.i = load i64, ptr %cp.i, align 8
  %stat.i = icmp eq i64 %c.i, -1
  br i1 %stat.i, label %axiom_retain.exit, label %bump.i

bump.i:                                           ; preds = %chk.i
  %c1.i = add nuw i64 %c.i, 1
  store i64 %c1.i, ptr %cp.i, align 8
  br label %axiom_retain.exit

axiom_retain.exit:                                ; preds = %0, %chk.i, %bump.i
  %t0.i19 = load i64, ptr @__axiom_argc, align 8
  %t3.i20 = load i64, ptr @__axiom_argv, align 8
  %p4.i21 = inttoptr i64 %t3.i20 to ptr
  %1 = getelementptr i64, ptr %p4.i21, i64 %t0.i19
  %2 = getelementptr i8, ptr %1, i64 8
  %g5.i22 = getelementptr i64, ptr %2, i64 %i
  %t6.i23 = load i64, ptr %g5.i22, align 8
  %c524 = icmp eq i64 %t6.i23, 0
  br i1 %c524, label %label_10, label %label_9.lr.ph

label_9.lr.ph:                                    ; preds = %axiom_retain.exit
  %t0.i.i.i = inttoptr i64 %prefix to ptr
  %t1.i.i6.i = getelementptr i8, ptr %t0.i.i.i, i64 8
  br label %label_9

label_9:                                          ; preds = %label_9.lr.ph, %label_17
  %t6.i26 = phi i64 [ %t6.i23, %label_9.lr.ph ], [ %t6.i, %label_17 ]
  %s.2.025 = phi i64 [ %i, %label_9.lr.ph ], [ %t28, %label_17 ]
  %t5.i.i = inttoptr i64 %t6.i26 to ptr
  br label %label_0.i.i

label_0.i.i:                                      ; preds = %label_0.i.i, %label_9
  %s.2.0.i.i = phi i64 [ 0, %label_9 ], [ %t18.i.i, %label_0.i.i ]
  %t6.i.i = getelementptr i8, ptr %t5.i.i, i64 %s.2.0.i.i
  %t7.i.i = load i8, ptr %t6.i.i, align 1
  %c9.i.i = icmp eq i8 %t7.i.i, 0
  %t18.i.i = add i64 %s.2.0.i.i, 1
  br i1 %c9.i.i, label %"Str$cstrLen.exit.i", label %label_0.i.i

"Str$cstrLen.exit.i":                             ; preds = %label_0.i.i
  %t0.i.i.i.i = tail call i64 @axiom_alloc(i64 24)
  %t7.i.i.i.i = add i64 %t0.i.i.i.i, -8
  %t8.i.i.i.i = inttoptr i64 %t7.i.i.i.i to ptr
  %t10.i.i.i.i = load i64, ptr %t8.i.i.i.i, align 8
  %t11.i.i.i.i = lshr i64 %t10.i.i.i.i, 1
  %t12.i.i.i.i = and i64 %t11.i.i.i.i, 16383
  %.t12.i.i.i.i = tail call i64 @llvm.umin.i64(i64 %t12.i.i.i.i, i64 47)
  %t22.i.i.i.i = shl nsw i64 -65536, %.t12.i.i.i.i
  %t23.i.i.i.i = and i64 %t22.i.i.i.i, 262144
  %t24.i.i.i.i = xor i64 %t23.i.i.i.i, 262144
  %t25.i.i.i.i = or i64 %t24.i.i.i.i, %t10.i.i.i.i
  store i64 %t25.i.i.i.i, ptr %t8.i.i.i.i, align 8
  %t5.i.i.i.i = inttoptr i64 %t0.i.i.i.i to ptr
  store i64 %s.2.0.i.i, ptr %t5.i.i.i.i, align 8
  %t6.i.i.i.i = getelementptr i8, ptr %t5.i.i.i.i, i64 8
  store i64 %t6.i26, ptr %t6.i.i.i.i, align 8
  %t6.i5.i.i.i = getelementptr i8, ptr %t5.i.i.i.i, i64 16
  store i64 0, ptr %t6.i5.i.i.i, align 8
  %imm.i.i.i.i = icmp slt i64 %t0.i.i.i.i, 4096
  br i1 %imm.i.i.i.i, label %"Str$strFromLit.exit", label %chk.i.i.i.i

chk.i.i.i.i:                                      ; preds = %"Str$cstrLen.exit.i"
  %hoff.i.i.i.i = add nsw i64 %t0.i.i.i.i, -16
  %cp.i.i.i.i = inttoptr i64 %hoff.i.i.i.i to ptr
  %c.i.i.i.i = load i64, ptr %cp.i.i.i.i, align 8
  %stat.i.i.i.i = icmp eq i64 %c.i.i.i.i, -1
  br i1 %stat.i.i.i.i, label %"Str$strFromLit.exit", label %bump.i.i.i.i

bump.i.i.i.i:                                     ; preds = %chk.i.i.i.i
  %c1.i.i.i.i = add nuw i64 %c.i.i.i.i, 1
  store i64 %c1.i.i.i.i, ptr %cp.i.i.i.i, align 8
  br label %"Str$strFromLit.exit"

"Str$strFromLit.exit":                            ; preds = %"Str$cstrLen.exit.i", %chk.i.i.i.i, %bump.i.i.i.i
  %t2.i.i.i = load i64, ptr %t0.i.i.i, align 8
  %t2.i.i2.i = load i64, ptr %t5.i.i.i.i, align 8
  %c2.i = icmp sgt i64 %t2.i.i.i, %t2.i.i2.i
  br i1 %c2.i, label %label_17, label %label_6.i

label_6.i:                                        ; preds = %"Str$strFromLit.exit"
  %c65.i.i.i = icmp sgt i64 %t2.i.i.i, 0
  br i1 %c65.i.i.i, label %label_3.lr.ph.i.i.i, label %label_16

label_3.lr.ph.i.i.i:                              ; preds = %label_6.i
  %t2.i.i7.i = load i64, ptr %t1.i.i6.i, align 8
  %t2.i.i4.i = load i64, ptr %t6.i.i.i.i, align 8
  %t20.i.i.i = inttoptr i64 %t2.i.i4.i to ptr
  %t25.i.i.i = inttoptr i64 %t2.i.i7.i to ptr
  br label %label_3.i.i.i

label_3.i.i.i:                                    ; preds = %label_3.i.i.i, %label_3.lr.ph.i.i.i
  %s.0.06.i.i.i = phi i64 [ 0, %label_3.lr.ph.i.i.i ], [ %t31.i.i.i, %label_3.i.i.i ]
  %t21.i.i.i = getelementptr i8, ptr %t20.i.i.i, i64 %s.0.06.i.i.i
  %t22.i.i.i = load i8, ptr %t21.i.i.i, align 1
  %t26.i.i.i = getelementptr i8, ptr %t25.i.i.i, i64 %s.0.06.i.i.i
  %t27.i.i.i = load i8, ptr %t26.i.i.i, align 1
  %t31.i.i.i = add nuw nsw i64 %s.0.06.i.i.i, 1
  %c6.i.i.i = icmp slt i64 %t31.i.i.i, %t2.i.i.i
  %c13.i.i.i = icmp eq i8 %t22.i.i.i, %t27.i.i.i
  %narrow.i.i.i = select i1 %c6.i.i.i, i1 %c13.i.i.i, i1 false
  br i1 %narrow.i.i.i, label %label_3.i.i.i, label %"Mem$memCmp.exit.loopexit.i"

"Mem$memCmp.exit.loopexit.i":                     ; preds = %label_3.i.i.i
  br i1 %c13.i.i.i, label %label_16, label %label_17

label_16:                                         ; preds = %label_6.i, %"Mem$memCmp.exit.loopexit.i"
  %t6.i5.i.i.i.le = getelementptr i8, ptr %t5.i.i.i.i, i64 16
  %t24 = sub i64 %t2.i.i2.i, %t2.i.i.i
  %c1.i14 = icmp slt i64 %t2.i.i.i, 0
  %t0.start.i = tail call i64 @llvm.smin.i64(i64 %t2.i.i.i, i64 %t2.i.i2.i)
  %t14.i = select i1 %c1.i14, i64 0, i64 %t0.start.i
  %t15.i = sub i64 %t2.i.i2.i, %t14.i
  %c16.i = icmp slt i64 %t24, 0
  %t15.count.i = tail call i64 @llvm.smin.i64(i64 %t24, i64 %t15.i)
  %t29.i = select i1 %c16.i, i64 0, i64 %t15.count.i
  %t2.i.i2.i16 = load i64, ptr %t6.i5.i.i.i.le, align 8
  %imm.i.i = icmp slt i64 %t2.i.i2.i16, 4096
  br i1 %imm.i.i, label %axiom_retain.exit.i, label %chk.i.i

chk.i.i:                                          ; preds = %label_16
  %hoff.i.i = add nsw i64 %t2.i.i2.i16, -16
  %cp.i.i = inttoptr i64 %hoff.i.i to ptr
  %c.i.i = load i64, ptr %cp.i.i, align 8
  %stat.i.i = icmp eq i64 %c.i.i, -1
  br i1 %stat.i.i, label %axiom_retain.exit.i, label %bump.i.i

bump.i.i:                                         ; preds = %chk.i.i
  %c1.i.i = add nuw i64 %c.i.i, 1
  store i64 %c1.i.i, ptr %cp.i.i, align 8
  br label %axiom_retain.exit.i

axiom_retain.exit.i:                              ; preds = %bump.i.i, %chk.i.i, %label_16
  %t2.i.i5.i = load i64, ptr %t6.i.i.i.i, align 8
  %t32.i = add i64 %t2.i.i5.i, %t14.i
  %t0.i.i6.i = tail call i64 @axiom_alloc(i64 24)
  %t7.i.i.i = add i64 %t0.i.i6.i, -8
  %t8.i.i.i = inttoptr i64 %t7.i.i.i to ptr
  %t10.i.i.i = load i64, ptr %t8.i.i.i, align 8
  %t11.i.i.i = lshr i64 %t10.i.i.i, 1
  %t12.i.i.i = and i64 %t11.i.i.i, 16383
  %.t12.i.i.i = tail call i64 @llvm.umin.i64(i64 %t12.i.i.i, i64 47)
  %t22.i.i.i17 = shl nsw i64 -65536, %.t12.i.i.i
  %t23.i.i.i = and i64 %t22.i.i.i17, 262144
  %t24.i.i.i = xor i64 %t23.i.i.i, 262144
  %t25.i.i.i18 = or i64 %t24.i.i.i, %t10.i.i.i
  store i64 %t25.i.i.i18, ptr %t8.i.i.i, align 8
  %t5.i.i.i = inttoptr i64 %t0.i.i6.i to ptr
  store i64 %t29.i, ptr %t5.i.i.i, align 8
  %t6.i.i.i = getelementptr i8, ptr %t5.i.i.i, i64 8
  store i64 %t32.i, ptr %t6.i.i.i, align 8
  %t6.i5.i.i = getelementptr i8, ptr %t5.i.i.i, i64 16
  store i64 %t2.i.i2.i16, ptr %t6.i5.i.i, align 8
  %imm.i.i.i = icmp slt i64 %t0.i.i6.i, 4096
  br i1 %imm.i.i.i, label %"Str$strSlice.exit", label %chk.i.i.i

chk.i.i.i:                                        ; preds = %axiom_retain.exit.i
  %hoff.i.i.i = add nsw i64 %t0.i.i6.i, -16
  %cp.i.i.i = inttoptr i64 %hoff.i.i.i to ptr
  %c.i.i.i = load i64, ptr %cp.i.i.i, align 8
  %stat.i.i.i = icmp eq i64 %c.i.i.i, -1
  br i1 %stat.i.i.i, label %"Str$strSlice.exit", label %bump.i.i.i

bump.i.i.i:                                       ; preds = %chk.i.i.i
  %c1.i.i.i = add nuw i64 %c.i.i.i, 1
  store i64 %c1.i.i.i, ptr %cp.i.i.i, align 8
  br label %"Str$strSlice.exit"

"Str$strSlice.exit":                              ; preds = %axiom_retain.exit.i, %chk.i.i.i, %bump.i.i.i
  tail call void @axiom_release(i64 %t0.i.i.i.i)
  br label %label_10

label_17:                                         ; preds = %"Str$strFromLit.exit", %"Mem$memCmp.exit.loopexit.i"
  %t28 = add i64 %s.2.025, 1
  tail call void @axiom_release(i64 %t0.i.i.i.i)
  %t0.i = load i64, ptr @__axiom_argc, align 8
  %t3.i = load i64, ptr @__axiom_argv, align 8
  %p4.i = inttoptr i64 %t3.i to ptr
  %3 = getelementptr i64, ptr %p4.i, i64 %t0.i
  %4 = getelementptr i8, ptr %3, i64 8
  %g5.i = getelementptr i64, ptr %4, i64 %t28
  %t6.i = load i64, ptr %g5.i, align 8
  %c5 = icmp eq i64 %t6.i, 0
  br i1 %c5, label %label_10, label %label_9

label_10:                                         ; preds = %label_17, %axiom_retain.exit, %"Str$strSlice.exit"
  %t30 = phi i64 [ %t0.i.i6.i, %"Str$strSlice.exit" ], [ ptrtoint (ptr getelementptr inbounds nuw (i8, ptr @strhdr_4, i64 16) to i64), %axiom_retain.exit ], [ ptrtoint (ptr getelementptr inbounds nuw (i8, ptr @strhdr_4, i64 16) to i64), %label_17 ]
  tail call void @axiom_release(i64 %prefix)
  ret i64 %t30
}

; Function Attrs: nounwind
define i64 @"Sys$sysEnvp"() #1 {
  %t0.i.i.i = load i64, ptr @__axiom_argc, align 8
  %t3.i.i.i = load i64, ptr @__axiom_argv, align 8
  %p4.i.i.i = inttoptr i64 %t3.i.i.i to ptr
  %1 = getelementptr i64, ptr %p4.i.i.i, i64 %t0.i.i.i
  %2 = getelementptr i8, ptr %1, i64 8
  br label %label_0.i.i

label_0.i.i:                                      ; preds = %label_0.i.i, %0
  %s.1.0.i.i = phi i64 [ 0, %0 ], [ %t12.i.i, %label_0.i.i ]
  %g5.i.i.i = getelementptr i64, ptr %2, i64 %s.1.0.i.i
  %t6.i.i.i = load i64, ptr %g5.i.i.i, align 8
  %c4.i.i = icmp eq i64 %t6.i.i.i, 0
  %t12.i.i = add i64 %s.1.0.i.i, 1
  br i1 %c4.i.i, label %"Sys$sysEnvCount.exit", label %label_0.i.i

"Sys$sysEnvCount.exit":                           ; preds = %label_0.i.i
  %t1 = shl i64 %s.1.0.i.i, 3
  %t2 = add i64 %t1, 8
  %t0.i = tail call i64 @axiom_alloc(i64 %t2)
  %c6.not11.i = icmp sgt i64 %s.1.0.i.i, 0
  br i1 %c6.not11.i, label %label_10.lr.ph.i, label %"Sys$sysEnvpFill.exit"

label_10.lr.ph.i:                                 ; preds = %"Sys$sysEnvCount.exit"
  %t5.i9.i = inttoptr i64 %t0.i to ptr
  br label %label_10.i

label_10.i:                                       ; preds = %label_10.i, %label_10.lr.ph.i
  %s.2.012.i = phi i64 [ 0, %label_10.lr.ph.i ], [ %t22.i, %label_10.i ]
  %t0.i.i = load i64, ptr @__axiom_argc, align 8
  %t3.i.i = load i64, ptr @__axiom_argv, align 8
  %p4.i.i = inttoptr i64 %t3.i.i to ptr
  %3 = getelementptr i64, ptr %p4.i.i, i64 %t0.i.i
  %4 = getelementptr i8, ptr %3, i64 8
  %g5.i.i = getelementptr i64, ptr %4, i64 %s.2.012.i
  %t6.i8.i = load i64, ptr %g5.i.i, align 8
  %t6.i10.i = getelementptr i64, ptr %t5.i9.i, i64 %s.2.012.i
  store i64 %t6.i8.i, ptr %t6.i10.i, align 8
  %t22.i = add nuw nsw i64 %s.2.012.i, 1
  %exitcond.not.i = icmp eq i64 %t22.i, %s.1.0.i.i
  br i1 %exitcond.not.i, label %"Sys$sysEnvpFill.exit", label %label_10.i

"Sys$sysEnvpFill.exit":                           ; preds = %label_10.i, %"Sys$sysEnvCount.exit"
  %t5.i.i = inttoptr i64 %t0.i to ptr
  %t6.i.i = getelementptr i64, ptr %t5.i.i, i64 %s.1.0.i.i
  store i64 0, ptr %t6.i.i, align 8
  ret i64 %t0.i
}

; Function Attrs: nofree norecurse nosync nounwind memory(readwrite, inaccessiblemem: none, target_mem0: none, target_mem1: none)
define i64 @"Sys$sysEnvpFill"(i64 returned %v, i64 %i, i64 %n) #3 {
  %c6.not11 = icmp slt i64 %i, %n
  br i1 %c6.not11, label %label_10.lr.ph, label %label_9

label_10.lr.ph:                                   ; preds = %0
  %t5.i9 = inttoptr i64 %v to ptr
  br label %label_10

label_9:                                          ; preds = %label_10, %0
  %t5.i = inttoptr i64 %v to ptr
  %t6.i = getelementptr i64, ptr %t5.i, i64 %n
  store i64 0, ptr %t6.i, align 8
  ret i64 %v

label_10:                                         ; preds = %label_10.lr.ph, %label_10
  %s.2.012 = phi i64 [ %i, %label_10.lr.ph ], [ %t22, %label_10 ]
  %t0.i = load i64, ptr @__axiom_argc, align 8
  %t3.i = load i64, ptr @__axiom_argv, align 8
  %p4.i = inttoptr i64 %t3.i to ptr
  %1 = getelementptr i64, ptr %p4.i, i64 %t0.i
  %2 = getelementptr i8, ptr %1, i64 8
  %g5.i = getelementptr i64, ptr %2, i64 %s.2.012
  %t6.i8 = load i64, ptr %g5.i, align 8
  %t6.i10 = getelementptr i64, ptr %t5.i9, i64 %s.2.012
  store i64 %t6.i8, ptr %t6.i10, align 8
  %t22 = add nsw i64 %s.2.012, 1
  %exitcond.not = icmp eq i64 %t22, %n
  br i1 %exitcond.not, label %label_9, label %label_10
}

; Function Attrs: nounwind
define i64 @"Sys$sysSpawn"(i64 %path, i64 %argv, i64 %envp) #1 {
label_5:
  %t9.i.i = tail call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 56, i64 -100, i64 %path, i64 0, i64 420, i64 0, i64 0) #15
  %c22 = icmp eq i64 %t9.i.i, -2
  br i1 %c22, label %label_6, label %label_26

label_26:                                         ; preds = %label_5
  %c28 = icmp sgt i64 %t9.i.i, -1
  br i1 %c28, label %label_31, label %label_33

label_31:                                         ; preds = %label_26
  %t1.i = tail call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 57, i64 %t9.i.i, i64 0, i64 0, i64 0, i64 0, i64 0) #15
  br label %label_33

label_33:                                         ; preds = %label_26, %label_31
  %t2.i = tail call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 220, i64 17, i64 0, i64 0, i64 0, i64 0, i64 0) #15
  %c43 = icmp eq i64 %t2.i, 0
  br i1 %c43, label %label_46, label %label_6

label_46:                                         ; preds = %label_33
  %t50 = tail call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 221, i64 %path, i64 %argv, i64 %envp, i64 0, i64 0, i64 0) #15
  %t52 = tail call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 94, i64 127, i64 0, i64 0, i64 0, i64 0, i64 0) #15
  br label %label_6

label_6:                                          ; preds = %label_5, %label_46, %label_33
  %t56 = phi i64 [ 0, %label_46 ], [ %t2.i, %label_33 ], [ -2, %label_5 ]
  ret i64 %t56
}

; Function Attrs: nounwind
define i64 @"Sys$sysWaitPid"(i64 %pid) #1 {
  %t0.i = tail call i64 @axiom_alloc(i64 8)
  %t5.i = inttoptr i64 %t0.i to ptr
  store i64 0, ptr %t5.i, align 8
  %t3 = tail call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 260, i64 %pid, i64 %t0.i, i64 0, i64 0, i64 0, i64 0) #15
  %c4 = icmp slt i64 %t3, 0
  br i1 %c4, label %label_9, label %label_8

label_8:                                          ; preds = %0
  %t2.i = load i64, ptr %t5.i, align 8
  br label %label_9

label_9:                                          ; preds = %0, %label_8
  %t11 = phi i64 [ %t2.i, %label_8 ], [ %t3, %0 ]
  ret i64 %t11
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(none)
define range(i64 0, 256) i64 @"Sys$sysExitCode"(i64 %status) #6 {
  %t0 = lshr i64 %status, 8
  %t1 = and i64 %t0, 255
  ret i64 %t1
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(none)
define range(i64 0, 128) i64 @"Sys$sysTermSignal"(i64 %status) #6 {
  %t0 = and i64 %status, 127
  ret i64 %t0
}

; Function Attrs: nounwind
define range(i64 -9223372036854775808, 256) i64 @"Sys$sysRun"(i64 %path, i64 %argv, i64 %envp) #1 {
  %t9.i.i.i = tail call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 56, i64 -100, i64 %path, i64 0, i64 420, i64 0, i64 0) #15
  %c22.i = icmp eq i64 %t9.i.i.i, -2
  br i1 %c22.i, label %"Sys$sysSpawn.exit", label %label_26.i

label_26.i:                                       ; preds = %0
  %c28.i = icmp sgt i64 %t9.i.i.i, -1
  br i1 %c28.i, label %label_31.i, label %label_33.i

label_31.i:                                       ; preds = %label_26.i
  %t1.i.i = tail call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 57, i64 %t9.i.i.i, i64 0, i64 0, i64 0, i64 0, i64 0) #15
  br label %label_33.i

label_33.i:                                       ; preds = %label_31.i, %label_26.i
  %t2.i.i = tail call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 220, i64 17, i64 0, i64 0, i64 0, i64 0, i64 0) #15
  %c43.i = icmp eq i64 %t2.i.i, 0
  br i1 %c43.i, label %label_46.i, label %"Sys$sysSpawn.exit"

label_46.i:                                       ; preds = %label_33.i
  %t50.i = tail call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 221, i64 %path, i64 %argv, i64 %envp, i64 0, i64 0, i64 0) #15
  %t52.i = tail call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 94, i64 127, i64 0, i64 0, i64 0, i64 0, i64 0) #15
  br label %"Sys$sysSpawn.exit"

"Sys$sysSpawn.exit":                              ; preds = %0, %label_33.i, %label_46.i
  %t56.i = phi i64 [ 0, %label_46.i ], [ %t2.i.i, %label_33.i ], [ -2, %0 ]
  %c1 = icmp slt i64 %t56.i, 0
  br i1 %c1, label %label_6, label %label_5

label_5:                                          ; preds = %"Sys$sysSpawn.exit"
  %t0.i.i = tail call i64 @axiom_alloc(i64 8)
  %t5.i.i = inttoptr i64 %t0.i.i to ptr
  store i64 0, ptr %t5.i.i, align 8
  %t3.i = tail call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 260, i64 %t56.i, i64 %t0.i.i, i64 0, i64 0, i64 0, i64 0) #15
  %c4.i = icmp slt i64 %t3.i, 0
  br i1 %c4.i, label %"Sys$sysWaitPid.exit", label %label_8.i

label_8.i:                                        ; preds = %label_5
  %t2.i.i1 = load i64, ptr %t5.i.i, align 8
  br label %"Sys$sysWaitPid.exit"

"Sys$sysWaitPid.exit":                            ; preds = %label_5, %label_8.i
  %t11.i = phi i64 [ %t2.i.i1, %label_8.i ], [ %t3.i, %label_5 ]
  %c8 = icmp slt i64 %t11.i, 0
  br i1 %c8, label %label_6, label %label_12

label_12:                                         ; preds = %"Sys$sysWaitPid.exit"
  %t0.i = and i64 %t11.i, 127
  %c15.not = icmp eq i64 %t0.i, 0
  br i1 %c15.not, label %label_19, label %label_18

label_18:                                         ; preds = %label_12
  %t22 = or disjoint i64 %t0.i, 128
  br label %label_6

label_19:                                         ; preds = %label_12
  %t0.i3 = lshr i64 %t11.i, 8
  %t1.i = and i64 %t0.i3, 255
  br label %label_6

label_6:                                          ; preds = %"Sys$sysWaitPid.exit", %label_19, %label_18, %"Sys$sysSpawn.exit"
  %t26 = phi i64 [ %t56.i, %"Sys$sysSpawn.exit" ], [ %t11.i, %"Sys$sysWaitPid.exit" ], [ %t22, %label_18 ], [ %t1.i, %label_19 ]
  ret i64 %t26
}

define range(i64 -9223372036854775808, 256) i64 @"Sys$sysRunPath"(i64 %name, i64 %argv, i64 %envp) #0 {
  %imm.i.i = icmp slt i64 %name, 4096
  br i1 %imm.i.i, label %axiom_retain.exit.i, label %chk.i.i

chk.i.i:                                          ; preds = %0
  %hoff.i.i = add nsw i64 %name, -16
  %cp.i.i = inttoptr i64 %hoff.i.i to ptr
  %c.i.i = load i64, ptr %cp.i.i, align 8
  %stat.i.i = icmp eq i64 %c.i.i, -1
  br i1 %stat.i.i, label %axiom_retain.exit.i, label %bump.i.i

bump.i.i:                                         ; preds = %chk.i.i
  %c1.i.i = add nuw i64 %c.i.i, 1
  store i64 %c1.i.i, ptr %cp.i.i, align 8
  br label %axiom_retain.exit.i

axiom_retain.exit.i:                              ; preds = %bump.i.i, %chk.i.i, %0
  %t0.i.i.i = inttoptr i64 %name to ptr
  %t2.i.i.i = load i64, ptr %t0.i.i.i, align 8
  %c7.not9.i = icmp sgt i64 %t2.i.i.i, 0
  br i1 %c7.not9.i, label %label_11.lr.ph.i, label %label_5.critedge

label_11.lr.ph.i:                                 ; preds = %axiom_retain.exit.i
  %t1.i.i.i.i = getelementptr i8, ptr %t0.i.i.i, i64 8
  %t2.i.i2.i.i = load i64, ptr %t1.i.i.i.i, align 8
  %t14.i.i = inttoptr i64 %t2.i.i2.i.i to ptr
  br label %label_11.i

label_11.i:                                       ; preds = %label_22.i, %label_11.lr.ph.i
  %s.3.010.i = phi i64 [ 0, %label_11.lr.ph.i ], [ %t28.i, %label_22.i ]
  %t15.i.i = getelementptr i8, ptr %t14.i.i, i64 %s.3.010.i
  %t16.i.i = load i8, ptr %t15.i.i, align 1
  %c18.i = icmp eq i8 %t16.i.i, 47
  br i1 %c18.i, label %"Str$strFindByte.exit.loopexit", label %label_22.i

label_22.i:                                       ; preds = %label_11.i
  %t28.i = add nuw nsw i64 %s.3.010.i, 1
  %exitcond.not.i = icmp eq i64 %t28.i, %t2.i.i.i
  br i1 %exitcond.not.i, label %"Str$strFindByte.exit.loopexit", label %label_11.i

"Str$strFindByte.exit.loopexit":                  ; preds = %label_22.i, %label_11.i
  %t30.i.ph = phi i64 [ -1, %label_22.i ], [ %s.3.010.i, %label_11.i ]
  %1 = icmp sgt i64 %t30.i.ph, -1
  tail call void @axiom_release(i64 %name)
  br i1 %1, label %label_4, label %label_5

label_4:                                          ; preds = %"Str$strFindByte.exit.loopexit"
  %t7 = tail call i64 @"Str$strDup"(i64 %name)
  %t0.i.i.i1 = inttoptr i64 %t7 to ptr
  %t1.i.i.i = getelementptr i8, ptr %t0.i.i.i1, i64 8
  %t2.i.i.i2 = load i64, ptr %t1.i.i.i, align 8
  %t9 = tail call i64 @"Sys$sysRun"(i64 %t2.i.i.i2, i64 %argv, i64 %envp)
  br label %label_6

label_5.critedge:                                 ; preds = %axiom_retain.exit.i
  tail call void @axiom_release(i64 %name)
  br label %label_5

label_5:                                          ; preds = %label_5.critedge, %"Str$strFindByte.exit.loopexit"
  %t1.i = tail call i64 @"Str$strConcat"(i64 ptrtoint (ptr getelementptr inbounds nuw (i8, ptr @strhdr_6, i64 16) to i64), i64 ptrtoint (ptr getelementptr inbounds nuw (i8, ptr @strhdr_5, i64 16) to i64))
  tail call void @axiom_release(i64 ptrtoint (ptr getelementptr inbounds nuw (i8, ptr @strhdr_5, i64 16) to i64))
  %t2.i = tail call i64 @"Sys$sysEnvLookup"(i64 %t1.i, i64 0)
  tail call void @axiom_release(i64 %t1.i)
  tail call void @axiom_release(i64 ptrtoint (ptr getelementptr inbounds nuw (i8, ptr @strhdr_6, i64 16) to i64))
  %t0.i.i = inttoptr i64 %t2.i to ptr
  %t2.i.i = load i64, ptr %t0.i.i, align 8
  %c13 = icmp eq i64 %t2.i.i, 0
  br i1 %c13, label %label_18, label %label_17

label_17:                                         ; preds = %label_5
  %t20 = tail call i64 @"Sys$sysRunSearch"(i64 %name, i64 %argv, i64 %envp, i64 %t2.i, i64 0)
  br label %label_18

label_18:                                         ; preds = %label_5, %label_17
  %t21 = phi i64 [ %t20, %label_17 ], [ -2, %label_5 ]
  tail call void @axiom_release(i64 %t2.i)
  br label %label_6

label_6:                                          ; preds = %label_18, %label_4
  %t22 = phi i64 [ %t9, %label_4 ], [ %t21, %label_18 ]
  ret i64 %t22
}

define range(i64 -2, 256) i64 @"Sys$sysRunSearch"(i64 %name, i64 %argv, i64 %envp, i64 %path, i64 %from) #0 {
  %imm.i = icmp slt i64 %name, 4096
  br i1 %imm.i, label %axiom_retain.exit, label %chk.i

chk.i:                                            ; preds = %0
  %hoff.i = add nsw i64 %name, -16
  %cp.i = inttoptr i64 %hoff.i to ptr
  %c.i = load i64, ptr %cp.i, align 8
  %stat.i = icmp eq i64 %c.i, -1
  br i1 %stat.i, label %axiom_retain.exit, label %bump.i

bump.i:                                           ; preds = %chk.i
  %c1.i = add nuw i64 %c.i, 1
  store i64 %c1.i, ptr %cp.i, align 8
  br label %axiom_retain.exit

axiom_retain.exit:                                ; preds = %0, %chk.i, %bump.i
  %imm.i27 = icmp slt i64 %path, 4096
  br i1 %imm.i27, label %axiom_retain.exit35, label %chk.i28

chk.i28:                                          ; preds = %axiom_retain.exit
  %hoff.i29 = add nsw i64 %path, -16
  %cp.i30 = inttoptr i64 %hoff.i29 to ptr
  %c.i31 = load i64, ptr %cp.i30, align 8
  %stat.i32 = icmp eq i64 %c.i31, -1
  br i1 %stat.i32, label %axiom_retain.exit35, label %bump.i33

bump.i33:                                         ; preds = %chk.i28
  %c1.i34 = add nuw i64 %c.i31, 1
  store i64 %c1.i34, ptr %cp.i30, align 8
  br label %axiom_retain.exit35

axiom_retain.exit35:                              ; preds = %axiom_retain.exit, %chk.i28, %bump.i33
  %t0.i.i = inttoptr i64 %path to ptr
  %t2.i.i55 = load i64, ptr %t0.i.i, align 8
  %c9.not56 = icmp slt i64 %from, %t2.i.i55
  br i1 %c9.not56, label %label_13.lr.ph, label %label_14

label_13.lr.ph:                                   ; preds = %axiom_retain.exit35
  %hoff.i.i = add nsw i64 %path, -16
  %cp.i.i = inttoptr i64 %hoff.i.i to ptr
  %t1.i.i.i.i = getelementptr i8, ptr %t0.i.i, i64 8
  %t1.i.i.i = getelementptr i8, ptr %t0.i.i, i64 16
  %t1.i.i4.i = getelementptr i8, ptr %t0.i.i, i64 8
  br label %label_13

label_13:                                         ; preds = %label_13.lr.ph, %label_0.backedge
  %s.5.057 = phi i64 [ %from, %label_13.lr.ph ], [ %s.5.0.be, %label_0.backedge ]
  br i1 %imm.i27, label %axiom_retain.exit.i, label %chk.i.i

chk.i.i:                                          ; preds = %label_13
  %c.i.i = load i64, ptr %cp.i.i, align 8
  %stat.i.i = icmp eq i64 %c.i.i, -1
  br i1 %stat.i.i, label %axiom_retain.exit.i, label %bump.i.i

bump.i.i:                                         ; preds = %chk.i.i
  %c1.i.i = add nuw i64 %c.i.i, 1
  store i64 %c1.i.i, ptr %cp.i.i, align 8
  br label %axiom_retain.exit.i

axiom_retain.exit.i:                              ; preds = %bump.i.i, %chk.i.i, %label_13
  %t2.i.i.i = load i64, ptr %t0.i.i, align 8
  %c7.not9.i = icmp slt i64 %s.5.057, %t2.i.i.i
  br i1 %c7.not9.i, label %label_11.i, label %"Str$strFindByte.exit"

label_11.i:                                       ; preds = %axiom_retain.exit.i, %label_22.i
  %s.3.010.i = phi i64 [ %t28.i, %label_22.i ], [ %s.5.057, %axiom_retain.exit.i ]
  %c0.i.i = icmp slt i64 %s.3.010.i, 0
  br i1 %c0.i.i, label %label_22.i, label %label_11.i.i

label_11.i.i:                                     ; preds = %label_11.i
  %t2.i.i2.i.i = load i64, ptr %t1.i.i.i.i, align 8
  %t14.i.i = inttoptr i64 %t2.i.i2.i.i to ptr
  %t15.i.i = getelementptr i8, ptr %t14.i.i, i64 %s.3.010.i
  %t16.i.i = load i8, ptr %t15.i.i, align 1
  %1 = icmp eq i8 %t16.i.i, 58
  br i1 %1, label %"Str$strFindByte.exit", label %label_22.i

label_22.i:                                       ; preds = %label_11.i, %label_11.i.i
  %t28.i = add nsw i64 %s.3.010.i, 1
  %exitcond.not.i = icmp eq i64 %t28.i, %t2.i.i.i
  br i1 %exitcond.not.i, label %"Str$strFindByte.exit", label %label_11.i

"Str$strFindByte.exit":                           ; preds = %label_11.i.i, %label_22.i, %axiom_retain.exit.i
  %t30.i = phi i64 [ -1, %axiom_retain.exit.i ], [ -1, %label_22.i ], [ %s.3.010.i, %label_11.i.i ]
  tail call void @axiom_release(i64 %path)
  %c19 = icmp slt i64 %t30.i, 0
  br i1 %c19, label %label_22, label %label_24

label_22:                                         ; preds = %"Str$strFindByte.exit"
  %t2.i.i37 = load i64, ptr %t0.i.i, align 8
  br label %label_24

label_24:                                         ; preds = %"Str$strFindByte.exit", %label_22
  %t27 = phi i64 [ %t2.i.i37, %label_22 ], [ %t30.i, %"Str$strFindByte.exit" ]
  %t31 = sub i64 %t27, %s.5.057
  %t2.i.i.i39 = load i64, ptr %t0.i.i, align 8
  %c1.i40 = icmp slt i64 %s.5.057, 0
  %t0.start.i = tail call i64 @llvm.smin.i64(i64 %s.5.057, i64 %t2.i.i.i39)
  %t14.i = select i1 %c1.i40, i64 0, i64 %t0.start.i
  %t15.i = sub i64 %t2.i.i.i39, %t14.i
  %c16.i = icmp slt i64 %t31, 0
  %t15.count.i = tail call i64 @llvm.smin.i64(i64 %t31, i64 %t15.i)
  %t29.i = select i1 %c16.i, i64 0, i64 %t15.count.i
  %t2.i.i2.i = load i64, ptr %t1.i.i.i, align 8
  %imm.i.i41 = icmp slt i64 %t2.i.i2.i, 4096
  br i1 %imm.i.i41, label %axiom_retain.exit.i49, label %chk.i.i42

chk.i.i42:                                        ; preds = %label_24
  %hoff.i.i43 = add nsw i64 %t2.i.i2.i, -16
  %cp.i.i44 = inttoptr i64 %hoff.i.i43 to ptr
  %c.i.i45 = load i64, ptr %cp.i.i44, align 8
  %stat.i.i46 = icmp eq i64 %c.i.i45, -1
  br i1 %stat.i.i46, label %axiom_retain.exit.i49, label %bump.i.i47

bump.i.i47:                                       ; preds = %chk.i.i42
  %c1.i.i48 = add nuw i64 %c.i.i45, 1
  store i64 %c1.i.i48, ptr %cp.i.i44, align 8
  br label %axiom_retain.exit.i49

axiom_retain.exit.i49:                            ; preds = %bump.i.i47, %chk.i.i42, %label_24
  %t2.i.i5.i = load i64, ptr %t1.i.i4.i, align 8
  %t32.i = add i64 %t2.i.i5.i, %t14.i
  %t0.i.i6.i = tail call i64 @axiom_alloc(i64 24)
  %t7.i.i.i = add i64 %t0.i.i6.i, -8
  %t8.i.i.i = inttoptr i64 %t7.i.i.i to ptr
  %t10.i.i.i = load i64, ptr %t8.i.i.i, align 8
  %t11.i.i.i = lshr i64 %t10.i.i.i, 1
  %t12.i.i.i = and i64 %t11.i.i.i, 16383
  %.t12.i.i.i = tail call i64 @llvm.umin.i64(i64 %t12.i.i.i, i64 47)
  %t22.i.i.i = shl nsw i64 -65536, %.t12.i.i.i
  %t23.i.i.i = and i64 %t22.i.i.i, 262144
  %t24.i.i.i = xor i64 %t23.i.i.i, 262144
  %t25.i.i.i = or i64 %t24.i.i.i, %t10.i.i.i
  store i64 %t25.i.i.i, ptr %t8.i.i.i, align 8
  %t5.i.i.i = inttoptr i64 %t0.i.i6.i to ptr
  store i64 %t29.i, ptr %t5.i.i.i, align 8
  %t6.i.i.i = getelementptr i8, ptr %t5.i.i.i, i64 8
  store i64 %t32.i, ptr %t6.i.i.i, align 8
  %t6.i5.i.i = getelementptr i8, ptr %t5.i.i.i, i64 16
  store i64 %t2.i.i2.i, ptr %t6.i5.i.i, align 8
  %imm.i.i.i = icmp slt i64 %t0.i.i6.i, 4096
  br i1 %imm.i.i.i, label %"Str$strSlice.exit", label %chk.i.i.i

chk.i.i.i:                                        ; preds = %axiom_retain.exit.i49
  %hoff.i.i.i = add nsw i64 %t0.i.i6.i, -16
  %cp.i.i.i = inttoptr i64 %hoff.i.i.i to ptr
  %c.i.i.i = load i64, ptr %cp.i.i.i, align 8
  %stat.i.i.i = icmp eq i64 %c.i.i.i, -1
  br i1 %stat.i.i.i, label %"Str$strSlice.exit", label %bump.i.i.i

bump.i.i.i:                                       ; preds = %chk.i.i.i
  %c1.i.i.i = add nuw i64 %c.i.i.i, 1
  store i64 %c1.i.i.i, ptr %cp.i.i.i, align 8
  br label %"Str$strSlice.exit"

"Str$strSlice.exit":                              ; preds = %axiom_retain.exit.i49, %chk.i.i.i, %bump.i.i.i
  %t2.i.i51 = load i64, ptr %t5.i.i.i, align 8
  %c34 = icmp eq i64 %t2.i.i51, 0
  br i1 %c34, label %label_0.backedge, label %label_38

label_0.backedge.sink.split:                      ; preds = %label_58, %label_38
  tail call void @axiom_release(i64 %t0.i.i6.i)
  br label %label_0.backedge

label_0.backedge:                                 ; preds = %label_0.backedge.sink.split, %"Str$strSlice.exit"
  %t0.i.i6.i.sink = phi i64 [ %t0.i.i6.i, %"Str$strSlice.exit" ], [ %t50, %label_0.backedge.sink.split ]
  tail call void @axiom_release(i64 %t0.i.i6.i.sink)
  %s.5.0.be = add i64 %t27, 1
  %t2.i.i = load i64, ptr %t0.i.i, align 8
  %c9.not = icmp slt i64 %s.5.0.be, %t2.i.i
  br i1 %c9.not, label %label_13, label %label_14

label_38:                                         ; preds = %"Str$strSlice.exit"
  %t48 = tail call i64 @"Str$strConcat"(i64 %t0.i.i6.i, i64 ptrtoint (ptr getelementptr inbounds nuw (i8, ptr @strhdr_7, i64 16) to i64))
  tail call void @axiom_release(i64 ptrtoint (ptr getelementptr inbounds nuw (i8, ptr @strhdr_7, i64 16) to i64))
  %t50 = tail call i64 @"Str$strConcat"(i64 %t48, i64 %name)
  tail call void @axiom_release(i64 %t48)
  %t0.i.i.i52 = inttoptr i64 %t50 to ptr
  %t1.i.i.i53 = getelementptr i8, ptr %t0.i.i.i52, i64 8
  %t2.i.i.i54 = load i64, ptr %t1.i.i.i53, align 8
  %t9.i.i = tail call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 56, i64 -100, i64 %t2.i.i.i54, i64 0, i64 420, i64 0, i64 0) #15
  %c54 = icmp slt i64 %t9.i.i, 0
  br i1 %c54, label %label_0.backedge.sink.split, label %label_58

label_58:                                         ; preds = %label_38
  %t1.i = tail call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 57, i64 %t9.i.i, i64 0, i64 0, i64 0, i64 0, i64 0) #15
  %t70 = tail call i64 @"Sys$sysRun"(i64 %t2.i.i.i54, i64 %argv, i64 %envp)
  %c71 = icmp sgt i64 %t70, -1
  br i1 %c71, label %label_59, label %label_0.backedge.sink.split

label_59:                                         ; preds = %label_58
  tail call void @axiom_release(i64 %t50)
  tail call void @axiom_release(i64 %t0.i.i6.i)
  br label %label_14

label_14:                                         ; preds = %label_0.backedge, %axiom_retain.exit35, %label_59
  %t84 = phi i64 [ %t70, %label_59 ], [ -2, %axiom_retain.exit35 ], [ -2, %label_0.backedge ]
  tail call void @axiom_release(i64 %name)
  tail call void @axiom_release(i64 %path)
  ret i64 %t84
}

; Function Attrs: nounwind
define i64 @"Sys$sysGetPid"() #1 {
  %t1 = tail call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 172, i64 0, i64 0, i64 0, i64 0, i64 0, i64 0) #15
  ret i64 %t1
}

; Function Attrs: nounwind
define i64 @"Sys$sysNowMicros"(i64 %buf) #1 {
label_5:
  %t22 = tail call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 113, i64 1, i64 %buf, i64 0, i64 0, i64 0, i64 0) #15
  %c23 = icmp slt i64 %t22, 0
  br i1 %c23, label %label_6, label %label_27

label_27:                                         ; preds = %label_5
  %t0.i = inttoptr i64 %buf to ptr
  %t2.i = load i64, ptr %t0.i, align 8
  %t1.i = getelementptr i8, ptr %t0.i, i64 8
  %t2.i2 = load i64, ptr %t1.i, align 8
  %t30 = mul i64 %t2.i, 1000000
  %t35 = sdiv i64 %t2.i2, 1000
  %t36 = add i64 %t35, %t30
  br label %label_6

label_6:                                          ; preds = %label_27, %label_5
  %t38 = phi i64 [ %t22, %label_5 ], [ %t36, %label_27 ]
  ret i64 %t38
}

; Function Attrs: nounwind
define i64 @"Sys$sysNowMonotonic"(i64 %buf) #1 {
label_5:
  %t9 = tail call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 113, i64 1, i64 %buf, i64 0, i64 0, i64 0, i64 0) #15
  %c10 = icmp slt i64 %t9, 0
  br i1 %c10, label %label_6, label %label_14

label_14:                                         ; preds = %label_5
  %t0.i = inttoptr i64 %buf to ptr
  %t2.i = load i64, ptr %t0.i, align 8
  %t1.i = getelementptr i8, ptr %t0.i, i64 8
  %t2.i2 = load i64, ptr %t1.i, align 8
  %t17 = mul i64 %t2.i, 1000000
  %t22 = sdiv i64 %t2.i2, 1000
  %t23 = add i64 %t22, %t17
  br label %label_6

label_6:                                          ; preds = %label_14, %label_5
  %t25 = phi i64 [ %t9, %label_5 ], [ %t23, %label_14 ]
  ret i64 %t25
}

; Function Attrs: nounwind
define i64 @"Sys$netSocketTcp"() #1 {
  %t3 = tail call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 198, i64 2, i64 1, i64 0, i64 0, i64 0, i64 0) #15
  ret i64 %t3
}

; Function Attrs: nounwind
define i64 @"Sys$netSocketTcp6"() #1 {
  %t3 = tail call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 198, i64 10, i64 1, i64 0, i64 0, i64 0, i64 0) #15
  ret i64 %t3
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(none)
define noundef i64 @"Sys$netAddr4Bytes"() #6 {
  ret i64 16
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(none)
define noundef i64 @"Sys$netAddr6Bytes"() #6 {
  ret i64 28
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(none)
define noundef i64 @"Sys$netAddrMaxBytes"() #6 {
  ret i64 28
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(write, inaccessiblemem: none, target_mem0: none, target_mem1: none)
define i64 @"Sys$netAddr4"(i64 returned %buf, i64 %port, i64 %a, i64 %b, i64 %c, i64 %d) #9 {
label_6:
  %t9.i.i = inttoptr i64 %buf to ptr
  store i8 0, ptr %t9.i.i, align 1
  %t10.i.i.1 = getelementptr i8, ptr %t9.i.i, i64 1
  store i8 0, ptr %t10.i.i.1, align 1
  %t10.i.i.2 = getelementptr i8, ptr %t9.i.i, i64 2
  store i8 0, ptr %t10.i.i.2, align 1
  %t10.i.i.3 = getelementptr i8, ptr %t9.i.i, i64 3
  store i8 0, ptr %t10.i.i.3, align 1
  %t10.i.i.4 = getelementptr i8, ptr %t9.i.i, i64 4
  store i8 0, ptr %t10.i.i.4, align 1
  %t10.i.i.5 = getelementptr i8, ptr %t9.i.i, i64 5
  store i8 0, ptr %t10.i.i.5, align 1
  %t10.i.i.6 = getelementptr i8, ptr %t9.i.i, i64 6
  store i8 0, ptr %t10.i.i.6, align 1
  %t10.i.i.7 = getelementptr i8, ptr %t9.i.i, i64 7
  store i8 0, ptr %t10.i.i.7, align 1
  %t10.i.i.8 = getelementptr i8, ptr %t9.i.i, i64 8
  store i8 0, ptr %t10.i.i.8, align 1
  %t10.i.i.9 = getelementptr i8, ptr %t9.i.i, i64 9
  store i8 0, ptr %t10.i.i.9, align 1
  %t10.i.i.10 = getelementptr i8, ptr %t9.i.i, i64 10
  store i8 0, ptr %t10.i.i.10, align 1
  %t10.i.i.11 = getelementptr i8, ptr %t9.i.i, i64 11
  store i8 0, ptr %t10.i.i.11, align 1
  %t10.i.i.12 = getelementptr i8, ptr %t9.i.i, i64 12
  store i8 0, ptr %t10.i.i.12, align 1
  %t10.i.i.13 = getelementptr i8, ptr %t9.i.i, i64 13
  store i8 0, ptr %t10.i.i.13, align 1
  %t10.i.i.14 = getelementptr i8, ptr %t9.i.i, i64 14
  store i8 0, ptr %t10.i.i.14, align 1
  %t10.i.i.15 = getelementptr i8, ptr %t9.i.i, i64 15
  store i8 0, ptr %t10.i.i.15, align 1
  store i8 2, ptr %t9.i.i, align 1
  %t1.i = getelementptr i8, ptr %t9.i.i, i64 1
  store i8 0, ptr %t1.i, align 1
  %t15 = lshr i64 %port, 8
  %t1.i3 = getelementptr i8, ptr %t9.i.i, i64 2
  %t2.i = trunc i64 %t15 to i8
  store i8 %t2.i, ptr %t1.i3, align 1
  %t1.i5 = getelementptr i8, ptr %t9.i.i, i64 3
  %t2.i6 = trunc i64 %port to i8
  store i8 %t2.i6, ptr %t1.i5, align 1
  %t1.i8 = getelementptr i8, ptr %t9.i.i, i64 4
  %t2.i9 = trunc i64 %a to i8
  store i8 %t2.i9, ptr %t1.i8, align 1
  %t1.i11 = getelementptr i8, ptr %t9.i.i, i64 5
  %t2.i12 = trunc i64 %b to i8
  store i8 %t2.i12, ptr %t1.i11, align 1
  %t1.i14 = getelementptr i8, ptr %t9.i.i, i64 6
  %t2.i15 = trunc i64 %c to i8
  store i8 %t2.i15, ptr %t1.i14, align 1
  %t1.i17 = getelementptr i8, ptr %t9.i.i, i64 7
  %t2.i18 = trunc i64 %d to i8
  store i8 %t2.i18, ptr %t1.i17, align 1
  ret i64 %buf
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(write, inaccessiblemem: none, target_mem0: none, target_mem1: none)
define i64 @"Sys$netAddr6"(i64 returned %buf, i64 %port, i64 %g0, i64 %g1, i64 %g2, i64 %g3, i64 %g4, i64 %g5, i64 %g6, i64 %g7) #9 {
label_7:
  %t9.i.i = inttoptr i64 %buf to ptr
  store i8 0, ptr %t9.i.i, align 1
  %t10.i.i.1 = getelementptr i8, ptr %t9.i.i, i64 1
  store i8 0, ptr %t10.i.i.1, align 1
  %t10.i.i.2 = getelementptr i8, ptr %t9.i.i, i64 2
  store i8 0, ptr %t10.i.i.2, align 1
  %t10.i.i.3 = getelementptr i8, ptr %t9.i.i, i64 3
  store i8 0, ptr %t10.i.i.3, align 1
  %t10.i.i.4 = getelementptr i8, ptr %t9.i.i, i64 4
  store i8 0, ptr %t10.i.i.4, align 1
  %t10.i.i.5 = getelementptr i8, ptr %t9.i.i, i64 5
  store i8 0, ptr %t10.i.i.5, align 1
  %t10.i.i.6 = getelementptr i8, ptr %t9.i.i, i64 6
  store i8 0, ptr %t10.i.i.6, align 1
  %t10.i.i.7 = getelementptr i8, ptr %t9.i.i, i64 7
  store i8 0, ptr %t10.i.i.7, align 1
  %t10.i.i.8 = getelementptr i8, ptr %t9.i.i, i64 8
  store i8 0, ptr %t10.i.i.8, align 1
  %t10.i.i.9 = getelementptr i8, ptr %t9.i.i, i64 9
  store i8 0, ptr %t10.i.i.9, align 1
  %t10.i.i.10 = getelementptr i8, ptr %t9.i.i, i64 10
  store i8 0, ptr %t10.i.i.10, align 1
  %t10.i.i.11 = getelementptr i8, ptr %t9.i.i, i64 11
  store i8 0, ptr %t10.i.i.11, align 1
  %t10.i.i.12 = getelementptr i8, ptr %t9.i.i, i64 12
  store i8 0, ptr %t10.i.i.12, align 1
  %t10.i.i.13 = getelementptr i8, ptr %t9.i.i, i64 13
  store i8 0, ptr %t10.i.i.13, align 1
  %t10.i.i.14 = getelementptr i8, ptr %t9.i.i, i64 14
  store i8 0, ptr %t10.i.i.14, align 1
  %t10.i.i.15 = getelementptr i8, ptr %t9.i.i, i64 15
  store i8 0, ptr %t10.i.i.15, align 1
  %t10.i.i.16 = getelementptr i8, ptr %t9.i.i, i64 16
  store i8 0, ptr %t10.i.i.16, align 1
  %t10.i.i.17 = getelementptr i8, ptr %t9.i.i, i64 17
  store i8 0, ptr %t10.i.i.17, align 1
  %t10.i.i.18 = getelementptr i8, ptr %t9.i.i, i64 18
  store i8 0, ptr %t10.i.i.18, align 1
  %t10.i.i.19 = getelementptr i8, ptr %t9.i.i, i64 19
  store i8 0, ptr %t10.i.i.19, align 1
  %t10.i.i.20 = getelementptr i8, ptr %t9.i.i, i64 20
  store i8 0, ptr %t10.i.i.20, align 1
  %t10.i.i.21 = getelementptr i8, ptr %t9.i.i, i64 21
  store i8 0, ptr %t10.i.i.21, align 1
  %t10.i.i.22 = getelementptr i8, ptr %t9.i.i, i64 22
  store i8 0, ptr %t10.i.i.22, align 1
  %t10.i.i.23 = getelementptr i8, ptr %t9.i.i, i64 23
  store i8 0, ptr %t10.i.i.23, align 1
  %t10.i.i.24 = getelementptr i8, ptr %t9.i.i, i64 24
  store i8 0, ptr %t10.i.i.24, align 1
  %t10.i.i.25 = getelementptr i8, ptr %t9.i.i, i64 25
  store i8 0, ptr %t10.i.i.25, align 1
  %t10.i.i.26 = getelementptr i8, ptr %t9.i.i, i64 26
  store i8 0, ptr %t10.i.i.26, align 1
  %t10.i.i.27 = getelementptr i8, ptr %t9.i.i, i64 27
  store i8 0, ptr %t10.i.i.27, align 1
  store i8 10, ptr %t9.i.i, align 1
  %t1.i = getelementptr i8, ptr %t9.i.i, i64 1
  store i8 0, ptr %t1.i, align 1
  %t21 = lshr i64 %port, 8
  %t1.i3 = getelementptr i8, ptr %t9.i.i, i64 2
  %t2.i = trunc i64 %t21 to i8
  store i8 %t2.i, ptr %t1.i3, align 1
  %t1.i5 = getelementptr i8, ptr %t9.i.i, i64 3
  %t2.i6 = trunc i64 %port to i8
  store i8 %t2.i6, ptr %t1.i5, align 1
  %t2.i7 = lshr i64 %g0, 8
  %t1.i.i = getelementptr i8, ptr %t9.i.i, i64 8
  %t2.i.i = trunc i64 %t2.i7 to i8
  store i8 %t2.i.i, ptr %t1.i.i, align 1
  %t1.i2.i = getelementptr i8, ptr %t9.i.i, i64 9
  %t2.i3.i = trunc i64 %g0 to i8
  store i8 %t2.i3.i, ptr %t1.i2.i, align 1
  %t2.i8 = lshr i64 %g1, 8
  %t1.i.i10 = getelementptr i8, ptr %t9.i.i, i64 10
  %t2.i.i11 = trunc i64 %t2.i8 to i8
  store i8 %t2.i.i11, ptr %t1.i.i10, align 1
  %t1.i2.i12 = getelementptr i8, ptr %t9.i.i, i64 11
  %t2.i3.i13 = trunc i64 %g1 to i8
  store i8 %t2.i3.i13, ptr %t1.i2.i12, align 1
  %t2.i14 = lshr i64 %g2, 8
  %t1.i.i16 = getelementptr i8, ptr %t9.i.i, i64 12
  %t2.i.i17 = trunc i64 %t2.i14 to i8
  store i8 %t2.i.i17, ptr %t1.i.i16, align 1
  %t1.i2.i18 = getelementptr i8, ptr %t9.i.i, i64 13
  %t2.i3.i19 = trunc i64 %g2 to i8
  store i8 %t2.i3.i19, ptr %t1.i2.i18, align 1
  %t2.i20 = lshr i64 %g3, 8
  %t1.i.i22 = getelementptr i8, ptr %t9.i.i, i64 14
  %t2.i.i23 = trunc i64 %t2.i20 to i8
  store i8 %t2.i.i23, ptr %t1.i.i22, align 1
  %t1.i2.i24 = getelementptr i8, ptr %t9.i.i, i64 15
  %t2.i3.i25 = trunc i64 %g3 to i8
  store i8 %t2.i3.i25, ptr %t1.i2.i24, align 1
  %t2.i26 = lshr i64 %g4, 8
  %t1.i.i28 = getelementptr i8, ptr %t9.i.i, i64 16
  %t2.i.i29 = trunc i64 %t2.i26 to i8
  store i8 %t2.i.i29, ptr %t1.i.i28, align 1
  %t1.i2.i30 = getelementptr i8, ptr %t9.i.i, i64 17
  %t2.i3.i31 = trunc i64 %g4 to i8
  store i8 %t2.i3.i31, ptr %t1.i2.i30, align 1
  %t2.i32 = lshr i64 %g5, 8
  %t1.i.i34 = getelementptr i8, ptr %t9.i.i, i64 18
  %t2.i.i35 = trunc i64 %t2.i32 to i8
  store i8 %t2.i.i35, ptr %t1.i.i34, align 1
  %t1.i2.i36 = getelementptr i8, ptr %t9.i.i, i64 19
  %t2.i3.i37 = trunc i64 %g5 to i8
  store i8 %t2.i3.i37, ptr %t1.i2.i36, align 1
  %t2.i38 = lshr i64 %g6, 8
  %t1.i.i40 = getelementptr i8, ptr %t9.i.i, i64 20
  %t2.i.i41 = trunc i64 %t2.i38 to i8
  store i8 %t2.i.i41, ptr %t1.i.i40, align 1
  %t1.i2.i42 = getelementptr i8, ptr %t9.i.i, i64 21
  %t2.i3.i43 = trunc i64 %g6 to i8
  store i8 %t2.i3.i43, ptr %t1.i2.i42, align 1
  %t2.i44 = lshr i64 %g7, 8
  %t1.i.i46 = getelementptr i8, ptr %t9.i.i, i64 22
  %t2.i.i47 = trunc i64 %t2.i44 to i8
  store i8 %t2.i.i47, ptr %t1.i.i46, align 1
  %t1.i2.i48 = getelementptr i8, ptr %t9.i.i, i64 23
  %t2.i3.i49 = trunc i64 %g7 to i8
  store i8 %t2.i3.i49, ptr %t1.i2.i48, align 1
  ret i64 %buf
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(write, inaccessiblemem: none, target_mem0: none, target_mem1: none)
define i64 @"Sys$netPutGroup"(i64 returned %buf, i64 %i, i64 %g) #9 {
  %t0 = shl i64 %i, 1
  %t2 = lshr i64 %g, 8
  %t0.i = inttoptr i64 %buf to ptr
  %1 = getelementptr i8, ptr %t0.i, i64 %t0
  %t1.i = getelementptr i8, ptr %1, i64 8
  %t2.i = trunc i64 %t2 to i8
  store i8 %t2.i, ptr %t1.i, align 1
  %2 = getelementptr i8, ptr %t0.i, i64 %t0
  %t1.i2 = getelementptr i8, ptr %2, i64 9
  %t2.i3 = trunc i64 %g to i8
  store i8 %t2.i3, ptr %t1.i2, align 1
  ret i64 %buf
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(read, inaccessiblemem: none, target_mem0: none, target_mem1: none)
define range(i64 0, 65536) i64 @"Sys$netGetGroup"(i64 %addr, i64 %i) #8 {
  %t0 = shl i64 %i, 1
  %t0.i = inttoptr i64 %addr to ptr
  %1 = getelementptr i8, ptr %t0.i, i64 %t0
  %t1.i = getelementptr i8, ptr %1, i64 8
  %t2.i = load i8, ptr %t1.i, align 1
  %t3.i = zext i8 %t2.i to i64
  %t3 = shl nuw nsw i64 %t3.i, 8
  %2 = getelementptr i8, ptr %t0.i, i64 %t0
  %t1.i2 = getelementptr i8, ptr %2, i64 9
  %t2.i3 = load i8, ptr %t1.i2, align 1
  %t3.i4 = zext i8 %t2.i3 to i64
  %t7 = or disjoint i64 %t3, %t3.i4
  ret i64 %t7
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(read, inaccessiblemem: none, target_mem0: none, target_mem1: none)
define range(i64 0, 65536) i64 @"Sys$netAddrFamily"(i64 %addr) #8 {
label_5:
  %t0.i = inttoptr i64 %addr to ptr
  %t2.i = load i8, ptr %t0.i, align 1
  %t3.i = zext i8 %t2.i to i64
  %t1.i = getelementptr i8, ptr %t0.i, i64 1
  %t2.i2 = load i8, ptr %t1.i, align 1
  %t3.i3 = zext i8 %t2.i2 to i64
  %t10 = shl nuw nsw i64 %t3.i3, 8
  %t11 = or disjoint i64 %t10, %t3.i
  ret i64 %t11
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(read, inaccessiblemem: none, target_mem0: none, target_mem1: none)
define range(i64 0, 65536) i64 @"Sys$netAddrPort"(i64 %addr) #8 {
  %t0.i = inttoptr i64 %addr to ptr
  %t1.i = getelementptr i8, ptr %t0.i, i64 2
  %t2.i = load i8, ptr %t1.i, align 1
  %t3.i = zext i8 %t2.i to i64
  %t1 = shl nuw nsw i64 %t3.i, 8
  %t1.i2 = getelementptr i8, ptr %t0.i, i64 3
  %t2.i3 = load i8, ptr %t1.i2, align 1
  %t3.i4 = zext i8 %t2.i3 to i64
  %t3 = or disjoint i64 %t1, %t3.i4
  ret i64 %t3
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(read, inaccessiblemem: none, target_mem0: none, target_mem1: none)
define range(i64 16, 29) i64 @"Sys$netAddrSize"(i64 %addr) #8 {
label_7:
  %t0.i.i = inttoptr i64 %addr to ptr
  %t2.i.i = load i8, ptr %t0.i.i, align 1
  %t3.i.i = zext i8 %t2.i.i to i64
  %t1.i.i = getelementptr i8, ptr %t0.i.i, i64 1
  %t2.i2.i = load i8, ptr %t1.i.i, align 1
  %t3.i3.i = zext i8 %t2.i2.i to i64
  %t10.i = shl nuw nsw i64 %t3.i3.i, 8
  %t11.i = or disjoint i64 %t10.i, %t3.i.i
  %c2 = icmp eq i64 %t11.i, 10
  %. = select i1 %c2, i64 28, i64 16
  ret i64 %.
}

; Function Attrs: nounwind
define i64 @"Sys$netBind"(i64 %fd, i64 %addr) #1 {
  %t0.i.i.i = inttoptr i64 %addr to ptr
  %t2.i.i.i = load i8, ptr %t0.i.i.i, align 1
  %t3.i.i.i = zext i8 %t2.i.i.i to i64
  %t1.i.i.i = getelementptr i8, ptr %t0.i.i.i, i64 1
  %t2.i2.i.i = load i8, ptr %t1.i.i.i, align 1
  %t3.i3.i.i = zext i8 %t2.i2.i.i to i64
  %t10.i.i = shl nuw nsw i64 %t3.i3.i.i, 8
  %t11.i.i = or disjoint i64 %t10.i.i, %t3.i.i.i
  %c2.i = icmp eq i64 %t11.i.i, 10
  %..i = select i1 %c2.i, i64 28, i64 16
  %t2 = tail call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 200, i64 %fd, i64 %addr, i64 %..i, i64 0, i64 0, i64 0) #15
  ret i64 %t2
}

; Function Attrs: nounwind
define i64 @"Sys$netListen"(i64 %fd, i64 %backlog) #1 {
  %t1 = tail call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 201, i64 %fd, i64 %backlog, i64 0, i64 0, i64 0, i64 0) #15
  ret i64 %t1
}

; Function Attrs: nounwind
define i64 @"Sys$netAccept"(i64 %fd) #1 {
  %t2 = tail call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 242, i64 %fd, i64 0, i64 0, i64 2048, i64 0, i64 0) #15
  ret i64 %t2
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(none)
define i64 @"Sys$netAcceptFinish"(i64 returned %c) #6 {
label_5:
  ret i64 %c
}

; Function Attrs: nounwind
define i64 @"Sys$netAcceptFrom"(i64 %fd, i64 %addr, i64 %cap, i64 %lenbuf) #1 {
  %c53.i.i = icmp slt i64 %cap, 1
  br i1 %c53.i.i, label %"Mem$memSet.exit", label %label_2.lr.ph.i.i

label_2.lr.ph.i.i:                                ; preds = %0
  %t9.i.i = inttoptr i64 %addr to ptr
  br label %label_2.i.i

label_2.i.i:                                      ; preds = %label_2.i.i, %label_2.lr.ph.i.i
  %s.0.04.i.i = phi i64 [ 0, %label_2.lr.ph.i.i ], [ %t13.i.i, %label_2.i.i ]
  %t10.i.i = getelementptr i8, ptr %t9.i.i, i64 %s.0.04.i.i
  store i8 0, ptr %t10.i.i, align 1
  %t13.i.i = add nuw nsw i64 %s.0.04.i.i, 1
  %exitcond.not.i.i = icmp eq i64 %t13.i.i, %cap
  br i1 %exitcond.not.i.i, label %"Mem$memSet.exit", label %label_2.i.i

"Mem$memSet.exit":                                ; preds = %label_2.i.i, %0
  %t0.i.i = inttoptr i64 %lenbuf to ptr
  %t2.i.i = trunc i64 %cap to i8
  store i8 %t2.i.i, ptr %t0.i.i, align 1
  %t3.i = lshr i64 %cap, 8
  %t1.i2.i = getelementptr i8, ptr %t0.i.i, i64 1
  %t2.i3.i = trunc i64 %t3.i to i8
  store i8 %t2.i3.i, ptr %t1.i2.i, align 1
  %t7.i = lshr i64 %cap, 16
  %t1.i5.i = getelementptr i8, ptr %t0.i.i, i64 2
  %t2.i6.i = trunc i64 %t7.i to i8
  store i8 %t2.i6.i, ptr %t1.i5.i, align 1
  %t11.i = lshr i64 %cap, 24
  %t1.i8.i = getelementptr i8, ptr %t0.i.i, i64 3
  %t2.i9.i = trunc i64 %t11.i to i8
  store i8 %t2.i9.i, ptr %t1.i8.i, align 1
  %t4 = tail call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 242, i64 %fd, i64 %addr, i64 %lenbuf, i64 2048, i64 0, i64 0) #15
  %c6 = icmp sgt i64 %t4, -1
  br i1 %c6, label %label_9, label %label_21

label_9:                                          ; preds = %"Mem$memSet.exit"
  %t2.i.i.i = load i8, ptr %t0.i.i, align 1
  %t3.i.i.i = zext i8 %t2.i.i.i to i64
  %t2.i3.i.i = load i8, ptr %t1.i2.i, align 1
  %t3.i4.i.i = zext i8 %t2.i3.i.i to i64
  %t3.i.i = shl nuw nsw i64 %t3.i4.i.i, 8
  %t2.i7.i.i = load i8, ptr %t1.i5.i, align 1
  %t3.i8.i.i = zext i8 %t2.i7.i.i to i64
  %t6.i.i = shl nuw nsw i64 %t3.i8.i.i, 16
  %t2.i11.i.i = load i8, ptr %t1.i8.i, align 1
  %t3.i12.i.i = zext i8 %t2.i11.i.i to i64
  %t9.i.i1 = shl nuw nsw i64 %t3.i12.i.i, 24
  %t10.i.i2 = or disjoint i64 %t3.i.i, %t3.i.i.i
  %t11.i.i = or disjoint i64 %t10.i.i2, %t6.i.i
  %t12.i.i = or disjoint i64 %t11.i.i, %t9.i.i1
  %c13 = icmp sle i64 %t12.i.i, %cap
  %brmerge = or i1 %c53.i.i, %c13
  br i1 %brmerge, label %label_21, label %label_2.lr.ph.i.i4

label_2.lr.ph.i.i4:                               ; preds = %label_9
  %t9.i.i5 = inttoptr i64 %addr to ptr
  br label %label_2.i.i6

label_2.i.i6:                                     ; preds = %label_2.i.i6, %label_2.lr.ph.i.i4
  %s.0.04.i.i7 = phi i64 [ 0, %label_2.lr.ph.i.i4 ], [ %t13.i.i9, %label_2.i.i6 ]
  %t10.i.i8 = getelementptr i8, ptr %t9.i.i5, i64 %s.0.04.i.i7
  store i8 0, ptr %t10.i.i8, align 1
  %t13.i.i9 = add nuw nsw i64 %s.0.04.i.i7, 1
  %exitcond.not.i.i10 = icmp eq i64 %t13.i.i9, %cap
  br i1 %exitcond.not.i.i10, label %label_21, label %label_2.i.i6

label_21:                                         ; preds = %label_2.i.i6, %label_9, %"Mem$memSet.exit"
  ret i64 %t4
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(read, inaccessiblemem: none, target_mem0: none, target_mem1: none)
define range(i64 0, 4294967296) i64 @"Sys$netAddrLenRead"(i64 %lenbuf) #8 {
  %t0.i.i = inttoptr i64 %lenbuf to ptr
  %t2.i.i = load i8, ptr %t0.i.i, align 1
  %t3.i.i = zext i8 %t2.i.i to i64
  %t1.i2.i = getelementptr i8, ptr %t0.i.i, i64 1
  %t2.i3.i = load i8, ptr %t1.i2.i, align 1
  %t3.i4.i = zext i8 %t2.i3.i to i64
  %t3.i = shl nuw nsw i64 %t3.i4.i, 8
  %t1.i6.i = getelementptr i8, ptr %t0.i.i, i64 2
  %t2.i7.i = load i8, ptr %t1.i6.i, align 1
  %t3.i8.i = zext i8 %t2.i7.i to i64
  %t6.i = shl nuw nsw i64 %t3.i8.i, 16
  %t1.i10.i = getelementptr i8, ptr %t0.i.i, i64 3
  %t2.i11.i = load i8, ptr %t1.i10.i, align 1
  %t3.i12.i = zext i8 %t2.i11.i to i64
  %t9.i = shl nuw nsw i64 %t3.i12.i, 24
  %t10.i = or disjoint i64 %t3.i, %t3.i.i
  %t11.i = or disjoint i64 %t10.i, %t6.i
  %t12.i = or disjoint i64 %t11.i, %t9.i
  ret i64 %t12.i
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(write, inaccessiblemem: none, target_mem0: none, target_mem1: none)
define i64 @"Sys$netPutInt32"(i64 returned %buf, i64 %off, i64 %v) #9 {
  %t0.i = inttoptr i64 %buf to ptr
  %t1.i = getelementptr i8, ptr %t0.i, i64 %off
  %t2.i = trunc i64 %v to i8
  store i8 %t2.i, ptr %t1.i, align 1
  %t3 = lshr i64 %v, 8
  %1 = getelementptr i8, ptr %t0.i, i64 %off
  %t1.i2 = getelementptr i8, ptr %1, i64 1
  %t2.i3 = trunc i64 %t3 to i8
  store i8 %t2.i3, ptr %t1.i2, align 1
  %t7 = lshr i64 %v, 16
  %2 = getelementptr i8, ptr %t0.i, i64 %off
  %t1.i5 = getelementptr i8, ptr %2, i64 2
  %t2.i6 = trunc i64 %t7 to i8
  store i8 %t2.i6, ptr %t1.i5, align 1
  %t11 = lshr i64 %v, 24
  %3 = getelementptr i8, ptr %t0.i, i64 %off
  %t1.i8 = getelementptr i8, ptr %3, i64 3
  %t2.i9 = trunc i64 %t11 to i8
  store i8 %t2.i9, ptr %t1.i8, align 1
  ret i64 %buf
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(read, inaccessiblemem: none, target_mem0: none, target_mem1: none)
define range(i64 0, 4294967296) i64 @"Sys$netGetInt32"(i64 %buf, i64 %off) #8 {
  %t0.i = inttoptr i64 %buf to ptr
  %t1.i = getelementptr i8, ptr %t0.i, i64 %off
  %t2.i = load i8, ptr %t1.i, align 1
  %t3.i = zext i8 %t2.i to i64
  %1 = getelementptr i8, ptr %t0.i, i64 %off
  %t1.i2 = getelementptr i8, ptr %1, i64 1
  %t2.i3 = load i8, ptr %t1.i2, align 1
  %t3.i4 = zext i8 %t2.i3 to i64
  %t3 = shl nuw nsw i64 %t3.i4, 8
  %2 = getelementptr i8, ptr %t0.i, i64 %off
  %t1.i6 = getelementptr i8, ptr %2, i64 2
  %t2.i7 = load i8, ptr %t1.i6, align 1
  %t3.i8 = zext i8 %t2.i7 to i64
  %t6 = shl nuw nsw i64 %t3.i8, 16
  %3 = getelementptr i8, ptr %t0.i, i64 %off
  %t1.i10 = getelementptr i8, ptr %3, i64 3
  %t2.i11 = load i8, ptr %t1.i10, align 1
  %t3.i12 = zext i8 %t2.i11 to i64
  %t9 = shl nuw nsw i64 %t3.i12, 24
  %t10 = or disjoint i64 %t3, %t3.i
  %t11 = or disjoint i64 %t10, %t6
  %t12 = or disjoint i64 %t11, %t9
  ret i64 %t12
}

define i64 @"Sys$netAddrText"(i64 %addr) #0 {
  %t0.i.i = inttoptr i64 %addr to ptr
  %t2.i.i = load i8, ptr %t0.i.i, align 1
  %t3.i.i = zext i8 %t2.i.i to i64
  %t1.i.i = getelementptr i8, ptr %t0.i.i, i64 1
  %t2.i2.i = load i8, ptr %t1.i.i, align 1
  %t3.i3.i = zext i8 %t2.i2.i to i64
  %t10.i = shl nuw nsw i64 %t3.i3.i, 8
  %t11.i = or disjoint i64 %t10.i, %t3.i.i
  %trunc = trunc nuw i64 %t11.i to i16
  switch i16 %trunc, label %label_17 [
    i16 10, label %label_10.lr.ph.i
    i16 2, label %label_16
  ]

label_10.lr.ph.i:                                 ; preds = %0, %label_20.i
  %s.4.0.ph16.i = phi i64 [ %t15.i, %label_20.i ], [ 1, %0 ]
  %s.3.0.ph15.i = phi i64 [ %s.2.011.i, %label_20.i ], [ -1, %0 ]
  %s.2.0.ph14.i = phi i64 [ %t25.i, %label_20.i ], [ 0, %0 ]
  br label %label_10.i

label_10.i:                                       ; preds = %label_21.i, %label_10.lr.ph.i
  %s.2.011.i = phi i64 [ %s.2.0.ph14.i, %label_10.lr.ph.i ], [ %t36.i, %label_21.i ]
  %t15.i = tail call i64 @"Sys$netAddrZeroRun"(i64 %addr, i64 %s.2.011.i)
  %c17.i = icmp sgt i64 %t15.i, %s.4.0.ph16.i
  br i1 %c17.i, label %label_20.i, label %label_21.i

label_20.i:                                       ; preds = %label_10.i
  %t25.i = add i64 %t15.i, %s.2.011.i
  %c610.i = icmp sgt i64 %t25.i, 7
  br i1 %c610.i, label %"Sys$netAddrZeroRunStart.exit", label %label_10.lr.ph.i

label_21.i:                                       ; preds = %label_10.i
  %t15..i = tail call i64 @llvm.smax.i64(i64 %t15.i, i64 1)
  %t36.i = add i64 %t15..i, %s.2.011.i
  %c6.i = icmp sgt i64 %t36.i, 7
  br i1 %c6.i, label %"Sys$netAddrZeroRunStart.exit", label %label_10.i

"Sys$netAddrZeroRunStart.exit":                   ; preds = %label_20.i, %label_21.i
  %s.3.0.ph.lcssa.i = phi i64 [ %s.3.0.ph15.i, %label_21.i ], [ %s.2.011.i, %label_20.i ]
  %t11 = tail call i64 @"Sys$netAddrText6"(i64 %addr, i64 0, i64 %s.3.0.ph.lcssa.i, i64 ptrtoint (ptr getelementptr inbounds nuw (i8, ptr @strhdr_4, i64 16) to i64))
  tail call void @axiom_release(i64 ptrtoint (ptr getelementptr inbounds nuw (i8, ptr @strhdr_4, i64 16) to i64))
  br label %label_7

label_16:                                         ; preds = %0
  %t19 = tail call i64 @"Sys$netAddrText4"(i64 %addr)
  br label %label_7

label_17:                                         ; preds = %0
  %t16.i = tail call i64 @"Fmt$fmtNat"(i64 %t11.i)
  %t22 = tail call i64 @"Str$strConcat"(i64 ptrtoint (ptr getelementptr inbounds nuw (i8, ptr @strhdr_8, i64 16) to i64), i64 %t16.i)
  tail call void @axiom_release(i64 ptrtoint (ptr getelementptr inbounds nuw (i8, ptr @strhdr_8, i64 16) to i64))
  tail call void @axiom_release(i64 %t16.i)
  br label %label_7

label_7:                                          ; preds = %label_16, %label_17, %"Sys$netAddrZeroRunStart.exit"
  %t24 = phi i64 [ %t11, %"Sys$netAddrZeroRunStart.exit" ], [ %t19, %label_16 ], [ %t22, %label_17 ]
  ret i64 %t24
}

define i64 @"Sys$netAddrText4"(i64 %addr) #0 {
  %t0.i = inttoptr i64 %addr to ptr
  %t1.i = getelementptr i8, ptr %t0.i, i64 4
  %t2.i = load i8, ptr %t1.i, align 1
  %t3.i = zext i8 %t2.i to i64
  %t16.i = tail call i64 @"Fmt$fmtNat"(i64 %t3.i)
  %t3 = tail call i64 @"Str$strConcat"(i64 %t16.i, i64 ptrtoint (ptr getelementptr inbounds nuw (i8, ptr @strhdr_3, i64 16) to i64))
  tail call void @axiom_release(i64 %t16.i)
  tail call void @axiom_release(i64 ptrtoint (ptr getelementptr inbounds nuw (i8, ptr @strhdr_3, i64 16) to i64))
  %t1.i2 = getelementptr i8, ptr %t0.i, i64 5
  %t2.i3 = load i8, ptr %t1.i2, align 1
  %t3.i4 = zext i8 %t2.i3 to i64
  %t16.i5 = tail call i64 @"Fmt$fmtNat"(i64 %t3.i4)
  %t7 = tail call i64 @"Str$strConcat"(i64 %t16.i5, i64 ptrtoint (ptr getelementptr inbounds nuw (i8, ptr @strhdr_3, i64 16) to i64))
  tail call void @axiom_release(i64 %t16.i5)
  tail call void @axiom_release(i64 ptrtoint (ptr getelementptr inbounds nuw (i8, ptr @strhdr_3, i64 16) to i64))
  %t8 = tail call i64 @"Str$strConcat"(i64 %t3, i64 %t7)
  tail call void @axiom_release(i64 %t3)
  tail call void @axiom_release(i64 %t7)
  %t1.i7 = getelementptr i8, ptr %t0.i, i64 6
  %t2.i8 = load i8, ptr %t1.i7, align 1
  %t3.i9 = zext i8 %t2.i8 to i64
  %t16.i10 = tail call i64 @"Fmt$fmtNat"(i64 %t3.i9)
  %t12 = tail call i64 @"Str$strConcat"(i64 %t16.i10, i64 ptrtoint (ptr getelementptr inbounds nuw (i8, ptr @strhdr_3, i64 16) to i64))
  tail call void @axiom_release(i64 %t16.i10)
  tail call void @axiom_release(i64 ptrtoint (ptr getelementptr inbounds nuw (i8, ptr @strhdr_3, i64 16) to i64))
  %t1.i12 = getelementptr i8, ptr %t0.i, i64 7
  %t2.i13 = load i8, ptr %t1.i12, align 1
  %t3.i14 = zext i8 %t2.i13 to i64
  %t16.i15 = tail call i64 @"Fmt$fmtNat"(i64 %t3.i14)
  %t15 = tail call i64 @"Str$strConcat"(i64 %t12, i64 %t16.i15)
  tail call void @axiom_release(i64 %t12)
  tail call void @axiom_release(i64 %t16.i15)
  %t16 = tail call i64 @"Str$strConcat"(i64 %t8, i64 %t15)
  tail call void @axiom_release(i64 %t8)
  tail call void @axiom_release(i64 %t15)
  ret i64 %t16
}

; Function Attrs: nofree nosync nounwind memory(read, inaccessiblemem: none, target_mem0: none, target_mem1: none)
define i64 @"Sys$netAddrZeroRun"(i64 %addr, i64 %i) #13 {
  br label %tailrecurse

tailrecurse:                                      ; preds = %label_10, %0
  %accumulator.tr = phi i64 [ 0, %0 ], [ %t15, %label_10 ]
  %i.tr = phi i64 [ %i, %0 ], [ %t13, %label_10 ]
  %c0 = icmp sgt i64 %i.tr, 7
  br i1 %c0, label %label_5, label %label_4

label_4:                                          ; preds = %tailrecurse
  %t0.i = shl i64 %i.tr, 1
  %t0.i.i = inttoptr i64 %addr to ptr
  %1 = getelementptr i8, ptr %t0.i.i, i64 %t0.i
  %t1.i.i = getelementptr i8, ptr %1, i64 8
  %t2.i.i = load i8, ptr %t1.i.i, align 1
  %t3.i.i = zext i8 %t2.i.i to i64
  %t3.i = shl nuw nsw i64 %t3.i.i, 8
  %t1.i2.i = getelementptr i8, ptr %1, i64 9
  %t2.i3.i = load i8, ptr %t1.i2.i, align 1
  %t3.i4.i = zext i8 %t2.i3.i to i64
  %t7.i = or disjoint i64 %t3.i, %t3.i4.i
  %c7 = icmp eq i64 %t7.i, 0
  br i1 %c7, label %label_10, label %label_5

label_10:                                         ; preds = %label_4
  %t13 = add nsw i64 %i.tr, 1
  %t15 = add i64 %accumulator.tr, 1
  br label %tailrecurse

label_5:                                          ; preds = %label_4, %tailrecurse
  %accumulator.ret.tr = add i64 %accumulator.tr, 0
  ret i64 %accumulator.ret.tr
}

; Function Attrs: nofree nosync nounwind memory(read, inaccessiblemem: none, target_mem0: none, target_mem1: none)
define i64 @"Sys$netAddrZeroRunStart"(i64 %addr, i64 %i, i64 %best, i64 %bestLen) #13 {
  %c61013 = icmp sgt i64 %i, 7
  br i1 %c61013, label %label_9, label %label_10.lr.ph

label_10.lr.ph:                                   ; preds = %0, %label_20
  %s.4.0.ph16 = phi i64 [ %t15, %label_20 ], [ %bestLen, %0 ]
  %s.3.0.ph15 = phi i64 [ %s.2.011, %label_20 ], [ %best, %0 ]
  %s.2.0.ph14 = phi i64 [ %t25, %label_20 ], [ %i, %0 ]
  br label %label_10

label_9:                                          ; preds = %label_20, %label_21, %0
  %s.3.0.ph.lcssa = phi i64 [ %s.3.0.ph15, %label_21 ], [ %best, %0 ], [ %s.2.011, %label_20 ]
  ret i64 %s.3.0.ph.lcssa

label_10:                                         ; preds = %label_10.lr.ph, %label_21
  %s.2.011 = phi i64 [ %s.2.0.ph14, %label_10.lr.ph ], [ %t36, %label_21 ]
  %t15 = tail call i64 @"Sys$netAddrZeroRun"(i64 %addr, i64 %s.2.011)
  %c17 = icmp sgt i64 %t15, %s.4.0.ph16
  br i1 %c17, label %label_20, label %label_21

label_20:                                         ; preds = %label_10
  %t25 = add i64 %t15, %s.2.011
  %c610 = icmp sgt i64 %t25, 7
  br i1 %c610, label %label_9, label %label_10.lr.ph

label_21:                                         ; preds = %label_10
  %t15. = tail call i64 @llvm.smax.i64(i64 %t15, i64 1)
  %t36 = add i64 %t15., %s.2.011
  %c6 = icmp sgt i64 %t36, 7
  br i1 %c6, label %label_9, label %label_10
}

define i64 @"Sys$netAddrText6"(i64 %addr, i64 %i, i64 %zs, i64 %acc) #0 {
  %imm.i = icmp slt i64 %acc, 4096
  br i1 %imm.i, label %axiom_retain.exit, label %chk.i

chk.i:                                            ; preds = %0
  %hoff.i = add nsw i64 %acc, -16
  %cp.i = inttoptr i64 %hoff.i to ptr
  %c.i = load i64, ptr %cp.i, align 8
  %stat.i = icmp eq i64 %c.i, -1
  br i1 %stat.i, label %axiom_retain.exit, label %bump.i

bump.i:                                           ; preds = %chk.i
  %c1.i = add nuw i64 %c.i, 1
  store i64 %c1.i, ptr %cp.i, align 8
  br label %axiom_retain.exit

axiom_retain.exit:                                ; preds = %0, %chk.i, %bump.i
  %c646 = icmp sgt i64 %i, 7
  br i1 %c646, label %label_9, label %label_10.lr.ph

label_10.lr.ph:                                   ; preds = %axiom_retain.exit
  %t0.i.i = inttoptr i64 %addr to ptr
  br label %label_10

label_9:                                          ; preds = %label_0.backedge, %axiom_retain.exit
  %s.4.0.lcssa = phi i64 [ %acc, %axiom_retain.exit ], [ %t40.sink, %label_0.backedge ]
  %imm.i19 = icmp slt i64 %s.4.0.lcssa, 4096
  br i1 %imm.i19, label %axiom_retain.exit27, label %chk.i20

chk.i20:                                          ; preds = %label_9
  %hoff.i21 = add nsw i64 %s.4.0.lcssa, -16
  %cp.i22 = inttoptr i64 %hoff.i21 to ptr
  %c.i23 = load i64, ptr %cp.i22, align 8
  %stat.i24 = icmp eq i64 %c.i23, -1
  br i1 %stat.i24, label %axiom_retain.exit27, label %bump.i25

bump.i25:                                         ; preds = %chk.i20
  %c1.i26 = add nuw i64 %c.i23, 1
  store i64 %c1.i26, ptr %cp.i22, align 8
  br label %axiom_retain.exit27

axiom_retain.exit27:                              ; preds = %label_9, %chk.i20, %bump.i25
  tail call void @axiom_release(i64 %s.4.0.lcssa)
  ret i64 %s.4.0.lcssa

label_10:                                         ; preds = %label_10.lr.ph, %label_0.backedge
  %s.4.048 = phi i64 [ %acc, %label_10.lr.ph ], [ %t40.sink, %label_0.backedge ]
  %s.2.047 = phi i64 [ %i, %label_10.lr.ph ], [ %s.2.0.be, %label_0.backedge ]
  %c15 = icmp eq i64 %s.2.047, %zs
  br i1 %c15, label %label_18, label %label_19

label_18:                                         ; preds = %label_10
  %t23 = tail call i64 @"Sys$netAddrZeroRun"(i64 %addr, i64 %s.2.047)
  %t26 = add i64 %t23, %s.2.047
  %c31 = icmp eq i64 %t26, 8
  %t39 = select i1 %c31, i64 ptrtoint (ptr getelementptr inbounds nuw (i8, ptr @strhdr_9, i64 16) to i64), i64 ptrtoint (ptr getelementptr inbounds nuw (i8, ptr @strhdr_10, i64 16) to i64)
  %t40 = tail call i64 @"Str$strConcat"(i64 %s.4.048, i64 %t39)
  tail call void @axiom_release(i64 %t39)
  %imm.i28 = icmp slt i64 %t40, 4096
  br i1 %imm.i28, label %label_0.backedge, label %chk.i29

chk.i29:                                          ; preds = %label_18
  %hoff.i30 = add nsw i64 %t40, -16
  %cp.i31 = inttoptr i64 %hoff.i30 to ptr
  %c.i32 = load i64, ptr %cp.i31, align 8
  %stat.i33 = icmp eq i64 %c.i32, -1
  br i1 %stat.i33, label %label_0.backedge, label %label_0.backedge.sink.split

label_0.backedge.sink.split:                      ; preds = %chk.i29, %chk.i38
  %c.i32.sink = phi i64 [ %c.i41, %chk.i38 ], [ %c.i32, %chk.i29 ]
  %cp.i31.sink = phi ptr [ %cp.i40, %chk.i38 ], [ %cp.i31, %chk.i29 ]
  %t40.sink.ph = phi i64 [ %t62, %chk.i38 ], [ %t40, %chk.i29 ]
  %s.2.0.be.ph = phi i64 [ %t44, %chk.i38 ], [ %t26, %chk.i29 ]
  %c1.i35 = add nuw i64 %c.i32.sink, 1
  store i64 %c1.i35, ptr %cp.i31.sink, align 8
  br label %label_0.backedge

label_0.backedge:                                 ; preds = %label_0.backedge.sink.split, %chk.i29, %label_18, %chk.i38, %label_52
  %t40.sink = phi i64 [ %t40, %chk.i29 ], [ %t62, %label_52 ], [ %t62, %chk.i38 ], [ %t40, %label_18 ], [ %t40.sink.ph, %label_0.backedge.sink.split ]
  %s.2.0.be = phi i64 [ %t26, %chk.i29 ], [ %t44, %label_52 ], [ %t44, %chk.i38 ], [ %t26, %label_18 ], [ %s.2.0.be.ph, %label_0.backedge.sink.split ]
  tail call void @axiom_release(i64 %s.4.048)
  tail call void @axiom_release(i64 %t40.sink)
  %c6 = icmp sgt i64 %s.2.0.be, 7
  br i1 %c6, label %label_9, label %label_10

label_19:                                         ; preds = %label_10
  %t44 = add nsw i64 %s.2.047, 1
  %c47 = icmp eq i64 %s.2.047, 0
  br i1 %c47, label %label_52, label %label_51

label_51:                                         ; preds = %label_19
  %t56 = tail call i64 @"Str$strConcat"(i64 %s.4.048, i64 ptrtoint (ptr getelementptr inbounds nuw (i8, ptr @strhdr_10, i64 16) to i64))
  tail call void @axiom_release(i64 ptrtoint (ptr getelementptr inbounds nuw (i8, ptr @strhdr_10, i64 16) to i64))
  br label %label_52

label_52:                                         ; preds = %label_19, %label_51
  %t57 = phi i64 [ %t56, %label_51 ], [ %s.4.048, %label_19 ]
  %t0.i = shl i64 %s.2.047, 1
  %1 = getelementptr i8, ptr %t0.i.i, i64 %t0.i
  %t1.i.i = getelementptr i8, ptr %1, i64 8
  %t2.i.i = load i8, ptr %t1.i.i, align 1
  %t3.i.i = zext i8 %t2.i.i to i64
  %t3.i = shl nuw nsw i64 %t3.i.i, 8
  %t1.i2.i = getelementptr i8, ptr %1, i64 9
  %t2.i3.i = load i8, ptr %t1.i2.i, align 1
  %t3.i4.i = zext i8 %t2.i3.i to i64
  %t7.i = or disjoint i64 %t3.i, %t3.i4.i
  %t61 = tail call i64 @"Fmt$fmtHex"(i64 %t7.i)
  %t62 = tail call i64 @"Str$strConcat"(i64 %t57, i64 %t61)
  tail call void @axiom_release(i64 %t61)
  %imm.i37 = icmp slt i64 %t62, 4096
  br i1 %imm.i37, label %label_0.backedge, label %chk.i38

chk.i38:                                          ; preds = %label_52
  %hoff.i39 = add nsw i64 %t62, -16
  %cp.i40 = inttoptr i64 %hoff.i39 to ptr
  %c.i41 = load i64, ptr %cp.i40, align 8
  %stat.i42 = icmp eq i64 %c.i41, -1
  br i1 %stat.i42, label %label_0.backedge, label %label_0.backedge.sink.split
}

define i64 @"Sys$netAddrTextPort"(i64 %addr) #0 {
  %t0.i.i = inttoptr i64 %addr to ptr
  %t2.i.i = load i8, ptr %t0.i.i, align 1
  %t3.i.i = zext i8 %t2.i.i to i64
  %t1.i.i = getelementptr i8, ptr %t0.i.i, i64 1
  %t2.i2.i = load i8, ptr %t1.i.i, align 1
  %t3.i3.i = zext i8 %t2.i2.i to i64
  %t10.i = shl nuw nsw i64 %t3.i3.i, 8
  %t11.i = or disjoint i64 %t10.i, %t3.i.i
  %c2 = icmp eq i64 %t11.i, 10
  %t9 = tail call i64 @"Sys$netAddrText"(i64 %addr)
  br i1 %c2, label %label_5, label %label_7

label_5:                                          ; preds = %0
  %t10 = tail call i64 @"Str$strConcat"(i64 ptrtoint (ptr getelementptr inbounds nuw (i8, ptr @strhdr_11, i64 16) to i64), i64 %t9)
  tail call void @axiom_release(i64 ptrtoint (ptr getelementptr inbounds nuw (i8, ptr @strhdr_11, i64 16) to i64))
  tail call void @axiom_release(i64 %t9)
  br label %label_7

label_7:                                          ; preds = %0, %label_5
  %.sink17 = phi i64 [ ptrtoint (ptr getelementptr inbounds nuw (i8, ptr @strhdr_12, i64 16) to i64), %label_5 ], [ ptrtoint (ptr getelementptr inbounds nuw (i8, ptr @strhdr_10, i64 16) to i64), %0 ]
  %t9.sink15 = phi i64 [ %t10, %label_5 ], [ %t9, %0 ]
  %t1.i.i6 = getelementptr i8, ptr %t0.i.i, i64 2
  %t2.i.i7 = load i8, ptr %t1.i.i6, align 1
  %t3.i.i8 = zext i8 %t2.i.i7 to i64
  %t1.i9 = shl nuw nsw i64 %t3.i.i8, 8
  %t1.i2.i10 = getelementptr i8, ptr %t0.i.i, i64 3
  %t2.i3.i11 = load i8, ptr %t1.i2.i10, align 1
  %t3.i4.i12 = zext i8 %t2.i3.i11 to i64
  %t3.i13 = or disjoint i64 %t1.i9, %t3.i4.i12
  %t16.i14 = tail call i64 @"Fmt$fmtNat"(i64 %t3.i13)
  %t20 = tail call i64 @"Str$strConcat"(i64 %.sink17, i64 %t16.i14)
  tail call void @axiom_release(i64 %.sink17)
  tail call void @axiom_release(i64 %t16.i14)
  %t21 = tail call i64 @"Str$strConcat"(i64 %t9.sink15, i64 %t20)
  tail call void @axiom_release(i64 %t9.sink15)
  tail call void @axiom_release(i64 %t20)
  ret i64 %t21
}

; Function Attrs: nounwind
define i64 @"Sys$netSetBlocking"(i64 %fd) #1 {
  %t2 = tail call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 25, i64 %fd, i64 3, i64 0, i64 0, i64 0, i64 0) #15
  %c3 = icmp slt i64 %t2, 0
  br i1 %c3, label %label_8, label %label_7

label_7:                                          ; preds = %0
  %t14 = and i64 %t2, 9223372036854773759
  %t15 = tail call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 25, i64 %fd, i64 4, i64 %t14, i64 0, i64 0, i64 0) #15
  br label %label_8

label_8:                                          ; preds = %0, %label_7
  %t16 = phi i64 [ %t15, %label_7 ], [ %t2, %0 ]
  ret i64 %t16
}

; Function Attrs: nounwind
define i64 @"Sys$netConnect"(i64 %fd, i64 %addr) #1 {
  %t0.i.i.i = inttoptr i64 %addr to ptr
  %t2.i.i.i = load i8, ptr %t0.i.i.i, align 1
  %t3.i.i.i = zext i8 %t2.i.i.i to i64
  %t1.i.i.i = getelementptr i8, ptr %t0.i.i.i, i64 1
  %t2.i2.i.i = load i8, ptr %t1.i.i.i, align 1
  %t3.i3.i.i = zext i8 %t2.i2.i.i to i64
  %t10.i.i = shl nuw nsw i64 %t3.i3.i.i, 8
  %t11.i.i = or disjoint i64 %t10.i.i, %t3.i.i.i
  %c2.i = icmp eq i64 %t11.i.i, 10
  %..i = select i1 %c2.i, i64 28, i64 16
  %t2 = tail call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 203, i64 %fd, i64 %addr, i64 %..i, i64 0, i64 0, i64 0) #15
  ret i64 %t2
}

; Function Attrs: nounwind
define i64 @"Sys$netShutdown"(i64 %fd, i64 %how) #1 {
  %t1 = tail call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 210, i64 %fd, i64 %how, i64 0, i64 0, i64 0, i64 0) #15
  ret i64 %t1
}

; Function Attrs: nounwind
define i64 @"Sys$netSetOptInt"(i64 %fd, i64 %level, i64 %name, i64 %value, i64 %v) #1 {
  %t0.i.i = inttoptr i64 %v to ptr
  %t2.i.i = trunc i64 %value to i8
  store i8 %t2.i.i, ptr %t0.i.i, align 1
  %t3.i = lshr i64 %value, 8
  %t1.i2.i = getelementptr i8, ptr %t0.i.i, i64 1
  %t2.i3.i = trunc i64 %t3.i to i8
  store i8 %t2.i3.i, ptr %t1.i2.i, align 1
  %t7.i = lshr i64 %value, 16
  %t1.i5.i = getelementptr i8, ptr %t0.i.i, i64 2
  %t2.i6.i = trunc i64 %t7.i to i8
  store i8 %t2.i6.i, ptr %t1.i5.i, align 1
  %t11.i = lshr i64 %value, 24
  %t1.i8.i = getelementptr i8, ptr %t0.i.i, i64 3
  %t2.i9.i = trunc i64 %t11.i to i8
  store i8 %t2.i9.i, ptr %t1.i8.i, align 1
  %t2 = tail call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 208, i64 %fd, i64 %level, i64 %name, i64 %v, i64 4, i64 0) #15
  ret i64 %t2
}

; Function Attrs: nounwind
define i64 @"Sys$netSetNonBlocking"(i64 %fd) #1 {
  %t2 = tail call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 25, i64 %fd, i64 3, i64 0, i64 0, i64 0, i64 0) #15
  %c3 = icmp slt i64 %t2, 0
  br i1 %c3, label %label_8, label %label_7

label_7:                                          ; preds = %0
  %t12 = or i64 %t2, 2048
  %t13 = tail call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 25, i64 %fd, i64 4, i64 %t12, i64 0, i64 0, i64 0) #15
  br label %label_8

label_8:                                          ; preds = %0, %label_7
  %t14 = phi i64 [ %t13, %label_7 ], [ %t2, %0 ]
  ret i64 %t14
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(none)
define range(i64 0, 2) i64 @"Sys$netWouldBlock"(i64 %r) #6 {
  %c2 = icmp eq i64 %r, -11
  %t3 = zext i1 %c2 to i64
  ret i64 %t3
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(write, inaccessiblemem: none, target_mem0: none, target_mem1: none)
define i64 @"Sys$netPutWord"(i64 returned %buf, i64 %off, i64 %v) #9 {
  %t0.i = inttoptr i64 %buf to ptr
  %t1.i = getelementptr i8, ptr %t0.i, i64 %off
  %t2.i = trunc i64 %v to i8
  store i8 %t2.i, ptr %t1.i, align 1
  %t3 = lshr i64 %v, 8
  %1 = getelementptr i8, ptr %t0.i, i64 %off
  %t1.i2 = getelementptr i8, ptr %1, i64 1
  %t2.i3 = trunc i64 %t3 to i8
  store i8 %t2.i3, ptr %t1.i2, align 1
  %t7 = lshr i64 %v, 16
  %2 = getelementptr i8, ptr %t0.i, i64 %off
  %t1.i5 = getelementptr i8, ptr %2, i64 2
  %t2.i6 = trunc i64 %t7 to i8
  store i8 %t2.i6, ptr %t1.i5, align 1
  %t11 = lshr i64 %v, 24
  %3 = getelementptr i8, ptr %t0.i, i64 %off
  %t1.i8 = getelementptr i8, ptr %3, i64 3
  %t2.i9 = trunc i64 %t11 to i8
  store i8 %t2.i9, ptr %t1.i8, align 1
  %t15 = lshr i64 %v, 32
  %4 = getelementptr i8, ptr %t0.i, i64 %off
  %t1.i11 = getelementptr i8, ptr %4, i64 4
  %t2.i12 = trunc i64 %t15 to i8
  store i8 %t2.i12, ptr %t1.i11, align 1
  %t19 = lshr i64 %v, 40
  %5 = getelementptr i8, ptr %t0.i, i64 %off
  %t1.i14 = getelementptr i8, ptr %5, i64 5
  %t2.i15 = trunc i64 %t19 to i8
  store i8 %t2.i15, ptr %t1.i14, align 1
  %t23 = lshr i64 %v, 48
  %6 = getelementptr i8, ptr %t0.i, i64 %off
  %t1.i17 = getelementptr i8, ptr %6, i64 6
  %t2.i18 = trunc i64 %t23 to i8
  store i8 %t2.i18, ptr %t1.i17, align 1
  %t27 = lshr i64 %v, 56
  %7 = getelementptr i8, ptr %t0.i, i64 %off
  %t1.i20 = getelementptr i8, ptr %7, i64 7
  %t2.i21 = trunc nuw i64 %t27 to i8
  store i8 %t2.i21, ptr %t1.i20, align 1
  ret i64 %buf
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(read, inaccessiblemem: none, target_mem0: none, target_mem1: none)
define i64 @"Sys$netGetWord"(i64 %buf, i64 %off) #8 {
  %t0.i = inttoptr i64 %buf to ptr
  %t1.i = getelementptr i8, ptr %t0.i, i64 %off
  %t2.i = load i8, ptr %t1.i, align 1
  %t3.i = zext i8 %t2.i to i64
  %1 = getelementptr i8, ptr %t0.i, i64 %off
  %t1.i2 = getelementptr i8, ptr %1, i64 1
  %t2.i3 = load i8, ptr %t1.i2, align 1
  %t3.i4 = zext i8 %t2.i3 to i64
  %t3 = shl nuw nsw i64 %t3.i4, 8
  %2 = getelementptr i8, ptr %t0.i, i64 %off
  %t1.i6 = getelementptr i8, ptr %2, i64 2
  %t2.i7 = load i8, ptr %t1.i6, align 1
  %t3.i8 = zext i8 %t2.i7 to i64
  %t6 = shl nuw nsw i64 %t3.i8, 16
  %3 = getelementptr i8, ptr %t0.i, i64 %off
  %t1.i10 = getelementptr i8, ptr %3, i64 3
  %t2.i11 = load i8, ptr %t1.i10, align 1
  %t3.i12 = zext i8 %t2.i11 to i64
  %t9 = shl nuw nsw i64 %t3.i12, 24
  %4 = getelementptr i8, ptr %t0.i, i64 %off
  %t1.i14 = getelementptr i8, ptr %4, i64 4
  %t2.i15 = load i8, ptr %t1.i14, align 1
  %t3.i16 = zext i8 %t2.i15 to i64
  %t12 = shl nuw nsw i64 %t3.i16, 32
  %5 = getelementptr i8, ptr %t0.i, i64 %off
  %t1.i18 = getelementptr i8, ptr %5, i64 5
  %t2.i19 = load i8, ptr %t1.i18, align 1
  %t3.i20 = zext i8 %t2.i19 to i64
  %t15 = shl nuw nsw i64 %t3.i20, 40
  %6 = getelementptr i8, ptr %t0.i, i64 %off
  %t1.i22 = getelementptr i8, ptr %6, i64 6
  %t2.i23 = load i8, ptr %t1.i22, align 1
  %t3.i24 = zext i8 %t2.i23 to i64
  %t18 = shl nuw nsw i64 %t3.i24, 48
  %7 = getelementptr i8, ptr %t0.i, i64 %off
  %t1.i26 = getelementptr i8, ptr %7, i64 7
  %t2.i27 = load i8, ptr %t1.i26, align 1
  %t3.i28 = zext i8 %t2.i27 to i64
  %t21 = shl nuw i64 %t3.i28, 56
  %t22 = or disjoint i64 %t6, %t3
  %t23 = or disjoint i64 %t22, %t9
  %t24 = or disjoint i64 %t23, %t12
  %t25 = or disjoint i64 %t24, %t15
  %t26 = or disjoint i64 %t25, %t18
  %t27 = or disjoint i64 %t26, %t21
  %t28 = add nuw i64 %t27, %t3.i
  ret i64 %t28
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(none)
define range(i64 0, -15) i64 @"Sys$netPollBufBytes"(i64 %n) #6 {
  %t1 = shl i64 %n, 4
  ret i64 %t1
}

; Function Attrs: nounwind
define i64 @"Sys$netPollCreate"() #1 {
  %t1 = tail call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 20, i64 0, i64 0, i64 0, i64 0, i64 0, i64 0) #15
  ret i64 %t1
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(write, inaccessiblemem: none, target_mem0: none, target_mem1: none)
define i64 @"Sys$netPollRec"(i64 returned %rec, i64 %fd, i64 %op) #9 {
label_7:
  %t9.i.i = inttoptr i64 %rec to ptr
  store i8 0, ptr %t9.i.i, align 1
  %t10.i.i.1 = getelementptr i8, ptr %t9.i.i, i64 1
  store i8 0, ptr %t10.i.i.1, align 1
  %t10.i.i.2 = getelementptr i8, ptr %t9.i.i, i64 2
  store i8 0, ptr %t10.i.i.2, align 1
  %t10.i.i.3 = getelementptr i8, ptr %t9.i.i, i64 3
  store i8 0, ptr %t10.i.i.3, align 1
  %t10.i.i.4 = getelementptr i8, ptr %t9.i.i, i64 4
  store i8 0, ptr %t10.i.i.4, align 1
  %t10.i.i.5 = getelementptr i8, ptr %t9.i.i, i64 5
  store i8 0, ptr %t10.i.i.5, align 1
  %t10.i.i.6 = getelementptr i8, ptr %t9.i.i, i64 6
  store i8 0, ptr %t10.i.i.6, align 1
  %t10.i.i.7 = getelementptr i8, ptr %t9.i.i, i64 7
  store i8 0, ptr %t10.i.i.7, align 1
  %t10.i.i.8 = getelementptr i8, ptr %t9.i.i, i64 8
  store i8 0, ptr %t10.i.i.8, align 1
  %t10.i.i.9 = getelementptr i8, ptr %t9.i.i, i64 9
  store i8 0, ptr %t10.i.i.9, align 1
  %t10.i.i.10 = getelementptr i8, ptr %t9.i.i, i64 10
  store i8 0, ptr %t10.i.i.10, align 1
  %t10.i.i.11 = getelementptr i8, ptr %t9.i.i, i64 11
  store i8 0, ptr %t10.i.i.11, align 1
  %t10.i.i.12 = getelementptr i8, ptr %t9.i.i, i64 12
  store i8 0, ptr %t10.i.i.12, align 1
  %t10.i.i.13 = getelementptr i8, ptr %t9.i.i, i64 13
  store i8 0, ptr %t10.i.i.13, align 1
  %t10.i.i.14 = getelementptr i8, ptr %t9.i.i, i64 14
  store i8 0, ptr %t10.i.i.14, align 1
  %t10.i.i.15 = getelementptr i8, ptr %t9.i.i, i64 15
  store i8 0, ptr %t10.i.i.15, align 1
  store i8 1, ptr %t9.i.i, align 1
  %t1.i2.i = getelementptr i8, ptr %t9.i.i, i64 1
  store i8 0, ptr %t1.i2.i, align 1
  %t1.i5.i = getelementptr i8, ptr %t9.i.i, i64 2
  store i8 0, ptr %t1.i5.i, align 1
  %t1.i8.i = getelementptr i8, ptr %t9.i.i, i64 3
  store i8 0, ptr %t1.i8.i, align 1
  %t1.i11.i = getelementptr i8, ptr %t9.i.i, i64 4
  store i8 0, ptr %t1.i11.i, align 1
  %t1.i14.i = getelementptr i8, ptr %t9.i.i, i64 5
  store i8 0, ptr %t1.i14.i, align 1
  %t1.i17.i = getelementptr i8, ptr %t9.i.i, i64 6
  store i8 0, ptr %t1.i17.i, align 1
  %t1.i20.i = getelementptr i8, ptr %t9.i.i, i64 7
  store i8 0, ptr %t1.i20.i, align 1
  %t1.i.i = getelementptr i8, ptr %t9.i.i, i64 8
  %t2.i.i = trunc i64 %fd to i8
  store i8 %t2.i.i, ptr %t1.i.i, align 1
  %t3.i = lshr i64 %fd, 8
  %t1.i2.i2 = getelementptr i8, ptr %t9.i.i, i64 9
  %t2.i3.i = trunc i64 %t3.i to i8
  store i8 %t2.i3.i, ptr %t1.i2.i2, align 1
  %t7.i = lshr i64 %fd, 16
  %t1.i5.i3 = getelementptr i8, ptr %t9.i.i, i64 10
  %t2.i6.i = trunc i64 %t7.i to i8
  store i8 %t2.i6.i, ptr %t1.i5.i3, align 1
  %t11.i = lshr i64 %fd, 24
  %t1.i8.i4 = getelementptr i8, ptr %t9.i.i, i64 11
  %t2.i9.i = trunc i64 %t11.i to i8
  store i8 %t2.i9.i, ptr %t1.i8.i4, align 1
  %t15.i = lshr i64 %fd, 32
  %t1.i11.i5 = getelementptr i8, ptr %t9.i.i, i64 12
  %t2.i12.i = trunc i64 %t15.i to i8
  store i8 %t2.i12.i, ptr %t1.i11.i5, align 1
  %t19.i = lshr i64 %fd, 40
  %t1.i14.i6 = getelementptr i8, ptr %t9.i.i, i64 13
  %t2.i15.i = trunc i64 %t19.i to i8
  store i8 %t2.i15.i, ptr %t1.i14.i6, align 1
  %t23.i = lshr i64 %fd, 48
  %t1.i17.i7 = getelementptr i8, ptr %t9.i.i, i64 14
  %t2.i18.i = trunc i64 %t23.i to i8
  store i8 %t2.i18.i, ptr %t1.i17.i7, align 1
  %t27.i = lshr i64 %fd, 56
  %t1.i20.i8 = getelementptr i8, ptr %t9.i.i, i64 15
  %t2.i21.i = trunc nuw i64 %t27.i to i8
  store i8 %t2.i21.i, ptr %t1.i20.i8, align 1
  ret i64 %rec
}

; Function Attrs: nounwind
define i64 @"Sys$netPollAddRead"(i64 %pfd, i64 %fd, i64 %rec) #1 {
label_7:
  %t9.i.i.i = inttoptr i64 %rec to ptr
  store i8 0, ptr %t9.i.i.i, align 1
  %t10.i.i.1.i = getelementptr i8, ptr %t9.i.i.i, i64 1
  store i8 0, ptr %t10.i.i.1.i, align 1
  %t10.i.i.2.i = getelementptr i8, ptr %t9.i.i.i, i64 2
  store i8 0, ptr %t10.i.i.2.i, align 1
  %t10.i.i.3.i = getelementptr i8, ptr %t9.i.i.i, i64 3
  store i8 0, ptr %t10.i.i.3.i, align 1
  %t10.i.i.4.i = getelementptr i8, ptr %t9.i.i.i, i64 4
  store i8 0, ptr %t10.i.i.4.i, align 1
  %t10.i.i.5.i = getelementptr i8, ptr %t9.i.i.i, i64 5
  store i8 0, ptr %t10.i.i.5.i, align 1
  %t10.i.i.6.i = getelementptr i8, ptr %t9.i.i.i, i64 6
  store i8 0, ptr %t10.i.i.6.i, align 1
  %t10.i.i.7.i = getelementptr i8, ptr %t9.i.i.i, i64 7
  store i8 0, ptr %t10.i.i.7.i, align 1
  %t10.i.i.8.i = getelementptr i8, ptr %t9.i.i.i, i64 8
  store i8 0, ptr %t10.i.i.8.i, align 1
  %t10.i.i.9.i = getelementptr i8, ptr %t9.i.i.i, i64 9
  store i8 0, ptr %t10.i.i.9.i, align 1
  %t10.i.i.10.i = getelementptr i8, ptr %t9.i.i.i, i64 10
  store i8 0, ptr %t10.i.i.10.i, align 1
  %t10.i.i.11.i = getelementptr i8, ptr %t9.i.i.i, i64 11
  store i8 0, ptr %t10.i.i.11.i, align 1
  %t10.i.i.12.i = getelementptr i8, ptr %t9.i.i.i, i64 12
  store i8 0, ptr %t10.i.i.12.i, align 1
  %t10.i.i.13.i = getelementptr i8, ptr %t9.i.i.i, i64 13
  store i8 0, ptr %t10.i.i.13.i, align 1
  %t10.i.i.14.i = getelementptr i8, ptr %t9.i.i.i, i64 14
  store i8 0, ptr %t10.i.i.14.i, align 1
  %t10.i.i.15.i = getelementptr i8, ptr %t9.i.i.i, i64 15
  store i8 0, ptr %t10.i.i.15.i, align 1
  store i8 1, ptr %t9.i.i.i, align 1
  store i8 0, ptr %t10.i.i.1.i, align 1
  store i8 0, ptr %t10.i.i.2.i, align 1
  store i8 0, ptr %t10.i.i.3.i, align 1
  store i8 0, ptr %t10.i.i.4.i, align 1
  store i8 0, ptr %t10.i.i.5.i, align 1
  store i8 0, ptr %t10.i.i.6.i, align 1
  store i8 0, ptr %t10.i.i.7.i, align 1
  %t2.i.i.i = trunc i64 %fd to i8
  store i8 %t2.i.i.i, ptr %t10.i.i.8.i, align 1
  %t3.i.i = lshr i64 %fd, 8
  %t2.i3.i.i = trunc i64 %t3.i.i to i8
  store i8 %t2.i3.i.i, ptr %t10.i.i.9.i, align 1
  %t7.i.i = lshr i64 %fd, 16
  %t2.i6.i.i = trunc i64 %t7.i.i to i8
  store i8 %t2.i6.i.i, ptr %t10.i.i.10.i, align 1
  %t11.i.i = lshr i64 %fd, 24
  %t2.i9.i.i = trunc i64 %t11.i.i to i8
  store i8 %t2.i9.i.i, ptr %t10.i.i.11.i, align 1
  %t15.i.i = lshr i64 %fd, 32
  %t2.i12.i.i = trunc i64 %t15.i.i to i8
  store i8 %t2.i12.i.i, ptr %t10.i.i.12.i, align 1
  %t19.i.i = lshr i64 %fd, 40
  %t2.i15.i.i = trunc i64 %t19.i.i to i8
  store i8 %t2.i15.i.i, ptr %t10.i.i.13.i, align 1
  %t23.i.i = lshr i64 %fd, 48
  %t2.i18.i.i = trunc i64 %t23.i.i to i8
  store i8 %t2.i18.i.i, ptr %t10.i.i.14.i, align 1
  %t27.i.i = lshr i64 %fd, 56
  %t2.i21.i.i = trunc nuw i64 %t27.i.i to i8
  store i8 %t2.i21.i.i, ptr %t10.i.i.15.i, align 1
  %t13 = tail call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 21, i64 %pfd, i64 1, i64 %fd, i64 %rec, i64 0, i64 0) #15
  ret i64 %t13
}

; Function Attrs: nounwind
define i64 @"Sys$netPollDelRead"(i64 %pfd, i64 %fd, i64 %rec) #1 {
label_7:
  %t9.i.i.i = inttoptr i64 %rec to ptr
  store i8 0, ptr %t9.i.i.i, align 1
  %t10.i.i.1.i = getelementptr i8, ptr %t9.i.i.i, i64 1
  store i8 0, ptr %t10.i.i.1.i, align 1
  %t10.i.i.2.i = getelementptr i8, ptr %t9.i.i.i, i64 2
  store i8 0, ptr %t10.i.i.2.i, align 1
  %t10.i.i.3.i = getelementptr i8, ptr %t9.i.i.i, i64 3
  store i8 0, ptr %t10.i.i.3.i, align 1
  %t10.i.i.4.i = getelementptr i8, ptr %t9.i.i.i, i64 4
  store i8 0, ptr %t10.i.i.4.i, align 1
  %t10.i.i.5.i = getelementptr i8, ptr %t9.i.i.i, i64 5
  store i8 0, ptr %t10.i.i.5.i, align 1
  %t10.i.i.6.i = getelementptr i8, ptr %t9.i.i.i, i64 6
  store i8 0, ptr %t10.i.i.6.i, align 1
  %t10.i.i.7.i = getelementptr i8, ptr %t9.i.i.i, i64 7
  store i8 0, ptr %t10.i.i.7.i, align 1
  %t10.i.i.8.i = getelementptr i8, ptr %t9.i.i.i, i64 8
  store i8 0, ptr %t10.i.i.8.i, align 1
  %t10.i.i.9.i = getelementptr i8, ptr %t9.i.i.i, i64 9
  store i8 0, ptr %t10.i.i.9.i, align 1
  %t10.i.i.10.i = getelementptr i8, ptr %t9.i.i.i, i64 10
  store i8 0, ptr %t10.i.i.10.i, align 1
  %t10.i.i.11.i = getelementptr i8, ptr %t9.i.i.i, i64 11
  store i8 0, ptr %t10.i.i.11.i, align 1
  %t10.i.i.12.i = getelementptr i8, ptr %t9.i.i.i, i64 12
  store i8 0, ptr %t10.i.i.12.i, align 1
  %t10.i.i.13.i = getelementptr i8, ptr %t9.i.i.i, i64 13
  store i8 0, ptr %t10.i.i.13.i, align 1
  %t10.i.i.14.i = getelementptr i8, ptr %t9.i.i.i, i64 14
  store i8 0, ptr %t10.i.i.14.i, align 1
  %t10.i.i.15.i = getelementptr i8, ptr %t9.i.i.i, i64 15
  store i8 0, ptr %t10.i.i.15.i, align 1
  store i8 1, ptr %t9.i.i.i, align 1
  store i8 0, ptr %t10.i.i.1.i, align 1
  store i8 0, ptr %t10.i.i.2.i, align 1
  store i8 0, ptr %t10.i.i.3.i, align 1
  store i8 0, ptr %t10.i.i.4.i, align 1
  store i8 0, ptr %t10.i.i.5.i, align 1
  store i8 0, ptr %t10.i.i.6.i, align 1
  store i8 0, ptr %t10.i.i.7.i, align 1
  %t2.i.i.i = trunc i64 %fd to i8
  store i8 %t2.i.i.i, ptr %t10.i.i.8.i, align 1
  %t3.i.i = lshr i64 %fd, 8
  %t2.i3.i.i = trunc i64 %t3.i.i to i8
  store i8 %t2.i3.i.i, ptr %t10.i.i.9.i, align 1
  %t7.i.i = lshr i64 %fd, 16
  %t2.i6.i.i = trunc i64 %t7.i.i to i8
  store i8 %t2.i6.i.i, ptr %t10.i.i.10.i, align 1
  %t11.i.i = lshr i64 %fd, 24
  %t2.i9.i.i = trunc i64 %t11.i.i to i8
  store i8 %t2.i9.i.i, ptr %t10.i.i.11.i, align 1
  %t15.i.i = lshr i64 %fd, 32
  %t2.i12.i.i = trunc i64 %t15.i.i to i8
  store i8 %t2.i12.i.i, ptr %t10.i.i.12.i, align 1
  %t19.i.i = lshr i64 %fd, 40
  %t2.i15.i.i = trunc i64 %t19.i.i to i8
  store i8 %t2.i15.i.i, ptr %t10.i.i.13.i, align 1
  %t23.i.i = lshr i64 %fd, 48
  %t2.i18.i.i = trunc i64 %t23.i.i to i8
  store i8 %t2.i18.i.i, ptr %t10.i.i.14.i, align 1
  %t27.i.i = lshr i64 %fd, 56
  %t2.i21.i.i = trunc nuw i64 %t27.i.i to i8
  store i8 %t2.i21.i.i, ptr %t10.i.i.15.i, align 1
  %t13 = tail call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 21, i64 %pfd, i64 2, i64 %fd, i64 %rec, i64 0, i64 0) #15
  ret i64 %t13
}

; Function Attrs: nounwind
define i64 @"Sys$netPollWait"(i64 %pfd, i64 %buf, i64 %maxEvents, i64 %timeoutMs, i64 %ts) #1 {
label_5:
  %t31 = tail call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 22, i64 %pfd, i64 %buf, i64 %maxEvents, i64 %timeoutMs, i64 0, i64 8) #15
  ret i64 %t31
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(read, inaccessiblemem: none, target_mem0: none, target_mem1: none)
define i64 @"Sys$netPollFdAt"(i64 %buf, i64 %i) #8 {
  %t1 = shl i64 %i, 4
  %t0.i.i = inttoptr i64 %buf to ptr
  %1 = getelementptr i8, ptr %t0.i.i, i64 %t1
  %t1.i.i = getelementptr i8, ptr %1, i64 8
  %t2.i.i = load i8, ptr %t1.i.i, align 1
  %t3.i.i = zext i8 %t2.i.i to i64
  %t1.i2.i = getelementptr i8, ptr %1, i64 9
  %t2.i3.i = load i8, ptr %t1.i2.i, align 1
  %t3.i4.i = zext i8 %t2.i3.i to i64
  %t3.i = shl nuw nsw i64 %t3.i4.i, 8
  %t1.i6.i = getelementptr i8, ptr %1, i64 10
  %t2.i7.i = load i8, ptr %t1.i6.i, align 1
  %t3.i8.i = zext i8 %t2.i7.i to i64
  %t6.i = shl nuw nsw i64 %t3.i8.i, 16
  %t1.i10.i = getelementptr i8, ptr %1, i64 11
  %t2.i11.i = load i8, ptr %t1.i10.i, align 1
  %t3.i12.i = zext i8 %t2.i11.i to i64
  %t9.i = shl nuw nsw i64 %t3.i12.i, 24
  %t1.i14.i = getelementptr i8, ptr %1, i64 12
  %t2.i15.i = load i8, ptr %t1.i14.i, align 1
  %t3.i16.i = zext i8 %t2.i15.i to i64
  %t12.i = shl nuw nsw i64 %t3.i16.i, 32
  %t1.i18.i = getelementptr i8, ptr %1, i64 13
  %t2.i19.i = load i8, ptr %t1.i18.i, align 1
  %t3.i20.i = zext i8 %t2.i19.i to i64
  %t15.i = shl nuw nsw i64 %t3.i20.i, 40
  %t1.i22.i = getelementptr i8, ptr %1, i64 14
  %t2.i23.i = load i8, ptr %t1.i22.i, align 1
  %t3.i24.i = zext i8 %t2.i23.i to i64
  %t18.i = shl nuw nsw i64 %t3.i24.i, 48
  %t1.i26.i = getelementptr i8, ptr %1, i64 15
  %t2.i27.i = load i8, ptr %t1.i26.i, align 1
  %t3.i28.i = zext i8 %t2.i27.i to i64
  %t21.i = shl nuw i64 %t3.i28.i, 56
  %t22.i = or disjoint i64 %t6.i, %t3.i
  %t23.i = or disjoint i64 %t22.i, %t9.i
  %t24.i = or disjoint i64 %t23.i, %t12.i
  %t25.i = or disjoint i64 %t24.i, %t15.i
  %t26.i = or disjoint i64 %t25.i, %t18.i
  %t27.i = or disjoint i64 %t26.i, %t21.i
  %t28.i = add nuw i64 %t27.i, %t3.i.i
  ret i64 %t28.i
}

; Function Attrs: nounwind
define range(i64 -9223372036854775808, 1) i64 @"Sys$sysRandomBytes"(i64 %buf, i64 %n) #1 {
  %c69 = icmp sgt i64 %n, 0
  br i1 %c69, label %label_3, label %label_4

label_3:                                          ; preds = %0, %label_3
  %s.1.011 = phi i64 [ %s.1.1, %label_3 ], [ 0, %0 ]
  %s.0.010 = phi i64 [ %s.0.1, %label_3 ], [ 0, %0 ]
  %t20 = sub i64 %n, %s.0.010
  %spec.select = tail call i64 @llvm.smin.i64(i64 %t20, i64 256)
  %t34 = add i64 %s.0.010, %buf
  %t35 = tail call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 278, i64 %t34, i64 %spec.select, i64 0, i64 0, i64 0, i64 0) #15
  %c36 = icmp slt i64 %t35, 0
  %c51 = icmp eq i64 %t35, 0
  %spec.select8 = select i1 %c51, i64 -1, i64 %s.1.011
  %t59 = tail call i64 @llvm.smax.i64(i64 %t35, i64 0)
  %s.0.1 = add i64 %t59, %s.0.010
  %s.1.1 = select i1 %c36, i64 %t35, i64 %spec.select8
  %c6 = icmp slt i64 %s.0.1, %n
  %c13 = icmp eq i64 %s.1.1, 0
  %narrow = select i1 %c6, i1 %c13, i1 false
  br i1 %narrow, label %label_3, label %label_4.loopexit

label_4.loopexit:                                 ; preds = %label_3
  %1 = tail call i64 @llvm.smin.i64(i64 %s.1.1, i64 0)
  br label %label_4

label_4:                                          ; preds = %label_4.loopexit, %0
  %s.1.0.lcssa = phi i64 [ 0, %0 ], [ %1, %label_4.loopexit ]
  ret i64 %s.1.0.lcssa
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(none)
define range(i64 1, -9223372036854775807) i64 @"Sys$sysSigBit"(i64 %signo) #6 {
  %t0 = add i64 %signo, -1
  %t1 = shl nuw i64 1, %t0
  ret i64 %t1
}

; Function Attrs: nounwind
define i64 @"Sys$sysSignalBlock"(i64 %mask, i64 %setbuf) #1 {
  %t0.i.i = inttoptr i64 %setbuf to ptr
  %t2.i.i = trunc i64 %mask to i8
  store i8 %t2.i.i, ptr %t0.i.i, align 1
  %t3.i = lshr i64 %mask, 8
  %t1.i2.i = getelementptr i8, ptr %t0.i.i, i64 1
  %t2.i3.i = trunc i64 %t3.i to i8
  store i8 %t2.i3.i, ptr %t1.i2.i, align 1
  %t7.i = lshr i64 %mask, 16
  %t1.i5.i = getelementptr i8, ptr %t0.i.i, i64 2
  %t2.i6.i = trunc i64 %t7.i to i8
  store i8 %t2.i6.i, ptr %t1.i5.i, align 1
  %t11.i = lshr i64 %mask, 24
  %t1.i8.i = getelementptr i8, ptr %t0.i.i, i64 3
  %t2.i9.i = trunc i64 %t11.i to i8
  store i8 %t2.i9.i, ptr %t1.i8.i, align 1
  %t15.i = lshr i64 %mask, 32
  %t1.i11.i = getelementptr i8, ptr %t0.i.i, i64 4
  %t2.i12.i = trunc i64 %t15.i to i8
  store i8 %t2.i12.i, ptr %t1.i11.i, align 1
  %t19.i = lshr i64 %mask, 40
  %t1.i14.i = getelementptr i8, ptr %t0.i.i, i64 5
  %t2.i15.i = trunc i64 %t19.i to i8
  store i8 %t2.i15.i, ptr %t1.i14.i, align 1
  %t23.i = lshr i64 %mask, 48
  %t1.i17.i = getelementptr i8, ptr %t0.i.i, i64 6
  %t2.i18.i = trunc i64 %t23.i to i8
  store i8 %t2.i18.i, ptr %t1.i17.i, align 1
  %t27.i = lshr i64 %mask, 56
  %t1.i20.i = getelementptr i8, ptr %t0.i.i, i64 7
  %t2.i21.i = trunc nuw i64 %t27.i to i8
  store i8 %t2.i21.i, ptr %t1.i20.i, align 1
  %t4 = tail call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 135, i64 0, i64 %setbuf, i64 0, i64 8, i64 0, i64 0) #15
  ret i64 %t4
}

; Function Attrs: nounwind
define i64 @"Sys$netSignalOpen"(i64 %pfd, i64 %mask, i64 %rec, i64 %setbuf) #1 {
label_4:
  %t0.i.i = inttoptr i64 %setbuf to ptr
  %t2.i.i = trunc i64 %mask to i8
  store i8 %t2.i.i, ptr %t0.i.i, align 1
  %t3.i = lshr i64 %mask, 8
  %t1.i2.i = getelementptr i8, ptr %t0.i.i, i64 1
  %t2.i3.i = trunc i64 %t3.i to i8
  store i8 %t2.i3.i, ptr %t1.i2.i, align 1
  %t7.i = lshr i64 %mask, 16
  %t1.i5.i = getelementptr i8, ptr %t0.i.i, i64 2
  %t2.i6.i = trunc i64 %t7.i to i8
  store i8 %t2.i6.i, ptr %t1.i5.i, align 1
  %t11.i = lshr i64 %mask, 24
  %t1.i8.i = getelementptr i8, ptr %t0.i.i, i64 3
  %t2.i9.i = trunc i64 %t11.i to i8
  store i8 %t2.i9.i, ptr %t1.i8.i, align 1
  %t15.i = lshr i64 %mask, 32
  %t1.i11.i = getelementptr i8, ptr %t0.i.i, i64 4
  %t2.i12.i = trunc i64 %t15.i to i8
  store i8 %t2.i12.i, ptr %t1.i11.i, align 1
  %t19.i = lshr i64 %mask, 40
  %t1.i14.i = getelementptr i8, ptr %t0.i.i, i64 5
  %t2.i15.i = trunc i64 %t19.i to i8
  store i8 %t2.i15.i, ptr %t1.i14.i, align 1
  %t23.i = lshr i64 %mask, 48
  %t1.i17.i = getelementptr i8, ptr %t0.i.i, i64 6
  %t2.i18.i = trunc i64 %t23.i to i8
  store i8 %t2.i18.i, ptr %t1.i17.i, align 1
  %t27.i = lshr i64 %mask, 56
  %t1.i20.i = getelementptr i8, ptr %t0.i.i, i64 7
  %t2.i21.i = trunc nuw i64 %t27.i to i8
  store i8 %t2.i21.i, ptr %t1.i20.i, align 1
  %t11 = tail call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 74, i64 -1, i64 %setbuf, i64 8, i64 0, i64 0, i64 0) #15
  %c12 = icmp slt i64 %t11, 0
  br i1 %c12, label %label_6, label %label_16

label_16:                                         ; preds = %label_4
  %t9.i.i.i = inttoptr i64 %rec to ptr
  store i8 0, ptr %t9.i.i.i, align 1
  %t10.i.i.1.i = getelementptr i8, ptr %t9.i.i.i, i64 1
  store i8 0, ptr %t10.i.i.1.i, align 1
  %t10.i.i.2.i = getelementptr i8, ptr %t9.i.i.i, i64 2
  store i8 0, ptr %t10.i.i.2.i, align 1
  %t10.i.i.3.i = getelementptr i8, ptr %t9.i.i.i, i64 3
  store i8 0, ptr %t10.i.i.3.i, align 1
  %t10.i.i.4.i = getelementptr i8, ptr %t9.i.i.i, i64 4
  store i8 0, ptr %t10.i.i.4.i, align 1
  %t10.i.i.5.i = getelementptr i8, ptr %t9.i.i.i, i64 5
  store i8 0, ptr %t10.i.i.5.i, align 1
  %t10.i.i.6.i = getelementptr i8, ptr %t9.i.i.i, i64 6
  store i8 0, ptr %t10.i.i.6.i, align 1
  %t10.i.i.7.i = getelementptr i8, ptr %t9.i.i.i, i64 7
  store i8 0, ptr %t10.i.i.7.i, align 1
  %t10.i.i.8.i = getelementptr i8, ptr %t9.i.i.i, i64 8
  store i8 0, ptr %t10.i.i.8.i, align 1
  %t10.i.i.9.i = getelementptr i8, ptr %t9.i.i.i, i64 9
  store i8 0, ptr %t10.i.i.9.i, align 1
  %t10.i.i.10.i = getelementptr i8, ptr %t9.i.i.i, i64 10
  store i8 0, ptr %t10.i.i.10.i, align 1
  %t10.i.i.11.i = getelementptr i8, ptr %t9.i.i.i, i64 11
  store i8 0, ptr %t10.i.i.11.i, align 1
  %t10.i.i.12.i = getelementptr i8, ptr %t9.i.i.i, i64 12
  store i8 0, ptr %t10.i.i.12.i, align 1
  %t10.i.i.13.i = getelementptr i8, ptr %t9.i.i.i, i64 13
  store i8 0, ptr %t10.i.i.13.i, align 1
  %t10.i.i.14.i = getelementptr i8, ptr %t9.i.i.i, i64 14
  store i8 0, ptr %t10.i.i.14.i, align 1
  %t10.i.i.15.i = getelementptr i8, ptr %t9.i.i.i, i64 15
  store i8 0, ptr %t10.i.i.15.i, align 1
  store i8 1, ptr %t9.i.i.i, align 1
  store i8 0, ptr %t10.i.i.1.i, align 1
  store i8 0, ptr %t10.i.i.2.i, align 1
  store i8 0, ptr %t10.i.i.3.i, align 1
  store i8 0, ptr %t10.i.i.4.i, align 1
  store i8 0, ptr %t10.i.i.5.i, align 1
  store i8 0, ptr %t10.i.i.6.i, align 1
  store i8 0, ptr %t10.i.i.7.i, align 1
  %t2.i.i.i = trunc i64 %t11 to i8
  store i8 %t2.i.i.i, ptr %t10.i.i.8.i, align 1
  %t3.i.i = lshr i64 %t11, 8
  %t2.i3.i.i = trunc i64 %t3.i.i to i8
  store i8 %t2.i3.i.i, ptr %t10.i.i.9.i, align 1
  %t7.i.i = lshr i64 %t11, 16
  %t2.i6.i.i = trunc i64 %t7.i.i to i8
  store i8 %t2.i6.i.i, ptr %t10.i.i.10.i, align 1
  %t11.i.i = lshr i64 %t11, 24
  %t2.i9.i.i = trunc i64 %t11.i.i to i8
  store i8 %t2.i9.i.i, ptr %t10.i.i.11.i, align 1
  %t15.i.i = lshr i64 %t11, 32
  %t2.i12.i.i = trunc i64 %t15.i.i to i8
  store i8 %t2.i12.i.i, ptr %t10.i.i.12.i, align 1
  %t19.i.i = lshr i64 %t11, 40
  %t2.i15.i.i = trunc i64 %t19.i.i to i8
  store i8 %t2.i15.i.i, ptr %t10.i.i.13.i, align 1
  %t23.i.i = lshr i64 %t11, 48
  %t2.i18.i.i = trunc i64 %t23.i.i to i8
  store i8 %t2.i18.i.i, ptr %t10.i.i.14.i, align 1
  %t27.i.i = lshr i64 %t11, 56
  %t2.i21.i.i = trunc nuw nsw i64 %t27.i.i to i8
  store i8 %t2.i21.i.i, ptr %t10.i.i.15.i, align 1
  %t22 = tail call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 21, i64 %pfd, i64 1, i64 %t11, i64 %rec, i64 0, i64 0) #15
  %c23 = icmp slt i64 %t22, 0
  %t22.t11 = select i1 %c23, i64 %t22, i64 %t11
  br label %label_6

label_6:                                          ; preds = %label_16, %label_4
  %t77 = phi i64 [ %t11, %label_4 ], [ %t22.t11, %label_16 ]
  ret i64 %t77
}

; Function Attrs: nounwind
define range(i64 -1, 4294967296) i64 @"Sys$netPollSignalAt"(i64 %buf, i64 %i, i64 %sigHandle, i64 %scratch) #1 {
label_4:
  %t1.i = shl i64 %i, 4
  %t0.i.i.i = inttoptr i64 %buf to ptr
  %0 = getelementptr i8, ptr %t0.i.i.i, i64 %t1.i
  %t1.i.i.i = getelementptr i8, ptr %0, i64 8
  %t2.i.i.i = load i8, ptr %t1.i.i.i, align 1
  %t3.i.i.i = zext i8 %t2.i.i.i to i64
  %t1.i2.i.i = getelementptr i8, ptr %0, i64 9
  %t2.i3.i.i = load i8, ptr %t1.i2.i.i, align 1
  %t3.i4.i.i = zext i8 %t2.i3.i.i to i64
  %t3.i.i = shl nuw nsw i64 %t3.i4.i.i, 8
  %t1.i6.i.i = getelementptr i8, ptr %0, i64 10
  %t2.i7.i.i = load i8, ptr %t1.i6.i.i, align 1
  %t3.i8.i.i = zext i8 %t2.i7.i.i to i64
  %t6.i.i = shl nuw nsw i64 %t3.i8.i.i, 16
  %t1.i10.i.i = getelementptr i8, ptr %0, i64 11
  %t2.i11.i.i = load i8, ptr %t1.i10.i.i, align 1
  %t3.i12.i.i = zext i8 %t2.i11.i.i to i64
  %t9.i.i = shl nuw nsw i64 %t3.i12.i.i, 24
  %t1.i14.i.i = getelementptr i8, ptr %0, i64 12
  %t2.i15.i.i = load i8, ptr %t1.i14.i.i, align 1
  %t3.i16.i.i = zext i8 %t2.i15.i.i to i64
  %t12.i.i = shl nuw nsw i64 %t3.i16.i.i, 32
  %t1.i18.i.i = getelementptr i8, ptr %0, i64 13
  %t2.i19.i.i = load i8, ptr %t1.i18.i.i, align 1
  %t3.i20.i.i = zext i8 %t2.i19.i.i to i64
  %t15.i.i = shl nuw nsw i64 %t3.i20.i.i, 40
  %t1.i22.i.i = getelementptr i8, ptr %0, i64 14
  %t2.i23.i.i = load i8, ptr %t1.i22.i.i, align 1
  %t3.i24.i.i = zext i8 %t2.i23.i.i to i64
  %t18.i.i = shl nuw nsw i64 %t3.i24.i.i, 48
  %t1.i26.i.i = getelementptr i8, ptr %0, i64 15
  %t2.i27.i.i = load i8, ptr %t1.i26.i.i, align 1
  %t3.i28.i.i = zext i8 %t2.i27.i.i to i64
  %t21.i.i = shl nuw i64 %t3.i28.i.i, 56
  %t22.i.i = or disjoint i64 %t6.i.i, %t3.i.i
  %t23.i.i = or disjoint i64 %t22.i.i, %t9.i.i
  %t24.i.i = or disjoint i64 %t23.i.i, %t12.i.i
  %t25.i.i = or disjoint i64 %t24.i.i, %t15.i.i
  %t26.i.i = or disjoint i64 %t25.i.i, %t18.i.i
  %t27.i.i = or disjoint i64 %t26.i.i, %t21.i.i
  %t28.i.i = add nuw i64 %t27.i.i, %t3.i.i.i
  %c8.not = icmp eq i64 %t28.i.i, %sigHandle
  br i1 %c8.not, label %label_12, label %label_6

label_12:                                         ; preds = %label_4
  %t17 = tail call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 63, i64 %sigHandle, i64 %scratch, i64 128, i64 0, i64 0, i64 0) #15
  %c19 = icmp slt i64 %t17, 128
  br i1 %c19, label %label_6, label %label_23

label_23:                                         ; preds = %label_12
  %t0.i = inttoptr i64 %scratch to ptr
  %t2.i = load i8, ptr %t0.i, align 1
  %t3.i = zext i8 %t2.i to i64
  %t1.i3 = getelementptr i8, ptr %t0.i, i64 1
  %t2.i4 = load i8, ptr %t1.i3, align 1
  %t3.i5 = zext i8 %t2.i4 to i64
  %t28 = shl nuw nsw i64 %t3.i5, 8
  %t1.i7 = getelementptr i8, ptr %t0.i, i64 2
  %t2.i8 = load i8, ptr %t1.i7, align 1
  %t3.i9 = zext i8 %t2.i8 to i64
  %t30 = shl nuw nsw i64 %t3.i9, 16
  %t1.i11 = getelementptr i8, ptr %t0.i, i64 3
  %t2.i12 = load i8, ptr %t1.i11, align 1
  %t3.i13 = zext i8 %t2.i12 to i64
  %t32 = shl nuw nsw i64 %t3.i13, 24
  %t33 = or disjoint i64 %t28, %t3.i
  %t34 = or disjoint i64 %t33, %t30
  %t35 = or disjoint i64 %t34, %t32
  br label %label_6

label_6:                                          ; preds = %label_12, %label_4, %label_23
  %t66 = phi i64 [ %t35, %label_23 ], [ -1, %label_4 ], [ -1, %label_12 ]
  ret i64 %t66
}

; Function Attrs: nounwind
define i64 @"Sys$sysKill"(i64 %pid, i64 %signo) #1 {
  %t1 = tail call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 129, i64 %pid, i64 %signo, i64 0, i64 0, i64 0, i64 0) #15
  ret i64 %t1
}

; Function Attrs: nounwind
define i64 @"Sys$sysForkProcess"() #1 {
label_8:
  %t2 = tail call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 220, i64 17, i64 0, i64 0, i64 0, i64 0, i64 0) #15
  ret i64 %t2
}

; Function Attrs: nounwind
define i64 @"IO$writeStr"(i64 %fd, i64 %s) #1 {
  %t0.i.i = inttoptr i64 %s to ptr
  %t1.i.i = getelementptr i8, ptr %t0.i.i, i64 8
  %t2.i.i = load i64, ptr %t1.i.i, align 8
  %t2.i.i2 = load i64, ptr %t0.i.i, align 8
  %c7.not11.i = icmp sgt i64 %t2.i.i2, 0
  br i1 %c7.not11.i, label %label_11.i, label %"Sys$sysWriteAllFd.exit"

label_11.i:                                       ; preds = %0, %label_26.i
  %s.4.012.i = phi i64 [ %t40.i, %label_26.i ], [ 0, %0 ]
  %t17.i = add i64 %s.4.012.i, %t2.i.i
  %t20.i = sub i64 %t2.i.i2, %s.4.012.i
  %t1.i.i3 = tail call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 64, i64 %fd, i64 %t17.i, i64 %t20.i, i64 0, i64 0, i64 0) #15
  %c22.i = icmp slt i64 %t1.i.i3, 1
  br i1 %c22.i, label %label_25.i, label %label_26.i

label_25.i:                                       ; preds = %label_11.i
  %c28.not.i = icmp eq i64 %t1.i.i3, 0
  %t35.i = select i1 %c28.not.i, i64 %s.4.012.i, i64 %t1.i.i3
  br label %"Sys$sysWriteAllFd.exit"

label_26.i:                                       ; preds = %label_11.i
  %t40.i = add i64 %t1.i.i3, %s.4.012.i
  %c7.not.i = icmp slt i64 %t40.i, %t2.i.i2
  br i1 %c7.not.i, label %label_11.i, label %"Sys$sysWriteAllFd.exit"

"Sys$sysWriteAllFd.exit":                         ; preds = %label_26.i, %0, %label_25.i
  %t41.i = phi i64 [ %t35.i, %label_25.i ], [ 0, %0 ], [ %t40.i, %label_26.i ]
  ret i64 %t41.i
}

; Function Attrs: nounwind
define i64 @"IO$printLit"(i64 %cstr) #1 {
  %t5.i = inttoptr i64 %cstr to ptr
  br label %label_0.i

label_0.i:                                        ; preds = %label_0.i, %0
  %s.2.0.i = phi i64 [ 0, %0 ], [ %t18.i, %label_0.i ]
  %t6.i = getelementptr i8, ptr %t5.i, i64 %s.2.0.i
  %t7.i = load i8, ptr %t6.i, align 1
  %c9.i = icmp eq i8 %t7.i, 0
  %t18.i = add i64 %s.2.0.i, 1
  br i1 %c9.i, label %"Str$cstrLen.exit", label %label_0.i

"Str$cstrLen.exit":                               ; preds = %label_0.i
  %c7.not11.i = icmp sgt i64 %s.2.0.i, 0
  br i1 %c7.not11.i, label %label_11.i, label %"Sys$sysWriteAllFd.exit"

label_11.i:                                       ; preds = %"Str$cstrLen.exit", %label_26.i
  %s.4.012.i = phi i64 [ %t40.i, %label_26.i ], [ 0, %"Str$cstrLen.exit" ]
  %t17.i = add i64 %s.4.012.i, %cstr
  %t20.i = sub i64 %s.2.0.i, %s.4.012.i
  %t1.i.i = tail call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 64, i64 1, i64 %t17.i, i64 %t20.i, i64 0, i64 0, i64 0) #15
  %c22.i = icmp slt i64 %t1.i.i, 1
  br i1 %c22.i, label %label_25.i, label %label_26.i

label_25.i:                                       ; preds = %label_11.i
  %c28.not.i = icmp eq i64 %t1.i.i, 0
  %t35.i = select i1 %c28.not.i, i64 %s.4.012.i, i64 %t1.i.i
  br label %"Sys$sysWriteAllFd.exit"

label_26.i:                                       ; preds = %label_11.i
  %t40.i = add i64 %t1.i.i, %s.4.012.i
  %c7.not.i = icmp slt i64 %t40.i, %s.2.0.i
  br i1 %c7.not.i, label %label_11.i, label %"Sys$sysWriteAllFd.exit"

"Sys$sysWriteAllFd.exit":                         ; preds = %label_26.i, %"Str$cstrLen.exit", %label_25.i
  %t41.i = phi i64 [ %t35.i, %label_25.i ], [ 0, %"Str$cstrLen.exit" ], [ %t40.i, %label_26.i ]
  ret i64 %t41.i
}

; Function Attrs: nounwind
define i64 @"IO$printlnLit"(i64 %cstr) #1 {
  %t5.i.i = inttoptr i64 %cstr to ptr
  br label %label_0.i.i

label_0.i.i:                                      ; preds = %label_0.i.i, %0
  %s.2.0.i.i = phi i64 [ 0, %0 ], [ %t18.i.i, %label_0.i.i ]
  %t6.i.i = getelementptr i8, ptr %t5.i.i, i64 %s.2.0.i.i
  %t7.i.i = load i8, ptr %t6.i.i, align 1
  %c9.i.i = icmp eq i8 %t7.i.i, 0
  %t18.i.i = add i64 %s.2.0.i.i, 1
  br i1 %c9.i.i, label %"Str$cstrLen.exit.i", label %label_0.i.i

"Str$cstrLen.exit.i":                             ; preds = %label_0.i.i
  %c7.not11.i.i = icmp sgt i64 %s.2.0.i.i, 0
  br i1 %c7.not11.i.i, label %label_11.i.i, label %label_11.i.i10

label_11.i.i:                                     ; preds = %"Str$cstrLen.exit.i", %label_11.i.i
  %s.4.012.i.i = phi i64 [ %t40.i.i, %label_11.i.i ], [ 0, %"Str$cstrLen.exit.i" ]
  %t17.i.i = add i64 %s.4.012.i.i, %cstr
  %t20.i.i = sub i64 %s.2.0.i.i, %s.4.012.i.i
  %t1.i.i.i = tail call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 64, i64 1, i64 %t17.i.i, i64 %t20.i.i, i64 0, i64 0, i64 0) #15
  %c22.i.i = icmp sgt i64 %t1.i.i.i, 0
  %t40.i.i = add i64 %t1.i.i.i, %s.4.012.i.i
  %c7.not.i.i = icmp slt i64 %t40.i.i, %s.2.0.i.i
  %or.cond = select i1 %c22.i.i, i1 %c7.not.i.i, i1 false
  br i1 %or.cond, label %label_11.i.i, label %label_11.i.i10

label_11.i.i10:                                   ; preds = %label_11.i.i, %"Str$cstrLen.exit.i"
  %t1.i.i.i14 = tail call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 64, i64 1, i64 ptrtoint (ptr @str_13 to i64), i64 1, i64 0, i64 0, i64 0) #15
  ret i64 %t1.i.i.i14
}

define i64 @"IO$readFileLit"(i64 %cstr) #0 {
  %t0 = tail call i64 @"Sys$sysReadFile"(i64 %cstr)
  ret i64 %t0
}

define i64 @"IO$readFile"(i64 %path) #0 {
  %t0.i = tail call i64 @"Str$strDup"(i64 %path)
  %t0.i.i.i.i = inttoptr i64 %t0.i to ptr
  %t1.i.i.i.i = getelementptr i8, ptr %t0.i.i.i.i, i64 8
  %t2.i.i.i.i = load i64, ptr %t1.i.i.i.i, align 8
  %t0.i1 = tail call i64 @"Sys$sysReadFile"(i64 %t2.i.i.i.i)
  ret i64 %t0.i1
}

; Function Attrs: nounwind
define i64 @"IO$ioPath"(i64 %path) #1 {
  %t0 = tail call i64 @"Str$strDup"(i64 %path)
  %t0.i.i.i = inttoptr i64 %t0 to ptr
  %t1.i.i.i = getelementptr i8, ptr %t0.i.i.i, i64 8
  %t2.i.i.i = load i64, ptr %t1.i.i.i, align 8
  ret i64 %t2.i.i.i
}

; Function Attrs: nounwind
define i64 @"IO$writeFile"(i64 %path, i64 %s) #1 {
  %t0.i = tail call i64 @"Str$strDup"(i64 %path)
  %t0.i.i.i.i = inttoptr i64 %t0.i to ptr
  %t1.i.i.i.i = getelementptr i8, ptr %t0.i.i.i.i, i64 8
  %t2.i.i.i.i = load i64, ptr %t1.i.i.i.i, align 8
  %t9.i.i.i = tail call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 56, i64 -100, i64 %t2.i.i.i.i, i64 577, i64 420, i64 0, i64 0) #15
  %t3.not.i = icmp sgt i64 %t9.i.i.i, -1
  br i1 %t3.not.i, label %label_5.i, label %"Sys$sysWriteFile.exit"

label_5.i:                                        ; preds = %0
  %t0.i.i.i = inttoptr i64 %s to ptr
  %t1.i.i.i = getelementptr i8, ptr %t0.i.i.i, i64 8
  %t2.i.i.i = load i64, ptr %t1.i.i.i, align 8
  %t2.i.i2.i = load i64, ptr %t0.i.i.i, align 8
  %c7.not11.i.i = icmp sgt i64 %t2.i.i2.i, 0
  br i1 %c7.not11.i.i, label %label_11.i.i, label %"Sys$sysWriteAllFd.exit.i"

label_11.i.i:                                     ; preds = %label_5.i, %label_26.i.i
  %s.4.012.i.i = phi i64 [ %t40.i.i, %label_26.i.i ], [ 0, %label_5.i ]
  %t17.i.i = add i64 %s.4.012.i.i, %t2.i.i.i
  %t20.i.i = sub i64 %t2.i.i2.i, %s.4.012.i.i
  %t1.i.i3.i = tail call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 64, i64 %t9.i.i.i, i64 %t17.i.i, i64 %t20.i.i, i64 0, i64 0, i64 0) #15
  %c22.i.i = icmp slt i64 %t1.i.i3.i, 1
  br i1 %c22.i.i, label %label_25.i.i, label %label_26.i.i

label_25.i.i:                                     ; preds = %label_11.i.i
  %c28.not.i.i = icmp eq i64 %t1.i.i3.i, 0
  %t35.i.i = select i1 %c28.not.i.i, i64 %s.4.012.i.i, i64 %t1.i.i3.i
  br label %"Sys$sysWriteAllFd.exit.i"

label_26.i.i:                                     ; preds = %label_11.i.i
  %t40.i.i = add i64 %t1.i.i3.i, %s.4.012.i.i
  %c7.not.i.i = icmp slt i64 %t40.i.i, %t2.i.i2.i
  br i1 %c7.not.i.i, label %label_11.i.i, label %"Sys$sysWriteAllFd.exit.i"

"Sys$sysWriteAllFd.exit.i":                       ; preds = %label_26.i.i, %label_25.i.i, %label_5.i
  %t41.i.i = phi i64 [ %t35.i.i, %label_25.i.i ], [ 0, %label_5.i ], [ %t40.i.i, %label_26.i.i ]
  %t1.i.i = tail call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 57, i64 %t9.i.i.i, i64 0, i64 0, i64 0, i64 0, i64 0) #15
  br label %"Sys$sysWriteFile.exit"

"Sys$sysWriteFile.exit":                          ; preds = %0, %"Sys$sysWriteAllFd.exit.i"
  %t11.i = phi i64 [ %t41.i.i, %"Sys$sysWriteAllFd.exit.i" ], [ %t9.i.i.i, %0 ]
  ret i64 %t11.i
}

; Function Attrs: nounwind
define i64 @"IO$appendFile"(i64 %path, i64 %s) #1 {
  %t0.i = tail call i64 @"Str$strDup"(i64 %path)
  %t0.i.i.i.i = inttoptr i64 %t0.i to ptr
  %t1.i.i.i.i = getelementptr i8, ptr %t0.i.i.i.i, i64 8
  %t2.i.i.i.i = load i64, ptr %t1.i.i.i.i, align 8
  %t9.i.i.i = tail call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 56, i64 -100, i64 %t2.i.i.i.i, i64 1089, i64 420, i64 0, i64 0) #15
  %t3.not.i = icmp sgt i64 %t9.i.i.i, -1
  br i1 %t3.not.i, label %label_5.i, label %"Sys$sysAppendFile.exit"

label_5.i:                                        ; preds = %0
  %t0.i.i.i = inttoptr i64 %s to ptr
  %t1.i.i.i = getelementptr i8, ptr %t0.i.i.i, i64 8
  %t2.i.i.i = load i64, ptr %t1.i.i.i, align 8
  %t2.i.i2.i = load i64, ptr %t0.i.i.i, align 8
  %c7.not11.i.i = icmp sgt i64 %t2.i.i2.i, 0
  br i1 %c7.not11.i.i, label %label_11.i.i, label %"Sys$sysWriteAllFd.exit.i"

label_11.i.i:                                     ; preds = %label_5.i, %label_26.i.i
  %s.4.012.i.i = phi i64 [ %t40.i.i, %label_26.i.i ], [ 0, %label_5.i ]
  %t17.i.i = add i64 %s.4.012.i.i, %t2.i.i.i
  %t20.i.i = sub i64 %t2.i.i2.i, %s.4.012.i.i
  %t1.i.i3.i = tail call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 64, i64 %t9.i.i.i, i64 %t17.i.i, i64 %t20.i.i, i64 0, i64 0, i64 0) #15
  %c22.i.i = icmp slt i64 %t1.i.i3.i, 1
  br i1 %c22.i.i, label %label_25.i.i, label %label_26.i.i

label_25.i.i:                                     ; preds = %label_11.i.i
  %c28.not.i.i = icmp eq i64 %t1.i.i3.i, 0
  %t35.i.i = select i1 %c28.not.i.i, i64 %s.4.012.i.i, i64 %t1.i.i3.i
  br label %"Sys$sysWriteAllFd.exit.i"

label_26.i.i:                                     ; preds = %label_11.i.i
  %t40.i.i = add i64 %t1.i.i3.i, %s.4.012.i.i
  %c7.not.i.i = icmp slt i64 %t40.i.i, %t2.i.i2.i
  br i1 %c7.not.i.i, label %label_11.i.i, label %"Sys$sysWriteAllFd.exit.i"

"Sys$sysWriteAllFd.exit.i":                       ; preds = %label_26.i.i, %label_25.i.i, %label_5.i
  %t41.i.i = phi i64 [ %t35.i.i, %label_25.i.i ], [ 0, %label_5.i ], [ %t40.i.i, %label_26.i.i ]
  %t1.i.i = tail call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 57, i64 %t9.i.i.i, i64 0, i64 0, i64 0, i64 0, i64 0) #15
  br label %"Sys$sysAppendFile.exit"

"Sys$sysAppendFile.exit":                         ; preds = %0, %"Sys$sysWriteAllFd.exit.i"
  %t11.i = phi i64 [ %t41.i.i, %"Sys$sysWriteAllFd.exit.i" ], [ %t9.i.i.i, %0 ]
  ret i64 %t11.i
}

; Function Attrs: nounwind
define i64 @"IO$removeFile"(i64 %path) #1 {
  %t0.i = tail call i64 @"Str$strDup"(i64 %path)
  %t0.i.i.i.i = inttoptr i64 %t0.i to ptr
  %t1.i.i.i.i = getelementptr i8, ptr %t0.i.i.i.i, i64 8
  %t2.i.i.i.i = load i64, ptr %t1.i.i.i.i, align 8
  %t9.i = tail call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 35, i64 -100, i64 %t2.i.i.i.i, i64 0, i64 0, i64 0, i64 0) #15
  ret i64 %t9.i
}

; Function Attrs: nounwind
define i64 @"IO$renamePath"(i64 %old, i64 %new) #1 {
  %t0.i = tail call i64 @"Str$strDup"(i64 %old)
  %t0.i.i.i.i = inttoptr i64 %t0.i to ptr
  %t1.i.i.i.i = getelementptr i8, ptr %t0.i.i.i.i, i64 8
  %t2.i.i.i.i = load i64, ptr %t1.i.i.i.i, align 8
  %t0.i1 = tail call i64 @"Str$strDup"(i64 %new)
  %t0.i.i.i.i2 = inttoptr i64 %t0.i1 to ptr
  %t1.i.i.i.i3 = getelementptr i8, ptr %t0.i.i.i.i2, i64 8
  %t2.i.i.i.i4 = load i64, ptr %t1.i.i.i.i3, align 8
  %t10.i = tail call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 38, i64 -100, i64 %t2.i.i.i.i, i64 -100, i64 %t2.i.i.i.i4, i64 0, i64 0) #15
  ret i64 %t10.i
}

define i64 @"IO$copyFile"(i64 %src, i64 %dst) #0 {
  %t0.i.i = tail call i64 @"Str$strDup"(i64 %src)
  %t0.i.i.i.i.i = inttoptr i64 %t0.i.i to ptr
  %t1.i.i.i.i.i = getelementptr i8, ptr %t0.i.i.i.i.i, i64 8
  %t2.i.i.i.i.i = load i64, ptr %t1.i.i.i.i.i, align 8
  %t1.i = tail call i64 @"Sys$sysReadErrno"(i64 %t2.i.i.i.i.i)
  %c1.not = icmp eq i64 %t1.i, 0
  br i1 %c1.not, label %label_5, label %label_4

label_4:                                          ; preds = %0
  %t7 = sub i64 0, %t1.i
  br label %label_6

label_5:                                          ; preds = %0
  %t0.i.i1 = tail call i64 @"Str$strDup"(i64 %src)
  %t0.i.i.i.i.i2 = inttoptr i64 %t0.i.i1 to ptr
  %t1.i.i.i.i.i3 = getelementptr i8, ptr %t0.i.i.i.i.i2, i64 8
  %t2.i.i.i.i.i4 = load i64, ptr %t1.i.i.i.i.i3, align 8
  %t0.i1.i = tail call i64 @"Sys$sysReadFile"(i64 %t2.i.i.i.i.i4)
  %t0.i.i5 = tail call i64 @"Str$strDup"(i64 %dst)
  %t0.i.i.i.i.i6 = inttoptr i64 %t0.i.i5 to ptr
  %t1.i.i.i.i.i7 = getelementptr i8, ptr %t0.i.i.i.i.i6, i64 8
  %t2.i.i.i.i.i8 = load i64, ptr %t1.i.i.i.i.i7, align 8
  %t9.i.i.i.i = tail call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 56, i64 -100, i64 %t2.i.i.i.i.i8, i64 577, i64 420, i64 0, i64 0) #15
  %t3.not.i.i = icmp sgt i64 %t9.i.i.i.i, -1
  br i1 %t3.not.i.i, label %label_5.i.i, label %label_6

label_5.i.i:                                      ; preds = %label_5
  %t0.i.i.i.i = inttoptr i64 %t0.i1.i to ptr
  %t1.i.i.i.i = getelementptr i8, ptr %t0.i.i.i.i, i64 8
  %t2.i.i.i.i = load i64, ptr %t1.i.i.i.i, align 8
  %t2.i.i2.i.i = load i64, ptr %t0.i.i.i.i, align 8
  %c7.not11.i.i.i = icmp sgt i64 %t2.i.i2.i.i, 0
  br i1 %c7.not11.i.i.i, label %label_11.i.i.i, label %"Sys$sysWriteAllFd.exit.i.i"

label_11.i.i.i:                                   ; preds = %label_5.i.i, %label_26.i.i.i
  %s.4.012.i.i.i = phi i64 [ %t40.i.i.i, %label_26.i.i.i ], [ 0, %label_5.i.i ]
  %t17.i.i.i = add i64 %s.4.012.i.i.i, %t2.i.i.i.i
  %t20.i.i.i = sub i64 %t2.i.i2.i.i, %s.4.012.i.i.i
  %t1.i.i3.i.i = tail call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 64, i64 %t9.i.i.i.i, i64 %t17.i.i.i, i64 %t20.i.i.i, i64 0, i64 0, i64 0) #15
  %c22.i.i.i = icmp slt i64 %t1.i.i3.i.i, 1
  br i1 %c22.i.i.i, label %label_25.i.i.i, label %label_26.i.i.i

label_25.i.i.i:                                   ; preds = %label_11.i.i.i
  %c28.not.i.i.i = icmp eq i64 %t1.i.i3.i.i, 0
  %t35.i.i.i = select i1 %c28.not.i.i.i, i64 %s.4.012.i.i.i, i64 %t1.i.i3.i.i
  br label %"Sys$sysWriteAllFd.exit.i.i"

label_26.i.i.i:                                   ; preds = %label_11.i.i.i
  %t40.i.i.i = add i64 %t1.i.i3.i.i, %s.4.012.i.i.i
  %c7.not.i.i.i = icmp slt i64 %t40.i.i.i, %t2.i.i2.i.i
  br i1 %c7.not.i.i.i, label %label_11.i.i.i, label %"Sys$sysWriteAllFd.exit.i.i"

"Sys$sysWriteAllFd.exit.i.i":                     ; preds = %label_26.i.i.i, %label_25.i.i.i, %label_5.i.i
  %t41.i.i.i = phi i64 [ %t35.i.i.i, %label_25.i.i.i ], [ 0, %label_5.i.i ], [ %t40.i.i.i, %label_26.i.i.i ]
  %t1.i.i.i = tail call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 57, i64 %t9.i.i.i.i, i64 0, i64 0, i64 0, i64 0, i64 0) #15
  br label %label_6

label_6:                                          ; preds = %"Sys$sysWriteAllFd.exit.i.i", %label_5, %label_4
  %t10 = phi i64 [ %t7, %label_4 ], [ %t41.i.i.i, %"Sys$sysWriteAllFd.exit.i.i" ], [ %t9.i.i.i.i, %label_5 ]
  ret i64 %t10
}

; Function Attrs: nounwind
define range(i64 0, 2) i64 @"IO$fileExists"(i64 %path) #1 {
  %t0.i = tail call i64 @"Str$strDup"(i64 %path)
  %t0.i.i.i.i = inttoptr i64 %t0.i to ptr
  %t1.i.i.i.i = getelementptr i8, ptr %t0.i.i.i.i, i64 8
  %t2.i.i.i.i = load i64, ptr %t1.i.i.i.i, align 8
  %t9.i.i.i = tail call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 56, i64 -100, i64 %t2.i.i.i.i, i64 0, i64 420, i64 0, i64 0) #15
  %c2.i = icmp slt i64 %t9.i.i.i, 0
  br i1 %c2.i, label %"Sys$sysFileExists.exit", label %label_6.i

label_6.i:                                        ; preds = %0
  %t1.i.i = tail call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 57, i64 %t9.i.i.i, i64 0, i64 0, i64 0, i64 0, i64 0) #15
  br label %"Sys$sysFileExists.exit"

"Sys$sysFileExists.exit":                         ; preds = %0, %label_6.i
  %t9.i = phi i64 [ 1, %label_6.i ], [ 0, %0 ]
  ret i64 %t9.i
}

define range(i64 0, 2) i64 @"IO$isDir"(i64 %path) #0 {
  %t0.i = tail call i64 @"Str$strDup"(i64 %path)
  %t0.i.i.i.i = inttoptr i64 %t0.i to ptr
  %t1.i.i.i.i = getelementptr i8, ptr %t0.i.i.i.i, i64 8
  %t2.i.i.i.i = load i64, ptr %t1.i.i.i.i, align 8
  %t0.i1 = tail call i64 @"Sys$sysReadErrno"(i64 %t2.i.i.i.i)
  %c2.i = icmp eq i64 %t0.i1, 21
  %t3.i = zext i1 %c2.i to i64
  ret i64 %t3.i
}

; Function Attrs: nounwind
define i64 @"IO$fileSize"(i64 %path) #1 {
  %t0.i = tail call i64 @"Str$strDup"(i64 %path)
  %t0.i.i.i.i = inttoptr i64 %t0.i to ptr
  %t1.i.i.i.i = getelementptr i8, ptr %t0.i.i.i.i, i64 8
  %t2.i.i.i.i = load i64, ptr %t1.i.i.i.i, align 8
  %t9.i.i.i = tail call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 56, i64 -100, i64 %t2.i.i.i.i, i64 0, i64 420, i64 0, i64 0) #15
  %c2.i = icmp slt i64 %t9.i.i.i, 0
  br i1 %c2.i, label %"Sys$sysFileSize.exit", label %label_6.i

label_6.i:                                        ; preds = %0
  %t1.i.i = tail call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 62, i64 %t9.i.i.i, i64 0, i64 2, i64 0, i64 0, i64 0) #15
  %t1.i1.i = tail call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 57, i64 %t9.i.i.i, i64 0, i64 0, i64 0, i64 0, i64 0) #15
  br label %"Sys$sysFileSize.exit"

"Sys$sysFileSize.exit":                           ; preds = %0, %label_6.i
  %t11.i = phi i64 [ %t1.i.i, %label_6.i ], [ %t9.i.i.i, %0 ]
  ret i64 %t11.i
}

define i64 @"IO$readErrno"(i64 %path) #0 {
  %t0.i = tail call i64 @"Str$strDup"(i64 %path)
  %t0.i.i.i.i = inttoptr i64 %t0.i to ptr
  %t1.i.i.i.i = getelementptr i8, ptr %t0.i.i.i.i, i64 8
  %t2.i.i.i.i = load i64, ptr %t1.i.i.i.i, align 8
  %t1 = tail call i64 @"Sys$sysReadErrno"(i64 %t2.i.i.i.i)
  ret i64 %t1
}

; Function Attrs: nounwind
define i64 @"IO$makeDir"(i64 %path) #1 {
  %t0.i = tail call i64 @"Str$strDup"(i64 %path)
  %t0.i.i.i.i = inttoptr i64 %t0.i to ptr
  %t1.i.i.i.i = getelementptr i8, ptr %t0.i.i.i.i, i64 8
  %t2.i.i.i.i = load i64, ptr %t1.i.i.i.i, align 8
  %t9.i = tail call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 34, i64 -100, i64 %t2.i.i.i.i, i64 493, i64 0, i64 0, i64 0) #15
  ret i64 %t9.i
}

define i64 @"IO$makeDirAll"(i64 %path) #0 {
  %t0 = tail call i64 @"IO$makeDirAllFrom"(i64 %path, i64 1)
  ret i64 %t0
}

define i64 @"IO$makeDirAllFrom"(i64 %path, i64 %i) #0 {
  %imm.i = icmp slt i64 %path, 4096
  br i1 %imm.i, label %axiom_retain.exit, label %chk.i

chk.i:                                            ; preds = %0
  %hoff.i = add nsw i64 %path, -16
  %cp.i = inttoptr i64 %hoff.i to ptr
  %c.i = load i64, ptr %cp.i, align 8
  %stat.i = icmp eq i64 %c.i, -1
  br i1 %stat.i, label %axiom_retain.exit, label %bump.i

bump.i:                                           ; preds = %chk.i
  %c1.i = add nuw i64 %c.i, 1
  store i64 %c1.i, ptr %cp.i, align 8
  br label %axiom_retain.exit

axiom_retain.exit:                                ; preds = %0, %chk.i, %bump.i
  %t0.i.i = inttoptr i64 %path to ptr
  %t2.i.i27 = load i64, ptr %t0.i.i, align 8
  %c6.not28 = icmp slt i64 %i, %t2.i.i27
  br i1 %c6.not28, label %label_10.lr.ph, label %label_9

label_10.lr.ph:                                   ; preds = %axiom_retain.exit
  %t1.i.i.i = getelementptr i8, ptr %t0.i.i, i64 8
  %t1.i.i.i18 = getelementptr i8, ptr %t0.i.i, i64 16
  %t1.i.i4.i = getelementptr i8, ptr %t0.i.i, i64 8
  br label %label_10

label_9:                                          ; preds = %label_0.backedge, %axiom_retain.exit
  %t0.i.i.i = tail call i64 @"Str$strDup"(i64 %path)
  %t0.i.i.i.i.i.i = inttoptr i64 %t0.i.i.i to ptr
  %t1.i.i.i.i.i.i = getelementptr i8, ptr %t0.i.i.i.i.i.i, i64 8
  %t2.i.i.i.i.i.i = load i64, ptr %t1.i.i.i.i.i.i, align 8
  %t9.i.i.i = tail call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 34, i64 -100, i64 %t2.i.i.i.i.i.i, i64 493, i64 0, i64 0, i64 0) #15
  %c31.i = icmp eq i64 %t9.i.i.i, -17
  %.t0.i = select i1 %c31.i, i64 0, i64 %t9.i.i.i
  br label %label_11

label_10:                                         ; preds = %label_10.lr.ph, %label_0.backedge
  %t2.i.i30 = phi i64 [ %t2.i.i27, %label_10.lr.ph ], [ %t2.i.i, %label_0.backedge ]
  %s.2.029 = phi i64 [ %i, %label_10.lr.ph ], [ %s.2.0.be, %label_0.backedge ]
  %c0.i = icmp slt i64 %s.2.029, 0
  br i1 %c0.i, label %label_0.backedge, label %label_11.i

label_11.i:                                       ; preds = %label_10
  %t2.i.i2.i = load i64, ptr %t1.i.i.i, align 8
  %t14.i = inttoptr i64 %t2.i.i2.i to ptr
  %t15.i = getelementptr i8, ptr %t14.i, i64 %s.2.029
  %t16.i = load i8, ptr %t15.i, align 1
  %1 = icmp eq i8 %t16.i, 47
  br i1 %1, label %label_20, label %label_0.backedge

label_20:                                         ; preds = %label_11.i
  %t0.start.i = tail call i64 @llvm.smin.i64(i64 %t2.i.i30, i64 0)
  %t15.i17 = sub i64 %t2.i.i30, %t0.start.i
  %t15.count.i = tail call i64 @llvm.smin.i64(i64 %s.2.029, i64 %t15.i17)
  %t2.i.i2.i19 = load i64, ptr %t1.i.i.i18, align 8
  %imm.i.i = icmp slt i64 %t2.i.i2.i19, 4096
  br i1 %imm.i.i, label %axiom_retain.exit.i, label %chk.i.i

chk.i.i:                                          ; preds = %label_20
  %hoff.i.i = add nsw i64 %t2.i.i2.i19, -16
  %cp.i.i = inttoptr i64 %hoff.i.i to ptr
  %c.i.i = load i64, ptr %cp.i.i, align 8
  %stat.i.i = icmp eq i64 %c.i.i, -1
  br i1 %stat.i.i, label %axiom_retain.exit.i, label %bump.i.i

bump.i.i:                                         ; preds = %chk.i.i
  %c1.i.i = add nuw i64 %c.i.i, 1
  store i64 %c1.i.i, ptr %cp.i.i, align 8
  br label %axiom_retain.exit.i

axiom_retain.exit.i:                              ; preds = %bump.i.i, %chk.i.i, %label_20
  %t2.i.i5.i = load i64, ptr %t1.i.i4.i, align 8
  %t32.i = add i64 %t2.i.i5.i, %t0.start.i
  %t0.i.i6.i = tail call i64 @axiom_alloc(i64 24)
  %t7.i.i.i = add i64 %t0.i.i6.i, -8
  %t8.i.i.i = inttoptr i64 %t7.i.i.i to ptr
  %t10.i.i.i = load i64, ptr %t8.i.i.i, align 8
  %t11.i.i.i = lshr i64 %t10.i.i.i, 1
  %t12.i.i.i = and i64 %t11.i.i.i, 16383
  %.t12.i.i.i = tail call i64 @llvm.umin.i64(i64 %t12.i.i.i, i64 47)
  %t22.i.i.i = shl nsw i64 -65536, %.t12.i.i.i
  %t23.i.i.i = and i64 %t22.i.i.i, 262144
  %t24.i.i.i = xor i64 %t23.i.i.i, 262144
  %t25.i.i.i = or i64 %t24.i.i.i, %t10.i.i.i
  store i64 %t25.i.i.i, ptr %t8.i.i.i, align 8
  %t5.i.i.i = inttoptr i64 %t0.i.i6.i to ptr
  store i64 %t15.count.i, ptr %t5.i.i.i, align 8
  %t6.i.i.i = getelementptr i8, ptr %t5.i.i.i, i64 8
  store i64 %t32.i, ptr %t6.i.i.i, align 8
  %t6.i5.i.i = getelementptr i8, ptr %t5.i.i.i, i64 16
  store i64 %t2.i.i2.i19, ptr %t6.i5.i.i, align 8
  %imm.i.i.i = icmp slt i64 %t0.i.i6.i, 4096
  br i1 %imm.i.i.i, label %"Str$strSlice.exit", label %chk.i.i.i

chk.i.i.i:                                        ; preds = %axiom_retain.exit.i
  %hoff.i.i.i = add nsw i64 %t0.i.i6.i, -16
  %cp.i.i.i = inttoptr i64 %hoff.i.i.i to ptr
  %c.i.i.i = load i64, ptr %cp.i.i.i, align 8
  %stat.i.i.i = icmp eq i64 %c.i.i.i, -1
  br i1 %stat.i.i.i, label %"Str$strSlice.exit", label %bump.i.i.i

bump.i.i.i:                                       ; preds = %chk.i.i.i
  %c1.i.i.i = add nuw i64 %c.i.i.i, 1
  store i64 %c1.i.i.i, ptr %cp.i.i.i, align 8
  br label %"Str$strSlice.exit"

"Str$strSlice.exit":                              ; preds = %axiom_retain.exit.i, %chk.i.i.i, %bump.i.i.i
  %t0.i.i.i20 = tail call i64 @"Str$strDup"(i64 %t0.i.i6.i)
  %t0.i.i.i.i.i.i21 = inttoptr i64 %t0.i.i.i20 to ptr
  %t1.i.i.i.i.i.i22 = getelementptr i8, ptr %t0.i.i.i.i.i.i21, i64 8
  %t2.i.i.i.i.i.i23 = load i64, ptr %t1.i.i.i.i.i.i22, align 8
  %t9.i.i.i24 = tail call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 34, i64 -100, i64 %t2.i.i.i.i.i.i23, i64 493, i64 0, i64 0, i64 0) #15
  %c31.i25 = icmp eq i64 %t9.i.i.i24, -17
  %.t0.i26 = select i1 %c31.i25, i64 0, i64 %t9.i.i.i24
  tail call void @axiom_release(i64 %t0.i.i6.i)
  %c27 = icmp slt i64 %.t0.i26, 0
  br i1 %c27, label %label_11, label %label_0.backedge

label_0.backedge:                                 ; preds = %label_11.i, %label_10, %"Str$strSlice.exit"
  %s.2.0.be = add nsw i64 %s.2.029, 1
  %t2.i.i = load i64, ptr %t0.i.i, align 8
  %c6.not = icmp slt i64 %s.2.0.be, %t2.i.i
  br i1 %c6.not, label %label_10, label %label_9

label_11:                                         ; preds = %"Str$strSlice.exit", %label_9
  %t41 = phi i64 [ %.t0.i, %label_9 ], [ %.t0.i26, %"Str$strSlice.exit" ]
  tail call void @axiom_release(i64 %path)
  ret i64 %t41
}

; Function Attrs: nounwind
define i64 @"IO$makeDirOk"(i64 %p) #1 {
label_8:
  %t0.i.i = tail call i64 @"Str$strDup"(i64 %p)
  %t0.i.i.i.i.i = inttoptr i64 %t0.i.i to ptr
  %t1.i.i.i.i.i = getelementptr i8, ptr %t0.i.i.i.i.i, i64 8
  %t2.i.i.i.i.i = load i64, ptr %t1.i.i.i.i.i, align 8
  %t9.i.i = tail call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 34, i64 -100, i64 %t2.i.i.i.i.i, i64 493, i64 0, i64 0, i64 0) #15
  %c31 = icmp eq i64 %t9.i.i, -17
  %.t0 = select i1 %c31, i64 0, i64 %t9.i.i
  ret i64 %.t0
}

; Function Attrs: nounwind
define i64 @"IO$removeDir"(i64 %path) #1 {
  %t0.i = tail call i64 @"Str$strDup"(i64 %path)
  %t0.i.i.i.i = inttoptr i64 %t0.i to ptr
  %t1.i.i.i.i = getelementptr i8, ptr %t0.i.i.i.i, i64 8
  %t2.i.i.i.i = load i64, ptr %t1.i.i.i.i, align 8
  %t9.i = tail call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 35, i64 -100, i64 %t2.i.i.i.i, i64 512, i64 0, i64 0, i64 0) #15
  ret i64 %t9.i
}

define i64 @"IO$listDir"(i64 %path) #0 {
  %t0.i = tail call i64 @"Str$strDup"(i64 %path)
  %t0.i.i.i.i = inttoptr i64 %t0.i to ptr
  %t1.i.i.i.i = getelementptr i8, ptr %t0.i.i.i.i, i64 8
  %t2.i.i.i.i = load i64, ptr %t1.i.i.i.i, align 8
  %t1 = tail call i64 @"Sys$sysReadDir"(i64 %t2.i.i.i.i)
  %t0.i.i.i.i1 = tail call i64 @axiom_alloc(i64 32)
  %t7.i.i.i.i = add i64 %t0.i.i.i.i1, -8
  %t8.i.i.i.i = inttoptr i64 %t7.i.i.i.i to ptr
  %t10.i.i.i.i = load i64, ptr %t8.i.i.i.i, align 8
  %t11.i.i.i.i = lshr i64 %t10.i.i.i.i, 1
  %t12.i.i.i.i = and i64 %t11.i.i.i.i, 16383
  %.t12.i.i.i.i = tail call i64 @llvm.umin.i64(i64 %t12.i.i.i.i, i64 47)
  %t22.i.i.i.i = shl nsw i64 -65536, %.t12.i.i.i.i
  %t23.i.i.i.i = and i64 %t22.i.i.i.i, 262144
  %t24.i.i.i.i = xor i64 %t23.i.i.i.i, 262144
  %t25.i.i.i.i = or i64 %t24.i.i.i.i, %t10.i.i.i.i
  store i64 %t25.i.i.i.i, ptr %t8.i.i.i.i, align 8
  %t0.i1.i.i.i = tail call i64 @axiom_alloc(i64 64)
  %imm.i.i.i.i = icmp slt i64 %t0.i.i.i.i1, 4096
  br i1 %imm.i.i.i.i, label %axiom_retain.exit.i.i.i, label %chk.i.i.i.i

chk.i.i.i.i:                                      ; preds = %0
  %hoff.i.i.i.i = add nsw i64 %t0.i.i.i.i1, -16
  %cp.i.i.i.i = inttoptr i64 %hoff.i.i.i.i to ptr
  %c.i.i.i.i = load i64, ptr %cp.i.i.i.i, align 8
  %stat.i.i.i.i = icmp eq i64 %c.i.i.i.i, -1
  br i1 %stat.i.i.i.i, label %axiom_retain.exit.i.i.i, label %bump.i.i.i.i

bump.i.i.i.i:                                     ; preds = %chk.i.i.i.i
  %c1.i.i.i.i = add nuw i64 %c.i.i.i.i, 1
  store i64 %c1.i.i.i.i, ptr %cp.i.i.i.i, align 8
  br label %axiom_retain.exit.i.i.i

axiom_retain.exit.i.i.i:                          ; preds = %bump.i.i.i.i, %chk.i.i.i.i, %0
  %imm.i2.i.i.i = icmp slt i64 %t0.i1.i.i.i, 4096
  br i1 %imm.i2.i.i.i, label %"Vec$vecNew.exit", label %chk.i3.i.i.i

chk.i3.i.i.i:                                     ; preds = %axiom_retain.exit.i.i.i
  %hoff.i4.i.i.i = add nsw i64 %t0.i1.i.i.i, -16
  %cp.i5.i.i.i = inttoptr i64 %hoff.i4.i.i.i to ptr
  %c.i6.i.i.i = load i64, ptr %cp.i5.i.i.i, align 8
  %stat.i7.i.i.i = icmp eq i64 %c.i6.i.i.i, -1
  br i1 %stat.i7.i.i.i, label %"Vec$vecNew.exit", label %bump.i8.i.i.i

bump.i8.i.i.i:                                    ; preds = %chk.i3.i.i.i
  %c1.i9.i.i.i = add nuw i64 %c.i6.i.i.i, 1
  store i64 %c1.i9.i.i.i, ptr %cp.i5.i.i.i, align 8
  br label %"Vec$vecNew.exit"

"Vec$vecNew.exit":                                ; preds = %axiom_retain.exit.i.i.i, %chk.i3.i.i.i, %bump.i8.i.i.i
  %t5.i12.i.i.i = inttoptr i64 %t0.i.i.i.i1 to ptr
  store i64 0, ptr %t5.i12.i.i.i, align 8
  %t6.i.i.i.i = getelementptr i8, ptr %t5.i12.i.i.i, i64 8
  store i64 8, ptr %t6.i.i.i.i, align 8
  %t6.i16.i.i.i = getelementptr i8, ptr %t5.i12.i.i.i, i64 16
  store i64 %t0.i1.i.i.i, ptr %t6.i16.i.i.i, align 8
  %t6.i19.i.i.i = getelementptr i8, ptr %t5.i12.i.i.i, i64 24
  store i64 0, ptr %t6.i19.i.i.i, align 8
  %t3 = tail call i64 @"IO$listDirKeep"(i64 %t1, i64 0, i64 %t0.i.i.i.i1)
  ret i64 %t0.i.i.i.i1
}

define noundef i64 @"IO$listDirKeep"(i64 %raw, i64 %i, i64 %out) #0 {
  %t0.i.i = inttoptr i64 %raw to ptr
  %t2.i.i33 = load i64, ptr %t0.i.i, align 8
  %c7.not34 = icmp slt i64 %i, %t2.i.i33
  br i1 %c7.not34, label %label_11.lr.ph, label %label_12

label_11.lr.ph:                                   ; preds = %0
  %t1.i.i.i = getelementptr i8, ptr %t0.i.i, i64 16
  %t0.i.i.i31 = inttoptr i64 %out to ptr
  br label %label_11

label_11:                                         ; preds = %label_11.lr.ph, %label_30
  %s.2.035 = phi i64 [ %i, %label_11.lr.ph ], [ %t36, %label_30 ]
  %c0.i = icmp slt i64 %s.2.035, 0
  br i1 %c0.i, label %"Vec$vecGet.exit", label %label_11.i

label_11.i:                                       ; preds = %label_11
  %t2.i.i2.i = load i64, ptr %t1.i.i.i, align 8
  %t0.i.i6 = inttoptr i64 %t2.i.i2.i to ptr
  %t1.i.i = getelementptr i64, ptr %t0.i.i6, i64 %s.2.035
  %t2.i.i7 = load i64, ptr %t1.i.i, align 8
  br label %"Vec$vecGet.exit"

"Vec$vecGet.exit":                                ; preds = %label_11, %label_11.i
  %t16.i = phi i64 [ 0, %label_11 ], [ %t2.i.i7, %label_11.i ]
  %t0.i.i.i8 = inttoptr i64 %t16.i to ptr
  %t2.i.i.i9 = load i64, ptr %t0.i.i.i8, align 8
  %c2.not.i = icmp eq i64 %t2.i.i.i9, 1
  br i1 %c2.not.i, label %"Mem$memCmp.exit.loopexit.i", label %label_19.critedge

"Mem$memCmp.exit.loopexit.i":                     ; preds = %"Vec$vecGet.exit"
  %t1.i.i.i10 = getelementptr i8, ptr %t0.i.i.i8, i64 8
  %t2.i.i4.i = load i64, ptr %t1.i.i.i10, align 8
  %t20.i.i.i = inttoptr i64 %t2.i.i4.i to ptr
  %t22.i.i.i = load i8, ptr %t20.i.i.i, align 1
  %c13.i.i.i = icmp eq i8 %t22.i.i.i, 46
  tail call void @axiom_release(i64 ptrtoint (ptr getelementptr inbounds nuw (i8, ptr @strhdr_3, i64 16) to i64))
  br i1 %c13.i.i.i, label %label_30, label %label_19

label_19.critedge:                                ; preds = %"Vec$vecGet.exit"
  tail call void @axiom_release(i64 ptrtoint (ptr getelementptr inbounds nuw (i8, ptr @strhdr_3, i64 16) to i64))
  br label %label_19

label_19:                                         ; preds = %label_19.critedge, %"Mem$memCmp.exit.loopexit.i"
  %t2.i.i.i12 = load i64, ptr %t0.i.i.i8, align 8
  %c2.not.i13 = icmp eq i64 %t2.i.i.i12, 2
  br i1 %c2.not.i13, label %label_6.i15, label %label_29.critedge

label_6.i15:                                      ; preds = %label_19
  %t1.i.i.i16 = getelementptr i8, ptr %t0.i.i.i8, i64 8
  %t2.i.i4.i17 = load i64, ptr %t1.i.i.i16, align 8
  %t20.i.i.i18 = inttoptr i64 %t2.i.i4.i17 to ptr
  %t22.i.i.i22 = load i8, ptr %t20.i.i.i18, align 1
  %c13.i.i.i27 = icmp eq i8 %t22.i.i.i22, 46
  br i1 %c13.i.i.i27, label %label_3.i.i.i19.1, label %label_29.critedge36

label_3.i.i.i19.1:                                ; preds = %label_6.i15
  %t21.i.i.i21.1 = getelementptr i8, ptr %t20.i.i.i18, i64 1
  %t22.i.i.i22.1 = load i8, ptr %t21.i.i.i21.1, align 1
  %c13.i.i.i27.1 = icmp eq i8 %t22.i.i.i22.1, 46
  tail call void @axiom_release(i64 ptrtoint (ptr getelementptr inbounds nuw (i8, ptr @strhdr_14, i64 16) to i64))
  br i1 %c13.i.i.i27.1, label %label_30, label %label_29

label_29.critedge:                                ; preds = %label_19
  tail call void @axiom_release(i64 ptrtoint (ptr getelementptr inbounds nuw (i8, ptr @strhdr_14, i64 16) to i64))
  br label %label_29

label_29.critedge36:                              ; preds = %label_6.i15
  tail call void @axiom_release(i64 ptrtoint (ptr getelementptr inbounds nuw (i8, ptr @strhdr_14, i64 16) to i64))
  br label %label_29

label_29:                                         ; preds = %label_29.critedge36, %label_29.critedge, %label_3.i.i.i19.1
  %t0.i = tail call i64 @"Vec$vecPush"(i64 %out, i64 %t16.i, i64 0)
  %t2.i.i.i32 = load i64, ptr %t0.i.i.i31, align 8
  %t2.i = add i64 %t2.i.i.i32, -1
  %t3.i = tail call i64 @"IO$listDirSift"(i64 %out, i64 %t2.i)
  br label %label_30

label_30:                                         ; preds = %"Mem$memCmp.exit.loopexit.i", %label_3.i.i.i19.1, %label_29
  %t36 = add nsw i64 %s.2.035, 1
  %t2.i.i = load i64, ptr %t0.i.i, align 8
  %c7.not = icmp slt i64 %t36, %t2.i.i
  br i1 %c7.not, label %label_11, label %label_12

label_12:                                         ; preds = %label_30, %0
  ret i64 0
}

define noundef i64 @"IO$listDirInsert"(i64 %v, i64 %s) #0 {
  %t0 = tail call i64 @"Vec$vecPush"(i64 %v, i64 %s, i64 0)
  %t0.i.i = inttoptr i64 %v to ptr
  %t2.i.i = load i64, ptr %t0.i.i, align 8
  %t2 = add i64 %t2.i.i, -1
  %t3 = tail call i64 @"IO$listDirSift"(i64 %v, i64 %t2)
  ret i64 0
}

define noundef i64 @"IO$listDirSift"(i64 %v, i64 %i) #0 {
  %c457 = icmp slt i64 %i, 1
  br i1 %c457, label %label_9, label %label_8.lr.ph

label_8.lr.ph:                                    ; preds = %0
  %t0.i.i.i = inttoptr i64 %v to ptr
  %t1.i.i.i = getelementptr i8, ptr %t0.i.i.i, i64 16
  %t0.i.i.i12 = inttoptr i64 %v to ptr
  %t1.i.i.i17 = getelementptr i8, ptr %t0.i.i.i12, i64 16
  %t0.i.i.i29 = inttoptr i64 %v to ptr
  %t1.i.i.i33 = getelementptr i8, ptr %t0.i.i.i29, i64 24
  %t1.i.i.i.i = getelementptr i8, ptr %t0.i.i.i29, i64 16
  %t1.i.i7.i = getelementptr i8, ptr %t0.i.i.i29, i64 16
  %t0.i.i.i37 = inttoptr i64 %v to ptr
  %t1.i.i.i41 = getelementptr i8, ptr %t0.i.i.i37, i64 24
  %t1.i.i.i.i51 = getelementptr i8, ptr %t0.i.i.i37, i64 16
  %t1.i.i7.i45 = getelementptr i8, ptr %t0.i.i.i37, i64 16
  br label %label_8

label_8:                                          ; preds = %label_8.lr.ph, %"Vec$vecSet.exit56"
  %s.2.058 = phi i64 [ %i, %label_8.lr.ph ], [ %t12, %"Vec$vecSet.exit56" ]
  %t12 = add nsw i64 %s.2.058, -1
  %t2.i.i.i = load i64, ptr %t0.i.i.i, align 8
  %c7.not.i.not = icmp sgt i64 %s.2.058, %t2.i.i.i
  br i1 %c7.not.i.not, label %label_4.i11, label %label_11.i

label_11.i:                                       ; preds = %label_8
  %t2.i.i2.i = load i64, ptr %t1.i.i.i, align 8
  %t0.i.i = inttoptr i64 %t2.i.i2.i to ptr
  %t1.i.i = getelementptr i64, ptr %t0.i.i, i64 %t12
  %t2.i.i = load i64, ptr %t1.i.i, align 8
  br label %label_4.i11

label_4.i11:                                      ; preds = %label_11.i, %label_8
  %t16.i = phi i64 [ 0, %label_8 ], [ %t2.i.i, %label_11.i ]
  %t2.i.i.i13 = load i64, ptr %t0.i.i.i12, align 8
  %c7.not.i14 = icmp slt i64 %s.2.058, %t2.i.i.i13
  br i1 %c7.not.i14, label %label_11.i16, label %"Vec$vecGet.exit22"

label_11.i16:                                     ; preds = %label_4.i11
  %t2.i.i2.i18 = load i64, ptr %t1.i.i.i17, align 8
  %t0.i.i19 = inttoptr i64 %t2.i.i2.i18 to ptr
  %t1.i.i20 = getelementptr i64, ptr %t0.i.i19, i64 %s.2.058
  %t2.i.i21 = load i64, ptr %t1.i.i20, align 8
  br label %"Vec$vecGet.exit22"

"Vec$vecGet.exit22":                              ; preds = %label_4.i11, %label_11.i16
  %t16.i15 = phi i64 [ 0, %label_4.i11 ], [ %t2.i.i21, %label_11.i16 ]
  %t0.i.i.i23 = inttoptr i64 %t16.i to ptr
  %t2.i.i.i24 = load i64, ptr %t0.i.i.i23, align 8
  %t0.i.i1.i = inttoptr i64 %t16.i15 to ptr
  %t2.i.i2.i25 = load i64, ptr %t0.i.i1.i, align 8
  %t0.t1.i = tail call i64 @llvm.smin.i64(i64 %t2.i.i.i24, i64 %t2.i.i2.i25)
  %c65.i.i.i = icmp sgt i64 %t0.t1.i, 0
  br i1 %c65.i.i.i, label %label_3.lr.ph.i.i.i, label %"Str$strCmp.exit"

label_3.lr.ph.i.i.i:                              ; preds = %"Vec$vecGet.exit22"
  %t1.i.i6.i = getelementptr i8, ptr %t0.i.i1.i, i64 8
  %t2.i.i7.i = load i64, ptr %t1.i.i6.i, align 8
  %t1.i.i.i26 = getelementptr i8, ptr %t0.i.i.i23, i64 8
  %t2.i.i4.i = load i64, ptr %t1.i.i.i26, align 8
  %t20.i.i.i = inttoptr i64 %t2.i.i4.i to ptr
  %t25.i.i.i = inttoptr i64 %t2.i.i7.i to ptr
  br label %label_3.i.i.i

label_3.i.i.i:                                    ; preds = %label_3.i.i.i, %label_3.lr.ph.i.i.i
  %s.0.06.i.i.i = phi i64 [ 0, %label_3.lr.ph.i.i.i ], [ %t31.i.i.i, %label_3.i.i.i ]
  %t21.i.i.i = getelementptr i8, ptr %t20.i.i.i, i64 %s.0.06.i.i.i
  %t22.i.i.i = load i8, ptr %t21.i.i.i, align 1
  %t23.i.i.i = zext i8 %t22.i.i.i to i64
  %t26.i.i.i = getelementptr i8, ptr %t25.i.i.i, i64 %s.0.06.i.i.i
  %t27.i.i.i = load i8, ptr %t26.i.i.i, align 1
  %t28.i.i.i = zext i8 %t27.i.i.i to i64
  %t29.i.i.i = sub nsw i64 %t23.i.i.i, %t28.i.i.i
  %t31.i.i.i = add nuw nsw i64 %s.0.06.i.i.i, 1
  %c6.i.i.i = icmp slt i64 %t31.i.i.i, %t0.t1.i
  %c13.i.i.i = icmp eq i64 %t29.i.i.i, 0
  %narrow.i.i.i = select i1 %c6.i.i.i, i1 %c13.i.i.i, i1 false
  br i1 %narrow.i.i.i, label %label_3.i.i.i, label %"Str$strCmp.exit"

"Str$strCmp.exit":                                ; preds = %label_3.i.i.i, %"Vec$vecGet.exit22"
  %s.1.0.lcssa.i.i.i = phi i64 [ 0, %"Vec$vecGet.exit22" ], [ %t29.i.i.i, %label_3.i.i.i ]
  %c12.not.i = icmp eq i64 %s.1.0.lcssa.i.i.i, 0
  %t18.i = sub i64 %t2.i.i.i24, %t2.i.i2.i25
  %t19.i = select i1 %c12.not.i, i64 %t18.i, i64 %s.1.0.lcssa.i.i.i
  %c18 = icmp slt i64 %t19.i, 1
  br i1 %c18, label %label_9, label %label_4.i28

label_4.i28:                                      ; preds = %"Str$strCmp.exit"
  %t2.i.i.i30 = load i64, ptr %t0.i.i.i29, align 8
  %c7.not.i31.not = icmp sgt i64 %s.2.058, %t2.i.i.i30
  br i1 %c7.not.i31.not, label %label_4.i36, label %label_11.i32

label_11.i32:                                     ; preds = %label_4.i28
  %t2.i.i2.i34 = load i64, ptr %t1.i.i.i33, align 8
  %c1.i.not.i = icmp eq i64 %t2.i.i2.i34, 1
  br i1 %c1.i.not.i, label %label_15.i, label %label_17.i

label_15.i:                                       ; preds = %label_11.i32
  %t2.i.i.i.i = load i64, ptr %t1.i.i.i.i, align 8
  %t0.i.i3.i = inttoptr i64 %t2.i.i.i.i to ptr
  %t1.i.i4.i = getelementptr i64, ptr %t0.i.i3.i, i64 %t12
  %t2.i.i5.i = load i64, ptr %t1.i.i4.i, align 8
  store i64 0, ptr %t1.i.i4.i, align 8
  tail call void @axiom_release(i64 %t2.i.i5.i)
  br label %label_17.i

label_17.i:                                       ; preds = %label_15.i, %label_11.i32
  %t2.i.i8.i = load i64, ptr %t1.i.i7.i, align 8
  %t5.i.i = inttoptr i64 %t2.i.i8.i to ptr
  %t6.i.i = getelementptr i64, ptr %t5.i.i, i64 %t12
  store i64 %t16.i15, ptr %t6.i.i, align 8
  br label %label_4.i36

label_4.i36:                                      ; preds = %label_17.i, %label_4.i28
  %t2.i.i.i38 = load i64, ptr %t0.i.i.i37, align 8
  %c7.not.i39 = icmp slt i64 %s.2.058, %t2.i.i.i38
  br i1 %c7.not.i39, label %label_11.i40, label %"Vec$vecSet.exit56"

label_11.i40:                                     ; preds = %label_4.i36
  %t2.i.i2.i42 = load i64, ptr %t1.i.i.i41, align 8
  %c1.i.not.i43 = icmp eq i64 %t2.i.i2.i42, 1
  br i1 %c1.i.not.i43, label %label_15.i50, label %label_17.i44

label_15.i50:                                     ; preds = %label_11.i40
  %t2.i.i.i.i52 = load i64, ptr %t1.i.i.i.i51, align 8
  %t0.i.i3.i53 = inttoptr i64 %t2.i.i.i.i52 to ptr
  %t1.i.i4.i54 = getelementptr i64, ptr %t0.i.i3.i53, i64 %s.2.058
  %t2.i.i5.i55 = load i64, ptr %t1.i.i4.i54, align 8
  store i64 0, ptr %t1.i.i4.i54, align 8
  tail call void @axiom_release(i64 %t2.i.i5.i55)
  br label %label_17.i44

label_17.i44:                                     ; preds = %label_15.i50, %label_11.i40
  %t2.i.i8.i46 = load i64, ptr %t1.i.i7.i45, align 8
  %t5.i.i48 = inttoptr i64 %t2.i.i8.i46 to ptr
  %t6.i.i49 = getelementptr i64, ptr %t5.i.i48, i64 %s.2.058
  store i64 %t16.i, ptr %t6.i.i49, align 8
  br label %"Vec$vecSet.exit56"

"Vec$vecSet.exit56":                              ; preds = %label_4.i36, %label_17.i44
  %c4 = icmp slt i64 %s.2.058, 2
  br i1 %c4, label %label_9, label %label_8

label_9:                                          ; preds = %"Vec$vecSet.exit56", %"Str$strCmp.exit", %0
  ret i64 0
}

define i64 @"IO$cwd"() #0 {
  %t0 = tail call i64 @"Sys$sysGetCwd"()
  ret i64 %t0
}

; Function Attrs: nounwind
define noundef i64 @"IO$exit"(i64 %code) #1 {
  %t1.i = tail call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 94, i64 %code, i64 0, i64 0, i64 0, i64 0, i64 0) #15
  ret i64 0
}

define noundef i64 @"IO$die"(i64 %s, i64 %code) #0 {
  %imm.i.i = icmp slt i64 %s, 4096
  br i1 %imm.i.i, label %"Show#String#show.exit", label %chk.i.i

chk.i.i:                                          ; preds = %0
  %hoff.i.i = add nsw i64 %s, -16
  %cp.i.i = inttoptr i64 %hoff.i.i to ptr
  %c.i.i = load i64, ptr %cp.i.i, align 8
  %stat.i.i = icmp eq i64 %c.i.i, -1
  br i1 %stat.i.i, label %"Show#String#show.exit", label %bump.i.i

bump.i.i:                                         ; preds = %chk.i.i
  %c1.i.i = add nuw i64 %c.i.i, 1
  store i64 %c1.i.i, ptr %cp.i.i, align 8
  br label %"Show#String#show.exit"

"Show#String#show.exit":                          ; preds = %0, %chk.i.i, %bump.i.i
  %t3 = tail call i64 @"Str$strConcat"(i64 %s, i64 ptrtoint (ptr getelementptr inbounds nuw (i8, ptr @strhdr_13, i64 16) to i64))
  tail call void @axiom_release(i64 %s)
  tail call void @axiom_release(i64 ptrtoint (ptr getelementptr inbounds nuw (i8, ptr @strhdr_13, i64 16) to i64))
  %t0.i.i.i = inttoptr i64 %t3 to ptr
  %t1.i.i.i = getelementptr i8, ptr %t0.i.i.i, i64 8
  %t2.i.i.i = load i64, ptr %t1.i.i.i, align 8
  %t2.i.i2.i = load i64, ptr %t0.i.i.i, align 8
  %c7.not11.i.i = icmp sgt i64 %t2.i.i2.i, 0
  br i1 %c7.not11.i.i, label %label_11.i.i, label %"IO$writeStr.exit"

label_11.i.i:                                     ; preds = %"Show#String#show.exit", %label_11.i.i
  %s.4.012.i.i = phi i64 [ %t40.i.i, %label_11.i.i ], [ 0, %"Show#String#show.exit" ]
  %t17.i.i = add i64 %s.4.012.i.i, %t2.i.i.i
  %t20.i.i = sub i64 %t2.i.i2.i, %s.4.012.i.i
  %t1.i.i3.i = tail call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 64, i64 2, i64 %t17.i.i, i64 %t20.i.i, i64 0, i64 0, i64 0) #15
  %c22.i.i = icmp sgt i64 %t1.i.i3.i, 0
  %t40.i.i = add i64 %t1.i.i3.i, %s.4.012.i.i
  %c7.not.i.i = icmp slt i64 %t40.i.i, %t2.i.i2.i
  %or.cond = select i1 %c22.i.i, i1 %c7.not.i.i, i1 false
  br i1 %or.cond, label %label_11.i.i, label %"IO$writeStr.exit"

"IO$writeStr.exit":                               ; preds = %label_11.i.i, %"Show#String#show.exit"
  %t1.i.i = tail call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 94, i64 %code, i64 0, i64 0, i64 0, i64 0, i64 0) #15
  ret i64 0
}

; Function Attrs: nounwind
define i64 @ask(i64 %x) #1 {
  %t0.i = tail call i64 @axiom_alloc(i64 140737488355328)
  ret i64 %t0.i
}

; Function Attrs: nounwind
define noundef i64 @usable(i64 %x) #1 {
  %t0.i = tail call i64 @axiom_alloc(i64 64)
  %t5.i = inttoptr i64 %t0.i to ptr
  store i64 4242, ptr %t5.i, align 8
  ret i64 4242
}

define i64 @__axiom_user_main() #0 {
label_12:
  %cell.i = tail call i64 @axiom_alloc(i64 24)
  %bump.i = load i64, ptr @__axiom_bump, align 8
  %end.i = load i64, ptr @__axiom_bump_end, align 8
  %chunk.i = load i64, ptr @__axiom_chunk, align 8
  %p0.i = inttoptr i64 %cell.i to ptr
  store i64 %bump.i, ptr %p0.i, align 8
  %a1.i = add i64 %cell.i, 8
  %p1.i = inttoptr i64 %a1.i to ptr
  store i64 %end.i, ptr %p1.i, align 8
  %a2.i = add i64 %cell.i, 16
  %p2.i = inttoptr i64 %a2.i to ptr
  store i64 %chunk.i, ptr %p2.i, align 8
  %t1 = tail call i64 @axiom_alloc(i64 128)
  %t2 = load i64, ptr @__axiom_recover_top, align 8
  %t3 = add i64 %t1, 24
  %t4 = inttoptr i64 %t3 to ptr
  store i64 %cell.i, ptr %t4, align 8
  %t5 = add i64 %t1, 32
  %t6 = inttoptr i64 %t5 to ptr
  store i64 %t2, ptr %t6, align 8
  %t7 = add i64 %t1, 40
  %t8 = inttoptr i64 %t7 to ptr
  store i64 0, ptr %t8, align 8
  store i64 %t1, ptr @__axiom_recover_top, align 8
  tail call void asm sideeffect "stp x19, x20, [$0, #48]\0Astp x21, x22, [$0, #64]\0Astp x23, x24, [$0, #80]\0Astp x25, x26, [$0, #96]\0Astp x27, x28, [$0, #112]\0Amov x9, sp\0Astr x9, [$0]\0Astr x29, [$0, #8]\0Aadr x9, 1f\0Astr x9, [$0, #16]\0Ab 2f\0A1:\0Aldp x19, x20, [x9, #48]\0Aldp x21, x22, [x9, #64]\0Aldp x23, x24, [x9, #80]\0Aldp x25, x26, [x9, #96]\0Aldp x27, x28, [x9, #112]\0A2:", "r,~{x0},~{x1},~{x2},~{x3},~{x4},~{x5},~{x6},~{x7},~{x8},~{x9},~{x10},~{x11},~{x12},~{x13},~{x14},~{x15},~{x16},~{x17},~{lr},~{x18},~{v0},~{v1},~{v2},~{v3},~{v4},~{v5},~{v6},~{v7},~{v8},~{v9},~{v10},~{v11},~{v12},~{v13},~{v14},~{v15},~{v16},~{v17},~{v18},~{v19},~{v20},~{v21},~{v22},~{v23},~{v24},~{v25},~{v26},~{v27},~{v28},~{v29},~{v30},~{v31},~{memory},~{cc}"(i64 %t1) #15
  %t9 = load i64, ptr %t8, align 8
  %t10 = icmp eq i64 %t9, 0
  br i1 %t10, label %label_13, label %label_14

label_13:                                         ; preds = %label_12
  %t15 = tail call i64 @axiom_alloc(i64 8)
  %t17 = inttoptr i64 %t15 to ptr
  store i64 ptrtoint (ptr @_lam_0 to i64), ptr %t17, align 8
  %t19 = add i64 %t15, -16
  %t20 = inttoptr i64 %t19 to ptr
  store i64 1, ptr %t20, align 8
  %t21 = add i64 %t15, -8
  %t22 = inttoptr i64 %t21 to ptr
  store i64 4, ptr %t22, align 8
  %t25 = load i64, ptr %t17, align 8
  %f26 = inttoptr i64 %t25 to ptr
  %t27 = tail call i64 %f26(i64 %t15, i64 0)
  tail call void @axiom_release(i64 %t15)
  br label %label_14

label_14:                                         ; preds = %label_13, %label_12
  %t11 = phi i64 [ %t9, %label_12 ], [ %t27, %label_13 ]
  store i64 %t2, ptr @__axiom_recover_top, align 8
  %t0.i.i = tail call i64 @axiom_alloc(i64 64)
  %t5.i.i = inttoptr i64 %t0.i.i to ptr
  store i64 4242, ptr %t5.i.i, align 8
  %narrow.i.not.i.i = icmp eq i64 %t11, -9223372036854775808
  br i1 %narrow.i.not.i.i, label %"Show#Int#show.exit", label %label_3.i.i

label_3.i.i:                                      ; preds = %label_14
  %c6.i.i = icmp slt i64 %t11, 0
  br i1 %c6.i.i, label %label_9.i.i, label %label_10.i.i

label_9.i.i:                                      ; preds = %label_3.i.i
  %t13.i.i = sub nsw i64 0, %t11
  %t14.i.i = tail call i64 @"Fmt$fmtNat"(i64 %t13.i.i)
  %t15.i.i = tail call i64 @"Str$strConcat"(i64 ptrtoint (ptr getelementptr inbounds nuw (i8, ptr @strhdr_1, i64 16) to i64), i64 %t14.i.i)
  tail call void @axiom_release(i64 ptrtoint (ptr getelementptr inbounds nuw (i8, ptr @strhdr_1, i64 16) to i64))
  tail call void @axiom_release(i64 %t14.i.i)
  br label %"Show#Int#show.exit"

label_10.i.i:                                     ; preds = %label_3.i.i
  %t16.i.i = tail call i64 @"Fmt$fmtNat"(i64 %t11)
  br label %"Show#Int#show.exit"

"Show#Int#show.exit":                             ; preds = %label_14, %label_9.i.i, %label_10.i.i
  %t18.i.i = phi i64 [ %t16.i.i, %label_10.i.i ], [ %t15.i.i, %label_9.i.i ], [ ptrtoint (ptr getelementptr inbounds nuw (i8, ptr @strhdr_0, i64 16) to i64), %label_14 ]
  %t32 = tail call i64 @"Str$strConcat"(i64 ptrtoint (ptr getelementptr inbounds nuw (i8, ptr @strhdr_15, i64 16) to i64), i64 %t18.i.i)
  tail call void @axiom_release(i64 ptrtoint (ptr getelementptr inbounds nuw (i8, ptr @strhdr_15, i64 16) to i64))
  tail call void @axiom_release(i64 %t18.i.i)
  %t34 = tail call i64 @"Str$strConcat"(i64 %t32, i64 ptrtoint (ptr getelementptr inbounds nuw (i8, ptr @strhdr_13, i64 16) to i64))
  tail call void @axiom_release(i64 %t32)
  tail call void @axiom_release(i64 ptrtoint (ptr getelementptr inbounds nuw (i8, ptr @strhdr_13, i64 16) to i64))
  %t0.i.i.i = inttoptr i64 %t34 to ptr
  %t1.i.i.i = getelementptr i8, ptr %t0.i.i.i, i64 8
  %t2.i.i.i = load i64, ptr %t1.i.i.i, align 8
  %t2.i.i2.i = load i64, ptr %t0.i.i.i, align 8
  %c7.not11.i.i = icmp sgt i64 %t2.i.i2.i, 0
  br i1 %c7.not11.i.i, label %label_11.i.i, label %"IO$writeStr.exit"

label_11.i.i:                                     ; preds = %"Show#Int#show.exit", %label_11.i.i
  %s.4.012.i.i = phi i64 [ %t40.i.i, %label_11.i.i ], [ 0, %"Show#Int#show.exit" ]
  %t17.i.i = add i64 %s.4.012.i.i, %t2.i.i.i
  %t20.i.i = sub i64 %t2.i.i2.i, %s.4.012.i.i
  %t1.i.i3.i = tail call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 64, i64 1, i64 %t17.i.i, i64 %t20.i.i, i64 0, i64 0, i64 0) #15
  %c22.i.i = icmp sgt i64 %t1.i.i3.i, 0
  %t40.i.i = add i64 %t1.i.i3.i, %s.4.012.i.i
  %c7.not.i.i = icmp slt i64 %t40.i.i, %t2.i.i2.i
  %or.cond = select i1 %c22.i.i, i1 %c7.not.i.i, i1 false
  br i1 %or.cond, label %label_11.i.i, label %"IO$writeStr.exit"

"IO$writeStr.exit":                               ; preds = %label_11.i.i, %"Show#Int#show.exit"
  %t16.i.i3 = tail call i64 @"Fmt$fmtNat"(i64 4242)
  %t39 = tail call i64 @"Str$strConcat"(i64 ptrtoint (ptr getelementptr inbounds nuw (i8, ptr @strhdr_16, i64 16) to i64), i64 %t16.i.i3)
  tail call void @axiom_release(i64 ptrtoint (ptr getelementptr inbounds nuw (i8, ptr @strhdr_16, i64 16) to i64))
  tail call void @axiom_release(i64 %t16.i.i3)
  %t41 = tail call i64 @"Str$strConcat"(i64 %t39, i64 ptrtoint (ptr getelementptr inbounds nuw (i8, ptr @strhdr_13, i64 16) to i64))
  tail call void @axiom_release(i64 %t39)
  tail call void @axiom_release(i64 ptrtoint (ptr getelementptr inbounds nuw (i8, ptr @strhdr_13, i64 16) to i64))
  %t0.i.i.i5 = inttoptr i64 %t41 to ptr
  %t1.i.i.i6 = getelementptr i8, ptr %t0.i.i.i5, i64 8
  %t2.i.i.i7 = load i64, ptr %t1.i.i.i6, align 8
  %t2.i.i2.i8 = load i64, ptr %t0.i.i.i5, align 8
  %c7.not11.i.i9 = icmp sgt i64 %t2.i.i2.i8, 0
  br i1 %c7.not11.i.i9, label %label_11.i.i11, label %"IO$writeStr.exit23"

label_11.i.i11:                                   ; preds = %"IO$writeStr.exit", %label_11.i.i11
  %s.4.012.i.i12 = phi i64 [ %t40.i.i18, %label_11.i.i11 ], [ 0, %"IO$writeStr.exit" ]
  %t17.i.i13 = add i64 %s.4.012.i.i12, %t2.i.i.i7
  %t20.i.i14 = sub i64 %t2.i.i2.i8, %s.4.012.i.i12
  %t1.i.i3.i15 = tail call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 64, i64 1, i64 %t17.i.i13, i64 %t20.i.i14, i64 0, i64 0, i64 0) #15
  %c22.i.i16 = icmp sgt i64 %t1.i.i3.i15, 0
  %t40.i.i18 = add i64 %t1.i.i3.i15, %s.4.012.i.i12
  %c7.not.i.i19 = icmp slt i64 %t40.i.i18, %t2.i.i2.i8
  %or.cond25 = select i1 %c22.i.i16, i1 %c7.not.i.i19, i1 false
  br i1 %or.cond25, label %label_11.i.i11, label %"IO$writeStr.exit23"

"IO$writeStr.exit23":                             ; preds = %label_11.i.i11, %"IO$writeStr.exit"
  %t0.i.i24 = tail call i64 @axiom_alloc(i64 140737488355328)
  br label %label_11.i.i.i

label_11.i.i.i:                                   ; preds = %"IO$writeStr.exit23", %label_11.i.i.i
  %s.4.012.i.i.i = phi i64 [ %t40.i.i.i, %label_11.i.i.i ], [ 0, %"IO$writeStr.exit23" ]
  %t17.i.i.i = add i64 %s.4.012.i.i.i, ptrtoint (ptr @str_17 to i64)
  %t20.i.i.i = sub i64 55, %s.4.012.i.i.i
  %t1.i.i.i.i = tail call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 64, i64 1, i64 %t17.i.i.i, i64 %t20.i.i.i, i64 0, i64 0, i64 0) #15
  %c22.i.i.i = icmp sgt i64 %t1.i.i.i.i, 0
  %t40.i.i.i = add i64 %t1.i.i.i.i, %s.4.012.i.i.i
  %c7.not.i.i.i = icmp slt i64 %t40.i.i.i, 55
  %or.cond.i = select i1 %c22.i.i.i, i1 %c7.not.i.i.i, i1 false
  br i1 %or.cond.i, label %label_11.i.i.i, label %"IO$printlnLit.exit"

"IO$printlnLit.exit":                             ; preds = %label_11.i.i.i
  %t1.i.i.i14.i = tail call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 64, i64 1, i64 ptrtoint (ptr @str_13 to i64), i64 1, i64 0, i64 0, i64 0) #15
  ret i64 %t1.i.i.i14.i
}

; Function Attrs: nounwind
define i64 @_lam_0(i64 %_env, i64 %x) #1 {
  %t0.i.i = tail call i64 @axiom_alloc(i64 140737488355328)
  ret i64 %t0.i.i
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(readwrite, inaccessiblemem: none, target_mem0: none, target_mem1: none)
define i64 @"Show#String#show"(i64 returned %s) #2 {
  %imm.i = icmp slt i64 %s, 4096
  br i1 %imm.i, label %axiom_retain.exit, label %chk.i

chk.i:                                            ; preds = %0
  %hoff.i = add nsw i64 %s, -16
  %cp.i = inttoptr i64 %hoff.i to ptr
  %c.i = load i64, ptr %cp.i, align 8
  %stat.i = icmp eq i64 %c.i, -1
  br i1 %stat.i, label %axiom_retain.exit, label %bump.i

bump.i:                                           ; preds = %chk.i
  %c1.i = add nuw i64 %c.i, 1
  store i64 %c1.i, ptr %cp.i, align 8
  br label %axiom_retain.exit

axiom_retain.exit:                                ; preds = %0, %chk.i, %bump.i
  ret i64 %s
}

define i64 @"Show#Int#show"(i64 %n) #0 {
  %narrow.i.not.i = icmp eq i64 %n, -9223372036854775808
  br i1 %narrow.i.not.i, label %"Fmt$fmtInt.exit", label %label_3.i

label_3.i:                                        ; preds = %0
  %c6.i = icmp slt i64 %n, 0
  br i1 %c6.i, label %label_9.i, label %label_10.i

label_9.i:                                        ; preds = %label_3.i
  %t13.i = sub nsw i64 0, %n
  %t14.i = tail call i64 @"Fmt$fmtNat"(i64 %t13.i)
  %t15.i = tail call i64 @"Str$strConcat"(i64 ptrtoint (ptr getelementptr inbounds nuw (i8, ptr @strhdr_1, i64 16) to i64), i64 %t14.i)
  tail call void @axiom_release(i64 ptrtoint (ptr getelementptr inbounds nuw (i8, ptr @strhdr_1, i64 16) to i64))
  tail call void @axiom_release(i64 %t14.i)
  br label %"Fmt$fmtInt.exit"

label_10.i:                                       ; preds = %label_3.i
  %t16.i = tail call i64 @"Fmt$fmtNat"(i64 %n)
  br label %"Fmt$fmtInt.exit"

"Fmt$fmtInt.exit":                                ; preds = %0, %label_9.i, %label_10.i
  %t18.i = phi i64 [ %t16.i, %label_10.i ], [ %t15.i, %label_9.i ], [ ptrtoint (ptr getelementptr inbounds nuw (i8, ptr @strhdr_0, i64 16) to i64), %0 ]
  ret i64 %t18.i
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(none)
define i64 @"Show#Bool#show"(i64 %b) #6 {
label_3:
  %t0.not = icmp eq i64 %b, 0
  %t6 = select i1 %t0.not, i64 ptrtoint (ptr getelementptr inbounds nuw (i8, ptr @strhdr_19, i64 16) to i64), i64 ptrtoint (ptr getelementptr inbounds nuw (i8, ptr @strhdr_18, i64 16) to i64)
  ret i64 %t6
}

define i64 @"Show#Float#show"(i64 %x) #0 {
  %d0.i.i = bitcast i64 %x to double
  %c2.i.i = fcmp olt double %d0.i.i, 0.000000e+00
  br i1 %c2.i.i, label %label_5.i.i, label %label_6.i.i

label_5.i.i:                                      ; preds = %0
  %d11.i.i = fsub double 0.000000e+00, %d0.i.i
  %t12.i.i = bitcast double %d11.i.i to i64
  %t13.i.i = tail call i64 @"Fmt$fmtFloatAbs"(i64 %t12.i.i, i64 6)
  %t14.i.i = tail call i64 @"Str$strConcat"(i64 ptrtoint (ptr getelementptr inbounds nuw (i8, ptr @strhdr_1, i64 16) to i64), i64 %t13.i.i)
  tail call void @axiom_release(i64 ptrtoint (ptr getelementptr inbounds nuw (i8, ptr @strhdr_1, i64 16) to i64))
  tail call void @axiom_release(i64 %t13.i.i)
  br label %"Fmt$fmtFloat.exit"

label_6.i.i:                                      ; preds = %0
  %t15.i.i = tail call i64 @"Fmt$fmtFloatAbs"(i64 %x, i64 6)
  br label %"Fmt$fmtFloat.exit"

"Fmt$fmtFloat.exit":                              ; preds = %label_5.i.i, %label_6.i.i
  %t16.i.i = phi i64 [ %t14.i.i, %label_5.i.i ], [ %t15.i.i, %label_6.i.i ]
  ret i64 %t16.i.i
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(none)
define internal noundef i64 @__axiom_recover_save(i64 %rec) #6 {
entry:
  ret i64 0
}

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(none)
define internal noundef i64 @__axiom_recover_load(i64 %rec) #6 {
entry:
  ret i64 0
}

; Function Attrs: nounwind
define internal fastcc void @__axiom_backtrace() unnamed_addr #1 {
entry:
  %0 = tail call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 64, i64 2, i64 ptrtoint (ptr @__axiom_bt_hdr to i64), i64 42, i64 0, i64 0, i64 0) #15
  %fpi = tail call i64 asm sideeffect "mov $0, x29", "=r"() #15
  br label %loop

loop:                                             ; preds = %__axiom_bt_name.exit, %entry
  %fp = phi i64 [ %fpi, %entry ], [ %nx, %__axiom_bt_name.exit ]
  %d = phi i64 [ 0, %entry ], [ %d1, %__axiom_bt_name.exit ]
  %deep = icmp samesign ugt i64 %d, 63
  %fpz = icmp eq i64 %fp, 0
  %mis = and i64 %fp, 7
  %misb = icmp ne i64 %mis, 0
  %s0 = or i1 %fpz, %deep
  %stop = or i1 %misb, %s0
  br i1 %stop, label %done, label %read

read:                                             ; preds = %loop
  %raa = add i64 %fp, 8
  %rap = inttoptr i64 %raa to ptr
  %ra = load i64, ptr %rap, align 8
  %raz = icmp eq i64 %ra, 0
  br i1 %raz, label %done, label %frame

frame:                                            ; preds = %read
  %fpp = inttoptr i64 %fp to ptr
  %nx = load i64, ptr %fpp, align 8
  %pc.i = add i64 %ra, -1
  br label %body.i

body.i:                                           ; preds = %body.i, %frame
  %bl5.i = phi i64 [ 0, %frame ], [ %bl1.i, %body.i ]
  %bn4.i = phi i64 [ 0, %frame ], [ %bn1.i, %body.i ]
  %ba3.i = phi i64 [ 0, %frame ], [ %ba1.i, %body.i ]
  %i2.i = phi i64 [ 0, %frame ], [ %i1.i, %body.i ]
  %pa.idx.i = mul nuw nsw i64 %i2.i, 24
  %pa.i = getelementptr i8, ptr @__axiom_symtab, i64 %pa.idx.i
  %a.i = load i64, ptr %pa.i, align 8
  %pn.i = getelementptr i8, ptr %pa.i, i64 8
  %nm.i = load i64, ptr %pn.i, align 8
  %pl.i = getelementptr i8, ptr %pa.i, i64 16
  %ln.i = load i64, ptr %pl.i, align 8
  %le.i = icmp ule i64 %a.i, %pc.i
  %gt.i = icmp ugt i64 %a.i, %ba3.i
  %take.i = and i1 %le.i, %gt.i
  %ba1.i = select i1 %take.i, i64 %a.i, i64 %ba3.i
  %bn1.i = select i1 %take.i, i64 %nm.i, i64 %bn4.i
  %bl1.i = select i1 %take.i, i64 %ln.i, i64 %bl5.i
  %i1.i = add nuw nsw i64 %i2.i, 1
  %exitcond.i = icmp eq i64 %i1.i, 316
  br i1 %exitcond.i, label %emit.i, label %body.i

emit.i:                                           ; preds = %body.i
  %1 = tail call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 64, i64 2, i64 ptrtoint (ptr @__axiom_bt_at to i64), i64 5, i64 0, i64 0, i64 0) #15
  %found.not.i = icmp eq i64 %bn1.i, 0
  br i1 %found.not.i, label %unknown.i, label %named.i

named.i:                                          ; preds = %emit.i
  %2 = tail call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 64, i64 2, i64 %bn1.i, i64 %bl1.i, i64 0, i64 0, i64 0) #15
  br label %__axiom_bt_name.exit

unknown.i:                                        ; preds = %emit.i
  %3 = tail call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 64, i64 2, i64 ptrtoint (ptr @__axiom_bt_unk to i64), i64 9, i64 0, i64 0, i64 0) #15
  br label %__axiom_bt_name.exit

__axiom_bt_name.exit:                             ; preds = %named.i, %unknown.i
  %4 = tail call i64 asm sideeffect "svc #0", "={x0},{x8},{x0},{x1},{x2},{x3},{x4},{x5},~{x1},~{x2},~{x3},~{x4},~{x5},~{x8},~{cc},~{memory}"(i64 64, i64 2, i64 ptrtoint (ptr @__axiom_bt_nl to i64), i64 1, i64 0, i64 0, i64 0) #15
  %ismain = icmp ne i64 %ba1.i, ptrtoint (ptr @main to i64)
  %d1 = add nuw nsw i64 %d, 1
  %up = icmp ugt i64 %nx, %fp
  %go = and i1 %up, %ismain
  br i1 %go, label %loop, label %done

done:                                             ; preds = %__axiom_bt_name.exit, %read, %loop
  ret void
}

; Function Attrs: nocallback nocreateundeforpoison nofree nosync nounwind speculatable willreturn memory(none)
declare i64 @llvm.umin.i64(i64, i64) #14

; Function Attrs: nocallback nocreateundeforpoison nofree nosync nounwind speculatable willreturn memory(none)
declare i64 @llvm.umax.i64(i64, i64) #14

; Function Attrs: nocallback nocreateundeforpoison nofree nosync nounwind speculatable willreturn memory(none)
declare i64 @llvm.smax.i64(i64, i64) #14

; Function Attrs: nocallback nocreateundeforpoison nofree nosync nounwind speculatable willreturn memory(none)
declare i64 @llvm.smin.i64(i64, i64) #14

attributes #0 = { "frame-pointer"="all" "no-builtins" }
attributes #1 = { nounwind "frame-pointer"="all" "no-builtins" }
attributes #2 = { mustprogress nofree norecurse nosync nounwind willreturn memory(readwrite, inaccessiblemem: none, target_mem0: none, target_mem1: none) "frame-pointer"="all" "no-builtins" }
attributes #3 = { nofree norecurse nosync nounwind memory(readwrite, inaccessiblemem: none, target_mem0: none, target_mem1: none) "frame-pointer"="all" "no-builtins" }
attributes #4 = { noreturn nounwind "frame-pointer"="all" "no-builtins" }
attributes #5 = { nofree norecurse nosync nounwind memory(read, inaccessiblemem: none, target_mem0: none, target_mem1: none) "frame-pointer"="all" "no-builtins" }
attributes #6 = { mustprogress nofree norecurse nosync nounwind willreturn memory(none) "frame-pointer"="all" "no-builtins" }
attributes #7 = { nofree norecurse nosync nounwind memory(write, inaccessiblemem: none, target_mem0: none, target_mem1: none) "frame-pointer"="all" "no-builtins" }
attributes #8 = { mustprogress nofree norecurse nosync nounwind willreturn memory(read, inaccessiblemem: none, target_mem0: none, target_mem1: none) "frame-pointer"="all" "no-builtins" }
attributes #9 = { mustprogress nofree norecurse nosync nounwind willreturn memory(write, inaccessiblemem: none, target_mem0: none, target_mem1: none) "frame-pointer"="all" "no-builtins" }
attributes #10 = { nofree norecurse nosync nounwind memory(none) "frame-pointer"="all" "no-builtins" }
attributes #11 = { nofree nosync nounwind memory(none) "frame-pointer"="all" "no-builtins" }
attributes #12 = { mustprogress nofree norecurse nosync nounwind willreturn memory(read, argmem: none, inaccessiblemem: none, target_mem0: none, target_mem1: none) "frame-pointer"="all" "no-builtins" }
attributes #13 = { nofree nosync nounwind memory(read, inaccessiblemem: none, target_mem0: none, target_mem1: none) "frame-pointer"="all" "no-builtins" }
attributes #14 = { nocallback nocreateundeforpoison nofree nosync nounwind speculatable willreturn memory(none) }
attributes #15 = { nounwind }

!0 = distinct !{!0, !1}
!1 = !{!"llvm.loop.peeled.count", i32 1}
