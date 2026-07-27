; Axiom compiled LLVM IR
target triple = "arm64-apple-macosx14.0.0"

declare i32 @printf(ptr, ...)
declare i32 @puts(ptr)
declare ptr @malloc(i64)
declare void @free(ptr)
declare ptr @memset(ptr, i32, i64)
declare ptr @memcpy(ptr, ptr, i64)
declare void @exit(i32)




define i64 @main() {
_block_0:
  %_t0 = call ptr @malloc(i64 16)
  %_t1 = ptrtoint ptr %_t0 to i64
  %_t2 = call ptr @malloc(i64 16)
  %_t3 = ptrtoint ptr %_t2 to i64
  %_t4 = add i64 %_t3, 0
  %_t5 = inttoptr i64 %_t4 to ptr
  store i64 1, ptr %_t5
  %_t6 = add i64 %_t3, 8
  %_t7 = inttoptr i64 %_t6 to ptr
  store i64 2, ptr %_t7
  %_t8 = add i64 %_t1, 0
  %_t9 = inttoptr i64 %_t8 to ptr
  store i64 %_t3, ptr %_t9
  %_t10 = call ptr @malloc(i64 16)
  %_t11 = ptrtoint ptr %_t10 to i64
  %_t12 = add i64 %_t11, 0
  %_t13 = inttoptr i64 %_t12 to ptr
  store i64 3, ptr %_t13
  %_t14 = add i64 %_t11, 8
  %_t15 = inttoptr i64 %_t14 to ptr
  store i64 4, ptr %_t15
  %_t16 = add i64 %_t1, 8
  %_t17 = inttoptr i64 %_t16 to ptr
  store i64 %_t11, ptr %_t17
  %_alloca__local_3 = alloca i64
  store i64 %_t1, ptr %_alloca__local_3
  %_t18 = load i64, ptr %_alloca__local_3
  %_alloca__local_5 = alloca i64
  br label %_block_3
_block_3:
  br label %_block_2
_block_2:
  %_t19 = add i64 %_t18, 0
  %_t20 = inttoptr i64 %_t19 to ptr
  %_t21 = load i64, ptr %_t20
  %_t22 = add i64 %_t21, 0
  %_t23 = inttoptr i64 %_t22 to ptr
  %_t24 = load i64, ptr %_t23
  %_t25 = icmp eq i64 %_t24, 1
  br i1 %_t25, label %_block_6, label %_block_5
_block_6:
  %_t26 = add i64 %_t21, 8
  %_t27 = inttoptr i64 %_t26 to ptr
  %_t28 = load i64, ptr %_t27
  %_alloca__local_10 = alloca i64
  store i64 %_t28, ptr %_alloca__local_10
  %_t29 = load i64, ptr %_alloca__local_10
  %_t30 = add i64 %_t29, %b
  store i64 %_t30, ptr %_alloca__local_5
  br label %_block_1
_block_5:
  br label %_block_4
_block_4:
  %_t31 = add i64 %_t18, 0
  %_t32 = inttoptr i64 %_t31 to ptr
  %_t33 = load i64, ptr %_t32
  %_t34 = add i64 %_t33, 0
  %_t35 = inttoptr i64 %_t34 to ptr
  %_t36 = load i64, ptr %_t35
  %_t37 = icmp eq i64 %_t36, 5
  br i1 %_t37, label %_block_7, label %_block_1
_block_7:
  %_t38 = add i64 %_t33, 8
  %_t39 = inttoptr i64 %_t38 to ptr
  %_t40 = load i64, ptr %_t39
  %_alloca__local_17 = alloca i64
  store i64 %_t40, ptr %_alloca__local_17
  %_t41 = load i64, ptr %_alloca__local_17
  %_t42 = add i64 %_t41, %d
  store i64 %_t42, ptr %_alloca__local_5
  br label %_block_1
_block_1:
  %_t43 = load i64, ptr %_alloca__local_5
  ret i64 %_t43
}

