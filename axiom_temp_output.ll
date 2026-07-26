; Axiom compiled LLVM IR
target triple = "arm64-apple-macosx14.0.0"

declare i32 @printf(ptr, ...)
declare i32 @puts(ptr)
declare ptr @malloc(i64)
declare void @free(ptr)
declare ptr @memset(ptr, i32, i64)
declare ptr @memcpy(ptr, ptr, i64)
declare void @exit(i32)



define i64 @main(i64 %x) {
_block_0:
  %_alloca_x = alloca i64
  store i64 %x, ptr %_alloca_x
  %_t0 = load i64, ptr %_alloca_x
  %_t1 = add i64 %_t0, 1
  ret i64 %_t1
}

