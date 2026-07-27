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
  %_t2 = add i64 %_t1, 0
  %_t3 = inttoptr i64 %_t2 to ptr
  store i64 1, ptr %_t3
  %_t4 = add i64 %_t1, 8
  %_t5 = inttoptr i64 %_t4 to ptr
  store i64 2, ptr %_t5
  %_alloca_t = alloca i64
  store i64 %_t1, ptr %_alloca_t
  %_t6 = load i64, ptr %_alloca_t
  %_alloca__local_2 = alloca i64
  br label %_block_3
_block_3:
  br label %_block_2
_block_2:
  %_t7 = add i64 %_t6, 0
  %_t8 = inttoptr i64 %_t7 to ptr
  %_t9 = load i64, ptr %_t8
  %_t10 = icmp eq i64 %_t9, 1
  br i1 %_t10, label %_block_4, label %_block_1
_block_4:
  %_t11 = add i64 %_t6, 8
  %_t12 = inttoptr i64 %_t11 to ptr
  %_t13 = load i64, ptr %_t12
  %_alloca_x = alloca i64
  store i64 %_t13, ptr %_alloca_x
  %_t14 = load i64, ptr %_alloca_x
  store i64 %_t14, ptr %_alloca__local_2
  br label %_block_1
_block_1:
  %_t15 = load i64, ptr %_alloca__local_2
  ret i64 %_t15
}

