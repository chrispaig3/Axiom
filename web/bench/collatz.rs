fn steps(mut n: i64) -> i64 {
    let mut c: i64 = 0;
    while n > 1 {
        if n % 2 == 0 { n = n / 2; } else { n = 3 * n + 1; }
        c += 1;
    }
    c
}

fn main() {
    let mut total: i64 = 0;
    let mut i: i64 = 1;
    while i <= 3000000 {
        total += steps(i);
        i += 1;
    }
    println!("{}", total);
}
